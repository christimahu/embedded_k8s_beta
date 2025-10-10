#!/bin/bash

# ============================================================================
#
#                    Install Argo CD (install_argocd.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Argo CD, a declarative, GitOps continuous delivery tool for
#  Kubernetes. It allows you to manage application deployments and cluster
#  configuration from a Git repository.
#
#  Tutorial Goal:
#  --------------
#  You will learn the fundamentals of GitOps. Instead of using `kubectl apply`
#  to push changes to the cluster, the GitOps model uses a Git repository as the
#  single source of truth. Argo CD runs in the cluster, continuously monitors your
#  Git repo, and automatically applies any changes to keep the cluster state in
#  sync with your declarations. This provides a fully auditable, version-controlled,
#  and automated way to manage infrastructure.
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster.
#  - Tools: `kubectl` must be installed and configured.
#  - Git: A Git repository (e.g., on Gitea, GitHub) to use as the source of truth.
#  - Time: ~10 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a management node. It will deploy Argo CD to your cluster
#  and provide instructions for accessing its UI and CLI.
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
print_success "Target user: $TARGET_USER"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the core k8s setup scripts first."
    exit 1
fi
print_success "Prerequisite 'kubectl' is installed."

if ! sudo -u "$TARGET_USER" kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to a Kubernetes cluster. Is your kubeconfig set up?"
    exit 1
fi
print_success "Successfully connected to Kubernetes cluster."

# ============================================================================
#                     STEP 1: DEPLOY ARGO CD TO CLUSTER
# ============================================================================

print_border "Step 1: Deploy Argo CD to the Cluster"

# --- Tutorial: Argo CD Installation ---
# We install Argo CD into its own namespace to keep its components isolated.
# The official installation manifest from the Argo project contains all the
# necessary Deployments, Services, CRDs, and RBAC configurations.
# ---
print_info "Creating the argocd namespace..."
sudo -u "$TARGET_USER" kubectl create namespace argocd --dry-run=client -o yaml | sudo -u "$TARGET_USER" kubectl apply -f -

print_info "Applying the official Argo CD installation manifest..."
sudo -u "$TARGET_USER" kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

print_success "Argo CD manifests applied."

# ============================================================================
#                      STEP 2: INSTALL ARGO CD CLI
# ============================================================================

print_border "Step 2: Install the Argo CD CLI"

print_info "Downloading the Argo CD CLI..."
readonly ARGOCD_VERSION="v2.11.3" # Check for the latest version
readonly ARGOCD_ARCH_MAP="x86_64:amd64 aarch64:arm64 arm64:arm64"
ARCH=$(uname -m)
ARGOCD_ARCH=$(echo "$ARGOCD_ARCH_MAP" | grep -o "$ARCH:[^ ]*" | cut -d: -f2)
if [[ -z "$ARGOCD_ARCH" ]]; then
    print_error "Unsupported architecture for Argo CD CLI: $ARCH"
    exit 1
fi

sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${ARGOCD_ARCH}
sudo chmod +x /usr/local/bin/argocd
print_success "Argo CD CLI installed successfully."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete & How to Access Argo CD"

print_info "Waiting for Argo CD pods to be ready (this can take a few minutes)..."
sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod --all -n argocd --timeout=600s
print_success "Argo CD services are running."
echo ""

print_warning "ACTION REQUIRED: Log in and change the default password."
echo ""
echo "1. Get the auto-generated initial admin password:"
echo "   argocd admin initial-password -n argocd"
echo ""
echo "2. From your local machine, forward the Argo CD server port:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "3. Open a browser to https://localhost:8080 (accept the self-signed cert warning)."
echo ""
echo "4. Log in with user 'admin' and the password from step 1."
echo ""
echo "5. You can also log in via the CLI:"
echo "   argocd login localhost:8080"
echo ""
echo "To get started with GitOps, read the user guide: https://argo-cd.readthedocs.io/en/stable/getting_started/"
