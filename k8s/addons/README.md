# Kubernetes Cluster Addons (`k8s/addons/`)

This directory contains scripts for installing essential cluster addons - foundational services that applications depend on. In Kubernetes terminology, an "addon" is any component installed into the cluster after it's bootstrapped.

**Important distinction:** "Addon" doesn't mean "optional." Many addons (like ingress controllers and service meshes) are essential infrastructure for production clusters. This directory contains those **platform-level addons** that fundamentally extend cluster capabilities.

---

## Understanding Addons vs. Tools

**Addons (`k8s/addons/`):**
- Installed **into** the Kubernetes cluster as pods/deployments
- Provide foundational platform capabilities
- Applications depend on them
- Changing them requires careful planning
- Examples: Service mesh, ingress controller, certificate management

**Tools (`k8s/tools/`):**
- May run in-cluster (Prometheus) or as CLI utilities (kubectl-ai)
- Enhance operations and observability
- Applications don't directly depend on them
- Can be added/removed more freely
- Examples: Monitoring, GitOps, developer utilities

**Core Components (installed during cluster bootstrap):**
- kubelet, kube-apiserver, etcd, CNI (Calico)
- Required for cluster to function
- Installed by `k8s/ops/bootstrap_cluster.sh`

---

## Available Addons

### Certificate Management

#### **cert-manager** (`install_cert_manager.sh`)
Automated certificate lifecycle management for cluster services.

**What it does:**
- Automatically provisions TLS certificates
- Integrates with Let's Encrypt for public certificates
- Can use private CA for internal services
- Handles certificate renewal automatically

**Why you need it:**
- HTTPS for Ingress resources
- mTLS for service meshes (Istio/Linkerd)
- Webhook TLS for admission controllers
- Service-to-service encryption

**Installation:**
```bash
cd embedded_k8s/k8s/addons
sudo ./install_cert_manager.sh
```

**When to install:** First, before ingress or service mesh.

---

### HTTP/HTTPS Routing

#### **NGINX Ingress Controller** (`install_ingress_nginx.sh`)
Layer 7 (HTTP/HTTPS) load balancer and router for cluster services.

**What it does:**
- Routes external HTTP/HTTPS traffic to services
- SSL/TLS termination
- Path-based and host-based routing
- Single external IP for multiple services

**Why you need it:**
- Expose web applications to users
- Host multiple apps on one IP address
- Automatic SSL certificate integration with cert-manager
- Standard way to provide external access

**Installation:**
```bash
cd embedded_k8s/k8s/addons
sudo ./install_ingress_nginx.sh
```

**When to install:** After cert-manager, before deploying web applications.

---

### Service Mesh (Choose ONE)

A service mesh provides advanced networking capabilities: mutual TLS, traffic management, observability, and policy enforcement for service-to-service communication.

**CRITICAL: Install ONLY ONE service mesh.** They are mutually exclusive and will conflict.

---

#### **Istio** (`install_istio.sh`) - Option 1

The most feature-rich and widely adopted service mesh.

**What it does:**
- Automatic mutual TLS (mTLS) between all services
- Fine-grained traffic routing (canary deployments, A/B testing)
- Distributed tracing and metrics collection
- Circuit breaking and fault injection
- Network policy enforcement

**Strengths:**
- Most mature and feature-complete
- Excellent observability (Kiali, Jaeger, Grafana)
- Strong enterprise support
- Extensive documentation

**Trade-offs:**
- Higher resource usage (~500Mi memory overhead)
- More complex architecture (control plane + sidecars)
- Steeper learning curve

**Best for:**
- Production environments
- Complex microservices architectures
- Teams needing advanced traffic management
- Enterprise compliance requirements

**Installation:**
```bash
cd embedded_k8s/k8s/addons
sudo ./install_istio.sh
```

---

#### **Linkerd** (`install_linkerd.sh`) - Option 2

The lightweight, simplicity-focused service mesh.

**What it does:**
- Automatic mutual TLS (mTLS) between all services
- Traffic metrics and golden metrics (success rate, latency)
- Load balancing and reliability features
- Simple traffic splitting

**Strengths:**
- Minimal resource overhead (~100Mi memory)
- Simpler architecture and easier to understand
- Fast installation and setup
- Excellent performance
- Strong security focus (Rust-based proxy)

**Trade-offs:**
- Fewer advanced features than Istio
- Less extensive ecosystem integrations
- Smaller community (though very active)

**Best for:**
- Resource-constrained environments (perfect for edge/ARM)
- Teams new to service meshes
- Simpler microservices deployments
- When simplicity and performance are priorities

**Installation:**
```bash
cd embedded_k8s/k8s/addons
sudo ./install_linkerd.sh
```

---

## Service Mesh Comparison

| Feature | Istio | Linkerd |
|---------|-------|---------|
| **Resource usage** | Higher (~500Mi) | Lower (~100Mi) |
| **Complexity** | More complex | Simpler |
| **Features** | Very extensive | Core features |
| **Performance** | Good | Excellent |
| **Learning curve** | Steeper | Gentler |
| **Maturity** | Very mature | Mature |
| **ARM64 support** | Yes | Yes |
| **Best for** | Production/Enterprise | Edge/Learning |

