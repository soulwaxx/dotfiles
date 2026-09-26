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
    ".claude/hooks/block-no-verify.sh" = "hooks/block-no-verify.sh";
    ".claude/hooks/notify-attention.sh" = "hooks/notify-attention.sh";
    ".claude/hooks/obsidian-session.sh" = "hooks/obsidian-session.sh";
    ".claude/hooks/semantic-command-scanner.sh" = "hooks/semantic-command-scanner.sh";
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
      ${builtins.readFile prompt}
    '';

  claudeAgentFiles = {
    ".claude/agents/scout.md" = {
      source = mkClaudeAgent "scout" ../../config/shared/agents/scout.md ''
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
      source = mkClaudeAgent "reviewer" ../../config/shared/agents/reviewer.md ''
        description: Use for read-only review of an explicit fixed-point-to-HEAD diff against repository standards and the originating specification.
        tools: Read, Grep, Glob, Bash
        model: sonnet
        permissionMode: plan
        effort: high
        background: true
        skills:
          - code-review
      '';
      force = true;
    };
    ".claude/agents/worker.md" = {
      source = mkClaudeAgent "worker" ../../config/shared/agents/worker.md ''
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
