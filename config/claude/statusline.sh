#!/usr/bin/env bash
input=$(cat)

RESET=$'\033[0m'
CYAN=$'\033[36m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
DIM=$'\033[2m'

if command -v jq >/dev/null 2>&1; then
  json_get() {
    local filter="$1"
    local fallback="$2"
    local value

    value=$(printf '%s' "$input" | jq -r "$filter" 2>/dev/null) || value="$fallback"
    if [ -z "$value" ] || [ "$value" = "null" ]; then
      value="$fallback"
    fi
    printf '%s\n' "$value"
  }
else
  json_get() {
    printf '%s\n' "$2"
  }
fi

model=$(json_get '.model.display_name // "?"' "?")

dir=$(json_get '.cwd // ""' "")
if [ -n "$dir" ] && [ -d "$dir" ]; then
  dir_name=$(basename "$dir" 2>/dev/null || printf '?')
else
  dir_name="?"
fi

git_info=""
if [ -n "$dir" ] && command -v git >/dev/null 2>&1 && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ]; then
    if ! git -C "$dir" diff --quiet 2>/dev/null || ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
      git_info="${YELLOW}${branch}*${RESET}"
    else
      git_info="${GREEN}${branch}${RESET}"
    fi
  fi
fi

pct_raw=$(json_get '.context_window.used_percentage // 0' "0")
pct=$(printf '%s\n' "$pct_raw" | LC_ALL=C awk '{p=$1+0; if (p<0) p=0; if (p>100) p=100; printf "%d", p}')
bar_width=10
filled=$((pct * bar_width / 100))
empty=$((bar_width - filled))
if [ "$pct" -lt 50 ]; then
  BAR_COLOR="${GREEN}"
elif [ "$pct" -lt 80 ]; then
  BAR_COLOR="${YELLOW}"
else
  BAR_COLOR="${RED}"
fi
bar="${BAR_COLOR}["
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done
bar+="] ${pct}%${RESET}"

cost=$(json_get '.cost.total_cost_usd // 0' "0")
cost_fmt=$(printf '%s\n' "$cost" | LC_ALL=C awk '{printf "%.2f", $1+0}')

vim_mode=$(json_get '.vim.mode // ""' "")
case "$vim_mode" in
  NORMAL) vim_info="${GREEN}N${RESET}" ;;
  INSERT) vim_info="${YELLOW}I${RESET}" ;;
  VISUAL) vim_info="${MAGENTA}V${RESET}" ;;
  *)      vim_info="" ;;
esac

SEP="${DIM}|${RESET}"
output="${CYAN}${dir_name}${RESET}"
[ -n "$git_info" ] && output+=" ${SEP} ${git_info}"
[ -n "$vim_info" ] && output+=" ${SEP} ${vim_info}"
output+=" ${SEP} ${MAGENTA}${model}${RESET}"
output+=" ${SEP} ${bar}"
output+=" ${SEP} 💰 ${GREEN}\$${cost_fmt}${RESET}"
printf '%s\n' "$output"
