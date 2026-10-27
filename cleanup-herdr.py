#!/usr/bin/env python3
"""Remove user-level Herdr integrations and state. Preview by default; no backups."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile


def is_herdr_hook(command, home):
    if not isinstance(command, str) or "herdr-agent-state.sh" not in command:
        return False
    # Only remove a standalone invocation, never an unrelated compound command.
    parts = shlex.split(command)
    if parts and parts[0] in ("bash", "sh", "/bin/bash", "/bin/sh"):
        parts = parts[1:]
    paths = {
        str(home / ".claude/hooks/herdr-agent-state.sh"),
        "~/.claude/hooks/herdr-agent-state.sh",
        "$HOME/.claude/hooks/herdr-agent-state.sh",
        "${HOME}/.claude/hooks/herdr-agent-state.sh",
    }
    if (
        not parts
        or parts[0] not in paths
        or len(parts) > 2
        or (len(parts) == 2 and not re.fullmatch(r"[a-zA-Z0-9_-]+", parts[1]))
    ):
        raise ValueError(f"Review ambiguous Herdr hook manually: {command!r}")
    return True


def clean_settings(path, home):
    original = path.read_bytes()
    settings = json.loads(original)
    hooks = settings.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"Expected a hooks object in {path}")
    removed = 0
    for event, groups in list(hooks.items()):
        kept_groups = []
        for group in groups:
            kept = []
            for hook in group["hooks"]:
                if is_herdr_hook(hook.get("command"), home):
                    removed += 1
                else:
                    kept.append(hook)
            # Preserve existing empty groups and their metadata unless we removed a hook.
            if kept == group["hooks"] or kept:
                group["hooks"] = kept
                kept_groups.append(group)
        if kept_groups != groups:
            if kept_groups:
                hooks[event] = kept_groups
            else:
                del hooks[event]
    if removed:
        if path.is_symlink() or path.stat().st_nlink != 1:
            raise ValueError(f"Refusing to rewrite linked settings: {path}")
        return original, (json.dumps(settings, indent=2) + "\n").encode(), removed
    return None


def replace_settings(path, original, cleaned):
    # Claude can write settings at runtime. Refuse observed drift, and use an
    # atomic replacement so readers never see a partially written JSON file.
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, temporary = tempfile.mkstemp(prefix=".herdr-cleanup-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(cleaned)
            stream.flush()
            os.fsync(stream.fileno())
        if path.is_symlink() or path.read_bytes() != original:
            raise ValueError(f"Settings changed during cleanup; retry with Claude closed: {path}")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="permanently delete; no backups")
    args = parser.parse_args()
    home = Path.home()
    integrations = [
        (home / ".pi/agent/extensions/herdr-agent-state.ts", "pi"),
        (home / ".claude/hooks/herdr-agent-state.sh", "claude"),
    ]
    removals = []
    # Validate every input before changing anything. Never delete an unmarked
    # custom file just because its name happens to match the generated script.
    for path, integration in integrations:
        if not os.path.lexists(path):
            continue
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Refusing non-regular integration file: {path}")
        content = path.read_text()
        if "installed by herdr" not in content or f"HERDR_INTEGRATION_ID={integration}" not in content:
            raise ValueError(f"Refusing unmarked integration file: {path}")
        removals.append(path)
    for path in (home / ".config/herdr", home / ".local/state/herdr"):
        if os.path.lexists(path):
            removals.append(path)
    settings = home / ".claude/settings.json"
    change = clean_settings(settings, home) if os.path.lexists(settings) else None
    if not removals and not change:
        print("Herdr cleanup: already clean")
        return
    if change:
        print(f"Remove {change[2]} Herdr hook(s) from {settings}")
    for path in removals:
        print(f"Delete {path}")
    if not args.apply:
        print("Preview only. Run with --apply to permanently delete without backups.")
        return
    processes = subprocess.run(
        ["ps", "-A", "-o", "comm="], check=True, capture_output=True, text=True
    ).stdout.splitlines()
    if any(Path(command.strip()).name.startswith(("herdr", "heeler")) for command in processes):
        raise ValueError("Stop Herdr and Heeler before running cleanup")
    if change:
        replace_settings(settings, change[0], change[1])
    for path in removals:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()
    print("Herdr cleanup: complete (no backups). Restart pi and Claude to unload old hooks.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
        print(f"Herdr cleanup failed: {error}", file=sys.stderr)
        sys.exit(1)
