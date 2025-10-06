-- ====================================================================================
--
--                    Minimal Neovim Configuration (init.lua)
--
-- ====================================================================================
--
--  Purpose:
--  --------
--  This is a streamlined Neovim configuration focused on editing Kubernetes configs,
--  Helm templates, and occasional hotfixes for Python/Rust/Go code. It provides
--  language-aware editing without the overhead of a full IDE setup.
--
--  Philosophy:
--  -----------
--  This config is designed for someone who primarily develops on macOS and uses
--  the Jetson/Raspberry Pi for testing, debugging platform-specific issues, and
--  quick iteration. It's NOT a replacement for a full development environment.
--
--  What This Config Provides:
--  --------------------------
--  - Beautiful color scheme (gruvbox-material)
--  - Language servers for Python, Rust, Go, and YAML (installed via system packages)
--  - File browser for navigation
--  - Smart indentation and formatting
--  - Diagnostic messages for errors/warnings
--  - No autocomplete UI (keep it simple)
--  - No AI assistants (Copilot stays on your Mac)
--
--  Learning Resources:
--  -------------------
--  If you're new to Vim/Neovim, start here:
--  1. Run 'vimtutor' in your terminal (20-minute interactive tutorial)
--  2. https://www.openvim.com/ (interactive browser tutorial)
--  3. https://vim.rtorr.com/ (quick command reference)
--  4. https://neovim.io/doc/user/ (official documentation)
--
--  Quick Reference:
--  ----------------
--  Run ~/vim_quick_reference.sh for common commands anytime you forget something.
--
-- ====================================================================================

-- ====================================================================================
--                              BASIC SETTINGS
-- ====================================================================================

vim.opt.compatible = false
vim.opt.encoding = 'utf-8'
vim.opt.background = 'dark'
vim.opt.number = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.copyindent = true
vim.opt.hlsearch = true
vim.opt.scrolloff = 5
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.wildmenu = true
vim.opt.showmatch = true
vim.opt.termguicolors = true
vim.opt.spell = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undolevels = 5000
vim.opt.history = 5000
vim.opt.autoread = true
vim.opt.backspace = 'indent,eol,start'
vim.opt.signcolumn = 'yes'
vim.opt.cursorline = true
vim.opt.wrap = false
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- ====================================================================================
--                           PLUGIN MANAGEMENT (PACKER)
-- ====================================================================================

local install_path = vim.fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
  vim.cmd('packadd packer.nvim')
end

require('packer').startup(function(use)
    use 'wbthomason/packer.nvim'
    use 'sainnhe/gruvbox-material'
    use 'neovim/nvim-lspconfig'
    use 'Vimjas/vim-python-pep8-indent'
    use 'mrcjkb/rustaceanvim'
    use 'fatih/vim-go'
    use {
        'nvim-tree/nvim-tree.lua',
        requires = 'nvim-tree/nvim-web-devicons'
    }
    use 'nvim-lualine/lualine.nvim'
    use 'lewis6991/gitsigns.nvim'
    use 'lukas-reineke/indent-blankline.nvim'
    use {
      'nvim-telescope/telescope.nvim',
      requires = { 'nvim-lua/plenary.nvim' }
    }
    use 'j-hui/fidget.nvim'
    use {
      'folke/trouble.nvim',
      requires = 'nvim-tree/nvim-web-devicons'
    }
end)

-- ====================================================================================
--                            COLOR SCHEME SETUP
-- ====================================================================================

vim.cmd([[if has("termguicolors") | set termguicolors | endif]])
vim.cmd([[colorscheme gruvbox-material]])

vim.g.gruvbox_material_background = 'medium'
vim.g.gruvbox_material_enable_italic = 1
vim.g.gruvbox_material_better_performance = 1

-- ====================================================================================
--                            PLUGIN CONFIGURATIONS
-- ====================================================================================

require('nvim-tree').setup({
    filters = {
        dotfiles = false,
    },
    view = {
        width = 30,
    },
})

require('lualine').setup({
    options = {
        theme = 'gruvbox-material',
        component_separators = { left = '', right = ''},
        section_separators = { left = '', right = ''},
    }
})

require('gitsigns').setup()

require('ibl').setup({
    indent = {
        char = '│',
    },
    scope = {
        enabled = true,
        show_start = true,
    }
})

require("fidget").setup({})

require("trouble").setup({
  icons = false,
  fold_open = "v",
  fold_closed = ">",
  signs = {
    error = "E",
    warning = "W",
    hint = "H",
    information = "I"
  },
})

-- ====================================================================================
--                       LANGUAGE SERVER CONFIGURATION
-- ====================================================================================
-- Language servers are installed via system packages (apt/npm/go install)
-- during the install_nvim.sh script. This ensures fast, reliable, deterministic
-- installation suitable for cluster provisioning.

vim.lsp.config('lua_ls', {})
vim.lsp.config('gopls', {})
vim.lsp.config('pyright', {})

vim.lsp.config('yamlls', {
    settings = {
        yaml = {
            schemas = {
                ["https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.28.0-standalone-strict/all.json"] = "/*.yaml",
            },
        },
    },
})

-- Enable language servers
vim.lsp.enable({'lua_ls', 'gopls', 'pyright', 'yamlls'})

-- ====================================================================================
--                         RUST CONFIGURATION (RUSTACEANVIM)
-- ====================================================================================

vim.g.rustaceanvim = {
    server = {
        settings = {
            ["rust-analyzer"] = {
                checkOnSave = {
                    command = "clippy",
                },
                cargo = {
                    allFeatures = true,
                },
                procMacro = {
                    enable = true,
                },
            },
        },
    },
}

-- ====================================================================================
--                          LSP KEYBINDINGS
-- ====================================================================================

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local opts = { buffer = ev.buf, noremap = true, silent = true }
    
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<leader>f', function() 
      vim.lsp.buf.format({ async = true }) 
    end, opts)
  end,
})

-- ====================================================================================
--                            GENERAL KEYBINDINGS
-- ====================================================================================

vim.g.mapleader = " "

vim.api.nvim_set_keymap('n', '<C-n>', ':NvimTreeToggle<CR>', {noremap = true, silent = true})
vim.api.nvim_set_keymap('n', '<leader>ff', ':Telescope find_files<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>fg', ':Telescope live_grep<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>fb', ':Telescope buffers<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>fh', ':Telescope help_tags<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>xx', ':TroubleToggle<CR>', {noremap = true})

-- ====================================================================================
--                         SPECIAL FILE TYPE MAPPINGS
-- ====================================================================================

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.ixx", "*.cppm", "*.mxx" },
  callback = function()
    vim.bo.filetype = "cpp"
  end
})

-- ====================================================================================
--                         PYTHON CONFIGURATION
-- ====================================================================================

local is_mac = vim.fn.has('macunix') == 1
local is_linux = vim.fn.has('unix') == 1 and vim.fn.has('macunix') == 0

if is_mac then
  vim.g.python3_host_prog = '/usr/local/bin/python3'
elseif is_linux then
  vim.g.python3_host_prog = '/usr/bin/python3'
end

-- ====================================================================================
--                    FORCE 2-SPACE INDENTATION FOR ALL FILES
-- ====================================================================================

vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
    vim.bo.expandtab = true
  end,
})

-- ====================================================================================
--                              END OF CONFIGURATION
-- ====================================================================================
