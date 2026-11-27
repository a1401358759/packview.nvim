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

function M.check()
	local view = require("packview.view")
	local git = require("packview.git")
	local plugins = view.plugins()
	local left = #plugins
	view.pending(left)
	for _, plugin in ipairs(plugins) do
		git.check(plugin, true, function()
			left = left - 1
			view.pending(left)
		end)
	end
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
	if plugin then
		require("packview.view").detail(plugin)
	end
end

return M
