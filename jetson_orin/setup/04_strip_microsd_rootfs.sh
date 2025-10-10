#!/bin/bash
# ============================================================================
#
#        Step 4: Strip MicroSD Root Filesystem (04_strip_microsd_rootfs.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This is an optional but highly recommended security-hardening script. Now that
#  the full operating system is running from the NVMe SSD, the OS files on the
#  microSD card are redundant. This script removes them, leaving only the essential
#  bootloader files in the `/boot` directory.
#
#  Tutorial Goal:
#  --------------
#  We are converting the microSD card from a full OS disk into a simple "key"
#  that just starts the boot process. Leaving a complete, un-updated OS on the
#  microSD is a security risk. An attacker with physical access could revert the
#  boot config and load that old OS, bypassing any security patches we apply to
#  the SSD. By "stripping" the root filesystem, we eliminate this attack
#  vector and ensure the SSD is the single source of truth for the running OS.
#
#  Prerequisites:
#  --------------
#  - Completed: `03_set_boot_to_ssd.sh` and rebooted the system.
#  - Hardware: System must be booted and running from the NVMe SSD.
#  - Network: SSH access to the Jetson.
#  - Time: ~2 minutes.
#
#  Workflow:
#  ---------
#  Run this script ONLY after you have rebooted and confirmed you are running
#  from the NVMe SSD.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="JetPack 5.1.2, Ubuntu 20.04"

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

print_info "Verifying that the system is running from the NVMe SSD..."
CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" != *"nvme"* ]]; then
  print_error "CRITICAL: System is NOT booted from the NVMe SSD."
  print_error "Running this script now would permanently destroy your current OS."
  exit 1
fi
print_success "System is correctly booted from the SSD. It is safe to proceed."


# --- Part 1: Wipe the microSD card ---

print_border "Step 1: Strip Root Filesystem from MicroSD Card"

MICROSD_PARTITION="/dev/mmcblk0p1"
MOUNT_POINT="/mnt/microsd_to_clean"

if [ ! -b "$MICROSD_PARTITION" ]; then
    print_error "Could not find the microSD card partition at $MICROSD_PARTITION."
    exit 1
fi

echo -e "${C_RED}!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
echo -e "${C_YELLOW}This script will permanently delete the old OS from the microSD card.${C_RESET}"
echo -e "${C_YELLOW}The essential /boot directory WILL BE PRESERVED.${C_RESET}"
echo -e "${C_RED}This action cannot be undone.${C_RESET}"
read -p "> To confirm, please type 'strip rootfs': " confirm_wipe

if [[ "$confirm_wipe" != "strip rootfs" ]]; then
    print_info "Cleanup aborted by user. No files were deleted."
    exit 1
fi

echo "Mounting $MICROSD_PARTITION to $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
if ! mountpoint -q "$MOUNT_POINT"; then
    mount "$MICROSD_PARTITION" "$MOUNT_POINT"
fi

echo "Deleting all files and directories from microSD except '/boot'..."
find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -not -name "boot" -exec rm -rf {} +
print_success "Old OS files have been deleted."

echo "Unmounting the microSD card partition..."
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

# --- Final Instructions ---
print_border "MicroSD Cleanup Complete"
print_success "The microSD card is now a minimal and secure boot device."
echo "The next step is to update the OS packages."
echo ""
echo "Run 'sudo ./setup/05_update_os.sh' now to proceed."
