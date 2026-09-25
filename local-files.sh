#!/usr/bin/env bash
# Check the untracked host files listed in README "Local machine files".
# Missing files never fail the caller. With --prompt, missing Git identity keys
# are asked on the terminal: /dev/tty, because `curl | bash` makes stdin the
# bootstrap script itself.
# Messages show paths as a literal ~/ for readability.
# shellcheck disable=SC2088
set -euo pipefail

role=${1:?usage: local-files.sh <work|personal> [--prompt]}
mode=${2:-}
# Tests point this at a file of answers.
tty=${BOOTSTRAP_TTY:-/dev/tty}

warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }

case "$role" in
  work | personal) ;;
  *)
    printf 'local-files: unknown host role %s\n' "'$role'" >&2
    exit 1
    ;;
esac

interactive=0
if [[ "$mode" == --prompt ]] && (: < "$tty") 2>/dev/null; then
  exec 3< "$tty"
  interactive=1
fi

git_identity() {
  local file=$1 label=$2 key value
  local shown="~/${file#"$HOME"/}"
  local missing=()
  for key in user.name user.email user.username; do
    if git config --file "$file" --get "$key" >/dev/null 2>&1; then
      continue
    fi
    value=
    if [[ $interactive -eq 1 ]]; then
      printf '%s Git %s for %s (empty to skip): ' "$label" "$key" "$shown" >&2
      read -r -u 3 value || value=
    fi
    if [[ -n "$value" ]]; then
      git config --file "$file" "$key" "$value"
      chmod 600 "$file"
    else
      missing+=("$key")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "$shown lacks ${missing[*]}; see README 'Local machine files', then switch again."
  fi
}

git_identity "$HOME/.gitconfig.personal" Personal
if [[ "$role" == work ]]; then
  git_identity "$HOME/.gitconfig.local" Work
fi

if [[ ! -f "$HOME/.secrets" ]]; then
  warn "~/.secrets is missing; MCP configuration expects GH_TOKEN."
fi
if [[ "$role" == work ]]; then
  if [[ ! -f "$HOME/.aws/config" ]]; then
    warn "~/.aws/config is missing; aws-mcp has no profiles."
  fi
  for skill in create-aws-account scaffold-gitops; do
    if [[ ! -d "${DOTFILES_DIR:?}/config/shared/skills/$skill" ]]; then
      warn "config/shared/skills/$skill is missing; copy it from a backup."
    fi
  done
fi
