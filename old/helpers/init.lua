-- ====================================================================================
--
--                       Neovim Configuration (init.lua)
--
-- ====================================================================================
--
--  Purpose:
--  --------
--  A minimal, robust Neovim configuration for editing Kubernetes YAML, Helm templates,
--  and shell scripts. It prioritizes stability and a light footprint over
--  IDE-like features, making it perfect for automated deployment on cluster nodes.
--
--  Philosophy - The "Neovim Appliance":
--  ------------------------------------
--  - No LSPs: This configuration does not use the Language Server Protocol (LSP).
--    This is an intentional design choice to avoid dependencies on external
--    runtimes like Node.js or Go, keeping the host OS clean.
--  - Highlighting via Tree-sitter: We use Neovim's fast, built-in Tree-sitter
--    engine for syntax highlighting. It parses code like a compiler, providing
--    more accurate and granular highlighting than older regex-based systems.
--  - Core Quality-of-Life Only: The plugins selected provide the essentials for
--    a modern editing experience: a color scheme, file browser, status line, and
--    fuzzy finder. It explicitly omits features like autocompletion, git
--    integration, and real-time diagnostics to maintain simplicity and stability.
--
-- ====================================================================================


-- ====================================================================================
--                              BASIC EDITOR SETTINGS
-- ====================================================================================
-- These options configure the fundamental behavior of the editor.
vim.opt.compatible = false                  -- Use Neovim defaults, not Vi-compatible
vim.opt.encoding = 'utf-8'                  -- Use UTF-8 encoding
vim.opt.background = 'dark'                 -- Assume a dark terminal background
vim.opt.number = true                       -- Show line numbers
vim.opt.tabstop = 2                         -- Number of spaces a tab counts for
vim.opt.shiftwidth = 2                      -- Number of spaces to use for autoindent
vim.opt.expandtab = true                    -- Use spaces instead of tab characters
vim.opt.autoindent = true                   -- Copy indent from current line when starting a new line
vim.opt.hlsearch = true                     -- Highlight all search matches
vim.opt.scrolloff = 5                       -- Keep 5 lines of context around the cursor
vim.opt.splitbelow = true                   -- A horizontal split will open below
vim.opt.splitright = true                   -- A vertical split will open to the right
vim.opt.termguicolors = true                -- Enable 24-bit RGB colors for themes
vim.opt.swapfile = false                    -- Do not create swap files
vim.opt.backup = false                      -- Do not create backup files
vim.opt.backspace = 'indent,eol,start'      -- Allow backspace over everything in insert mode
vim.opt.signcolumn = 'yes'                  -- Always show the sign column to prevent jitter
vim.opt.cursorline = true                   -- Highlight the current line
vim.opt.wrap = false                        -- Do not wrap long lines
vim.opt.ignorecase = true                   -- Ignore case in search patterns
vim.opt.smartcase = true                    -- Override ignorecase if pattern has uppercase letters


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
end)


-- ====================================================================================
--                            PLUGIN CONFIGURATIONS
-- ====================================================================================

-- --- Color Scheme ---
vim.g.gruvbox_material_background = 'medium'
vim.g.gruvbox_material_enable_italic = 1
vim.cmd([[colorscheme gruvbox-material]])


-- --- File Browser (NvimTree) ---
require('nvim-tree').setup({
    filters = {
        dotfiles = false, -- Hide dotfiles like .git, .DS_Store, etc.
    },
    view = {
        width = 30, -- Set the width of the file browser window
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


-- --- Indentation Guides ---
require('ibl').setup({
    indent = {
        char = '│', -- Use a subtle character for the guide
    },
    scope = { enabled = false }, -- Keep it simple, no scope highlighting
})


-- --- Syntax Highlighting (Tree-sitter) ---
-- See: https://github.com/nvim-treesitter/nvim-treesitter
require('nvim-treesitter.configs').setup {
    -- A selection of parsers to install automatically. These cover the primary
    -- file types used in this repository.
    ensure_installed = { "yaml", "lua", "bash", "json", "go", "python" },

    -- Automatically install parsers for new file types when you open them.
    auto_install = true,

    -- Enable the syntax highlighting module.
    highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
    },
    -- Enable indentation based on Tree-sitter's understanding of the code structure.
    indent = {
        enable = true
    },
}

-- --- Fuzzy Finder (Telescope) ---
-- No custom config needed; the default settings are excellent.
require('telescope').setup()


-- ====================================================================================
--                                 KEYBINDINGS
-- ====================================================================================

vim.g.mapleader = " " -- Set the leader key to the Space bar

-- Toggle the NvimTree file browser
vim.api.nvim_set_keymap('n', '<C-n>', ':NvimTreeToggle<CR>', {noremap = true, silent = true})

-- Telescope keybindings for finding things quickly
vim.api.nvim_set_keymap('n', '<leader>ff', ':Telescope find_files<CR>', {noremap = true}) -- Find Files
vim.api.nvim_set_keymap('n', '<leader>fg', ':Telescope live_grep<CR>', {noremap = true})  -- Find Text (grep)
vim.api.nvim_set_keymap('n', '<leader>fb', ':Telescope buffers<CR>', {noremap = true})   -- Find in open buffers
vim.api.nvim_set_keymap('n', '<leader>fh', ':Telescope help_tags<CR>', {noremap = true})  -- Search help docs


-- ====================================================================================
--                         GLOBAL FILETYPE CONFIGURATION
-- ====================================================================================

-- This autocommand ensures that all files, regardless of type, use a consistent
-- 2-space indentation. This is ideal for YAML and common practice for most
-- other languages in this project.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*", -- Match all file types
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
    vim.bo.expandtab = true
  end,
})

-- ====================================================================================
--                              END OF CONFIGURATION
-- ====================================================================================
