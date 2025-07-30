#!/usr/bin/env bash
# =============================================================================
# Docker Manager Module
# Handles Docker and Docker Compose installation, NVIDIA runtime setup,
# and container orchestration for AI services
# =============================================================================

# Prevent multiple sourcing
[ -n "${_DOCKER_MANAGER_SH_LOADED:-}" ] && return 0
declare -gr _DOCKER_MANAGER_SH_LOADED=1

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies using dependency groups
source "${SCRIPT_DIR}/../core/dependency-groups.sh"
load_dependency_group "APPLICATION" "$SCRIPT_DIR/.."

# =============================================================================
# DOCKER INSTALLATION AND SETUP
# =============================================================================

# Install Docker with proper configuration
install_docker() {
    local skip_install="${1:-false}"
    
    with_error_context "install_docker" \
        _install_docker_impl "$skip_install"
}

_install_docker_impl() {
    local skip_install="$1"
    
    echo "Setting up Docker environment..." >&2
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        echo "Docker is already installed" >&2
        
        # Validate Docker daemon is running
        if ! docker info >/dev/null 2>&1; then
            echo "Starting Docker daemon..." >&2
            sudo systemctl start docker || {
                throw_error $ERROR_AWS_API "Failed to start Docker daemon"
            }
        fi
        
        if [ "$skip_install" = "true" ]; then
            return 0
        fi
    else
        echo "Docker not found, installing..." >&2
        install_docker_engine
    fi
    
    # Configure Docker daemon
    configure_docker_daemon
    
    # Setup user permissions
    setup_docker_permissions
    
    # Install Docker Compose
    install_docker_compose
    
    # Validate installation
    validate_docker_installation
    
    echo "Docker setup completed successfully" >&2
}

# Install Docker Engine
install_docker_engine() {
    echo "Installing Docker Engine..." >&2
    
    # Detect distribution
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    case "$distro" in
        ubuntu|debian)
            install_docker_ubuntu
            ;;
        amzn)
            install_docker_amazon_linux
            ;;
        rhel|centos|fedora)
            install_docker_rhel
            ;;
        *)
            install_docker_generic
            ;;
    esac
}

# Install Docker on Ubuntu/Debian
install_docker_ubuntu() {
    echo "Installing Docker on Ubuntu/Debian..." >&2
    
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
install_docker_amazon_linux() {
    echo "Installing Docker on Amazon Linux..." >&2
    
    # Update system
    sudo yum update -y
    
    # Install Docker
    sudo yum install -y docker
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
}

# Install Docker on RHEL/CentOS/Fedora
install_docker_rhel() {
    echo "Installing Docker on RHEL-based system..." >&2
    
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
install_docker_generic() {
    echo "Installing Docker using convenience script..." >&2
    
    # Download and run Docker convenience script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
}

# Configure Docker daemon with optimized settings
configure_docker_daemon() {
    echo "Configuring Docker daemon..." >&2
    
    # Create Docker configuration directory
    sudo mkdir -p /etc/docker
    
    # Detect optimal storage driver
    local storage_driver=""
    local storage_opts="[]"
    
    # Check if overlay2 is supported
    if [ -d "/sys/module/overlay" ] || sudo modprobe overlay 2>/dev/null; then
        storage_driver="overlay2"
        storage_opts='["overlay2.override_kernel_check=true"]'
    fi
    
    # Create daemon configuration
    local config_file="/etc/docker/daemon.json"
    local temp_config="/tmp/docker-daemon-config.json"
    
    # Generate optimized configuration for AI workloads
    cat > "$temp_config" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "${storage_driver:-overlay2}",
    "storage-opts": ${storage_opts},
    "data-root": "/var/lib/docker",
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
    }
}
EOF
    
    # Validate JSON syntax
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json; json.load(open('$temp_config'))" || {
            throw_error $ERROR_VALIDATION_FAILED "Generated Docker configuration has invalid JSON"
        }
    fi
    
    # Move configuration to final location
    sudo mv "$temp_config" "$config_file"
    sudo chmod 644 "$config_file"
    
    # Reload Docker daemon
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    echo "Docker daemon configured successfully" >&2
}

