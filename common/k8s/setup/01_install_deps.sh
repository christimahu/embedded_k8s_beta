#!/bin/bash

# ====================================================================================
#
#        Step 1: Install Kubernetes Dependencies (01_install_deps.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This is the first of the common scripts, run on every node destined for the
#  cluster. It installs and configures the foundational dependencies required for a
#  machine to run containers and participate in a Kubernetes network.
#
#  Tutorial Goal:
#  --------------
#  Before we can install Kubernetes itself, we must prepare the underlying OS.
#  This involves two main components:
#  1. The Container Runtime (we'll use 'containerd'): This is the low-level engine
#     that actually pulls container images and runs containers.
#  2. Kernel & Network Configuration: We will enable specific Linux kernel modules
#     and settings that are required for Kubernetes' advanced networking model
#     to function correctly.
#
#  This script must be run on a fully prepared node (i.e., after completing the
#  platform-specific setup in `jetson_orin/setup/`).
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

if [ -z "$(swapon --show)" ]; then
    print_success "Swap is disabled, as required by Kubernetes."
else
    print_error "Swap is still active. Please ensure it was disabled during node setup."
    exit 1
fi


# --- Part 1: Configure Kernel Modules and Network Settings ---

print_border "Step 1: Configuring Kernel for Container Networking"

# --- Tutorial: Kernel Modules for Containers ---
# Kubernetes networking is complex. For it to work, the Linux kernel on each node
# needs to be able to correctly handle container network traffic.
# `overlay`: This is a filesystem driver that allows containers to efficiently
#            layer filesystems, which is fundamental to how container images work.
# `br_netfilter`: This module allows the Linux bridge (which connects containers
#                 to the network) to pass traffic through the host's firewall
#                 (`iptables`), making container traffic visible and manageable.
#
# These settings ensure that packets flowing between pods can be correctly
# processed by the host's networking stack.
# See: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
# ---
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
print_success "Kernel modules loaded and network settings applied."


# --- Part 2: Install Container Runtime (containerd) ---

print_border "Step 2: Installing Container Runtime (containerd)"

print_info "Installing containerd..."
apt-get update && apt-get install -y containerd
print_success "containerd package installed."

# --- Tutorial: Configuring containerd's Cgroup Driver ---
# A 'cgroup' (control group) is a Linux kernel feature that limits and isolates
# the resource usage (CPU, memory, etc.) of a process. Both the container runtime
# (containerd) and the kubelet need to agree on which 'cgroup driver' to use to
# manage these limits. The modern standard is `systemd`. Here, we generate
# containerd's default config file and then modify it to ensure it uses the
# `systemd` driver, which is what the kubelet expects. A mismatch here is a
# common cause of cluster instability.
# ---
print_info "Configuring containerd to use the systemd cgroup driver..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
print_success "containerd configured and restarted."


# --- Final Instructions ---

print_border "Dependency Installation Complete"
echo "This node is now ready for the Kubernetes tools to be installed."
echo ""
echo "Run './setup/02_install_kube.sh' now to proceed."
