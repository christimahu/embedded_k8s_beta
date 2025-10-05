#!/bin/bash

# ====================================================================================
#
#                    Jetson Node Setup Verifier (verify_setup.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This is a non-destructive verification and auditing tool. It runs a series of
#  checks to confirm that a Jetson node has been correctly configured by the
#  `setup/` scripts and is in a healthy, predictable state.
#
#  Tutorial Goal:
#  --------------
#  After performing major system changes, it's good practice to verify that
#  everything is in the state you expect. This script acts as an automated
#  checklist, ensuring our node meets all the foundational requirements before
#  we attempt to install Kubernetes on it. It provides a clear pass/fail report
#  on the most critical configuration points.
#
# ====================================================================================


# --- Helper Functions for Better Output ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'

print_pass() {
    echo -e "  ${C_GREEN}[PASS] $1${C_RESET}"
}
print_fail() {
    echo -e "  ${C_RED}[FAIL] $1${C_RESET}"
}
print_info() {
    echo -e "  ${C_YELLOW}[INFO] $1${C_RESET}"
}
print_border() {
    echo ""
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    echo " $1"
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
}

# --- Main Logic ---

print_border "Jetson Node Setup Verification"

if [ "$(id -u)" -ne 0 ]; then
    print_fail "This script should be run with root privileges. Please use 'sudo'."
    exit 1
fi

# --- Verification Checks ---

echo ""
# --- Check 1: Boot Device ---
print_info "1. Verifying OS is running from the NVMe SSD..."
CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" == *"nvme"* ]]; then
    print_pass "System is correctly booted from the SSD ($CURRENT_ROOT_DEV)."
else
    print_fail "System is NOT booted from the SSD. Current root is: $CURRENT_ROOT_DEV."
fi
echo ""

# --- Check 2: Boot Configuration ---
print_info "2. Verifying bootloader is configured to use SSD..."
# This is the check that would have caught our issue.
if grep -q "root=UUID=" /boot/extlinux/extlinux.conf; then
    print_pass "extlinux.conf correctly points to the SSD via UUID."
else
    print_fail "extlinux.conf does NOT point to the SSD via UUID. Booting may be unreliable."
fi
echo ""

# --- Check 3: MicroSD Cleanup ---
print_info "3. Verifying microSD card has been stripped..."
MICROSD_PARTITION="/dev/mmcblk0p1"
MOUNT_POINT="/mnt/verify_microsd"

if [ ! -b "$MICROSD_PARTITION" ]; then
    print_fail "Could not find the microSD card partition at $MICROSD_PARTITION."
else
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount -o ro "$MICROSD_PARTITION" "$MOUNT_POINT" &>/dev/null
    fi

    if mountpoint -q "$MOUNT_POINT"; then
        ITEM_COUNT=$(ls -A1 "$MOUNT_POINT" | wc -l)
        BOOT_DIR_EXISTS=$(find "$MOUNT_POINT" -maxdepth 1 -type d -name "boot")
        if [[ "$ITEM_COUNT" -le 2 && -n "$BOOT_DIR_EXISTS" ]]; then
            print_pass "MicroSD contains only the /boot directory (and optionally /lost+found)."
        else
            print_fail "MicroSD has NOT been cleaned. It still contains old OS files."
        fi
        umount "$MOUNT_POINT" &>/dev/null
        rmdir "$MOUNT_POINT" &>/dev/null
    else
        print_fail "Could not mount microSD to verify its contents."
    fi
fi
echo ""


# --- Check 4: Swap Status ---
print_info "4. Verifying that swap is disabled..."
if [ -z "$(swapon --show)" ]; then
    print_pass "All swap devices are disabled."
else
    print_fail "Swap is still active. Kubernetes installation will fail."
fi
echo ""

# --- Check 5: Headless Mode ---
print_info "5. Verifying headless (command-line) boot target..."
DEFAULT_TARGET=$(systemctl get-default)
if [[ "$DEFAULT_TARGET" == "multi-user.target" ]]; then
    print_pass "System is correctly configured for headless boot."
else
    print_fail "System is NOT configured for headless boot (GUI is enabled)."
fi

print_border "Verification Complete"
