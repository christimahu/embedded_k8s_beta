#!/bin/bash

# ====================================================================================
#
#                         Install Neovim (install_nvim.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs the latest version of Neovim from the unstable PPA and configures it
#  with a minimal, well-documented init.lua file tailored for occasional editing
#  of Kubernetes configurations, Helm templates, and hotfixes to Python/Rust/Go code.
#
#  Tutorial Goal:
#  --------------
#  This script demonstrates how to install modern development tools on ARM64 systems
#  like the Jetson Orin. We use a PPA (Personal Package Archive) to get the latest
#  Neovim version rather than Ubuntu's default (which is often outdated). The script
#  also sets up the correct directory structure for Neovim configuration and installs
#  all plugins automatically.
#
#  Why Neovim Instead of Vim?:
#  ----------------------------
#  While traditional vim is powerful, Neovim offers several advantages for our use case:
#  - Built-in LSP (Language Server Protocol) support for intelligent code editing
#  - Better plugin ecosystem with modern features
#  - Asynchronous operations (faster for operations like file searching)
#  - More active development and better ARM64 support
#  - Lua configuration (more powerful than vimscript)
#
#  For simple config edits, vim would be sufficient. But for debugging Python ML code
#  that won't run in Docker on macOS, or Rust binaries that compile on macOS but fail
#  on ARM64, you need LSP to catch platform-specific issues. Neovim provides this
#  without the complexity of setting up vim with external plugins.
#
#  What Gets Installed:
#  --------------------
#  - Neovim (latest from PPA)
#  - init.lua with minimal plugins:
#    * gruvbox-material (color scheme)
#    * Mason (LSP server installer)
#    * Language servers: pyright (Python), rust-analyzer (Rust), gopls (Go), yaml-language-server
#    * nvim-tree (file browser)
#    * Basic LSP configuration for diagnostics and formatting
#  - A 'vim' alias pointing to nvim for convenience
#
#  Workflow:
#  ---------
#  1. Installs Neovim and dependencies.
#  2. Creates the necessary configuration directory for the user running the script.
#  3. Copies the init.lua file into the configuration directory.
#  4. Runs Neovim headlessly to install all plugins via Packer.
#  5. Sets up a 'vim' alias in the user's .bashrc for convenience.
#
# ====================================================================================

# --- Helper Functions for Better Output ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'

print_success() {
    echo -e "${C_GREEN}[OK] $1${C_RESET}"
}
print_error() {
    echo -e "${C_RED}[ERROR] $1${C_RESET}"
}
print_info() {
    echo -e "${C_YELLOW}[INFO] $1${C_RESET}"
}
print_border() {
    echo ""
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    echo " $1"
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
}

# --- Initial Sanity Checks ---

print_border "Step 0: Pre-flight Checks"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with root privileges. Please use 'sudo'."
    exit 1
fi
print_success "Running as root."

# Determine the user who is actually running the script, not 'root'
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
print_success "Will install and configure for user: $TARGET_USER"

# --- Part 1: Install Neovim and Dependencies ---

print_border "Step 1: Installing Neovim and Dependencies"

# --- Tutorial: Why These Dependencies ---
# git: Required by Packer (the plugin manager) to clone plugin repositories
# curl: Used by plugin installers to download language servers and tools
# software-properties-common: Provides the add-apt-repository command for adding PPAs
# ---

print_info "Installing base dependencies..."
apt-get update
apt-get install -y git curl software-properties-common

if [ $? -ne 0 ]; then
    print_error "Failed to install dependencies. Check your network connection."
    exit 1
fi
print_success "Dependencies installed."

# --- Tutorial: Using a PPA for Latest Neovim ---
# Ubuntu's default repositories often have outdated software. PPAs (Personal Package
# Archives) are maintained by the community or software authors and provide newer
# versions. The neovim-ppa/unstable PPA gives us the latest Neovim release.
# 
# Why "unstable"? Despite the name, this PPA contains the latest stable release of
# Neovim. The "unstable" refers to it being updated frequently, not that the software
# itself is unstable. For a development tool like Neovim, we want the latest features
# and bug fixes.
# ---

print_info "Adding Neovim unstable PPA for latest version..."
add-apt-repository ppa:neovim-ppa/unstable -y

if [ $? -ne 0 ]; then
    print_error "Failed to add Neovim PPA. Aborting."
    exit 1
fi

apt-get update
print_success "PPA added successfully."

print_info "Installing Neovim from PPA..."
apt-get install -y neovim

if ! command -v nvim &> /dev/null; then
    print_error "Neovim installation failed. Aborting."
    exit 1
fi

NVIM_VERSION=$(nvim --version | head -1)
print_success "Neovim installed: $NVIM_VERSION"

# --- Part 2: Configure Neovim ---

print_border "Step 2: Configuring Neovim for user '$TARGET_USER'"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG_SOURCE_PATH="$SCRIPT_DIR/init.lua"
CONFIG_DEST_DIR="$TARGET_HOME/.config/nvim"
CONFIG_DEST_PATH="$CONFIG_DEST_DIR/init.lua"

