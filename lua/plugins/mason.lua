return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = {
      run_on_start = false,
      ensure_installed = {
        "tree-sitter-cli",
        "fsautocomplete",
        "eslint_d",
      },
    },
  },
}
