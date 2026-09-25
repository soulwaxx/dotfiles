# Declarative MCP server management for Claude Code.
# Merges Nix-managed servers into ~/.claude.json on activation;
# manually-added servers are preserved.
{
  pkgs,
  config,
  lib,
  ...
}:

let
  jsonFormat = pkgs.formats.json { };
  isWork = config.dotfiles.claude.enableWorkIntegrations;
  awsMcp = config.dotfiles.aws.mcp;
  reconcileMcpFilter = "${config.dotfiles.path}/modules/claude/jq/reconcile-mcp.jq";

  # Definitions shared with modules/pi.nix. Claude's schema requires an
  # explicit type field that pi infers from url (http) vs command (stdio).
  mcpServersLib = import ../mcp-servers.nix { inherit lib pkgs; };
  addType = entry: entry // { type = if entry ? url then "http" else "stdio"; };

  mcpServers = lib.mapAttrs (_: addType) (
    mcpServersLib.commonServers
    // lib.optionalAttrs isWork (mcpServersLib.mkWorkServers { inherit awsMcp; })
  );
  mcpServersFile = jsonFormat.generate "claude-mcp-servers.json" mcpServers;
in
{
  home.activation.claudeMcpServers = lib.hm.dag.entryAfter [ "claudeSettings" ] ''
    CLAUDE_JSON="$HOME/.claude.json"
    verboseEcho "claude: reconciling declarative MCP servers in $CLAUDE_JSON"
    if [[ -f "$CLAUDE_JSON" ]]; then
      if ${pkgs.jq}/bin/jq -S '.mcpServers' "$CLAUDE_JSON" 2>/dev/null | \
         ${pkgs.diffutils}/bin/cmp -s - <(${pkgs.jq}/bin/jq -S '.' ${mcpServersFile}); then
        verboseEcho "claude: MCP servers unchanged, skipping"
      else
        ${pkgs.jq}/bin/jq --slurpfile mcp ${mcpServersFile} \
          --from-file ${lib.escapeShellArg reconcileMcpFilter} \
          "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
      fi
    else
      ${pkgs.jq}/bin/jq -n --slurpfile mcp ${mcpServersFile} \
        '{"mcpServers": $mcp[0]}' > "$CLAUDE_JSON"
    fi
  '';
}
