-- One floating window. The bar is a row of buttons; updates sit under their plugin.

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

local function byte(color, shift)
	return math.floor(color / shift) % 256
end

-- A button needs its own background. Link a group and the background is lost.
local function colors()
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local cursor = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
	local info = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false })
	local hint = vim.api.nvim_get_hl(0, { name = "DiagnosticHint", link = false })
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
	local bg = normal.bg or cursor.bg or 0x24283b
	local r, g, b = byte(bg, 65536), byte(bg, 256), byte(bg, 1)
	local light = (r + g + b) / 3 > 140
	local function step(c)
		return light and math.max(0, c - 24) or math.min(255, c + 28)
	end
	local pill = step(r) * 65536 + step(g) * 256 + step(b)
	local accent = info.fg or hint.fg or normal.fg
	vim.api.nvim_set_hl(0, "PackviewButton", { bg = pill, fg = normal.fg })
	vim.api.nvim_set_hl(0, "PackviewButtonKey", { bg = pill, fg = accent })
	vim.api.nvim_set_hl(0, "PackviewBadge", { bg = pill, fg = accent, bold = true })
	vim.api.nvim_set_hl(0, "PackviewWhen", { fg = comment.fg, italic = true })
end

local function link(name, to)
	vim.api.nvim_set_hl(0, name, { link = to, default = true })
end

link("PackviewTitle", "Title")
link("PackviewDim", "Comment")
link("PackviewName", "Normal")
link("PackviewLoaded", "DiagnosticOk")
link("PackviewReason", "Constant")
link("PackviewHash", "Identifier")
link("PackviewType", "Function")
link("PackviewSubject", "Comment")
link("PackviewMark", "Special")

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
	local function win_opt(name, value)
		vim.api.nvim_set_option_value(name, value, { win = state.win })
	end
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
		{ "Log", updates },
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

local function kind_of(subject)
	local kind, rest = subject:match("^([%a][%w_]*)[%w_%(%)!]*:%s+(.*)$")
	if kind and rest ~= "" then
		return kind, rest
	end
end

local actions = {
	{ "Update", "u" },
	{ "All", "U" },
	{ "Check", "r" },
	{ "Clean", "x" },
	{ "Open", "Enter" },
}

function M.draw()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	colors()
	local cursor = state.win and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_get_cursor(state.win)
	local cols = width()
	local lines = {}
	state.rows, state.spans = {}, {}

	local function line(text)
		lines[#lines + 1] = text
		return #lines
	end

	-- One slot per button, the label centered in it, so the row fills the window.
	local slot = math.floor(cols / #actions)
	local cells = {}
	for i = 1, cols do
		cells[i] = " "
	end
	local function place(at, text)
		for i = 1, #text do
			local pos = at + i - 1
			if pos >= 1 and pos <= cols then
				cells[pos] = text:sub(i, i)
			end
		end
	end
	local bar = line("")
	for i, action in ipairs(actions) do
		local label = " " .. action[1] .. " (" .. action[2] .. ") "
		local at = (i - 1) * slot + math.max(math.floor((slot - #label) / 2), 0) + 1
		place(at, label)
		add(bar, at - 1, label, "PackviewButton")
		add(bar, at + #action[1] + 1, "(" .. action[2] .. ")", "PackviewButtonKey")
	end
	lines[bar] = table.concat(cells)

	local updates = 0
	for _, plugin in ipairs(state.plugins) do
		if plugin.status == "update" then
			updates = updates + 1
		end
	end
	local summary = ("  Total: %d plugins"):format(#state.plugins)
	if state.pending > 0 then
		summary = summary .. ("    checking %d"):format(state.pending)
	end
	local row = line(summary)
	add(row, 2, summary:sub(3), "PackviewTitle")
	line("")

	for _, group in ipairs(groups()) do
		local title, indexes = group[1], group[2]
		if #indexes > 0 then
			local heading = ("  %s  (%d)"):format(title, #indexes)
			local grow = line(heading)
			add(grow, 2, title, "PackviewTitle")
			add(grow, 2 + #title + 2, "(" .. #indexes .. ")", "PackviewDim")

			for _, index in ipairs(indexes) do
				local plugin = state.plugins[index]
				local dot = (plugin.loaded or plugin.active) and "\226\151\143" or "\226\151\139"
				local mark = state.marked[index] and "\226\150\184 " or "  "
				local why = reason(plugin)
				local badge = plugin.status == "update" and " updates available " or ""
				local prefix = mark .. dot .. " "
				local left = prefix .. plugin.name .. (why ~= "" and ("  " .. why) or "")
				local gap = cols - vim.api.nvim_strwidth(left) - vim.api.nvim_strwidth(badge) - 2
				local text = left .. (" "):rep(math.max(gap, 2)) .. badge
				local prow = line(text)
				state.rows[prow] = index
				add(prow, #mark, dot, (plugin.loaded or plugin.active) and "PackviewLoaded" or "PackviewDim")
				local at = #prefix
				add(prow, at, plugin.name, "PackviewName")
				if why ~= "" then
					add(prow, at + #plugin.name + 2, why, "PackviewReason")
				end
				if badge ~= "" then
					add(prow, #text - #badge, badge, "PackviewBadge")
				end

				for i, commit in ipairs(plugin.commits or {}) do
					if i > 4 then
						break
					end
					local indent = (" "):rep(vim.api.nvim_strwidth(prefix) + 2)
					local kind, rest = kind_of(commit.subject)
					local body = kind and (kind .. ": " .. rest) or commit.subject
					local when = "(" .. commit.when .. ")"
					local commit_line = indent .. commit.sha .. "  " .. body .. "  " .. when
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
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for _, span in ipairs(state.spans) do
		pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, span[1] - 1, span[2], {
			end_col = math.min(span[3], #lines[span[1]]),
			hl_group = span[4],
		})
	end
	if cursor then
		pcall(vim.api.nvim_win_set_cursor, state.win, { math.min(cursor[1], #lines), 0 })
	end
end

return M
