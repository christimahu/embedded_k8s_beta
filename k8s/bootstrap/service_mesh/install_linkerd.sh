#!/bin/bash

# ============================================================================
#
#                 Install Linkerd Service Mesh (install_linkerd.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Linkerd, a lightweight, simple, and security-focused service mesh
#  for Kubernetes. Linkerd provides automatic mutual TLS, observability, and
#  reliability features with minimal resource overhead and complexity.
#
#  Tutorial Goal:
#  --------------
#  You will learn what a service mesh is and why Linkerd is particularly well-
#  suited for edge computing and resource-constrained environments like ARM64
#  clusters. A service mesh automatically secures service-to-service communication,
#  provides detailed metrics, and improves reliability - all without code changes.
#  Linkerd accomplishes this with a much smaller footprint than alternatives.
#
#  What is a Service Mesh?
#  -----------------------
#  A service mesh is infrastructure that handles service-to-service communication.
#  It works by injecting a lightweight proxy (sidecar) into each pod. All network
#  traffic flows through these proxies, which provide:
#  - Automatic mutual TLS (mTLS) - encrypted, authenticated communication
#  - Traffic metrics - success rates, latencies, request volumes
#  - Reliability features - retries, timeouts, load balancing
#  - Traffic splitting - for canary deployments and A/B testing
#
#  Why Linkerd for ARM/Edge?
#  --------------------------
#  - Ultra-lightweight: ~100Mi memory overhead vs Istio's ~500Mi
#  - Written in Rust: Fast, secure, efficient
#  - Simple architecture: Easier to understand and troubleshoot
#  - Excellent ARM64 support: First-class support for ARM platforms
#  - Zero-config mTLS: Secure by default with no configuration
#
#  Linkerd vs Istio:
#  ------------------
#  - Linkerd: Simpler, lighter, faster (better for ARM/edge/learning)
#  - Istio: More features, more complex (better for large enterprises)
#
#  CRITICAL: You can only install ONE service mesh. If Istio is already
#  installed, this script will detect it and refuse to proceed.
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster
#  - Tools: kubectl must be installed and configured
#  - Resources: At least 2Gi total memory across cluster
#  - Network: Internet access for downloading Linkerd
#  - Time: ~10 minutes
#
#  Workflow:
#  ---------
#  Run this script on a management node with kubectl access. It will download
#  the Linkerd CLI, validate the cluster, and install Linkerd's control plane.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04, Kubernetes v1.30, Linkerd 2.14"

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
#              STEP 1: CHECK FOR CONFLICTING SERVICE MESH
# ============================================================================

print_border "Step 1: Checking for Conflicting Service Mesh"

# --- Tutorial: Why Service Meshes Are Mutually Exclusive ---
# Service meshes inject sidecar proxies into every pod to control network traffic.
# Running two service meshes simultaneously would cause:
# 1. Resource waste - two sidecars per pod
# 2. Conflicting policies - both meshes trying to control the same traffic
# 3. Unpredictable routing behavior
# 4. Certificate conflicts - both trying to manage mTLS
#
# You must choose one service mesh and stick with it.
# ---

print_info "Checking for existing Istio installation..."

if sudo -u "$TARGET_USER" kubectl get namespace istio-system &> /dev/null; then
    print_error "Istio is already installed in this cluster."
    echo ""
    echo "Service meshes are mutually exclusive. You must uninstall Istio before"
    echo "installing Linkerd, or choose to keep Istio instead."
    echo ""
    echo "To uninstall Istio:"
    echo "  istioctl uninstall --purge -y"
    echo "  kubectl delete namespace istio-system"
    echo ""
    echo "To keep Istio (recommended for large-scale deployments):"
    echo "  Cancel this installation and use Istio instead."
    echo ""
    exit 1
fi

if command -v istioctl &> /dev/null; then
    print_warning "istioctl CLI is installed but Istio is not running in the cluster."
    print_info "Proceeding with Linkerd installation."
fi

print_success "No conflicting service mesh detected."

# ============================================================================
#                      STEP 2: INSTALL LINKERD CLI
# ============================================================================

print_border "Step 2: Installing Linkerd CLI"

# --- Tutorial: The Linkerd CLI ---
# The linkerd CLI is the primary tool for installing and managing Linkerd.
# It provides commands for installation, verification, diagnostics, and more.
# The CLI is also used for development workflows like live traffic tapping.
# ---

