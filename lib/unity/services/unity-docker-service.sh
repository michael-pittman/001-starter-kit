#!/usr/bin/env bash
# =============================================================================
# Unity Docker Service - Unified Container Operations & Orchestration
# Consolidates all Docker-related functionality from GeuseMaker into a unified service
# Compatible with bash 3.x+ and follows GeuseMaker architecture patterns
# =============================================================================

# Prevent multiple sourcing
[ -n "${_UNITY_DOCKER_SERVICE_SH_LOADED:-}" ] && return 0
declare -gr _UNITY_DOCKER_SERVICE_SH_LOADED=1

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies using the unified library loader
source "$SCRIPT_DIR/../../utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Initialize script with required modules
initialize_script "unity-docker-service" \
    "core/logging" \
    "core/errors" \
    "core/registry"

# Load optional modules with fallback
safe_source "modules/application/docker_manager.sh" false "Docker Manager Module"
safe_source "modules/application/health_monitor.sh" false "Health Monitor Module"
safe_source "modules/monitoring/log_aggregation.sh" false "Log Aggregation Module"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Service constants
readonly DOCKER_SERVICE_VERSION="2.0.0"
readonly DOCKER_COMPOSE_MIN_VERSION="2.0.0"
readonly NVIDIA_RUNTIME_NAME="nvidia"

# Container lifecycle states
readonly CONTAINER_STATE_CREATED="created"
readonly CONTAINER_STATE_RUNNING="running"
readonly CONTAINER_STATE_PAUSED="paused"
readonly CONTAINER_STATE_RESTARTING="restarting"
readonly CONTAINER_STATE_REMOVING="removing"
readonly CONTAINER_STATE_EXITED="exited"
readonly CONTAINER_STATE_DEAD="dead"

# Health check states
readonly HEALTH_STATE_HEALTHY="healthy"
readonly HEALTH_STATE_UNHEALTHY="unhealthy"
readonly HEALTH_STATE_STARTING="starting"
readonly HEALTH_STATE_NO_HEALTHCHECK="none"

# Configuration defaults
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-100m}"
DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"
DOCKER_HEALTH_CHECK_INTERVAL="${DOCKER_HEALTH_CHECK_INTERVAL:-30s}"
DOCKER_HEALTH_CHECK_TIMEOUT="${DOCKER_HEALTH_CHECK_TIMEOUT:-10s}"
DOCKER_HEALTH_CHECK_RETRIES="${DOCKER_HEALTH_CHECK_RETRIES:-3}"

# Monitoring configuration
DOCKER_MONITORING_ENABLED="${DOCKER_MONITORING_ENABLED:-true}"
DOCKER_LOG_AGGREGATION_ENABLED="${DOCKER_LOG_AGGREGATION_ENABLED:-true}"
DOCKER_AUTO_RECOVERY_ENABLED="${DOCKER_AUTO_RECOVERY_ENABLED:-true}"

# Storage paths
DOCKER_SHARED_STORAGE="${DOCKER_SHARED_STORAGE:-/shared}"
DOCKER_LOG_DIR="${DOCKER_LOG_DIR:-$DOCKER_SHARED_STORAGE/logs/docker}"
DOCKER_METRICS_DIR="${DOCKER_METRICS_DIR:-$DOCKER_SHARED_STORAGE/metrics}"

# Initialize storage directories
mkdir -p "$DOCKER_LOG_DIR" "$DOCKER_METRICS_DIR"

# =============================================================================
# DOCKER INSTALLATION AND SETUP
# =============================================================================

# Install and configure Docker with GeuseMaker optimizations
docker_install() {
    local skip_install="${1:-false}"
    local enable_gpu="${2:-auto}"
    
    log_info "Installing and configuring Docker environment" "DOCKER"
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker is already installed" "DOCKER"
        
        # Validate Docker daemon is running
        if ! docker info >/dev/null 2>&1; then
            log_info "Starting Docker daemon..." "DOCKER"
            sudo systemctl start docker || {
                error_docker_daemon_failed "Failed to start Docker daemon"
                return $ERROR_DEPLOYMENT_FAILED
            }
        fi
        
        if [ "$skip_install" = "true" ]; then
            return 0
        fi
    else
        log_info "Docker not found, installing..." "DOCKER"
        docker_install_engine
    fi
    
    # Configure Docker daemon with optimizations
    docker_configure_daemon
    
    # Setup user permissions
    docker_setup_permissions
    
    # Install Docker Compose
    docker_install_compose
    
    # Setup GPU support if requested
    if [ "$enable_gpu" = "true" ] || ([ "$enable_gpu" = "auto" ] && docker_has_gpu); then
        docker_setup_nvidia_runtime
    fi
    
    # Validate installation
    docker_validate_installation
    
    log_info "Docker setup completed successfully" "DOCKER"
}

# Install Docker Engine using distribution-specific methods
docker_install_engine() {
    log_info "Installing Docker Engine..." "DOCKER"
    
    # Detect distribution
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    case "$distro" in
        ubuntu|debian)
            docker_install_ubuntu
            ;;
        amzn)
            docker_install_amazon_linux
            ;;
        rhel|centos|fedora)
            docker_install_rhel
            ;;
        *)
            docker_install_generic
            ;;
    esac
}

