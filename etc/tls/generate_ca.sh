#!/bin/bash

# ============================================================================
#
#              Generate Private Certificate Authority (generate_ca.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Creates a private Certificate Authority (CA) that can sign certificates for
#  internal services. This is a one-time operation that establishes the root of
#  trust for your infrastructure.
#
#  Tutorial Goal:
#  --------------
#  You will learn what a Certificate Authority is and why it's the foundation
#  of TLS security. A CA is an entity that issues digital certificates. In
#  production, companies like Let's Encrypt, DigiCert, and others act as CAs.
#  For private infrastructure, you can be your own CA - this gives you complete
#  control and works in air-gapped environments.
#
#  What This Script Creates:
#  --------------------------
#  1. CA Private Key (ca.key): The secret key that signs certificates
#  2. CA Certificate (ca.crt): The public certificate that clients trust
#
#  How Certificate Trust Works:
#  -----------------------------
#  1. You create a CA (this script)
#  2. You generate service certificates signed by your CA (generate_cert.sh)
#  3. You install the CA certificate on client systems (trust_ca_on_nodes.sh)
#  4. Clients automatically trust any certificate signed by your CA
#
#  Security Note:
#  --------------
#  The CA private key (ca.key) is EXTREMELY SENSITIVE. Anyone with this file
#  can create certificates that your infrastructure will trust. Protect it like
#  a root password. Never commit it to Git, never share it, back it up encrypted.
#
#  Prerequisites:
#  --------------
#  - Tools: openssl must be installed
#  - Time: < 1 minute
#
#  Workflow:
#  ---------
#  Run this script once when setting up your infrastructure. The generated
#  CA certificate is valid for 10 years.
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

if ! command -v openssl &> /dev/null; then
    print_error "openssl is not installed. Installing now..."
    apt-get update && apt-get install -y openssl
fi
print_success "openssl is installed."

# Get script directory
readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# ============================================================================
#                    STEP 1: CHECK FOR EXISTING CA
# ============================================================================

print_border "Step 1: Checking for Existing CA"

if [ -f "ca.key" ] || [ -f "ca.crt" ]; then
    print_warning "CA files already exist in this directory:"
    [ -f "ca.key" ] && echo "  - ca.key (CA private key)"
    [ -f "ca.crt" ] && echo "  - ca.crt (CA certificate)"
    echo ""
    echo "Regenerating the CA will invalidate all certificates signed by the old CA."
    echo "This means you'll need to:"
    echo "  1. Regenerate ALL service certificates"
    echo "  2. Reconfigure ALL services with new certificates"
    echo "  3. Re-trust the new CA on ALL cluster nodes"
    echo ""
    read -p "Are you sure you want to regenerate the CA? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        print_info "CA generation cancelled."
        exit 0
    fi
    
    # Backup existing files
    print_info "Backing up existing CA files..."
    BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
    [ -f "ca.key" ] && mv ca.key "ca.key.backup.$BACKUP_SUFFIX"
    [ -f "ca.crt" ] && mv ca.crt "ca.crt.backup.$BACKUP_SUFFIX"
    print_success "Existing files backed up with suffix: $BACKUP_SUFFIX"
fi

# ============================================================================
#                   STEP 2: COLLECT CA INFORMATION
# ============================================================================

print_border "Step 2: Certificate Authority Information"

# --- Tutorial: Certificate Subject Information ---
# X.509 certificates contain "Subject" information that identifies the entity.
# For a CA, this typically includes:
# - Country (C): Two-letter country code
# - State/Province (ST): Full state or province name
# - Locality (L): City name
# - Organization (O): Company or entity name
# - Organizational Unit (OU): Department or division
# - Common Name (CN): The name of the CA
#
# While this information is mostly informational for a private CA, filling it
# out properly makes certificates more professional and easier to identify.
# ---

print_info "Enter information for your Certificate Authority."
print_info "This information will be embedded in all certificates you issue."
echo ""

read -p "Country Code (2 letters, e.g., US): " CA_COUNTRY
CA_COUNTRY=${CA_COUNTRY:-US}

read -p "State/Province (e.g., California): " CA_STATE
CA_STATE=${CA_STATE:-California}

read -p "City/Locality (e.g., San Francisco): " CA_LOCALITY
CA_LOCALITY=${CA_LOCALITY:-San Francisco}

read -p "Organization (e.g., Homelab): " CA_ORG
CA_ORG=${CA_ORG:-Homelab}

read -p "Organizational Unit (e.g., IT Department): " CA_OU
CA_OU=${CA_OU:-IT Department}

read -p "Common Name (e.g., Homelab Root CA): " CA_CN
CA_CN=${CA_CN:-Homelab Root CA}

echo ""
print_info "CA will be created with the following information:"
echo "  Country:       $CA_COUNTRY"
echo "  State:         $CA_STATE"
echo "  Locality:      $CA_LOCALITY"
echo "  Organization:  $CA_ORG"
echo "  Org Unit:      $CA_OU"
echo "  Common Name:   $CA_CN"
echo ""

