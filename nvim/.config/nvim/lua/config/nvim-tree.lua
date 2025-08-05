local function opts(desc)
	return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
end
local function my_on_attach(bufnr)
  local api = require "nvim-tree.api"


  -- default mappings
  api.config.mappings.default_on_attach(bufnr)

end

local api = require "nvim-tree.api"

vim.keymap.set("n", "<C-f>", api.tree.open, opts("Open"))

-- pass to setup along with your other options
require("nvim-tree").setup {
  ---
  on_attach = my_on_attach,
  ---
}
