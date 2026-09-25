-- Neovim LSP + tooling. Mason owns every server, formatter, and linter on both
-- macOS and Linux; the Homebrew (macOS) and Nix (Linux) package sets no longer
-- ship editor tooling on PATH. Only behavioral opt-outs remain here.
--
-- Nix LSP: nixd is deliberately NOT used. It is unavailable via both Homebrew
-- and Mason (it links against Nix's C++ internals, so no prebuilt binary is
-- distributed), which would force a Nix package back onto macOS. The LazyVim
-- nix extra's default nil_ls (Mason package `nil`) is used instead. Trade-off:
-- weaker home-manager/NixOS option completion than nixd, and nil can prompt to
-- fetch flake inputs on eval when they are not archived in the store.
return {
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				-- nil_ls (the lang.nix extra's default Nix LSP) evaluates flake
				-- inputs on open and blocks with an interactive "fetch inputs?"
				-- prompt when they are not archived. autoEvalInputs=false stops the
				-- prompt at the cost of weaker cross-input option completion.
				nil_ls = {
					settings = {
						["nil"] = {
							nix = {
								flake = {
									-- null (default) asks to fetch missing inputs; false never
									-- touches the network, so no interactive prompt on open.
									autoArchive = false,
									autoEvalInputs = false,
								},
							},
						},
					},
				},
				-- regols installs via `go install`, but there is no Go toolchain
				-- here, so Mason retries and fails every start. regal (Mason) is
				-- the sole Rego server.
				regols = { enabled = false },
			},
		},
	},
	-- yamlfmt (conform.lua) is not ensured by any LazyVim extra, so pin it here.
	-- stylua / tflint / shellcheck / shfmt return via the LazyVim core / terraform
	-- / dot extras, which already ensure them.
	--
	-- The lang.nix extra lints with statix and formats with nixfmt but assumes
	-- both are on PATH. They are NOT pinned via Mason: Mason has no darwin-arm64
	-- nixfmt binary ("platform unsupported") and builds statix slowly from source.
	-- Instead they come from Homebrew (macOS) / Nix (Linux) like the rest of the
	-- nix toolchain — see modules/homebrew-packages.nix + modules/linux/packages.nix.
	{
		"mason-org/mason.nvim",
		opts = { ensure_installed = { "yamlfmt" } },
	},
}
