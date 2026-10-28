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
  mkCurlInstaller = import ./lib/mk-curl-installer.nix { inherit lib pkgs; };
  theme = config.dotfiles.theme.current;

  # Catppuccin Mocha pi theme. Roles follow the Catppuccin style guide:
  # keywords Mauve, strings Green, functions Blue, types Yellow, operators Sky,
  # numbers Peach, comments and delimiters Overlay 2, active border Lavender.
  # Tool backgrounds reuse the catppuccin/delta 20% Red/Green blends.
  piThemeFile = jsonFormat.generate "pi-theme-${theme.name}.json" {
    "$schema" = "https://pi.dev/schemas/theme.schema.json";
    inherit (theme) name;
    appearance = "dark";
    vars = theme.palette;
    colors = {
      accent = "mauve";
      border = "lavender";
      borderAccent = "mauve";
      borderMuted = "overlay0";
      success = "green";
      error = "red";
      warning = "yellow";
      muted = "subtext0";
      dim = "overlay1";
      text = "text";
      thinkingText = "overlay2";
      selectedBg = "surface1";
      scrollbarTrack = "surface0";
      scrollbarThumb = "overlay1";
      searchMatchBg = "surface2";
      searchMatchText = "yellow";
      userMessageBg = "surface0";
      userMessageText = "text";
      customMessageBg = "mantle";
      customMessageText = "subtext0";
      customMessageLabel = "mauve";
      toolPendingBg = "mantle";
      toolSuccessBg = "#394545";
      toolErrorBg = "#493447";
      toolTitle = "text";
      toolOutput = "subtext0";
      mdHeading = "red";
      mdLink = "blue";
      mdLinkUrl = "overlay2";
      mdCode = "mauve";
      mdCodeBlock = "green";
      mdCodeBlockBorder = "overlay0";
      mdQuote = "subtext0";
      mdQuoteBorder = "overlay0";
      mdHr = "overlay0";
      mdListBullet = "mauve";
      toolDiffAdded = "green";
      toolDiffRemoved = "red";
      toolDiffContext = "overlay2";
      syntaxComment = "overlay2";
      syntaxKeyword = "mauve";
      syntaxFunction = "blue";
      syntaxVariable = "text";
      syntaxString = "green";
      syntaxNumber = "peach";
      syntaxType = "yellow";
      syntaxOperator = "sky";
      syntaxPunctuation = "overlay2";
      thinkingOff = "overlay0";
      thinkingMinimal = "overlay2";
      thinkingLow = "sapphire";
      thinkingMedium = "blue";
      thinkingHigh = "mauve";
      thinkingXhigh = "pink";
      thinkingMax = "red";
      bashMode = "green";
    };
    export = {
      pageBg = "base";
      cardBg = "mantle";
      infoBg = "surface0";
    };
  };

  mkPiAgent =
    name: prompt: frontmatter:
    pkgs.writeText "pi-agent-${name}.md" ''
      ---
      name: ${name}
      ${frontmatter}
      ---
      ${prompt}
    '';

  # pi-subagents agent definitions. Builtin agents are disabled in settings;
  # on macOS the obsidian-second-brain package also ships its own vault agent.
  piAgentFiles = {
    ".pi/agent/agents/scout.md" = {
      source = mkPiAgent "scout" (builtins.readFile ../config/shared/agents/scout.md) ''
        description: Use for read-only codebase investigation that traces behavior, locates relevant files, callers, and tests, and returns cited evidence.
        advertise: true
        tools: read, bash, grep, find, ls
        model: ${subagentModels.scout}
        thinking: low
        async: true
        inheritProjectContext: true
        inheritGlobalContext: true
        acceptanceRole: read-only
      '';
      force = true;
    };
    ".pi/agent/agents/reviewer.md" = {
      # pi-subagents never injects skills marked disable-model-invocation
      # (code-review is explicit-only), so point the reviewer at the file.
      source =
        mkPiAgent "reviewer"
          (
            ''
              For diff reviews only, read ${config.home.homeDirectory}/.pi/agent/skills/code-review/SKILL.md and follow it as the review contract.

            ''
            + builtins.readFile ../config/shared/agents/reviewer.md
          )
          ''
            description: Use for read-only diff reviews against an explicit fixed point, or current-state audits of named files, configuration, or behavior against supplied criteria.
            advertise: true
            tools: read, bash, grep, find, ls
            model: ${subagentModels.reviewer}
            thinking: high
            async: true
            inheritProjectContext: true
            inheritGlobalContext: true
            acceptanceRole: read-only
          '';
      force = true;
    };
    ".pi/agent/agents/researcher.md" = {
      source =
        mkPiAgent "researcher"
          (
            ''
              Read ${config.home.homeDirectory}/.pi/agent/skills/research/SKILL.md for its sourcing and verification rules. Return the brief in your response; do not follow its file-writing steps.

            ''
            + builtins.readFile ../config/shared/agents/researcher.md
          )
          ''
            description: Use for read-only local and web research on a bounded question; return inspected primary-source citations, findings, and unknowns without editing or publishing.
            advertise: true
            tools: read, bash, grep, find, ls, web_enable, web_search, fetch_content, get_search_content
            model: ${subagentModels.worker}
            thinking: high
            async: true
            inheritProjectContext: true
            inheritGlobalContext: true
            acceptanceRole: read-only
          '';
      force = true;
    };
    ".pi/agent/agents/infra-reviewer.md" = {
      source =
        mkPiAgent "infra-reviewer"
          (
            ''
              Read ${config.home.homeDirectory}/.pi/agent/skills/infra-review/SKILL.md and follow it as the review contract. For Kubernetes, Helm, Kustomize, or GitOps reviews, also read ${config.home.homeDirectory}/.pi/agent/skills/kubernetes-skill/SKILL.md and its relevant references.

            ''
            + builtins.readFile ../config/shared/agents/infra-reviewer.md
          )
          ''
            description: Use for read-only operational-risk review of Terraform/OpenTofu, Kubernetes/GitOps, and infrastructure security; verify official docs and report evidence-backed findings without applying changes.
            advertise: true
            tools: read, bash, grep, find, ls, web_enable, web_search, fetch_content, get_search_content
            model: ${subagentModels.reviewer}
            thinking: high
            async: true
            inheritProjectContext: true
            inheritGlobalContext: true
            acceptanceRole: read-only
          '';
      force = true;
    };
    ".pi/agent/agents/worker.md" = {
      source = mkPiAgent "worker" (builtins.readFile ../config/shared/agents/worker.md) ''
        description: Use for an already well-scoped implementation task with clear success criteria; make minimal edits and run focused verification.
        advertise: true
        tools: read, bash, edit, write, grep, find, ls, web_enable, web_search, fetch_content, get_search_content
        model: ${subagentModels.worker}
        thinking: high
        async: true
        inheritProjectContext: true
        inheritGlobalContext: true
        acceptanceRole: writer
      '';
      force = true;
    };
  };

  piPackages = [
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
    "npm:@soulwaxx/pi-skill-autocomplete"
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    "npm:@soulwaxx/obsidian-second-brain"
  ];

  piSettings = {
    defaultProvider = config.dotfiles.pi.defaultProvider;
    defaultModel = config.dotfiles.pi.defaultModel;
    defaultThinkingLevel = "high";
    # Keep ordinary reserves for unlisted models, including smaller subagents.
    compaction = {
      enabled = true;
      reserveTokens = 16384;
      keepRecentTokens = 20000;
      modelOverrides = {
        # Confirmed 1M work window: compact above 300K context tokens.
        "anthropic/claude-opus-5-5".reserveTokens = 1000000 - 300000;
        # Confirmed 272K personal window: compact above 220K context tokens.
        "openai/gpt-6.1-sol".reserveTokens = 272000 - 220000;
      };
    };
    theme = theme.name;
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
    # pi-subagents settings-level keys; runtime limits live in config/pi/subagents.json.
    # Only the agents declared in this module (plus the macOS vault package agent) are used.
    subagents = {
      disableBuiltins = true;
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      # The package agent already inherits project context; add the global AGENTS.md.
      agentOverrides."obsidian-second-brain.wiki-vault" = {
        inheritGlobalContext = true;
      }
      // lib.optionalAttrs (config.dotfiles.pi.vaultAgentModel != null) {
        model = config.dotfiles.pi.vaultAgentModel;
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

  # Use explicit per-host paths: pi-fff does not expand ~ in database paths,
  # and its automatic defaults would reuse existing Neovim FFF databases.
  piFffFile = jsonFormat.generate "pi-fff.json" {
    "$schema" =
      "https://raw.githubusercontent.com/dmtrKovalenko/fff/main/packages/pi-fff/pi-fff.schema.json";
    mode = "override";
    frecencyDbPath = "${config.home.homeDirectory}/.pi/agent/fff/frecency";
    historyDbPath = "${config.home.homeDirectory}/.pi/agent/fff/history";
    enableFsRootScanning = false;
    enableHomeDirScanning = false;
    followSymlinks = true;
  };

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
      ".pi/agent/pi-fff.json" = {
        source = piFffFile;
        force = true;
      };
      ".pi/agent/themes/${theme.name}.json" = {
        source = piThemeFile;
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

      # Display-only footer, auto-discovered by pi on every host.
      ".pi/agent/extensions/dotfiles-statusline".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/statusline";

      # Extension configs — static JSON, symlinked.
      ".pi/agent/extensions/pi-permission-system/config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/permission-system.json";
      ".pi/agent/extensions/subagent/config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/subagents.json";

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
