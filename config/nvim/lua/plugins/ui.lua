-- Messages and cmdline use LazyVim's default noice.nvim setup (cmdline popup
-- at top center, search in the bottom line, long output in a split). Neovim
-- 0.12's builtin ui2 stays off: it can only draw the cmdline at the bottom.

return {
	-- LazyVim's default colorscheme, unused here (core.lua pins catppuccin) and
	-- only ever reached through LazyVim's default `colorscheme` option.
	{ "folke/tokyonight.nvim", enabled = false },
}
