#!/bin/bash
# ============================================================================
#
#                 Step 2: Clone OS to SSD (02_clone_os_to_ssd.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This script clones the entire configured operating system from the microSD
#  card to the NVMe SSD. It performs a pure clone and does NOT modify the boot
#  configuration.
#
#  Tutorial Goal:
#  --------------
#  To gain the significant performance and reliability benefits of an SSD, we must
#  first copy the OS from the microSD card to the NVMe drive. This script
#  automates that process, creating a perfect replica of the configured OS on the
#  new storage medium. This also serves as a "backup" of your configured headless
#  state. Activating this new OS as the boot device is handled in the next step.
#
#  Prerequisites:
#  --------------
#  - Completed: `01_config_headless.sh` and subsequent shutdown.
#  - Hardware: NVMe SSD installed in the Jetson.
#  - Network: SSH access to the Jetson.
#  - Time: ~15-20 minutes.
#
#  Workflow:
#  ---------
#  1. After powering on the headless device, SSH in.
#  2. Run this script: `sudo ./02_clone_os_to_ssd.sh`.
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

CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" == *"nvme"* ]]; then
    print_error "This script is intended to be run while booted from a microSD card."
    print_error "The system is already running from the NVMe SSD. You can skip this step."
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

umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"


# --- Final Instructions ---

print_border "OS Clone Complete"
echo "The configured operating system has been successfully cloned to the NVMe SSD."
echo "The boot configuration has NOT been changed."
echo ""
echo "To make the SSD the primary boot device, run 'sudo ./03_set_boot_to_ssd.sh' now."
echo "If you only intended to clone the OS as a backup, you can skip that step."
