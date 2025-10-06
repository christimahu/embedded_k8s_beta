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
--  - Language servers for Python, Rust, Go, and YAML
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
-- These are fundamental settings that control how Neovim looks and behaves.
-- Think of these as the "preferences" in a GUI application.

-- Disable vi compatibility mode
-- Vim started as an improved version of 'vi'. This ensures we use Vim's features,
-- not vi's limited feature set.
vim.opt.compatible = false

-- Set file encoding to UTF-8
-- UTF-8 is the modern standard for text encoding and supports all international
-- characters. Always use UTF-8 for new files.
vim.opt.encoding = 'utf-8'

-- Use a dark background
-- This tells the color scheme to optimize for dark backgrounds. Most terminal
-- emulators use dark backgrounds, so this makes colors more readable.
vim.opt.background = 'dark'

-- Show line numbers in the left margin
-- Line numbers help you navigate files and are essential when debugging (e.g.,
-- "error on line 42"). In Vim, you can jump to a line with :42 or 42G.
vim.opt.number = true

-- Set tab width to 2 spaces (how many spaces a tab character displays as)
-- In Python/YAML/Kubernetes configs, 2 spaces is the standard indentation.
vim.opt.tabstop = 2

-- Set indent width to 2 spaces (how many spaces to indent when you press >> or Tab)
-- This should match tabstop for consistency.
vim.opt.shiftwidth = 2

-- Convert tabs to spaces
-- This is crucial for Python and YAML. Instead of inserting a tab character (\t),
-- Neovim will insert the equivalent number of spaces. This prevents indentation
-- errors in Python and makes files consistent across editors.
vim.opt.expandtab = true

-- Enable automatic indentation
-- When you press Enter, Neovim will automatically indent the next line to match
-- the previous line's indentation level. This is a huge time-saver.
vim.opt.autoindent = true

-- Copy indent structure from the previous line
-- This is smarter than autoindent. It preserves the exact indentation pattern,
-- including tabs/spaces mix if present (though we avoid that with expandtab).
vim.opt.copyindent = true

-- Highlight search results
-- When you search with /pattern, all matches will be highlighted in the file.
-- This makes it easy to see all occurrences of what you're searching for.
vim.opt.hlsearch = true

-- Keep 5 lines visible above/below cursor when scrolling
-- This "scroll offset" prevents the cursor from being at the very top or bottom
-- of the screen, giving you context about what's above and below.
vim.opt.scrolloff = 5

-- Open new horizontal splits below current window
-- By default, :split opens a new window above. This reverses that behavior,
-- which feels more natural (like opening a new tab "below" the current one).
vim.opt.splitbelow = true

-- Open new vertical splits to the right of current window
-- Similar to splitbelow, this makes :vsplit open to the right instead of left.
vim.opt.splitright = true

-- Enable command-line completion with a visual menu
-- When you type : to enter a command, pressing Tab will show completion options
-- in a menu rather than just cycling through them. Try typing :color<Tab>.
vim.opt.wildmenu = true

