#!/bin/bash

# ============================================================================
#
#                Install Flannel CNI (install_flannel.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Flannel, a simple and easy-to-understand Container Network
#  Interface (CNI) plugin that provides basic pod networking for Kubernetes
#  clusters using an overlay network.
#
#  Tutorial Goal:
#  --------------
#  You will learn what a CNI plugin is and why Flannel is an excellent choice
#  for learning Kubernetes networking. While less feature-rich than Calico,
#  Flannel's simplicity makes it perfect for understanding the fundamentals
#  of pod networking. It provides everything needed for a functional cluster
#  without the complexity of advanced features you may not need yet.
#
#  What is a Container Network Interface (CNI)?
#  ---------------------------------------------
#  A CNI plugin is responsible for:
#  - Assigning IP addresses to pods
#  - Setting up routing so pods can communicate across nodes
#  - Creating the network overlay that connects pods
#  - Managing the pod network according to your cluster's CIDR
#
#  Without a CNI, Kubernetes nodes remain in "NotReady" state and pods cannot
#  start properly. The CNI is the critical piece that makes pod-to-pod
#  networking possible.
#
#  Why Choose Flannel?
#  -------------------
#  - Simplicity: Easiest CNI to understand and troubleshoot
#  - Lightweight: Minimal resource overhead
#  - Proven: One of the oldest and most stable CNI plugins
#  - VXLAN Overlay: Works in any network environment (no BGP needed)
#  - Great for Learning: Simple architecture makes it educational
#  - ARM Support: Excellent support for ARM64 platforms (Jetson, Pi)
#
#  Flannel vs Calico:
#  -------------------
#  - Flannel: Simpler, lighter, easier to understand for learning
#  - Calico: More features, network policies, better for production
#
#  How Flannel Works:
#  ------------------
#  Flannel creates a VXLAN overlay network. Each node gets a subnet from the
#  pod network CIDR (e.g., 10.244.0.0/24, 10.244.1.0/24). Packets between
#  nodes are encapsulated in VXLAN tunnels, making pod-to-pod communication
#  work even if your physical network doesn't support pod IPs.
#
#  Prerequisites:
#  --------------
#  - Completed: k8s/node_setup/ scripts on ALL nodes that will join cluster
#  - Network: All nodes must be able to communicate on the network
#  - Ports: Ensure UDP port 8472 is open (VXLAN)
#  - Time: ~3-5 minutes
#
#  Workflow:
#  ---------
#  Run this script BEFORE running bootstrap_cluster.sh. It will install Flannel
#  configuration on this node. After bootstrapping the cluster, Flannel will
#  automatically propagate to worker nodes as they join.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04, Kubernetes v1.30, Flannel v0.25.1"

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
#                    STEP 1: INSTALL FLANNEL CNI PLUGIN
# ============================================================================

print_border "Step 1: Installing Flannel CNI Plugin"

# --- Tutorial: Flannel Installation ---
# Flannel is installed by applying a YAML manifest that creates:
# - flannel namespace: Contains Flannel components
# - flannel DaemonSet: Runs flannel pod on every node
# - RBAC permissions: Service accounts and roles for Flannel
# - ConfigMap: Flannel network configuration
#
# The DaemonSet ensures that as nodes join the cluster, they automatically
# get a Flannel pod that handles pod networking for that node.
# ---

readonly FLANNEL_VERSION="v0.25.1"
readonly FLANNEL_MANIFEST_URL="https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml"

print_info "Downloading Flannel manifest (version ${FLANNEL_VERSION})..."

# Create CNI directories if they don't exist
mkdir -p /etc/cni/net.d
mkdir -p /opt/cni/bin

# Download Flannel manifest
curl -sSL "$FLANNEL_MANIFEST_URL" -o /tmp/kube-flannel.yml

if [ ! -f /tmp/kube-flannel.yml ]; then
    print_error "Failed to download Flannel manifest."
    exit 1
fi

print_success "Flannel manifest downloaded."

# ============================================================================
#                  STEP 2: CONFIGURE FLANNEL FOR YOUR NETWORK
# ============================================================================

print_border "Step 2: Configure Flannel Network Settings"

# --- Tutorial: Pod Network CIDR ---
# The pod network CIDR defines the IP address range that will be assigned to
# pods in your cluster. This must match the --pod-network-cidr parameter you
# use with kubeadm init.
#
# Flannel default CIDR: 10.244.0.0/16
#
# This default works well and doesn't conflict with common private networks:
# - 192.168.0.0/16 (home/office networks)
# - 172.16.0.0/12 (Docker default bridge)
# - 10.96.0.0/12 (Kubernetes service network)
#
# Each node will get a /24 subnet from this range:
# - Node 1: 10.244.0.0/24 (10.244.0.1 - 10.244.0.254)
# - Node 2: 10.244.1.0/24 (10.244.1.1 - 10.244.1.254)
# - Node 3: 10.244.2.0/24 (10.244.2.1 - 10.244.2.254)
# - etc.
# ---

print_info "Flannel will use pod network CIDR: 10.244.0.0/16 (default)"

# Verify the manifest has the correct network configuration
# The manifest should already have this by default, but we verify it
if grep -q "10.244.0.0/16" /tmp/kube-flannel.yml; then
    print_success "Flannel manifest is configured for pod network 10.244.0.0/16"
