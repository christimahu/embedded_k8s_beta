#!/bin/bash

# ====================================================================================
#
#              Step 3: Set Boot Device to SSD (03_set_boot_to_ssd.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This optional script modifies the bootloader configuration to make the NVMe SSD
#  the primary operating system drive.
#
#  Tutorial Goal:
#  --------------
#  This script performs the critical "handoff" configuration. We will edit the
#  `extlinux.conf` file (which physically resides on the microSD card), changing
#  the `root=` parameter to point to the unique ID (UUID) of the SSD.
#  On the next boot, the Jetson firmware (U-Boot) will load from the microSD, read
#  this new instruction, and then pivot to load the full operating system from the
#  much faster SSD. This is a separate, deliberate step to give you full control
#  over when the boot device is changed.
#
#  Workflow:
#  ---------
#  1. Run this script after cloning the OS with `02_clone_os_to_ssd.sh`.
#  2. `sudo ./setup/03_set_boot_to_ssd.sh`
#  3. A reboot is required for this change to take effect.
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

# This command is now more robust, using flags to ensure clean list output without formatting characters.
SSD_PARTITION=$(lsblk -pnl -o NAME | awk '/nvme.*p1/')
if [ -z "$SSD_PARTITION" ]; then
    print_error "No formatted NVMe SSD partition found. Please run '02_clone_os_to_ssd.sh' first."
    exit 1
fi
print_success "Found prepared NVMe SSD partition at $SSD_PARTITION."


# --- Part 1: Update Boot Configuration ---

print_border "Step 1: Modify Bootloader Configuration"

BOOT_CONFIG_FILE="/boot/extlinux/extlinux.conf"
if grep -q "root=UUID=" "$BOOT_CONFIG_FILE"; then
    print_success "Boot configuration already points to the SSD. No changes needed."
    exit 0
fi

echo ""
echo -e "${C_YELLOW}This script will modify the bootloader to make the NVMe SSD the primary OS drive.${C_RESET}"
read -p "> Do you want to proceed? (Y/N): " confirm_set_boot

if [[ "$confirm_set_boot" != "Y" && "$confirm_set_boot" != "y" ]]; then
    print_info "Boot configuration change aborted by user."
    exit 1
fi

echo "Updating boot configuration to use the SSD..."
SSD_UUID=$(blkid -s UUID -o value "$SSD_PARTITION")
if [ -z "$SSD_UUID" ]; then
    print_error "Could not determine the SSD's UUID. Cannot update boot config."
    exit 1
fi

sed -i "s|root=[^ ]*|root=UUID=$SSD_UUID|" "$BOOT_CONFIG_FILE"
print_success "Boot configuration updated. The system will now boot from the SSD."


# --- Final Instructions ---

print_border "Boot Device Set to SSD"
echo "A reboot is required for this change to take effect."
echo "After rebooting, SSH back into this device to continue the setup."
echo ""
echo "Run 'sudo reboot' now to boot from the SSD."
