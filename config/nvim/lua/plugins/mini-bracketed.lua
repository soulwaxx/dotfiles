-- ]f/[f jump between functions, ]d/[d between diagnostics, etc. LazyVim ships
-- ]d/[d itself; mini.bracketed adds the rest (functions, treesitter nodes,
-- yanks, quickfix, windows) that stock LazyVim doesn't cover.
return {
	{
		"nvim-mini/mini.bracketed",
		event = "BufReadPost",
		opts = {
			-- Keep LazyVim's [c/]c class navigation and its builtin diff fallback.
			comment = { suffix = "" },
			file = { suffix = "" },
			window = { suffix = "" },
			quickfix = { suffix = "" },
			yank = { suffix = "" },
			treesitter = { suffix = "n" },
		},
	},
}
