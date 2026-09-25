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
      # Ride the terminal's 16-color ANSI palette (Ghostty's Catppuccin Mocha theme
      # populates slots 0-15) instead of hardcoded hex, so fzf follows the active
      # terminal theme without a rebuild. This base scheme keeps the background at
      # the terminal default; append e.g. `bg+:8` for a themed selection tint.
      "--color=16"
      # Render in a centered tmux popup when inside tmux; --height is the
      # fallback layout for shells running outside a tmux session.
      "--tmux center,85%,75%"
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
