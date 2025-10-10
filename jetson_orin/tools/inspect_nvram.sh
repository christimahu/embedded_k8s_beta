#!/bin/bash

#!/bin/bash

# ============================================================================
#
#               Inspect NVRAM Boot State (inspect_nvram.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This is a read-only diagnostic script that displays the current UEFI boot
#  configuration stored in the Jetson's NVRAM. It helps identify any custom boot
#  entries that may have been created outside of the standard setup process.
#
#  Tutorial Goal:
#  --------------
#  Understanding NVRAM is crucial for managing the Jetson boot process. NVRAM
#  (Non-Volatile RAM) is a small chip on the Jetson's motherboard that stores
#  firmware settings, including the boot entry list. Unlike the microSD card or
#  SSD, NVRAM persists across power cycles and even survives re-imaging of storage
#  devices. This script teaches you how to inspect this hidden configuration layer
#  to understand the boot order and identify why custom NVRAM entries can cause
#  unpredictable boot behavior.
#
#  Prerequisites:
#  --------------
#  - Completed: Basic Jetson setup. Can be run at any time.
#  - Hardware: A booted Jetson Orin device.
#  - Network: Not required.
#  - Time: < 1 minute.
#
#  Workflow:
#  ---------
#  Run this non-destructive script anytime you need to audit the boot state,
#  especially before using `clean_nvram.sh` to see what might be removed. This
#  script makes NO CHANGES to the system.
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
readonly C_BLUE='\033[0;34m'

print_info() {
    echo -e "${C_YELLOW}[INFO] $1${C_RESET}"
}
print_header() {
    echo ""
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    echo " $1"
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
}

print_header "NVRAM Boot Configuration Inspector"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] This script must be run with root privileges. Please use 'sudo'.${C_RESET}"
    exit 1
fi

if ! command -v efibootmgr &> /dev/null; then
    echo -e "${C_RED}[ERROR] efibootmgr not found. Is this a UEFI system?${C_RESET}"
    exit 1
fi

# --- Part 1: Display Current Boot State ---

print_header "Part 1: Current Boot State"

# --- Tutorial: Understanding BootCurrent vs BootOrder ---
# The `BootCurrent` variable tells us which boot entry the system ACTUALLY used
# during this boot cycle. The `BootOrder` variable is the firmware's preference
# list - it tries the first entry, and if that fails, moves to the next.
# If BootCurrent doesn't match the first entry in BootOrder, it means the
# firmware attempted to boot from the preferred device but failed, then fell
# back to a working entry.
# ---

echo -e "${C_BLUE}BootCurrent (what the system actually booted from):${C_RESET}"
efibootmgr | grep "BootCurrent"
echo ""
echo -e "${C_BLUE}BootOrder (firmware's preference list):${C_RESET}"
efibootmgr | grep "BootOrder"

# --- Part 2: List All Boot Entries ---

print_header "Part 2: All Boot Entries"

# --- Tutorial: Reading efibootmgr Output ---
# Each line shows a boot entry number (e.g., Boot0001) followed by a descriptive
# name and the device path. The asterisk (*) indicates an active entry.
# Device paths use UEFI's complex notation to precisely identify hardware.
# See: https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface
# ---

efibootmgr -v

# --- Part 3: Analysis and Anomaly Detection ---

print_header "Part 3: Analysis"

BOOT_CURRENT=$(efibootmgr | grep "BootCurrent" | awk '{print $2}')
echo -e "${C_YELLOW}Currently booted from: Boot${BOOT_CURRENT}${C_RESET}"
efibootmgr -v | grep "Boot${BOOT_CURRENT}\*"

echo ""
echo -e "${C_YELLOW}Checking for custom/unusual boot entries...${C_RESET}"

# --- Tutorial: Standard NVIDIA Boot Entries ---
# A factory-fresh Jetson Orin has a specific set of boot entries created by
# NVIDIA's flashing process. These include:
#   - Boot0000: UEFI Setup Menu
#   - Boot0001: microSD card
#   - Boot0002-0005: Network boot options (PXE)
#   - Boot0006: Boot Manager Menu
#   - Boot0007: UEFI Shell
#   - Boot0008: NVMe SSD (if detected)
# Any entry outside of this range (e.g., Boot0009 or higher) was created by
# a user, script, or tool and should be investigated.
# ---

STANDARD_ENTRIES="Enter Setup|UEFI SD Device|UEFI PXE|UEFI HTTP|BootManagerMenuApp|UEFI Shell|UEFI Samsung"
CUSTOM_FOUND=false

while IFS= read -r line; do
    if [[ "$line" =~ ^Boot[0-9]+ ]] && ! echo "$line" | grep -qE "$STANDARD_ENTRIES"; then
        echo -e "${C_RED}  CUSTOM ENTRY FOUND: ${C_RESET}"
        echo "  $line"
        CUSTOM_FOUND=true
    fi
done < <(efibootmgr -v | grep "^Boot")

if [ "$CUSTOM_FOUND" = false ]; then
    echo -e "${C_GREEN}  No custom boot entries detected.${C_RESET}"
fi

# --- Part 4: Expected Configuration Summary ---

print_header "Part 4: Boot Entry Reference"

echo ""
echo -e "${C_BLUE}Standard NVIDIA Boot Entries (Expected):${C_RESET}"
echo "  Boot0001 - UEFI SD Device (microSD card)"
echo "  Boot0008 - UEFI Samsung SSD (NVMe drive, if present)"
echo ""
echo -e "${C_BLUE}Your Actual Entries:${C_RESET}"
efibootmgr | grep -E "^Boot000[18]\*"

# --- Final Summary ---

print_header "Inspection Complete"
echo "This was a read-only inspection. No changes were made to NVRAM."
echo ""
echo "If custom entries were found, consider running 'clean_nvram.sh' to remove them."
