Embedded K8s: An Educational Homelab JourneyThis repository contains a complete, end-to-end collection of shell scripts and deployment manifests for setting up a production-grade Kubernetes cluster on ARM64 single-board computers.The entire project is built around an educational philosophy. Every script and YAML file is heavily commented, not just explaining what a command does, but why it's necessary, the architectural concepts behind it, and how it fits into the larger cloud-native ecosystem. This repo serves as both an automation toolset and a deep-dive, hands-on learning resource.PhilosophyEducational First: The primary goal is to demystify complex topics like the Jetson boot process, Kubernetes networking, GitOps, and cluster monitoring through hands-on practice.Modular Design: Hardware-specific setup (like for the Jetson Orin) is completely separate from the generic Kubernetes installation. This allows for a clean, repeatable workflow.Production-Oriented: While designed for a homelab, the scripts install and configure tools (Prometheus, Argo CD, Gitea) in a way that reflects industry best practices.Transparent and Recoverable: No magic scripts. Every step is explicit, and the repository includes tools for auditing the system state and recovering to a known-good configuration.Directory StructureTHISXTOXREPLACEX````.├── etc/                  # Host-level utilities (Neovim, Gitea, Docker Registry)├── jetson_orin/          # Hardware-specific setup for NVIDIA Jetson Orin├── k8s/│   ├── deployments/      # A library of heavily-commented example YAML manifests│   ├── node_setup/       # Common Kubernetes prerequisites for every node│   ├── ops/              # Cluster operations: bootstrapping and joining nodes│   └── tools/            # Cluster-wide add-ons (Prometheus, Argo CD, etc.)└── raspberry_pi/         # (Placeholder) Hardware-specific setup for Raspberry Pi
## Quick Start: Jetson Orin Workflow

This workflow will take a stock Jetson Orin and turn it into a fully configured Kubernetes node.

**1. Hardware Preparation (Physical Access Required)**

-   Flash NVIDIA JetPack to a microSD card and install it along with an NVMe SSD in the Jetson.
-   Complete the initial on-screen Ubuntu setup.
-   Open a terminal and clone this repository.

**2. Run Platform-Specific Setup**

First, run the script to configure headless mode, then shut down to disconnect the monitor and keyboard.

THISXTOXREPLACEXbash
cd embedded_k8s/jetson_orin/setup
sudo ./01_config_headless.sh
# When complete:
sudo shutdown now
THISXTOXREPLACEX

**3. Continue via SSH**

Power the device back on and SSH into it. Complete the rest of the Jetson setup, which clones the OS to the SSD and prepares it for Kubernetes.

THISXTOXREPLACEXbash
# ... complete steps 02 through 06 in jetson_orin/setup/ ...
THISXTOXREPLACEX

**4. Install Common Kubernetes Prerequisites**

Run these scripts on **every** node you add to the cluster.

THISXTOXREPLACEXbash
cd embedded_k8s/k8s/node_setup
sudo ./01_install_deps.sh
sudo ./02_install_kube.sh
THISXTOXREPLACEX

**5. Assign a Cluster Role**

-   **On the first control plane node only**:
    THISXTOXREPLACEXbash
    cd embedded_k8s/k8s/ops
    sudo ./bootstrap_cluster.sh
    THISXTOXREPLACEX

-   **On all subsequent nodes (workers or other control planes)**:
    THISXTOXREPLACEXbash
    cd embedded_k8s/k8s/ops
    sudo ./join_node.sh
    THISXTOXREPLACEX

