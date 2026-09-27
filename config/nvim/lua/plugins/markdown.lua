-- markdown-preview.nvim (from the lang.markdown extra) is dropped: upstream is
-- untouched since 2023-10 and it builds a bundled Node server from a deep npm
-- tree at install time — an unaudited install-time dependency on both hosts for
-- a browser preview that render-markdown.nvim already covers in-buffer.
--
-- This frees <leader>cp. Browser-quality rendering, when actually needed, is a
-- shell away (`glow`, or a real browser on the rendered file).
local markdownlint_config = vim.fn.stdpath("config") .. "/markdownlint-cli2.jsonc"

return {
	{ "iamcco/markdown-preview.nvim", enabled = false },
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters = {
				["markdownlint-cli2"] = { prepend_args = { "--config", markdownlint_config } },
			},
		},
	},
	{
		"stevearc/conform.nvim",
		opts = {
			formatters = {
				["markdownlint-cli2"] = { prepend_args = { "--config", markdownlint_config } },
			},
		},
	},
}
