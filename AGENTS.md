# AGENTS.md: dotfiles

This repository declares cross-platform dotfiles with Nix flakes, nix-darwin, Home Manager, and macOS Homebrew. The current inventory in `flake.nix` covers two Apple Silicon Macs (`work-macbook`, `personal-mac`), one ARM Linux host (`oci-arm`), and two x86_64 Linux hosts (`probook`, `tnas-f2-424`). Shared agent behavior lives in `config/shared/AGENTS.md`; Home Manager links it into both Claude Code and pi.

## Build and environment

- `flake.nix` is the only project manifest. `flake.lock` is the only dependency lockfile and pins `nixpkgs-unstable`, Home Manager `master`, nix-darwin `master`, nixGL, and treefmt-nix. There are no independent npm, Cargo, Python, or Go manifests.
- Run `nix develop` for the repository shell. `flake.nix` supplies Bash, jq, nh, nix-fast-build, nix-output-monitor, ripgrep, shellcheck, statix, deadnix, treefmt/nixfmt, and zsh.
- Linux development packages include Node.js 24, Rust, uv, and OpenTofu through `modules/linux/packages.nix`. macOS gets most user-facing tools from Homebrew; Terraform is the exception and is pinned through `modules/terraform.nix`. Versions otherwise follow the locked Nix inputs or installed Homebrew formulae rather than repository language-version files.
- Bootstrap a checked-out repository with `bash bootstrap.sh <host-name>`, or run `curl -fsSL https://raw.githubusercontent.com/soulwaxx/dotfiles/main/bootstrap.sh | bash -s -- <host-name>` on a fresh host. Run it as a normal user with `git`, `curl`, working network access, and `sudo`; it installs upstream nixos.org Nix and installs Homebrew only on macOS.
- `DOTFILES_DIR` selects a nonstandard checkout path for bootstrap and generated apps. Relative values resolve under `$HOME`. `DOTFILES_REPO` overrides the bootstrap clone URL.
- Keep machine-local values in ignored `~/.secrets` and local shell additions in `~/.zshrc.local`. Employer identifiers (account IDs, account/role names, work email, internal IPs) stay out of the repo: `aws-mcp` reads profiles from `~/.aws/config` at launch, the work git identity lives in `~/.gitconfig.local`, and employer-specific skills are gitignored. The personal git identity lives in `~/.gitconfig.personal` on every host. `local-files.sh` checks these files for the inventory `role`: bootstrap prompts for missing Git identity keys, and switch apps only warn. MCP configuration expects `GH_TOKEN`. Provider credentials and MCP OAuth tokens remain runtime state under `~/.pi/` or the tool-specific home directory; do not commit them.

## Architecture and data flow

```text
flake.nix              -> host inventory, outputs, switch apps, checks, dev shell
hosts/                 -> selects base + platform + role profiles per machine
modules/profiles/      -> base -> darwin/linux -> work/personal layering
modules/               -> one Home Manager or nix-darwin module per tool
config/                -> hand-edited files copied or symlinked into $HOME
tests/                 -> executable behavior tests run by flake checks, not agent directives
```

`flake.nix` turns each inventory entry into either a nix-darwin system or a standalone Home Manager configuration. Each host imports the shared base profile, one platform profile, and one role profile; those profiles import tool modules. Modules then install packages, generate settings, or link files from `config/` into the live home directory.

On macOS, nix-darwin owns system settings and Homebrew, then Home Manager owns user configuration. On Linux, standalone Home Manager owns user configuration and Nix packages; this repository does not manage Linuxbrew.

## Directory ownership

| Path | Ownership |
| --- | --- |
| `flake.nix` | Canonical host names, systems, users, output generation, apps, checks, and development shell |
| `hosts/` | Per-machine profile selection and machine-only settings |
| `modules/profiles/` | Shared, platform, and role composition |
| `modules/darwin/` | nix-darwin system settings and Homebrew activation |
| `modules/linux/` | Linux-native package set and Linux Home Manager behavior |
| `modules/host-specific/` | Work or personal logic that must not be selected by shell hostname checks |
| `modules/claude/`, `modules/pi.nix`, `modules/mcp-servers.nix` | AI tool installation, generated settings, shared MCP declarations, agents, hooks, and skills wiring |
| `config/claude/`, `config/pi/` | Hand-edited AI settings, hooks, extensions, and permission policy |
| `config/shared/` | Agent prompts, behavioral guidance, and the skill tree shared by Claude Code and pi |
| `tests/` | Flake check definitions and shell behavior tests |

