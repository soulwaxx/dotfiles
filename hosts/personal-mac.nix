{
  username,
  ...
}:
{
  imports = [
    ../modules/darwin/system.nix
  ];

  home-manager.users.${username} = {
    imports = [
      ../modules/profiles/base-home.nix
      ../modules/profiles/darwin-home.nix
      ../modules/profiles/personal-home.nix
    ];
    home.homeDirectory = "/Users/${username}";
    dotfiles.pi.vaultAgentModel = "openai/gpt-6-luna";
    dotfiles.herdr.heeler.enable = true;
  };
}
