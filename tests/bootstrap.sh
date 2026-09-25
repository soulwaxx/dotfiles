#!/usr/bin/env bash
set -euo pipefail

bootstrap=${1:?usage: bootstrap.sh BOOTSTRAP_SCRIPT LOCAL_FILES_SCRIPT}
local_files=${2:?usage: bootstrap.sh BOOTSTRAP_SCRIPT LOCAL_FILES_SCRIPT}
base_path=$PATH

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

write_stub() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
}

make_stubs() {
  local bin=$1
  mkdir -p "$bin"

  write_stub "$bin/id" <<'EOF'
case "${1:-}" in
  -u) printf '1000\n' ;;
  -un) printf '%s\n' "${TEST_USER:?}" ;;
  *) exit 2 ;;
esac
EOF

  write_stub "$bin/uname" <<'EOF'
printf '%s\n' "${TEST_OS:-Linux}"
EOF

  write_stub "$bin/nix-store" <<'EOF'
[[ "$*" == "--verify --check-contents" ]] || exit 2
exit "${STORE_STATUS:-0}"
EOF

  write_stub "$bin/nix" <<'EOF'
case "$*" in
  --version)
    printf 'nix (Nix) test\n'
    ;;
  *"config show trusted-users"*)
    printf '%s\n' "${TRUSTED_USERS:-root}"
    ;;
  *"#hosts"*)
    printf 'host\tsystem\tuser\tswitch-app\trole\n'
    system=${HOST_SYSTEM:-}
    if [[ -z "$system" && "${TEST_OS:-Linux}" == "Darwin" ]]; then
      system=aarch64-darwin
    elif [[ -z "$system" ]]; then
      system=x86_64-linux
    fi
    printf 'test-host\t%s\t%s\tswitch-test\t%s\n' "$system" "${HOST_USER:?}" "${HOST_ROLE:-personal}"
    ;;
  *"#switch-test"*)
    printf 'switched\n' >> "${TEST_LOG:?}/nix"
    ;;
  *)
    printf 'unexpected nix invocation: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

  write_stub "$bin/git" <<'EOF'
if [[ "$*" == *"remote get-url origin"* ]]; then
  printf '%s\n' "${ACTUAL_REPO:?}"
elif [[ "${1:-}" == config && "${2:-}" == --file ]]; then
  PATH=${BASE_PATH:?} exec git "$@"
else
  printf 'unexpected git invocation: %s\n' "$*" >&2
  exit 2
fi
EOF

  write_stub "$bin/curl" <<'EOF'
exit 0
EOF

  write_stub "$bin/systemctl" <<'EOF'
exit 0
EOF

  write_stub "$bin/sudo" <<'EOF'
printf '%s\n' "$*" >> "${TEST_LOG:?}/sudo"
if [[ "${1:-}" == "tee" ]]; then
  cat > "$TEST_LOG/trusted-users"
