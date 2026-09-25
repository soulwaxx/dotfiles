-- Custom snacks dashboard: compact header, curated action keys.
-- Overrides LazyVim's default dashboard preset while keeping the snacks engine.
return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
					-- stylua: ignore
          header = [[]],
					-- stylua: ignore
					---@type snacks.dashboard.Item[]
					keys = {
						{ icon = " ", key = "f", desc = "Find File", action = ":lua require('fff').find_files()" },
						{ icon = " ", key = "g", desc = "Find Text", action = ":lua require('fff').live_grep()" },
						{ icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
						{ icon = " ", key = "w", desc = "Git Workspace", action = ":lua require('workspace_git').pick()" },
						{ icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
						{ icon = " ", key = "s", desc = "Restore Session", section = "session" },
						{ icon = " ", key = "q", desc = "Quit", action = ":qa" },
					},
        },
      },
    },
  },
}
