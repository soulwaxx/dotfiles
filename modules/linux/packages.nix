{
  config,
  lib,
  pkgs,
  ...
}:
let
  basePackages = [
    pkgs.curl # keep: system curl on Linux is often outdated; brew not available
    pkgs.gh # keep: fast-moving; macOS uses brew gh for cadence
    pkgs.htop # linux-only complement to btop
    pkgs.unzip # macOS ships unzip via system
    pkgs.wget # keep: macOS uses brew wget for newer version
  ];

  cloudPackages = [
    pkgs.awscli2 # keep: fast-moving; macOS uses brew awscli for cadence
  ];

  kubernetesPackages = [
    pkgs.argocd # keep: ArgoCD CLI — work tool, needed on servers/NAS
    pkgs.kubectl # keep: version must match cluster; macOS uses brew kubectl
    pkgs.kubernetes-helm # keep: macOS uses brew helm for version cadence
    pkgs.krew # kubectl plugin manager
    pkgs.kubectx
    pkgs.kustomize
  ];

  # Standalone CLI binaries. macOS gets these from Homebrew
  # (modules/homebrew-packages.nix cliBrews); Linux has no brew, so Nix owns
  # them here. LSPs/formatters are not pinned — nvim's Mason owns them.
  cliPackages = [
    pkgs.btop
    pkgs.cmake
    pkgs.eza
    pkgs.fblog
    pkgs.fd
    pkgs.glow
    pkgs.graphviz
    pkgs.herdr # config lives in modules/herdr.nix
    pkgs.ghostscript
    pkgs.imagemagick
    pkgs.jq
    pkgs.gnumake
    pkgs.mermaid-cli
    pkgs.nixfmt # nvim conform (nix) + treefmt parity
    pkgs.statix # nvim-lint nix source
    pkgs.p7zip
    pkgs.python3 # herdr's Claude session hook runs python3
    pkgs.ripgrep
    pkgs.shellcheck
    pkgs.tmux # config lives in modules/tmux.nix
    pkgs.tree-sitter
    pkgs.unar
    pkgs.yamlfmt # Zed YAML external formatter (parity with nvim conform)
    pkgs.yq-go
  ];

  devToolchainPackages = [
    pkgs.cargo # rust toolchain; macOS uses brew rust
    pkgs.clippy
    pkgs.nodejs_24 # Node 24 LTS parity with macOS Homebrew node@24
    pkgs.opentofu # Linux stays on the Nix-native Terraform-compatible CLI
    pkgs.pre-commit # keep: macOS uses brew pre-commit (python ecosystem)
    pkgs.rust-analyzer
    pkgs.rustc
    pkgs.rustfmt
    pkgs.uv # keep: fast-moving; macOS uses brew uv for cadence
  ];
in
{
  # Linux package set. macOS routes the same tools through Homebrew
  # (modules/homebrew-packages.nix); there is no cross-platform shared list.
  home.packages =
    basePackages
    ++ cloudPackages
    ++ cliPackages
    ++ lib.optionals config.dotfiles.kubernetes.enable kubernetesPackages
    ++ devToolchainPackages;
}
