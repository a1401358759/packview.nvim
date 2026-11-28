local M = {}

function M.setup(opts)
	require("packview.config").setup(opts)
end

function M.open()
	if vim.fn.has("nvim-0.12") == 0 then
		return vim.notify("packview needs Neovim 0.12 (vim.pack)", vim.log.levels.ERROR)
	end
	require("packview.view").show(require("packview.state").list())
	require("packview.actions").check()
end

return M
