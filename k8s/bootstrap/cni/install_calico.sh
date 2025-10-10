#!/bin/bash

# ============================================================================
#
#                Install Calico CNI (install_calico.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Calico, a powerful and flexible Container Network Interface (CNI)
#  plugin that provides networking and network policy for Kubernetes clusters.
#
#  Tutorial Goal:
#  --------------
#  You will learn what a CNI plugin is and why it's essential for Kubernetes.
#  Without a CNI, pods cannot communicate with each other - the cluster would
#  be non-functional. Calico is one of the most popular CNI choices because it
#  provides not just basic pod networking, but also advanced features like
#  network policies for security, BGP routing for complex topologies, and
#  excellent performance at scale.
#
#  What is a Container Network Interface (CNI)?
#  ---------------------------------------------
#  A CNI plugin is responsible for:
#  - Assigning IP addresses to pods
#  - Setting up routing so pods can communicate across nodes
#  - Implementing network policies for security
#  - Managing the pod network according to your cluster's CIDR
#
#  Without a CNI, Kubernetes nodes remain in "NotReady" state and pods cannot
#  start properly. The CNI is the critical piece that makes pod-to-pod
#  networking possible.
#
#  Why Choose Calico?
#  ------------------
#  - Network Policies: Provides Kubernetes NetworkPolicy API for pod security
#  - BGP Support: Can integrate with existing network infrastructure
#  - Performance: Uses standard Linux networking (no overlays by default)
#  - Scalability: Proven in large production environments (1000+ nodes)
#  - eBPF Mode: Optional high-performance dataplane
#  - Active Community: CNCF project with strong support
#
#  Calico vs Flannel:
#  -------------------
#  - Calico: More features, network policies, better for production
#  - Flannel: Simpler, lighter, easier to understand for learning
#
#  Prerequisites:
#  --------------
#  - Completed: k8s/node_setup/ scripts on ALL nodes that will join cluster
#  - Network: All nodes must be able to communicate on the network
#  - Ports: Ensure required ports are open (179 for BGP, 4789 for VXLAN)
#  - Time: ~5-10 minutes
#
#  Workflow:
#  ---------
#  Run this script BEFORE running bootstrap_cluster.sh. It will install Calico
#  on this node. After bootstrapping the cluster, Calico will automatically
#  propagate to worker nodes as they join.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
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

# Check if kubeadm is installed
if ! command -v kubeadm &> /dev/null; then
    print_error "kubeadm is not installed."
    echo ""
    echo "Please complete the node setup scripts first:"
    echo "  cd ../../node_setup"
    echo "  sudo ./01_install_deps.sh"
    echo "  sudo ./02_install_kube.sh"
    exit 1
fi
print_success "Kubernetes tools are installed."

# Check if CNI is already installed
if [ -d "/etc/cni/net.d" ] && [ "$(ls -A /etc/cni/net.d 2>/dev/null)" ]; then
    print_error "A CNI plugin appears to be already installed!"
    echo ""
    echo "Existing CNI configuration found in /etc/cni/net.d:"
    ls -la /etc/cni/net.d/
    echo ""
    echo "Installing multiple CNI plugins will cause conflicts."
    echo ""
    echo "If you want to replace the existing CNI:"
    echo "  1. Drain and delete all nodes except control plane"
    echo "  2. Delete existing CNI: rm -rf /etc/cni/net.d/*"
    echo "  3. Restart kubelet: systemctl restart kubelet"
    echo "  4. Re-run this script"
    echo ""
    exit 1
fi
print_success "No conflicting CNI installation detected."

# ============================================================================
#                    STEP 1: INSTALL CALICO CNI PLUGIN
# ============================================================================

print_border "Step 1: Installing Calico CNI Plugin"

# --- Tutorial: Calico Installation Methods ---
# Calico can be installed in two ways:
# 1. Operator-based (recommended): Uses Tigera Operator for lifecycle management
# 2. Manifest-based: Direct kubectl apply of manifests
#
# We use the operator-based approach because it:
# - Simplifies upgrades and configuration changes
# - Provides better day-2 operations
# - Is the officially recommended method
# - Handles complex scenarios automatically
#
# The installation creates:
# - tigera-operator namespace: Contains the operator that manages Calico
# - calico-system namespace: Contains Calico components (node, kube-controllers)
# - calico-apiserver namespace: Optional API server for Calico resources
# ---

readonly CALICO_VERSION="v3.28.0"
readonly CALICO_OPERATOR_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
readonly CALICO_CUSTOM_RESOURCES_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml"

print_info "Installing Calico Operator (version ${CALICO_VERSION})..."
print_info "This creates the Tigera Operator that will manage Calico lifecycle."

# Create CNI directories if they don't exist
mkdir -p /etc/cni/net.d
mkdir -p /opt/cni/bin

# Download and apply the Tigera Operator manifest
curl -sSL "$CALICO_OPERATOR_URL" -o /tmp/tigera-operator.yaml

if [ ! -f /tmp/tigera-operator.yaml ]; then
    print_error "Failed to download Tigera Operator manifest."
    exit 1
fi

# Apply the operator (this will fail if cluster isn't initialized yet, which is expected)
# We install it to prepare the node
print_info "Installing Tigera Operator manifest..."
cat /tmp/tigera-operator.yaml > /tmp/calico-operator-ready.yaml

print_success "Calico Operator manifest prepared."

# Download custom resources
curl -sSL "$CALICO_CUSTOM_RESOURCES_URL" -o /tmp/calico-custom-resources.yaml

