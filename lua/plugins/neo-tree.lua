return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    source_selector = {
      winbar = false,
      statusline = false,
    },
    filesystem = {
      follow_current_file = {
        enabled = true,
        leave_dirs_open = false,
      },
      filtered_items = {
        visible = false,
        hide_dotfiles = false,
        hide_gitignored = false,
        hide_by_name = {
          ".git",
        },
      },
      hijack_netrw_behavior = "open_current",
      use_libuv_file_watcher = true,
      use_popups_for_input = true,
    },
    window = {
      width = 25,
      mappings = {
        ["H"] = function() require("smart-splits").move_cursor_left() end,
        ["h"] = function() require("smart-splits").move_cursor_right() end,
        ["k"] = function() require("smart-splits").move_cursor_down() end,
        ["K"] = function() require("smart-splits").move_cursor_up() end,
        ["l"] = "open",
        ["<CR>"] = "open",
        ["s"] = "none",
        ["S"] = "none",
      },
    },
  },
}
