#!/bin/bash

# ============================================================================
#
#                    Install Knative (install_knative.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Knative, a Kubernetes-based platform for deploying and managing
#  serverless workloads. Knative enables auto-scaling, scale-to-zero, and
#  event-driven architectures on your own infrastructure.
#
#  Tutorial Goal:
#  --------------
#  You will learn how serverless computing works on Kubernetes. Knative brings
#  AWS Lambda-style functions to your cluster, but with containers instead of
#  code bundles. The key innovation is "scale to zero" - when your function
#  isn't being used, it consumes ZERO resources. On edge/ARM hardware with
#  limited resources, this is transformative.
#
#  What is Serverless?
#  -------------------
#  Traditional: Deploy an app → it runs 24/7 → wastes resources when idle
#  Serverless:  Deploy a function → runs on-demand → scales to zero when idle
#
#  Knative Components:
#  -------------------
#  This script installs both main components:
#
#  1. **Knative Serving** - Serverless containers
#     - Auto-scaling from 0 to N replicas based on traffic
#     - Scale to zero after idle period (default: 60 seconds)
#     - Built-in traffic splitting (canary deployments, A/B testing)
#     - Automatic HTTPS with cert-manager integration
#
#  2. **Knative Eventing** - Event-driven architecture
#     - Event sources (webhooks, message queues, sensors)
#     - Event routing and filtering
#     - Triggers and subscriptions
#     - Perfect for IoT and edge computing
#
#  Why Knative for Edge/ARM?
#  --------------------------
#  - Save power: Functions scale to zero when idle
#  - Efficient resource use: Only run what you need, when you need it
#  - IoT-friendly: Event-driven model perfect for sensors/actuators
#  - Cost-effective: Maximize workload density on limited hardware
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster.
#  - Completed: Install a networking layer FIRST:
#    * Option A: install_ingress_nginx.sh (simpler, recommended)
#    * Option B: install_istio.sh or install_linkerd.sh (advanced)
#  - Optional: install_cert_manager.sh (for automatic HTTPS)
#  - Tools: kubectl must be installed and configured.
#  - Network: SSH access and an active internet connection.
#  - Resources: At least 4Gi total memory recommended.
#  - Time: ~10-15 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a management node with kubectl access. It will deploy
#  Knative Serving and Eventing into your cluster.
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

# Check for networking layer
print_info "Checking for required networking layer..."

HAS_INGRESS=false
HAS_ISTIO=false
HAS_LINKERD=false

if sudo -u "$TARGET_USER" kubectl get namespace ingress-nginx &> /dev/null; then
    HAS_INGRESS=true
    print_success "Found NGINX Ingress Controller."
fi

if sudo -u "$TARGET_USER" kubectl get namespace istio-system &> /dev/null; then
    HAS_ISTIO=true
    print_success "Found Istio service mesh."
fi

if sudo -u "$TARGET_USER" kubectl get namespace linkerd &> /dev/null; then
    HAS_LINKERD=true
    print_success "Found Linkerd service mesh."
fi

if ! $HAS_INGRESS && ! $HAS_ISTIO && ! $HAS_LINKERD; then
    print_error "No networking layer found!"
    echo ""
    echo "Knative requires a networking layer to route traffic to functions."
    echo "Please install one of the following first:"
    echo ""
    echo "  Recommended (simpler):"
    echo "    cd embedded_k8s/k8s/addons"
    echo "    sudo ./install_ingress_nginx.sh"
    echo ""
    echo "  Advanced (if you want service mesh features):"
    echo "    sudo ./install_istio.sh"
    echo "    OR"
    echo "    sudo ./install_linkerd.sh"
    exit 1
fi

# ============================================================================
#            STEP 1: INSTALL KNATIVE SERVING (CORE COMPONENT)
# ============================================================================

print_border "Step 1: Installing Knative Serving"

