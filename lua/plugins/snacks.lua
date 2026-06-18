local image_globs = require("utils.image_globs").patterns()
local picker_excludes = vim.list_extend(vim.deepcopy(image_globs), {
  ".git",
  "node_modules",
  "garage",
})

local git_picker_layout = {
  layout = {
    box = "vertical",
    border = "rounded",
    title = "{source}",
    title_pos = "center",
    width = 0.98,
    height = 0.95,
    { win = "preview", title = "{preview}", border = "bottom" },
    { win = "input", height = 1, border = "bottom", title = "{title} {live} {flags}" },
    { win = "list", height = 5, border = "none" },
  },
}

return {
  "folke/snacks.nvim",
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "SnacksDashboardOpened",
      once = true,
      callback = function()
        if vim.fn.argc() == 0 then vim.cmd "Neotree show filesystem left" end
      end,
    })
  end,
  opts = {
    image = {
      enabled = false,
      formats = {},
      doc = {
        enabled = false,
        inline = false,
        float = false,
      },
    },

    dashboard = {
      preset = {
        header = table.concat({
          "                @@#@@@#@                ",
          "               @##@#@@@#@@              ",
          "             @@##@##@@@@##@             ",
          "            @@@@@@@@@@@@@@@@            ",
          "          @(((((((((((((((((((@         ",
          "        @((((((@  @(((@  @((((((@       ",
          "      @((((((@@ ** @(@ ** @(((((((@     ",
          "     @@((((((@@    @(@    @(((((((@@    ",
          "   @%%@(((((((((@@((@((@@(((((((((@%%@  ",
          " @%%%%@((((((((((@*****@((((((((((@%%%%@",
          "  @@@@@((((((((@**********@(((((((@@@@@ ",
          "        (&((((((&#*******#&((((((&(     ",
          "          @((((((((@***@((((((((@       ",
          "            @((((((((@(((((((@@         ",
          "               @@(((((((@@              ",
        }, "\n"),
      },
    },

    picker = {
      -- LSP auto fixes should not show up with the snacks picker by default
      ui_select = false,

      layout = {
        width = 0.95,
        height = 0.95,
        layout = {
          box = "vertical",
          border = "rounded",
          title = "{source}",
          title_pos = "center",
          { win = "preview", title = "{preview}", height = 0.4, border = "bottom" },
          { win = "input", height = 1, border = "bottom", title = "{title} {live} {flags}" },
          { win = "list", border = "none" },
        },
      },

      sources = {
        files = {
          hidden = true,
          exclude = picker_excludes,
        },
        grep = {
          hidden = true,
          exclude = picker_excludes,
        },
        grep_word = {
          hidden = true,
          exclude = picker_excludes,
        },

        git_status = { layout = vim.deepcopy(git_picker_layout) },
        git_log = { layout = vim.deepcopy(git_picker_layout) },
        git_branches = { layout = vim.deepcopy(git_picker_layout) },
      },

      win = {
        input = {
          keys = {
            ["<Esc>"] = { "close", mode = { "n", "i" } },
          },
        },
      },
    },
  },
}
