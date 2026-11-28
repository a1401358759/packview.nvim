-- Every change goes through vim.pack. The view only displays the result.

local M = {}

local function names(plugins)
	return vim.tbl_map(function(plugin)
		return plugin.name
	end, plugins)
end

local function run(fn)
	local ok, err = pcall(fn)
	if not ok then
		vim.notify(err, vim.log.levels.ERROR)
	end
end

local checking = false

function M.check()
	if checking then
		return
	end
	checking = true
	local view = require("packview.view")
	local git = require("packview.git")
	local plugins = view.plugins()
	local left = #plugins
	local next_i = 1
	local active = 0
	view.pending(left)

	local function pump()
		while active < 6 and next_i <= #plugins do
			local plugin = plugins[next_i]
			next_i = next_i + 1
			active = active + 1
			git.check(plugin, true, function()
				active = active - 1
				left = left - 1
				view.pending(left)
				if left == 0 then
					checking = false
				end
				pump()
			end)
		end
	end

	if #plugins == 0 then
		checking = false
		return
	end
	pump()
end

function M.update(all)
	local view = require("packview.view")
	local plugins = all and vim.tbl_filter(function(plugin)
		return plugin.status == "update"
	end, view.plugins()) or view.marked()
	if #plugins == 0 then
		return
	end
	run(function()
		vim.pack.update(names(plugins), { force = true })
	end)
	M.check()
end

function M.delete()
	local view = require("packview.view")
	local plugins = view.marked()
	if #plugins == 0 then
		return
	end
	local label = table.concat(names(plugins), ", ")
	if vim.fn.confirm("Delete " .. label .. "?", "&Yes\n&No", 2) ~= 1 then
		return
	end
	run(function()
		vim.pack.del(names(plugins))
	end)
	view.show(require("packview.state").list())
end

function M.detail()
	local plugin = require("packview.view").current()
	if not plugin then
		return
	end
	local url = plugin.src:gsub("%.git$", "")
	if plugin.head and plugin.tip and plugin.head ~= plugin.tip then
		url = url .. "/compare/" .. plugin.head:sub(1, 12) .. "..." .. plugin.tip:sub(1, 12)
	end
	vim.ui.open(url)
end

return M
