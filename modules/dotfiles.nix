{
  lib,
  dotfilesPath,
  ...
}:
let
  dollar = "$";
in
{
  options.dotfiles = {
    path = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path to the checked-out dotfiles repository.";
    };

    pathShellExpr = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      description = "Shell expression that respects DOTFILES_DIR at runtime.";
    };

    env = {
      userBinDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        internal = true;
        description = "Home-relative user bin directories added to interactive shells and tmux.";
      };

      nixProfileBinDir = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        internal = true;
        description = "Home-relative Nix profile bin directory.";
      };

      darwinPackageBinDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        internal = true;
        description = "Darwin package-manager bin directories added when present.";
      };

      systemBinDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        internal = true;
        description = "Fallback system bin directories kept in tmux's environment.";
      };
    };

    eza = {
      baseFlags = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        internal = true;
        description = "Shared eza flags for plain listings and fzf file previews.";
      };

      treePreviewCommand = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        internal = true;
        description = "Shared eza tree-preview command for fzf and zoxide directory pickers.";
      };
    };

    pi = {
      defaultProvider = lib.mkOption {
        type = lib.types.str;
        default = "anthropic";
        description = "Pi model provider selected at startup.";
      };

      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "claude-opus-5-5";
        description = "Pi model selected at startup.";
      };

      subagentModels = {
        scout = lib.mkOption {
          type = lib.types.str;
          default = "claude-haiku-4-5";
          description = "Pi model used by the scout subagent.";
        };

        reviewer = lib.mkOption {
          type = lib.types.str;
          default = "claude-opus-5-5";
          description = "Pi model used by the reviewer subagent.";
        };

        worker = lib.mkOption {
          type = lib.types.str;
          default = "claude-sonnet-5";
          description = "Pi model used by the worker subagent.";
        };
      };
    };
    claude.enableWorkIntegrations = lib.mkEnableOption "Claude Code work-only plugins, MCP servers, permissions, and hooks";
    aws.mcp = {
      endpointRegion = lib.mkOption {
        type = lib.types.enum [
          "us-east-1"
          "eu-central-1"
        ];
        default = "us-east-1";
        description = "Region hosting the managed AWS MCP Server endpoint.";
      };

      operationRegion = lib.mkOption {
        type = lib.types.str;
        default = "us-east-1";
        description = "Default AWS Region metadata passed to AWS MCP Server operations.";
      };
    };
    kubernetes.enable = lib.mkEnableOption "Kubernetes CLI packages and integrations";
    linux = {
      enableDesktop = lib.mkEnableOption "Linux desktop GUI tools and integrations";

      enableLoginShellRegistration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether Home Manager should try to register the Nix zsh as the login shell on Linux.";
      };

      nixGLWrapper = lib.mkOption {
        type = lib.types.enum [
          "mesa"
          "nvidia"
          "mesaPrime"
          "nvidiaPrime"
        ];
        default = "mesa";
        description = "nixGL wrapper used for Nix-built OpenGL applications on non-NixOS Linux desktops.";
      };
    };
    cursor.enable = lib.mkEnableOption "Cursor settings symlink on Darwin work hosts";
  };
  config = {
    dotfiles = {
      path = lib.mkDefault dotfilesPath;
      # Normalize relative DOTFILES_DIR to absolute so shell helpers work from any cwd.
      # Same logic as the flake app setup in flake.nix.
      # Uses double-quoted strings with dollar="$" to keep the escaping manageable:
      #   ${dollar} → shell $, ${dotfilesPath} → Nix-interpolated value.
      pathShellExpr = lib.mkDefault "${dollar}(d=\"${dollar}{DOTFILES_DIR:-${dotfilesPath}}\"; [ \"${dollar}d\" != \"${dollar}{d#/}\" ] || d=\"${dollar}HOME/${dollar}d\"; printf '%s' \"${dollar}d\")";
      eza = {
        baseFlags = "--group-directories-first --icons=auto";
        treePreviewCommand = "eza --tree --level=2 --icons=always --group-directories-first --git --color=always --time-style=relative";
      };
      env = {
        userBinDirs = [
          ".cargo/bin"
          ".local/bin"
          ".npm-global/bin"
          ".krew/bin"
        ];
        nixProfileBinDir = ".nix-profile/bin";
        darwinPackageBinDirs = [
          "/opt/homebrew/opt/node@24/bin"
          "/usr/local/opt/node@24/bin"
          "/opt/homebrew/bin"
          "/usr/local/bin"
          "/opt/homebrew/opt/ncurses/bin"
          "/usr/local/opt/ncurses/bin"
        ];
        systemBinDirs = [
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
    };
  };
}
