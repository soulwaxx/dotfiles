-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- One option borders every float Neovim opens (LSP hover, signature help,
-- diagnostics, vim.ui.input). Neovim 0.12+; the pcall keeps older builds quiet.
vim.o.winborder = "rounded"

-- Builtin undo-history browser shipped in $VIMRUNTIME/pack/dist/opt (0.12+).
-- `undofile` is on by default under LazyVim, so the history is already persisted.
pcall(vim.cmd.packadd, "nvim.undotree")

vim.opt.softtabstop = 2
vim.opt.wrap = true
vim.opt.scrolloff = 8
vim.opt.swapfile = false
vim.opt.backup = false
