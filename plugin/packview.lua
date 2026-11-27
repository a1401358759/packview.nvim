if vim.g.loaded_packview then
	return
end
vim.g.loaded_packview = true

vim.api.nvim_create_user_command("Packview", function()
	require("packview").open()
end, { desc = "Installed plugins" })
