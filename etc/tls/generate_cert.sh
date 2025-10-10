#!/bin/bash

# ============================================================================
#
#           Generate Service Certificate (generate_cert.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Generates TLS certificates for services (Docker registry, Gitea, etc.)
#  signed by your private Certificate Authority. These certificates enable
#  HTTPS/TLS for your infrastructure services.
#
#  Tutorial Goal:
#  --------------
#  You will learn how TLS certificates are created and why Subject Alternative
#  Names (SANs) are important. Modern TLS requires certificates to explicitly
#  list all hostnames and IP addresses they're valid for. This script handles
#  that complexity, generating production-ready certificates that work with
#  both DNS names and IP addresses.
#
#  How Certificate Signing Works:
#  -------------------------------
#  1. Generate a private key for the service
#  2. Create a Certificate Signing Request (CSR) with service details
#  3. Sign the CSR with your CA's private key
#  4. Result: A certificate trusted by anyone who trusts your CA
#
#  Subject Alternative Names (SAN):
#  --------------------------------
#  Modern browsers and tools require SANs - you must explicitly list every
#  hostname and IP address the certificate should be valid for:
#  - DNS name: registry.local
#  - IP address: 192.168.1.50
#  - Both in the same certificate
#
#  Without SANs, you'll get "certificate is valid for X, not Y" errors.
#
#  Prerequisites:
#  --------------
#  - Completed: generate_ca.sh (must have ca.key and ca.crt)
#  - Tools: openssl must be installed
#  - Time: < 1 minute per certificate
#
#  Workflow:
#  ---------
#  Run this script for each service that needs a TLS certificate.
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

usage() {
    cat <<EOF
Usage: sudo ./generate_cert.sh --service <name> --hostname <dns> --ip <address>

Required arguments:
  --service <name>     Service name (e.g., registry, gitea)
  --hostname <dns>     DNS hostname (e.g., registry.local)
  --ip <address>       IP address (e.g., 192.168.1.50)

Optional arguments:
  --ca-cert <file>     CA certificate file (default: ca.crt)
  --ca-key <file>      CA private key file (default: ca.key)
  --days <number>      Certificate validity in days (default: 365)

Examples:
  # Docker registry
  sudo ./generate_cert.sh --service registry --hostname registry.local --ip 192.168.1.50

  # Gitea server
  sudo ./generate_cert.sh --service gitea --hostname git.local --ip 192.168.1.51

  # With custom CA and longer validity
  sudo ./generate_cert.sh --service myapp --hostname app.local --ip 192.168.1.100 \\
    --ca-cert prod-ca.crt --ca-key prod-ca.key --days 730

EOF
    exit 1
}

# ============================================================================
#                         PARSE ARGUMENTS
# ============================================================================

SERVICE_NAME=""
HOSTNAME=""
IP_ADDRESS=""
CA_CERT="ca.crt"
CA_KEY="ca.key"
CERT_DAYS=365

while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --ip)
            IP_ADDRESS="$2"
            shift 2
            ;;
        --ca-cert)
            CA_CERT="$2"
            shift 2
            ;;
        --ca-key)
            CA_KEY="$2"
            shift 2
            ;;
        --days)
            CERT_DAYS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown argument: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" ]] || [[ -z "$HOSTNAME" ]] || [[ -z "$IP_ADDRESS" ]]; then
    print_error "Missing required arguments."
    echo ""
    usage
fi

# ============================================================================
#                         STEP 0: PRE-FLIGHT CHECKS
# ============================================================================

print_border "Step 0: Pre-flight Checks"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with root privileges. Please use 'sudo'."
    exit 1
fi
print_success "Running as root."

if ! command -v openssl &> /dev/null; then
    print_error "openssl is not installed."
    exit 1
fi
print_success "openssl is installed."

# Get script directory
readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check for CA files
if [ ! -f "$CA_CERT" ]; then
    print_error "CA certificate not found: $CA_CERT"
    echo "Run ./generate_ca.sh first to create your Certificate Authority."
    exit 1
fi

if [ ! -f "$CA_KEY" ]; then
    print_error "CA private key not found: $CA_KEY"
    echo "Run ./generate_ca.sh first to create your Certificate Authority."
    exit 1
