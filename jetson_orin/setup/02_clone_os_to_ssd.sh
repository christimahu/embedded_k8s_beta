#!/bin/bash

# ====================================================================================
#
#                 Step 2: Clone OS to SSD (02_clone_os_to_ssd.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This script migrates the entire configured operating system from the initial
#  microSD card to a high-performance NVMe SSD.
#
#  Tutorial Goal:
#  --------------
#  The Jetson Orin platform is designed to load its initial bootloader from either
#  on-board QSPI flash or a microSD card. It cannot boot directly from an NVMe
#  drive from a cold start. Therefore, to gain the significant performance and
#  reliability benefits of an SSD, we must perform a two-stage boot process:
#
#  1. The board powers on and uses the microSD card to load the bootloader.
#  2. We configure that bootloader to immediately hand off control to the NVMe SSD,
#     which then loads and runs the full operating system.
#
#  This script automates the second part of that setup: cloning the OS and then
#  reconfiguring the bootloader to point to the SSD for all subsequent operations.
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

CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" == *"nvme"* ]]; then
    print_error "This script is intended to be run from a microSD card before migration."
    print_error "The system is already running from the NVMe SSD. Aborting."
    exit 1
fi
print_success "System is running from microSD card. Safe to proceed with migration."


# --- Part 1: OS Migration to NVMe SSD ---

print_border "Step 1: Clone OS from microSD to NVMe SSD"

SSD_DEVICE=$(lsblk -d -o NAME,ROTA | grep '0' | awk '/nvme/ {print "/dev/"$1}')
if [ -z "$SSD_DEVICE" ]; then
    print_error "No NVMe SSD detected. Please ensure it is installed correctly. Aborting."
    exit 1
fi
print_success "Detected NVMe SSD at: $SSD_DEVICE"

echo ""
echo -e "${C_RED}!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
echo -e "${C_YELLOW}This next step will completely and IRREVERSIBLY ERASE all data on the SSD.${C_RESET}"
echo -e "${C_RED}!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
read -p "> To confirm, please type 'erase ssd': " confirm_erase

if [[ "$confirm_erase" != "erase ssd" ]]; then
    print_info "Migration aborted by user. The SSD was not touched."
    exit 1
fi

echo "Preparing the SSD..."
parted -s "$SSD_DEVICE" mklabel gpt
parted -s "$SSD_DEVICE" mkpart primary ext4 0% 100%
sleep 3
SSD_PARTITION="${SSD_DEVICE}p1"

mkfs.ext4 "$SSD_PARTITION"
print_success "SSD has been partitioned and formatted."

echo "Cloning filesystem. This will take several minutes..."
MOUNT_POINT="/mnt/ssd_root"
mkdir -p "$MOUNT_POINT"
mount "$SSD_PARTITION" "$MOUNT_POINT"

rsync -axHAWX --numeric-ids --info=progress2 --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / "$MOUNT_POINT"
print_success "Filesystem cloned successfully."

echo "Updating boot configuration to use the SSD..."
SSD_UUID=$(blkid -s UUID -o value "$SSD_PARTITION")
if [ -z "$SSD_UUID" ]; then
    print_error "Could not determine the SSD's UUID. Cannot update boot config."
    umount "$MOUNT_POINT"
    exit 1
fi

sed -i "s|root=[^ ]*|root=UUID=$SSD_UUID|" "/boot/extlinux/extlinux.conf"
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
print_success "Boot configuration updated. The system will now boot from the SSD."


# --- Final Instructions ---

print_border "OS Migration Complete"
echo "The system is now configured to run from the NVMe SSD."
echo "A reboot is required to apply this change."
echo ""
echo "After rebooting:"
echo "  - Connect to the node via SSH at its static IP."
echo "  - Run 'sudo ./setup/03_strip_microsd_rootfs.sh' to secure the node."
echo ""
echo "Run 'sudo reboot' now to boot from the SSD."
