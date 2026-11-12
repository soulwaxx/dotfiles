# Store health gate shared by flake apps (bootstrap, clean), the macOS GC and
# optimise daemons, and the Linux nh-clean service. Exits non-zero when store
# contents fail verification or a top-level store path is writable.
{ pkgs }:
pkgs.writeShellScript "verify-nix-store" ''
  if ! ${pkgs.nix}/bin/nix-store --verify --check-contents; then
    echo "Nix store/database inconsistency detected. Do not edit /nix/store directly; repair the reported paths before continuing." >&2
    exit 1
  fi
  writable_store_path="$(${pkgs.findutils}/bin/find /nix/store \
    -mindepth 1 -maxdepth 1 ! -type l ! -name '*.lock' ! -name .links \
    \( -perm -0200 -o -perm -0020 -o -perm -0002 \) -print -quit)"
  if [[ -n "$writable_store_path" ]]; then
    echo "Writable Nix store path detected: $writable_store_path" >&2
    echo "Do not chmod paths under /nix/store; repair it before continuing." >&2
    exit 1
  fi
''
