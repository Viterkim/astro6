local eslint_filetypes = {
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
}

return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },

  opts = {
    format_on_save = function(bufnr)
      local filetype = vim.bo[bufnr].filetype

      return {
        timeout_ms = 5000,
        -- TS/JS must only use ESLint. Never silently fall back to
        -- vtsls or another LSP formatter.
        lsp_format = eslint_filetypes[filetype] and "never" or "fallback",
      }
    end,

    formatters_by_ft = {
      rust = { "rustfmt" },
      lua = { "stylua" },

      javascript = { "eslint_d" },
      javascriptreact = { "eslint_d" },
      typescript = { "eslint_d" },
      typescriptreact = { "eslint_d" },
    },
  },
}