# Install Docker on Ubuntu/Debian
docker_install_ubuntu() {
    log_info "Installing Docker on Ubuntu/Debian..." "DOCKER"
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Install Docker on Amazon Linux
docker_install_amazon_linux() {
    log_info "Installing Docker on Amazon Linux..." "DOCKER"
    
    # Update system
    sudo yum update -y
    
    # Install Docker
    sudo yum install -y docker
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
}

# Install Docker on RHEL/CentOS/Fedora
docker_install_rhel() {
    log_info "Installing Docker on RHEL-based system..." "DOCKER"
    
    # Remove old versions
    sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    
    # Install yum-utils
    sudo yum install -y yum-utils
    
    # Set up repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker Engine
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
}

# Generic Docker installation (fallback)
docker_install_generic() {
    log_info "Installing Docker using convenience script..." "DOCKER"
    
    # Download and run Docker convenience script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
}

# Setup user permissions for Docker
docker_setup_permissions() {
    log_info "Setting up Docker permissions..." "DOCKER"
    
    # Check if ubuntu user exists
    if id ubuntu >/dev/null 2>&1; then
        # Add ubuntu user to docker group
        if ! groups ubuntu | grep -q docker; then
            sudo usermod -aG docker ubuntu
            log_info "Added ubuntu user to docker group" "DOCKER"
        fi
    fi
    
    # Check current user
    local current_user=$(whoami)
    if [ "$current_user" != "root" ]; then
        if ! groups "$current_user" | grep -q docker; then
            sudo usermod -aG docker "$current_user"
            log_info "Added $current_user to docker group" "DOCKER"
        fi
    fi
}

# Install Docker Compose
docker_install_compose() {
    log_info "Installing Docker Compose..." "DOCKER"
    
    # Check if Docker Compose plugin is available
    if docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose plugin is already available" "DOCKER"
        return 0
    fi
    
    # Check if standalone docker-compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        log_info "Docker Compose standalone is already available" "DOCKER"
        return 0
    fi
    
    # Install Docker Compose plugin
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' || echo "v2.24.5")
    
    if [ -z "$compose_version" ]; then
        compose_version="v2.24.5"  # Fallback version
    fi
    
    # Create plugins directory
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    
    # Download Docker Compose plugin
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) 
            log_warn "Unsupported architecture: $arch" "DOCKER"
            return 1
            ;;
    esac
    
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${arch}"
    
    sudo curl -L "$compose_url" -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    
    # Create symlink for backward compatibility
    sudo ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    
    log_info "Docker Compose installed successfully" "DOCKER"
}

# Validate Docker installation
docker_validate_installation() {
    log_info "Validating Docker installation..." "DOCKER"
    
    # Test Docker info
    if ! docker info >/dev/null 2>&1; then
        error_docker_daemon_failed "Docker info command failed"
        return $ERROR_VALIDATION_FAILED
    fi
    
    # Test Docker run
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        error_docker_config_invalid "Docker run test failed"
        return $ERROR_VALIDATION_FAILED
    fi
    
    # Clean up test image
    docker rmi hello-world >/dev/null 2>&1 || true
    
    # Test Docker Compose
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose version >/dev/null 2>&1; then
        error_docker_config_invalid "Docker Compose not available"
        return $ERROR_VALIDATION_FAILED
    fi
    
    log_info "Docker installation validated successfully" "DOCKER"
}

# Install NVIDIA Container Toolkit
docker_install_nvidia_toolkit() {
    log_info "Installing NVIDIA Container Toolkit..." "DOCKER"
    
    # Detect distribution
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    case "$distro" in
        ubuntu|debian)
            docker_install_nvidia_toolkit_ubuntu
            ;;
        amzn|rhel|centos|fedora)
            docker_install_nvidia_toolkit_rhel
            ;;
        *)
            docker_install_nvidia_toolkit_generic
            ;;
    esac
}

# Install NVIDIA Container Toolkit on Ubuntu/Debian
docker_install_nvidia_toolkit_ubuntu() {
    # Setup the package repository
    local distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Install the toolkit
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
}

# Install NVIDIA Container Toolkit on RHEL-based systems
docker_install_nvidia_toolkit_rhel() {
    # Setup the package repository
    local distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | \
        sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    
    # Install the toolkit
    sudo yum install -y nvidia-container-toolkit
}

# Generic NVIDIA Container Toolkit installation
docker_install_nvidia_toolkit_generic() {
    log_info "Installing NVIDIA Container Toolkit using generic method..." "DOCKER"
    
    # Download and install using tarball
    local toolkit_version="1.14.3"
    local arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch" "DOCKER"
            return 1
            ;;
    esac
    
    local download_url="https://github.com/NVIDIA/nvidia-container-toolkit/releases/download/v${toolkit_version}/nvidia-container-toolkit_${toolkit_version}_linux_${arch}.tar.gz"
    
    # Download and extract
    curl -L "$download_url" -o /tmp/nvidia-container-toolkit.tar.gz
    sudo tar -xzf /tmp/nvidia-container-toolkit.tar.gz -C /usr/local/
    rm /tmp/nvidia-container-toolkit.tar.gz
    
    # Set up binaries
    sudo ln -sf /usr/local/nvidia-container-toolkit/nvidia-container-runtime /usr/bin/
    sudo ln -sf /usr/local/nvidia-container-toolkit/nvidia-container-runtime-hook /usr/bin/
}

