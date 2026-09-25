#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/soulwaxx/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
if [[ "$DOTFILES_DIR" != /* ]]; then
  DOTFILES_DIR="$HOME/$DOTFILES_DIR"
fi
export DOTFILES_DIR
HOST="${1:-}"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

repo_identity() {
  local repo="${1%/}"
  repo="${repo%.git}"
  case "$repo" in
    git@*:* )
      repo="${repo#git@}"
      repo="${repo/:/\/}"
      ;;
    *://* )
      repo="${repo#*://}"
      repo="${repo#*@}"
      ;;
  esac
  printf '%s\n' "$repo"
}

if [[ -z "$HOST" ]]; then
  echo "Usage: bash bootstrap.sh <host-name>"
  echo ""
  echo "Run 'nix run .#hosts' from an existing checkout to list available hosts."
  exit 1
fi

# Run as your normal user, not root/sudo: Homebrew's installer refuses to run
# as root, and root's own environment usually doesn't have `nix` on PATH even
# when it's fully installed (root never sources /etc/{bashrc,zshrc}), which
# makes the check in Step 2 below misfire. Steps that need privileges call
# sudo internally.
if [[ "$(id -u)" -eq 0 ]]; then
  error "Run this as your normal user, e.g.: bash bootstrap.sh $HOST (it uses sudo internally where needed)."
fi

CURRENT_USER="$(id -un)"
OS="$(uname -s)"

# Step 1: Verify bootstrap dependencies are available (not guaranteed on minimal Linux installs)
for cmd in git curl; do
  command -v "$cmd" &>/dev/null || error "$cmd is required but not found. Install $cmd first."
done

# Step 2: Install Nix
NIX_DAEMON_PROFILE=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# `command -v nix` alone isn't enough: a fresh install only updates PATH for
# shells started after it (or via the sourcing below), so re-running this
# script in the same terminal right after installing looks exactly like "no
# Nix" and re-triggers the installer against a Nix that's already there. That
# collides with leftover state (volume, shell-profile backups) from the first
# run and can leave things half-fixed. Check for the binary on disk too.
if command -v nix &>/dev/null; then
  info "Nix already installed: $(nix --version)"
elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
  info "Nix is installed but not on PATH in this shell; sourcing profile..."
  # shellcheck source=/dev/null
  . "$NIX_DAEMON_PROFILE"
  info "Nix already installed: $(nix --version)"
else
  info "Installing Nix (upstream nixos.org installer)..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://nixos.org/nix/install | sh -s -- --daemon --yes
  if [[ -f "$NIX_DAEMON_PROFILE" ]]; then
    # Source the daemon profile so `nix` is on PATH for the rest of this session
    # shellcheck source=/dev/null
    . "$NIX_DAEMON_PROFILE"
  fi
  info "Nix installed successfully"
fi

configure_linux_nix_trust() {
  local trusted_users
  trusted_users="$(nix --extra-experimental-features nix-command config show trusted-users 2>/dev/null)" \
    || error "Could not read the effective trusted-users setting."

  if printf '%s\n' "$trusted_users" | tr ' ' '\n' | grep -qxF "$CURRENT_USER"; then
    info "$CURRENT_USER is already a trusted Nix user"
  else
    trusted_users="${trusted_users:-root}"
    info "Adding $CURRENT_USER to trusted-users in /etc/nix/nix.conf..."
    printf 'trusted-users = %s %s\n' "$trusted_users" "$CURRENT_USER" \
      | sudo tee -a /etc/nix/nix.conf >/dev/null \
      || error "Could not update trusted-users in /etc/nix/nix.conf."
  fi

  if command -v systemctl &>/dev/null; then
    sudo systemctl restart nix-daemon \
      || error "Could not restart nix-daemon after verifying trusted-users."
  else
    error "No systemctl found. Restart nix-daemon manually, then rerun bootstrap."
  fi
}

homebrew_bin() {
  for candidate in \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew
  do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

add_homebrew_to_path() {
  if [[ -d /opt/homebrew/bin ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
  elif [[ -d /usr/local/bin ]]; then
    export PATH="/usr/local/bin:$PATH"
  fi
}

install_homebrew_if_needed() {
  if brew_path="$(homebrew_bin)"; then
    info "Homebrew already installed: $("$brew_path" --version | head -n 1)"
    add_homebrew_to_path
    return 0
  fi

  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  add_homebrew_to_path
  brew_path="$(homebrew_bin)" || error "Homebrew installation finished, but brew was not found in the expected paths."

  # Make brew available to the current non-login bootstrap shell.
  eval "$("$brew_path" shellenv)"
  info "Homebrew installed: $(brew --version | head -n 1)"
}

# Step 3: Clone dotfiles
if [[ -d "$DOTFILES_DIR" ]]; then
  actual_repo="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)" \
    || error "$DOTFILES_DIR exists but is not a Git checkout with an origin remote."
  if [[ "$(repo_identity "$actual_repo")" != "$(repo_identity "$DOTFILES_REPO")" ]]; then
    error "$DOTFILES_DIR uses origin '$actual_repo', expected '$DOTFILES_REPO'. Remove it or choose a different DOTFILES_DIR."
  fi
  [[ -f "$DOTFILES_DIR/flake.nix" ]] \
    || error "$DOTFILES_DIR is missing flake.nix; repair the checkout before rerunning bootstrap."
  info "Dotfiles repo already exists at $DOTFILES_DIR"
else
  info "Cloning dotfiles to $DOTFILES_DIR..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR" \
    || error "Failed to clone dotfiles repo. Check network connectivity and that $DOTFILES_REPO is reachable."
fi

# Step 4: Read host metadata from flake.nix. This keeps flake.nix as the single
# source of truth for host names, target systems, usernames, and switch apps.
HOSTS_OUTPUT="$(nix --extra-experimental-features 'nix-command flakes' run "path:$DOTFILES_DIR#hosts")"
if ! HOST_LINE="$(printf '%s\n' "$HOSTS_OUTPUT" | awk -v host="$HOST" 'NR > 1 && $1 == host { print; found=1 } END { exit found ? 0 : 1 }')"; then
  valid_hosts="$(printf '%s\n' "$HOSTS_OUTPUT" | awk 'NR > 1 { hosts = hosts sep $1; sep = ", " } END { print hosts }')"
  error "Unknown host '$HOST'. Valid hosts: $valid_hosts"
fi

read -r _host_name HOST_SYSTEM HOST_USER SWITCH_APP HOST_ROLE <<< "$HOST_LINE"

if [[ "$CURRENT_USER" != "$HOST_USER" ]]; then
  error "Host '$HOST' expects user '$HOST_USER', but bootstrap is running as '$CURRENT_USER'."
fi

case "$HOST_SYSTEM" in
  *-darwin)
    [[ "$OS" == "Darwin" ]] || error "Host '$HOST' targets $HOST_SYSTEM but this machine is Linux."
    ;;
  *-linux)
    [[ "$OS" != "Darwin" ]] || error "Host '$HOST' targets $HOST_SYSTEM but this machine is macOS."
    ;;
  *)
    error "Host '$HOST' has unsupported target system '$HOST_SYSTEM'."
    ;;
esac

# Ask for untracked host files before the first switch: activation reads the
# Git identities from them to build ~/.ssh/allowed_signers.
bash "$DOTFILES_DIR/local-files.sh" "$HOST_ROLE" --prompt

# Step 5: Configure platform prerequisites before the first switch.
if [[ "$OS" == "Darwin" ]]; then
  # A damaged reinstall can leave /nix working for the current session while
  # silently omitting the plumbing that makes it survive a reboot.
  # Tests override the root because Darwin builds expose these host paths.
  nix_plumbing_root="${BOOTSTRAP_NIX_PLUMBING_ROOT:-}"
  missing=()
  { [[ -f "$nix_plumbing_root/etc/synthetic.conf" ]] && grep -q '^nix$' "$nix_plumbing_root/etc/synthetic.conf"; } || missing+=("/etc/synthetic.conf")
  { [[ -f "$nix_plumbing_root/etc/fstab" ]] && awk '$2 == "/nix" { found=1 } END { exit !found }' "$nix_plumbing_root/etc/fstab"; } || missing+=("/etc/fstab")
  [[ -f "$nix_plumbing_root/Library/LaunchDaemons/org.nixos.darwin-store.plist" ]] || missing+=("org.nixos.darwin-store LaunchDaemon")
  [[ -f "$nix_plumbing_root/Library/LaunchDaemons/org.nixos.nix-daemon.plist" ]] || missing+=("org.nixos.nix-daemon LaunchDaemon")
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Nix volume mount config incomplete (missing: ${missing[*]}). Repair the upstream Nix installation before rerunning bootstrap."
  fi

  if ! sudo launchctl list 2>/dev/null | grep -q org.nixos.nix-daemon; then
    warn "nix-daemon is not loaded; attempting to load it..."
    sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.nix-daemon.plist \
      || error "Could not load nix-daemon; check /Library/LaunchDaemons/org.nixos.nix-daemon.plist"
    info "nix-daemon loaded"
  fi
fi

info "Checking Nix store consistency..."
if ! nix-store --verify --check-contents; then
  error "Nix store/database inconsistency detected. Do not edit /nix/store directly. Run 'nix-store --verify --check-contents' and repair the reported paths before rerunning bootstrap."
fi

if [[ "$OS" == "Darwin" ]]; then
  install_homebrew_if_needed
else
  configure_linux_nix_trust
fi

# Step 6: Build and switch
info "Building configuration for host: $HOST"

if [[ "$OS" == "Darwin" ]]; then
  info "Detected macOS — using the flake-locked nix-darwin bootstrap app"
  nix --extra-experimental-features 'nix-command flakes' \
    run "path:$DOTFILES_DIR#bootstrap-$HOST"
else
  info "Detected Linux — using Home Manager via flake app"
  # Runs the named switch app defined in flake.nix so home-manager is sourced
  # from the flake's own pinned input (flake.lock), not the Nix registry.
  nix --extra-experimental-features 'nix-command flakes' \
    run "path:$DOTFILES_DIR#$SWITCH_APP"
fi

echo ""
info "Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (or run: exec zsh)"
echo "  2. For future updates: cd $DOTFILES_DIR && nix run .#$SWITCH_APP"
echo ""
echo "Rollback if needed:"
if [[ "$OS" == "Darwin" ]]; then
  echo "  darwin-rebuild switch --rollback"
  echo "  # List generations: nix-env --list-generations --profile /nix/var/nix/profiles/system"
else
  echo "  home-manager generations"
  echo "  home-manager switch --generation <N>"
fi