fi
EOF

  chmod +x "$bin"/*
}

run_case() {
  local name=$1
  local expected_status=$2
  shift 2

  local root="$tmp/$name"
  local home="$root/home"
  local checkout="$home/dotfiles"
  local log="$root/log"
  local bin="$root/bin"
  mkdir -p "$checkout" "$log"
  touch "$checkout/flake.nix"
  cp "$local_files" "$checkout/local-files.sh"
  if declare -F "setup_${name//-/_}" >/dev/null; then
    "setup_${name//-/_}" "$home"
  fi
  make_stubs "$bin"

  set +e
  env \
    PATH="$bin:$base_path" \
    BASE_PATH="$base_path" \
    BOOTSTRAP_TTY=/dev/null \
    HOME="$home" \
    TEST_LOG="$log" \
    TEST_USER=testuser \
    TEST_OS=Linux \
    HOST_USER=testuser \
    ACTUAL_REPO=https://github.com/soulwaxx/dotfiles.git \
    TRUSTED_USERS='root testuser' \
    STORE_STATUS=0 \
    DOTFILES_DIR="$checkout" \
    "$@" \
    bash "$bootstrap" test-host > "$log/output" 2>&1
  local status=$?
  set -e

  if [[ $status -ne $expected_status ]]; then
    cat "$log/output" >&2
    printf '%s: expected status %s, got %s\n' "$name" "$expected_status" "$status" >&2
    exit 1
  fi
}

run_case custom-repo 0 \
  DOTFILES_REPO=git@github.com:fork/dotfiles.git \
  ACTUAL_REPO=https://github.com/fork/dotfiles
[[ -s "$tmp/custom-repo/log/nix" ]]
[[ ! -e "$tmp/custom-repo/log/trusted-users" ]]
grep -qxF 'systemctl restart nix-daemon' "$tmp/custom-repo/log/sudo"

run_case trust-merge 0 \
  TRUSTED_USERS='root admin @builders'
grep -qxF 'trusted-users = root admin @builders testuser' "$tmp/trust-merge/log/trusted-users"
grep -qxF 'systemctl restart nix-daemon' "$tmp/trust-merge/log/sudo"

run_case trust-existing 0 \
  TRUSTED_USERS='root admin testuser'
[[ ! -e "$tmp/trust-existing/log/trusted-users" ]]
grep -qxF 'systemctl restart nix-daemon' "$tmp/trust-existing/log/sudo"

run_case wrong-user 1 HOST_USER=someone-else
[[ ! -e "$tmp/wrong-user/log/sudo" ]]
grep -qF "expects user 'someone-else'" "$tmp/wrong-user/log/output"

run_case wrong-platform 1 TEST_OS=Darwin HOST_SYSTEM=x86_64-linux
[[ ! -e "$tmp/wrong-platform/log/sudo" ]]
grep -qF 'targets x86_64-linux but this machine is macOS' "$tmp/wrong-platform/log/output"

run_case unhealthy-store 1 STORE_STATUS=1
grep -qF 'Nix store/database inconsistency detected' "$tmp/unhealthy-store/log/output"
[[ ! -e "$tmp/unhealthy-store/log/nix" ]]

run_case wrong-origin 1 ACTUAL_REPO=https://github.com/other/dotfiles.git
grep -qF "uses origin 'https://github.com/other/dotfiles.git'" "$tmp/wrong-origin/log/output"

run_case darwin-incomplete-plumbing 1 \
  TEST_OS=Darwin \
  BOOTSTRAP_NIX_PLUMBING_ROOT="$tmp/darwin-incomplete-plumbing/system-root"
grep -qF 'Nix volume mount config incomplete' "$tmp/darwin-incomplete-plumbing/log/output"
[[ ! -e "$tmp/darwin-incomplete-plumbing/log/nix" ]]

# Git identity files: prompts write missing keys, keep existing ones, and never
# block the switch when no answer is available.
identity() { git config --file "$1" --get "$2"; }
mode() { stat -c %a "$1"; }

run_case no-tty 0
[[ -s "$tmp/no-tty/log/nix" ]]
[[ ! -e "$tmp/no-tty/home/.gitconfig.personal" ]]
grep -qF '.gitconfig.personal lacks user.name user.email user.username' "$tmp/no-tty/log/output"
grep -qF '.secrets is missing' "$tmp/no-tty/log/output"
if grep -qF '.gitconfig.local' "$tmp/no-tty/log/output"; then exit 1; fi

printf 'Personal Name\npersonal@example.com\npersonal-gh\n' > "$tmp/personal-answers"
run_case personal-prompt 0 BOOTSTRAP_TTY="$tmp/personal-answers"
p="$tmp/personal-prompt/home/.gitconfig.personal"
[[ "$(identity "$p" user.name)" == 'Personal Name' ]]
[[ "$(identity "$p" user.email)" == personal@example.com ]]
[[ "$(identity "$p" user.username)" == personal-gh ]]
[[ "$(mode "$p")" == 600 ]]
[[ ! -e "$tmp/personal-prompt/home/.gitconfig.local" ]]
if grep -qF 'lacks' "$tmp/personal-prompt/log/output"; then exit 1; fi

printf 'P\np@example.com\np-gh\nW\nw@example.com\nw-gh\n' > "$tmp/work-answers"
run_case work-prompt 0 HOST_ROLE=work BOOTSTRAP_TTY="$tmp/work-answers"
[[ "$(identity "$tmp/work-prompt/home/.gitconfig.personal" user.email)" == p@example.com ]]
w="$tmp/work-prompt/home/.gitconfig.local"
[[ "$(identity "$w" user.email)" == w@example.com ]]
[[ "$(identity "$w" user.username)" == w-gh ]]
[[ "$(mode "$w")" == 600 ]]
grep -qF '.aws/config is missing' "$tmp/work-prompt/log/output"
grep -qF 'skills/create-aws-account is missing' "$tmp/work-prompt/log/output"

setup_partial_identity() {
  git config --file "$1/.gitconfig.personal" user.name 'Kept Name'
  git config --file "$1/.gitconfig.personal" user.email kept@example.com
  chmod 644 "$1/.gitconfig.personal"
}
printf 'added-gh\n' > "$tmp/partial-answers"
run_case partial-identity 0 BOOTSTRAP_TTY="$tmp/partial-answers"
p="$tmp/partial-identity/home/.gitconfig.personal"
[[ "$(identity "$p" user.name)" == 'Kept Name' ]]
[[ "$(identity "$p" user.email)" == kept@example.com ]]
[[ "$(identity "$p" user.username)" == added-gh ]]
[[ "$(mode "$p")" == 600 ]]

run_case unknown-role 1 HOST_ROLE=shared
grep -qF "unknown host role 'shared'" "$tmp/unknown-role/log/output"
[[ ! -e "$tmp/unknown-role/log/nix" ]]

if grep -qF 'github:nix-darwin/nix-darwin/master' "$bootstrap"; then
  echo 'bootstrap uses an unlocked nix-darwin runner' >&2
  exit 1
fi

# The assertion intentionally matches the literal runtime variables.
# shellcheck disable=SC2016
grep -qF 'run "path:$DOTFILES_DIR#bootstrap-$HOST"' "$bootstrap"
