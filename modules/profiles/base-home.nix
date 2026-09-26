{ lib, ... }:
let
  nixSwitchModule =
    {
      config,
      lib,
      hostname,
      ...
    }:
    let
      dotfilesPathExpr = config.dotfiles.pathShellExpr;
    in
    {
      programs.zsh.initContent = lib.mkBefore ''
        # Nix - apply this host's configuration.
        nix-switch() {
          local extra_args=()
          [[ -n "''${DOTFILES_DIR:-}" ]] && extra_args+=(--impure)
          nix run "''${extra_args[@]}" "${dotfilesPathExpr}#${hostname}" -- "$@"
        }
        nix-switch-refresh() {
          nix-switch --refresh "$@"
        }
      '';
    };
in
{
  # Single source of truth for Home Manager state version across all hosts.
  home.stateVersion = lib.mkDefault "26.05";

  imports = [
    ../dotfiles.nix
    ../shared.nix
    ../atuin.nix
    ../git.nix
    nixSwitchModule
    ../zsh
    ../fzf.nix
    ../carapace.nix
    ../starship.nix
    ../neovim.nix
    ../tmux.nix
    ../herdr.nix
    ../sesh.nix
    ../k9s.nix
    ../terraform.nix
    ../theme
    ../claude
    ../claude-obsidian.nix
    ../pi.nix
  ];
}