# Configure Docker daemon with GeuseMaker optimizations
docker_configure_daemon() {
    log_info "Configuring Docker daemon with GeuseMaker optimizations..." "DOCKER"
    
    # Create Docker configuration directory
    sudo mkdir -p /etc/docker
    
    # Generate optimized configuration for AI workloads
    local config_file="/etc/docker/daemon.json"
    local temp_config="/tmp/docker-daemon-config-$$.json"
    
    # Detect optimal storage driver
    local storage_driver="overlay2"
    local storage_opts='["overlay2.override_kernel_check=true"]'
    
    # Generate configuration
    cat > "$temp_config" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "$DOCKER_LOG_MAX_SIZE",
        "max-file": "$DOCKER_LOG_MAX_FILE",
        "labels": "com.geusemaker.log-aggregation=enabled"
    },
    "storage-driver": "$storage_driver",
    "storage-opts": $storage_opts,
    "data-root": "$DOCKER_DATA_ROOT",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "features": {
        "buildkit": true
    },
    "default-runtime": "runc",
    "runtimes": {
        "runc": {
            "path": "runc"
        }
    },
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 5,
    "default-shm-size": "1G",
    "default-ulimits": {
        "memlock": {
            "Hard": -1,
            "Name": "memlock",
            "Soft": -1
        },
        "nofile": {
            "Hard": 1048576,
            "Name": "nofile",
            "Soft": 1048576
        }
    },
    "metrics-addr": "127.0.0.1:9323",
    "experimental": true,
    "debug": false
}
EOF
    
    # Validate JSON syntax
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json; json.load(open('$temp_config'))" || {
            error_docker_config_invalid "Generated Docker configuration has invalid JSON"
            return $ERROR_VALIDATION_FAILED
        }
    fi
    
    # Move configuration to final location
    sudo mv "$temp_config" "$config_file"
    sudo chmod 644 "$config_file"
    
    # Reload Docker daemon
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    log_info "Docker daemon configured successfully" "DOCKER"
}

# =============================================================================
# CONTAINER LIFECYCLE MANAGEMENT
# =============================================================================

# Start container with comprehensive configuration and monitoring
docker_start_container() {
    local image="$1"
    local container_name="${2:-geusemaker-$(date +%s)}"
    local options="${3:-}"
    local wait_for_health="${4:-true}"
    
    log_info "Starting container: $container_name from $image" "DOCKER"
    
    # Parse additional options
    local docker_args=()
    if [ -n "$options" ]; then
        # Simple parsing - in production, use proper argument parsing
        read -ra docker_args <<< "$options"
    fi
    
    # Add standard GeuseMaker labels and configurations
    docker_args+=(
        "--label" "com.geusemaker.managed=true"
        "--label" "com.geusemaker.service=unity-docker"
        "--label" "com.geusemaker.stack=${STACK_NAME:-unknown}"
        "--restart" "unless-stopped"
        "--log-driver" "json-file"
        "--log-opt" "max-size=$DOCKER_LOG_MAX_SIZE"
        "--log-opt" "max-file=$DOCKER_LOG_MAX_FILE"
    )
    
    # Start container
    if docker run --name "$container_name" "${docker_args[@]}" "$image"; then
        log_info "Container $container_name started successfully" "DOCKER"
        
        # Setup monitoring if enabled
        if [ "$DOCKER_MONITORING_ENABLED" = "true" ]; then
            docker_monitor_container "$container_name" &
        fi
        
        # Wait for health check if requested
        if [ "$wait_for_health" = "true" ]; then
            docker_wait_for_health "$container_name"
        fi
        
        return 0
    else
        error_docker_container_start_failed "$container_name" "Failed to start container"
        return $ERROR_DEPLOYMENT
    fi
}

# Stop container gracefully with proper cleanup
docker_stop_container() {
    local container_name="$1"
    local timeout="${2:-30}"
    local remove="${3:-false}"
    
    log_info "Stopping container: $container_name (timeout: ${timeout}s)" "DOCKER"
    
    # Check if container exists and is running
    if ! docker ps -q -f name="$container_name" | grep -q .; then
        log_info "Container $container_name is not running" "DOCKER"
        return 0
    fi
    
    # Stop container gracefully
    if docker stop --time "$timeout" "$container_name"; then
        log_info "Container $container_name stopped successfully" "DOCKER"
        
        # Remove container if requested
        if [ "$remove" = "true" ]; then
            docker rm "$container_name" >/dev/null 2>&1 || true
            log_info "Container $container_name removed" "DOCKER"
        fi
        
        return 0
    else
        log_warn "Failed to stop container $container_name gracefully, forcing..." "DOCKER"
        docker kill "$container_name" >/dev/null 2>&1 || true
        return 1
    fi
}

# Restart container with health checking
docker_restart_container() {
    local container_name="$1"
    local wait_for_health="${2:-true}"
    
    log_info "Restarting container: $container_name" "DOCKER"
    
    if docker restart "$container_name"; then
        log_info "Container $container_name restarted successfully" "DOCKER"
        
        if [ "$wait_for_health" = "true" ]; then
            docker_wait_for_health "$container_name"
        fi
        
        return 0
    else
        error_docker_container_restart_failed "$container_name" "Failed to restart container"
        return $ERROR_DEPLOYMENT
    fi
}

# Get container status with detailed information
docker_get_container_status() {
    local container_name="$1"
    local format="${2:-json}"
    
    if ! docker ps -a -q -f name="$container_name" | grep -q .; then
        case "$format" in
            "json")
                echo '{"status": "not_found", "exists": false}'
                ;;
            *)
                echo "Container $container_name not found"
                ;;
        esac
        return 1
    fi
    
    # Get container information
    local container_info
    container_info=$(docker inspect "$container_name" 2>/dev/null)
    
    if [ -z "$container_info" ]; then
        case "$format" in
            "json")
                echo '{"status": "error", "exists": true, "error": "Failed to inspect container"}'
                ;;
            *)
                echo "Error: Failed to inspect container $container_name"
                ;;
        esac
        return 1
    fi
    
    case "$format" in
        "json")
            echo "$container_info" | jq '.[0] | {
                name: .Name,
                status: .State.Status,
                health: (.State.Health.Status // "none"),
                running: .State.Running,
                pid: .State.Pid,
                started_at: .State.StartedAt,
                finished_at: .State.FinishedAt,
                exit_code: .State.ExitCode,
                image: .Config.Image,
                ports: .NetworkSettings.Ports,
                networks: .NetworkSettings.Networks,
                mounts: [.Mounts[] | {source: .Source, destination: .Destination, type: .Type}],
                labels: .Config.Labels
            }'
            ;;
        *)
            local state running health
            state=$(echo "$container_info" | jq -r '.[0].State.Status')
            running=$(echo "$container_info" | jq -r '.[0].State.Running')
            health=$(echo "$container_info" | jq -r '.[0].State.Health.Status // "none"')
            
            echo "Container $container_name:"
            echo "  Status: $state"
            echo "  Running: $running"
            echo "  Health: $health"
            ;;
    esac
}

