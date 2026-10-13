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
  observationalMemory = config.dotfiles.pi.observationalMemory;
  mkCurlInstaller = import ./lib/mk-curl-installer.nix { inherit lib pkgs; };

  mkPiAgent =
    name: prompt: frontmatter:
    pkgs.writeText "pi-agent-${name}.md" ''
      ---
      name: ${name}
      ${frontmatter}
      ---
      ${prompt}
    '';

  piAgentFiles = {
    ".pi/agent/agents/scout.md" = {
      source = mkPiAgent "scout" (builtins.readFile ../config/shared/agents/scout.md) ''
        description: Use for read-only codebase investigation that traces behavior, locates relevant files, callers, and tests, and returns cited evidence.
        tools: read, bash, grep, find, ls
        model: ${subagentModels.scout}
        thinking: low
        max_turns: 0
        run_in_background: true
        prompt_mode: replace
        inherit_context: false
        locked: model, thinking, max_turns, inherit_context
      '';
      force = true;
    };
    ".pi/agent/agents/reviewer.md" = {
      source =
        mkPiAgent "reviewer"
          (
            ''
              Before reviewing, read ${config.home.homeDirectory}/.pi/agent/skills/code-review/SKILL.md and follow it as the review contract; this runner does not preload skills.

            ''
            + builtins.readFile ../config/shared/agents/reviewer.md
          )
          ''
            description: Use for read-only review of an explicit fixed-point-to-HEAD diff against repository standards and the originating specification.
            tools: read, bash, grep, find, ls
            model: ${subagentModels.reviewer}
            thinking: high
            max_turns: 0
            run_in_background: true
            prompt_mode: replace
            inherit_context: false
            locked: model, thinking, max_turns, inherit_context
          '';
      force = true;
    };
    ".pi/agent/agents/worker.md" = {
      source = mkPiAgent "worker" (builtins.readFile ../config/shared/agents/worker.md) ''
        description: Use for an already well-scoped implementation task with clear success criteria; make minimal edits and run focused verification.
        tools: read, bash, edit, write, grep, find, ls, web_enable, web_search, fetch_content, get_search_content
        model: ${subagentModels.worker}
        thinking: high
        max_turns: 0
        run_in_background: true
        prompt_mode: replace
        inherit_context: false
        locked: model, thinking, max_turns, inherit_context
      '';
      force = true;
    };
  }
  //
    lib.genAttrs
      (map (name: ".pi/agent/agents/${name}.md") [
        "Explore"
        "Plan"
        "general-purpose"
      ])
      (_: {
        text = ''
          ---
          enabled: false
          ---
        '';
        force = true;
      })
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    ".pi/agent/agents/obsidian-second-brain.wiki-vault.md" = {
      source =
        mkPiAgent "obsidian-second-brain.wiki-vault"
          ''
            Before vault work, read these installed package files in order:
            1. ${config.home.homeDirectory}/.pi/agent/npm/node_modules/@soulwaxx/obsidian-second-brain/agents/pi/wiki-vault.md
            2. ${config.home.homeDirectory}/.pi/agent/npm/node_modules/@soulwaxx/obsidian-second-brain/skills/wiki/SKILL.md

            Follow the specialist's instructions and the wiki skill, including guard, validation, and Obsidian Git ownership rules. Resolve the configured vault independently of the caller's working directory. Do not delegate. Keep one wiki writer at a time. If either instruction file is missing, stop and report the blocker rather than proceeding without it.
          ''
          ''
            description: Work in the configured Obsidian vault using the packaged specialist contract and wiki skill.
            tools: read, bash, edit, write, grep, find, ls, web_enable, web_search, fetch_content, get_search_content
            ${lib.optionalString (
              config.dotfiles.pi.vaultAgentModel != null
            ) "model: ${config.dotfiles.pi.vaultAgentModel}"}
            max_turns: 0
            run_in_background: true
            prompt_mode: replace
            inherit_context: false
            locked: model, thinking, max_turns, inherit_context
          '';
      force = true;
    };
  };

  piPackages = [
    "npm:@gotgenes/pi-permission-system"
    "npm:@gotgenes/pi-anthropic-auth"
    "npm:pi-web-access"
    "npm:@gotgenes/pi-subagents"
    "npm:@juicesharp/rpiv-todo"
    "npm:@juicesharp/rpiv-ask-user-question"
    "npm:pi-powerline-footer"
    "npm:pi-observational-memory"
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    "npm:@soulwaxx/obsidian-second-brain"
  ];

  piSettings = {
    defaultProvider = config.dotfiles.pi.defaultProvider;
    defaultModel = config.dotfiles.pi.defaultModel;
    defaultThinkingLevel = "high";
    theme = "dark";
    defaultTools = [
      "+tool_search"
      "+codemode"
    ];
    # Opt out of the anonymous install/update ping and provider attribution
    # headers; keep analytics sharing off explicitly rather than relying on the
    # default.
    enableInstallTelemetry = false;
    enableAnalytics = false;
    # Render mermaid diagrams once complete instead of streaming partial frames.
    markdown.mermaid = "final";
    tuiMode = "fullscreen"; # alternatives: "fullscreen" (default since 1.0.0), "regular"
    # Force capabilities pi may under-detect behind a multiplexer.
    # Kitty images work in Ghostty through Herdr graphics passthrough.
    terminal = {
      hyperlinks = true;
      trueColor = true;
      images = "kitty";
    };
    defaultProjectTrust = "ask";
    quietStartup = true;
    # Give the skill/file/command autocomplete dropdown room to browse.
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
    # Fixed ("calibrated") threshold rather than a context-window ratio, so the
    # trigger does not depend on the window pi reports for the session model.
    "observational-memory" = {
      compactAfterTokensMode = "calibrated";
      inherit (observationalMemory) compactAfterTokens;
      model = {
        inherit (observationalMemory.model) provider id;
        thinking = "low";
      };
    };
  };

  mkPiMcp = import ./lib/pi-mcp.nix { inherit lib pkgs; };
  piMcp = mkPiMcp { inherit isWork awsMcp; };

  piPackageSource = package: if builtins.isString package then package else package.source;
  piPackageNames = map (package: lib.removePrefix "npm:" (piPackageSource package)) (
    builtins.filter (package: lib.hasPrefix "npm:" (piPackageSource package)) piPackages
  );
  piAllowedPackagesFile = jsonFormat.generate "pi-allowed-packages.json" piPackageNames;

  piSettingsFile = jsonFormat.generate "pi-settings.json" piSettings;
  piMcpFile = jsonFormat.generate "pi-mcp.json" piMcp;
