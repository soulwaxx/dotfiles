#!/usr/bin/env zsh
# ============================================================================
# GIT WORKFLOW FUNCTIONS
# ============================================================================
# Professional git workflow functions for commit management, rebasing,
# conflict resolution, and branch operations.
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Color helpers (TTY only)
_git_color_init() {
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        _git_c_reset="$(tput sgr0)"
        _git_c_bold="$(tput bold)"
        _git_c_red="$(tput setaf 1)"
        _git_c_green="$(tput setaf 2)"
        _git_c_yellow="$(tput setaf 3)"
        _git_c_blue="$(tput setaf 4)"
        _git_c_cyan="$(tput setaf 6)"
    else
        _git_c_reset=""
        _git_c_bold=""
        _git_c_red=""
        _git_c_green=""
        _git_c_yellow=""
        _git_c_blue=""
        _git_c_cyan=""
    fi
}
_git_color_init

_git_header() { printf "%s%s%s%s\n" "$_git_c_bold" "$_git_c_cyan" "$*" "$_git_c_reset"; }
_git_info() { printf "%s%s%s\n" "$_git_c_blue" "$*" "$_git_c_reset"; }
_git_success() { printf "%s%s%s\n" "$_git_c_green" "$*" "$_git_c_reset"; }
_git_warn() { printf "%s%s%s\n" "$_git_c_yellow" "$*" "$_git_c_reset"; }
_git_error() { printf "%s%s%s\n" "$_git_c_red" "$*" "$_git_c_reset" >&2; }
_git_prompt() { printf "%s%s%s" "$_git_c_bold" "$*" "$_git_c_reset"; }

# Require fzf for interactive helpers
_git_require_fzf() {
    if ! command -v fzf &> /dev/null; then
        _git_error "Error: fzf not installed"
        return 1
    fi
    return 0
}

# Require a git repository
_git_require_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        _git_error "Error: not a git repository"
        return 1
    fi
    return 0
}

# Helper function to detect the default base branch
_git_get_base_branch() {
    local specified_branch="$1"

    # If user specified a branch, use it
    if [[ -n "$specified_branch" ]]; then
        if git rev-parse --verify "$specified_branch" &>/dev/null; then
            echo "$specified_branch"
            return 0
        else
            _git_error "Error: Branch '$specified_branch' does not exist"
            return 1
        fi
    fi

    local current_branch
    current_branch=$(git branch --show-current)

    # Try to get default branch from remote
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    # If we're on the default branch, use the remote tracking branch instead
    if [[ -n "$default_branch" && "$current_branch" == "$default_branch" ]]; then
        if git rev-parse --verify "origin/$default_branch" &>/dev/null; then
            echo "origin/$default_branch"
            return 0
        fi
    fi

    # If default branch exists locally and we're not on it, use it
    if [[ -n "$default_branch" ]] && git rev-parse --verify "$default_branch" &>/dev/null; then
        echo "$default_branch"
        return 0
    fi

    # Fallback: check common branch names, prefer remote tracking branches if on that branch
    for branch in main master develop development; do
        if [[ "$current_branch" == "$branch" ]] && git rev-parse --verify "origin/$branch" &>/dev/null; then
            echo "origin/$branch"
            return 0
        elif git rev-parse --verify "$branch" &>/dev/null; then
            echo "$branch"
            return 0
        fi
    done

    _git_error "Error: Could not determine base branch"
    return 1
}

_git_current_branch() {
    local branch
    branch=$(git branch --show-current)
    if [[ -z "$branch" ]]; then
        _git_error "Error: detached HEAD (no current branch)"
        return 1
    fi
    echo "$branch"
}

# True when HEAD is already contained in its upstream (i.e. nothing local to rewrite).
_git_head_is_published() {
    local upstream
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || return 1
    git merge-base --is-ancestor HEAD "$upstream" 2>/dev/null
}

