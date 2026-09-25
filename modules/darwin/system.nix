{
  pkgs,
  lib,
  nixpkgs,
  username,
  ...
}:
let
  caches = import ../lib/nix-substituters.nix;
  verifyNixStore = pkgs.writeShellScript "verify-nix-store" ''
    if ! ${pkgs.nix}/bin/nix-store --verify --check-contents; then
      echo "Nix store content verification failed; repair the reported paths before cleanup." >&2
      exit 1
    fi
  '';
  verifiedNixGc = pkgs.writeShellScript "verified-nix-gc" ''
    set -eu
    ${verifyNixStore}
    ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 30d
    ${verifyNixStore}
  '';
  verifiedNixOptimise = pkgs.writeShellScript "verified-nix-optimise" ''
    set -eu
    ${verifyNixStore}
    ${pkgs.nix}/bin/nix-store --optimise
    ${verifyNixStore}
  '';
in
{
  imports = [
    ./homebrew.nix
  ];

  # Upstream Nix: nix-darwin manages the daemon, /etc/nix/nix.conf, and GC.
  nix = {
    enable = true;
    settings = {
      # upstream does not enable flakes by default; the repo's workflow needs them
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # nix-darwin's module default already supplies "root", so only add admins.
      trusted-users = [ "@admin" ];

      # Upstream Nix ships only cache.nixos.org. Add the nix-community cache
      # used by this repository (see ../lib).
      inherit (caches) substituters;
      trusted-public-keys = caches.trustedPublicKeys;

      # Fetch build deps from the cache instead of copying them over (slow)
      # remote-builder links.
      builders-use-substitutes = true;
      # Keep build outputs and .drvs alive so devshells / repeated builds are
      # not re-fetched or rebuilt after a GC. keep-derivations is already the
      # upstream default; set it here so the intent is co-located.
      keep-outputs = true;
      keep-derivations = true;
      # This repo is always a dirty git checkout; the dirty-tree warning is pure
      # noise on every `nix run .#…`.
      warn-dirty = false;
      # Fall back to building from source when a substituter is missing a path
      # instead of aborting the whole build.
      fallback = true;
      # More parallel narinfo/nar fetches on fast links (upstream default 25).
      http-connections = 50;
    };
    # Pin `nixpkgs#…` shorthand and <nixpkgs> to the flake's locked nixpkgs, so
    # `nix run nixpkgs#hello` resolves instantly and offline instead of hitting
    # the network flake registry.
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs}" ];
    # Keep old system generations bounded without inline store optimisation.
    gc = {
      automatic = true;
      interval = {
        Weekday = 0; # Sunday
        Hour = 3;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };
    # Store dedup runs as a scheduled job only. `nix.settings.auto-optimise-store`
    # is deliberately NOT set: inline optimisation races the daemon and can
    # corrupt the store (NixOS/nix#7273), and nix-darwin now asserts against it
    # (nix-darwin#1252).
    optimise.automatic = true;
  };
  launchd.daemons = {
    nix-gc.command = lib.mkForce "${verifiedNixGc}";
    nix-optimise.command = lib.mkForce "${verifiedNixOptimise}";
  };

  nixpkgs.config.allowUnfree = true;

  security.pam.services.sudo_local.touchIdAuth = true;
  # reattach re-connects to the user bootstrap session so Touch ID works
  # inside tmux / screen.
  security.pam.services.sudo_local.reattach = true;

  system = {
    primaryUser = username;
    stateVersion = 6;
  };

  users.users.${username} = {
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };
}
