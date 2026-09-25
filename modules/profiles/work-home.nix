{
  imports = [
    ../host-specific/work.nix
  ];

  dotfiles = {
    aws.mcp = {
      endpointRegion = "eu-central-1";
      operationRegion = "eu-west-1";
    };
    claude.enableWorkIntegrations = true;
    kubernetes.enable = true;
    cursor.enable = true;
  };
}
