-- fff.nvim owns file-finding and live-grep; snacks.picker keeps every other
-- source (explorer, LSP, git, buffers, diagnostics). The two pickers coexist
-- deliberately: fff only implements files + grep, so a full swap would trade
-- 30 snacks sources for 2. Their filters intentionally differ: fff honors
-- .gitignore and picker-only .ignore files; Snacks includes ignored files and
-- applies the explicit ignored_globs list configured in core.lua.
--
-- Delete this file to revert: LazyVim's snacks_picker extra re-claims the four
-- keymaps below on its own.
-- Keep grep scoped to the visible workspace rather than the opened file's root.
local function workspace_grep()
  local explorer = Snacks.picker.get({ source = "explorer" })[1]
  require("fff").live_grep({ cwd = explorer and not explorer.closed and explorer:cwd() or vim.uv.cwd() })
end

return {
  -- lazy.nvim resolves same-lhs keys across specs nondeterministically, so the
  -- inherited snacks bindings are explicitly disabled rather than shadowed.
  {
    "folke/snacks.nvim",
    -- stylua: ignore
    keys = {
      { "<leader><space>", false },
      { "<leader>ff", false },
      { "<leader>/", false },
      { "<leader>sg", false },
    },
  },

  {
    "dmtrKovalenko/fff",
    version = "v0.10.6", -- stable releases have prebuilt binaries for every supported platform
    -- Downloads a prebuilt binary for this platform, falling back to a local
    -- cargo build. The binary is a cache artifact, not config, so it stays
    -- outside Nix rather than pulling rust-overlay + zig-overlay into the flake.
    build = function()
      require("fff.download").download_or_build_binary()
    end,
    lazy = false, -- the plugin lazy-initialises itself
    -- stylua: ignore
    keys = {
      { "<leader><space>", function() require("fff").find_files() end, desc = "Find Files (fff)" },
      { "<leader>ff", function() require("fff").find_files() end, desc = "Find Files (fff)" },
      { "<leader>/", workspace_grep, desc = "Grep (fff)" },
      { "<leader>sg", workspace_grep, desc = "Grep (fff)" },
    },
  },
}
