{
  config,
  lib,
  pkgs,
  ...
}:
let
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

        # Resolve stable releases at activation time, not during Nix evaluation.
        # Plugin manifest versions need not match repository release tags (Heeler).
        update_herdr_plugin() {
          local plugin="$1" repo="$2" subdir="''${3:-}" ref
          ref=$(${pkgs.curl}/bin/curl --fail --silent --show-error --location \
            --connect-timeout 10 --max-time 60 \
            "https://api.github.com/repos/$repo/releases/latest" \
            | ${pkgs.jq}/bin/jq -er '.tag_name | select(type == "string" and length > 0)')

          if ! ${herdrBin} plugin list --plugin "$plugin" --json \
            | ${pkgs.jq}/bin/jq -e --arg ref "$ref" --arg repo "$repo" --arg subdir "$subdir" '
              .result.plugins | any(.enabled and .source.kind == "github"
                and (.source.owner + "/" + .source.repo) == $repo
                and (.source.subdir // "") == $subdir
                and .source.requested_ref == $ref)
            ' >/dev/null; then
            run env PATH="${lib.makeBinPath [ pkgs.git ]}:${
              if pkgs.stdenv.hostPlatform.isDarwin then
                lib.concatStringsSep ":" config.dotfiles.env.darwinPackageBinDirs
              else
                lib.makeBinPath [
                  pkgs.cargo
                  pkgs.rustc
                  pkgs.stdenv.cc
                  pkgs.nodejs_24
                ]
            }:$PATH" \
              ${herdrBin} plugin install "$repo''${subdir:+/$subdir}" --ref "$ref" --yes
          fi
        }

        update_herdr_plugin herdr-navigator thanhdat77/herdr-navigator

        ${lib.optionalString config.dotfiles.herdr.heeler.enable ''
          update_herdr_plugin heeler ZingerLittleBee/Heeler plugin

          # Ghostty launches Herd directly, without the interactive shell PATH.
          # Bind the plugin's runtime scripts to Node; refresh on every
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
