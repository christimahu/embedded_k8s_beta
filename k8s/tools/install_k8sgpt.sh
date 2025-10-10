#!/bin/bash

# ============================================================================
#
#                    Install k8sgpt (install_k8sgpt.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs k8sgpt, a CNCF Sandbox tool that uses AI to diagnose and explain
#  Kubernetes cluster issues, providing actionable remediation steps.
#
#  Tutorial Goal:
#  --------------
#  This script introduces AI-powered cluster diagnostics. Instead of manually
#  parsing logs and error messages, k8sgpt scans your cluster for problems,
#  analyzes them using an LLM, and explains both the root cause and how to fix
#  it. This dramatically reduces time-to-resolution for cluster issues.
#
#  What is k8sgpt?
#  ---------------
#  k8sgpt is a CNCF Sandbox project that acts as an intelligent diagnostic tool
#  for Kubernetes. It:
#  - Scans your cluster for issues (failing pods, misconfigurations, etc.)
#  - Analyzes error messages and events
#  - Uses an LLM to explain problems in plain English
#  - Provides step-by-step remediation guidance
#  - Supports multiple AI backends (OpenAI, Azure, local models)
#
#  How It Works:
#  -------------
#  1. k8sgpt analyzes cluster state (pods, deployments, services, etc.)
#  2. Identifies anomalies and error conditions
#  3. Sends problem data to an LLM for analysis
#  4. Returns human-readable explanations and fixes
#
#  k8sgpt vs kubectl-ai:
#  ---------------------
#  - kubectl-ai: Helps you BUILD commands ("How do I...?")
#  - k8sgpt: Helps you FIX problems ("Why is this broken?")
#
#  Prerequisites:
#  --------------
#  - Completed: Core Kubernetes setup (`kubectl` must be installed).
#  - Network: SSH access and an active internet connection.
#  - API Access: You'll need access to an LLM service after installation.
#  - Time: ~5 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a management node or any machine with kubectl access.
#  After installation, you must configure an AI backend (OpenAI, Azure, or
#  local model like Ollama).
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

if [ -n "$SUDO_USER" ]; then
    readonly TARGET_USER="$SUDO_USER"
else
    print_error "Could not determine the target user. Please run with 'sudo'."
    exit 1
fi
print_success "Will install k8sgpt for user: $TARGET_USER"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the core k8s setup scripts first."
    exit 1
fi
print_success "Prerequisite 'kubectl' is installed."

# ============================================================================
#                        STEP 1: INSTALL K8SGPT
# ============================================================================

print_border "Step 1: Installing k8sgpt"

# --- Tutorial: What is k8sgpt? ---
# k8sgpt is a CNCF Sandbox project that acts as an AI-powered diagnostic tool
# for your Kubernetes cluster. It scans for issues and uses an LLM to explain
# the root cause and suggest remediation steps.
#
# The tool is distributed as a single binary that works standalone or can be
# installed as an in-cluster operator for continuous monitoring.
# ---
print_info "Detecting system architecture..."
readonly K8SGPT_VERSION="v0.3.31"
readonly K8SGPT_ARCH_MAP="x86_64:amd64 aarch64:arm64 arm64:arm64"
ARCH=$(uname -m)
K8SGPT_ARCH=$(echo "$K8SGPT_ARCH_MAP" | grep -o "$ARCH:[^ ]*" | cut -d: -f2)
if [[ -z "$K8SGPT_ARCH" ]]; then
    print_error "Unsupported architecture for k8sgpt: $ARCH"
    echo "Supported architectures: x86_64 (amd64), aarch64/arm64"
    exit 1
fi

print_success "Detected architecture: $ARCH (k8sgpt arch: $K8SGPT_ARCH)"

readonly K8SGPT_URL="https://github.com/k8sgpt-ai/k8sgpt/releases/download/${K8SGPT_VERSION}/k8sgpt_linux_${K8SGPT_ARCH}.tar.gz"

