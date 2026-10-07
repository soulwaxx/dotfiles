{ lib, pkgs }:
{ isWork, awsMcp }:
let
  mcpServersLib = import ../mcp-servers.nix { inherit lib pkgs; };
in
{
  mcpServers =
    lib.mapAttrs
      (
        name: server:
        server
        // {
          exposure = "deferred";
          timeout = if name == "aws-mcp" then 300 else 60;
        }
      )
      (
        mcpServersLib.commonServers
        // lib.optionalAttrs isWork (mcpServersLib.mkWorkServers { inherit awsMcp; })
      );
}
