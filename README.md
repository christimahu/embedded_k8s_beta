# embedded_k8s

**A production-grade Kubernetes platform for GPU computing, MLOps, and distributed AI workloads - designed to scale from edge hardware to enterprise infrastructure.**

This repository provides a complete, battle-tested foundation for deploying Kubernetes on ARM64 and GPU-accelerated hardware. Built with NVIDIA Jetson, Raspberry Pi, and GPU clusters in mind, it delivers an educational journey that results in a production-ready platform.

---

## Why This Repository Exists

Modern AI/ML infrastructure demands Kubernetes expertise, but learning on cloud platforms is expensive and abstracts away critical knowledge. Building on physical hardware teaches you how things actually work while creating a platform capable of real production workloads.

### The GPU/MLOps Problem

Training and fine-tuning large language models requires:
- **Distributed PyTorch** across multiple GPUs
- **Kubernetes orchestration** for job scheduling and resource management
- **Production-grade infrastructure** (service mesh, monitoring, GitOps)
- **Confidence that your PoC will scale** to enterprise GPU clusters

This repository solves that problem. Develop and test your ML pipelines on accessible hardware (Jetson Orin, consumer NVIDIA GPUs), then deploy to professional NVIDIA A100/H100 clusters with **zero architectural changes**.

### The Philosophy

**Educational transparency meets production architecture.** Every script explains the "why" behind each decision, teaching you Kubernetes and cloud-native patterns while building infrastructure you can actually use.

- ✅ **Production patterns** - Service mesh, GitOps, chaos engineering, observability
- ✅ **Vendor-agnostic** - Standard Kubernetes, not a proprietary distribution
- ✅ **GPU-native** - Designed for NVIDIA CUDA workloads from day one
- ✅ **Financially accessible** - Learn on Jetson/Pi, deploy on A100s
- ✅ **Fully documented** - Tutorial-style comments throughout

---

## Use Cases

### 1. MLOps and Distributed AI Training

**Development workflow:**
```
Jetson Orin Cluster (8GB RAM, 1024 CUDA cores) → Develop distributed PyTorch training
    ↓
Test fine-tuning small LLMs (Llama 2 7B, Mistral 7B)
    ↓
Deploy identical architecture on A100 cluster → Fine-tune Llama 70B, GPT-J, Falcon 40B
```

The Kubernetes manifests, Helm charts, and infrastructure configurations are **identical**. Only the GPU resources change.

### 2. Edge AI and Computer Vision

Deploy production computer vision pipelines:
- Real-time video analytics on Jetson
- Knative serverless for inference (scale-to-zero when idle)
- Distributed model serving across edge nodes
- Central training, edge inference architecture

### 3. GPU Cluster Management

Learn to manage GPU resources professionally:
- NVIDIA GPU Operator integration
- Multi-Instance GPU (MIG) partitioning
- GPU scheduling and resource quotas
- Monitoring GPU utilization with Prometheus

### 4. Production Kubernetes Skills

Everything you learn here transfers directly to:
- AWS EKS, Google GKE, Azure AKS
- On-premises enterprise Kubernetes
- Kubernetes certification exams (CKA, CKAD, CKS)
- Real-world MLOps and DevOps roles

---

## Architecture Overview

### Hardware-Agnostic Design

The repository separates hardware-specific setup from cluster configuration:

```
Hardware Preparation (NVIDIA Jetson Orin, Raspberry Pi, x86 GPU servers)
    ↓
Common Kubernetes Installation (works on any prepared node)
    ↓
Role Assignment (control plane, GPU worker, CPU worker)
    ↓
Addon Installation (service mesh, monitoring, serverless, MLOps tools)
```

A Jetson node, a Raspberry Pi, and a server with NVIDIA A100 GPUs can all join the **same cluster** with complementary roles.

### Components

#### Platform Setup (`JETSON_ORIN/`, `RASPBERRY_PI/`)
Hardware-specific scripts to prepare nodes for Kubernetes:
- Headless configuration and system hardening
- Boot optimization (NVMe SSD migration on Jetson)
- GPU driver and CUDA setup
- OS updates and verification

