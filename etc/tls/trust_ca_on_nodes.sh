#!/bin/bash

# ============================================================================
#
#         Trust CA Certificate on Cluster Nodes (trust_ca_on_nodes.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Distributes your private CA certificate to all Kubernetes cluster nodes and
#  configures them to trust certificates signed by your CA. This enables secure
#  communication with external services (Docker registry, Gitea, etc.) without
#  "insecure" configurations.
#
#  Tutorial Goal:
#  --------------
#  You will learn how TLS trust works in Linux systems. When a system encounters
#  a TLS certificate, it checks if the certificate is signed by a trusted CA.
#  The list of trusted CAs lives in the system trust store. This script adds
#  your private CA to that trust store on every node.
#
#  What This Script Does:
#  -----------------------
#  For each cluster node:
#  1. Copies ca.crt to /usr/local/share/ca-certificates/
#  2. Runs update-ca-certificates (rebuilds trust store)
#  3. Restarts containerd (picks up new trust settings)
#  4. Optionally restarts Docker (if installed)
#
#  After running this script, all cluster nodes will trust any certificate
#  signed by your CA - no more "insecure-registries" configuration needed!
#
#  How It Works:
#  -------------
#  Linux systems maintain a trust store at /etc/ssl/certs/. The update-ca-
#  certificates command rebuilds this store from certificates in:
#  - /usr/share/ca-certificates/ (system CAs)
#  - /usr/local/share/ca-certificates/ (local CAs - us!)
#
#  Prerequisites:
#  --------------
#  - Completed: generate_ca.sh (must have ca.crt)
#  - SSH access to all cluster nodes with password-less sudo
#  - Time: ~1 minute per node
#
#  Workflow:
#  ---------
#  Run this script after creating your CA and whenever you add new nodes to
#  the cluster.
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

# Get script directory
readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check for CA certificate
if [ ! -f "ca.crt" ]; then
    print_error "CA certificate not found: ca.crt"
    echo "Run ./generate_ca.sh first to create your Certificate Authority."
    exit 1
fi
print_success "CA certificate found: ca.crt"

# ============================================================================
#                    STEP 1: COLLECT NODE INFORMATION
# ============================================================================

print_border "Step 1: Collecting Cluster Node Information"

print_info "This script will install the CA certificate on all cluster nodes."
echo ""
echo "You can provide node IPs in one of two ways:"
echo "  1. Enter them manually (interactive)"
echo "  2. Auto-detect from kubectl (if running on a cluster node)"
echo ""

read -p "Auto-detect nodes from kubectl? (yes/no): " AUTO_DETECT

