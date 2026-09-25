#!/usr/bin/env zsh
set -eo pipefail

nvim_functions=${1:?nvim functions path required}
git_functions=${2:?git functions path required}
aliases_file=${3:?aliases path required}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin=$work/bin
log=$work/log
mkdir -p "$bin" "$log" "$work/cwd/nested" "$work/search/nested" "$work/search dir/nested"

cat >"$bin/fd" <<'EOF'
#!/bin/sh
printf '%s|%s\n' "$PWD" "$*" >> "$TEST_LOG/fd"
[ "$*" = '--type f --strip-cwd-prefix' ] || exit 2
printf '%s\n' 'nested/selected file'
EOF

cat >"$bin/fzf" <<'EOF'
#!/bin/sh
printf '%s\n' "$PWD" >> "$TEST_LOG/fzf"
printf '%s\n' "$*" >> "$TEST_LOG/fzf-args"
if [ -n "${FZF_SELECTION:-}" ]; then
  printf '%s\n' "$FZF_SELECTION"
else
  IFS= read -r selection
  printf '%s\n' "$selection"
fi
EOF

cat >"$bin/nvim" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$TEST_LOG/nvim"
EOF

cat >"$bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_LOG/gh"
case "$1" in
  repo) printf '%s\n' test-owner/test-repo ;;
  api) printf '%s\n' "${GH_PROTECTED:-false}" ;;
  *) exit 2 ;;
esac
EOF

cat >"$bin/git" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_LOG/git"
case "$*" in
  'rev-parse --is-inside-work-tree') printf '%s\n' true ;;
  'branch --show-current') printf '%s\n' local ;;
  'remote get-url --push origin') printf '%s\n' git@github.com:test-owner/origin-repo.git ;;
  'remote get-url --push upstream') printf '%s\n' https://github.com/test-owner/upstream-repo.git ;;
  'rev-parse --verify refs/remotes/origin/release') printf '%s\n' deadbeef ;;
  'rev-parse --verify refs/remotes/upstream/feature/release') printf '%s\n' feedface ;;
  'rev-parse --verify main')
    if [ "${GIT_NO_BASE:-}" = 1 ]; then
      exit 1
    fi
    printf '%s\n' main
    ;;
  'rev-parse --verify HEAD^') printf '%s\n' parent ;;
  'rev-parse --abbrev-ref --symbolic-full-name @{u}')
    [ -n "${GIT_PUBLISHED_COMMIT:-}" ] && printf '%s\n' origin/local || exit 1
    ;;
  'rev-list HEAD^..HEAD') printf '%s\n' "${GIT_AMEND_COMMIT:-local}" ;;
  'rev-list HEAD~2..HEAD'|'rev-list main..HEAD') printf '%s\n' published; printf '%s\n' local ;;
  'rev-list --count HEAD') printf '%s\n' 3 ;;
  'merge-base --is-ancestor '* ) [ "$3" = "${GIT_PUBLISHED_COMMIT:-}" ] ;;
  'diff --name-only --diff-filter=U') printf '%s\n' conflict.txt ;;
  'stash list --format=%gd %s') printf '%s\n' 'stash@{0} WIP changes' ;;
  'stash show -p stash@{0}') ;;
  'fetch --prune') [ "${GIT_FETCH_FAIL:-}" != 1 ] ;;
  'for-each-ref --format=%(refname:short) %(upstream:track) refs/heads') printf '%s\n' "${GIT_GONE_REFS:-}" ;;
  'branch -D '*) [ "${3:-}" != "${GIT_DELETE_FAIL:-}" ] ;;
  log\ *|rebase\ *|push\ *|commit\ *|add\ *) ;;
  *)
    printf 'unexpected git invocation: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$bin"/*

export PATH="$bin:$PATH"
export TEST_LOG=$log
source "$nvim_functions"
source "$git_functions"

(
  cd "$work/cwd"
  nvf
)
grep -Fx "$work/cwd|--type f --strip-cwd-prefix" "$log/fd" >/dev/null
grep -Fx "$work/cwd" "$log/fzf" >/dev/null
grep -Fx './nested/selected file' "$log/nvim" >/dev/null

: >"$log/fd"
: >"$log/fzf"
: >"$log/nvim"
nvf "$work/search"
grep -Fx "$work/search|--type f --strip-cwd-prefix" "$log/fd" >/dev/null
grep -Fx "$work/search" "$log/fzf" >/dev/null
grep -Fx "$work/search/nested/selected file" "$log/nvim" >/dev/null