else
    print_warning "Flannel manifest may have a different CIDR. Adjusting..."
    # Update the network configuration in the ConfigMap
    sed -i 's|"Network": "[^"]*"|"Network": "10.244.0.0/16"|g' /tmp/kube-flannel.yml
    print_success "Flannel manifest updated to use 10.244.0.0/16"
fi

# ============================================================================
#                  STEP 3: PREPARE CNI CONFIGURATION
# ============================================================================

print_border "Step 3: Prepare CNI Configuration"

# --- Tutorial: CNI Configuration Directory ---
# The /etc/cni/net.d/ directory contains CNI plugin configurations. When the
# kubelet starts, it reads this directory to determine which CNI to use.
# We create a basic configuration file that indicates Flannel is installed.
# The actual Flannel configuration will be managed by the Flannel DaemonSet
# after the cluster is initialized.
# ---

print_info "Creating CNI configuration marker..."

# Create a minimal CNI configuration
cat > /etc/cni/net.d/10-flannel.conflist <<EOF
{
  "name": "cbr0",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "flannel",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
EOF

print_success "CNI configuration file created."

# Set appropriate permissions
chmod 644 /etc/cni/net.d/10-flannel.conflist

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Flannel CNI Installation Complete"
print_success "Flannel CNI plugin is now installed and configured!"
echo ""
echo "Configuration Summary:"
echo "  CNI Plugin:        Flannel ${FLANNEL_VERSION}"
echo "  Pod Network CIDR:  10.244.0.0/16"
echo "  Backend:           VXLAN (UDP port 8472)"
echo ""
print_warning "NEXT STEPS:"
echo ""
echo "1. Initialize the cluster with bootstrap_cluster.sh:"
echo "   cd ../../bootstrap"
echo "   sudo ./bootstrap_cluster.sh"
echo ""
echo "   IMPORTANT: Use --pod-network-cidr=10.244.0.0/16 (this is the default)"
echo "   The bootstrap script will detect Flannel is installed and proceed."
echo ""
echo "2. After cluster initialization, apply Flannel manifest:"
echo ""
echo "   As the regular user (NOT root), run:"
echo ""
echo "   kubectl apply -f /tmp/kube-flannel.yml"
echo ""
echo "3. Wait for Flannel pods to be ready (may take 1-2 minutes):"
echo "   watch kubectl get pods -n kube-flannel"
echo ""
echo "   You should see:"
echo "   - kube-flannel-ds (DaemonSet - one pod per node)"
echo ""
echo "4. Verify nodes become Ready:"
echo "   kubectl get nodes"
echo ""
echo "   The control plane node should change from NotReady to Ready once"
echo "   Flannel is fully operational."
echo ""
echo "============================================================================"
echo "Flannel Architecture:"
echo "============================================================================"
echo ""
echo "How Flannel Works:"
echo "  1. Each node runs a flannel daemon (as a DaemonSet pod)"
echo "  2. Flannel allocates a subnet to each node (e.g., 10.244.0.0/24)"
echo "  3. When a pod starts, it gets an IP from the node's subnet"
echo "  4. Cross-node traffic is encapsulated in VXLAN tunnels"
echo "  5. The VXLAN overlay makes pod IPs routable across nodes"
echo ""
echo "VXLAN Overlay:"
echo "  - Uses UDP port 8472 for encapsulation"
echo "  - Works in any network environment"
echo "  - No BGP or complex routing needed"
echo "  - Small performance overhead (typically < 5%)"
echo ""
echo "Subnet Allocation:"
echo "  - Each node gets a /24 from 10.244.0.0/16"
echo "  - Up to 256 nodes supported (10.244.0.0 through 10.244.255.0)"
echo "  - Each node can run up to 254 pods"
echo "  - Total cluster capacity: ~65,000 pods"
echo ""
echo "============================================================================"
echo "Network Requirements:"
echo "============================================================================"
echo ""
echo "Firewall Rules:"
echo "  Ensure UDP port 8472 is open between all cluster nodes for VXLAN."
echo ""
echo "  Example iptables rule:"
echo "    iptables -A INPUT -p udp --dport 8472 -j ACCEPT"
echo ""
echo "  Example ufw rule:"
echo "    ufw allow 8472/udp"
echo ""
echo "============================================================================"
echo "Troubleshooting:"
echo "============================================================================"
echo ""
echo "If nodes stay NotReady after 5 minutes:"
echo "  1. Check Flannel pod status:"
echo "     kubectl get pods -n kube-flannel"
echo "     kubectl describe pods -n kube-flannel"
echo ""
echo "  2. Check for common issues:"
echo "     - UDP port 8472 blocked by firewall"
echo "     - CIDR mismatch between this config and kubeadm init"
echo "     - Network connectivity issues between nodes"
echo ""
echo "  3. View Flannel logs:"
echo "     kubectl logs -n kube-flannel -l app=flannel"
echo ""
echo "If you see 'CNI failed to initialize':"
echo "  - Ensure this script completed successfully on all nodes"
echo "  - Verify /etc/cni/net.d/ contains Flannel configuration"
echo "  - Restart kubelet: systemctl restart kubelet"
echo ""
echo "If pods can't communicate across nodes:"
echo "  - Check VXLAN interface exists: ip link show flannel.1"
echo "  - Verify routes: ip route | grep flannel"
echo "  - Test VXLAN connectivity between nodes:"
echo "    ping -I flannel.1 <pod-ip-on-other-node>"
echo ""
echo "For detailed Flannel documentation:"
echo "  https://github.com/flannel-io/flannel"
echo ""
echo "============================================================================"
