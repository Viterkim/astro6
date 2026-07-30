local prefix = "<Leader>t"

---@return neotest
local function neotest()
  return require "neotest" --[[@as neotest]]
end

return {
  {
    "AstroNvim/astrocore",
    opts = {
      mappings = {
        n = {
          [prefix] = { desc = "󰗇 Tests" },
          [prefix .. "t"] = { function() neotest().run.run() end, desc = "Run test" },
          [prefix .. "d"] = {
            function() neotest().run.run { strategy = "dap", suite = false } end,
            desc = "Debug test",
          },
          [prefix .. "f"] = {
            function() neotest().run.run(vim.fn.expand "%") end,
            desc = "Run all tests in file",
          },
          [prefix .. "p"] = {
            function() neotest().run.run(vim.fn.getcwd()) end,
            desc = "Run all tests in project",
          },
          [prefix .. "<CR>"] = { function() neotest().summary.toggle() end, desc = "Test Summary" },
          [prefix .. "o"] = { function() neotest().output.open() end, desc = "Output hover" },
          [prefix .. "O"] = { function() neotest().output_panel.toggle() end, desc = "Output window" },
          ["]T"] = { function() neotest().jump.next() end, desc = "Next test" },
          ["[T"] = { function() neotest().jump.prev() end, desc = "Previous test" },
        },
      },
    },
  },
}