# =============================================================================
# DOCKER COMPOSE ORCHESTRATION
# =============================================================================

# Deploy Docker Compose stack with enhanced orchestration
docker_compose_deploy() {
    local compose_file="$1"
    local env_file="${2:-}"
    local stack_name="${3:-geusemaker}"
    local services="${4:-}"
    local wait_for_health="${5:-true}"
    
    log_info "Deploying Docker Compose stack: $stack_name" "DOCKER"
    
    # Validate compose file exists
    if [ ! -f "$compose_file" ]; then
        error_docker_compose_file_not_found "$compose_file"
        return $ERROR_VALIDATION_FAILED
    fi
    
    # Build compose command
    local compose_cmd="docker compose -f $compose_file"
    
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
        log_info "Using environment file: $env_file" "DOCKER"
    fi
    
    # Set project name
    compose_cmd="$compose_cmd -p $stack_name"
    
    # Pull images first
    log_info "Pulling Docker images..." "DOCKER"
    $compose_cmd pull --ignore-buildable || log_warn "Failed to pull some images" "DOCKER"
    
    # Deploy services
    log_info "Starting services..." "DOCKER"
    if [ -n "$services" ]; then
        if $compose_cmd up -d $services; then
            log_info "Specific services deployed: $services" "DOCKER"
        else
            error_docker_compose_deploy_failed "$stack_name" "Failed to deploy specific services: $services"
            return $ERROR_DEPLOYMENT
        fi
    else
        if $compose_cmd up -d; then
            log_info "All services deployed successfully" "DOCKER"
        else
            error_docker_compose_deploy_failed "$stack_name" "Failed to deploy services"
            return $ERROR_DEPLOYMENT
        fi
    fi
    
    # Wait for services to be healthy
    if [ "$wait_for_health" = "true" ]; then
        docker_compose_wait_for_health "$compose_file" "$env_file" "$stack_name"
    fi
    
    # Setup stack monitoring
    if [ "$DOCKER_MONITORING_ENABLED" = "true" ]; then
        docker_monitor_compose_stack "$stack_name" &
    fi
    
    log_info "Docker Compose stack $stack_name deployed successfully" "DOCKER"
}

# Stop Docker Compose stack
docker_compose_stop() {
    local compose_file="$1"
    local env_file="${2:-}"
    local stack_name="${3:-geusemaker}"
    local services="${4:-}"
    local remove_volumes="${5:-false}"
    
    log_info "Stopping Docker Compose stack: $stack_name" "DOCKER"
    
    local compose_cmd="docker compose -f $compose_file"
    
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name"
    
    if [ -n "$services" ]; then
        $compose_cmd stop $services
        log_info "Specific services stopped: $services" "DOCKER"
    else
        local down_args=()
        [ "$remove_volumes" = "true" ] && down_args+=("--volumes")
        
        $compose_cmd down "${down_args[@]}"
        log_info "Stack $stack_name stopped" "DOCKER"
    fi
}

# Get Docker Compose stack status
docker_compose_status() {
    local compose_file="$1"
    local env_file="${2:-}"
    local stack_name="${3:-geusemaker}"
    local format="${4:-table}"
    
    local compose_cmd="docker compose -f $compose_file"
    
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name"
    
    case "$format" in
        "json")
            $compose_cmd ps --format json
            ;;
        *)
            $compose_cmd ps
            ;;
    esac
}

# Wait for Docker Compose services to become healthy
docker_compose_wait_for_health() {
    local compose_file="$1"
    local env_file="${2:-}"
    local stack_name="${3:-geusemaker}"
    local max_wait="${4:-300}"  # 5 minutes default
    
    log_info "Waiting for services to become healthy..." "DOCKER"
    
    local compose_cmd="docker compose -f $compose_file"
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    compose_cmd="$compose_cmd -p $stack_name"
    
    local wait_time=0
    local check_interval=10
    
    while [ $wait_time -lt $max_wait ]; do
        # Check service health
        local unhealthy_services
        unhealthy_services=$($compose_cmd ps --format json | jq -r '.[] | select(.Health != "healthy" and .Health != "" and .Health != null) | .Service' 2>/dev/null || echo "")
        
        if [ -z "$unhealthy_services" ]; then
            log_info "All services are healthy" "DOCKER"
            return 0
        fi
        
        log_info "Waiting for services to be healthy: $(echo "$unhealthy_services" | tr '\n' ' ')" "DOCKER"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    log_warn "Some services did not become healthy within ${max_wait}s" "DOCKER"
    $compose_cmd ps
    return 1
}

# =============================================================================
# HEALTH MONITORING AND AUTO-RECOVERY
# =============================================================================

