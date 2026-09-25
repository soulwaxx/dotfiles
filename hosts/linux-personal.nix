{
  lib,
  username,
  linuxHost,
  ...
}:
{
  imports = [
    ../modules/profiles/base-home.nix
    ../modules/profiles/linux-home.nix
    ../modules/profiles/personal-home.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
  };

  dotfiles.linux = {
    enableDesktop = lib.mkDefault linuxHost.enableDesktop;
    enableLoginShellRegistration = lib.mkDefault linuxHost.enableLoginShellRegistration;
  };

  dotfiles.kubernetes.enable = lib.mkDefault linuxHost.enableKubernetes;
}
