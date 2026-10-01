{ lib, pkgs }:
{ isWork, awsMcp }:
let
  mcpServersLib = import ../mcp-servers.nix { inherit lib pkgs; };
in
{
  mcpServers =
    lib.mapAttrs
      (
        _: server:
        server
        // {
          exposure = "codemode";
          timeout = 60;
        }
      )
      (
        mcpServersLib.commonServers
        // lib.optionalAttrs isWork (mcpServersLib.mkWorkServers { inherit awsMcp; })
      );
}