# Setup user permissions for Docker
setup_docker_permissions() {
    echo "Setting up Docker permissions..." >&2
    
    # Check if ubuntu user exists
    if id ubuntu >/dev/null 2>&1; then
        # Add ubuntu user to docker group
        if ! groups ubuntu | grep -q docker; then
            sudo usermod -aG docker ubuntu
            echo "Added ubuntu user to docker group" >&2
        fi
    fi
    
    # Check current user
    local current_user=$(whoami)
    if [ "$current_user" != "root" ]; then
        if ! groups "$current_user" | grep -q docker; then
            sudo usermod -aG docker "$current_user"
            echo "Added $current_user to docker group" >&2
        fi
    fi
}

# Install Docker Compose
install_docker_compose() {
    echo "Installing Docker Compose..." >&2
    
    # Check if Docker Compose plugin is available
    if docker compose version >/dev/null 2>&1; then
        echo "Docker Compose plugin is already available" >&2
        return 0
    fi
    
    # Check if standalone docker-compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        echo "Docker Compose standalone is already available" >&2
        return 0
    fi
    
    # Install Docker Compose plugin
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/')
    
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
            echo "Unsupported architecture: $arch" >&2
            return 1
            ;;
    esac
    
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${arch}"
    
    sudo curl -L "$compose_url" -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    
    # Create symlink for backward compatibility
    sudo ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    
    echo "Docker Compose installed successfully" >&2
}

# Validate Docker installation
validate_docker_installation() {
    echo "Validating Docker installation..." >&2
    
    # Test Docker info
    docker info >/dev/null || {
        throw_error $ERROR_VALIDATION_FAILED "Docker info command failed"
    }
    
    # Test Docker run
    docker run --rm hello-world >/dev/null || {
        throw_error $ERROR_VALIDATION_FAILED "Docker run test failed"
    }
    
    # Clean up test image
    docker rmi hello-world >/dev/null 2>&1 || true
    
    # Test Docker Compose
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose version >/dev/null 2>&1; then
        throw_error $ERROR_VALIDATION_FAILED "Docker Compose not available"
    fi
    
    echo "Docker installation validated successfully" >&2
}

# =============================================================================
# NVIDIA DOCKER RUNTIME SETUP
# =============================================================================

# Install and configure NVIDIA Docker runtime
setup_nvidia_docker() {
    local force_install="${1:-false}"
    
    with_error_context "setup_nvidia_docker" \
        _setup_nvidia_docker_impl "$force_install"
}

_setup_nvidia_docker_impl() {
    local force_install="$1"
    
    echo "Setting up NVIDIA Docker runtime..." >&2
    
    # Check if system has NVIDIA GPU
    if ! has_nvidia_gpu; then
        echo "No NVIDIA GPU detected, skipping NVIDIA Docker setup" >&2
        return 0
    fi
    
    # Check if NVIDIA Docker is already configured
    if [ "$force_install" != "true" ] && is_nvidia_docker_configured; then
        echo "NVIDIA Docker runtime already configured" >&2
        return 0
    fi
    
    # Install NVIDIA drivers if needed
    install_nvidia_drivers
    
    # Install NVIDIA Container Toolkit
    install_nvidia_container_toolkit
    
    # Configure Docker to use NVIDIA runtime
    configure_nvidia_runtime
    
    # Validate NVIDIA Docker setup
    validate_nvidia_docker
    
    echo "NVIDIA Docker runtime setup completed" >&2
}

# Check if system has NVIDIA GPU
has_nvidia_gpu() {
    # Check for NVIDIA GPU using lspci
    if command -v lspci >/dev/null 2>&1; then
        lspci | grep -i nvidia >/dev/null 2>&1
    else
        # Fallback: check if nvidia-smi works
        command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1
    fi
}

# Check if NVIDIA Docker is already configured
is_nvidia_docker_configured() {
    # Check if nvidia runtime is in Docker daemon config
    if [ -f /etc/docker/daemon.json ]; then
        grep -q "nvidia" /etc/docker/daemon.json 2>/dev/null
    else
        false
    fi
}

