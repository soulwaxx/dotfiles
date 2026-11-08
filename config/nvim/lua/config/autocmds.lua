-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Editing defaults; EditorConfig applies project overrides after FileType.
-- jsonls uses the buffer's shiftwidth for formatting; Ruff has its own fallback
-- in plugins/lsp.lua. JSON5 has no formatter configured (editing only).
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json", "jsonc", "json5", "python" },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.shiftwidth = 2
    vim.opt_local.tabstop = 2
    vim.opt_local.softtabstop = 2
  end,
})
