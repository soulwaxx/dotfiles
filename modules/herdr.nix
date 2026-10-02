{
  config,
  lib,
  pkgs,
  ...
}:
let
  herdrBin =
    if pkgs.stdenv.hostPlatform.isDarwin then "/opt/homebrew/bin/herdr" else "${pkgs.herdr}/bin/herdr";
in
{
  xdg.configFile = {
    "herdr/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/herdr/config.toml";

    "herdr/plugins/config/herdr-navigator/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/herdr/navigator.toml";

  };

  home.activation.herdrIntegrations =
    lib.hm.dag.entryAfter [ "linkGeneration" "installObsidianPlugin" "installPi" ]
      ''
        if [[ ! -x "${herdrBin}" ]]; then
          echo "herdr: binary not found at ${herdrBin}" >&2
          exit 1
        fi

        if ! ${herdrBin} plugin list --plugin herdr-navigator --json \
          | ${pkgs.jq}/bin/jq -e '.result.plugins | any(.version == "0.3.3" and .enabled)' >/dev/null; then
          run env PATH="${lib.makeBinPath [ pkgs.git ]}:${
            if pkgs.stdenv.hostPlatform.isDarwin then
              "/opt/homebrew/bin"
            else
              lib.makeBinPath [
                pkgs.cargo
                pkgs.rustc
                pkgs.stdenv.cc
              ]
          }:$PATH" \
            ${herdrBin} plugin install thanhdat77/herdr-navigator --ref v0.3.3 --yes
        fi

        run ${herdrBin} integration install pi
        run ${herdrBin} integration install claude
        run install -m 644 "$HOME/.claude/settings.json" "$HOME/.local/state/dotfiles/claude-settings.last.json"
      '';
}
