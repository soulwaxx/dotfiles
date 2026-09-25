#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/mcp.json" <<'JSON'
{
  "github": { "type": "http", "url": "https://api.githubcopilot.com/mcp" },
  "context7": { "type": "stdio", "command": "npx", "args": ["-y", "@upstash/context7-mcp"] }
}
JSON

cat > "$TMPDIR/claude.json" <<'JSON'
{
  "mcpServers": {
    "github": { "type": "stdio", "command": "old-github" },
    "manual": { "type": "stdio", "command": "manual-server" }
  }
}
JSON

jq --slurpfile mcp "$TMPDIR/mcp.json" \
  --from-file "$ROOT/modules/claude/jq/reconcile-mcp.jq" \
  "$TMPDIR/claude.json" > "$TMPDIR/claude.out.json"

jq -e '.mcpServers.github.url == "https://api.githubcopilot.com/mcp"' "$TMPDIR/claude.out.json" >/dev/null
jq -e '.mcpServers.context7.command == "npx"' "$TMPDIR/claude.out.json" >/dev/null
jq -e '.mcpServers | has("manual") | not' "$TMPDIR/claude.out.json" >/dev/null

echo "claude-state-jq: ok"
