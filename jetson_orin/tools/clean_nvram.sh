#!/bin/bash

#!/bin/bash

# ============================================================================
#
#               Clean Custom NVRAM Entries (clean_nvram.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Removes custom UEFI boot entries from NVRAM that were created outside the
#  standard NVIDIA setup process. This ensures the system uses only the factory
#  default boot configuration, eliminating potential sources of boot inconsistency.
#
#  Tutorial Goal:
#  --------------
#  This script teaches safe NVRAM modification. While NVRAM changes cannot brick
#  the Jetson, incorrect boot entries can cause confusing behavior where the system
#  boots via an unexpected path. By understanding what this script removes—any entry
#  numbered Boot0009 or higher—you'll gain insight into how custom entries can
#  bypass the standard `extlinux.conf` boot chain and why removing them is a key
#  troubleshooting step for restoring predictable behavior.
#
#  Prerequisites:
#  --------------
#  - Completed: `inspect_nvram.sh` (recommended to view entries first).
#  - Hardware: A booted Jetson Orin device.
#  - Network: Not required.
#  - Time: < 1 minute.
#
#  Workflow:
#  ---------
#  Run this script to resolve issues caused by non-standard boot entries or
#  to ensure a clean state before a redeployment. It preserves all standard
#  NVIDIA boot entries (Boot0000-Boot0008).
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

if ! command -v efibootmgr &> /dev/null; then
    print_error "efibootmgr not found. Is this a UEFI system?"
    exit 1
fi
print_success "efibootmgr is available."

# --- Part 1: Scan for Custom Boot Entries ---

print_border "Step 1: Scan for Custom Boot Entries"

# --- Tutorial: How We Identify Custom Entries ---
# We maintain a list of standard boot entry numbers (0000-0008) that NVIDIA's
# factory image creates. We then iterate through all boot entries reported by
# `efibootmgr` and check if each entry number is in our standard list. Any
# entry not in this list is flagged as custom. This approach is conservative:
# it only removes entries we're certain are non-standard.
# ---

print_info "Scanning for custom boot entries..."

STANDARD_BOOT_NUMS="0000 0001 0002 0003 0004 0005 0006 0007 0008"
CUSTOM_ENTRIES=()

while IFS= read -r line; do
    # Extract the boot entry number using regex
    if [[ "$line" =~ ^Boot([0-9]{4})\* ]]; then
        BOOT_NUM="${BASH_REMATCH[1]}"
        
        # Check if this number is in our standard list
        IS_STANDARD=false
        for STANDARD in $STANDARD_BOOT_NUMS; do
            if [ "$BOOT_NUM" = "$STANDARD" ]; then
                IS_STANDARD=true
                break
            fi
        done
        
        # If not standard, add to our removal list
        if [ "$IS_STANDARD" = false ]; then
            CUSTOM_ENTRIES+=("$BOOT_NUM")
            print_info "Found custom entry: Boot${BOOT_NUM}"
            echo "    $line"
        fi
    fi
done < <(efibootmgr)

if [ ${#CUSTOM_ENTRIES[@]} -eq 0 ]; then
    print_success "No custom boot entries found. NVRAM is clean."
    exit 0
fi

# --- Part 2: Confirm Removal ---

print_border "Step 2: Confirm Removal"

echo ""
echo -e "${C_YELLOW}Found ${#CUSTOM_ENTRIES[@]} custom boot entry/entries.${C_RESET}"
echo "These will be removed: ${CUSTOM_ENTRIES[@]}"
echo ""
echo "Removing these entries will not affect the standard NVIDIA boot entries."
echo "The system will revert to using only the factory default boot configuration."
echo ""
read -p "> Remove these custom entries? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    print_info "Operation cancelled. No changes made to NVRAM."
    exit 0
fi

# --- Part 3: Remove Custom Entries ---

print_border "Step 3: Removing Custom Entries"

# --- Tutorial: The `efibootmgr -b XXXX -B` Command ---
# The `-b` flag specifies a boot entry number, and the `-B` flag means "delete".
# This command modifies NVRAM directly, removing the specified entry from the
# firmware's boot entry list. The change takes effect immediately and persists
# across reboots. Unlike changes to files on disk, NVRAM changes cannot be
# undone by re-imaging the microSD or SSD.
# See: man efibootmgr
# ---

for BOOT_NUM in "${CUSTOM_ENTRIES[@]}"; do
    print_info "Removing Boot${BOOT_NUM}..."
    if efibootmgr -b "$BOOT_NUM" -B > /dev/null 2>&1; then
        print_success "Boot${BOOT_NUM} removed."
    else
        print_error "Failed to remove Boot${BOOT_NUM}."
    fi
done

# --- Part 4: Verify Cleanup ---

print_border "Step 4: Verification"
print_info "Remaining boot entries:"
efibootmgr | grep "^Boot"

# --- Final Instructions ---

print_border "Cleanup Complete"
print_success "Custom NVRAM entries have been removed."
print_info "The system will now use only standard NVIDIA boot entries."
echo ""
echo "The NVRAM is now in a clean, factory-default state for boot configuration."