-- Highlight matching brackets/parentheses
-- When your cursor is on a bracket like ( or {, Neovim will briefly highlight
-- the matching closing bracket. This is essential for complex nested code.
vim.opt.showmatch = true

-- Enable 24-bit RGB colors in the terminal
-- Modern terminals support millions of colors (24-bit color). This enables
-- beautiful color schemes like gruvbox-material. Without this, you get only 256 colors.
vim.opt.termguicolors = true

-- Enable spell checking
-- Neovim will underline misspelled words. Useful for comments and documentation.
-- Press 'z=' on a misspelled word to see suggestions. ':set nospell' to disable.
vim.opt.spell = true

-- Disable swap files
-- Swap files (.swp) are Neovim's crash recovery mechanism, but they clutter
-- your directories. Since we're on a stable system and use version control,
-- we don't need them.
vim.opt.swapfile = false

-- Disable backup files
-- Similar to swap files, these are the ~ files Neovim creates. Version control
-- (git) is a better backup system than these files.
vim.opt.backup = false

-- Set undo history limit to 5000 changes
-- You can undo up to 5000 changes with the 'u' command. This is plenty for
-- even large editing sessions.
vim.opt.undolevels = 5000

-- Set command history to 5000 commands
-- Press ':' and use up/down arrows to see previous commands you've run.
vim.opt.history = 5000

-- Automatically read files if changed outside Neovim
-- If another program modifies a file you have open, Neovim will reload it
-- automatically. Useful when running formatters or build tools externally.
vim.opt.autoread = true

-- Allow backspace to delete anything in insert mode
-- By default, vim limits what backspace can delete. This makes it work like
-- any normal text editor: you can delete anything.
vim.opt.backspace = 'indent,eol,start'

-- Always show the sign column (left margin for diagnostics/git)
-- The sign column is where error icons, warning icons, and git change markers
-- appear. Always showing it prevents the text from jumping when errors appear.
vim.opt.signcolumn = 'yes'

-- Highlight the current line
-- This adds a subtle background highlight to the line your cursor is on,
-- making it easy to track where you are in a large file.
vim.opt.cursorline = true

-- Disable line wrapping
-- Long lines will extend past the screen edge rather than wrapping to the next
-- line. This is better for code where wrapping breaks visual structure.
-- Scroll horizontally with the arrow keys if a line is too long.
vim.opt.wrap = false

-- Case-insensitive search by default
-- Searching for /hello will match 'hello', 'Hello', and 'HELLO'.
vim.opt.ignorecase = true

-- Smart case-sensitive search
-- If you search for /hello (all lowercase), it's case-insensitive.
-- But if you search for /Hello (with capitals), it becomes case-sensitive.
-- This is the best of both worlds.
vim.opt.smartcase = true

-- ====================================================================================
--                           PLUGIN MANAGEMENT (PACKER)
-- ====================================================================================
-- Packer is a plugin manager for Neovim. It downloads and manages all the extra
-- functionality we want beyond base Neovim.

-- Bootstrap Packer (automatic installation)
-- This code checks if Packer is installed. If not, it downloads and installs it
-- automatically using git. This is the magic that makes the install script work.
local install_path = vim.fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
  vim.cmd('packadd packer.nvim')
end

-- Plugin List
-- Everything inside this function is a plugin we want to install.
-- Format: use 'username/repository' where the repository is on GitHub.
require('packer').startup(function(use)
    -- Packer manages itself (required)
    use 'wbthomason/packer.nvim'

    -- ====================================================================================
    --                            COLOR SCHEME
    -- ====================================================================================
    -- gruvbox-material: A warm, retro-inspired color scheme
    -- This is the color scheme you use on your Mac. It's easier on the eyes than
    -- harsh blue/white schemes and has excellent syntax highlighting.
    -- GitHub: https://github.com/sainnhe/gruvbox-material
    use 'sainnhe/gruvbox-material'

    -- ====================================================================================
    --                       LANGUAGE SERVER PROTOCOL (LSP)
    -- ====================================================================================
    -- LSP is the magic that makes Neovim understand your code. It provides:
    -- - Error detection as you type
    -- - Go to definition
    -- - Hover documentation
    -- - Automatic formatting
    -- Without LSP, Neovim is just a text editor. With LSP, it understands Python,
    -- Rust, Go, etc.

    -- Mason: Automatic LSP server installer
    -- Mason downloads and manages language servers for you. Without Mason, you'd
    -- have to manually install rust-analyzer, pyright, gopls, etc.
    -- GitHub: https://github.com/williamboman/mason.nvim
    use 'williamboman/mason.nvim'

    -- Mason-LSPConfig: Bridge between Mason and LSP
    -- This connects Mason (which installs servers) with nvim-lspconfig (which
    -- configures them). It ensures the servers Mason installs work with Neovim.
    use 'williamboman/mason-lspconfig.nvim'

    -- LSPConfig: Official LSP configuration plugin
    -- This provides pre-made configurations for all major language servers. Without
    -- this, you'd have to manually configure each language server's settings.
    -- GitHub: https://github.com/neovim/nvim-lspconfig
    use 'neovim/nvim-lspconfig'

    -- ====================================================================================
    --                      LANGUAGE-SPECIFIC PLUGINS
    -- ====================================================================================
    -- These plugins provide better support for specific languages beyond what LSP offers.

    -- Python indentation fixer
    -- Python's indentation rules are complex (especially for multi-line statements).
    -- This plugin ensures your Python indentation follows PEP 8 standards.
    -- GitHub: https://github.com/Vimjas/vim-python-pep8-indent
    use 'Vimjas/vim-python-pep8-indent'

    -- Rust tools
    -- Adds Rust-specific commands like running tests, viewing crate documentation,
    -- and inline type hints. Makes Rust development much smoother.
    -- GitHub: https://github.com/simrat39/rust-tools.nvim
    use 'simrat39/rust-tools.nvim'

    -- Go plugin
    -- Provides Go-specific commands like :GoBuild, :GoTest, and :GoRun. Essential
    -- if you're editing Helm templates (which use Go templates).
    -- GitHub: https://github.com/fatih/vim-go
    use 'fatih/vim-go'

    -- ====================================================================================
    --                         USER INTERFACE PLUGINS
    -- ====================================================================================
    -- These plugins improve the visual experience and navigation.

    -- Nvim-tree: File browser
    -- A sidebar file tree like VS Code's file explorer. Press Ctrl+n to toggle.
    -- Essential for navigating projects with many files.
    -- GitHub: https://github.com/nvim-tree/nvim-tree.lua
    use {
        'nvim-tree/nvim-tree.lua',
        requires = 'nvim-tree/nvim-web-devicons'
    }

    -- Lualine: Status line
    -- The bottom bar showing your current file, line number, git branch, etc.
    -- Much prettier and more informative than the default.
    -- GitHub: https://github.com/nvim-lualine/lualine.nvim
    use 'nvim-lualine/lualine.nvim'

    -- Gitsigns: Git integration
    -- Shows added/modified/deleted lines in the sign column (left margin).
    -- Essential for seeing what you've changed at a glance.
    -- GitHub: https://github.com/lewis6991/gitsigns.nvim
    use 'lewis6991/gitsigns.nvim'

    -- Indent-blankline: Indentation guides
    -- Shows vertical lines for each indentation level. Makes Python/YAML much
    -- easier to read by showing you which lines are at the same indentation.
    -- GitHub: https://github.com/lukas-reineke/indent-blankline.nvim
    use 'lukas-reineke/indent-blankline.nvim'

    -- Telescope: Fuzzy finder
    -- Press <Space>ff to search for files by name, <Space>fg to search file contents.
    -- This is how you quickly find things in large projects.
    -- GitHub: https://github.com/nvim-telescope/telescope.nvim
    use {
      'nvim-telescope/telescope.nvim',
      requires = { 'nvim-lua/plenary.nvim' }
    }

    -- Fidget: LSP progress indicator
    -- Shows a small notification when language servers are loading/analyzing.
    -- Without this, you might think Neovim is frozen when it's just waiting for LSP.
    -- GitHub: https://github.com/j-hui/fidget.nvim
    use 'j-hui/fidget.nvim'

    -- Trouble: Diagnostic viewer
    -- Opens a panel showing all errors/warnings in your project. Press <Space>xx.
    -- Much better than jumping through errors one by one.
    -- GitHub: https://github.com/folke/trouble.nvim
    use {
      'folke/trouble.nvim',
      requires = 'nvim-tree/nvim-web-devicons'
    }
end)

-- ====================================================================================
--                          LANGUAGE SERVER SETUP
-- ====================================================================================
-- Now we configure Mason to install specific language servers and set them up.

-- Initialize Mason
-- This starts Mason with default settings. The UI section customizes the
-- symbols shown in Mason's interface.
require("mason").setup({
    ui = {
        icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗"
        }
    }
})

-- Tell Mason which language servers to install
-- This list defines what gets downloaded when you run the install script.
-- Each server provides language support for specific file types:
-- - lua_ls: Lua (for editing Neovim config)
-- - rust_analyzer: Rust
-- - gopls: Go (also provides Go template support for Helm)
-- - pyright: Python (includes type checking)
-- - yamlls: YAML (Kubernetes configs, Docker Compose, etc.)
require("mason-lspconfig").setup({
    ensure_installed = {
        "lua_ls",
        "rust_analyzer",
        "gopls",
        "pyright",
        "yamlls",
    },
    automatic_installation = true,
})

-- ====================================================================================
--                            COLOR SCHEME SETUP
-- ====================================================================================
-- Apply the gruvbox-material color scheme and configure its options.

-- Enable true color support (required for good colors)
-- This was set earlier in basic settings, but we ensure it's on here too.
vim.cmd([[if has("termguicolors") | set termguicolors | endif]])

-- Apply the gruvbox-material color scheme
-- This is the actual command that changes all the colors.
vim.cmd([[colorscheme gruvbox-material]])

-- Color scheme options
-- These variables customize gruvbox-material's appearance:
vim.g.gruvbox_material_background = 'medium'
vim.g.gruvbox_material_enable_italic = 1
vim.g.gruvbox_material_better_performance = 1

-- ====================================================================================
--                            FILE BROWSER SETUP
-- ====================================================================================
-- Configure nvim-tree (the file browser sidebar)

require('nvim-tree').setup({
    filters = {
        dotfiles = false,
    },
    view = {
        width = 30,
    },
})

-- ====================================================================================
--                            STATUS LINE SETUP
-- ====================================================================================
-- Configure lualine (the bottom status bar)

require('lualine').setup({
    options = {
        theme = 'gruvbox-material',
        component_separators = { left = '', right = ''},
        section_separators = { left = '', right = ''},
    }
})

-- ====================================================================================
--                              GIT SIGNS SETUP
-- ====================================================================================
-- Configure gitsigns (shows git changes in the margin)

require('gitsigns').setup()

-- ====================================================================================
--                         INDENTATION GUIDES SETUP
-- ====================================================================================
-- Configure indent-blankline (vertical lines showing indentation levels)

require('ibl').setup({
    indent = {
        char = '│',
    },
    scope = {
        enabled = true,
        show_start = true,
    }
})

-- ====================================================================================
--                       LANGUAGE SERVER CONFIGURATION
-- ====================================================================================
-- This is where we actually configure each language server to work with Neovim.

local lspconfig = require('lspconfig')

-- Define configuration for each language server
-- We set up each server individually with its specific settings.
-- This replaces the old setup_handlers approach which was deprecated.
local servers = {
    lua_ls = {},
    gopls = {},
    pyright = {},
    yamlls = {
        settings = {
            yaml = {
                schemas = {
                    -- Kubernetes schema: validates Deployment, Service, Pod, etc.
                    ["https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.28.0-standalone-strict/all.json"] = "/*.yaml",
                },
            },
        },
    },
}

-- Apply configuration to each server
-- This loop sets up each language server using lspconfig.
-- For most servers, we use default settings (empty table {}).
-- For YAML, we provide custom schema configuration for Kubernetes.
for server, config in pairs(servers) do
    lspconfig[server].setup(config)
end

-- Rust gets special handling via rust-tools
-- rust-tools provides extra features for Rust beyond basic LSP,
-- so we configure it separately instead of through lspconfig directly.
require("rust-tools").setup({
    server = {
        settings = {
            ["rust-analyzer"] = {
                -- Run clippy (Rust linter) on save
                -- Clippy catches common mistakes and suggests improvements.
                checkOnSave = {
                    command = "clippy",
                },
            },
        },
    },
})

-- ====================================================================================
--                          LSP KEYBINDINGS
-- ====================================================================================
-- These keybindings are activated when a language server attaches to a file.
-- They provide shortcuts for common LSP actions.

-- Tutorial: Understanding Keybindings
-- In Vim, keybindings follow this pattern:
-- - Normal mode: Press keys when NOT editing (after pressing Esc)
-- - <leader> is a prefix key (Space by default)
-- - gd means "press g then d" in quick succession
--
-- Common LSP actions:
-- - gd: Go to where a function/variable is defined
-- - K: Show documentation for what's under your cursor
-- - <leader>rn: Rename a variable everywhere it's used
-- - <leader>ca: Show code actions (like auto-fixes)
-- - gr: Show all references to this function/variable
-- - <leader>f: Format the current file

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local opts = { buffer = ev.buf, noremap = true, silent = true }
    
    -- gd: Go to definition
    -- Press 'gd' when your cursor is on a function/variable name to jump to
    -- where it's defined. Press Ctrl+o to jump back.
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    
    -- K: Show hover documentation
    -- Press 'K' (capital k) to see documentation for the function/type under
    -- your cursor. Press it again to jump into the documentation window.
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    
    -- <leader>rn: Rename symbol
    -- Press Space then 'rn' to rename a variable everywhere it's used in your
    -- project. The LSP ensures all references are updated.
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
    
    -- <leader>ca: Code actions
    -- Press Space then 'ca' to see available fixes for errors or suggestions.
    -- For example, adding missing imports or fixing type errors.
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    
    -- gr: Go to references
    -- Press 'gr' to see all places where this function/variable is used.
    -- Useful for understanding impact before making changes.
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    
    -- <leader>f: Format document
    -- Press Space then 'f' to auto-format the current file according to the
    -- language's style guide (PEP 8 for Python, rustfmt for Rust, etc.)
    vim.keymap.set('n', '<leader>f', function() 
      vim.lsp.buf.format({ async = true }) 
    end, opts)
  end,
})

