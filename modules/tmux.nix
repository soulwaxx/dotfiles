{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.libtmux ]);
  tpm = pkgs.fetchFromGitHub {
    owner = "tmux-plugins";
    repo = "tpm";
    rev = "e261deb1b47614eed3400089ce7197dc68acc4eb";
    hash = "sha256-oRKUZNyJYQXlkeQfbEYiltUEBpvdwn2SoEBWHVUNmrA=";
  };
  runtimePath = lib.concatStringsSep ":" (
    [
      (lib.makeBinPath (
        [
          python
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
    ]
  );
  refresh = pkgs.writeShellScriptBin "tmux-window-name-refresh" ''
    [[ -n "''${TMUX:-}" ]] || exit 0
    script="${config.xdg.configHome}/tmux/plugins/tmux-window-name/scripts/rename_session_windows.py"
    [[ -f "$script" ]] || exit 0
    # preexec fires before the foreground process exists; give it time to start.
    if [[ "''${1:-}" == --delay ]]; then
      ${pkgs.coreutils}/bin/sleep 0.1
    fi
    exec ${python}/bin/python3 "$script"
  '';
  reconcile = pkgs.writeShellApplication {
    name = "tmux-reconcile-plugins";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
    ];
    text = builtins.readFile ../config/tmux/reconcile-plugins.sh;
  };
in
{
  # The URL plugin expects xre in its checkout; activation links this Nix build
  # there rather than allowing a first-use curl | bash installer.
  home.packages = [
    refresh
    pkgs.xre
  ];

  home.activation.tmuxPlugins = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${reconcile}/bin/tmux-reconcile-plugins \
      ${
        if pkgs.stdenv.hostPlatform.isDarwin then "/opt/homebrew/bin/tmux" else "${pkgs.tmux}/bin/tmux"
      } \
      ${tpm} \
      "${config.xdg.configHome}/tmux/dotfiles.conf" \
      "${config.xdg.configHome}/tmux/plugins" \
      ${pkgs.xre}/bin/xre
  '';

  xdg.configFile."tmux/dotfiles.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/tmux/tmux.conf";

  xdg.configFile."sesh/sesh.toml".source = (pkgs.formats.toml { }).generate "sesh.toml" {
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

  programs.tmux = {
    enable = true;
    package = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.tmux;
    prefix = "C-a";
    terminal = "tmux-256color";
    shell = "${pkgs.zsh}/bin/zsh";
    baseIndex = 1;
    keyMode = "vi";
    mouse = true;
    focusEvents = true;
    historyLimit = 100000;
    extraConfig = ''
      # GUI-launched servers do not inherit the interactive shell's PATH.
      # Python/libtmux are needed by TPM's naming hooks, not a user pip install.
      set-environment -g PATH "${runtimePath}:$PATH"
      set-environment -g TMUX_PLUGIN_MANAGER_PATH "${config.xdg.configHome}/tmux/plugins/"
      source-file "${config.xdg.configHome}/tmux/dotfiles.conf"
      run-shell "${tpm}/tpm"
      set-hook -g 'after-select-pane[8922]' 'run-shell -b "${refresh}/bin/tmux-window-name-refresh"'
      set-hook -g 'after-new-window[8922]' 'run-shell -b "${refresh}/bin/tmux-window-name-refresh"'
      set-hook -g 'after-split-window[8922]' 'run-shell -b "${refresh}/bin/tmux-window-name-refresh"'
      set-hook -g 'client-session-changed[8922]' 'run-shell -b "${refresh}/bin/tmux-window-name-refresh"'
    '';
  };

  programs.zsh.initContent = lib.mkAfter ''
    # Bare tmux reconnects to the same workspace as Ghostty.
    unalias tmux 2>/dev/null
    tmux() {
      if [[ $# -eq 0 ]]; then
        exec command tmux new-session -A -s main
      else
        command tmux "$@"
      fi
    }

    # Refresh directory/program labels without a polling daemon. Manual window
    # names are respected by tmux-window-name's own enable/disable tracking.
    _dotfiles_tmux_name_refresh() {
      [[ -n "''${TMUX:-}" ]] || return 0
      ${refresh}/bin/tmux-window-name-refresh >/dev/null 2>&1 &!
    }
    _dotfiles_tmux_name_preexec() {
      [[ -n "''${TMUX:-}" ]] || return 0
      ${refresh}/bin/tmux-window-name-refresh --delay >/dev/null 2>&1 &!
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook chpwd _dotfiles_tmux_name_refresh
    add-zsh-hook precmd _dotfiles_tmux_name_refresh
    add-zsh-hook preexec _dotfiles_tmux_name_preexec
  '';
}
