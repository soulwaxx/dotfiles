{ config, lib, ... }:
let
  theme = config.dotfiles.theme.current;
  p = theme.palette;
  paletteName = lib.replaceStrings [ "-" ] [ "_" ] theme.name;
in
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      "$schema" = "https://starship.rs/config-schema.json";
      palette = paletteName;
      add_newline = false;
      format = "$directory$git_branch$git_status$character";
      right_format = "$aws";
      command_timeout = 500;
      palettes.${paletteName} = p;

      aws = {
        disabled = false;
        symbol = "☁ ";
        style = "orange";
        format = "[$symbol$profile]($style)";
      };

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
        vimcmd_symbol = "[N >>>](bold green)";
      };

      directory = {
        style = "bold purple";
        truncation_length = 3;
        truncate_to_repo = false;
        truncation_symbol = "…/";
        home_symbol = "~";
      };

      git_branch = {
        symbol = "󰘬 "; # nf-md-source_branch
        style = "green";
        format = "[$symbol$branch(:$remote_branch)]($style) ";
      };
      git_status = {
        style = "yellow";
        format = "[$all_status$ahead_behind]($style) ";
      };
    };
  };
}
