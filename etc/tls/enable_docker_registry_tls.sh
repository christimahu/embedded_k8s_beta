#!/bin/bash

# ============================================================================
#
#      Enable TLS on Docker Registry (enable_docker_registry_tls.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Reconfigures an existing Docker registry to use HTTPS/TLS instead of plain
#  HTTP. This enables secure image pulls/pushes without needing "insecure-
#  registries" configuration on Docker clients.
#
#  Tutorial Goal:
#  --------------
#  You will learn how to secure a Docker registry with TLS certificates. A
#  registry running over HTTP is insecure - images and credentials are sent in
#  plain text. With TLS, all communication is encrypted and the registry's
#  identity is verified by your CA certificate.
#
#  What This Script Does:
#  -----------------------
#  1. Stops the existing registry container
#  2. Creates a directory for TLS certificates
#  3. Copies the registry certificate and key
#  4. Reconfigures the registry to listen on HTTPS (port 5000)
#  5. Restarts the registry with TLS enabled
#
#  Before vs After:
#  ----------------
#  Before: http://registry-ip:5000 (insecure, requires special config)
#  After:  https://registry-ip:5000 (secure, works with trusted CA)
#
#  Prerequisites:
#  --------------
#  - Completed: etc/install_docker_registry.sh (registry must be running)
#  - Completed: etc/tls/generate_cert.sh --service docker-registry ...
#  - Files: docker-registry.crt and docker-registry.key must exist in etc/tls/
#  - Time: ~2 minutes
#
#  Workflow:
#  ---------
#  Run this script on the host where the Docker registry is running
#  (typically a Raspberry Pi or standalone server, NOT a k8s node).
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

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed."
    echo "The Docker registry requires Docker to be running."
    exit 1
fi
print_success "Docker is installed."

# Check if registry container exists
if ! docker ps -a --format '{{.Names}}' | grep -q '^docker-registry$'; then
    print_error "Docker registry container 'docker-registry' not found."
    echo ""
    echo "Please install the registry first:"
    echo "  cd embedded_k8s/etc"
    echo "  sudo ./install_docker_registry.sh"
    exit 1
fi
print_success "Docker registry container found."

# Determine where the TLS directory is
# The script could be run from etc/ or etc/tls/
if [ -f "docker-registry.crt" ] && [ -f "docker-registry.key" ]; then
    # Running from etc/tls/
    readonly TLS_DIR="$(pwd)"
elif [ -f "tls/docker-registry.crt" ] && [ -f "tls/docker-registry.key" ]; then
    # Running from etc/
    readonly TLS_DIR="$(pwd)/tls"
else
    print_error "Registry certificate files not found."
    echo ""
    echo "Please generate a certificate for the registry first:"
    echo "  cd embedded_k8s/etc/tls"
    echo "  sudo ./generate_cert.sh --service docker-registry --hostname registry.local --ip <registry-ip>"
    echo ""
    echo "Expected files:"
    echo "  - docker-registry.crt (certificate)"
    echo "  - docker-registry.key (private key)"
    exit 1
fi

print_success "Registry certificates found in: $TLS_DIR"

# ============================================================================
#                   STEP 1: STOP EXISTING REGISTRY
# ============================================================================

print_border "Step 1: Stopping Existing Registry"

print_info "Stopping registry container..."

if docker ps --format '{{.Names}}' | grep -q '^docker-registry$'; then
    docker stop docker-registry
    print_success "Registry stopped."
else
    print_info "Registry was not running."
fi

# ============================================================================
#                 STEP 2: PREPARE TLS CERTIFICATES
# ============================================================================

print_border "Step 2: Preparing TLS Certificates"

# --- Tutorial: Docker Registry Certificate Location ---
# The Docker registry container expects certificates to be mounted at:
# /certs/domain.crt and /certs/domain.key
#
# We'll create a directory on the host and bind-mount it into the container.
# The registry configuration will reference these files.
# ---

readonly CERTS_DIR="/var/lib/docker-registry-certs"

print_info "Creating certificate directory: $CERTS_DIR"
mkdir -p "$CERTS_DIR"
chmod 755 "$CERTS_DIR"

print_info "Copying certificates to $CERTS_DIR..."
cp "$TLS_DIR/docker-registry.crt" "$CERTS_DIR/domain.crt"
cp "$TLS_DIR/docker-registry.key" "$CERTS_DIR/domain.key"

# Set appropriate permissions
chmod 644 "$CERTS_DIR/domain.crt"
chmod 600 "$CERTS_DIR/domain.key"
chown root:root "$CERTS_DIR/domain.crt" "$CERTS_DIR/domain.key"

print_success "Certificates installed in $CERTS_DIR"

# ============================================================================
#            STEP 3: RECONFIGURE REGISTRY WITH TLS
# ============================================================================

