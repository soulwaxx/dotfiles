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
      description = "Search and manage GitHub repositories, code, issues, and pull requests.";
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
        description = "Inspect and manage AWS resources using configured AWS CLI profiles.";
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
        description = "Look up AWS service pricing and estimate infrastructure costs.";
        command = "uvx";
        args = [ "awslabs.aws-pricing-mcp-server@latest" ];
        env = { };
      };

      aws-knowledge-mcp = {
        description = "Search and read AWS documentation, guidance, and best practices.";
        url = "https://knowledge-mcp.global.api.aws";
      };

      kubernetes = {
        description = "Inspect Kubernetes clusters, workloads, resources, and logs in read-only mode.";
        command = "npx";
        args = [
          "-y"
          "kubernetes-mcp-server@latest"
          "--read-only"
        ];
        env = { };
      };

      notion = {
        description = "Search, read, and manage Notion pages and databases.";
        url = "https://mcp.notion.com/mcp";
      };

      datadog = {
        description = "Investigate Datadog metrics, logs, traces, monitors, and incidents.";
        url = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
      };
    };
}
