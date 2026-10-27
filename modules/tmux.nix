{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtimePath = lib.concatStringsSep ":" (
    [
      (lib.makeBinPath (
        [
          pkgs.bash
          pkgs.coreutils
          pkgs.git
          pkgs.gawk
          pkgs.gnused
          pkgs.gnugrep
          pkgs.fzf
          pkgs.findutils
          pkgs.ncurses
          pkgs.zoxide
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.procps
          pkgs.sesh
        ]
      ))
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin config.dotfiles.env.darwinPackageBinDirs
    ++ [
      (
        if pkgs.stdenv.hostPlatform.isDarwin then
          "/etc/profiles/per-user/${config.home.username}/bin"
        else
          "${config.home.homeDirectory}/${config.dotfiles.env.nixProfileBinDir}"
      )
    ]
    ++ map (dir: "${config.home.homeDirectory}/${dir}") config.dotfiles.env.userBinDirs
    ++ [
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ]
  );
  bootstrap = pkgs.writeShellApplication {
    name = "tmux-bootstrap-plugins";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
    ];
    text = builtins.readFile ../config/tmux/bootstrap-plugins.sh;
  };
in
{
  home = {
    # The URL plugin expects xre in its checkout; activation links this Nix build
    # there rather than allowing a first-use curl | bash installer.
    packages = [ pkgs.xre ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.tmux ];

    # Preserve Home Manager's secureSocket default on Linux without its wrapper.
    sessionVariables = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      TMUX_TMPDIR = ''''${XDG_RUNTIME_DIR:-"/run/user/$(id -u)"}'';
    };

    activation.bootstrapTpm = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${bootstrap}/bin/tmux-bootstrap-plugins \
        ${pkgs.tmux}/bin/tmux \
        "${config.xdg.configHome}/tmux/plugins" \
        ${pkgs.xre}/bin/xre
    '';
  };

  xdg.configFile = {
    "tmux/tmux.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/tmux/tmux.conf";

    "tmux/environment.conf".text = ''
      # Machine-specific paths; replace PATH so repeated reloads remain stable.
      set-environment -g PATH "${runtimePath}"
      set-environment -g TMUX_PLUGIN_MANAGER_PATH "${config.xdg.configHome}/tmux/plugins/"
      set -g default-shell "${pkgs.zsh}/bin/zsh"
    '';

    "sesh/sesh.toml".source = (pkgs.formats.toml { }).generate "sesh.toml" {
      sort_order = [
        "tmux"
        "config"
        "zoxide"
      ];
      default_session.preview_command = "eza --all --git --icons --color=always {}";
      tui = {
        prompt = "⚡ ";
        placeholder = "Filter sessions... ";
        show_icons = true;
      };
    };
  };

  programs.zsh.initContent = lib.mkAfter ''
    # Bare tmux reconnects to home; Ghostty creates independent sessions.
    unalias tmux 2>/dev/null
    tmux() {
      if [[ $# -eq 0 ]]; then
        exec command tmux new-session -A -s home
      else
        command tmux "$@"
      fi
    }
  '';
}
