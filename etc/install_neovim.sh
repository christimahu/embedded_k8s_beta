#!/bin/bash

# ============================================================================
#
#                    Install Neovim (install_neovim.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs a minimal, robust Neovim setup designed for quick edits on headless
#  cluster nodes, providing a modern terminal-based editing experience.
#
#  Tutorial Goal:
#  --------------
#  This script demonstrates how to create a lightweight, self-contained "appliance"
#  out of Neovim. We will focus on core editor quality-of-life improvements that
#  do not require heavy external runtimes like Node.js. You will learn how Neovim's
#  plugin manager (Packer) and its built-in Tree-sitter engine can provide a
#  rich, stable editing experience perfect for automated deployments.
#
#  Prerequisites:
#  --------------
#  - Completed: Base OS setup.
#  - Files: `init.lua` and `vim_quick_reference.sh` must be in the same directory.
#  - Network: SSH access and an active internet connection.
#  - Time: ~5-10 minutes.
#
#  Workflow:
#  ---------
#  Run this script on any node where you want a modern terminal editor. It will
#  configure Neovim for the user who invokes the script with `sudo`.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04"

set -euo pipefail
trap 'print_error "Script failed at line $LINENO"' ERR

# ============================================================================
#                           HELPER FUNCTIONS
# ============================================================================

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_MAGENTA='\033[0;35m'

print_success() { echo -e "${C_GREEN}[OK] $1${C_RESET}"; }
print_error() { echo -e "${C_RED}[ERROR] $1${C_RESET}"; }
print_info() { echo -e "${C_YELLOW}[INFO] $1${C_RESET}"; }
print_warning() { echo -e "${C_MAGENTA}[WARNING] $1${C_RESET}"; }
print_border() {
    echo ""
    echo "============================================================================"
    echo " $1"
    echo "============================================================================"
}

# ============================================================================
#                         STEP 0: PRE-FLIGHT CHECKS
# ============================================================================

print_border "Step 0: Pre-flight Checks"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with root privileges. Please use 'sudo'."
    exit 1
fi
print_success "Running as root."

if [ -n "$SUDO_USER" ]; then
    readonly TARGET_USER="$SUDO_USER"
    readonly TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
print_success "Will install and configure for user: $TARGET_USER"

readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ ! -f "$SCRIPT_DIR/init.lua" ]; then
    print_error "Neovim config file 'init.lua' not found in script directory."
    exit 1
fi
print_success "Found required configuration file 'init.lua'."

# ============================================================================
#                STEP 1: INSTALL NEOVIM AND DEPENDENCIES
# ============================================================================

print_border "Step 1: Installing Neovim and Dependencies"

print_info "Installing base dependencies (git, build-essential)..."
# --- Tutorial: Required Dependencies ---
# `git` is required by the Packer plugin manager to clone plugins from GitHub.
# `build-essential` provides the C/C++ compiler toolchain needed to build the
# Tree-sitter parsers for fast, accurate syntax highlighting.
# ---
sudo apt-get update
sudo apt-get install -y git software-properties-common build-essential
print_success "Dependencies installed."

print_info "Adding Neovim PPA for the latest version..."
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt-get update
print_success "PPA added successfully."

print_info "Installing Neovim..."
sudo apt-get install -y neovim
print_success "Neovim installed: $(nvim --version | head -1)"

# ============================================================================
#                  STEP 2: CONFIGURE NEOVIM FOR TARGET USER
# ============================================================================

print_border "Step 2: Configuring Neovim for user '$TARGET_USER'"

readonly CONFIG_DEST_DIR="$TARGET_HOME/.config/nvim"
readonly CONFIG_DEST_PATH="$CONFIG_DEST_DIR/init.lua"

print_info "Creating configuration directory: $CONFIG_DEST_DIR"
sudo -u "$TARGET_USER" mkdir -p "$CONFIG_DEST_DIR"

print_info "Copying init.lua..."
sudo cp "$SCRIPT_DIR/init.lua" "$CONFIG_DEST_PATH"
sudo chown "$TARGET_USER:$TARGET_USER" "$CONFIG_DEST_PATH"
print_success "Neovim configuration copied."

# ============================================================================
#             STEP 3: INSTALL PLUGINS AND TREE-SITTER PARSERS
# ============================================================================

print_border "Step 3: Installing Plugins and Tree-sitter Parsers"

print_info "This may take a minute as plugins and parsers are installed..."
# --- Tutorial: Headless Plugin Installation ---
# This command is the key to a fully automated setup. It opens Neovim without a
# UI (`--headless`), runs PackerSync to download all plugins defined in init.lua,
# and automatically quits when finished. This prevents any interactive prompts
# and makes the installation repeatable and script-friendly.
# ---
sudo -u "$TARGET_USER" nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
print_success "All Neovim plugins and Tree-sitter parsers installed."

# ============================================================================
#                       STEP 4: FINALIZE USER SETUP
# ============================================================================

print_border "Step 4: Finalizing User Setup"

readonly BASHRC_PATH="$TARGET_HOME/.bashrc"
readonly ALIAS_LINE="alias vim='nvim'"
if ! grep -qF "$ALIAS_LINE" "$BASHRC_PATH"; then
    print_info "Adding 'vim' alias to $BASHRC_PATH..."
    echo -e "\n# Alias for Neovim (added by embedded_k8s)\n$ALIAS_LINE" >> "$BASHRC_PATH"
    print_success "Alias added."
fi

readonly QUICK_REF_SOURCE="$SCRIPT_DIR/vim_quick_reference.sh"
readonly QUICK_REF_DEST="$TARGET_HOME/vim_quick_reference.sh"
if [ -f "$QUICK_REF_SOURCE" ]; then
    sudo cp "$QUICK_REF_SOURCE" "$QUICK_REF_DEST"
    sudo chown "$TARGET_USER:$TARGET_USER" "$QUICK_REF_DEST"
    sudo chmod +x "$QUICK_REF_DEST"
    print_success "Vim quick reference installed at: $QUICK_REF_DEST"
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete"
print_success "Lean Neovim setup is complete!"
echo ""
echo "Key features:"
echo "  ✓ Modern UI (Colors, File Tree, Status Line)"
echo "  ✓ Fast File Finding (Telescope)"
echo "  ✓ Advanced Syntax Highlighting (Tree-sitter)"
echo ""
echo "To activate the 'vim' alias in your current terminal, run:"
echo "    source ~/.bashrc"
echo ""
echo "To start the editor, simply run:"
echo "    nvim"
