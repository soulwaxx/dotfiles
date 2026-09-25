{ config, ... }:
let
  theme = config.dotfiles.theme.current;
in
{
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    # UI styles use ANSI color names, not hex: delta resolves them against the
    # terminal's 16 palette slots, so colors follow the active terminal theme
    # without a rebuild. `syntax` keeps the diff body syntax-highlighted via the
    # base16 syntax-theme set centrally in modules/theme/default.nix.
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
      hyperlinks = true;
      keep-plus-minus-markers = false;
      line-numbers-left-format = "{nm:>4} ";
      line-numbers-right-format = "{np:>4} ";
      line-numbers-zero-style = "brightblack";
      hunk-header-style = "file line-number syntax";
      minus-style = "syntax";
      minus-emph-style = "syntax bold";
      plus-style = "syntax";
      plus-emph-style = "syntax bold";
      syntax-theme = theme.bat;
      line-numbers-left-style = "brightblack";
      line-numbers-right-style = "brightblack";
      line-numbers-minus-style = "red";
      line-numbers-plus-style = "green";
      commit-decoration-style = "yellow box";
      commit-style = "yellow bold";
      file-decoration-style = "blue ul";
      file-style = "blue bold";
      hunk-header-decoration-style = "blue box";
      hunk-header-file-style = "blue bold";
      hunk-header-line-number-style = "yellow bold";
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
