{
  description = "Dotfiles — Nix + Home Manager";

  inputs = {
    # nixpkgs-unstable, not master: only the channel branches wait for Darwin
    # builds to reach cache.nixos.org, and this repo is macOS-majority.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      home-manager,
      nixgl,
      treefmt-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # Where the dotfiles repo is cloned. Set DOTFILES_DIR and use the
      # generated switch apps for nonstandard clone locations; the apps pass
      # --impure only when DOTFILES_DIR is set so this remains pure by default.
      dotfilesDirFromEnv = builtins.getEnv "DOTFILES_DIR";
      dotfilesDir = if dotfilesDirFromEnv != "" then dotfilesDirFromEnv else "dotfiles";
      defaultDotfilesPath = if lib.hasPrefix "/" dotfilesDir then dotfilesDir else "$HOME/${dotfilesDir}";

      appDotfilesSetup =
        {
          withExtraArgs ? false,
        }:
        ''
          ${lib.optionalString withExtraArgs ''dotfiles_dir_from_env="''${DOTFILES_DIR:-}"''}
          export DOTFILES_DIR="''${DOTFILES_DIR:-${defaultDotfilesPath}}"
          if [[ "$DOTFILES_DIR" != /* ]]; then
            DOTFILES_DIR="$HOME/$DOTFILES_DIR"
          fi
          cd "$DOTFILES_DIR"
          ${lib.optionalString withExtraArgs ''
            extra_args=()
            [[ -n "$dotfiles_dir_from_env" ]] && extra_args+=(--impure)
          ''}
        '';

      darwinHosts = {
        "work-macbook" = {
          app = "switch-work";
          module = ./hosts/work-macbook.nix;
          role = "work";
          username = "andrea.balsamo";
          system = "aarch64-darwin";
        };

        "personal-mac" = {
          app = "switch-personal";
          module = ./hosts/personal-mac.nix;
          role = "personal";
          username = "balsamoan";
          system = "aarch64-darwin";
        };
      };

      linuxHosts = {
        "oci-arm" = {
          app = "switch-oci-arm";
          enableDesktop = false;
          enableKubernetes = false;
          enableLoginShellRegistration = true;
          module = ./hosts/linux-personal.nix;
          role = "personal";
          username = "ubuntu";
          system = "aarch64-linux";
        };

        "tnas-f2-424" = {
          app = "switch-tnas";
          enableDesktop = false;
          enableKubernetes = true;
          enableLoginShellRegistration = false;
          module = ./hosts/linux-personal.nix;
          role = "personal";
          username = "omv";
          system = "x86_64-linux";
        };

        "probook" = {
          app = "switch-probook";
          enableDesktop = true;
          enableKubernetes = true;
          enableLoginShellRegistration = true;
          module = ./hosts/linux-personal.nix;
          role = "personal";
          username = "soulwaxx";
          system = "x86_64-linux";
        };
      };

      # Wrap a shell snippet as a runnable flake app (nix run .#<name>)
      mkApp = pkgs: name: text: {
        type = "app";
        program = "${pkgs.writeShellScriptBin name text}/bin/${name}";
        meta.description = name;
      };

      # Warn-only check of untracked host files; bootstrap runs it with --prompt.
      localFilesCheck = pkgs: host: ''
        PATH="${pkgs.git}/bin:$PATH" ${pkgs.bash}/bin/bash ${./local-files.sh} ${host.role}
      '';

      nixStoreCheck = pkgs: ''
        if ! ${pkgs.nix}/bin/nix-store --verify --check-contents; then
          echo "Nix store/database inconsistency detected. Do not edit /nix/store directly; repair the reported paths before continuing." >&2
          exit 1
        fi
        writable_store_path="$(${pkgs.findutils}/bin/find /nix/store \
          -mindepth 1 -maxdepth 1 ! -type l ! -name '*.lock' ! -name .links \
          \( -perm -0200 -o -perm -0020 -o -perm -0002 \) -print -quit)"
        if [[ -n "$writable_store_path" ]]; then
          echo "Writable Nix store path detected: $writable_store_path" >&2
          echo "Do not chmod paths under /nix/store; repair it before continuing." >&2
          exit 1
        fi
      '';

      # Resolve the absolute on-host path to the dotfiles checkout once, here,
      # so both nix-darwin (system) modules and Home Manager (user) modules
      # receive the same value via specialArgs/extraSpecialArgs. Avoids each
      # module re-implementing the "is it absolute? else prepend $HOME" rule.
      resolveDotfilesPath =
        { username, isDarwin }:
        if lib.hasPrefix "/" dotfilesDir then
          dotfilesDir
        else
          "${if isDarwin then "/Users" else "/home"}/${username}/${dotfilesDir}";

      mkDarwin =
        {
          hostname,
          hostModule,
          system ? "aarch64-darwin",
          username,
        }:
        let
          dotfilesPath = resolveDotfilesPath {
            inherit username;
            isDarwin = true;
          };
        in
        nix-darwin.lib.darwinSystem {
          inherit system;
          modules = [
            hostModule
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-backup";
                extraSpecialArgs = {
                  inherit
                    dotfilesDir
                    dotfilesPath
                    hostname
                    ;
                };
              };
            }
          ];
          specialArgs = {
            inherit
              nixpkgs
              username
              dotfilesDir
              dotfilesPath
              hostname
              ;
          };
        };

      mkLinux =
        {
          hostname,
          hostModule,
          system ? "x86_64-linux",
          username,
          enableDesktop ? false,
          enableKubernetes ? false,
          enableLoginShellRegistration ? false,
        }:
        let
          dotfilesPath = resolveDotfilesPath {
            inherit username;
            isDarwin = false;
          };
          nixglPackages = nixgl.packages.${system};
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          modules = [ hostModule ];
          extraSpecialArgs = {
            linuxHost = {
              inherit
                enableDesktop
                enableKubernetes
                enableLoginShellRegistration
                ;
            };
            inherit
              nixpkgs
              username
              dotfilesDir
              dotfilesPath
              hostname
              nixglPackages
              ;
          };
        };

      treefmtWrapperFor = pkgs: (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.wrapper;

      mkChecks = pkgs: {
        bootstrap =
          pkgs.runCommand "check-bootstrap"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gawk
                pkgs.git
                pkgs.gnugrep
              ];
            }
            ''
              ${pkgs.bash}/bin/bash ${./tests/bootstrap.sh} ${./bootstrap.sh} ${./local-files.sh}
              touch $out
            '';
        # Behavioural test for the MCP reconcile filter. Only the filter and
        # the script are copied in, so the whole repo does not enter the store.
        claude-state-jq = pkgs.runCommand "check-claude-state-jq" { nativeBuildInputs = [ pkgs.jq ]; } ''
          mkdir -p tests modules/claude/jq
          cp ${./tests/claude-state-jq.sh} tests/claude-state-jq.sh
          cp ${./modules/claude/jq/reconcile-mcp.jq} modules/claude/jq/reconcile-mcp.jq
          ${pkgs.bash}/bin/bash tests/claude-state-jq.sh
          touch $out
        '';
        herdr-config = pkgs.runCommand "check-herdr-config" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          python3 ${./tests/herdr-config.py} ${./config/herdr/config.toml}
          touch $out
        '';
        skill-autocomplete =
          pkgs.runCommand "check-skill-autocomplete" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
            ''
              node ${./tests/skill-autocomplete.mjs} ${./config/pi/extensions/skill-autocomplete.ts}
              touch $out
            '';
        semantic-command-scanner =
          pkgs.runCommand "check-semantic-command-scanner"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.jq
              ];
            }
            ''
              mkdir -p tests config/claude/hooks
              cp ${./tests/semantic-command-scanner.sh} tests/semantic-command-scanner.sh
              cp ${./config/claude/hooks/semantic-command-scanner.sh} config/claude/hooks/semantic-command-scanner.sh
              ${pkgs.bash}/bin/bash tests/semantic-command-scanner.sh \
                config/claude/hooks/semantic-command-scanner.sh
              touch $out
            '';
        obsidian-lifecycle =
          pkgs.runCommand "check-obsidian-lifecycle"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.git
                pkgs.jq
                pkgs.nodejs_24
                (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
              ];
            }
            ''
              ${pkgs.bash}/bin/bash ${./tests/obsidian-lifecycle.sh} \
                ${./config/claude/hooks/obsidian-session.sh} \
                ${./config/shared/skills/wiki/scripts/okf_mw}
              python3 ${./tests/obsidian-middleware.py} \
                ${./config/shared/skills/wiki/scripts/okf_mw} \
                ${./config/shared/skills/wiki/scripts/migrate_wikilinks.py}
              node ${./tests/obsidian-extension.mjs} \
                ${./config/pi/extensions/obsidian.ts} \
                ${./config/claude/hooks/obsidian-session.sh} \
                ${./config/shared/skills/wiki/scripts/okf_mw}
              touch $out
            '';
        zsh-functions =
          pkgs.runCommand "check-zsh-functions"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.zsh
              ];
            }
            ''
              mkdir -p tests modules/zsh
              cp ${./tests/zsh-functions.zsh} tests/zsh-functions.zsh
              cp ${./modules/zsh/nvim-functions.zsh} modules/zsh/nvim-functions.zsh
              cp ${./modules/zsh/git-functions.zsh} modules/zsh/git-functions.zsh
              cp ${./modules/zsh/aliases.nix} modules/zsh/aliases.nix
              ${pkgs.zsh}/bin/zsh tests/zsh-functions.zsh \
                modules/zsh/nvim-functions.zsh \
                modules/zsh/git-functions.zsh \
                modules/zsh/aliases.nix
              touch $out
            '';
      };

      mkCommonApps =
        pkgs:
        let
          treefmtWrapper = treefmtWrapperFor pkgs;
          currentSystem = pkgs.stdenv.hostPlatform.system;
          darwinBuildTargets = lib.concatStringsSep " " (
            map (hostname: ".#darwinConfigurations.${hostname}.system") (
              lib.attrNames (lib.filterAttrs (_: host: host.system == currentSystem) darwinHosts)
            )
          );
          linuxBuildTargets = lib.concatStringsSep " " (
            map (hostname: ".#homeConfigurations.${hostname}.activationPackage") (
              lib.attrNames (lib.filterAttrs (_: host: host.system == currentSystem) linuxHosts)
            )
          );
          # Per-host evaluation. `nix flake check` never walks
          # homeConfigurations/darwinConfigurations, so a broken host ships
          # silently. Evaluating the activation/system derivation *path* forces
          # the entire config — every home.file source, package, and activation
          # string — and fires module assertions, while still building nothing.
          # This repo is IFD-free by construction, so it evaluates from either
          # platform without a cross-build.
          #
          # An earlier version forced only `config.assertions`, which walks the
          # assertion list and almost nothing else: a typo in a package attr or
          # a broken mkOutOfStoreSymlink source passed `check` and only
          # surfaced at `check-build`.
          evalCheckTargets = lib.concatStringsSep " " (
            map (hostname: ".#homeConfigurations.${hostname}.activationPackage.drvPath") (
              lib.attrNames linuxHosts
            )
            ++ map (hostname: ".#darwinConfigurations.${hostname}.system.drvPath") (lib.attrNames darwinHosts)
          );
          hostLines = lib.mapAttrsToList (
            hostname: host: "${hostname}\t${host.system}\t${host.username}\t${host.app}\t${host.role}"
          ) (darwinHosts // linuxHosts);
          lintSnippet = ''
            sh_files=()
            while IFS= read -r -d "" file; do
              sh_files+=("$file")
            done < <(${pkgs.ripgrep}/bin/rg --files -0 --hidden -g '*.sh')
            if (( ''${#sh_files[@]} > 0 )); then
              ${pkgs.shellcheck}/bin/shellcheck "''${sh_files[@]}"
            fi

            zsh_files=()
            while IFS= read -r -d "" file; do
              zsh_files+=("$file")
            done < <(${pkgs.ripgrep}/bin/rg --files -0 --hidden -g '*.zsh')
            for file in "''${zsh_files[@]}"; do
              ${pkgs.zsh}/bin/zsh -n "$file"
            done

            json_files=()
            while IFS= read -r -d "" file; do
              json_files+=("$file")
            done < <(${pkgs.ripgrep}/bin/rg --files -0 --hidden -g '*.json' -g '!config/zed/**' config)
            if (( ''${#json_files[@]} > 0 )); then
              # config/zed/ is excluded: Zed settings are JSONC (trailing commas), not strict JSON.
              ${pkgs.jq}/bin/jq -e . "''${json_files[@]}" >/dev/null
            fi
            # tests/ are flake `checks` outputs, run by `nix flake check` in the
            # check app; lint stays formatting/static-analysis only.
            ${pkgs.statix}/bin/statix check .
            ${pkgs.deadnix}/bin/deadnix --fail .
          '';
          # treefmt owns formatting and its own file discovery; --ci fails on any
          # file it would reformat.
          fmtCheckSnippet = ''
            ${treefmtWrapper}/bin/treefmt --ci
          '';
          # Fast validation: flake eval + checks, per-host eval, formatting, lint.
          # No --no-build: the `checks` outputs are the test suite and must
          # actually run. They are tiny; the other buildable outputs
          # (devShells.default, formatter) are already substituted.
          checkSnippet = ''
            set -euo pipefail
            ${appDotfilesSetup { withExtraArgs = true; }}
            nix flake check "''${extra_args[@]}" --all-systems
            for target in ${evalCheckTargets}; do
              nix eval "''${extra_args[@]}" --raw "$target" >/dev/null
            done
            ${fmtCheckSnippet}
            ${lintSnippet}
          '';
        in
        {
          # Validate the flake without building, plus lightweight source lint.
          check = mkApp pkgs "check" checkSnippet;
          # Run check then build activation outputs for every declared host on this system.
          check-full = mkApp pkgs "check-full" ''
            ${checkSnippet}
            if [[ "$(uname -s)" == "Darwin" ]]; then
              ${pkgs.nix-output-monitor}/bin/nom build "''${extra_args[@]}" --no-link ${darwinBuildTargets}
            else
              ${pkgs.nix-output-monitor}/bin/nom build "''${extra_args[@]}" --no-link ${linuxBuildTargets}
            fi
          '';
          # Validate shell scripts and source JSON files.
          lint = mkApp pkgs "lint" ''
            set -euo pipefail
            ${appDotfilesSetup { }}
            ${fmtCheckSnippet}
            ${lintSnippet}
          '';
          # Verify Nix formatting without modifying files.
          fmt-check = mkApp pkgs "fmt-check" ''
            set -euo pipefail
            ${appDotfilesSetup { }}
            ${fmtCheckSnippet}
          '';
          # Print the canonical host inventory from flake.nix.
          hosts = mkApp pkgs "hosts" ''
            set -euo pipefail
            printf 'host\tsystem\tuser\tswitch-app\trole\n'
            printf '%s\n' ${lib.escapeShellArgs hostLines}
          '';
          # Build activation outputs for every declared host on this system.
          check-build = mkApp pkgs "check-build" ''
            set -euo pipefail
            ${appDotfilesSetup { withExtraArgs = true; }}
            if [[ "$(uname -s)" == "Darwin" ]]; then
              ${pkgs.nix-output-monitor}/bin/nom build "''${extra_args[@]}" --no-link ${darwinBuildTargets}
            else
              ${pkgs.nix-output-monitor}/bin/nom build "''${extra_args[@]}" --no-link ${linuxBuildTargets}
            fi
          '';
          # Format all files treefmt knows about (currently Nix via nixfmt).
          fmt = mkApp pkgs "fmt" ''
            set -euo pipefail
            ${appDotfilesSetup { }}
            ${treefmtWrapper}/bin/treefmt
          '';
          # Garbage-collect the Nix store
          clean = mkApp pkgs "clean" ''
            set -euo pipefail
            ${nixStoreCheck pkgs}
            nix store gc
            nix store optimise
            ${nixStoreCheck pkgs}
          '';
        };

      mkDarwinSwitchApp =
        pkgs: hostname: host: name:
        mkApp pkgs name ''
          set -euo pipefail
          force_host_mismatch=0
          if [[ "''${1:-}" == "--force-host-mismatch" ]]; then
            force_host_mismatch=1
            shift
          fi
          if [[ "$force_host_mismatch" -ne 1 && "$(${pkgs.coreutils}/bin/id -un)" != "${host.username}" ]]; then
            echo "Refusing to switch ${hostname}: expected user ${host.username}, got $(${pkgs.coreutils}/bin/id -un). Pass --force-host-mismatch to override." >&2
            exit 1
          fi
          ${appDotfilesSetup { withExtraArgs = true; }}
          ${localFilesCheck pkgs host}
          # nh wraps darwin-rebuild and self-elevates twice: once to set the
          # system profile and once to activate. Pre-validate sudo so the
          # credential cache covers both calls — one Touch ID tap, not two.
          sudo -v
          ${pkgs.nh}/bin/nh darwin switch . -H ${hostname} -- "''${extra_args[@]}" "$@"
        '';

      mkDarwinBootstrapApps =
        pkgs:
        lib.mapAttrs' (
          hostname: host:
          lib.nameValuePair "bootstrap-${hostname}" (
            mkApp pkgs "bootstrap-${hostname}" ''
              set -euo pipefail
              if [[ "$(${pkgs.coreutils}/bin/id -un)" != "${host.username}" ]]; then
                echo "Refusing to bootstrap ${hostname}: expected user ${host.username}, got $(${pkgs.coreutils}/bin/id -un)." >&2
                exit 1
              fi
              ${appDotfilesSetup { withExtraArgs = true; }}
              ${nixStoreCheck pkgs}
              sudo --preserve-env=HOME,DOTFILES_DIR \
                ${nix-darwin.packages.${host.system}.darwin-rebuild}/bin/darwin-rebuild \
                switch --flake "$DOTFILES_DIR#${hostname}" "''${extra_args[@]}" "$@"
            ''
          )
        ) darwinHosts;

      mkLinuxSwitchApp =
        pkgs: hostname: host: name:
        mkApp pkgs name ''
          set -euo pipefail
          force_host_mismatch=0
          if [[ "''${1:-}" == "--force-host-mismatch" ]]; then
            force_host_mismatch=1
            shift
          fi
          if [[ "$force_host_mismatch" -ne 1 && "$(${pkgs.coreutils}/bin/id -un)" != "${host.username}" ]]; then
            echo "Refusing to switch ${hostname}: expected user ${host.username}, got $(${pkgs.coreutils}/bin/id -un). Pass --force-host-mismatch to override." >&2
            exit 1
          fi
          ${appDotfilesSetup { withExtraArgs = true; }}
          ${localFilesCheck pkgs host}
          # nh starts its own nix process, so the outer `nix run` feature flags
          # do not reach it during the first switch, before Home Manager has
          # written ~/.config/nix/nix.conf.
          export NIX_CONFIG="''${NIX_CONFIG:-}
          experimental-features = nix-command flakes"
          # nh wraps home-manager: nvd diff of changed packages on every switch.
          ${pkgs.nh}/bin/nh home switch . -c ${hostname} -- "''${extra_args[@]}" "$@"
        '';

      mkSwitchApps =
        pkgs: mkSwitch: hosts:
        lib.mapAttrs' (
          hostname: host: lib.nameValuePair host.app (mkSwitch pkgs hostname host host.app)
        ) hosts
        // lib.mapAttrs (hostname: host: mkSwitch pkgs hostname host hostname) hosts;
    in
    {
      darwinConfigurations = lib.mapAttrs (
        hostname: host:
        mkDarwin {
          inherit hostname;
          hostModule = host.module;
          inherit (host) system username;
        }
      ) darwinHosts;

      homeConfigurations = lib.mapAttrs (
        hostname: host:
        mkLinux {
          inherit hostname;
          hostModule = host.module;
          inherit (host)
            enableDesktop
            enableKubernetes
            enableLoginShellRegistration
            system
            username
            ;
        }
      ) linuxHosts;

      apps =
        let
          darwinPkgs = nixpkgs.legacyPackages.aarch64-darwin;
          armLinuxPkgs = nixpkgs.legacyPackages.aarch64-linux;
          x86LinuxPkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
          aarch64-darwin =
            mkCommonApps darwinPkgs
            // mkSwitchApps darwinPkgs mkDarwinSwitchApp darwinHosts
            // mkDarwinBootstrapApps darwinPkgs;
          aarch64-linux = mkCommonApps armLinuxPkgs // mkSwitchApps armLinuxPkgs mkLinuxSwitchApp linuxHosts;
          x86_64-linux = mkCommonApps x86LinuxPkgs // mkSwitchApps x86LinuxPkgs mkLinuxSwitchApp linuxHosts;
        };

      # Pure-eval invariant tests plus the MCP reconcile filter test.
      # `nix run .#check` runs these via `nix flake check`.
      checks = {
        aarch64-darwin = mkChecks nixpkgs.legacyPackages.aarch64-darwin;
        aarch64-linux = mkChecks nixpkgs.legacyPackages.aarch64-linux;
        x86_64-linux = mkChecks nixpkgs.legacyPackages.x86_64-linux;
      };

      # `nix fmt` standard entry point, backed by treefmt (treefmt.nix).
      # `nix run .#fmt` runs the same wrapper.
      formatter = {
        aarch64-darwin = treefmtWrapperFor nixpkgs.legacyPackages.aarch64-darwin;
        aarch64-linux = treefmtWrapperFor nixpkgs.legacyPackages.aarch64-linux;
        x86_64-linux = treefmtWrapperFor nixpkgs.legacyPackages.x86_64-linux;
      };

      devShells =
        let
          mkDevShell =
            pkgs:
            (pkgs.mkShell.override { stdenv = pkgs.stdenvNoCC; }) {
              packages = [
                pkgs.bash
                pkgs.deadnix
                pkgs.jq
                pkgs.nh
                pkgs.nix-fast-build
                pkgs.nix-output-monitor
                pkgs.ripgrep
                pkgs.shellcheck
                pkgs.statix
                # Formatting goes through treefmt (treefmt.nix); `nix fmt` or
                # `nix run .#fmt` invoke the same wrapper.
                (treefmtWrapperFor pkgs)
                pkgs.zsh
              ];
            };
        in
        {
          aarch64-darwin.default = mkDevShell nixpkgs.legacyPackages.aarch64-darwin;
          aarch64-linux.default = mkDevShell nixpkgs.legacyPackages.aarch64-linux;
          x86_64-linux.default = mkDevShell nixpkgs.legacyPackages.x86_64-linux;
        };
    };
}