fi

print_success "CA files found: $CA_CERT, $CA_KEY"

# Validate IP address format (basic check)
if ! [[ "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    print_error "Invalid IP address format: $IP_ADDRESS"
    exit 1
fi
print_success "Valid IP address: $IP_ADDRESS"

# ============================================================================
#                  STEP 1: CHECK FOR EXISTING CERTIFICATE
# ============================================================================

print_border "Step 1: Checking for Existing Certificate"

readonly CERT_KEY="${SERVICE_NAME}.key"
readonly CERT_FILE="${SERVICE_NAME}.crt"
readonly CSR_FILE="${SERVICE_NAME}.csr"

if [ -f "$CERT_KEY" ] || [ -f "$CERT_FILE" ]; then
    print_warning "Certificate files already exist for service: $SERVICE_NAME"
    [ -f "$CERT_KEY" ] && echo "  - $CERT_KEY (private key)"
    [ -f "$CERT_FILE" ] && echo "  - $CERT_FILE (certificate)"
    echo ""
    read -p "Overwrite existing certificate? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        print_info "Certificate generation cancelled."
        exit 0
    fi
    
    # Backup existing files
    BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
    [ -f "$CERT_KEY" ] && mv "$CERT_KEY" "${CERT_KEY}.backup.$BACKUP_SUFFIX"
    [ -f "$CERT_FILE" ] && mv "$CERT_FILE" "${CERT_FILE}.backup.$BACKUP_SUFFIX"
    print_info "Existing files backed up with suffix: $BACKUP_SUFFIX"
fi

# ============================================================================
#                   STEP 2: GENERATE SERVICE PRIVATE KEY
# ============================================================================

print_border "Step 2: Generating Service Private Key"

# --- Tutorial: Service Key Size ---
# We use 2048-bit RSA for service certificates. This is:
# - Sufficient security for certificates with 1-year validity
# - Faster for TLS handshakes (matters for high-traffic services)
# - Universally supported
#
# The CA uses 4096-bit because it's long-lived (10 years), but service
# certificates are renewed annually and don't need the extra size.
# ---

print_info "Generating 2048-bit RSA private key for $SERVICE_NAME..."

openssl genrsa -out "$CERT_KEY" 2048

if [ $? -ne 0 ]; then
    print_error "Failed to generate private key."
    exit 1
fi

chmod 600 "$CERT_KEY"
chown root:root "$CERT_KEY"

print_success "Private key generated: $CERT_KEY"

# ============================================================================
#         STEP 3: CREATE CERTIFICATE SIGNING REQUEST (CSR)
# ============================================================================

print_border "Step 3: Creating Certificate Signing Request"

# --- Tutorial: Certificate Signing Request (CSR) ---
# A CSR is a request for a certificate. It contains:
# 1. The service's public key (derived from the private key)
# 2. Information about the service (CN, organization, etc.)
# 3. Subject Alternative Names (SANs) - hostnames and IPs
#
# The CA signs the CSR to create the final certificate.
# ---

print_info "Creating CSR with Subject Alternative Names..."

# Create OpenSSL configuration for the CSR
cat > "${SERVICE_NAME}.conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = US
ST = California
L = San Francisco
O = Homelab
OU = Services
CN = $HOSTNAME

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $HOSTNAME
IP.1 = $IP_ADDRESS
EOF

# Generate the CSR
openssl req -new \
    -key "$CERT_KEY" \
    -out "$CSR_FILE" \
    -config "${SERVICE_NAME}.conf"

if [ $? -ne 0 ]; then
    print_error "Failed to create CSR."
    rm -f "${SERVICE_NAME}.conf"
    exit 1
fi

print_success "CSR created: $CSR_FILE"

# ============================================================================
#                   STEP 4: SIGN CERTIFICATE WITH CA
# ============================================================================

print_border "Step 4: Signing Certificate with CA"

# --- Tutorial: Certificate Signing ---
# This is the key operation: we use the CA's private key to sign the CSR,
# creating a certificate. The signature proves that the CA vouches for this
# certificate. Anyone who trusts the CA will automatically trust this cert.
#
# Extensions we add:
# - extendedKeyUsage: Specifies this is for TLS servers
# - subjectAltName: Carries over the SANs from the CSR
# ---

print_info "Signing certificate with CA (valid for $CERT_DAYS days)..."

# Create extensions file for signing
cat > "${SERVICE_NAME}_ext.conf" <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $HOSTNAME
IP.1 = $IP_ADDRESS
EOF

# Sign the CSR with the CA
openssl x509 -req \
    -in "$CSR_FILE" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$CERT_FILE" \
    -days "$CERT_DAYS" \
    -sha256 \
    -extfile "${SERVICE_NAME}_ext.conf"

if [ $? -ne 0 ]; then
    print_error "Failed to sign certificate."
    rm -f "${SERVICE_NAME}.conf" "${SERVICE_NAME}_ext.conf"
    exit 1
fi

chmod 644 "$CERT_FILE"

print_success "Certificate signed: $CERT_FILE"

# Cleanup temporary files
rm -f "$CSR_FILE" "${SERVICE_NAME}.conf" "${SERVICE_NAME}_ext.conf" ca.srl

# ============================================================================
#                      STEP 5: VERIFY CERTIFICATE
# ============================================================================

print_border "Step 5: Verifying Certificate"

print_info "Certificate details:"
echo ""

# Display subject and issuer
openssl x509 -in "$CERT_FILE" -noout -subject -issuer

# Display validity period
echo ""
print_info "Validity:"
openssl x509 -in "$CERT_FILE" -noout -dates

# Display Subject Alternative Names
echo ""
print_info "Subject Alternative Names:"
openssl x509 -in "$CERT_FILE" -noout -text | grep -A 2 "Subject Alternative Name"

# Verify the certificate chain
echo ""
print_info "Verifying certificate chain..."
if openssl verify -CAfile "$CA_CERT" "$CERT_FILE" > /dev/null 2>&1; then
    print_success "Certificate chain is valid!"
else
    print_error "Certificate verification failed!"
    exit 1
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Certificate Generated Successfully"
echo ""
echo "Files created in: $SCRIPT_DIR"
echo ""
echo "  ${CERT_KEY} - Service Private Key (2048-bit RSA)"
echo "               ⚠️  Keep this secure on the service host"
echo "               ⚠️  Only the service needs this file"
echo ""
echo "  ${CERT_FILE} - Service Certificate"
echo "               ✓ Signed by your CA"
echo "               ✓ Valid for $CERT_DAYS days"
echo "               ✓ Includes both DNS name and IP address"
echo ""
print_warning "NEXT STEPS:"
echo ""
echo "1. Copy certificate and key to the service host:"
echo "   scp ${CERT_KEY} ${CERT_FILE} user@${IP_ADDRESS}:/path/to/certs/"
echo ""
echo "2. Configure your service to use TLS:"
echo ""
if [[ "$SERVICE_NAME" == "registry" ]]; then
    echo "   For Docker Registry:"
    echo "   sudo ./enable_registry_tls.sh"
    echo ""
elif [[ "$SERVICE_NAME" == "gitea" ]]; then
    echo "   For Gitea, edit /opt/gitea/app.ini:"
    echo "   [server]"
    echo "   PROTOCOL = https"
    echo "   CERT_FILE = /path/to/${CERT_FILE}"
    echo "   KEY_FILE = /path/to/${CERT_KEY}"
    echo ""
else
    echo "   Configure your service to use:"
    echo "   Certificate: /path/to/${CERT_FILE}"
    echo "   Private Key: /path/to/${CERT_KEY}"
    echo ""
fi

echo "3. Ensure cluster nodes trust your CA:"
echo "   sudo ./trust_ca_on_nodes.sh"
echo ""
echo "============================================================================"
echo "Testing the Certificate:"
echo "============================================================================"
echo ""
echo "After configuring the service, test from a cluster node:"
echo ""
echo "  # Test HTTPS connection"
echo "  curl https://${HOSTNAME}"
echo ""
echo "  # Or by IP"
echo "  curl https://${IP_ADDRESS}"
echo ""
echo "If you get 'certificate signed by unknown authority', you need to run:"
echo "  sudo ./trust_ca_on_nodes.sh"
echo ""
echo "============================================================================"
