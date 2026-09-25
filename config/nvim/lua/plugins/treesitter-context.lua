-- Sticky header showing the enclosing function/class/block at the top of the
-- window. Massive QoL in large files — you always know where you are.
return {
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = "BufReadPost",
		opts = {
			max_lines = 3,
			multiline_threshold = 1,
		},
		keys = {
			{
				"<leader>tc",
				function()
					require("treesitter-context").go_to_context(vim.v.count1)
				end,
				desc = "Jump to context (treesitter-context)",
			},
		},
	},
}
