# Zed editor Nix wiring.
#
# Config (config/zed/settings.json, config/zed/keymap.json) is hand-edited and
# symlinked into place — not Nix-generated. Zed uses the XDG config dir
# (~/.config/zed/) on both macOS and Linux, so the symlink targets are
# platform-uniform.
#
# Binary source by platform:
#   macOS  — Homebrew cask "zed" (modules/homebrew-packages.nix darwinCasks)
#   Linux  — nixpkgs zed-editor (binary name: zeditor), installed below when
#             config.dotfiles.linux.enableDesktop is true
{
  pkgs,
  lib,
  config,
  ...
}:
let
  mkLink = rel: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/${rel}";

  enableLinux = pkgs.stdenv.hostPlatform.isLinux && config.dotfiles.linux.enableDesktop;
in
{
  # isDarwin and isLinux are mutually exclusive; one predicate covers both the
  # unconditional macOS symlink and the enableDesktop-gated Linux symlink.
  home.file = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin || enableLinux) {
    ".config/zed/settings.json".source = mkLink "config/zed/settings.json";
    ".config/zed/keymap.json".source = mkLink "config/zed/keymap.json";
  };

  # nil is the Nix LSP for Zed's Nix extension. Unlike nvim (Mason owns nil),
  # Zed has no built-in installer, so we put nil on PATH via Nix on both
  # platforms. macOS Homebrew has no nil formula, hence Nix here too.
  home.packages =
    lib.optionals (pkgs.stdenv.hostPlatform.isDarwin || enableLinux) [ pkgs.nil ]
    ++ lib.optionals enableLinux [ pkgs.zed-editor ];
}
