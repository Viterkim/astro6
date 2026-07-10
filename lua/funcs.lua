local M = {}

local function safe_cmd(cmd)
  pcall(function() vim.cmd(cmd) end)
end

function M.sudoku_quit()
  local answer = vim.fn.input "Type sudoku to nuke all windows: "
  if answer ~= "sudoku" then
    vim.notify "Aborted"
    return
  end

  safe_cmd "Neotree close left"
  safe_cmd "Neotree close right"
  vim.cmd "qa!"
end

function M.exit_visual()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
end

function M.quit_window_or_nvim()
  local sidebar_filetypes = {
    ["neo-tree"] = true,
    aerial = true,
  }

  if sidebar_filetypes[vim.bo.filetype] then
    vim.cmd "qa"
  else
    vim.cmd "q"
  end
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

function M.close_hidden_file_buffers()
  local keep = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then keep[vim.api.nvim_win_get_buf(win)] = true end
  end

  local closed = 0
  local skipped_modified = 0

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_real_file_buffer(bufnr) and not keep[bufnr] then
      if vim.bo[bufnr].modified then
        skipped_modified = skipped_modified + 1
      else
        local ok = pcall(vim.api.nvim_buf_delete, bufnr, {})
        if ok then closed = closed + 1 end
      end
    end
  end

  local msg = ("Closed %d hidden buffer%s"):format(closed, closed == 1 and "" or "s")

  if skipped_modified > 0 then msg = msg .. ("; skipped %d modified"):format(skipped_modified) end

  vim.notify(msg)
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

local function restart_session_file()
  local dir = vim.fn.stdpath "state" .. "/restart-session"
  vim.fn.mkdir(dir, "p")

  local cwd = vim.uv.cwd() or vim.fn.getcwd()
  local name = vim.fn.fnamemodify(cwd, ":p"):gsub("[/\\:]", "%%")

  return dir .. "/" .. name .. ".vim"
end

local function window_with_filetype(filetype)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == filetype then return win end
  end
end

local function real_file_from_codediff_session(diff)
  if not diff then return nil end

  for _, bufnr in ipairs { diff.modified_bufnr, diff.original_bufnr, diff.result_bufnr } do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and vim.bo[bufnr].buftype == "" and vim.fn.filereadable(name) == 1 then return name end
    end
  end
end

local function cleanup_active_codediff_tabs()
  local ok_lifecycle, lifecycle = pcall(require, "codediff.ui.lifecycle")
  local ok_session, session = pcall(require, "codediff.ui.lifecycle.session")
  if not ok_lifecycle or not ok_session then return end

  local active_diffs = session.get_active_diffs()
  local diff_tabs = {}
  for tabpage in pairs(active_diffs) do
    if vim.api.nvim_tabpage_is_valid(tabpage) then table.insert(diff_tabs, tabpage) end
  end
  if #diff_tabs == 0 then return end

  local all_tabs_are_diffs = #diff_tabs == #vim.api.nvim_list_tabpages()
  if all_tabs_are_diffs then
    local current_tab = vim.api.nvim_get_current_tabpage()
    local fallback_file = real_file_from_codediff_session(active_diffs[current_tab])
    vim.cmd "tabnew"
    if fallback_file then pcall(vim.cmd, "edit " .. vim.fn.fnameescape(fallback_file)) end
  end

  table.sort(
    diff_tabs,
    function(a, b) return vim.api.nvim_tabpage_get_number(a) > vim.api.nvim_tabpage_get_number(b) end
  )

  local original_tab = vim.api.nvim_get_current_tabpage()

  for _, tabpage in ipairs(diff_tabs) do
    if vim.api.nvim_tabpage_is_valid(tabpage) then
      pcall(vim.api.nvim_set_current_tabpage, tabpage)
      lifecycle.cleanup_for_quit(tabpage)

      if #vim.api.nvim_list_tabpages() > 1 then pcall(vim.cmd, "tabclose") end
    end
  end

  if vim.api.nvim_tabpage_is_valid(original_tab) then
    pcall(vim.api.nvim_set_current_tabpage, original_tab)
    return
  end

  local remaining_tabs = vim.api.nvim_list_tabpages()
  if remaining_tabs[1] then pcall(vim.api.nvim_set_current_tabpage, remaining_tabs[1]) end
end