# --- Tutorial: Knative Serving Architecture ---
# Knative Serving consists of several components:
# 1. CRDs: Define new resource types (Service, Route, Configuration, Revision)
# 2. Controller: Manages the lifecycle of serverless workloads
# 3. Webhook: Validates and mutates Knative resources
# 4. Autoscaler: Scales workloads based on metrics (including to zero)
# 5. Activator: Buffers requests and wakes up scaled-to-zero services
#
# These work together to provide the serverless experience.
# ---

readonly KNATIVE_VERSION="v1.12.0"

print_info "Installing Knative Serving CRDs and core components (${KNATIVE_VERSION})..."

# Install CRDs
sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml"

if [ $? -ne 0 ]; then
    print_error "Failed to install Knative Serving CRDs."
    exit 1
fi
print_success "Knative Serving CRDs installed."

# Install core components
sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml"

if [ $? -ne 0 ]; then
    print_error "Failed to install Knative Serving core components."
    exit 1
fi
print_success "Knative Serving core components installed."

# ============================================================================
#              STEP 2: INSTALL NETWORKING LAYER FOR KNATIVE
# ============================================================================

print_border "Step 2: Configuring Knative Networking Layer"

# --- Tutorial: Knative Networking Options ---
# Knative can work with several networking layers:
# - Kourier (Knative's own, lightweight)
# - Istio (service mesh with advanced features)
# - Contour (Envoy-based ingress)
# - NGINX Ingress (via Knative integration)
#
# We'll install Kourier as it's the simplest and works with your existing
# ingress controller or service mesh for external access.
# ---

print_info "Installing Kourier networking layer for Knative..."

sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml"

if [ $? -ne 0 ]; then
    print_error "Failed to install Kourier."
    exit 1
fi

# Configure Knative to use Kourier
sudo -u "$TARGET_USER" kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

print_success "Kourier networking layer installed and configured."

# ============================================================================
#                 STEP 3: CONFIGURE DNS (MAGIC DNS)
# ============================================================================

print_border "Step 3: Configuring DNS"

# --- Tutorial: DNS for Knative Services ---
# Each Knative Service gets a unique URL like: myfunction.default.example.com
# For development/testing, we use "Magic DNS" (sslip.io or nip.io) which
# provides wildcard DNS without needing a real domain.
#
# For production, you'd configure real DNS pointing to your LoadBalancer IP.
# ---

print_info "Configuring Magic DNS for development (using sslip.io)..."

sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-default-domain.yaml"

if [ $? -eq 0 ]; then
    print_success "Magic DNS configured. Functions will be accessible at *.sslip.io URLs."
else
    print_warning "Magic DNS configuration failed. You may need to configure DNS manually."
fi

# ============================================================================
#           STEP 4: INSTALL KNATIVE EVENTING (OPTIONAL)
# ============================================================================

print_border "Step 4: Installing Knative Eventing"

print_info "Knative Eventing enables event-driven architectures."
echo ""
read -p "Install Knative Eventing? (Recommended for IoT/edge) (Y/N): " INSTALL_EVENTING

if [[ "$INSTALL_EVENTING" =~ ^[Yy] ]]; then
    print_info "Installing Knative Eventing CRDs and core components..."
    
    # Install Eventing CRDs
    sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-crds.yaml"
    
    # Install Eventing core
    sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml"
    
    # Install in-memory channel (simple event routing)
    sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/in-memory-channel.yaml"
    
    # Install MT Channel Broker
    sudo -u "$TARGET_USER" kubectl apply -f "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/mt-channel-broker.yaml"
    
    print_success "Knative Eventing installed."
else
    print_info "Skipping Knative Eventing. You can install it later if needed."
fi

# ============================================================================
#                      STEP 5: WAIT FOR DEPLOYMENT
# ============================================================================

print_border "Step 5: Waiting for Knative to be Ready"

print_info "Waiting for Knative Serving pods to be ready (this may take 2-3 minutes)..."

if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod --all -n knative-serving --timeout=300s; then
    print_success "Knative Serving is ready."
else
    print_warning "Some components may still be starting. Check with: kubectl get pods -n knative-serving"
fi

