return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    -- Saving code shouldn't rescan the whole tree.
    enable_refresh_on_write = false,

    event_handlers = {
      {
        event = "neo_tree_buffer_enter",
        handler = function() require("neo-tree.sources.manager").refresh "filesystem" end,
      },
    },

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
          "target",
          "node_modules",
        },
      },

      hijack_netrw_behavior = "open_current",
      -- Avoid recursive filesystem watcher traffic in large Rust workspaces.
      -- Neo-tree still refreshes when opened and after its own file operations.
      use_libuv_file_watcher = false,
      use_popups_for_input = true,
    },

    window = {
      width = 25,

      mappings = {
        -- Do not let Neo-tree take over the global leader key.
        ["<space>"] = false,

        ["n"] = function() vim.cmd "normal! k" end,
        ["e"] = function() vim.cmd "normal! j" end,
        ["i"] = "open",
        ["ø"] = "show_file_details",

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