# Monitor container health with auto-recovery
docker_monitor_container() {
    local container_name="$1"
    local check_interval="${2:-30}"
    local recovery_enabled="${3:-$DOCKER_AUTO_RECOVERY_ENABLED}"
    
    log_info "Starting health monitoring for container: $container_name" "DOCKER"
    
    local consecutive_failures=0
    local max_failures=3
    
    while docker ps -q -f name="$container_name" | grep -q .; do
        local health_status
        health_status=$(docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
        
        case "$health_status" in
            "healthy")
                consecutive_failures=0
                log_debug "Container $container_name is healthy" "DOCKER"
                ;;
            "unhealthy")
                consecutive_failures=$((consecutive_failures + 1))
                log_warn "Container $container_name is unhealthy (failures: $consecutive_failures)" "DOCKER"
                
                if [ "$recovery_enabled" = "true" ] && [ $consecutive_failures -ge $max_failures ]; then
                    log_info "Attempting auto-recovery for container $container_name" "DOCKER"
                    docker_restart_container "$container_name" true
                    consecutive_failures=0
                fi
                ;;
            "starting")
                log_debug "Container $container_name health check is starting" "DOCKER"
                ;;
            "none")
                # No health check defined, check if container is running
                if ! docker ps -q -f name="$container_name" | grep -q .; then
                    log_warn "Container $container_name is not running" "DOCKER"
                    break
                fi
                ;;
        esac
        
        sleep "$check_interval"
    done
    
    log_info "Health monitoring stopped for container: $container_name" "DOCKER"
}

# Monitor Docker Compose stack
docker_monitor_compose_stack() {
    local stack_name="$1"
    local check_interval="${2:-60}"
    
    log_info "Starting monitoring for Docker Compose stack: $stack_name" "DOCKER"
    
    while docker ps -q -f label="com.docker.compose.project=$stack_name" | grep -q .; do
        # Get all containers in the stack
        local containers
        containers=$(docker ps --format "{{.Names}}" -f label="com.docker.compose.project=$stack_name")
        
        if [ -n "$containers" ]; then
            echo "$containers" | while read -r container; do
                local status
                status=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
                
                if [ "$status" != "running" ]; then
                    log_warn "Stack $stack_name: Container $container is not running (status: $status)" "DOCKER"
                fi
            done
        fi
        
        sleep "$check_interval"
    done
    
    log_info "Monitoring stopped for Docker Compose stack: $stack_name" "DOCKER"
}

# Wait for container to become healthy
docker_wait_for_health() {
    local container_name="$1"
    local timeout="${2:-120}"
    
    log_info "Waiting for container $container_name to become healthy..." "DOCKER"
    
    local waited=0
    local check_interval=5
    
    while [ $waited -lt $timeout ]; do
        local health_status
        health_status=$(docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
        
        case "$health_status" in
            "healthy")
                log_info "Container $container_name is healthy" "DOCKER"
                return 0
                ;;
            "unhealthy")
                log_warn "Container $container_name is unhealthy" "DOCKER"
                return 1
                ;;
            "starting")
                log_debug "Container $container_name health check is starting..." "DOCKER"
                ;;
            "none")
                # No health check, just verify it's running
                if docker ps -q -f name="$container_name" | grep -q .; then
                    log_info "Container $container_name is running (no health check)" "DOCKER"
                    return 0
                else
                    log_warn "Container $container_name is not running" "DOCKER"
                    return 1
                fi
                ;;
        esac
        
        sleep $check_interval
        waited=$((waited + check_interval))
    done
    
    log_warn "Timeout waiting for container $container_name to become healthy" "DOCKER"
    return 1
}

# =============================================================================
# LOG AGGREGATION AND ANALYSIS
# =============================================================================

# Setup log aggregation for Docker containers
docker_setup_log_aggregation() {
    local output_dir="${1:-$DOCKER_LOG_DIR}"
    local retention_days="${2:-7}"
    
    if [ "$DOCKER_LOG_AGGREGATION_ENABLED" != "true" ]; then
        log_info "Docker log aggregation is disabled" "DOCKER"
        return 0
    fi
    
    log_info "Setting up Docker log aggregation" "DOCKER"
    
    mkdir -p "$output_dir"
    
    # Create log collection script
    cat > "$output_dir/collect-docker-logs.sh" << 'EOF'
#!/usr/bin/env bash
# Docker log collection script

set -euo pipefail

OUTPUT_DIR="$1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Collect logs from all GeuseMaker containers
docker ps --filter "label=com.geusemaker.managed=true" --format "{{.Names}}" | while read -r container; do
    if [ -n "$container" ]; then
        echo "Collecting logs from $container..."
        docker logs --since "1h" "$container" > "$OUTPUT_DIR/${container}_${TIMESTAMP}.log" 2>&1 || true
    fi
done

# Collect Docker daemon logs
if [ -f /var/log/docker.log ]; then
    tail -n 1000 /var/log/docker.log > "$OUTPUT_DIR/docker_daemon_${TIMESTAMP}.log" 2>/dev/null || true
fi

# Collect system Docker events
docker events --since "1h" --until "now" > "$OUTPUT_DIR/docker_events_${TIMESTAMP}.log" 2>/dev/null || true

echo "Log collection completed: $TIMESTAMP"
EOF
    
    chmod +x "$output_dir/collect-docker-logs.sh"
    
    # Create log rotation script
    cat > "$output_dir/rotate-docker-logs.sh" << EOF
#!/usr/bin/env bash
# Docker log rotation script

set -euo pipefail

OUTPUT_DIR="$output_dir"
RETENTION_DAYS="$retention_days"

echo "Starting Docker log rotation (retention: \$RETENTION_DAYS days)..."

# Clean up old logs
find "\$OUTPUT_DIR" -name "*.log" -type f -mtime +\$RETENTION_DAYS -delete 2>/dev/null || true

# Compress logs older than 1 day
find "\$OUTPUT_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

echo "Docker log rotation completed"
EOF
    
    chmod +x "$output_dir/rotate-docker-logs.sh"
    
    # Setup cron job for log collection and rotation
    cat > "$output_dir/docker-logs.cron" << EOF
# Docker log collection every hour
0 * * * * $output_dir/collect-docker-logs.sh "$output_dir"

# Docker log rotation daily at 2 AM
0 2 * * * $output_dir/rotate-docker-logs.sh
EOF
    
    log_info "Docker log aggregation setup completed" "DOCKER"
}

