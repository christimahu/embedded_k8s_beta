#!/bin/bash

# ============================================================================
#
#           Install Local Docker Registry (install_docker_registry.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs and runs a private, local Docker container registry. This allows
#  the cluster to pull images from a local source instead of a public hub,
#  which is faster, avoids rate limits, and is more secure.
#
#  Tutorial Goal:
#  --------------
#  You will learn why a local container registry is a critical piece of
#  infrastructure for a private cluster. We will use the official Docker
#  `registry` image to run our own image hosting service. This script also
#  covers the important concept of configuring remote Docker daemons to
#  trust an "insecure" HTTP registry, a common requirement for local and
#  air-gapped development environments.
#
#  HTTP vs HTTPS:
#  --------------
#  This script installs the registry with HTTP by default for simplicity.
#  For production use, you should enable TLS:
#  1. Generate certificates: etc/tls/generate_cert.sh
#  2. Enable TLS: etc/tls/enable_registry_tls.sh
#
#  Prerequisites:
#  --------------
#  - Completed: Base OS setup on the node that will host the registry.
#  - Hardware: A node with at least 20GB of free disk space recommended.
#  - Network: SSH access and an active internet connection.
#  - Time: ~10 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a single, designated node in your network. This node will
#  become the central image store for your Kubernetes cluster.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
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

# ============================================================================
#                   STEP 1: RUN THE DOCKER REGISTRY CONTAINER
# ============================================================================

print_border "Step 1: Run the Docker Registry Container"

# --- Tutorial: Docker Registry Container ---
# We use the official `registry:2` image, which is lightweight and secure.
# `-d`: Run the container in detached mode (in the background).
# `--restart=always`: Ensures the registry automatically starts on system boot.
# `-p`: Maps port 5000 on the host to port 5000 in the container.
# `-v`: Mounts a host directory into the container for persistent image storage.
# ---
if [ "$(docker ps -q -f name=^/local-registry$)" ]; then
    print_success "Registry container 'local-registry' is already running."
else
    print_info "Starting Docker registry container..."
    
    readonly REGISTRY_NAME="local-registry"
    readonly REGISTRY_PORT="5000"
    readonly REGISTRY_STORAGE_PATH="/var/lib/docker-registry"
    
    print_info "  - Name: $REGISTRY_NAME"
    print_info "  - Port: $REGISTRY_PORT"
    print_info "  - Storage: $REGISTRY_STORAGE_PATH"

    sudo mkdir -p "$REGISTRY_STORAGE_PATH"
    docker run -d \
      --name "$REGISTRY_NAME" \
      --restart=always \
      -p "${REGISTRY_PORT}:${REGISTRY_PORT}" \
      -v "${REGISTRY_STORAGE_PATH}:/var/lib/registry" \
      registry:2

    print_success "Registry container started successfully."
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete"
print_success "Your local Docker registry is running!"

readonly HOST_IP=$(hostname -I | awk '{print $1}')
readonly REGISTRY_ADDRESS="${HOST_IP}:5000"

echo ""
print_warning "SECURITY NOTICE: Registry is running over HTTP (insecure)"
echo ""
echo "Current configuration:"
echo "  Protocol: HTTP (unencrypted)"
echo "  Address:  http://${REGISTRY_ADDRESS}"
echo ""
echo "For production use, enable TLS:"
echo ""
echo "1. Generate CA and certificates:"
echo "   cd embedded_k8s/etc/tls"
echo "   sudo ./generate_ca.sh"
echo "   sudo ./generate_cert.sh --service registry --hostname registry.local --ip ${HOST_IP}"
echo ""
echo "2. Enable TLS on registry:"
echo "   sudo ./enable_registry_tls.sh"
echo ""
echo "3. Trust CA on all cluster nodes:"
echo "   sudo ./trust_ca_on_nodes.sh"
echo ""
echo "============================================================================"
print_warning "ACTION REQUIRED: Configure all Docker clients to trust this registry"
echo ""
echo "Until you enable TLS, you must configure each node's Docker daemon"
echo "to accept insecure connections:"
echo ""
echo "On EACH Kubernetes node (and your local machine), do the following:"
echo ""
echo "1. Edit the Docker daemon configuration file:"
echo "   sudo nano /etc/docker/daemon.json"
echo ""
echo "2. Add the following content. If the file has other content, just add the"
echo "   'insecure-registries' key:"
echo "   {"
echo "     \"insecure-registries\": [\"${REGISTRY_ADDRESS}\"]"
echo "   }"
echo ""
echo "3. Restart the Docker daemon on that node:"
echo "   sudo systemctl restart docker"
echo ""
echo "4. If using containerd (Kubernetes), also restart it:"
echo "   sudo systemctl restart containerd"
echo ""
echo "============================================================================"
echo "Usage Example:"
echo "============================================================================"
echo ""
echo "1. Pull an image:      docker pull alpine"
echo "2. Tag for local repo: docker tag alpine ${REGISTRY_ADDRESS}/my-alpine"
echo "3. Push to local repo: docker push ${REGISTRY_ADDRESS}/my-alpine"
echo "4. Use in Kubernetes:  image: ${REGISTRY_ADDRESS}/my-alpine"
echo ""
echo "Test connection:"
echo "  curl http://${REGISTRY_ADDRESS}/v2/_catalog"
echo ""
echo "View registry logs:"
echo "  docker logs local-registry"
echo ""
echo "Stop registry:"
echo "  docker stop local-registry"
echo ""
echo "Start registry:"
echo "  docker start local-registry"
echo ""
echo "============================================================================"
