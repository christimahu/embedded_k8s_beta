#!/bin/bash

# ============================================================================
#
#          Install NGINX Ingress Controller (install_ingress_nginx.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs the NGINX Ingress Controller, which provides Layer 7 (HTTP/HTTPS)
#  load balancing and routing for Kubernetes services. This is the standard
#  way to expose web applications to external users.
#
#  Tutorial Goal:
#  --------------
#  You will learn how Kubernetes separates internal networking (Services) from
#  external access (Ingress). A Service gives pods a stable internal endpoint,
#  but to make them accessible from outside the cluster via HTTP/HTTPS, you
#  need an Ingress Controller. The NGINX Ingress Controller is the most popular
#  choice, providing powerful routing, SSL termination, and integration with
#  cert-manager for automatic HTTPS.
#
#  What the NGINX Ingress Controller Provides:
#  --------------------------------------------
#  - HTTP/HTTPS routing based on hostname and path
#  - SSL/TLS termination (handles HTTPS for your apps)
#  - Single external IP for multiple services (cost-effective)
#  - Integration with cert-manager for automatic certificates
#  - Advanced features: rate limiting, auth, URL rewriting
#
#  Ingress vs Service Type LoadBalancer:
#  --------------------------------------
#  - LoadBalancer: One external IP per service (expensive in cloud)
#  - Ingress: One external IP, routes to many services based on hostname/path
#
#  Example:
#  - app1.example.com → Service A (on same IP)
#  - app2.example.com → Service B (on same IP)
#  - example.com/api → API Service (on same IP)
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster
#  - Tools: kubectl must be installed and configured
#  - Optional: cert-manager (for automatic HTTPS certificates)
#  - Network: Internet access for downloading manifests
#  - Time: ~5-10 minutes
#
#  Workflow:
#  ---------
#  Run this script on a management node with kubectl access. It will deploy
#  the NGINX Ingress Controller into your cluster.
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
#            STEP 1: INSTALL NGINX INGRESS CONTROLLER
# ============================================================================

print_border "Step 1: Installing NGINX Ingress Controller"

# --- Tutorial: Bare Metal vs Cloud Installation ---
# The NGINX Ingress Controller has different manifests for different environments:
# - Cloud: Uses LoadBalancer service type (cloud provides external IP)
# - Bare metal: Uses NodePort or requires MetalLB for LoadBalancer
#
# For bare metal (Jetson, Raspberry Pi), we use the "bare metal" manifest
# which sets up NodePort access. This means the ingress will be accessible
# on a high port (30000-32767) on every node.
#
# If you want a proper LoadBalancer on bare metal, install MetalLB first:
# https://metallb.universe.tf/
# ---

readonly INGRESS_VERSION="v1.9.4"
readonly INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_VERSION}/deploy/static/provider/baremetal/deploy.yaml"

print_info "Installing NGINX Ingress Controller ${INGRESS_VERSION} (bare metal configuration)..."
print_info "This will create the ingress-nginx namespace and all required components."

sudo -u "$TARGET_USER" kubectl apply -f "$INGRESS_MANIFEST"

if [ $? -ne 0 ]; then
    print_error "Failed to install NGINX Ingress Controller manifests."
    exit 1
fi
print_success "NGINX Ingress Controller manifests applied."

# ============================================================================
#                      STEP 2: WAIT FOR DEPLOYMENT
# ============================================================================

print_border "Step 2: Waiting for NGINX Ingress to be Ready"

print_info "Waiting for ingress controller pods to start (this may take 1-2 minutes)..."

# Wait for the namespace to exist
until sudo -u "$TARGET_USER" kubectl get namespace ingress-nginx &> /dev/null; do
    sleep 2
done

# Wait for the deployment to be ready
if sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/component=controller \
    -n ingress-nginx \
    --timeout=300s; then
    print_success "NGINX Ingress Controller is running."
else
    print_warning "Controller may still be starting. Check with: kubectl get pods -n ingress-nginx"
fi

# ============================================================================
#                      STEP 3: DISPLAY ACCESS INFO
# ============================================================================

print_border "Step 3: Determining Access Method"

# Check the service type
SERVICE_TYPE=$(sudo -u "$TARGET_USER" kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}')

if [ "$SERVICE_TYPE" = "NodePort" ]; then
    # Get the NodePort
    HTTP_PORT=$(sudo -u "$TARGET_USER" kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
    HTTPS_PORT=$(sudo -u "$TARGET_USER" kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    
    print_success "NGINX Ingress Controller is accessible via NodePort."
    echo ""
    echo "HTTP Port:  $HTTP_PORT"
    echo "HTTPS Port: $HTTPS_PORT"
    echo ""
    echo "You can access ingress resources at:"
    echo "  http://<any-node-ip>:$HTTP_PORT"
    echo "  https://<any-node-ip>:$HTTPS_PORT"
    
elif [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    print_success "NGINX Ingress Controller is using LoadBalancer service type."
    echo ""
    echo "External IP will be assigned by your load balancer (MetalLB, cloud provider, etc.)"
    echo "Check status with: kubectl get svc ingress-nginx-controller -n ingress-nginx"
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Installation Complete"
print_success "NGINX Ingress Controller is now running in your cluster!"
echo ""
echo "Components installed:"
echo "  ✓ NGINX Ingress Controller"
echo "  ✓ Admission webhooks"
echo "  ✓ Default backend"
echo ""
print_warning "NEXT STEPS: Create an Ingress resource for your application"
echo ""
echo "Example: Basic HTTP Ingress"
echo "============================================================================"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
YAML
EOF
echo ""
echo "Example: HTTPS Ingress with cert-manager"
echo "============================================================================"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress-tls
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
YAML
EOF
echo ""
echo "============================================================================"
echo "Verification:"
echo "  kubectl get pods -n ingress-nginx"
echo "  kubectl get svc -n ingress-nginx"
echo "  kubectl get ingressclass"
echo ""
echo "View ingress controller logs:"
echo "  kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller"
echo ""
echo "For LoadBalancer on bare metal, install MetalLB:"
echo "  https://metallb.universe.tf/installation/"
echo ""
echo "Learn more: https://kubernetes.github.io/ingress-nginx/"
echo "============================================================================"