# Analyze Docker logs for issues
docker_analyze_logs() {
    local log_dir="${1:-$DOCKER_LOG_DIR}"
    local output_file="${2:-}"
    
    log_info "Analyzing Docker logs for issues..." "DOCKER"
    
    local analysis_report=""
    local error_count=0
    local warning_count=0
    
    # Analyze container logs for errors
    if find "$log_dir" -name "*.log" -type f -exec grep -l -i "error\|exception\|fatal\|critical" {} \; | while read -r logfile; do
        local container_name=$(basename "$logfile" | cut -d'_' -f1)
        local errors=$(grep -c -i "error\|exception\|fatal\|critical" "$logfile" || echo "0")
        
        if [ "$errors" -gt 0 ]; then
            analysis_report+="Container $container_name: $errors errors\n"
            error_count=$((error_count + errors))
            
            # Show recent errors
            analysis_report+="Recent errors:\n"
            grep -i "error\|exception\|fatal\|critical" "$logfile" | tail -3 | sed 's/^/  /' | while read -r line; do
                analysis_report+="  $line\n"
            done
            analysis_report+="\n"
        fi
    done; then
        log_info "Log analysis completed" "DOCKER"
    fi
    
    # Generate summary
    local summary="Docker Log Analysis Summary:\n"
    summary+="Total Errors: $error_count\n"
    summary+="Total Warnings: $warning_count\n"
    summary+="Analysis Time: $(date)\n\n"
    summary+="$analysis_report"
    
    if [ -n "$output_file" ]; then
        echo -e "$summary" > "$output_file"
        log_info "Log analysis report saved to: $output_file" "DOCKER"
    else
        echo -e "$summary"
    fi
}

# =============================================================================
# RESOURCE MONITORING AND OPTIMIZATION
# =============================================================================

# Monitor Docker resource usage
docker_monitor_resources() {
    local output_file="${1:-$DOCKER_METRICS_DIR/resource_usage.jsonl}"
    local duration="${2:-3600}"  # 1 hour default
    local interval="${3:-30}"    # 30 seconds default
    
    log_info "Starting Docker resource monitoring for ${duration}s..." "DOCKER"
    
    mkdir -p "$(dirname "$output_file")"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    while [ $(date +%s) -lt $end_time ]; do
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        # Get container stats
        local stats
        if stats=$(docker stats --no-stream --format "json" 2>/dev/null); then
            echo "$stats" | jq -c --arg timestamp "$timestamp" '. + {timestamp: $timestamp}' >> "$output_file"
        fi
        
        # Get system Docker info
        local system_info
        if system_info=$(docker system df --format "json" 2>/dev/null); then
            echo "$system_info" | jq -c --arg timestamp "$timestamp" '{type: "system", timestamp: $timestamp, data: .}' >> "$output_file"
        fi
        
        sleep "$interval"
    done
    
    log_info "Docker resource monitoring completed. Data saved to: $output_file" "DOCKER"
}

# Clean up Docker resources
docker_cleanup_resources() {
    local aggressive="${1:-false}"
    local max_age="${2:-24h}"
    
    log_info "Cleaning up Docker resources..." "DOCKER"
    
    local freed_space=0
    
    # Remove stopped containers
    local stopped_containers
    if stopped_containers=$(docker container prune -f --filter "until=$max_age" 2>&1); then
        log_info "Cleaned up stopped containers: $stopped_containers" "DOCKER"
    fi
    
    # Remove unused images
    local unused_images
    if unused_images=$(docker image prune -f --filter "until=$max_age" 2>&1); then
        log_info "Cleaned up unused images: $unused_images" "DOCKER"
    fi
    
    # Remove unused volumes
    local unused_volumes
    if unused_volumes=$(docker volume prune -f 2>&1); then
        log_info "Cleaned up unused volumes: $unused_volumes" "DOCKER"
    fi
    
    # Remove unused networks
    local unused_networks
    if unused_networks=$(docker network prune -f 2>&1); then
        log_info "Cleaned up unused networks: $unused_networks" "DOCKER"
    fi
    
    if [ "$aggressive" = "true" ]; then
        log_info "Performing aggressive cleanup..." "DOCKER"
        # Remove all unused data
        local system_prune
        if system_prune=$(docker system prune -af --volumes --filter "until=$max_age" 2>&1); then
            log_info "Aggressive cleanup completed: $system_prune" "DOCKER"
        fi
    fi
    
    # Show space usage after cleanup
    docker system df
    
    log_info "Docker cleanup completed" "DOCKER"
}

# =============================================================================
# NVIDIA GPU SUPPORT
# =============================================================================

# Check if system has NVIDIA GPU
docker_has_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi >/dev/null 2>&1
    else
        false
    fi
}

# Setup NVIDIA Docker runtime
docker_setup_nvidia_runtime() {
    local force_install="${1:-false}"
    
    log_info "Setting up NVIDIA Docker runtime..." "DOCKER"
    
    # Check if system has NVIDIA GPU
    if ! docker_has_gpu; then
        log_info "No NVIDIA GPU detected, skipping NVIDIA Docker setup" "DOCKER"
        return 0
    fi
    
    # Check if NVIDIA runtime is already configured
    if [ "$force_install" != "true" ] && docker_nvidia_runtime_configured; then
        log_info "NVIDIA Docker runtime already configured" "DOCKER"
        return 0
    fi
    
    # Install NVIDIA Container Toolkit
    docker_install_nvidia_toolkit
    
    # Configure Docker to use NVIDIA runtime
    docker_configure_nvidia_runtime
    
    # Validate NVIDIA Docker setup
    docker_validate_nvidia_setup
    
    log_info "NVIDIA Docker runtime setup completed" "DOCKER"
}

