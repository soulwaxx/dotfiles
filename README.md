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
- **Terraform/OpenTofu**: Apple Silicon macOS hosts use Nix-managed Terraform pinned in `modules/terraform.nix`. Linux hosts use Nix-managed `opentofu`.
- **Kubernetes tooling**: `dotfiles.kubernetes.enable` controls shared Kubernetes CLIs and K9s integration. Work hosts turn it on through `modules/profiles/work-home.nix`; Linux hosts set it explicitly in the `flake.nix` inventory.
- **Shell completion**: native zsh completions feed `fzf-tab`, `fzf` stays in place for shell widgets and fuzzy pickers, and Atuin owns history search.
- **Config files** in `config/` are symlinked into `$HOME` via `mkOutOfStoreSymlink` only where this repo intentionally owns the live file. Claude settings are generated from `config/claude/settings.json` and copied into place by Nix; Claude instructions, statusline, rules, shared hooks, and shared skills are symlinked; package hooks are installed by their owning plugins. VS Code settings are symlinked by `modules/vscode.nix`. pi reads the shared global instructions via `~/.pi/agent/AGENTS.md` (a context/memory file, symmetric with Claude's `CLAUDE.md`) and the shared skills tree via `~/.pi/agent/skills`.
- **AI MCP servers** live in `modules/mcp-servers.nix`. Claude and pi each render their own schema from the same source; common servers are shared, and work-only servers are gated by the work profile. The standalone [obsidian-second-brain](https://www.npmjs.com/package/@soulwaxx/obsidian-second-brain) integration is enabled only on macOS: pi loads `npm:@soulwaxx/obsidian-second-brain`, while Claude Code installs the same npm artifact as `obsidian-second-brain@obsidian-second-brain` at user scope through the `soulwaxx/obsidian-second-brain` GitHub marketplace. Both use `~/.config/obsidian-second-brain/properties.json` for the vault and feature selection; activation seeds this editable file only when absent. Guard, generated navigation, and retrieval refresh default on; deprecated agent auto-commit defaults off. Obsidian Git exclusively owns commits, pulls, and pushes and must be installed/enabled by the owner; use the package's preview/hash-confirmed [configuration workflow](https://github.com/soulwaxx/obsidian-second-brain/blob/main/docs/setup.md) to configure it and exclude derived state from Git. Linux switches disable an existing user-scoped Claude plugin; pi omits the package. From any working directory, invoke `/obsidian-second-brain:wiki` in Claude Code or `/skill:wiki` in pi. The focused `wiki-query`, `wiki-save`, `wiki-ingest`, `wiki-research`, and `wiki-health` skills use the same prefixes. The optional vault shell (`brain`) only enters the vault; it does not sync it. Home Manager exposes `obsidian-second-brain` in `~/.local/bin`, reusing pi's installed npm package for CLI search/doctor/build commands without a second installation. `dotfiles.pi.vaultAgentModel` sets the packaged pi specialist's model per host in `hosts/`; Claude's specialist inherits its Claude session settings. Package updates are explicit: `pi update npm:@soulwaxx/obsidian-second-brain`; for Claude Code, run `claude plugin marketplace update obsidian-second-brain` followed by `claude plugin update obsidian-second-brain@obsidian-second-brain --scope user`.
- **AI harness security**: `@gotgenes/pi-permission-system` owns declarative authorization in pi through `config/pi/permission-system.json`; Claude Code uses `config/claude/settings.json`. Permissions protect secret content and catastrophic machine operations, and ask before external or destructive effects.
- **Repository skills**: `~/.claude/skills` is a symlink to `config/shared/skills`; pi reads the same tree via `~/.pi/agent/skills`. Shared skills are explicit-only except `infra-review` and `writing-style`, which the model can invoke; the Obsidian `wiki` skill is owned by [obsidian-second-brain](https://github.com/soulwaxx/obsidian-second-brain).
- **Vendored skills**: several skills are adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). They are an adapted fork rather than a verbatim mirror. Harness-neutral tool wording, local workflow changes, and cross-skill references were added locally, so re-vendoring blindly regresses that work. Adapted skills and their upstream paths: `code-review`, `implement`, `research` (under `skills/engineering/`); `grilling`, `handoff` (under `skills/productivity/`); and `writing-great-skills` (upstream `skills/productivity/writing-for-agents`, renamed). To check for updates: `git clone --depth 1 https://github.com/mattpocock/skills` and diff each `skills/<bucket>/<name>/` against `config/shared/skills/<name>/`. Ignore the upstream em-dash→colon prose sweep and harness-specific tool names already handled locally. Port substantive workflow changes by hand.
- **Shared host shape** lives in `modules/profiles/base-home.nix` plus platform (`darwin-home.nix`, `linux-home.nix`) and role (`work-home.nix`, `personal-home.nix`) profiles; host files import these profiles explicitly.
- **Host-specific logic** lives in `hosts/<name>.nix` and `modules/host-specific/` — no hostname checks in shell files.

## Maintenance rules

- Add a host by editing the `darwinHosts` or `linuxHosts` inventory in `flake.nix`, then add only the role/platform delta under `hosts/` or `modules/host-specific/`.
- Add macOS Homebrew formulae/casks to `modules/homebrew-packages.nix`.
- Add Linux CLI packages to `modules/linux/packages.nix`; Linuxbrew is intentionally not used.
- Add Kubernetes tools on macOS via Homebrew (`modules/homebrew-packages.nix` `kubernetesBrews`, folded into `workBrews`) and on Linux via Nix (`modules/linux/packages.nix` `kubernetesPackages`, gated by `dotfiles.kubernetes.enable`), or a dedicated module such as `modules/k9s.nix`. Both paths follow `dotfiles.kubernetes.enable`, which is false on `personal-mac`.
- Add a package to another Nix module when Home Manager needs it for generated config, shell activation, runtime integration, or platform-specific ownership.
- Run `nix run .#check` before switching hosts; it runs the dotfiles behavior checks (`bootstrap`, `claude-state-jq`, and `pi-installer`), then evaluates each host's activation/system derivation path so a broken `home.file` source or package attr fails fast without a cross-build. Tests and flake checks are executable verification, not model directives.
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

## tmux workspaces

`modules/tmux.nix` supplies the shared configuration on all five hosts. Homebrew owns tmux and Sesh on macOS; Nix owns their Linux packages. Home Manager owns configuration, a pinned TPM source, and the naming plugin's Python/libtmux environment—no user pip installation is needed.

Ghostty runs `tmux new-session -A -s main`: projects normally occupy windows in one persistent `main` session. Closing or disconnecting Ghostty leaves processes running; reopening reconnects. This does **not** restore sessions after a reboot or tmux server exit, and does not launch editors or agents automatically. Ordinary shells and SSH do not auto-attach. In an interactive shell, bare `tmux` replaces the shell with a create-or-attach client for `main`; `tmux` with arguments passes them through unchanged.

Ghostty's native tab/window shortcuts remain unchanged. Tabs attached to the same tmux session share its selected window; they are not independent project views. Use tmux windows to switch projects.

### Keys and appearance

The prefix is **Ctrl+a**. Standard tmux bindings remain available except where overridden below.

| Binding | Action |
| --- | --- |
| prefix → Ctrl+a | Send literal Ctrl+a to the application |
| prefix → t | Pick windows in the current session |
| prefix → o | Sesh's built-in interactive picker with icons and configured directory previews |
| prefix → c | New window in the active pane's directory |
| prefix → % / `\|` | Side-by-side split in that directory |
| prefix → " / - | Stacked split in that directory |
| prefix → h / j / k / l | Select the pane left / down / up / right |
| prefix → H / J / K / L | Resize in that direction by 5 cells; repeatable |
| prefix → < / > | Swap with the previous / next window; repeatable |
| prefix → a | Switch to the last window |
| prefix → Ctrl+p / Ctrl+n | Previous / next window |
| prefix → X | Confirm and kill the current window |
| prefix → r | Reload the generated tmux configuration |
| prefix → Space | Command menu for pane, window, and session actions; no snapshot actions |
| prefix → p / P | Floax floating scratch terminal / Floax menu |
| prefix → F | tmux-fzf action picker |
| prefix → u | Fuzzy URL picker over the last 2,000 scrollback lines |
| prefix → d | Detach without terminating processes |
| prefix → [ | Enter vi copy mode; v selects and y copies |
| prefix → , | Set a manual window name |

Sesh creates secondary sessions on demand with a plain shell; it has no managed project inventory or startup commands. Its native picker handles cancellation and displays icons; `sesh/sesh.toml` restores the tmux/config/zoxide source order, prompt, and eza directory preview command. Floax supplies a persistent `scratch` session while the tmux server runs, not reboot recovery.

Mouse dragging stays within the selected pane and copies on release. In copy mode the wheel scrolls five lines at a time; normal full-screen applications retain mouse reporting. Clipboard mode is **external-only**: tmux's own copies can reach the terminal clipboard, but direct application OSC 52 copies are blocked. This intentionally prevents Pi's direct remote clipboard path from working inside tmux. The `clip <file>` shell helper uses `tmux load-buffer -w` inside tmux and direct OSC 52 outside it. Clipboard delivery still depends on the outer terminal's permissions. Window/pane numbers start at 1; window numbers close gaps when one is removed. History retains 100,000 lines per pane.

Catppuccin Mocha uses rounded numbered window labels on a single top bar, with separate rounded session and short-hostname modules on the right. An empty top pane-border row separates the bar from terminal content; no extra status row is added. `tmux-window-name` supplies shortest unique directory paths and program icons; command arguments are hidden. Known directory-oriented programs include Neovim, Git, pi/Claude, Node/Python, SSH, btop, and k9s; other commands use the plugin's program-name fallback. Shell labels receive their icon from the theme. Manually named windows stay fixed; run `tmux rename-window ""` to return the current window to automatic naming. Shell directory/command changes and pane/window selection refresh labels without a polling daemon. The separate Nerd Font naming plugin is deliberately omitted to avoid competing renamers.

Existing Claude desktop-notification hooks and pi permission bells remain enabled. Native tmux window flags show bells; no agent-state dashboard or phone push-notification replacement is installed.

### Plugin installation and updates

Switch activation installs missing plugins through TPM under `~/.config/tmux/plugins`, then reconciles those writable Git checkouts synchronously:

- `catppuccin/tmux` stays on **v2.3.2**. Edit the declared tag in `config/tmux/tmux.conf` to upgrade it.
- `ofirgall/tmux-window-name`, `omerxx/tmux-floax`, `wfxr/tmux-fzf-url`, and `sainnhe/tmux-fzf` follow their upstream default branches using fast-forward-only updates.
- Activation links Nix's `xre` into the URL plugin's ignored `bin` directory, preventing its first-use download installer.
- Network, install, update, dirty-checkout, and unexpected-origin failures fail activation. Local tracked modifications are never reset or stashed automatically.
- TPM itself is pinned through Nix in `modules/tmux.nix`. No mutable TPM self-update is performed.

Activation uses a temporary, sessionless tmux server; it does not restart sessions or reload a live user server. After switching, load the configuration into an existing server explicitly with `tmux source-file ~/.config/tmux/tmux.conf`, or open tmux normally if no server is running. Never use `tmux kill-server` to reload configuration with unsaved work.

TPM's prefix → I remains available for installation. Prefer a dotfiles switch for updates: TPM's upstream bulk updater does not reliably propagate individual background failures and cannot pull a detached release tag. Plugin checkout updates are **outside Nix-generation rollback**; rolling back a generation does not roll those directories back. There is no automated tmux behavior suite; use the manual checks below after configuration or plugin updates.

### Terminal compatibility and migration

The configuration advertises truecolor, underline styles/colors, extended keys, and OSC 8 hyperlinks for Ghostty, and uses CSI-u extended-key forwarding. Ghostty's existing macOS Cmd+w encoding is unchanged. **Known accepted limitation:** tmux 3.8 converts its Super+w CSI-u sequence to Alt+w, so Neovim's <D-w> mapping does not work through tmux as configured. No private-sequence translation or shortcut remapping is installed. Pi uses automatic hyperlink/image detection and keeps truecolor enabled. Its current renderer intentionally falls back to text for images under tmux; no Kitty mode is forced. Passthrough is enabled separately for Neovim's Snacks image/Mermaid/math rendering. Image input to models is unaffected.

After an approved switch, manually verify:

1. Ghostty reopens the same `main` session, with readable labels and the expected Mocha bar.
2. The window, Sesh, URL, and action pickers, command menu, and Floax scratch terminal behave correctly; pane selection, directory changes, and manual names still work.
3. Copy-mode selections and `clip <file>` reach the clipboard where supported; direct application OSC 52 copies remain blocked as selected.
4. Pi Shift+Enter, Enter, and Alt+Enter remain distinct. Account for the accepted Cmd+w → Alt+w limitation in Neovim.
5. Links open correctly, Neovim image previews render through passthrough, Claude notifications still arrive, and pi bells mark inactive windows.

Herd and Heeler are no longer declared. Before applying this migration, save work in existing Herd sessions: Homebrew's normal cleanup may uninstall the undeclared Herd package. The migration does not stop Herd servers, delete session/plugin/pairing data, disable local integration entries, revoke phone SSH keys, or change SSH/NetBird policy.

**Local integration cleanup is manual and report-only.** The inspected Mac still has `~/.pi/agent/extensions/herdr-agent-state.ts` (pi v9) and `~/.claude/hooks/herdr-agent-state.sh` (Claude v11). Both guard their behavior with Herd environment variables, but remain obsolete artifacts after migration. Review the generated entries and their install markers before disabling/removing anything; do not delete unrelated hooks or settings. The existing Claude settings-copy activation retains its normal behavior of reconciling the live settings file to repository settings when they drift; this migration adds no integration-cleanup action. Heeler phone authorization remains valid until explicitly revoked separately.

## Pi maintenance

Pi uses the upstream managed installer from `https://pi.dev/install.sh`, which pins core dependencies under `~/.pi/agent/install` and exposes `pi` through `~/.local/bin/pi`. Activation installs only when that executable is missing. On the first switch after migration, the installer verifies the managed release before removing the old npm copy from `~/.npm-global`; configuration, credentials, sessions, and extensions under `~/.pi/agent` remain in place. Later switches and flake updates do not upgrade an existing Pi installation. Extension sources in `modules/pi.nix` remain unversioned.

Update the core and extensions explicitly:

```bash
pi update
pi --version
pi update --extensions
# Or update one declared extension:
pi update npm:@gotgenes/pi-permission-system
pi list
npm list --prefix "$HOME/.pi/agent/npm" --depth=0
```

Use `pi update` for the managed core and `pi update --extensions` for extensions. Package updates reconcile installed resources without changing their declarations. Add or remove declarations in `modules/pi.nix`, not through `pi install`, `pi remove`, or `pi config`, which write Home Manager-owned settings. Run the repository checks before switching changed generated settings or MCP wiring. Restart Pi after package updates or changes to subagent `disabledFeatures`; static permission configuration is symlinked from `config/pi/permission-system.json`.

The restore policy asks before worktree-discarding restores. Its narrow staging-only exceptions require an explicit `--` immediately after `--staged` or `-S`, so subsequent pathspecs cannot enable worktree restoration:

```bash
git restore --staged -- <pathspec>
git restore -S -- <pathspec>
```

Other option layouts, including staging-only commands with Git global options, conservatively require confirmation. Permission prompts emit a terminal bell; whether it produces a sound or visual indication depends on the terminal settings.

### Subagents

Pi uses [`pi-subagents`](https://pi.dev/packages/pi-subagents). `modules/pi.nix` loads only its extension and its `pi-subagents` skill; the package prompt templates and `council-mode` skill are filtered out.

- Agents: `subagents.disableBuiltins` hides every bundled agent. The only agents are `scout`, `reviewer`, and `worker`, generated from `config/shared/agents/` into `~/.pi/agent/agents/`, plus `obsidian-second-brain.wiki-vault` on macOS, which the obsidian-second-brain package ships. `dotfiles.pi.vaultAgentModel` sets that agent's model through `subagents.agentOverrides`.
- Generated agents run in the background with fresh context, repository instructions, the shared global `AGENTS.md` (`inheritGlobalContext`; the vault agent gets it through `agentOverrides`), and strict tool allowlists. Background children load the parent's installed extensions, so the permission system and web access also apply inside children.
- `config/pi/subagents.json` is symlinked to `~/.pi/agent/extensions/subagent/config.json`. Direct launches and JavaScript workflow scripts are available; scripts use `runs.run` for sequential work and `runs.all` for parallel work instead of top-level `tasks` and `chain`. Lane-management controls are available for reviewed cleanup, with confirmation required for worktree discard and destructive cleanup. Other optional feature groups, including preflight hints, scheduled runs, and automatic missions, remain disabled.
- `maxSubagentDepth: 1` prevents child delegation. Artifact saving and concurrency use package defaults, as does the 30-minute run deadline for each single-agent launch.
- The reviewer supports fixed-point diff reviews and current-state audits. Only diff reviews require the `code-review` skill and a fixed point.
- No global `APPEND_SYSTEM.md` is managed, and no standing delegation authorization is supplied. Package guidance requires authorization before delegation and one writer per checkout/worktree.
- The package keeps its default `toolActivation: "auto"`, so new sessions may first call `subagents_enable`.

Start a new Pi session after changing `config/pi/subagents.json`; resumed sessions retain previously declared tool definitions. Use `/subagents-doctor` to check the setup.

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
- Darwin hosts with `dotfiles.kubernetes.enable` install the `modify-secret` krew plugin when missing. This depends on upstream network availability.
- Claude and pi MCP servers may launch pinned `npx`/`uvx` packages declared in `modules/mcp-servers.nix`.
- Claude permissions intentionally allow broad research and platform tooling. Treat `config/claude/settings.json` as the trust boundary for tool access.
- pi activation executes the upstream managed installer from `https://pi.dev/install.sh` without interactive prompts when `~/.local/bin/pi` is absent. The installer uses its release lockfile and removes a discovered legacy npm installation only after verifying the new release. Provider auth and MCP OAuth tokens remain runtime state under `~/.pi/` and are not managed by Nix.

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

MIT, see [`LICENSE`](LICENSE). Vendored and adapted shared skills keep their upstream license and copyright beside their source under `config/shared/skills/`. The extracted [obsidian-second-brain](https://github.com/soulwaxx/obsidian-second-brain) package carries its upstream MIT license and attribution.
