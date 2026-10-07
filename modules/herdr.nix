{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Heeler v0.1.13 ships plugin 0.6.0; pin the checkout as well as the version.
  heelerRef = "f98028b426f927feb75dc263dbf659e92fc57657";
  heelerNode =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "/opt/homebrew/opt/node@24/bin/node"
    else
      "${pkgs.nodejs_24}/bin/node";
  herdrBin =
    if pkgs.stdenv.hostPlatform.isDarwin then "/opt/homebrew/bin/herdr" else "${pkgs.herdr}/bin/herdr";
in
{
  options.dotfiles.herdr.heeler.enable = lib.mkEnableOption "Heeler phone pairing and notifications";

  config.xdg.configFile = {
    "herdr/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/herdr/config.toml";

    "herdr/plugins/config/herdr-navigator/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/config/herdr/navigator.toml";

  };

  config.home.activation.herdrIntegrations =
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

        ${lib.optionalString config.dotfiles.herdr.heeler.enable ''
          if ! ${herdrBin} plugin list --plugin heeler --json \
            | ${pkgs.jq}/bin/jq -e '.result.plugins | any(.version == "0.6.0" and .enabled and .source.resolved_commit == "${heelerRef}")' >/dev/null; then
            run env PATH="${lib.makeBinPath [ pkgs.git ]}:${
              if pkgs.stdenv.hostPlatform.isDarwin then
                lib.concatStringsSep ":" config.dotfiles.env.darwinPackageBinDirs
              else
                lib.makeBinPath [ pkgs.nodejs_24 ]
            }:$PATH" \
              ${herdrBin} plugin install ZingerLittleBee/Heeler/plugin --ref ${heelerRef} --yes
          fi

          # Ghostty launches Herd directly, without the interactive shell PATH.
          # Bind the pinned plugin's runtime scripts to Node; refresh on every
          # activation so reinstalling or changing the Nix Node path is safe.
          heelerManifest=$(${herdrBin} plugin list --plugin heeler --json \
            | ${pkgs.jq}/bin/jq -er '.result.plugins[] | select(.plugin_id == "heeler") | .manifest_path')
          run ${pkgs.gnused}/bin/sed -E -i \
            's|^(command = \[")[^"]+(", "src/[^"]+\.js"\])$|\1${heelerNode}\2|' \
            "$heelerManifest"
        ''}

        run ${herdrBin} integration install pi
        run ${herdrBin} integration install claude
        run install -m 644 "$HOME/.claude/settings.json" "$HOME/.local/state/dotfiles/claude-settings.last.json"
      '';
}
