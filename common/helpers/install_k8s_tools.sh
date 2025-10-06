#!/bin/bash

# ====================================================================================
#
#                   Install Kubernetes CLI Tools (install_k8s_tools.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs essential command-line tools for working with Kubernetes clusters.
#  These are stable, production-ready tools that make daily k8s operations more
#  efficient and pleasant.
#
#  Tutorial Goal:
#  --------------
#  Kubernetes management involves constant interaction with YAML configs, JSON
#  output, and multiple clusters/namespaces. This script installs the standard
#  toolkit that experienced k8s administrators rely on for productivity.
#
#  What Gets Installed:
#  --------------------
#  1. jq - Command-line JSON processor
#     Why: kubectl outputs JSON. jq lets you parse, filter, and transform it.
#     Example: kubectl get pods -o json | jq '.items[].metadata.name'
#
#  2. yq - Command-line YAML processor (like jq but for YAML)
#     Why: k8s configs are YAML. yq lets you edit them programmatically.
#     Example: yq eval '.spec.replicas = 5' deployment.yaml
#
#  3. helm - Kubernetes package manager
#     Why: Deploy complex applications with single commands instead of managing
#          dozens of YAML files manually. The standard for k8s deployments.
#     Example: helm install prometheus prometheus-community/prometheus
#
#  4. kubectx - Fast context switching between clusters
#     Why: If you manage multiple clusters (dev/staging/prod), switching between
#          them with kubectl is tedious. kubectx makes it one command.
#     Example: kubectx production
#
#  5. kubens - Fast namespace switching
#     Why: Kubernetes namespaces isolate resources. kubens lets you switch your
#          default namespace so you don't have to type -n namespace every time.
#     Example: kubens kube-system
#
#  6. k9s - Terminal UI for Kubernetes
#     Why: A beautiful, efficient TUI for browsing and managing your cluster.
#          Much faster than repeatedly typing kubectl commands. Think of it as
#          "top" or "htop" but for Kubernetes.
#     Example: Just run 'k9s' and explore
#
#  Philosophy:
#  -----------
#  These tools represent the modern k8s workflow. While you can do everything
#  with raw kubectl commands, these tools dramatically improve efficiency and
#  reduce errors. They're industry-standard and found on most k8s admin machines.
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

# Verify kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the k8s setup scripts first."
    print_error "Location: common/k8s/setup/02_install_kube.sh"
    exit 1
fi
print_success "kubectl is installed."

# --- Part 1: Install jq (JSON Processor) ---

print_border "Step 1: Installing jq (JSON Processor)"

# --- Tutorial: Why jq? ---
# Kubernetes heavily uses JSON for data interchange. When you run commands like
# 'kubectl get pods -o json', you get a massive JSON blob. jq is a lightweight
# command-line tool that lets you parse, filter, and format JSON data.
#
# Real-world example:
#   kubectl get pods -o json | jq '.items[] | select(.status.phase=="Running") | .metadata.name'
#   This gets all running pod names - much cleaner than parsing JSON manually.
#
# jq is to JSON what grep/awk/sed are to text - essential for shell scripting.
# See: https://stedolan.github.io/jq/
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
# While jq handles JSON, Kubernetes configurations are written in YAML. yq brings
# the same powerful query/transformation capabilities to YAML files. This is
# incredibly useful for:
# - Programmatically editing k8s manifests in scripts
# - Extracting specific values from Helm charts
# - Merging or transforming YAML configs
#
# Example:
#   yq eval '.spec.replicas = 3' deployment.yaml
#   This changes the replica count in a deployment file - no text editing needed.
#
# We install the Go-based yq by Mike Farah (mikefarah/yq), which is the most
# popular and actively maintained version. Don't confuse this with the Python
# yq, which is a different tool.
# See: https://github.com/mikefarah/yq
# ---

print_info "Installing yq from GitHub releases..."

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        YQ_ARCH="amd64"
        ;;
    aarch64|arm64)
        YQ_ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

YQ_VERSION="v4.40.5"
YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}"

print_info "Downloading yq ${YQ_VERSION} for ${YQ_ARCH}..."
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
# Helm is the package manager for Kubernetes, similar to apt for Ubuntu or
# Homebrew for macOS. It solves a critical problem: deploying complex applications
# to Kubernetes typically requires dozens of interconnected YAML files
# (deployments, services, configmaps, secrets, etc.). Managing these manually is
# error-prone and tedious.
#
# Helm packages these files into "charts" - reusable, parameterized templates.
# Instead of managing 30 YAML files, you run one command:
#   helm install prometheus prometheus-community/prometheus
#
# Charts can be versioned, shared, and customized. The Helm community maintains
# thousands of pre-built charts for popular applications. This dramatically
# accelerates deployment and reduces human error.
#
# Helm is essential for modern k8s workflows and is used by virtually all
# production Kubernetes deployments.
# See: https://helm.sh/
# ---