#### Kubernetes Core (`k8s/node_setup/`, `k8s/ops/`)
Standard Kubernetes installation using upstream kubeadm:
- Container runtime (containerd) with systemd cgroup driver
- Kubernetes packages (kubelet, kubeadm, kubectl)
- Calico CNI for pod networking
- Cluster bootstrapping and node joining

#### Infrastructure Addons (`k8s/addons/`)
Production-grade platform services:
- **cert-manager** - Automated TLS certificate management
- **NGINX Ingress** - HTTP/HTTPS routing and load balancing
- **Istio** or **Linkerd** - Service mesh for mTLS, observability, traffic management
- **Knative** - Serverless platform (scale-to-zero for cost efficiency)

#### Operational Tools (`k8s/tools/`)
Day-2 operations and workflows:
- **Prometheus + Grafana** - Metrics, dashboards, GPU monitoring
- **Argo CD** - GitOps continuous delivery
- **Chaos Mesh** - Chaos engineering and resilience testing
- **kubectl-ai** - AI-assisted cluster operations
- **k8sgpt** - AI-powered diagnostics and troubleshooting

#### External Services (`etc/`)
Supporting infrastructure (typically on standalone hosts):
- **Docker Registry** - Private container image storage
- **Gitea** - Self-hosted Git server for GitOps workflows
- **TLS Certificate Authority** - Internal PKI for service encryption

#### Example Deployments (`k8s/deployments/`)
Reference manifests demonstrating best practices:
- StatefulSets for distributed training jobs
- PersistentVolumes for model storage
- Resource quotas and limits for GPU sharing
- Ingress configurations for model serving endpoints

---

## Quick Start: Jetson Orin GPU Cluster

This walkthrough creates a 3-node cluster suitable for distributed PyTorch experimentation.

### Prerequisites

**Hardware:**
- 3× NVIDIA Jetson Orin Nano Developer Kits (8GB)
- 3× NVMe SSD drives (256GB+ recommended)
- 3× MicroSD cards (64GB+, for boot firmware)
- Network switch and Ethernet cables
- 1× Monitor, keyboard (for initial setup only)

**Software:**
- NVIDIA JetPack 5.1.2+ flashed to microSD cards
- This repository cloned to each device

### Step 1: Hardware Preparation (Per Node)

With monitor and keyboard attached:

```bash
# Complete Ubuntu initial setup GUI
# Clone this repository
git clone https://github.com/yourusername/embedded_k8s.git
cd embedded_k8s/jetson_orin/setup

# Configure for headless operation
sudo ./01_config_headless.sh
sudo shutdown now

# Disconnect monitor/keyboard, power on, SSH in:
ssh user@<node-ip>
cd embedded_k8s/jetson_orin/setup

# Migrate OS to NVMe SSD for performance
sudo ./02_clone_os_to_ssd.sh
sudo ./03_set_boot_to_ssd.sh
sudo reboot

# After reboot, SSH back in:
sudo ./04_strip_microsd_rootfs.sh  # Security hardening
sudo ./05_update_os.sh             # System updates
sudo ./06_verify_setup.sh          # Validation
```

**Result:** Clean, headless, SSD-booted node ready for Kubernetes.

### Step 2: Install Kubernetes (All Nodes)

```bash
cd embedded_k8s/k8s/node_setup
sudo ./01_install_deps.sh    # Container runtime, networking
sudo ./02_install_kube.sh    # Kubernetes packages
```

### Step 3: Bootstrap the Cluster (First Node Only)

```bash
cd embedded_k8s/k8s/ops
sudo ./bootstrap_cluster.sh
```

**Output:** Join commands for worker nodes and additional control planes.

### Step 4: Join Worker Nodes (Remaining Nodes)

On nodes 2 and 3:

```bash
cd embedded_k8s/k8s/ops
sudo ./join_node.sh
# Paste the join command from Step 3
```

### Step 5: Install Platform Addons (From Any Control Plane)

