# Neovim (LazyVim) cheatsheet

Leader is `<Space>`. File finding and live grep use **fff.nvim**; other sources and the explorer use **snacks.picker**. Project search-and-replace is **grug-far**.
Meta-tip: press `<Space>` and pause. which-key lists every binding under it. `<leader>sk` searches all keymaps. This sheet is the high-value subset, not the full set.

## The three you asked for

### Two files side by side (vertical split)

| Keys | Action |
| --- | --- |
| `<leader>\|` | Split window right (vertical split) |
| `<leader>-` | Split window below (horizontal split) |
| `<C-h>` / `<C-l>` | Move focus to the left / right window |
| `<C-j>` / `<C-k>` | Move focus to the lower / upper window |
| `<leader>wd` | Close the focused window |
| `<C-Up/Down/Left/Right>` | Resize the focused window |

Workflow: open file A, press `<leader>|`, then `<leader><space>` to find file B in the new split.

### Find and replace

| Keys | Scope |
| --- | --- |
| `:%s/old/new/g` | Current file (add `c` flag, `:%s/old/new/gc`, to confirm each) |
| `:s/old/new/g` (after visual select) | Selected lines only |
| `<leader>sr` | **Project-wide** via grug-far: live preview, restrict by Files path or glob |
| `<leader>cr` | Rename the symbol under the cursor (LSP, semantic, respects scope) |

Use `<leader>cr` over text replace when renaming a variable or function: it follows the language server, not raw text.

### Grep / find in a folder

| Keys | Action |
| --- | --- |
| `<leader>/` / `<leader>sg` | Live grep with fff.nvim (Snacks Explorer root when open, otherwise cwd) |
| `<leader><space>` / `<leader>ff` | Find files with fff.nvim |
| `<leader>sG` | Snacks live grep in the current working directory |
| `<leader>sw` | Snacks grep for the word under the cursor (works in visual mode too) |

fff honors `.gitignore` and picker-only `.ignore` files. Snacks shows hidden and gitignored files, excluding only the explicit ignored globs (`.pytest_cache`, `.terraform`, `.venv`, `__pycache__`, and `venv`); its `<a-h>` and `<a-i>` keys toggle hidden/ignored files.

To scope a grep to one subfolder: open it in the explorer (`<leader>e`) and search from there, or use grug-far (`<leader>sr`) and set its Files field to the folder path or a glob.

## Files and buffers

| Keys | Action |
| --- | --- |
| `<leader>e` | Snacks explorer (project root), `<leader>E` for cwd |
| `<S-l>` / `<S-h>` | Next / previous buffer |
| `<leader>,` | Switch buffer via picker |
| `<leader>bd` | Delete the current buffer |
| `<C-s>` | Save file |

### File operations (Snacks explorer)

In the explorer, use `<Tab>` or visual mode to select multiple files. Navigate to the destination and press `m` to move or `c` to copy the selection. Use `r` to rename, `d` to delete, and `a` to create a file or directory (end the name with `/` for a directory). Deletes use the system trash when available.

## Entering insert mode

| Keys | Action |
| --- | --- |
| `i` | Insert before the cursor |
| `a` | Append (insert) after the cursor |
| `I` | Insert at the first non-blank character of the line |
| `A` | Append at the end of the line |
| `o` | Open a new line below the current line and insert |
| `O` | Open a new line above the current line and insert |
| `gi` | Go to the last insert position and start inserting |

Return to Normal mode with `Esc` (or the custom `jk` in this config).

## Operators + motions (the grammar)

| Keys | Action |
| --- | --- |
| `d` | Delete operator (waits for a motion or text object) |
| `c` | Change operator: delete, then enter Insert mode |
| `y` | Yank (copy) operator |
| `>` / `<` | Indent / outdent operator |
| `gc` | Toggle comment operator (also `gcc` on one line) |
| `w` | Forward to start of next word |
| `e` | Forward to end of word |
| `b` | Back to start of previous word |
| `$` | To end of line |
| `0` | To start of line |
| `^` | To first non-blank character of line |
| `gg` / `G` | To first / last line of buffer |
| `{` / `}` | Backward / forward one paragraph |
| `daw` | Delete a word (including surrounding space) |
| `ciw` | Change inner word |
| `ci"` | Change inside double quotes |
| `ci(` / `ci{` | Change inside parentheses / braces |
| `dap` | Delete a paragraph |
| `yi(` | Yank inside parentheses |
| `dt,` | Delete until (but not including) the comma |
| `d/foo` | Delete until the next search match `foo` |
| `>ip` | Indent a paragraph |
| `.` | Repeat the last change |

