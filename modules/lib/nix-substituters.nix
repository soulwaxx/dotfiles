# Shared binary-cache substituters and their public keys, consumed by both the
# nix-darwin system config (modules/darwin/system.nix) and the standalone Home
# Manager Nix config on Linux (modules/nix.nix). Kept here so the two harnesses
# never drift on which caches are trusted.
#
# cache.nixos.org is listed explicitly because setting nix.settings.substituters
# replaces the list rather than appending to it. nix-community.cachix.org backs
# packages built by nix-community (home-manager, nixGL, overlays) so they are
# substituted instead of rebuilt locally.
{
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
