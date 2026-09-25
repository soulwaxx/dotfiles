let
  packages = import ../homebrew-packages.nix;
in
{
  homebrew = {
    taps = packages.workTaps;
    brews = packages.workBrews;
    casks = packages.workCasks;
  };
}
