#!/bin/bash

# ============================================================================
#
#              Install NFS Server for k8s (install_nfs_server.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Sets up this node as an NFS (Network File System) server, providing a simple
#  way to create network-accessible persistent storage for the Kubernetes cluster.
#
#  Tutorial Goal:
#  --------------
#  You will learn a foundational method for providing PersistentVolumes in
#  Kubernetes. While not typically used for high-performance production, NFS is
#  an excellent, easy-to-understand way to enable stateful applications (like
#  databases or web apps that need to store uploads) during development and
#  testing. We will install the NFS server, configure a shared directory, and
#  set export permissions.
#
#  Prerequisites:
#  --------------
#  - Completed: A base OS installation.
#  - Network: A known, static IP for this server node.
#  - Time: ~5 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a single, designated node that will act as the storage
#  server for your cluster. The script will output the server IP and export
#  path needed to configure PersistentVolume resources in Kubernetes.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
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

# ============================================================================
#                     STEP 1: INSTALL NFS SERVER PACKAGES
# ============================================================================

print_border "Step 1: Install NFS Server Packages"

print_info "Installing nfs-kernel-server..."
sudo apt-get update
sudo apt-get install -y nfs-kernel-server
print_success "NFS packages installed."

# ============================================================================
#                 STEP 2: CREATE AND CONFIGURE EXPORT DIRECTORY
# ============================================================================

print_border "Step 2: Create and Configure Export Directory"

readonly NFS_EXPORT_PATH="/srv/nfs/kubedata"
print_info "Creating export directory at $NFS_EXPORT_PATH..."
sudo mkdir -p "$NFS_EXPORT_PATH"
# --- Tutorial: NFS Permissions ---
# For an NFS share, we must ensure the directory has open permissions so that
# any client (like a Kubernetes pod) can read and write data. `chown nobody:nogroup`
# assigns ownership to a generic, non-privileged user, which is a standard
# security practice for public shares.
# ---
sudo chown -R nobody:nogroup "$NFS_EXPORT_PATH"
sudo chmod 777 "$NFS_EXPORT_PATH"
print_success "Export directory created and permissions set."

# --- Tutorial: The `/etc/exports` File ---
# This file is the main configuration for the NFS server. Each line defines a
# directory to share and who can access it.
# `*`: Allows any client on the network to connect.
# `rw`: Grants read and write permissions.
# `sync`: Ensures data is written to disk before the server confirms the write.
# `no_subtree_check`: Improves reliability by disabling certain checks.
# ---
print_info "Configuring the NFS export..."
echo "$NFS_EXPORT_PATH *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
print_success "NFS export configured in /etc/exports."

# ============================================================================
#                       STEP 3: START NFS SERVICES
# ============================================================================

print_border "Step 3: Start and Enable NFS Services"

print_info "Applying export configuration and restarting NFS server..."
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server
print_success "NFS server is running and enabled on boot."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete"
print_success "This node is now an active NFS server."
echo ""
echo "Use the following details to create PersistentVolume resources in your cluster:"
echo ""
echo "  NFS Server IP:  $(hostname -I | awk '{print $1}')"
echo "  NFS Path:       $NFS_EXPORT_PATH"
echo ""
echo "Example Kubernetes PersistentVolume YAML:"
cat <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv-example
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  nfs:
    path: "$NFS_EXPORT_PATH"
    server: "$(hostname -I | awk '{print $1}')"
EOF
