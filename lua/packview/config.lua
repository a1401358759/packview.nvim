local M = {}

M.opts = {
	width = 0.8,
	height = 0.8,
	border = "rounded",
}

-- provider() -> { { name, loaded, why, needs } }
M.provider = nil

function M.setup(opts)
	M.opts = vim.tbl_extend("force", M.opts, opts or {})
	M.provider = M.opts.provider
end

return M
