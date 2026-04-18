---@type LazySpec
return {
  "AstroNvim/astrocore",
  opts = {
    mappings = {
      n = {
        -- Own
        ["j"] = {
          function()
            local key = vim.api.nvim_replace_termcodes("<C-o>", true, false, true)
            vim.api.nvim_feedkeys(key, "n", false)
          end,
          desc = "Jump Back",
        },
        ["J"] = {
          function()
            local key = vim.api.nvim_replace_termcodes("<C-i>", true, false, true)
            vim.api.nvim_feedkeys(key, "n", false)
          end,
          desc = "Jump Forward",
        },
        ["l"] = { "o<esc>", desc = "New Line Below" },
        ["r"] = { "<C-u>", desc = "Page Up" },
        ["s"] = { "<C-d>", desc = "Page Down" },
        ["S"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["R"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Prev buffer" },
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },
        ["gd"] = { function() vim.lsp.buf.definition() end, desc = "LSP Definition" },
        ["gy"] = { function() vim.lsp.buf.type_definition() end, desc = "LSP Type Definition" },
        ["grr"] = { function() require("snacks").picker.lsp_references() end, desc = "Show References" },
        ["gI"] = { function() vim.lsp.buf.implementation() end, desc = "LSP Implementation" },
        ["ø"] = { function() vim.lsp.buf.hover() end, desc = "Hover symbol details" },

        -- leader F (search, literal, simple)
        ["<leader>F"] = { desc = "Literal search" },
        ["<leader>Ff"] = {
          function() require("snacks").picker.files() end,
          desc = "Find in file names",
        },
        ["<leader>Fw"] = {
          function() require("snacks").picker.grep { regex = false } end,
          desc = "Find words in files literally",
        },
        ["<leader>Fc"] = {
          function() require("snacks").picker.grep_word { regex = false } end,
          desc = "Find current word literally",
        },

        -- leader i
        ["<leader>iæ"] = {
          function()
            local bufnr = 0
            local enabled = vim.diagnostic.is_enabled { bufnr = bufnr }
            vim.diagnostic.enable(not enabled, { bufnr = bufnr })
            vim.notify("Diagnostics " .. (enabled and "OFF" or "ON") .. " for current buffer")
          end,
          desc = "Toggle Diagnostics",
        },
        ["<leader>if"] = { function() vim.lsp.buf.code_action() end, desc = "LSP Fixes" },
        ["<leader>id"] = { function() vim.diagnostic.open_float() end, desc = "Float diagnostics" },
        ["<leader>ic"] = {
          function()
            vim.diagnostic.open_float()
            vim.diagnostic.open_float()
            vim.cmd "normal! ggVGy"
            vim.cmd "close"
          end,
          desc = "Copy diagnostics",
        },
        ["<leader>ii"] = { function() require("snacks").picker.diagnostics() end, desc = "All diagnostics" },
        ["<leader>im"] = {
          function()
            local rm = require "render-markdown"
            rm.toggle()
            vim.notify("RenderMarkdown: " .. (rm.get() and "ON" or "OFF"))
          end,
          desc = "Toggle RenderMarkdown",
        },
        ["<leader>ir"] = { function() require("snacks").picker.lsp_references() end, desc = "Show References" },
        ["<leader>ff"] = { function() require("snacks").picker.files() end, desc = "Find Files" },
        ["<leader>fw"] = { function() require("snacks").picker.grep() end, desc = "Find Words" },
        ["<leader>iy"] = { "<cmd>let @+=expand('%:~:.')<cr>", desc = "Copy relative path" },
        ["<leader>ix"] = { "<cmd>e ++ff=unix<cr>", desc = "Fix windows endlines" },
        ["<leader>ib"] = { "<cmd>RustLsp debug<cr>", desc = "Debug Function" },
        ["<leader>ip"] = { "<cmd>AerialPrev<cr><cmd>RustLsp debug<cr>", desc = "Debug Prev Func" },
        ["<leader>io"] = { function() require("crates").show_features_popup() end, desc = "Crate Features" },
        ["<leader>iu"] = { "<cmd>AerialNavOpen<cr>", desc = "Aerial Nav" },
        ["<leader>is"] = {
          "<cmd>AerialPrev<cr><cmd>RustLsp hover actions<cr><cmd>RustLsp hover actions<cr>",
          desc = "Hover Actions",
        },
        ["<leader>it"] = {
          function()
            vim.lsp.buf.hover()
            vim.lsp.buf.hover()
          end,
          desc = "Hover Enter",
        },

        -- leader s (fixes / convenience)
        ["<leader>s"] = { desc = "Fixes" },
        ["<leader>sf"] = {
          function() require("funcs").rust_fill_match_arms_smart() end,
          desc = "Rust fill match arms",
        },
        ["<leader>su"] = {
          function() require("funcs").rust_remove_unused_imports_this_file() end,
          desc = "Rust remove unused imports",
        },
        ["<leader>sn"] = {
          function() require("funcs").rename_save_and_cleanup() end,
          desc = "Rename, save all, close new buffers",
        },
        ["<leader>st"] = { "V$%", desc = "Select block to matching brace" },
        ["<leader>ss"] = {
          function() require("funcs").select_whole_file() end,
          desc = "Select whole file",
        },
        ["<leader>sw"] = {
          function() require("funcs").strip_trailing_whitespace_all_buffers() end,
          desc = "Strip trailing whitespace (all buffers)",
        },
        ["<leader>sW"] = {
          function() require("funcs").strip_trailing_whitespace_current_buffer() end,
          desc = "Strip trailing whitespace (current buffer)",
        },

        -- session
        ["<leader>S"] = { desc = "Session" },
        ["<leader>Sq"] = {
          function() require("funcs").save_session_and_quit() end,
          desc = "Save session and quit",
        },

        -- leader other
        ["<leader>ti"] = { function() require("neotest").output.open { enter = true } end, desc = "Neotest Output" },
        ["<leader>q"] = { "<cmd>q<CR>", desc = "Quit window" },
        ["<leader>0"] = {
          function() require("funcs").sudoku_quit() end,
          desc = "Nuke all windows",
        },

        -- leader , spectre
        ["<leader>,"] = { desc = "Spectre" },
        ["<leader>,a"] = { '<cmd>lua require("spectre").open()<CR>', desc = "Spectre" },
        ["<leader>,p"] = {
          '<cmd>lua require("spectre").open_file_search()<CR>',
          desc = "Spectre (current file)",
        },
        ["<leader>,w"] = {
          '<cmd>lua require("spectre").open_visual({select_word=true})<CR>',
          desc = "Spectre (current word)",
        },

        -- other
        ["__"] = { ":w<cr>", desc = "Save File" },
        ["<Backspace>"] = { "x", desc = "Delete char" },
        ["de"] = { "<S-v>ygvd", desc = "Cut Line" },
        ["<S-Up>"] = { "<cmd>m-2<cr>", desc = "Move line up" },
        ["<S-Down>"] = { "<cmd>m+<cr>", desc = "Move line down" },
        ["<S-l>"] = { "<cmd>:call vm#commands#add_cursor_up(0, 1)<cr>", desc = "Multicursor up" },
        ["<S-u>"] = { "<cmd>:call vm#commands#add_cursor_down(0, 1)<cr>", desc = "Multicursor down" },
        ["H"] = { function() require("smart-splits").move_cursor_left() end, desc = "Move left" },
        ["h"] = { function() require("smart-splits").move_cursor_right() end, desc = "Move right" },
        ["k"] = { function() require("smart-splits").move_cursor_down() end, desc = "Move down" },
        ["K"] = { function() require("smart-splits").move_cursor_up() end, desc = "Move up" },
        ["<C-s>"] = { ":w!<cr>", desc = "Save File" },
        ["<C-y>"] = {
          function()
            local new_val = not vim.diagnostic.config().virtual_lines
            vim.diagnostic.config { virtual_lines = new_val }
          end,
          desc = "Toggle lsp_lines",
        },
        ["<C-b>"] = { "<esc>$a;<esc>", desc = "Insert ; at end" },
        ["<C-t>"] = { "<esc>", desc = "Escape" },
      },

      i = {
        ["<C-y>"] = {
          function()
            local new_val = not vim.diagnostic.config().virtual_lines
            vim.diagnostic.config { virtual_lines = new_val }
          end,
          desc = "Toggle lsp_lines",
        },
        ["<C-b>"] = { "<esc>$a;<esc>:w<cr>", desc = "Insert ; and save" },
        ["<C-s>"] = { "<esc>:w<cr>a", desc = "Save File" },
        ["<C-t>"] = { "<esc>", desc = "Normal Mode" },
        ["<C-p>"] = { "<esc>p", desc = "Paste" },
        ["<C-f>"] = { "<esc>P", desc = "Paste before" },
        ["<C-d>"] = { function() require("lsp_signature").toggle_float_win() end, desc = "LSP Signature" },
        ["__"] = { "<esc>:w<cr>", desc = "Save & Normal" },
        ["_("] = { "_", desc = "Literal underscore" },
      },

      v = {
        -- visual leader f (regex)
        ["<leader>f"] = { desc = "Find" },
        ["<leader>fw"] = {
          function()
            local text = require("funcs").get_visual_selection()
            if text == "" then return end
            require("funcs").exit_visual()
            vim.schedule(function() require("snacks").picker.grep { search = text } end)
          end,
          desc = "Find selected text (regex)",
        },
        ["<leader>ff"] = {
          function()
            local text = require("funcs").get_visual_one_line()
            if text == "" then return end
            require("funcs").exit_visual()
            vim.schedule(
              function()
                require("snacks").picker.files {
                  search = "*" .. text .. "*",
                }
              end
            )
          end,
          desc = "Find file names from selection",
        },

        -- visual leader F (literal)
        ["<leader>F"] = { desc = "Literal search" },
        ["<leader>Fw"] = {
          function()
            local text = require("funcs").get_visual_selection()
            if text == "" then return end
            require("funcs").exit_visual()
            vim.schedule(
              function()
                require("snacks").picker.grep {
                  search = text,
                  regex = false,
                }
              end
            )
          end,
          desc = "Find selected text literally",
        },
        ["<leader>Ff"] = {
          function()
            local text = require("funcs").get_visual_one_line()
            if text == "" then return end
            require("funcs").exit_visual()
            vim.schedule(
              function()
                require("snacks").picker.files {
                  search = "*" .. text .. "*",
                }
              end
            )
          end,
          desc = "Find file names from selection",
        },

        -- visual spectre
        ["<leader>,"] = {
          '<Esc><cmd>lua require("spectre").open_visual()<CR>',
          desc = "Spectre (selection)",
        },

        -- visual fixes
        ["<leader>s"] = { desc = "Fixes" },
        ["<leader>sf"] = {
          '<Esc><cmd>lua require("funcs").rust_fill_match_arms_smart()<CR>',
          desc = "Rust fill match arms",
        },
        ["<leader>sv"] = {
          '<Esc><cmd>lua require("funcs").select_whole_file()<CR>',
          desc = "Select whole file",
        },
        ["<leader>st"] = {
          "<Esc>V$%",
          desc = "Select block to matching brace",
        },

        -- other
        ["r"] = { "<C-u>" },
        ["s"] = { "<C-d>" },
        ["j"] = { "<esc>", desc = "Normal Mode" },
        ["p"] = {
          function() return require("funcs").visual_paste_keep_regs "p" end,
          expr = true,
          desc = "Paste over selection and keep clipboard",
        },
        ["P"] = {
          function() return require("funcs").visual_paste_keep_regs "P" end,
          expr = true,
          desc = "Paste before selection and keep clipboard",
        },
        ["<S-Up>"] = { "<cmd>m-2<cr>", desc = "Move line up" },
        ["<S-Down>"] = { "<cmd>m+<cr>", desc = "Move line down" },
        ["<C-y>"] = {
          function()
            local new_val = not vim.diagnostic.config().virtual_lines
            vim.diagnostic.config { virtual_lines = new_val }
          end,
          desc = "Toggle lsp_lines",
        },
        ["<C-t>"] = { "<esc>", desc = "Normal Mode" },
        ["<C-b>"] = { "<esc>$a;<esc>", desc = "Insert ;" },
        ["__"] = { "<esc>:w<cr>", desc = "Save & Normal" },
        ["<Backspace>"] = { '"_d', desc = "Delete" },
        ["o"] = { "ygvd", desc = "Cut" },
        ["c"] = { "ygv", desc = "Copy" },
      },
    },
  },
}