if [[ "$INSTALL_EVENTING" =~ ^[Yy] ]]; then
    print_info "Waiting for Knative Eventing pods to be ready..."
    
    if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod --all -n knative-eventing --timeout=300s; then
        print_success "Knative Eventing is ready."
    else
        print_warning "Some components may still be starting. Check with: kubectl get pods -n knative-eventing"
    fi
fi

# ============================================================================
#                  STEP 6: CONFIGURE AUTOSCALER FOR EDGE
# ============================================================================

print_border "Step 6: Optimizing Autoscaler for Edge Computing"

# --- Tutorial: Autoscaler Configuration ---
# Knative's autoscaler can be tuned for edge/ARM environments:
# - scale-to-zero-grace-period: How long to wait before scaling to zero
# - stable-window: Time window for stable scaling decisions
# - target-burst-capacity: Extra capacity during traffic spikes
#
# For edge computing, we optimize for resource efficiency over ultra-low latency.
# ---

print_info "Configuring autoscaler for edge computing optimization..."

sudo -u "$TARGET_USER" kubectl patch configmap/config-autoscaler \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{
    "scale-to-zero-grace-period":"30s",
    "stable-window":"60s",
    "enable-scale-to-zero":"true"
  }}'

print_success "Autoscaler configured for edge computing."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Installation Complete"
print_success "Knative is now running in your cluster!"
echo ""
echo "Components installed:"
echo "  ✓ Knative Serving (serverless containers)"
if [[ "$INSTALL_EVENTING" =~ ^[Yy] ]]; then
echo "  ✓ Knative Eventing (event-driven architecture)"
fi
echo "  ✓ Kourier networking layer"
echo "  ✓ Magic DNS (sslip.io for development)"
echo ""
print_warning "NEXT STEPS: Deploy your first serverless function"
echo ""
echo "============================================================================"
echo "Example 1: Simple Hello World Function"
echo "============================================================================"
echo ""
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: default
spec:
  template:
    spec:
      containers:
        - image: gcr.io/knative-samples/helloworld-go
          ports:
            - containerPort: 8080
          env:
            - name: TARGET
              value: "Knative on Edge"
YAML
EOF
echo ""
echo "Check service status:"
echo "  kubectl get ksvc hello"
echo ""
echo "Get the service URL:"
echo "  kubectl get ksvc hello -o jsonpath='{.status.url}'"
echo ""
echo "Test the function:"
echo "  curl \$(kubectl get ksvc hello -o jsonpath='{.status.url}')"
echo ""
echo "Watch it scale to zero after 30 seconds of no traffic:"
echo "  watch kubectl get pods"
echo ""
echo "============================================================================"
echo "Example 2: Using Your Local Docker Registry"
echo "============================================================================"
echo ""
cat <<'EOF'
# Build and push your function to local registry:
docker build -t registry.local:5000/my-function:v1 .
docker push registry.local:5000/my-function:v1

# Deploy from local registry:
cat <<YAML | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: my-function
spec:
  template:
    spec:
      containers:
        - image: registry.local:5000/my-function:v1
          ports:
            - containerPort: 8080
YAML
EOF
echo ""
echo "============================================================================"
echo "Example 3: Traffic Splitting (Canary Deployment)"
echo "============================================================================"
echo ""
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: my-app
spec:
  traffic:
    - revisionName: my-app-v1
      percent: 90
    - revisionName: my-app-v2
      percent: 10
      tag: canary
YAML
EOF
echo ""
echo "This routes 90% traffic to v1, 10% to v2 for testing."
echo ""
if [[ "$INSTALL_EVENTING" =~ ^[Yy] ]]; then
echo "============================================================================"
echo "Example 4: Event-Driven Function (Eventing)"
echo "============================================================================"
echo ""
cat <<'EOF'
# Create a broker:
kubectl create -f - <<YAML
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: default
  namespace: default
YAML

# Create a function that responds to events:
kubectl create -f - <<YAML
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: event-handler
spec:
  template:
    spec:
      containers:
        - image: gcr.io/knative-samples/helloworld-go
YAML

# Create a trigger to route events:
kubectl create -f - <<YAML
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: my-trigger
spec:
  broker: default
  subscriber:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: event-handler
