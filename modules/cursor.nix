# Cursor editor settings symlink — Darwin work hosts only.
#
# Cursor is installed via the Homebrew cask (workCasks in
# modules/homebrew-packages.nix). This module symlinks the hand-edited settings
# file into place; it is gated on dotfiles.cursor.enable so personal macOS
# hosts (which do not install Cursor) are unaffected.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  enableCursor = pkgs.stdenv.hostPlatform.isDarwin && config.dotfiles.cursor.enable;
  mkLink = rel: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/${rel}";
in
{
  home.file = lib.mkIf enableCursor {
    "Library/Application Support/Cursor/User/settings.json".source =
      mkLink "config/cursor/settings.json";
  };
}
