#!/usr/bin/env python3
"""Exercise permanent cleanup against isolated homes, never the real host state."""

import copy
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "cleanup-herdr.py"


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / "home with spaces"
        self.home.mkdir()
        self.bin = Path(self.temporary.name) / "bin"
        self.bin.mkdir()
        ps = self.bin / "ps"
        ps.write_text('#!/bin/sh\nprintf "%s\\n" "${TEST_PROCESS:-pi}"\nexit "${TEST_PS_STATUS:-0}"\n')
        ps.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home), "PATH": f"{self.bin}:{os.environ['PATH']}"}
        self.pi = self.write(".pi/agent/extensions/herdr-agent-state.ts", "// installed by herdr\n// HERDR_INTEGRATION_ID=pi\n")
        self.claude = self.write(".claude/hooks/herdr-agent-state.sh", "# installed by herdr\n# HERDR_INTEGRATION_ID=claude\n")
        self.write(".config/herdr/session-snapshots/session.json", "old session")
        self.write(".local/state/herdr/plugins/heeler/notify/state.json", "old state")
        self.unrelated = self.write(".pi/agent/extensions/keep.ts", "keep")
        self.settings = {
            "enabledPlugins": {"keep@keep": True},
            "permissions": {"defaultMode": "auto"},
            "hooks": {
                "SessionStart": [{"matcher": "startup", "hooks": [
                    {"type": "command", "command": f"bash '{self.claude}' session", "timeout": 10},
                    {"type": "command", "command": "keep-this-hook"},
                ]}],
                "Stop": [{"matcher": "*", "hooks": [
                    {"type": "command", "command": 'sh "$HOME/.claude/hooks/herdr-agent-state.sh" idle'},
                ]}],
                "Notification": [{"hooks": [{"command": "notify-attention.sh"}]}],
                "Empty": [],
            },
        }
        self.settings_path = self.write(".claude/settings.json", json.dumps(self.settings))
        self.settings_path.chmod(0o640)
        self.write(".pi/agent/settings.json", '{"packages": ["keep"]}')

    def write(self, relative, content):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def run_cleanup(self, *args, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *args], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return result

    def test_preview_then_apply_and_repeat(self):
        before = self.settings_path.read_bytes()
        self.run_cleanup()
        self.assertEqual(self.settings_path.read_bytes(), before)
        self.assertTrue(self.pi.exists())
        self.run_cleanup("--apply")
        expected = copy.deepcopy(self.settings)
        expected["hooks"]["SessionStart"][0]["hooks"].pop(0)
        del expected["hooks"]["Stop"]
        self.assertEqual(json.loads(self.settings_path.read_text()), expected)
        self.assertEqual(self.settings_path.stat().st_mode & 0o777, 0o640)
        for path in (self.pi, self.claude, self.home / ".config/herdr", self.home / ".local/state/herdr"):
            self.assertFalse(path.exists(), path)
        self.assertEqual(self.unrelated.read_text(), "keep")
        self.assertEqual((self.home / ".pi/agent/settings.json").read_text(), '{"packages": ["keep"]}')
        self.assertIn("already clean", self.run_cleanup("--apply").stdout)
        self.assertFalse(list(self.home.rglob("*backup*")))
        self.assertFalse(list(self.home.rglob(".herdr-cleanup-*")))

    def test_missing_home_state(self):
        self.env["HOME"] = str(Path(self.temporary.name) / "empty")
        self.assertIn("already clean", self.run_cleanup("--apply").stdout)

    def test_invalid_settings_prevents_all_deletions(self):
        self.settings_path.write_text("not json")
        self.run_cleanup("--apply", success=False)
        self.assertTrue(self.pi.exists())
        self.assertTrue((self.home / ".config/herdr").exists())

    def test_unmarked_file_prevents_all_deletions(self):
        self.pi.write_text("custom file")
        self.run_cleanup("--apply", success=False)
        self.assertTrue(self.claude.exists())
        self.assertEqual(json.loads(self.settings_path.read_text()), self.settings)

    def test_ambiguous_command_prevents_all_deletions(self):
        self.settings["hooks"]["SessionStart"][0]["hooks"][0]["command"] += " && keep-this"
        self.settings_path.write_text(json.dumps(self.settings))
        self.run_cleanup("--apply", success=False)
        self.assertTrue(self.pi.exists())

    def test_linked_settings_are_not_rewritten(self):
        target = self.settings_path.with_name("real-settings.json")
        self.settings_path.rename(target)
        self.settings_path.symlink_to(target)
        before = target.read_bytes()
        self.run_cleanup("--apply", success=False)
        self.assertEqual(target.read_bytes(), before)
        self.assertTrue(self.pi.exists())

    def test_linked_integration_is_rejected(self):
        self.pi.unlink()
        self.pi.symlink_to(self.unrelated)
        self.run_cleanup("--apply", success=False)
        self.assertTrue(self.claude.exists())
        self.assertEqual(self.unrelated.read_text(), "keep")

    def test_state_symlink_only_unlinks_the_link(self):
        import shutil
        state = self.home / ".config/herdr"
        shutil.rmtree(state)
        external = Path(self.temporary.name) / "outside"
        external.mkdir()
        keep = external / "keep"
        keep.write_text("outside data")
        state.symlink_to(external, target_is_directory=True)
        self.run_cleanup("--apply")
        self.assertFalse(state.is_symlink())
        self.assertEqual(keep.read_text(), "outside data")

    def test_running_herdr_or_heeler_prevents_changes(self):
        for process in ("/usr/bin/herdr", "/tmp/heeler-plugin"):
            with self.subTest(process=process):
                self.env["TEST_PROCESS"] = process
                self.run_cleanup("--apply", success=False)
                self.assertTrue(self.pi.exists())
                self.assertEqual(json.loads(self.settings_path.read_text()), self.settings)

    def test_process_check_failure_prevents_changes(self):
        self.env["TEST_PS_STATUS"] = "1"
        self.run_cleanup("--apply", success=False)
        self.assertTrue(self.pi.exists())

    def test_settings_drift_is_not_overwritten(self):
        module = runpy.run_path(str(SCRIPT))
        before = self.settings_path.read_bytes()
        self.settings_path.write_text("changed by Claude")
        with self.assertRaises(ValueError):
            module["replace_settings"](self.settings_path, before, b"{}")
        self.assertEqual(self.settings_path.read_text(), "changed by Claude")
        self.assertFalse(list(self.home.rglob(".herdr-cleanup-*")))


unittest.main()
