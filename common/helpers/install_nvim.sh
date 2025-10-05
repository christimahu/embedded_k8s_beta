#!/bin/bash

# ====================================================================================
#
#                         Install Neovim (install_nvim.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs Neovim and configures it using the provided init.lua file.
#
#  Workflow:
#  ---------
#  1. Installs Neovim and dependencies.
#  2. Creates the necessary configuration directory for the user running the script.
#  3. Copies the init.lua file into the configuration directory.
#  4. Installs all Neovim plugins via the Packer package manager defined in init.lua.
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
apt-get update
apt-get install -y git curl fuse
print_success "Dependencies installed."

print_info "Downloading latest Neovim AppImage for ARM64..."
curl -L https://github.com/neovim/neovim/releases/latest/download/nvim.appimage -o /tmp/nvim.appimage
if [ $? -ne 0 ]; then
    print_error "Failed to download Neovim AppImage. Aborting."
    exit 1
fi

chmod +x /tmp/nvim.appimage
mv /tmp/nvim.appimage /usr/local/bin/nvim
print_success "Neovim installed to /usr/local/bin/nvim"


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
# Run as the target user to ensure correct permissions from the start
sudo -u "$TARGET_USER" mkdir -p "$CONFIG_DEST_DIR"

print_info "Copying init.lua..."
# Copy the file and then set ownership, as root is performing the copy
cp "$CONFIG_SOURCE_PATH" "$CONFIG_DEST_PATH"
chown "$TARGET_USER:$TARGET_USER" "$CONFIG_DEST_PATH"
print_success "Neovim configuration copied."


# --- Part 3: Install Neovim Plugins ---

print_border "Step 3: Installing Neovim Plugins via Packer"
print_info "This may take a few minutes..."

# We run Neovim headlessly as the target user to trigger Packer to sync.
# The command tells packer to quit automatically once it's done.
sudo -u "$TARGET_USER" nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

if [ $? -ne 0 ]; then
    print_error "Plugin installation failed. Please run 'nvim' and ':PackerSync' manually to debug."
else
    print_success "All Neovim plugins installed successfully."
fi


# --- Part 4: Update .bashrc ---

print_border "Step 4: Creating vim alias in .bashrc"
BASHRC_PATH="$TARGET_HOME/.bashrc"
ALIAS_LINE="alias vim='nvim'"

if grep -qF "$ALIAS_LINE" "$BASHRC_PATH"; then
    print_success "Alias 'vim=nvim' already exists in $BASHRC_PATH."
else
    print_info "Adding alias to $BASHRC_PATH..."
    echo "" >> "$BASHRC_PATH"
    echo "# Alias for Neovim" >> "$BASHRC_PATH"
    echo "$ALIAS_LINE" >> "$BASHRC_PATH"
    print_success "Alias added."
fi


# --- Final Instructions ---

print_border "Setup Complete"
print_info "Neovim and all helper tools have been installed for user '$TARGET_USER'."
echo "Please start a new terminal session or run 'source ~/.bashrc' for the 'vim' alias to take effect."
