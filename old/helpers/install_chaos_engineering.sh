#!/bin/bash

# ====================================================================================
#
#          Install Chaos Engineering Tools (install_chaos_engineering.sh)
#
# ====================================================================================
#
#  Purpose:
#  --------
#  Installs Chaos Mesh, a CNCF chaos engineering platform for Kubernetes. Chaos
#  engineering is the discipline of experimenting on distributed systems to build
#  confidence in their ability to withstand turbulent conditions.
#
#  Tutorial Goal:
#  --------------
#  This script teaches chaos engineering concepts while installing the tools to
#  practice them. You'll learn why deliberately breaking things is a critical part
#  of building reliable systems.
#
#  What is Chaos Engineering?:
#  ---------------------------
#  Chaos engineering is the practice of intentionally injecting failures into your
#  system to test its resilience. The philosophy comes from Netflix, who pioneered
#  it with their "Chaos Monkey" tool.
#
#  The core idea: if you're going to have failures (and you will), it's better to
#  cause them deliberately in a controlled way during development, rather than
#  discovering your system's weaknesses during a production incident at 3 AM.
#
#  What Chaos Mesh Does:
#  ----------------------
#  Chaos Mesh is a CNCF project that provides a comprehensive chaos engineering
#  platform for Kubernetes. It can simulate:
#
#  1. Pod Failures - Kill pods randomly or based on criteria
#  2. Network Chaos - Add latency, packet loss, bandwidth limits, network partitions
#  3. Stress Testing - CPU/memory pressure on pods
#  4. I/O Chaos - Simulate slow disks, read/write errors
#  5. Time Chaos - Shift system time to test time-sensitive code
#  6. Kernel Chaos - Inject kernel-level faults
#
#  Why Chaos Mesh vs Older Tools (kube-monkey)?:
#  ----------------------------------------------
#  - Modern: Active development, CNCF project
#  - Comprehensive: Many failure types, not just pod killing
#  - Safe: Fine-grained control over blast radius
#  - Observable: Built-in monitoring and metrics
#  - User-friendly: Web UI + kubectl plugin
#  - ARM64: Full support for embedded platforms
#
#  Learning Value:
#  ---------------
#  For embedded GPU workloads, chaos engineering helps you understand:
#  - What happens when a GPU node fails during training?
#  - How does your job queue handle network partitions?
#  - Can your monitoring detect partial failures?
#  - Do your retry mechanisms work correctly?
#
#  This aligns perfectly with this repo's goal: hands-on learning of modern
#  cloud-native workflows through experimentation.
#
#  Installation Method:
#  --------------------
#  Chaos Mesh is installed via Helm (requires helm to be installed first).
#  It runs as a set of controllers in your cluster and provides a web dashboard
#  for designing and monitoring chaos experiments.
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
print_success "Target user: $TARGET_USER"

# Verify kubectl is installed and configured
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please run the k8s setup scripts first."
    exit 1
fi
print_success "kubectl is installed."

# Verify cluster access
if ! sudo -u "$TARGET_USER" kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster."
    print_error "Ensure you have a running cluster and kubeconfig is configured."
    exit 1
fi
print_success "Connected to Kubernetes cluster."

# Verify Helm is installed
if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed."
    print_error "Please run 'common/helpers/install_k8s_tools.sh' first."
    exit 1
fi
print_success "Helm is installed."

# --- Important Notice About Chaos Engineering ---

print_border "IMPORTANT: Understanding Chaos Engineering"
echo ""
echo -e "${C_YELLOW}Chaos engineering intentionally breaks things.${C_RESET}"
echo ""
echo "This is powerful for learning, but requires caution:"
echo ""
echo "  ✓ Great for: Testing resilience, learning k8s behavior"
echo "  ✗ Not for: Production clusters (until you know what you're doing)"
echo ""
echo "Chaos Mesh will be installed to your cluster and can:"
echo "  - Kill pods"
echo "  - Inject network latency/packet loss"
echo "  - Cause CPU/memory stress"
echo "  - Simulate disk failures"
echo ""
echo "You maintain full control - chaos experiments are explicitly triggered."
echo ""
read -p "Continue with installation? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Installation cancelled."
    exit 0
fi

# --- Part 1: Add Chaos Mesh Helm Repository ---

print_border "Step 1: Adding Chaos Mesh Helm Repository"

# --- Tutorial: Helm Repositories ---
# Helm charts are distributed through repositories, similar to package managers
# like apt or yum. The Chaos Mesh project maintains an official Helm repository
# with stable releases. Adding the repository allows helm to find and install
# Chaos Mesh.
# ---

print_info "Adding Chaos Mesh Helm repository..."
sudo -u "$TARGET_USER" helm repo add chaos-mesh https://charts.chaos-mesh.org

print_info "Updating Helm repositories..."
sudo -u "$TARGET_USER" helm repo update

print_success "Chaos Mesh Helm repository added."

# --- Part 2: Install Chaos Mesh ---

print_border "Step 2: Installing Chaos Mesh to Kubernetes Cluster"