-- ====================================================================================
--                            KEYBINDINGS (GENERAL)
-- ====================================================================================
-- These keybindings work all the time, not just when LSP is active.

-- Tutorial: Leader Key
-- The leader key is a prefix for custom commands. By default it's Space.
-- This gives you a whole namespace of commands: <Space>f, <Space>g, <Space>t, etc.
vim.g.mapleader = " "

-- Ctrl+n: Toggle file browser
-- Press Ctrl and n together to open/close the file tree sidebar.
vim.api.nvim_set_keymap('n', '<C-n>', ':NvimTreeToggle<CR>', {noremap = true, silent = true})

-- Telescope keybindings (fuzzy finder)
-- <Space>ff: Find files by name
-- Type part of a filename and Telescope will show matches. Use arrows to navigate.
vim.api.nvim_set_keymap('n', '<leader>ff', ':Telescope find_files<CR>', {noremap = true})

-- <Space>fg: Find in files (grep)
-- Search for text across all files in your project. Like "find in files" in VS Code.
vim.api.nvim_set_keymap('n', '<leader>fg', ':Telescope live_grep<CR>', {noremap = true})

-- <Space>fb: Find in open buffers
-- Show a list of currently open files and quickly switch between them.
vim.api.nvim_set_keymap('n', '<leader>fb', ':Telescope buffers<CR>', {noremap = true})

