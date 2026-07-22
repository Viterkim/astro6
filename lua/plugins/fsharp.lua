return {
  {
    "AstroNvim/astrolsp",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      table.insert(opts.servers, "fsautocomplete")

      opts.config = opts.config or {}
      opts.config.fsautocomplete = vim.tbl_deep_extend("force", opts.config.fsautocomplete or {}, {
        cmd = { "fsautocomplete", "--adaptive-lsp-server-enabled" },
        init_options = { AutomaticWorkspaceInit = true },
        settings = {
          FSharp = {
            UnusedDeclarationsAnalyzerExclusions = { ".*Win32\\.fs$" },
          },
        },
      })

      return opts
    end,
  },

  {
    "AstroNvim/astrocore",
    opts = function(_, opts)
      vim.filetype.add {
        extension = {
          fs = "fsharp",
          fsi = "fsharp",
          fsx = "fsharp",
        },
      }

      opts.treesitter.ensure_installed = opts.treesitter.ensure_installed or {}
      table.insert(opts.treesitter.ensure_installed, "fsharp")
      return opts
    end,
  },
}
