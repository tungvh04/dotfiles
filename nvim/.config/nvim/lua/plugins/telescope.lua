return {
    'nvim-telescope/telescope.nvim', tag = '0.1.8',
-- or                              , branch = '0.1.x',
    dependencies = { 'nvim-lua/plenary.nvim' },
	config = function()
		local builtin = require('telescope.builtin')
		vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
		vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telescope live grep' })
		vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
		vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })
		local actions = require("telescope.actions")
	end,
	opts = function()
		local actions = require('telescope.actions')
		require("telescope").setup({
			defaults = {
				mappings = {
					n = {
						['q'] = actions.close,
						["<C-c>"] = actions.close,
					},
					i = {
						["<C-c>"] = function()
							vim.api.nvim_command("stopinsert")
						end,
					}
				}
			}
		})
	end,
}
