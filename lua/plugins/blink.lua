return {
  "saghen/blink.cmp",
  version = "1.*",
  opts = function(_, opts)
    opts.keymap = vim.tbl_extend("force", opts.keymap or {}, {
      ["<Down>"] = { "select_next", "fallback" },
      ["<Up>"] = { "select_prev", "fallback" },
      ["<C-n>"] = { "select_next", "fallback" },
      ["<C-p>"] = { "select_prev", "fallback" },

      ["<CR>"] = { "accept", "fallback" },
      ["<C-e>"] = false,
    })

    opts.completion = vim.tbl_deep_extend("force", opts.completion or {}, {
      menu = {
        auto_show = true,
      },
      documentation = {
        auto_show = true,
        auto_show_delay_ms = 200,
      },
      trigger = {
        show_on_insert = false,
        show_on_insert_on_trigger_character = true,
      },
    })

    return opts
  end,
}
