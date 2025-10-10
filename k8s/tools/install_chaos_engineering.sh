#!/bin/bash

# ============================================================================
#
#        Install Chaos Engineering Tools (install_chaos_engineering.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Chaos Mesh, a CNCF chaos engineering platform for Kubernetes,
#  which allows you to deliberately inject failures to test system resilience.
#
#  Tutorial Goal:
#  --------------
#  This script teaches chaos engineering concepts while installing the tools to
#  practice them. You'll learn why deliberately breaking things (killing pods,
#  injecting network latency) in a controlled way is a critical part of
#  building reliable, modern distributed systems.
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster.
#  - Tools: `kubectl` and `helm` must be installed and configured.
#  - Network: SSH access and an active internet connection.
#  - Time: ~10 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a management node. It will use Helm to install the
#  Chaos Mesh controllers and dashboard into your Kubernetes cluster.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04, Kubernetes v1.30, Helm v3.13"

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
print_success "Target user: $TARGET_USER"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the core k8s setup scripts first."
    exit 1
fi
print_success "Prerequisite 'kubectl' is installed."

if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please run 'install_k8s_extras.sh' first."
    exit 1
fi
print_success "Prerequisite 'Helm' is installed."

if ! sudo -u "$TARGET_USER" kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to a Kubernetes cluster. Is your kubeconfig set up?"
    exit 1
fi
print_success "Successfully connected to Kubernetes cluster."

# ============================================================================
#                  STEP 1: INSTALL CHAOS MESH VIA HELM
# ============================================================================

print_border "Step 1: Installing Chaos Mesh to Kubernetes Cluster"

# --- Tutorial: What Gets Installed? ---
# Chaos Mesh installs several components into a dedicated `chaos-mesh` namespace:
# 1. Custom Resource Definitions (CRDs): New k8s resources for chaos experiments.
# 2. Controllers: Watch for and execute chaos experiments.
# 3. Dashboard: A web UI for designing and monitoring experiments.
# ---
print_info "Adding Chaos Mesh Helm repository..."
sudo -u "$TARGET_USER" helm repo add chaos-mesh https://charts.chaos-mesh.org
sudo -u "$TARGET_USER" helm repo update
print_success "Chaos Mesh Helm repository added."

print_info "Installing Chaos Mesh via Helm (this may take a few minutes)..."
sudo -u "$TARGET_USER" helm install chaos-mesh chaos-mesh/chaos-mesh \
    --namespace chaos-mesh \
    --create-namespace \
    --set dashboard.create=true \
    --set dashboard.securityMode=false \
    --wait

print_success "Chaos Mesh installed successfully."

# ============================================================================
#                      STEP 2: VERIFY INSTALLATION
# ============================================================================

print_border "Step 2: Verifying Installation"

print_info "Waiting for all Chaos Mesh pods to be ready..."
if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod --all -n chaos-mesh --timeout=300s; then
    print_success "All Chaos Mesh components are up and running."
else
    print_warning "Some components may still be starting. Check with: kubectl get pods -n chaos-mesh"
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete & How to Access Dashboard"
print_success "Chaos Mesh is now installed in your cluster!"

readonly DASHBOARD_SERVICE=$(sudo -u "$TARGET_USER" kubectl get svc -n chaos-mesh -l app.kubernetes.io/component=dashboard -o jsonpath='{.items[0].metadata.name}')

if [ -n "$DASHBOARD_SERVICE" ]; then
    echo ""
    echo "To access the Chaos Mesh dashboard:"
    echo "1. From your local machine (with kubectl access), run:"
    echo "   kubectl port-forward -n chaos-mesh svc/$DASHBOARD_SERVICE 2333:2333"
    echo ""
    echo "2. Open a browser to: http://localhost:2333"
    echo ""
else
    print_warning "Could not find dashboard service. It may still be initializing."
fi

print_info "To learn more and see experiment examples, visit: https://chaos-mesh.org/docs/"
