-- Integration test using the installed Neovim config/plugins.
-- nvim --headless -i NONE -c 'luafile tests/nvim-sidebar.lua'
vim.schedule(coroutine.wrap(function()
  local function process_input()
    local thread = coroutine.running()
    vim.defer_fn(function()
      assert(coroutine.resume(thread))
    end, 100)
    coroutine.yield()
  end
  local dir = vim.fn.tempname()
  local confirm = vim.fn.confirm
  local ok, err = xpcall(function()
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
    vim.o.lines, vim.o.columns = 50, 160
    vim.fn.mkdir(dir .. "/project/folder", "p")
    dir = assert(vim.uv.fs_realpath(dir))
    local project = dir .. "/project"
    local a, b, outside = project .. "/a.txt", project .. "/b.txt", dir .. "/outside.txt"
    for _, path in ipairs({ a, b, outside, project .. "/folder/child.txt" }) do
      vim.fn.writefile({ "original" }, path)
    end
    vim.cmd.cd(project)
    vim.cmd.edit(a)
    local main = vim.api.nvim_get_current_win()
    local a_buf = vim.api.nvim_get_current_buf()
    local b_buf = vim.fn.bufadd(b)
    vim.fn.bufload(b_buf)
    vim.bo[b_buf].buflisted = true
    local outside_buf = vim.fn.bufadd(outside)
    vim.fn.bufload(outside_buf)
    vim.bo[outside_buf].buflisted = true

    local sidebar = require("sidebar")
    sidebar.open(project)
    local manager = require("neo-tree.sources.manager")
    local tree = assert(sidebar.state())
    local buffers = manager.get_state("buffers")
    assert(
      vim.wait(2000, function()
        return buffers.tree and buffers.tree:get_node(outside) and tree.tree and tree.tree:get_node(b)
      end),
      "sidebar nodes did not load"
    )
    vim.wait(300, function()
      return false
    end)
    local files_pos = vim.api.nvim_win_get_position(tree.winid)
    local buffers_pos = vim.api.nvim_win_get_position(buffers.winid)
    assert(buffers_pos[1] < files_pos[1] and buffers_pos[2] == files_pos[2], "panels are not stacked")
    assert(vim.fn.getcwd() == project, "Open Editors changed cwd")
    assert(buffers.tree:get_node(outside), "Open Editors omitted an outside-project buffer")
    io.stdout:write("PASS: stacked panels, outside-project buffers, unchanged cwd\n")

    local function click_node(state, id, double)
      require("neo-tree.ui.renderer").focus_node(state, id)
      vim.cmd.redraw()
      local node, line = state.tree:get_node(id)
      assert(node and line, "node is not visible")
      local pos = vim.fn.screenpos(state.winid, line, 10)
      assert(pos.row > 0, "node is not on screen")
      vim.api.nvim_input_mouse("left", "press", double and "2" or "", 0, pos.row - 1, pos.col - 1)
      process_input()
      vim.api.nvim_input_mouse("left", "release", "", 0, pos.row - 1, pos.col - 1)
      process_input()
      vim.wait(200, function()
        return false
      end)
    end
    click_node(tree, b)
    assert(vim.api.nvim_get_current_win() == tree.winid, "single click did not select the entry")
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(main)) == a, "single click opened the file")
    click_node(tree, b, true)
    assert(
      vim.api.nvim_get_current_win() == main and vim.api.nvim_buf_get_name(0) == b,
      "double click did not open the file in the editor: "
        .. vim.api.nvim_get_current_win()
        .. " "
        .. vim.api.nvim_buf_get_name(0)
        .. " mouse="
        .. vim.inspect(vim.fn.getmousepos())
    )
    click_node(tree, project .. "/folder", true)
    assert(tree.tree:get_node(project .. "/folder"):is_expanded(), "double click did not expand folder")
    click_node(tree, project .. "/folder", true)
    assert(not tree.tree:get_node(project .. "/folder"):is_expanded(), "double click did not collapse folder")
    click_node(buffers, outside)
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(main)) == b, "single click switched buffer")
    click_node(buffers, outside, true)
    assert(vim.api.nvim_buf_get_name(0) == outside, "double click did not switch buffer")
    io.stdout:write("PASS: single-click selection; double-click opening, folder toggling, buffer switching\n")

    local function drag(row, from_col, to_col)
      vim.api.nvim_input_mouse("left", "press", "", 0, row, from_col)
      process_input()
      vim.api.nvim_input_mouse("left", "drag", "", 0, row, to_col)
      process_input()
      vim.api.nvim_input_mouse("left", "release", "", 0, row, to_col)
      process_input()
    end
    local width = vim.api.nvim_win_get_width(tree.winid)
    local row = vim.api.nvim_win_get_position(tree.winid)[1] + 3
    drag(row, width, width + 10)
    assert(vim.api.nvim_win_get_width(tree.winid) == width + 10, "mouse drag did not widen sidebar")
    assert(vim.api.nvim_win_get_width(buffers.winid) == width + 10, "mouse resize separated panel widths")
    drag(row, width + 10, width - 5)
    assert(vim.api.nvim_win_get_width(tree.winid) == width - 5, "mouse drag did not shrink sidebar")
    assert(vim.api.nvim_win_get_width(buffers.winid) == width - 5, "panel widths differ after shrinking")
    io.stdout:write("PASS: mouse sidebar resizing in both directions\n")

    for _, case in ipairs({ { tree, b }, { buffers, outside } }) do
      local state, path = unpack(case)
      vim.api.nvim_set_current_win(state.winid)
      require("neo-tree.ui.renderer").focus_node(state, path)
      local wins_before = #vim.api.nvim_tabpage_list_wins(0)
      vim.api.nvim_feedkeys(vim.keycode("<C-v>"), "mx", false)
      process_input()
      assert(#vim.api.nvim_tabpage_list_wins(0) == wins_before + 1, "Ctrl-v did not create a split")
      assert(vim.api.nvim_buf_get_name(0) == path and vim.bo.filetype ~= "neo-tree", "Ctrl-v opened in sidebar")
      assert(
        vim.api.nvim_win_get_position(0)[2] ~= vim.api.nvim_win_get_position(main)[2],
        "Ctrl-v created a horizontal rather than vertical split"
      )
      vim.cmd.close()
    end
    io.stdout:write("PASS: Ctrl-v vertical splits from Files and Open Editors\n")

    require("neo-tree.ui.renderer").focus_node(buffers, outside)
    sidebar.close_buffer(buffers)
    assert(
      vim.fn.buflisted(outside_buf) == 0 and vim.fn.filereadable(outside) == 1,
      "closing an editor deleted a file or kept the buffer"
    )
    assert(vim.api.nvim_win_is_valid(main), "closing an editor destroyed the editor window")

    vim.api.nvim_buf_set_lines(a_buf, 0, -1, false, { "saved edit" })
    local prompts = 0
    vim.fn.confirm = function()
      prompts = prompts + 1
      return 3 -- Cancel
    end
    -- Click the actual winbar control rather than calling its Lua callback.
    vim.cmd.redraw()
    local header_row = vim.fn.screenpos(buffers.winid, 1, 1).row - 2
    local header_col = vim.api.nvim_win_get_position(buffers.winid)[2] + vim.api.nvim_win_get_width(buffers.winid) - 5
    vim.api.nvim_input_mouse("left", "press", "", 0, header_row, header_col)
    process_input()
    vim.api.nvim_input_mouse("left", "release", "", 0, header_row, header_col)
    process_input()
    assert(
      prompts == 1 and vim.fn.buflisted(a_buf) == 1 and vim.fn.buflisted(b_buf) == 1,
      "Cancel did not stop Close All"
    )
    assert(vim.fn.readfile(a)[1] == "original", "Cancel saved or discarded changes")

    local terminal = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_open_term(terminal, {})
    vim.fn.confirm = function()
      return 1
    end -- Save
    sidebar.close_all()
    assert(vim.api.nvim_buf_is_valid(terminal), "Close All closed a terminal")
    assert(vim.fn.readfile(a)[1] == "saved edit", "Save did not preserve edits")
    assert(vim.fn.buflisted(a_buf) == 0 and vim.fn.buflisted(b_buf) == 0, "Close All left files open")
    assert(sidebar.state() and vim.api.nvim_win_is_valid(buffers.winid), "Close All closed the sidebar")

    vim.api.nvim_set_current_win(main)
    vim.cmd.edit(b)
    local discard_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(discard_buf, 0, -1, false, { "discarded edit" })
    vim.fn.confirm = function()
      return 2
    end -- Discard
    sidebar.close_all()
    assert(
      vim.fn.readfile(b)[1] == "original" and vim.fn.buflisted(discard_buf) == 0,
      "Discard wrote changes or kept the buffer open"
    )
    io.stdout:write("PASS: close selected; Close All Save, Discard, Cancel; sidebar preserved\n")

    sidebar.toggle(project)
    vim.wait(200, function()
      return false
    end)
    assert(not sidebar.state(), "toggle did not close the sidebar")
    sidebar.toggle(project)
    vim.wait(300, function()
      return false
    end)
    assert(
      sidebar.state() and vim.api.nvim_win_is_valid(manager.get_state("buffers").winid),
      "toggle did not restore both panels"
    )
    io.stdout:write("PASS: toggle closes/restores both panels\n")
  end, debug.traceback)
  vim.fn.confirm = confirm
  vim.fn.delete(dir, "rf")
  if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")
  end
end))
