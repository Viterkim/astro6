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

    local function diff_window(tabpage)
      if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then return end

      local current = vim.api.nvim_get_current_win()
      local fallback
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if filetype ~= "codediff-explorer" and filetype ~= "codediff-history" then
          if win == current then return win end
          if not fallback or vim.api.nvim_win_get_position(win)[2] > vim.api.nvim_win_get_position(fallback)[2] then
            fallback = win
          end
        end
      end
      return fallback
    end

    local function settle_view(tabpage)
      vim.schedule(function()
        vim.schedule(function()
          local state = pending[tabpage]
          if not state or not vim.api.nvim_tabpage_is_valid(tabpage) then return end

          for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
            local bufnr = vim.api.nvim_win_get_buf(window)
            if vim.startswith(vim.api.nvim_buf_get_name(bufnr), "codediff://") then
              if not vim.b[bufnr].viter_codediff_loaded then return end
            end
          end
          local win = diff_window(tabpage)
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
          pending[tabpage] = nil
        end)
      end)
    end

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffOpen",
      callback = function(args)
        local tabpage = args.data and args.data.tabpage
        if tabpage then vim.g.viter_codediff_last_tab = tabpage end
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffFileSelect",
      callback = function(args)
        local data = args.data or {}
        if not data.tabpage then return end
        if data.tabpage then vim.g.viter_codediff_last_tab = data.tabpage end
        if data.path then vim.g.viter_codediff_last_file = data.path end

        local continue_file = vim.g.viter_codediff_continue_file
        local root = vim.g.viter_codediff_last_root
        local selected = root and data.path and vim.fs.normalize(vim.fs.joinpath(root, data.path))
        pending[data.tabpage] = {
          line = continue_file and selected == vim.fs.normalize(continue_file) and vim.g.viter_codediff_continue_line
            or nil,
          col = vim.g.viter_codediff_continue_col,
        }
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