if [ ! -f /tmp/calico-custom-resources.yaml ]; then
    print_error "Failed to download Calico custom resources manifest."
    exit 1
fi

print_success "Calico custom resources manifest prepared."

# ============================================================================
#                  STEP 2: CONFIGURE CALICO FOR YOUR NETWORK
# ============================================================================

print_border "Step 2: Configure Calico Network Settings"

# --- Tutorial: Pod Network CIDR ---
# The pod network CIDR defines the IP address range that will be assigned to
# pods in your cluster. This must match the --pod-network-cidr parameter you
# use with kubeadm init.
#
# Default Calico CIDR: 192.168.0.0/16
# Common alternative: 10.244.0.0/16 (compatible with Flannel)
#
# We use 10.244.0.0/16 to match the bootstrap_cluster.sh default, providing
# consistency across CNI choices.
#
# IMPORTANT: This CIDR must NOT overlap with:
# - Your physical network
# - Your service CIDR (default: 10.96.0.0/12)
# - Any VPN or other network you connect to
# ---

print_info "Configuring Calico to use pod network CIDR: 10.244.0.0/16"

# Modify the custom resources to use our desired CIDR
sed -i 's|cidr: 192\.168\.0\.0/16|cidr: 10.244.0.0/16|g' /tmp/calico-custom-resources.yaml

print_success "Calico configured for pod network 10.244.0.0/16"

# Create a marker file so bootstrap_cluster.sh knows Calico is installed
mkdir -p /etc/cni/net.d
cat > /etc/cni/net.d/00-calico.conflist <<EOF
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "datastore_type": "kubernetes",
      "nodename": "__KUBERNETES_NODE_NAME__",
      "mtu": __CNI_MTU__,
      "ipam": {
        "type": "calico-ipam"
      },
      "policy": {
        "type": "k8s"
      },
      "kubernetes": {
        "kubeconfig": "__KUBECONFIG_FILEPATH__"
      }
    },
    {
      "type": "portmap",
      "snat": true,
      "capabilities": {"portMappings": true}
    },
    {
      "type": "bandwidth",
      "capabilities": {"bandwidth": true}
    }
  ]
}
EOF

print_success "Calico CNI configuration file created."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Calico CNI Installation Complete"
print_success "Calico CNI plugin is now installed and configured!"
echo ""
echo "Configuration Summary:"
echo "  CNI Plugin:        Calico ${CALICO_VERSION}"
echo "  Pod Network CIDR:  10.244.0.0/16"
echo "  Installation Mode: Tigera Operator"
echo ""
print_warning "NEXT STEPS:"
echo ""
echo "1. Initialize the cluster with bootstrap_cluster.sh:"
echo "   cd ../../bootstrap"
echo "   sudo ./bootstrap_cluster.sh"
echo ""
echo "   The bootstrap script will detect Calico is installed and proceed."
echo ""
echo "2. After cluster initialization, apply Calico manifests:"
echo ""
echo "   As the regular user (NOT root), run:"
echo ""
echo "   kubectl create -f /tmp/calico-operator-ready.yaml"
echo "   kubectl create -f /tmp/calico-custom-resources.yaml"
echo ""
echo "3. Wait for Calico pods to be ready (may take 2-3 minutes):"
echo "   watch kubectl get pods -n calico-system"
echo ""
echo "   You should see:"
echo "   - calico-node (DaemonSet - one per node)"
echo "   - calico-kube-controllers (Deployment)"
echo ""
echo "4. Verify nodes become Ready:"
echo "   kubectl get nodes"
echo ""
echo "   The control plane node should change from NotReady to Ready once"
echo "   Calico is fully operational."
echo ""
echo "============================================================================"
echo "Calico Features:"
echo "============================================================================"
echo ""
echo "Network Policies:"
echo "  Calico implements Kubernetes NetworkPolicy for pod-level security."
echo "  Example: Restrict traffic to a pod to only specific sources."
echo ""
echo "BGP Peering:"
echo "  Calico can peer with physical routers using BGP for advanced routing."
echo "  This enables direct pod IP routing without overlays."
echo ""
echo "IP-in-IP Encapsulation:"
echo "  Automatic tunneling for cross-subnet communication (enabled by default)."
echo ""
echo "VXLAN Mode:"
echo "  Alternative to IP-in-IP for environments where IP-in-IP is blocked."
echo ""
echo "eBPF Dataplane:"
echo "  High-performance dataplane using eBPF (optional, advanced use case)."
echo ""
echo "============================================================================"
echo "Troubleshooting:"
echo "============================================================================"
echo ""
echo "If nodes stay NotReady after 5 minutes:"
echo "  1. Check Calico pod status:"
echo "     kubectl get pods -n calico-system"
echo "     kubectl describe pods -n calico-system"
echo ""
echo "  2. Check for common issues:"
echo "     - Firewall blocking Calico ports (179/TCP for BGP, 4789/UDP for VXLAN)"
echo "     - CIDR mismatch between this config and kubeadm init"
echo "     - Network connectivity issues between nodes"
echo ""
echo "  3. View Calico node logs:"
echo "     kubectl logs -n calico-system -l k8s-app=calico-node"
echo ""
echo "If you see 'CNI failed to initialize':"
echo "  - Ensure this script completed successfully on all nodes"
echo "  - Verify /etc/cni/net.d/ contains Calico configuration"
echo "  - Restart kubelet: systemctl restart kubelet"
echo ""
echo "For detailed Calico documentation:"
echo "  https://docs.tigera.io/calico/latest/about"
echo ""
echo "============================================================================"
