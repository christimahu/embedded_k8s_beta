#!/bin/bash

# ====================================================================================
#
#               Install Kubernetes CLI Extras (install_k8s_extras.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs a suite of highly-recommended, optional command-line tools that make
#  managing and interacting with a Kubernetes cluster significantly easier and more
#  efficient. These are considered "extras" or "helpers" for the human user.
#
#  Tutorial Goal:
#  --------------
#  This script explains the difference between the essential Kubernetes node
#  binaries (`kubectl`, `kubelet`, `kubeadm`) and the rich ecosystem of third-party
#  tools that enhance the administrator's workflow. The core binaries, which are
#  required for a node to function, are installed by the scripts in `common/k8s/setup`.
#  The tools installed here are not required for the cluster to run, but they are
#  industry-standard utilities that save time, reduce errors, and provide much
#  deeper insight into cluster operations.
#
#  What Gets Installed (The Admin "Extras" Toolkit):
#  -------------------------------------------------
#  1. jq: The essential command-line JSON processor for parsing `kubectl` output.
#  2. yq: The `jq` equivalent for YAML, perfect for scripting changes to manifests.
#  3. helm: The de facto package manager for Kubernetes.
#  4. kubectx / kubens: Fast context and namespace switchers.
#  5. k9s: A powerful, terminal-based UI for managing your cluster.
#
#  Philosophy:
#  -----------
#  While you can manage a cluster with `kubectl` alone, this toolkit represents
#  the modern, efficient workflow adopted by Kubernetes administrators worldwide.
#  Installing these extras dramatically improves the day-to-day experience of
#  cluster management, making it faster, more intuitive, and more enjoyable.
#
# ====================================================================================

# --- Helper Functions for Better Output ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

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

if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
print_success "Will install tools for user: $TARGET_USER"

# Verify kubectl is installed (it's a prerequisite from the core setup)
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the core k8s setup scripts first."
    print_error "Location: common/k8s/setup/02_install_kube.sh"
    exit 1
fi
print_success "kubectl is installed."

# --- Part 1: Install jq (JSON Processor) ---

print_border "Step 1: Installing jq (JSON Processor)"

# --- Tutorial: Why jq? ---
# Kubernetes heavily uses JSON. 'kubectl get pods -o json' produces a massive JSON
# blob. jq is a lightweight tool that lets you parse, filter, and format that JSON
# directly on the command line, making it essential for scripting and automation.
# ---

print_info "Installing jq from Ubuntu repositories..."
apt-get update
apt-get install -y jq

if ! command -v jq &> /dev/null; then
    print_error "Failed to install jq."
    exit 1
fi

JQ_VERSION=$(jq --version)
print_success "jq installed: $JQ_VERSION"

# --- Part 2: Install yq (YAML Processor) ---

print_border "Step 2: Installing yq (YAML Processor)"

# --- Tutorial: Why yq? ---
# Kubernetes configurations are written in YAML. yq brings the same power of jq
# to YAML files, allowing you to programmatically edit Kubernetes manifests,
# extract values from Helm charts, or merge configurations in your scripts.
# ---

print_info "Installing yq from GitHub releases..."
ARCH=$(uname -m)
case $ARCH in
    x86_64) YQ_ARCH="amd64" ;;
    aarch64|arm64) YQ_ARCH="arm64" ;;
    *) print_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac
YQ_VERSION="v4.40.5"
YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}"
curl -L "$YQ_URL" -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
if ! command -v yq &> /dev/null; then
    print_error "Failed to install yq."
    exit 1
fi
print_success "yq installed: $(yq --version)"

# --- Part 3: Install Helm (Package Manager) ---

print_border "Step 3: Installing Helm (Kubernetes Package Manager)"

# --- Tutorial: Why Helm? ---
# Helm is the 'apt' or 'homebrew' for Kubernetes. It allows you to install complex
# applications from pre-packaged templates called "charts," instead of managing
# dozens of interconnected YAML files manually. It's the standard for deploying
# applications on Kubernetes.
# ---

print_info "Installing Helm using official installer..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
if ! command -v helm &> /dev/null; then
    print_error "Failed to install Helm."
    exit 1
fi
HELM_VERSION=$(helm version --short)
print_success "Helm installed: $HELM_VERSION"
print_info "Adding common Helm chart repositories..."
sudo -u "$TARGET_USER" helm repo add stable https://charts.helm.sh/stable 2>/dev/null || true
sudo -u "$TARGET_USER" helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
sudo -u "$TARGET_USER" helm repo update
print_success "Helm repositories configured."

# --- Part 4: Install kubectx and kubens (Context/Namespace Switchers) ---

print_border "Step 4: Installing kubectx and kubens"

# --- Tutorial: Why kubectx and kubens? ---
# These are simple but powerful quality-of-life tools. They reduce the verbose
# kubectl commands for switching between different clusters (`kubectx`) and
# namespaces (`kubens`) to a single, memorable command.
# ---

print_info "Installing kubectx and kubens from GitHub..."
curl -L "https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx" -o /usr/local/bin/kubectx
chmod +x /usr/local/bin/kubectx
curl -L "https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens" -o /usr/local/bin/kubens
chmod +x /usr/local/bin/kubens
if ! command -v kubectx &> /dev/null || ! command -v kubens &> /dev/null; then
    print_error "Failed to install kubectx/kubens."
    exit 1
fi
print_success "kubectx and kubens installed."

# --- Part 5: Install k9s (Terminal UI) ---

print_border "Step 5: Installing k9s (Terminal UI for Kubernetes)"

# --- Tutorial: Why k9s? ---
# k9s is a terminal-based UI that provides a real-time, interactive view of your
# cluster. It's like 'htop' for Kubernetes, allowing you to navigate resources,
# view logs, exec into containers, and manage the cluster much faster than by
# repeatedly typing kubectl commands.
# ---

print_info "Installing k9s from GitHub releases..."
case $ARCH in
    x86_64) K9S_ARCH="amd64" ;;
    aarch64|arm64) K9S_ARCH="arm64" ;;
    *) print_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac
K9S_VERSION="v0.31.7"
K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${K9S_ARCH}.tar.gz"
curl -L "$K9S_URL" -o /tmp/k9s.tar.gz
tar -xzf /tmp/k9s.tar.gz -C /tmp
mv /tmp/k9s /usr/local/bin/
chmod +x /usr/local/bin/k9s
rm /tmp/k9s.tar.gz
if ! command -v k9s &> /dev/null; then
    print_error "Failed to install k9s."
    exit 1
fi
print_success "k9s installed: $(k9s version --short)"

# --- Final Instructions ---

print_border "Installation Complete"
echo ""
echo -e "${C_GREEN}All Kubernetes CLI extras successfully installed!${C_RESET}"
echo ""
echo -e "${C_BLUE}Installed Tools:${C_RESET}"
echo "  ✓ jq       - JSON processor"
echo "  ✓ yq       - YAML processor"
echo "  ✓ helm     - Package manager"
echo "  ✓ kubectx  - Context switcher"
echo "  ✓ kubens   - Namespace switcher"
echo "  ✓ k9s      - Terminal UI"
echo ""
echo -e "${C_YELLOW}To start exploring your cluster, just run:${C_RESET}"
echo "  k9s"
echo ""