if [[ "$AUTO_DETECT" =~ ^[Yy] ]]; then
    # Try to get nodes from kubectl
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        print_info "Detecting nodes from Kubernetes cluster..."
        
        # Get node IPs
        NODE_IPS=($(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))
        
        if [ ${#NODE_IPS[@]} -eq 0 ]; then
            print_error "Could not detect any nodes from kubectl."
            AUTO_DETECT="no"
        else
            print_success "Detected ${#NODE_IPS[@]} node(s):"
            for ip in "${NODE_IPS[@]}"; do
                echo "  - $ip"
            done
            echo ""
            read -p "Use these nodes? (yes/no): " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
                AUTO_DETECT="no"
            fi
        fi
    else
        print_warning "kubectl not available or not connected to cluster."
        AUTO_DETECT="no"
    fi
fi

if [[ ! "$AUTO_DETECT" =~ ^[Yy] ]]; then
    print_info "Enter cluster node IP addresses (one per line, empty line to finish):"
    NODE_IPS=()
    while true; do
        read -p "Node IP: " ip
        if [ -z "$ip" ]; then
            break
        fi
        NODE_IPS+=("$ip")
    done
    
    if [ ${#NODE_IPS[@]} -eq 0 ]; then
        print_error "No node IPs provided."
        exit 1
    fi
    
    print_info "Will configure ${#NODE_IPS[@]} node(s):"
    for ip in "${NODE_IPS[@]}"; do
        echo "  - $ip"
    done
fi

echo ""
read -p "SSH username for nodes (default: current user): " SSH_USER
SSH_USER=${SSH_USER:-$(whoami)}

print_info "Will connect to nodes as user: $SSH_USER"

# ============================================================================
#                 STEP 2: TEST SSH CONNECTIVITY
# ============================================================================

print_border "Step 2: Testing SSH Connectivity"

print_info "Testing SSH access to all nodes..."

FAILED_NODES=()
for node_ip in "${NODE_IPS[@]}"; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SSH_USER}@${node_ip}" "echo 'SSH OK'" &>/dev/null; then
        print_success "SSH accessible: $node_ip"
    else
        print_error "Cannot SSH to: $node_ip"
        FAILED_NODES+=("$node_ip")
    fi
done

if [ ${#FAILED_NODES[@]} -gt 0 ]; then
    print_error "SSH failed for ${#FAILED_NODES[@]} node(s). Please resolve before continuing."
    echo ""
    echo "Common solutions:"
    echo "  - Set up SSH key authentication: ssh-copy-id ${SSH_USER}@<node-ip>"
    echo "  - Ensure nodes are reachable from this machine"
    echo "  - Verify SSH daemon is running on nodes"
    exit 1
fi

print_success "All nodes are SSH accessible."

# ============================================================================
#               STEP 3: INSTALL CA ON EACH NODE
# ============================================================================

print_border "Step 3: Installing CA Certificate on Nodes"

# --- Tutorial: The update-ca-certificates Process ---
# Ubuntu and Debian systems use update-ca-certificates to manage the trust store.
# The process:
# 1. Certificates in /usr/local/share/ca-certificates/*.crt are trusted
# 2. update-ca-certificates scans this directory
# 3. It creates symlinks in /etc/ssl/certs/ pointing to trusted certs
# 4. It rebuilds /etc/ssl/certs/ca-certificates.crt (bundle of all trusted CAs)
#
# Programs like curl, wget, and containerd read from this trust store.
# ---

SUCCESSFUL=0
FAILED=0

for node_ip in "${NODE_IPS[@]}"; do
    print_info "Processing node: $node_ip"
    
    # Create script to run on remote node
    REMOTE_SCRIPT=$(cat <<'SCRIPT_END'
#!/bin/bash
set -e

# Copy CA cert to trust store
sudo mkdir -p /usr/local/share/ca-certificates
sudo cp /tmp/private-ca.crt /usr/local/share/ca-certificates/private-ca.crt
sudo chmod 644 /usr/local/share/ca-certificates/private-ca.crt

# Update trust store
sudo update-ca-certificates

# Restart containerd to pick up new trust
if systemctl is-active --quiet containerd; then
    sudo systemctl restart containerd
fi

# Restart docker if it exists
if systemctl is-active --quiet docker; then
    sudo systemctl restart docker
fi

# Cleanup
rm -f /tmp/private-ca.crt

echo "CA certificate installed successfully"
SCRIPT_END
)
    
    # Copy CA cert to node
    if scp -o StrictHostKeyChecking=no ca.crt "${SSH_USER}@${node_ip}:/tmp/private-ca.crt" &>/dev/null; then
        # Execute installation script
        if ssh -o StrictHostKeyChecking=no "${SSH_USER}@${node_ip}" "bash -s" <<< "$REMOTE_SCRIPT" &>/dev/null; then
            print_success "  ✓ CA installed on $node_ip"
            ((SUCCESSFUL++))
        else
            print_error "  ✗ Installation failed on $node_ip"
            ((FAILED++))
        fi
    else
        print_error "  ✗ Failed to copy CA to $node_ip"
        ((FAILED++))
    fi
done

# ============================================================================
#                      STEP 4: VERIFY INSTALLATION
# ============================================================================

print_border "Step 4: Verifying Installation"

print_info "Verifying CA is trusted on nodes..."

for node_ip in "${NODE_IPS[@]}"; do
    # Check if CA is in trust store
    VERIFY_CMD="grep -q 'BEGIN CERTIFICATE' /usr/local/share/ca-certificates/private-ca.crt"
    
    if ssh -o StrictHostKeyChecking=no "${SSH_USER}@${node_ip}" "$VERIFY_CMD" &>/dev/null; then
        print_success "  ✓ Verified: $node_ip"
    else
        print_warning "  ? Could not verify: $node_ip"
    fi
done

# ============================================================================
#                           FINAL SUMMARY
# ============================================================================

print_border "Installation Complete"
echo ""
echo "Summary:"
echo "  ✓ Successful: $SUCCESSFUL node(s)"
if [ $FAILED -gt 0 ]; then
    echo "  ✗ Failed:     $FAILED node(s)"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    print_success "All cluster nodes now trust your private CA!"
else
    print_warning "Some nodes failed. Review errors above and re-run for failed nodes."
fi

echo ""
print_warning "VERIFICATION STEPS:"
echo ""
echo "Test from any cluster node:"
echo ""
echo "1. If you have a Docker registry with TLS enabled:"
echo "   docker pull registry.local:5000/test-image"
echo "   (Should work without 'insecure-registries' configuration)"
echo ""
echo "2. Test with curl:"
echo "   curl https://registry.local:5000/v2/_catalog"
echo "   (Should not show certificate errors)"
echo ""
echo "3. View trusted CAs on a node:"
echo "   ssh ${SSH_USER}@${NODE_IPS[0]} \"ls -la /usr/local/share/ca-certificates/\""
echo ""
echo "============================================================================"
echo "Adding New Nodes:"
echo "============================================================================"
echo ""
echo "When you add new nodes to the cluster in the future, re-run this script"
echo "to install the CA certificate on them:"
echo ""
echo "  cd $SCRIPT_DIR"
echo "  sudo ./trust_ca_on_nodes.sh"
echo ""
echo "Or install manually on a single node:"
echo ""
echo "  scp ca.crt ${SSH_USER}@<new-node-ip>:/tmp/"
echo "  ssh ${SSH_USER}@<new-node-ip>"
echo "  sudo cp /tmp/ca.crt /usr/local/share/ca-certificates/private-ca.crt"
echo "  sudo update-ca-certificates"
echo "  sudo systemctl restart containerd"
echo ""
echo "============================================================================"
