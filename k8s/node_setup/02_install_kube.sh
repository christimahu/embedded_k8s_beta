#!/bin/bash

# ============================================================================
#
#          Step 2: Install Kubernetes Tools (02_install_kube.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This is the second common script, run on every node. It installs the
#  core Kubernetes command-line packages: `kubelet`, `kubeadm`, and `kubectl`.
#
#  Tutorial Goal:
#  --------------
#  With the container runtime installed, we can now install the Kubernetes-specific
#  software from Google's official repositories. You will learn what each of
#  the three key binaries does and why we "hold" their versions with `apt-mark`
#  to prevent accidental upgrades that could destabilize the cluster.
#    1. `kubelet`: The agent on every node that manages containers.
#    2. `kubeadm`: The tool to easily bootstrap a cluster (`init` and `join`).
#    3. `kubectl`: The admin tool to interact with the cluster.
#
#  Prerequisites:
#  --------------
#  - Completed: `01_install_deps.sh`.
#  - Hardware: A fully prepared node.
#  - Network: SSH access and an active internet connection.
#  - Time: ~5 minutes.
#
#  Workflow:
#  ---------
#  Run this script on every node after installing the dependencies.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04, Kubernetes v1.30"

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

# ============================================================================
#                 STEP 1: INSTALL KUBERNETES PACKAGES
# ============================================================================

print_border "Step 1: Installing kubeadm, kubelet, and kubectl"

# --- Tutorial: Using the Official K8s Package Repository ---
# To ensure we get authentic, up-to-date versions, we configure `apt` to use
# the official Kubernetes repository. This involves adding the repository's GPG
# key to verify package authenticity and adding the repository URL to our
# system's sources.
# See: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
# ---
print_info "Adding Kubernetes APT repository..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# The directory /etc/apt/keyrings is the modern standard location for GPG keys.
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
if [ $? -ne 0 ]; then
    print_error "Failed to add Kubernetes GPG key."
    exit 1
fi

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
print_success "Kubernetes repository added successfully."

print_info "Installing kubelet, kubeadm, and kubectl..."
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
print_success "Kubernetes packages installed."

# --- Tutorial: Holding Package Versions ---
# A Kubernetes cluster is a distributed system where all nodes must run
# compatible versions. If `apt` were to automatically upgrade `kubelet` on just
# one node, it could become incompatible with the control plane. The `apt-mark
# hold` command prevents this, ensuring version changes are done deliberately
# across the entire cluster.
# ---
print_info "Locking package versions to prevent unintended upgrades..."
sudo apt-mark hold kubelet kubeadm kubectl
print_success "Kubernetes packages have been version-held."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Kubernetes Tool Installation Complete"
print_success "This node is now ready to be assigned a role in the cluster."
echo ""
echo "Next steps:"
echo "  - To initialize the cluster, run 'ops/bootstrap_cluster.sh' on this node."
echo "  - To join an existing cluster, run 'ops/join_node.sh' on this node."
