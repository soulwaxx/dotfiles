#!/usr/bin/env bash

set -euo pipefail

tmux_bin=$1
tpm=$2
config_file=$3
plugins_dir=$4
xre=$5
PATH="$(dirname "$tmux_bin"):$PATH"
export PATH
export GIT_TERMINAL_PROMPT=0
# Activation may inherit TERM=unknown (or no TERM). This process only uses a
# private, headless server, so give tmux and TPM a known terminal definition.
export TERM=xterm-256color

scratch=$(mktemp -d)
socket="$scratch/socket"
cleanup() {
  "$tmux_bin" -S "$socket" kill-server 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

# TPM consults a server and a config file even for installation. Give it a
# private, sessionless server: never source config or reload a live user server.
unset TMUX TMUX_PANE
mkdir -p "$scratch/tmux" "$plugins_dir"
awk '/^[[:space:]]*set -g @plugin / { print }' "$config_file" > "$scratch/tmux/tmux.conf"
"$tmux_bin" -S "$socket" -f /dev/null start-server \; \
  set -g exit-empty off \; \
  set-environment -g TMUX_PLUGIN_MANAGER_PATH "$plugins_dir/"
TMUX="$socket,$("$tmux_bin" -S "$socket" display-message -p '#{pid}'),0"
export TMUX
XDG_CONFIG_HOME="$scratch" "$tpm/bin/install_plugins"

# TPM's updater backgrounds each pull, losing per-plugin failure state; it also
# tries to pull detached release tags. Reconcile its checkouts synchronously so
# activation fails on network errors, dirty worktrees, or non-fast-forward refs.
while IFS= read -r spec; do
  repo=${spec%%#*}
  name=${repo##*/}
  checkout="$plugins_dir/$name"
  origin=$(git -C "$checkout" config --get remote.origin.url)
  case "$origin" in
    "https://github.com/$repo"|"https://github.com/$repo.git"|"https://git::@github.com/$repo") ;;
    *) echo "tmux: unexpected origin for $name: $origin" >&2; exit 1 ;;
  esac
  if [[ -n "$(git -C "$checkout" status --porcelain --untracked-files=no)" ]]; then
    echo "tmux: $checkout has local changes; refusing to overwrite them" >&2
    exit 1
  fi

  if [[ "$spec" == *'#'* ]]; then
    ref=${spec#*#}
    git -C "$checkout" fetch --no-tags origin "refs/tags/$ref:refs/tags/$ref"
    git -C "$checkout" checkout --detach "$ref"
  else
    git -C "$checkout" remote set-head origin --auto
    remote_head=$(git -C "$checkout" symbolic-ref --short refs/remotes/origin/HEAD)
    branch=${remote_head#origin/}
    if [[ "$(git -C "$checkout" symbolic-ref --short HEAD)" != "$branch" ]]; then
      echo "tmux: $checkout is not on upstream's default branch ($branch)" >&2
      exit 1
    fi
    git -C "$checkout" fetch origin "$branch"
    git -C "$checkout" merge-base --is-ancestor HEAD FETCH_HEAD
    git -C "$checkout" merge --ff-only FETCH_HEAD
  fi
  git -C "$checkout" submodule update --init --recursive
done < <(awk '/^[[:space:]]*set -g @plugin / { gsub(/[\047\042]/, "", $4); print $4 }' "$config_file")

# tmux-fzf-url ignores PATH for xre and otherwise downloads an executable on
# first use. Its ignored bin directory is runtime state, not tracked source.
mkdir -p "$plugins_dir/tmux-fzf-url/bin"
ln -sfn "$xre" "$plugins_dir/tmux-fzf-url/bin/xre"
