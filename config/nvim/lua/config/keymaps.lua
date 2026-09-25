-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Quick escape from insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Escape insert mode" })

-- Builtin undo tree (packadd'ed in config/options.lua). Branches of the undo
-- history are unreachable with plain u/<C-r>, which only walk one line of it.
vim.keymap.set("n", "<leader>uu", "<cmd>Undotree<cr>", { desc = "Undo tree" })

-- Re-root the snacks explorer at the current file's git repo. Snacks' git
-- status is single-root: in a workspace holding many repos, the tree anchored
-- at the workspace shows no git status for the sub-repos. This jumps the tree
-- into whichever repo the current file belongs to so its status shows.
vim.keymap.set("n", "<leader>er", function()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		return
	end
	local root = Snacks.git.get_root(file)
	if not root then
		vim.notify("No git repo for " .. file, vim.log.levels.WARN)
		return
	end
	local explorer = Snacks.picker.get({ source = "explorer" })[1]
	if explorer and not explorer.closed then
		explorer:set_cwd(root)
		explorer:find()
	else
		Snacks.explorer({ cwd = root })
	end
end, { desc = "Explorer: re-root at file's git repo" })

-- Workspace git overview: pick a sibling repo with uncommitted/unpushed work
-- and re-root the explorer there. Complements <leader>er (which re-roots at the
-- current file's repo) for when no relevant file is open yet.
vim.keymap.set("n", "<leader>gw", function()
	require("workspace_git").pick()
end, { desc = "Git: workspace repos with changes" })
