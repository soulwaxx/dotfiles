# Shared Nix settings, consumed by both the nix-darwin system config
# (modules/darwin/system.nix) and the standalone Home Manager Nix config on
# Linux (modules/nix.nix). Kept here so the two never drift; each consumer adds
# only its platform-specific settings.
{
  # upstream does not enable flakes by default; the repo's workflow needs them
  experimental-features = [
    "nix-command"
    "flakes"
  ];

  # cache.nixos.org is listed explicitly because setting substituters replaces
  # the list rather than appending to it. nix-community.cachix.org backs
  # packages built by nix-community (home-manager, nixGL, overlays) so they are
  # substituted instead of rebuilt locally.
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];

  # Fetch build deps from the cache instead of copying them over (slow)
  # remote-builder links.
  builders-use-substitutes = true;
  # Keep build outputs and .drvs alive so devshells / repeated builds are not
  # re-fetched or rebuilt after a GC. keep-derivations is already the upstream
  # default; set it here so the intent is co-located.
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

  # `auto-optimise-store` is deliberately NOT set: inline optimisation races
  # the daemon and can corrupt the store (NixOS/nix#7273); nix-darwin asserts
  # against it (nix-darwin#1252). macOS dedups via scheduled nix.optimise;
  # Linux via `nix run .#clean`.
}
