return
{
  'hrsh7th/nvim-cmp',
  dependencies = {
    'hrsh7th/cmp-nvim-lsp',  -- LSP source for nvim-cmp
    'hrsh7th/cmp-buffer',    -- Buffer source for nvim-cmp
    'hrsh7th/cmp-path',      -- Path source for nvim-cmp
    'L3MON4D3/LuaSnip',      -- Optional snippet engine
    'saadparwaiz1/cmp_luasnip',  -- Snippet completion source
  },
  config = function()
    require('config.cmp')   -- Point to your cmp.lua configuration
  end,
}
