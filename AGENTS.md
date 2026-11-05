# AGENTS.md: dotfiles

Cross-platform dotfiles using Nix flakes, nix-darwin, Home Manager, and macOS Homebrew. `flake.nix` owns the host inventory, outputs, apps, checks, and dev shell; `flake.lock` pins dependencies. Shared agent behavior lives in `config/shared/AGENTS.md`, linked into Claude Code and pi.

## Layout and ownership

- `hosts/` selects shared, platform, and role profiles from `modules/profiles/`.
- `modules/` owns tool configuration; keep one module per tool. Put machine-only settings in hosts and role-specific behavior in `modules/host-specific/`, not shell hostname checks.
- macOS: nix-darwin owns system settings and Homebrew; Home Manager owns user configuration. Linux: standalone Home Manager owns configuration and Nix packages; no Linuxbrew.
- macOS user tools belong in `modules/homebrew-packages.nix`; Linux CLI packages in `modules/linux/packages.nix`. Nix also owns Home Manager dependencies and pinned Terraform (`modules/terraform.nix`).
- `config/` holds hand-edited files. Most use `mkOutOfStoreSymlink`, so edits take effect immediately. Claude settings are reconciled during activation: edit `config/claude/settings.json` for declarative values. Runtime `pluginConfigs` preferences survive unless overridden in the repo; other live settings still reset. pi's `settings.json` and `mcp.json` are generated: edit Nix modules instead.
- Declare MCP servers once in `modules/mcp-servers.nix`; keep harness-specific schema handling in consumers.
- Shared skills live in `config/shared/skills/<name>/SKILL.md` and are explicit-only by default: invoke by name, not automatic selection. Exceptions: `grilling` and `infra-review` may be selected automatically according to their descriptions.
- `tests/` contains executable verification, not agent directives. Obsidian and skill-completion tests live in their standalone package repositories.

## Environment and local state

- Use `nix develop` for repository tooling. Bootstrap with `bash bootstrap.sh <host-name>` as a normal user with `git`, `curl`, network access, and `sudo`.
- `DOTFILES_DIR` overrides the checkout path; relative values resolve under `$HOME`. Generated apps add `--impure` only when it is set. `DOTFILES_REPO` overrides the bootstrap clone URL.
- Keep secrets in ignored `~/.secrets`, shell additions in `~/.zshrc.local`, work Git identity in `~/.gitconfig.local`, and personal identity in `~/.gitconfig.personal`. Employer identifiers and employer-specific skills stay out of Git; `aws-mcp` reads runtime profiles from `~/.aws/config`.
- `local-files.sh` checks role-specific local files; bootstrap prompts for missing Git identity keys, while switch apps only warn. MCP expects `GH_TOKEN`; provider credentials and OAuth tokens remain runtime state, never committed.
- Preserve protections in `config/pi/permission-system.json` and `config/claude/settings.json`: secret access, catastrophic operations, and confirmation for external or destructive effects.

## Verification

```bash
nix run .#check        # Flake tests, all-host evaluation, formatting, static lint
nix run .#check-build  # Build all host outputs for the current system
nix run .#check-full   # check + check-build
nix run .#lint         # Formatting/static checks only; no behavior tests
nix run .#fmt          # Format Nix files (treefmt/nixfmt)
nix run .#fmt-check    # Verify formatting without changes
```

Before switching, run `check`; for activation scripts, generated files, MCP wiring, or module structure, also run `check-build`. Apply with `nix run .#<host>` or its switch alias. Switch apps reject mismatched usernames; use `--force-host-mismatch` only intentionally. All gates run locally; there is no CI. Do not reformat unrelated files.

## Operational pitfalls

- Never use bare `exit` in `home.activation`: Home Manager concatenates entries into one `set -eu` script, so even successful exit skips later activation. Wrap the entry in a function and `return` from skip paths.
- Keep `nix.settings.auto-optimise-store` unset: inline optimisation races the daemon. macOS uses scheduled `nix.optimise.automatic`; Linux deduplication is manual via `nix run .#clean`.
- Keep `nixpkgs` on `nixpkgs-unstable`, not `nixos-unstable`; that channel waits for Darwin cache builds.
- Bootstrap adds the Linux user to Nix `trusted-users`; otherwise the daemon silently ignores user-level substituters and related settings.
- Homebrew cleanup uses `zap`: undeclared packages are removed. Activation does not auto-update or upgrade declared packages.
- Kubernetes tooling follows `dotfiles.kubernetes.enable`: macOS formulae are work-only; Linux flags live in the flake inventory.
- Treat `home.stateVersion` (`modules/profiles/base-home.nix`) and nix-darwin `system.stateVersion` as compatibility levels, not package versions.
- Activation installers and MCP commands may require network access.
