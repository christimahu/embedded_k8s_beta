#!/bin/bash

# ============================================================================
#
#                Install Chaos Mesh (install_chaos_mesh.sh)
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
#  What is Chaos Engineering?
#  --------------------------
#  Chaos engineering is the discipline of experimenting on a system to build
#  confidence in its capability to withstand turbulent conditions. By
#  intentionally injecting failures (pod crashes, network delays, disk
#  failures), you discover weaknesses before they cause real outages.
#
#  Why Chaos Mesh?
#  ---------------
#  Chaos Mesh is a CNCF incubating project that provides:
#  - Native Kubernetes integration (uses CRDs)
#  - Wide variety of chaos types (pod, network, IO, stress, time)
#  - Web-based dashboard for designing experiments
#  - Safe, declarative chaos definitions
#  - Scheduling and workflow capabilities
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

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the core k8s setup scripts first."
    exit 1
fi
print_success "Prerequisite 'kubectl' is installed."

if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed."
    echo ""
    echo "Install Helm with:"
    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
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
# 4. DNS Server: For DNS chaos experiments.
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

readonly DASHBOARD_SERVICE=$(sudo -u "$TARGET_USER" kubectl get svc -n chaos-mesh -l app.kubernetes.io/component=dashboard -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

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
    echo "Check with: kubectl get svc -n chaos-mesh"
fi

echo "============================================================================"
echo "Chaos Experiment Examples:"
echo "============================================================================"
echo ""
echo "Example 1: Kill a random pod in the default namespace"
echo "------------------------------------------------------------"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-example
  namespace: default
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - default
  duration: '30s'
  scheduler:
    cron: '@every 2m'
YAML
EOF
echo ""
echo "Example 2: Add network latency to a service"
echo "------------------------------------------------------------"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay-example
  namespace: default
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: my-app
  delay:
    latency: '100ms'
    correlation: '100'
    jitter: '0ms'
  duration: '1m'
YAML
EOF
echo ""
echo "Example 3: Stress test CPU usage"
echo "------------------------------------------------------------"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-example
  namespace: default
spec:
  mode: one
  selector:
    namespaces:
      - default
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: '30s'
YAML
EOF
echo ""
echo "============================================================================"
echo "Available Chaos Types:"
echo "============================================================================"
echo ""
echo "  - PodChaos:      Kill, restart, or inject failures into pods"
echo "  - NetworkChaos:  Introduce latency, packet loss, corruption"
echo "  - IOChaos:       Inject disk read/write errors and delays"
echo "  - StressChaos:   Stress CPU, memory, or disk"
echo "  - TimeChaos:     Shift system time to test time-sensitive logic"
echo "  - DNSChaos:      Inject DNS resolution errors"
echo "  - HTTPChaos:     Abort HTTP requests, inject delays"
echo "  - KernelChaos:   Inject kernel-level failures"
echo ""
echo "============================================================================"
echo "Verification Commands:"
echo "============================================================================"
echo ""
echo "List all chaos experiments:"
echo "  kubectl get podchaos,networkchaos,iochaos,stresschaos -A"
echo ""
echo "Check Chaos Mesh components:"
echo "  kubectl get pods -n chaos-mesh"
echo ""
echo "View chaos experiment details:"
echo "  kubectl describe podchaos pod-kill-example -n default"
echo ""
echo "Delete a chaos experiment:"
echo "  kubectl delete podchaos pod-kill-example -n default"
echo ""
echo "============================================================================"
echo "Best Practices:"
echo "============================================================================"
echo ""
echo "1. Start small - Test on non-production environments first"
echo "2. Use short durations initially (30s-1m)"
echo "3. Monitor your systems during chaos experiments"
echo "4. Document findings and fix discovered weaknesses"
echo "5. Gradually increase complexity and scope"
echo "6. Use selectors carefully to target specific workloads"
echo "7. Schedule experiments during low-traffic periods"
echo ""
echo "============================================================================"
echo ""
echo "Learn more: https://chaos-mesh.org/docs/"
echo "============================================================================"