if [ ! -f "$CONFIG_SOURCE_PATH" ]; then
    print_error "Neovim configuration file 'init.lua' not found in the same directory as this script."
    print_error "Please ensure both files are in: $SCRIPT_DIR"
    exit 1
fi

# --- Tutorial: Neovim Configuration Location ---
# Neovim follows the XDG Base Directory specification, which means configuration
# files go in ~/.config/nvim/ instead of the home directory. This keeps your home
# directory cleaner. The init.lua file is the main configuration file (equivalent
# to .vimrc in traditional vim, but using Lua instead of vimscript).
# ---

print_info "Creating configuration directory: $CONFIG_DEST_DIR"
sudo -u "$TARGET_USER" mkdir -p "$CONFIG_DEST_DIR"

print_info "Copying init.lua..."
cp "$CONFIG_SOURCE_PATH" "$CONFIG_DEST_PATH"
chown "$TARGET_USER:$TARGET_USER" "$CONFIG_DEST_PATH"
print_success "Neovim configuration copied."

# --- Part 3: Install Neovim Plugins ---

print_border "Step 3: Installing Neovim Plugins via Packer"

# --- Tutorial: Plugin Installation Process ---
# Neovim plugins are managed by Packer, a plugin manager written in Lua. When we
# run Neovim headlessly with the PackerSync command, it:
# 1. Reads the init.lua file to see what plugins are requested
# 2. Clones each plugin's git repository to ~/.local/share/nvim/site/pack/packer/
# 3. Runs any post-install hooks (like compiling Tree-sitter parsers)
# 
# The --headless flag runs Neovim without a UI, and we tell it to quit automatically
# when PackerSync completes. This entire process can take 2-5 minutes on ARM64 as
# some components need to be compiled from source.
# ---

print_info "This may take several minutes on ARM64 as plugins are installed and compiled..."
print_info "Language servers (pyright, rust-analyzer, gopls, yaml-language-server) will be downloaded..."

# Run Neovim headlessly to trigger Packer installation
sudo -u "$TARGET_USER" nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

if [ $? -ne 0 ]; then
    print_error "Plugin installation failed. This is often due to network issues or ARM64 compatibility."
    print_info "You can manually run ':PackerSync' inside nvim to retry."
else
    print_success "All Neovim plugins installed successfully."
fi

# --- Part 4: Update .bashrc ---

print_border "Step 4: Creating vim alias in .bashrc"

BASHRC_PATH="$TARGET_HOME/.bashrc"
ALIAS_LINE="alias vim='nvim'"

# --- Tutorial: Shell Aliases ---
# A shell alias is a shortcut command. By creating 'alias vim=nvim', we make it so
# typing 'vim' at the command line actually runs 'nvim'. This is convenient because:
# 1. Most muscle memory is for typing 'vim', not 'nvim'
# 2. Many scripts and tools call 'vim' by default
# 3. It's easier to type
# The alias only affects the specific user, not system-wide.
# ---

if grep -qF "$ALIAS_LINE" "$BASHRC_PATH"; then
    print_success "Alias 'vim=nvim' already exists in $BASHRC_PATH."
else
    print_info "Adding alias to $BASHRC_PATH..."
    echo "" >> "$BASHRC_PATH"
    echo "# Alias for Neovim" >> "$BASHRC_PATH"
    echo "$ALIAS_LINE" >> "$BASHRC_PATH"
    print_success "Alias added."
fi

# --- Part 5: Copy Quick Reference Script ---

print_border "Step 5: Installing Vim Quick Reference"

QUICK_REF_SOURCE="$SCRIPT_DIR/vim_quick_reference.sh"
QUICK_REF_DEST="$TARGET_HOME/vim_quick_reference.sh"

if [ -f "$QUICK_REF_SOURCE" ]; then
    print_info "Copying vim quick reference script..."
    cp "$QUICK_REF_SOURCE" "$QUICK_REF_DEST"
    chown "$TARGET_USER:$TARGET_USER" "$QUICK_REF_DEST"
    chmod +x "$QUICK_REF_DEST"
    print_success "Quick reference installed at: $QUICK_REF_DEST"
    print_info "Run '~/vim_quick_reference.sh' anytime you need a command reminder."
else
    print_info "Quick reference script not found. Skipping."
fi

# --- Final Instructions ---

print_border "Setup Complete"
print_info "Neovim and all plugins have been installed for user '$TARGET_USER'."
echo ""
echo "To use Neovim:"
echo "  1. Start a new terminal session or run: source ~/.bashrc"
echo "  2. Type 'vim' or 'nvim' to start"
echo "  3. Run '~/vim_quick_reference.sh' for a command cheatsheet"
echo ""
echo "First-time setup:"
echo "  - Language servers will download on first use (this is normal)"
echo "  - Press ':checkhealth' in nvim to verify everything works"
echo "  - See init.lua comments for detailed explanations of every setting"
echo ""
echo "Official resources:"
echo "  - Neovim documentation: https://neovim.io/doc/"
echo "  - Vim basics tutorial: Run 'vimtutor' in your terminal"
echo "  - Interactive Vim tutorial: https://www.openvim.com/"
