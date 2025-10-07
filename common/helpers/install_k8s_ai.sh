#!/bin/bash

# ====================================================================================
#
#                Install AI-Powered Kubernetes Tools (install_k8s_ai.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs AI-native tools that enhance Kubernetes operations with machine learning
#  and large language models. These tools represent the cutting edge of AI-assisted
#  cluster management and troubleshooting.
#
#  Tutorial Goal:
#  --------------
#  AI is transforming how we interact with complex systems. These tools leverage
#  large language models to make Kubernetes more accessible and to catch issues
#  that traditional monitoring might miss. This script demonstrates the AI-native
#  approach to modern cloud infrastructure management.
#
#  What Gets Installed:
#  --------------------
#  1. kubectl-ai - AI-powered kubectl assistant
#     Why: Translates natural language into kubectl commands. Instead of memorizing
#          complex kubectl syntax, you can ask "show me pods using more than 80%
#          memory" and it generates the correct command.
#
#  2. k8sgpt - AI-powered cluster diagnostics
#     Why: Analyzes your cluster for issues and provides AI-generated explanations
#          and remediation steps. It's like having an SRE assistant that understands
#          your cluster state and can suggest fixes in plain English.
#
#  Philosophy - AI-Native Infrastructure:
#  ---------------------------------------
#  Traditional k8s tooling requires deep expertise. AI-powered tools democratize
#  this knowledge by:
#  - Making Kubernetes accessible to engineers learning the platform
#  - Reducing cognitive load for experienced operators
#  - Catching non-obvious issues through pattern recognition
#  - Providing context-aware troubleshooting
#
#  IMPORTANT - API Keys Required:
#  ------------------------------
#  These tools require API access to large language models. You have options:
#  - Paid Services: OpenAI, Azure OpenAI, etc. (Requires an API key)
#  - Local Models: Ollama allows you to run open-source models like Mistral for free.
#
# ====================================================================================

# --- Helper Functions for Better Output ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_MAGENTA='\033[0;35m'

print_success() {
    echo -e "${C_GREEN}[OK] $1${C_RESET}"
}
print_error() {
    echo -e "${C_RED}[ERROR] $1${C_RESET}"
}
print_info() {
    echo -e "${C_YELLOW}[INFO] $1${C_RESET}"
}
print_warning() {
    echo -e "${C_MAGENTA}[WARNING] $1${C_RESET}"
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

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the k8s setup scripts first."
    exit 1
fi
print_success "kubectl is installed."

# --- Important Notice About AI Services ---

print_border "IMPORTANT: AI Service Requirements"
echo ""
echo -e "${C_YELLOW}These tools require API access to AI language models.${C_RESET}"
echo "Options:"
echo "  1. Paid Cloud APIs (e.g., OpenAI)"
echo "  2. Free Local Models (e.g., Mistral via Ollama)"
echo ""
read -p "Continue with installation? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Installation cancelled."
    exit 0
fi

# --- Part 1: Install kubectl-ai ---

print_border "Step 1: Installing kubectl-ai"

# --- Tutorial: What is kubectl-ai? ---
# kubectl-ai is a kubectl plugin that uses large language models (LLMs) to
# translate natural language queries into kubectl commands. Instead of remembering
# complex syntax, you describe what you want in plain English.
#
# How it works:
# 1. You type a question like: kubectl ai "show me all pods in crashloopbackoff"
# 2. The plugin sends your query to an LLM.
# 3. The LLM generates the appropriate kubectl command.
# 4. You are shown the command and asked to confirm before it runs.
#
# This is valuable for learning Kubernetes, performing complex queries, and
# troubleshooting under pressure. Because you approve every command, it's safe
# to use.
# ---

print_info "Checking for Go installation..."
if ! command -v go &> /dev/null; then
    print_info "Go not found. Installing Go..."
    apt-get update
    apt-get install -y golang-go
    if ! command -v go &> /dev/null; then
        print_error "Failed to install Go. Cannot proceed with kubectl-ai."
        exit 1
    fi
fi
print_success "Go is available."

print_info "Installing kubectl-ai via go install..."
# The actual package path is in the /cmd/kubectl-ai subdirectory of the repo.
sudo -u "$TARGET_USER" bash -c "export HOME=$TARGET_HOME && go install github.com/GoogleCloudPlatform/kubectl-ai/cmd/kubectl-ai@latest"

GO_BIN_PATH="$TARGET_HOME/go/bin"
if [ -d "$GO_BIN_PATH" ]; then
    if ! grep -q "$GO_BIN_PATH" "$TARGET_HOME/.bashrc"; then
        echo "" >> "$TARGET_HOME/.bashrc"
        echo "# Go binaries" >> "$TARGET_HOME/.bashrc"
        echo "export PATH=\"\$PATH:$GO_BIN_PATH\"" >> "$TARGET_HOME/.bashrc"
        print_success "Added Go bin directory to PATH in ~/.bashrc"
    fi
fi

if [ ! -f "$GO_BIN_PATH/kubectl-ai" ]; then
    print_error "kubectl-ai installation failed."
    exit 1
fi

print_success "kubectl-ai installed to $GO_BIN_PATH/kubectl-ai"

# --- Part 2: Install k8sgpt ---

print_border "Step 2: Installing k8sgpt"

# --- Tutorial: What is k8sgpt? ---
# k8sgpt is a CNCF Sandbox project that acts as an AI-powered diagnostic tool
# for your Kubernetes cluster. It:
# - Scans your cluster for issues (resource constraints, misconfigurations, etc.).
# - Identifies problems and uses an LLM to explain WHY the problem is happening.
# - Suggests specific remediation steps in human-readable language.
#
# Unlike traditional monitoring which just alerts, k8sgpt provides CONTEXT. For
# example, instead of "Pod is CrashLooping," it might explain that the container
# is trying to bind to a privileged port without the correct permissions.
#
# It can use cloud APIs or be configured to use local models for full privacy.
# ---

print_info "Installing k8sgpt from GitHub releases..."
ARCH=$(uname -m)
case $ARCH in
    x86_64) K8SGPT_ARCH="amd64" ;;
    aarch64|arm64) K8SGPT_ARCH="arm64" ;;
    *) print_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

