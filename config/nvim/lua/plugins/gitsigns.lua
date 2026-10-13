-- Inline git blame for the line under the cursor (gitsigns ships with LazyVim).
-- Toggle per session with :Gitsigns toggle_current_line_blame.
return {
	{
		"lewis6991/gitsigns.nvim",
		opts = {
			current_line_blame = true,
			current_line_blame_opts = {
				delay = 300,
				virt_text_pos = "eol",
			},
			current_line_blame_formatter = "<author>, <author_time:%R> • <summary>",
		},
	},
}
