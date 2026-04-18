local M = {}

function M.sudoku_quit()
  local answer = vim.fn.input "Type sudoku to nuke all windows: "
  if answer ~= "sudoku" then
    vim.notify "Aborted"
    return
  end

  pcall(function() vim.cmd "Neotree close left" end)
  pcall(function() vim.cmd "Neotree close right" end)
  vim.cmd "qa!"
end

function M.exit_visual()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
end

local function get_visual_bounds()
  local mode = vim.fn.mode()
  local start_pos, end_pos

  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos "v"
    end_pos = vim.fn.getpos "."
  else
    mode = vim.fn.visualmode()
    start_pos = vim.fn.getpos "'<"
    end_pos = vim.fn.getpos "'>"
  end

  local srow, scol = start_pos[2], start_pos[3]
  local erow, ecol = end_pos[2], end_pos[3]

  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
  end

  return mode, srow, scol, erow, ecol
end

function M.get_visual_selection()
  local mode, srow, scol, erow, ecol = get_visual_bounds()
  if srow == 0 or erow == 0 then return "" end

  if mode == "V" then
    local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
    return table.concat(lines, "\n")
  end

  local lines = vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
  return table.concat(lines, "\n")
end

function M.get_visual_one_line()
  local text = M.get_visual_selection()
  text = text:gsub("\n", " ")
  text = text:gsub("%s+", " ")
  return vim.trim(text)
end

function M.save_session_and_quit()
  local resession = require "resession"
  local cwd = vim.uv.cwd() or vim.fn.getcwd()

  resession.save(cwd, {
    dir = "dirsession",
    notify = false,
    attach = false,
  })

  vim.cmd "qa"
end

local function is_real_file_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
    and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function save_all_real_files()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_real_file_buffer(bufnr) and vim.bo[bufnr].modified then
      pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd "silent update" end)
    end
  end
end

local function close_new_buffers(before, keep_buf)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if not before[bufnr] and is_real_file_buffer(bufnr) and bufnr ~= keep_buf and not vim.bo[bufnr].modified then
      pcall(vim.api.nvim_buf_delete, bufnr, {})
    end
  end
end

function M.rename_save_and_cleanup()
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local current_name = vim.fn.expand "<cword>"

  local client = nil
  for _, c in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
    if c.supports_method and c:supports_method "textDocument/rename" then
      client = c
      break
    end
  end

  if not client then
    vim.notify("No LSP rename available here", vim.log.levels.WARN)
    return
  end

  local before = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if is_real_file_buffer(b) then before[b] = true end
  end

  vim.ui.input({ prompt = "Rename to: ", default = current_name }, function(new_name)
    if not new_name or new_name == "" or new_name == current_name then return end

    local pos = vim.lsp.util.make_position_params(winid, client.offset_encoding)
    local params = {
      textDocument = pos.textDocument,
      position = pos.position,
      newName = new_name,
    }

    client:request("textDocument/rename", params, function(err, result)
      if err then
        vim.schedule(function() vim.notify(("Rename failed: %s"):format(err.message), vim.log.levels.ERROR) end)
        return
      end

      if not result then
        vim.schedule(function() vim.notify("Rename returned no changes", vim.log.levels.WARN) end)
        return
      end

      vim.schedule(function()
        vim.lsp.util.apply_workspace_edit(result, client.offset_encoding)
        save_all_real_files()
        close_new_buffers(before, bufnr)

        if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(bufnr) then
          pcall(vim.api.nvim_set_current_win, winid)
          if vim.api.nvim_win_get_buf(winid) ~= bufnr then pcall(vim.api.nvim_win_set_buf, winid, bufnr) end
        end
      end)
    end, bufnr)
  end)
end

