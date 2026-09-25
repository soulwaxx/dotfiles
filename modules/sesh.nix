{
  programs.sesh = {
    enable = true;
    enableAlias = false;
    enableTmuxIntegration = false;
    icons = true;
    settings = {
      sort_order = [
        "tmux"
        "config"
        "zoxide"
      ];

      default_session.preview_command = "eza --all --git --icons --color=always {}";

      tui = {
        prompt = "⚡ ";
        placeholder = "Filter sessions... ";
        show_icons = true;
      };
    };
  };
}
