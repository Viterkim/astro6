---@type LazySpec
return {
  "esmuellert/codediff.nvim",
  -- Keep the UI patches lazy until a CodeDiff command is used.
  event = function() return {} end,
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
    local navigation = require "codediff.ui.view.navigation"
    local refresh = require "codediff.ui.refresh"
    local view_render = require "codediff.ui.view.render"
    local codediff_config = require "codediff.config"
    local pending = {}

    -- Panel options must stay local or new editor windows inherit the
    -- explorer's missing numbers and signs. Upstream issue #579.
    local Split = require "codediff.ui.lib.split"
    function Split:_apply_win_options()
      if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then return end
      for name, value in pairs(self._win_options) do
        vim.api.nvim_set_option_value(name, value, { win = self.winid, scope = "local" })
      end
    end

    -- The diff panes also change the inheritable list/cursorline defaults.
    -- Keep their local appearance while handing normal windows their defaults.
    local view = require "codediff.ui.view"
    local create_view = view.create
    view.create = function(...)
      local defaults = {}
      for _, name in ipairs { "list", "cursorline" } do
        defaults[name] = vim.api.nvim_get_option_value(name, { win = 0, scope = "global" })
      end

      local result = create_view(...)
      local win = result and (result.modified_win or result.original_win)
      if win and vim.api.nvim_win_is_valid(win) then
        for _, pane in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))) do
          for name, value in pairs(defaults) do
            vim.api.nvim_set_option_value(name, value, { win = pane, scope = "global" })
          end
        end
      end
      return result
    end

    -- CodeDiff adds leader mappings after WhichKey attached to the buffer.
    -- Rebuild its trigger after mapping changes, including tab restoration.
    -- Remove when upstream PR #586 is included.
    local keymap_slots = require "codediff.keymap.slots"
    local which_key_pending = {}
    for _, action in ipairs { "claim", "release", "set_active" } do
      local change_mapping = keymap_slots[action]
      keymap_slots[action] = function(owner, bufnr, ...)
        local result = change_mapping(owner, bufnr, ...)
        local which_key = package.loaded["which-key.buf"]
        if bufnr and which_key and require("which-key.config").loaded and not which_key_pending[bufnr] then
          which_key_pending[bufnr] = true
          vim.schedule(function()
            which_key_pending[bufnr] = nil
            if vim.api.nvim_buf_is_valid(bufnr) then
              which_key.clear { buf = bufnr }
              which_key.get { buf = bufnr, mode = "n" }
            end
          end)
        end
        return result
      end
    end

    -- A directory symlink is one Git entry, but :edit opens its target as a
    -- directory and Neo-tree replaces the diff pane. Skip those entries.
    local git = require "codediff.core.git"
    local function without_directory_links(root, callback)
      return function(err, status)
        if status then
          for _, group in ipairs { "unstaged", "staged", "conflicts" } do
            if status[group] then
              status[group] = vim.tbl_filter(function(file)
                local path = vim.fs.joinpath(root, file.path)
                local link = vim.uv.fs_lstat(path)
                local target = link and link.type == "link" and vim.uv.fs_stat(path)
                return not (target and target.type == "directory")
              end, status[group])
            end
          end
        end
        callback(err, status)
      end
    end
    local get_status = git.get_status_with_line_stats
    git.get_status_with_line_stats = function(root, callback, ...)
      return get_status(root, without_directory_links(root, callback), ...)
    end
    local get_diff_revision = git.get_diff_revision_with_line_stats
    git.get_diff_revision_with_line_stats = function(revision, root, callback, ...)
      return get_diff_revision(revision, root, without_directory_links(root, callback), ...)
    end
    local get_diff_revisions = git.get_diff_revisions_with_line_stats
    git.get_diff_revisions_with_line_stats = function(original, modified, root, callback, ...)
      return get_diff_revisions(original, modified, root, without_directory_links(root, callback), ...)
    end
    local get_diff_staged = git.get_diff_staged
    git.get_diff_staged = function(revision, root, callback, ...)
      return get_diff_staged(revision, root, without_directory_links(root, callback), ...)
    end

    -- :edit on a revision's path can ask to discard changes when the editor
    -- already has that file open. Switch to its buffer and keep those edits.
    local panes = require "codediff.ui.view.actions.panes"
    local open_in_prev_tab = panes.open_in_prev_tab
    panes.open_in_prev_tab = function(ctx)
      local preview = vim.api.nvim_get_current_buf()
      local original, modified = lifecycle.get_paths(ctx.tabpage)
      local path = preview == ctx.modified_bufnr and modified or preview == ctx.original_bufnr and original
      if not path or path.absolute == "" then return open_in_prev_tab(ctx) end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local editor_tab
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if tab == ctx.tabpage then break end
        if not lifecycle.get_session(tab) then editor_tab = tab end
      end
      if editor_tab then
        vim.api.nvim_set_current_tabpage(editor_tab)
      else
        vim.cmd "-tabnew"
      end

      local buf = vim.fn.bufadd(path.absolute)
      if vim.api.nvim_get_current_buf() ~= buf then vim.cmd.buffer(buf) end
      if vim.api.nvim_get_current_buf() ~= buf then return end

      vim.bo[buf].buflisted = true
      if not vim.bo[buf].modified and vim.fn.filereadable(path.absolute) == 1 then
        vim.cmd("silent checktime " .. buf)
      end
      cursor[1] = math.min(cursor[1], vim.api.nvim_buf_line_count(buf))
      vim.api.nvim_win_set_cursor(0, cursor)
      vim.cmd "normal! zz"
    end

    -- A one-file panel selects the same file when cycling. Report that
    -- no file changed so hunk navigation can wrap within the current file.
    local panel_data = require "codediff.ui.refresh.panel"
    local function file_navigation(move)
      return function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        local session = lifecycle.get_session(tabpage)
        local panel = lifecycle.get_panel(tabpage)
        if not panel then return move() end

        local selection = panel.data.current_selection
        move()
        local changed = not panel_data.same_selection(selection, panel.data.current_selection)
        if not changed and session then session.pending_cursor_landing = nil end
        return changed
      end
    end
    navigation.next_file = file_navigation(navigation.next_file)
    navigation.prev_file = file_navigation(navigation.prev_file)

    -- A cross-file hunk jump changes the explorer selection before the new
    -- diff has finished loading. Another e/n in that gap can navigate using
    -- the previous file's hunks and leave the selection and view out of sync.
    local hunk_moves = {}
    local next_hunk, prev_hunk = navigation.next_hunk, navigation.prev_hunk
    local function drain_hunk_moves(tabpage)
      local moves = hunk_moves[tabpage]
      if not moves or moves.draining then return end
      if not vim.api.nvim_tabpage_is_valid(tabpage) or vim.api.nvim_get_current_tabpage() ~= tabpage then
        hunk_moves[tabpage] = nil
        return
      end
      local session = lifecycle.get_session(tabpage)
      if not session then
        hunk_moves[tabpage] = nil
        return
      end
      if (session.refresh and session.refresh.loading) or not session.stored_diff_result then return end

      moves.draining = true
      while #moves.queue > 0 do
        local next_direction = table.remove(moves.queue, 1)
        if next_direction == "next" then next_hunk() else prev_hunk() end
        if (session.refresh and session.refresh.loading) or not session.stored_diff_result then break end
      end
      moves.draining = false
      if #moves.queue == 0 then hunk_moves[tabpage] = nil end
    end
    local function move_hunk(direction)
      local tabpage = vim.api.nvim_get_current_tabpage()
      local moves = hunk_moves[tabpage]
      if not moves then
        moves = { queue = {} }
        hunk_moves[tabpage] = moves
      end
      table.insert(moves.queue, direction)
      drain_hunk_moves(tabpage)
    end
    navigation.next_hunk = function() move_hunk "next" end
    navigation.prev_hunk = function() move_hunk "prev" end

    -- TEMP MONKEY PATCH: CodeDiff forces wrap off while rendering side-by-side
    -- views. Re-enable it after scrollbind is established so selecting or
    -- reloading a file does not leave the diff panes unwrapped.
    -- Wrapped rows can still drift against its virtual filler lines (#50).
    local function enable_word_wrap(win)
      if not win or not vim.api.nvim_win_is_valid(win) then return end
      vim.wo[win].wrap = true
      vim.wo[win].linebreak = true
      vim.wo[win].breakindent = true
    end

    local establish_scrollbind = view_render.establish_scrollbind
    view_render.establish_scrollbind = function(original_win, modified_win, ...)
      local result = establish_scrollbind(original_win, modified_win, ...)
      enable_word_wrap(original_win)
      enable_word_wrap(modified_win)
      return result
    end

    local function wrap_diff_windows(tabpage)
      if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.w[win].codediff_restore == 1 then enable_word_wrap(win) end
      end
    end

    local function clear_pending(tabpage)
      if not tabpage then return end
      local state = pending[tabpage]
      if state and state.follow_request then require("funcs").finish_codediff_follow(state.follow_request) end
      pending[tabpage] = nil
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
      local tabpage = select(2, ...)
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
    local function create_history_with_cleanup(...) return capture_resize_autocmds(select(2, ...), create_history, ...) end
    history_render.create = create_history_with_cleanup
    history_module.create = create_history_with_cleanup

    local group = vim.api.nvim_create_augroup("viter_codediff", { clear = true })
    local wrap_enter_autocmds = {}

    -- Native scrollbind only follows the current window. A mouse wheel can
    -- scroll another pane without focusing it. Upstream PR #570.
    vim.api.nvim_create_autocmd("WinScrolled", {
      group = group,
      callback = function()
        local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
        if not session then return end

        local focused = vim.api.nvim_get_current_win()
        for id, delta in pairs(vim.v.event) do
          local win = tonumber(id)
          local pane = win and (win == session.original_win or win == session.modified_win or win == session.result_win)
          if
            pane
            and win ~= focused
            and delta.topline ~= 0
            and vim.api.nvim_win_is_valid(win)
            and vim.wo[win].scrollbind
          then
            vim.api.nvim_win_call(win, function() vim.cmd [[execute "normal! \<Ignore>"]] end)
          end
        end
      end,
    })

    local function keep_diff_windows_wrapped(tabpage)
      if wrap_enter_autocmds[tabpage] then pcall(vim.api.nvim_del_autocmd, wrap_enter_autocmds[tabpage]) end
      wrap_enter_autocmds[tabpage] = vim.api.nvim_create_autocmd(
        { "BufWinEnter", "BufEnter", "WinEnter", "FileType" },
        {
          group = group,
          callback = function()
            if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
            local win = vim.api.nvim_get_current_win()
            if vim.w[win].codediff_restore ~= 1 then return end
            enable_word_wrap(win)

            local session = lifecycle.get_session(tabpage)
            if not session or not (session.refresh and session.refresh.loading) then return end

            -- The panes get their new buffers before CodeDiff finishes loading
            -- and installs its mappings. Keep hunk keys connected to the queue.
            local keys = require("codediff.keymap.resolve").keymaps_for "view"
            local buf = vim.api.nvim_get_current_buf()
            for action, desc in pairs { next_hunk = "Next hunk", prev_hunk = "Previous hunk" } do
              if not lifecycle.owns_keymap(tabpage, keys[action], "n", buf) then
                lifecycle.set_buf_keymap(tabpage, buf, "n", keys[action], navigation[action], {
                  desc = desc,
                  silent = true,
                  nowait = true,
                })
              end
            end
          end,
        }
      )
    end

    -- Bare file comparisons create their session after CodeDiffOpen. Register
    -- after the session's own autocmds so they cannot turn wrap off again.
    local create_session = lifecycle.create_session
    lifecycle.create_session = function(tabpage, ...)
      local result = create_session(tabpage, ...)
      keep_diff_windows_wrapped(tabpage)
      return result
    end

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
      if tabpage ~= vim.api.nvim_get_current_tabpage() then return end
      local snacks = rawget(_G, "Snacks")
      if
        snacks
        and not package.loaded["snacks.indent"]
        and snacks.config.indent.enabled
        and vim.g.snacks_indent ~= false
      then
        -- Revision buffers use BufReadCmd, so Snacks never sees the
        -- BufReadPost event that normally starts its indent renderer.
        snacks.indent.enable()
      end

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

    -- CodeDiff publishes the rendered diff through ready(). Its scheduled
    -- callback clears loading first, then this callback refreshes the panes
    -- and resumes any hunk keys pressed during the file change.
    local ready = refresh.ready
    refresh.ready = function(tabpage)
      local result = ready(tabpage)
      vim.schedule(function()
        local session = lifecycle.get_session(tabpage)
        if not session or (session.refresh and session.refresh.loading) then return end
        wrap_diff_windows(tabpage)
        refresh_indent_scopes(tabpage)
        -- The first draw can precede the final diff-window setup, leaving
        -- Tree-sitter captures absent from the displayed right pane.
        if vim.api.nvim_get_current_tabpage() == tabpage then vim.cmd "redraw!" end
        drain_hunk_moves(tabpage)
      end)
      return result
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
      if state.deadline <= vim.uv.hrtime() then
        if state.follow_request then state.follow_request.timed_out = true end
        clear_pending(tabpage)
        vim.notify("Timed out waiting for CodeDiff after 5 seconds", vim.log.levels.WARN)
        return
      end
      if not view_ready(tabpage, state) then
        vim.defer_fn(function() settle_view(tabpage) end, 10)
        return
      end

      local session = lifecycle.get_session(tabpage)
      local rendered_diff = session and session.stored_diff_result
      if not rendered_diff or type(rendered_diff.changes) ~= "table" then
        vim.defer_fn(function() settle_view(tabpage) end, 10)
        return
      end

      state.armed = true
      local function restore_position()
        if pending[tabpage] ~= state or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
        local current_session = lifecycle.get_session(tabpage)
        if
          not current_session
          or current_session.stored_diff_result ~= rendered_diff
          or not view_ready(tabpage, state)
        then
          state.armed = false
          settle_view(tabpage)
          return
        end
        if vim.api.nvim_get_current_tabpage() ~= tabpage then
          clear_pending(tabpage)
          return
        end

        local original_win, modified_win = lifecycle.get_windows(tabpage)
        local win = state.side == "original" and original_win or state.side == "modified" and modified_win
        if not win or not vim.api.nvim_win_is_valid(win) then win = primary_window(tabpage) end
        if not win then return end

        local line = state.line
        -- Enter the pane before restoring its cursor and centering the view.
        vim.api.nvim_set_current_win(win)
        if line then
          local bufnr = vim.api.nvim_win_get_buf(win)
          line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(bufnr)))
          pcall(vim.api.nvim_win_set_cursor, win, { line, state.col or 0 })
        end

        vim.cmd "normal! zz"
        wrap_diff_windows(tabpage)
        schedule_indent_refresh(tabpage)
        if state.follow_request then require("funcs").finish_codediff_follow(state.follow_request) end
        pending[tabpage] = nil
      end

      -- Virtual-file loading can queue multiple renders. Wait for the result
      -- to remain stable before restoring; SafeState may not fire after async IO.
      vim.defer_fn(restore_position, 50)
    end

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffOpen",
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        if tabpage then
          vim.g.viter_codediff_last_tab = tabpage
          keep_diff_windows_wrapped(tabpage)
          fix_comment_contrast(tabpage)
          schedule_indent_refresh(tabpage)
          vim.schedule(function()
            wrap_diff_windows(tabpage)
            require("funcs").select_codediff_follow(tabpage)
          end)
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
        fix_comment_contrast(data.tabpage)
        schedule_indent_refresh(data.tabpage)
        vim.schedule(function() wrap_diff_windows(data.tabpage) end)

        local session = lifecycle.get_session(data.tabpage)
        local root = session and session.git_root
        local selected = root and vim.fs.normalize(vim.fs.joinpath(root, data.path))
        local follow = require("funcs").codediff_follow_position(data.tabpage, data.path)
        if not follow then
          clear_pending(data.tabpage)
          return
        end
        pending[data.tabpage] = {
          deadline = follow.request.deadline,
          file = selected,
          relative = data.path,
          line = follow.line,
          col = follow.request.col,
          side = follow.request.side,
          follow_request = follow.request,
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
              local tabpage = vim.api.nvim_win_get_tabpage(win)
              schedule_indent_refresh(tabpage)
              vim.schedule(function() wrap_diff_windows(tabpage) end)
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
        if vim.w.codediff_restore == 1 then
          wrap_diff_windows(tabpage)
          schedule_indent_refresh(tabpage)
        end
        if pending[tabpage] then settle_view(tabpage) end
      end,
    })

    -- Remember the position if the tab is closed. Ignore intermediate
    -- window switches while CodeDiff is still selecting/rendering a file.
    vim.api.nvim_create_autocmd({ "WinLeave", "TabLeave" }, {
      group = group,
      callback = function(args)
        local tabpage = vim.api.nvim_get_current_tabpage()
        if args.event == "TabLeave" then hunk_moves[tabpage] = nil end
        local session = lifecycle.get_session(tabpage)
        if not pending[tabpage] and not (session and session.refresh and session.refresh.loading) then
          require("funcs").remember_codediff_position(tabpage, vim.api.nvim_get_current_win())
        end
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffClose",
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        if tabpage then
          hunk_moves[tabpage] = nil
          if wrap_enter_autocmds[tabpage] then pcall(vim.api.nvim_del_autocmd, wrap_enter_autocmds[tabpage]) end
          wrap_enter_autocmds[tabpage] = nil
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
