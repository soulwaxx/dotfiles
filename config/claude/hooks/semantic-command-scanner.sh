#!/usr/bin/env bash
# Block the compound-shell hazard declarative command globs cannot express:
# downloads piped directly to a shell.

set -u

# Fail closed: any unexpected nonzero exit (unset var under set -u, a failed
# command) is remapped to 2, Claude's blocking code. Exit 0 (allow/deny-JSON)
# and exit 2 (missing jq) already carry their intended meaning and pass
# through unchanged.
# shellcheck disable=SC2329 # invoked indirectly via the trap below
__exit_guard() {
  local code=$?
  if [[ $code -ne 0 && $code -ne 2 ]]; then
    exit 2
  fi
}
trap __exit_guard EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "semantic-command-scanner: jq is required to inspect Bash tool input" >&2
  exit 2
fi

input=$(cat)
if ! tool=$(printf '%s' "$input" | jq -er '.tool_name // ""' 2>/dev/null); then
  echo "semantic-command-scanner: malformed hook input" >&2
  exit 2
fi
[[ "$tool" == "Bash" ]] || exit 0

if ! cmd=$(printf '%s' "$input" | jq -er '.tool_input.command // ""' 2>/dev/null); then
  echo "semantic-command-scanner: malformed Bash tool input" >&2
  exit 2
fi
[[ -z "$cmd" ]] && exit 0

# Structured deny: Claude only honours JSON on exit 0. With exit 2 it ignores
# stdout and reads stderr instead, so the reason below would be dropped and the
# block would surface without explanation.
deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Quote-character removal catches quoted downloader and shell executable names
# while retaining pipeline separators and spacing.
quote_chars_stripped_cmd=$(printf '%s' "$cmd" | sed -E 's/["'"'"']//g')

# Permission-system evaluates commands, not shell pipelines, so compound-shell
# meaning belongs here. Parentheses cover subshell and command-substitution
# groups; common command wrappers may precede the downloader without changing
# the pipeline's meaning.
if printf '%s' "$quote_chars_stripped_cmd" | grep -qE '(^|&&|;|\||\()[[:space:]]*(([^[:space:]]*/)?(sudo|env|command)[[:space:]]+)*([^[:space:]]*/)?(curl|wget)[[:space:]]+[^|;&]*\|[[:space:]]*((/usr/bin/)?env[[:space:]]+|sudo[[:space:]]+)?([^[:space:]]*/)?(sh|bash|zsh)([[:space:])]|$)'; then
  deny "download piped directly to a shell detected. Download and inspect the script before executing it."
fi

exit 0
