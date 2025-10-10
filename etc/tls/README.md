# TLS Certificate Management (`etc/tls/`)

This directory contains scripts for creating and managing TLS certificates for **external infrastructure** - services that run outside your Kubernetes cluster but need to be trusted by it.

---

## The Two-Tier Certificate Strategy

This repository uses a two-tier approach to TLS certificates:

### Tier 1: External Services (This Directory - `etc/tls/`)
**For services running on standalone hosts:**
- Docker Registry (on Raspberry Pi, not a k8s node)
- Gitea (can run standalone or in k8s)
- Any other external services that cluster nodes need to trust

**Approach:** Private Certificate Authority (CA)
- You create your own CA (one time)
- Generate certificates for each service signed by your CA
- Distribute the CA certificate to all cluster nodes
- Nodes trust anything signed by your CA

### Tier 2: Cluster Services (`k8s/addons/install_cert_manager.sh`)
**For services running inside Kubernetes:**
- Ingress HTTPS termination
- Service mesh mTLS
- Webhook certificates

**Approach:** cert-manager addon
- Automated certificate lifecycle
- Can use Let's Encrypt (public) or your private CA
- Automatic renewal
- Native Kubernetes integration

---

## Why a Private CA?

For a homelab or edge computing cluster with external infrastructure, a private CA is the best approach:

