#!/usr/bin/env bash
# Apply Rex app settings that mirror modules/ghostty.nix and config/herdr.
#
# Rex stores these in macOS defaults (com.superlogical.rex), not in init.lua,
# so they are set through the running app's client.setting.* actions. This is
# run by hand, not from activation, because it needs Rex.app running with
# Remote Control enabled (Settings > Rex Server). Re-running is idempotent.
# List settings and allowed values with: rex actions --json
set -euo pipefail

rex_bin=${REX_BIN_DIR:+$REX_BIN_DIR/}rex
set_rex() {
  "$rex_bin" "do" "client.setting.$1" "${@:2}"
}

# Themes: Rex built-ins.
set_rex themes.dark.palette value=heliotrope-haze
set_rex themes.light.palette value=merino-light
set_rex interface.appearance.scheme value=auto
set_rex interface.appearance.tint value=true # Herdr theme = "terminal"

# Typography (Ghostty font-family, font-size, adjust-cell-height 6%).
set_rex terminal.typography.font value="JetBrainsMono Nerd Font Mono"
set_rex terminal.typography.size value=13.5
set_rex terminal.typography.line_height value=1.06

# Cursor: steady block. Leave cursor.force off so Neovim can still switch to
# a bar in insert mode.
set_rex terminal.cursor.style value=block
set_rex terminal.cursor.blink value=off

# Window and padding (Ghostty window-padding-x/y = 12, display-p3,
# macos-option-as-alt = left).
set_rex interface.pane_padding.horizontal value=12
set_rex interface.pane_padding.vertical value=12
set_rex interface.pane_padding.color value=automatic
set_rex terminal.colors.display_p3 value=true
set_rex terminal.keyboard.option value=left_sends_alt

# Tabs (Herdr status_indicators = symbols, generated window titles).
set_rex interface.tabs.color value=active_tabs
set_rex interface.tabs.shell_icon_theme value=theme
set_rex terminal.titles.prefer_generated value=true

# Notifications (Herdr toast delivery = in-app): in-app overview, and system
# notification plus sound only when an agent is blocked or failed.
set_rex notifications.overview.position value=top_right
set_rex notifications.activity.status_blocked notifications=true sound=true
set_rex notifications.activity.status_error notifications=true sound=true
set_rex notifications.activity.status_working notifications=false sound=false
set_rex notifications.activity.status_done notifications=false sound=false
