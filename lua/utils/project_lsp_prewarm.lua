local M = {}

M.enabled = false

M.projects = {
  rust = {
    enabled = true,
    marker = "Cargo.toml",
    client = "rust-analyzer",
    filetype = "rust",
  },
  node = {
    enabled = true,
    marker = "package.json",
    client = "vtsls",
    filetype = "typescript",
  },
}

M.last_results = {}

local function result(name, data)
  data.name = name
  table.insert(M.last_results, data)
  return data
end

local function has_client(client_name, root)
  for _, client in ipairs(vim.lsp.get_clients { name = client_name }) do
    local client_root = vim.fs.normalize(client.config.root_dir or "")
    if client_root == root then return true end

    for _, folder in ipairs(client.workspace_folders or {}) do
      if vim.fs.normalize(folder.name) == root then return true end
    end
  end

  return false
end

local function normalize_start_path(path)
  if not path or path == "" then return end

  path = vim.fn.fnamemodify(path, ":p")
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "file" then return vim.fs.dirname(path) end
  return path
end

local function root_candidates()
  local candidates = { normalize_start_path(vim.uv.cwd() or vim.fn.getcwd()) }

  local current = normalize_start_path(vim.api.nvim_buf_get_name(0))
  if current then table.insert(candidates, current) end

  for _, arg in ipairs(vim.fn.argv()) do
    local path = normalize_start_path(arg)
    if path then table.insert(candidates, path) end
  end

  return candidates
end

local function find_roots(marker)
  local roots = {}
  for _, candidate in ipairs(root_candidates()) do
    local root = vim.fs.root(candidate, marker)
    if root then roots[vim.fs.normalize(root)] = true end
  end

  return vim.tbl_keys(roots)
end

local function make_real_file_buf(filename, filetype)
  local bufnr = vim.fn.bufadd(filename)
  vim.bo[bufnr].swapfile = false
  vim.fn.bufload(bufnr)
  if vim.bo[bufnr].filetype == "" then vim.bo[bufnr].filetype = filetype end
  return bufnr
end

local function first_path(paths)
  for _, path in ipairs(paths) do
    if vim.uv.fs_stat(path) then return path end
  end
end

local function first_glob(patterns)
  for _, pattern in ipairs(patterns) do
    local matches = vim.fn.glob(pattern, false, true)
    if matches[1] then return matches[1] end
  end
end

local function cargo_metadata_targets(root)
  if vim.fn.executable "cargo" ~= 1 then return {} end

  local result = vim
    .system({ "cargo", "metadata", "--no-deps", "--format-version", "1" }, {
      cwd = root,
      text = true,
    })
    :wait()

  if result.code ~= 0 then return {} end

  local ok, metadata = pcall(vim.json.decode, result.stdout)
  if not ok or type(metadata) ~= "table" or type(metadata.packages) ~= "table" then return {} end

  local paths = {}
  for _, package in ipairs(metadata.packages) do
    for _, target in ipairs(package.targets or {}) do
      if type(target.src_path) == "string" then table.insert(paths, target.src_path) end
    end
  end

  table.sort(paths)
  return paths
end

local function find_rust_entrypoint(root)
  return cargo_metadata_targets(root)[1]
    or first_path {
      root .. "/src/lib.rs",
      root .. "/src/main.rs",
    }
    or first_glob {
      root .. "/crates/*/src/lib.rs",
      root .. "/crates/*/src/main.rs",
      root .. "/*/src/lib.rs",
      root .. "/*/src/main.rs",
    }
end

local function rg_files(root, globs)
  if vim.fn.executable "rg" ~= 1 then return {} end

  local cmd = { "rg", "--files" }
  for _, glob in ipairs(globs) do
    table.insert(cmd, "-g")
    table.insert(cmd, glob)
  end

  local result = vim.system(cmd, { cwd = root, text = true }):wait()
  if result.code ~= 0 then return {} end

  local files = {}
  for file in result.stdout:gmatch "[^\r\n]+" do
    table.insert(files, root .. "/" .. file)
  end
  table.sort(files)
  return files
end