-- <Space>fh: Find help tags
-- Search Neovim's help documentation. Try <Space>fh then type "yanking".
vim.api.nvim_set_keymap('n', '<leader>fh', ':Telescope help_tags<CR>', {noremap = true})

-- ====================================================================================
--                       ADDITIONAL PLUGIN SETUP
-- ====================================================================================

-- Fidget: LSP progress indicator
-- Shows a small notification when language servers are working.
require("fidget").setup({})

-- Trouble: Diagnostic list
-- Provides a nice panel for viewing all errors/warnings.
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

-- Keybinding for Trouble
-- <Space>xx: Toggle the diagnostic list
-- See all errors/warnings in your project in one place.
vim.api.nvim_set_keymap('n', '<leader>xx', ':TroubleToggle<CR>', {noremap = true})

-- ====================================================================================
--                         SPECIAL FILE TYPE MAPPINGS
-- ====================================================================================
-- Tell Neovim to treat certain file extensions as specific languages.

-- Treat .ixx, .cppm, .mxx files as C++
-- These are C++20 module file extensions. Rare, but good to support.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.ixx", "*.cppm", "*.mxx" },
  callback = function()
    vim.bo.filetype = "cpp"
  end
})

-- ====================================================================================
--                         PYTHON CONFIGURATION
-- ====================================================================================
-- Detect OS and set the correct Python path for the LSP.

