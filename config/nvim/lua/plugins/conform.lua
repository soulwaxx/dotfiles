return {
	"stevearc/conform.nvim",
	opts = {
		formatters_by_ft = {
			yaml = { "yamlfmt" }, -- K8s/Helm-friendly formatter over prettier
		},
		formatters = {
			yamlfmt = {
				command = "yamlfmt",
				-- yamlfmt takes formatter options as one comma-separated value, not as
				-- separate flags, and needs an explicit `-` to read stdin (conform's
				-- builtin supplies that; overriding `args` replaces it).
				-- indentless_arrays=false keeps sequence items indented under their key
				-- (matches VSCode/prettier); retain_line_breaks keeps blank-line grouping.
				args = { "-formatter", "type=basic,indentless_arrays=false,retain_line_breaks=true", "-" },
			},
		},
	},
}
