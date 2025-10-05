#!/bin/bash

# ====================================================================================
#
#              Initialize Kubernetes Control Plane (init.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  This script bootstraps the Kubernetes control plane on the **first** control
#  plane node. It initializes the cluster, sets up `kubectl` access, and installs
#  the crucial network plugin (CNI).
#
#  Tutorial Goal:
#  --------------
#  This is the moment of creation. We will use `kubeadm init` to bring our
#  cluster to life. This process generates the necessary certificates and configs,
#  starts the core control plane components (API server, scheduler, etc.) as
#  static pods, and prepares the cluster for networking and worker nodes.
#
#  Workflow:
#  ---------
#  - Run this script ONLY on the first machine designated as a control plane.
#  - It must be run AFTER the setup scripts (`01_...` and `02_...`) are complete.
#
# ====================================================================================


# --- Helper Functions for Better Output ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'

print_success() {
    echo -e "${C_GREEN}[OK] $1${C_RESET}"
}
print_error() {
    echo -e "${C_RED}[ERROR] $1${C_RESET}"
}
print_info() {
    echo -e "${C_YELLOW}[INFO] $1${C_RESET}"
}
print_border() {
    echo ""
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
    echo " $1"
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
}


# --- Initial Sanity Checks ---

print_border "Step 0: Pre-flight Checks"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with root privileges. Please use 'sudo'."
    exit 1
fi
print_success "Running as root."

# Determine the non-root user who invoked sudo
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi


# --- Part 1: Initialize the Kubernetes Cluster ---

print_border "Step 1: Initialize the Kubernetes Control Plane"

# --- Tutorial: `kubeadm init` Parameters ---
# `kubeadm init` is the command that bootstraps the cluster.
# `--pod-network-cidr`: This is a crucial parameter. It defines the private IP
#   address range from which pods will be assigned their own IPs. This range must
#   not conflict with your physical network's IP range. The CNI plugin we install
#   later (Calico) must be configured to use this same CIDR block.
#
# See: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
# ---
IP_ADDR=$(hostname -I | awk '{print $1}')
print_info "Initializing cluster on this node ($IP_ADDR)... This will take a few minutes."
kubeadm init --pod-network-cidr=10.244.0.0/16

if [ $? -ne 0 ]; then
    print_error "kubeadm init failed. Please check the output above for errors."
    exit 1
fi
print_success "Control plane initialized successfully."


# --- Part 2: Configure kubectl Access ---
print_border "Step 2: Configure kubectl for Cluster Administration"

# --- Tutorial: The `kubeconfig` File ---
# The `kubeadm init` process generates a file called `admin.conf`. This file
# contains the cluster's details and the administrative credentials needed to
# connect to it. `kubectl` looks for this information in a file named `config`
# inside a `.kube` directory in a user's home directory. These next commands copy
# the file to the correct location and set its ownership so the user can run
# `kubectl` without needing `sudo`.
# ---
print_info "Setting up kubeconfig for user '$TARGET_USER'..."
mkdir -p "$TARGET_HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$TARGET_HOME/.kube/config"
chown "$(id -u $TARGET_USER):$(id -g $TARGET_USER)" "$TARGET_HOME/.kube/config"
print_success "kubectl is now configured for the user. Try 'kubectl get nodes'."


# --- Part 3: Install the Pod Network (CNI) ---

print_border "Step 3: Install a Pod Network Add-on (Calico CNI)"

# --- Tutorial: Why We Need a CNI Plugin ---
# A fresh Kubernetes cluster has a control plane, but the nodes cannot communicate
# with each other yet. A Container Network Interface (CNI) plugin is required to
# create a "pod network" that allows containers on different nodes to communicate.
# Without a CNI, your pods will be stuck in a "ContainerCreating" state and your
# nodes will remain "NotReady". We are using Calico, a popular CNI that is
# efficient and supports advanced features like network policies.
# ---
print_info "Installing Calico Operator for pod networking..."
# We must run this as the user who has the kubeconfig file.
sudo -u "$TARGET_USER" kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

print_info "Applying Calico custom resource definition..."
sudo -u "$TARGET_USER" kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml

print_info "Waiting for Calico pods to start... This may take a minute."
sleep 10
sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s
print_success "Calico CNI installed and running."


# --- Final Instructions ---
print_border "Control Plane Setup Complete!"
print_success "Your Kubernetes cluster is up and running."
echo ""
print_info "IMPORTANT: To add more nodes to the cluster, use the following commands:"
echo ""

# The `kubeadm token create` command is the most reliable way to generate a fresh join command.
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "  - To add a NEW WORKER node, run this on the worker:"
echo "    ----------------------------------------------------------"
echo "    sudo $JOIN_COMMAND"
echo "    ----------------------------------------------------------"
echo ""

CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -n1)
echo "  - To add a NEW CONTROL PLANE node, run this on the other node:"
echo "    ----------------------------------------------------------"
echo "    sudo $JOIN_COMMAND --control-plane --certificate-key $CERT_KEY"
echo "    ----------------------------------------------------------"
echo ""
echo "Save these commands. You will need them for the '../worker/join.sh' script."
