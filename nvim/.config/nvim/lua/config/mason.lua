local servers = {'lua_ls', 'clangd', 'pyright', 'tsserver', 'ast_grep', 'rust_analyzer'}

require('mason').setup()
require('mason-lspconfig').setup({
	ensure_installed = servers,
})

