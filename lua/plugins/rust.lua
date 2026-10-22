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
local pending_dependency_starts = {}
local workspace_starts = {}

local rust_target_scopes = {
  package = { workspace = false, allTargets = false, extraArgs = {} },
  package_tests = { workspace = false, allTargets = true, extraArgs = {} },
  workspace = { workspace = true, allTargets = false, extraArgs = {} },
  workspace_tests = { workspace = true, allTargets = true, extraArgs = {} },
  tests = { workspace = false, allTargets = false, extraArgs = { "--tests" } },
}

local function configure_analyzer(client, changes)
  local settings = vim.deepcopy(client.settings or client.config.settings or {})
  settings["rust-analyzer"] = vim.tbl_deep_extend("force", settings["rust-analyzer"] or {}, changes)
  client.settings = settings
  client:notify("workspace/didChangeConfiguration", { settings = settings })
end

local function set_rust_target(bufnr, scope)
  local aliases = { default = "workspace_tests", normal = "package", test = "tests", all = "workspace_tests" }
  scope = aliases[scope] or scope

  local check = rust_target_scopes[scope]
  if not check then
    vim.notify("RustTarget: unknown target " .. scope, vim.log.levels.ERROR)
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

  for _, client in ipairs(clients) do
    configure_analyzer(client, { check = vim.deepcopy(check) })
  end

  vim.notify("Rust target: " .. scope)
end

local function pick_rust_platform(bufnr)
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "rust-analyzer" })[1]
  if not client then
    vim.notify("RustPlatform: rust-analyzer is not attached", vim.log.levels.WARN)
    return
  end

  local cwd = toolchain_cwd(vim.api.nvim_buf_get_name(bufnr))
  vim.system({ "rustup", "target", "list", "--installed" }, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Could not list Rust platforms:\n" .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
        return
      end
      if client:is_stopped() then return end

      local current = vim.tbl_get(client.settings or {}, "rust-analyzer", "cargo", "target")
      local choices = { { label = "Native / Cargo default", target = vim.NIL } }
      for target in (result.stdout or ""):gmatch "[^\r\n]+" do
        table.insert(choices, { label = target, target = target })
      end

      vim.ui.select(choices, {
        kind = "rust_platform",
        prompt = "Rust platform to browse",
        format_item = function(choice)
          local selected = (current == nil and choice.target == vim.NIL) or current == choice.target
          return (selected and "● " or "  ") .. choice.label
        end,
      }, function(choice)
        if not choice or client:is_stopped() then return end

        configure_analyzer(client, { cargo = { target = choice.target } })
        vim.notify("Rust platform: " .. choice.label .. ". Reloading workspace…")
      end)
    end)
  end)
end

local function pick_rust_target(bufnr)
  local client = vim
    .iter(vim.lsp.get_clients { bufnr = bufnr })
    :find(function(item) return item.name == "rust-analyzer" end)
  if not client then
    vim.notify("RustTarget: rust-analyzer is not attached to this buffer", vim.log.levels.WARN)
    return
  end

  local settings = (client.settings or {})["rust-analyzer"] or {}
  local current = settings.check
  local features = vim.tbl_get(settings, "cargo", "features")

  local choices = {
    { label = "Everything", scope = "workspace_tests" },
    { label = "Everything (no tests)", scope = "workspace" },
    { label = "This crate", scope = "package_tests" },
    { label = "This crate (no tests)", scope = "package" },
    { label = "Tests only (this crate)", scope = "tests" },
    { label = "Cargo features: default", features = {} },
    { label = "Cargo features: all", features = "all" },
  }

  vim.ui.select(choices, {
    kind = "rust_target",
    prompt = "Rust checks and browsing",
    format_item = function(choice)
      if choice.features then
        local selected = vim.deep_equal(features or {}, choice.features)
        return (selected and "● " or "  ") .. choice.label
      end

      local target = rust_target_scopes[choice.scope]
      local selected = current
        and current.workspace == target.workspace
        and current.allTargets == target.allTargets
        and vim.deep_equal(current.extraArgs or {}, target.extraArgs)

      return (selected and "● " or "  ") .. choice.label
    end,
  }, function(choice)
    if not choice or client:is_stopped() then return end

    if choice.features then
      configure_analyzer(client, { cargo = { features = choice.features } })
      vim.notify(choice.label .. ". Reloading workspace…")
    else
      set_rust_target(bufnr, choice.scope)
    end
  end)
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