Think `operator` + `motion` (or text object): `d$` deletes to end of line, `caw` changes a word, and a count like `d2w` doubles the motion.

## Text objects

| Keys | Action |
| --- | --- |
| `iw` / `aw` | Inner word / a word (includes trailing space) |
| `is` / `as` | Inner sentence / a sentence |
| `ip` / `ap` | Inner paragraph / a paragraph |
| `i"` / `a"` | Inside / around double quotes |
| `i'` / `a'` | Inside / around single quotes |
| `` i` `` / `` a` `` | Inside / around backticks |
| `i(` / `a(` | Inside / around parentheses (also `ib` / `ab`) |
| `i{` / `a{` | Inside / around braces (also `iB` / `aB`) |
| `i[` / `a[` | Inside / around brackets |
| `i<` / `a<` | Inside / around angle brackets |
| `it` / `at` | Inside / around HTML/XML tag |

`i` = inner (delimiters excluded), `a` = around (delimiters included). Use `ci"` to change the string contents, `da"` to remove the quotes too.

## Visual mode

| Keys | Action |
| --- | --- |
| `v` | Enter character-wise Visual mode |
| `V` | Enter line-wise Visual mode |
| `<C-v>` | Enter Visual Block mode (column selection) |
| `o` | In Visual mode, jump to the other end of the selection |
| `>` / `<` | Indent / outdent the selection |
| `y` / `d` / `c` | Yank, delete, or change the selection |
| `u` / `U` / `~` | Lowercase, uppercase, or toggle case of selection |
| `:` | Start an Ex command on the selected range |
| `gv` | Reselect the last Visual selection |
| `<C-v> ... I` | In Visual Block, insert at the start of every selected line |
| `<C-v> ... A` | In Visual Block, append at the end of every selected line |

In Visual Block, select a column with `<C-v>`, press `I` (insert before) or `A` (append after), type the text, then `<Esc>` — the edit appears on every selected line. In character-wise Visual, plain `a` and `i` are text-object prefixes, not insert commands; to insert around a selection use block `I`/`A` or `c` to replace.

## Editing shortcuts

| Keys | Action |
| --- | --- |
| `x` | Delete the character under the cursor |
| `r` | Replace the character under the cursor with the next typed character |
| `R` | Enter Replace mode: overwrite characters as you type |
| `s` | Substitute the character under the cursor (delete it and insert) |
| `S` / `cc` | Change the whole line |
| `C` | Change from cursor to end of line |
| `D` | Delete from cursor to end of line |
| `J` | Join the current line with the next (adds a space) |
| `gJ` | Join lines without adding a space |
| `u` | Undo last change |
| `<C-r>` | Redo |
| `~` | Toggle case of the character under the cursor |
| `p` | Paste after the cursor |
| `P` | Paste before the cursor |
| `xp` | Swap the current character with the next |
| `ddp` | Swap the current line with the next |

`D` deletes to end of line; `C` does the same and drops you into Insert mode.

## Marks & jumps

| Keys | Action |
| --- | --- |
| ``` `` ``` | Jump to the exact position before the last jump |
| `<C-o>` | Jump backward in the jump list |
| `<C-i>` | Jump forward in the jump list |
| `ma` | Set mark `a` at the cursor position |
| `` `a `` | Jump to mark `a` (line and column) |
| `'a` | Jump to the line of mark `a` |
| `%` | Jump to the matching bracket or tag |
| `gg` / `G` | Go to first / last line |
| `{count}G` | Go to line `{count}` (for example, `42G`) |
| `:{count}` | Go to line `{count}` (for example, `:42`) |

Use `<C-o>` and `<C-i>` to retrace `gd`, search, or other jumps.

## Code and LSP

| Keys | Action |
| --- | --- |
| `gd` / `gr` | Go to definition / references |
| `gI` / `gy` | Go to implementation / type definition |
| `K` | Hover docs |
| `<leader>ca` | Code action |
| `<leader>cr` | Rename symbol |
| `<leader>cf` | Format buffer (conform) |
| `]d` / `[d` | Next / previous diagnostic |
| `gcc` / `gc` | Toggle comment (line / selection) |

## Diffing two files (builtin)

No plugin involved. Use this for comparing any two files, including files from different projects or outside git.

| Command | Action |
| --- | --- |
| `nvim -d a.txt b.txt` | Open two files already in diff mode (shell) |
| `:vert diffsplit path/to/other` | Diff the current buffer against a file, side by side |
| `:windo diffthis` | Turn every window in the current tab into a diff |
| `:diffoff!` | Leave diff mode everywhere in the tab |
| `:diffupdate` | Recompute the diff after editing |

Moving and importing changes:

