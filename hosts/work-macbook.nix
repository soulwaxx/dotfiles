{
  username,
  ...
}:
{
  imports = [
    ../modules/darwin/system.nix
    ../modules/darwin/work-homebrew.nix
  ];

  home-manager.users.${username} = {
    imports = [
      ../modules/profiles/base-home.nix
      ../modules/profiles/darwin-home.nix
      ../modules/profiles/work-home.nix
    ];
    home.homeDirectory = "/Users/${username}";
  };
}
