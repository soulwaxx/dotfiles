-- Rex key bindings. Validate with `rex config check`; apply with
-- `rex config reload` (bound to cmd+shift+r below). Appearance and terminal
-- settings are not read from this file: see config/rex/apply-settings.sh.

-- Herdr-style ctrl+a prefix, kept for muscle memory from the Herdr setup.
local p = "ctrl+a>"

-- Panes
rex.bind(p .. "v", "pane.split.right")
rex.bind(p .. "-", "pane.split.down")
rex.bind(p .. "h", "pane.focus.left")
rex.bind(p .. "j", "pane.focus.down")
rex.bind(p .. "k", "pane.focus.up")
rex.bind(p .. "l", "pane.focus.right")
rex.bind(p .. "z", "pane.zoom")
rex.bind(p .. "x", "pane.close")
rex.bind(p .. "=", "pane.balance")
rex.bind(p .. "[", "pane.copy_mode.enter")

-- Tabs and sessions
rex.bind(p .. "c", "client.tab.new")
rex.bind(p .. "n", "client.tab.next")
rex.bind(p .. "p", "client.tab.previous")
rex.bind(p .. ",", "client.tab.rename")
rex.bind(p .. "s", "session.switch")
rex.bind(p .. "b", "client.sidebar.toggle")
for i = 1, 9 do
  rex.bind(p .. i, "client.tab.goto", { index = i })
end

-- Pressing the prefix twice sends ctrl+a to the program (shell
-- beginning-of-line).
rex.bind(p .. "ctrl+a", "pane.send_key", { key = "ctrl+a" })

-- Resize mode: prefix r, then h/j/k/l repeatedly, escape to leave.
rex.bind(p .. "r", "client.mode.enter", { name = "resize" })
rex.mode("resize", {})
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("resize/" .. key, "pane.resize", { direction = direction })
end
rex.bind("resize/escape", "client.mode.exit")

-- Ghostty parity (modules/ghostty.nix)
rex.bind("cmd+shift+r", "client.config.reload")
-- Forward cmd+w to the program instead of closing, so Neovim can map <D-w>
-- to close a buffer.
rex.bind("cmd+w", "pane.send_key", { key = "cmd+w" })
