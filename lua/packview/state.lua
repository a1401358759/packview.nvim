-- Plugins come from vim.pack. Load reasons come from the optional provider.

local M = {}

function M.list()
	local extra = {}
	local provider = require("packview.config").provider
	if provider then
		for _, row in ipairs(provider()) do
			extra[row.name] = row
		end
	end

	local plugins = {}
	for _, pack in ipairs(vim.pack.get(nil, { info = false })) do
		local name = pack.spec.name
		local row = extra[name] or {}
		plugins[#plugins + 1] = {
			name = name,
			src = pack.spec.src,
			path = pack.path,
			version = pack.spec.version,
			rev = pack.rev or "",
			active = pack.active,
			loaded = row.loaded == true,
			why = row.why or "",
			needs = row.needs or {},
			status = "idle",
			ahead = 0,
			log = {},
			label = "",
		}
	end
	table.sort(plugins, function(a, b)
		return a.name < b.name
	end)
	return plugins
end

return M
