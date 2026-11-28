-- The list reads as a status board. A plugin's state is a badge on its row,
-- so an update in progress is visible without leaving the window.

local M = {}

local ns = vim.api.nvim_create_namespace("packview")

local state = {
	plugins = {},
	rows = {},
	spans = {},
	marked = {},
	pending = 0,
	buf = nil,
	win = nil,
}

local ink = "#222222"

local function colors()
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
	local warn = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false })
	local ok = vim.api.nvim_get_hl(0, { name = "DiagnosticOk", link = false })
	local info = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false })
	local error = vim.api.nvim_get_hl(0, { name = "DiagnosticError", link = false })
	local function chip(fg)
		return { bg = fg, fg = ink, bold = true }
	end
	vim.api.nvim_set_hl(0, "PackviewHeader", chip("#DCA561"))
	vim.api.nvim_set_hl(0, "PackviewVersion", chip("#56B6C2"))
	vim.api.nvim_set_hl(0, "PackviewUpdate", chip(string.format("#%06x", warn.fg or 0xe0af68)))
	vim.api.nvim_set_hl(0, "PackviewBusy", chip(string.format("#%06x", info.fg or 0x7dcfff)))
	vim.api.nvim_set_hl(0, "PackviewDone", chip(string.format("#%06x", ok.fg or 0x9ece6a)))
	vim.api.nvim_set_hl(0, "PackviewFail", chip(string.format("#%06x", error.fg or 0xf7768e)))
	vim.api.nvim_set_hl(0, "PackviewQueued", { bg = "#888888", fg = ink })
	vim.api.nvim_set_hl(0, "PackviewButton", { bg = "#888888", fg = ink })
	vim.api.nvim_set_hl(0, "PackviewButtonKey", { bg = "#888888", fg = ink, bold = true })
	vim.api.nvim_set_hl(0, "PackviewWhen", { fg = comment.fg, italic = true })
end

local function link(name, to)
	vim.api.nvim_set_hl(0, name, { link = to, default = true })
end

link("PackviewTitle", "Title")
link("PackviewDim", "Comment")
link("PackviewName", "Normal")
link("PackviewDot", "DiagnosticOk")
link("PackviewReason", "Constant")
link("PackviewHash", "Identifier")
link("PackviewType", "Function")
link("PackviewSubject", "Comment")
link("PackviewMark", "Special")

local function width()
	return vim.api.nvim_win_get_width(state.win)
end

local function win_opt(name, value)
	vim.api.nvim_set_option_value(name, value, { win = state.win })
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
	})
	win_opt("number", false)
	win_opt("relativenumber", false)
	win_opt("signcolumn", "no")
	win_opt("statuscolumn", "")
	win_opt("foldcolumn", "0")
	win_opt("cursorline", true)
	win_opt("wrap", false)
	win_opt("list", false)
	vim.bo[state.buf].filetype = "packview"
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

