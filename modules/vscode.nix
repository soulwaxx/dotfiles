# VS Code is installed via Homebrew on macOS and Nix on desktop Linux hosts.
# Settings mirror Cursor, without its product-specific options.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  enableLinux = pkgs.stdenv.hostPlatform.isLinux && config.dotfiles.linux.enableDesktop;
  settingsPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/Code/User/settings.json"
    else
      "${config.xdg.configHome}/Code/User/settings.json";
in
{
  home.file = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin || enableLinux) {
    "${settingsPath}".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/vscode/settings.json";
  };

  home.packages = lib.optionals enableLinux [ pkgs.vscode ];
}
