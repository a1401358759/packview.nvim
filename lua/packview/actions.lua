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

-- A newer check drops results from the one it replaced, so a refresh
-- after an update cannot be stuck behind the check that was already running.
local check_gen = 0

function M.check()
	check_gen = check_gen + 1
	local gen = check_gen
	local view = require("packview.view")
	local git = require("packview.git")
	local plugins = view.plugins()
	local left = #plugins
	local next_i = 1
	local active = 0
	view.pending(left)

	local function pump()
		while active < 5 and next_i <= #plugins and gen == check_gen do
			local plugin = plugins[next_i]
			next_i = next_i + 1
			active = active + 1
			git.check(plugin, true, function()
				if gen ~= check_gen then
					return
				end
				active = active - 1
				left = left - 1
				view.pending(left)
				pump()
			end)
		end
	end

	if #plugins > 0 then
		pump()
	end
end

local updating = false
local batch = 5

function M.update(all)
	if updating then
		return
	end
	local view = require("packview.view")
	local plugins = all and vim.tbl_filter(function(plugin)
		return plugin.status == "update"
	end, view.plugins()) or view.marked()
	if #plugins == 0 then
		return
	end
	updating = true
	for _, plugin in ipairs(plugins) do
		plugin.phase = "queued"
	end
	local index = 1

	local function finish()
		updating = false
		view.pending(0)
		vim.schedule(function()
			view.show(require("packview.state").list())
			M.check()
		end)
	end

	local function step()
		local group = vim.list_slice(plugins, index, index + batch - 1)
		if #group == 0 then
			finish()
			return
		end
		for _, plugin in ipairs(group) do
			plugin.phase = "updating"
		end
		view.pending(0)
		vim.schedule(function()
			local notify = vim.notify
			vim.notify = function()
				return 0
			end
			local ok, err = pcall(vim.pack.update, names(group), { force = true })
			vim.notify = notify
			if not ok then
				vim.notify(err, vim.log.levels.ERROR)
			end
			local pending = #group
			for _, plugin in ipairs(group) do
				vim.system({ "git", "rev-parse", "HEAD" }, { cwd = plugin.path, text = true }, function(result)
					local head = vim.trim(result.stdout or "")
					local moved = not plugin.tip or head == plugin.tip
					plugin.phase = (ok and result.code == 0 and moved) and "updated" or "error"
					pending = pending - 1
					if pending == 0 then
						vim.schedule(function()
							index = index + #group
							step()
						end)
					end
				end)
			end
		end)
	end

	step()
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