# ============================================================================
#                     STEP 3: GENERATE CA PRIVATE KEY
# ============================================================================

print_border "Step 3: Generating CA Private Key"

# --- Tutorial: RSA Private Key Generation ---
# We generate a 4096-bit RSA private key for maximum security. This is larger
# than the typical 2048-bit keys used for service certificates because:
# 1. The CA key is long-lived (10 years)
# 2. Compromise of the CA key compromises everything
# 3. It doesn't need to be used frequently (performance isn't critical)
#
# The -aes256 flag would encrypt the key with a passphrase, but for automation
# purposes, we generate an unencrypted key. Store it securely!
# ---

print_info "Generating 4096-bit RSA private key for CA..."
print_info "This may take 30-60 seconds..."

openssl genrsa -out ca.key 4096

if [ $? -ne 0 ]; then
    print_error "Failed to generate CA private key."
    exit 1
fi

# Set restrictive permissions immediately
chmod 600 ca.key
chown root:root ca.key

print_success "CA private key generated: ca.key"
print_warning "SECURITY: This file must be kept secret and secure!"

# ============================================================================
#                  STEP 4: GENERATE CA CERTIFICATE
# ============================================================================

print_border "Step 4: Generating CA Certificate"

# --- Tutorial: Self-Signed Root Certificate ---
# A CA certificate is "self-signed" - it's signed by its own private key.
# This makes it a "root certificate" or "trust anchor." When clients trust
# this certificate, they automatically trust anything it signs.
#
# Key parameters:
# - x509: Create an X.509 certificate (the standard format)
# - new: Create a new certificate
# - sha256: Use SHA-256 hash algorithm (secure, widely supported)
# - days 3650: Valid for 10 years
# - key ca.key: Use the CA private key we just generated
# - out ca.crt: Output file for the certificate
# - subj: Subject information in Distinguished Name (DN) format
# - extensions: Mark as a CA certificate (can sign other certs)
# ---

print_info "Creating self-signed CA certificate (valid for 10 years)..."

# Create OpenSSL configuration for CA certificate
cat > ca.conf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = $CA_COUNTRY
ST = $CA_STATE
L = $CA_LOCALITY
O = $CA_ORG
OU = $CA_OU
CN = $CA_CN

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF

openssl req -x509 -new -nodes \
    -key ca.key \
    -sha256 \
    -days 3650 \
    -out ca.crt \
    -config ca.conf

if [ $? -ne 0 ]; then
    print_error "Failed to generate CA certificate."
    rm -f ca.conf
    exit 1
fi

rm -f ca.conf

# Set readable permissions (this is public)
chmod 644 ca.crt

print_success "CA certificate generated: ca.crt"

# ============================================================================
#                      STEP 5: VERIFY CERTIFICATE
# ============================================================================

print_border "Step 5: Verifying CA Certificate"

print_info "Certificate details:"
echo ""
openssl x509 -in ca.crt -noout -text | grep -A 2 "Subject:"
openssl x509 -in ca.crt -noout -text | grep -A 2 "Validity"
openssl x509 -in ca.crt -noout -text | grep "CA:TRUE"

print_success "CA certificate is valid and properly configured."

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Certificate Authority Created Successfully"
echo ""
echo "Files created in: $SCRIPT_DIR"
echo ""
echo "  ca.key - CA Private Key (4096-bit RSA)"
echo "           ⚠️  KEEP THIS SECRET AND SECURE!"
echo "           ⚠️  Back it up encrypted offline"
echo "           ⚠️  Never commit to Git or share"
echo ""
echo "  ca.crt - CA Certificate (Public)"
echo "           ✓ Safe to distribute"
echo "           ✓ Install on all systems that need to trust your certificates"
echo "           ✓ Valid for 10 years"
echo ""
print_warning "NEXT STEPS:"
echo ""
echo "1. Secure the CA private key:"
echo "   - Current location: $SCRIPT_DIR/ca.key"
echo "   - Permissions: 600 (root only)"
echo "   - Create encrypted backup:"
echo "     tar czf - ca.key | openssl enc -aes-256-cbc -out ca.key.tar.gz.enc"
echo ""
echo "2. Generate service certificates:"
echo "   cd $SCRIPT_DIR"
echo "   sudo ./generate_cert.sh --service registry --hostname registry.local --ip 192.168.1.50"
echo ""
echo "3. Trust the CA on all cluster nodes:"
echo "   sudo ./trust_ca_on_nodes.sh"
echo ""
echo "============================================================================"
echo "CA Certificate Fingerprint (for verification):"
echo "============================================================================"
openssl x509 -in ca.crt -noout -fingerprint -sha256
echo ""
echo "Keep this fingerprint in a safe place. You can use it to verify that"
echo "you're using the correct CA certificate when distributing it."
echo "============================================================================"
