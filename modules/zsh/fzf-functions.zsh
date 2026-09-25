#!/usr/bin/env zsh
# ============================================================================
# FZF PROCESS FUNCTIONS
# ============================================================================

# Pick processes with fzf and signal them.
# Usage: fkill [signal]
#   fkill        send TERM to the selected processes
#   fkill KILL   send KILL instead
# Tab multi-selects; Esc aborts without signalling anything.
fkill() {
  emulate -L zsh
  local -a pids

  # `-o pid=,comm=` (trailing `=`) suppresses headers on both BSD ps (macOS)
  # and procps (Linux); --no-headers is procps-only.
  if (( UID )); then
    pids=(${(f)"$(ps -u "$UID" -o pid=,comm= | fzf -m --header='fkill: Tab to select, Enter to signal' | awk '{print $1}')"})
  else
    pids=(${(f)"$(ps -eo pid=,comm= | fzf -m --header='fkill: Tab to select, Enter to signal' | awk '{print $1}')"})
  fi

  (( $#pids )) || return 0
  kill -"${1:-TERM}" $pids
}
