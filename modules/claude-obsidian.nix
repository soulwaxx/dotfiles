{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.dotfiles.claude.obsidian;
  homeDir = config.home.homeDirectory;
  defaultVaultPath = if pkgs.stdenv.hostPlatform.isDarwin then "${homeDir}/soulwaxx_brain" else null;
  properties = pkgs.writeText "obsidian-properties.json" (
    builtins.toJSON {
      inherit (cfg) vaultPath;
      features = {
        guard = true;
        toc = true;
        # Deprecated: Obsidian Git exclusively owns commits and sync.
        autoCommit = false;
        retrievalRefresh = true;
      };
    }
  );
in
{
  imports = [
    (lib.mkAliasOptionModule
      [
        "claudeObsidian"
        "vaultPath"
      ]
      [
        "dotfiles"
        "claude"
        "obsidian"
        "vaultPath"
      ]
    )
  ];

  options.dotfiles.claude.obsidian = {
    vaultPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = defaultVaultPath;
      description = ''
        Absolute path to the Obsidian vault. Defaults to the shared vault on
        macOS hosts and null on Linux. Used to initialize the standalone
        package's editable properties file and to select the brain shell vault.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Create a user-editable property file only once; package upgrades and
      # switches must not overwrite local feature selections.
      home.activation.obsidianProperties = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ ! -e "$HOME/.config/obsidian-second-brain/properties.json" ]]; then
          run mkdir -p "$HOME/.config/obsidian-second-brain"
          run install -m 644 ${properties} "$HOME/.config/obsidian-second-brain/properties.json"
        fi
      '';
      # The wiki skill's okf_mw middleware shells out to `python3`.
      # Provisioned by the single Python interpreter with PyYAML in shared.nix;
      # not declared here to avoid a home.packages conflict.
      #
      # This coexists with settings.json `disableSkillShellExecution: true`: that
      # flag only suppresses unaudited inline shell interpolation (!`...` and
      # ```! blocks) during skill/command preprocessing. The skills here invoke
      # their scripts as explicit `python3 ...` Bash-tool calls, which run
      # through the normal permission-audited tool path and are unaffected — so
      # provisioning the interpreter and keeping the gate are not in tension.
    }

    # Obsidian ships its own `obsidian-cli` inside the app bundle; the vault's
    # transport detection and any agent that shells out to `obsidian` expect it
    # on PATH. Link it into ~/.local/bin (already on PATH, non-Nix-managed like
    # the uv/claude symlinks that live there) instead of the hand-made symlink
    # in Homebrew's prefix, so it is reproducible. macOS only; the Obsidian cask
    # is declared in modules/homebrew-packages.nix. Best effort: warn, never
    # fail, if the app is absent.
    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      # Reuse pi's managed npm package; its stable path follows package updates
      # without installing a second copy or pointing at a versioned Claude cache.
      home.file.".local/bin/obsidian-second-brain" = {
        source = pkgs.writeShellScript "obsidian-second-brain" ''
          exec ${pkgs.nodejs_24}/bin/node \
            "$HOME/.pi/agent/npm/node_modules/@soulwaxx/obsidian-second-brain/scripts/obsidian-second-brain.mjs" "$@"
        '';
        executable = true;
      };

      home.activation.obsidianCliLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        obsidianCli="/Applications/Obsidian.app/Contents/MacOS/obsidian-cli"
        if [[ -x "$obsidianCli" ]]; then
          run mkdir -p "$HOME/.local/bin"
          # The wiki skill's transport detection invokes "obsidian-cli";
          # link under that exact name (the bundle's own binary name). Keep the
          # legacy "obsidian" name too so anything calling that still resolves.
          run ln -sf "$obsidianCli" "$HOME/.local/bin/obsidian-cli"
          run ln -sf "$obsidianCli" "$HOME/.local/bin/obsidian"
          verboseEcho "obsidian-cli linked into ~/.local/bin (obsidian-cli + obsidian)"
        else
          echo "WARN: Obsidian.app not found at $obsidianCli; skipping obsidian-cli PATH link." >&2
        fi
      '';
    })

    (lib.mkIf (cfg.vaultPath != null) {
      # Optional vault shell; Claude and pi can use the configured wiki from
      # any cwd. Obsidian Git exclusively owns commits, pulls, and pushes.
      programs.zsh.initContent = ''
        brain() {
          (
            cd ${lib.escapeShellArg cfg.vaultPath} || exit 1
            zsh -i
          )
        }
      '';

      home.activation.claudeObsidianVaultCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ ! -d ${lib.escapeShellArg cfg.vaultPath} ]]; then
          echo "WARN: brain vault path '${cfg.vaultPath}' does not exist on this host." >&2
        fi
      '';
    })
  ];
}
