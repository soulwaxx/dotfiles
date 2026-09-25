{ pkgs, lib, ... }:
{
  # carapace is a multi-shell, spec-based argument completer. It supplies rich
  # completions for hundreds of CLIs from a single binary. Its bridge to zsh's
  # native completers only fires when carapace returns zero completions, which
  # rarely happens because it auto-generates --help/--version flags for every
  # command it knows; CARAPACE_EXCLUDES below is the real fallback mechanism.
  home.packages = [ pkgs.carapace ];

  programs.zsh = {
    sessionVariables = {
      # Fall back to existing zsh/bash completers for commands carapace has no
      # spec for. 'zsh' first keeps Nix- and plugin-provided _completers working
      # when carapace declines a command. fish and inshellisense are not
      # installed on any host here, so they are not listed.
      CARAPACE_BRIDGES = "zsh,bash";

      # carapace registers one _carapace_completer for ~2200 commands, which
      # shadows the native zsh completers even where those are far richer
      # (_git's refs/stashes, _kubectl, _nix) or where carapace only emits
      # auto-generated --help/--version flags and no file arguments (cat, grep,
      # rm). CARAPACE_EXCLUDES keeps carapace from claiming these at all, so
      # zsh's own completer stays registered — replaces a hand-rolled
      # compdef -d loop that also broke commands with no native completer.
      CARAPACE_EXCLUDES = lib.concatStringsSep "," [
        # native zsh completers are better than carapace's specs
        "git"
        "kubectl"
        "nix"
        "docker"
        "ssh"
        # POSIX file-consuming commands: carapace's flag-only output breaks
        # `cat docs/<tab>`, and the bridge does not fire because those
        # auto-generated flags count as a non-empty result
        "cat"
        "bat"
        "ls"
        "grep"
        "head"
        "tail"
        "less"
        "more"
        "cp"
        "mv"
        "rm"
        "mkdir"
        "rmdir"
        "touch"
        "chmod"
        "chown"
        "file"
        "vim"
        "nvim"
      ];
    };

    # Source carapace after compinit (completionInit) but BEFORE fzf-tab, which
    # loads at mkOrder 600. fzf-tab must be the last plugin that emits compdef,
    # so every carapace completer has to be registered ahead of it; otherwise
    # fzf-tab does not wrap carapace's menus. Normal-priority completion zstyles
    # in zsh/default.nix run afterwards and still apply to carapace candidates.
    initContent = lib.mkOrder 590 ''
      # fzf's/agent shells can source ~/.zshrc without a usable ZLE context; the
      # completer itself is inert until a real completion is requested, so this
      # is safe to source unconditionally.
      source <(${pkgs.carapace}/bin/carapace _carapace zsh)
    '';
  };
}
