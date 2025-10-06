#!/bin/bash

# ====================================================================================
#
#                         Install Neovim (install_nvim.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs Neovim and all language servers via system packages for reliable,
#  deterministic cluster provisioning. No Mason, no compilation delays, no network
#  timeouts. This script is designed for automation and repeatability.
#
# ====================================================================================

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

print_info "Installing base dependencies..."
apt-get update
apt-get install -y git curl software-properties-common

if [ $? -ne 0 ]; then
    print_error "Failed to install dependencies. Check your network connection."
    exit 1
fi
print_success "Dependencies installed."

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

print_info "Creating configuration directory: $CONFIG_DEST_DIR"
sudo -u "$TARGET_USER" mkdir -p "$CONFIG_DEST_DIR"

print_info "Copying init.lua..."
cp "$CONFIG_SOURCE_PATH" "$CONFIG_DEST_PATH"
chown "$TARGET_USER:$TARGET_USER" "$CONFIG_DEST_PATH"
print_success "Neovim configuration copied."

# --- Part 3: Install Neovim Plugins ---

print_border "Step 3: Installing Neovim Plugins via Packer"

print_info "This may take several minutes as plugins are installed and compiled..."

sudo -u "$TARGET_USER" nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

if [ $? -ne 0 ]; then
    print_error "Plugin installation failed."
    exit 1
else
    print_success "All Neovim plugins installed successfully."
fi

# --- Part 4: Install Language Servers via System Packages ---

print_border "Step 4: Installing Language Servers (System Packages)"

# Install Node.js and npm (needed for pyright and yaml-language-server)
print_info "Installing Node.js and npm..."
apt-get install -y nodejs npm

if [ $? -ne 0 ]; then
    print_error "Failed to install Node.js/npm."
    exit 1
fi
print_success "Node.js and npm installed."

# Install pyright (Python language server)
print_info "Installing pyright..."
npm install -g pyright

if ! command -v pyright &> /dev/null; then
    print_error "Failed to install pyright."
    exit 1
fi
print_success "pyright installed: $(pyright --version)"

# Install yaml-language-server
print_info "Installing yaml-language-server..."
npm install -g yaml-language-server

if ! command -v yaml-language-server &> /dev/null; then
    print_error "Failed to install yaml-language-server."
    exit 1
fi
print_success "yaml-language-server installed."

# Install lua-language-server
print_info "Installing lua-language-server..."
apt-get install -y lua-language-server

if ! command -v lua-language-server &> /dev/null; then
    print_error "Failed to install lua-language-server."
    exit 1
fi
print_success "lua-language-server installed."

# Install Go and gopls
print_info "Installing Go..."
apt-get install -y golang-go

if [ $? -ne 0 ]; then
    print_error "Failed to install Go."
    exit 1
fi
print_success "Go installed."

print_info "Installing gopls..."
export GOPATH="$TARGET_HOME/go"
sudo -u "$TARGET_USER" bash -c "export GOPATH=$TARGET_HOME/go && go install golang.org/x/tools/gopls@latest"

# Add Go bin to PATH
GO_BIN_PATH="$TARGET_HOME/go/bin"
if [ -d "$GO_BIN_PATH" ]; then
    if ! grep -q "$GO_BIN_PATH" "$TARGET_HOME/.bashrc"; then
        echo "" >> "$TARGET_HOME/.bashrc"
        echo "# Go binaries" >> "$TARGET_HOME/.bashrc"
        echo "export PATH=\"\$PATH:$GO_BIN_PATH\"" >> "$TARGET_HOME/.bashrc"
        print_success "Added Go bin directory to PATH."
    fi
fi

if [ ! -f "$GO_BIN_PATH/gopls" ]; then
    print_error "gopls installation failed."
    exit 1
fi
print_success "gopls installed."

# Install rust-analyzer
print_info "Installing rust-analyzer..."
apt-get install -y rust-analyzer

if ! command -v rust-analyzer &> /dev/null; then
    print_error "Failed to install rust-analyzer."
    exit 1
fi
print_success "rust-analyzer installed."

# --- Part 5: Update .bashrc ---

print_border "Step 5: Creating vim alias in .bashrc"

BASHRC_PATH="$TARGET_HOME/.bashrc"
ALIAS_LINE="alias vim='nvim'"

if grep -qF "$ALIAS_LINE" "$BASHRC_PATH"; then
    print_success "Alias 'vim=nvim' already exists in $BASHRC_PATH."
else
    print_info "Adding alias to $BASHRC_PATH..."
    echo "" >> "$BASHRC_PATH"
    echo "# Alias for Neovim" >> "$BASHRC_PATH"
    echo "$ALIAS_LINE" >> "$BASHRC_PATH"
    print_success "Alias added to $BASHRC_PATH."
fi

# --- Part 6: Copy Quick Reference Script ---

print_border "Step 6: Installing Vim Quick Reference"

QUICK_REF_SOURCE="$SCRIPT_DIR/vim_quick_reference.sh"
QUICK_REF_DEST="$TARGET_HOME/vim_quick_reference.sh"

if [ -f "$QUICK_REF_SOURCE" ]; then
    print_info "Copying vim quick reference script..."
    cp "$QUICK_REF_SOURCE" "$QUICK_REF_DEST"
    chown "$TARGET_USER:$TARGET_USER" "$QUICK_REF_DEST"
    chmod +x "$QUICK_REF_DEST"
    print_success "Quick reference installed at: $QUICK_REF_DEST"
else
    print_info "Quick reference script not found. Skipping."
fi

# --- Final Instructions ---

print_border "Setup Complete"
echo ""
echo -e "${C_GREEN}Neovim installation successful!${C_RESET}"
echo ""
echo "All language servers installed via system packages:"
echo "  ✓ pyright (Python)"
echo "  ✓ gopls (Go)"
echo "  ✓ yaml-language-server (YAML/Kubernetes)"
echo "  ✓ lua-language-server (Lua)"
echo "  ✓ rust-analyzer (Rust)"
echo ""
echo -e "${C_BLUE}To activate the 'vim' alias in your current terminal, run:${C_RESET}"
echo ""
echo -e "    ${C_GREEN}source ~/.bashrc${C_RESET}"
echo ""
echo "All nodes in your cluster are now identically configured."
echo ""
