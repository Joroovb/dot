-- ============================================================================
-- Utility Shortcuts
-- ============================================================================

local opt = vim.opt
local autocmd = vim.api.nvim_create_autocmd

-- ============================================================================
-- Basic Options
-- ============================================================================

-- Indentation: Use spaces instead of tabs, with 2-space width
opt.expandtab = true
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2

-- UI: Hide default command-line statusbar (lualine provides statusline)
opt.cmdheight = 0

-- Undo
opt.undofile = true

-- Line numbers: Show absolute line number on current line, relative elsewhere
opt.number = true
opt.relativenumber = true

-- Set leader key to Space for custom keybindings
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- updatetime: Time (ms) of inactivity before CursorHold event fires
-- Used for LSP document highlighting and other idle-triggered actions
opt.updatetime = 250

-- timeoutlen: Time (ms) to wait for a mapped sequence to complete
opt.timeoutlen = 300

-- ============================================================================
-- Keymaps
-- ============================================================================

--- Helper function to create keymaps
--- @param keys string   The key combination to map
--- @param func string|function The function to execute
--- @param desc string   Description shown in which-key/telescope
local map = function(keys, func, desc)
  local opts = { noremap = true, silent = true, desc = desc }
  vim.keymap.set("n", keys, func, opts)
end

map("fe", "<CMD>Oil<CR>", "Open Oil file browser")
map("<leader>o", "<CMD>Outline<CR>", "Toggle symbol outline/document structure")

-- Trouble keymaps
map("<leader>xx", "<CMD>Trouble diagnostics toggle<CR>", "Toggle diagnostics (all buffers)")
map("<leader>xX", "<CMD>Trouble diagnostics toggle filter.buf=0<CR>", "Toggle diagnostics (current buffer)")
map("<leader>xq", "<CMD>Trouble quickfix toggle<CR>", "Toggle quickfix list")

-- Window/pane navigation: Seamless movement between Neovim splits and tmux panes
map("<C-h>", "<CMD>TmuxNavigateLeft<CR>", "")
map("<C-j>", "<CMD>TmuxNavigateDown<CR>", "")
map("<C-k>", "<CMD>TmuxNavigateUp<CR>", "")
map("<C-l>", "<CMD>TmuxNavigateRight<CR>", "")

-- ============================================================================
-- LSP Configuration
-- ============================================================================

