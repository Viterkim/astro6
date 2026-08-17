local function autoformat_enabled(bufnr) return vim.F.if_nil(vim.b[bufnr].autoformat, vim.g.autoformat, true) end

local async_filetypes = {
  fsharp = true,
  rust = true,
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
}

return {
  "stevearc/conform.nvim",

  opts = {
    default_format_opts = {
      lsp_format = "never",
      -- 5 sec because work eslint/prettier is slow on cold start
      timeout_ms = 5000,
    },

    formatters = {
      -- work does prettier through eslint
      eslint_d = {
        env = { ESLINT_D_MISS = "fail" },
      },

      fantomas = {
        command = "dotnet",
        args = { "fantomas", "$FILENAME" },
        stdin = false,
      },
    },

    format_on_save = function(bufnr)
      if not autoformat_enabled(bufnr) or async_filetypes[vim.bo[bufnr].filetype] then return end
      return { lsp_format = "never" }
    end,

    format_after_save = function(bufnr)
      if autoformat_enabled(bufnr) and async_filetypes[vim.bo[bufnr].filetype] then return { lsp_format = "never" } end
    end,

    formatters_by_ft = {
      rust = { "rustfmt" },
      lua = { "stylua" },
      fsharp = { "fantomas" },

      javascript = { "eslint_d" },
      javascriptreact = { "eslint_d" },
      typescript = { "eslint_d" },
      typescriptreact = { "eslint_d" },
    },
  },
}
