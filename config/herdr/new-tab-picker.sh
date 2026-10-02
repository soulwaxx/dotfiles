#!/usr/bin/env bash
set -euo pipefail

# Popups do not load the interactive zsh setup that exposes Nix packages.
PATH="/etc/profiles/per-user/$(id -un)/bin:$HOME/.nix-profile/bin:$PATH"
export PATH

HERDR_BIN_PATH="${HERDR_BIN_PATH:-herdr}"
export HERDR_BIN_PATH
plugin_root=$("$HERDR_BIN_PATH" plugin list --plugin herdr-navigator --json \
  | jq -er '.result.plugins[0].plugin_root')
export HERDR_TAB_PICKER_WORKSPACE_ID="${HERDR_ACTIVE_WORKSPACE_ID:?missing active workspace}"
export HERDR_PLUGIN_CONFIG_DIR="$HOME/.config/herdr/plugins/config/herdr-navigator-tabs"
exec "$plugin_root/target/release/herdr-navigator" ui
