#!/bin/bash

# ============================================================================
#
#                  Drain and Remove Node (drain_node.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Safely removes a node from the Kubernetes cluster by draining workloads,
#  cordoning the node to prevent new pods, and removing it from the cluster.
#
#  Tutorial Goal:
#  --------------
#  You will learn the proper procedure for removing a node from a Kubernetes
#  cluster without causing downtime or data loss. Simply deleting a node or
#  powering it off is dangerous - running pods will be lost and the cluster
#  may enter an inconsistent state. This script demonstrates the correct
#  three-step process: cordon (prevent new pods), drain (evict existing pods),
#  and delete (remove from cluster). This is essential knowledge for cluster
#  maintenance, upgrades, and decommissioning hardware.
#
#  The Three-Step Process:
#  ------------------------
#  1. Cordon: Mark the node as unschedulable so no new pods are placed on it
#  2. Drain: Gracefully evict all pods, moving them to other nodes
#  3. Delete: Remove the node object from the cluster's state
#
#  Why This Order Matters:
#  -----------------------
#  If you drain before cordoning, new pods might be scheduled during the drain.
#  If you delete before draining, pods are lost without graceful termination.
#  The cordon-drain-delete sequence ensures zero downtime for your applications.
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster with multiple nodes
#  - Access: kubectl configured with cluster-admin permissions
#  - Network: SSH access to run kubectl commands
#  - Time: 5-15 minutes depending on workload count
#
#  Workflow:
#  ---------
#  Run this script from any machine with kubectl access (typically a control
#  plane node or your workstation). You'll be prompted for the node name to
#  drain. The script will guide you through the process with safety checks.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
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
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
print_success "Will execute kubectl as user: $TARGET_USER"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH."
    exit 1
fi
print_success "kubectl is available."

if ! sudo -u "$TARGET_USER" kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster."
    echo ""
    echo "Ensure kubectl is configured with valid credentials:"
    echo "  kubectl config view"
    echo "  kubectl get nodes"
    exit 1
fi
print_success "Successfully connected to Kubernetes cluster."

# ============================================================================
#                    STEP 1: SELECT NODE TO DRAIN
# ============================================================================

print_border "Step 1: Select Node to Drain"

print_info "Current cluster nodes:"
echo ""
sudo -u "$TARGET_USER" kubectl get nodes -o wide
echo ""

# --- Tutorial: Node Selection ---
# You can drain any node in the cluster, but be careful with control plane
# nodes. If you drain your only control plane, the cluster becomes unmanageable
# until you restore it. Always ensure you have at least one healthy control
# plane node before draining another.
# ---

read -p "Enter the name of the node to drain: " NODE_NAME

if [ -z "$NODE_NAME" ]; then
    print_error "Node name cannot be empty."
    exit 1
fi

# Verify the node exists
if ! sudo -u "$TARGET_USER" kubectl get node "$NODE_NAME" &> /dev/null; then
    print_error "Node '$NODE_NAME' not found in cluster."
    echo ""
    echo "Available nodes:"
    sudo -u "$TARGET_USER" kubectl get nodes -o name | sed 's|node/||'
    exit 1
fi

print_success "Node '$NODE_NAME' found in cluster."

# Check if it's a control plane node
if sudo -u "$TARGET_USER" kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels}' | grep -q "control-plane"; then
    print_warning "WARNING: '$NODE_NAME' is a CONTROL PLANE node!"
    echo ""
    echo "Draining a control plane node will affect cluster management."
    echo "Ensure you have at least one other healthy control plane node."
    echo ""
    
    # Count control plane nodes
    CONTROL_PLANE_COUNT=$(sudo -u "$TARGET_USER" kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | wc -l)
    echo "Total control plane nodes in cluster: $CONTROL_PLANE_COUNT"
    echo ""
    
    if [ "$CONTROL_PLANE_COUNT" -le 1 ]; then
        print_error "This is your ONLY control plane node!"
        echo "Draining it will make the cluster unmanageable."
        echo "Add another control plane node before proceeding."
        exit 1
    fi
    
    read -p "Are you sure you want to drain this control plane node? (yes/no): " CONFIRM_CP
    if [[ "$CONFIRM_CP" != "yes" ]]; then
        print_info "Operation cancelled."
        exit 0
    fi