: >"$log/fzf"
: >"$log/fzf-args"
: >"$log/nvim"
export FZF_SELECTION='nested/selected file:42:matched text'
nvgg "$work/search dir"
unset FZF_SELECTION
grep -Fx "$work/search dir" "$log/fzf" >/dev/null
grep -F -- '--disabled' "$log/fzf-args" >/dev/null
grep -F -- "start:reload:printf ''" "$log/fzf-args" >/dev/null
grep -F -- 'change:reload:[ -n {q} ] && rg --line-number --no-heading --color=never --smart-case -- {q} || true' "$log/fzf-args" >/dev/null
grep -Fx '+42' "$log/nvim" >/dev/null
grep -Fx -- '--' "$log/nvim" >/dev/null
grep -Fx "$work/search dir/nested/selected file" "$log/nvim" >/dev/null

: >"$log/git"
: >"$log/gh"
printf 'release\n' | git-push-force release origin
grep -Fx 'remote get-url --push origin' "$log/git" >/dev/null
grep -Fx 'api repos/test-owner/origin-repo/branches/release --jq .protected' "$log/gh" >/dev/null
grep -Fx 'rev-parse --verify refs/remotes/origin/release' "$log/git" >/dev/null
grep -Fx 'push --force-with-lease=refs/heads/release:deadbeef origin local:refs/heads/release' "$log/git" >/dev/null
if grep -Eq '^push --force( |$)' "$log/git"; then
  echo 'git-push-force used raw --force' >&2
  exit 1
fi

: >"$log/git"
: >"$log/gh"
printf 'feature/release\n' | git-push-force feature/release upstream
grep -Fx 'remote get-url --push upstream' "$log/git" >/dev/null
grep -Fx 'api repos/test-owner/upstream-repo/branches/feature%2Frelease --jq .protected' "$log/gh" >/dev/null
if grep -q '^repo view ' "$log/gh"; then
  echo 'git-push-force inferred the repository instead of using the selected remote' >&2
  exit 1
fi
grep -Fx 'rev-parse --verify refs/remotes/upstream/feature/release' "$log/git" >/dev/null
grep -Fx 'push --force-with-lease=refs/heads/feature/release:feedface upstream local:refs/heads/feature/release' "$log/git" >/dev/null

: >"$log/git"
: >"$log/gh"
if GH_PROTECTED=true git-push-force feature/release upstream </dev/null; then
  echo 'git-push-force allowed a protected explicit target branch' >&2
  exit 1
fi
grep -Fx 'api repos/test-owner/upstream-repo/branches/feature%2Frelease --jq .protected' "$log/gh" >/dev/null
if grep -q '^push ' "$log/git"; then
  echo 'git-push-force attempted to push a protected target branch' >&2
  exit 1
fi

strategy_help=$(git-rebase-with-strategy invalid main 2>&1 || true)
printf '%s\n' "$strategy_help" | grep -F 'ours   - Keep the upstream/base side on conflicts' >/dev/null
printf '%s\n' "$strategy_help" | grep -F 'theirs - Keep the rebased branch side on conflicts' >/dev/null

: >"$log/git"
printf 'y\n' | git-rebase-with-strategy ours main
printf 'y\n' | git-rebase-with-strategy theirs main
grep -Fx 'rebase -X ours main' "$log/git" >/dev/null
grep -Fx 'rebase -X theirs main' "$log/git" >/dev/null

conflict_help=$(git-conflicts)
printf '%s\n' "$conflict_help" | grep -F "Use Git's 'ours' side (operation-dependent)" >/dev/null
printf '%s\n' "$conflict_help" | grep -F "Use Git's 'theirs' side (operation-dependent)" >/dev/null
if printf '%s\n' "$conflict_help" | grep -Eq '(your changes|incoming changes)'; then
  echo 'git-conflicts labels operation-dependent sides as yours or incoming' >&2
  exit 1
fi

resolve_help=$(git-resolve-all invalid 2>&1 || true)
printf '%s\n' "$resolve_help" | grep -F "Use Git's 'ours' side for all conflicts (operation-dependent)" >/dev/null
printf '%s\n' "$resolve_help" | grep -F "Use Git's 'theirs' side for all conflicts (operation-dependent)" >/dev/null

for alias in \
  'linux-realign = "cfg-realign && nix-clean-all";' \
  'linux-upgrade = "cfg-upgrade && nix-clean-all";'; do
  grep -F "$alias" "$aliases_file" >/dev/null
done
if ! grep -F 'zshconfig =' "$aliases_file" | grep -F 'modules/zsh/default.nix' >/dev/null; then
  echo 'zshconfig does not open the repository-owned zsh configuration' >&2
  exit 1
