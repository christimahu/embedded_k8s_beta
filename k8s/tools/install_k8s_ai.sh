#!/bin/bash

# ============================================================================
#
#             Install AI-Powered Kubernetes Tools (install_k8s_ai.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs AI-native tools that enhance Kubernetes operations with machine
#  learning and large language models (LLMs).
#
#  Tutorial Goal:
#  --------------
#  This script demonstrates the cutting edge of AI-assisted infrastructure
#  management. You will learn how LLMs can translate natural language into
#  `kubectl` commands and provide AI-powered diagnostics, making Kubernetes
#  more accessible and easier to troubleshoot.
#
#  Prerequisites:
#  --------------
#  - Completed: Core Kubernetes setup (`kubectl` must be installed).
#  - Network: SSH access and an active internet connection.
#  - API Keys: Access to an LLM service (OpenAI, Azure, local Ollama) is required.
#  - Time: ~5 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a management node. After installation, you must configure
#  the tools with API keys for an AI service.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
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

if [ -n "$SUDO_USER" ]; then
    readonly TARGET_USER="$SUDO_USER"
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
print_success "Will install tools for user: $TARGET_USER"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the core k8s setup scripts first."
    exit 1
fi
print_success "Prerequisite 'kubectl' is installed."

# ============================================================================
#                   STEP 1: INSTALL KUBECTL-AI
# ============================================================================

print_border "Step 1: Installing kubectl-ai"

# --- Tutorial: What is kubectl-ai? ---
# `kubectl-ai` is a kubectl plugin that uses LLMs to translate natural language
# queries into kubectl commands. It is a safe and powerful way to learn and use
# Kubernetes without memorizing complex syntax.
# ---
print_info "Installing kubectl-ai from GitHub releases..."
readonly KUBECTL_AI_VERSION="v0.0.26"
readonly KC_AI_ARCH_MAP="x86_64:amd64 aarch64:arm64 arm64:arm64"
ARCH=$(uname -m)
KC_AI_ARCH=$(echo "$KC_AI_ARCH_MAP" | grep -o "$ARCH:[^ ]*" | cut -d: -f2)
if [[ -z "$KC_AI_ARCH" ]]; then
    print_error "Unsupported architecture for kubectl-ai: $ARCH"
    exit 1
fi

KC_AI_URL="https://github.com/GoogleCloudPlatform/kubectl-ai/releases/download/${KUBECTL_AI_VERSION}/kubectl-ai_Linux_${KC_AI_ARCH}.tar.gz"

print_info "Downloading kubectl-ai ${KUBECTL_AI_VERSION} for ${KC_AI_ARCH}..."
curl -L "$KC_AI_URL" -o /tmp/kubectl-ai.tar.gz
sudo tar -xzf /tmp/kubectl-ai.tar.gz -C /usr/local/bin kubectl-ai
rm /tmp/kubectl-ai.tar.gz

print_success "kubectl-ai installed successfully."

# ============================================================================
#                       STEP 2: INSTALL K8SGPT
# ============================================================================

print_border "Step 2: Installing k8sgpt"

# --- Tutorial: What is k8sgpt? ---
# `k8sgpt` is a CNCF Sandbox project that acts as an AI-powered diagnostic tool
# for your Kubernetes cluster. It scans for issues and uses an LLM to explain
# the root cause and suggest remediation steps.
# ---
print_info "Installing k8sgpt from GitHub releases..."
readonly K8SGPT_VERSION="v0.3.31"
readonly K8SGPT_ARCH_MAP="x86_64:amd64 aarch64:arm64 arm64:arm64"
ARCH=$(uname -m)
K8SGPT_ARCH=$(echo "$K8SGPT_ARCH_MAP" | grep -o "$ARCH:[^ ]*" | cut -d: -f2)
if [[ -z "$K8SGPT_ARCH" ]]; then
    print_error "Unsupported architecture for k8sgpt: $ARCH"
    exit 1
fi

K8SGPT_URL="https://github.com/k8sgpt-ai/k8sgpt/releases/download/${K8SGPT_VERSION}/k8sgpt_linux_${K8SGPT_ARCH}.tar.gz"

print_info "Downloading k8sgpt ${K8SGPT_VERSION} for ${K8SGPT_ARCH}..."
curl -L "$K8SGPT_URL" -o /tmp/k8sgpt.tar.gz
sudo tar -xzf /tmp/k8sgpt.tar.gz -C /usr/local/bin k8sgpt
rm /tmp/k8sgpt.tar.gz

print_success "k8sgpt installed: $(k8sgpt version)"

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Configuration Required"
print_warning "ACTION REQUIRED: Both tools require AI backend configuration."
echo ""
echo "To use OpenAI (Paid Service):"
echo "1. Get an OpenAI API key: https://platform.openai.com/api-keys"
echo "2. Set for kubectl-ai: export OPENAI_API_KEY='your-key-here'"
echo "3. Set for k8sgpt:     k8sgpt auth add openai --apikey YOUR_API_KEY"
echo ""
echo "To use a local model like Mistral (Free via Ollama):"
echo "1. Install Ollama on a machine: curl https://ollama.ai/install.sh | sh"
echo "2. Pull a model:              ollama pull mistral"
echo "3. Configure kubectl-ai:    export OPENAI_API_BASE=http://<ollama_host>:11434"
echo "4. Configure k8sgpt:        k8sgpt auth add ollama --model mistral --baseurl http://<ollama_host>:11434"
echo ""
print_info "Add 'export' commands to your ~/.bashrc file to make them permanent."
echo ""
print_success "AI-powered Kubernetes tools installed successfully!"
