{
  pkgs,
  config,
  lib,
  ...
}:

# oh-my-pi (omp) trial alongside pi. omp keeps its own state under ~/.omp and
# reads ~/.pi only through the linked Obsidian package below.
# config/omp/config.yml is hand-maintained; this module installs the binary
# and renders only files that need Nix values.
let
  dotfiles = config.dotfiles.path;
  jsonFormat = pkgs.formats.json { };
  isWork = config.dotfiles.claude.enableWorkIntegrations;
  awsMcp = config.dotfiles.aws.mcp;
  subagentModels = config.dotfiles.pi.subagentModels;
  mkCurlInstaller = import ./lib/mk-curl-installer.nix { inherit lib pkgs; };
  mcpServersLib = import ./mcp-servers.nix { inherit lib pkgs; };

  # omp needs an explicit transport type and takes timeouts in milliseconds.
  ompMcpFile = jsonFormat.generate "omp-mcp.json" {
    mcpServers =
      lib.mapAttrs
        (
          name: entry:
          (lib.removeAttrs entry [ "description" ])
          // {
            type = if entry ? url then "http" else "stdio";
            timeout = if name == "aws-mcp" then 300000 else 60000;
          }
        )
        (
          mcpServersLib.commonServers
          // lib.optionalAttrs isWork (mcpServersLib.mkWorkServers { inherit awsMcp; })
        );
  };

  # Repository agents replace omp's bundled ones (see task.disabledAgents in
  # config/omp/config.yml). Prompt bodies are shared with pi and Claude.
  readTools = "read, grep, glob, bash";
  mkOmpAgent =
    name:
    {
      description,
      model,
      thinking,
      tools,
      preamble ? "",
      autoloadSkills ? [ ],
    }:
    {
      source = pkgs.writeText "omp-agent-${name}.md" ''
        ---
        name: ${name}
        description: ${description}
        tools: ${tools}
        model: anthropic/${model}
        thinking-level: ${thinking}
        ${lib.optionalString (
          autoloadSkills != [ ]
        ) "autoloadSkills: [${lib.concatStringsSep ", " autoloadSkills}]"}
        ---
        ${preamble}${builtins.readFile ../config/shared/agents/${name}.md}'';
      force = true;
    };

  ompAgents = lib.mapAttrs' (name: spec: lib.nameValuePair ".omp/agent/agents/${name}.md" spec) (
    lib.mapAttrs mkOmpAgent {
      scout = {
        description = "Use for read-only codebase investigation that traces behavior, locates relevant files, callers, and tests, and returns cited evidence.";
        model = subagentModels.scout;
        thinking = "low";
        tools = readTools;
      };
      reviewer = {
        description = "Use for read-only diff reviews against an explicit fixed point, or current-state audits of named files, configuration, or behavior against supplied criteria.";
        model = subagentModels.reviewer;
        thinking = "high";
        tools = readTools;
        # code-review is explicit-only, so diff reviews read it on demand.
        preamble = ''
          For diff reviews only, read skill://code-review and follow it as the review contract.

        '';
      };
      worker = {
        description = "Use for an already well-scoped implementation task with clear success criteria; make minimal edits and run focused verification.";
        model = subagentModels.worker;
        thinking = "high";
        tools = "${readTools}, edit, write, web_search";
      };
      researcher = {
        description = "Use for read-only local and web research on a bounded question; return inspected primary-source citations, findings, and unknowns without editing or publishing.";
        model = subagentModels.worker;
        thinking = "high";
        tools = "${readTools}, web_search";
        autoloadSkills = [ "research" ];
      };
      infra-reviewer = {
        description = "Use for read-only operational-risk review of Terraform/OpenTofu, Kubernetes/GitOps, and infrastructure security; verify official docs and report evidence-backed findings without applying changes.";
        model = subagentModels.reviewer;
        thinking = "high";
        tools = "${readTools}, web_search";
        autoloadSkills = [ "infra-review" ];
        preamble = ''
          For Kubernetes, Helm, Kustomize, or GitOps reviews, also read skill://kubernetes-skill and its relevant references.

        '';
      };
    }
  );
in
{
  home.activation = {
    # Prebuilt, SHA-256-verified binary; installs only when missing. Upgrade
    # with `omp update` (update.auto is off in config.yml).
    installOmp = mkCurlInstaller {
      name = "omp";
      displayName = "omp";
      installDir = "$HOME/.local/bin";
      url = "https://omp.sh/install";
      binPath = "$HOME/.local/bin/omp";
      installerArgs = [ "--binary" ];
      extraPath = [
        "${pkgs.gnugrep}/bin"
        "${pkgs.gnused}/bin"
      ];
      postInstall = ''
        verboseEcho "omp: installed version: $("$BIN_PATH" --version 2>/dev/null || echo unknown)"
      '';
    };
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    # Reuse pi's managed copy of the vault package, as the obsidian-second-brain
    # CLI wrapper does. Best effort: warn and continue on failure. Wrapped in a
    # function: a bare `exit` would skip later activation entries.
    linkOmpObsidianPlugin = lib.hm.dag.entryAfter [ "installOmp" ] ''
      _link_omp_obsidian_plugin() {
        local omp="$HOME/.local/bin/omp"
        local pkg="$HOME/.pi/agent/npm/node_modules/@soulwaxx/obsidian-second-brain"
        local linked="$HOME/.omp/plugins/node_modules/@soulwaxx/obsidian-second-brain"
        [[ -x "$omp" ]] || return 0
        if [[ ! -d "$pkg" ]]; then
          echo "omp: WARN: $pkg is missing; start pi once, then switch again to link it" >&2
          return 0
        fi
        [[ -e "$linked" ]] && return 0
        run "$omp" plugin link "$pkg" \
          || echo "omp: WARN: failed to link @soulwaxx/obsidian-second-brain" >&2
      }
      _link_omp_obsidian_plugin
      unset -f _link_omp_obsidian_plugin
    '';
  };

  home.file = {
    ".omp/agent/mcp.json" = {
      source = ompMcpFile;
      force = true;
    };

    # Hand-maintained settings; omp writes runtime changes through the link.
    ".omp/agent/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/omp/config.yml";

    # RULES.md, unlike AGENTS.md, also reaches omp subagents, matching pi's
    # inheritGlobalContext for the repository agents.
    ".omp/agent/RULES.md".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/AGENTS.md";
    ".omp/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/skills";
    ".omp/agent/commands/adversarial.md".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/prompts/adversarial.md";
    ".omp/agent/commands/lesson.md".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/shared/prompts/lesson.md";
  }
  // ompAgents;
}