```bash
cd embedded_k8s/k8s/addons

# Core infrastructure
sudo ./install_cert_manager.sh      # Certificate automation
sudo ./install_ingress_nginx.sh     # HTTP routing
sudo ./install_linkerd.sh           # Service mesh (lightweight for ARM)
sudo ./install_knative.sh           # Serverless platform

# Operational tools
cd ../tools
sudo ./install_prometheus.sh        # Monitoring and GPU metrics
sudo ./install_argocd.sh           # GitOps deployment
```

### Step 6: Deploy a Distributed Training Job

Example: Distributed PyTorch on 3 Jetson GPUs

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pytorch-distributed
spec:
  clusterIP: None  # Headless service for peer discovery
  selector:
    app: pytorch-training
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pytorch-training
spec:
  serviceName: pytorch-distributed
  replicas: 3  # One per GPU node
  selector:
    matchLabels:
      app: pytorch-training
  template:
    metadata:
      labels:
        app: pytorch-training
    spec:
      containers:
      - name: pytorch
        image: nvcr.io/nvidia/pytorch:24.01-py3
        command: 
          - python
          - -m
          - torch.distributed.run
          - --nproc_per_node=1
          - --nnodes=3
          - --node_rank=$(RANK)
          - --master_addr=pytorch-training-0.pytorch-distributed
          - --master_port=29500
          - train.py
        env:
        - name: RANK
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['apps.kubernetes.io/pod-index']
        resources:
          limits:
            nvidia.com/gpu: 1  # Request GPU
```

**Result:** Distributed training across 3 Jetson GPUs using PyTorch DDP.

---

## Scaling to Production GPU Infrastructure

The exact same Kubernetes manifests work on professional GPU clusters:

### Small-Scale Development
- **3× Jetson Orin Nano** (8GB, 1024 CUDA cores each)
- **Budget:** ~$1,500
- **Workloads:** Small LLM fine-tuning, CV model development, learning

### Mid-Scale Production
- **3× Servers with NVIDIA RTX 4090** (24GB, 16,384 CUDA cores each)
- **Budget:** ~$15,000
- **Workloads:** Medium LLM fine-tuning, production inference, batch processing

### Enterprise Scale
- **8× Servers with NVIDIA A100 80GB** (80GB, 6,912 tensor cores each)
- **Budget:** ~$200,000+
- **Workloads:** Large LLM training, massive distributed jobs, multi-tenant ML platform

**The Kubernetes YAML files don't change.** Only the resource requests scale:

```yaml
# Development (Jetson)
resources:
  limits:
    nvidia.com/gpu: 1      # 8GB VRAM
    memory: 4Gi

# Production (A100)
resources:
  limits:
    nvidia.com/gpu: 1      # 80GB VRAM
    memory: 64Gi
