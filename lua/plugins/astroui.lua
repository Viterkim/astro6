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
  },
}
