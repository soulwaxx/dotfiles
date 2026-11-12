{
  config,
  pkgs,
  lib,
  nixpkgs,
  username,
  ...
}:
let
  verifyNixStore = import ../lib/verify-nix-store.nix { inherit pkgs; };
  # Replaces nix-darwin's GC command (below), so read nix.gc.options here.
  verifiedNixGc = pkgs.writeShellScript "verified-nix-gc" ''
    set -eu
    ${verifyNixStore}
    ${pkgs.nix}/bin/nix-collect-garbage ${config.nix.gc.options}
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
    settings = import ../lib/nix-settings.nix // {
      # nix-darwin's module default already supplies "root", so only add admins.
      trusted-users = [ "@admin" ];
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
    # Store dedup runs as a scheduled job only (see ../lib/nix-settings.nix).
    optimise.automatic = true;
  };
  launchd.daemons = {
    nix-gc.command = lib.mkForce "${verifiedNixGc}";
    nix-optimise.command = lib.mkForce "${verifiedNixOptimise}";
  };

  nixpkgs.config.allowUnfree = true;

  security.pam.services.sudo_local.touchIdAuth = true;

  # Home Manager owns zsh completion initialization for this user.
  programs.zsh.enableGlobalCompInit = false;
  # Starship owns the prompt; skip /etc/zshrc's `promptinit; prompt suse` (~16 ms).
  programs.zsh.promptInit = "";

  system = {
    primaryUser = username;
    stateVersion = 6;
  };

  users.users.${username} = {
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };
}