**Advantages:**
- ✅ Works in air-gapped environments (no internet required)
- ✅ No rate limits (Let's Encrypt has strict limits)
- ✅ Full control over certificate policies
- ✅ Free forever
- ✅ Perfect for internal services

**Trade-offs:**
- ❌ Not trusted by browsers by default (must import CA)
- ❌ Not suitable for public-facing services
- ❌ Manual distribution of CA certificate

**For public services:** Use Let's Encrypt via cert-manager instead.

---

## The Complete Workflow

### Phase 1: One-Time CA Setup
```bash
cd embedded_k8s/etc/tls

# 1. Generate your private CA (do this once)
sudo ./generate_ca.sh
# Creates: ca.crt (public) and ca.key (private)
```

**Result:** You now have a Certificate Authority. Keep `ca.key` secure!

---

### Phase 2: Generate Service Certificates
```bash
# 2. Generate a certificate for your Docker registry
sudo ./generate_cert.sh \
  --service registry \
  --hostname registry.local \
  --ip 192.168.1.50

# Creates: registry.crt and registry.key
```

Repeat for each service (Gitea, internal web apps, etc.).

---

### Phase 3: Distribute CA to Cluster Nodes
```bash
# 3. Install the CA certificate on all k8s nodes
sudo ./trust_ca_on_nodes.sh

# This copies ca.crt to each node's trust store
# Cluster nodes now trust certificates signed by your CA
```

---

### Phase 4: Enable TLS on Services
```bash
# 4. Configure your services to use TLS
sudo ./enable_registry_tls.sh

# Or manually configure Gitea, nginx, etc.
```

---

## Understanding the Scripts

### **generate_ca.sh** - Create Your Certificate Authority

**What it does:**
- Generates a private key for your CA (4096-bit RSA)
- Creates a self-signed root certificate valid for 10 years
- This certificate can sign other certificates

**Output files:**
- `ca.key` - **KEEP THIS SECRET!** Anyone with this can sign certificates
- `ca.crt` - Public certificate, distribute this freely

**When to run:** Once, when setting up your infrastructure

**Storage:** Keep both files in this directory. Back up `ca.key` securely!

---

### **generate_cert.sh** - Create Service Certificates

**What it does:**
- Generates a private key for the service
- Creates a Certificate Signing Request (CSR)
- Signs the CSR with your CA to create a certificate
- Includes Subject Alternative Names (SAN) for IP and DNS

**Usage:**
```bash
sudo ./generate_cert.sh \
  --service <name> \
  --hostname <dns-name> \
  --ip <ip-address>
```

**Example:**
```bash
# Docker registry on 192.168.1.50
sudo ./generate_cert.sh \
  --service registry \
  --hostname registry.local \
  --ip 192.168.1.50

# Gitea on 192.168.1.51
sudo ./generate_cert.sh \
  --service gitea \
  --hostname git.local \
  --ip 192.168.1.51
```

**Output files:**
- `<service>.key` - Private key for the service
- `<service>.crt` - Signed certificate

**When to run:** For each external service that needs TLS

---

### **trust_ca_on_nodes.sh** - Distribute CA to Cluster

**What it does:**
- SSHs into each Kubernetes node
- Copies `ca.crt` to the system trust store
- Updates the trust store
- Restarts containerd (so it picks up the new trust)

**Prerequisites:**
- SSH access to all cluster nodes
- You must have your nodes in a list (script will prompt)
- Or manually specify node IPs

**When to run:** 
- After generating your CA
- When adding new nodes to the cluster

**Alternative:** Manually copy `ca.crt` to each node and run:
```bash
sudo cp ca.crt /usr/local/share/ca-certificates/private-ca.crt
sudo update-ca-certificates
sudo systemctl restart containerd
```

---

### **enable_registry_tls.sh** - Secure the Docker Registry

**What it does:**
- Backs up current registry configuration
- Reconfigures the registry container for HTTPS
- Installs the service certificate and key
- Restarts the registry

**Prerequisites:**
- Docker registry already installed (`etc/install_docker_registry.sh`)
- Certificate generated for the registry

**When to run:** After generating the registry certificate

**Result:** 
- Registry accessible via `https://registry-ip:5000`
- Cluster nodes can pull images securely
- No more "insecure-registries" configuration needed

---

## Example: Securing the Docker Registry

Complete walkthrough from scratch:

```bash
cd embedded_k8s/etc/tls

# 1. Create your CA (one time, ever)
sudo ./generate_ca.sh
# Output: ca.crt, ca.key

# 2. Generate certificate for registry at 192.168.1.50
sudo ./generate_cert.sh \
  --service registry \
  --hostname registry.local \
  --ip 192.168.1.50
# Output: registry.crt, registry.key

# 3. Trust your CA on all cluster nodes
sudo ./trust_ca_on_nodes.sh
# Connects to each node via SSH and installs ca.crt

# 4. Enable TLS on the registry
sudo ./enable_registry_tls.sh
# Configures Docker registry for HTTPS

# 5. Test from any cluster node
docker pull registry.local:5000/test-image
# Should work without "insecure-registries" configuration!
```

---

## Integration with cert-manager

Your private CA can also be used inside Kubernetes:

```bash
# After creating your CA with generate_ca.sh:

# 1. Create a secret in cert-manager namespace
kubectl create secret tls ca-key-pair \
  --cert=ca.crt \
  --key=ca.key \
  -n cert-manager

# 2. Create a ClusterIssuer using your CA
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: private-ca-issuer
spec:
  ca:
    secretName: ca-key-pair
EOF

# 3. Now cert-manager can issue certificates signed by your CA
```

**Result:** Single CA for both external services and in-cluster services!

---

## Security Best Practices

### Protecting the CA Private Key

**The `ca.key` file is extremely sensitive.** Anyone with this file can:
- Sign certificates that your cluster will trust
- Impersonate your services
- Perform man-in-the-middle attacks

**Protection measures:**
1. **Restrict permissions:**
   ```bash
   chmod 600 ca.key
   chown root:root ca.key
   ```

2. **Backup securely:**
   - Store encrypted backups offline
   - Use a password manager or hardware security module
   - Never commit to Git!

3. **Limit access:**
   - Only generate certificates on a secure admin workstation
   - Don't copy `ca.key` to service hosts (only copy service certificates)

### Certificate Rotation

**Service certificates should be rotated periodically:**

```bash
# Generate new certificate for a service
sudo ./generate_cert.sh --service registry --hostname registry.local --ip 192.168.1.50

# Reconfigure the service
sudo ./enable_registry_tls.sh

# No need to update trust on nodes (CA hasn't changed)
```

**Default validity:** 
- CA certificate: 10 years
- Service certificates: 1 year

For production, consider 90-day service certificates with automated rotation.

---

## Troubleshooting

### "Certificate signed by unknown authority"

**Symptom:**
```bash
docker pull registry.local:5000/myimage
# Error: x509: certificate signed by unknown authority
```

**Cause:** The node doesn't trust your CA certificate.

**Fix:**
```bash
# On the node showing the error:
sudo cp ca.crt /usr/local/share/ca-certificates/private-ca.crt
sudo update-ca-certificates
sudo systemctl restart containerd
sudo systemctl restart docker  # if using docker
```

---

### "Certificate is valid for X, not Y"

**Symptom:**
```bash
docker pull 192.168.1.50:5000/myimage
# Error: certificate is valid for registry.local, not 192.168.1.50
```

**Cause:** Accessing the service by IP, but certificate only has DNS name (or vice versa).

**Fix:** Regenerate the certificate with both:
```bash
sudo ./generate_cert.sh \
  --service registry \
  --hostname registry.local \
  --ip 192.168.1.50
```

Or access using the name in the certificate.

---

### Browser Shows "Not Secure"

**Symptom:** Browsing to `https://registry.local:5000` shows security warning.

**Cause:** Your browser doesn't trust your private CA (expected behavior).

**Fix (for development only):**
1. **Firefox:** Import `ca.crt` in Preferences → Privacy & Security → Certificates → View Certificates → Authorities → Import
2. **Chrome:** Import `ca.crt` in Settings → Privacy and security → Security → Manage certificates → Authorities → Import
3. **Safari:** Double-click `ca.crt`, add to Keychain, set to "Always Trust"

**For production public services:** Use Let's Encrypt instead.

---

## When NOT to Use This

**Don't use a private CA for:**
- ❌ Public-facing websites (users will see warnings)
- ❌ Services that need to be trusted by unknown clients
- ❌ Mobile apps distributed to end users
- ❌ Anything requiring broad public trust

**Use Let's Encrypt (via cert-manager) instead for:**
- ✅ Public websites
- ✅ APIs accessed by external clients
- ✅ Services with real DNS names
- ✅ Anything requiring browser trust without warnings

---

## Advanced: Multiple CAs

For complex environments, you might want separate CAs:

```bash
# Production CA
sudo ./generate_ca.sh --name prod-ca

# Development CA  
sudo ./generate_ca.sh --name dev-ca

# Use specific CA when generating certificates
sudo ./generate_cert.sh \
  --ca-cert prod-ca.crt \
  --ca-key prod-ca.key \
  --service registry \
  --hostname prod-registry.local \
  --ip 192.168.1.50
```

This allows different trust levels and easier CA rotation.

---

## Related Documentation

- [Main README](../../README.md) - Repository overview
- [etc/ README](../README.md) - Standalone utilities
- [Docker Registry Setup](../install_docker_registry.sh) - Install registry first
- [Gitea Setup](../install_gitea.sh) - Self-hosted Git server
- [cert-manager](../../k8s/addons/install_cert_manager.sh) - In-cluster certificate automation

### External Resources
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [X.509 Certificate Format](https://en.wikipedia.org/wiki/X.509)
- [Let's Encrypt](https://letsencrypt.org/) - Free public certificates
- [cert-manager Documentation](https://cert-manager.io/docs/)

---

## Contributing

When adding new TLS-related scripts:

1. **Security first**
   - Never log private keys
   - Set restrictive permissions on key files
   - Validate inputs to prevent injection attacks

2. **Clear documentation**
   - Explain the cryptographic operations
   - Document file permissions and ownership
   - Provide troubleshooting for common errors

3. **Idempotent where possible**
   - Safe to re-run scripts
   - Detect existing files and prompt before overwriting
   - Backup before making changes

4. **Test thoroughly**
   - Verify certificates work with real services
   - Test trust chain validation
   - Test on actual ARM64 hardware

Remember: TLS is security-critical infrastructure. Scripts must be rock-solid, well-documented, and easy to audit.