print_border "Step 3: Reconfiguring Registry for HTTPS"

# --- Tutorial: Docker Registry TLS Configuration ---
# The registry image automatically enables TLS if it finds:
# - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt
# - REGISTRY_HTTP_TLS_KEY=/certs/domain.key
#
# We set these as environment variables when starting the container.
# The registry will listen on port 5000 with HTTPS enabled.
# ---

print_info "Removing old registry container..."
docker rm docker-registry

print_info "Starting registry with TLS enabled..."

readonly REGISTRY_PORT="5000"
readonly REGISTRY_STORAGE="/var/lib/docker-registry"

docker run -d \
  --name docker-registry \
  --restart=always \
  -p "${REGISTRY_PORT}:${REGISTRY_PORT}" \
  -v "${REGISTRY_STORAGE}:/var/lib/registry" \
  -v "${CERTS_DIR}:/certs" \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  registry:2

if [ $? -ne 0 ]; then
    print_error "Failed to start registry with TLS."
    exit 1
fi

print_success "Registry restarted with HTTPS enabled."

# ============================================================================
#                      STEP 4: VERIFY TLS IS WORKING
# ============================================================================

print_border "Step 4: Verifying TLS Configuration"

print_info "Waiting for registry to start (5 seconds)..."
sleep 5

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q '^docker-registry$'; then
    print_success "Registry container is running."
else
    print_error "Registry container failed to start."
    echo ""
    echo "Check logs with:"
    echo "  docker logs docker-registry"
    exit 1
fi

# Try to connect to registry
print_info "Testing HTTPS connection..."

readonly HOST_IP=$(hostname -I | awk '{print $1}')

if curl -k -s "https://${HOST_IP}:${REGISTRY_PORT}/v2/" > /dev/null 2>&1; then
    print_success "Registry is responding on HTTPS."
else
    print_warning "Could not connect to registry. This may be normal if firewall is blocking."
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "TLS Configuration Complete"
print_success "Docker registry is now secured with HTTPS!"
echo ""
echo "Registry details:"
echo "  Protocol:  HTTPS"
echo "  Port:      $REGISTRY_PORT"
echo "  Address:   https://${HOST_IP}:${REGISTRY_PORT}"
echo ""
echo "Certificate information:"
echo "  Location:  $CERTS_DIR"
echo "  Files:     domain.crt, domain.key"
echo ""
print_warning "IMPORTANT: Configure Docker clients to trust your CA"
echo ""
echo "On cluster nodes, ensure the CA certificate is trusted:"
echo "  cd embedded_k8s/etc/tls"
echo "  sudo ./trust_ca_on_nodes.sh"
echo ""
echo "============================================================================"
echo "Testing the Registry:"
echo "============================================================================"
echo ""
echo "From any cluster node with trusted CA:"
echo ""
echo "1. Test connection:"
echo "   curl https://${HOST_IP}:${REGISTRY_PORT}/v2/_catalog"
echo ""
echo "2. Push an image:"
echo "   docker pull alpine:latest"
echo "   docker tag alpine:latest ${HOST_IP}:${REGISTRY_PORT}/alpine:latest"
echo "   docker push ${HOST_IP}:${REGISTRY_PORT}/alpine:latest"
echo ""
echo "3. Pull the image:"
echo "   docker pull ${HOST_IP}:${REGISTRY_PORT}/alpine:latest"
echo ""
echo "============================================================================"
echo "Using with Kubernetes:"
echo "============================================================================"
echo ""
echo "In your Kubernetes deployments, reference images like:"
echo ""
cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: ${HOST_IP}:${REGISTRY_PORT}/my-app:v1.0
EOF
echo ""
echo "============================================================================"
echo "Troubleshooting:"
echo "============================================================================"
echo ""
echo "If you get 'certificate signed by unknown authority':"
echo "  - Run trust_ca_on_nodes.sh to install CA on all cluster nodes"
echo "  - Verify CA is in: /usr/local/share/ca-certificates/private-ca.crt"
echo "  - Restart containerd: sudo systemctl restart containerd"
echo ""
echo "If you get 'certificate is valid for X, not Y':"
echo "  - Regenerate certificate with correct hostname/IP"
echo "  - Run this script again"
echo ""
echo "View registry logs:"
echo "  docker logs docker-registry"
echo ""
echo "Check certificate details:"
echo "  openssl x509 -in $CERTS_DIR/domain.crt -noout -text"
echo ""
echo "============================================================================"
echo ""
echo "For DNS-based access (recommended):"
echo "  1. Add registry hostname to /etc/hosts on all nodes:"
echo "     echo '${HOST_IP} registry.local' | sudo tee -a /etc/hosts"
echo ""
echo "  2. Use hostname in image names:"
echo "     docker pull registry.local:${REGISTRY_PORT}/my-image"
echo ""
echo "============================================================================"
