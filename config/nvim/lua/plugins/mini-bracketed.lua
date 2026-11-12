-- Bracket motions LazyVim doesn't ship (buffers, conflicts, indent, jumps,
-- oldfiles, undo, ...). Targets that LazyVim or builtins already own (comment,
-- file, window, quickfix, yank) are disabled below; treesitter nodes move to
-- ]n/[n.
return {
  {
    "nvim-mini/mini.bracketed",
    event = "BufReadPost",
    opts = {
      -- Keep LazyVim's [c/]c class navigation and its builtin diff fallback.
      comment = { suffix = "" },
      file = { suffix = "" },
      window = { suffix = "" },
      quickfix = { suffix = "" },
      yank = { suffix = "" },
      treesitter = { suffix = "n" },
    },
  },
}
