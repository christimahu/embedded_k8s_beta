-- ====================================================================================
--
--                       Neovim Configuration (init.lua)
--
-- ====================================================================================
--
--  Purpose:
--  --------
--  A production-ready Neovim configuration for infrastructure engineers working with
--  Kubernetes, Helm templates, and GPU/ML workloads. It provides modern editing
--  features while remaining lightweight enough for headless servers and ARM devices.
--
--  Philosophy - The "Neovim Appliance":
--  ------------------------------------
--  - No LSPs: This configuration does not use the Language Server Protocol (LSP).
--    This is an intentional design choice to avoid dependencies on external
--    runtimes like Node.js or Go, keeping the host OS clean and the installation
--    reliable on resource-constrained edge devices.
--  - Highlighting via Tree-sitter: We use Neovim's fast, built-in Tree-sitter
--    engine for syntax highlighting. It parses code like a compiler, providing
--    more accurate highlighting than older regex-based systems.
--  - Stable Plugins Only: Every plugin is pure Lua/Vimscript with no external
--    dependencies. No auto-installers, no network calls after initial setup, no
--    compilation of external tools. This ensures the config works reliably on
--    Jetson, Raspberry Pi, and other ARM platforms.
--
-- ====================================================================================


-- ====================================================================================
--                              BASIC EDITOR SETTINGS
-- ====================================================================================

-- --- Tutorial: Core Vim Options ---
-- These settings control Neovim's fundamental behavior. We configure them first
-- because plugins may depend on these base settings being correct.
-- ---
vim.opt.compatible = false
vim.opt.encoding = 'utf-8'
vim.opt.background = 'dark'
vim.opt.number = true
vim.opt.relativenumber = true

-- --- Tutorial: Indentation Settings ---
-- We enforce 2-space indentation everywhere for consistency. This matches the
-- convention used in YAML (Kubernetes manifests), Helm charts, and most modern
-- configuration files.
-- ---
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.copyindent = true

-- --- Tutorial: Search Settings ---
-- `ignorecase` makes searches case-insensitive by default.
-- `smartcase` overrides this if your search contains uppercase letters.
-- Example: "/test" finds "test" and "TEST", but "/Test" only finds "Test"
-- ---
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- --- Tutorial: Editor Comfort Settings ---
-- `scrolloff = 5`: Keep 5 lines visible above/below cursor (context awareness)
-- `cursorline`: Highlight the current line (easy to find cursor)
-- `signcolumn = 'yes'`: Always show sign column (prevents text shifting for git signs)
-- ---
vim.opt.scrolloff = 5
vim.opt.cursorline = true
vim.opt.showmatch = true
vim.opt.signcolumn = 'yes'

-- Split behavior
vim.opt.splitbelow = true
vim.opt.splitright = true

-- --- Tutorial: File Management ---
-- `swapfile = false`: Don't create .swp files (cleaner filesystem)
-- `backup = false`: Don't create backup files (use git instead)
-- `undofile = true`: Save undo history to disk (persist across sessions)
-- ---
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
vim.opt.undolevels = 5000
vim.opt.history = 5000
vim.opt.autoread = true

-- Other quality-of-life settings
vim.opt.termguicolors = true
vim.opt.wildmenu = true
vim.opt.backspace = 'indent,eol,start'
vim.opt.wrap = false
vim.opt.mouse = 'a'


-- ====================================================================================
--                           PLUGIN MANAGEMENT (PACKER)
-- ====================================================================================
-- This section automatically installs the Packer plugin manager if it's not present.
local install_path = vim.fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
  vim.cmd('packadd packer.nvim')
end

-- This is the main plugin list. Packer will ensure these are installed.
require('packer').startup(function(use)
    -- Packer can manage itself
    use 'wbthomason/packer.nvim'

    -- Color Scheme
    use 'sainnhe/gruvbox-material'

    -- UI Enhancements
    use {
        'nvim-tree/nvim-tree.lua',
        requires = 'nvim-tree/nvim-web-devicons' -- For file icons
    }
    use 'nvim-lualine/lualine.nvim'
    use 'lukas-reineke/indent-blankline.nvim'
    use 'lewis6991/gitsigns.nvim' -- Git change indicators

    -- Fuzzy Finder for quickly finding files
    use {
      'nvim-telescope/telescope.nvim',
      requires = { 'nvim-lua/plenary.nvim' } -- A required utility library
    }

    -- Syntax Highlighting via Tree-sitter
    use {
        'nvim-treesitter/nvim-treesitter',
        run = ':TSUpdate' -- Command to install/update parsers
    }

    -- Language-Specific Plugins (Pure Vimscript/Lua - No External Dependencies)
    use 'Vimjas/vim-python-pep8-indent'      -- Proper Python indentation (for PyTorch/ML)
    use 'fatih/vim-go'                       -- Go syntax (for Helm templates)
    use 'octol/vim-cpp-enhanced-highlight'   -- C++ highlighting (for CUDA)
    use 'rust-lang/rust.vim'                 -- Rust syntax
    use 'towolf/vim-helm'                    -- Helm chart template syntax
    use 'stephpy/vim-yaml'                   -- Enhanced YAML support

    -- Editing Helpers
    use 'numToStr/Comment.nvim'              -- Toggle comments with gcc
    use 'windwp/nvim-autopairs'              -- Auto-close brackets and quotes
end)


-- ====================================================================================
--                            PLUGIN CONFIGURATIONS
-- ====================================================================================

-- --- Color Scheme ---
vim.g.gruvbox_material_background = 'medium'
vim.g.gruvbox_material_enable_italic = 1
vim.g.gruvbox_material_better_performance = 1
vim.cmd([[colorscheme gruvbox-material]])


