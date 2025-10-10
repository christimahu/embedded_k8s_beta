#!/bin/bash

# ============================================================================
#
#              Enable TLS on Gitea (enable_gitea_tls.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Reconfigures an existing Gitea installation to use HTTPS/TLS instead of
#  plain HTTP. This enables secure Git operations and web access without
#  exposing credentials in plain text.
#
#  Tutorial Goal:
#  --------------
#  You will learn how to secure a Gitea server with TLS certificates. A Gitea
#  instance running over HTTP is insecure - credentials and repository data are
#  sent in plain text. With TLS, all communication is encrypted and the server's
#  identity is verified by your CA certificate.
#
#  What This Script Does:
#  -----------------------
#  1. Stops the existing Gitea container
#  2. Creates directories for TLS certificates
#  3. Copies the Gitea certificate and key
#  4. Updates the Gitea configuration file (app.ini)
#  5. Updates Docker Compose to map the HTTPS port
#  6. Restarts Gitea with TLS enabled
#
#  Before vs After:
#  ----------------
#  Before: http://gitea-ip:3000 (insecure)
#  After:  https://gitea-ip:3000 (secure, works with trusted CA)
#
#  Prerequisites:
#  --------------
#  - Completed: etc/install_gitea.sh (Gitea must be running)
#  - Completed: etc/tls/generate_cert.sh --service gitea ...
#  - Files: gitea.crt and gitea.key must exist in etc/tls/
#  - Time: ~2 minutes
#
#  Workflow:
#  ---------
#  Run this script on the host where Gitea is running (typically a standalone
#  server or Raspberry Pi, NOT a k8s node).
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
    echo "Gitea requires Docker to be running."
    exit 1
fi
print_success "Docker is installed."

# Check if Gitea container exists
if ! docker ps -a --format '{{.Names}}' | grep -q '^gitea$'; then
    print_error "Gitea container 'gitea' not found."
    echo ""
    echo "Please install Gitea first:"
    echo "  cd embedded_k8s/etc"
    echo "  sudo ./install_gitea.sh"
    exit 1
fi
print_success "Gitea container found."

# Determine where the TLS directory is
# The script could be run from etc/ or etc/tls/
if [ -f "gitea.crt" ] && [ -f "gitea.key" ]; then
    # Running from etc/tls/
    readonly TLS_DIR="$(pwd)"
elif [ -f "tls/gitea.crt" ] && [ -f "tls/gitea.key" ]; then
    # Running from etc/
    readonly TLS_DIR="$(pwd)/tls"
else
    print_error "Gitea certificate files not found."
    echo ""
    echo "Please generate a certificate for Gitea first:"
    echo "  cd embedded_k8s/etc/tls"
    echo "  sudo ./generate_cert.sh --service gitea --hostname git.local --ip <gitea-ip>"
    echo ""
    echo "Expected files:"
    echo "  - gitea.crt (certificate)"
    echo "  - gitea.key (private key)"
    exit 1
fi

print_success "Gitea certificates found in: $TLS_DIR"

# ============================================================================
#                   STEP 1: STOP EXISTING GITEA
# ============================================================================

print_border "Step 1: Stopping Existing Gitea"

readonly GITEA_BASE_PATH="/opt/gitea"

print_info "Stopping Gitea containers..."
cd "$GITEA_BASE_PATH"

if docker ps --format '{{.Names}}' | grep -q '^gitea$'; then
    docker-compose stop
    print_success "Gitea stopped."
else
    print_info "Gitea was not running."
fi

# ============================================================================
#                 STEP 2: PREPARE TLS CERTIFICATES
# ============================================================================

print_border "Step 2: Preparing TLS Certificates"

# --- Tutorial: Gitea Certificate Location ---
# Gitea expects certificates to be accessible within its data directory.
# We'll create a certs subdirectory and configure Gitea to use these files.
# ---

readonly CERTS_DIR="$GITEA_BASE_PATH/data/certs"

print_info "Creating certificate directory: $CERTS_DIR"
mkdir -p "$CERTS_DIR"
chmod 755 "$CERTS_DIR"

print_info "Copying certificates to $CERTS_DIR..."
cp "$TLS_DIR/gitea.crt" "$CERTS_DIR/cert.pem"
cp "$TLS_DIR/gitea.key" "$CERTS_DIR/key.pem"

# Set appropriate permissions
chmod 644 "$CERTS_DIR/cert.pem"
chmod 600 "$CERTS_DIR/key.pem"
chown -R 1000:1000 "$CERTS_DIR"

print_success "Certificates installed in $CERTS_DIR"

# ============================================================================
#            STEP 3: CONFIGURE GITEA FOR HTTPS
# ============================================================================

print_border "Step 3: Configuring Gitea for HTTPS"

# --- Tutorial: Gitea app.ini Configuration ---
# Gitea stores its configuration in the app.ini file. For TLS, we need to
# configure the [server] section with:
# - PROTOCOL = https
# - CERT_FILE = path to certificate
# - KEY_FILE = path to private key
# - HTTP_PORT = 3000 (Gitea uses the same port for HTTPS)
#
# We'll modify the configuration file to enable HTTPS.
# ---

readonly APP_INI="$GITEA_BASE_PATH/data/gitea/conf/app.ini"

# Create config directory if it doesn't exist
mkdir -p "$GITEA_BASE_PATH/data/gitea/conf"

print_info "Updating Gitea configuration for HTTPS..."

# Check if app.ini exists
if [ -f "$APP_INI" ]; then
    print_info "Backing up existing app.ini..."
    cp "$APP_INI" "${APP_INI}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Update or create the [server] section for HTTPS
