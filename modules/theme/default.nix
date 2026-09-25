{ lib, ... }:
let
  # Catppuccin Mocha palette (https://github.com/catppuccin/catppuccin).
  # Layering: background < currentline < surface < overlay < foreground.
  palette = {
    background = "#1e1e2e"; # Base
    currentline = "#313244"; # Surface0
    surface = "#45475a"; # Surface1
    overlay = "#585b70"; # Surface2
    overlay1 = "#7f849c"; # Overlay1
    overlay2 = "#9399b2"; # Overlay2
    subtext0 = "#a6adc8"; # Subtext0
    foreground = "#cdd6f4"; # Text
    comment = "#6c7086"; # Overlay0
    cyan = "#89dceb"; # Sky
    teal = "#94e2d5"; # Teal
    blue = "#89b4fa"; # Blue
    lavender = "#b4befe"; # Lavender
    green = "#a6e3a1"; # Green
    orange = "#fab387"; # Peach
    pink = "#f5c2e7"; # Pink
    flamingo = "#f2cdcd"; # Flamingo
    rosewater = "#f5e0dc"; # Rosewater
    purple = "#cba6f7"; # Mauve
    red = "#f38ba8"; # Red
    maroon = "#eba0ac"; # Maroon
    yellow = "#f9e2af"; # Yellow
  };

in
{
  options.dotfiles.theme = {
    current = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Catppuccin Mocha theme metadata.";
    };
  };

  config.dotfiles.theme.current = {
    inherit palette;
    name = "catppuccin-mocha";
    variant = "dark";
    # bat/delta syntax highlighting rides the terminal's 16 ANSI slots via the
    # base16 syntax theme instead of hardcoded truecolor, so it follows the
    # active terminal theme. Consumed by modules/shared.nix (bat) and
    # modules/git.nix (delta syntax-theme).
    bat = "base16";
    # ANSI theme modeled on fast-syntax-highlighting's default palette; rides
    # the terminal's 16 ANSI slots, so it follows Ghostty's Catppuccin colors
    # rather than pinning muted pastel truecolor like catppuccin-mocha.
    patina = "classic";
    # Ghostty ships Catppuccin Mocha as a built-in theme.
    ghostty = "Catppuccin Mocha";
    k9sSkin = "catppuccin-mocha";
    font = {
      regular = "JetBrainsMono Nerd Font";
      mono = "JetBrainsMono Nerd Font Mono";
    };
  };
}
