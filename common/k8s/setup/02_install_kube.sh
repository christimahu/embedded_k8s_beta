#!/bin/bash

# ====================================================================================
#
#          Step 2: Install Kubernetes Tools (02_install_kube.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This is the second of the common scripts, run on every node. It installs the
#  core Kubernetes command-line packages: `kubelet`, `kubeadm`, and `kubectl`.
#
#  Tutorial Goal:
#  --------------
#  With the container runtime installed, we can now install the Kubernetes-specific
#  software. We will install three key binaries:
#  1. `kubelet`: The primary agent that runs on every node. It receives instructions
#     from the control plane and is responsible for starting/stopping containers.
#  2. `kubeadm`: The tool that provides the `init` and `join` commands to easily
#     bootstrap a Kubernetes cluster.
#  3. `kubectl`: The command-line tool used by administrators to interact with the
#     cluster (e.g., `kubectl get pods`).
#
#  We install these from Google's official package repositories and then "hold"
#  the packages to prevent accidental, unmanaged upgrades.
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


# --- Part 1: Install Kubernetes Packages ---

print_border "Step 1: Installing kubeadm, kubelet, and kubectl"

# --- Tutorial: Using the Official K8s Package Repository ---
# To ensure we are getting authentic, up-to-date versions, we configure our
# system's package manager (`apt`) to use the official Kubernetes repository
# hosted by Google. This involves adding the repository's GPG key to verify
# package authenticity and then adding the repository URL to our system's sources.
#
# See: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
# ---
print_info "Adding Kubernetes APT repository..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg

# The directory /etc/apt/keyrings is the modern standard location for GPG keys.
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

print_info "Installing kubelet, kubeadm, and kubectl..."
apt-get update
apt-get install -y kubelet kubeadm kubectl

# --- Tutorial: Holding Package Versions ---
# A Kubernetes cluster is a distributed system where all nodes must run
# compatible versions of the core components. If your OS's package manager were
# to automatically upgrade `kubelet` on just one node, it could cause that node
# to become incompatible with the control plane, leading to instability. The
# `apt-mark hold` command prevents automatic upgrades, ensuring that all version
# changes are done manually and deliberately across the entire cluster.
# ---
apt-mark hold kubelet kubeadm kubectl
print_success "Kubernetes packages installed and version-held."


# --- Final Instructions ---

print_border "Kubernetes Tool Installation Complete"
print_success "This node is now ready to be assigned a role in the cluster."
echo "Next steps:"
echo "  - If this is your FIRST control plane node, run '../control_plane/init.sh' on it now."
echo "  - If this is a worker node (or a subsequent control plane), run '../worker/join.sh' on it."
