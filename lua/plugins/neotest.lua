local prefix = "<Leader>t"
return {
  {
    "AstroNvim/astrocore",
    opts = {
      mappings = {
        n = {
          [prefix] = { desc = "󰗇 Tests" },
          [prefix .. "t"] = { function() require("neotest").run.run() end, desc = "Run test" },
          [prefix .. "d"] = {
            function() require("neotest").run.run { strategy = "dap", suite = false } end,
            desc = "Debug test",
          },
          [prefix .. "f"] = {
            function() require("neotest").run.run(vim.fn.expand "%") end,
            desc = "Run all tests in file",
          },
          [prefix .. "p"] = {
            function() require("neotest").run.run(vim.fn.getcwd()) end,
            desc = "Run all tests in project",
          },
          [prefix .. "<CR>"] = { function() require("neotest").summary.toggle() end, desc = "Test Summary" },
          [prefix .. "o"] = { function() require("neotest").output.open() end, desc = "Output hover" },
          [prefix .. "O"] = { function() require("neotest").output_panel.toggle() end, desc = "Output window" },
          ["]T"] = { function() require("neotest").jump.next() end, desc = "Next test" },
          ["[T"] = { function() require("neotest").jump.prev() end, desc = "Previous test" },
        },
      },
    },
  },
}
