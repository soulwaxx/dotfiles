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
    observationalMemory = {
      model = {
        provider = "openai";
        id = "gpt-6-luna";
      };
      # GPT sessions are limited to a 272K window; compact well before it.
      compactAfterTokens = 220000;
    };
  };
}
