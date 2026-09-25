-- Catppuccin Mocha (dark only) — the user never uses macOS light appearance.
local colorscheme = vim.env.NVIM_COLORSCHEME or "catppuccin"

-- Shared ignore globs for the pickers/explorer below. Mirrored by hand in
-- config/zed/settings.json (file_scan_exclusions) — no shared source between
-- that static JSON and this lua.
local ignored_globs = {
	"**/.pytest_cache",
	"**/.terraform",
	"**/.venv",
	"**/__pycache__",
	"**/venv",
}

return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = false,
		priority = 1000,
		opts = {
			flavour = "mocha",
			-- Map highlights onto the terminal's 16 ANSI slots so colors follow
			-- Ghostty's Catppuccin Mocha theme.
			term_colors = true,
			-- LazyVim leaves auto_integrations on, which walks the whole lazy.nvim
			-- plugin list on every startup (~15ms of a ~100ms boot) to guess this
			-- same table. The plugin set here is declared, not discovered, so the
			-- guessing buys nothing. Add an entry when adding a themed plugin.
			auto_integrations = false,
			integrations = {
				blink_cmp = { style = "bordered" },
				bufferline = true,
				dashboard = true,
				diffview = true,
				flash = true,
				gitsigns = true,
				grug_far = true,
				lsp_trouble = true,
				markdown = true,
				mason = true,
				mini = { enabled = true, indentscope_color = "overlay2" },
				native_lsp = { enabled = true },
				notifier = true,
				render_markdown = true,
				semantic_tokens = true,
				snacks = true,
				treesitter = true,
				treesitter_context = true,
				which_key = true,
			},
		},
	},

	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = colorscheme,
		},
	},

	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			-- Regex is already ensured by LazyVim core. Keep only gitignore,
			-- which no enabled language extra currently guarantees.
			ensure_installed = {
				"gitignore",
			},
		},
	},

	{
		"folke/snacks.nvim",
		opts = {
			-- Inline image/mermaid/math rendering in markdown and image buffers.
			-- Opt-in module (off by default): without this the imagemagick,
			-- ghostscript, and mermaid-cli Homebrew deps and tmux allow-passthrough
			-- would go unused. Ghostty supplies the Kitty graphics protocol.
			image = { enabled = true },
			notifier = {
				-- Keep notifications visible longer (default 3000ms is easy to miss).
				timeout = 5000,
			},
			picker = {
				-- Snacks shows hidden and gitignored files, filtering only the explicit
				-- ignored_globs set. FFF intentionally keeps its own supported policy:
				-- it honors .gitignore and picker-only .ignore files. Runtime toggles:
				-- <a-h> hidden, <a-i> ignored (Snacks only).
				hidden = true,
				ignored = true,
				exclude = ignored_globs,
				sources = {
					explorer = {
						hidden = true,
						ignored = true,
						exclude = ignored_globs,
						git_status_open = true,
						layout = {
							preset = "sidebar",
							preview = "main",
						},
					},
				},
			},
		},
	},
}
