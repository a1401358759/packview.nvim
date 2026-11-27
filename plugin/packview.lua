if vim.g.loaded_packview then
	return
end
vim.g.loaded_packview = true

vim.api.nvim_create_user_command("Packview", function()
	require("packview").open()
end, { desc = "Installed plugins" })

vim.api.nvim_create_user_command("PackviewUpdate", function()
	vim.pack.update(nil, { force = true })
end, { desc = "Update every plugin" })

vim.keymap.set("n", "<leader>ps", "<cmd>Packview<cr>", { desc = "Plugins", silent = true })
vim.keymap.set("n", "<leader>pU", "<cmd>PackviewUpdate<cr>", { desc = "Update plugins", silent = true })
