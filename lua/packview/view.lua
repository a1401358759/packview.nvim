-- One floating window, laid out like a plugin manager: a bar, then groups.
-- A plugin with new commits shows them underneath instead of in a second window.

local M = {}

local ns = vim.api.nvim_create_namespace("packview")

local function hl(name, link)
	vim.api.nvim_set_hl(0, name, { link = link, default = true })
end

hl("PackviewTitle", "Title")
hl("PackviewKey", "Special")
hl("PackviewDim", "Comment")
hl("PackviewName", "Normal")
hl("PackviewLoaded", "DiagnosticOk")
hl("PackviewUpdate", "DiagnosticWarn")
hl("PackviewReason", "Constant")
hl("PackviewCommit", "Identifier")
hl("PackviewSubject", "String")
hl("PackviewMark", "Special")

local state = {
	plugins = {},
	rows = {}, -- buffer line -> plugin index
	spans = {}, -- { line, col, end_col, group }
	marked = {},
	pending = 0,
	buf = nil,
	win = nil,
}

local function width()
	return vim.api.nvim_win_get_width(state.win)
end

local function open()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local cfg = require("packview.config").opts
	local w = math.floor(vim.o.columns * cfg.width)
	local h = math.floor(vim.o.lines * cfg.height)
	state.buf = vim.api.nvim_create_buf(false, true)
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = w,
		height = h,
		row = math.floor((vim.o.lines - h) / 2),
		col = math.floor((vim.o.columns - w) / 2),
		border = cfg.border,
		title = " packview ",
		title_pos = "center",
	})
	vim.bo[state.buf].filetype = "packview"
	vim.wo[state.win].cursorline = true
	require("packview.keys").bind(state.buf)
end

function M.show(plugins)
	state.plugins = plugins
	open()
	M.draw()
end

function M.plugins()
	return state.plugins
end

function M.pending(n)
	state.pending = n
	M.draw()
end

function M.current()
	local line = vim.api.nvim_win_get_cursor(state.win)[1]
	local index = state.rows[line]
	return index and state.plugins[index] or nil
end

function M.marked()
	local list = {}
	for index in pairs(state.marked) do
		list[#list + 1] = state.plugins[index]
	end
	if #list == 0 then
		local plugin = M.current()
		return plugin and { plugin } or {}
	end
	return list
end

function M.toggle()
	local line = vim.api.nvim_win_get_cursor(state.win)[1]
	local index = state.rows[line]
	if index then
		state.marked[index] = not state.marked[index] or nil
		M.draw()
	end
end

function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win, state.buf = nil, nil
end

local function add(line, col, text, group)
	state.spans[#state.spans + 1] = { line, col, col + #text, group }
end

local function groups()
	local updates, loaded, waiting = {}, {}, {}
	for index, plugin in ipairs(state.plugins) do
		if plugin.status == "update" then
			updates[#updates + 1] = index
		elseif plugin.loaded or plugin.active then
			loaded[#loaded + 1] = index
		else
			waiting[#waiting + 1] = index
		end
	end
	return {
		{ "Updates", updates },
		{ "Loaded", loaded },
		{ "Not loaded", waiting },
	}
end

local function reason(plugin)
	if plugin.why ~= "" then
		return plugin.why
	end
	if plugin.active then
		return "start"
	end
	return ""
end

function M.draw()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	local cursor = state.win and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_get_cursor(state.win)
	local cols = width()
	local lines = {}
	state.rows, state.spans = {}, {}

	local function line(text)
		lines[#lines + 1] = text
		return #lines
	end

	local actions = {
		{ "Update", "u" },
		{ "All", "U" },
		{ "Check", "r" },
		{ "Clean", "x" },
		{ "Open", "Enter" },
	}
		local pieces = {}
		for _, action in ipairs(actions) do
			pieces[#pieces + 1] = action[1] .. " (" .. action[2] .. ")"
		end
		local bar = line("  " .. table.concat(pieces, "   "))
		local col = 2
		for i, action in ipairs(actions) do
			local key = " (" .. action[2] .. ")"
			add(bar, col, action[1], "PackviewTitle")
			add(bar, col + #action[1], key, "PackviewKey")
			col = col + #action[1] + #key + (i < #actions and 3 or 0)
		end

	local loaded, updates = 0, 0
	for _, plugin in ipairs(state.plugins) do
		if plugin.loaded or plugin.active then
			loaded = loaded + 1
		end
		if plugin.status == "update" then
			updates = updates + 1
		end
	end
	local summary = ("  Total: %d plugins"):format(#state.plugins)
	if state.pending > 0 then
		summary = summary .. ("    checking %d"):format(state.pending)
	elseif updates > 0 then
		summary = summary .. ("    %d updates"):format(updates)
	end
	local row = line(summary)
	add(row, 0, summary, "PackviewTitle")
	line("")

	for _, group in ipairs(groups()) do
		local title, indexes = group[1], group[2]
		if #indexes > 0 then
			local heading = ("  %s  (%d)"):format(title, #indexes)
			local grow = line(heading)
			add(grow, 2, title, "PackviewTitle")
			add(grow, 2 + #title, heading:sub(3 + #title), "PackviewDim")

			for _, index in ipairs(indexes) do
				local plugin = state.plugins[index]
					local dot = (plugin.loaded or plugin.active) and "●" or "○"
					local mark = state.marked[index] and "▸ " or "  "
					local why = reason(plugin)
					local right = plugin.status == "update" and "updates available" or ""
					local prefix = mark .. dot .. " "
					local left = prefix .. plugin.name .. (why ~= "" and ("  " .. why) or "")
					local gap = cols - vim.api.nvim_strwidth(left) - vim.api.nvim_strwidth(right) - 2
					local text = left .. (" "):rep(math.max(gap, 2)) .. right
					local prow = line(text)
					state.rows[prow] = index
					local at = #mark
					add(prow, 0, mark, state.marked[index] and "PackviewMark" or "PackviewDim")
					add(prow, at, dot, (plugin.loaded or plugin.active) and "PackviewLoaded" or "PackviewDim")
					at = #prefix
					add(prow, at, plugin.name, "PackviewName")
					at = at + #plugin.name + 2
					if why ~= "" then
						add(prow, at, why, "PackviewReason")
					end
					if right ~= "" then
						add(prow, #text - #right, right, "PackviewUpdate")
					end

					for i, commit in ipairs(plugin.commits or {}) do
						if i > 4 then
							break
						end
						local indent = (" "):rep(vim.api.nvim_strwidth(prefix))
						local when = "(" .. commit.when .. ")"
						local commit_line = indent .. commit.sha .. "  " .. commit.subject .. "  " .. when
						local crow = line(commit_line)
						state.rows[crow] = index
						local cat = #indent
						add(crow, cat, commit.sha, "PackviewCommit")
						cat = cat + #commit.sha + 2
						add(crow, cat, commit.subject, "PackviewSubject")
						cat = cat + #commit.subject + 2
						add(crow, cat, when, "PackviewDim")
					end
			end
			line("")
		end
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for _, span in ipairs(state.spans) do
		vim.api.nvim_buf_set_extmark(state.buf, ns, span[1] - 1, span[2], {
			end_col = span[3],
			hl_group = span[4],
		})
	end
	if cursor then
		pcall(vim.api.nvim_win_set_cursor, state.win, { math.min(cursor[1], #lines), cursor[2] })
	end
end

return M