fi

# ============================================================================
#                   STEP 2: DISPLAY NODE INFORMATION
# ============================================================================

print_border "Step 2: Node Information"

print_info "Details for node '$NODE_NAME':"
echo ""
sudo -u "$TARGET_USER" kubectl describe node "$NODE_NAME" | head -n 20
echo ""

# Count pods on the node
POD_COUNT=$(sudo -u "$TARGET_USER" kubectl get pods --all-namespaces --field-selector spec.nodeName="$NODE_NAME" --no-headers 2>/dev/null | wc -l)

print_info "Pods currently running on this node: $POD_COUNT"

if [ "$POD_COUNT" -gt 0 ]; then
    echo ""
    print_warning "The following pods will be evicted:"
    sudo -u "$TARGET_USER" kubectl get pods --all-namespaces --field-selector spec.nodeName="$NODE_NAME" -o wide
fi

echo ""
read -p "Continue with draining this node? (yes/no): " CONFIRM_DRAIN
if [[ "$CONFIRM_DRAIN" != "yes" ]]; then
    print_info "Operation cancelled."
    exit 0
fi

# ============================================================================
#                      STEP 3: CORDON THE NODE
# ============================================================================

print_border "Step 3: Cordon Node"

# --- Tutorial: What Cordoning Does ---
# Cordoning marks a node as "unschedulable". This means:
# - No new pods will be scheduled on this node
# - Existing pods continue to run (they are NOT evicted)
# - The node remains part of the cluster
#
# This is the first safety step. We prevent new workloads from being placed
# on a node we're about to drain. Without this, new pods might appear during
# the drain process, defeating the purpose.
# ---

print_info "Cordoning node '$NODE_NAME' (marking as unschedulable)..."

if sudo -u "$TARGET_USER" kubectl cordon "$NODE_NAME"; then
    print_success "Node cordoned successfully."
else
    print_error "Failed to cordon node."
    exit 1
fi

# Verify the node is cordoned
if sudo -u "$TARGET_USER" kubectl get node "$NODE_NAME" | grep -q "SchedulingDisabled"; then
    print_success "Verified: Node is marked as SchedulingDisabled."
else
    print_warning "Node may not be properly cordoned. Check manually."
fi

# ============================================================================
#                        STEP 4: DRAIN THE NODE
# ============================================================================

print_border "Step 4: Drain Node"

# --- Tutorial: What Draining Does ---
# Draining evicts all pods from a node. Kubernetes will:
# 1. Send SIGTERM to each pod (graceful shutdown)
# 2. Wait up to terminationGracePeriodSeconds (default: 30s)
# 3. If pods haven't stopped, send SIGKILL (forced termination)
# 4. Reschedule the pods on other nodes
#
# DaemonSet pods are NOT evicted by default (they're meant to run on all nodes).
# We use --ignore-daemonsets to allow the drain to proceed despite them.
#
# Pods managed by ReplicaSets/Deployments are safely rescheduled elsewhere.
# Standalone pods (not managed by a controller) will be permanently deleted!
# ---

print_info "Draining node '$NODE_NAME' (evicting all pods)..."
echo ""
print_warning "This may take several minutes depending on pod count and grace periods."
echo ""

# Drain with commonly used flags
# --ignore-daemonsets: Allow drain to proceed despite DaemonSet pods
# --delete-emptydir-data: Delete pods using emptyDir volumes
# --force: Force deletion of standalone pods (not managed by controllers)
# --grace-period=30: Wait up to 30 seconds for graceful termination

if sudo -u "$TARGET_USER" kubectl drain "$NODE_NAME" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --grace-period=30; then
    print_success "Node drained successfully."
else
    print_error "Failed to drain node."
    echo ""
    echo "Common causes:"
    echo "  - PodDisruptionBudgets preventing eviction (check with: kubectl get pdb -A)"
    echo "  - Pods stuck in terminating state"
    echo "  - Storage volumes not releasing properly"
    echo ""
    echo "The node is still cordoned. To uncordon it:"
    echo "  kubectl uncordon $NODE_NAME"
    exit 1