-- --- File Browser (NvimTree) ---
require('nvim-tree').setup({
    filters = {
        dotfiles = false, -- Show hidden files (important for .dockerignore, .gitignore)
    },
    view = {
        width = 30, -- Set the width of the file browser window
    },
    renderer = {
        icons = {
            show = {
                file = true,
                folder = true,
                folder_arrow = true,
                git = true,
            },
        },
    },
})


-- --- Status Line (Lualine) ---
require('lualine').setup({
    options = {
        theme = 'gruvbox-material',
        component_separators = { left = '', right = ''},
        section_separators = { left = '', right = ''},
    }
})


-- --- Git Signs ---
require('gitsigns').setup()


-- --- Indentation Guides ---
require('ibl').setup({
    indent = {
        char = '│', -- Use a subtle character for the guide
    },
    scope = {
        enabled = true,
        show_start = true,
    }
})


-- --- Comment Toggling ---
require('Comment').setup()


-- --- Auto Pairs ---
require('nvim-autopairs').setup()


-- --- Syntax Highlighting (Tree-sitter) ---
-- Parsers cover all languages used in this repository: infrastructure configs,
-- programming languages for ML/GPU work, and documentation formats.
require('nvim-treesitter.configs').setup {
    ensure_installed = {
        -- Infrastructure and configs
        "yaml", "json", "toml", "dockerfile",
        -- Shell and scripting
        "bash", "lua",
        -- Programming languages
        "python",        -- PyTorch, ML scripts
        "go",            -- Helm template language
        "gomod",         -- Go module files
        "gowork",        -- Go workspace files
        "cpp", "c",      -- CUDA, GPU programming
        "rust",          -- Systems programming
        -- Documentation
        "markdown",
    },

    -- Automatically install parsers for new file types when you open them
    auto_install = true,

    -- Enable the syntax highlighting module
    highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
    },
    -- Enable indentation based on Tree-sitter's understanding of the code structure
    indent = {
        enable = true
    },
}


-- --- Fuzzy Finder (Telescope) ---
require('telescope').setup({
    defaults = {
        layout_strategy = 'horizontal',
        layout_config = {
            horizontal = {
                preview_width = 0.55,
            },
        },
    },
})


-- ====================================================================================
--                       LANGUAGE-SPECIFIC CONFIGURATIONS
-- ====================================================================================

-- vim-go: Enable syntax highlighting for Go (used in Helm templates)
vim.g.go_highlight_functions = 1
vim.g.go_highlight_function_calls = 1
vim.g.go_highlight_types = 1
vim.g.go_highlight_fields = 1
vim.g.go_highlight_operators = 1
vim.g.go_highlight_extra_types = 1
vim.g.go_highlight_build_constraints = 1

-- Rust: Disable auto-formatting on save (can be slow on edge devices)
vim.g.rustfmt_autosave = 0

-- Python: Enable all syntax highlighting features
vim.g.python_highlight_all = 1


-- ====================================================================================
--                                 KEYBINDINGS
-- ====================================================================================

vim.g.mapleader = " " -- Set the leader key to the Space bar

-- File Explorer
vim.api.nvim_set_keymap('n', '<C-n>', ':NvimTreeToggle<CR>', {noremap = true, silent = true})

-- Telescope keybindings for finding things quickly
vim.api.nvim_set_keymap('n', '<leader>ff', ':Telescope find_files<CR>', {noremap = true}) -- Find Files
vim.api.nvim_set_keymap('n', '<leader>fg', ':Telescope live_grep<CR>', {noremap = true})  -- Find Text (grep)
vim.api.nvim_set_keymap('n', '<leader>fb', ':Telescope buffers<CR>', {noremap = true})   -- Find in open buffers
vim.api.nvim_set_keymap('n', '<leader>fh', ':Telescope help_tags<CR>', {noremap = true})  -- Search help docs

-- Buffer navigation
vim.api.nvim_set_keymap('n', '<leader>bn', ':bnext<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>bp', ':bprevious<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>bd', ':bdelete<CR>', {noremap = true})

-- Window navigation
vim.api.nvim_set_keymap('n', '<C-h>', '<C-w>h', {noremap = true})
vim.api.nvim_set_keymap('n', '<C-j>', '<C-w>j', {noremap = true})
vim.api.nvim_set_keymap('n', '<C-k>', '<C-w>k', {noremap = true})
vim.api.nvim_set_keymap('n', '<C-l>', '<C-w>l', {noremap = true})

-- Quick save and quit
vim.api.nvim_set_keymap('n', '<leader>w', ':w<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>q', ':q<CR>', {noremap = true})

-- Clear search highlighting
vim.api.nvim_set_keymap('n', '<leader>h', ':nohlsearch<CR>', {noremap = true, silent = true})


-- ====================================================================================
--                              AUTOCOMMANDS
-- ====================================================================================

-- Force 2-space indentation for all file types (consistency across YAML, code, etc.)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
    vim.bo.expandtab = true
  end,
})

-- Recognize Helm template files as Go templates (for proper syntax highlighting)
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
  pattern = {"*/templates/*.yaml", "*/templates/*.tpl"},
  callback = function()
    vim.bo.filetype = "helm"
  end,
})

-- Recognize C++20 module files
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
  pattern = {"*.ixx", "*.cppm", "*.mxx"},
  callback = function()
    vim.bo.filetype = "cpp"
  end,
})

-- Highlight yanked (copied) text briefly for visual feedback
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank({higroup = 'IncSearch', timeout = 200})
  end,
})

-- Auto-remove trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    local save_cursor = vim.fn.getpos(".")
    vim.cmd([[%s/\s\+$//e]])
    vim.fn.setpos(".", save_cursor)
  end,
})


-- ====================================================================================
--                              END OF CONFIGURATION
-- ====================================================================================
