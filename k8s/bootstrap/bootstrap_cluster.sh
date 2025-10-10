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
#  master node. It initializes the cluster and sets up `kubectl` access for
#  the user. Unlike previous versions, this script does NOT install a CNI
#  plugin - that must be done separately beforehand.
#
#  Tutorial Goal:
#  --------------
#  This is the moment of creation for the cluster. We will use `kubeadm init`
#  to bring the control plane to life. You'll learn how this command generates
#  certificates, starts core components (API server, scheduler), and prepares
#  the cluster for networking and worker nodes. 
#
#  IMPORTANT: The cluster will not be functional without a CNI (Container 
#  Network Interface). This must be installed BEFORE running this script.
#  Without a CNI, pods cannot communicate and nodes will remain in a 'NotReady'
#  state. This separation gives you explicit control over your network plugin
#  choice and teaches the critical role CNIs play in cluster operation.
#
#  Prerequisites:
#  --------------
#  - Completed: `node_setup/01_install_deps.sh` and `02_install_kube.sh`.
#  - Completed: A CNI installation from `bootstrap/cni/` directory.
#  - Hardware: The first designated control plane node.
#  - Network: SSH access. Node should have a static IP.
#  - Time: ~10-15 minutes.
#
#  Workflow:
#  ---------
#  1. Install a CNI plugin first (see bootstrap/cni/README.md for options)
#  2. Run this script ONLY on the first machine designated as a control plane.
#  3. Optionally install a service mesh after cluster is running.
#
# ============================================================================

readonly SCRIPT_VERSION="2.0.0"
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

if [ -n "$SUDO_USER" ]; then
    readonly TARGET_USER="$SUDO_USER"
    readonly TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
print_success "Target user for kubectl config: $TARGET_USER"

# ============================================================================
#                    STEP 1: VERIFY CNI INSTALLATION
# ============================================================================

print_border "Step 1: Verify CNI Plugin Installation"

# --- Tutorial: Why We Check for CNI First ---
# A CNI (Container Network Interface) is absolutely required for a functional
# Kubernetes cluster. It creates the pod network that allows containers on
# different nodes to communicate. Without a CNI:
# - Pods will be stuck in 'ContainerCreating' state
# - Nodes will remain 'NotReady'
# - No network communication between pods is possible
# - CoreDNS pods won't start
#
# We check for CNI installation by looking for CNI configuration files and
# binaries. This script does NOT install a CNI - that must be done separately
# using scripts in the bootstrap/cni/ directory. This separation is intentional:
# it forces you to make an explicit choice about your network plugin and
# understand its role in the cluster.
# ---

print_info "Checking for CNI plugin installation..."

CNI_INSTALLED=false

# Check for CNI configuration files in standard locations
if [ -d "/etc/cni/net.d" ] && [ "$(ls -A /etc/cni/net.d 2>/dev/null)" ]; then
    CNI_INSTALLED=true
    print_success "Found CNI configuration in /etc/cni/net.d"
fi

# Check for CNI binaries
if [ -d "/opt/cni/bin" ] && [ "$(ls -A /opt/cni/bin 2>/dev/null)" ]; then
    if [ "$CNI_INSTALLED" = false ]; then
        CNI_INSTALLED=true
    fi
    print_success "Found CNI binaries in /opt/cni/bin"
fi

if [ "$CNI_INSTALLED" = false ]; then
    print_error "No CNI plugin installation detected!"
    echo ""
    echo "A Container Network Interface (CNI) plugin is REQUIRED before bootstrapping"
    echo "the cluster. The CNI provides pod-to-pod networking and is essential for"
    echo "cluster functionality."
    echo ""
    echo "============================================================================"
    echo "REQUIRED ACTION: Install a CNI Plugin"
    echo "============================================================================"
    echo ""
    echo "Available CNI plugins are located in: bootstrap/cni/"
    echo ""
    echo "For guidance on choosing a CNI, see: bootstrap/README.md"
    echo ""
    echo "Quick start options:"
    echo ""
    echo "  Option 1: Calico (Recommended for most use cases)"
    echo "  ---------------------------------------------------"
    echo "    cd bootstrap/cni"
    echo "    sudo ./install_calico.sh"
    echo ""
    echo "  Option 2: Flannel (Simpler, lighter weight)"
    echo "  ---------------------------------------------------"
    echo "    cd bootstrap/cni"
    echo "    sudo ./install_flannel.sh"
    echo ""
    echo "After installing a CNI, run this script again to continue."
    echo "============================================================================"
    exit 1