-- Check which OS we're running on
local is_mac = vim.fn.has('macunix') == 1
local is_linux = vim.fn.has('unix') == 1 and vim.fn.has('macunix') == 0

-- Set Python path based on OS
-- This tells the Python language server where to find Python. Different systems
-- install Python in different locations.
if is_mac then
  vim.g.python3_host_prog = '/usr/local/bin/python3'
elseif is_linux then
  vim.g.python3_host_prog = '/usr/bin/python3'
end

-- ====================================================================================
--                    FORCE 2-SPACE INDENTATION FOR ALL FILES
-- ====================================================================================
-- This ensures that ALL file types use 2-space indentation, overriding any
-- filetype-specific defaults that might try to use 4 spaces or tabs.

-- Tutorial: Autocmd (Auto Commands)
-- Autocmds run commands automatically when certain events happen. This autocmd
-- runs every time Neovim detects a file's type (FileType event). It sets the
-- indentation to 2 spaces for every file type.
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
--
--  Quick Command Reference:
--  ------------------------
--  Run ~/vim_quick_reference.sh anytime you forget a command!
--
--  Essential commands to remember:
--  - :w          Save file
--  - :q          Quit
--  - :wq         Save and quit
--  - :q!         Quit without saving
--  - u           Undo
--  - Ctrl+r      Redo
--  - /pattern    Search forward
--  - ?pattern    Search backward
--  - n           Next search result
--  - dd          Delete line
--  - yy          Copy line
--  - p           Paste
--  - v           Visual mode (select text)
--  - Esc         Return to normal mode
--
--  LSP commands:
--  - gd          Go to definition
--  - K           Show documentation
--  - Space+rn    Rename
--  - Space+f     Format file
--
--  File navigation:
--  - Ctrl+n      Toggle file tree
--  - Space+ff    Find files
--  - Space+fg    Search in files
--
--  Getting help:
--  - :help topic        Show help for a topic
--  - :checkhealth       Verify Neovim setup
--  - Space+fh           Search help interactively
--
-- ====================================================================================
