vim.opt.winblend = 0

vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*",
  desc = "Disable auto-comment formatting for this buffer",
  callback = function() vim.opt_local.formatoptions:remove { "c", "r", "o" } end,
})

local image_globs = require("utils.image_globs").patterns()

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("no_image_buffers", { clear = true }),
  pattern = image_globs,
  desc = "Block image/media files from opening in Neovim",
  callback = function(args)
    local buf = args.buf
    local file = args.file
    local name = vim.fn.fnamemodify(file, ":t")

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "Image/media opening disabled.",
      "",
      file,
    })

    vim.bo[buf].modified = false
    vim.bo[buf].modifiable = false

    vim.notify("Blocked image/media file: " .. name, vim.log.levels.WARN)
  end,
})

local os = (vim.uv or vim.loop).os_uname().sysname
if os == "Linux" then vim.opt.mousescroll = "ver:8,hor:2" end

vim.api.nvim_create_user_command("UpdateAll", function()
  vim.cmd "AstroUpdate"
  vim.cmd "TSUpdate"
end, { desc = "Update AstroNvim packages and Treesitter parsers" })
