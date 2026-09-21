local image_globs = require("utils.image_globs").patterns()

local picker_excludes = vim.list_extend(vim.deepcopy(image_globs), {
  ".git",
  "node_modules",
  "garage",
})

local grep_excludes = vim.list_extend(vim.deepcopy(picker_excludes), {
  "tests",
})

local rust_test_ranges = {}

local function get_rust_test_ranges(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return {} end

  local version = table.concat({ stat.size, stat.mtime.sec, stat.mtime.nsec }, ":")
  local cached = rust_test_ranges[path]
  if cached and cached.version == version then return cached.ranges end

  local file = io.open(path, "rb")
  if not file then return {} end
  local source = file:read "*a"
  file:close()

  local ok, trees = pcall(function() return vim.treesitter.get_string_parser(source, "rust"):parse() end)
  if not ok or not trees[1] then return {} end
  local ranges = {}

  local function visit(parent)
    local cfg_test = false
    for index = 0, parent:named_child_count() - 1 do
      local child = parent:named_child(index)
      local kind = child:type()
      if kind == "attribute_item" then
        local attribute = vim.treesitter.get_node_text(child, source):gsub("%s", "")
        cfg_test = cfg_test or attribute == "#[cfg(test)]"
      elseif kind ~= "line_comment" and kind ~= "block_comment" then
        if cfg_test then
          local start_row, _, end_row = child:range()
          ranges[#ranges + 1] = { start_row, end_row }
        else
          visit(child)
        end
        cfg_test = false
      end
    end
  end

  visit(trees[1]:root())
  rust_test_ranges[path] = { version = version, ranges = ranges }
  return ranges
end

local function hide_rust_test_matches(item)
  if not item.file or not item.pos or not item.file:match "%.rs$" then return end
  local path = require("snacks.picker.util").path(item)
  if not path then return end

  local row = item.pos[1] - 1
  for _, range in ipairs(get_rust_test_ranges(path)) do
    if row >= range[1] and row <= range[2] then return false end
  end
end

local function git_picker_layout(list_height)
  return {
    layout = {
      box = "vertical",
      border = "rounded",
      title = "{source}",
      title_pos = "center",
      width = 0.98,
      height = 0.95,
      { win = "preview", title = "{preview}", border = "bottom" },
      { win = "input", height = 1, border = "bottom", title = "{title} {live} {flags}" },
      { win = "list", height = list_height, border = "none" },
    },
  }
end

local function open_neotree_with_project_src()
  local cwd = vim.fn.getcwd()
  local src = cwd .. "/src"
  local stat = vim.uv.fs_stat(src)

  if stat and stat.type == "directory" then
    local manager = require "neo-tree.sources.manager"
    local utils = require "neo-tree.utils"
    local state = manager.get_state "filesystem"
    cwd = utils.normalize_path(cwd)
    src = utils.normalize_path(utils.path_join(cwd, "src"))
    state.force_open_folders = { cwd, src }
  end

  vim.cmd "Neotree focus filesystem left"
end

return {
  "folke/snacks.nvim",
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "SnacksDashboardOpened",
      once = true,
      callback = function()
        if vim.fn.argc() == 0 then
          open_neotree_with_project_src()
          vim.schedule(function()
            vim.o.showtabline = 2
            vim.cmd.redrawtabline()
          end)
        end
      end,
    })
  end,
  opts = {
    input = { enabled = false },

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

      layouts = {
        git_compare = git_picker_layout(8),
      },

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
          exclude = grep_excludes,
          transform = hide_rust_test_matches,
        },
        grep_word = {
          hidden = true,
          exclude = grep_excludes,
          transform = hide_rust_test_matches,
        },

        git_status = { layout = git_picker_layout(5) },
        git_log = { layout = git_picker_layout(5) },
        git_branches = { layout = git_picker_layout(5) },
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