```

---

## Why Full Kubernetes (Not K3s)?

This repository uses **upstream Kubernetes** (kubeadm) rather than lightweight distributions like K3s:

### Educational Transparency
Every component is installed and configured explicitly. You learn:
- How container runtimes integrate with Kubernetes
- Why CNI plugins are necessary and how they work
- Control plane architecture and component responsibilities
- How to make production-ready architectural decisions

K3s abstracts these details away. Great for production simplicity, poor for learning.

### Industry Standard
- Cloud providers (EKS, GKE, AKS) run standard Kubernetes
- Kubernetes certifications test standard Kubernetes knowledge
- Enterprise GPU clusters use standard Kubernetes + NVIDIA GPU Operator
- Your skills transfer directly to any Kubernetes environment

### Production Flexibility
- Choose your own components (CNI, service mesh, ingress, storage)
- Full compatibility with all Helm charts and operators
- NVIDIA GPU Operator officially supports standard Kubernetes
- Easy migration path from edge to cloud

### MLOps Ecosystem Compatibility
Tools like Kubeflow, Ray, MLflow, and Seldon Core are designed for standard Kubernetes. While they often work with K3s, documentation and community support assume upstream k8s.

**Learn standard Kubernetes here. If you later decide K3s fits a use case, the transition is trivial. The reverse is painful.**

---

## Repository Structure

```
embedded_k8s/
├── README.md                          # This file
├── jetson_orin/                       # NVIDIA Jetson Orin setup
│   ├── setup/                         # Sequential OS preparation scripts
│   │   ├── 01_config_headless.sh      # Headless configuration
│   │   ├── 02_clone_os_to_ssd.sh      # SSD migration
│   │   ├── 03_set_boot_to_ssd.sh      # Boot configuration
│   │   ├── 04_strip_microsd_rootfs.sh # Security hardening
│   │   ├── 05_update_os.sh            # System updates
│   │   └── 06_verify_setup.sh         # Validation
│   ├── tools/                         # NVRAM and recovery utilities
│   └── README.md                      # Detailed Jetson guide
├── raspberry_pi/                      # Raspberry Pi setup (future)
│   └── README.md
├── k8s/                               # Kubernetes installation and configuration
│   ├── node_setup/                    # Prerequisites for all nodes
│   │   ├── 01_install_deps.sh         # Container runtime, kernel modules
│   │   └── 02_install_kube.sh         # Kubernetes packages
│   ├── ops/                           # Cluster operations
│   │   ├── bootstrap_cluster.sh       # Initialize first control plane
│   │   └── join_node.sh               # Add nodes to cluster
│   ├── addons/                        # Platform-level services
│   │   ├── install_cert_manager.sh    # TLS automation
│   │   ├── install_ingress_nginx.sh   # HTTP routing
│   │   ├── install_istio.sh           # Service mesh (advanced)
│   │   ├── install_linkerd.sh         # Service mesh (lightweight)
│   │   ├── install_knative.sh         # Serverless platform
│   │   └── README.md
│   ├── tools/                         # Operational tooling
│   │   ├── install_prometheus.sh      # Monitoring stack
│   │   ├── install_argocd.sh          # GitOps
│   │   ├── install_chaos_mesh.sh      # Chaos engineering
│   │   ├── install_kubectl_ai.sh      # AI-assisted operations
│   │   ├── install_k8sgpt.sh          # AI diagnostics
│   │   ├── install_nfs_server.sh      # Shared storage
│   │   └── README.md
│   ├── deployments/                   # Example Kubernetes manifests
│   │   ├── deployment.yaml            # Standard deployment
│   │   ├── statefulset.yaml           # Stateful workloads (databases, training jobs)
│   │   ├── ingress.yaml               # HTTP routing rules
│   │   ├── persistent_volume.yaml     # Storage configurations
│   │   └── README.md
│   └── README.md
└── etc/                               # Supporting infrastructure
    ├── install_docker_registry.sh     # Private image registry
    ├── install_gitea.sh               # Self-hosted Git server
    ├── install_neovim.sh              # Terminal editor setup
    ├── tls/                           # TLS certificate management
    │   ├── generate_ca.sh             # Create Certificate Authority
    │   ├── generate_cert.sh           # Issue service certificates
    │   ├── enable_docker_registry_tls.sh  # Secure registry
    │   ├── enable_gitea_tls.sh        # Secure Git server
    │   └── trust_ca_on_nodes.sh       # Distribute CA to cluster
    └── README.md