# Install NVIDIA drivers
install_nvidia_drivers() {
    echo "Installing NVIDIA drivers..." >&2
    
    # Check if drivers are already installed
    if nvidia-smi >/dev/null 2>&1; then
        echo "NVIDIA drivers already installed" >&2
        return 0
    fi
    
    # Detect distribution and install drivers
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    case "$distro" in
        ubuntu|debian)
            install_nvidia_drivers_ubuntu
            ;;
        amzn)
            install_nvidia_drivers_amazon_linux
            ;;
        rhel|centos|fedora)
            install_nvidia_drivers_rhel
            ;;
        *)
            echo "WARNING: Unknown distribution, manual NVIDIA driver installation may be required" >&2
            ;;
    esac
}

# Install NVIDIA drivers on Ubuntu/Debian
install_nvidia_drivers_ubuntu() {
    # Update package list
    sudo apt-get update
    
    # Install NVIDIA drivers
    sudo apt-get install -y ubuntu-drivers-common
    sudo ubuntu-drivers autoinstall
    
    # Alternative: Install specific driver version
    # sudo apt-get install -y nvidia-driver-525
}

# Install NVIDIA drivers on Amazon Linux
install_nvidia_drivers_amazon_linux() {
    # Install NVIDIA drivers for Amazon Linux 2
    sudo yum update -y
    sudo yum install -y gcc kernel-devel-$(uname -r)
    
    # Download and install NVIDIA driver
    wget https://us.download.nvidia.com/tesla/525.147.05/NVIDIA-Linux-x86_64-525.147.05.run
    sudo sh NVIDIA-Linux-x86_64-525.147.05.run --silent
    rm NVIDIA-Linux-x86_64-525.147.05.run
}

# Install NVIDIA drivers on RHEL/CentOS/Fedora
install_nvidia_drivers_rhel() {
    # Install EPEL repository
    sudo yum install -y epel-release
    
    # Install development tools
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)
    
    # Install NVIDIA drivers
    sudo yum install -y nvidia-driver nvidia-driver-cuda
}

# Install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    echo "Installing NVIDIA Container Toolkit..." >&2
    
    # Detect distribution
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    case "$distro" in
        ubuntu|debian)
            install_nvidia_toolkit_ubuntu
            ;;
        amzn|rhel|centos|fedora)
            install_nvidia_toolkit_rhel
            ;;
        *)
            install_nvidia_toolkit_generic
            ;;
    esac
}

# Install NVIDIA Container Toolkit on Ubuntu/Debian
install_nvidia_toolkit_ubuntu() {
    # Setup the package repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Install the toolkit
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
}

# Install NVIDIA Container Toolkit on RHEL-based systems
install_nvidia_toolkit_rhel() {
    # Setup the package repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | \
        sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    
    # Install the toolkit
    sudo yum install -y nvidia-container-toolkit
}

# Generic NVIDIA Container Toolkit installation
install_nvidia_toolkit_generic() {
    echo "Installing NVIDIA Container Toolkit using generic method..." >&2
    
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
            echo "Unsupported architecture: $arch" >&2
            return 1
            ;;
    esac
    
    local download_url="https://github.com/NVIDIA/nvidia-container-toolkit/releases/download/v${toolkit_version}/nvidia-container-toolkit_${toolkit_version}_linux_${arch}.tar.gz"
    
    # Download and extract
    wget "$download_url" -O /tmp/nvidia-container-toolkit.tar.gz
    sudo tar -xzf /tmp/nvidia-container-toolkit.tar.gz -C /usr/local/
    rm /tmp/nvidia-container-toolkit.tar.gz
    
    # Set up binaries
    sudo ln -sf /usr/local/nvidia-container-toolkit/nvidia-container-runtime /usr/bin/
    sudo ln -sf /usr/local/nvidia-container-toolkit/nvidia-container-runtime-hook /usr/bin/
}

