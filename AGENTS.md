# dotfiles

Cross-platform Nix flakes, nix-darwin, Home Manager, and macOS Homebrew.
`flake.nix` owns hosts, outputs, apps, checks, and the dev shell; `flake.lock`
pins dependencies. Shared behavior: `config/shared/AGENTS.md`, linked into
Claude Code and pi.

## Ownership

- `hosts/` selects shared/platform/role profiles from `modules/profiles/`.
  Keep machine settings in hosts, role behavior in `modules/host-specific/`,
  and one module per tool in `modules/`. Do not use shell hostname checks.
- macOS: nix-darwin owns system settings/Homebrew; Home Manager owns user
  configuration. Put user tools in `modules/homebrew-packages.nix`.
- Linux: standalone Home Manager owns configuration/packages; no Linuxbrew.
  CLI packages belong in `modules/linux/packages.nix`. Nix also owns Home
  Manager dependencies and pinned Terraform (`modules/terraform.nix`).
- Edit hand-maintained files in `config/`; most are out-of-store symlinks
  and take effect immediately. Edit generated pi `settings.json`/`mcp.json`
  through Nix modules.
- Claude declarative settings: `config/claude/settings.json`. Activation
  preserves runtime `pluginConfigs` preferences unless overridden here;
  other live settings reset.
- Declare MCP servers in `modules/mcp-servers.nix`; consumers own
  harness-specific schemas.
- Shared skills: `config/shared/skills/<name>/SKILL.md`. Invoke explicitly,
  except `grilling` and `infra-review`, which may auto-select by description.
- `tests/` is executable verification, not agent instructions. Obsidian and
  skill-completion tests belong to their standalone package repositories.

## Environment and safety

- Use `nix develop` for tooling. Bootstrap as a normal user with Git, curl,
  network access, and sudo: `bash bootstrap.sh <host-name>`.
- `DOTFILES_DIR` overrides the checkout; relative paths resolve under
  `$HOME`. Generated apps add `--impure` only when it is set.
  `DOTFILES_REPO` overrides the bootstrap clone URL.
- Local-only state: secrets in ignored `~/.secrets`, shell additions in
  `~/.zshrc.local`, Git identities in `~/.gitconfig.local` (work) and
  `~/.gitconfig.personal` (personal). Keep employer identifiers/skills out
  of Git. `aws-mcp` reads runtime `~/.aws/config` profiles.
- `local-files.sh` checks role-specific files. Bootstrap prompts for missing
  Git identity keys; switch apps only warn. MCP expects `GH_TOKEN`.
  Never commit credentials or OAuth tokens.
- Preserve secret-access, catastrophic-operation, and external/destructive
  effect confirmation protections in `config/pi/permission-system.json`
  and `config/claude/settings.json`.
- When changing bash or MCP rules in `config/pi/permission-system.json`,
  mirror them in `config/omp/config.yml` (`bash.patterns`,
  `tools.approval`); no test checks they match.

## Verification and activation

```bash
nix run .#check        # Tests, all-host evaluation, formatting, static lint
nix run .#check-build  # Build all current-system host outputs
nix run .#check-full   # check + check-build
nix run .#lint         # Formatting/static checks; no behavior tests
nix run .#fmt          # Format Nix with treefmt/nixfmt
nix run .#fmt-check    # Check formatting without changes
```

Run `check` before switching; also run `check-build` for activation scripts,
generated files, MCP wiring, or module structure. Apply with
`nix run .#<host>` or its switch alias. Use `--force-host-mismatch` only
intentionally; switch apps otherwise reject mismatched usernames.
All gates are local; there is no CI. Do not reformat unrelated files.

## Operational pitfalls

- Never use bare `exit` in `home.activation`: entries share one `set -eu`
  script, so even success skips later entries. Wrap entries in functions
  and `return` from skip paths.
- Leave `nix.settings.auto-optimise-store` unset: inline optimisation races
  the daemon. macOS uses scheduled `nix.optimise.automatic`; Linux uses
  manual `nix run .#clean`.
- Keep `nixpkgs` on `nixpkgs-unstable`, not `nixos-unstable`, to wait for
  Darwin cache builds.
- Linux bootstrap adds the user to Nix `trusted-users`; otherwise the daemon
  silently ignores user substituters and related settings.
- Homebrew cleanup uses `zap` and removes undeclared packages. Activation
  does not auto-update or upgrade declared packages.
- Kubernetes tools follow `dotfiles.kubernetes.enable`: macOS formulae
  are work-only; Linux flags live in the flake inventory.
- `home.stateVersion` (`modules/profiles/base-home.nix`) and nix-darwin
  `system.stateVersion` are compatibility levels, not package versions.
- Activation installers and MCP commands may need network access.
