#!/bin/bash

# ====================================================================================
#
#                    Install Neovim (install_neovim.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs a minimal, robust Neovim setup designed for quick edits on headless
#  cluster nodes. This script provides a modern, terminal-based editing experience
#  that is significantly better than vanilla Vim, without adding unnecessary bloat
#  or external dependencies to the host operating system.
#
#  Tutorial Goal:
#  --------------
#  This script demonstrates how to create a lightweight, self-contained "appliance"
#  out of Neovim. Instead of a full-fledged IDE with language servers that require
#  external runtimes (like Node.js or Go), we will focus on core editor quality-of-
#  life improvements. You will learn how Neovim's plugin manager (Packer) and its
#  built-in Tree-sitter engine can provide a rich editing experience that is both
#  powerful and extremely stable for automated deployments.
#
#  Philosophy - The "Neovim Appliance":
#  ------------------------------------
#  - No External Runtimes: This setup intentionally avoids Language Server Protocol
#    (LSP) plugins that require installing `npm`, `go`, `pip`, etc., on the host.
#    The cluster nodes should remain as lean as possible.
#  - Fully Automated: After this script runs, the `nvim` command works perfectly on
#    first launch with no popups, errors, or manual configuration steps required.
#  - Highlighting via Tree-sitter: We use Neovim's modern, built-in Tree-sitter
#    engine. It parses code like a compiler, providing far more accurate and
#    intelligent syntax highlighting than traditional regex-based methods.
#  - Core Quality of Life: This configuration provides the essentials for a great
#    editing experience: a file browser, a fuzzy finder for quickly opening files,
#    a clean status line, and a beautiful color scheme.
#
# ====================================================================================

# --- Helper Functions for Better Output ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

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

print_info "Installing base dependencies (git, build-essential for Tree-sitter)..."
apt-get update
# `git` is required by the Packer plugin manager to clone plugins.
# `build-essential` provides the C++ compiler needed to build Tree-sitter parsers.
apt-get install -y git software-properties-common build-essential

if [ $? -ne 0 ]; then
    print_error "Failed to install dependencies. Check your network connection."
    exit 1
fi
print_success "Dependencies installed."

print_info "Adding Neovim unstable PPA for latest version..."
add-apt-repository ppa:neovim-ppa/unstable -y
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
    exit 1
fi

print_info "Creating configuration directory: $CONFIG_DEST_DIR"
sudo -u "$TARGET_USER" mkdir -p "$CONFIG_DEST_DIR"

print_info "Copying init.lua..."
cp "$CONFIG_SOURCE_PATH" "$CONFIG_DEST_PATH"
chown "$TARGET_USER:$TARGET_USER" "$CONFIG_DEST_PATH"
print_success "Neovim configuration copied."

# --- Part 3: Install Neovim Plugins ---

print_border "Step 3: Installing Neovim Plugins and Tree-sitter Parsers"

print_info "This may take several minutes as plugins and parsers are installed..."
# This command performs the critical final setup step non-interactively.
# It opens Neovim without a UI, runs PackerSync to download all the plugins,
# and then automatically triggers the Tree-sitter installation defined in init.lua.
sudo -u "$TARGET_USER" nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

if [ $? -ne 0 ]; then
    print_error "Plugin installation failed."
else
    print_success "All Neovim plugins and Tree-sitter parsers installed."
fi

# --- Part 4: Finalize Setup ---

print_border "Step 4: Finalizing User Setup"

# Create vim alias in .bashrc for convenience
BASHRC_PATH="$TARGET_HOME/.bashrc"
ALIAS_LINE="alias vim='nvim'"
if ! grep -qF "$ALIAS_LINE" "$BASHRC_PATH"; then
    print_info "Adding 'vim' alias to $BASHRC_PATH..."
    echo "" >> "$BASHRC_PATH"
    echo "# Alias for Neovim" >> "$BASHRC_PATH"
    echo "$ALIAS_LINE" >> "$BASHRC_PATH"
    print_success "Alias added."
fi

# Copy quick reference script
QUICK_REF_SOURCE="$SCRIPT_DIR/vim_quick_reference.sh"
QUICK_REF_DEST="$TARGET_HOME/vim_quick_reference.sh"
if [ -f "$QUICK_REF_SOURCE" ]; then
    cp "$QUICK_REF_SOURCE" "$QUICK_REF_DEST"
    chown "$TARGET_USER:$TARGET_USER" "$QUICK_REF_DEST"
    chmod +x "$QUICK_REF_DEST"
    print_success "Vim quick reference installed at: $QUICK_REF_DEST"
fi

# --- Final Instructions ---

print_border "Setup Complete"
echo ""
echo -e "${C_GREEN}Lean Neovim setup is complete!${C_RESET}"
echo ""
echo "Key features:"
echo "  ✓ Modern UI (Colors, File Tree, Status Line)"
echo "  ✓ Fast File Finding (Telescope)"
echo "  ✓ Advanced Syntax Highlighting (Tree-sitter)"
echo "  ✗ No heavy language servers or external dependencies."
echo ""
echo -e "${C_BLUE}To activate the 'vim' alias in your current terminal, run:${C_RESET}"
echo ""
echo -e "    ${C_GREEN}source ~/.bashrc${C_RESET}"
echo ""
