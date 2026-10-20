{ config, ... }:
let
  theme = config.dotfiles.theme.current;
  p = theme.palette;
in
{
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    # Colors follow the official catppuccin/delta Mocha config. The diff body
    # is syntax-highlighted by the bat theme set in modules/theme/default.nix.
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
      hyperlinks = true;
      keep-plus-minus-markers = false;
      line-numbers-left-format = "{nm:>4} ";
      line-numbers-right-format = "{np:>4} ";
      dark = true;
      syntax-theme = theme.bat;
      blame-palette = "${p.base} ${p.mantle} ${p.crust} ${p.surface0} ${p.surface1}";
      commit-decoration-style = "${p.overlay0} bold box ul";
      file-decoration-style = p.overlay0;
      file-style = p.text;
      hunk-header-decoration-style = "${p.overlay0} box ul";
      hunk-header-file-style = "bold";
      hunk-header-line-number-style = "bold ${p.subtext0}";
      hunk-header-style = "file line-number syntax";
      line-numbers-left-style = p.overlay0;
      line-numbers-right-style = p.overlay0;
      line-numbers-zero-style = p.overlay0;
      line-numbers-minus-style = "bold ${p.red}";
      line-numbers-plus-style = "bold ${p.green}";
      # Upstream blends: emph = 35% accent over Base, plain = 20%.
      minus-emph-style = "bold syntax #694559";
      minus-style = "syntax #493447";
      plus-emph-style = "bold syntax #4e6356";
      plus-style = "syntax #394545";
      # Moved-line colors for diff.colorMoved.
      map-styles = "bold purple => syntax #5b4e74, bold blue => syntax #445375, bold cyan => syntax #446170, bold yellow => syntax #6b635b";
      whitespace-error-style = "red reverse";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      push.followTags = true;
      fetch = {
        prune = true;
        pruneTags = true;
        all = true;
      };
      merge.conflictstyle = "zdiff3";
      diff.colorMoved = "default";
      diff.algorithm = "histogram";
      rerere.enabled = true;
      rebase.autosquash = true;
      rebase.autostash = true;
      commit.verbose = true;
      branch.sort = "-committerdate";
      tag.sort = "version:refname";
      column.ui = "auto";
      core.editor = "nvim";
      core.autocrlf = "input";
    };
    ignores = [
      ".DS_Store"
      "__pycache__"
      ".secrets"
      ".claude"
      "CLAUDE.md"
      "SPEC.md"
      "AGENTS.md"
      "PLAN.md"
      ".pi"
    ];
  };
}
