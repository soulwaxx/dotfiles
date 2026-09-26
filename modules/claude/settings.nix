# Copy config/claude/settings.json to ~/.claude/settings.json on activation.
# Claude Code writes to this file at runtime, so it's a copy, not a symlink.
# Snapshots track repo changes and live drift independently so integrations can
# add generated entries after the repo settings are copied.
{
  pkgs,
  config,
  lib,
  ...
}:

let
  settingsSource = "${config.dotfiles.path}/config/claude/settings.json";
in
{
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    STATE_DIR="$HOME/.local/state/dotfiles"
    LAST="''${STATE_DIR}/claude-settings.last.json"
    BASE="''${STATE_DIR}/claude-settings.base.json"
    LIVE="$HOME/.claude/settings.json"
    SRC="${settingsSource}"

    run mkdir -p "''${STATE_DIR}"
    run mkdir -p "$HOME/.claude"

    if [ -f "''${LIVE}" ] && [ -f "''${LAST}" ]; then
      if ! ${pkgs.jq}/bin/jq -S . "''${LAST}" > /dev/null 2>&1 || ! ${pkgs.jq}/bin/jq -S . "''${LIVE}" > /dev/null 2>&1; then
        : # skip diff if either file is not valid JSON
      elif ! ${pkgs.diffutils}/bin/cmp -s <(${pkgs.jq}/bin/jq -S . "''${LAST}") <(${pkgs.jq}/bin/jq -S . "''${LIVE}"); then
        echo "claude-settings: settings.json was modified since the last switch; resetting to the repo version. Lost changes:"
        ${pkgs.diffutils}/bin/diff -u <(${pkgs.jq}/bin/jq -S . "''${LAST}") <(${pkgs.jq}/bin/jq -S . "''${LIVE}") | sed -n '1,60p' || true
        echo "claude-settings: to keep a change, edit config/claude/settings.json directly"
      fi
    fi

    if ! ${pkgs.diffutils}/bin/cmp -s "''${SRC}" "''${BASE}" 2>/dev/null || \
       ! ${pkgs.diffutils}/bin/cmp -s "''${LIVE}" "''${LAST}" 2>/dev/null; then
      run install -m 644 "''${SRC}" "''${LIVE}"
      run install -m 644 "''${SRC}" "''${BASE}"
    fi
  '';
}
