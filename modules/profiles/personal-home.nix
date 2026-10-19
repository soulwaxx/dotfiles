{
  imports = [
    ../host-specific/personal.nix
  ];

  dotfiles.pi = {
    defaultProvider = "openai";
    defaultModel = "gpt-6.1-sol";
    subagentModels = {
      scout = "openai/gpt-6-luna";
      reviewer = "openai/gpt-6.1-sol";
      worker = "openai/gpt-6-luna";
    };
  };
}
