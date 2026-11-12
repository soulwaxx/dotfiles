{ lib, pkgs }:

{
  name,
  displayName,
  installDir,
  url,
  binPath,
  installerArgs ? [ ],
  installerCommand ? [ "${pkgs.bash}/bin/bash" ],
  extraPath ? [ ],
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

    run env PATH="${path}" ${lib.escapeShellArgs installerCommand} "$tmpfile" ${lib.escapeShellArgs installerArgs} || installer_status=$?
    ${pkgs.coreutils}/bin/rm -f "$tmpfile"
    return $installer_status
  }

  BIN_PATH="${binPath}"
  if [[ ! -x "$BIN_PATH" ]]; then
    verboseEcho "${name}: installing ${displayName} into ${installDir}"
    _install_${name} || {
      echo "${name}: ${displayName} install failed (curl or installer returned non-zero)" >&2
      false
    }
  fi

  ${lib.optionalString (postInstall != "") ''
    if [[ -x "$BIN_PATH" ]]; then
      ${postInstall}
    fi
  ''}
''
