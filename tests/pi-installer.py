#!/usr/bin/env python3
"""Check that the activation runner avoids terminal prompts and reports failures."""

import errno
import os
from pathlib import Path
import pty
import subprocess
import sys
import tempfile

node, runner, bash = sys.argv[1:]

with tempfile.TemporaryDirectory() as tmp:
    installer = Path(tmp) / "installer.sh"
    installer.write_text(
        """
set -eu
if ( : <>/dev/tty ) 2>/dev/null; then
  echo "installer still has a controlling terminal" >&2
  exit 2
fi
if read -r answer; then
  echo "installer stdin is not closed" >&2
  exit 3
fi
[[ "$TERM" == dumb && "$1" == "argument with spaces" ]]
echo "installer stdout"
echo "installer stderr" >&2
exit "${INSTALLER_STATUS:-0}"
"""
    )
    command = [node, runner, bash, str(installer), "argument with spaces"]

    # Start with a real controlling terminal: redirecting stdin alone would
    # leave /dev/tty accessible and the upstream installer waiting for input.
    pid, fd = pty.fork()
    if pid == 0:
        os.close(os.open("/dev/tty", os.O_RDWR))
        os.execv(node, command)
    output = b""
    try:
        while True:
            chunk = os.read(fd, 4096)
            if not chunk:
                break
            output += chunk
    except OSError as error:
        if error.errno != errno.EIO:
            raise
    finally:
        os.close(fd)
    _, status = os.waitpid(pid, 0)
    assert os.waitstatus_to_exitcode(status) == 0, output
    assert b"installer stdout" in output and b"installer stderr" in output, output

    result = subprocess.run(
        command,
        env={**os.environ, "INSTALLER_STATUS": "7"},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 7, result
    assert "installer stdout" in result.stdout, result
    assert "installer stderr" in result.stderr, result

    result = subprocess.run(
        [node, runner, "/no-such-pi-installer"],
        capture_output=True,
        check=False,
    )
    assert result.returncode == 1 and result.stderr, result

    result = subprocess.run(
        [node, runner, bash, "-c", "kill -TERM $$"], check=False
    )
    assert result.returncode == 1, result

print("pi-installer: ok")
