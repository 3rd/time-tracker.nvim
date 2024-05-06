vim.opt.rtp:append(".")
vim.opt.rtp:append("./development/testing.nvim")

require("testing").setup()
