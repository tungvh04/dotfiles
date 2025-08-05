return {

    -- LSP config plugin
    {
        'neovim/nvim-lspconfig',
        config = function()
            require('config.lsp')  -- Call the LSP configuration from 'lua/config/lsp.lua'
        end,
    },

}