# Check if NVIDIA runtime is configured
docker_nvidia_runtime_configured() {
    if [ -f /etc/docker/daemon.json ]; then
        grep -q "nvidia" /etc/docker/daemon.json 2>/dev/null
    else
        false
    fi
}

# Configure NVIDIA runtime for Docker
docker_configure_nvidia_runtime() {
    log_info "Configuring NVIDIA runtime for Docker..." "DOCKER"
    
    # Configure the container runtime
    if command -v nvidia-ctk >/dev/null 2>&1; then
        sudo nvidia-ctk runtime configure --runtime=docker
    else
        # Manual configuration fallback
        docker_configure_nvidia_runtime_manual
    fi
    
    # Restart Docker daemon
    sudo systemctl restart docker
    
    log_info "NVIDIA runtime configured for Docker" "DOCKER"
}

# Manual NVIDIA runtime configuration
docker_configure_nvidia_runtime_manual() {
    local config_file="/etc/docker/daemon.json"
    
    # Read existing config or create new one
    local existing_config="{}"
    if [ -f "$config_file" ]; then
        existing_config=$(cat "$config_file")
    fi
    
    # Add NVIDIA runtime configuration
    local updated_config
    if command -v jq >/dev/null 2>&1; then
        updated_config=$(echo "$existing_config" | jq '. + {
            "runtimes": {
                "nvidia": {
                    "path": "nvidia-container-runtime",
                    "runtimeArgs": []
                }
            }
        }')
    else
        # Fallback without jq
        updated_config='{"runtimes": {"nvidia": {"path": "nvidia-container-runtime", "runtimeArgs": []}}}'
    fi
    
    # Write updated configuration
    echo "$updated_config" | sudo tee "$config_file" > /dev/null
    
    log_info "NVIDIA runtime configuration added manually" "DOCKER"
}

# Validate NVIDIA Docker setup
docker_validate_nvidia_setup() {
    log_info "Validating NVIDIA Docker setup..." "DOCKER"
    
    # Test NVIDIA runtime with a simple container
    if docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.2-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        log_info "NVIDIA Docker setup validated successfully" "DOCKER"
        return 0
    else
        error_docker_nvidia_validation_failed "NVIDIA Docker runtime test failed"
        return $ERROR_VALIDATION_FAILED
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get Docker system information
docker_get_system_info() {
    local format="${1:-json}"
    
    case "$format" in
        "json")
            docker system info --format "json"
            ;;
        *)
            docker system info
            ;;
    esac
}

# List all GeuseMaker containers
docker_list_geusemaker_containers() {
    local format="${1:-table}"
    
    case "$format" in
        "json")
            docker ps -a --filter "label=com.geusemaker.managed=true" --format "json"
            ;;
        "names")
            docker ps -a --filter "label=com.geusemaker.managed=true" --format "{{.Names}}"
            ;;
        *)
            docker ps -a --filter "label=com.geusemaker.managed=true"
            ;;
    esac
}

# Export Docker environment variables
docker_export_env() {
    local instance_type="${1:-$(get_variable INSTANCE_TYPE 2>/dev/null || echo 'unknown')}"
    local region="${2:-$(get_variable AWS_REGION 2>/dev/null || echo 'us-east-1')}"
    
    # Set common Docker environment variables
    export DOCKER_BUILDKIT=1
    export COMPOSE_DOCKER_CLI_BUILD=1
    
    # Set instance-specific variables
    export INSTANCE_TYPE="$instance_type"
    export AWS_DEFAULT_REGION="$region"
    
    # Set resource limits based on instance type
    case "$instance_type" in
        g4dn.xlarge)
            export DOCKER_CPU_LIMIT="3.4"
            export DOCKER_MEMORY_LIMIT="14G"
            ;;
        g4dn.2xlarge)
            export DOCKER_CPU_LIMIT="7.5"
            export DOCKER_MEMORY_LIMIT="30G"
            ;;
        g5.xlarge)
            export DOCKER_CPU_LIMIT="3.5"
            export DOCKER_MEMORY_LIMIT="14G"
            ;;
        *)
            export DOCKER_CPU_LIMIT="2.0"
            export DOCKER_MEMORY_LIMIT="8G"
            ;;
    esac
    
    log_info "Docker environment variables exported for $instance_type" "DOCKER"
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Docker-specific error functions (extend the core error system)
error_docker_daemon_failed() {
    throw_error $ERROR_DEPLOYMENT_FAILED "docker_daemon_failed" "$1"
}

error_docker_config_invalid() {
    throw_error $ERROR_VALIDATION_FAILED "docker_config_invalid" "$1"
}

error_docker_container_start_failed() {
    throw_error $ERROR_DEPLOYMENT_FAILED "docker_container_start_failed" "Container: $1, Error: $2"
}

error_docker_container_restart_failed() {
    throw_error $ERROR_DEPLOYMENT_FAILED "docker_container_restart_failed" "Container: $1, Error: $2"
}

error_docker_compose_file_not_found() {
    throw_error $ERROR_VALIDATION_FAILED "docker_compose_file_not_found" "File: $1"
}

error_docker_compose_deploy_failed() {
    throw_error $ERROR_DEPLOYMENT_FAILED "docker_compose_deploy_failed" "Stack: $1, Error: $2"
}

error_docker_nvidia_validation_failed() {
    throw_error $ERROR_VALIDATION_FAILED "docker_nvidia_validation_failed" "$1"
}

# =============================================================================
# UNITY SERVICE INTEGRATION
# =============================================================================

