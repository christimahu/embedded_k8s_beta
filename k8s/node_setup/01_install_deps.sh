#!/bin/bash

# ============================================================================
#
#        Step 1: Install Kubernetes Dependencies (01_install_deps.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This is the first common script, run on every node. It installs and
#  configures the foundational dependencies required for a machine to run
#  containers and participate in a Kubernetes network.
#
#  Tutorial Goal:
#  --------------
#  Before we can install Kubernetes itself, we must prepare the underlying OS.
#  This involves installing a container runtime ('containerd') and configuring
#  specific Linux kernel modules (`overlay`, `br_netfilter`) that are required
#  for Kubernetes' advanced networking model to function correctly. You will
#  also learn about `cgroups` and why a consistent cgroup driver between the
#  runtime and the kubelet is critical for stability.
#
#  Prerequisites:
#  --------------
#  - Completed: Platform-specific setup (e.g., from `jetson_orin` folder).
#  - Hardware: A fully prepared node.
#  - Network: SSH access and an active internet connection.
#  - Time: ~5 minutes.
#
#  Workflow:
#  ---------
#  Run this script on every node that will be part of the cluster.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04"

set -euo pipefail
trap 'print_error "Script failed at line $LINENO"' ERR

# ============================================================================
#                           HELPER FUNCTIONS
# ============================================================================

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_MAGENTA='\033[0;35m'

print_success() { echo -e "${C_GREEN}[OK] $1${C_RESET}"; }
print_error() { echo -e "${C_RED}[ERROR] $1${C_RESET}"; }
print_info() { echo -e "${C_YELLOW}[INFO] $1${C_RESET}"; }
print_warning() { echo -e "${C_MAGENTA}[WARNING] $1${C_RESET}"; }
print_border() {
    echo ""
    echo "============================================================================"
    echo " $1"
    echo "============================================================================"
}

# ============================================================================
#                         STEP 0: PRE-FLIGHT CHECKS
# ============================================================================

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

# ============================================================================
#            STEP 1: CONFIGURE KERNEL MODULES & NETWORK SETTINGS
# ============================================================================

print_border "Step 1: Configuring Kernel for Container Networking"

# --- Tutorial: Kernel Modules for Containers ---
# Kubernetes networking is complex. For it to work, the Linux kernel needs to
# correctly handle container network traffic.
# `overlay`: A filesystem driver that allows containers to efficiently layer
#            filesystems, which is fundamental to how container images work.
# `br_netfilter`: Allows the Linux bridge to pass traffic through the host's
#                 firewall (`iptables`), making container traffic manageable.
# ---
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
print_success "Kernel modules loaded."

# --- Tutorial: System Control Settings for K8s ---
# These settings ensure that packets flowing between pods can be correctly
# processed by the host's networking stack. We enable IPv4 forwarding and
# ensure bridged traffic is processed by iptables for filtering and port
# forwarding.
# See: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
# ---
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
print_success "Network settings applied and verified."

# ============================================================================
#               STEP 2: INSTALL CONTAINER RUNTIME (CONTAINERD)
# ============================================================================

print_border "Step 2: Installing Container Runtime (containerd)"

print_info "Installing containerd from standard repositories..."
sudo apt-get update
sudo apt-get install -y containerd
print_success "containerd package installed."

# --- Tutorial: Configuring containerd's Cgroup Driver ---
# A 'cgroup' (control group) limits the resources (CPU, memory) a process can
# use. Both the container runtime (containerd) and the kubelet must agree on
# the same 'cgroup driver' to manage these limits. The modern standard is
# `systemd`. A mismatch here is a common cause of cluster instability.
# ---
print_info "Configuring containerd to use the systemd cgroup driver..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
print_success "containerd configured with systemd cgroup driver and restarted."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Dependency Installation Complete"
print_success "This node is now ready for the Kubernetes tools to be installed."
echo ""
echo "Run './02_install_kube.sh' now to proceed."
