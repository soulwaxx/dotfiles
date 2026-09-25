# Standalone Home Manager Nix settings for Linux hosts. On Darwin, nix-darwin
# owns /etc/nix/nix.conf (modules/darwin/system.nix); on Linux there is no
# system module in this repo, so Home Manager manages ~/.config/nix/nix.conf.
#
# Caveat: a user-level nix.conf only takes effect for substituters/keys when the
# invoking user is a trusted-user of the multi-user daemon. The upstream
# installer does not grant that, so bootstrap.sh writes `trusted-users` to
# /etc/nix/nix.conf and modules/profiles/linux-home.nix warns
# when it is missing. experimental-features and the registry work regardless of
# trust; everything else here is silently dropped for an untrusted user.
{
  nixpkgs,
  pkgs,
  ...
}:
let
  caches = import ./lib/nix-substituters.nix;
in
{
  nix = {
    enable = true;
    package = pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      inherit (caches) substituters;
      trusted-public-keys = caches.trustedPublicKeys;
      builders-use-substitutes = true;
      keep-outputs = true;
      keep-derivations = true;
      warn-dirty = false;
      fallback = true;
      # `auto-optimise-store` is deliberately NOT set: inline optimisation races
      # the daemon and can corrupt the store (NixOS/nix#7273). Home Manager has
      # no `nix.optimise` timer equivalent, so store dedup on Linux is manual
      # via `nix run .#clean`.
      http-connections = 50;
    };
    # Pin `nixpkgs#…` and <nixpkgs> to the flake's locked nixpkgs (see the
    # Darwin config for rationale).
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs}" ];
  };
}
