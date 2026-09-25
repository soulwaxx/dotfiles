#!/usr/bin/env bash

set -u

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null) || exit 0

case "$event" in
  Notification)
    notification_type=$(printf '%s' "$input" | jq -r '.notification_type // "notification"' 2>/dev/null)
    title=$(printf '%s' "$input" | jq -r '.title // "Claude Code"' 2>/dev/null)
    message=$(printf '%s' "$input" | jq -r '.message // "Claude Code needs attention"' 2>/dev/null)
    title="${title} (${notification_type})"
    ;;
  StopFailure)
    error=$(printf '%s' "$input" | jq -r '.error // "unknown"' 2>/dev/null)
    message=$(printf '%s' "$input" | jq -r '.error_details // .last_assistant_message // "Claude Code turn failed"' 2>/dev/null)
    title="Claude Code failed: ${error}"
    ;;
  *)
    exit 0
    ;;
esac

message=$(printf '%s' "$message" | tr '\n' ' ' | cut -c 1-240)

if [[ "$(uname -s)" == "Darwin" && -x /usr/bin/osascript ]]; then
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
    -e 'end run' \
    "$title" "$message" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "$title" "$message" >/dev/null 2>&1 || true
fi

exit 0
