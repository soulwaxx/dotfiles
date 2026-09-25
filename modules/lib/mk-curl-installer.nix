{ lib, pkgs }:

{
  name,
  displayName,
  installDir,
  url,
  binPath,
  installerArgs ? [ ],
  extraPath ? [ ],
  versionFloor ? null,
  versionCommand ? null,
  postInstall ? "",
}:

let
  basePath = [
    "${pkgs.curl}/bin"
    "${pkgs.bash}/bin"
    "${pkgs.coreutils}/bin"
    "${pkgs.gnutar}/bin"
    "${pkgs.gzip}/bin"
  ];
  path = lib.concatStringsSep ":" (basePath ++ extraPath) + ":$PATH";
  versionCmd =
    if versionCommand != null then
      versionCommand
    else
      ''"$BIN_PATH" --version 2>/dev/null | ${pkgs.coreutils}/bin/cut -d' ' -f1'';
in

lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  _install_${name}() {
    local tmpfile checksum_file state_dir old_checksum new_checksum installer_status=0
    tmpfile=$(${pkgs.coreutils}/bin/mktemp)

    if ! ${pkgs.curl}/bin/curl -fsSL ${lib.escapeShellArg url} > "$tmpfile"; then
      ${pkgs.coreutils}/bin/rm -f "$tmpfile"
      return 1
    fi

    new_checksum=$(${pkgs.coreutils}/bin/sha256sum "$tmpfile" | ${pkgs.coreutils}/bin/cut -d' ' -f1)

    state_dir="$HOME/.local/state/dotfiles"
    checksum_file="$state_dir/${name}-installer.sha256"
    ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
    if [[ -f "$checksum_file" ]]; then
      old_checksum=$(${pkgs.coreutils}/bin/cat "$checksum_file")
      if [[ "$old_checksum" != "$new_checksum" ]]; then
        echo "${name}: WARN: upstream installer script changed since last switch" >&2
      fi
    fi
    ${pkgs.coreutils}/bin/printf '%s\n' "$new_checksum" > "$checksum_file"

    run env PATH="${path}" ${pkgs.bash}/bin/bash "$tmpfile" ${lib.escapeShellArgs installerArgs} || installer_status=$?
    ${pkgs.coreutils}/bin/rm -f "$tmpfile"
    return $installer_status
  }

  BIN_PATH="${binPath}"
  if [[ ! -x "$BIN_PATH" ]]; then
    verboseEcho "${name}: installing ${displayName} into ${installDir}"
    _install_${name} || {
      echo "${name}: ${displayName} install failed (curl or installer returned non-zero)" >&2
      exit 1
    }
  fi

  ${lib.optionalString (versionFloor != null) ''
    if [[ -x "$BIN_PATH" ]]; then
      INSTALLED_VERSION="$(${versionCmd})"
      if [[ -n "$INSTALLED_VERSION" ]] \
        && [[ "$(printf '%s\n' "${versionFloor}" "$INSTALLED_VERSION" | ${pkgs.coreutils}/bin/sort -V | ${pkgs.coreutils}/bin/head -n1)" != "${versionFloor}" ]]; then
        echo "${name}: installed version $INSTALLED_VERSION is below the ${versionFloor} floor; re-running installer" >&2
        _install_${name} || echo "${name}: WARN: update failed; keeping $INSTALLED_VERSION" >&2
      fi
    fi
  ''}

  ${lib.optionalString (postInstall != "") ''
    if [[ -x "$BIN_PATH" ]]; then
      ${postInstall}
    fi
  ''}
''
