---@type LazySpec
return {
  "AstroNvim/astrocore",
  opts = function(_, opts)
    ---@cast opts AstroCoreOpts
    opts.treesitter = opts.treesitter or {}
    opts.treesitter.highlight = true
    opts.treesitter.indent = true
    opts.treesitter.auto_install = false

    local seen = {}
    opts.treesitter.ensure_installed = vim.tbl_filter(function(parser)
      if seen[parser] then return false end
      seen[parser] = true
      return true
    end, opts.treesitter.ensure_installed or {})
  end,
}