local function setup_lsp()
  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        diagnostics = { globals = { "vim" } },
        workspace = {
          -- Make the server aware of Neovim runtime files
          library = vim.api.nvim_get_runtime_file("", true),
        },
      }
    }
  })

  -- Configure diagnostic display and behavior
  vim.diagnostic.config({
    virtual_text = false,     -- Do not show diagnostics as virtual text at end of line
    underline = true,         -- Underline diagnostic text
    update_in_insert = false, -- Don't update diagnostics while typing
    severity_sort = true,     -- Sort diagnostics by severity (errors first)
    float = {
      border = "rounded",     -- Use rounded borders for floating windows
      source = true,          -- Show diagnostic source (e.g., "eslint")
    },
    signs = {
      -- Custom icons for diagnostic signs in the sign column (requires nerd font)
      text = {
        [vim.diagnostic.severity.ERROR] = "󰅚 ",
        [vim.diagnostic.severity.WARN] = "󰀪 ",
        [vim.diagnostic.severity.INFO] = "󰋽 ",
        [vim.diagnostic.severity.HINT] = "󰌶 ",
      },

      -- Highlight line numbers for errors and warnings
      numhl = {
        [vim.diagnostic.severity.ERROR] = "ErrorMsg",
        [vim.diagnostic.severity.WARN] = "WarningMsg",
      },
    },
  })

  vim.api.nvim_create_user_command("Format", function(args)
    local range = nil
    if args.count ~= -1 then
      local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
      range = {
        start = { args.line1, 0 },
        ["end"] = { args.line2, end_line:len() },
      }
    end
    require("conform").format({ async = true, lsp_format = "fallback", range = range })
  end, { range = true })


  -- Set up buffer-local LSP keymaps when LSP attaches to a buffer
  autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
    callback = function(event)
      --- Helper function to create buffer-local LSP keymaps
      --- @param keys string   The key combination to map
      --- @param func function The function to execute
      --- @param desc string   Description shown in which-key/telescope
      local lspmap = function(keys, func, desc)
        local bufopts = { noremap = true, silent = true, buffer = event.buf, desc = "LSP: " .. desc }
        vim.keymap.set("n", keys, func, bufopts)
      end

      -- Code actions and refactoring
      lspmap("<leader>la", vim.lsp.buf.code_action, "Code Action")
      lspmap("<leader>lr", vim.lsp.buf.rename, "Rename all references")
      lspmap("<leader>lf", vim.lsp.buf.format, "Format")

      -- Diagnostics navigation
      lspmap("<leader>e", vim.diagnostic.open_float, "Open floating diagnostic window")

      lspmap("<leader>j", function()
        vim.diagnostic.jump({ count = 1, float = true })
      end, "Jump to next diagnostic")

      lspmap("<leader>k", function()
        vim.diagnostic.jump({ count = -1, float = true })
      end, "Jump to previous diagnostic")

      -- Documentation
      lspmap("K", vim.lsp.buf.hover, "Hover Documentation")
      lspmap("gl", vim.diagnostic.open_float, "Open Diagnostic Float")
      lspmap("gs", vim.lsp.buf.signature_help, "Signature Documentation")

      -- Navigation
      lspmap("gd", vim.lsp.buf.definition, "Goto Definition")
      lspmap("gr", vim.lsp.buf.references, "Goto References")
      lspmap("gi", vim.lsp.buf.implementation, "Goto Implementation")
      lspmap("gt", vim.lsp.buf.type_definition, "Goto Type Definition")
      lspmap("gD", vim.lsp.buf.declaration, "Goto Declaration")

      -- Get LSP client that just attached
      local client = assert(vim.lsp.get_client_by_id(event.data.client_id))
      local methods = vim.lsp.protocol.Methods

      -- Enable document highlighting if server supports it
      -- Highlights all instances of the symbol under cursor when idle
      if client:supports_method(methods.textDocument_documentHighlight) then
        local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })

        -- Highlight all instances when cursor stops moving
        autocmd({ 'CursorHold', 'CursorHoldI' }, {
          buffer = event.buf,
          group = highlight_augroup,
          callback = vim.lsp.buf.document_highlight,
        })

        -- Clear highlighting when cursor starts moving
        autocmd({ 'CursorMoved', 'CursorMovedI' }, {
          buffer = event.buf,
          group = highlight_augroup,
          callback = vim.lsp.buf.clear_references,
        })

        -- Clean up when LSP detaches from buffer
        autocmd('LspDetach', {
          group = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
          callback = function(event2)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = event2.buf }
          end,
        })
      end
    end,
  })
end

-- ============================================================================
-- Plugin Configuration
-- ============================================================================