| Keys | Action |
| --- | --- |
| `]c` / `[c` | Next / previous change (diff mode) |
| `do` | **diff obtain** — pull the hunk under the cursor _from_ the other buffer |
| `dp` | **diff put** — push the hunk under the cursor _to_ the other buffer |
| `:diffget` / `:diffput` | Same, but works on a visual selection (`V`, then the command) |
| `zr` / `zm` | Unfold / refold the collapsed context |

Direction rule: `do` and `dp` always act on the window your cursor is in. Put the cursor in the **destination** file and use `do` to import.

Three-way merge (`:h diff-mode`): `:diffget //2` takes the left/ours side, `:diffget //3` the right/theirs side.

LazyVim already sets `diffopt` to `indent-heuristic,inline:char,linematch:40`, so lines that only changed slightly are aligned and highlighted character-by-character instead of showing as whole-block replacements. Nothing to configure.

## Diffing with git (Diffview)

Use this when the other side is a git ref — a branch, a commit, the index — rather than a file on disk.

| Keys | Action |
| --- | --- |
| `<leader>gd` | Diffview: working tree vs `HEAD` |
| `<leader>gD` | Close Diffview |
| `<leader>gv` | File history of the current file |
| `<leader>gV` | File history of the whole repo |

Commands for anything more specific:

| Command | Action |
| --- | --- |
| `:DiffviewOpen main` | Working tree vs `main` |
| `:DiffviewOpen main..feature` | Compare two branches |
| `:DiffviewOpen HEAD~3` | Everything changed in the last 3 commits |
| `:DiffviewOpen --cached` | Staged changes only |
| `:DiffviewFileHistory %` | History of the current file, one commit per entry |
| `:DiffviewOpen` (during a merge) | Three-way conflict resolution view |

Inside the view:

| Keys | Action |
| --- | --- |
| `<Tab>` / `<S-Tab>` | Next / previous file in the changed-files panel |
| `<leader>e` / `<leader>b` | Focus / toggle the file panel |
| `g?` | Show all Diffview mappings for the current panel |
| `-` (in panel) | Stage / unstage the file under the cursor |
| `do` / `dp` | Same builtin hunk import — Diffview windows are normal diff windows |

Conflict resolution uses `diff3_mixed` layout: `<leader>co` takes ours, `<leader>ct` theirs, `<leader>cb` base, `<leader>ca` all, `dx` deletes the conflict region. `]x` / `[x` jump between conflicts.

Rule of thumb: **two files → builtin `:vert diffsplit`. Two git refs → `:DiffviewOpen`.**

## Navigation and motion

| Keys | Action |
| --- | --- |
| `s` | Flash jump (type 2 chars, then a label) |
| `S` | Flash treesitter (select by syntax node) |
| `<leader>tc` | Jump to the enclosing Treesitter context |
| `<leader>xx` | Diagnostics list (Trouble) |
| `<leader>xs` | Document symbols (Trouble) |

## Data and numbers (Dial)

| Keys | Action |
|---|---|
| `<C-a>` / `<C-x>` | Increment / decrement number, date, hex, ordinal under cursor |

## Sessions and layouts

| Keys | Action |
| --- | --- |
| `<leader>ql` | Restore last session |
| `<leader>qs` | Restore session (pick from list) |
| `<leader>uu` | Undo tree (builtin `nvim.undotree`) |
| `<leader>uz` | Toggle Zen mode |
| `<leader>uZ` / `<leader>wm` | Toggle window zoom |
| `<D-w>` | Close buffer (macOS `cmd-w` muscle memory) |

## Messages and cmdline

Handled by Neovim's builtin `ui2` (`:h ui2`), not `noice.nvim`. There is no
"Press ENTER" prompt: long output opens the pager as an ordinary buffer, so
normal-mode motions, search, and yank all work in it.

| Keys | Action |
| --- | --- |
| `:messages` | Message history in the pager buffer |
| `q` | Close the pager |
| `g<` | Reopen the last message output |

## Markdown

Inline rendering is handled automatically by `render-markdown.nvim` (headings, code blocks, checkboxes, links).

There is no in-editor browser preview: `markdown-preview.nvim` was dropped (unmaintained since 2023, built a bundled Node server from a deep npm tree at install time). For browser-quality output, render the file outside Neovim.

## AI

| Keys | Action |
| --- | --- |
| Copilot | Native inline ghost text via copilot-native extra; `<Tab>` accepts |
| `:LspCopilotSignIn` | Authenticate Copilot once per host |

AI in Neovim is tab-completion only, deliberately. There is no in-editor agent
chat or diff-apply surface: `claudecode.nvim` was dropped, since agents are
driven from the shell (tmux) where their own TUI is better than any embedded one.
