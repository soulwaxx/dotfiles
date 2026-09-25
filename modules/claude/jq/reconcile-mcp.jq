# Overwrite the top-level (global) MCP server map with the Nix-managed set.
# $mcp[0] is the generated server list slurped in by modules/claude/mcp.nix.
# Project-scoped servers under .projects[*].mcpServers are left untouched, so
# any server added manually to a specific project survives the reconcile.
.mcpServers = $mcp[0]
