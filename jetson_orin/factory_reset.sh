#!/bin/bash

# ====================================================================================
#
#                    Jetson Node Factory Reset (factory_reset.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This script performs a complete, destructive "factory reset" of a Jetson node.
#  It is designed to be run from an OS that is currently booting from the NVMe SSD.
#
#  Tutorial Goal:
#  --------------
#  This script is the logical "undo" for the setup process. While the setup scripts
#  (specifically `03_set_boot_to_ssd.sh`) modify the bootloader to hand off to the
#  SSD, this script does the reverse. It restores a pristine OS back onto the microSD
#  card and, critically, modifies the bootloader configuration to force the system
#  to boot from that card again, returning the node to its original state.
#
#  Acquiring the OS Image (`sd-blob.img`):
#  -----------------------------------------
#  **IMPORTANT DISCLAIMER:** Links and version numbers become outdated quickly.
#  The following information is provided as a contextual example ONLY and is likely
#  out of date. It is the user's responsibility to obtain the correct OS image for
#  their specific hardware and firmware version from official NVIDIA sources.
#
#  At the time of writing, for a Jetson Orin Nano with JetPack 6.x (L4T r36.x),
#  the process was as follows:
#    - General instructions were found at: https://www.jetson-ai-lab.com/initial_setup_jon.html
#    - The specific image was downloaded from:
#      https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/jp62-orin-nano-sd-card-image.zip
#    - The `sd-blob.img` file was then produced by running:
#      `unzip jp62-orin-nano-sd-card-image.zip`
#
#  **WARNING:** Always consult the official NVIDIA Jetson documentation to determine
#  your board's firmware version and download the corresponding, official SD card
#  image. Flashing an incorrect image can lead to an unbootable state and may
#  damage the microSD card or the device itself.
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

print_border "Step 0: Pre-flight Safety Checks"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with root privileges. Please use 'sudo'."
    exit 1
fi
print_success "Running as root."

print_info "Verifying that the system is running from the NVMe SSD..."
CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" != *"nvme"* ]]; then
    print_error "CRITICAL: System is NOT booted from the NVMe SSD."
    print_error "Running this script now would make the node unbootable."
    print_error "This script is ONLY for resetting a node from a stable SSD-based OS."
    exit 1
fi
print_success "System is correctly booted from the SSD. It is safe to proceed."

IMAGE_NAME="sd-blob.img"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
IMAGE_PATH="$SCRIPT_DIR/$IMAGE_NAME"

if [ ! -f "$IMAGE_PATH" ]; then
    print_error "Pristine OS image '$IMAGE_NAME' not found in the script directory."
    print_error "Please ensure the image file is located at: $IMAGE_PATH"
    exit 1
fi
print_success "Found OS image at: $IMAGE_PATH"


# --- Part 1: Re-Image the MicroSD Card ---

print_border "Step 1: Re-Image MicroSD Card"

MICROSD_DEVICE="/dev/mmcblk0"
if [ ! -b "$MICROSD_DEVICE" ]; then
    print_error "Could not find the microSD card device at $MICROSD_DEVICE."
    exit 1
fi

echo ""
echo -e "${C_RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
echo -e "${C_YELLOW}This script will perform a complete factory reset of this node.${C_RESET}"
echo -e "${C_RED}1. ALL data on the microSD card will be PERMANENTLY ERASED.${C_RESET}"
echo -e "${C_RED}2. The boot configuration will be changed to boot from the microSD.${C_RESET}"
echo -e "${C_YELLOW}After rebooting, you will need physical access (monitor/keyboard) to${C_RESET}"
echo -e "${C_YELLOW}complete the initial Ubuntu setup on the fresh OS.${C_RESET}"
echo -e "${C_RED}This action is IRREVERSIBLE.${C_RESET}"
echo ""
read -p "> To confirm this destructive action, please type 'reset this node': " confirm_reset

if [[ "$confirm_reset" != "reset this node" ]]; then
    print_info "Reset aborted by user. No changes were made."
    exit 1
fi

echo "Unmounting microSD card partitions (if mounted)..."
umount ${MICROSD_DEVICE}p* &> /dev/null

echo "Writing '$IMAGE_NAME' to $MICROSD_DEVICE... This will take several minutes."
dd if="$IMAGE_PATH" of="$MICROSD_DEVICE" bs=4M conv=fdatasync status=progress

sync
print_success "MicroSD card has been re-imaged."


# --- Part 2: Modify Boot Configuration ---

print_border "Step 2: Update Boot Configuration to Boot from MicroSD"

# The kernel needs a moment to re-read the partition table after `dd`.
partprobe "$MICROSD_DEVICE"
sleep 3

BOOT_CONFIG_FILE="/boot/extlinux/extlinux.conf"
if [ ! -f "$BOOT_CONFIG_FILE" ]; then
    print_error "Could not find boot configuration file at $BOOT_CONFIG_FILE."
    print_error "This may happen if the /boot directory is not mounted correctly."
    print_error "Cannot change boot device. The system will continue to boot from the SSD."
    exit 1
fi

echo "Modifying bootloader to point to the microSD card..."
# This is the failsafe step. We explicitly find the `root=UUID=` line (the SSD boot
# instruction) and change it back to `root=/dev/mmcblk0p1` to be absolutely certain.
sed -i "s|root=UUID=[^ ]*|root=/dev/mmcblk0p1|" "$BOOT_CONFIG_FILE"
print_success "Boot configuration updated."


# --- Final Instructions ---

print_border "Factory Reset Complete"
echo ""
echo -e "${C_YELLOW}The node is now configured to boot from the freshly imaged microSD card.${C_RESET}"
echo "A reboot is required to complete the process."
echo ""
echo "After rebooting:"
echo "  1. Connect a monitor and keyboard to the Jetson."
echo "  2. Complete the initial on-screen Ubuntu setup."
echo "  3. Once on the desktop, you will need to re-clone this repository to begin"
echo "     the setup process again with 'setup/01_config_headless.sh'."
echo ""
echo "Run 'sudo reboot' now to boot into the fresh OS."