K8SGPT_VERSION="v0.3.31"
K8SGPT_URL="https://github.com/k8sgpt-ai/k8sgpt/releases/download/${K8SGPT_VERSION}/k8sgpt_${K8SGPT_VERSION#v}_linux_${K8SGPT_ARCH}.tar.gz"

curl -L "$K8SGPT_URL" -o /tmp/k8sgpt.tar.gz
tar -xzf /tmp/k8sgpt.tar.gz -C /tmp
mv /tmp/k8sgpt /usr/local/bin/
chmod +x /usr/local/bin/k8sgpt
rm /tmp/k8sgpt.tar.gz

if ! command -v k8sgpt &> /dev/null; then
    print_error "Failed to install k8sgpt."
    exit 1
fi

print_success "k8sgpt installed: $(k8sgpt version)"

# --- Part 3: Configuration Instructions ---

print_border "Configuration Required"
echo ""
echo -e "${C_YELLOW}Both tools require AI backend configuration.${C_RESET}"
echo ""
echo -e "${C_BLUE}To use OpenAI (Paid Service):${C_RESET}"
echo "  1. Get an OpenAI API key: https://platform.openai.com/api-keys"
echo "  2. Set for kubectl-ai: export OPENAI_API_KEY='your-key-here'"
echo "  3. Set for k8sgpt: k8sgpt auth add openai --apikey YOUR_API_KEY"
echo ""
echo -e "${C_BLUE}To use a local model like Mistral (Free):${C_RESET}"
echo "  1. Install Ollama: curl https://ollama.ai/install.sh | sh"
echo "  2. Pull the model: ollama pull mistral"
echo "  3. Configure k8sgpt: k8sgpt auth add ollama --model mistral"
echo "  4. Configure kubectl-ai: export OPENAI_API_BASE=http://localhost:11434"
echo ""
echo -e "${C_MAGENTA}Note: Add 'export' commands to ~/.bashrc to make them permanent.${C_RESET}"
echo ""
print_success "AI-powered Kubernetes tools installed successfully!"
