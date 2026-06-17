---@type LazySpec
return {
  {
    "syaiful6/koka.nvim",
    branch = "develop",
    ft = "koka",
    init = function()
      vim.filetype.add {
        extension = {
          kk = "koka",
        },
      }
    end,
    config = function()
      local group = vim.api.nvim_create_augroup("viter_koka", { clear = true })

      local function setup_koka_buffer(bufnr)
        bufnr = bufnr or vim.api.nvim_get_current_buf()

        local map = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc }) end

        map("<leader>kb", "<cmd>Koka build<cr>", "Koka build")
        map("<leader>kr", "<cmd>Koka run<cr>", "Koka run")
        map("<leader>ki", "<cmd>Koka config<cr>", "Koka config")
        map("<leader>kR", "<cmd>Koka lsp restart<cr>", "Koka LSP restart")
        map("<leader>kL", "<cmd>Koka refresh_codelens<cr>", "Koka refresh codelens")
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "koka",
        callback = function(args) setup_koka_buffer(args.buf) end,
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not client then return end
          if not client.name:lower():find("koka", 1, true) then return end

          -- Kill the noisy semantic-token request path.
          client.server_capabilities.semanticTokensProvider = nil
          pcall(vim.lsp.semantic_tokens.stop, args.buf, client.id)
        end,
      })

      if vim.bo.filetype == "koka" then setup_koka_buffer(0) end
    end,
  },
}
