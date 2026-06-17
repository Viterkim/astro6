-- Maybe not needed
return {
  "folke/which-key.nvim",

  opts = function(_, opts)
    -- Only create automatic WhichKey triggers for the keys we actually
    -- use as menus. This avoids special/plugin buffers confusing its
    -- automatic trigger tracking.
    opts.triggers = {
      { "<Leader>", mode = { "n", "v" } },
      { "<LocalLeader>", mode = { "n", "v" } },
    }

    return opts
  end,
}
