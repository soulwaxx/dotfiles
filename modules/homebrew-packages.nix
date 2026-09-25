let
  commonTaps = [
    "nikitabobko/tap" # AeroSpace tiling WM cask
    "FelixKratz/formulae" # borders
  ];

  workTaps = [
    "argoproj/tap"
    "aws/tap"
  ];

  baseBrews = [
    "curl"
    "wget"
    "gh"
    "git"
  ];

  cloudBrews = [
    "awscli"
  ];

  # Work-only: personal-mac sets no `dotfiles.kubernetes.enable`, so shipping
  # these in commonBrews contradicted the flag that already gates k9s and the
  # Linux equivalents (modules/linux/packages.nix).
  kubernetesBrews = [
    "kubectl"
    "helm"
    "krew" # kubectl plugin manager (Linux: modules/linux/packages.nix)
    "kubectx" # kubectx/kubens
    "kustomize"
  ];

  # Standalone CLI binaries. On macOS Homebrew owns most user-facing packages;
  # Linux gets the same tools via Nix (modules/linux/packages.nix). LSPs and
  # formatters are no longer pinned by Nix here — nvim's Mason owns them on both
  # platforms. Config-generating Home Manager program modules (bat, fzf,
  # starship, atuin, tmux config, git/delta, …) stay Nix-managed on both.
  cliBrews = [
    "btop"
    "cmake"
    "eza"
    "fblog"
    "fd"
    "glow"
    "graphviz"
    "jq"
    "make" # GNU make (installs as gmake)
    "nixfmt" # nvim conform + treefmt parity; Mason has no darwin-arm64 nixfmt
    "p7zip"
    "ripgrep"
    "shellcheck"
    "tmux" # config lives in modules/tmux.nix
    "statix" # nvim-lint nix source; Mason only builds it slowly from cargo
    "tree-sitter-cli" # nvim-treesitter parser compilation (the plain `tree-sitter` formula ships only the library)
    "unar"
    "yq" # Mike Farah's Go yq (== nixpkgs yq-go)
    "yamlfmt" # Zed YAML external formatter (parity with nvim conform); also general-purpose
  ];

  devToolchainBrews = [
    "node@24" # LTS parity with Linux and npm-based activation scripts; keg-only, so PATH is declared in modules/dotfiles.nix
    "uv"
    "pre-commit"
    "rust"
    "rust-analyzer" # editor LSP parity with Linux (Linux ships it via packages.nix)
  ];

  commonBrews = baseBrews ++ cloudBrews ++ devToolchainBrews ++ cliBrews;

  darwinBrews = [
    # Linux installs neovim via Nix (programs.neovim in modules/neovim.nix).
    "neovim"
    # keep: macOS ships no flock binary; claude-obsidian wiki-lock.sh requires it
    "flock"
    "docker"
    "docker-buildx"
    "docker-compose"
    "docker-credential-helper"
    "docker-credential-helper-ecr"
    "python3"
    # Managed as a launchd service so retrieval reranking (soulwaxx_brain
    # rerank.py → 127.0.0.1:11434) survives reboots instead of silently
    # degrading to BM25-only when the server is down.
    {
      name = "ollama";
      start_service = true;
      restart_service = "changed";
    }
    "ncurses"
    "imagemagick"
    "ghostscript"
    "mermaid-cli"
    # keep: macOS-only desktop daemon launched by AeroSpace's after-startup-command
    "borders"
  ];

  darwinCasks = [
    "the-unarchiver"
    "spotify"
    "discord"
    "ghostty"
    "zed"
    "obsidian"
    "orbstack"
    "font-jetbrains-mono"
    "font-jetbrains-mono-nerd-font"
    "font-fira-code"
    "font-fira-code-nerd-font"
    "aerospace"
  ];

  # Work-host-only Homebrew packages, referenced from hosts/work-macbook.nix.
  workBrews = kubernetesBrews ++ [
    "argocd"
    "aws-sso-cli"
    "argoproj/tap/kubectl-argo-rollouts"
    "aws/tap/eks-node-viewer"
    "flyway"
    "pyenv"
    "k6"
    "keeper-commander"
    "terraform-docs"
  ];

  workCasks = [
    "cursor"
    "keepingyouawake"
    "session-manager-plugin"
  ];
in
# Only the composed lists are exported; the category bindings above are
# assembly detail and had no consumers.
{
  inherit
    commonTaps
    workTaps
    commonBrews
    darwinBrews
    darwinCasks
    workBrews
    workCasks
    ;
}
