#!/usr/bin/env bash
# Reconcile Claude Code plugins from one local marketplace checkout, then link
# their roots and skills for pi and for agent prompts.
#
# usage: activate.sh <config.json> <links-dir>
# The untracked config keeps employer identifiers out of this repository:
#   {"path": "~/workspace/repo", "plugins": ["plugin"], "repo": "git@host:org/repo.git"}
# `repo` is optional and only clones a missing checkout. Claude Code documents
# that relative-path plugins of a directory marketplace load in place (its
# install record reports `readFromFolder`), so both harnesses read the checkout.
#
# Problems with the local config, checkout, or Claude CLI only warn: they must
# not abort the shared activation script.
set -euo pipefail

config=${1:?usage: activate.sh <config.json> <links-dir>}
links=${2:?usage: activate.sh <config.json> <links-dir>}
claude=${CLAUDE:-claude}

warn() { printf 'claude-plugins: %s\n' "$*" >&2; }
run_claude() { "$claude" "$@" >/dev/null || warn "claude $* failed"; }

if [[ ! -f $config ]]; then
  rm -rf "$links"
  exit 0
fi
if ! jq -e '(.path | type == "string") and ((.repo // "") | type == "string")
  and (.plugins | type == "array" and all(type == "string"))' "$config" >/dev/null 2>&1; then
  warn "$config must be {\"path\": string, \"plugins\": [string], \"repo\"?: string}"
  exit 0
fi

path=$(jq -r .path "$config")
path=${path/#\~/$HOME}
[[ $path == /* ]] || path=$HOME/$path
repo=$(jq -r '.repo // ""' "$config")
if [[ ! -d $path ]]; then
  if [[ -z $repo ]]; then
    warn "$path is missing; clone the marketplace there or set \"repo\" in $config"
    exit 0
  fi
  mkdir -p "$(dirname "$path")"
  # Fail fast instead of waiting on a host-key or passphrase prompt.
  if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' git clone --quiet "$repo" "$path"; then
    warn "cloning $repo into $path failed"
    exit 0
  fi
fi
manifest=$path/.claude-plugin/marketplace.json
if ! marketplace=$(jq -er 'select(.plugins | type == "array") | .name | strings' "$manifest" 2>/dev/null); then
  warn "$manifest is missing, has no name, or has no plugins array"
  exit 0
fi

# Rebuild the links in a sibling directory and swap it in, so pi never sees a
# half-written tree.
mkdir -p "$(dirname "$links")"
tmp=$(mktemp -d "$links.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/plugins" "$tmp/skills"
plugins=()
while IFS= read -r plugin; do
  source=$(jq -r --arg p "$plugin" 'first(.plugins[] | objects | select(.name == $p) | .source | strings) // ""' "$manifest")
  root=$path/${source#./}
  if [[ -z $source || $source == /* || $source == *..* || ! -d $root ]]; then
    warn "$marketplace has no local plugin directory for $plugin"
    continue
  fi
  plugins+=("$plugin")
  ln -s "$root" "$tmp/plugins/$plugin"
  for skill in "$root"/skills/*/SKILL.md; do
    [[ -f $skill ]] || continue
    dir=${skill%/SKILL.md}
    if [[ -e $tmp/skills/${dir##*/} ]]; then
      warn "skill ${dir##*/} of $plugin is already linked from another plugin"
      continue
    fi
    ln -s "$dir" "$tmp/skills/${dir##*/}"
  done
done < <(jq -r '.plugins | unique[]' "$config")
rm -rf "$links"
mv "$tmp" "$links"
trap - EXIT

if ! command -v "$claude" >/dev/null; then
  warn "$claude not found; Claude Code plugins not reconciled"
  exit 0
fi
if ! known=$("$claude" plugin marketplace list --json); then
  warn "claude plugin marketplace list failed"
  exit 0
fi
if ! location=$(jq -er --arg m "$marketplace" 'first(.[] | select(.name == $m) | .installLocation // .path) // ""' <<<"$known" 2>/dev/null); then
  warn "unexpected claude plugin marketplace list output"
  exit 0
fi
if [[ -z $location ]]; then
  run_claude plugin marketplace add "$path"
elif [[ $(realpath "$location") != "$(realpath "$path")" ]]; then
  warn "Claude Code marketplace $marketplace comes from $location, not $path; run 'claude plugin marketplace remove $marketplace' and switch again"
  exit 0
fi

if ! installed=$("$claude" plugin list --json); then
  warn "claude plugin list failed"
  exit 0
fi
for plugin in ${plugins[@]+"${plugins[@]}"}; do
  id=$plugin@$marketplace
  state=$(jq -r --arg id "$id" 'first(.[] | select(.id == $id and .scope == "user") | .enabled | tostring) // "absent"' <<<"$installed" 2>/dev/null) || state=unknown
  case $state in
  absent) run_claude plugin install "$id" --scope user ;;
  unknown) warn "unexpected claude plugin list output" ;;
  false) run_claude plugin enable "$id" --scope user ;;
  esac
done
# Plugins of this marketplace that the config no longer lists.
jq -r --arg suffix "@$marketplace" '.[] | select(.scope == "user" and .enabled == true and (.id | endswith($suffix))) | .id' <<<"$installed" 2>/dev/null |
  while IFS= read -r id; do
    for plugin in ${plugins[@]+"${plugins[@]}"}; do
      [[ $id == "$plugin@$marketplace" ]] && continue 2
    done
    run_claude plugin disable "$id" --scope user
  done || warn "unexpected claude plugin list output"
