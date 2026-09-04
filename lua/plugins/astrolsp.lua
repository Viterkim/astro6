---@type LazySpec
return {
  "AstroNvim/astrolsp",

  ---@type AstroLSPOpts
  opts = {
    handlers = {
      stylua = false,
      -- TEMP MONKEY PATCH: Taplo 0.10 rejects SchemaStore's current catalog
      -- before client settings can disable it. TOML formatting still uses the
      -- Taplo CLI; re-enable the LSP when upstream accepts the catalog again.
      taplo = false,
    },

    config = {
      lua_ls = {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            workspace = {
              checkThirdParty = false,
              library = {
                vim.fs.joinpath(vim.env.VIMRUNTIME, "lua"),
                vim.fs.joinpath(vim.fn.stdpath "data", "lazy", "lazy.nvim", "lua"),
              },
            },
          },
        },
      },
      rust_analyzer = {
        settings = {
          ["rust-analyzer"] = {
            -- Override rust-analyzer default: analyze files on demand instead
            -- of warming the entire workspace on every server start.
            cachePriming = { enable = false },
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
      -- Override Astro default.
      codelens = false,
    },

    formatting = {
      -- Override Astro default; Conform owns formatting.
      disabled = true,
    },

    mappings = {
      n = {
        -- Override Astro default.
        gD = {
          function() require("funcs").centered_lsp_picker "lsp_declarations" end,
          desc = "Declaration of current symbol",
          cond = "textDocument/declaration",
        },
        -- Override Astro default.
        gd = {
          function() require("funcs").centered_lsp_picker "lsp_definitions" end,
          desc = "Show the definition of current symbol",
          cond = "textDocument/definition",
        },
        -- Override Astro default.
        gy = {
          function() require("funcs").centered_lsp_picker "lsp_type_definitions" end,
          desc = "Definition of current type",
          cond = "textDocument/typeDefinition",
        },
        -- Additional alias; Astro does not define gI.
        gI = {
          function() require("funcs").centered_lsp_picker "lsp_implementations" end,
          desc = "Implementation of current symbol",
          cond = "textDocument/implementation",
        },
        -- Override Neovim default.
        gri = {
          function() require("funcs").centered_lsp_picker "lsp_implementations" end,
          desc = "Implementation of current symbol",
          cond = "textDocument/implementation",
        },
        -- Override Neovim default.
        grt = {
          function() require("funcs").centered_lsp_picker "lsp_type_definitions" end,
          desc = "Definition of current type",
          cond = "textDocument/typeDefinition",
        },
        -- Override Neovim default.
        grr = {
          function() require("funcs").centered_lsp_picker "lsp_references" end,
          desc = "Show references",
          cond = "textDocument/references",
        },
        -- Override Astro default.
        ["<Leader>lR"] = {
          function() require("funcs").centered_lsp_picker "lsp_references" end,
          desc = "Search references",
          cond = "textDocument/references",
        },
      },
    },
  },
}
