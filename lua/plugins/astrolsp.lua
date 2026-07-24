---@type LazySpec
return {
  "AstroNvim/astrolsp",

  ---@type AstroLSPOpts
  opts = {
    features = {
      codelens = false,
      inlay_hints = false,
      semantic_tokens = true,
    },

    formatting = {
      format_on_save = {
        enabled = true,

        -- Conform owns these filetypes (using rustfmt or eslint_d).
        ignore_filetypes = {
          "rust",
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
        },
      },

      -- Never use these LSP clients as document formatters.
      disabled = {
        "tsserver",
        "ts_ls",
        "vtsls",
        "eslint",
      },

      timeout_ms = 5000,
    },

    mappings = {
      n = {
        gD = {
          function() vim.lsp.buf.declaration() end,
          desc = "Declaration of current symbol",
          cond = "textDocument/declaration",
        },
      },
    },
  },
}
