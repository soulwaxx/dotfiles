-- Workspace git overview. Snacks' git status is single-root (see the
-- <leader>er re-root keymap), so a workspace holding many sibling repos shows
-- no status for any of them. This scans the immediate subdirectories of the
-- cwd and lists the repos that have uncommitted OR unpushed work, so open work
-- is easy to recall. Selecting a repo re-roots the snacks explorer there.
local M = {}
local uv = vim.uv or vim.loop

-- `--branch` prints the "## a...b [ahead N]" header line (ahead = local
-- commits not on upstream); the remaining porcelain lines are the uncommitted
-- (staged + unstaged + untracked) file entries. Without an upstream, count
-- commits not reachable from a remote-tracking ref.
local function repo_status(dir)
	local out = vim.fn.systemlist({ "git", "-C", dir, "status", "--porcelain=v1", "--branch" })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local ahead, dirty, branch = 0, 0, nil
	for _, line in ipairs(out) do
		if line:sub(1, 2) == "##" then
			ahead = tonumber(line:match("ahead (%d+)")) or 0
			if not line:find("...", 1, true) or line:find("[gone]", 1, true) then
				branch = line:match("^## (.-)%.%.%.") or line:match("^## ([^%s]+)")
				if branch == "HEAD" or line:find("No commits yet", 1, true) then
					branch = nil
				end
			end
		else
			dirty = dirty + 1
		end
	end
	if branch and ahead == 0 then
		local refs = vim.fn.systemlist({ "git", "-C", dir, "for-each-ref", "--format=%(refname)" })
		if vim.v.shell_error == 0 then
			local args = { "git", "-C", dir, "rev-list", "--count", "HEAD", "--not" }
			for _, ref in ipairs(refs) do
				if ref:sub(1, 13) == "refs/remotes/" then
					args[#args + 1] = ref
				end
			end
			local count = vim.fn.systemlist(args)
			if vim.v.shell_error == 0 then
				ahead = tonumber(count[1]) or 0
			end
		end
	end
	return { ahead = ahead, dirty = dirty }
end

local function find_repos()
	local root = vim.fn.getcwd()
	local items = {}
	for name, t in vim.fs.dir(root) do
		local dir = root .. "/" .. name
		local git_entry = uv.fs_stat(dir .. "/.git")
		if t == "directory" and git_entry and (git_entry.type == "directory" or git_entry.type == "file") then
			local st = repo_status(dir)
			if st and (st.dirty > 0 or st.ahead > 0) then
				items[#items + 1] = { text = name, dir = dir, dirty = st.dirty, ahead = st.ahead }
			end
		end
	end
	table.sort(items, function(a, b)
		return a.text < b.text
	end)
	return items
end

local function reroot_explorer(dir)
	local explorer = Snacks.picker.get({ source = "explorer" })[1]
	if explorer and not explorer.closed then
		explorer:set_cwd(dir)
		explorer:find()
	else
		Snacks.explorer({ cwd = dir })
	end
end

function M.pick()
	local items = find_repos()
	if #items == 0 then
		vim.notify("No repos with uncommitted or unpushed changes", vim.log.levels.INFO)
		return
	end
	Snacks.picker.pick({
		source = "workspace_git",
		title = "Workspace repos with changes",
		items = items,
		preview = "none",
		format = function(item)
			local ret = { { ("%-32s"):format(item.text), "Directory" } }
			if item.dirty > 0 then
				ret[#ret + 1] = { ("  ●%d"):format(item.dirty), "DiagnosticWarn" }
			end
			if item.ahead > 0 then
				ret[#ret + 1] = { ("  ↑%d"):format(item.ahead), "DiagnosticInfo" }
			end
			return ret
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				reroot_explorer(item.dir)
			end
		end,
	})
end

return M