fi
if grep -F 'zshconfig =' "$aliases_file" | grep -F '.zshrc' >/dev/null; then
  echo 'zshconfig still opens generated ~/.zshrc' >&2
  exit 1
fi
if ! grep -F 'system-clean = "(failed=0; nix-clean-all || failed=1; cache-clean || failed=1; docker-clean || failed=1; exit $failed)";' "$aliases_file" >/dev/null; then
  echo 'system-clean does not retain failures while attempting every cleanup stage' >&2
  exit 1
fi
system_clean=$(grep '^    system-clean = ' "$aliases_file")
system_clean=${system_clean#*\"}
system_clean=${system_clean%\";}
cleanup_log=$log/system-clean
nix-clean-all() { print -r -- nix-clean-all >>"$cleanup_log"; [[ "$SYSTEM_CLEAN_FAIL" == nix ]] && return 1; }
cache-clean() { print -r -- cache-clean >>"$cleanup_log"; [[ "$SYSTEM_CLEAN_FAIL" == cache ]] && return 1; }
docker-clean() { print -r -- docker-clean >>"$cleanup_log"; [[ "$SYSTEM_CLEAN_FAIL" == docker ]] && return 1; }
for failed_stage in nix cache docker; do
  : >"$cleanup_log"
  if SYSTEM_CLEAN_FAIL=$failed_stage eval "$system_clean"; then
    echo "system-clean succeeded when $failed_stage failed" >&2
    exit 1
  fi
  printf '%s\n' nix-clean-all cache-clean docker-clean | diff - "$cleanup_log" >/dev/null
done
unset SYSTEM_CLEAN_FAIL

: >"$log/git"
: >"$log/fzf-args"
printf '4\n' | git-stash-browse
# The no-colon display format makes {1} a valid stash revision in the preview.
grep -Fx -- '--preview=git stash show -p {1} --preview-window=right:60%' "$log/fzf-args" >/dev/null
grep -Fx 'stash list --format=%gd %s' "$log/git" >/dev/null
grep -Fx 'stash show -p stash@{0}' "$log/git" >/dev/null

: >"$log/git"
export GIT_PUBLISHED_COMMIT=published
export GIT_AMEND_COMMIT=published
if printf 'no\n' | git-amend; then
  echo 'git-amend allowed a published commit rewrite without confirmation' >&2
  exit 1
fi
grep -Fx 'rev-list HEAD^..HEAD' "$log/git" >/dev/null
if grep -Fx 'commit --amend --no-edit' "$log/git" >/dev/null; then
  echo 'git-amend rewrote history after a declined confirmation' >&2
  exit 1
fi

: >"$log/git"
printf 'rewrite\ny\n' | git-squash 2
grep -Fx 'rev-list HEAD~2..HEAD' "$log/git" >/dev/null
grep -Fx 'rebase -i HEAD~2' "$log/git" >/dev/null

: >"$log/git"
printf 'rewrite\n' | git-rebase-interactive main
grep -Fx 'rev-list main..HEAD' "$log/git" >/dev/null
grep -Fx 'rebase -i main' "$log/git" >/dev/null
unset GIT_PUBLISHED_COMMIT GIT_AMEND_COMMIT

: >"$log/git"
export GIT_NO_BASE=1
if git-compare >/dev/null 2>&1; then
  echo 'git-compare continued after failing to determine its base branch' >&2
  exit 1
fi
if grep -q '^log ' "$log/git"; then
  echo 'git-compare invoked git log with an unresolved base branch' >&2
  exit 1
fi
unset GIT_NO_BASE

: >"$log/git"
export GIT_GONE_REFS=$'current [gone]\nworktree [gone]'
export GIT_DELETE_FAIL=worktree
if prune_output=$(printf 'y\n' | git-prune-local); then
  echo 'git-prune-local reported a failed branch deletion as successful' >&2
  exit 1
fi
printf '%s\n' "$prune_output" | grep -F 'Cleanup incomplete.' >/dev/null
grep -Fx 'branch -D current' "$log/git" >/dev/null
grep -Fx 'branch -D worktree' "$log/git" >/dev/null
if grep -Eq '^branch -D [*+]$' "$log/git"; then
  echo 'git-prune-local treated a branch display marker as a branch name' >&2
  exit 1
fi
unset GIT_GONE_REFS GIT_DELETE_FAIL

: >"$log/git"
export GIT_FETCH_FAIL=1
if git-prune-local >/dev/null 2>&1; then
  echo 'git-prune-local continued after fetch failure' >&2
  exit 1
fi
if grep -q '^for-each-ref ' "$log/git"; then
  echo 'git-prune-local inspected branches after fetch failure' >&2
  exit 1
fi
unset GIT_FETCH_FAIL
