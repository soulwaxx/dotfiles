{
  pkgs,
  lib,
  config,
  ...
}:
let
  dotfilesPathExpr = config.dotfiles.pathShellExpr;
  p = config.dotfiles.theme.current.palette;
  prependExistingPathDirs = dirs: ''
    for _path_dir in ${lib.concatStringsSep " " (lib.reverseList dirs)}; do
      [[ -d "$_path_dir" ]] && export PATH="$_path_dir:$PATH"
    done
    unset _path_dir
  '';
  userPath = lib.concatStringsSep ":" (map (dir: "$HOME/${dir}") config.dotfiles.env.userBinDirs);
  nixProfilePath = "$HOME/${config.dotfiles.env.nixProfileBinDir}";
  # dircolors' default database uses the 16 ANSI slots (e.g. di=01;34), not
  # truecolor, so completion entry colors follow Ghostty's active theme like
  # bat/fzf/delta do. Baked at build time to avoid a dircolors fork per shell.
  # Sourced, not inlined via readFile: readFile would make this an
  # import-from-derivation, realised on every eval and never GC-rooted.
  lsColorsFile = pkgs.runCommand "ls-colors.sh" { } ''
    ${pkgs.coreutils}/bin/dircolors -b > $out
  '';
in
{
  imports = [
    ./aliases.nix
  ];

  # Owned here beside its shell init below. Must live in the Nix profile (not
  # Homebrew) so it stays on PATH inside tmux display-popups, where sesh's
  # zoxide source runs without an interactive shell to source brew shellenv.
  home.packages = [
    pkgs.zoxide
    pkgs.zsh-patina
  ];

  # Patina's daemon reads this once at start; `zsh-patina restart` after edits.
  xdg.configFile."zsh-patina/config.toml".text = ''
    [highlighting]
    theme = "${config.dotfiles.theme.current.patina}"
  '';

  # Create writable directories required by declarative tool config without an
  # activation script. npm owns the contents at runtime.
  home.file = {
    ".npm-global/bin/.keep".text = "";
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    autosuggestion.highlight = "fg=${p.comment}";
    syntaxHighlighting.enable = false; # We use zsh-patina, activated below

    history = {
      # atuin manages history — keep a minimal HISTFILE only as fallback
      size = 1000;
      save = 1000;
      ignoreSpace = true;
    };

    # historySubstringSearch disabled — atuin handles up/down arrow history navigation

    sessionVariables = {
      # EDITOR is set by programs.neovim.defaultEditor (modules/neovim.nix).
      LANG = "en_US.UTF-8";
      # Scope the forced UTF-8 to character classification only; LC_ALL would
      # override every locale category and mask per-category preferences.
      LC_CTYPE = "en_US.UTF-8";
      _ZO_EXCLUDE_DIRS = "$HOME:$HOME/.cache/*:$HOME/.local/share/Trash/*:$HOME/.Trash/*:$HOME/Library/Caches/*:/tmp/*";
      # Agent shells can replay incomplete snapshots and trip zoxide's doctor
      # even when the real ~/.zshrc ordering is correct.
      _ZO_DOCTOR = "0";
      _ZO_FZF_OPTS = "--height=60% --layout=reverse --info=inline --border=rounded --preview-window=right,55%,border-left --bind=ctrl-/:toggle-preview --preview '${config.dotfiles.eza.treePreviewCommand} {} 2>/dev/null | head -200'";
      _ZO_MAXAGE = "20000";
      _ZO_RESOLVE_SYMLINKS = "1";
      # npm -g can't write to the read-only Nix store — redirect to a writable prefix
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
      HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
    };

    # Cache strategy borrowed from ez-compinit: zsh's own `Nmh-20` glob
    # qualifier ("exists and modified under 20 hours ago") replaces the
    # date/zstat/uname branching this used to need to read an mtime portably.
    # 20h rather than 24h so the full rebuild lands on the first shell of each
    # day instead of drifting later with every rebuild.
    completionInit = ''
      autoload -Uz compinit
      zmodload zsh/complist
      setopt local_options extended_glob
      _dump_file="''${ZDOTDIR:-$HOME}/.zcompdump"
      # -C skips the function check; only safe while the dump is fresh AND at
      # least as new as the .zshrc that determines fpath.
      if [[ -n ''${_dump_file}(#qNmh-20) && "$_dump_file" -nt "''${ZDOTDIR:-$HOME}/.zshrc" ]]; then
        compinit -C -d "$_dump_file"
      else
        compinit -d "$_dump_file"
        touch "$_dump_file"
      fi
      # Backgrounded (&!) so a cold zcompile never blocks the first prompt. The
      # mkdir is the lock: it is atomic, so concurrent shells cannot interleave
      # writes to the same .zwc.
      {
        if [[ -s "$_dump_file" && ( ! -s "$_dump_file.zwc" || "$_dump_file" -nt "$_dump_file.zwc" ) ]]; then
          if command mkdir "$_dump_file.zwc.lock" 2>/dev/null; then
            zcompile "$_dump_file"
            command rmdir "$_dump_file.zwc.lock" 2>/dev/null
          fi
        fi
      } &!
      unset _dump_file
    '';

    profileExtra = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
      prependExistingPathDirs config.dotfiles.env.darwinPackageBinDirs
    );

    initContent = lib.mkMerge [
      # Early: PATH setup and module_path fix (runs before everything else)
      (lib.mkBefore ''
        # Deduplicate PATH. On darwin the package-dir prepend runs in both
        # profileExtra and here, so a login shell that also sources .zshrc would
        # otherwise carry every entry twice. Dedup keeps the first occurrence,
        # so re-prepending an existing dir still moves it to the front.
        typeset -gU path PATH
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
          prependExistingPathDirs config.dotfiles.env.darwinPackageBinDirs
        )}
        # Re-assert Nix profile after any platform package-manager prepend so Nix
        # python3.withPackages (defusedxml, boto3) stays preferred.
        [[ -d "${nixProfilePath}" ]] && export PATH="${nixProfilePath}:$PATH"
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          # pip install --user lands in ~/Library/Python/X.Y/bin on macOS.
          # Avoid spawning python during every interactive shell startup.
          for _py_user_bin in "$HOME"/Library/Python/*/bin; do
            [[ -d "$_py_user_bin" ]] && export PATH="$_py_user_bin:$PATH"
          done
          unset _py_user_bin
        ''}
        export PATH="${userPath}:$PATH"

      '')

      (lib.mkOrder 600 ''
        # fzf-tab is the UI layer for zsh completions. Load it after compinit
        # and before widget-wrapping plugins such as autosuggestions/F-Sy-H.
        source "${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh"
      '')

      # Normal priority: completion styling, functions, local machine hooks
      ''
        # Shell behaviour — directory stack via `cd -<tab>`, comments in
        # interactive shells, extended globbing, no terminal bell.
        setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
        setopt INTERACTIVE_COMMENTS EXTENDED_GLOB NO_BEEP

        # Color completion candidates (dirs, symlinks, executables, archives) by
        # file type so fzf-tab differentiates them. LS_COLORS rides the terminal's
        # ANSI palette; list-colors feeds it into zsh's completion system.
        source ${lsColorsFile}
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

        # Complete hidden files without typing a leading dot (cat/nvim <tab>).
        # Scoped to completion only so normal `*` globbing (rm/cp/git add) does
        # NOT sweep in dotfiles, unlike a global `setopt GLOB_DOTS`.
        _comp_options+=(globdots)

        # fzf-tab strips escape sequences from group descriptions, so keep the
        # format plain. An empty group-name turns on per-tag grouping for native
        # completers too (carapace sets it per-context for its own candidates).
        zstyle ':completion:*:descriptions' format '-- %d --'
        zstyle ':completion:*' group-name '''
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
        # fzf-tab IS the menu: `menu select` makes zsh grab the
        # unambiguous-prefix path before fzf-tab ever runs.
        zstyle ':completion:*' menu no
        zstyle ':completion:*' special-dirs true
        # Not a zsh default: without this, file completion behaves as if there
        # were a `*` between consecutive slashes.
        zstyle ':completion:*' squeeze-slashes true
        # Ride the terminal's 16-color ANSI palette like programs.fzf does, so the
        # completion menu follows Ghostty's active theme and the background stays
        # transparent. bg+:8 adds a subtle selection tint via the ANSI surface slot.
        zstyle ':fzf-tab:*' fzf-flags --color=16 --color=bg+:8

        # Carapace registers a single _carapace_completer using zsh's generic
        # _describe rather than _files/_path_files, so it never narrows $PREFIX
        # to the unfinished path segment. fzf-tab's default query-string mode
        # ('input') seeds its search box from that $PREFIX, so completing a path
        # like "config/<TAB>" prefills the query with the whole typed path and
        # matches none of the bare-name candidates carapace returns (menu looks
        # empty). fzf-tab keys its context off the command name, not the
        # completer function, so this has to be unscoped.
        zstyle ':fzf-tab:complete:*' query-string 'prefix'

        # Preview directory contents in Tab menus, reusing the same tree command
        # as the zoxide and fzf directory pickers.
        zstyle ':fzf-tab:complete:(cd|z|ls|eza):*' fzf-preview '${config.dotfiles.eza.treePreviewCommand} $realpath 2>/dev/null | head -200'

        # fzf's shell widgets require a real terminal; agent/tool shells can be
        # interactive without a usable ZLE context.
        if [[ -t 0 && -t 1 && $TERM != "dumb" ]]; then
          source <(${pkgs.fzf}/bin/fzf --zsh)
        fi

        # Vi mode — 10 ms timeout so single Esc feels instant
        bindkey -v
        export KEYTIMEOUT=1
        # Preserve Emacs-style line editing convenience keys in insert mode
        bindkey '^A' beginning-of-line
        bindkey '^E' end-of-line
        bindkey '^?' backward-delete-char
        # Cursor shape: block in normal mode, beam in insert mode
        _vi_mode_cursor() {
          case ''${KEYMAP} in
            vicmd)      print -n '\e[1 q' ;;
            viins|main) print -n '\e[5 q' ;;
          esac
          # Repaint the prompt so starship's character module can swap in its
          # vicmd_symbol (N >>>) when entering normal mode.
          zle reset-prompt
        }
        # add-zle-hook-widget registers into a hook chain; `zle -N` on these
        # widget names would replace the dispatcher and silently drop any other
        # plugin's hook (or have its own dropped).
        autoload -Uz add-zle-hook-widget
        add-zle-hook-widget zle-keymap-select _vi_mode_cursor
        _vi_mode_line_init() { print -n '\e[5 q'; }
        add-zle-hook-widget zle-line-init _vi_mode_line_init
        # Reset cursor to beam after each command (TUIs can leave a block cursor)
        _dotfiles_reset_cursor_preexec() { print -n '\e[5 q'; }
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _dotfiles_reset_cursor_preexec

        # Live again now that carapace no longer claims git (CARAPACE_EXCLUDES in
        # modules/carapace.nix): local branches before remotes for git checkout.
        zstyle ':completion:*:*:git-checkout:*' tag-order 'heads remotes'

        # Git workflow functions
        _git_functions="${dotfilesPathExpr}/modules/zsh/git-functions.zsh"
        if [[ -r "$_git_functions" ]]; then
          source "$_git_functions"
        else
          echo "zsh: git-functions.zsh not readable at $_git_functions; git helpers unavailable" >&2
        fi
        unset _git_functions

        # Nvim quick-start functions
        _nvim_functions="${dotfilesPathExpr}/modules/zsh/nvim-functions.zsh"
        if [[ -r "$_nvim_functions" ]]; then
          source "$_nvim_functions"
        else
          echo "zsh: nvim-functions.zsh not readable at $_nvim_functions; nvim helpers unavailable" >&2
        fi
        unset _nvim_functions

        # fzf process picker
        _fzf_functions="${dotfilesPathExpr}/modules/zsh/fzf-functions.zsh"
        if [[ -r "$_fzf_functions" ]]; then
          source "$_fzf_functions"
        else
          echo "zsh: fzf-functions.zsh not readable at $_fzf_functions; fkill unavailable" >&2
        fi
        unset _fzf_functions

        # Copy a whole file to the local machine's clipboard. OSC 52 travels over
        # the terminal connection, so this also works through SSH. Inside tmux,
        # `set-clipboard external` drops OSC 52 from panes; load-buffer -w makes
        # tmux forward it to the outer terminal instead.
        clip() {
          [[ $# -eq 1 && -f $1 && -r $1 ]] || { echo "usage: clip <file>" >&2; return 1; }
          if [[ -n $TMUX ]]; then
            command tmux load-buffer -w "$1"
          else
            printf '\e]52;c;%s\a' "$(base64 < "$1" | tr -d '\n')"
          fi
        }

        # Load secrets (untracked). Guarded so a syntax error in the file reports
        # instead of silently aborting the rest of shell init.
        if [[ -f ~/.secrets ]]; then
          source ~/.secrets || echo "zsh: ~/.secrets failed to load (syntax error?); continuing" >&2
        fi

        # Local machine hooks (untracked, not an override layer).
        if [[ -f ~/.zshrc.local ]]; then
          source ~/.zshrc.local || echo "zsh: ~/.zshrc.local failed to load (syntax error?); continuing" >&2
        fi
      ''
      (lib.mkOrder 1400 ''
        # zsh-patina replaces fast-syntax-highlighting: a shared Rust daemon
        # does the highlighting out of process. Activated near the end as its
        # README requires, so it sees every alias/function defined above and
        # hooks ZLE after the other widget-wrapping plugins.
        #
        # Same TTY guard as fzf above: agent shells are interactive but have no
        # usable ZLE, and activating there would spawn the daemon for a shell
        # that can never render a highlight.
        if [[ -t 0 && -t 1 && $TERM != "dumb" ]]; then
          eval "$(${pkgs.zsh-patina}/bin/zsh-patina activate)"
        fi
      '')
      (lib.mkOrder 1500 ''
        # zoxide must run last so later shell integrations do not override its cd hook.
        eval "$(zoxide init zsh --cmd z)"
      '')
    ];
  };
}
