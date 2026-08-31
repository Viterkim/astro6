---@type LazySpec
return {
  "AstroNvim/astroui",
  ---@type AstroUIOpts
  opts = {
    colorscheme = "tokyonight-storm",
    highlights = {
      init = {
        -- Rust analyzer marks unreachable/inactive code as unnecessary. Tokyonight makes that impossible to read, fixerino:
        DiagnosticUnnecessary = { fg = "#9aa5ce", italic = false },
        DiagnosticDeprecated = { fg = "#a9b1d6", italic = false, strikethrough = false },
        DiagnosticVirtualTextUnnecessary = { fg = "#9aa5ce", italic = false },
        DiagnosticVirtualTextDeprecated = { fg = "#a9b1d6", italic = false, strikethrough = false },
        ["@lsp.mod.unnecessary"] = { fg = "#9aa5ce", italic = false },
        ["@lsp.mod.deprecated"] = { fg = "#a9b1d6", italic = false, strikethrough = false },
        CodeDiffComment = { fg = "#a9b1d6", italic = true },
      },
      astrodark = {},
    },
    icons = {
      LSPLoading1 = "⠋",
      LSPLoading2 = "⠙",
      LSPLoading3 = "⠹",
      LSPLoading4 = "⠸",
      LSPLoading5 = "⠼",
      LSPLoading6 = "⠴",
      LSPLoading7 = "⠦",
      LSPLoading8 = "⠧",
      LSPLoading9 = "⠇",
      LSPLoading10 = "⠏",
    },
    status = {
      components = {
        -- Override Astro default.
        file_info = {
          filename = {
            condition = function(...) return require("astroui.status.condition").is_file(...) end,
            fname = function(bufnr)
              local filename = vim.api.nvim_buf_get_name(bufnr)
              if filename == "" then return "" end

              filename = vim.fs.normalize(filename)
              local cwd = vim.fs.normalize(vim.uv.cwd() or vim.fn.getcwd())
              local relative = vim.fs.relpath(cwd, filename)
              if relative and relative ~= ".." and not vim.startswith(relative, "../") then
                return vim.fs.basename(cwd) .. "/" .. relative
              end

              local root = vim.fs.root(filename, ".git")
              relative = root and vim.fs.relpath(root, filename)
              if relative then return vim.fs.basename(root) .. "/" .. relative end

              return vim.fn.fnamemodify(filename, ":~")
            end,
            modify = "",
            padding = { left = 1, right = 1 },
          },
        },
        -- Override Astro default.
        tabline_file_info = {
          unique_path = false,
          filename = {
            fname = function(bufnr)
              local filename = vim.api.nvim_buf_get_name(bufnr)
              if filename == "" then return "" end

              filename = vim.fs.normalize(filename)
              local parent = vim.fs.basename(vim.fs.dirname(filename))
              local basename = vim.fs.basename(filename)
              return parent ~= "" and parent .. "/" .. basename or basename
            end,
            modify = "",
          },
        },
      },
    },
  },
}