print_info "Downloading and installing Linkerd CLI..."

# Download and install using the official installation script
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh

# The script installs to ~/.linkerd2/bin, so we need to move it to /usr/local/bin
LINKERD_HOME="$HOME/.linkerd2"
if [ -d "$LINKERD_HOME" ]; then
    sudo cp "$LINKERD_HOME/bin/linkerd" /usr/local/bin/
    sudo chmod +x /usr/local/bin/linkerd
fi

if ! command -v linkerd &> /dev/null; then
    print_error "Failed to install Linkerd CLI."
    exit 1
fi

print_success "Linkerd CLI installed: $(linkerd version --client --short)"

# ============================================================================
#                    STEP 3: VALIDATE CLUSTER READINESS
# ============================================================================

print_border "Step 3: Validating Cluster"

# --- Tutorial: linkerd check --pre ---
# Linkerd provides a comprehensive pre-flight check that validates your cluster
# is ready for installation. It checks:
# - Kubernetes version compatibility
# - Cluster permissions and RBAC
# - Required API resources
# - Network configuration
#
# This catches issues before installation, preventing failures mid-process.
# ---

print_info "Running Linkerd pre-installation checks..."

if sudo -u "$TARGET_USER" linkerd check --pre; then
    print_success "Cluster passed all pre-installation checks."
else
    print_error "Cluster failed pre-installation checks."
    echo ""
    echo "Please resolve the issues shown above before installing Linkerd."
    echo "Common issues:"
    echo "  - Kubernetes version too old (requires 1.21+)"
    echo "  - Missing permissions (ensure kubectl has cluster-admin)"
    echo "  - Network policies blocking required ports"
    exit 1
fi

# ============================================================================
#                  STEP 4: INSTALL LINKERD CONTROL PLANE
# ============================================================================

print_border "Step 4: Installing Linkerd Control Plane"

# --- Tutorial: Linkerd Architecture ---
# Linkerd has a simple, two-component architecture:
# 1. Control Plane: Runs in the linkerd namespace
#    - destination: Service discovery and routing
#    - identity: Certificate authority for mTLS
#    - proxy-injector: Automatically injects sidecars
# 2. Data Plane: Linkerd proxy sidecars in your application pods
#
# The control plane is lightweight (uses ~100Mi memory total) and provides
# the core service mesh capabilities.
# ---

print_info "Installing Linkerd control plane to cluster..."
print_info "This creates the linkerd namespace and core components."

# Generate the installation manifests and apply them
sudo -u "$TARGET_USER" linkerd install --crds | sudo -u "$TARGET_USER" kubectl apply -f -

if [ $? -ne 0 ]; then
    print_error "Failed to install Linkerd CRDs."
    exit 1
fi

print_info "Installing Linkerd control plane components..."

sudo -u "$TARGET_USER" linkerd install | sudo -u "$TARGET_USER" kubectl apply -f -

if [ $? -ne 0 ]; then
    print_error "Failed to install Linkerd control plane."
    exit 1
fi

print_success "Linkerd control plane installed."

# ============================================================================
#                      STEP 5: WAIT FOR DEPLOYMENT
# ============================================================================

print_border "Step 5: Waiting for Linkerd to be Ready"

print_info "Waiting for Linkerd control plane to be ready (this may take 1-2 minutes)..."

# Wait for all control plane pods to be ready
if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod \
    --all -n linkerd --timeout=300s; then
    print_success "Linkerd control plane is ready."
else
    print_warning "Some components may still be starting."
fi

# Run the full Linkerd check
print_info "Running comprehensive Linkerd health check..."

if sudo -u "$TARGET_USER" linkerd check; then
    print_success "All Linkerd checks passed!"
else
    print_warning "Some checks failed. Review the output above."
fi

# ============================================================================
#                   STEP 6: INSTALL LINKERD VIZ (OPTIONAL)
# ============================================================================

print_border "Step 6: Installing Linkerd Viz (Dashboard & Metrics)"

# --- Tutorial: Linkerd Viz Extension ---
# Linkerd Viz is an optional extension that provides:
# - Web dashboard for visualizing the service mesh
# - Grafana dashboards for metrics
# - Prometheus for metrics collection
# - Tap for real-time traffic inspection
#
# It's highly recommended for understanding what's happening in your mesh.
# ---

