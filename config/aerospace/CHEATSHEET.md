# AeroSpace cheatsheet

Modifier is `alt`. AeroSpace tiles windows; `alt-shift-s` drops into a
short-lived **service** mode for layout resets and window joins.

## Main mode

| Keys | Action |
| --- | --- |
| `alt-h` / `j` / `k` / `l` | Focus left / down / up / right |
| `alt-shift-h` / `j` / `k` / `l` | Move the focused window left / down / up / right |
| `alt-1`..`9` | Switch to workspace 1-9 |
| `alt-shift-1`..`9` | Move the focused window to workspace 1-9 and follow it |
| `alt-t` | Tiles layout, alternating horizontal/vertical |
| `alt-a` | Accordion layout, alternating horizontal/vertical |
| `alt-f` | Toggle floating / tiling for the focused window |
| `alt-shift-f` | Toggle fullscreen |
| `alt-r` / `alt-e` | Shrink / grow the focused window (`resize smart -50` / `+50`) |
| `alt-n` / `alt-p` | Focus the next / previous window in tree order |
| `alt-tab` | Jump back to the previously focused workspace |
| `alt-shift-q` | Close the window (quits the app if it's the last window) |
| `alt-shift-s` | Enter service mode |

## Service mode (`alt-shift-s`)

| Keys | Action |
| --- | --- |
| `esc` | Reload config, back to main mode |
| `r` | Flatten the workspace tree (reset layout), back to main mode |
| `f` | Toggle floating/tiling, back to main mode |
| `backspace` | Close every window but the current one, back to main mode |
| `alt-shift-h` / `j` / `k` / `l` | Join the focused window with the one left / down / up / right, back to main mode |

## Why no punctuation/letter workspace bindings, and a trade-off on 5/9

This machine runs the **Italian-Pro keyboard layout**, but AeroSpace's
`qwerty` key-mapping preset resolves every binding by physical **US keycode**,
not by the character printed on the keycap. On an Italian-Pro layout those US
punctuation keycodes (`-` `=` `;` `,` `.` `/`) type accented Italian letters
instead, and the actual `@ # [ ] { }` characters only come out with Option
held down on non-digit keys. Binding `alt-<punctuation>` would either
silently fail to fire or steal a combo needed to type that character, and
letter-based workspace bindings (as used upstream for workspaces 10+) would
collide with letters already bound elsewhere (`h j k l t a f r e n p`). So
workspaces use only digits 1-9, with no punctuation or letter bindings.

Known accepted trade-off: **`alt-5` and `alt-9` steal Option+5 (`~`) and
Option+9 (`` ` ``)** on this layout — both used constantly in shell paths
and command substitution. Workspaces 5 and 9 were still bound for a full
1-9 range; if `~`/`` ` `` stop typing while AeroSpace is running, this is
why.