# Unity service initialization
unity_docker_init() {
    log_info "Initializing Unity Docker Service v$DOCKER_SERVICE_VERSION" "DOCKER"
    
    # Validate Docker installation
    if ! unity_docker_validate; then
        log_warn "Docker validation failed during initialization" "DOCKER"
        return $ERROR_MISSING_DEPENDENCY
    fi
    
    # Setup monitoring and log aggregation
    if [ "$DOCKER_MONITORING_ENABLED" = "true" ]; then
        docker_setup_log_aggregation
    fi
    
    # Export environment variables
    docker_export_env
    
    log_info "Unity Docker Service initialized successfully" "DOCKER"
    return 0
}

# Unity service validation
unity_docker_validate() {
    local errors=0
    
    # Check Docker CLI
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker CLI not found" "DOCKER"
        errors=$((errors + 1))
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not accessible" "DOCKER"
        errors=$((errors + 1))
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose version >/dev/null 2>&1; then
        log_error "Docker Compose not available" "DOCKER"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "Docker environment validation passed" "DOCKER"
        return 0
    else
        log_error "Docker environment validation failed ($errors errors)" "DOCKER"
        return $ERROR_MISSING_DEPENDENCY
    fi
}

# Unity service execution dispatcher
unity_docker_execute() {
    local operation="$1"
    shift
    
    case "$operation" in
        # Container operations
        "install")
            docker_install "$@"
            ;;
        "start")
            docker_start_container "$@"
            ;;
        "stop")
            docker_stop_container "$@"
            ;;
        "restart")
            docker_restart_container "$@"
            ;;
        "status")
            docker_get_container_status "$@"
            ;;
        "logs")
            [ $# -gt 0 ] && docker logs "$@" || docker logs --help
            ;;
        
        # Compose operations
        "compose-deploy")
            docker_compose_deploy "$@"
            ;;
        "compose-stop")
            docker_compose_stop "$@"
            ;;
        "compose-status")
            docker_compose_status "$@"
            ;;
        
        # Resource operations
        "cleanup")
            docker_cleanup_resources "$@"
            ;;
        "monitor")
            docker_monitor_resources "$@"
            ;;
        "system-info")
            docker_get_system_info "$@"
            ;;
        
        # Health operations
        "health-check")
            docker_wait_for_health "$@"
            ;;
        "analyze-logs")
            docker_analyze_logs "$@"
            ;;
        
        # GPU operations
        "setup-gpu")
            docker_setup_nvidia_runtime "$@"
            ;;
        
        # List operations
        "list")
            docker_list_geusemaker_containers "$@"
            ;;
        "list-all")
            docker ps -a "$@"
            ;;
        
        *)
            log_error "Unknown Docker operation: $operation" "DOCKER"
            return $ERROR_VALIDATION_FAILED
            ;;
    esac
}

# Unity service cleanup
unity_docker_cleanup() {
    log_info "Cleaning up Unity Docker Service..." "DOCKER"
    
    # Stop any background monitoring processes
    pkill -f "docker_monitor_container" 2>/dev/null || true
    pkill -f "docker_monitor_compose_stack" 2>/dev/null || true
    
    # Optionally clean up resources
    if [ "${DOCKER_CLEANUP_ON_EXIT:-false}" = "true" ]; then
        docker_cleanup_resources false
    fi
    
    log_info "Unity Docker Service cleanup completed" "DOCKER"
    return 0
}

# Unity service status
unity_docker_status() {
    log_info "Unity Docker Service Status:" "DOCKER"
    log_info "  Version: $DOCKER_SERVICE_VERSION" "DOCKER"
    log_info "  Monitoring: $DOCKER_MONITORING_ENABLED" "DOCKER"
    log_info "  Log Aggregation: $DOCKER_LOG_AGGREGATION_ENABLED" "DOCKER"
    log_info "  Auto Recovery: $DOCKER_AUTO_RECOVERY_ENABLED" "DOCKER"
    
    if command -v docker >/dev/null 2>&1; then
        local version=$(docker --version 2>/dev/null || echo "unknown")
        log_info "  Docker CLI: $version" "DOCKER"
        
        if docker info >/dev/null 2>&1; then
            log_info "  Docker Daemon: accessible" "DOCKER"
            local containers=$(docker ps -q | wc -l)
            log_info "  Running Containers: $containers" "DOCKER"
        else
            log_info "  Docker Daemon: not accessible" "DOCKER"
        fi
    else
        log_info "  Docker CLI: not installed" "DOCKER"
    fi
    
    if docker_has_gpu; then
        log_info "  GPU Support: available" "DOCKER"
    else
        log_info "  GPU Support: not available" "DOCKER"
    fi
    
    return 0
}

# =============================================================================
# REGISTER WITH RESOURCE REGISTRY
# =============================================================================

# Register functions with the resource registry if available
if declare -f register_resource >/dev/null 2>&1; then
    register_resource "docker_service" "unity_docker_service" "Docker container orchestration and management"
    register_resource "docker_install" "docker_install" "Install and configure Docker"
    register_resource "docker_compose_deploy" "docker_compose_deploy" "Deploy Docker Compose stack"
    register_resource "docker_cleanup" "docker_cleanup_resources" "Clean up Docker resources"
    register_resource "docker_monitor" "docker_monitor_resources" "Monitor Docker resource usage"
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# Export key functions for use by other modules
export -f docker_install
export -f docker_start_container
export -f docker_stop_container
export -f docker_restart_container
export -f docker_get_container_status
export -f docker_compose_deploy
export -f docker_compose_stop
export -f docker_compose_status
export -f docker_cleanup_resources
export -f docker_monitor_resources
export -f docker_setup_log_aggregation
export -f docker_analyze_logs
export -f docker_has_gpu
export -f docker_setup_nvidia_runtime
export -f unity_docker_init
export -f unity_docker_validate
export -f unity_docker_execute
export -f unity_docker_cleanup
export -f unity_docker_status

log_info "Unity Docker Service v$DOCKER_SERVICE_VERSION loaded successfully" "DOCKER"
