{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfilesPath = config.dotfiles.path;
in
{
  # macOS installs the neovim binary via Homebrew (modules/homebrew-packages.nix
  # darwinBrews); Linux has no brew, so Nix owns it. The config symlink and zsh
  # aliases below are cross-platform regardless of binary source.
  programs = {
    neovim = {
      enable = pkgs.stdenv.hostPlatform.isLinux;
      defaultEditor = true; # sets EDITOR=nvim on Linux; macOS handled below
      sideloadInitLua = true;
    };

    zsh = {
      shellAliases = {
        vi = "nvim";
        vim = "nvim";
        v = "nvim .";
      };
    };
  };

  # programs.neovim.defaultEditor only sets EDITOR when the module is enabled, so
  # macOS (brew neovim, module disabled) needs EDITOR set explicitly.
  home.sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin { EDITOR = "nvim"; };

  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/config/nvim";
  };
}
