# Docker CLI glue for OrbStack (installed as a Homebrew cask).
#
# OrbStack provides the container engine and creates an `orbstack` docker context
# that is auto-activated in the terminal. The docker CLI itself stays declarative
# via Homebrew (modules/homebrew-packages.nix); OrbStack leaves an existing docker
# install alone. What OrbStack does NOT wire up for a pre-existing Homebrew CLI is
# the plugins, so symlink buildx and compose into ~/.docker/cli-plugins from the
# Homebrew kegs so `docker buildx` and `docker compose` resolve.
#
# Homebrew prefix is /opt/homebrew because both Macs are aarch64-darwin.
{ config, ... }:
{
  home.file = {
    ".docker/cli-plugins/docker-buildx" = {
      source = config.lib.file.mkOutOfStoreSymlink "/opt/homebrew/opt/docker-buildx/bin/docker-buildx";
      force = true;
    };
    ".docker/cli-plugins/docker-compose" = {
      source = config.lib.file.mkOutOfStoreSymlink "/opt/homebrew/opt/docker-compose/bin/docker-compose";
      force = true;
    };
  };
}
