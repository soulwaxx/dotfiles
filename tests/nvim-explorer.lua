-- Integration regression test; requires the installed Neovim config and plugins.
-- nvim --headless -i NONE -c 'luafile tests/nvim-explorer.lua'
vim.schedule(function()
  local dir = vim.fn.tempname()
  local ok, err = xpcall(function()
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
    vim.fn.mkdir(dir .. "/repo", "p")
    dir = assert(vim.uv.fs_realpath(dir))
    local repo = dir .. "/repo"
    local file = repo .. "/sample.txt"
    vim.fn.writefile({ "sample" }, file)
    vim.fn.system({ "git", "-C", repo, "init", "--quiet" })
    assert(vim.v.shell_error == 0, "could not create test repository")
    vim.cmd.cd(dir)
    vim.cmd.edit(file)

    local plugins = require("lazy.core.config").plugins
    assert(not plugins["neo-tree.nvim"], "Neo-tree is still enabled")
    assert(Snacks.config.get("explorer").enabled, "Snacks explorer is disabled")
    assert(vim.fn.maparg("<leader>be", "n") == "", "custom Open Editors binding remains")
    assert(vim.fn.maparg("<leader>ba", "n") == "", "custom Close All binding remains")

    local function explorer_at(root)
      assert(vim.wait(2000, function()
        local picker = Snacks.picker.get({ source = "explorer" })[1]
        return picker and picker:cwd() == root and picker.list.win:valid()
      end), "explorer did not open at " .. root)
      local pickers = Snacks.picker.get({ source = "explorer" })
      assert(#pickers == 1, "multiple explorers opened")
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        assert(vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree", "custom panel opened")
      end
      return pickers[1]
    end

    local function press(key)
      vim.api.nvim_feedkeys(vim.keycode(key), "mx", false)
    end

    press("<leader>e")
    local picker = explorer_at(LazyVim.root())
    assert(picker.opts.layout.preset == "sidebar", "default sidebar layout was overridden")
    assert(not picker.opts.git_status_open, "recursive git status override remains")
    press("<leader>e")
    assert(vim.wait(2000, function()
      return #Snacks.picker.get({ source = "explorer" }) == 0
    end), "root shortcut did not toggle explorer closed")
    press("<leader>E")
    picker = explorer_at(dir)
    io.stdout:write("PASS: default Snacks explorer, root/cwd shortcuts, no Open Editors panel\n")

    -- Directory editing (including `nvim .`) should use Snacks, not Neo-tree/netrw.
    picker:close()
    vim.cmd.edit(dir)
    picker = explorer_at(dir)
    io.stdout:write("PASS: opening a directory launches Snacks explorer\n")

    -- Re-rooting must replace an existing explorer, not just toggle it closed.
    picker:close()
    vim.cmd.edit(file)
    Snacks.explorer({ cwd = dir })
    picker = explorer_at(dir)
    vim.api.nvim_set_current_win(picker.main)
    vim.fn.maparg("<leader>er", "n", false, true).callback()
    picker = explorer_at(repo)
    io.stdout:write("PASS: current-file Git shortcut re-roots the explorer\n")

    require("workspace_git").pick()
    assert(vim.wait(2000, function()
      local overview = Snacks.picker.get({ source = "workspace_git" })[1]
      return overview and overview:current() ~= nil
    end), "workspace Git picker did not load")
    local overview = Snacks.picker.get({ source = "workspace_git" })[1]
    overview.opts.confirm(overview, overview:current())
    picker = explorer_at(repo)
    assert(vim.fn.getcwd() == dir, "workspace shortcut changed cwd")
    io.stdout:write("PASS: workspace Git selection opens Snacks explorer without changing cwd\n")
    picker:close()
  end, debug.traceback)
  vim.fn.delete(dir, "rf")
  if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")
  end
end)