## Repository conventions

- Keep one module per tool. Add tool-specific behavior to that module rather than a profile or host file.
- Homebrew owns fast-moving macOS user tools in `modules/homebrew-packages.nix`. Nix owns Linux command-line packages in `modules/linux/packages.nix`. Nix also owns generated configuration and packages required by Home Manager modules.
- Edit repository-owned static configuration under `config/` directly. Most static files use `mkOutOfStoreSymlink`, so edits take effect immediately. Claude's `settings.json` is an exception: `modules/claude/settings.nix` copies it during activation because Claude mutates the live file. pi's `settings.json` and `mcp.json` are generated and must be changed through Nix modules.
- Declare MCP servers once in `modules/mcp-servers.nix`; put harness-specific schema handling in the consumers.
- Keep shared skills under `config/shared/skills/<name>/SKILL.md`; they are explicit-only and must be invoked by name rather than automatically selected by the model.
- `config/pi/permission-system.json` and `config/claude/settings.json` protect secret content and catastrophic machine operations, and require confirmation for external or destructive effects.
- Claude Code uses `config/claude/hooks/semantic-command-scanner.sh` for direct download-to-shell hazards; it is not Git process policy. Keep compound-shell parsing out of simple permission globs.
- Treefmt owns formatting and currently runs nixfmt only. Use `nix fmt` or `nix run .#fmt`; do not reformat unrelated files.
- `home.stateVersion` is `26.05` in `modules/profiles/base-home.nix`; nix-darwin `system.stateVersion` is `6`. Treat these as compatibility levels, not package versions.

## Verification gates

The commands below come from `flake.nix` `mkCommonApps`.

```bash
# Run all-system flake checks, evaluate every host derivation, check formatting,
# run shellcheck and zsh syntax checks, validate JSON, then run statix/deadnix.
nix run .#check

# Run check, then build every declared host output for the current system.
nix run .#check-full

# Build current-system host outputs without running check first.
nix run .#check-build

# Format Nix files, or verify formatting without changing files.
nix run .#fmt
nix run .#fmt-check

# Run formatting and static/source lint only. Flake tests are not included.
nix run .#lint
```

`nix run .#check` runs six behavior checks: `bootstrap`, `claude-state-jq`, `skill-autocomplete`, `semantic-command-scanner`, `obsidian-lifecycle`, and `zsh-functions`. It also evaluates all five host derivation paths, including hosts for other systems, without cross-building them. Tests and flake checks are executable verification, not model directives.

Before switching a host:

1. Run `nix run .#check`.
2. For activation scripts, generated files, MCP wiring, or module structure, also run `nix run .#check-build`.
3. Apply with `nix run .#<host>` or its switch alias, for example `nix run .#work-macbook`.

No CI workflow exists. All gates run locally.

## Failure modes

- Generated switch apps reject a username that differs from the inventory entry. Pass `--force-host-mismatch` only for an intentional override.
- A custom `DOTFILES_DIR` makes flake evaluation impure; generated apps add `--impure` only when the variable is set.
- Never use a bare `exit` in `home.activation`. Home Manager concatenates entries into one `set -eu` script, so an early successful exit skips every later activation. Wrap the entry in a function and `return` from skip paths.
- Keep `nix.settings.auto-optimise-store` unset. Inline store optimisation races the daemon. macOS uses scheduled `nix.optimise.automatic`; Linux deduplication is manual through `nix run .#clean`.
- Keep `nixpkgs` on `nixpkgs-unstable`, not `nixos-unstable`; the chosen branch waits for Darwin cache builds.
- Upstream Nix does not trust the installing Linux user by default. `bootstrap.sh` adds the user to `trusted-users`; without that, the daemon silently ignores user-level substituters and related settings.
- Homebrew activation uses cleanup mode `zap`, so undeclared macOS packages are removed. It does not auto-update or upgrade declared packages.
- Kubernetes tooling follows `dotfiles.kubernetes.enable`. macOS Kubernetes formulae are work-only; Linux hosts set the flag in the `flake.nix` inventory; `personal-mac` leaves it disabled.
- Runtime installers and MCP commands need network access. Activation can install Claude Code, pi, selected Python tools, tmux TPM, and krew content from upstream sources.
