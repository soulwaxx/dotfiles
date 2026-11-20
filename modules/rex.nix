# Rex (terminal emulator + multiplexer), on trial as a replacement for
# Ghostty + Herdr. Rex.app is installed manually: there is no Homebrew cask,
# so it updates itself through Sparkle. Revisit ownership if a cask appears
# or the trial ends; remove ghostty.nix/herdr.nix only after it succeeds.
#
# Key bindings: config/rex/init.lua. App settings live in macOS defaults and
# are applied by hand with config/rex/apply-settings.sh. The Claude Code
# session hook is declared in config/claude/settings.json; the skill lives in
# config/shared/skills/rex.
{ config, ... }:
{
  xdg.configFile."rex/init.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/rex/init.lua";

  # Rex exports REX_BIN_DIR to its terminals but does not put the bundled
  # `rex` CLI on PATH. Append it so agents and the Claude hook can call `rex`.
  programs.zsh.initContent = ''
    [[ -n "''${REX_BIN_DIR-}" && -d "$REX_BIN_DIR" ]] && path+=("$REX_BIN_DIR")
  '';
}
