{
  pkgs,
  config,
  lib,
  ...
}:

let
  dotfiles = config.dotfiles.path;
  jsonFormat = pkgs.formats.json { };
  isWork = config.dotfiles.claude.enableWorkIntegrations;
  awsMcp = config.dotfiles.aws.mcp;
  subagentModels = config.dotfiles.pi.subagentModels;

  mkPiAgent =
    name: prompt: frontmatter:
    pkgs.writeText "pi-agent-${name}.md" ''
      ---
      name: ${name}
      ${frontmatter}
      ---
      ${builtins.readFile prompt}
    '';

  piAgentFiles = {
    ".pi/agent/agents/scout.md" = {
      source = mkPiAgent "scout" ../config/shared/agents/scout.md ''
        description: Use for read-only codebase investigation that traces behavior, locates relevant files, callers, and tests, and returns cited evidence.
        advertise: true
        tools: read, bash, grep, find, ls
        model: ${subagentModels.scout}
        thinking: low
        async: true
        systemPromptMode: replace
        inheritProjectContext: true
        inheritGlobalContext: false
        inheritSkills: false
        acceptanceRole: read-only
      '';
      force = true;
    };
    ".pi/agent/agents/reviewer.md" = {
      source = mkPiAgent "reviewer" ../config/shared/agents/reviewer.md ''
        description: Use for read-only review of an explicit fixed-point-to-HEAD diff against repository standards and the originating specification.
        advertise: true
        tools: read, bash, grep, find, ls
        model: ${subagentModels.reviewer}
        thinking: high
        async: true
        systemPromptMode: replace
        inheritProjectContext: true
        inheritGlobalContext: false
        inheritSkills: false
        skills: code-review
        acceptanceRole: read-only
      '';
      force = true;
    };
    ".pi/agent/agents/worker.md" = {
      source = mkPiAgent "worker" ../config/shared/agents/worker.md ''
        description: Use for an already well-scoped implementation task with clear success criteria; make minimal edits and run focused verification.
        advertise: true
        tools: read, bash, edit, write, grep, find, ls
        model: ${subagentModels.worker}
        thinking: high
        async: true
        systemPromptMode: replace
        inheritProjectContext: true
        inheritGlobalContext: false
        inheritSkills: false
        acceptanceRole: writer
      '';
      force = true;
    };
  };

  piPackages = [
    "npm:pi-mcp-adapter"
    "npm:@gotgenes/pi-permission-system"
    "npm:@gotgenes/pi-anthropic-auth"
    "npm:pi-web-access"
    "npm:@ff-labs/pi-fff"
    {
      source = "npm:pi-subagents";
      extensions = [ "index.js" ];
      skills = [ "skills/pi-subagents/SKILL.md" ];
      prompts = [ ];
    }
    "npm:@juicesharp/rpiv-todo"
    "npm:@juicesharp/rpiv-ask-user-question"
    "npm:@juicesharp/rpiv-btw"
    "npm:pi-powerline-footer"
    "npm:pi-blackhole"
  ];

  piSettings = {
    defaultProvider = config.dotfiles.pi.defaultProvider;
    defaultModel = config.dotfiles.pi.defaultModel;
    defaultThinkingLevel = "high";
    theme = "catppuccin-mocha";
    # Opt out of the anonymous install/update ping and provider attribution
    # headers; keep analytics sharing off explicitly rather than relying on the
    # default.
    enableInstallTelemetry = false;
    enableAnalytics = false;
    # Render mermaid diagrams once complete instead of streaming partial frames.
    markdown.mermaid = "final";
    tuiMode = "fullscreen"; # alternatives: "regular" (default), "fullscreen"
    # Force capabilities pi may under-detect behind a multiplexer.
    # Kitty images work in Ghostty through Herdr or tmux graphics passthrough.
    terminal = {
      hyperlinks = true;
      trueColor = true;
      images = "kitty";
    };
    defaultProjectTrust = "ask";
    quietStartup = true;
    # Give the skill/file/command autocomplete dropdown (incl. the mid-prompt
    # skill picker in extensions/skill-autocomplete.ts) room to browse.
    autocompleteMaxVisible = 8;
    enableSkillCommands = true;
    packages = piPackages;
    powerline = {
      preset = "default";
      placement = "above";
      welcome = false;
      cost.subscriptionDisplay = "reported-cost";
      cache_read.format = "both";
      queue.compactPromptMode = "native";
    };
    powerlineShortcuts = {
      stashHistory = null;
      copyEditor = null;
      cutEditor = null;
      queueOpen = null;
      editorStart = null;
      editorEnd = null;
    };
    subagents.disableBuiltins = true;
  };

  mkPiMcp = import ./lib/pi-mcp.nix { inherit lib pkgs; };
  piMcp = mkPiMcp { inherit isWork awsMcp; };

  piPackageSource = package: if builtins.isString package then package else package.source;
  piPackageNames = map (package: lib.removePrefix "npm:" (piPackageSource package)) piPackages;
  piAllowedPackagesFile = jsonFormat.generate "pi-allowed-packages.json" piPackageNames;

  piSettingsFile = jsonFormat.generate "pi-settings.json" piSettings;
  piMcpFile = jsonFormat.generate "pi-mcp.json" piMcp;
