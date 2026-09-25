let
  atuinConfig = {
    command_chaining = true;
    dialect = "uk";
    enter_accept = true;
    inline_height = 24;
    inline_height_shell_up_key_binding = 16;
    keymap_mode = "auto";
    max_preview_height = 8;
    search_mode = "daemon-fuzzy";
    search_mode_shell_up_key_binding = "prefix";
    style = "compact";
    workspaces = true;
    filter_mode = "workspace";

    daemon = {
      enabled = true;
      autostart = true;
    };

    preview.strategy = "static";

    # Nix owns the binary — no self-update to advertise.
    update_check = false;

    tmux = {
      enabled = true;
      width = "80%";
      height = "60%";
    };

    ui.columns = [
      "exit"
      "duration"
      "directory"
      "command"
    ];
  };
in
{
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = atuinConfig;
  };
}
