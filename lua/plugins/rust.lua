local function is_dependency_source(filename)
  local cargo_home = vim.env.CARGO_HOME or (vim.env.HOME .. "/.cargo")
  local rustup_home = vim.env.RUSTUP_HOME or (vim.env.HOME .. "/.rustup")
  local path = vim.fs.normalize(filename)

  return vim.startswith(path, vim.fs.normalize(cargo_home .. "/registry/src/"))
    or vim.startswith(path, vim.fs.normalize(cargo_home .. "/git/checkouts/"))
    or vim.startswith(path, vim.fs.normalize(rustup_home .. "/toolchains/"))
end

local function toolchain_cwd(filename)
  if is_dependency_source(filename) then
    local cwd = vim.uv.cwd() or vim.fn.getcwd()
    if vim.fs.find({ "rust-toolchain.toml", "rust-toolchain", "Cargo.toml" }, { path = cwd, upward = true })[1] then
      return cwd
    end
  end

  local directory = vim.fs.dirname(filename)
  local toolchain = vim.fs.find({ "rust-toolchain.toml", "rust-toolchain" }, {
    path = directory,
    upward = true,
  })[1]
  return toolchain and vim.fs.dirname(toolchain) or directory
end

local analyzer_state = {}
local pending_dependency_starts = {}

local function start_buffer(bufnr)
  if
    vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
    and vim.bo[bufnr].filetype == "rust"
    and vim.bo[bufnr].buftype == ""
  then
    require("rustaceanvim.lsp").start(bufnr)
  end
end

local function has_initialized_analyzer()
  return vim
    .iter(vim.lsp.get_clients { name = "rust-analyzer" })
    :any(function(client) return client.initialized and not client:is_stopped() end)
end

local function has_project_rust_buffer()
  return vim.iter(vim.api.nvim_list_bufs()):any(
    function(bufnr)
      return vim.api.nvim_buf_is_loaded(bufnr)
        and vim.bo[bufnr].filetype == "rust"
        and not is_dependency_source(vim.api.nvim_buf_get_name(bufnr))
    end
  )
end

local function defer_dependency_start(bufnr, attempt)
  if pending_dependency_starts[bufnr] and not attempt then return end
  pending_dependency_starts[bufnr] = true
  attempt = attempt or 1

  if has_initialized_analyzer() or not has_project_rust_buffer() or attempt >= 100 then
    pending_dependency_starts[bufnr] = nil
    start_buffer(bufnr)
  else
    vim.defer_fn(function() defer_dependency_start(bufnr, attempt + 1) end, 100)
  end
end

local function start_waiting_buffers(buffers)
  local project_buffers = {}
  local dependency_buffers = {}

  for bufnr in pairs(buffers) do
    local filename = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
    table.insert(is_dependency_source(filename) and dependency_buffers or project_buffers, bufnr)
  end

  for _, bufnr in ipairs(project_buffers) do
    start_buffer(bufnr)
  end

  for _, bufnr in ipairs(dependency_buffers) do
    defer_dependency_start(bufnr)
  end
end

local function finish_analyzer_check(key, success, installed, error_message)
  vim.schedule(function()
    local state = analyzer_state[key]
    if not state then return end

    local buffers = state.buffers
    state.buffers = {}
    state.status = success and "ready" or nil

    if not success then
      vim.notify(
        "Could not install rust-analyzer:\n" .. (error_message or "unknown rustup error"),
        vim.log.levels.ERROR
      )
      return
    end
    if installed then vim.notify "Installed rust-analyzer for this project's Rust toolchain" end

    start_waiting_buffers(buffers)
  end)
end

local function ensure_rust_analyzer(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" or vim.bo[bufnr].buftype ~= "" or vim.fn.executable "rustup" ~= 1 then return false end

  local cwd = toolchain_cwd(filename)
  local key = vim.fs.normalize(cwd)
  local state = analyzer_state[key]
  if state and state.status == "ready" then return true end

  state = state or { buffers = {} }
  analyzer_state[key] = state
  state.buffers[bufnr] = true
  if state.status == "checking" or state.status == "installing" then return false end

  state.status = "checking"
  vim.system({ "rustup", "which", "rust-analyzer" }, { cwd = cwd, text = true }, function(which)
    if which.code == 0 then
      finish_analyzer_check(key, true, false)
      return
    end

    vim.schedule(function()
      local current = analyzer_state[key]
      if not current then return end
      current.status = "installing"
      vim.notify "Installing rust-analyzer for this project's Rust toolchain…"
      vim.system(
        { "rustup", "component", "add", "rust-analyzer" },
        { cwd = cwd, text = true },
        function(install) finish_analyzer_check(key, install.code == 0, true, install.stderr) end
      )
    end)
  end)

  return false
end

---@type LazySpec
return {
  "mrcjkb/rustaceanvim",
  dependencies = { "AstroNvim/astrolsp" },
  opts = function(_, opts)
    opts.server = opts.server or {}

    local default_auto_attach = opts.server.auto_attach
    opts.server.auto_attach = function(bufnr)
      if default_auto_attach == false then return false end
      if type(default_auto_attach) == "function" and not default_auto_attach(bufnr) then return false end
      if not ensure_rust_analyzer(bufnr) then return false end

      if
        is_dependency_source(vim.api.nvim_buf_get_name(bufnr))
        and has_project_rust_buffer()
        and not has_initialized_analyzer()
      then
        defer_dependency_start(bufnr)
        return false
      end

      return true
    end

    -- Mason's bin directory can shadow rustup's proxy directory. Resolve the
    -- analyzer component itself so the project's pinned toolchain always wins.
    opts.server.cmd = function()
      -- This runs after asynchronous root detection, when the current buffer
      -- may already be a codediff:// preview rather than the Rust source.
      local cwd = vim.uv.cwd() or vim.fn.getcwd()
      local result = vim.system({ "rustup", "which", "rust-analyzer" }, { cwd = cwd, text = true }):wait()
      local executable = result.code == 0 and vim.trim(result.stdout or "") or ""
      return { executable ~= "" and executable or "rust-analyzer" }
    end

    -- AstroCommunity captures AstroLSP settings too early when a Rust file is
    -- restored during startup. Resolve them when rust-analyzer actually starts.
    opts.server.settings = function(project_root, default_settings)
      vim.lsp.config("rust_analyzer", {})
      local astrolsp = vim.lsp.config.rust_analyzer or {}
      local defaults = require("astrocore").extend_tbl(default_settings or {}, astrolsp.settings or {})
      return require("rustaceanvim.config.server").load_rust_analyzer_settings(project_root, {
        settings_file_pattern = "rust-analyzer.json",
        default_settings = defaults,
      })
    end
  end,
}
