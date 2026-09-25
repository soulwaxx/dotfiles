#!/usr/bin/env zsh
# ============================================================================
# NVIM QUICK-START FUNCTIONS
# ============================================================================
# Shell-side fuzzy finder wrappers that pipe fd/rg into fzf and open the
# result in nvim — no running nvim process needed.

# Fuzzy-find a file (fd + fzf) and open in nvim.
# Usage: nvf [dir]
#   nvf .        search current directory
#   nvf ~/src    search a specific directory
nvf() {
  local search_dir="${1:-.}"
  if [[ ! -d "$search_dir" ]]; then
    echo "nvf: not a directory: $search_dir" >&2
    return 1
  fi
  local file
  file="$(
    (
      cd "$search_dir" || exit
      fd --type f --strip-cwd-prefix | \
        fzf --preview 'bat --style=numbers --color=always {} 2>/dev/null || head -80 {}'
    )
  )"
  [[ -n "$file" ]] && nvim "$search_dir/$file"
}

# Live-grep file contents (rg + fzf) and open at matching line.
# Usage: nvgg [dir]
nvgg() {
  local search_dir="${1:-.}"
  if [[ ! -d "$search_dir" ]]; then
    echo "nvgg: not a directory: $search_dir" >&2
    return 1
  fi

  # fzf quotes {q}, {1}, and {2} before running bound and preview commands.
  # Keep the initial list empty: an empty rg pattern would list every line.
  local reload_command='[ -n {q} ] && rg --line-number --no-heading --color=never --smart-case -- {q} || true'
  local result
  result="$(
    (
      cd "$search_dir" || exit
      fzf --disabled \
        --bind "start:reload:printf ''" \
        --bind "change:reload:$reload_command" \
        --delimiter=: \
        --nth=3.. \
        --preview 'bat --style=numbers --color=always {1} --highlight-line {2} 2>/dev/null || head -80 {1}' \
        --preview-window='up:60%'
    )
  )"
  [[ -n "$result" ]] || return 0

  local file="${result%%:*}"
  local remainder="${result#*:}"
  local line="${remainder%%:*}"
  nvim "+$line" -- "$search_dir/$file"
}