**For this repository's typical use case (edge compute on ARM64):** Linkerd is often the better choice due to lower resource requirements.

---

## Installation Order

**Recommended sequence:**

1. **Bootstrap cluster** (already done via `k8s/ops/bootstrap_cluster.sh`)
2. **Install cert-manager** - Foundation for TLS
   ```bash
   sudo ./install_cert_manager.sh
   ```
3. **Install NGINX Ingress** - HTTP routing
   ```bash
   sudo ./install_ingress_nginx.sh
   ```
4. **Choose service mesh** (optional but recommended)
   ```bash
   # Option A: Istio (feature-rich)
   sudo ./install_istio.sh
   
   # Option B: Linkerd (lightweight)
   sudo ./install_linkerd.sh
   ```

**Result:** A production-ready cluster platform with:
- Automated certificate management
- External HTTP/HTTPS access
- Service-to-service encryption and observability

---

## Verification

After installing addons:

```bash
# Check cert-manager
kubectl get pods -n cert-manager

# Check NGINX Ingress
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Check Istio (if installed)
kubectl get pods -n istio-system

# Check Linkerd (if installed)
linkerd check
```

---

## Integration with External TLS

If you've set up external services (Docker registry, Gitea) with TLS using `etc/tls/`:

**cert-manager can use your private CA:**
```bash
# After generating CA with etc/tls/generate_ca.sh
# Configure cert-manager to use it for cluster certificates
# (Script will prompt for this option)
```

**Ingress can use cert-manager certificates:**
```yaml
# In your Ingress resource:
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
```

---

## When NOT to Install These

**cert-manager:**
- Skip if you'll manually manage all certificates
- Skip if using a different cert solution (Vault)

**NGINX Ingress:**
- Skip if using a different ingress controller (Traefik, HAProxy)
- Skip if using service mesh ingress gateway instead
- Skip for clusters with no external HTTP services

**Service Mesh:**
- Skip for single-service deployments
- Skip if you don't need mTLS or advanced traffic features
- Skip on very resource-constrained clusters (< 4Gi total memory)

---

## Troubleshooting

### cert-manager Pods Pending
```bash
# Check for webhook certificate issues
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Delete and reinstall if needed
kubectl delete namespace cert-manager
sudo ./install_cert_manager.sh
```

### NGINX Ingress No External IP
```bash
# On bare metal, you need MetalLB or similar
kubectl get svc -n ingress-nginx

# Check if using NodePort (alternative to LoadBalancer)
# Access via http://<node-ip>:<nodeport>
```

### Service Mesh Installation Fails
```bash
# Check if other mesh is installed
kubectl get namespaces | grep -E "(istio|linkerd)"

# Must uninstall one before installing the other
# See script output for uninstall commands
```

### Both Service Meshes Installed (Conflict)
```bash
# This will cause issues - uninstall one:

# To remove Istio:
istioctl uninstall --purge -y
kubectl delete namespace istio-system

# To remove Linkerd:
linkerd uninstall | kubectl delete -f -
```

---

## Advanced Topics

### Custom Ingress Configurations

NGINX Ingress supports extensive customization via ConfigMaps:
```bash
kubectl edit configmap ingress-nginx-controller -n ingress-nginx
```

Common tweaks:
- Proxy timeouts
- Request body size limits
- SSL protocols and ciphers

### cert-manager Issuers

The script installs with a basic setup. For production:

**Let's Encrypt (public certificates):**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

**Private CA (internal services):**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: private-ca
spec:
  ca:
    secretName: ca-key-pair
```

### Service Mesh Observability

**Istio includes:**
- Kiali (service mesh dashboard)
- Jaeger (distributed tracing)
- Grafana (metrics visualization)

**Linkerd includes:**
- Linkerd Viz (built-in dashboard)
- Grafana integration
- Tap for real-time traffic inspection

Both integrate with Prometheus (install via `k8s/tools/install_prometheus.sh`).

---

## Related Documentation

- [Main README](../../README.md) - Repository overview
- [Kubernetes Setup](../README.md) - Cluster installation
- [Cluster Tools](../tools/README.md) - Optional enhancements
- [TLS Management](../../etc/tls/README.md) - External service certificates
- [Example Deployments](../deployments/README.md) - Sample applications

### Official Documentation
- [cert-manager](https://cert-manager.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Istio](https://istio.io/latest/docs/)
- [Linkerd](https://linkerd.io/2/overview/)

---

## Contributing

When adding new addon scripts:

1. **Check for conflicts**
   - Verify compatibility with existing addons
   - Document any mutual exclusivity

2. **Follow the pattern**
   - Use the same helper functions
   - Include pre-flight checks
   - Verify installation success

3. **Educational approach**
   - Explain what the addon does
   - Explain why it's needed
   - Compare alternatives

4. **Update this README**
   - Add to the appropriate section
   - Update installation order if needed
   - Add troubleshooting entries

Remember: Addons are foundational. They should be stable, well-tested, and essential to cluster operations.
