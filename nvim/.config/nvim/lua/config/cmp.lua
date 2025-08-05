local cmp = require('cmp')

cmp.setup({
  snippet = {
    expand = function(args)
      require('luasnip').lsp_expand(args.body)  -- Using LuaSnip for snippets (optional)
    end,
  },
  mapping = {
    ['<CR>'] = cmp.mapping.confirm({ select = true }),  -- Confirm the first option with Enter
    ['<Tab>'] = cmp.mapping.select_next_item(),
    ['<S-Tab>'] = cmp.mapping.select_prev_item(),
  },
  sources = {
    { name = 'nvim_lsp' },  -- Use LSP as a source for autocompletion
    { name = 'buffer' },  -- Use LSP as a source for autocompletion
    { name = 'path' },  -- Use LSP as a source for autocompletion
    -- Add other sources like buffer, path, etc., if needed
  },
})
