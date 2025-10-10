#!/bin/bash
# ============================================================================
#
#                    Jetson Node Setup Verifier (06_verify_setup.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This is a non-destructive verification and auditing tool. It runs a series of
#  checks to confirm that a Jetson node has been correctly configured by the
#  setup scripts (01-05) and is in a healthy, predictable state ready for
#  Kubernetes deployment.
#
#  Tutorial Goal:
#  --------------
#  After performing major system changes, it's good practice to verify that
#  everything is in the state you expect. This script acts as an automated
#  checklist, ensuring our node meets all foundational requirements before
#  we attempt to install Kubernetes on it. It provides a clear pass/fail report
#  on the most critical configuration points, like boot device and swap status.
#
#  Prerequisites:
#  --------------
#  - Completed: All setup scripts from 01 through 05.
#  - Hardware: System is fully configured and running from the SSD.
#  - Network: SSH access to the Jetson.
#  - Time: < 1 minute.
#
#  Workflow:
#  ---------
#  Run this script ONLY AFTER completing ALL setup steps (01 through 05).
#  Running it mid-setup will show false failures because the system is in an
#  intermediate state. This is by design - it checks for the FINAL state.
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

# --- Check 1: Boot Device ---
echo ""
print_info "1. Verifying OS is running from the NVMe SSD..."

# --- Tutorial: Understanding Root Device ---
# The `findmnt` command with the root path (/) shows us which physical device
# is currently mounted as the root filesystem. After running scripts 01-03,
# this should be the NVMe SSD partition (/dev/nvme0n1p1). If it's still the
# microSD (/dev/mmcblk0p1), either script 03 didn't run, or the bootloader
# configuration didn't persist correctly.
# ---

CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$CURRENT_ROOT_DEV" == *"nvme"* ]]; then
    print_pass "System is correctly booted from the SSD ($CURRENT_ROOT_DEV)."
else
    print_fail "System is NOT booted from the SSD. Current root is: $CURRENT_ROOT_DEV."
fi

# --- Check 2: Boot Configuration ---
echo ""
print_info "2. Verifying bootloader is configured to use SSD..."

# --- Tutorial: Why We Check the MicroSD's Copy ---
# This is a critical distinction that causes confusion. When you're booted from
# the SSD, the path `/boot/extlinux/extlinux.conf` refers to the SSD's copy,
# which was cloned BEFORE script 03 ran. That copy still points to the microSD.
# However, the BOOTLOADER reads extlinux.conf from the MICROSD during the early
# boot process (before any filesystems are mounted). So we must check the
# microSD's copy, not the SSD's copy. We do this by temporarily mounting the
# microSD's first partition and reading the file directly from it.
# ---

TEMP_MOUNT="/mnt/verify_microsd"
mkdir -p "$TEMP_MOUNT"

if mount /dev/mmcblk0p1 "$TEMP_MOUNT" 2>/dev/null; then
    if [ -f "$TEMP_MOUNT/boot/extlinux/extlinux.conf" ]; then
        # Check if it uses UUID format (root=UUID=...)
        if grep -q "root=UUID=" "$TEMP_MOUNT/boot/extlinux/extlinux.conf"; then
            # Get the actual SSD UUID
            SSD_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
            
            # Verify it's the SSD's UUID, not some other UUID
            if grep -q "root=UUID=$SSD_UUID" "$TEMP_MOUNT/boot/extlinux/extlinux.conf"; then
                print_pass "Bootloader (extlinux.conf) correctly points to SSD (UUID: $SSD_UUID)."
            else
                CONF_UUID=$(grep "root=UUID=" "$TEMP_MOUNT/boot/extlinux/extlinux.conf" | sed -n 's/.*root=UUID=\([^ ]*\).*/\1/p')
                print_fail "extlinux.conf has UUID but not the SSD's. Expected: $SSD_UUID, Found: $CONF_UUID"
            fi
        else
            print_fail "extlinux.conf does NOT use UUID format. It may still point to microSD."
        fi
    else
        print_fail "Could not find extlinux.conf on microSD at expected location."
    fi
    
    umount "$TEMP_MOUNT" 2>/dev/null
else
    print_fail "Could not mount microSD partition to verify boot configuration."
fi

rmdir "$TEMP_MOUNT" 2>/dev/null

# --- Check 3: Boot via Proper Path ---
echo ""
print_info "3. Verifying boot via standard NVIDIA boot path..."

# --- Tutorial: NVRAM and Boot Entries ---
# The Jetson's UEFI firmware maintains a list of boot entries in NVRAM.
# BootCurrent tells us which entry was used for this boot. Boot0001 is the
# microSD's EFI System Partition - this is the standard NVIDIA boot path.
# If BootCurrent shows anything other than 0001 (especially 0009 or higher),
# it means we're using a custom boot entry, which indicates the scripts didn't
# work as intended or someone modified NVRAM externally.
# ---

BOOT_CURRENT=$(efibootmgr | grep "BootCurrent" | awk '{print $2}')
if [ "$BOOT_CURRENT" = "0001" ]; then
    print_pass "System booted via standard path (Boot0001 - microSD ESP)."
elif [ "$BOOT_CURRENT" = "0008" ]; then
    print_fail "System booted directly from SSD (Boot0008). This shouldn't happen - microSD ESP is required."
