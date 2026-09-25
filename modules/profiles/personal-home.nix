{
  imports = [
    ../host-specific/personal.nix
  ];

  dotfiles.pi = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-6-sol";
    subagentModels = {
      scout = "openai-codex/gpt-6-luna";
      reviewer = "openai-codex/gpt-6-sol";
      worker = "openai-codex/gpt-6-luna";
    };
  };
}
