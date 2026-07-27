---@type LazySpec
return {
  "AstroNvim/astrolsp",

  ---@type AstroLSPOpts
  opts = {
    config = {
      rust_analyzer = {
        settings = {
          ["rust-analyzer"] = {
            -- Keep checks automatic, but use the faster command recommended by
            -- the AstroCommunity Rust pack for large projects.
            check = { command = "check", extraArgs = {} },
          },
        },
      },
    },

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
