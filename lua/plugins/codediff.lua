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
      untracked = "all",
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
    require("codediff").setup(opts)

    -- TEMP MONKEY PATCH: CodeDiff does not persist a manually resized explorer
    -- across hide/show, and an in-flight render can steal focus back after it
    -- is shown. Remove this when the plugin owns both states publicly.
    local explorer_module = require "codediff.ui.explorer"
    local explorer_render = require "codediff.ui.explorer.render"
    local explorer_actions = require "codediff.ui.explorer.actions"
    local history_module = require "codediff.ui.history"
    local history_render = require "codediff.ui.history.render"
    local lifecycle = require "codediff.ui.lifecycle"
    local codediff_config = require "codediff.config"
    local pending = {}
    local settle_timeout_ns = 5 * 1e9

    local function clear_pending(tabpage)
      if not tabpage then return end
      local state = pending[tabpage]
      if state and state.follow_request then require("funcs").finish_codediff_follow(state.follow_request) end
      pending[tabpage] = nil
    end

    -- TEMP MONKEY PATCH: CodeDiff v3's native watcher force-refreshes on
    -- every notification, including its own Git status activity. That loops
    -- through file re-selection and rendering. Keep the existing 500ms
    -- polling fallback, whose unchanged-status check avoids all UI churn.
    local watcher = require "codediff.core.watcher"
    ---@diagnostic disable-next-line: duplicate-set-field
    watcher.subscribe = function()
      return function() end
    end

    -- TEMP MONKEY PATCH: CodeDiff can report a deletion at EOF one line past
    -- the shorter pane. Direct next-hunk moves then retry the unreachable line
    -- forever, while cross-file backward moves fail to land on the last hunk.
    -- Clamp both direct navigation and renderer landings to real buffer lines.
    local navigation = require "codediff.ui.view.navigation"
    local view_render = require "codediff.ui.view.render"
    local establish_scrollbind = view_render.establish_scrollbind
    local function clamp_cursor(winid, cursor)
      if not cursor or not winid or not vim.api.nvim_win_is_valid(winid) then return cursor end
      local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid))
      return { math.max(1, math.min(cursor[1], line_count)), cursor[2] }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    view_render.establish_scrollbind = function(
      original_win,
      modified_win,
      original_buf,
      modified_buf,
      lines_diff,
      original_cursor,
      modified_cursor
    )
      return establish_scrollbind(
        original_win,
        modified_win,
        original_buf,
        modified_buf,
        lines_diff,
        clamp_cursor(original_win, original_cursor),
        clamp_cursor(modified_win, modified_cursor)
      )
    end

    local next_hunk = navigation.next_hunk
    ---@diagnostic disable-next-line: duplicate-set-field
    navigation.next_hunk = function()
      local tabpage = vim.api.nvim_get_current_tabpage()
      local session = lifecycle.get_session(tabpage)
      if not session then return next_hunk() end
      local changes = session.stored_diff_result and session.stored_diff_result.changes
      if type(changes) ~= "table" or #changes == 0 then return next_hunk() end

      local current_buf = vim.api.nvim_get_current_buf()
      local is_original = session.layout ~= "inline" and current_buf == session.original_bufnr
      local is_modified = current_buf == session.modified_bufnr
        or session.result_bufnr and current_buf == session.result_bufnr
      if not is_original and not is_modified then return next_hunk() end

      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      local line_count = vim.api.nvim_buf_line_count(current_buf)
      for index, change in ipairs(changes) do
        local target_line = is_original and change.original.start_line or change.modified.start_line
        if target_line > current_line then
          if target_line <= line_count then break end

          if current_line < line_count then
            vim.api.nvim_win_set_cursor(0, { line_count, 0 })
            vim.cmd "normal! zz"
            vim.api.nvim_echo({ { ("Hunk %d of %d"):format(index, #changes), "None" } }, false, {})
            return true
          end

          if opts.diff.cycle_hunks_across_files then
            session.pending_cursor_landing = "first"
            return navigation.next_file()
          end
          break
        end
      end

      return next_hunk()
    end

    -- Inline rendering keeps its cursor helper private, so carry the same
    -- landing intent through CodeDiffFileSelect and clamp it after rendering.
    local next_file = navigation.next_file
    ---@diagnostic disable-next-line: duplicate-set-field
    navigation.next_file = function()
      local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
      if session and session.pending_cursor_landing then
        session.viter_pending_cursor_landing = session.pending_cursor_landing
      end
      return next_file()
    end
    local prev_file = navigation.prev_file
    ---@diagnostic disable-next-line: duplicate-set-field
    navigation.prev_file = function()
      local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
      if session and session.pending_cursor_landing then
        session.viter_pending_cursor_landing = session.pending_cursor_landing
      end
      return prev_file()
    end

    local function focus_right_diff(tabpage)
      local original_win, modified_win = lifecycle.get_windows(tabpage)
      local winid = modified_win and vim.api.nvim_win_is_valid(modified_win) and modified_win or original_win
      if winid and vim.api.nvim_win_is_valid(winid) then vim.api.nvim_set_current_win(winid) end
    end

    local toggle_visibility = explorer_actions.toggle_visibility
    local function toggle_explorer(explorer)
      local was_hidden = explorer and explorer.is_hidden
      if explorer then clear_pending(explorer.tabpage) end
      local split = explorer and explorer.split
      local winid = split and split.winid
      if explorer and not explorer.is_hidden and winid and vim.api.nvim_win_is_valid(winid) then
        local position = opts.explorer.position or "left"
        local size = position == "bottom" and vim.api.nvim_win_get_height(winid) or vim.api.nvim_win_get_width(winid)
        split._size = size
        codediff_config.options.explorer[position == "bottom" and "height" or "width"] = size
      end
      local result = toggle_visibility(explorer)
      if was_hidden and explorer.winid and vim.api.nvim_win_is_valid(explorer.winid) then
        vim.api.nvim_set_current_win(explorer.winid)
        vim.defer_fn(function()
          if not explorer.is_hidden and explorer.winid and vim.api.nvim_win_is_valid(explorer.winid) then
            vim.api.nvim_set_current_win(explorer.winid)
          end
        end, 150)
      elseif explorer and explorer.tabpage then
        focus_right_diff(explorer.tabpage)
      end
      return result
    end
    explorer_actions.toggle_visibility = toggle_explorer
    explorer_module.toggle_visibility = toggle_explorer

    -- TEMP MONKEY PATCH: CodeDiff currently creates an ungrouped WinResized
    -- autocmd for every explorer/history panel and never deletes it. Capture
    -- only the autocmds created synchronously by each panel's create() and
    -- remove them on CodeDiffClose. Remove this when upstream puts them in a
    -- session group.
    local leaked_resize_autocmds = {}
    local function capture_resize_autocmds(tabpage, create, ...)
      local existing = {}
      for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = "WinResized" }) do
        existing[autocmd.id] = true
      end

      local panel = create(...)
      if tabpage then
        leaked_resize_autocmds[tabpage] = leaked_resize_autocmds[tabpage] or {}
        for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = "WinResized" }) do
          if not existing[autocmd.id] and not autocmd.group then
            table.insert(leaked_resize_autocmds[tabpage], autocmd.id)
          end
        end
      end
      return panel
    end

    local create_explorer = explorer_render.create
    local function create_explorer_with_cleanup(...)
      local tabpage = select(3, ...)
      local explorer = capture_resize_autocmds(tabpage, create_explorer, ...)
      if tabpage then
        -- TEMP MONKEY PATCH: CodeDiff has no configurable context-specific
        -- explorer keys. Keep the diff-pane actions, but give the explorer
        -- familiar navigation and symmetric focus/open behavior.
        local map_options = { noremap = true, silent = true, nowait = true }
        local map_meta = { suspendable = false, priority = 100 }
        local function map(lhs, rhs, desc)
          lifecycle.set_buf_keymap(
            tabpage,
            explorer.bufnr,
            "n",
            lhs,
            rhs,
            vim.tbl_extend("force", map_options, { desc = desc }),
            map_meta
          )
        end

        map("n", function() vim.cmd "normal! k" end, "CodeDiff: previous explorer entry")
        map("e", function() vim.cmd "normal! j" end, "CodeDiff: next explorer entry")
        map("o", function() focus_right_diff(tabpage) end, "CodeDiff: focus right diff pane")
        map("i", function()
          local enter = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
          vim.api.nvim_feedkeys(enter, "m", false)
        end, "CodeDiff: select/toggle entry")
      end
      return explorer
    end
    explorer_render.create = create_explorer_with_cleanup
    explorer_module.create = create_explorer_with_cleanup

    local create_history = history_render.create
    local function create_history_with_cleanup(...) return capture_resize_autocmds(select(3, ...), create_history, ...) end
    history_render.create = create_history_with_cleanup
    history_module.create = create_history_with_cleanup

    local group = vim.api.nvim_create_augroup("viter_codediff", { clear = true })

    local function remap_highlight(win, from, to)
      local mappings = vim.split(vim.wo[win].winhighlight, ",", { plain = true, trimempty = true })
      local prefix = from .. ":"
      for index, mapping in ipairs(mappings) do
        if vim.startswith(mapping, prefix) then
          mappings[index] = prefix .. to
          vim.wo[win].winhighlight = table.concat(mappings, ",")
          return
        end
      end
      table.insert(mappings, prefix .. to)
      vim.wo[win].winhighlight = table.concat(mappings, ",")
    end

    local function fix_comment_contrast(tabpage)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.w[win].codediff_restore == 1 then
          remap_highlight(win, "Comment", "CodeDiffComment")
          remap_highlight(win, "@comment", "CodeDiffComment")
        end
      end
    end

    local function primary_window(tabpage)
      if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then return end

      -- Deleted files only have a left pane; return right when it comes back.
      local primary
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.w[win].codediff_restore == 1 then
          if not primary or vim.api.nvim_win_get_position(win)[2] > vim.api.nvim_win_get_position(primary)[2] then
            primary = win
          end
        end
      end
      return primary
    end

    local function refresh_indent_scopes(tabpage)
      if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.w[win].codediff_restore == 1 then
          vim.api.nvim_win_call(
            win,
            function()
              vim.api.nvim_exec_autocmds("CursorMoved", {
                buffer = vim.api.nvim_get_current_buf(),
                modeline = false,
              })
            end
          )
        end
      end
      vim.cmd "redraw"
    end

    local indent_refresh_scheduled = {}
    local function schedule_indent_refresh(tabpage)
      if not tabpage or indent_refresh_scheduled[tabpage] then return end
      indent_refresh_scheduled[tabpage] = true
      vim.schedule(function()
        indent_refresh_scheduled[tabpage] = nil
        refresh_indent_scopes(tabpage)
      end)
    end

    local function view_ready(tabpage, state)
      local session = lifecycle.get_session(tabpage)
      if session and session.layout == "inline" and session.stored_diff_result then
        local original = session.original and session.original.relative
        local modified = session.modified and session.modified.relative
        if original == state.relative or modified == state.relative then return true end
      end

      local selected = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.w[win].codediff_restore == 1 then
          local bufnr = vim.api.nvim_win_get_buf(win)
          local name = vim.api.nvim_buf_get_name(bufnr)
          if vim.startswith(name, "codediff://") then
            if not vim.b[bufnr].viter_codediff_loaded then return false end
            selected = selected or vim.endswith(name, "/" .. state.relative)
          else
            selected = selected
              or vim.endswith(name, "/" .. state.relative)
              or (state.file and vim.fs.normalize(name) == state.file)
          end
        end
      end
      return selected
    end

    local function settle_view(tabpage)
      local state = pending[tabpage]
      if not state or state.armed or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
      if state.follow_request and state.follow_request.timed_out then
        pending[tabpage] = nil
        return
      end
      if state.follow_request and state.follow_request.deadline <= vim.uv.hrtime() then
        state.follow_request.timed_out = true
        clear_pending(tabpage)
        vim.notify("Timed out waiting for CodeDiff after 5 seconds", vim.log.levels.WARN)
        return
      end
      if state.deadline and state.deadline <= vim.uv.hrtime() then
        clear_pending(tabpage)
        vim.notify("Timed out waiting for the CodeDiff file after 5 seconds", vim.log.levels.WARN)
        return
      end
      if not view_ready(tabpage, state) then
        if state.follow_change or state.cursor_landing then vim.defer_fn(function() settle_view(tabpage) end, 10) end
        return
      end

      if state.follow_change then
        local session = lifecycle.get_session(tabpage)
        if not session or not session.stored_diff_result or type(session.stored_diff_result.changes) ~= "table" then
          vim.defer_fn(function() settle_view(tabpage) end, 10)
          return
        end
      end

      state.armed = true
      local function restore_position()
        if pending[tabpage] ~= state or not vim.api.nvim_tabpage_is_valid(tabpage) then return end

        local win = primary_window(tabpage)
        if not win then return end

        local line = state.line
        if state.cursor_landing then
          local session = lifecycle.get_session(tabpage)
          local changes = session and session.stored_diff_result and session.stored_diff_result.changes or {}
          local hunk = state.cursor_landing == "last" and changes[#changes] or changes[1]
          if session and hunk then
            local bufnr = vim.api.nvim_win_get_buf(win)
            local is_original = session.layout ~= "inline" and bufnr == session.original_bufnr
            line = is_original and hunk.original.start_line or hunk.modified.start_line
          end
        end
        if state.follow_change and line then
          local session = lifecycle.get_session(tabpage)
          local changes = session and session.stored_diff_result and session.stored_diff_result.changes or {}
          local is_changed_line = false
          for _, change in ipairs(changes) do
            local start_line = change.modified.start_line
            local end_line = change.modified.end_line
            if (line >= start_line and line < end_line) or (start_line == end_line and line == start_line) then
              is_changed_line = true
              break
            end
          end
          if not is_changed_line then line = nil end
        end

        if line then
          local bufnr = vim.api.nvim_win_get_buf(win)
          line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(bufnr)))
          pcall(vim.api.nvim_win_set_cursor, win, { line, state.col or 0 })
          vim.g.viter_codediff_continue_file = nil
          vim.g.viter_codediff_continue_line = nil
          vim.g.viter_codediff_continue_col = nil
        end

        vim.api.nvim_set_current_win(win)
        vim.cmd "normal! zz"
        schedule_indent_refresh(tabpage)
        if state.follow_request then require("funcs").finish_codediff_follow(state.follow_request) end
        pending[tabpage] = nil
      end

      if state.follow_change or state.cursor_landing then
        vim.schedule(restore_position)
      else
        vim.api.nvim_create_autocmd("SafeState", {
          group = group,
          once = true,
          callback = restore_position,
        })
      end
    end

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffOpen",
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        if tabpage then
          vim.g.viter_codediff_last_tab = tabpage
          fix_comment_contrast(tabpage)
          schedule_indent_refresh(tabpage)
          vim.schedule(function() require("funcs").select_codediff_follow(tabpage) end)
        end
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffFileSelect",
      callback = function(args)
        local data = args.data or {}
        if not data.tabpage or type(data.path) ~= "string" then return end
        vim.g.viter_codediff_last_tab = data.tabpage
        vim.g.viter_codediff_last_file = data.path
        fix_comment_contrast(data.tabpage)
        schedule_indent_refresh(data.tabpage)

        local continue_file = vim.g.viter_codediff_continue_file
        local root = vim.g.viter_codediff_last_root
        local selected = root and vim.fs.normalize(vim.fs.joinpath(root, data.path))
        local follow = require("funcs").codediff_follow_position(data.tabpage, data.path)
        local session = lifecycle.get_session(data.tabpage)
        local cursor_landing = session and session.viter_pending_cursor_landing
        if session then session.viter_pending_cursor_landing = nil end
        pending[data.tabpage] = {
          file = selected,
          relative = data.path,
          line = follow and follow.line
            or continue_file and selected == vim.fs.normalize(continue_file) and vim.g.viter_codediff_continue_line
            or nil,
          col = vim.g.viter_codediff_continue_col,
          follow_change = follow ~= nil,
          follow_request = follow and follow.request,
          cursor_landing = cursor_landing,
          deadline = not follow and cursor_landing and (vim.uv.hrtime() + settle_timeout_ns) or nil,
        }
        settle_view(data.tabpage)
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffVirtualFileLoaded",
      callback = function(args)
        local bufnr = args.data and args.data.buf
        if bufnr then
          vim.b[bufnr].viter_codediff_loaded = true
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
              schedule_indent_refresh(vim.api.nvim_win_get_tabpage(win))
            end
          end
        end
        for tabpage in pairs(pending) do
          settle_view(tabpage)
        end
      end,
    })

    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        if vim.w.codediff_restore == 1 then schedule_indent_refresh(tabpage) end
        if pending[tabpage] then settle_view(tabpage) end
      end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function(args)
        local diff_tab = vim.g.viter_codediff_last_tab
        if
          type(diff_tab) ~= "number"
          or not vim.api.nvim_tabpage_is_valid(diff_tab)
          or vim.api.nvim_get_current_tabpage() == diff_tab
        then
          return
        end

        local root = vim.g.viter_codediff_last_root
        local relative = vim.g.viter_codediff_last_file
        if type(root) ~= "string" or type(relative) ~= "string" then return end

        local expected = vim.fs.normalize(vim.fs.joinpath(root, relative))
        if vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf)) ~= expected then return end

        local win = vim.api.nvim_get_current_win()
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == args.buf then
            vim.api.nvim_win_call(win, function() vim.cmd "normal! zz" end)
          end
        end)
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffClose",
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        if tabpage then
          for _, autocmd in ipairs(leaked_resize_autocmds[tabpage] or {}) do
            pcall(vim.api.nvim_del_autocmd, autocmd)
          end
          leaked_resize_autocmds[tabpage] = nil
          indent_refresh_scheduled[tabpage] = nil
        end
        clear_pending(tabpage)
        if vim.g.viter_codediff_last_tab == tabpage then vim.g.viter_codediff_last_tab = nil end
      end,
    })
  end,
}
