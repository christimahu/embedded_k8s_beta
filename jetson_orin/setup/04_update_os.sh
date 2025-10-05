#!/bin/bash

# ====================================================================================
#
#                  Step 4: Update Operating System (04_update_os.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This is the final script in the node setup process. Its sole purpose is to
#  apply all available system updates and security patches to the operating system
#  now running on the NVMe SSD.
#
#  Tutorial Goal:
#  --------------
#  Before we install any new software (like Kubernetes), it's crucial to ensure
#  the underlying operating system is fully patched and secure. This script
#  automates the standard `apt update` and `apt upgrade` process, bringing all
#  installed packages to their latest versions.
#
#  Workflow:
#  ---------
#  1. After cleaning the microSD with `03_clean_microsd.sh`, run this script.
#  2. `sudo ./setup/04_update_os.sh`
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
if [[ "$CURRENT_ROOT_DEV" != *"nvme"* ]]; then
    print_error "This script must be run from the NVMe SSD."
    print_error "The system is still running from the microSD card. Please complete the migration first."
    exit 1
fi
print_success "System is running from SSD. Proceeding with updates."


# --- Part 1: System Package Update ---

print_border "Step 1: Apply System Updates"

print_info "Applying latest security patches and software updates to the system."
print_info "This may take several minutes depending on network speed."
read -p "> Run 'apt update' and 'apt upgrade' now? (Recommended) (Y/N): " confirm_update
if [[ "$confirm_update" == "Y" || "$confirm_update" == "y" ]]; then
    apt-get update && apt-get upgrade -y
    print_success "System is now up to date."
else
    print_info "Skipping system updates."
fi


# --- Final Instructions ---

print_border "Jetson Setup Complete"
print_success "This node is now fully prepared and secured."
echo "You can now proceed with the Kubernetes installation using the scripts"
echo "in the 'common/k8s' directory."