function M.strip_trailing_whitespace_all_buffers()
  local current = vim.api.nvim_get_current_buf()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.bo[buf].buftype == "" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd [[silent! %s/\s\+$//e]]
          vim.cmd "silent update"
        end)
      end
    end
  end

  vim.api.nvim_set_current_buf(current)
  vim.notify "Trailing whitespace removed"
end

function M.strip_trailing_whitespace_current_buffer()
  vim.cmd [[silent! %s/\s\+$//e]]
  vim.cmd "silent update"
  vim.notify "Trailing whitespace removed"
end

local function looks_like_match_arms_action(action)
  local title = (action.title or ""):lower()
  return title:find("fill match arms", 1, true) ~= nil
end

local function ensure_match_line_has_braces()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()

  if not line:find "match%s+" then return nil end

  if not line:find("{", 1, true) then
    line = line:gsub("%s*$", "") .. " {}"
    vim.api.nvim_set_current_line(line)
  elseif not line:find("}", 1, true) then
    line = line:gsub("%s*$", "") .. "}"
    vim.api.nvim_set_current_line(line)
  end

  local open_brace = line:find("{", 1, true)
  local close_brace = open_brace and line:find("}", open_brace + 1, true) or nil
  if not open_brace or not close_brace then return nil end

  local inner_col = open_brace
  vim.api.nvim_win_set_cursor(0, { row, inner_col })

  return { row = row }
end

local function replace_generated_todos_with_braces(open_pos)
  if not open_pos then return end

  local save = vim.api.nvim_win_get_cursor(0)

  local line = vim.api.nvim_buf_get_lines(0, open_pos.row - 1, open_pos.row, false)[1]
  if not line then return end

  local open_brace = line:find("{", 1, true)
  if not open_brace then return end

  local brace_col = open_brace - 1
  pcall(vim.api.nvim_win_set_cursor, 0, { open_pos.row, brace_col })

  local ok = pcall(function() vim.cmd.normal { args = { "%" }, bang = true } end)

  if not ok then
    pcall(vim.api.nvim_win_set_cursor, 0, save)
    return
  end

  local close = vim.api.nvim_win_get_cursor(0)
  pcall(vim.api.nvim_win_set_cursor, 0, save)

  local start_row = open_pos.row
  local end_row = close[1]

  if end_row < start_row then return end

  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
  if #lines == 0 then return end

  for i, l in ipairs(lines) do
    lines[i] = l:gsub("(=>%s*)todo!%(%)(%s*,?)", "%1{}%2")
  end

  vim.api.nvim_buf_set_lines(0, start_row - 1, end_row, false, lines)
end

local function looks_like_organize_imports_action(action)
  local title = (action.title or ""):lower()
  local kind = action.kind or ""

  return kind == "source.organizeImports"
    or vim.startswith(kind, "source.organizeImports")
    or title:find("remove unused imports", 1, true) ~= nil
    or title:find("remove all unused imports", 1, true) ~= nil
    or title:find("organize imports", 1, true) ~= nil
end

local function apply_first_matching_code_action(filter, context, timeout_ms)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = "textDocument/codeAction" }

  if #clients == 0 then
    vim.notify("No LSP code actions available", vim.log.levels.WARN)
    return false
  end

  for _, client in ipairs(clients) do
    ---@type lsp.CodeActionParams
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(bufnr),
      range = vim.lsp.util.make_range_params(0, client.offset_encoding).range,
      context = vim.tbl_deep_extend("force", {
        diagnostics = vim.diagnostic.get(bufnr),
      }, context or {}),
    }

    local resp = client:request_sync("textDocument/codeAction", params, timeout_ms or 3000, bufnr)
    local actions = resp and resp.result or {}

    for _, action in ipairs(actions) do
      if filter(action, client) then
        if action.edit then vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding) end

        if type(action.command) == "table" then
          client:exec_cmd(action.command, { bufnr = bufnr })
        elseif type(action.command) == "string" then
          client:exec_cmd({
            title = action.title,
            command = action.command,
            arguments = action.arguments,
          }, { bufnr = bufnr })
        end

        return true
      end
    end
  end

  return false
end

function M.rust_fill_match_arms_smart()
  if vim.bo.filetype ~= "rust" then return end

  vim.cmd.stopinsert()

  local open_pos = ensure_match_line_has_braces()
  if not open_pos then return end

  local ok = apply_first_matching_code_action(looks_like_match_arms_action)
  if not ok then
    vim.notify("No fill match arms action found", vim.log.levels.INFO)
    return
  end

  vim.defer_fn(function() replace_generated_todos_with_braces(open_pos) end, 120)
end

function M.rust_remove_unused_imports_this_file()
  if vim.bo.filetype ~= "rust" then return end

  vim.cmd.stopinsert()

  local ok = apply_first_matching_code_action(looks_like_organize_imports_action, {
    only = { "source.organizeImports" },
    diagnostics = {},
  })

  if ok then
    vim.cmd "silent update"
  else
    vim.notify("No remove-unused-imports action found", vim.log.levels.INFO)
  end
end

function M.select_whole_file() vim.cmd.normal { args = { "gg0vG$" }, bang = true } end

local function visual_paste_restore_reg()
  local reg = vim.v.register

  if reg == nil or reg == "" or reg == '"' then
    local cb = vim.opt.clipboard:get()
    if vim.tbl_contains(cb, "unnamedplus") then
      reg = "+"
    elseif vim.tbl_contains(cb, "unnamed") then
      reg = "*"
    else
      reg = '"'
    end
  end

  return reg
end

function M.visual_paste_keep_regs(cmd)
  local reg = visual_paste_restore_reg()
  local saved = {
    value = vim.fn.getreg(reg),
    regtype = vim.fn.getregtype(reg),
  }

  vim.schedule(function() vim.fn.setreg(reg, saved.value, saved.regtype) end)

  return cmd
end

return M
