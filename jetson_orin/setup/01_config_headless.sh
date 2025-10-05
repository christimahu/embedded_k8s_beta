#!/bin/bash

# ====================================================================================
#
#               Step 1: Jetson Headless Configuration (01_config_headless.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This is the FIRST script to run on a freshly imaged Jetson device that is
#  booted from the microSD card. It automates all the essential "Day 0" setup
#  tasks to transform the device from a desktop machine into a hardened, headless
#  server ready for the next setup stage.
#
#  Tutorial Goal:
#  --------------
#  This script handles the foundational preparation of a physical machine for a
#  cluster. We will configure the network for stability, minimize the OS for
#  security and performance, and disable features that are incompatible with
#  Kubernetes—all prerequisites for a stable cluster environment.
#
#  Workflow:
#  ---------
#  1. Boot a new Jetson from a freshly flashed microSD card.
#  2. Complete the initial on-screen Ubuntu setup.
#  3. Clone this repository onto the device.
#  4. Run this script: `sudo ./setup/01_config_headless.sh`
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

# --- Tutorial: Why a Static IP is Critical for Kubernetes ---
# A Kubernetes cluster is a distributed system where nodes must reliably
# communicate. If a node's IP address changes (as can happen with default DHCP
# settings), the control plane loses contact, marking the node as "NotReady" and
# disrupting workloads. By assigning a permanent, static IP, we ensure each node
# has a stable, predictable address for the lifetime of the cluster. This is a
# fundamental requirement for any server in a cluster.
# ---
INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -z "$INTERFACE" ]]; then
    print_error "Could not detect the primary network interface. Is Ethernet plugged in?"
    exit 1
fi

CONNECTION_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep -E ":$INTERFACE$" | cut-d: -f1)
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
    print_info "Suggested IP scheme for Kubernetes nodes:"
    echo "  - Control Planes: $SUBNET.240 - $SUBNET.249"
    echo "  - Worker Nodes:   $SUBNET.200 - $SUBNET.239"
    echo ""

    read -p "> Enter the last number (octet) for this node's static IP (e.g., 200-249): " ip_octet
    if ! [[ "$ip_octet" =~ ^[0-9]+$ ]]; then
        print_error "Invalid input. You must enter a number."
        exit 1
    fi

    STATIC_IP="$SUBNET.$ip_octet"
    echo "Configuring static IP to $STATIC_IP..."
    nmcli con mod "$CONNECTION_NAME" ipv4.method manual ipv4.addresses "${STATIC_IP}/24" ipv4.gateway "$GATEWAY_IP" ipv4.dns "8.8.8.8,8.8.4.4"

    nmcli con down "$CONNECTION_NAME" > /dev/null 2>&1 && nmcli con up "$CONNECTION_NAME" > /dev/null 2>&1
    sleep 2
    print_success "Static IP configured. SSH will be available at: $STATIC_IP"
fi


# --- Part 2: System Customization & Hardening ---

print_border "Step 2: System Customization & Hardening"

CURRENT_HOSTNAME=$(hostname)
print_info "The current hostname is '$CURRENT_HOSTNAME'."
read -p "> Do you want to set a new hostname for this node? (Y/N): " confirm_hostname
if [[ "$confirm_hostname" == "Y" || "$confirm_hostname" == "y" ]]; then
    read -p "> Enter the new hostname (e.g., k8s-worker-1): " new_hostname
    if [ -z "$new_hostname" ]; then
        print_error "Hostname cannot be empty. Skipping."
    else
        echo "Setting hostname to '$new_hostname'..."
        hostnamectl set-hostname "$new_hostname"
        sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$new_hostname/g" /etc/hosts
        print_success "Hostname has been set to '$new_hostname'."
    fi
else
    print_info "Skipping hostname change."
fi
echo ""

# --- Tutorial: Removing the Desktop GUI ---
# A server, especially a Kubernetes node, should be as lean as possible. A graphical
# user interface (GUI) consumes significant system resources (RAM, CPU) that are
# better allocated to running your containerized applications. Removing the desktop
# also reduces the system's "attack surface" by eliminating many unnecessary
# packages, making the system more secure.
# ---
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

# --- Tutorial: Disabling Swap Memory for Kubernetes ---
# This is a mandatory prerequisite for Kubernetes. The core K8s agent on a node,
# the `kubelet`, needs absolute control over resources and is designed to work with
# a known amount of memory. Swap memory, which uses the disk as slower, virtual
# RAM, makes this accounting unpredictable. If a pod uses swap, its performance
# becomes erratic. The kubelet is designed to enforce memory limits strictly; if
# a pod exceeds its memory, it should be terminated and restarted, not allowed to
# slow down the whole system by using disk swap.
# ---
print_info "Kubernetes requires swap memory to be disabled for stability."
read -p "> Disable swap? (This is required for Kubernetes) (Y/N): " confirm_swap
if [[ "$confirm_swap" == "Y" || "$confirm_swap" == "y" ]]; then
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    print_info "Disabling NVIDIA's ZRAM service..."
    if systemctl list-unit-files | grep -q 'nvzramconfig.service'; then
        systemctl stop nvzramconfig.service
        systemctl disable nvzramconfig.service
        print_success "NVIDIA ZRAM service disabled."
    else
        print_info "NVIDIA ZRAM service not found, assuming it's not in use."
    fi
    print_success "All swap has been disabled."
else
    print_info "Swap not disabled. Note: Kubernetes installation will fail until this is done."
fi

# --- Final Instructions ---
print_border "Headless Configuration Complete"
echo "The next step is to migrate this configured OS to the NVMe SSD."
echo ""
echo "Run 'sudo ./setup/02_migrate_os.sh' now to proceed."
