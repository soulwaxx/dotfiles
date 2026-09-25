_:
let
  packages = import ../homebrew-packages.nix;
in
{
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      # Homebrew requires explicit confirmation for bundle cleanup in recent
      # releases; nix-darwin activation is non-interactive by design.
      extraFlags = [ "--force-cleanup" ];
      # Homebrew 6 requires trust for non-official taps by default; keep Brewfile
      # tap declarations as the source of truth instead of maintaining trust state.
      extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
      # Keep Homebrew updates/upgrades explicit via `brew-upgrade` / `cfg-upgrade`.
      autoUpdate = false;
      upgrade = false;
    };
    taps = packages.commonTaps;
    brews = packages.commonBrews ++ packages.darwinBrews;
    casks = packages.darwinCasks;
  };
}
