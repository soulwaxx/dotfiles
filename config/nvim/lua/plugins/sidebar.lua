-- Trial 2: VS Code-style stacked Open Editors + Files sidebar.
-- Native splits keep mouse separator dragging available (Edgy locks sizes).
return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
    keys = {
      {
        "<leader>fe",
        function()
          require("sidebar").toggle(LazyVim.root())
        end,
        desc = "Sidebar (Root Dir)",
      },
      {
        "<leader>fE",
        function()
          require("sidebar").toggle(vim.uv.cwd())
        end,
        desc = "Sidebar (cwd)",
      },
      {
        "<leader>be",
        function()
          require("sidebar").open(LazyVim.root())
          require("neo-tree.command").execute({ action = "focus", source = "buffers", position = "right" })
        end,
        desc = "Focus Open Editors",
      },
      {
        "<leader>ba",
        function()
          require("sidebar").close_all()
        end,
        desc = "Close All Editors",
      },
    },
    opts = {
      sources = { "filesystem", "buffers", "git_status" },
      source_selector = { winbar = false, statusline = false },
      event_handlers = {
        {
          event = "neo_tree_window_after_open",
          handler = function(args)
            if args.source == "filesystem" then
              vim.schedule(function()
                require("sidebar").open_buffers()
              end)
            end
          end,
        },
      },
      window = {
        width = 36,
        mappings = {
          -- A single click selects; double-click opens files or toggles folders.
          ["<2-LeftMouse>"] = "open",
          ["<C-v>"] = "open_vsplit",
          ["Q"] = function()
            require("sidebar").close()
          end,
        },
      },
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          never_show = { ".pytest_cache", ".terraform", ".venv", "__pycache__", "venv" },
        },
      },
      buffers = {
        bind_to_cwd = false,
        show_unloaded = true,
        window = {
          mappings = {
            -- Closing an editor is not a filesystem delete. Snacks supplies
            -- Save / Discard / Cancel prompts and preserves editor splits.
            ["d"] = function(state)
              require("sidebar").close_buffer(state)
            end,
            ["bd"] = function(state)
              require("sidebar").close_buffer(state)
            end,
            ["x"] = function(state)
              require("sidebar").close_buffer(state)
            end,
          },
        },
      },
    },
  },
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = true,
        offsets = { { filetype = "neo-tree", text = "Workspace", highlight = "Directory", text_align = "left" } },
      },
    },
  },
}
