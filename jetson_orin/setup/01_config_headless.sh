#!/bin/bash

# ====================================================================================
#
#             Step 1: Configure Headless Mode (01_config_headless.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This is the very first script to run on a freshly imaged Jetson device while it
#  is still running from the microSD card. Its goal is to get the device off the
#  desk and manageable over the network as quickly as possible.
#
#  Tutorial Goal:
#  --------------
#  We will perform the essential "Day 0" setup tasks to transition the Jetson from
#  a desktop machine requiring a monitor and keyboard into a true "headless"
#  server. This involves:
#    1. Setting a Static IP: For reliable, predictable SSH access.
#    2. Setting a Hostname: To easily identify the node on the network.
#    3. Removing the GUI: To free up significant system resources (RAM/CPU) and
#       reduce the security attack surface.
#    4. Disabling Swap: A mandatory prerequisite for a stable Kubernetes node.
#
#  This script is a mandatory first step for all setup paths (SSD or microSD-only).
#
#  Workflow:
#  ---------
#  1. After the initial graphical Ubuntu setup, open a terminal and run this script.
#  2. `sudo ./setup/01_config_headless.sh`
#  3. When it completes, run `sudo shutdown now`, then disconnect the monitor and
#     keyboard.
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
    print_error "This script is intended to be run from a microSD card."
    print_error "The system is already running from the NVMe SSD. Aborting."
    exit 1
fi
print_success "System is running from microSD card. Proceeding with headless setup."


# --- Part 1: Network Configuration ---

print_border "Step 1: Network Configuration (Static IP)"

INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -z "$INTERFACE" ]]; then
    print_error "Could not detect the primary network interface. Is Ethernet plugged in?"
    exit 1
fi

CONNECTION_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep -E ":$INTERFACE$" | cut -d: -f1)
if [[ -z "$CONNECTION_NAME" ]]; then
    print_error "Could not find a NetworkManager connection for interface '$INTERFACE'."
    exit 1
fi

METHOD=$(nmcli -g ipv4.method con show "$CONNECTION_NAME")
if [[ "$METHOD" == "manual" ]]; then
    CURRENT_IP=$(nmcli -g IP4.ADDRESS con show "$CONNECTION_NAME" | cut -d'/' -f1)
    print_success "Static IP is already configured: $CURRENT_IP"
else
    print_info "A server needs a permanent, predictable IP address. We'll now configure one."
    GATEWAY_IP=$(ip route | awk '/default/ {print $3; exit}')
    SUBNET=$(ip -o -f inet addr show "$INTERFACE" | awk '/scope global/ {print $4}' | cut -d'/' -f1 | cut -d'.' -f1-3)

    echo "Detected Network Details:"
    echo "  - Connection Name: '$CONNECTION_NAME' on Interface '$INTERFACE'"
    echo "  - Network Subnet:  $SUBNET.0/24"
    echo "  - Network Gateway: $GATEWAY_IP"
    echo ""

    read -p "> Enter the last number (octet) for this node's static IP: " ip_octet
    if ! [[ "$ip_octet" =~ ^[0-9]+$ ]]; then
        print_error "Invalid input. You must enter a number."
        exit 1
    fi

    STATIC_IP="$SUBNET.$ip_octet"
    echo "Configuring static IP to $STATIC_IP..."
    nmcli con mod "$CONNECTION_NAME" ipv4.method manual ipv4.addresses "${STATIC_IP}/24" ipv4.gateway "$GATEWAY_IP" ipv4.dns "8.8.8.8,8.8.4.4"

    nmcli con down "$CONNECTION_NAME" > /dev/null 2>&1 && nmcli con up "$CONNECTION_NAME" > /dev/null 2>&1
    sleep 2
    print_success "Static IP configured. After shutdown, SSH will be available at: $STATIC_IP"
fi


# --- Part 2: System Customization & Hardening ---

print_border "Step 2: System Customization & Hardening"

CURRENT_HOSTNAME=$(hostname)
read -p "> Enter a new hostname for this node (e.g., k8s-worker-1) or press Enter to keep '$CURRENT_HOSTNAME': " new_hostname
if [ -n "$new_hostname" ]; then
    echo "Setting hostname to '$new_hostname'..."
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$new_hostname/g" /etc/hosts
    print_success "Hostname has been set to '$new_hostname'."
else
    print_info "Skipping hostname change."
fi
echo ""

print_info "To create a lean, secure server, we will remove the desktop GUI."
read -p "> Remove the full desktop environment? (Highly Recommended) (Y/N): " confirm_remove
if [[ "$confirm_remove" == "Y" || "$confirm_remove" == "y" ]]; then
    echo "Setting boot target to command-line..."
    systemctl set-default multi-user.target

    echo "Removing desktop packages... This may take a few minutes."
    apt-get remove --purge ubuntu-desktop -y && apt-get autoremove --purge -y
    print_success "Desktop environment removed. System will now boot to terminal."
else
    print_info "Skipping desktop removal. The GUI will remain installed."
fi
echo ""

print_info "Kubernetes requires swap memory to be disabled for stability."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
if systemctl list-unit-files | grep -q 'nvzramconfig.service'; then
    systemctl stop nvzramconfig.service
    systemctl disable nvzramconfig.service
fi
print_success "All swap has been disabled."


# --- Final Instructions ---
print_border "Headless Configuration Complete"
echo "The system is now configured for remote access."
echo ""
echo -e "${C_YELLOW}A shutdown is required to proceed. Please run the following command:${C_RESET}"
echo "  sudo shutdown now"
echo ""
echo "After the device shuts down, disconnect the monitor and keyboard."
echo "You can then power the device back on and access it via SSH to continue the setup."
