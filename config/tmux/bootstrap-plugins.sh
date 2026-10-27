#!/usr/bin/env bash

set -euo pipefail

tmux_bin=$1
plugins_dir=$2
xre=$3
tpm_dir="$plugins_dir/tpm"
PATH="$(dirname "$tmux_bin"):$PATH"
export PATH

# Restore TPM's mutable, install-and-clean lifecycle. Existing checkouts are
# deliberately not updated on switch; installation failures only warn.
if [[ ! -d "$tpm_dir/.git" ]]; then
  if ! { mkdir -p "$plugins_dir" && git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir"; }; then
    echo "tmux: failed to clone TPM; open tmux and install manually from https://github.com/tmux-plugins/tpm" >&2
  fi
fi

if [[ -x "$tpm_dir/bin/install_plugins" ]]; then
  case "${TERM:-}" in
    ''|unknown|dumb) export TERM=screen-256color ;;
  esac

  # This intentionally uses the default server, as the previous setup did.
  # Starting it may load the user's config; never kill or explicitly reload it.
  if "$tmux_bin" start-server \; set-environment -g TMUX_PLUGIN_MANAGER_PATH "$plugins_dir/"; then
    "$tpm_dir/bin/install_plugins" || \
      echo "tmux: TPM plugin install failed; run prefix + I inside tmux" >&2
    if [[ -x "$tpm_dir/bin/clean_plugins" ]]; then
      "$tpm_dir/bin/clean_plugins" || \
        echo "tmux: TPM plugin cleanup failed; run prefix + alt-u inside tmux" >&2
    fi
  else
    echo "tmux: skipping TPM plugin install during activation; run prefix + I inside tmux" >&2
  fi
fi

# The URL plugin ignores PATH for xre. Preserve the Nix-provided helper instead
# of allowing its first-use download installer, even if TPM only partly worked.
if [[ -d "$plugins_dir/tmux-fzf-url" ]]; then
  if ! { mkdir -p "$plugins_dir/tmux-fzf-url/bin" && ln -sfn "$xre" "$plugins_dir/tmux-fzf-url/bin/xre"; }; then
    echo "tmux: failed to link xre for tmux-fzf-url" >&2
  fi
fi
