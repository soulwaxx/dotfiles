# Team Claude Code plugins for both harnesses, on hosts with work integrations.
# The marketplace checkout and plugin names come from the untracked
# ~/.config/claude-plugins.json (README "Local machine files"), so employer
# identifiers stay out of this repository. Activation installs the plugins in
# Claude Code and links their roots and skills under linksDir, which the pi
# extension config/pi/extensions/claude-plugins.ts and agent prompts read.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claudePlugins;
in
{
  options.dotfiles.claudePlugins = {
    configFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = "${config.home.homeDirectory}/.config/claude-plugins.json";
      description = "Untracked marketplace checkout and plugin list.";
    };

    linksDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = "${config.home.homeDirectory}/.local/share/claude-plugins";
      description = "Activation-owned links: plugins/<plugin> and skills/<skill>.";
    };

    kubernetesSkillHint = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      # The team plugin owns kubernetes-skill; activation links it on work hosts.
      default = lib.optionalString config.dotfiles.claude.enableWorkIntegrations " For Kubernetes, Helm, Kustomize, or GitOps reviews, also read ${cfg.linksDir}/skills/kubernetes-skill/SKILL.md and its relevant references.";
      description = "infra-reviewer prompt sentence pointing at the linked kubernetes-skill, empty without work integrations.";
    };

    modelAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        haiku = "${config.dotfiles.pi.defaultProvider}/claude-haiku-5-5";
        sonnet = "${config.dotfiles.pi.defaultProvider}/claude-sonnet-5-5";
        opus = "${config.dotfiles.pi.defaultProvider}/claude-opus-5-5";
      };
      description = "pi models for Claude Code agent `model:` aliases; pi-subagents' fuzzy match would otherwise pick the shortest matching id.";
    };
  };

  config = lib.mkIf config.dotfiles.claude.enableWorkIntegrations {
    # After Claude settings reconciliation and before herdrIntegrations snapshots
    # ~/.claude/settings.json, so the CLI's plugin entries count as baseline
    # rather than drift on the next switch.
    home.activation.claudePlugins =
      lib.hm.dag.entryBetween [ "herdrIntegrations" ] [ "installClaudeCode" "claudeSettings" ]
        ''
          if [[ -v DRY_RUN ]]; then
            verboseEcho "claude-plugins: skipped in dry run"
          else
            PATH="${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.git
                pkgs.jq
              ]
            }:/usr/bin:/bin" CLAUDE="$HOME/.local/bin/claude" \
              ${pkgs.bash}/bin/bash ${./activate.sh} ${
                lib.escapeShellArgs [
                  cfg.configFile
                  cfg.linksDir
                ]
              } ||
              echo "claude-plugins: activation failed; continuing" >&2
          fi
        '';
  };
}
