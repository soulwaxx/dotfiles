# Reconcile config/claude/settings.json into ~/.claude/settings.json on activation.
# Claude Code writes to this file at runtime, so it's a copy, not a symlink.
# Preserve runtime pluginConfigs (including /config effort choices), with repo
# values taking precedence. Other live drift still resets to the repo version.
# Snapshots track repo changes and live drift independently so integrations can
# add generated entries after reconciliation.
{
  pkgs,
  config,
  lib,
  ...
}:

let
  settingsSource = "${config.dotfiles.path}/config/claude/settings.json";
  pluginConfigsFilter = "${config.dotfiles.path}/modules/claude/jq/preserve-plugin-configs.jq";
  emptySettings = pkgs.writeText "empty-claude-settings.json" "{}";
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
        echo "claude-settings: detected live changes; preserving pluginConfigs and resetting other fields to the repo version:"
        ${pkgs.diffutils}/bin/diff -u <(${pkgs.jq}/bin/jq -S . "''${LAST}") <(${pkgs.jq}/bin/jq -S . "''${LIVE}") | sed -n '1,60p' || true
        echo "claude-settings: to keep a non-plugin change, edit config/claude/settings.json directly"
      fi
    fi

    if ! ${pkgs.diffutils}/bin/cmp -s "''${SRC}" "''${BASE}" 2>/dev/null || \
       ! ${pkgs.diffutils}/bin/cmp -s "''${LIVE}" "''${LAST}" 2>/dev/null; then
      runtime_source="''${LIVE}"
      if [ ! -f "''${runtime_source}" ]; then
        runtime_source=${emptySettings}
      fi
      candidate=$(${pkgs.coreutils}/bin/mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile live "''${runtime_source}" \
        --from-file ${lib.escapeShellArg pluginConfigsFilter} "''${SRC}" > "''${candidate}"; then
        run install -m 644 "''${candidate}" "''${LIVE}"
        run install -m 644 "''${SRC}" "''${BASE}"
        rm -f "''${candidate}"
      else
        rm -f "''${candidate}"
        echo "claude-settings: invalid settings; refusing to replace the live profile" >&2
        false
      fi
    fi
  '';
}
