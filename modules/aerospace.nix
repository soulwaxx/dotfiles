# AeroSpace tiling window manager (macOS-only). The binary comes from the
# nikitabobko/tap Homebrew cask (modules/homebrew-packages.nix); this module
# only links the config so it can be edited live, like config/tmux/tmux.conf.
{ config, ... }:
let
  dotfilesPath = config.dotfiles.path;
in
{
  xdg.configFile."aerospace/aerospace.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/config/aerospace/aerospace.toml";
}
