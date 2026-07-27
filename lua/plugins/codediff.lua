---@type LazySpec
return {
  "esmuellert/codediff.nvim",
  opts = {
    diff = {
      cycle_hunks_across_files = true,
      cycle_next_hunk = true,
      cycle_next_file = true,
      jump_to_first_change = true,
    },
    explorer = {
      initial_focus = "modified",
      focus_on_select = true,
    },

    keymaps = {
      view = {
        next_hunk = "e",
        prev_hunk = "n",
        next_file = "u",
        prev_file = "l",
        open_in_prev_tab = "i",
        close_on_open_in_prev_tab = true,
        toggle_explorer = "y",
        focus_explorer = "o",
      },
      explorer = {
        hover = false,
        toggle_view_mode = false,
      },
    },
  },
  config = function(_, opts)
    ---@class ViterCodeDiffExplorerSplit
    ---@field winid? integer

    ---@class ViterCodeDiffExplorer
    ---@field split? ViterCodeDiffExplorerSplit
    ---@field winid? integer
    ---@field bufnr? integer
    ---@field is_hidden? boolean

    ---@class ViterCodeDiffPath
    ---@field absolute string
    ---@field relative string

    ---@class ViterCodeDiffSession
    ---@field stored_diff_result? { changes?: ViterCodeDiffChange[] }
    ---@field modified_win? integer
    ---@field original_win? integer
    ---@field result_win? integer
    ---@field original_bufnr? integer
    ---@field modified_bufnr? integer
    ---@field result_bufnr? integer
    ---@field modified? ViterCodeDiffPath
    ---@field git_root? string
    ---@field explorer? ViterCodeDiffExplorer
    ---@field layout? "inline"|"side-by-side"
    ---@field pending_cursor_landing? "first"|"last"

    ---@class ViterCodeDiffChange
    ---@field original { start_line: integer }
    ---@field modified { start_line: integer }

    require("codediff").setup(opts)

    -- CodeDiff asks the real buffer's LSP for semantic tokens for codediff://
    -- revision buffers. rust-analyzer treats those URIs as extra workspace
    -- documents, and CodeDiff 2.53 can send duplicate didOpen/orphan didClose
    -- notifications while changing files or closing the view. Keep TreeSitter
    -- highlighting for Rust diffs, but do not involve rust-analyzer.
    local semantic_tokens = require "codediff.ui.semantic_tokens"
    local apply_semantic_tokens = semantic_tokens.apply_semantic_tokens

    local function is_rust_buffer(bufnr)
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end
      if vim.bo[bufnr].filetype == "rust" then return true end
      return vim.api.nvim_buf_get_name(bufnr):match "%.rs$" ~= nil
    end

    semantic_tokens.apply_semantic_tokens = function(virtual_buf, source_buf)
      if is_rust_buffer(virtual_buf) or is_rust_buffer(source_buf) then return false end
      return apply_semantic_tokens(virtual_buf, source_buf)
    end

    -- Cleanup sends didClose independently of whether semantic highlighting
    -- opened the virtual document. Filter only CodeDiff's rust-analyzer
    -- notifications; normal Neovim LSP traffic remains untouched.
    local codediff_compat = require "codediff.core.compat"
    local codediff_lsp_notify = codediff_compat.lsp_notify

    codediff_compat.lsp_notify = function(client, method, params)
      local client_name = client and client.name
      local uri = params and params.textDocument and params.textDocument.uri
      local rust_analyzer = client_name == "rust-analyzer" or client_name == "rust_analyzer"
      local virtual_document = type(uri) == "string" and uri:match "^codediff:"
      local document_lifecycle = method == "textDocument/didOpen" or method == "textDocument/didClose"

      if rust_analyzer and virtual_document and document_lifecycle then return true end
      return codediff_lsp_notify(client, method, params)
    end

    local lifecycle = require "codediff.ui.lifecycle"
    local navigation = require "codediff.ui.view.navigation"
    local codediff_next_hunk = navigation.next_hunk

    -- A deletion after the final retained line is represented as line_count + 1
    -- on the modified side. CodeDiff 2.53 treats the failed cursor move as a
    -- successful jump and never reaches its cross-file fallback.
    local function handle_eof_deletion_hunk()
      local tabpage = vim.api.nvim_get_current_tabpage()
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage)
      local changes = session and session.stored_diff_result and session.stored_diff_result.changes
      if not session or type(changes) ~= "table" or #changes == 0 then return end
      if not opts.diff.cycle_hunks_across_files or not lifecycle.get_explorer(tabpage) then return end

      local current_buf = vim.api.nvim_get_current_buf()
      local uses_modified_lines = session.layout == "inline" or current_buf == session.modified_bufnr
      if not uses_modified_lines then return end

      local line_count = vim.api.nvim_buf_line_count(current_buf)
      local current_line = vim.api.nvim_win_get_cursor(0)[1]

      for index, change in ipairs(changes) do
        local target_line = change.modified.start_line
        if target_line > current_line then
          if target_line <= line_count then return end

          if current_line < line_count then
            vim.api.nvim_win_set_cursor(0, { line_count, 0 })
            vim.cmd "normal! zz"
            vim.api.nvim_echo({ { ("Hunk %d of %d"):format(index, #changes), "None" } }, false, {})
            return true
          end

          session.pending_cursor_landing = "first"
          navigation.next_file()
          return true
        end
      end
    end

    navigation.next_hunk = function()
      local handled = handle_eof_deletion_hunk()
      if handled ~= nil then return handled end
      return codediff_next_hunk()
    end

    local focus_explorer_key = opts.keymaps and opts.keymaps.view and opts.keymaps.view.focus_explorer
    local blocked_sidebar_keys = { "<leader>e", "<leader>o" }

    local function remember_last_tab(tabpage)
      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      if tab and vim.api.nvim_tabpage_is_valid(tab) then vim.g.viter_codediff_last_tab = tab end
    end

    ---@param session ViterCodeDiffSession?
    local function continue_target_matches(session)
      local target_file = vim.g.viter_codediff_continue_file
      if type(target_file) ~= "string" or target_file == "" then return true end
      local session_file = session and session.modified and session.modified.absolute
      if type(session_file) ~= "string" or session_file == "" then return false end

      return vim.fn.fnamemodify(session_file, ":p") == vim.fn.fnamemodify(target_file, ":p")
    end

    local function consume_continue_landing(tabpage, attempt)
      local target_line = vim.g.viter_codediff_continue_line
      if type(target_line) ~= "number" then return end

      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
      local win = session and session.modified_win
      if
        not session
        or not continue_target_matches(session)
        or not session.stored_diff_result
        or not win
        or not vim.api.nvim_win_is_valid(win)
        or not vim.api.nvim_buf_is_valid(vim.api.nvim_win_get_buf(win))
      then
        if (attempt or 1) < 30 then
          vim.defer_fn(function() consume_continue_landing(tabpage, (attempt or 1) + 1) end, 50)
        end
        return
      end

      local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
      local line = math.max(1, math.min(target_line, line_count))
      local col = type(vim.g.viter_codediff_continue_col) == "number" and vim.g.viter_codediff_continue_col or 0

      vim.api.nvim_set_current_win(win)
      pcall(vim.api.nvim_win_set_cursor, win, { line, col })
      vim.cmd "normal! zz"
      vim.g.viter_codediff_continue_file = nil
      vim.g.viter_codediff_continue_line = nil
      vim.g.viter_codediff_continue_col = nil
    end

    local function wrap_diff_windows(tabpage)
      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tab)
      if not session then return end

      local windows = { session.original_win, session.modified_win, session.result_win }

      -- CodeDiff 2.53 enforces nowrap during view lifecycle events. Restore the
      -- wrapped view after those events so deeply indented code remains visible.
      for _, win in ipairs(windows) do
        if win and vim.api.nvim_win_is_valid(win) then
          vim.wo[win].wrap = true
          vim.wo[win].linebreak = true
          vim.wo[win].breakindent = true
        end
      end
    end

    ---@param explorer_obj ViterCodeDiffExplorer?
    ---@return integer?
    local function get_explorer_win(explorer_obj)
      local split = explorer_obj and explorer_obj.split
      local win = split and split.winid
      if win and vim.api.nvim_win_is_valid(win) then return win end

      win = explorer_obj and explorer_obj.winid
      if win and vim.api.nvim_win_is_valid(win) then return win end

      local buf = explorer_obj and explorer_obj.bufnr
      if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

      win = vim.fn.bufwinid(buf)
      if win == -1 or not vim.api.nvim_win_is_valid(win) then return end

      if split then split.winid = win end
      explorer_obj.winid = win
      return win
    end

    local function focus_sidebar_or_modified(tabpage)
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage)
      ---@type ViterCodeDiffExplorer?
      local explorer_obj = lifecycle.get_explorer(tabpage)
      if not session or not explorer_obj then return end

      local current_win = vim.api.nvim_get_current_win()
      local current_buf = vim.api.nvim_get_current_buf()
      local explorer_win = get_explorer_win(explorer_obj)
      local in_explorer = current_buf == explorer_obj.bufnr or (explorer_win and current_win == explorer_win)

      if in_explorer then
        local target = session.modified_win
        if not (target and vim.api.nvim_win_is_valid(target)) then target = session.original_win end
        if not (target and vim.api.nvim_win_is_valid(target)) then target = session.result_win end
        if target and vim.api.nvim_win_is_valid(target) then vim.api.nvim_set_current_win(target) end
        return
      end

      if explorer_obj.is_hidden or not explorer_win then
        require("codediff.ui.explorer").toggle_visibility(explorer_obj)
      end

      vim.schedule(function()
        local target = get_explorer_win(explorer_obj)
        if target then vim.api.nvim_set_current_win(target) end
      end)
    end

    local function remap_focus_explorer(tabpage)
      if not focus_explorer_key then return end
      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      lifecycle.set_tab_keymap(tab, "n", focus_explorer_key, function() focus_sidebar_or_modified(tab) end, {
        desc = "Toggle CodeDiff sidebar focus",
      })
    end

    local function set_preview_sidebar_guards(tabpage)
      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      for _, lhs in ipairs(blocked_sidebar_keys) do
        lifecycle.set_tab_keymap(tab, "n", lhs, "<Nop>", {
          desc = "Disabled in CodeDiff",
        })
      end
    end

    local function apply_session_customizations(tabpage, expected_path, attempt)
      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      local session = lifecycle.get_session(tab)
      local current_path = session and session.modified and session.modified.relative
      local ready = session and session.stored_diff_result and (not expected_path or current_path == expected_path)

      if not ready then
        if (attempt or 1) < 100 then
          vim.defer_fn(function() apply_session_customizations(tab, expected_path, (attempt or 1) + 1) end, 50)
        end
        return
      end

      consume_continue_landing(tab)
      remap_focus_explorer(tab)
      set_preview_sidebar_guards(tab)
      wrap_diff_windows(tab)
    end

    local customization_group = vim.api.nvim_create_augroup("viter_codediff_customizations", { clear = true })

    vim.api.nvim_create_autocmd("User", {
      group = customization_group,
      pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        remember_last_tab(tabpage)
        local expected_path = args.data and args.data.path
        vim.schedule(function() apply_session_customizations(tabpage, expected_path) end)
      end,
    })

    vim.api.nvim_create_autocmd("WinEnter", {
      group = customization_group,
      callback = function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        local session = lifecycle.get_session(tabpage)
        local win = vim.api.nvim_get_current_win()
        if session and (win == session.original_win or win == session.modified_win or win == session.result_win) then
          vim.schedule(function() wrap_diff_windows(tabpage) end)
        end
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = customization_group,
      pattern = "CodeDiffClose",
      callback = function()
        vim.schedule(function()
          -- CodeDiff 2.53 can move its unlisted working buffer into the
          -- previous tab with `i`. Make it a normal AstroNvim buffer again.
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local bufnr = vim.api.nvim_win_get_buf(win)
            if vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= "" then
              vim.bo[bufnr].buflisted = true
            end
          end
        end)
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("viter_codediff_continue", { clear = true }),
      pattern = "CodeDiffFileSelect",
      callback = function(args)
        if not args.data or not args.data.path then return end

        local tabpage = args.data.tabpage or vim.api.nvim_get_current_tabpage()
        ---@type ViterCodeDiffSession?
        local session = lifecycle.get_session(tabpage)
        remember_last_tab(args.data.tabpage)
        vim.g.viter_codediff_last_file = args.data.path
        vim.g.viter_codediff_last_root = session and session.git_root or nil
      end,
    })
  end,
}
