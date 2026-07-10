---@type LazySpec
return {
  "esmuellert/codediff.nvim",
  opts = {
    diff = {
      cycle_hunks_across_files = true,
      cycle_next_hunk = false,
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
    ---@class ViterCodeDiffChangeSide
    ---@field start_line integer

    ---@class ViterCodeDiffChange
    ---@field original ViterCodeDiffChangeSide
    ---@field modified ViterCodeDiffChangeSide

    ---@class ViterCodeDiffDiffResult
    ---@field changes ViterCodeDiffChange[]?

    ---@class ViterCodeDiffExplorerSplit
    ---@field winid? integer

    ---@class ViterCodeDiffExplorer
    ---@field split? ViterCodeDiffExplorerSplit
    ---@field winid? integer
    ---@field bufnr? integer
    ---@field is_hidden? boolean

    ---@class ViterCodeDiffSession
    ---@field stored_diff_result? ViterCodeDiffDiffResult
    ---@field pending_cursor_landing? "first"|"last"
    ---@field modified_win? integer
    ---@field original_win? integer
    ---@field result_win? integer
    ---@field original_bufnr? integer
    ---@field modified_bufnr? integer
    ---@field result_bufnr? integer
    ---@field modified_path? string
    ---@field git_root? string
    ---@field explorer? ViterCodeDiffExplorer

    require("codediff").setup(opts)

    local navigation = require "codediff.ui.view.navigation"
    local lifecycle = require "codediff.ui.lifecycle"
    local open_in_prev_tab_key = opts.keymaps and opts.keymaps.view and opts.keymaps.view.open_in_prev_tab
    local focus_explorer_key = opts.keymaps and opts.keymaps.view and opts.keymaps.view.focus_explorer
    local blocked_sidebar_keys = { "<leader>e", "<leader>o" }
    local guarded_sidebar_buffers = {}
    local original_next_hunk = navigation.next_hunk
    local original_prev_hunk = navigation.prev_hunk

    local function hunkless_file_hop(direction)
      local tabpage = vim.api.nvim_get_current_tabpage()
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage)
      local changes = session and session.stored_diff_result and session.stored_diff_result.changes

      -- `nil` means CodeDiff is still loading the next diff. Only single-pane
      -- entries (untracked/added/deleted files) have a fully loaded, empty
      -- change list. Treating the loading state as hunkless can start another
      -- file switch before the first one finishes.
      if type(changes) ~= "table" or #changes ~= 0 then return false end
      if not opts.diff.cycle_hunks_across_files then return false end
      if not lifecycle.get_explorer(tabpage) then return false end

      if session then session.pending_cursor_landing = direction == "next" and "first" or "last" end

      if direction == "next" then
        return navigation.next_file()
      else
        return navigation.prev_file()
      end
    end

    -- Let CodeDiff's native cross-file hunk navigation handle real diffs.
    -- The fallback only skips its single-pane, zero-hunk file entries.
    function navigation.next_hunk() return original_next_hunk() or hunkless_file_hop "next" end

    function navigation.prev_hunk() return original_prev_hunk() or hunkless_file_hop "prev" end

    ---@param session ViterCodeDiffSession?
    local function continue_target_matches(session)
      local target_file = vim.g.viter_codediff_continue_file
      if type(target_file) ~= "string" or target_file == "" then return true end
      if not session or type(session.modified_path) ~= "string" or session.modified_path == "" then return false end

      local session_file = session.modified_path
      if session.git_root and session_file:sub(1, 1) ~= "/" then
        session_file = session.git_root .. "/" .. session_file
      end

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
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
      if not session then return end

      for _, win in ipairs { session.original_win, session.modified_win, session.result_win } do
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
        if not (target and vim.api.nvim_win_is_valid(target)) then
          target = session.original_win
        end
        if not (target and vim.api.nvim_win_is_valid(target)) then
          target = session.result_win
        end
        if target and vim.api.nvim_win_is_valid(target) then vim.api.nvim_set_current_win(target) end
        return
      end

      if explorer_obj.is_hidden or not explorer_win then require("codediff.ui.explorer").toggle_visibility(explorer_obj) end

      vim.schedule(function()
        local target = get_explorer_win(explorer_obj)
        if target then vim.api.nvim_set_current_win(target) end
      end)
    end

    local function open_real_buffer_in_prev_tab(tabpage)
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage)
      if not session then return end

      local original_bufnr, modified_bufnr = lifecycle.get_buffers(tabpage)
      local current_buf = vim.api.nvim_get_current_buf()
      local side = current_buf == original_bufnr and "original" or current_buf == modified_bufnr and "modified" or nil
      if not side then return end

      local is_virtual = side == "original" and lifecycle.is_original_virtual(tabpage)
        or side == "modified" and lifecycle.is_modified_virtual(tabpage)

      local target_file = vim.api.nvim_buf_get_name(current_buf)
      if is_virtual then
        local original_path, modified_path = lifecycle.get_paths(tabpage)
        local rel_path = side == "original" and original_path or modified_path
        if not rel_path or rel_path == "" then
          vim.notify("Buffer has no associated file path", vim.log.levels.WARN)
          return
        end
        target_file = session.git_root .. "/" .. rel_path
      end

      if target_file == "" then
        vim.notify("Buffer has no name; cannot open in previous tab", vim.log.levels.WARN)
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local current_tab = vim.api.nvim_get_current_tabpage()
      local tabs = vim.api.nvim_list_tabpages()
      local current_index

      for i, tab in ipairs(tabs) do
        if tab == current_tab then
          current_index = i
          break
        end
      end

      local target_tab
      if current_index and current_index > 1 then
        target_tab = tabs[current_index - 1]
      else
        vim.cmd "tabnew"
        target_tab = vim.api.nvim_get_current_tabpage()
        vim.cmd "tabmove 0"
      end

      if vim.api.nvim_get_current_tabpage() ~= target_tab then vim.api.nvim_set_current_tabpage(target_tab) end

      local ok, err = pcall(vim.cmd, "hide edit " .. vim.fn.fnameescape(target_file))
      if not ok then
        vim.notify("Failed to open buffer in previous tab: " .. err, vim.log.levels.ERROR)
        return
      end

      pcall(vim.api.nvim_win_set_cursor, 0, cursor)

      if opts.keymaps.view.close_on_open_in_prev_tab and vim.api.nvim_tabpage_is_valid(current_tab) then
        lifecycle.cleanup(current_tab)
        vim.cmd(vim.api.nvim_tabpage_get_number(current_tab) .. "tabclose")
      end

      vim.cmd "normal! zz"
    end

    local function remap_open_in_prev_tab(tabpage)
      if not open_in_prev_tab_key then return end
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
      if not session then return end

      for _, bufnr in ipairs { session.original_bufnr, session.modified_bufnr } do
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          vim.keymap.set("n", open_in_prev_tab_key, function() open_real_buffer_in_prev_tab(tabpage) end, {
            buffer = bufnr,
            noremap = true,
            silent = true,
            nowait = true,
            desc = "Open buffer in previous tab",
          })
        end
      end
    end

    local function remap_focus_explorer(tabpage)
      if not focus_explorer_key then return end
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
      if not session then return end

      for _, bufnr in ipairs { session.original_bufnr, session.modified_bufnr, session.result_bufnr } do
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          vim.keymap.set("n", focus_explorer_key, function() focus_sidebar_or_modified(tabpage) end, {
            buffer = bufnr,
            noremap = true,
            silent = true,
            nowait = true,
            desc = "Focus CodeDiff sidebar",
          })
        end
      end

      local explorer = session.explorer
      if explorer and explorer.bufnr and vim.api.nvim_buf_is_valid(explorer.bufnr) then
        vim.keymap.set("n", focus_explorer_key, function() focus_sidebar_or_modified(tabpage) end, {
          buffer = explorer.bufnr,
          noremap = true,
          silent = true,
          nowait = true,
          desc = "Return to modified pane",
        })
      end
    end

    ---@param session ViterCodeDiffSession?
    ---@return integer[]
    local function collect_session_buffers(session)
      if not session then return {} end

      local buffers = {}
      local seen = {}
      local explorer = session.explorer

      for _, bufnr in ipairs {
        session.original_bufnr,
        session.modified_bufnr,
        session.result_bufnr,
        explorer and explorer.bufnr or nil,
      } do
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) and not seen[bufnr] then
          seen[bufnr] = true
          table.insert(buffers, bufnr)
        end
      end

      return buffers
    end

    ---@param buffers integer[]
    local function clear_sidebar_guards_for_buffers(buffers)
      for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          for _, lhs in ipairs(blocked_sidebar_keys) do
            pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
          end
        end
      end
    end

    local function set_preview_sidebar_guards(tabpage)
      ---@type ViterCodeDiffSession?
      local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
      if not session then return end

      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      local guarded = guarded_sidebar_buffers[tab] or {}
      local desired = {}

      for _, bufnr in ipairs(collect_session_buffers(session)) do
        desired[bufnr] = true
        for _, lhs in ipairs(blocked_sidebar_keys) do
          vim.keymap.set("n", lhs, "<Nop>", {
            buffer = bufnr,
            noremap = true,
            silent = true,
            nowait = true,
            desc = "Disabled in CodeDiff",
          })
        end
      end

      local stale = {}
      for bufnr in pairs(guarded) do
        if not desired[bufnr] then table.insert(stale, bufnr) end
      end
      clear_sidebar_guards_for_buffers(stale)

      guarded_sidebar_buffers[tab] = desired
    end

    local function clear_preview_sidebar_guards(tabpage)
      local tab = tabpage or vim.api.nvim_get_current_tabpage()
      local tracked = guarded_sidebar_buffers[tab]
      if not tracked then return end

      local buffers = {}
      for bufnr in pairs(tracked) do
        table.insert(buffers, bufnr)
      end

      clear_sidebar_guards_for_buffers(buffers)
      guarded_sidebar_buffers[tab] = nil
    end

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("viter_codediff_wrap", { clear = true }),
      pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        vim.schedule(function()
          wrap_diff_windows(tabpage)
          consume_continue_landing(tabpage)
          remap_open_in_prev_tab(tabpage)
          remap_focus_explorer(tabpage)
          set_preview_sidebar_guards(tabpage)
          vim.defer_fn(function() wrap_diff_windows(tabpage) end, 80)
        end)
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("viter_codediff_continue", { clear = true }),
      pattern = "CodeDiffFileSelect",
      callback = function(args)
        if not args.data or not args.data.path then return end

        ---@type ViterCodeDiffSession?
        local session = lifecycle.get_session(args.data.tabpage or vim.api.nvim_get_current_tabpage())
        vim.g.viter_codediff_last_file = args.data.path
        vim.g.viter_codediff_last_root = session and session.git_root or nil
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("viter_codediff_sidebar_guards", { clear = true }),
      pattern = "CodeDiffClose",
      callback = function(args)
        clear_preview_sidebar_guards(args.data and args.data.tabpage)
      end,
    })
  end,
}
