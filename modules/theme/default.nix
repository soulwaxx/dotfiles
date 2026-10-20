{ lib, ... }:
let
  # Catppuccin Mocha palette (https://github.com/catppuccin/catppuccin).
  # Key names match the official color names; role guidance lives in
  # https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md.
  palette = {
    rosewater = "#f5e0dc";
    flamingo = "#f2cdcd";
    pink = "#f5c2e7";
    mauve = "#cba6f7";
    red = "#f38ba8";
    maroon = "#eba0ac";
    peach = "#fab387";
    yellow = "#f9e2af";
    green = "#a6e3a1";
    teal = "#94e2d5";
    sky = "#89dceb";
    sapphire = "#74c7ec";
    blue = "#89b4fa";
    lavender = "#b4befe";
    text = "#cdd6f4";
    subtext1 = "#bac2de";
    subtext0 = "#a6adc8";
    overlay2 = "#9399b2";
    overlay1 = "#7f849c";
    overlay0 = "#6c7086";
    surface2 = "#585b70";
    surface1 = "#45475a";
    surface0 = "#313244";
    base = "#1e1e2e";
    mantle = "#181825";
    crust = "#11111b";
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
    # Built into bat and delta. Consumed by modules/shared.nix (bat) and
    # modules/git.nix (delta syntax-theme).
    bat = "Catppuccin Mocha";
    # zsh-patina built-in theme for command-line highlighting.
    patina = "catppuccin-mocha";
    # Ghostty ships Catppuccin Mocha as a built-in theme.
    ghostty = "Catppuccin Mocha";
    k9sSkin = "catppuccin-mocha";
    # Official catppuccin/fzf Mocha colors without `bg`, so the terminal
    # background shows through. Shared by fzf and fzf-tab.
    fzfColors =
      "--color="
      + lib.concatStringsSep "," [
        "bg+:${palette.surface0}"
        "spinner:${palette.rosewater}"
        "hl:${palette.red}"
        "fg:${palette.text}"
        "header:${palette.red}"
        "info:${palette.mauve}"
        "pointer:${palette.rosewater}"
        "marker:${palette.lavender}"
        "fg+:${palette.text}"
        "prompt:${palette.mauve}"
        "hl+:${palette.red}"
        "selected-bg:${palette.surface1}"
        "border:${palette.overlay0}"
        "label:${palette.text}"
      ];
    font = {
      regular = "JetBrainsMono Nerd Font";
      mono = "JetBrainsMono Nerd Font Mono";
    };
  };
}
