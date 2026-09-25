{
  pkgs,
  config,
  ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  ezaBase = config.dotfiles.eza.baseFlags;
  ezaLong = "-lagh --header --git --smart-group --time-style=relative --color-scale=age ${ezaBase}";
  dotfilesPathExpr = config.dotfiles.pathShellExpr;

  # Package-manager download caches, backing the cache-clean alias below.
  # Everything dropped here is re-fetchable, so this is safe to run at any
  # time; the only cost is a colder first install afterwards. Kept out of the
  # nix-clean-* family on purpose — those manage store generations and
  # rollback, this only drops caches.
  #
  # `;` rather than `&&`: a tool missing on one host (npm on a headless Linux
  # box, brew anywhere but darwin) must not skip the remaining cleanups.
  #
  # `uv cache prune`, not `uv cache clean`: uv hardlinks wheels out of the
  # cache into venvs and any ad-hoc `uv tool install` targets, and prune drops
  # only dangling entries while honouring the in-use checks that clean's
  # --force bypasses.
  #
  # brew is darwin-only, and `brew cleanup --prune=all` is additive to
  # modules/darwin/homebrew.nix's onActivation.cleanup = "zap": zap uninstalls
  # formulae absent from the Brewfile, it never prunes ~/Library/Caches/Homebrew.
  cacheClean =
    "npm cache clean --force; uv cache prune" + (if isDarwin then "; brew cleanup --prune=all" else "");
in
{
  programs.zsh.shellAliases = {
    # Core
    cp = "cp -i";
    mv = "mv -i";
    rm = "rm -i";
    mkdir = "mkdir -p";

    # zsh EXTENDED_GLOB treats `#` as a glob operator, so unquoted flake refs
    # like `.#check` or `nixpkgs#hello` fail with "zsh: no matches found".
    # noglob disables filename generation for every nix invocation, fixing the
    # cfg-* aliases and interactive `nix run .#…` without quoting each ref.
    nix = "noglob nix";

    # Listing
    ls = "eza ${ezaBase}";
    ll = "eza ${ezaLong}";
    la = "eza -a ${ezaBase}";
    l = "eza -a ${ezaBase}";
    lt = "eza ${ezaLong} --sort=modified";
    tree = "eza --tree --level=3 ${ezaBase}";

    # System info
    df = "df -h";
    du = "du -h";
    checkmyip = "curl -s checkip.amazonaws.com";
    ports = "lsof -i -P -n | grep LISTEN";

    # Grep
    grep = "grep --color=auto";
    fgrep = "grep -F --color=auto";
    egrep = "grep -E --color=auto";

    # Config
    reload = "source \"\${ZDOTDIR:-$HOME}/.zshrc\"";
    zshconfig = "\"$EDITOR\" \"${dotfilesPathExpr}/modules/zsh/default.nix\"";
    dotfiles = "cd \"${dotfilesPathExpr}\"";

    # Navigation — short jump alias for zoxide's `z` (defined by zoxide init).
    j = "z";

    # Python
    venv = "python3 -m venv";

    # Git
    gs = "git status";
    ga = "git add";
    gaa = "git add .";
    gc = "git commit";
    gcm = "git commit -m";
    gp = "git push";
    gl = "git pull";
    gd = "git diff";
    gb = "git branch";
    gba = "git branch -a";
    gco = "git checkout";
    gcb = "git checkout -b";
    glog = "git log --oneline --graph --decorate --all";
    gclean = "git for-each-ref --merged HEAD --format='%(refname:short)' refs/heads | grep -v -E '^(main|master)$' | grep -vFx \"\$(git symbolic-ref --short HEAD 2>/dev/null)\" | xargs -n 1 git branch -d";

    # Better defaults
    cat = "bat";
    # Markdown preview: renders formatted markdown in the terminal via glow.
    # Pass -p for plain (no line numbers) or omit for the default pager.
    mdview = "glow";
    top = "btop";

    # Tmux
    tls = "tmux list-sessions";

    # Docker
    d = "docker";
    dc = "docker compose";
    dps = "docker ps";
    dpsa = "docker ps -a";
    di = "docker images";
    drm = "docker rm";
    drmi = "docker rmi";
    dprune = "docker-clean";

    # One-time: create a multi-platform buildx builder (amd64 via Rosetta + arm64).
    buildx-init = "docker buildx inspect multiarch >/dev/null 2>&1 || docker buildx create --name multiarch --driver docker-container --bootstrap --use";

    # Kubernetes
    k = "kubectl";
    kgp = "kubectl get pods";
    kgs = "kubectl get services";
    kgd = "kubectl get deployments";

    # Dotfiles desired state
    cfg-check = "(cd \"${dotfilesPathExpr}\" && nix run .#check)";
    cfg-fmt = "(cd \"${dotfilesPathExpr}\" && nix run .#fmt)";
    cfg-update = "(cd \"${dotfilesPathExpr}\" && nix flake update)";
    cfg-realign = "cfg-check && nix-switch";
    nix-profile-add = "nix profile add";
    hm-news = "home-manager news";

    # Nix — store cleanup
    # All variants keep the current + booted generation; never `nix-collect-garbage -d`.
    nix-health = "nix-store --verify --check-contents";
    nix-gc = "nix-health && nix store gc && nix-health";
    nix-gc-dry = "nix store gc --dry-run";
    nix-roots = "nix-store --gc --print-roots | grep -vE '^(/proc|\\{memory)'";
    nix-store-du = "du -sh /nix/store";
    nix-history = "nix profile history --profile ~/.nix-profile";
    # User-profile cleanup: prune generations >30d in user profiles (HM,
    # nix-profile), GC the store, then hard-link duplicates.
    nix-clean-old = "nix-health && nix-collect-garbage --delete-older-than 30d && nix store gc && nix store optimise && nix-health";

    # Caches — see cacheClean above.
    cache-clean = cacheClean;

    # Kept out of cache-clean because it is not a pure cache drop: -a also
    # discards the build cache, which costs real time on the next build. -f is
    # required because prune prompts interactively and would block a chain.
    # Runs against whichever context is active.
    docker-clean = "docker system prune -af";

    # Everything, in one go. Run in a subshell so every stage is attempted and
    # failure is retained even when a later stage succeeds. `docker system
    # prune` notably exits non-zero when no daemon is reachable. nix-clean-all
    # runs first because on darwin it is the only stage needing sudo, so the
    # password prompt lands immediately instead of a minute in. Still
    # generation-safe: nix-clean-all keeps the current and booted generations
    # (never `nix-collect-garbage -d`), so rollback via nix-rollback survives
    # this.
    system-clean = "(failed=0; nix-clean-all || failed=1; cache-clean || failed=1; docker-clean || failed=1; exit $failed)";
  }
  // (
    if isDarwin then
      {
        flush_dns = "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";
        showfiles = "defaults write com.apple.finder AppleShowAllFiles YES && killall Finder";
        hidefiles = "defaults write com.apple.finder AppleShowAllFiles NO && killall Finder";
        # AeroSpace's startup hook launches borders; borders remains independent
        # after AeroSpace exits, so stop both processes explicitly.
        aerospace-on = "open -a AeroSpace";
        aerospace-off = "pkill -x AeroSpace; pkill -x borders";
        # brew upgrade is intentionally separate: it can break dylib links if transitive
        # deps get new sonames; run this explicitly, then darwin-rebuild if needed.
        # Ghostty needs --greedy (auto_updates cask, skipped by plain upgrade;
        # its in-app updater is disabled in modules/ghostty.nix).
        brew-upgrade = "brew update && brew upgrade && brew upgrade --greedy ghostty";
        cfg-upgrade = "cfg-update && brew-upgrade && nix-switch";
        # Roll back to the previous darwin-rebuild generation
        nix-rollback = "sudo darwin-rebuild switch --rollback";
        # List darwin system generations (newest at top, current marked)
        nix-generations = "darwin-rebuild --list-generations";
        # System-profile cleanup: deletes system generations older than 30d.
        # Needs sudo because /nix/var/nix/profiles/system is root-owned.
        # Still keeps the booted+current generations.
        nix-clean-system = "sudo nix-collect-garbage --delete-older-than 30d && nix-health";
        # Full safe sweep: system + user generations >30d, GC store, optimise.
        # Same as the weekly launchd job but on-demand. Run `nix-gc-dry` first.
        # sudo nix-collect-garbage already covers both system and user profiles
        # via the daemon, so skip the redundant user-level nix-collect-garbage
        # that nix-clean-old would repeat and jump straight to store GC + optimise.
        nix-clean-all = "nix-clean-system && nix store gc && nix store optimise && nix-health";
      }
    else
      {
        free = "free -m";
        cfg-upgrade = "cfg-update && nix-switch";
        # List available home-manager generations (use 'home-manager switch --generation N' to roll back)
        nix-generations = "home-manager generations";
        # Linux equivalent of darwin's nix-clean-system: prune the per-user
        # HM profile generations older than 30d, then run shared GC sweep.
        # `home-manager expire-generations` only removes the profile symlinks;
        # the store paths get reclaimed by nix-clean-old below.
        nix-clean-system = "home-manager expire-generations '-30 days' && nix-clean-old && nix-health";
        nix-clean-all = "nix-clean-system";
        linux-realign = "cfg-realign && nix-clean-all";
        linux-upgrade = "cfg-upgrade && nix-clean-all";
      }
  );
}