_git_github_repo_for_remote() {
    local remote="$1" remote_url repo
    remote_url=$(git remote get-url --push "$remote" 2>/dev/null) || return 1

    case "$remote_url" in
        git@github.com:*|git://github.com/*)
            repo="${remote_url#*github.com[:/]}"
            ;;
        ssh://git@github.com/*|https://github.com/*|http://github.com/*)
            repo="${remote_url#*github.com/}"
            ;;
        *) return 1 ;;
    esac
    repo="${repo%.git}"
    [[ "$repo" == */* ]] || return 1
    print -r -- "$repo"
}

_git_require_not_protected_branch() {
    local branch="${1:-}" remote="${2:-}" repo protected api_branch
    if [[ -z "$branch" ]]; then
        branch=$(_git_current_branch) || return 1
    fi

    # Check even when local commits are ahead: a force push can still rewrite
    # the target remote branch. For an explicit remote, resolve its push URL
    # instead of asking gh to infer the repository from the current checkout.
    if ! command -v gh &>/dev/null; then
        return 0
    fi
    if [[ -n "$remote" ]]; then
        repo=$(_git_github_repo_for_remote "$remote") || return 0
    else
        repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || return 0
    fi
    [[ -n "$repo" ]] || return 0

    # GitHub's branch path parameter treats slashes as path separators.
    api_branch="${branch//\//%2F}"
    protected=$(gh api "repos/${repo}/branches/${api_branch}" --jq '.protected' 2>/dev/null)
    if [[ "$protected" == "true" ]]; then
        _git_error "Error: refusing to rewrite protected branch '$branch' (protected on GitHub)"
        return 1
    fi
}

_git_confirm_if_published() {
    local rewrite_range="$1" upstream commit
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || return 0

    # A branch may have an unpushed tip atop published commits. Check every
    # commit this operation will rewrite, rather than treating that tip as a
    # blanket exemption from confirmation.
    local commits
    commits=$(git rev-list "$rewrite_range") || return 1
    for commit in ${(f)commits}; do
        [[ -z "$commit" ]] && continue
        if git merge-base --is-ancestor "$commit" "$upstream" 2>/dev/null; then
            _git_warn "The rewrite range includes published history ($upstream)."
            _git_prompt "Type 'rewrite' to continue rewriting published history: "
            local response
            read -r response
            [[ "$response" == "rewrite" ]] || { _git_warn "Cancelled."; return 1; }
            return 0
        fi
    done
}

_git_require_safe_rewrite() {
    local rewrite_range="$1"
    _git_require_not_protected_branch || return 1
    _git_confirm_if_published "$rewrite_range" || return 1
}

_git_last_commit_rewrite_range() {
    if git rev-parse --verify HEAD^ &>/dev/null; then
        echo "HEAD^..HEAD"
    else
        echo "HEAD"
    fi
}

_git_confirm() {
    local _reply
    _git_prompt "$1"
    read -r _reply
    [[ "$_reply" =~ ^[Yy]$ ]]
}

# ============================================================================
# BRANCH MANAGEMENT
# ============================================================================

# Interactive branch deletion with fzf
git-branch-delete() {
    _git_require_repo || return 1
    _git_require_fzf || return 1

    local delete_flag="-d"
    if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
        delete_flag="-D"
    fi

    local current_branch
    current_branch=$(_git_current_branch) || return 1
    local branches
    branches=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -v "^${current_branch}$")

    if [[ -z "$branches" ]]; then
        _git_warn "No other local branches to delete."
        return 0
    fi

    local selection
    selection=$(echo "$branches" | fzf --multi --preview="git log {} --")
    [[ -z "$selection" ]] && return 0

    echo "$selection" | while read -r branch; do
        git branch "$delete_flag" "$branch" || \
            _git_warn "Could not delete '$branch' safely; rerun 'git-branch-delete --force' if you intend to discard it."
    done
}

# Clean up local branches that were deleted on remote
git-prune-local() {
    _git_require_repo || return 1
    _git_info "Fetching and pruning remote references..."
    if ! git fetch --prune; then
        _git_error "Failed to fetch and prune remote references."
        return 1
    fi

    printf "\n"
    _git_header "Finding local branches that have been deleted on remote..."

    # Use plumbing rather than `git branch -vv`: its leading current-branch
    # and worktree markers are presentation details, not branch names.
    local gone_output
    if ! gone_output=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads); then
        _git_error "Failed to inspect local branches."
        return 1
    fi
    local -a gone_branches
    local branch tracking
    while IFS=' ' read -r branch tracking; do
        [[ "$tracking" == "[gone]" ]] && gone_branches+=("$branch")
    done <<< "$gone_output"

    if (( ${#gone_branches[@]} == 0 )); then
        _git_success "No local branches to delete - all clean!"
        return 0
    fi

    _git_warn "The following branches will be deleted:"
    printf "%s\n" "${gone_branches[@]}"

    # Ask for confirmation
    printf "\n"
    if _git_confirm "Delete these branches? (y/N): "; then
        local failed=0
        for branch in "${gone_branches[@]}"; do
            if git branch -D "$branch"; then
                _git_success "Deleted: $branch"
            else
                _git_error "Could not delete '$branch'."
                failed=1
            fi
        done
        printf "\n"
        if (( failed )); then
            _git_warn "Cleanup incomplete."
            return 1
        fi
        _git_success "Cleanup complete!"
    else
        _git_warn "Cancelled - no branches deleted."
    fi
}

# Compare two branches side by side
git-compare() {
    _git_require_repo || return 1
    local branch1="${1:-HEAD}"
    local branch2
    if [[ -n "${2:-}" ]]; then
        branch2="$2"
    else
        branch2=$(_git_get_base_branch) || return 1
    fi

    _git_header "Commits in $branch1 but not in $branch2:"
    git log "$branch2".."$branch1" --oneline --graph --color

    printf "\n"
    _git_header "═══════════════════════════════════════"
    printf "\n"

    _git_header "Commits in $branch2 but not in $branch1:"
    git log "$branch1".."$branch2" --oneline --graph --color
}

# ============================================================================
# HISTORY & VISUALIZATION
# ============================================================================

# Interactive commit history viewer with fzf
git-log() {
    _git_require_repo || return 1
    _git_require_fzf || return 1
    git log --graph --color=always \
        --format="%C(auto)%h %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --tiebreak=index \
        --preview='git show --color=always {1}' \
        --preview-window='right:60%:wrap' \
        --bind "ctrl-d:preview-page-down" \
        --bind "ctrl-u:preview-page-up" \
        --bind "ctrl-f:preview-down" \
        --bind "ctrl-b:preview-up" \
        --bind "ctrl-m:execute:
                (grep -o '[a-f0-9]\{7\}' | head -1 |
                xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
                {}
FZF-EOF" \
        --header='CTRL-D/U: page down/up | CTRL-F/B: scroll | CTRL-M: full view | ESC: quit'
}

# Show clean commit history for current branch
git-history() {
    _git_require_repo || return 1
    local base_branch
    base_branch=$(_git_get_base_branch "$1") || return 1

    _git_header "Commits on current branch (diverged from $base_branch):"
    printf "\n"
    git log "$base_branch"..HEAD --oneline --graph --decorate --color

    _git_header "─────────────────────────────────────────"
    local commit_count
    commit_count=$(git rev-list --count "$base_branch"..HEAD)
    _git_info "Total commits: $commit_count"
}

# ============================================================================
# COMMIT OPERATIONS
# ============================================================================

# Quick commit with editor (shows what will be committed first)
git-commit-verbose() {
    _git_require_repo || return 1
    _git_header "Files to be committed:"
    git status --short
    _git_header "─────────────────────────────────────────"
    _git_info "Opening editor for commit message..."
    _git_info "Format:"
    printf "%s\n" "  Line 1: Subject (50 chars)"
    printf "%s\n" "  Line 2: BLANK"
    printf "%s\n" "  Line 3+: Details (wrap at 72 chars)"
    _git_header "─────────────────────────────────────────"
    printf "\n"
    git commit -v "$@"  # -v shows diff in editor
}

# Commit with template pre-filled
git-commit-template() {
    _git_require_repo || return 1
    local commit_template
    commit_template=$(cat <<'EOF'
# Title: Brief summary (50 chars or less)


# Why this change is needed:
# -

# What was changed:
# -

# Breaking changes or notes:
# -

EOF
)
    echo "$commit_template" | git commit -F - --edit "$@"
}

# Amend last commit (reuse message)
git-amend() {
    _git_require_repo || return 1
    local rewrite_range
    rewrite_range=$(_git_last_commit_rewrite_range) || return 1
    _git_require_safe_rewrite "$rewrite_range" || return 1
    git commit --amend --no-edit "$@"
    _git_success "Last commit amended"
}

# Amend last commit with new message
git-amend-msg() {
    _git_require_repo || return 1
    local rewrite_range
    rewrite_range=$(_git_last_commit_rewrite_range) || return 1
    _git_require_safe_rewrite "$rewrite_range" || return 1
    git commit --amend "$@"
}

# Amend specific files to last commit
git-amend-files() {
    _git_require_repo || return 1
    if [[ $# -eq 0 ]]; then
        _git_error "Usage: git-amend-files <file1> [file2] ..."
        _git_info "Example: git-amend-files src/main.js tests/main.test.js"
        return 1
    fi

    local rewrite_range
    rewrite_range=$(_git_last_commit_rewrite_range) || return 1
    _git_require_safe_rewrite "$rewrite_range" || return 1
    git add "$@"
    git commit --amend --no-edit
    _git_success "Files added to last commit: $*"
}

# ============================================================================
# SQUASH & REBASE
# ============================================================================

# Squash last N commits properly using rebase
git-squash() {
    _git_require_repo || return 1
    if [[ -z "$1" ]]; then
        _git_error "Usage: git-squash <number-of-commits> [base-branch]"
        _git_info "Example: git-squash 3        # Squash last 3 commits"
        _git_info "         git-squash 5 main   # Squash last 5 commits from main"
        return 1
    fi
    local num_commits=$1
    local base_branch=""
    if [[ -n "$2" ]]; then
        base_branch=$(_git_get_base_branch "$2") || return 1
    fi

    # Verify we have enough commits on the current branch
    local total_commits
    if [[ -n "$base_branch" ]]; then
        total_commits=$(git rev-list --count "${base_branch}..HEAD")
    else
        total_commits=$(git rev-list --count HEAD)
    fi

    if (( total_commits < num_commits )); then
        _git_error "Error: Only $total_commits commit(s) on branch, cannot squash $num_commits"
        return 1
    fi

    local total_all rewrite_range
    total_all=$(git rev-list --count HEAD) || return 1
    if (( num_commits >= total_all )); then
        rewrite_range="HEAD"
    else
        rewrite_range="HEAD~$num_commits..HEAD"
    fi
    _git_require_safe_rewrite "$rewrite_range" || return 1

    _git_info "Squashing last $num_commits commits..."
    printf "\n"
    _git_header "Commits to be squashed:"
    git log --oneline -n "$num_commits" --color

    printf "\n"
    if _git_confirm "Continue? (y/N): "; then
        # Use sed to change 'pick' to 'squash' for commits 2 to N
        # Use --root when squashing all commits (HEAD~N would be before the root)
        if (( num_commits >= total_all )); then
            GIT_SEQUENCE_EDITOR="sed -i.bak '2,${num_commits}s/^pick/squash/'" \
                git rebase -i --root
        else
            GIT_SEQUENCE_EDITOR="sed -i.bak '2,${num_commits}s/^pick/squash/'" \
                git rebase -i "HEAD~$num_commits"
        fi
    else
        _git_warn "Cancelled."
    fi
}

# Interactive rebase from base branch
git-rebase-interactive() {
    _git_require_repo || return 1
    local base_branch
    base_branch=$(_git_get_base_branch "$1") || return 1
    _git_require_safe_rewrite "$base_branch..HEAD" || return 1

    _git_info "Starting interactive rebase from $base_branch..."
    git rebase -i "$base_branch"
}

# Rebase with automatic conflict resolution strategy
git-rebase-with-strategy() {
    _git_require_repo || return 1
    local strategy="$1"
    local base_branch
    base_branch=$(_git_get_base_branch "$2") || return 1

    if [[ "$strategy" != "ours" && "$strategy" != "theirs" ]]; then
        _git_error "Usage: git-rebase-with-strategy <ours|theirs> [base-branch]"
        printf "\n"
        _git_info "  ours   - Keep the upstream/base side on conflicts"
        _git_info "  theirs - Keep the rebased branch side on conflicts"
        printf "\n"
        _git_info "Example: git-rebase-with-strategy theirs main"
        return 1
    fi
    _git_require_safe_rewrite "$base_branch..HEAD" || return 1

    _git_info "Rebasing onto $base_branch with strategy: $strategy"
    if _git_confirm "Continue? (y/N): "; then
        if [[ "$strategy" == "ours" ]]; then
            git rebase -X ours "$base_branch"
        else
            git rebase -X theirs "$base_branch"
        fi
    else
        _git_warn "Cancelled."
    fi
}

# ============================================================================
# FIXUP & AUTOSQUASH
# ============================================================================

# Create fixup commit for a specific commit
git-fixup() {
    _git_require_repo || return 1
    if [[ -z "$1" ]]; then
        # Interactive selection with fzf
        _git_require_fzf || return 1
        _git_header "Select commit to fixup:"
        local commit
        commit=$(git log --oneline -n 30 | fzf --preview='git show --color=always {1}' | awk '{print $1}')
        [[ -z "$commit" ]] && return 1
    else
        local commit="$1"
        shift
    fi

    git commit --fixup="$commit" "$@"
    printf "\n"
    _git_success "Fixup commit created for $commit"
    _git_info "To autosquash, run: git-autosquash"
}

# Auto-squash fixup commits
git-autosquash() {
    _git_require_repo || return 1
    local base_branch
    base_branch=$(_git_get_base_branch "$1") || return 1
    _git_require_safe_rewrite "$base_branch..HEAD" || return 1

    _git_info "Auto-squashing fixup commits from $base_branch..."
    if _git_confirm "Continue? (y/N): "; then
        git rebase -i --autosquash "$base_branch"
    else
        _git_warn "Cancelled."
    fi
}

# ============================================================================
# UNDO & RESET
# ============================================================================

# Undo last commit and discard changes
git-undo-hard() {
    _git_require_repo || return 1
    local num_commits="${1:-1}"
    _git_require_safe_rewrite "HEAD~$num_commits..HEAD" || return 1

    _git_warn "WARNING: This will PERMANENTLY DELETE the last $num_commits commit(s) and all changes!"
    git log --oneline -n "$num_commits" --color

    printf "\n"
    _git_prompt "Are you ABSOLUTELY sure? Type 'yes' to confirm: "
    read -r response

    if [[ "$response" == "yes" ]]; then
        git reset --hard "HEAD~$num_commits"
        printf "\n"
        _git_success "Commit(s) and changes permanently removed."
        git status
    else
        _git_warn "Cancelled."
    fi
}

# Undo last commit but keep changes staged
git-undo-soft() {
    _git_require_repo || return 1
    local num_commits="${1:-1}"
    _git_require_safe_rewrite "HEAD~$num_commits..HEAD" || return 1

    _git_info "Undoing last $num_commits commit(s) but keeping changes staged..."
    git log --oneline -n "$num_commits" --color

    printf "\n"
    if _git_confirm "Continue? (y/N): "; then
        git reset --soft "HEAD~$num_commits"
        printf "\n"
        _git_success "Commit(s) undone. Changes remain staged."
        git status
    else
        _git_warn "Cancelled."
    fi
}

# ============================================================================
# CONFLICT RESOLUTION
# ============================================================================

# Show files with merge conflicts
git-conflicts() {
    _git_require_repo || return 1
    local conflicts
    conflicts=$(git diff --name-only --diff-filter=U)

    if [[ -z "$conflicts" ]]; then
        _git_success "No conflicts found"
        return 0
    fi

    _git_header "Files with conflicts:"
    echo "$conflicts"
    printf "\n"
    _git_info "Actions:"
    printf "%s\n" "  git checkout --ours <file>    # Use Git's 'ours' side (operation-dependent)"
    printf "%s\n" "  git checkout --theirs <file>  # Use Git's 'theirs' side (operation-dependent)"
    printf "%s\n" "  git-resolve-all ours          # Resolve all with Git's 'ours' side"
    printf "%s\n" "  git-resolve-all theirs        # Resolve all with Git's 'theirs' side"
}

# Resolve all conflicts with strategy
git-resolve-all() {
    _git_require_repo || return 1
    local strategy="$1"

    if [[ "$strategy" != "ours" && "$strategy" != "theirs" ]]; then
        _git_error "Usage: git-resolve-all <ours|theirs>"
        printf "\n"
        _git_info "  ours   - Use Git's 'ours' side for all conflicts (operation-dependent)"
        _git_info "  theirs - Use Git's 'theirs' side for all conflicts (operation-dependent)"
        return 1
    fi

    local conflicts
    conflicts=$(git diff --name-only --diff-filter=U)

    if [[ -z "$conflicts" ]]; then
        _git_success "No conflicts to resolve"
        return 0
    fi

    _git_info "Resolving conflicts with: $strategy"
    echo "$conflicts"
    printf "\n"
    if _git_confirm "Continue? (y/N): "; then
        echo "$conflicts" | while read -r file; do
            git checkout "--$strategy" "$file"
            git add "$file"
            _git_success "Resolved: $file (using $strategy)"
        done
        printf "\n"
        _git_success "All conflicts resolved. Review and commit."
    else
        _git_warn "Cancelled."
    fi
}

# ============================================================================
# STASH MANAGEMENT
# ============================================================================

# Interactive stash browser with fzf
git-stash-browse() {
    _git_require_repo || return 1
    _git_require_fzf || return 1
    local stash
    stash=$(git stash list --format='%gd %s' | fzf --preview='git stash show -p {1}' --preview-window=right:60%)
    [[ -z "$stash" ]] && return

    local stash_index
    stash_index="${stash%% *}"

    _git_info "Selected: $stash"
    _git_header "1) Apply  2) Pop  3) Drop  4) Show  5) Cancel"
    _git_prompt "Choose action: "
    read -r action

    case "$action" in
        1) git stash apply "$stash_index" ;;
        2) git stash pop "$stash_index" ;;
        3) git stash drop "$stash_index" ;;
        4) git stash show -p "$stash_index" ;;
        *) _git_warn "Cancelled" ;;
    esac
}

# Quick stash with message
git-stash-save() {
    _git_require_repo || return 1
    if [[ -z "$1" ]]; then
        _git_error "Usage: git-stash-save <message>"
        _git_info "Example: git-stash-save 'WIP: testing feature'"
        return 1
    fi

    git stash push -m "$1"
    _git_success "Stashed with message: $1"
}

# ============================================================================
# PUSH OPERATIONS
# ============================================================================

# Show what will be pushed to remote
git-push-preview() {
    _git_require_repo || return 1
    local remote="${1:-origin}"
    local branch
    branch=$(git branch --show-current)

    if ! git rev-parse --verify "$remote/$branch" &>/dev/null; then
        _git_error "Remote branch not found: $remote/$branch"
        return 1
    fi

    _git_header "Changes that will be pushed to $remote/$branch:"
    printf "\n"
    git log "$remote/$branch"..HEAD --oneline --graph --decorate --color

    _git_header "─────────────────────────────────────────"
    _git_info "File changes:"
    git diff --stat "$remote/$branch"..HEAD
}

# Force push
# Usage: git-push-force [target-branch] [remote]
#   git-push-force              → push current branch to same branch on origin
#   git-push-force test         → push current branch to 'test' on origin
#   git-push-force test upstream → push current branch to 'test' on upstream
git-push-force() {
    _git_require_repo || return 1
    local local_branch
    local_branch=$(_git_current_branch) || return 1

    local target_branch="${1:-$local_branch}"
    local remote="${2:-origin}"

    _git_require_not_protected_branch "$target_branch" "$remote" || return 1

    local remote_ref="refs/remotes/$remote/$target_branch"
    if ! git rev-parse --verify "$remote_ref" &>/dev/null; then
        _git_error "Remote branch not found: $remote/$target_branch"
        return 1
    fi
    local expected_oid
    expected_oid=$(git rev-parse --verify "$remote_ref") || return 1

    _git_warn "Force pushing $local_branch → $remote/$target_branch..."
    printf "\n"
    _git_header "Changes to be pushed:"
    git log "$remote_ref"..HEAD --oneline --color

    printf "\n"
    _git_prompt "Type target branch name to confirm '$target_branch': "
    local response
    read -r response

    if [[ "$response" == "$target_branch" ]]; then
        git push --force-with-lease="refs/heads/$target_branch:$expected_oid" \
            "$remote" "${local_branch}:refs/heads/$target_branch"
    else
        _git_warn "Cancelled."
    fi
}

# Push current branch and set upstream
git-push-set-upstream() {
    _git_require_repo || return 1
    local branch
    branch=$(git branch --show-current)
    local remote="${1:-origin}"

    _git_info "Pushing $branch and setting upstream to $remote/$branch..."
    git push -u "$remote" "$branch"
}

# ============================================================================
# CHERRY-PICK OPERATIONS
# ============================================================================

# Interactive cherry-pick with fzf
git-cherry-pick-interactive() {
    _git_require_repo || return 1
    _git_require_fzf || return 1
    local base_branch
    base_branch=$(_git_get_base_branch "$1")

    if [[ -z "$base_branch" ]]; then
        _git_header "Select commits to cherry-pick from history:"
        local commits
        commits=$(git log --oneline -n 50 | fzf --multi --preview='git show --color=always {1}' | awk '{print $1}')
    else
        _git_header "Select commits to cherry-pick from $base_branch:"
        local commits
        commits=$(git log "$base_branch" --oneline -n 50 | fzf --multi --preview='git show --color=always {1}' | awk '{print $1}')
    fi

    [[ -z "$commits" ]] && return 1

    _git_info "Cherry-picking commits:"
    echo "$commits"
    printf "\n"
    if _git_confirm "Continue? (y/N): "; then
        echo "$commits" | xargs git cherry-pick
    else
        _git_warn "Cancelled."
    fi
}

# ============================================================================
# WORKTREE OPERATIONS
# ============================================================================

# Create a new worktree for a branch
git-worktree-new() {
    _git_require_repo || return 1
    if [[ -z "$1" || -z "$2" ]]; then
        _git_error "Usage: git-worktree-new <path> <branch>"
        _git_info "Example: git-worktree-new ../feature-x feature/new-feature"
        return 1
    fi

    local path="$1"
    local branch="$2"

    git worktree add "$path" -b "$branch"
    _git_success "Worktree created at $path for branch $branch"
}

# List all worktrees
git-worktree-list() {
    _git_require_repo || return 1
    git worktree list
}

# Remove a worktree
git-worktree-remove() {
    _git_require_repo || return 1
    if [[ -z "$1" ]]; then
        _git_error "Usage: git-worktree-remove <path>"
        return 1
    fi

    git worktree remove "$1"
}
