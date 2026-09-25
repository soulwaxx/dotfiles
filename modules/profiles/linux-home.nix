{
  config,
  pkgs,
  lib,
  nixglPackages,
  ...
}:
{
  imports = [
    ../nix.nix
    ../zed.nix
    ../ghostty.nix
    ../linux/packages.nix
  ];

  programs.home-manager.enable = true;
  xdg.enable = true;
  targets.genericLinux.enable = true;
  targets.genericLinux.nixGL = {
    packages = nixglPackages;
    defaultWrapper = config.dotfiles.linux.nixGLWrapper;
  };

  home.packages = [
    pkgs.docker
    pkgs.docker-compose
  ]
  ++ lib.optionals config.dotfiles.linux.enableDesktop [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.fira-code
    pkgs.nerd-fonts.fira-code
  ];

  # Wrapped in a function: activation entries are concatenated into one
  # `set -eu` script, so a bare `exit 0` on the skip paths below would silently
  # abort every later entry with a success status. The skip paths are the
  # common case (sudo usually needs a password), so this fires routinely.
  home.activation = {
    registerZshShell = lib.mkIf config.dotfiles.linux.enableLoginShellRegistration (
      lib.hm.dag.entryAfter [ "installPackages" ] ''
        _register_zsh_shell() {
          local zsh_path="$HOME/.nix-profile/bin/zsh"
          if [ ! -x "$zsh_path" ]; then
            echo "linux: $zsh_path not executable yet; skipping login shell registration" >&2
            return 0
          fi

          if ! command -v sudo >/dev/null 2>&1 || ! command -v chsh >/dev/null 2>&1; then
            echo "linux: sudo or chsh is unavailable; skipping login shell registration" >&2
            return 0
          fi

          if ! sudo -n true 2>/dev/null; then
            echo "linux: sudo needs a password; skipping login shell registration" >&2
            echo "linux: run: sudo chsh -s $zsh_path $USER" >&2
            return 0
          fi

          if ! grep -qxF "$zsh_path" /etc/shells; then
            echo "$zsh_path" | run sudo tee -a /etc/shells > /dev/null
          fi

          local current_shell="$SHELL"
          if command -v getent >/dev/null 2>&1; then
            current_shell="$(getent passwd "$USER" | cut -d: -f7)"
          fi

          if [ "$current_shell" != "$zsh_path" ]; then
            run sudo chsh -s "$zsh_path" "$USER"
          fi
        }
        _register_zsh_shell
        unset -f _register_zsh_shell
      ''
    );

    # ~/.config/nix/nix.conf (modules/nix.nix) is a *client* config: the daemon
    # discards substituters, trusted-public-keys, keep-outputs, keep-derivations,
    # http-connections and builders-use-substitutes from it unless the invoking
    # user is trusted. bootstrap.sh sets this on fresh installs; this catches
    # hosts installed before that and manual /etc/nix/nix.conf edits.
    warnUntrustedNixUser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _warn_untrusted_nix_user() {
        local nix_bin="${config.nix.package}/bin/nix"
        [ -x "$nix_bin" ] || return 0

        local trusted
        trusted="$("$nix_bin" --extra-experimental-features nix-command config show trusted-users 2>/dev/null)" || return 0

        if printf '%s\n' "$trusted" | tr ' ' '\n' | grep -qxF "$USER"; then
          return 0
        fi

        echo "linux: $USER is not a trusted Nix user; the daemon is ignoring ~/.config/nix/nix.conf" >&2
        echo "linux: run: sudo sh -c 'echo \"trusted-users = root $USER\" >> /etc/nix/nix.conf' && sudo systemctl restart nix-daemon" >&2
      }
      _warn_untrusted_nix_user
      unset -f _warn_untrusted_nix_user
    '';
  };
}
