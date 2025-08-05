return {
    "williamboman/mason.nvim",
	{
		"williamboman/mason-lspconfig.nvim",
		config = function()
			require("config.mason")
		end,
	},
    "neovim/nvim-lspconfig",
}