in
{
  home = {
    activation = {
      installPi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _install_pi() {
          run env PATH="${pkgs.nodejs_24}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin" \
            NPM_CONFIG_PREFIX="$HOME/.npm-global" \
            ${pkgs.nodejs_24}/bin/npm install -g --ignore-scripts @earendil-works/pi-coding-agent
        }

        if [[ ! -x "$HOME/.npm-global/bin/pi" ]]; then
          verboseEcho "pi: installing @earendil-works/pi-coding-agent into $HOME/.npm-global"
          _install_pi || {
            echo "pi: install failed (npm returned non-zero)" >&2
            exit 1
          }
        fi

        if [[ -x "$HOME/.npm-global/bin/pi" ]]; then
          verboseEcho "pi: installed version: $("$HOME/.npm-global/bin/pi" --version 2>/dev/null || echo unknown)"
        fi
        unset -f _install_pi
      '';

      # Wrapped in a function: activation entries are concatenated into one
      # `set -eu` script, so a bare `exit 0` here would silently skip every
      # later entry (launch agents, signer updates) with a success status.
      prunePiPackages = lib.hm.dag.entryAfter [ "installPi" ] ''
        _prune_pi_packages() {
          local npm_dir="$HOME/.pi/agent/npm"
          local pkg_json="$npm_dir/package.json"
          [[ -f "$pkg_json" ]] || return 0
          local extras
          extras=$(${pkgs.jq}/bin/jq -r --slurpfile allowed '${piAllowedPackagesFile}' \
            '(.dependencies // {}) | keys[] as $k | select($allowed[0] | index($k) | not) | $k' \
            "$pkg_json") || return 0
          [[ -n "$extras" ]] || return 0
          while IFS= read -r pkg; do
            [[ -n "$pkg" ]] || continue
            verboseEcho "pi: pruning undeclared package $pkg"
            run env PATH="${pkgs.nodejs_24}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin" \
              ${pkgs.nodejs_24}/bin/npm uninstall --prefix "$npm_dir" "$pkg" >/dev/null 2>&1 \
              || echo "pi: WARN: failed to prune undeclared package $pkg" >&2
          done <<< "$extras"
        }
        _prune_pi_packages
        unset -f _prune_pi_packages
      '';
    };

    file = {
      # Generated configuration.
      ".pi/agent/settings.json" = {
        source = piSettingsFile;
        force = true;
      };
      ".pi/agent/mcp.json" = {
        source = piMcpFile;
        force = true;
      };

      # Static configs — symlinked from config/pi/ so edits take effect without rebuild.
      # pi-web-access resolves its config dir as PI_CODING_AGENT_DIR ->
      # $XDG_CONFIG_HOME/pi -> ~/.pi/agent (homedir fallback). macOS leaves both
      # env vars unset, so it reads ~/.pi/agent/web-search.json — the pi agent
      # dir, not ~/.pi. Linux sessions export XDG_CONFIG_HOME=~/.config; the
      # matching xdg.configFile entry below covers that path. Both targets point
      # at the same source so `workflow: none` is honored on every host.
      ".pi/agent/web-search.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/web-search.json";

      # Extension configs — static JSON, symlinked.
      ".pi/agent/extensions/dotfiles-obsidian/config.json".source =
        jsonFormat.generate "pi-obsidian-config.json"
          {
            hookPath = "~/.claude/hooks/obsidian-session.sh";
            vaultPath = config.dotfiles.claude.obsidian.vaultPath;
          };
      ".pi/agent/extensions/pi-permission-system/config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/permission-system.json";
      ".pi/agent/pi-fff.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/pi-fff.json";
      ".pi/agent/pi-blackhole/pi-blackhole-config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/pi-blackhole.json";
      ".pi/agent/extensions/subagent/config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/subagents.json";

      # Extension source symlinks. Pi auto-discovers these paths and supports /reload.
      ".pi/agent/extensions/dotfiles-obsidian/index.ts".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/extensions/obsidian.ts";
      ".pi/agent/extensions/dotfiles-handoff/index.ts".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/extensions/handoff.ts";
      ".pi/agent/extensions/dotfiles-skill-autocomplete/index.ts".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/extensions/skill-autocomplete.ts";

      # Shared global instructions and skills — harness-agnostic prose owned by
      # config/shared and symlinked into both harnesses as a context/memory file:
      # pi reads it as ~/.pi/agent/AGENTS.md, Claude reads it as CLAUDE.md. Both
      # are context files layered above project AGENTS.md, so the two harnesses
      # stay symmetric. Behavioral guidance only; safety lives in the permission
      # system and semantic guards, so `-nc` dropping this file is not a risk.
      ".pi/agent/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/AGENTS.md";
      ".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/skills";
      ".pi/agent/themes".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/themes";

      # Prompt templates.
      ".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/prompts";
    }
    // piAgentFiles;
  };

  # pi-web-access reads this path on Linux when XDG_CONFIG_HOME is set and
  # PI_CODING_AGENT_DIR is unset. The rpiv packages use these XDG paths on every
  # host, falling back to the same ~/.config locations when the variable is unset.
  xdg.configFile = {
    "pi/web-search.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/web-search.json";
    "rpiv-ask-user-question/config.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/rpiv-ask-user-question.json";
    "rpiv-todo/config.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/rpiv-todo.json";
  };
}