local function find_node_entrypoint(root)
  return rg_files(root, {
    "*.ts",
    "*.tsx",
    "*.js",
    "*.jsx",
    "!node_modules/**",
    "!dist/**",
    "!build/**",
    "!coverage/**",
  })[1] or first_path {
    root .. "/src/index.ts",
    root .. "/src/main.ts",
    root .. "/src/index.tsx",
    root .. "/src/main.tsx",
    root .. "/index.ts",
    root .. "/index.js",
  }
end

local function resolve_cmd(cmd)
  if type(cmd) ~= "table" or not cmd[1] then return nil end

  local executable = vim.fn.exepath(cmd[1])
  if executable == "" then
    local mason_executable = vim.fn.stdpath "data" .. "/mason/bin/" .. cmd[1]
    if vim.fn.executable(mason_executable) == 1 then executable = mason_executable end
  end
  if executable == "" then return nil end

  local resolved = vim.deepcopy(cmd)
  resolved[1] = executable
  return resolved
end

local function cleanup_legacy_prewarm_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    local old_rust = name:match "/src/main%.rs$"
    local old_typescript = name:match "/__nvim_lsp_prewarm%.ts$"

    if vim.bo[bufnr].buftype == "nofile" and not vim.bo[bufnr].buflisted and (old_rust or old_typescript) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

local function prewarm_rust(root, spec)
  if has_client(spec.client, root) then return result("rust", { root = root, status = "already-running" }) end

  require("lazy").load { plugins = { "rustaceanvim" } }

  local entrypoint = find_rust_entrypoint(root)
  if not entrypoint then return result("rust", { root = root, status = "no-entrypoint" }) end

  local bufnr = make_real_file_buf(entrypoint, spec.filetype)
  require("rustaceanvim.lsp").start(bufnr)
  return result("rust", { root = root, entrypoint = entrypoint, status = "started" })
end

local function prewarm_astrolsp(root, spec)
  if has_client(spec.client, root) then return result("node", { root = root, status = "already-running" }) end

  require("lazy").load { plugins = { "astrolsp", "nvim-vtsls" } }
  require("astrolsp").lsp_setup(spec.client)

  local config = vim.deepcopy(vim.lsp.config[spec.client] or {})
  config.cmd = resolve_cmd(config.cmd)
  if not config.cmd then return result("node", { root = root, status = "missing-command" }) end

  config.root_dir = root
  config.name = config.name or spec.client

  local entrypoint = find_node_entrypoint(root)
  if not entrypoint then return result("node", { root = root, status = "no-entrypoint" }) end

  local bufnr = make_real_file_buf(entrypoint, spec.filetype)
  local client_id = vim.lsp.start(config, {
    bufnr = bufnr,
    reuse_client = function(client, new_config)
      return client.name == new_config.name and vim.fs.normalize(client.config.root_dir or "") == root
    end,
  })
  if not client_id then return result("node", { root = root, status = "start-failed" }) end
  return result("node", { root = root, entrypoint = entrypoint, status = "started" })
end

function M.start()
  if not M.enabled then return end

  M.last_results = {}
  cleanup_legacy_prewarm_buffers()

  for name, spec in pairs(M.projects) do
    if spec.enabled then
      local roots = find_roots(spec.marker)
      if #roots == 0 then result(name, { marker = spec.marker, status = "no-root" }) end

      for _, root in ipairs(roots) do
        if name == "rust" then
          prewarm_rust(root, spec)
        else
          prewarm_astrolsp(root, spec)
        end
      end
    end
  end

  return M.last_results
end

function M.status()
  local lines = {}
  for _, item in ipairs(M.last_results) do
    local parts = { item.name .. ": " .. item.status }
    if item.root then table.insert(parts, "root=" .. item.root) end
    if item.marker then table.insert(parts, "marker=" .. item.marker) end
    if item.entrypoint then table.insert(parts, "entrypoint=" .. item.entrypoint) end
    table.insert(lines, table.concat(parts, " | "))
  end

  if #lines == 0 then table.insert(lines, "project LSP prewarm has not run yet") end
  vim.notify(table.concat(lines, "\n"))
end

return M
