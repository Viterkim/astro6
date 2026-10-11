return {
  "saghen/blink.cmp",
  version = "1.*",
  opts = function(_, opts)
    local function select_in_menu(command)
      return function(cmp)
        if cmp.is_menu_visible() then
          cmp[command]()
          return true
        end

        if cmp.is_active() then
          return cmp.show { initial_selected_item_idx = command == "select_next" and 1 or -1 }
        end
      end
    end

    opts.keymap = vim.tbl_extend("force", opts.keymap or {}, {
      ["<Down>"] = { select_in_menu("select_next"), "fallback" },
      ["<Up>"] = { select_in_menu("select_prev"), "fallback" },
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