# Configure Docker to use NVIDIA runtime
configure_nvidia_runtime() {
    echo "Configuring NVIDIA runtime for Docker..." >&2
    
    # Configure the container runtime
    sudo nvidia-ctk runtime configure --runtime=docker
    
    # Alternative manual configuration if nvidia-ctk fails
    if ! sudo nvidia-ctk runtime configure --runtime=docker; then
        echo "Configuring NVIDIA runtime manually..." >&2
        configure_nvidia_runtime_manual
    fi
    
    # Restart Docker daemon
    sudo systemctl restart docker
    
    echo "NVIDIA runtime configured for Docker" >&2
}

# Manual NVIDIA runtime configuration
configure_nvidia_runtime_manual() {
    local config_file="/etc/docker/daemon.json"
    
    # Read existing config or create new one
    local existing_config="{}"
    if [ -f "$config_file" ]; then
        existing_config=$(cat "$config_file")
    fi
    
    # Add NVIDIA runtime configuration
    local updated_config
    updated_config=$(echo "$existing_config" | jq '. + {
        "default-runtime": "nvidia",
        "runtimes": {
            "nvidia": {
                "path": "nvidia-container-runtime",
                "runtimeArgs": []
            }
        }
    }')
    
    # Write updated configuration
    echo "$updated_config" | sudo tee "$config_file" > /dev/null
    
    echo "NVIDIA runtime configuration added manually" >&2
}

# Validate NVIDIA Docker setup
validate_nvidia_docker() {
    echo "Validating NVIDIA Docker setup..." >&2
    
    # Test NVIDIA runtime
    if ! docker run --rm --runtime=nvidia nvidia/cuda:12.2-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        throw_error $ERROR_VALIDATION_FAILED "NVIDIA Docker runtime test failed"
    fi
    
    echo "NVIDIA Docker setup validated successfully" >&2
}

# =============================================================================
# CONTAINER ORCHESTRATION
# =============================================================================

# Deploy AI services using Docker Compose
deploy_ai_services() {
    local compose_file="$1"
    local env_file="${2:-}"
    local services="${3:-}"  # Optional: specific services to deploy
    
    with_error_context "deploy_ai_services" \
        _deploy_ai_services_impl "$compose_file" "$env_file" "$services"
}

_deploy_ai_services_impl() {
    local compose_file="$1"
    local env_file="$2"
    local services="$3"
    
    echo "Deploying AI services..." >&2
    
    # Validate compose file exists
    require_file "$compose_file"
    
    # Build compose command
    local compose_cmd="docker compose -f $compose_file"
    
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    # Pull images first
    echo "Pulling Docker images..." >&2
    $compose_cmd pull || echo "WARNING: Some images failed to pull" >&2
    
    # Deploy services
    echo "Starting services..." >&2
    if [ -n "$services" ]; then
        $compose_cmd up -d $services || {
            throw_error $ERROR_AWS_API "Failed to deploy specific services: $services"
        }
    else
        $compose_cmd up -d || {
            throw_error $ERROR_AWS_API "Failed to deploy AI services"
        }
    fi
    
    # Wait for services to be healthy
    wait_for_services_health "$compose_file" "$env_file"
    
    echo "AI services deployed successfully" >&2
}

# Wait for services to become healthy
wait_for_services_health() {
    local compose_file="$1"
    local env_file="${2:-}"
    local max_wait="${3:-300}"  # 5 minutes default
    
    echo "Waiting for services to become healthy..." >&2
    
    local compose_cmd="docker compose -f $compose_file"
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    local wait_time=0
    local check_interval=10
    
    while [ $wait_time -lt $max_wait ]; do
        # Check service health
        local unhealthy_services
        unhealthy_services=$($compose_cmd ps --format json | jq -r '.[] | select(.Health != "healthy" and .Health != "") | .Service' 2>/dev/null || echo "")
        
        if [ -z "$unhealthy_services" ]; then
            echo "All services are healthy" >&2
            return 0
        fi
        
        echo "Waiting for services to be healthy: $unhealthy_services" >&2
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    echo "WARNING: Some services did not become healthy within ${max_wait}s" >&2
    $compose_cmd ps
    return 1
}

