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
  xdg.configFile."herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/herdr/config.toml";

  home.activation.herdrIntegrations =
    lib.hm.dag.entryAfter [ "linkGeneration" "claudeSettings" "installPi" ]
      ''
        if [[ ! -x "${herdrBin}" ]]; then
          echo "herdr: binary not found at ${herdrBin}" >&2
          exit 1
        fi

        run ${herdrBin} integration install pi
        run ${herdrBin} integration install claude
        run install -m 644 "$HOME/.claude/settings.json" "$HOME/.local/state/dotfiles/claude-settings.last.json"
      '';
}
