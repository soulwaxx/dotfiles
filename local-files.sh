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
if [[ "$mode" == --prompt ]] && (: <"$tty") 2>/dev/null; then
  exec 3<"$tty"
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

# Git reads ~/.gitconfig after Home Manager's ~/.config/git/config, so identity
# or signing settings there silently override the managed ones.
if [[ -f "$HOME/.gitconfig" ]]; then
  # No mapfile: bootstrap runs this with macOS's bash 3.2.
  shadowing=$(git config --file "$HOME/.gitconfig" --name-only \
    --get-regexp '^(user\.|gpg\.|commit\.gpgsign$|tag\.gpgsign$)' 2>/dev/null | sort -u | tr '\n' ' ') || true
  if [[ -n "$shadowing" ]]; then
    warn "~/.gitconfig sets ${shadowing% }, which take precedence over the Home Manager Git config; remove them (identities belong in ~/.gitconfig.personal or ~/.gitconfig.local)."
  fi
fi

# Signing keys named by programs.git.signing and ssh.allowedSigners in
# modules/host-specific/<role>.nix.
signing_keys=(git_personal)
if [[ "$role" == work ]]; then
  signing_keys=(git git_personal)
fi
for key in "${signing_keys[@]}"; do
  if [[ -f "$HOME/.ssh/$key.pub" ]]; then
    continue
  fi
  if [[ -f "$HOME/.ssh/$key" ]]; then
    warn "~/.ssh/$key.pub is missing; recreate it with 'ssh-keygen -y -f ~/.ssh/$key > ~/.ssh/$key.pub', then switch again."
  else
    warn "~/.ssh/$key.pub is missing; Git commit signing fails until the key pair is copied to ~/.ssh."
  fi
done

if [[ ! -f "$HOME/.secrets" ]]; then
  warn "~/.secrets is missing; MCP configuration expects GH_TOKEN."
fi
if [[ "$role" == work ]]; then
  if [[ ! -f "$HOME/.aws/config" ]]; then
    warn "~/.aws/config is missing; aws-mcp has no profiles."
  fi
  if [[ ! -f "$HOME/.config/claude-plugins.json" ]]; then
    warn "~/.config/claude-plugins.json is missing; team Claude Code plugins are not installed."
  fi
fi
