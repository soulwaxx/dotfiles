-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- JSON uses 4-space indent. jsonls formats with the buffer's shiftwidth, so
-- this also controls format-on-save output.
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "json", "jsonc", "json5" },
	callback = function()
		vim.opt_local.shiftwidth = 4
		vim.opt_local.tabstop = 4
		vim.opt_local.softtabstop = 4
	end,
})
