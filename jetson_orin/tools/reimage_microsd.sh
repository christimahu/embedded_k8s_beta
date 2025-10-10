#!/bin/bash

#!/bin-bash

# ============================================================================
#
#                  Re-image MicroSD Card (reimage_microsd.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Re-images the microSD card with a fresh OS from the `sd-blob.img` file, restoring
#  it to a factory-fresh state. This script performs a low-level block copy that
#  recreates all partitions, filesystems, and boot files.
#
#  Tutorial Goal:
#  --------------
#  This script demonstrates safe disk imaging using the `dd` command. You'll learn
#  how to perform a byte-for-byte copy of a disk image to physical media and the
#  critical safety checks required beforehand. Most importantly, it reinforces the
#  Jetson boot architecture: this script MUST be run while booted from the NVMe SSD,
#  as attempting to re-image the microSD while booted from it would destroy the
#  currently running operating system. This provides a guaranteed path back to a
#  known-good state without needing a separate computer.
#
#  Prerequisites:
#  --------------
#  - Completed: Full Jetson setup with boot from SSD.
#  - Hardware: The system MUST be running from the NVMe SSD, not the microSD.
#  - Files: The `sd-blob.img` file must be present in the same directory.
#  - Time: ~10-15 minutes.
#
#  Workflow:
#  ---------
#  Run this script from an SSD-booted system to completely reset the microSD
#  card for a fresh deployment or to recover from a corrupted state.
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

print_border "Step 0: Pre-flight Safety Checks"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with root privileges. Please use 'sudo'."
    exit 1
fi
print_success "Running as root."

# --- Tutorial: Why We Check the Boot Device ---
# The `findmnt` command shows us which physical device is mounted as the root
# filesystem (`/`). If the root device contains 'nvme', we know we're running
# from the SSD and it's safe to modify the microSD. If the root device contains
# 'mmcblk', we're running from the microSD itself, and re-imaging it would be
# catastrophic - like sawing off the branch you're sitting on.
# ---

print_info "Verifying that the system is running from the NVMe SSD..."
CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" != *"nvme"* ]]; then
    print_error "CRITICAL: System is NOT booted from the NVMe SSD."
    print_error "Current root device is: $CURRENT_ROOT_DEV"
    print_error "Running this script now would destroy the running OS."
    print_error "This script can ONLY be run while booted from SSD."
    exit 1
fi
print_success "System is correctly booted from the SSD ($CURRENT_ROOT_DEV)."

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
IMAGE_NAME="sd-blob.img"
IMAGE_PATH="$SCRIPT_DIR/$IMAGE_NAME"

if [ ! -f "$IMAGE_PATH" ]; then
    print_error "OS image '$IMAGE_NAME' not found in the script directory."
    print_error "Please ensure the image file is located at: $IMAGE_PATH"
    print_error "You can obtain this file from NVIDIA's JetPack downloads page."
    exit 1
fi
print_success "Found OS image at: $IMAGE_PATH"

MICROSD_DEVICE="/dev/mmcblk0"
if [ ! -b "$MICROSD_DEVICE" ]; then
    print_error "Could not find the microSD card device at $MICROSD_DEVICE."
    print_error "Is the microSD card properly installed?"
    exit 1
fi
print_success "MicroSD card detected at: $MICROSD_DEVICE"

# --- Part 1: Confirm Destructive Operation ---

print_border "Step 1: Confirm Operation"

echo ""
echo -e "${C_RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
echo -e "${C_YELLOW}This script will re-image the microSD card.${C_RESET}"
echo -e "${C_RED}ALL data on the microSD card will be PERMANENTLY ERASED.${C_RESET}"
echo ""
echo "This includes:"
echo "  - All partitions and their contents"
echo "  - The current bootloader configuration"
echo "  - Any custom kernel or boot files"
echo ""
echo -e "${C_YELLOW}NVRAM will NOT be modified by this script.${C_RESET}"
echo -e "${C_RED}This action is IRREVERSIBLE.${C_RESET}"
echo ""
read -p "> To confirm, please type 'reimage microsd': " confirm_reimage

if [[ "$confirm_reimage" != "reimage microsd" ]]; then
    print_info "Operation cancelled. No changes were made."
    exit 1
fi

# --- Part 2: Unmount MicroSD Partitions ---

print_border "Step 2: Prepare MicroSD Card"

# --- Tutorial: Why We Unmount First ---
# If any partitions on the microSD are currently mounted (perhaps someone manually
# mounted them to inspect files), the `dd` operation could fail or produce
# inconsistent results. We use `umount` to cleanly unmount all partitions on the
# target device. The `&> /dev/null` redirects any error messages - it's safe if
# partitions aren't mounted; unmounting will simply fail silently.
# ---

print_info "Unmounting microSD card partitions (if mounted)..."
umount ${MICROSD_DEVICE}p* &> /dev/null
print_success "MicroSD card is ready for imaging."

# --- Part 3: Perform the Block Copy ---

print_border "Step 3: Write Image to MicroSD"

# --- Tutorial: The `dd` Command ---
# `dd` stands for "data duplicator" (or "disk dump"). It performs a low-level,
# block-by-block copy from an input file (`if=`) to an output device (`of=`).
# Parameters:
#   - `bs=4M`: Block size of 4 megabytes for efficient transfer
#   - `conv=fdatasync`: Forces a sync after every write, ensuring data integrity
#   - `status=progress`: Shows a progress indicator
# This operation can take 5-10 minutes depending on microSD card speed.
# See: man dd
# ---

print_info "Writing '$IMAGE_NAME' to $MICROSD_DEVICE..."
echo "This will take several minutes. Please be patient."
dd if="$IMAGE_PATH" of="$MICROSD_DEVICE" bs=4M conv=fdatasync status=progress

if [ $? -ne 0 ]; then
    print_error "Failed to write image to microSD card."
    print_error "The card may be write-protected or damaged."
    exit 1
fi

# Force all cached writes to complete
sync
print_success "MicroSD card has been re-imaged successfully."

# --- Final Instructions ---

print_border "Re-imaging Complete"
echo ""
echo "The microSD card now contains a fresh OS image identical to a factory-fresh state."
echo ""
echo "Next steps:"
echo "  1. Run 'sudo reboot' to restart the system."
echo "  2. After reboot, you will need physical access (monitor and keyboard)."
echo "  3. Complete the Ubuntu initial setup wizard (oem-config)."
echo "  4. Once on the desktop, begin the node setup with '01_config_headless.sh'."
echo ""
echo "NVRAM boot entries were not modified and remain as configured."
