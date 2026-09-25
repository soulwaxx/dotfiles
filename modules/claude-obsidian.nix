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
        macOS hosts and null on Linux. Set to null to disable claude-obsidian
        shell wiring and vault checks on this host.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Claude's hooks read this at runtime; null disables them on Linux.
      home.file.".claude/obsidian-vault-path".text =
        if cfg.vaultPath == null then "" else "${cfg.vaultPath}\n";
      # The wiki skill's okf_mw middleware (validate.py/guard.py/sync.py, bundled
      # in config/shared/skills/wiki/scripts/okf_mw/) shells out to `python3`.
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
      home.activation.obsidianCliLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        obsidianCli="/Applications/Obsidian.app/Contents/MacOS/obsidian-cli"
        if [[ -x "$obsidianCli" ]]; then
          run mkdir -p "$HOME/.local/bin"
          # The wiki-cli skill's transport detection invokes "obsidian-cli";
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
      # The claude-obsidian plugin (and the pi wiki skill it's symlinked to) are
      # vault-cwd-scoped: hooks and scripts only work when the harness runs inside
      # the vault. `brain` is harness-agnostic: it cd's there, pulls the latest
      # vault commits, drops the user into an interactive shell in the vault (they
      # launch `claude` or `pi` themselves from there), then pushes on exit.
      programs.zsh.initContent = ''
        brain() {
          (
            cd ${lib.escapeShellArg cfg.vaultPath} || exit 1
            git pull --ff-only --quiet || echo 'WARN: vault pull failed (offline or diverged); continuing on local state' >&2
            zsh -i
            git push --quiet || true
          )
        }
      '';

      home.activation.claudeObsidianVaultCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ ! -d ${lib.escapeShellArg cfg.vaultPath} ]]; then
          echo "WARN: dotfiles.claude.obsidian.vaultPath '${cfg.vaultPath}' does not exist on this host; hooks will silently no-op." >&2
        fi
      '';
    })
  ];
}
