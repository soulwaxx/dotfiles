-- markdown-preview.nvim (from the lang.markdown extra) is dropped: upstream is
-- untouched since 2023-10 and it builds a bundled Node server from a deep npm
-- tree at install time — an unaudited install-time dependency on both hosts for
-- a browser preview that render-markdown.nvim already covers in-buffer.
--
-- This frees <leader>cp. Browser-quality rendering, when actually needed, is a
-- shell away (`glow`, or a real browser on the rendered file).
return {
	{ "iamcco/markdown-preview.nvim", enabled = false },
}
