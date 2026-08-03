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
      untracked = "normal",
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

    local group = vim.api.nvim_create_augroup("viter_codediff", { clear = true })
    local pending = {}

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
    end

    local function view_ready(tabpage, state)
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
      if not state or state.armed or not vim.api.nvim_tabpage_is_valid(tabpage) or not view_ready(tabpage, state) then
        return
      end

      state.armed = true
      vim.api.nvim_create_autocmd("SafeState", {
        group = group,
        once = true,
        callback = function()
          if pending[tabpage] ~= state or not vim.api.nvim_tabpage_is_valid(tabpage) then return end

          local win = primary_window(tabpage)
          if not win then return end

          if state.line then
            local bufnr = vim.api.nvim_win_get_buf(win)
            local line = math.max(1, math.min(state.line, vim.api.nvim_buf_line_count(bufnr)))
            pcall(vim.api.nvim_win_set_cursor, win, { line, state.col or 0 })
            vim.g.viter_codediff_continue_file = nil
            vim.g.viter_codediff_continue_line = nil
            vim.g.viter_codediff_continue_col = nil
          end

          vim.api.nvim_set_current_win(win)
          vim.cmd "normal! zz"
          refresh_indent_scopes(tabpage)
          pending[tabpage] = nil
        end,
      })
    end

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffOpen",
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        if tabpage then
          vim.g.viter_codediff_last_tab = tabpage
          fix_comment_contrast(tabpage)
        end
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffFileSelect",
      callback = function(args)
        local data = args.data or {}
        if not data.tabpage or type(data.path) ~= "string" then return end
        if data.tabpage then vim.g.viter_codediff_last_tab = data.tabpage end
        if data.path then vim.g.viter_codediff_last_file = data.path end
        fix_comment_contrast(data.tabpage)

        local continue_file = vim.g.viter_codediff_continue_file
        local root = vim.g.viter_codediff_last_root
        local selected = root and data.path and vim.fs.normalize(vim.fs.joinpath(root, data.path))
        pending[data.tabpage] = {
          file = selected,
          relative = data.path,
          line = continue_file and selected == vim.fs.normalize(continue_file) and vim.g.viter_codediff_continue_line
            or nil,
          col = vim.g.viter_codediff_continue_col,
        }
        settle_view(data.tabpage)
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffVirtualFileLoaded",
      callback = function(args)
        local bufnr = args.data and args.data.buf
        if bufnr then vim.b[bufnr].viter_codediff_loaded = true end
        for tabpage in pairs(pending) do
          settle_view(tabpage)
        end
      end,
    })

    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function()
        local tabpage = vim.api.nvim_get_current_tabpage()
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
        if tabpage then pending[tabpage] = nil end
        if vim.g.viter_codediff_last_tab == tabpage then vim.g.viter_codediff_last_tab = nil end
      end,
    })
  end,
}
