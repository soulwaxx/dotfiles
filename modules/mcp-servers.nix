# Shared MCP server definitions for both harnesses.
# modules/pi.nix consumes these as-is; modules/claude/mcp.nix maps over them
# to add the `type = "http"/"stdio"` field Claude's schema requires (inferred
# here from whether an entry has `url` or `command`).
{ lib, pkgs }:
let
  awsMcpEndpoints = {
    "us-east-1" = "https://aws-mcp.us-east-1.api.aws/mcp";
    "eu-central-1" = "https://aws-mcp.eu-central-1.api.aws/mcp";
  };

  # Profiles are read from ~/.aws/config at launch so account names stay out of
  # the repo. The proxy defaults to the first profile, so read-only profiles go
  # first. AWS_MCP_PROFILE_FILTER (ERE, e.g. in ~/.secrets) narrows the list;
  # with no profiles the proxy falls back to AWS_PROFILE.
  awsMcpLauncher = pkgs.writeShellScript "aws-mcp-launcher" ''
    profiles="$(aws configure list-profiles 2>/dev/null | ${lib.getExe pkgs.gawk} \
      -v filter="''${AWS_MCP_PROFILE_FILTER:-.}" '
        $0 ~ filter { if (tolower($0) ~ /read-?only/) ro = ro $0 " "; else rw = rw $0 " " }
        END { s = ro rw; sub(/ $/, "", s); print s }')"
    if [[ -n "$profiles" ]]; then
      export AWS_MCP_PROXY_PROFILES="$profiles"
    fi
    exec uvx mcp-proxy-for-aws-cli@latest "$@"
  '';
in
{
  commonServers = {
    github = {
      url = "https://api.githubcopilot.com/mcp";
      headers."Authorization" = "Bearer \${GH_TOKEN}";
    };
  };

  # Work-only servers. awsMcp is config.dotfiles.aws.mcp.
  mkWorkServers =
    { awsMcp }:
    let
      awsMcpEndpoint = awsMcpEndpoints.${awsMcp.endpointRegion};
    in
    {
      aws-mcp = {
        command = "${awsMcpLauncher}";
        args = [
          awsMcpEndpoint
          "--metadata"
          "AWS_REGION=${awsMcp.operationRegion}"
          "--tool-timeout"
          "300"
          "--disable-telemetry"
        ];
        env = { };
      };

      aws-pricing-mcp-server = {
        command = "uvx";
        args = [ "awslabs.aws-pricing-mcp-server@latest" ];
        env = { };
      };

      aws-knowledge-mcp = {
        url = "https://knowledge-mcp.global.api.aws";
      };

      kubernetes = {
        command = "npx";
        args = [
          "-y"
          "kubernetes-mcp-server@latest"
          "--read-only"
        ];
        env = { };
      };

      notion = {
        url = "https://mcp.notion.com/mcp";
      };

      datadog = {
        url = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
      };
    };
}
