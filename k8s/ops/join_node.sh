#!/bin/bash

# ============================================================================
#
#                    Join Node to Cluster (join_node.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  This script securely joins a prepared node to an existing Kubernetes cluster
#  as either a worker or an additional control plane node.
#
#  Tutorial Goal:
#  --------------
#  The final step in expanding our cluster is to join nodes to the control
#  plane using the `kubeadm join` command. You'll learn that this command is
#  unique to your cluster and contains a temporary security token for a safe
#  handshake. This script provides an interactive and safe way to execute that
#  sensitive command.
#
#  Prerequisites:
#  --------------
#  - Completed: `node_setup/01_install_deps.sh` and `02_install_kube.sh`.
#  - Information: The `kubeadm join` command from the `bootstrap_cluster.sh` output.
#  - Network: SSH access to the node.
#  - Time: ~5 minutes.
#
#  Workflow:
#  ---------
#  Run this script on any prepared node you wish to add to the cluster. You will
#  be prompted to paste the full join command.
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
#                     STEP 1: JOIN NODE TO THE CLUSTER
# ============================================================================

print_border "Step 1: Join this Node to the Kubernetes Cluster"

# --- Tutorial: The `kubeadm join` Command ---
# The join command contains three key pieces for a secure handshake:
# 1. API Server Address: The IP and port of the control plane.
# 2. Bootstrap Token: A short-lived, secure credential for initial authentication.
# 3. CA Cert Hash: A fingerprint of the cluster's root CA, which the new node
#    uses to verify it is talking to the correct, trusted control plane.
# ---
print_info "Please paste the full 'sudo kubeadm join...' command that was generated"
print_info "by the 'bootstrap_cluster.sh' script on your master node."
echo ""

read -rp "> Paste the full join command here: " JOIN_COMMAND

# Basic validation to prevent common errors
if [[ ! "$JOIN_COMMAND" == *"kubeadm join"* ]]; then
    print_error "Invalid input. The command must include 'kubeadm join'."
    exit 1
fi

# The user is prompted for "sudo kubeadm join..." but we run with sudo,
# so we should strip the leading "sudo" if they pasted it.
JOIN_COMMAND_NO_SUDO="${JOIN_COMMAND#sudo }"

print_info "Executing join command..."
if sudo "$JOIN_COMMAND_NO_SUDO"; then
    print_success "This node has successfully joined the cluster!"
    echo "On your control plane node, run 'kubectl get nodes' to see it appear."
else
    print_error "Failed to join the cluster. Please check the output above for errors."
    exit 1
fi
