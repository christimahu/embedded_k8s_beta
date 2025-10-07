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
#     Example: kubectl-ai "list all failed pods from the last hour"
#     Provider: Google Cloud (via github.com/GoogleCloudPlatform/kubectl-ai)
#
#  2. k8sgpt - AI-powered cluster diagnostics
#     Why: Analyzes your cluster for issues and provides AI-generated explanations
#          and remediation steps. It's like having an SRE assistant that understands
#          your cluster state and can suggest fixes in plain English.
#     Example: k8sgpt analyze --explain
#     Provider: CNCF Sandbox project, supports multiple AI backends
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
#  This aligns with the repo's goal of encouraging experimentation and learning.
#  These tools lower the barrier to entry while still teaching best practices.
#
#  IMPORTANT - API Keys Required:
#  ------------------------------
#  Both tools require API access to large language models. You'll need to configure:
#  - kubectl-ai: OpenAI API key or compatible endpoint
#  - k8sgpt: OpenAI, Azure OpenAI, or local models (Ollama)
#
#  API calls cost money. Typical usage for a small cluster: $5-20/month.
#  Consider using local models with Ollama for cost-free operation.
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

# Verify kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the k8s setup scripts first."
    exit 1
fi
print_success "kubectl is installed."

# --- Important Notice About AI Services ---

print_border "IMPORTANT: AI Service Requirements"
echo ""
echo -e "${C_YELLOW}These tools require API access to AI language models.${C_RESET}"
echo ""
echo "Options:"
echo "  1. OpenAI API (recommended, requires API key, costs money)"
echo "  2. Azure OpenAI (enterprise option)"
echo "  3. Local models via Ollama (free, but requires GPU/significant RAM)"
echo ""
echo "Estimated costs for OpenAI:"
echo "  - Light usage:  ~\$5-10/month"
echo "  - Heavy usage:  ~\$20-50/month"
echo ""
echo "You'll need to configure API keys after installation."
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
# kubectl-ai is a kubectl plugin that uses OpenAI's GPT models to translate
# natural language queries into kubectl commands. Instead of remembering complex
# kubectl syntax, you describe what you want in plain English.
#
# How it works:
# 1. You type a question in natural language
# 2. kubectl-ai sends it to an LLM (with cluster context if needed)
# 3. The LLM generates the appropriate kubectl command
# 4. You review and execute the command
#
# This is particularly valuable when:
# - Learning Kubernetes (teaches correct syntax)
# - Doing complex queries (combining multiple filters)
# - Troubleshooting under time pressure
#
# Example queries:
#   kubectl-ai "show me all pods in crashloopbackoff"
#   kubectl-ai "find pods using more than 500Mi memory"
#   kubectl-ai "get events from the last 10 minutes sorted by time"
#
# Security: You review commands before execution, so there's no risk of
# AI-generated commands running automatically.
# See: https://github.com/GoogleCloudPlatform/kubectl-ai
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
sudo -u "$TARGET_USER" bash -c "go install github.com/GoogleCloudPlatform/kubectl-ai@latest"

# Add Go bin to PATH if not already there
GO_BIN_PATH="$TARGET_HOME/go/bin"
if [ -d "$GO_BIN_PATH" ]; then
    if ! grep -q "$GO_BIN_PATH" "$TARGET_HOME/.bashrc"; then
        echo "" >> "$TARGET_HOME/.bashrc"
        echo "# Go binaries" >> "$TARGET_HOME/.bashrc"
        echo "export PATH=\"\$PATH:$GO_BIN_PATH\"" >> "$TARGET_HOME/.bashrc"
        print_success "Added Go bin directory to PATH."
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
# k8sgpt is a CNCF Sandbox project that analyzes your Kubernetes cluster for
# problems and uses AI to explain them in human-readable language. It's like
# having an SRE assistant that:
# - Scans your cluster for issues
# - Identifies problems (crashlooping pods, resource constraints, misconfigurations)
# - Explains WHY the problem is happening
# - Suggests specific remediation steps
#
# Unlike traditional monitoring (which just alerts), k8sgpt provides CONTEXT.
# For example, instead of "Pod is CrashLooping", it might say:
#   "Pod 'my-app-xyz' is CrashLooping because the container is trying to bind
#    to port 80, but the user doesn't have permission. Consider running as root
#    or using a port above 1024."
#
# k8sgpt uses pattern recognition across thousands of common k8s issues. It can
# catch problems that simple monitoring rules miss.
#
# Particularly useful for:
# - New k8s users (explains error messages)
# - Complex deployments (connects multiple failure points)
# - Post-mortems (understands what went wrong)
#
# Privacy: k8sgpt can be configured to anonymize cluster data before sending
# to AI services, or you can use local models for full data privacy.
# See: https://k8sgpt.ai/
# ---

