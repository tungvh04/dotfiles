local lspconfig = require('lspconfig')

local on_attach = function(client, bufnr)
	-- Enable 'gd' to go to definition
	local opts = { noremap=true, silent=true }
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
end

-- Python LSP
lspconfig.pyright.setup {
	on_attach = on_attach
}

-- JavaScript/TypeScript LSP
lspconfig.tsserver.setup {
	on_attach = on_attach
}

-- Lua LSP
lspconfig.lua_ls.setup {
  settings = {
    Lua = {
      diagnostics = {
        globals = { 'vim' },  -- Recognize 'vim' as a global variable
      },
      workspace = {
        library = vim.api.nvim_get_runtime_file("", true),  -- Make the server aware of Neovim runtime files
        checkThirdParty = false,  -- Prevent asking about third-party libraries
      },
      telemetry = {
        enable = false,  -- Disable telemetry data collection
      },
    },
  },
  on_attach = on_attach
}

-- C++ LSP setup
lspconfig.clangd.setup{
    cmd = { "clangd" },  -- This ensures `clangd` is being called as the language server
    filetypes = { "c", "cpp", "objc", "objcpp" },  -- Supported filetypes
    root_dir = lspconfig.util.root_pattern("compile_commands.json", ".git"),  -- Root directory setup
    settings = {
        clangd = {
            -- Add any specific clangd options here if needed
        },
    },
	on_attach = on_attach
}
