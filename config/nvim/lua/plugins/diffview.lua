-- Git-aware diffs: branch vs branch, commit ranges, per-file history.
-- Plain file-vs-file diffing is builtin (`:vert diffsplit`), see CHEATSHEET.md.
--
-- Tracks dlyongemallo's fork, not sindrets/diffview.nvim: upstream has had no
-- commit since 2024-06 while the fork carries bug fixes forward. Same module
-- name, same commands, same options — only the source changes, so `name` is
-- pinned so lazy.nvim keeps the original plugin directory and identity.
return {
	{
		"dlyongemallo/diffview.nvim",
		name = "diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
		keys = {
			{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree" },
			{ "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
			{ "<leader>gv", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: history (file)" },
			{ "<leader>gV", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: history (repo)" },
		},
		opts = {
			enhanced_diff_hl = true,
			view = { merge_tool = { layout = "diff3_mixed" } },
		},
	},
}
