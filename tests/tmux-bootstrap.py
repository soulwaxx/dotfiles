"""Exercise TPM bootstrap with fake executables; never touch a live tmux server."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve()
BASH = sys.argv.pop(1)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.plugins = self.root / "plugins"
        self.fixture = self.root / "tpm-fixture"
        (self.fixture / ".git").mkdir(parents=True)
        self.log = self.root / "commands"
        self.env = {
            **os.environ,
            "HOME": str(self.root),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "LOG": str(self.log),
            "TPM_FIXTURE": str(self.fixture),
            "PLUGINS": str(self.plugins),
            "TERM": "unknown",
        }
        self.executable(self.bin / "tmux", '''
            printf 'tmux TERM=%s %s\n' "$TERM" "$*" >> "$LOG"
            exit "${SERVER_STATUS:-0}"
        ''')
        self.executable(self.bin / "git", '''
            printf 'git %s\n' "$*" >> "$LOG"
            [[ $* == 'clone --depth 1 https://github.com/tmux-plugins/tpm '* ]] || exit 90
            [[ ${CLONE_STATUS:-0} == 0 ]] || exit "$CLONE_STATUS"
            cp -R "$TPM_FIXTURE" "${@: -1}"
        ''')
        self.executable(self.fixture / "bin/install_plugins", '''
            echo install >> "$LOG"
            mkdir -p "$PLUGINS/tmux-fzf" "$PLUGINS/tmux-fzf-url"
            exit "${INSTALL_STATUS:-0}"
        ''')
        self.executable(self.fixture / "bin/clean_plugins", '''
            echo clean >> "$LOG"
            rm -rf "$PLUGINS/retired"
            exit "${CLEAN_STATUS:-0}"
        ''')

    def executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"#!{BASH}\nset -eu\n{body}\n")
        path.chmod(0o755)

    def run_bootstrap(self, **env):
        result = subprocess.run(
            [BASH, str(SCRIPT), str(self.bin / "tmux"), str(self.plugins), "/nix/xre"],
            env={**self.env, **env}, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.log.read_text() if self.log.exists() else ""
        return result, commands

    def test_clone_install_clean_and_link(self):
        (self.plugins / "retired").mkdir(parents=True)
        result, commands = self.run_bootstrap()
        self.assertEqual(result.stderr, "")
        self.assertIn("git clone --depth 1 https://github.com/tmux-plugins/tpm", commands)
        self.assertIn(
            f"tmux TERM=screen-256color start-server ; set-environment -g TMUX_PLUGIN_MANAGER_PATH {self.plugins}/",
            commands,
        )
        self.assertIn("install\nclean\n", commands)
        self.assertFalse((self.plugins / "retired").exists())
        self.assertTrue((self.plugins / "tmux-fzf").is_dir())
        self.assertEqual(os.readlink(self.plugins / "tmux-fzf-url/bin/xre"), "/nix/xre")

    def test_existing_checkouts_are_not_updated(self):
        self.run_bootstrap()
        self.log.write_text("")
        _, commands = self.run_bootstrap(TERM="xterm-256color")
        self.assertNotIn("git ", commands)
        self.assertIn("TERM=xterm-256color", commands)
        self.assertIn("install\nclean\n", commands)

    def test_clone_failure_only_warns(self):
        result, commands = self.run_bootstrap(CLONE_STATUS="1")
        self.assertIn("failed to clone TPM", result.stderr)
        self.assertNotIn("tmux TERM=", commands)

    def test_install_failure_still_cleans(self):
        result, commands = self.run_bootstrap(INSTALL_STATUS="1")
        self.assertIn("TPM plugin install failed", result.stderr)
        self.assertIn("install\nclean\n", commands)

    def test_cleanup_failure_only_warns(self):
        result, _ = self.run_bootstrap(CLEAN_STATUS="1")
        self.assertIn("TPM plugin cleanup failed", result.stderr)

    def test_server_failure_skips_install_and_cleanup(self):
        result, commands = self.run_bootstrap(SERVER_STATUS="1")
        self.assertIn("skipping TPM plugin install", result.stderr)
        self.assertNotIn("\ninstall\n", commands)
        self.assertNotIn("\nclean\n", commands)

    def test_terminal_fallbacks(self):
        self.run_bootstrap()
        for term in ("", "unknown", "dumb"):
            with self.subTest(term=term):
                _, commands = self.run_bootstrap(TERM=term)
                self.assertIn("TERM=screen-256color", commands)


if __name__ == "__main__":
    unittest.main()
