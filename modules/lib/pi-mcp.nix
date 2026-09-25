{ lib, pkgs }:
{ isWork, awsMcp }:
let
  mcpServersLib = import ../mcp-servers.nix { inherit lib pkgs; };
in
{
  settings = {
    scriptMode = false;
    directTools = false;
    # Backstop against indefinite hangs on live MCP calls (e.g. stalled
    # datadog/notion streaming). 0/omitted uses the SDK default (no bound).
    requestTimeoutMs = 60000;
  };
  mcpServers =
    mcpServersLib.commonServers
    // lib.optionalAttrs isWork (mcpServersLib.mkWorkServers { inherit awsMcp; });
}
