vim.opt.winblend = 0

vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*",
  desc = "Disable auto-comment formatting for this buffer",
  callback = function() vim.opt_local.formatoptions:remove { "c", "r", "o" } end,
})

local os = (vim.uv or vim.loop).os_uname().sysname
if os == "Linux" then vim.opt.mousescroll = "ver:8,hor:2" end

vim.api.nvim_create_user_command("UpdateAll", function()
  vim.cmd "AstroUpdate"
  vim.cmd "TSUpdate"
end, { desc = "Update AstroNvim packages and Treesitter parsers" })
