#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/mcp.json" <<'JSON'
{
  "github": { "type": "http", "url": "https://api.githubcopilot.com/mcp" },
  "context7": { "type": "stdio", "command": "npx", "args": ["-y", "@upstash/context7-mcp"] }
}
JSON

cat >"$TMPDIR/claude.json" <<'JSON'
{
  "mcpServers": {
    "github": { "type": "stdio", "command": "old-github" },
    "manual": { "type": "stdio", "command": "manual-server" }
  }
}
JSON

jq --slurpfile mcp "$TMPDIR/mcp.json" \
  --from-file "$ROOT/modules/claude/jq/reconcile-mcp.jq" \
  "$TMPDIR/claude.json" >"$TMPDIR/claude.out.json"

jq -e '.mcpServers.github.url == "https://api.githubcopilot.com/mcp"' "$TMPDIR/claude.out.json" >/dev/null
jq -e '.mcpServers.context7.command == "npx"' "$TMPDIR/claude.out.json" >/dev/null
jq -e '.mcpServers | has("manual") | not' "$TMPDIR/claude.out.json" >/dev/null

cat >"$TMPDIR/settings-source.json" <<'JSON'
{
  "effortLevel": "high",
  "permissions": { "defaultMode": "auto" },
  "pluginConfigs": { "builtin": { "options": { "mode": "declared" } } }
}
JSON
cat >"$TMPDIR/settings-live.json" <<'JSON'
{
  "effortLevel": "low",
  "permissions": { "defaultMode": "bypassPermissions" },
  "pluginConfigs": {
    "builtin": { "options": { "mode": "runtime", "extra": true } },
    "obsidian-second-brain@obsidian-second-brain": { "options": { "vault_agent_effort": "low" } }
  }
}
JSON
filter="$ROOT/modules/claude/jq/preserve-plugin-configs.jq"
jq --slurpfile live "$TMPDIR/settings-live.json" --from-file "$filter" \
  "$TMPDIR/settings-source.json" >"$TMPDIR/settings.out.json"
jq -e '
  .effortLevel == "high" and .permissions.defaultMode == "auto" and
  .pluginConfigs.builtin.options == {mode:"declared",extra:true} and
  .pluginConfigs["obsidian-second-brain@obsidian-second-brain"].options.vault_agent_effort == "low"
' "$TMPDIR/settings.out.json" >/dev/null
# Repeated activation is stable; checked-in plugin choices still win.
jq --slurpfile live "$TMPDIR/settings.out.json" --from-file "$filter" \
  "$TMPDIR/settings-source.json" >"$TMPDIR/settings-again.json"
cmp "$TMPDIR/settings.out.json" "$TMPDIR/settings-again.json"
jq '.pluginConfigs["obsidian-second-brain@obsidian-second-brain"].options.vault_agent_effort = "high"' \
  "$TMPDIR/settings-source.json" >"$TMPDIR/settings-explicit.json"
jq --slurpfile live "$TMPDIR/settings-live.json" --from-file "$filter" \
  "$TMPDIR/settings-explicit.json" | \
  jq -e '.pluginConfigs["obsidian-second-brain@obsidian-second-brain"].options.vault_agent_effort == "high"' >/dev/null
printf '{}\n' >"$TMPDIR/settings-empty.json"
jq --slurpfile live "$TMPDIR/settings-empty.json" --from-file "$filter" \
  "$TMPDIR/settings-source.json" >"$TMPDIR/settings-initial.json"
jq -e --slurpfile source "$TMPDIR/settings-source.json" '. == $source[0]' "$TMPDIR/settings-initial.json" >/dev/null
for invalid in '[]' '{"pluginConfigs":[]}' '{"pluginConfigs":"invalid"}'; do
  printf '%s\n' "$invalid" >"$TMPDIR/settings-invalid.json"
  if jq --slurpfile live "$TMPDIR/settings-invalid.json" --from-file "$filter" \
    "$TMPDIR/settings-source.json" > /dev/null 2>&1; then
    echo "malformed live settings were accepted" >&2
    exit 1
  fi
done

echo "claude-state-jq: ok"