YAML
EOF
echo ""
echo "Send an event:"
echo "  kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \\"
echo "    -X POST http://broker-ingress.knative-eventing.svc.cluster.local/default/default \\"
echo "    -H 'Ce-Id: 1' -H 'Ce-Source: test' -H 'Ce-Type: test' \\"
echo "    -H 'Ce-Specversion: 1.0' -d 'Hello from edge!'"
echo ""
fi
echo "============================================================================"
echo "Knative Concepts:"
echo "============================================================================"
echo ""
echo "  Service:     Top-level resource (like Deployment + Service combined)"
echo "  Revision:    Immutable snapshot of code + config (like Git commit)"
echo "  Route:       Maps URLs to Revisions (traffic splitting happens here)"
echo "  Configuration: Desired state of your function"
echo ""
echo "  Scale to Zero: Functions consume ZERO resources when idle"
echo "  Cold Start:    Time to wake up from zero (~1-2 seconds)"
echo "  Auto-scaling:  Automatic scaling based on request concurrency"
echo ""
echo "============================================================================"
echo "Monitoring & Debugging:"
echo "============================================================================"
echo ""
echo "List all Knative services:"
echo "  kubectl get ksvc"
echo ""
echo "Get detailed service info:"
echo "  kubectl describe ksvc <service-name>"
echo ""
echo "View function logs:"
echo "  kubectl logs -l serving.knative.dev/service=<service-name> -c user-container"
echo ""
echo "Watch auto-scaling in action:"
echo "  watch kubectl get pods"
echo ""
echo "Check Knative Serving components:"
echo "  kubectl get pods -n knative-serving"
echo ""
if [[ "$INSTALL_EVENTING" =~ ^[Yy] ]]; then
echo "Check Knative Eventing components:"
echo "  kubectl get pods -n knative-eventing"
echo ""
fi
echo "============================================================================"
echo "Resource Savings with Scale-to-Zero:"
echo "============================================================================"
echo ""
echo "Traditional Deployment (always running):"
echo "  - 3 replicas × 512Mi = 1.5Gi RAM used 24/7"
echo "  - Running even when idle (wasteful on edge hardware)"
echo ""
echo "Knative Service (scale-to-zero):"
echo "  - 0 replicas when idle = 0Mi RAM"
echo "  - Scales up in ~1 second when request arrives"
echo "  - Scales back down after 30 seconds idle"
echo "  - Savings: ~99% for workloads with sporadic traffic"
echo ""
echo "============================================================================"
echo "Production DNS Setup (Optional):"
echo "============================================================================"
echo ""
echo "For production, replace Magic DNS with real DNS:"
echo ""
echo "1. Get your LoadBalancer IP:"
echo "   kubectl get svc kourier -n kourier-system"
echo ""
echo "2. Create DNS wildcard record:"
echo "   *.knative.yourdomain.com → <LoadBalancer-IP>"
echo ""
echo "3. Configure Knative to use your domain:"
echo "   kubectl patch configmap/config-domain -n knative-serving \\"
echo "     --type merge \\"
echo "     --patch '{\"data\":{\"knative.yourdomain.com\":\"\"}}'"
echo ""
echo "============================================================================"
echo "Integration with cert-manager (HTTPS):"
echo "============================================================================"
echo ""
echo "If you installed cert-manager, enable automatic HTTPS:"
echo ""
echo "1. Install net-certmanager:"
echo "   kubectl apply -f https://github.com/knative/net-certmanager/releases/download/knative-${KNATIVE_VERSION}/release.yaml"
echo ""
echo "2. Configure your ClusterIssuer (Let's Encrypt):"
echo "   kubectl patch configmap/config-certmanager -n knative-serving \\"
echo "     --type merge \\"
echo "     --patch '{\"data\":{\"issuerRef\":\"kind: ClusterIssuer\\nname: letsencrypt-prod\"}}'"
echo ""
echo "All Knative services will automatically get HTTPS certificates!"
echo ""
echo "============================================================================"
echo "Learn more: https://knative.dev/docs/"
echo "============================================================================"