# Stop AI services
stop_ai_services() {
    local compose_file="$1"
    local env_file="${2:-}"
    local services="${3:-}"  # Optional: specific services to stop
    
    echo "Stopping AI services..." >&2
    
    local compose_cmd="docker compose -f $compose_file"
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    if [ -n "$services" ]; then
        $compose_cmd stop $services
    else
        $compose_cmd down
    fi
    
    echo "AI services stopped" >&2
}

# Get service status
get_service_status() {
    local compose_file="$1"
    local env_file="${2:-}"
    
    local compose_cmd="docker compose -f $compose_file"
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    $compose_cmd ps --format json | jq -r '.[] | "\(.Service): \(.State) (\(.Health // "no health check"))"'
}

# =============================================================================
# RESOURCE MANAGEMENT
# =============================================================================

# Monitor Docker resource usage
monitor_docker_resources() {
    echo "=== Docker Resource Usage ===" >&2
    
    # Container stats
    echo "Container Resource Usage:" >&2
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
    
    # System resource usage
    echo -e "\nSystem Resource Usage:" >&2
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% used" >&2
    echo "Memory: $(free | grep Mem | awk '{printf("%.2f%% used\n", $3/$2 * 100.0)}')" >&2
    echo "Disk: $(df -h / | awk 'NR==2{printf "%s used\n", $5}')" >&2
    
    # GPU usage if available
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo -e "\nGPU Usage:" >&2
        nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | \
        awk -F, '{printf "GPU: %s%% | Memory: %s/%sMB | Temp: %s°C\n", $1, $2, $3, $4}'
    fi
}

# Clean up Docker resources
cleanup_docker_resources() {
    local aggressive="${1:-false}"
    
    echo "Cleaning up Docker resources..." >&2
    
    # Remove stopped containers
    docker container prune -f
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused volumes
    docker volume prune -f
    
    # Remove unused networks
    docker network prune -f
    
    if [ "$aggressive" = "true" ]; then
        echo "Performing aggressive cleanup..." >&2
        # Remove all unused data
        docker system prune -af --volumes
    fi
    
    echo "Docker cleanup completed" >&2
}

# =============================================================================
# DOCKER UTILITIES
# =============================================================================

# Check Docker daemon status
check_docker_daemon() {
    if systemctl is-active --quiet docker; then
        echo "Docker daemon is running" >&2
        return 0
    else
        echo "Docker daemon is not running" >&2
        return 1
    fi
}

