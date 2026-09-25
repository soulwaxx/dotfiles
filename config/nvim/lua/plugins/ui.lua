-- UI surface trimmed against what Neovim 0.12 now does natively.
--
-- ui2 (`:h ui2`) is the core redesign of the messages/cmdline/pager UI. It
-- covers what noice.nvim was carrying here — cmdline popup, no "Press ENTER"
-- interruptions, highlighted cmdline, pager-as-buffer — so noice and its only
-- dependency nui.nvim are both dropped. LazyVim's lualine spec guards its noice
-- components with `package.loaded["noice"]`, so they simply go quiet.
--
-- ui2 is still marked experimental and lives behind a private module path, so
-- the enable is guarded: on a Neovim without it (or after an upstream rename)
-- the legacy message grid is used and nothing errors.
pcall(function()
	require("vim._core.ui2").enable()
end)

return {
	-- Superseded by ui2 above.
	{ "folke/noice.nvim", enabled = false },
	{ "MunifTanjim/nui.nvim", enabled = false },


	-- LazyVim's default colorscheme, unused here (core.lua pins catppuccin) and
	-- only ever reached through LazyVim's default `colorscheme` option.
	{ "folke/tokyonight.nvim", enabled = false },
}
