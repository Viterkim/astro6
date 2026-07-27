return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = {
      run_on_start = false,
      ensure_installed = {
        -- Core
        "lua-language-server",
        "stylua",
        "tree-sitter-cli",

        -- F#
        "fsautocomplete",

        -- Rust
        "codelldb",

        -- TypeScript / JavaScript
        "vtsls",
        "js-debug-adapter",
        "eslint-lsp",
        "eslint_d",
      },
    },
  },
}
