return {
  "nvim-neotest/neotest-jest",
  optional = true,
  opts = {
    jestCommand = "npm test --",
    jestConfigFile = "custom.jest.config.ts",
    env = { CI = true },
    cwd = function() return vim.fn.getcwd() end,
  },
}
