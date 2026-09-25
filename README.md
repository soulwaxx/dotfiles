# dotfiles

Declarative cross-platform dotfiles using **Nix flakes**, **nix-darwin**, **Home Manager**, and macOS **Homebrew**. One repo manages macOS workstations and Linux hosts.

## Quick start

Bootstrap a fresh machine (installs Nix, installs Homebrew on macOS, clones repo, builds config):

```bash
curl -fsSL https://raw.githubusercontent.com/soulwaxx/dotfiles/main/bootstrap.sh | bash -s -- <host-name>
```

Available hosts: `work-macbook`, `personal-mac`, `oci-arm`, `probook`, `tnas-f2-424`

After cloning, `nix run .#hosts` prints the host inventory from `flake.nix`.

Some host data lives in untracked files. Create them as listed in [Local machine files](#local-machine-files-untracked); create `~/.gitconfig.personal` before switching any host. On work hosts, also create `~/.gitconfig.local` before the first switch or switch again afterwards.

Set `DOTFILES_DIR` when bootstrapping or switching from a nonstandard clone path. Relative `dotfilesDir` values in `flake.nix` are resolved under `$HOME`; absolute values are supported for hosts that need a fixed custom path.

## Usage

### Apply changes (macOS)

```bash
nix run .#switch-work
nix run .#switch-personal
# Host-name aliases also work:
nix run .#work-macbook
nix run .#personal-mac
```

### Apply changes (Linux)

```bash
nix run .#switch-oci-arm
nix run .#switch-probook
nix run .#switch-tnas
# Host-name aliases also work:
nix run .#oci-arm
nix run .#probook
nix run .#tnas-f2-424
```

### Validate without building

```bash
nix run .#check
```

### Build activation outputs for this system

```bash
nix run .#check-build
```

### Format Nix files

```bash
nix run .#fmt
```

### Verify formatting

```bash
nix run .#fmt-check
```

### Development shell

```bash
nix develop
```

### Rollback

```bash
# Home Manager
home-manager generations
home-manager switch --generation <N>

# nix-darwin
darwin-rebuild switch --rollback
```

## Structure

The repo is organized around a small set of ownership boundaries:

- `flake.nix` declares every host and generates switch/check apps.
- `hosts/` selects platform and role profiles for each machine.
- `modules/profiles/` defines shared, platform, and role layering.
- `modules/` owns generated Home Manager, nix-darwin, Homebrew, shell, editor, AI-tool, and package configuration.
- `config/` contains hand-edited files that are symlinked into place where live editing is useful.

Start with `flake.nix`, then read `modules/profiles/base-home.nix` plus the relevant platform and role profile. Most tool-specific behavior lives in one module named after the tool.

## How it works

- **macOS**: nix-darwin manages system-level settings (Homebrew packages/casks, Touch ID sudo, defaults). Home Manager manages user dotfiles and generated config.
- **Linux**: Home Manager standalone manages shell/config wiring and native Nix packages. Linuxbrew is not managed by this repo.
- **Host inventory**: `flake.nix` declares host name, username, module, system, switch app, and role (`work` or `personal`) in one attrset per platform. The role selects which untracked files `local-files.sh` checks. Configuration outputs and `nix run .#switch-*` apps are generated from that inventory.
- **Package ownership**: Homebrew owns most fast-moving user tools on macOS only. Linux CLI tools live in `modules/linux/packages.nix`. Nix also owns Home Manager modules, generated config, shell integration, Python libraries used by shell tools, bootstrap tools that must be in the Nix profile, and the pinned macOS Terraform binary. macOS switches uninstall undeclared Homebrew packages but do not upgrade declared packages; run `brew-upgrade` or `cfg-upgrade` explicitly when upgrades are intended.
- **Terraform/OpenTofu**: Apple Silicon macOS hosts use Nix-managed Terraform 1.12.2. Linux hosts use Nix-managed `opentofu`.
- **Kubernetes tooling**: `dotfiles.kubernetes.enable` controls shared Kubernetes CLIs and K9s integration. Work hosts turn it on through `modules/profiles/work-home.nix`; Linux hosts set it explicitly in the `flake.nix` inventory.
- **Shell completion**: native zsh completions feed `fzf-tab`, `fzf` stays in place for shell widgets and fuzzy pickers, and Atuin owns history search.
- **Config files** in `config/` are symlinked into `$HOME` via `mkOutOfStoreSymlink` only where this repo intentionally owns the live file. Claude settings are generated from `config/claude/settings.json` and copied into place by Nix; Claude instructions, statusline, rules, hooks, and skills are symlinked. Cursor settings are symlinked by `modules/cursor.nix`; Zed settings are symlinked by `modules/zed.nix`. pi reads the shared global instructions via `~/.pi/agent/AGENTS.md` (a context/memory file, symmetric with Claude's `CLAUDE.md`) and the shared skills tree via `~/.pi/agent/skills`. AeroSpace (`config/aerospace/`) is symlinked the same way, via `modules/aerospace.nix`.
- **AI MCP servers** live in `modules/mcp-servers.nix`. Claude and pi each render their own schema from the same source; common servers are shared, work-only servers are gated by the work profile, and Obsidian is gated by `dotfiles.claude.obsidian.vaultPath`.
- **AI harness security**: `@gotgenes/pi-permission-system` owns declarative authorization in pi through `config/pi/permission-system.json`; Claude Code uses `config/claude/settings.json`. Permissions protect secret content and catastrophic machine operations, and ask before external or destructive effects. Claude's semantic scanner covers direct download-to-shell hazards, not Git process policy.
- **Repository skills**: `~/.claude/skills` is a symlink to `config/shared/skills`; pi reads the same tree via `~/.pi/agent/skills`. Skills are explicit-only and must be invoked by name rather than automatically selected by the model.
- **Vendored skills**: several skills are adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). They are an adapted fork rather than a verbatim mirror. Harness-neutral tool wording, local workflow changes, and cross-skill references were added locally, so re-vendoring blindly regresses that work. Adapted skills and their upstream paths: `codebase-design`, `code-review`, `diagnosing-bugs`, `domain-modeling`, `grill-with-docs`, `implement`, `prototype`, `research`, `resolving-merge-conflicts` (under `skills/engineering/`); `grilling`, `handoff` (under `skills/productivity/`); and `writing-great-skills` (upstream `skills/productivity/writing-for-agents`, renamed). Last reconciled against upstream commit `0ab1b63` (2026-08-20). To check for updates: `git clone --depth 1 https://github.com/mattpocock/skills` and diff each `skills/<bucket>/<name>/` against `config/shared/skills/<name>/`. Ignore the upstream em-dash→colon prose sweep and harness-specific tool names already handled locally. Port substantive workflow changes by hand.
- **Shared host shape** lives in `modules/profiles/base-home.nix` plus platform (`darwin-home.nix`, `linux-home.nix`) and role (`work-home.nix`, `personal-home.nix`) profiles; host files import these profiles explicitly.
- **Host-specific logic** lives in `hosts/<name>.nix` and `modules/host-specific/` — no hostname checks in shell files.

## Maintenance rules

- Add a host by editing the `darwinHosts` or `linuxHosts` inventory in `flake.nix`, then add only the role/platform delta under `hosts/` or `modules/host-specific/`.
- Add macOS Homebrew formulae/casks to `modules/homebrew-packages.nix`.
- Add Linux CLI packages to `modules/linux/packages.nix`; Linuxbrew is intentionally not used.
- Add Kubernetes tools on macOS via Homebrew (`modules/homebrew-packages.nix` `kubernetesBrews`, folded into `workBrews`) and on Linux via Nix (`modules/linux/packages.nix` `kubernetesPackages`, gated by `dotfiles.kubernetes.enable`), or a dedicated module such as `modules/k9s.nix`. Both paths follow `dotfiles.kubernetes.enable`, which is false on `personal-mac`.
- Add a package to another Nix module when Home Manager needs it for generated config, shell activation, runtime integration, or platform-specific ownership.
- Run `nix run .#check` before switching hosts; it runs six behavior checks (`bootstrap`, `claude-state-jq`, `skill-autocomplete`, `semantic-command-scanner`, `obsidian-lifecycle`, and `zsh-functions`), then evaluates each host's activation/system derivation path so a broken `home.file` source or package attr fails fast without a cross-build. Tests and flake checks are executable verification, not model directives.
- Run `nix run .#check-build` when changing activation scripts, generated files, MCP wiring, or Home Manager/nix-darwin module structure. It builds every declared host output for the current system; other-system hosts are evaluation-checked only.
- Add shared MCP servers in `modules/mcp-servers.nix`; add tool-specific differences inside that server entry instead of duplicating definitions in `modules/claude/mcp.nix`.
- Treat `~/.pi/agent/settings.json` and `~/.pi/agent/mcp.json` as read-only. Home Manager owns both files. Change Pi settings, packages, extensions, and MCP servers in this repository, then switch the host.
- Add shared skills under `config/shared/skills/<name>/SKILL.md`. Home Manager links `config/shared/skills` to `~/.claude/skills`; pi reads the same tree via `~/.pi/agent/skills`. Mark repository skills explicit-only so they are invoked by name.
- Some shared skills are vendored (and re-authored) from upstream projects. When a skill is derived from an external source, record its provenance and update-check steps in a `VENDOR.md` beside its `SKILL.md` (see `config/shared/skills/aws-architecture-diagram/VENDOR.md`), so a future agent can diff against upstream and port improvements without re-discovering the source.

Useful shell aliases:

| Alias                   | What it does                                                                    |
| ----------------------- | ------------------------------------------------------------------------------- |
| `cfg-check`             | Validate the flake across Darwin and Linux outputs                              |
| `nix run .#check-build` | Build every declared host output for this system                                |
| `nix run .#fmt-check`   | Verify Nix formatting without modifying files                                   |
| `nix run .#hosts`       | Print the declared host inventory from `flake.nix`                              |
| `nix-switch-refresh`    | Reapply this host's declared config with a forced Nix fetch refresh             |
| `nix-switch`            | Reapply this host's declared config                                             |
| `cfg-realign`           | Check, then switch back to declared config                                      |
| `cfg-upgrade`           | Update flake inputs, check, run tool upgrades, then switch                      |
| `brew-upgrade`          | macOS only: update and upgrade Homebrew packages                                |
| `linux-realign`         | Linux only: check/switch, then clean Nix store                                  |
| `linux-upgrade`         | Linux only: update flake inputs, switch, then clean Nix store                   |

## Nix distribution choice

Bootstrap uses the upstream nixos.org installer (`https://nixos.org/nix/install --daemon --yes`). This repo runs 100% open-source Nix with no downstream distribution.

How the pieces fit:

- The same installer path works for macOS and Linux.
- Upstream does not enable flakes by default. `modules/darwin/system.nix` enables `nix-command` and `flakes` declaratively. Bootstrap passes those features to its initial `nix run`; the Linux switch app also exports them through `NIX_CONFIG` because `nh` starts a separate Nix process.
- On macOS, nix-darwin owns Nix management: `modules/darwin/system.nix` sets `nix.enable = true`, so nix-darwin manages the daemon, `/etc/nix/nix.conf`, GC (`nix.gc`), and store optimisation (`nix.optimise`).
- Linux hosts run standalone Home Manager. `modules/nix.nix` manages the user Nix configuration after the first switch; the generated switch app supplies the experimental features needed to reach that point.

On first macOS bootstrap, `bootstrap.sh` invokes the repository's generated `bootstrap-<host>` app. That app runs `darwin-rebuild` from the locked `nix-darwin` input; subsequent switches use `nix run .#switch-work` or `nix run .#switch-personal`.

## Runtime trust boundaries

- Fresh-machine bootstrap can execute remote shell content from this repository, the upstream nixos.org Nix installer, and the Homebrew installer. Inspect first with `curl -fsSL https://raw.githubusercontent.com/soulwaxx/dotfiles/main/bootstrap.sh` when bootstrapping a machine you do not fully control yet.

- Claude Code is installed by executing Anthropic's installer from `https://claude.ai/install.sh` during activation when `~/.local/bin/claude` is absent.
- macOS activation installs CLI-only Python tools through Nix-provided `uv`; install failures warn and continue so temporary PyPI/network issues do not block activation.
- tmux TPM is bootstrapped during activation when missing. Darwin hosts with `dotfiles.kubernetes.enable` also install the `modify-secret` krew plugin when missing. Both depend on upstream network availability.
- Claude and pi MCP servers may launch pinned `npx`/`uvx` packages declared in `modules/mcp-servers.nix`.
- Claude permissions intentionally allow broad research and platform tooling. Treat `config/claude/settings.json` as the trust boundary for tool access.
- pi is installed by `npm install -g` into the repo-managed `~/.npm-global` prefix during activation; provider auth and MCP OAuth tokens remain runtime state under `~/.pi/` and are not managed by Nix.
- tmux resurrect is enabled, but pane-content capture is disabled so session snapshots do not persist terminal output.

## Local machine files (untracked)

These files hold host data that stays out of the repo. `bootstrap.sh` runs `local-files.sh`, which prompts for missing Git identity keys and writes them with mode 600. Every `switch-*` app runs the same check and only warns. Create the other files by hand. Skipped files do not break activation, but the features that read them lose that data.

All hosts:

- `~/.secrets` — environment variables and tokens, sourced by zsh. MCP configuration expects `GH_TOKEN`.
- `~/.zshrc.local` — machine-specific shell additions, sourced by zsh; not the primary override layer.

Personal and work hosts:

- `~/.gitconfig.personal` — personal Git identity. Personal hosts include it unconditionally; work hosts include it only for repos cloned through the `github.com-personal` SSH alias. The signing key path stays in Nix. Activation reads `user.email` from it for `~/.ssh/allowed_signers`. Create it before switching; without it, this configuration supplies no personal name or email and the personal signer entry is skipped.

  ```bash
  git config --file ~/.gitconfig.personal user.name "<personal-name>"
  git config --file ~/.gitconfig.personal user.email "<personal-email>"
  git config --file ~/.gitconfig.personal user.username "<personal-github-user>"
  chmod 600 ~/.gitconfig.personal
  ```

Work hosts:

- `~/.gitconfig.local` — work Git identity. Included before the personal-remote override. Activation also reads `user.email` from it as the work principal in `~/.ssh/allowed_signers`. The shared Git module does not supply `user.name`, so set it here.

  ```bash
  git config --file ~/.gitconfig.local user.name "<work-name>"
  git config --file ~/.gitconfig.local user.email "<work-email>"
  git config --file ~/.gitconfig.local user.username "<work-github-user>"
  chmod 600 ~/.gitconfig.local
  ```

- `~/.aws/config` — the `aws-mcp` server reads its profile allowlist from `aws configure list-profiles` at launch, read-only profiles first. Optionally set `AWS_MCP_PROFILE_FILTER` (ERE) in `~/.secrets` to narrow the list.
- `~/.zshrc.local` — also holds work VPN server aliases and the `dev-portal` function.
- `config/shared/skills/{create-aws-account,scaffold-gitops}/` — gitignored employer-specific skills inside the checkout. A fresh clone does not contain them; copy them from a backup. They load through the skills symlink without a switch.

## Nix cheat sheet

| Command                                    | What it does                                                 |
| ------------------------------------------ | ------------------------------------------------------------ |
| `nix flake update`                         | Update all flake inputs (nixpkgs, home-manager, nix-darwin)  |
| `nix flake update nixpkgs`                 | Update only nixpkgs                                          |
| `nix flake check --all-systems`            | Validate the flake and run the `checks` test suite           |
| `nix run .#check-build`                    | Build every declared host output for this system             |
| `nix store gc`                             | Remove unused Nix store paths (free disk space)              |
| `nix store optimise`                       | Deduplicate identical files in the Nix store                 |
| `nix-collect-garbage -d`                   | Delete old generations and garbage collect                   |
| `nix search nixpkgs <package>`             | Search for a package                                         |
| `nix shell nixpkgs#<package>`              | Temporarily use a package without installing                 |
| `nix repl` then `:lf .`                    | Explore the flake interactively                              |

## License

MIT, see [`LICENSE`](LICENSE). Vendored and adapted skills keep their upstream MIT license and copyright in their own directory: a `LICENSE` in each vendored skill directory under `config/shared/skills/`, and `LICENSE-claude-obsidian` beside the vendored `wiki/scripts/okf_mw/lint.py`.
