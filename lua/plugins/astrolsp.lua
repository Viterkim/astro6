---@type LazySpec
return {
  "AstroNvim/astrolsp",

  ---@type AstroLSPOpts
  opts = {
    handlers = {
      stylua = false,
    },

    config = {
      rust_analyzer = {
        settings = {
          ["rust-analyzer"] = {
            -- Keep Clippy package-scoped so large workspaces stay usable.
            checkOnSave = true,
            check = {
              command = "clippy",
              extraArgs = { "--no-deps" },
              workspace = false,
              allTargets = false,
            },
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
      disabled = true,
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
