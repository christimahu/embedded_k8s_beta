#!/bin/bash

# ============================================================================
#
#                    Install Istio Service Mesh (install_istio.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Istio, a feature-rich service mesh that provides secure service-to-
#  service communication, traffic management, and deep observability for
#  microservices running in Kubernetes.
#
#  Tutorial Goal:
#  --------------
#  You will learn what a service mesh is and why it's valuable for production
#  Kubernetes deployments. Without a service mesh, services communicate over
#  plain HTTP with no encryption, no fine-grained traffic control, and limited
#  observability. Istio solves this by automatically injecting sidecar proxies
#  that handle all network traffic, providing:
#  - Automatic mutual TLS (mTLS) for service-to-service encryption
#  - Traffic routing and splitting (canary deployments, A/B testing)
#  - Distributed tracing to understand request flows
#  - Circuit breaking and fault injection for resilience testing
#
#  What is a Sidecar?
#  ------------------
#  A sidecar is a second container that runs alongside your application container
#  in the same pod. Istio injects an Envoy proxy sidecar into each pod. All
#  network traffic in/out of your app goes through this proxy, which enforces
#  policies and collects metrics without any code changes to your application.
#
#  Istio vs Linkerd:
#  ------------------
#  - Istio: More features, higher resource usage, steeper learning curve
#  - Linkerd: Simpler, lighter, easier to learn (better for ARM/edge)
#
#  CRITICAL: You can only install ONE service mesh. If Linkerd is already
#  installed, this script will detect it and refuse to proceed.
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster
#  - Tools: kubectl must be installed and configured
#  - Resources: At least 4Gi total memory across cluster (Istio is heavier)
#  - Network: Internet access for downloading Istio
#  - Time: ~10-15 minutes
#
#  Workflow:
#  ---------
#  Run this script on a management node with kubectl access. It will download
#  istioctl, install Istio's control plane, and configure basic settings.
#
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04, Kubernetes v1.30, Istio 1.20"

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
# Service meshes work by injecting sidecar proxies into every pod and
# controlling all network traffic. Having two service meshes would mean:
# 1. Two sidecars in every pod (massive resource waste)
# 2. Conflicting traffic policies and routing rules
# 3. Unpredictable behavior as both try to control the same traffic
#
# It's technically possible but practically nonsensical. You must choose one.
# ---

print_info "Checking for existing Linkerd installation..."

if sudo -u "$TARGET_USER" kubectl get namespace linkerd &> /dev/null; then
    print_error "Linkerd is already installed in this cluster."
    echo ""
    echo "Service meshes are mutually exclusive. You must uninstall Linkerd before"
    echo "installing Istio, or choose to keep Linkerd instead."
    echo ""
    echo "To uninstall Linkerd:"
    echo "  linkerd uninstall | kubectl delete -f -"
    echo ""
    echo "To keep Linkerd (recommended for ARM/edge clusters):"
    echo "  Cancel this installation and use Linkerd instead."
    echo ""
    exit 1
fi

if command -v linkerd &> /dev/null; then
    print_warning "Linkerd CLI is installed but Linkerd is not running in the cluster."
    print_info "Proceeding with Istio installation."
fi

print_success "No conflicting service mesh detected."

# ============================================================================
#                      STEP 2: INSTALL ISTIOCTL
# ============================================================================

print_border "Step 2: Installing istioctl CLI"

# --- Tutorial: istioctl ---
# istioctl is the command-line tool for installing and managing Istio.
# It handles the complex installation process, validates configurations,
# and provides diagnostic commands. We'll download the latest stable version.
# ---

readonly ISTIO_VERSION="1.20.0"

print_info "Downloading Istio ${ISTIO_VERSION}..."

cd /tmp
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -

if [ ! -d "/tmp/istio-${ISTIO_VERSION}" ]; then
    print_error "Failed to download Istio."
    exit 1
fi

print_info "Installing istioctl to /usr/local/bin..."
sudo cp "/tmp/istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/
sudo chmod +x /usr/local/bin/istioctl

if ! command -v istioctl &> /dev/null; then
    print_error "Failed to install istioctl."
    exit 1
fi

print_success "istioctl installed: $(istioctl version --remote=false --short)"

# ============================================================================
#                    STEP 3: INSTALL ISTIO TO CLUSTER
# ============================================================================

print_border "Step 3: Installing Istio to Cluster"

# --- Tutorial: Istio Installation Profiles ---
# Istio provides several installation profiles:
# - default: Suitable for production (installs istiod and ingress gateway)
# - demo: For learning and testing (includes extra observability tools)
# - minimal: Just the core components
# - ambient: New sidecar-less mode (experimental)
#
# We use 'default' for a production-ready setup. The demo profile includes
# Kiali, Jaeger, Prometheus, and Grafana, but those increase resource usage
# significantly. For this repository, users can install Prometheus separately
# via k8s/tools/install_prometheus.sh.
# ---

