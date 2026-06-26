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
        toggle_explorer = "o",
        focus_explorer = "f",
      },
      explorer = {
        hover = false,
        toggle_view_mode = false,
      },
    },
  },
  config = function(_, opts)
    require("codediff").setup(opts)

    local navigation = require "codediff.ui.view.navigation"
    local lifecycle = require "codediff.ui.lifecycle"
    local original_next_hunk = navigation.next_hunk
    local original_prev_hunk = navigation.prev_hunk
    local explorer_toggle_key = opts.keymaps and opts.keymaps.view and opts.keymaps.view.toggle_explorer
    local explorer_focus_key = opts.keymaps and opts.keymaps.view and opts.keymaps.view.focus_explorer

    local function hunkless_file_hop(direction)
      local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
      local changes = session and session.stored_diff_result and session.stored_diff_result.changes
      if changes and #changes > 0 then return false end
      if not opts.diff.cycle_hunks_across_files then return false end

      if session then session.pending_cursor_landing = direction == "next" and "first" or "last" end

      if direction == "next" then
        return navigation.next_file()
      else
        return navigation.prev_file()
      end
    end

    function navigation.next_hunk() return hunkless_file_hop "next" or original_next_hunk() end

    function navigation.prev_hunk() return hunkless_file_hop "prev" or original_prev_hunk() end

    local function consume_continue_landing(tabpage, attempt)
      local target_line = vim.g.viter_codediff_continue_line
      if type(target_line) ~= "number" then return end

      local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
      local win = session and session.modified_win
      if
        not session
        or not session.stored_diff_result
        or not win
        or not vim.api.nvim_win_is_valid(win)
        or not vim.api.nvim_buf_is_valid(vim.api.nvim_win_get_buf(win))
      then
        if (attempt or 1) < 8 then
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
      local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
      if not ok then return end

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

    local function get_explorer_win(explorer_obj)
      local split = explorer_obj and explorer_obj.split
      local win = split and split.winid or explorer_obj and explorer_obj.winid
      if win and vim.api.nvim_win_is_valid(win) then return win end
    end

    local function fallback_view_win(session)
      if not session then return end
      for _, win in ipairs { session.modified_win, session.original_win, session.result_win } do
        if win and vim.api.nvim_win_is_valid(win) then return win end
      end
    end

    local function focus_explorer_sidebar(tabpage)
      local session = lifecycle.get_session(tabpage)
      local explorer_obj = lifecycle.get_explorer(tabpage)
      if not session or not explorer_obj then
        vim.notify("No explorer found for this tab", vim.log.levels.WARN)
        return
      end

      local current_win = vim.api.nvim_get_current_win()
      local explorer_win = get_explorer_win(explorer_obj)

      if current_win ~= explorer_win then session.viter_explorer_return_win = current_win end

      if explorer_obj.is_hidden or not explorer_win then require("codediff.ui.explorer").toggle_visibility(explorer_obj) end

      vim.schedule(function()
        local target = get_explorer_win(explorer_obj)
        if target then vim.api.nvim_set_current_win(target) end
      end)
    end

    local function toggle_explorer_sidebar(tabpage)
      local session = lifecycle.get_session(tabpage)
      local explorer_obj = lifecycle.get_explorer(tabpage)
      if not session or not explorer_obj then
        vim.notify("No explorer found for this tab", vim.log.levels.WARN)
        return
      end

      local current_win = vim.api.nvim_get_current_win()
      local explorer_win = get_explorer_win(explorer_obj)

      if explorer_win and current_win == explorer_win and not explorer_obj.is_hidden then
        require("codediff.ui.explorer").toggle_visibility(explorer_obj)

        vim.schedule(function()
          local target = session.viter_explorer_return_win
          if not (target and vim.api.nvim_win_is_valid(target)) or target == explorer_win then
            target = fallback_view_win(session)
          end
          if target then vim.api.nvim_set_current_win(target) end
          session.viter_explorer_return_win = nil
        end)

        return
      end

      focus_explorer_sidebar(tabpage)
    end

    local original_set_tab_keymap = lifecycle._viter_original_set_tab_keymap or lifecycle.set_tab_keymap
    if not lifecycle._viter_explorer_sidebar_keys_wrapped then
      lifecycle._viter_original_set_tab_keymap = original_set_tab_keymap
      lifecycle.set_tab_keymap = function(tabpage, mode, lhs, rhs, map_opts)
        if mode == "n" and lhs == explorer_toggle_key and lifecycle.get_mode(tabpage) == "explorer" then
          rhs = function() toggle_explorer_sidebar(tabpage) end
          map_opts = vim.tbl_extend("force", map_opts or {}, { desc = "Toggle explorer and focus" })
        elseif mode == "n" and lhs == explorer_focus_key and lifecycle.get_mode(tabpage) == "explorer" then
          rhs = function() focus_explorer_sidebar(tabpage) end
          map_opts = vim.tbl_extend("force", map_opts or {}, { desc = "Focus explorer panel" })
        end

        return original_set_tab_keymap(tabpage, mode, lhs, rhs, map_opts)
      end
      lifecycle._viter_explorer_sidebar_keys_wrapped = true
    end

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("viter_codediff_wrap", { clear = true }),
      pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        vim.schedule(function()
          wrap_diff_windows(tabpage)
          consume_continue_landing(tabpage)
          vim.defer_fn(function() wrap_diff_windows(tabpage) end, 80)
        end)
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("viter_codediff_continue", { clear = true }),
      pattern = "CodeDiffFileSelect",
      callback = function(args)
        if not args.data or not args.data.path then return end

        local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
        if not ok then return end

        local session = lifecycle.get_session(args.data.tabpage or vim.api.nvim_get_current_tabpage())
        vim.g.viter_codediff_last_file = args.data.path
        vim.g.viter_codediff_last_root = session and session.git_root or nil
      end,
    })
  end,
}