local function setup_plugins()
  -- Oil: File browser that opens directories as buffers
  require("oil").setup()

  -- Mini.pairs: Automatic bracket/quote pairing
  require("mini.pairs").setup()

  -- Outline: Symbol/tag browser showing document structure
  require("outline").setup()

  local ts = require("telescope.builtin")
  map("<leader>ff", ts.find_files, "Telescope Find Files")
  map("<leader>fb", ts.buffers, "Telescope Buffers")
  map("<leader>fg", ts.live_grep, "Telescope Live Grep")
  map("<leader>fs", ts.lsp_document_symbols, "Telescope File Symbols")


  -- Trouble: Pretty diagnostics and quickfix list UI
  require("trouble").setup({ cmd = "Trouble" })

  -- Mason: Portable package manager for LSP servers, DAP servers, linters, and formatters
  -- Automatically installs and manages language servers
  require("mason").setup()


  local undotree = require('undotree')
  map("<leader>u", undotree.toggle, "")

  -- Mason-lspconfig: Bridge between mason.nvim and nvim-lspconfig
  -- Automatically installs language servers listed in ensure_installed on first launch
  require("mason-lspconfig").setup {
    ensure_installed = {
      "gopls",         -- Go
      "lua_ls",        -- Lua
      "pyright",       -- Python
      "ts_ls",         -- TypeScript/JavaScript
      "rust_analyzer", -- Rust
      "tinymist",      -- Typst
      "nil_ls",
    },
  }

  -- Blink.cmp: Fast completion engine with LSP integration
  require("blink.cmp").setup({
    signature = { enabled = true },
    appearance = {
      use_nvim_cmp_as_default = false,
      nerd_font_variant = "normal",
    },

    -- Completion menu keybindings
    keymap = {
      preset = "default",
      ["<S-Tab>"] = { "select_prev", "fallback" }, -- Navigate up in completion menu
      ["<Tab>"] = { "select_next", "fallback" },   -- Navigate down in completion menu
      ["<CR>"] = { "accept", "fallback" },         -- Accept selected completion
    },

    -- Completion menu appearance
    completion = {
      ghost_text = { enabled = true },
      menu = {
        border = "rounded",
        scrolloff = 1, -- Keep 1 line above/below cursor when scrolling
        scrollbar = false,
        draw = {
          columns = {
            { "kind_icon" },   -- Icon for completion kind (function, variable, etc.)
            { "label",      "label_description", gap = 1 },
            { "kind" },        -- Text label for kind
            { "source_name" }, -- Source (LSP, buffer, path, etc.)
          },
        },
      },

      -- Documentation window settings
      documentation = {
        window = {
          border = "rounded",
          scrollbar = false,
          winhighlight = 'Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,EndOfBuffer:BlinkCmpDoc',
        },
        auto_show = true,
        auto_show_delay_ms = 500, -- Delay before showing documentation
      },
    },

    -- Fuzzy matching: Prefer Rust implementation for speed
    fuzzy = { implementation = "prefer_rust", prebuilt_binaries = { force_version = "v1.8.0" } }
  })
end

-- ============================================================================
-- Plugin Installation
-- ============================================================================