# We'll use a simple approach: if [server] exists, update it; otherwise create it
if grep -q "\[server\]" "$APP_INI" 2>/dev/null; then
    print_info "Updating existing [server] section..."
    # Remove old PROTOCOL, CERT_FILE, KEY_FILE lines if they exist
    sed -i '/^PROTOCOL[[:space:]]*=/d' "$APP_INI"
    sed -i '/^CERT_FILE[[:space:]]*=/d' "$APP_INI"
    sed -i '/^KEY_FILE[[:space:]]*=/d' "$APP_INI"
    
    # Add new configuration after [server] line
    sed -i '/^\[server\]/a PROTOCOL = https\nCERT_FILE = /data/certs/cert.pem\nKEY_FILE = /data/certs/key.pem' "$APP_INI"
else
    print_info "Creating new [server] section..."
    cat >> "$APP_INI" <<EOF

[server]
PROTOCOL = https
CERT_FILE = /data/certs/cert.pem
KEY_FILE = /data/certs/key.pem
HTTP_PORT = 3000
EOF
fi

chown 1000:1000 "$APP_INI"
print_success "Gitea configuration updated for HTTPS."

# ============================================================================
#            STEP 4: UPDATE DOCKER COMPOSE (Optional)
# ============================================================================

print_border "Step 4: Verifying Docker Compose Configuration"

# The existing docker-compose.yml should work fine with HTTPS on port 3000
# No changes needed - just informing the user
print_info "Docker Compose configuration is compatible with HTTPS."
print_info "Port 3000 will now serve HTTPS traffic."

# ============================================================================
#                      STEP 5: START GITEA WITH TLS
# ============================================================================

print_border "Step 5: Starting Gitea with TLS Enabled"

print_info "Starting Gitea with HTTPS enabled..."

cd "$GITEA_BASE_PATH"
docker-compose up -d

if [ $? -ne 0 ]; then
    print_error "Failed to start Gitea with TLS."
    echo "Check logs with: docker-compose logs gitea"
    exit 1
fi

print_success "Gitea restarted with HTTPS enabled."

# ============================================================================
#                      STEP 6: VERIFY TLS IS WORKING
# ============================================================================

print_border "Step 6: Verifying TLS Configuration"

print_info "Waiting for Gitea to start (5 seconds)..."
sleep 5

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q '^gitea$'; then
    print_success "Gitea container is running."
else
    print_error "Gitea container failed to start."
    echo ""
    echo "Check logs with:"
    echo "  cd $GITEA_BASE_PATH"
    echo "  docker-compose logs gitea"
    exit 1
fi

# Try to connect to Gitea
print_info "Testing HTTPS connection..."

readonly HOST_IP=$(hostname -I | awk '{print $1}')

if curl -k -s "https://${HOST_IP}:3000/" > /dev/null 2>&1; then
    print_success "Gitea is responding on HTTPS."
else
    print_warning "Could not connect to Gitea. This may be normal if firewall is blocking."
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "TLS Configuration Complete"
print_success "Gitea is now secured with HTTPS!"
echo ""
echo "Gitea details:"
echo "  Protocol:  HTTPS"
echo "  Port:      3000"
echo "  Address:   https://${HOST_IP}:3000"
echo ""
echo "Certificate information:"
echo "  Location:  $CERTS_DIR"
echo "  Files:     cert.pem, key.pem"
echo ""
print_warning "IMPORTANT: Configure Git clients to trust your CA"
echo ""
echo "On cluster nodes and development machines, ensure the CA certificate is trusted:"
echo "  cd embedded_k8s/etc/tls"
echo "  sudo ./trust_ca_on_nodes.sh"
echo ""
echo "For individual machines:"
echo "  sudo cp ca.crt /usr/local/share/ca-certificates/private-ca.crt"
echo "  sudo update-ca-certificates"
echo ""
echo "============================================================================"
echo "Testing Gitea:"
echo "============================================================================"
echo ""
echo "From any machine with trusted CA:"
echo ""
echo "1. Access web interface:"
echo "   https://${HOST_IP}:3000"
echo ""
echo "2. Clone a repository over HTTPS:"
echo "   git clone https://${HOST_IP}:3000/username/repository.git"
echo ""
echo "3. Clone a repository over SSH (still works on port 222):"
echo "   git clone ssh://git@${HOST_IP}:222/username/repository.git"
echo ""
echo "============================================================================"
echo "Troubleshooting:"
echo "============================================================================"
echo ""
echo "If you get 'certificate signed by unknown authority':"
echo "  - Run trust_ca_on_nodes.sh to install CA on all cluster nodes"
echo "  - Verify CA is in: /usr/local/share/ca-certificates/private-ca.crt"
echo "  - Run: sudo update-ca-certificates"
echo ""
echo "If you get 'certificate is valid for X, not Y':"
echo "  - Regenerate certificate with correct hostname/IP"
echo "  - Run this script again"
echo ""
echo "View Gitea logs:"
echo "  cd $GITEA_BASE_PATH"
echo "  docker-compose logs -f gitea"
echo ""
echo "Check certificate details:"
echo "  openssl x509 -in $CERTS_DIR/cert.pem -noout -text"
echo ""
echo "============================================================================"
echo ""
echo "For DNS-based access (recommended):"
echo "  1. Add Gitea hostname to /etc/hosts on all machines:"
echo "     echo '${HOST_IP} git.local' | sudo tee -a /etc/hosts"
echo ""
echo "  2. Access via hostname:"
echo "     https://git.local:3000"
echo "     git clone https://git.local:3000/username/repository.git"
echo ""
echo "============================================================================"
