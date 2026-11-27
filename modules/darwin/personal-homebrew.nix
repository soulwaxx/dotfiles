let
  packages = import ../homebrew-packages.nix;
in
{
  homebrew = {
    taps = packages.personalTaps;
    casks = packages.personalCasks;
  };
}
