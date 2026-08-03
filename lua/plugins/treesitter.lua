---@type LazySpec
return {
  "AstroNvim/astrocore",
  opts = function(_, opts)
    ---@cast opts AstroCoreOpts
    opts.treesitter = opts.treesitter or {}
    opts.treesitter.highlight = true
    opts.treesitter.indent = true
    opts.treesitter.auto_install = false

    local ensure_installed = opts.treesitter.ensure_installed
    if type(ensure_installed) == "table" then
      local seen = {}
      opts.treesitter.ensure_installed = vim.tbl_filter(function(parser)
        if seen[parser] then return false end
        seen[parser] = true
        return true
      end, ensure_installed)
    end
  end,
}
