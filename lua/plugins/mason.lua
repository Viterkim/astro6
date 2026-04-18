return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = {
      run_on_start = false,
      ensure_installed = {
        -- core
        "lua-language-server",
        "stylua",
        "tree-sitter-cli",

        -- rust
        "rust-analyzer",
        "codelldb",

        -- typescript / javascript
        "vtsls",
        "js-debug-adapter",
        "eslint_d",
      },
    },
  },
}
