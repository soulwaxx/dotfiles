{
  pkgs,
  lib,
  config,
  ...
}:
let
  enableGhostty = pkgs.stdenv.hostPlatform.isDarwin || config.dotfiles.linux.enableDesktop;
  ghosttyPackage =
    if pkgs.stdenv.hostPlatform.isDarwin then null else config.lib.nixGL.wrap pkgs.ghostty;
in
{
  programs.ghostty = {
    enable = enableGhostty;
    # Darwin uses the Homebrew cask for the GUI app. Linux uses the Nix package.
    package = ghosttyPackage;
    enableZshIntegration = true;
    installBatSyntax = !pkgs.stdenv.hostPlatform.isDarwin;

    settings = {
      theme = config.dotfiles.theme.current.ghostty;

      command =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "direct:/opt/homebrew/bin/herdr"
        else
          "direct:${pkgs.herdr}/bin/herdr";

      font-family = config.dotfiles.theme.current.font.mono;
      # font-size is in points. Ghostty's point->pixel baseline is 72 DPI on
      # macOS but 96 DPI on Linux/GTK, so an identical point size renders ~33%
      # larger on Linux. Scale the Linux value by 72/96 to match macOS visually.
      font-size = if pkgs.stdenv.hostPlatform.isDarwin then 13 else 9.75;
      font-thicken = true;
      # Adds 8% to the font's natural cell height and vertically centers the
      # glyph, giving airier line spacing that reads as less visually noisy.
      adjust-cell-height = "8%";

      cursor-style = "bar";
      cursor-style-blink = true;
      mouse-hide-while-typing = true;

      window-decoration = "auto";
      window-theme = "auto";
      confirm-close-surface = false;

      window-padding-x = 10;
      window-padding-y = 8;
      window-padding-balance = true;

      shell-integration = "detect";
      shell-integration-features = "true";

      keybind =
        if pkgs.stdenv.hostPlatform.isDarwin then
          [
            "cmd+t=new_tab"
            "cmd+n=new_window"
            "cmd+shift+r=reload_config"
            # Forward cmd+w as CSI-u (super+w) through tmux instead of closing
            # the surface, so Neovim can decode it as <D-w> and close a buffer.
            "cmd+w=text:\\x1b[119;9u"
          ]
        else
          [
            "ctrl+shift+t=new_tab"
            "ctrl+shift+n=new_window"
            "ctrl+shift+r=reload_config"
          ];
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      macos-titlebar-style = "transparent";
      macos-option-as-alt = "left";
      bell-features = "system";
      # Sparkle in-app updates off: Ghostty otherwise upgrades itself outside
      # the declarative cycle (its cask is auto_updates, so plain `brew
      # upgrade` skips it and brew's view drifts from reality). brew-upgrade
      # runs `brew upgrade --greedy ghostty` instead, so the binary stays
      # owned by cfg-upgrade.
      auto-update = "off";
    };
  };

  xdg.dataFile."applications/com.mitchellh.ghostty.desktop" =
    lib.mkIf (enableGhostty && pkgs.stdenv.hostPlatform.isLinux)
      {
        text = ''
          [Desktop Entry]
          Version=1.0
          Name=Ghostty
          GenericName=Terminal Emulator
          Type=Application
          Comment=A terminal emulator
          TryExec=${ghosttyPackage}/bin/ghostty
          Exec=${ghosttyPackage}/bin/ghostty --gtk-single-instance=true
          Icon=com.mitchellh.ghostty
          Categories=System;TerminalEmulator;
          Keywords=terminal;tty;pty;
          StartupNotify=true
          StartupWMClass=com.mitchellh.ghostty
          Terminal=false
          Actions=new-window;
          X-GNOME-UsesNotifications=true
          X-TerminalArgExec=-e
          X-TerminalArgTitle=--title=
          X-TerminalArgAppId=--class=
          X-TerminalArgDir=--working-directory=
          X-TerminalArgHold=--wait-after-command
          X-KDE-Shortcuts=Ctrl+Alt+T

          [Desktop Action new-window]
          Name=New Window
          Exec=${ghosttyPackage}/bin/ghostty --gtk-single-instance=true
        '';
      };
}
