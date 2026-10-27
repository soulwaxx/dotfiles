"""Check generated tmux wiring and behavior on private sockets with a fake TPM."""

import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time
import unittest

FIXTURES = json.loads(Path(sys.argv.pop(1)).read_text())
CONFIG = Path(sys.argv.pop(1)).read_text()
TMUX = sys.argv.pop(1)
ZSH = sys.argv.pop(1)
BASH = sys.argv.pop(1)


def environment_path(fixture):
    environment = Path(fixture["environment"]).read_text()
    line = next(line for line in environment.splitlines() if line.startswith("set-environment -g PATH "))
    return environment, shlex.split(line)[3]


class ConfigTests(unittest.TestCase):
    def test_generated_files_and_package_ownership(self):
        for host, fixture in FIXTURES.items():
            with self.subTest(host=host):
                self.assertEqual(os.readlink(fixture["source"]), fixture["expectedSource"])
                self.assertFalse(fixture["generatedWrapper"])
                self.assertFalse(fixture["hasDotfilesConf"])
                self.assertEqual(fixture["tmuxInstalled"], not fixture["darwin"])
                self.assertEqual(
                    fixture["socketDirectory"],
                    None if fixture["darwin"] else '${XDG_RUNTIME_DIR:-"/run/user/$(id -u)"}',
                )
                environment, path = environment_path(fixture)
                self.assertNotIn("$PATH", path)
                self.assertIn(f'set -g default-shell "{fixture["shell"]}"', environment)
                self.assertIn(f'"{fixture["configHome"]}/tmux/plugins/"', environment)
                entries = path.split(":")
                self.assertTrue(entries[0].startswith("/nix/store/"))
                profile = (
                    f'/etc/profiles/per-user/{Path(fixture["homeDirectory"]).name}/bin'
                    if fixture["darwin"] else f'{fixture["homeDirectory"]}/.nix-profile/bin'
                )
                user = f'{fixture["homeDirectory"]}/.local/bin'
                self.assertLess(entries.index(profile), entries.index(user))
                if fixture["darwin"]:
                    self.assertLess(entries.index("/opt/homebrew/bin"), entries.index(profile))
                self.assertEqual(entries[-4:], ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])

    def test_launch_commands_and_shell_wrapper(self):
        for host, fixture in FIXTURES.items():
            with self.subTest(host=host), tempfile.TemporaryDirectory(prefix="tmux-launch-") as directory:
                self.assertEqual(len(fixture["ghosttyCommand"]), 1)
                command = shlex.split(fixture["ghosttyCommand"][0])
                self.assertEqual(command[1:], ["new-session"])
                if fixture["darwin"]:
                    self.assertEqual(command[0], "direct:/opt/homebrew/bin/tmux")
                else:
                    self.assertTrue(command[0].startswith("direct:/nix/store/"))
                    self.assertTrue(command[0].endswith("/bin/tmux"))
                wrapper = re.search(r"(?ms)^tmux\(\) \{\n.*?^\}", fixture["shellInit"])
                self.assertIsNotNone(wrapper)
                fake = Path(directory) / "tmux"
                fake.write_text(f'#!{BASH}\nprintf \'%s\\n\' "$@"\n')
                fake.chmod(0o755)
                for args, expected in [([], ["new-session", "-A", "-s", "home"]),
                                       (["list-sessions"], ["list-sessions"])]:
                    result = subprocess.run(
                        [ZSH, "-f", "-c", wrapper[0] + '\ntmux "$@"', "test", *args],
                        env={**os.environ, "PATH": directory}, text=True,
                        capture_output=True, check=True, timeout=10,
                    )
                    self.assertEqual(result.stdout.splitlines(), expected)

    def test_plugins_and_theme_declarations(self):
        plugins = [shlex.split(line)[3] for line in CONFIG.splitlines()
                   if line.startswith("set -g @plugin ")]
        self.assertEqual(plugins, ["tmux-plugins/tpm", "catppuccin/tmux#v2.3.2",
                                  "tmux-plugins/tmux-resurrect", "omerxx/tmux-floax",
                                  "wfxr/tmux-fzf-url", "sainnhe/tmux-fzf"])
        self.assertIn("@resurrect-capture-pane-contents 'off'", CONFIG)
        self.assertIn("@resurrect-strategy-nvim 'session'", CONFIG)
        self.assertIn("Restore tmux session from last snapshot? (y/n)", CONFIG)

    def test_isolated_runtime_and_reload(self):
        for host, fixture in FIXTURES.items():
            with self.subTest(host=host), tempfile.TemporaryDirectory(prefix="tmux-config-") as directory:
                root = Path(directory)
                plugins = root / "plugins"
                tpm = plugins / "tpm/tpm"
                tpm.parent.mkdir(parents=True)
                # Never load real plugins or touch their mutable user state.
                tpm.write_text(
                    f'#!{BASH}\nset -eu\n'
                    'tmux bind C-s display-message save\n'
                    'tmux bind C-r display-message restore\n'
                    'printf \'%s\\n\' "$TMUX" > "$TMUX_TEST_LOG"\n'
                )
                tpm.chmod(0o755)
                environment, path = environment_path(fixture)
                # Homebrew and user profiles do not exist in the Nix sandbox.
                environment = environment.replace(f'"{path}"', f'"{Path(TMUX).parent}:{path}"')
                environment = environment.replace(f'{fixture["configHome"]}/tmux/plugins/', f'{plugins}/')
                env_file = root / "environment.conf"
                env_file.write_text(environment)
                config = root / "tmux.conf"
                config.write_text(CONFIG.replace("~/.config/tmux/environment.conf", str(env_file)))
                socket = root / "socket"
                log = root / "tpm-loaded"
                command = [TMUX, "-S", str(socket)]
                env = {**os.environ, "HOME": directory, "XDG_CONFIG_HOME": directory,
                       "TMUX_TEST_LOG": str(log), "TERM": "screen-256color"}
                env.pop("TMUX", None)

                def tmux(*args, check=True):
                    return subprocess.run(command + list(args), env=env, text=True,
                                          capture_output=True, check=check, timeout=10)

                def option(name, scope="-g"):
                    return tmux("show-options", scope, "-v", name).stdout.strip()

                def wait_for_tpm():
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        if (log.exists()
                                and tmux("list-keys", "-T", "prefix", "C-s", check=False).returncode != 0
                                and tmux("list-keys", "-T", "prefix", "C-r", check=False).returncode != 0):
                            return
                        time.sleep(0.05)
                    self.fail("TPM stub did not load and remove direct snapshot bindings")

                try:
                    result = tmux("-f", str(config), "new-session", "-d", "-s", "test", f"{BASH} -c 'sleep 120'")
                    self.assertEqual(result.stderr, "")
                    wait_for_tpm()
                    self.assertTrue(log.read_text().startswith(str(socket) + ","))
                    for name, expected in {
                        "default-terminal": "tmux-256color", "default-shell": fixture["shell"],
                        "prefix": "C-a", "base-index": "1", "pane-base-index": "1",
                        "history-limit": "100000", "mouse": "on", "focus-events": "on",
                        "mode-keys": "vi", "status-keys": "emacs", "status-interval": "15",
                        "aggressive-resize": "off", "clock-mode-style": "12",
                        "detach-on-destroy": "on", "popup-border-lines": "rounded",
                        "pane-border-lines": "single", "pane-border-status": "top",
                        "allow-passthrough": "on", "allow-rename": "off", "automatic-rename": "off",
                        "bell-action": "other", "visual-bell": "off",
                        "@catppuccin_flavor": "mocha", "@catppuccin_window_status_style": "rounded",
                    }.items():
                        self.assertEqual(option(name), expected, name)
                    for name, expected in {"extended-keys": "on", "extended-keys-format": "csi-u",
                                           "set-clipboard": "external", "escape-time": "10"}.items():
                        self.assertEqual(option(name, "-s"), expected, name)
                    for name in ["@catppuccin_window_text", "@catppuccin_window_current_text"]:
                        self.assertEqual(tmux("show-options", "-g", "-v", name).stdout.rstrip("\n"), " #W")
                    for key in ["+", "Y", "Enter", "|", "C-b"]:
                        self.assertNotEqual(tmux("list-keys", "-T", "prefix", key, check=False).returncode, 0)
                    for table, key, expected in [
                        ("prefix", "v", "split-window -h"), ("prefix", "m", "select-pane -m"),
                        ("prefix", "t", "choose-tree"), ("prefix", "o", "sesh picker -i"),
                        ("copy-mode-vi", "H", "top-line"), ("copy-mode-vi", "L", "bottom-line"),
                        ("copy-mode-vi", "Escape", "clear-selection"),
                        ("copy-mode-vi", "C-v", "rectangle-toggle"),
                        ("root", "WheelUpPane", "copy-mode -e"),
                        ("root", "WheelDownPane", "send -M"),
                        ("copy-mode-vi", "WheelUpPane", "-N 5 scroll-up"),
                        ("copy-mode-vi", "WheelDownPane", "-N 5 scroll-down"),
                    ]:
                        self.assertIn(expected, tmux("list-keys", "-T", table, key).stdout)
                    self.assertNotEqual(tmux("list-keys", "-T", "copy-mode-vi", "Y", check=False).returncode, 0)
                    before_path = tmux("show-environment", "-g", "PATH").stdout
                    before_features = tmux("show-options", "-s", "terminal-features").stdout
                    # Simulate the previous theme overrides on an already running server.
                    cleared = ["@catppuccin_status_background", "@catppuccin_window_number_position",
                               "@catppuccin_window_number_color", "@catppuccin_window_current_number",
                               "@catppuccin_window_current_text_color", "@catppuccin_window_current_number_color",
                               "@catppuccin_window_flags", "@catppuccin_pane_active_border_style",
                               "@catppuccin_pane_border_style", "@catppuccin_status_connect_separator",
                               "@catppuccin_status_left_separator", "@catppuccin_status_right_separator"]
                    for name in cleared:
                        tmux("set-option", "-g", name, "stale-override")
                    for _ in range(2):
                        log.unlink()
                        result = tmux("source-file", str(config))
                        self.assertEqual(result.stderr, "")
                        wait_for_tpm()
                        self.assertEqual(tmux("show-environment", "-g", "PATH").stdout, before_path)
                        self.assertEqual(tmux("show-options", "-s", "terminal-features").stdout, before_features)
                        for name in cleared:
                            self.assertEqual(tmux("show-options", "-gqv", name).stdout, "", name)
                    self.assertIn("xterm-ghostty*:RGB:usstyle:extkeys:hyperlinks", before_features)
                    self.assertIn("ghostty:RGB:usstyle:extkeys:hyperlinks", before_features)
                finally:
                    # This socket belongs exclusively to this test, never the live server.
                    tmux("kill-server", check=False)


if __name__ == "__main__":
    unittest.main()
