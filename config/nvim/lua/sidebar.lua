-- Shared entry points for the stacked Neo-tree sidebar and workspace tools.
local M = {}

function M.state()
  if not package.loaded["neo-tree"] then
    return
  end
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    return state
  end
end

function M.open_buffers()
  if not M.state() then
    return
  end
  local state = require("neo-tree.sources.manager").get_state("buffers")
  if not (state.winid and vim.api.nvim_win_is_valid(state.winid)) then
    -- A distinct initial position lets both Neo-tree sources coexist.
    -- Root at / to include files outside the project, then stack natively.
    require("neo-tree.command").execute({ action = "show", source = "buffers", position = "right", dir = "/" })
    local files = M.state()
    vim.fn.win_splitmove(state.winid, files.winid, { vertical = false, rightbelow = false })
    vim.wo[state.winid].winbar = " Open Editors %= %@v:lua.require'sidebar'.click_close_all@Close All%T "
    vim.wo[files.winid].winbar = " Files"
    vim.api.nvim_win_set_height(state.winid, math.max(3, math.floor(vim.o.lines * 0.25)))
  end
end

function M.open(dir)
  local command = require("neo-tree.command")
  command.execute({ action = "show", source = "filesystem", position = "left", dir = dir })
  M.open_buffers()
  command.execute({ action = "focus", source = "filesystem", position = "left" })
end

function M.close()
  local manager = require("neo-tree.sources.manager")
  manager.close("buffers")
  manager.close("filesystem")
end

function M.toggle(dir)
  if M.state() then
    M.close()
  else
    M.open(dir)
  end
end

function M.close_buffer(state)
  local node = state.tree:get_node()
  local buf = node and node.extra and node.extra.bufnr
  if buf then
    Snacks.bufdelete(buf)
  end
end

function M.close_all()
  -- Snapshot the list: bufdelete creates a fresh empty buffer when the last
  -- editor closes. Leave terminals and tool panels alone.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      Snacks.bufdelete(buf)
      -- Cancel stops the whole operation, not just this file's prompt.
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
        break
      end
    end
  end
end

-- Winbar callbacks must defer edits out of mouse/statusline evaluation.
function M.click_close_all()
  vim.schedule(M.close_all)
end

return M