fi

print_success "CNI plugin is installed. Cluster will have pod networking."

# ============================================================================
#            STEP 2: INITIALIZE THE KUBERNETES CONTROL PLANE
# ============================================================================

print_border "Step 2: Initialize the Kubernetes Control Plane"

# --- Tutorial: `kubeadm init` Parameters ---
# `kubeadm init` is the command that bootstraps the cluster.
# `--pod-network-cidr`: This crucial parameter defines the private IP address
#   range for Pods. This range must not conflict with your physical network.
#   The CNI plugin you installed must be compatible with this CIDR block.
#   
#   Standard CIDR blocks:
#   - Calico: 192.168.0.0/16 (default) or 10.244.0.0/16
#   - Flannel: 10.244.0.0/16 (default)
#   
#   We use 10.244.0.0/16 as it works with both popular CNIs. If you installed
#   a different CNI with specific requirements, you may need to adjust this.
#
# See: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
# ---
readonly IP_ADDR=$(hostname -I | awk '{print $1}')
print_info "Initializing cluster on this node ($IP_ADDR)... This may take several minutes."

sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$IP_ADDR"

if [ $? -ne 0 ]; then
    print_error "Failed to initialize control plane."
    exit 1
fi

print_success "Control plane initialized successfully."

# ============================================================================
#                STEP 3: CONFIGURE KUBECTL FOR THE USER
# ============================================================================

print_border "Step 3: Configure kubectl for Cluster Administration"

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
#                      STEP 4: VERIFY CLUSTER STATE
# ============================================================================

print_border "Step 4: Verifying Cluster State"

print_info "Waiting for control plane components to be ready..."
sleep 10

# Check if the node is ready
NODE_STATUS=$(sudo -u "$TARGET_USER" kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')

if [ "$NODE_STATUS" = "Ready" ]; then
    print_success "Control plane node is Ready!"
    print_info "Your CNI is working correctly and the cluster is functional."
elif [ "$NODE_STATUS" = "NotReady" ]; then
    print_warning "Control plane node is NotReady."
    echo ""
    echo "This usually means the CNI is not fully operational yet."
    echo "Common causes:"
    echo "  - CNI pods are still starting (check: kubectl get pods -n kube-system)"
    echo "  - CNI configuration mismatch with pod network CIDR"
    echo "  - Network connectivity issues between nodes"
    echo ""
    echo "The node should become Ready within 1-2 minutes as CNI pods start."
else
    print_warning "Could not determine node status. Check manually with: kubectl get nodes"
fi

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
readonly CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n1)

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
echo ""
echo "============================================================================"
echo "Next Steps:"
echo "============================================================================"
echo ""
echo "1. Verify your cluster is healthy:"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo ""
echo "2. [OPTIONAL] Install a Service Mesh for production-grade networking:"
echo ""
echo "   Service meshes provide advanced features like:"
echo "   - Automatic mutual TLS (encrypted service-to-service communication)"
echo "   - Traffic management (canary deployments, circuit breaking)"
echo "   - Deep observability (distributed tracing, metrics)"
echo "   - Network policy enforcement"
echo ""
echo "   Available service meshes are in: bootstrap/service_mesh/"
echo ""
echo "   For guidance on choosing a service mesh, see: bootstrap/README.md"
echo ""
echo "   Quick start options:"
echo ""
echo "     Option 1: Linkerd (Lightweight, recommended for ARM/edge)"
echo "     --------------------------------------------------------"
echo "       cd bootstrap/service_mesh"
echo "       sudo ./install_linkerd.sh"
echo ""
echo "     Option 2: Istio (Feature-rich, recommended for production)"
echo "     --------------------------------------------------------"
echo "       cd bootstrap/service_mesh"
echo "       sudo ./install_istio.sh"
echo ""
echo "   NOTE: Service meshes are optional. Your cluster is fully functional"
echo "   without one. Install a mesh only if you need its advanced features."
echo ""
echo "3. Install cluster addons (ingress, cert-manager, etc.):"
echo "   cd ../addons"
echo "   See addons/README.md for available options"
echo ""
echo "4. Deploy your first application:"
echo "   cd ../deployments"
echo "   kubectl apply -f deployment.yaml"
echo ""
echo "============================================================================"