# Restart Docker daemon
restart_docker_daemon() {
    echo "Restarting Docker daemon..." >&2
    sudo systemctl restart docker
    
    # Wait for daemon to be ready
    local wait_time=0
    while [ $wait_time -lt 60 ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon restarted successfully" >&2
            return 0
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    throw_error $ERROR_TIMEOUT "Docker daemon failed to restart"
}

# Get Docker system information
get_docker_info() {
    echo "=== Docker System Information ===" >&2
    docker version
    echo "" >&2
    docker info
    echo "" >&2
    
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose version
    elif docker compose version >/dev/null 2>&1; then
        docker compose version
    fi
}

# Export Docker environment variables
export_docker_env() {
    local instance_type="${1:-$(get_variable INSTANCE_TYPE)}"
    local region="${2:-$(get_variable AWS_REGION)}"
    
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
    
    echo "Docker environment variables exported" >&2
}

# =============================================================================
# LEGACY COMPATIBILITY FUNCTIONS (MIGRATED FROM MONOLITH)
# =============================================================================

# Deploy application stack (legacy compatibility function)
deploy_application_stack() {
    local instance_ip="$1"
    local key_file="$2"
    local stack_name="$3"
    local compose_file="${4:-docker-compose.gpu-optimized.yml}"
    local environment="${5:-development}"
    local follow_logs="${6:-true}"
    
    if [ -z "$instance_ip" ] || [ -z "$key_file" ] || [ -z "$stack_name" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "deploy_application_stack requires instance_ip, key_file, and stack_name parameters"
    fi
    
    # Validate and sanitize inputs to prevent command injection
    # Validate stack name format first
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,31}$ ]]; then
        throw_error $ERROR_INVALID_ARGUMENT "Invalid stack name format. Must start with letter, contain only alphanumeric and hyphens, max 32 chars: '$stack_name'"
    fi
    
    # Validate environment format
    if [[ ! "$environment" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,31}$ ]]; then
        throw_error $ERROR_INVALID_ARGUMENT "Invalid environment format. Must start with letter, contain only alphanumeric and hyphens, max 32 chars: '$environment'"
    fi
    
    # Validate compose file name format
    if [[ ! "$(basename "$compose_file")" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,63}\.(yml|yaml)$ ]]; then
        throw_error $ERROR_INVALID_ARGUMENT "Invalid compose file format. Must be a valid YAML file: '$compose_file'"
    fi
    
    # Use validated inputs (no need for further sanitization)
    local sanitized_stack_name="$stack_name"
    local sanitized_environment="$environment"
    local sanitized_compose_file="$(basename "$compose_file")"

    echo "Deploying application stack to $instance_ip..." >&2
    
    # Start log streaming if requested
    if [ "$follow_logs" = "true" ]; then
        stream_provisioning_logs "$instance_ip" "$key_file"
        # Register cleanup function
        trap 'stop_provisioning_logs' EXIT INT TERM
    fi

    # Copy project files
    echo "Copying project files..." >&2
    rsync -avz -e "ssh -i $key_file -o StrictHostKeyChecking=no" \
        --exclude='.git' \
        --exclude='*.log' \
        --exclude='*.pem' \
        --exclude='*.key' \
        --exclude='.env*' \
        ./ ubuntu@"$instance_ip":/home/ubuntu/GeuseMaker/ || {
        throw_error $ERROR_DEPLOYMENT "Failed to copy project files"
    }

    # Run deployment fixes first
    echo "Running deployment fixes (disk space, EFS, Parameter Store)..." >&2
    if [ "$follow_logs" = "true" ]; then
        echo "Watch the [INSTANCE] logs below for detailed progress..." >&2
        sleep 3  # Give user time to see the message
    fi
    
    # Copy and run the fix script using validated variables
    scp -i "$key_file" -o StrictHostKeyChecking=no \
        ./scripts/fix-deployment-issues.sh ubuntu@"$instance_ip":/tmp/ || {
        throw_error $ERROR_DEPLOYMENT "Failed to copy fix script"
    }
    
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" \
        "chmod +x /tmp/fix-deployment-issues.sh && sudo /tmp/fix-deployment-issues.sh '$sanitized_stack_name' '${AWS_REGION:-us-east-1}' 2>&1 | tee -a /var/log/deployment.log" || {
        throw_error $ERROR_DEPLOYMENT "Deployment fixes failed"
    }

    # Generate environment configuration
    echo "Generating environment configuration..." >&2
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" << EOF
cd /home/ubuntu/GeuseMaker
echo "\$(date): Starting environment configuration..." | tee -a /var/log/deployment.log
chmod +x scripts/config-manager.sh
echo "\$(date): Generating $sanitized_environment configuration..." | tee -a /var/log/deployment.log
./scripts/config-manager.sh generate $sanitized_environment 2>&1 | tee -a /var/log/deployment.log
echo "\$(date): Setting up environment variables..." | tee -a /var/log/deployment.log
./scripts/config-manager.sh env $sanitized_environment 2>&1 | tee -a /var/log/deployment.log
echo "\$(date): Environment configuration completed" | tee -a /var/log/deployment.log
EOF
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_DEPLOYMENT "Environment configuration failed"
    fi

    # Deploy application
    echo "Starting application stack..." >&2
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" << EOF
cd /home/ubuntu/GeuseMaker

# Ensure deployment log exists and is writable
sudo touch /var/log/deployment.log 2>/dev/null || touch \$HOME/deployment.log
DEPLOY_LOG=\$([ -w /var/log/deployment.log ] && echo "/var/log/deployment.log" || echo "\$HOME/deployment.log")

echo "\$(date): Starting application deployment..." | tee -a "\$DEPLOY_LOG"