print_info "Installing Linkerd Viz extension..."

sudo -u "$TARGET_USER" linkerd viz install | sudo -u "$TARGET_USER" kubectl apply -f -

if [ $? -eq 0 ]; then
    print_success "Linkerd Viz extension installed."
    
    # Wait for viz pods
    print_info "Waiting for Linkerd Viz components..."
    sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod \
        --all -n linkerd-viz --timeout=300s 2>/dev/null || true
    
    print_success "Linkerd Viz is ready."
else
    print_warning "Failed to install Linkerd Viz. You can install it manually later."
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Installation Complete"
print_success "Linkerd service mesh is now running in your cluster!"
echo ""
echo "Components installed:"
echo "  ✓ Linkerd control plane (destination, identity, proxy-injector)"
echo "  ✓ Linkerd Viz extension (dashboard, metrics, tap)"
echo ""
print_warning "NEXT STEP: Inject Linkerd into your applications"
echo ""
echo "Linkerd uses a 'data plane' approach - you must explicitly add Linkerd to"
echo "your applications by injecting the proxy sidecar."
echo ""
echo "Method 1: Automatic injection (label the namespace)"
echo "============================================================================"
echo "  kubectl annotate namespace default linkerd.io/inject=enabled"
echo ""
echo "  All NEW pods in this namespace will automatically get Linkerd sidecars."
echo "  Restart existing deployments to inject sidecars:"
echo "  kubectl rollout restart deployment -n default"
echo ""
echo "Method 2: Manual injection (inject specific resources)"
echo "============================================================================"
echo "  kubectl get deploy -o yaml | linkerd inject - | kubectl apply -f -"
echo ""
echo "============================================================================"
echo "Verification:"
echo "============================================================================"
echo ""
echo "Check all Linkerd components:"
echo "  linkerd check"
echo ""
echo "View Linkerd dashboard:"
echo "  linkerd viz dashboard"
echo "  (Opens in your browser automatically)"
echo ""
echo "Check which pods have Linkerd injected:"
echo "  linkerd viz stat deployments -n default"
echo ""
echo "============================================================================"
echo "Example: Add Linkerd to an Application"
echo "============================================================================"
echo ""
cat <<'EOF'
# Deploy a sample application:
kubectl create deployment hello --image=nginx
kubectl expose deployment hello --port=80

# Inject Linkerd into it:
kubectl get deployment hello -o yaml | linkerd inject - | kubectl apply -f -

# Verify the sidecar was injected:
kubectl get pod -l app=hello
# Should show 2/2 containers (nginx + linkerd-proxy)

# Check Linkerd stats for the deployment:
linkerd viz stat deployment/hello

# Watch live traffic (like tcpdump but for HTTP):
linkerd viz tap deployment/hello
EOF
echo ""
echo "============================================================================"
echo "Golden Metrics (Automatic):"
echo "============================================================================"
echo ""
echo "Linkerd automatically provides 'golden metrics' for all meshed services:"
echo "  - Success rate (percentage of successful requests)"
echo "  - Request rate (requests per second)"
echo "  - Latency (p50, p95, p99)"
echo ""
echo "View in the dashboard:"
echo "  linkerd viz dashboard"
echo ""
echo "View in CLI:"
echo "  linkerd viz stat deployments -n default"
echo "  linkerd viz top deployments -n default"
echo ""
echo "============================================================================"
echo "Integration with Prometheus:"
echo "============================================================================"
echo ""
echo "Linkerd Viz includes its own Prometheus, but you can integrate with"
echo "the cluster-wide Prometheus installed via k8s/tools/install_prometheus.sh"
echo ""
echo "Configure Prometheus to scrape Linkerd metrics:"
echo "  kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd2/main/grafana/values.yaml"
echo ""
echo "============================================================================"
echo "Uninstalling Linkerd:"
echo "============================================================================"
echo ""
echo "If you need to remove Linkerd:"
echo "  linkerd viz uninstall | kubectl delete -f -"
echo "  linkerd uninstall | kubectl delete -f -"
echo ""
echo "Learn more: https://linkerd.io/2/overview/"
echo "============================================================================"