print_info "Downloading k8sgpt ${K8SGPT_VERSION} for ${K8SGPT_ARCH}..."
curl -L "$K8SGPT_URL" -o /tmp/k8sgpt.tar.gz

if [ $? -ne 0 ]; then
    print_error "Failed to download k8sgpt."
    exit 1
fi

print_info "Extracting k8sgpt..."
sudo tar -xzf /tmp/k8sgpt.tar.gz -C /usr/local/bin k8sgpt
rm /tmp/k8sgpt.tar.gz

if [ ! -f "/usr/local/bin/k8sgpt" ]; then
    print_error "k8sgpt binary not found after extraction."
    exit 1
fi

sudo chmod +x /usr/local/bin/k8sgpt
print_success "k8sgpt installed successfully."

# Verify installation
if command -v k8sgpt &> /dev/null; then
    print_success "k8sgpt is available: $(k8sgpt version)"
else
    print_error "k8sgpt is not in PATH. Installation may have failed."
    exit 1
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Installation Complete"
print_success "k8sgpt is now installed!"
echo ""
print_warning "ACTION REQUIRED: Configure an AI backend"
echo ""
echo "k8sgpt requires access to a Large Language Model (LLM) for analysis."
echo "You have several options:"
echo ""
echo "============================================================================"
echo "Option 1: OpenAI (Paid Service - Recommended for Production)"
echo "============================================================================"
echo ""
echo "1. Get an OpenAI API key:"
echo "   - Visit: https://platform.openai.com/api-keys"
echo "   - Create a new API key"
echo ""
echo "2. Configure k8sgpt with your key:"
echo "   k8sgpt auth add openai --apikey YOUR_API_KEY"
echo ""
echo "3. Set as default backend:"
echo "   k8sgpt auth default openai"
echo ""
echo "============================================================================"
echo "Option 2: Azure OpenAI (Enterprise)"
echo "============================================================================"
echo ""
echo "1. Set up Azure OpenAI service in Azure Portal"
echo ""
echo "2. Configure k8sgpt:"
echo "   k8sgpt auth add azureopenai \\"
echo "     --baseurl https://your-resource.openai.azure.com/ \\"
echo "     --apikey YOUR_AZURE_KEY \\"
echo "     --engine your-deployment-name"
echo ""
echo "============================================================================"
echo "Option 3: Local Model with Ollama (Free - Best for Learning/Development)"
echo "============================================================================"
echo ""
echo "1. Install Ollama on a machine (can be this one or a server):"
echo "   curl https://ollama.ai/install.sh | sh"
echo ""
echo "2. Pull a model (e.g., Mistral or Llama2):"
echo "   ollama pull mistral"
echo ""
echo "3. Configure k8sgpt to use Ollama:"
echo "   k8sgpt auth add ollama --model mistral --baseurl http://localhost:11434/v1"
echo ""
echo "   If Ollama is on a different machine:"
echo "   k8sgpt auth add ollama --model mistral --baseurl http://<ollama-host>:11434/v1"
echo ""
echo "4. Set as default:"
echo "   k8sgpt auth default ollama"
echo ""
echo "============================================================================"
echo "Basic Usage:"
echo "============================================================================"
echo ""
echo "Analyze your cluster for issues:"
echo "  k8sgpt analyze"
echo ""
echo "Get detailed explanations of problems:"
echo "  k8sgpt analyze --explain"
echo ""
echo "Filter by specific resource types:"
echo "  k8sgpt analyze --filter Pod"
echo "  k8sgpt analyze --filter Deployment,Service"
echo ""
echo "Analyze a specific namespace:"
echo "  k8sgpt analyze --namespace kube-system --explain"
echo ""
echo "Get output in different formats:"
echo "  k8sgpt analyze --explain --output json"
echo ""
echo "============================================================================"
echo "Advanced Usage:"
echo "============================================================================"
echo ""
echo "Install k8sgpt operator (for continuous monitoring):"
echo "  k8sgpt generate"
echo "  kubectl apply -f k8sgpt-deployment.yaml"
echo ""
echo "List available analyzers:"
echo "  k8sgpt filters list"
echo ""
echo "Add custom filters:"
echo "  k8sgpt filters add Service,Ingress"
echo ""
echo "Remove filters:"
echo "  k8sgpt filters remove Service"
echo ""
echo "View configured backends:"
echo "  k8sgpt auth list"
echo ""
echo "============================================================================"
echo "Example Output:"
echo "============================================================================"
echo ""
echo "When you run 'k8sgpt analyze --explain', you might see:"
echo ""
echo "0: Pod default/my-app-7d4f9c8b-xkj2l"
echo "- Error: CrashLoopBackOff"
echo "- AI Analysis: The pod is failing to start because the container image"
echo "  'my-app:v2.0' cannot be found. This typically indicates:"
echo "  1. The image doesn't exist in the registry"
echo "  2. The image tag is incorrect"
echo "  3. Authentication to the registry failed"
echo ""
echo "- Recommended Fix:"
echo "  1. Verify the image exists: docker pull my-app:v2.0"
echo "  2. Check imagePullSecrets if using a private registry"
echo "  3. Review deployment YAML for correct image tag"
echo ""
echo "============================================================================"
echo "Integration with kubectl:"
echo "============================================================================"
echo ""
echo "Use k8sgpt as part of your debugging workflow:"
echo ""
echo "1. Notice a problem:"
echo "   kubectl get pods"
echo "   # See pod in CrashLoopBackOff"
echo ""
echo "2. Get AI explanation:"
echo "   k8sgpt analyze --explain --filter Pod"
echo ""
echo "3. Apply the suggested fix"
echo ""
echo "4. Verify:"
echo "   kubectl get pods"
echo ""
echo "============================================================================"
echo "Analyzers Available:"
echo "============================================================================"
echo ""
echo "k8sgpt can analyze these Kubernetes resources:"
echo ""
echo "  - Pod              (failing pods, crashes, evictions)"
echo "  - Deployment       (replica mismatches, rollout issues)"
echo "  - StatefulSet      (persistent volume issues)"
echo "  - Service          (endpoint problems, selector mismatches)"
echo "  - Ingress          (configuration errors)"
echo "  - PersistentVolume (binding failures)"
echo "  - NetworkPolicy    (connectivity issues)"
echo "  - Node             (resource pressure, conditions)"
echo "  - CronJob          (failed jobs)"
echo "  - ReplicaSet       (scaling issues)"
echo ""
echo "============================================================================"
echo "Tips for Best Results:"
echo "============================================================================"
echo ""
echo "1. Start with 'k8sgpt analyze' to get a quick overview"
echo "2. Add '--explain' when you need detailed analysis"
echo "3. Use '--filter' to focus on specific resource types"
echo "4. Run regularly to catch issues early"
echo "5. Use '--output json' for integration with other tools"
echo "6. Combine with 'kubectl describe' for full context"
echo ""
echo "============================================================================"
echo "Troubleshooting:"
echo "============================================================================"
echo ""
echo "If you get 'No auth provider found':"
echo "  k8sgpt auth add <provider> --apikey <your-key>"
echo "  k8sgpt auth default <provider>"
echo ""
echo "If you get 'No analyzers found':"
echo "  k8sgpt filters add Pod,Deployment,Service"
echo ""
echo "If analysis takes too long:"
echo "  - Use more specific filters"
echo "  - Analyze one namespace at a time"
echo "  - Consider using a faster AI backend"
echo ""
echo "Check current configuration:"
echo "  k8sgpt auth list"
echo "  k8sgpt filters list"
echo ""
echo "For more help:"
echo "  k8sgpt --help"
echo "  k8sgpt analyze --help"
echo ""
echo "============================================================================"
echo "Learn more: https://k8sgpt.ai/"
echo "============================================================================"
