#!/bin/bash

# ============================================================================
#
#                    Install Gitea (install_gitea.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  Installs Gitea, a lightweight, self-hosted Git service. This provides a
#  private, local alternative to GitHub or GitLab for source code management.
#
#  Tutorial Goal:
#  --------------
#  You will learn how to deploy a multi-service application using Docker
#  Compose. We will create a `docker-compose.yml` file to define and link two
#  services: the Gitea web application and its PostgreSQL database. This
#  approach demonstrates a declarative, repeatable, and isolated way to manage
#  application stacks, which is a core concept in modern DevOps.
#
#  Prerequisites:
#  --------------
#  - Completed: Base OS setup on the node that will host Gitea.
#  - Hardware: A node with at least 2GB RAM and 10GB disk space recommended.
#  - Network: SSH access and an active internet connection.
#  - Time: ~15 minutes.
#
#  Workflow:
#  ---------
#  Run this script on a single, designated node. After the script completes,
#  you will need to access the Gitea web UI to perform the final configuration.
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

# Install Docker
if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing now..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl enable --now docker
    print_success "Docker installed and started."
else
    print_success "Docker is already installed."
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    print_info "Docker Compose not found. Installing now..."
    sudo apt-get update
    sudo apt-get install -y docker-compose
    print_success "Docker Compose installed."
else
    print_success "Docker Compose is already installed."
fi

# ============================================================================
#                  STEP 1: CREATE GITEA CONFIGURATION
# ============================================================================

print_border "Step 1: Create Gitea Configuration and Directories"

readonly GITEA_BASE_PATH="/opt/gitea"
readonly GITEA_COMPOSE_FILE="$GITEA_BASE_PATH/docker-compose.yml"

print_info "Creating Gitea directories in $GITEA_BASE_PATH..."
sudo mkdir -p "$GITEA_BASE_PATH/data" "$GITEA_BASE_PATH/postgres"
sudo chown -R 1000:1000 "$GITEA_BASE_PATH"
print_success "Gitea directories created."

# --- Tutorial: Docker Compose File ---
# This YAML file declaratively defines our application stack.
# `services`: Defines the containers to run (gitea, db).
# `volumes`: Defines persistent storage, linking host directories to container
#            directories so data survives container restarts.
# `environment`: Sets environment variables, used here to pass database
#                credentials to the Gitea container securely.
# `networks`: Creates a private network for the containers to communicate.
# ---
print_info "Creating Docker Compose file at $GITEA_COMPOSE_FILE..."
cat <<EOF | sudo tee "$GITEA_COMPOSE_FILE" > /dev/null
version: "3"

networks:
  gitea:
    external: false

services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=db:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=gitea
    restart: always
    networks:
      - gitea
    volumes:
      - ./data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000" # Web UI
      - "222:22"    # SSH Git access
    depends_on:
      - db

  db:
    image: postgres:15
    container_name: gitea-db
    restart: always
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=gitea
      - POSTGRES_DB=gitea
    networks:
      - gitea
    volumes:
      - ./postgres:/var/lib/postgresql/data
EOF
print_success "Docker Compose file created."

# ============================================================================
#                       STEP 2: LAUNCH GITEA
# ============================================================================

print_border "Step 2: Launch Gitea using Docker Compose"

print_info "Starting Gitea and PostgreSQL containers..."
cd "$GITEA_BASE_PATH"
sudo docker-compose up -d

if [ $? -eq 0 ]; then
    print_success "Gitea services started successfully."
else
    print_error "Failed to start Gitea services. Check 'docker-compose logs' in '$GITEA_BASE_PATH'."
    exit 1
fi

# ============================================================================
#                           FINAL INSTRUCTIONS
# ============================================================================

print_border "Setup Complete"
print_success "Gitea is running!"

readonly HOST_IP=$(hostname -I | awk '{print $1}')
echo ""
print_warning "ACTION REQUIRED: Complete the Gitea setup in your web browser."
echo ""
echo "1. Open your web browser and navigate to:"
echo "   http://${HOST_IP}:3000"
echo ""
echo "2. On the initial configuration page, verify the following settings:"
echo "   - Database Type:       PostgreSQL"
echo "   - Host:                db:5432"
echo "   - Database Name:       gitea"
echo "   - User:                gitea"
echo "   - Gitea Base URL:      http://${HOST_IP}:3000/"
echo ""
echo "3. Complete the rest of the form to create your admin account."
echo "4. Click 'Install Gitea'."
