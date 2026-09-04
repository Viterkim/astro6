---@type LazySpec
return {
  "AstroNvim/astrocore",
  opts = function(_, opts)
    ---@cast opts AstroCoreOpts
    opts.treesitter = opts.treesitter or {}
    -- Override Astro default: install parsers explicitly.
    opts.treesitter.auto_install = false

    local ensure_installed = opts.treesitter.ensure_installed
    if type(ensure_installed) == "table" then
      local astrocore = require "astrocore"
      astrocore.list_insert_unique(ensure_installed, { "regex" })
      opts.treesitter.ensure_installed = astrocore.unique_list(ensure_installed)
    end
  end,
}
