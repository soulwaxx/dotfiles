{
  pkgs,
  lib,
  config,
  hostname,
  ...
}:
let
  theme = config.dotfiles.theme.current;
  # Pin nh's flake refs to this host so bare `nh <platform> switch` resolves the
  # right config even when the machine hostname differs from the flake output.
  nhFlakeRef = "${config.dotfiles.path}#${hostname}";
  verifyNixStore = pkgs.writeShellScript "verify-nix-store" ''
    if ! ${pkgs.nix}/bin/nix-store --verify --check-contents; then
      echo "Nix store content verification failed; repair the reported paths before cleanup." >&2
      exit 1
    fi
  '';
in
{
  config = {
    news.display = "silent";

    # Colored man pages through bat, so they follow the same syntax theme as
    # `cat` and delta instead of a separate LESS_TERMCAP_* escape-code table.
    # `col -bx` strips the overstrike backspace sequences roff emits for
    # bold/underline, which bat would otherwise render literally; MANROFFOPT=-c
    # stops groff re-adding them via SGR sequences bat cannot parse.
    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat --language man --plain'";
      MANROFFOPT = "-c";
    };

    home.packages = [
      # Sole python3 provider on Linux (not in linux/packages.nix) and preferred
      # over Homebrew's transitive python on darwin. The wiki skill's okf_mw
      # validator and index sync import PyYAML; use the same interpreter for the wiki hooks
      # and middleware that the Obsidian lifecycle check uses.
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.coreutils
      pkgs.bash
      pkgs.gnutar
      pkgs.gzip
    ];

    systemd.user.services.nh-clean.Service = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      ExecStartPre = [ "${verifyNixStore}" ];
      ExecStartPost = [ "${verifyNixStore}" ];
    };

    programs = {
      bat = {
        enable = true;
        config = {
          style = "plain";
          theme = theme.bat;
        };
      };

      direnv = {
        enable = true;
        config.global.hide_env_diff = true;
        nix-direnv.enable = true; # faster nix shell loading
      };

      lazygit = {
        enable = true;
      };

      nh = {
        enable = true;
        flake = nhFlakeRef;
        homeFlake = nhFlakeRef;
        darwinFlake = nhFlakeRef;
        # Scheduled GC runs via a systemd user timer, so it is Linux-only. macOS
        # keeps the manual nix-clean-* aliases (see modules/zsh/aliases.nix).
        clean = {
          enable = pkgs.stdenv.hostPlatform.isLinux;
          extraArgs = "--keep 5 --keep-since 30d";
        };
      };
    };
  };
}
