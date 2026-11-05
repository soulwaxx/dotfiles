#!/usr/bin/env python3
"""Check shared prompt links and safe migration from whole-directory links."""

import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def check_content(shared, pi):
    assert {p.name for p in shared.glob("*.md")} == {"adversarial.md", "lesson.md"}
    assert {p.name for p in pi.glob("*.md")} == {"init.md"}
    for path in sorted(shared.glob("*.md")):
        text = path.read_text()
        assert text.startswith("---\n"), path
        header, body = text[4:].split("---\n", 1)
        assert "description:" in header and "argument-hint:" in header, path
        assert "$ARGUMENTS" in body and "If no " in body, path
        assert re.findall(r"\$(?:\{[^}]*\}|[A-Za-z_@0-9]+)", body) == [
            "$ARGUMENTS"
        ], f"{path}: use only the shared argument syntax"


def check_migration(bash, script, dotfiles, target, old_source):
    for case in ("absent", "directory", "legacy", "chain", "unrelated", "dangling", "file"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            repo = root / "dotfiles"
            legacy = repo / old_source
            legacy.mkdir(parents=True)
            marker = legacy / "keep.md"
            marker.write_text("keep source untouched\n")
            destination = home / target
            destination.parent.mkdir(parents=True)
            if case == "directory":
                destination.mkdir()
                (destination / "local.md").write_text("local prompt\n")
            elif case == "legacy":
                destination.symlink_to(legacy)
            elif case == "chain":
                store_link = root / "store-link"
                store_link.symlink_to(legacy)
                destination.symlink_to(store_link)
            elif case in ("unrelated", "dangling"):
                other = root / "other"
                if case == "unrelated":
                    other.mkdir()
                destination.symlink_to(other)
            elif case == "file":
                destination.write_text("not a directory\n")

            before = destination.readlink() if destination.is_symlink() else None
            shell = (
                'set -euo pipefail\nHOME="$1"\nrun() { "$@"; }\n'
                + script.replace(dotfiles, str(repo))
            )
            # A second activation must be harmless too.
            for _ in range(2):
                subprocess.run([bash, "-c", shell, "migration", str(home)], check=True)
            assert marker.read_text() == "keep source untouched\n", case
            assert list(legacy.iterdir()) == [marker], case
            if case in ("legacy", "chain"):
                assert destination.is_dir() and not destination.is_symlink(), case
                assert not list(destination.iterdir()), case
            elif case == "absent":
                assert not destination.exists(), case
            elif case == "directory":
                assert (destination / "local.md").read_text() == "local prompt\n", case
            elif case in ("unrelated", "dangling"):
                assert destination.readlink() == before, case
            else:
                assert destination.read_text() == "not a directory\n", case


def main():
    fixtures = json.loads(Path(sys.argv[1]).read_text())
    check_content(Path(sys.argv[2]), Path(sys.argv[3]))
    bash = sys.argv[4]
    for hostname, fixture in fixtures.items():
        dotfiles = fixture["dotfiles"]
        sources = fixture["sources"]
        expected = {
            f"{prefix}/{name}.md": f"config/shared/prompts/{name}.md"
            for prefix in (".pi/agent/prompts", ".claude/commands")
            for name in ("adversarial", "lesson")
        }
        expected[".pi/agent/prompts/init.md"] = "config/pi/prompts/init.md"
        assert set(sources) == set(expected), hostname
        for target, source in sources.items():
            assert str(Path(source).readlink()) == f"{dotfiles}/{expected[target]}", (
                hostname,
                target,
            )
        check_migration(
            bash, fixture["piMigration"], dotfiles,
            ".pi/agent/prompts", "config/pi/prompts",
        )
        check_migration(
            bash, fixture["claudeMigration"], dotfiles,
            ".claude/commands", "config/claude/commands",
        )


if __name__ == "__main__":
    main()
