-- One floating window. The buffer is rebuilt on every change.

local M = {}

local ns = vim.api.nvim_create_namespace("packview")
vim.api.nvim_set_hl(0, "PackviewUpdate", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "PackviewLoaded", { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, "PackviewDim", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "PackviewMark", { link = "Special", default = true })

local state = {
	plugins = {},
	rows = {}, -- buffer line -> plugin index
	marked = {},
	pending = 0,
	buf = nil,
	win = nil,
}

local function open()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local cfg = require("packview.config").opts
	local width = math.floor(vim.o.columns * cfg.width)
	local height = math.floor(vim.o.lines * cfg.height)
	state.buf = vim.api.nvim_create_buf(false, true)
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		border = cfg.border,
		title = " packview ",
		title_pos = "center",
		footer = " space mark   u update   U all   r check   d delete   q close ",
		footer_pos = "center",
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

local function counts()
	local loaded, updates = 0, 0
	for _, plugin in ipairs(state.plugins) do
		if plugin.loaded or plugin.active then
			loaded = loaded + 1
		end
		if plugin.status == "update" then
			updates = updates + 1
		end
	end
	return loaded, updates
end

function M.draw()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	local cursor = state.win and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_get_cursor(state.win)
	local loaded, updates = counts()
	local head = ("%d plugins   %d loaded   %d updates"):format(#state.plugins, loaded, updates)
	if state.pending > 0 then
		head = head .. ("   checking %d"):format(state.pending)
	end

	local lines = { head, "" }
	local marks = {}
	state.rows = {}
	for index, plugin in ipairs(state.plugins) do
		local dot = (plugin.loaded or plugin.active) and "●" or "○"
		local box = state.marked[index] and "[x]" or "[ ]"
		local note = plugin.label ~= "" and plugin.label or plugin.rev:sub(1, 7)
		lines[#lines + 1] = (" %s %s  %-28s %-22s %s"):format(box, dot, plugin.name, plugin.why, note)
		state.rows[#lines] = index
		marks[#lines] = plugin
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(state.buf, ns, 0, 0, { end_row = 1, hl_group = "Title", hl_eol = true })
	for line, plugin in pairs(marks) do
		local group = plugin.status == "update" and "PackviewUpdate"
			or (plugin.loaded or plugin.active) and "PackviewLoaded"
			or "PackviewDim"
		vim.api.nvim_buf_set_extmark(state.buf, ns, line - 1, 0, { end_row = line, hl_group = group, hl_eol = true })
		if state.marked[state.rows[line]] then
			vim.api.nvim_buf_set_extmark(state.buf, ns, line - 1, 1, { end_col = 4, hl_group = "PackviewMark" })
		end
	end
	if cursor then
		pcall(vim.api.nvim_win_set_cursor, state.win, { math.min(cursor[1], #lines), cursor[2] })
	end
end

function M.detail(plugin)
	local lines = {
		plugin.name,
		"",
		"src     " .. plugin.src,
		"commit  " .. plugin.rev:sub(1, 7),
		"load    " .. (plugin.why ~= "" and plugin.why or "when required"),
		"needs   " .. (#plugin.needs > 0 and table.concat(plugin.needs, ", ") or "-"),
		"state   " .. ((plugin.loaded or plugin.active) and "loaded" or "not loaded"),
		"path    " .. plugin.path,
	}
	if #plugin.log > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = plugin.ahead .. " new commits"
		for _, line in ipairs(plugin.log) do
			lines[#lines + 1] = "  " .. line
		end
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "text"
	local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = math.floor(vim.o.columns * 0.6),
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor(vim.o.columns * 0.2),
		border = "rounded",
		title = " " .. plugin.name .. " ",
		title_pos = "center",
	})
	vim.keymap.set("n", "q", function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf })
end

return M
