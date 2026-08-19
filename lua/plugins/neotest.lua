local prefix = "<Leader>t"

local ignored_discovery_dirs = {
  [".git"] = true,
  ["node_modules"] = true,
  target = true,
  output = true,
  ["cargo-git"] = true,
}

-- Resolve these once during config setup. Neotest calls filter_dir from a
-- libuv filesystem callback, where vim.fn functions raise E5560.
local user_home = assert(vim.uv.os_homedir())
local cargo_home = vim.fs.normalize(vim.env.CARGO_HOME or vim.fs.joinpath(user_home, ".cargo"))
local rustup_home = vim.fs.normalize(vim.env.RUSTUP_HOME or vim.fs.joinpath(user_home, ".rustup"))

local function dependency_tree(root)
  root = vim.fs.normalize(root or "")
  return root == cargo_home
    or vim.startswith(root, cargo_home .. "/")
    or root == rustup_home
    or vim.startswith(root, rustup_home .. "/")
end

local function configure_neotest(_, opts)
  opts.discovery = opts.discovery or {}
  local previous_filter = opts.discovery.filter_dir
  opts.discovery.filter_dir = function(name, relative, root)
    if ignored_discovery_dirs[name] or dependency_tree(root) then return false end
    return not previous_filter or previous_filter(name, relative, root)
  end

  for _, adapter in ipairs(opts.adapters or {}) do
    if
      type(adapter) == "table"
      and adapter.name == "rustaceanvim"
      and type(adapter.discover_positions) == "function"
      and not adapter._viter_empty_positions_patch
    then
      local discover_positions = adapter.discover_positions

      -- TEMP MONKEY PATCH: rustaceanvim's Neotest adapter currently calls
      -- neotest's parse_tree({}) when rust-analyzer returns no runnables. The
      -- current Neotest asserts on that empty list, producing one traceback per
      -- Rust file. Remove this wrapper when the adapter returns nil itself.
      adapter.discover_positions = function(path)
        local ok, positions = pcall(discover_positions, path)
        if ok then return positions end

        local message = tostring(positions)
        if message:find("neotest/lib/positions/init.lua", 1, true)
          and message:find("assertion failed", 1, true)
        then
          return nil
        end
        error(positions, 0)
      end
      adapter._viter_empty_positions_patch = true
    end
  end
end

---@return neotest
local function neotest()
  return require "neotest" --[[@as neotest]]
end

return {
  {
    "nvim-neotest/neotest",
    opts = configure_neotest,
  },
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
