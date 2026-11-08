-- Inline git blame for the line under the cursor (gitsigns ships with LazyVim).
-- Toggle per session with :Gitsigns toggle_current_line_blame.
return {
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      {
        "<LeftMouse>",
        function()
          local mouse = vim.fn.getmousepos()
          if mouse.winid == 0 or mouse.line == 0 then
            return "<LeftMouse>"
          end
          -- Inspect the rendered gutter, not fixed column offsets: folds and
          -- line-number widths can move or replace the visible Git marker.
          local gutter = vim.api.nvim_eval_statusline(vim.wo[mouse.winid].statuscolumn, {
            winid = mouse.winid,
            use_statuscol_lnum = mouse.line,
            highlights = true,
          })
          for i, highlight in ipairs(gutter.highlights) do
            local is_git = vim.iter(highlight.groups):any(function(group)
              return group:match("^GitSigns") ~= nil
            end)
            local last = gutter.highlights[i + 1]
            local first_col = vim.fn.strdisplaywidth(gutter.str:sub(1, highlight.start))
            local last_col = vim.fn.strdisplaywidth(gutter.str:sub(1, last and last.start or #gutter.str))
            if is_git and mouse.wincol - 1 >= first_col and mouse.wincol - 1 < last_col then
              -- Wrapped/virtual rows do not repeat the actual Git marker.
              local marker = vim.fn.strcharpart(gutter.str:sub(highlight.start + 1), 0, 1)
              local screen_col = mouse.screencol - mouse.wincol + first_col + 1
              if vim.fn.screenstring(mouse.screenrow, screen_col) ~= marker then
                return "<LeftMouse>"
              end
              vim.schedule(function()
                if not vim.api.nvim_win_is_valid(mouse.winid) then
                  return
                end
                vim.api.nvim_set_current_win(mouse.winid)
                vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
                -- Let the mouse event and CursorMoved settle before the
                -- preview installs its close-on-move handler.
                vim.defer_fn(function()
                  if
                    vim.api.nvim_get_current_win() == mouse.winid
                    and vim.api.nvim_win_get_cursor(mouse.winid)[1] == mouse.line
                  then
                    require("gitsigns").preview_hunk_inline()
                  end
                end, 10)
              end)
              return ""
            end
          end
          return "<LeftMouse>"
        end,
        expr = true,
        desc = "Preview clicked Git hunk",
      },
    },
    opts = {
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 300,
        virt_text_pos = "eol",
      },
      current_line_blame_formatter = "<author>, <author_time:%R> • <summary>",
    },
  },
}
