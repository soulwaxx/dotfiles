{
  pkgs,
  config,
  lib,
  ...
}:

let
  dotfiles = config.dotfiles.path;
  # Version floor enforced at switch time. requiredMinimumVersion in settings.json
  # is managed-settings-only (ignored in user scope), and Home Manager cannot own
  # the system-level managed-settings path on Linux hosts, so the installer re-runs
  # instead when the binary is older. Bump when the config relies on newer behavior.
  mkCurlInstaller = import ../lib/mk-curl-installer.nix { inherit lib pkgs; };
  symlinkedPaths = {
    ".claude/statusline-command.sh" = "statusline.sh";
    ".claude/commands" = "commands";
    ".claude/hooks/notify-attention.sh" = "hooks/notify-attention.sh";
  };
  # Harness-agnostic prose lives in config/shared and is symlinked into both
  # harnesses (pi mirrors these; see modules/pi.nix).
  sharedPaths = {
    ".claude/CLAUDE.md" = "AGENTS.md";
    ".claude/skills" = "skills";
  };

  mkClaudeAgent =
    name: prompt: frontmatter:
    pkgs.writeText "claude-agent-${name}.md" ''
      ---
      name: ${name}
      ${frontmatter}
      ---
      ${prompt}
    '';

  claudeAgentFiles = {
    ".claude/agents/scout.md" = {
      source = mkClaudeAgent "scout" (builtins.readFile ../../config/shared/agents/scout.md) ''
        description: Use for read-only codebase investigation that traces behavior, locates relevant files, callers, and tests, and returns cited evidence.
        tools: Read, Grep, Glob, Bash
        model: haiku
        permissionMode: plan
        effort: low
        background: true
      '';
      force = true;
    };
    ".claude/agents/reviewer.md" = {
      # Explicit-only skills cannot be preloaded through the skills field.
      source =
        mkClaudeAgent "reviewer"
          (
            ''
              For diff reviews only, read ${config.home.homeDirectory}/.claude/skills/code-review/SKILL.md and follow it as the review contract.

            ''
            + builtins.readFile ../../config/shared/agents/reviewer.md
          )
          ''
            description: Use for read-only review of an explicit fixed-point-to-HEAD diff against repository standards and the originating specification.
            tools: Read, Grep, Glob, Bash
            model: sonnet
            permissionMode: plan
            effort: high
            background: true
          '';
      force = true;
    };
    ".claude/agents/researcher.md" = {
      source =
        mkClaudeAgent "researcher"
          (
            ''
              Read ${config.home.homeDirectory}/.claude/skills/research/SKILL.md for its sourcing and verification rules. Return the brief in your response; do not follow its file-writing steps.

            ''
            + builtins.readFile ../../config/shared/agents/researcher.md
          )
          ''
            description: Use for read-only local and web research on a bounded question; return inspected primary-source citations, findings, and unknowns without editing or publishing.
            tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
            model: sonnet
            permissionMode: plan
            effort: high
            background: true
          '';
      force = true;
    };
    ".claude/agents/infra-reviewer.md" = {
      source =
        mkClaudeAgent "infra-reviewer"
          (
            ''
              For Kubernetes, Helm, Kustomize, or GitOps reviews, also read ${config.home.homeDirectory}/.claude/skills/kubernetes-skill/SKILL.md and its relevant references.

            ''
            + builtins.readFile ../../config/shared/agents/infra-reviewer.md
          )
          ''
            description: Use for read-only operational-risk review of Terraform/OpenTofu, Kubernetes/GitOps, and infrastructure security; verify official docs and report evidence-backed findings without applying changes.
            tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
            model: sonnet
            permissionMode: plan
            effort: high
            background: true
            skills:
              - infra-review
          '';
      force = true;
    };
    ".claude/agents/worker.md" = {
      source = mkClaudeAgent "worker" (builtins.readFile ../../config/shared/agents/worker.md) ''
        description: Use for an already well-scoped implementation task with clear success criteria; make minimal edits and run focused verification.
        tools: Read, Edit, Write, Grep, Glob, Bash
        model: opus
        effort: high
        background: false
      '';
      force = true;
    };
  };

in
{
  imports = [
    ./settings.nix
    ./mcp.nix
  ];

  home = {
    sessionVariables = lib.mkIf config.dotfiles.claude.enableWorkIntegrations {
      CLAUDE_CODE_SUBAGENT_MODEL = "haiku";
    };

    activation = {
      migrateClaudeHooks = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        if [[ -L "$HOME/.claude/hooks" && "$(readlink -f "$HOME/.claude/hooks")" == "${dotfiles}/config/claude/hooks" ]]; then
          run rm "$HOME/.claude/hooks"
          run mkdir -p "$HOME/.claude/hooks"
        fi
      '';

      installClaudeCode = mkCurlInstaller {
        name = "claude";
        displayName = "Claude Code";
        installDir = "$HOME/.local/bin";
        url = "https://claude.ai/install.sh";
        binPath = "$HOME/.local/bin/claude";
        extraPath = [ "/usr/bin" ];
      };

      # Claude uses the GitHub plugin marketplace; the npm package is for pi.
      installObsidianPlugin = lib.hm.dag.entryAfter [ "installClaudeCode" "claudeSettings" ] (
        if pkgs.stdenv.hostPlatform.isDarwin then
          ''
            if ! "$HOME/.local/bin/claude" plugin marketplace list --json |
              ${pkgs.jq}/bin/jq -e 'any(.[]; .name == "obsidian-second-brain")' >/dev/null; then
              run "$HOME/.local/bin/claude" plugin marketplace add soulwaxx/obsidian-second-brain
            fi
            if ! "$HOME/.local/bin/claude" plugin list --json |
              ${pkgs.jq}/bin/jq -e 'any(.[]; .id == "obsidian-second-brain@obsidian-second-brain" and .scope == "user")' >/dev/null; then
              run "$HOME/.local/bin/claude" plugin install obsidian-second-brain@obsidian-second-brain --scope user
            fi
            if "$HOME/.local/bin/claude" plugin list --json |
              ${pkgs.jq}/bin/jq -e 'any(.[]; .id == "obsidian-second-brain@obsidian-second-brain" and .scope == "user" and .enabled == false)' >/dev/null; then
              run "$HOME/.local/bin/claude" plugin enable obsidian-second-brain@obsidian-second-brain --scope user
            fi
          ''
        else
          ''
            if "$HOME/.local/bin/claude" plugin list --json |
              ${pkgs.jq}/bin/jq -e 'any(.[]; .id == "obsidian-second-brain@obsidian-second-brain" and .scope == "user" and .enabled == true)' >/dev/null; then
              run "$HOME/.local/bin/claude" plugin disable obsidian-second-brain@obsidian-second-brain --scope user
            fi
          ''
      );
    };

    # Symlinked so edits take effect without a rebuild.
    file =
      lib.mapAttrs (_target: sourcePath: {
        source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/${sourcePath}";
        force = true;
      }) symlinkedPaths
      // lib.mapAttrs (_target: sourcePath: {
        source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/${sourcePath}";
        force = true;
      }) sharedPaths
      // claudeAgentFiles;
  };
}
