return {
  "stevearc/dressing.nvim",
  lazy = true,
  init = function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(...)
      local lazy = require "lazy" --[[@as Lazy]]
      lazy.load { plugins = { "dressing.nvim" } }
      return vim.ui.select(...)
    end
  end,
  opts = {
    input = { enabled = true },
    select = {
      enabled = true,
      backend = { "telescope", "builtin" }, -- Fallback order
      get_config = function(opts)
        if opts.kind == "rust_target" or opts.kind == "rust_platform" then return { backend = { "builtin" } } end
      end,
      builtin = {
        relative = "editor",
        max_width = 80,
        min_height = 5, -- Ensures no "0 height" errors
      },
    },
  },
}