print_info "Installing Helm using official installer..."

# The official Helm install script downloads the appropriate binary for your
# architecture and installs it to /usr/local/bin. This is the recommended
# installation method from the Helm project.
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

if ! command -v helm &> /dev/null; then
    print_error "Failed to install Helm."
    exit 1
fi

HELM_VERSION=$(helm version --short)
print_success "Helm installed: $HELM_VERSION"

# Add popular Helm chart repositories
print_info "Adding common Helm chart repositories..."
sudo -u "$TARGET_USER" helm repo add stable https://charts.helm.sh/stable 2>/dev/null || true
sudo -u "$TARGET_USER" helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
sudo -u "$TARGET_USER" helm repo update
print_success "Helm repositories configured."

# --- Part 4: Install kubectx and kubens (Context/Namespace Switchers) ---

print_border "Step 4: Installing kubectx and kubens"

# --- Tutorial: Why kubectx and kubens? ---
# When working with Kubernetes, you often need to:
# 1. Switch between different clusters (dev, staging, prod)
# 2. Switch between different namespaces within a cluster
#
# The kubectl way to do this is verbose:
#   kubectl config use-context my-cluster
#   kubectl config set-context --current --namespace=my-namespace
#
# kubectx and kubens reduce this to:
#   kubectx my-cluster
#   kubens my-namespace
#
# They also provide interactive selection with fuzzy finding if you have fzf
# installed. These small quality-of-life improvements add up over hundreds of
# daily context/namespace switches.
# See: https://github.com/ahmetb/kubectx
# ---

print_info "Installing kubectx and kubens from GitHub..."

# Download kubectx
KUBECTX_URL="https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx"
curl -L "$KUBECTX_URL" -o /usr/local/bin/kubectx
chmod +x /usr/local/bin/kubectx

# Download kubens
KUBENS_URL="https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens"
curl -L "$KUBENS_URL" -o /usr/local/bin/kubens
chmod +x /usr/local/bin/kubens

if ! command -v kubectx &> /dev/null || ! command -v kubens &> /dev/null; then
    print_error "Failed to install kubectx/kubens."
    exit 1
fi

print_success "kubectx and kubens installed."

# --- Part 5: Install k9s (Terminal UI) ---

print_border "Step 5: Installing k9s (Terminal UI for Kubernetes)"

# --- Tutorial: Why k9s? ---
# k9s is a terminal-based UI for managing Kubernetes clusters. Think of it as
# "htop" but for Kubernetes. It provides:
# - Real-time view of all cluster resources
# - Easy navigation between namespaces, pods, services, etc.
# - Log viewing, exec into containers, port-forwarding - all with simple keystrokes
# - Resource usage visualization
# - Much faster than typing kubectl commands repeatedly
#
# k9s is beloved by the Kubernetes community for its efficiency and polish. It
# significantly improves the day-to-day experience of cluster management, especially
# for troubleshooting and monitoring.
#
# Learning curve: ~5 minutes. Productivity gain: substantial.
# See: https://k9scli.io/
# ---

print_info "Installing k9s from GitHub releases..."

# Detect architecture for k9s
case $ARCH in
    x86_64)
        K9S_ARCH="amd64"
        ;;
    aarch64|arm64)
        K9S_ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

K9S_VERSION="v0.31.7"
K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${K9S_ARCH}.tar.gz"

print_info "Downloading k9s ${K9S_VERSION} for ${K9S_ARCH}..."
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
echo -e "${C_GREEN}All Kubernetes tools successfully installed!${C_RESET}"
echo ""
echo -e "${C_BLUE}Installed Tools:${C_RESET}"
echo "  ✓ jq       - JSON processor"
echo "  ✓ yq       - YAML processor"
echo "  ✓ helm     - Package manager"
echo "  ✓ kubectx  - Context switcher"
echo "  ✓ kubens   - Namespace switcher"
echo "  ✓ k9s      - Terminal UI"
echo ""
echo -e "${C_YELLOW}Quick Start Examples:${C_RESET}"
echo ""
echo "  # Parse JSON output from kubectl"
echo "  kubectl get pods -o json | jq '.items[].metadata.name'"
echo ""
echo "  # Edit YAML files"
echo "  yq eval '.spec.replicas = 5' deployment.yaml"
echo ""
echo "  # Install an application with Helm"
echo "  helm search repo nginx"
echo "  helm install my-nginx bitnami/nginx"
echo ""
echo "  # Switch contexts and namespaces"
echo "  kubectx              # List contexts"
echo "  kubens               # List namespaces"
echo ""
echo "  # Launch the k9s UI"
echo "  k9s"
echo ""
echo -e "${C_INFO}Next Steps:${C_RESET}"
echo "  - Explore k9s by running: k9s"
echo "  - Browse Helm charts: helm search hub prometheus"
echo "  - See Helm documentation: https://helm.sh/docs/"
echo ""