# Function to wait for apt locks to be released
wait_for_apt_lock() {
    local max_wait=300
    local wait_time=0
    echo "\$(date): Waiting for apt locks to be released..." | tee -a "\$DEPLOY_LOG"
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        if [ \$wait_time -ge \$max_wait ]; then
            echo "\$(date): Timeout waiting for apt locks, killing blocking processes..." | tee -a "\$DEPLOY_LOG"
            sudo pkill -9 -f "unattended-upgrade" || true
            sudo pkill -9 -f "apt-get" || true
            sleep 5
            break
        fi
        echo "\$(date): APT is locked, waiting 10 seconds..." | tee -a "\$DEPLOY_LOG"
        sleep 10
        wait_time=\$((wait_time + 10))
    done
    echo "\$(date): APT locks released" | tee -a "\$DEPLOY_LOG"
}

# Wait for any ongoing apt operations to complete
wait_for_apt_lock

# Install missing dependencies first
echo "\$(date): Installing missing dependencies..." | tee -a "\$DEPLOY_LOG"
sudo apt-get update -qq 2>&1 | tee -a "\$DEPLOY_LOG"

# Install docker-compose and other dependencies
if ! command -v docker compose >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "\$(date): Docker Compose not found, installation will be handled by user data script" | tee -a "\$DEPLOY_LOG"
fi

sudo apt-get install -y yq jq gettext-base 2>&1 | tee -a "\$DEPLOY_LOG"

# Define docker compose command to use (check both)
if command -v docker compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    echo "\$(date): Using docker compose plugin" | tee -a "\$DEPLOY_LOG"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    echo "\$(date): Using legacy docker-compose binary" | tee -a "\$DEPLOY_LOG"
else
    echo "\$(date): ERROR: Neither 'docker compose' nor 'docker-compose' command found" | tee -a "\$DEPLOY_LOG"
    echo "\$(date): This should have been installed by the user data script" | tee -a "\$DEPLOY_LOG"
    exit 1
fi

# Pull latest images
echo "\$(date): Pulling Docker images..." | tee -a "\$DEPLOY_LOG"
\$DOCKER_COMPOSE_CMD -f $sanitized_compose_file pull 2>&1 | tee -a "\$DEPLOY_LOG"

# Start services
echo "\$(date): Starting Docker services..." | tee -a "\$DEPLOY_LOG"
\$DOCKER_COMPOSE_CMD -f $sanitized_compose_file up -d 2>&1 | tee -a "\$DEPLOY_LOG"

# Wait for services to stabilize
echo "\$(date): Waiting for services to stabilize..." | tee -a "\$DEPLOY_LOG"
sleep 30

# Check service status
echo "\$(date): Checking service status..." | tee -a "\$DEPLOY_LOG"
\$DOCKER_COMPOSE_CMD -f $sanitized_compose_file ps 2>&1 | tee -a "\$DEPLOY_LOG"

echo "\$(date): Application deployment completed" | tee -a "\$DEPLOY_LOG"
EOF

    if [ $? -ne 0 ]; then
        throw_error $ERROR_DEPLOYMENT "Application deployment failed"
    fi

    # Stop log streaming
    if [ "$follow_logs" = "true" ]; then
        sleep 5  # Allow final logs to flow
        stop_provisioning_logs
    fi

    echo "Application stack deployed successfully" >&2
    return 0
}

# Wait for APT lock to be released (helper function)
wait_for_apt_lock() {
    local max_wait="${1:-300}"
    local wait_time=0
    
    echo "Waiting for apt locks to be released..." >&2
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            echo "Timeout waiting for apt locks, killing blocking processes..." >&2
            sudo pkill -9 -f "unattended-upgrade" || true
            sudo pkill -9 -f "apt-get" || true
            sleep 5
            break
        fi
        echo "APT is locked, waiting 10 seconds..." >&2
        sleep 10
        wait_time=$((wait_time + 10))
    done
    echo "APT locks released" >&2
}

# Stream provisioning logs (placeholder - to be implemented)
stream_provisioning_logs() {
    local instance_ip="$1"
    local key_file="$2"
    
    echo "Starting log streaming from $instance_ip..." >&2
    # Implementation would go here
}

# Stop provisioning logs (placeholder - to be implemented)
stop_provisioning_logs() {
    echo "Stopping log streaming..." >&2
    # Implementation would go here
}