fi

echo ""
print_info "Waiting 10 seconds for pods to fully terminate..."
sleep 10

# Verify drain completed
REMAINING_PODS=$(sudo -u "$TARGET_USER" kubectl get pods --all-namespaces --field-selector spec.nodeName="$NODE_NAME" --no-headers 2>/dev/null | grep -v "DaemonSet" | wc -l)

if [ "$REMAINING_PODS" -eq 0 ]; then
    print_success "All non-DaemonSet pods have been evicted."
else
    print_warning "$REMAINING_PODS pod(s) still on the node (may be DaemonSets or stuck pods)."
    sudo -u "$TARGET_USER" kubectl get pods --all-namespaces --field-selector spec.nodeName="$NODE_NAME"
fi

# ============================================================================
#                    STEP 5: DELETE NODE FROM CLUSTER
# ============================================================================

print_border "Step 5: Delete Node from Cluster"

# --- Tutorial: Deleting vs Draining ---
# Deleting a node removes its object from the Kubernetes API. After deletion:
# - The node no longer appears in "kubectl get nodes"
# - The cluster forgets about this node's existence
# - If the node's kubelet is still running, it will try to re-register
#
# You should ALWAYS drain before deleting. If you delete without draining,
# pods are lost without graceful shutdown, potentially causing data loss or
# service disruption.
# ---

echo ""
print_warning "The node is now drained. You can:"
echo "  1. Delete it from the cluster permanently"
echo "  2. Leave it cordoned for maintenance and uncordon later"
echo ""
read -p "Delete '$NODE_NAME' from cluster? (yes/no): " CONFIRM_DELETE

if [[ "$CONFIRM_DELETE" != "yes" ]]; then
    print_info "Node NOT deleted. It remains cordoned in the cluster."
    echo ""
    echo "To uncordon the node later (make it schedulable again):"
    echo "  kubectl uncordon $NODE_NAME"
    echo ""
    echo "To delete the node later:"
    echo "  kubectl delete node $NODE_NAME"
    exit 0
fi

print_info "Deleting node '$NODE_NAME' from cluster..."

if sudo -u "$TARGET_USER" kubectl delete node "$NODE_NAME"; then
    print_success "Node deleted from cluster successfully."
else
    print_error "Failed to delete node from cluster."
    exit 1
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Node Removal Complete"
print_success "Node '$NODE_NAME' has been successfully removed from the cluster!"
echo ""
echo "What was done:"
echo "  ✓ Node was cordoned (marked unschedulable)"
echo "  ✓ All pods were drained (evicted and rescheduled)"
echo "  ✓ Node was deleted from cluster state"
echo ""
print_warning "NEXT STEPS on the removed node itself:"
echo ""
echo "If you want to fully decommission the node:"
echo ""
echo "1. SSH into the node:"
echo "   ssh user@<node-ip>"
echo ""
echo "2. Stop Kubernetes services:"
echo "   sudo systemctl stop kubelet"
echo "   sudo systemctl disable kubelet"
echo ""
echo "3. Clean up Kubernetes data (OPTIONAL - only if decommissioning):"
echo "   sudo kubeadm reset -f"
echo "   sudo rm -rf /etc/cni/net.d"
echo "   sudo rm -rf /var/lib/kubelet"
echo "   sudo rm -rf /etc/kubernetes"
echo ""
echo "If you want to rejoin the node to the cluster later:"
echo ""
echo "1. On the node, reset it:"
echo "   sudo kubeadm reset -f"
echo ""
echo "2. Generate a new join token on a control plane node:"
echo "   kubeadm token create --print-join-command"
echo ""
echo "3. On the node, run the join command from step 2"
echo ""
echo "============================================================================"
echo "Verify Cluster Health:"
echo "============================================================================"
echo ""
echo "Check remaining nodes:"
echo "  kubectl get nodes"
echo ""
echo "Verify pods were rescheduled:"
echo "  kubectl get pods -A -o wide"
echo ""
echo "Check for any issues:"
echo "  kubectl get events --sort-by='.lastTimestamp'"
echo ""
echo "============================================================================"