local function close_session_poison()
  safe_cmd "silent! Neotree close"
  safe_cmd "silent! Neotree close left"
  safe_cmd "silent! Neotree close right"
  safe_cmd "silent! AerialClose"

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype

    if ft == "neo-tree" or ft == "aerial" then pcall(vim.api.nvim_win_close, win, true) end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.bo[buf].filetype

    if ft == "neo-tree" or ft == "aerial" then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  end
end

local function append_restart_commands(file, state)
  vim.fn.writefile({
    "",
    '" Re-open disposable UI after real session state has been restored.',
    "lua vim.schedule(function()"
      .. (state.neo_tree_open and " pcall(function() vim.cmd [[silent! Neotree reveal left]] end)" or "")
      .. (state.aerial_open and " pcall(function() vim.cmd [[silent! AerialOpen]] end)" or "")
      .. " pcall(function() vim.cmd [[wincmd p]] end)"
      .. " end)",
  }, file, "a")
end

function M.restart_with_session()
  save_all_real_files()
  local state = {
    neo_tree_open = window_with_filetype "neo-tree" ~= nil,
    aerial_open = window_with_filetype "aerial" ~= nil,
  }

  cleanup_active_codediff_tabs()
  close_session_poison()

  local file = restart_session_file()
  local old_sessionoptions = vim.o.sessionoptions

  vim.opt.sessionoptions = {
    "buffers",
    "curdir",
    "folds",
    "tabpages",
    "winsize",
    "terminal",
  }

  vim.cmd("silent! mksession! " .. vim.fn.fnameescape(file))
  vim.o.sessionoptions = old_sessionoptions

  append_restart_commands(file, state)

  vim.cmd("restart source " .. vim.fn.fnameescape(file))
end

function M.rust_remove_unused_imports_this_file()
  if vim.bo.filetype ~= "rust" then return end

  local bufnr = vim.api.nvim_get_current_buf()

  local client
  for _, c in ipairs(vim.lsp.get_clients { bufnr = bufnr, method = "textDocument/codeAction" }) do
    if c.name == "rust-analyzer" or c.name == "rust_analyzer" then
      client = c
      break
    end
  end

  if not client then
    vim.notify("No rust-analyzer attached", vim.log.levels.WARN)
    return
  end

  local function clean_code(code)
    if type(code) == "table" then code = code.code or code.value end
    if type(code) == "string" or type(code) == "number" then return code end
    return nil
  end

  local function raw_lsp_diagnostic(diagnostic)
    local user_data = diagnostic.user_data
    if type(user_data) == "table" and type(user_data.lsp) == "table" then return user_data.lsp end
    return nil
  end

  local function is_unused_import(diagnostic)
    local lsp = raw_lsp_diagnostic(diagnostic)
    local code = clean_code(diagnostic.code) or clean_code(lsp and lsp.code)
    local message = ((diagnostic.message or "") .. " " .. ((lsp and lsp.message) or "")):lower()

    code = tostring(code or ""):lower()

    return code == "unused_imports"
      or code:find("unused_import", 1, true) ~= nil
      or message:find("unused import", 1, true) ~= nil
      or message:find("unused imports", 1, true) ~= nil
  end

  local function to_lsp_diagnostic(diagnostic)
    local lsp = raw_lsp_diagnostic(diagnostic)
    if type(lsp) == "table" and type(lsp.range) == "table" then
      return {
        range = lsp.range,
        severity = lsp.severity,
        code = clean_code(lsp.code),
        source = lsp.source,
        message = lsp.message or diagnostic.message or "",
        tags = type(lsp.tags) == "table" and lsp.tags or nil,
        data = lsp.data,
      }
    end

    return {
      range = {
        start = {
          line = diagnostic.lnum or 0,
          character = diagnostic.col or 0,
        },
        ["end"] = {
          line = diagnostic.end_lnum or diagnostic.lnum or 0,
          character = diagnostic.end_col or diagnostic.col or 0,
        },
      },
      severity = diagnostic.severity,
      code = clean_code(diagnostic.code),
      source = diagnostic.source,
      message = diagnostic.message or "",
    }
  end

  local diagnostics = vim.tbl_filter(is_unused_import, vim.diagnostic.get(bufnr))
  if #diagnostics == 0 then
    vim.notify("No unused-import diagnostics in this buffer", vim.log.levels.INFO)
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = line_count - 1, character = #last_line },
    },
    context = {
      diagnostics = vim.tbl_map(to_lsp_diagnostic, diagnostics),
      only = { "quickfix" },
    },
  }

  local response = client:request_sync("textDocument/codeAction", params, 3000, bufnr)
  local actions = response and response.result or {}
  local best
  local best_score = 999

  for _, action in ipairs(actions) do
    local title = (action.title or ""):lower()
    local score

    if title:find("remove all", 1, true) and title:find("unused import", 1, true) then
      score = 1
    elseif title:find("remove", 1, true) and title:find("unused imports", 1, true) then
      score = 2
    elseif title:find("remove", 1, true) and title:find("unused import", 1, true) then
      score = 3
    elseif title:find("delete", 1, true) and title:find("unused import", 1, true) then
      score = 4
    end

    if score and score < best_score then
      best = action
      best_score = score
    end
  end

  if not best then
    vim.notify("No remove-unused-import code action from rust-analyzer", vim.log.levels.INFO)
    return
  end

  if not best.edit and not best.command and client:supports_method("codeAction/resolve", bufnr) then
    local resolved = client:request_sync("codeAction/resolve", best, 3000, bufnr)
    best = resolved and resolved.result or best
  end

  if best.edit then vim.lsp.util.apply_workspace_edit(best.edit, client.offset_encoding) end
  if type(best.command) == "table" then
    client:exec_cmd(best.command, { bufnr = bufnr })
  elseif type(best.command) == "string" then
    client:exec_cmd({
      title = best.title,
      command = best.command,
      arguments = best.arguments,
    }, { bufnr = bufnr })
  end

  vim.cmd "silent update"
  vim.notify(("Applied: %s"):format(best.title or "remove unused imports"))
