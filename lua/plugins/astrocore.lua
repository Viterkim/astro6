---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    features = {
      autoformat = true,
      large_buf = { size = 1024 * 256, lines = 10000 },
      autopairs = true,
      cmp = true,
      diagnostics = { virtual_text = true, virtual_lines = false },
      highlighturl = true,
      notifications = true,
    },
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    autocmds = {
      clear_jumps_on_start = {
        {
          event = "VimEnter",
          desc = "Clear jump list on startup",
          callback = function() vim.cmd "clearjumps" end,
        },
      },
    },
    options = {
      opt = {
        clipboard = "unnamedplus",
        relativenumber = true,
        number = true,
        spell = false,
        signcolumn = "yes",
        wrap = true,
      },
      g = {
        autoformat = true,
        diagnostics_mode = 2,
      },
    },
  },
}
