---@type LazySpec
return {
  "esmuellert/codediff.nvim",
  opts = {
    diff = {
      cycle_hunks_across_files = true,
      cycle_next_hunk = false,
      cycle_next_file = true,
      jump_to_first_change = true,
    },

    keymaps = {
      view = {
        next_hunk = "e",
        prev_hunk = "n",
        toggle_explorer = "b",
        focus_explorer = "f",
      },
      explorer = {
        hover = false,
      },
    },
  },
}
