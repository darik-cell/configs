vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  defaults = {
    lazy = false,
  },
  install = {
    colorscheme = { "darcula-dark" },
  },
  checker = {
    enabled = false,
  },
  change_detection = {
    notify = false,
  },
})

require("config.tabline").setup()
require("config.keymaps")
require("config.autocmds")
