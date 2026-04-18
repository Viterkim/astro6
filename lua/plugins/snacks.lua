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
  opts = {
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
