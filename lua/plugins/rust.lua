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

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
      if vim.bo[bufnr].filetype == "rust" and name ~= "" and not is_dependency_source(name) then
        return toolchain_cwd(name)
      end
    end
  end

  local directory = vim.fs.dirname(filename)
  local toolchain = vim.fs.find({ "rust-toolchain.toml", "rust-toolchain" }, {
    path = directory,
    upward = true,
  })[1]
  if toolchain then return vim.fs.dirname(toolchain) end

  local manifest = vim.fs.find("Cargo.toml", { path = directory, upward = true })[1]
  return manifest and vim.fs.dirname(manifest) or directory
end

local analyzer_state = {}

local rust_target_scopes = {
  default = { allTargets = false, extraArgs = { "--no-deps" } },
  test = { allTargets = false, extraArgs = { "--no-deps", "--tests" } },
  all = { allTargets = true, extraArgs = { "--no-deps" } },
}

local function set_rust_target(bufnr, scope)
  scope = scope == "" and "default" or scope
  scope = scope == "normal" and "default" or scope
  scope = scope == "tests" and "test" or scope

  local check = rust_target_scopes[scope]
  if not check then
    vim.notify("RustTarget: use default, test, or all", vim.log.levels.ERROR)
    return
  end

  local clients = vim.tbl_filter(
    function(client) return client.name == "rust-analyzer" end,
    vim.lsp.get_clients { bufnr = bufnr }
  )
  if #clients == 0 then
    vim.notify("RustTarget: rust-analyzer is not attached", vim.log.levels.WARN)
    return
  end

  require("rustaceanvim.lsp").set_config(bufnr, { check = vim.deepcopy(check) })
  vim.notify("Rust target: " .. scope)
end

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

local function start_waiting_buffers(buffers)
  for bufnr in pairs(buffers) do
    start_buffer(bufnr)
  end
end

local function finish_analyzer_check(key, success, installed, error_message, executable)
  vim.schedule(function()
    local state = analyzer_state[key]
    if not state then return end

    local buffers = state.buffers
    state.buffers = {}
    state.status = success and "ready" or nil
    state.executable = success and executable or nil

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
      finish_analyzer_check(key, true, false, nil, vim.trim(which.stdout or ""))
      return
    end

    vim.schedule(function()
      local current = analyzer_state[key]
      if not current then return end
      current.status = "installing"
      vim.notify "Installing rust-analyzer for this project's Rust toolchain…"
      vim.system({ "rustup", "component", "add", "rust-analyzer" }, { cwd = cwd, text = true }, function(install)
        if install.code ~= 0 then
          finish_analyzer_check(key, false, true, install.stderr)
          return
        end

        vim.system(
          { "rustup", "which", "rust-analyzer" },
          { cwd = cwd, text = true },
          function(result)
            finish_analyzer_check(key, result.code == 0, true, result.stderr, vim.trim(result.stdout or ""))
          end
        )
      end)
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
    local command_cwd

    local default_on_attach = opts.server.on_attach
    opts.server.on_attach = function(client, bufnr)
      if default_on_attach then default_on_attach(client, bufnr) end

      client.server_capabilities.semanticTokensProvider = nil

      if not vim.api.nvim_buf_get_commands(bufnr, {})["RustTarget"] then
        vim.api.nvim_buf_create_user_command(
          bufnr,
          "RustTarget",
          function(args) set_rust_target(bufnr, args.args) end,
          {
            nargs = "?",
            desc = "Set Clippy target scope",
            complete = function(lead)
              return vim.tbl_filter(
                function(scope) return vim.startswith(scope, lead) end,
                { "default", "test", "all" }
              )
            end,
          }
        )
      end
    end

    local default_auto_attach = opts.server.auto_attach
    opts.server.auto_attach = function(bufnr)
      if default_auto_attach == false then return false end
      if type(default_auto_attach) == "function" and not default_auto_attach(bufnr) then return false end
      if not ensure_rust_analyzer(bufnr) then return false end

      return true
    end

    -- use the project's toolchain
    opts.server.cmd = function()
      local cwd = command_cwd
      command_cwd = nil
      if cwd then
        cwd = toolchain_cwd(vim.fs.joinpath(cwd, "Cargo.toml"))
      else
        local filename = vim.api.nvim_buf_get_name(0)
        local is_file = filename ~= "" and vim.bo.buftype == "" and not filename:match "^%w+://"
        cwd = is_file and toolchain_cwd(filename) or (vim.uv.cwd() or vim.fn.getcwd())
      end
      if not vim.uv.fs_stat(cwd) then cwd = vim.uv.cwd() or vim.fn.getcwd() end

      local state = analyzer_state[vim.fs.normalize(cwd)]
      if state and state.executable and state.executable ~= "" then return { state.executable } end

      local result = vim.system({ "rustup", "which", "rust-analyzer" }, { cwd = cwd, text = true }):wait()
      local executable = result.code == 0 and vim.trim(result.stdout or "") or ""
      return { executable ~= "" and executable or "rust-analyzer" }
    end

    opts.server.settings = function(project_root, default_settings)
      command_cwd = project_root
      vim.lsp.config("rust_analyzer", {})
      local astrolsp = vim.lsp.config.rust_analyzer or {}
      local astrocore = require "astrocore" --[[@as astrocore]]
      local defaults = astrocore.extend_tbl(default_settings or {}, astrolsp.settings or {})
      return require("rustaceanvim.config.server").load_rust_analyzer_settings(project_root, {
        settings_file_pattern = "rust-analyzer.json",
        default_settings = defaults,
      })
    end
  end,
}