in
{
  home = {
    # pi already copies via OSC 52 over SSH, but a pi started inside a
    # multiplexer and reattached later over SSH has no SSH_* variables.
    sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isLinux { PI_CLIPBOARD_OSC52 = "1"; };

    activation = {
      installPi = mkCurlInstaller {
        name = "pi";
        displayName = "Pi";
        installDir = "$HOME/.pi/agent/install";
        url = "https://pi.dev/install.sh";
        binPath = "$HOME/.local/bin/pi";
        installerCommand = [
          "${pkgs.nodejs_24}/bin/node"
          "${../config/pi/run-installer.cjs}"
          "${pkgs.bash}/bin/bash"
        ];
        # Prefer the managed entrypoint and expose the old npm install so the
        # upstream installer can migrate it after verifying the new release.
        extraPath = [
          "${pkgs.nodejs_24}/bin"
          "$HOME/.local/bin"
          "$HOME/.npm-global/bin"
          "/usr/bin"
          "/bin"
        ];
        postInstall = ''
          verboseEcho "pi: installed version: $("$BIN_PATH" --version 2>/dev/null || echo unknown)"
        '';
      };

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
      ".pi/agent/extensions/pi-permission-system/config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/permission-system.json";
      ".pi/agent/subagents.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/subagents.json";
      ".pi/agent/APPEND_SYSTEM.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/subagents.md";

      # Shared global instructions and skills — harness-agnostic prose owned by
      # config/shared and symlinked into both harnesses as a context/memory file:
      # pi reads it as ~/.pi/agent/AGENTS.md, Claude reads it as CLAUDE.md. Both
      # are context files layered above project AGENTS.md, so the two harnesses
      # stay symmetric. Behavioral guidance only; safety lives in the permission
      # system, so `-nc` dropping this file is not a risk.
      ".pi/agent/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/AGENTS.md";
      ".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/skills";

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
