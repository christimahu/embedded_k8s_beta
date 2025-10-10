#!/bin/bash

# ============================================================================
#
#              Install Prometheus & Grafana (install_prometheus.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Deploys the kube-prometheus-stack, a comprehensive monitoring solution for
#  Kubernetes. This includes Prometheus for metrics collection, Grafana for
#  dashboards, and Alertmanager for notifications.
#
#  Tutorial Goal:
#  --------------
#  You will learn the standard, Helm-based method for deploying a complete
#  monitoring stack. We will install the `kube-prometheus-stack` chart, which
#  is pre-configured with ServiceMonitors to automatically discover and scrape
#  metrics from core Kubernetes components. You'll understand how these tools
#  work together to provide deep visibility into cluster health and performance.
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster.
#  - Tools: `kubectl` and `helm` must be installed and configured.
#  - Network: SSH access and an active internet connection.
#  - Time: ~15-20 minutes (image pulls can be large).
#
#  Workflow:
#  ---------
#  Run this script on a management node. It will use Helm to deploy the entire
#  monitoring stack into a dedicated `monitoring` namespace in your cluster.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
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
#           STEP 1: INSTALL PROMETHEUS MONITORING STACK VIA HELM
# ============================================================================

print_border "Step 1: Install Prometheus Monitoring Stack"

# --- Tutorial: The kube-prometheus-stack Helm Chart ---
# This community-managed chart is the industry standard for Kubernetes monitoring.
# It bundles together Prometheus, Grafana, and Alertmanager and includes a set
# of pre-configured dashboards and alerting rules specifically for Kubernetes,
# saving hundreds of hours of manual configuration.
# ---
print_info "Adding the Prometheus community Helm repository..."
sudo -u "$TARGET_USER" helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
sudo -u "$TARGET_USER" helm repo update
print_success "Prometheus repository added."

print_info "Installing the kube-prometheus-stack (this may take several minutes)..."
sudo -u "$TARGET_USER" helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --wait

print_success "kube-prometheus-stack has been deployed successfully."

# ============================================================================
#                      STEP 2: VERIFY INSTALLATION
# ============================================================================

print_border "Step 2: Verifying Installation"

print_info "Waiting for all monitoring pods to be ready..."
if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod --all -n monitoring --timeout=600s; then
    print_success "All Prometheus and Grafana components are up and running."
else
    print_warning "Some components may still be starting. Check with: kubectl get pods -n monitoring"
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete & How to Access Dashboards"
print_success "Prometheus and Grafana are now monitoring your cluster."
echo ""
echo "To access the Grafana dashboard (for viewing metrics):"
echo "1. Get the auto-generated admin password:"
echo "   kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 --decode ; echo"
echo ""
echo "2. From your local machine, forward the Grafana port:"
echo "   kubectl port-forward --namespace monitoring svc/prometheus-grafana 8080:80"
echo ""
echo "3. Open a browser to http://localhost:8080 and log in with:"
echo "   - User: admin"
echo "   - Password: <the password from step 1>"
echo ""
echo "----------------------------------------------------------------------------"
echo "To access the Prometheus UI (for querying raw metrics):"
echo "1. From your local machine, forward the Prometheus port:"
echo "   kubectl port-forward --namespace monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo ""
echo "2. Open a browser to http://localhost:9090"
echo "----------------------------------------------------------------------------"