print_info "Installing k8sgpt from GitHub releases..."

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        K8SGPT_ARCH="amd64"
        ;;
    aarch64|arm64)
        K8SGPT_ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

K8SGPT_VERSION="v0.3.31"
K8SGPT_URL="https://github.com/k8sgpt-ai/k8sgpt/releases/download/${K8SGPT_VERSION}/k8sgpt_${K8SGPT_VERSION#v}_linux_${K8SGPT_ARCH}.tar.gz"

print_info "Downloading k8sgpt ${K8SGPT_VERSION} for ${K8SGPT_ARCH}..."
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
echo -e "${C_BLUE}kubectl-ai Configuration:${C_RESET}"
echo "  1. Get an OpenAI API key: https://platform.openai.com/api-keys"
echo "  2. Set environment variable:"
echo "     export OPENAI_API_KEY='your-key-here'"
echo "  3. Add to ~/.bashrc to persist:"
echo "     echo 'export OPENAI_API_KEY=\"your-key-here\"' >> ~/.bashrc"
echo ""
echo -e "${C_BLUE}k8sgpt Configuration:${C_RESET}"
echo "  1. Authenticate k8sgpt with your AI provider:"
echo "     k8sgpt auth add openai --apikey YOUR_API_KEY"
echo ""
echo "  2. Or use local models (free, requires GPU):"
echo "     # Install Ollama first"
echo "     curl https://ollama.ai/install.sh | sh"
echo "     ollama pull llama2"
echo "     k8sgpt auth add ollama --apikey dummy --baseurl http://localhost:11434/v1"
echo ""
echo "  3. Test k8sgpt:"
echo "     k8sgpt analyze --explain"
echo ""
echo -e "${C_MAGENTA}Privacy Note:${C_RESET}"
echo "  k8sgpt can anonymize data before sending to AI services:"
echo "    k8sgpt analyze --explain --anonymize"
echo ""

# --- Final Instructions ---

print_border "Installation Complete"
echo ""
echo -e "${C_GREEN}AI-powered Kubernetes tools installed successfully!${C_RESET}"
echo ""
echo -e "${C_BLUE}Installed Tools:${C_RESET}"
echo "  ✓ kubectl-ai  - Natural language kubectl interface"
echo "  ✓ k8sgpt      - AI cluster diagnostics"
echo ""
echo -e "${C_YELLOW}Getting Started:${C_RESET}"
echo ""
echo "  # FIRST: Configure API keys (see instructions above)"
echo ""
echo "  # Then, start a new terminal or run:"
echo "  source ~/.bashrc"
echo ""
echo "  # Try kubectl-ai:"
echo "  kubectl-ai \"show me all pods that are not running\""
echo ""
echo "  # Try k8sgpt:"
echo "  k8sgpt analyze --explain"
echo ""
echo -e "${C_INFO}Documentation:${C_RESET}"
echo "  - kubectl-ai: https://github.com/GoogleCloudPlatform/kubectl-ai"
echo "  - k8sgpt: https://docs.k8sgpt.ai/"
echo ""
echo -e "${C_WARNING}Remember: API calls cost money. Monitor your usage!${C_RESET}"
echo ""