else
    print_fail "System booted via non-standard entry (Boot$BOOT_CURRENT). Custom NVRAM entries may exist."
fi

# --- Check 4: MicroSD Cleanup ---
echo ""
print_info "4. Verifying microSD card has been stripped..."

# --- Tutorial: Why We Strip the MicroSD ---
# After migrating to SSD, the microSD contains a redundant copy of the OS.
# Leaving this in place is a security risk: someone with physical access could
# revert the boot configuration and boot from the old, un-updated OS. Script 04
# removes these redundant files, keeping only the /boot directory (which contains
# the EFI System Partition and bootloader). This check ensures that cleanup
# happened. Note: This check will fail if script 04 was skipped, which is okay
# as script 04 is optional (though recommended).
# ---

MICROSD_PARTITION="/dev/mmcblk0p1"
MOUNT_POINT="/mnt/verify_microsd"

if [ ! -b "$MICROSD_PARTITION" ]; then
    print_fail "Could not find the microSD card partition at $MICROSD_PARTITION."
else
    mkdir -p "$MOUNT_POINT"
    
    if mount -o ro "$MICROSD_PARTITION" "$MOUNT_POINT" &>/dev/null; then
        # Count top-level items (should be just 'boot' and optionally 'lost+found')
        ITEM_COUNT=$(ls -A1 "$MOUNT_POINT" | wc -l)
        BOOT_DIR_EXISTS=$(find "$MOUNT_POINT" -maxdepth 1 -type d -name "boot")
        
        # Acceptable: just /boot, or /boot + /lost+found (created by ext4)
        if [[ "$ITEM_COUNT" -le 2 && -n "$BOOT_DIR_EXISTS" ]]; then
            print_pass "MicroSD contains only /boot directory (and optionally /lost+found)."
        else
            print_fail "MicroSD has NOT been cleaned. It still contains old OS files."
            print_info "This is okay if you skipped script 04, but not recommended for production."
        fi
        
        umount "$MOUNT_POINT" &>/dev/null
        rmdir "$MOUNT_POINT" &>/dev/null
    else
        print_fail "Could not mount microSD to verify its contents."
    fi
fi

# --- Check 5: EFI Partition Mount ---
echo ""
print_info "5. Verifying /boot/efi is mounted from microSD..."

# --- Tutorial: The EFI System Partition ---
# The /boot/efi directory should be a mount point for the microSD's EFI System
# Partition (partition 10, specifically /dev/mmcblk0p10). This partition contains
# the UEFI bootloader binary (BOOTAA64.efi) that the firmware executes at boot.
# Script 02 configures the SSD's /etc/fstab to mount this partition. If this
# check fails, kernel updates might not write boot files to the correct location.
# ---

BOOT_EFI_DEV=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null)
if [[ "$BOOT_EFI_DEV" == "/dev/mmcblk0p10" ]]; then
    print_pass "/boot/efi is correctly mounted from microSD ESP ($BOOT_EFI_DEV)."
else
    if [ -z "$BOOT_EFI_DEV" ]; then
        print_fail "/boot/efi is NOT mounted. Kernel updates may fail."
    else
        print_fail "/boot/efi is mounted from wrong device: $BOOT_EFI_DEV (expected: /dev/mmcblk0p10)."
    fi
fi

# --- Check 6: Swap Status ---
echo ""
print_info "6. Verifying that swap is disabled..."

# --- Tutorial: Why Kubernetes Requires No Swap ---
# Kubernetes requires swap to be completely disabled. Swap allows the kernel to
# move memory pages to disk when RAM is full. This can cause unpredictable
# performance for containerized workloads and interferes with Kubernetes' memory
# management. The kubelet will refuse to start if swap is enabled. Script 01
# disables all swap, and this check confirms it stayed disabled.
# See: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
# ---

if [ -z "$(swapon --show)" ]; then
    print_pass "All swap devices are disabled."
else
    print_fail "Swap is still active. Kubernetes installation will fail."
    swapon --show
fi

# --- Check 7: Headless Mode ---
echo ""
print_info "7. Verifying headless (command-line) boot target..."

# --- Tutorial: Systemd Boot Targets ---
# Systemd uses "targets" to define what services start at boot. The default on
# desktop Ubuntu is `graphical.target`, which starts the full GUI. For a server,
# we use `multi-user.target`, which provides a command-line interface and network
# services but no GUI. This saves significant RAM and CPU. Script 01 makes this
# change. The `systemctl get-default` command shows the current default target.
# ---

DEFAULT_TARGET=$(systemctl get-default)
if [[ "$DEFAULT_TARGET" == "multi-user.target" ]]; then
    print_pass "System is correctly configured for headless boot."
else
    print_fail "System is NOT configured for headless boot. Current target: $DEFAULT_TARGET"
fi

# --- Final Summary ---
print_border "Verification Complete"
echo ""
echo "If any checks failed, review the setup scripts and re-run them as needed."
echo ""
echo "Critical checks for Kubernetes readiness:"
echo "  - Booted from SSD (performance)"
echo "  - Swap disabled (required)"
echo "  - Headless mode (resource efficiency)"
echo ""
echo "If all critical checks passed, proceed with Kubernetes installation:"
echo "  cd ../../common/k8s/setup"
echo "  sudo ./01_install_deps.sh"
