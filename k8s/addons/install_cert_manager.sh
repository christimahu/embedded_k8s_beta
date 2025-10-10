#!/bin/bash

# ============================================================================
#
#              Install cert-manager (install_cert_manager.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs cert-manager, the Kubernetes certificate management controller.
#  It automates the creation, renewal, and management of TLS certificates
#  for cluster services.
#
#  Tutorial Goal:
#  --------------
#  You will learn why automated certificate management is essential for
#  modern Kubernetes clusters. Manual certificate management is error-prone
#  and doesn't scale. cert-manager integrates with Let's Encrypt for public
#  certificates or can use private CAs for internal services, automatically
#  handling the entire certificate lifecycle including renewal.
#
#  What cert-manager Provides:
#  ----------------------------
#  - Automatic certificate provisioning via Let's Encrypt or private CA
#  - Automatic certificate renewal (no more expired cert outages)
#  - Integration with Ingress for automatic HTTPS
#  - Support for service mesh mTLS (mutual TLS)
#  - Webhook certificates for admission controllers
#
#  Prerequisites:
#  --------------
#  - Completed: A running Kubernetes cluster
#  - Tools: kubectl must be installed and configured
#  - Network: Internet access for downloading cert-manager manifests
#  - Time: ~5-10 minutes
#
#  Workflow:
#  ---------
#  Run this script on a management node with kubectl access. It will deploy
#  cert-manager into your cluster and configure a basic ClusterIssuer.
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
#              STEP 1: INSTALL CERT-MANAGER VIA KUBECTL APPLY
# ============================================================================

print_border "Step 1: Installing cert-manager"

# --- Tutorial: cert-manager Architecture ---
# cert-manager consists of several components:
# 1. cert-manager controller: Core logic for certificate lifecycle
# 2. webhook: Validates and mutates cert-manager resources
# 3. cainjector: Injects CA bundles into webhooks and API services
# 4. Custom Resource Definitions (CRDs): Certificate, Issuer, ClusterIssuer, etc.
#
# These run in the cert-manager namespace and watch for Certificate resources.
# When you create a Certificate, cert-manager automatically provisions it
# from the specified Issuer (Let's Encrypt, private CA, etc.).
# ---

readonly CERT_MANAGER_VERSION="v1.13.2"
readonly CERT_MANAGER_MANIFEST="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

print_info "Installing cert-manager ${CERT_MANAGER_VERSION}..."
print_info "This will create the cert-manager namespace and all required components."

sudo -u "$TARGET_USER" kubectl apply -f "$CERT_MANAGER_MANIFEST"

if [ $? -ne 0 ]; then
    print_error "Failed to install cert-manager manifests."
    exit 1
fi
print_success "cert-manager manifests applied."

# ============================================================================
#                      STEP 2: WAIT FOR DEPLOYMENT
# ============================================================================

print_border "Step 2: Waiting for cert-manager to be Ready"

print_info "Waiting for cert-manager pods to start (this may take 1-2 minutes)..."

# Wait for the cert-manager namespace to exist
until sudo -u "$TARGET_USER" kubectl get namespace cert-manager &> /dev/null; do
    sleep 2
done

# Wait for all deployments to be ready
if sudo -u "$TARGET_USER" kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=300s; then
    print_success "All cert-manager components are running."
else
    print_warning "Some components may still be starting. Check with: kubectl get pods -n cert-manager"
fi

# ============================================================================
#                    STEP 3: CREATE BASIC CLUSTERISSUER
# ============================================================================

print_border "Step 3: Creating a Basic ClusterIssuer"

# --- Tutorial: Issuers vs ClusterIssuers ---
# An "Issuer" is namespaced - it can only issue certificates in its namespace.
# A "ClusterIssuer" is cluster-wide - it can issue certificates in any namespace.
#
# For most use cases, ClusterIssuer is more convenient. We'll create a
# self-signed ClusterIssuer as a starting point. For production, you would
# configure Let's Encrypt or a private CA.
# ---

print_info "Creating a self-signed ClusterIssuer for testing..."

cat <<EOF | sudo -u "$TARGET_USER" kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

if [ $? -eq 0 ]; then
    print_success "Self-signed ClusterIssuer created."
else
    print_warning "Failed to create ClusterIssuer. You can create it manually later."
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Installation Complete"
print_success "cert-manager is now running in your cluster!"
echo ""
echo "Components installed:"
echo "  ✓ cert-manager controller"
echo "  ✓ cert-manager webhook"
echo "  ✓ cert-manager cainjector"
echo "  ✓ Self-signed ClusterIssuer (for testing)"
echo ""
print_warning "NEXT STEPS: Configure a production certificate issuer"
echo ""
echo "Option 1: Let's Encrypt (for public certificates)"
echo "-----------------------------------------------------"
echo "Create a ClusterIssuer for Let's Encrypt:"
echo ""
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Change this!
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
YAML
EOF
echo ""
echo "Option 2: Private CA (for internal services)"
echo "-----------------------------------------------------"
echo "If you've created a private CA using etc/tls/generate_ca.sh:"
echo ""
echo "1. Create a secret with your CA certificate and key:"
echo "   kubectl create secret tls ca-key-pair \\"
echo "     --cert=/path/to/ca.crt \\"
echo "     --key=/path/to/ca.key \\"
echo "     -n cert-manager"
echo ""
echo "2. Create a ClusterIssuer using your CA:"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: private-ca-issuer
spec:
  ca:
    secretName: ca-key-pair
YAML
EOF
echo ""
echo "============================================================================"
echo "Verification:"
echo "  kubectl get pods -n cert-manager"
echo "  kubectl get clusterissuers"
echo ""
echo "Test certificate creation:"
cat <<'EOF'
cat <<YAML | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-certificate
  namespace: default
spec:
  secretName: test-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  commonName: test.example.com
  dnsNames:
    - test.example.com
YAML
EOF
echo ""
echo "Check certificate status:"
echo "  kubectl get certificate -n default"
echo "  kubectl describe certificate test-certificate -n default"
echo ""
echo "Learn more: https://cert-manager.io/docs/"
echo "============================================================================"
