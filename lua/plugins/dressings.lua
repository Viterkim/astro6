return {
  "stevearc/dressing.nvim",
  lazy = true,
  init = function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(...)
      require("lazy").load { plugins = { "dressing.nvim" } }
      return vim.ui.select(...)
    end
  end,
  opts = {
    input = { enabled = true },
    select = {
      enabled = true,
      backend = { "telescope", "builtin" }, -- Fallback order
      builtin = {
        relative = "editor",
        max_width = 80,
        min_height = 5, -- Ensures no "0 height" errors
      },
    },
  },
}
