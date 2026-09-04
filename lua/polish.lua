vim.opt.winblend = 0

local function is_empty_untitled(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
    and not vim.bo[bufnr].modified
    and vim.api.nvim_buf_get_name(bufnr) == ""
    and vim.api.nvim_buf_line_count(bufnr) == 1
    and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ""
end

vim.api.nvim_create_autocmd("BufHidden", {
  group = vim.api.nvim_create_augroup("cleanup_abandoned_untitled_buffers", { clear = true }),
  desc = "Remove abandoned empty buffers from the tabline",
  callback = function(args)
    vim.schedule(function()
      if is_empty_untitled(args.buf) then pcall(vim.api.nvim_buf_delete, args.buf, { force = true }) end
    end)
  end,
})

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

local os = vim.uv.os_uname().sysname
if os == "Linux" then
  -- Ghostty already multiplies discrete wheel events; other terminals (including
  -- Windows Terminal over SSH) need Neovim to provide the scroll multiplier.
  local is_ghostty = vim.env.TERM_PROGRAM == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
  vim.opt.mousescroll = is_ghostty and "ver:1,hor:2" or "ver:8,hor:2"
end

vim.api.nvim_create_user_command(
  "UpdateAll",
  function() vim.cmd "AstroUpdate" end,
  { desc = "Update AstroNvim packages" }
)

vim.api.nvim_create_user_command("Res", function() require("funcs").restart_with_session() end, {
  desc = "Restart Neovim and restore session",
})

vim.opt.equalalways = false

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("stable_sidebar_widths", { clear = true }),
  pattern = { "neo-tree", "aerial" },
  callback = function()
    vim.opt_local.winfixwidth = true
    vim.opt_local.winfixheight = false
  end,
})