print_info "Installing Istio with 'default' profile..."
print_info "This installs the Istio control plane (istiod) and ingress gateway."

sudo -u "$TARGET_USER" istioctl install --set profile=default -y

if [ $? -ne 0 ]; then
    print_error "Istio installation failed."
    exit 1
fi

print_success "Istio control plane installed."

# ============================================================================
#                   STEP 4: ENABLE AUTOMATIC SIDECAR INJECTION
# ============================================================================

print_border "Step 4: Configuring Automatic Sidecar Injection"

# --- Tutorial: Sidecar Injection ---
# Istio works by running an Envoy proxy sidecar in each pod. You can inject
# sidecars manually or automatically. Automatic injection works by labeling
# a namespace with 'istio-injection=enabled'. When you deploy a pod to that
# namespace, Istio's admission webhook automatically adds the sidecar.
#
# We'll label the 'default' namespace as an example. For production, you would
# label your application namespaces.
# ---

print_info "Enabling automatic sidecar injection for the 'default' namespace..."

sudo -u "$TARGET_USER" kubectl label namespace default istio-injection=enabled --overwrite

if [ $? -eq 0 ]; then
    print_success "Automatic sidecar injection enabled for 'default' namespace."
else
    print_warning "Failed to label namespace. You can do this manually later."
fi

echo ""
print_info "To enable sidecar injection for other namespaces:"
echo "  kubectl label namespace <namespace-name> istio-injection=enabled"

# ============================================================================
#                      STEP 5: WAIT FOR DEPLOYMENT
# ============================================================================

print_border "Step 5: Waiting for Istio to be Ready"

print_info "Waiting for Istio control plane pods to be ready..."

if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod \
    --all -n istio-system --timeout=300s; then
    print_success "All Istio components are running."
else
    print_warning "Some components may still be starting. Check with: kubectl get pods -n istio-system"
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Installation Complete"
print_success "Istio service mesh is now running in your cluster!"
echo ""
echo "Components installed:"
echo "  ✓ istiod (control plane)"
echo "  ✓ istio-ingressgateway"
echo "  ✓ Automatic sidecar injection enabled for 'default' namespace"
echo ""
print_warning "IMPORTANT: Restart existing pods to inject sidecars"
echo ""
echo "Pods created before Istio was installed don't have sidecars yet."
echo "Restart them to get Istio features:"
echo ""
echo "  kubectl rollout restart deployment -n default"
echo ""
echo "============================================================================"
echo "Verification:"
echo "============================================================================"
echo ""
echo "Check Istio components:"
echo "  kubectl get pods -n istio-system"
echo ""
echo "Verify sidecar injection is enabled:"
echo "  kubectl get namespace -L istio-injection"
echo ""
echo "Check Istio version:"
echo "  istioctl version"
echo ""
echo "Analyze cluster configuration:"
echo "  istioctl analyze"
echo ""
echo "============================================================================"
echo "Example: Deploy a sample application with Istio"
echo "============================================================================"
echo ""
cat <<'EOF'
# Deploy the Istio sample bookinfo application:
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml

# Verify sidecars were injected:
kubectl get pods
# Each pod should show 2/2 containers (app + istio-proxy)

# Expose via Istio Ingress Gateway:
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/networking/bookinfo-gateway.yaml

# Get the ingress gateway IP/port:
export INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')

# Access the application:
echo "http://${INGRESS_HOST}:${INGRESS_PORT}/productpage"
EOF
echo ""
echo "============================================================================"
echo "Observability Add-ons (Optional):"
echo "============================================================================"
echo ""
echo "Istio can integrate with observability tools. Install them separately:"
echo ""
echo "Prometheus (metrics):"
echo "  cd /tmp/istio-${ISTIO_VERSION}"
echo "  kubectl apply -f samples/addons/prometheus.yaml"
echo ""
echo "Grafana (dashboards):"
echo "  kubectl apply -f samples/addons/grafana.yaml"
echo ""
echo "Kiali (service mesh dashboard):"
echo "  kubectl apply -f samples/addons/kiali.yaml"
echo ""
echo "Jaeger (distributed tracing):"
echo "  kubectl apply -f samples/addons/jaeger.yaml"
echo ""
echo "Or install our full monitoring stack:"
echo "  cd embedded_k8s/k8s/tools"
echo "  sudo ./install_prometheus.sh"
echo ""
echo "============================================================================"
echo "Uninstalling Istio:"
echo "============================================================================"
echo ""
echo "If you need to remove Istio:"
echo "  istioctl uninstall --purge -y"
echo "  kubectl delete namespace istio-system"
echo ""
echo "Learn more: https://istio.io/latest/docs/"
echo "============================================================================"

# Cleanup
rm -rf "/tmp/istio-${ISTIO_VERSION}"
