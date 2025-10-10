#!/bin/bash

# ============================================================================
#
#              Bootstrap Kubernetes Cluster (bootstrap_cluster.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This script bootstraps the Kubernetes control plane on the very first
#  master node. It initializes the cluster, sets up `kubectl` access for the
#  user, and installs the Calico network plugin (CNI).
#
#  Tutorial Goal:
#  --------------
#  This is the moment of creation for the cluster. We will use `kubeadm init`
#  to bring the control plane to life. You'll learn how this command generates
#  certificates, starts core components (API server, scheduler), and prepares
#  the cluster for networking and worker nodes. We'll also cover why a CNI
#  (Container Network Interface) is essential for pod-to-pod communication.
#
#  Prerequisites:
#  --------------
#  - Completed: `node_setup/01_install_deps.sh` and `02_install_kube.sh`.
#  - Hardware: The first designated control plane node.
#  - Network: SSH access. Node should have a static IP.
#  - Time: ~10-15 minutes.
#
#  Workflow:
#  ---------
#  Run this script ONLY on the first machine designated as a control plane.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04, Kubernetes v1.30, Calico v3.28"

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

if [ -n "$SUDO_USER" ]; then
    readonly TARGET_USER="$SUDO_USER"
    readonly TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
print_success "Target user for kubectl config: $TARGET_USER"

# ============================================================================
#            STEP 1: INITIALIZE THE KUBERNETES CONTROL PLANE
# ============================================================================

print_border "Step 1: Initialize the Kubernetes Control Plane"

# --- Tutorial: `kubeadm init` Parameters ---
# `kubeadm init` is the command that bootstraps the cluster.
# `--pod-network-cidr`: This crucial parameter defines the private IP address
#   range for Pods. This range must not conflict with your physical network.
#   The CNI plugin we install later (Calico) must use this same CIDR block.
# See: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
# ---
readonly IP_ADDR=$(hostname -I | awk '{print $1}')
print_info "Initializing cluster on this node ($IP_ADDR)... This may take several minutes."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$IP_ADDR"

print_success "Control plane initialized successfully."

# ============================================================================
#                STEP 2: CONFIGURE KUBECTL FOR THE USER
# ============================================================================

print_border "Step 2: Configure kubectl for Cluster Administration"

# --- Tutorial: The `kubeconfig` File ---
# The `kubeadm init` process generates an `admin.conf` file containing cluster
# details and admin credentials. `kubectl` looks for this information in a
# file named `config` inside a `.kube` directory in the user's home. These
# commands copy the file to the correct location and set ownership so the
# user can run `kubectl` without needing `sudo`.
# ---
print_info "Setting up kubeconfig for user '$TARGET_USER'..."
sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$TARGET_HOME/.kube/config"
sudo chown "$(id -u "$TARGET_USER"):$(id -g "$TARGET_USER")" "$TARGET_HOME/.kube/config"

print_success "kubectl is now configured. Try running: kubectl get nodes"

# ============================================================================
#                  STEP 3: INSTALL THE POD NETWORK (CNI)
# ============================================================================

print_border "Step 3: Install a Pod Network Add-on (Calico CNI)"

# --- Tutorial: Why We Need a CNI Plugin ---
# A fresh Kubernetes cluster has a control plane, but nodes cannot communicate
# yet. A Container Network Interface (CNI) plugin creates a "pod network" that
# allows containers on different nodes to communicate. Without a CNI, Pods will
# be stuck in a "ContainerCreating" state and Nodes will remain "NotReady".
# We are using Calico, a popular and powerful CNI.
# ---
print_info "Installing Calico Operator for pod networking..."
sudo -u "$TARGET_USER" kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

print_info "Applying Calico custom resource definition..."
sudo -u "$TARGET_USER" kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml

print_info "Waiting for Calico pods to start... This may take a minute."
# Wait for the calico-node daemonset to be ready
sudo -u "$TARGET_USER" kubectl -n calico-system wait --for=condition=ready pod -l k8s-app=calico-node --timeout=300s
print_success "Calico CNI installed and running."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Control Plane Setup Complete!"
print_success "Your Kubernetes cluster is up and running."
echo ""
print_warning "SAVE THE FOLLOWING COMMANDS TO ADD MORE NODES TO THE CLUSTER"
echo ""

# --- Tutorial: Join Commands ---
# `kubeadm token create` reliably generates a fresh, short-lived token and
# prints the full join command. We generate two commands: one for worker nodes
# and one for additional control plane nodes, which requires an extra
# certificate key for secure control plane replication.
# ---
readonly JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
readonly CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -n1)

echo "To add a NEW WORKER node, run this on the new node:"
echo "----------------------------------------------------------------------------"
echo "sudo ${JOIN_COMMAND}"
echo "----------------------------------------------------------------------------"
echo ""
echo "To add a NEW CONTROL PLANE node, run this on the new node:"
echo "----------------------------------------------------------------------------"
echo "sudo ${JOIN_COMMAND} --control-plane --certificate-key ${CERT_KEY}"
echo "----------------------------------------------------------------------------"
echo ""
print_info "These tokens are only valid for 24 hours. You can generate new ones later if needed."
