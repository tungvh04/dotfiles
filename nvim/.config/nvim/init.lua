vim.opt.list = true
vim.opt.listchars = {
  tab = '»·',    -- Tab character: "»" for tab and "·" for each space in the tab
  trail = '·',   -- Trailing spaces: also shown as a dot
}
vim.opt.expandtab = true

local set = vim.opt -- set options
set.tabstop = 4
set.softtabstop = 4
set.shiftwidth = 4

vim.opt.relativenumber = true
vim.opt.number = true

-- Create an autocommand for ModeChanged
vim.api.nvim_create_autocmd("ModeChanged", {
  pattern = "*",
  callback = function()
    -- Get the current mode
    local current_mode = vim.fn.mode()

    -- If we are in normal mode (n), enable relative line numbers
    if current_mode == "n" then
      vim.opt.relativenumber = true
      vim.opt.number = true  -- absolute number for the current line
    else
      -- For other modes (like insert, visual), disable relative line numbers
      vim.opt.relativenumber = false
      vim.opt.number = true  -- still keep the absolute line number
    end
  end,
})

-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

require("config.lazy")

vim.cmd("colorscheme onedark")

-- vim.api.nvim_set_option("clipboard", "unnamed")
vim.g.clipboard = "unnamed"