local function add(line, col, text, group, priority)
	state.spans[#state.spans + 1] = { line, col, col + #text, group, priority }
end

local badge = {
	updating = { " updating ", "PackviewBusy" },
	queued = { " queued ", "PackviewQueued" },
	updated = { " updated ", "PackviewDone" },
	update = { " updates available ", "PackviewUpdate" },
	checking = { " checking ", "PackviewBusy" },
	error = { " failed ", "PackviewFail" },
}

local titles = { "Updating", "Queued", "Updates", "Failed", "Updated", "Loaded", "Not loaded" }

local function rank(plugin)
	if plugin.phase == "updating" then
		return 1
	end
	if plugin.phase == "queued" then
		return 2
	end
	if plugin.status == "update" then
		return 3
	end
	if plugin.phase == "error" then
		return 4
	end
	if plugin.phase == "updated" then
		return 5
	end
	if plugin.loaded or plugin.active then
		return 6
	end
	return 7
end

local function sections()
	local order = {}
	for index in ipairs(state.plugins) do
		order[#order + 1] = index
	end
	table.sort(order, function(a, b)
		local ra, rb = rank(state.plugins[a]), rank(state.plugins[b])
		return ra == rb and a < b or ra < rb
	end)
	local result, current = {}, nil
	for _, index in ipairs(order) do
		local title = titles[rank(state.plugins[index])]
		if title ~= current then
			current = title
			result[#result + 1] = { title, {} }
		end
		local bucket = result[#result][2]
		bucket[#bucket + 1] = index
	end
	return result
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

local function kind_of(subject)
	local kind, rest = subject:match("^([%a][%w_]*)[%w_%(%)!]*:%s+(.*)$")
	if kind and rest ~= "" then
		return kind, rest
	end
end

local buttons = {
	{ "Update", "u" },
	{ "All", "U" },
	{ "Check", "r" },
	{ "Clean", "x" },
	{ "Open", "Enter" },
}

local function center(text, cols)
	local pad = math.max(math.floor((cols - vim.api.nvim_strwidth(text)) / 2), 0)
	return (" "):rep(pad) .. text .. (" "):rep(cols - pad - vim.api.nvim_strwidth(text))
end

local function put(row, col, text)
	return row:sub(1, col) .. text .. row:sub(col + 1 + #text)
end

function M.draw()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	colors()
	local follow = nil
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		follow = state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
	end
	local cols = width()
	local lines = {}
	state.rows, state.spans = {}, {}

	local function line(text)
		lines[#lines + 1] = text
		return #lines
	end

	local name, version = " packview.nvim ", " " .. require("packview.version").VERSION .. " "
	local title = center(name .. version, cols)
	local head = line(title)
	local name_at = math.floor((cols - #name - #version) / 2)
	add(head, math.max(name_at, 0), name, "PackviewHeader")
	add(head, math.max(name_at, 0) + #name, version, "PackviewVersion")

	local url = "https://github.com/a1401358759/packview.nvim"
	local url_row = line(center(url, cols))
	add(url_row, math.max(math.floor((cols - #url) / 2), 0), url, "PackviewDim")
	line("")

	local bar = line((" "):rep(cols))
	local x = 2
	for _, button in ipairs(buttons) do
		local text = " (" .. button[2] .. ") " .. button[1] .. " "
		if x + #text > cols then
			break
		end
		lines[bar] = put(lines[bar], x, text)
		add(bar, x, text, "PackviewButton", 100)
		add(bar, x + 2, button[2], "PackviewButtonKey", 110)
		x = x + #text + 1
	end
	lines[bar] = lines[bar] .. (" "):rep(cols - #lines[bar])

	line("")
	line("")

	local updates, busy, queued = 0, 0, 0
	for _, plugin in ipairs(state.plugins) do
		if plugin.status == "update" then
			updates = updates + 1
		end
		if plugin.phase == "updating" then
			busy = busy + 1
		elseif plugin.phase == "queued" then
			queued = queued + 1
		end
	end
	local summary = ("  %d plugins"):format(#state.plugins)
	if busy > 0 or queued > 0 then
		summary = summary .. ("    %d updating"):format(busy)
		if queued > 0 then
			summary = summary .. ("    %d queued"):format(queued)
		end
	elseif state.pending > 0 then
		summary = summary .. ("    checking %d"):format(state.pending)
	elseif updates > 0 then
		summary = summary .. ("    %d updates"):format(updates)
	end
	local row = line(summary)
	add(row, 2, summary:sub(3), "PackviewTitle")
	line("")

	for _, section in ipairs(sections()) do
		local title, indexes = section[1], section[2]
		local heading = ("  %s  (%d)"):format(title, #indexes)
		local grow = line(heading)
		add(grow, 2, title, "PackviewTitle")
		add(grow, 2 + #title + 2, "(" .. #indexes .. ")", "PackviewDim")

		for _, index in ipairs(indexes) do
			local plugin = state.plugins[index]
			local dot = (plugin.loaded or plugin.active) and "\226\151\143" or "\226\151\139"
			local mark = state.marked[index] and "\226\150\184" or " "
			local why = reason(plugin)
			local chip = badge[plugin.phase] or badge[plugin.status]
			local chip_text = chip and chip[1] or ""
			local prefix = " " .. mark .. " " .. dot .. " "
			local body = plugin.name .. (why ~= "" and ("   " .. why) or "")
			local left = prefix .. body
			local gap = cols - vim.api.nvim_strwidth(left) - vim.api.nvim_strwidth(chip_text) - 2
			local text = left .. (" "):rep(math.max(gap, 2)) .. chip_text
			local prow = line(text)
			state.rows[prow] = index
			if state.marked[index] then
				add(prow, 1, mark, "PackviewMark")
			end
			add(prow, 3, dot, (plugin.loaded or plugin.active) and "PackviewDot" or "PackviewDim")
			add(prow, #prefix, plugin.name, "PackviewName")
			if why ~= "" then
				add(prow, #prefix + #plugin.name + 3, why, "PackviewReason")
			end
			if chip then
				add(prow, #text - #chip_text, chip_text, chip[2])
			end

			for i, commit in ipairs(plugin.commits or {}) do
				if i > 4 then
					break
				end
				local indent = (" "):rep(vim.api.nvim_strwidth(prefix) + 2)
				local kind, rest = kind_of(commit.subject)
				local when = "(" .. commit.when .. ")"
				local commit_line = indent .. commit.sha .. "  " .. (kind and (kind .. ": " .. rest) or commit.subject) .. "  " .. when
				local crow = line(commit_line)
				state.rows[crow] = index
				local cat = #indent
				add(crow, cat, commit.sha, "PackviewHash")
				cat = cat + #commit.sha + 2
				if kind then
					add(crow, cat, kind, "PackviewType")
					cat = cat + #kind
					add(crow, cat, ": " .. rest, "PackviewSubject")
					cat = cat + 2 + #rest + 2
				else
					add(crow, cat, commit.subject, "PackviewSubject")
					cat = cat + #commit.subject + 2
				end
				add(crow, cat, when, "PackviewWhen")
			end
		end
		line("")
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for _, span in ipairs(state.spans) do
		pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, span[1] - 1, span[2], {
			end_col = math.min(span[3], #lines[span[1]]),
			hl_group = span[4],
			priority = span[5],
		})
	end
	local target = nil
	if follow then
		for i, index in pairs(state.rows) do
			if index == follow and (not target or i < target) then
				target = i
			end
		end
	end
	if not target then
		for i = 1, #lines do
			if state.rows[i] then
				target = i
				break
			end
		end
	end
	if target then
		pcall(vim.api.nvim_win_set_cursor, state.win, { target, 0 })
	end
end

return M
