-- Integration regression test; requires the installed Neovim config and plugins.
-- Run from the repository: nvim --headless -i NONE -c 'luafile tests/nvim-grep.lua'
vim.schedule(function()
  local dir = vim.fn.tempname()
  local ok, err = xpcall(function()
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
    vim.fn.mkdir(dir, "p")
    dir = assert(vim.uv.fs_realpath(dir))
    local path = dir .. "/sample.txt"
    local lines = {}
    for i = 1, 120 do
      lines[i] = "line " .. i
    end
    lines[80] = "target needle here"
    vim.fn.writefile(lines, path)
    local specs = dofile("config/nvim/lua/plugins/fff.lua")
    vim.cmd.cd(dir)
    local ui = require("fff.picker_ui.picker_ui")
    for _, case in ipairs({
      { name = "dashboard and explorer", dashboard = true, explorer = true, key = "<leader>/" },
      { name = "editor and explorer", explorer = true, key = "<leader>sg" },
      { name = "editor only", key = "<leader>/" },
      { name = "split from explorer", dashboard = true, explorer = true, key = "<leader>/", action = "split" },
      { name = "vertical split from explorer", dashboard = true, explorer = true, key = "<leader>/", action = "vsplit" },
      { name = "tab from explorer", dashboard = true, explorer = true, key = "<leader>/", action = "tab" },
      { name = "cancel from explorer", dashboard = true, explorer = true, key = "<leader>/", cancel = true },
    }) do
      vim.cmd("tabonly!")
      vim.cmd("only!")
      vim.cmd("enew!")
      local main = vim.api.nvim_get_current_win()
      if case.dashboard then
        Snacks.dashboard.open({ buf = 0, win = main })
      end
      local explorer
      if case.explorer then
        explorer = Snacks.explorer({ cwd = dir })
        assert(vim.wait(2000, function() return explorer.list.win:valid() end), "explorer did not open")
        explorer:focus("list")
      end

      local origin = vim.api.nvim_get_current_win()
      local origin_buf = vim.api.nvim_get_current_buf()
      for _, key in ipairs(specs[2].keys) do
        if key[1] == case.key then
          key[2]()
          break
        end
      end
      assert(ui.state.active, "grep did not open")
      ui.state.query = "needle"
      ui.update_results_sync()
      assert(vim.wait(2000, function() return #ui.state.filtered_items > 0 end), "no grep result")
      assert(ui.state.filtered_items[1].line_number == 80, "wrong search result")
      if case.cancel then
        ui.close()
      else
        ui.select(case.action)
      end
      -- Allow deferred picker teardown, file opening and Snacks focus callbacks.
      vim.wait(500, function() return false end)
      if case.cancel then
        assert(vim.api.nvim_get_current_win() == origin, "cancel changed focus")
        assert(vim.api.nvim_get_current_buf() == origin_buf, "cancel changed buffer")
      else
        if not case.action then
          assert(vim.api.nvim_get_current_win() == main, case.name .. ": focus stayed in Snacks")
        end
        assert(vim.api.nvim_buf_get_name(0) == path, case.name .. ": wrong buffer")
        assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 80, 7 }), case.name .. ": wrong cursor")
      end
      print("PASS: " .. case.name)
      if explorer then
        explorer:close()
      end
    end
  end, debug.traceback)
  vim.fn.delete(dir, "rf")
  if not ok then
    vim.api.nvim_err_writeln(err)
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")
  end
end)
