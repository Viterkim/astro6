---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = function(_, opts)
      local is_ssh = vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT
      local in_tmux = vim.env.TMUX ~= nil

      opts = opts or {}
      opts.options = opts.options or {}
      opts.options.opt = opts.options.opt or {}

      -- Over SSH, keep normal Vim registers.
      -- That means p stays normal Vim paste, not clipboard paste.
      if is_ssh and not in_tmux then opts.options.opt.clipboard = "" end

      return opts
    end,
    init = function()
      local is_ssh = vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT
      local in_tmux = vim.env.TMUX ~= nil
      if not is_ssh or in_tmux then return end

      local copy_plus = require("vim.ui.clipboard.osc52").copy "+"
      local group = vim.api.nvim_create_augroup("ssh_osc52_yank", { clear = true })

      vim.api.nvim_create_autocmd("TextYankPost", {
        group = group,
        pattern = "*",
        callback = function()
          local ev = vim.deepcopy(vim.v.event)
          if ev.operator ~= "y" then return end
          ---@diagnostic disable-next-line: redundant-parameter
          copy_plus(ev.regcontents, ev.regtype)
        end,
      })
    end,
  },
}