end

function M.open_current_file_codediff()
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file == "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end

  local git = require "codediff.core.git"
  local view = require "codediff.ui.view"

  git.get_git_root(current_file, function(err_root, git_root)
    if err_root then
      vim.schedule(function() vim.notify(err_root, vim.log.levels.ERROR) end)
      return
    end

    local relative_path = git.get_relative_path(current_file, git_root)
    local abs_path = git_root .. "/" .. relative_path
    local filetype = vim.bo[0].filetype
    if not filetype or filetype == "" then filetype = vim.filetype.match { filename = current_file } or "" end

    git.get_status(git_root, function(err_status, status_result)
      if err_status then
        vim.schedule(function() vim.notify(err_status, vim.log.levels.ERROR) end)
        return
      end

      local function find_file(files)
        for _, file in ipairs(files or {}) do
          if file.path == relative_path then return file end
        end
      end

      local unstaged = find_file(status_result.unstaged)
      local staged = find_file(status_result.staged)
      local conflict = find_file(status_result.conflicts)

      if conflict then
        vim.schedule(function() vim.notify("Use <Leader>rr for conflict previews", vim.log.levels.INFO) end)
        return
      end

      if not unstaged and not staged then
        vim.schedule(function() vim.notify("No staged or unstaged changes for current file", vim.log.levels.INFO) end)
        return
      end

      git.resolve_revision("HEAD", git_root, function(err_resolve, head)
        if err_resolve then
          vim.schedule(function() vim.notify(err_resolve, vim.log.levels.ERROR) end)
          return
        end

        local session_config
        if unstaged then
          session_config = {
            mode = "standalone",
            git_root = git_root,
            original_path = relative_path,
            modified_path = abs_path,
            original_revision = staged and ":0" or head,
            modified_revision = nil,
            layout = "side-by-side",
          }
        else
          session_config = {
            mode = "standalone",
            git_root = git_root,
            original_path = staged.old_path or relative_path,
            modified_path = relative_path,
            original_revision = head,
            modified_revision = ":0",
            layout = "side-by-side",
          }
        end

        vim.schedule(function() view.create(session_config, filetype) end)
      end)
    end)
  end)
end

function M.continue_codediff()
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file ~= "" then
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.g.viter_codediff_continue_file = current_file
    vim.g.viter_codediff_continue_line = cursor[1]
    vim.g.viter_codediff_continue_col = cursor[2]
    vim.cmd "CodeDiff"
    return
  end

  local root = vim.g.viter_codediff_last_root
  local relative_path = vim.g.viter_codediff_last_file

  if type(root) ~= "string" or root == "" or type(relative_path) ~= "string" or relative_path == "" then
    vim.notify("No CodeDiff position to continue", vim.log.levels.INFO)
    return
  end

  local path = root .. "/" .. relative_path
  if vim.fn.filereadable(path) == 0 then
    vim.notify("Last CodeDiff file no longer exists: " .. relative_path, vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.cmd "CodeDiff"
end

return M
