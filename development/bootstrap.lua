vim.opt.rtp:append(".")
vim.opt.rtp:append("./development/testing.nvim")
vim.opt.rtp:append("./development/sqlite.nvim")

require("testing").setup()