local function start_workspace_from_cwd()
  local cwd = vim.fn.getcwd()
  local manifest = vim.fs.find("Cargo.toml", { path = cwd, upward = true })[1]
  if not manifest then return end

  local directory = vim.fs.dirname(manifest)
  if workspace_starts[directory] then return end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].filetype == "rust"
      and vim.startswith(name, directory .. "/")
    then
      return
    end
  end

  workspace_starts[directory] = true
  vim.system({ "cargo", "metadata", "--no-deps", "--format-version", "1", "--offline" }, {
    cwd = directory,
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        workspace_starts[directory] = nil
        vim.notify(
          "Could not start rust-analyzer for " .. directory .. ":\n" .. vim.trim(result.stderr or ""),
          vim.log.levels.WARN
        )
        return
      end

      local ok, metadata = pcall(vim.json.decode, result.stdout)
      if not ok then
        workspace_starts[directory] = nil
        vim.notify("Could not read Cargo metadata for " .. directory, vim.log.levels.WARN)
        return
      end

      local root = metadata.workspace_root
      if root ~= directory and workspace_starts[root] then return end
      workspace_starts[root] = true

      for _, client in ipairs(vim.lsp.get_clients { name = "rust-analyzer" }) do
        if client.root_dir == root then return end
      end

      local members = {}
      for _, id in ipairs(metadata.workspace_members or {}) do
        members[id] = true
      end

      for _, package in ipairs(metadata.packages or {}) do
        if members[package.id] then
          for _, target in ipairs(package.targets or {}) do
            local source = target.src_path
            if source and vim.uv.fs_stat(source) and source:match "%.rs$" then
              local bufnr = vim.fn.bufadd(source)
              if not vim.api.nvim_buf_is_loaded(bufnr) and not vim.bo[bufnr].buflisted then
                local swapfile = vim.bo[bufnr].swapfile
                vim.bo[bufnr].swapfile = false
                vim.api.nvim_create_autocmd("BufWinEnter", {
                  buffer = bufnr,
                  callback = function()
                    if not vim.bo[bufnr].buflisted then return end

                    vim.bo[bufnr].swapfile = swapfile
                    return true
                  end,
                })
              end

              vim.fn.bufload(bufnr)
              if vim.bo[bufnr].filetype == "" then
                vim.api.nvim_buf_call(bufnr, function() vim.bo.filetype = "rust" end)
              else
                start_buffer(bufnr)
              end
              return
            end
          end
        end
      end

      workspace_starts[directory] = nil
      workspace_starts[root] = nil
      vim.notify("Could not find a Rust source file in " .. directory, vim.log.levels.WARN)
    end)
  end)
end

local function rust_target_buffer()
  local current = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients { bufnr = current, name = "rust-analyzer" } > 0 then return current end

  local name = vim.api.nvim_buf_get_name(current)
  local path = vim.bo[current].buftype == "" and name ~= "" and name or vim.fn.getcwd()
  for _, client in ipairs(vim.lsp.get_clients { name = "rust-analyzer" }) do
    local root = client.root_dir
    if root and (path == root or vim.startswith(path, root .. "/")) then
      for bufnr in pairs(client.attached_buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then return bufnr end
      end
    end
  end

  return current
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

local function start_dependency_buffer(bufnr)
  if has_initialized_analyzer() or not has_project_rust_buffer() then
    start_buffer(bufnr)
    return
  end

  pending_dependency_starts[bufnr] = true
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
    start_dependency_buffer(bufnr)
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
  init = function()
    local group = vim.api.nvim_create_augroup("rust_workspace_start", { clear = true })
    vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
      group = group,
      callback = start_workspace_from_cwd,
    })
    vim.api.nvim_create_autocmd("LspAttach", {
      group = group,
      callback = function(event)
        local client = vim.lsp.get_client_by_id(event.data.client_id)
        if not client or client.name ~= "rust-analyzer" then return end

        local pending = pending_dependency_starts
        pending_dependency_starts = {}
        for bufnr in pairs(pending) do
          start_buffer(bufnr)
        end
      end,
    })

    vim.api.nvim_create_user_command("RustTarget", function(args)
      local bufnr = rust_target_buffer()
      if args.args == "" then
        pick_rust_target(bufnr)
      else
        set_rust_target(bufnr, args.args)
      end
    end, {
      nargs = "?",
      desc = "Choose Rust check scope and features",
      complete = function(lead)
        return vim.tbl_filter(
          function(scope) return vim.startswith(scope, lead) end,
          { "workspace_tests", "workspace", "package_tests", "package", "tests" }
        )
      end,
    })
    vim.api.nvim_create_user_command("RustPlatform", function() pick_rust_platform(rust_target_buffer()) end, {
      desc = "Choose Rust platform for browsing",
    })
  end,
  opts = function(_, opts)
    opts.server = opts.server or {}
    opts.tools = opts.tools or {}
    -- Nextest writes no JUnit file when compilation fails, and the adapter loses the Cargo error.
    opts.tools.enable_nextest = false
    opts.tools.code_actions = opts.tools.code_actions or {}
    opts.tools.code_actions.ui_select_fallback = true
    opts.dap = opts.dap or {}
    opts.dap.autoload_configurations = false

    local command_cwd

    -- TEMP MONKEY PATCH: current rust-analyzer releases log a warning for
    -- every missing optional config path they probe. Preserve real errors and
    -- panics without filling Neovim's LSP log with those expected misses.
    opts.server.cmd_env = vim.tbl_extend("force", opts.server.cmd_env or {}, { RA_LOG = "error" })

    local default_on_attach = opts.server.on_attach
    opts.server.on_attach = function(client, bufnr)
      if default_on_attach then default_on_attach(client, bufnr) end

      client.server_capabilities.semanticTokensProvider = nil
    end

    opts.server.auto_attach = function(bufnr)
      if
        vim.bo[bufnr].buftype ~= ""
        or not require("rustaceanvim.os").is_valid_file_path(vim.api.nvim_buf_get_name(bufnr))
      then
        return false
      end
      if not ensure_rust_analyzer(bufnr) then return false end

      if
        is_dependency_source(vim.api.nvim_buf_get_name(bufnr))
        and has_project_rust_buffer()
        and not has_initialized_analyzer()
      then
        start_dependency_buffer(bufnr)
        return false
      end

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

      return { "rust-analyzer" }
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
