local M = {}

function M.bind(buf)
	local function map(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true })
	end
	local actions = require("packview.actions")
	local view = require("packview.view")
	map("q", view.close)
	map("<Esc>", view.close)
	map("<Space>", view.toggle)
	map("r", actions.check)
	map("u", function()
		actions.update(false)
	end)
	map("U", function()
		actions.update(true)
	end)
	map("d", actions.delete)
	map("<CR>", actions.detail)
end

return M
