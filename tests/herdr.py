#!/usr/bin/env python3
"""Behavior tests for the generated Herd integration activation snippet."""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


FIXTURE = Path(sys.argv[1])
BASH = sys.argv[2]


def run_case(fixture):
    with tempfile.TemporaryDirectory(prefix="herdr-test-") as tmp:
        root = Path(tmp)
        home = root / "home"
        home.mkdir()
        (home / ".claude").mkdir()
        (home / ".local/state/dotfiles").mkdir(parents=True)
        settings = home / ".claude/settings.json"
        settings.write_text('{"integrations":{"keep":true}}\n')
        log = root / "calls.jsonl"

        bindir = root / "bin"
        bindir.mkdir()
        herdr = bindir / "herdr"
        herdr.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "a=sys.argv[1:]\n"
            "open(os.environ['HERDR_LOG'],'a').write(json.dumps(a)+'\\n')\n"
            "sys.exit(0 if a[:2] == ['integration','install'] else 2)\n"
        )
        herdr.chmod(0o755)

        script = fixture["script"]
        script = re.sub(r"/nix/store/[^ '\"$]+/bin/install", "install", script)
        script = re.sub(r"/nix/store/[^ '\"$]+/bin/herdr", str(herdr), script)
        script = script.replace("/opt/homebrew/bin/herdr", str(herdr))
        script_file = root / "activation.sh"
        script_file.write_text("set -euo pipefail\nrun() { \"$@\"; }\n" + script + "\n")

        env = os.environ.copy()
        env.update({
            "HOME": str(home),
            "PATH": str(bindir) + os.pathsep + env["PATH"],
            "HERDR_LOG": str(log),
        })
        result = subprocess.run([BASH, str(script_file)], env=env, text=True, capture_output=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        backup = home / ".local/state/dotfiles/claude-settings.last.json"
        return result, calls, backup.read_text() if backup.exists() else None


def expect(condition, message):
    if not condition:
        raise AssertionError(message)


def run_host(host, fixture):
    expect("script" in fixture, f"{host}: missing script")
    result, calls, backup = run_case(fixture)
    expect(result.returncode == 0, f"{host}: activation failed: {result.stderr}")
    expect(
        calls == [["integration", "install", "pi"], ["integration", "install", "claude"]],
        f"{host}: unexpected herdr calls: {calls}",
    )
    expect(backup == '{"integrations":{"keep":true}}\n', "settings backup missing or integrations were not preserved")
    print(f"herdr activation behavior passed ({host})")


def main():
    fixtures = json.loads(FIXTURE.read_text())
    expect(fixtures, "fixture must contain at least one host")
    for host, fixture in fixtures.items():
        run_host(host, fixture)


if __name__ == "__main__":
    main()
