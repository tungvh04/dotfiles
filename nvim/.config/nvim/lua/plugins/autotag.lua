return {
	'windwp/nvim-ts-autotag',
	config = function()
		require('nvim-ts-autotag').setup({
		filetypes = { "html", "xml", "typescriptreact", "javascriptreact", "vue", "svelte", "markdown" },
		skip_tags = { "area", "base", "br", "col", "command", "embed", "hr", "img", "slot", "input", "keygen", "link", "meta", "param", "source", "track", "wbr" },
	})
  end,
}
