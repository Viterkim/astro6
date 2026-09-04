local is_ssh = vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT
local use_osc52 = is_ssh and vim.env.TMUX == nil

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    features = {
      -- Override Astro default: detect large buffers sooner.
      large_buf = { size = 1024 * 256, lines = 10000 },
      -- Override Astro default: keep virtual lines off initially.
      diagnostics = { virtual_text = true, virtual_lines = false },
    },
    autocmds = {
      clear_jumps_on_start = {
        {
          event = "VimEnter",
          desc = "Clear jump list on startup",
          callback = function() vim.cmd "clearjumps" end,
        },
      },
      ssh_osc52_yank = use_osc52 and {
        {
          event = "TextYankPost",
          callback = function()
            local ev = vim.v.event
            if ev.operator == "y" then require("vim.ui.clipboard.osc52").copy "+"(ev.regcontents) end
          end,
        },
      } or false,
    },
    options = {
      opt = {
        -- y goes to the local terminal over SSH; p stays in Vim.
        clipboard = use_osc52 and "" or "unnamedplus",
        spell = false,
        -- Override Astro default.
        wrap = true,
      },
      g = {
        autoformat = true,
      },
    },
  },
}