-- Declare plugins using Neovim's native package manager
-- Plugins are downloaded to ~/.local/share/nvim/site/pack/*/start/
vim.pack.add({
  "https://github.com/nvim-tree/nvim-web-devicons",    -- Icons for file types
  "https://github.com/neovim/nvim-lspconfig",          -- LSP configuration helpers
  "https://github.com/mason-org/mason.nvim",           -- LSP server package manager
  "https://github.com/mason-org/mason-lspconfig.nvim", -- Mason + lspconfig integration
  "https://github.com/stevearc/oil.nvim",              -- File browser as buffer
  "https://github.com/hedyhli/outline.nvim",           -- Symbol outline viewer
  "https://github.com/blazkowolf/gruber-darker.nvim",  -- Gruber Darker colorscheme
  "https://github.com/folke/trouble.nvim",             -- Diagnostics UI
  "https://github.com/christoomey/vim-tmux-navigator", -- Seamless vim/tmux navigation
  "https://github.com/saghen/blink.cmp",               -- Completion engine
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/nvim-telescope/telescope.nvim",
  "https://github.com/jiaoshijie/undotree",
  "https://github.com/nvim-mini/mini.nvim",
  "https://github.com/stevearc/conform.nvim"
})

-- ============================================================================
-- Initialization
-- ============================================================================

local misc = require('mini.misc')
local now = function(f) misc.safely('now', f) end
local later = function(f) misc.safely('later', f) end
local now_if_args = vim.fn.argc(-1) > 0 and now or later
local gr = vim.api.nvim_create_augroup('custom-config', {})
local new_autocmd = function(event, pattern, callback, desc)
  local opts = { group = gr, pattern = pattern, callback = callback, desc = desc }
  vim.api.nvim_create_autocmd(event, opts)
end

-- Initialize LSP and plugins (must happen after vim.pack.add)
setup_lsp()
setup_plugins()

now(function()
  require('mini.basics').setup({
    -- Manage options in 'plugin/10_options.lua' for didactic purposes
    options = { basic = false },
    mappings = {
      -- Create `<C-hjkl>` mappings for window navigation
      windows = true,
      -- Create `<M-hjkl>` mappings for navigation in Insert and Command modes
      move_with_alt = true,
    },
  })
end)

now(function()
  require("conform").setup({
    format_on_save = {
      -- These options will be passed to conform.format()
      timeout_ms = 500,
      lsp_format = "fallback",
    },
    formatters_by_ft = {
      lua = { "stylua" },
      -- Conform will run the first available formatter
      javascript = { "prettierd", "prettier", stop_after_first = true },
      typescript = { "prettierd", "prettier", stop_after_first = true },
      typescriptreact = { "prettierd", "prettier", stop_after_first = true },
    },
  })
end)

now(function()
  local gen_loader = require('mini.snippets').gen_loader
  require('mini.snippets').setup({
    snippets = {
      -- Load custom file with global snippets first (adjust for Windows)
      gen_loader.from_file('~/.config/nvim/snippets/global.json'),

      -- Load snippets based on current language by reading files from
      -- "snippets/" subdirectories from 'runtimepath' directories.
      -- gen_loader.from_lang(),
    },
  })
end)

now(function() require('mini.statusline').setup() end)
now(function() require('mini.tabline').setup() end)
now_if_args(function()
  -- Enable directory/file preview
  require('mini.files').setup({ windows = { preview = true } })

  -- Add common bookmarks for every explorer. Example usage inside explorer:
  -- - `'c` to navigate into your config directory
  -- - `g?` to see available bookmarks
  local add_marks = function()
    MiniFiles.set_bookmark('c', vim.fn.stdpath('config'), { desc = 'Config' })
    local vimpack_plugins = vim.fn.stdpath('data') .. '/site/pack/core/opt'
    MiniFiles.set_bookmark('p', vimpack_plugins, { desc = 'Plugins' })
    MiniFiles.set_bookmark('w', vim.fn.getcwd, { desc = 'Working directory' })
  end
  new_autocmd('User', 'MiniFilesExplorerOpen', add_marks, 'Add bookmarks')
end)

later(function() require('mini.cmdline').setup() end)
later(function() require('mini.indentscope').setup() end)

later(function()
  require('mini.keymap').setup()
  -- Navigate 'mini.completion' menu with `<Tab>` /  `<S-Tab>`
  MiniKeymap.map_multistep('i', '<Tab>', { 'pmenu_next' })
  MiniKeymap.map_multistep('i', '<S-Tab>', { 'pmenu_prev' })
  -- On `<CR>` try to accept current completion item, fall back to accounting
  -- for pairs from 'mini.pairs'
  MiniKeymap.map_multistep('i', '<CR>', { 'pmenu_accept', 'minipairs_cr' })
  -- On `<BS>` just try to account for pairs from 'mini.pairs'
  MiniKeymap.map_multistep('i', '<BS>', { 'minipairs_bs' })
end)

later(function()
  local mmap = require('mini.map')
  mmap.setup({
    -- Use Braille dots to encode text
    symbols = { encode = mmap.gen_encode_symbols.dot('4x2') },
    -- Show built-in search matches, 'mini.diff' hunks, and diagnostic entries
    integrations = {
      mmap.gen_integration.builtin_search(),
      mmap.gen_integration.diff(),
      mmap.gen_integration.diagnostic(),
    },
  })

  -- Map built-in navigation characters to force map refresh
  for _, key in ipairs({ 'n', 'N', '*', '#' }) do
    local rhs = key
        -- Also open enough folds when jumping to the next match
        .. 'zv'
        .. '<Cmd>lua MiniMap.refresh({}, { lines = false, scrollbar = false })<CR>'
    vim.keymap.set('n', key, rhs)
  end
end)
later(function() require('mini.trailspace').setup() end)

-- Apply colorscheme
vim.cmd.colorscheme("gruber-darker")