# --- Tutorial: What Gets Installed? ---
# Chaos Mesh installs several components into your cluster:
# 1. Custom Resource Definitions (CRDs) - Define new k8s resources for chaos experiments
# 2. Controllers - Watch for chaos experiments and execute them
# 3. Admission Webhooks - Validate and mutate chaos experiment resources
# 4. Dashboard - Web UI for designing and monitoring experiments
#
# These components run in a dedicated 'chaos-mesh' namespace to isolate them
# from your workloads. The installation takes 1-2 minutes as Helm downloads
# container images and initializes the controllers.
# ---

print_info "Creating chaos-mesh namespace..."
sudo -u "$TARGET_USER" kubectl create namespace chaos-mesh --dry-run=client -o yaml | sudo -u "$TARGET_USER" kubectl apply -f -

print_info "Installing Chaos Mesh via Helm (this may take a few minutes)..."
print_info "Installing components: CRDs, controllers, admission webhooks, dashboard..."

# Install Chaos Mesh with dashboard enabled
sudo -u "$TARGET_USER" helm install chaos-mesh chaos-mesh/chaos-mesh \
    --namespace=chaos-mesh \
    --set dashboard.create=true \
    --set dashboard.securityMode=false \
    --wait

if [ $? -ne 0 ]; then
    print_error "Chaos Mesh installation failed."
    print_error "Check cluster resources and try again."
    exit 1
fi

print_success "Chaos Mesh installed successfully."

# --- Part 3: Verify Installation ---

print_border "Step 3: Verifying Installation"

print_info "Checking Chaos Mesh pods..."
sudo -u "$TARGET_USER" kubectl get pods -n chaos-mesh

print_info "Waiting for all Chaos Mesh pods to be ready..."
sudo -u "$TARGET_USER" kubectl wait --for=condition=ready pod \
    --all \
    -n chaos-mesh \
    --timeout=300s

if [ $? -eq 0 ]; then
    print_success "All Chaos Mesh components are running."
else
    print_warning "Some components may still be starting. Check with: kubectl get pods -n chaos-mesh"
fi

# --- Part 4: Access Dashboard ---

print_border "Step 4: Dashboard Access Information"

# --- Tutorial: Accessing the Dashboard ---
# Chaos Mesh includes a web-based dashboard for designing and monitoring chaos
# experiments. Since this is likely a headless cluster, we'll show how to access
# it from your laptop using kubectl port-forward.
# ---

DASHBOARD_SERVICE=$(sudo -u "$TARGET_USER" kubectl get svc -n chaos-mesh -l app.kubernetes.io/component=dashboard -o jsonpath='{.items[0].metadata.name}')

if [ -n "$DASHBOARD_SERVICE" ]; then
    print_success "Dashboard service found: $DASHBOARD_SERVICE"
    echo ""
    echo -e "${C_BLUE}To access the Chaos Mesh dashboard:${C_RESET}"
    echo ""
    echo "  1. From your laptop (not the cluster node), run:"
    echo "     kubectl port-forward -n chaos-mesh svc/$DASHBOARD_SERVICE 2333:2333"
    echo ""
    echo "  2. Open browser to: http://localhost:2333"
    echo ""
else
    print_warning "Could not find dashboard service. It may still be initializing."
fi

# --- Part 5: Usage Examples ---

print_border "Chaos Engineering Quick Start"
echo ""
echo -e "${C_GREEN}Chaos Mesh is now installed!${C_RESET}"
echo ""
echo -e "${C_BLUE}Example Chaos Experiments:${C_RESET}"
echo ""
echo "1. Kill a random pod in a namespace:"
cat << 'EOF'

cat <<YAML | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-example
  namespace: default
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - default
  scheduler:
    cron: '@every 2m'
YAML
EOF
echo ""
echo "2. Inject network latency:"
cat << 'EOF'

cat <<YAML | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay
  namespace: default
spec:
  action: delay
  mode: one
  selector:
    namespaces:
      - default
  delay:
    latency: "100ms"
    correlation: "100"
  duration: "1m"
YAML
EOF
echo ""
echo "3. Create CPU stress:"
cat << 'EOF'

cat <<YAML | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress
  namespace: default
spec:
  mode: one
  selector:
    namespaces:
      - default
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "30s"
YAML
EOF
echo ""
echo -e "${C_YELLOW}List active experiments:${C_RESET}"
echo "  kubectl get podchaos,networkchaos,stresschaos -A"
echo ""
echo -e "${C_YELLOW}Stop an experiment:${C_RESET}"
echo "  kubectl delete podchaos pod-kill-example"
echo ""
echo -e "${C_MAGENTA}Best Practices:${C_RESET}"
echo "  1. Start with short durations (30s-1m)"
echo "  2. Target specific namespaces, not the whole cluster"
echo "  3. Monitor with k9s or the dashboard during experiments"
echo "  4. Document what you expect to happen vs what actually happens"
echo "  5. Build up from simple (pod kill) to complex (network partition)"
echo ""
echo -e "${C_INFO}Documentation:${C_RESET}"
echo "  - Chaos Mesh docs: https://chaos-mesh.org/docs/"
echo "  - Experiment types: https://chaos-mesh.org/docs/simulate-pod-chaos-on-kubernetes/"
echo "  - Best practices: https://chaos-mesh.org/docs/production-recommendations/"
echo ""
echo -e "${C_GREEN}Happy chaos engineering! Break things to make them stronger.${C_RESET}"
echo ""