```

---

## Learning Path

This repository is structured as a progressive journey:

### 1. Foundation (Week 1-2)
- Hardware setup and OS preparation
- Understanding Linux kernel modules for containers
- Container runtime architecture (containerd + systemd cgroups)
- Basic Kubernetes concepts (pods, deployments, services)

### 2. Core Kubernetes (Week 3-4)
- Control plane components and their roles
- CNI networking deep-dive (Calico)
- Storage abstractions (PV, PVC, StorageClasses)
- ConfigMaps, Secrets, and application configuration

### 3. Production Infrastructure (Week 5-6)
- Service mesh architecture and mTLS
- Ingress controllers and Layer 7 routing
- Certificate management and PKI
- Monitoring, logging, and observability

### 4. Advanced Operations (Week 7-8)
- GitOps workflows with Argo CD
- Chaos engineering and resilience testing
- Serverless with Knative
- GPU resource management

### 5. MLOps Specialization (Week 9+)
- Distributed training patterns
- Model serving and inference
- ML pipelines and workflows
- Multi-tenancy and resource quotas

**But also:** This is a reference. Use it for a weekend project or a long-term learning journey. Every script stands alone with complete documentation.

---

## Key Features

### Tutorial-Style Documentation
Every script includes:
- **Purpose:** What the script does and why it exists
- **Tutorial Goal:** Concepts you'll learn
- **Prerequisites:** What must be done first
- **Workflow:** When and where to run the script
- **Inline Comments:** Explaining every command's purpose

Example from `01_install_deps.sh`:
```bash
# --- Tutorial: Kernel Modules for Containers ---
# Kubernetes networking is complex. For it to work, the Linux kernel needs to
# correctly handle container network traffic.
# `overlay`: A filesystem driver that allows containers to efficiently layer
#            filesystems, which is fundamental to how container images work.
# `br_netfilter`: Allows the Linux bridge to pass traffic through the host's
#                 firewall (`iptables`), making container traffic manageable.
```

### Production Patterns
- Service mesh for zero-trust security
- GitOps for declarative operations
- Chaos engineering for resilience validation
- Comprehensive monitoring and alerting

### Vendor Neutrality
- Standard Kubernetes (not a distribution)
- CNI-agnostic (Calico by default, easily swappable)
- Cloud-portable (same manifests work on EKS, GKE, AKS)
- No proprietary lock-in

### Hardware Flexibility
- ARM64 native (Jetson, Raspberry Pi)
- x86_64 compatible (standard servers)
- Mixed-architecture clusters supported
- GPU and CPU nodes can coexist

---

## GPU and CUDA Support

### NVIDIA Jetson Integration

The Jetson platform is first-class:
- JetPack CUDA drivers work out-of-box with Kubernetes
- GPU resource scheduling via `nvidia.com/gpu` resource
- CUDA container support with nvidia-container-runtime
- TensorRT optimization for inference workloads

### NVIDIA GPU Operator (Coming Soon)

Future addition for production GPU clusters:
- Automated driver installation and updates
- Multi-Instance GPU (MIG) support
- GPU feature discovery and labeling
- Time-slicing for GPU sharing

### ML Framework Support

Tested and documented with:
- PyTorch (distributed training, DDP, FSDP)
- TensorFlow (distributed strategies)
- JAX (for research workloads)
- NVIDIA NeMo (LLM training framework)

---

## Community and Support

### Contributing

Contributions welcome! This repository values:
- **Educational clarity** - Explain the "why," not just the "what"
- **Production readiness** - Scripts must work on real hardware
- **Comprehensive testing** - Test on actual ARM64 devices
- **Documentation quality** - Update READMEs with changes

See individual README files for contribution guidelines.

### Getting Help

- **GitHub Issues:** Bug reports and feature requests
- **Discussions:** Architecture questions and use cases
- **Documentation:** Every directory has detailed README files

### Acknowledgments

Built on the shoulders of:
- **NVIDIA Jetson AI Lab** - Jetson setup inspiration
- **Kubernetes SIGs** - Upstream Kubernetes development
- **CNCF Projects** - Istio, Linkerd, Knative, Argo, Prometheus, and more
- **The Cloud Native Community** - For making this knowledge accessible

---

## License

[Specify your license - e.g., MIT, Apache 2.0]

---

## What's Next?

After completing this repository, you'll have:
- ✅ A production Kubernetes cluster
- ✅ Deep understanding of cloud-native architecture
- ✅ GPU-accelerated infrastructure for ML workloads
- ✅ Skills that transfer to any Kubernetes environment
- ✅ A platform for experimenting with distributed AI

**Use it to:**
- Train your first distributed neural network
- Build a computer vision pipeline
- Experiment with LLM fine-tuning
- Prepare for Kubernetes certifications
- Create a homelab that rivals production infrastructure

**The gap between learning and production is smaller than you think.**

Start with a Jetson. End with an A100 cluster. The architecture stays the same.
