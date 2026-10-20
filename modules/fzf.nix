{ config, ... }:
{
  programs.fzf = {
    enable = true;
    # HM's auto-integration loads fzf ZLE widgets unconditionally; Claude Code
    # and other agent shells inherit ~/.zshrc but lack a real TTY, which trips
    # the widget installation. zsh/default.nix sources `fzf --zsh` manually
    # with a TTY guard instead.
    enableZshIntegration = false;
    defaultOptions = [
      # Catppuccin Mocha colors from modules/theme/default.nix. zoxide's picker
      # inherits them through FZF_DEFAULT_OPTS.
      config.dotfiles.theme.current.fzfColors
      "--height 40%"
      "--border"
      "--preview '([[ -f {} ]] && (bat --style=numbers --color=always {} || head -20 {})) || ([[ -d {} ]] && eza -lagh ${config.dotfiles.eza.baseFlags} --color=always {}) || echo {}'"
      "--preview-window=right:40%"
    ];
    fileWidget.options = [
      # Ctrl-T selects files into the command line; multi-select plus a direct
      # "open these in $EDITOR and abort" escape hatch covers the common case
      # of browsing to a file and editing it without a second command.
      "--multi"
      "--bind 'ctrl-o:execute(\${EDITOR:-nvim} {+})+abort'"
    ];
    changeDirWidget.options = [
      # Match the zoxide (_ZO_FZF_OPTS) tree preview so both cd-style pickers look the same.
      "--preview '${config.dotfiles.eza.treePreviewCommand} {} 2>/dev/null | head -200'"
    ];
  };
}
