#!/bin/bash
# Unity Docker Service - Complete Production-Ready Implementation
# Comprehensive Docker service with Docker Compose generation, multi-environment support,
# container lifecycle management, GPU support, and Unity event integration
# Compatible with bash 3.x+ and follows Unity architecture patterns

set -euo pipefail

# Prevent multiple sourcing
[ -n "${_UNITY_DOCKER_SERVICE_COMPLETE_SH_LOADED:-}" ] && return 0
declare -gr _UNITY_DOCKER_SERVICE_COMPLETE_SH_LOADED=1

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core dependencies
if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-core.sh" ]]; then
    source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
fi

if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-events.sh" ]]; then
    source "$PROJECT_ROOT/lib/unity/core/unity-events.sh"
fi

# =============================================================================
# SERVICE METADATA AND CONFIGURATION
# =============================================================================

# Service constants
readonly UNITY_DOCKER_SERVICE_VERSION="3.0.0"
readonly UNITY_DOCKER_SERVICE_NAME="unity-docker-service-complete"
readonly UNITY_DOCKER_MIN_VERSION="20.10.0"
readonly UNITY_COMPOSE_MIN_VERSION="2.0.0"

# Docker Compose version compatibility
COMPOSE_CMD="docker compose"
if ! docker compose version >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
fi

# Service state directories - bash 3/4 compatible
UNITY_DOCKER_STATE_DIR=".unity/docker"
UNITY_DOCKER_COMPOSE_DIR="$UNITY_DOCKER_STATE_DIR/compose"
UNITY_DOCKER_LOGS_DIR="$UNITY_DOCKER_STATE_DIR/logs"
UNITY_DOCKER_CACHE_DIR="$UNITY_DOCKER_STATE_DIR/cache"
UNITY_DOCKER_CONFIG_DIR="$UNITY_DOCKER_STATE_DIR/config"

# Service state tracking - bash 3/4 compatible
declare -A UNITY_DOCKER_CONTAINERS 2>/dev/null || UNITY_DOCKER_CONTAINERS=()
declare -A UNITY_DOCKER_NETWORKS 2>/dev/null || UNITY_DOCKER_NETWORKS=()
declare -A UNITY_DOCKER_VOLUMES 2>/dev/null || UNITY_DOCKER_VOLUMES=()
declare -A UNITY_DOCKER_STACKS 2>/dev/null || UNITY_DOCKER_STACKS=()

# Configuration defaults
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-100m}"
DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"
DOCKER_HEALTH_CHECK_INTERVAL="${DOCKER_HEALTH_CHECK_INTERVAL:-30s}"
DOCKER_HEALTH_CHECK_TIMEOUT="${DOCKER_HEALTH_CHECK_TIMEOUT:-10s}"
DOCKER_HEALTH_CHECK_RETRIES="${DOCKER_HEALTH_CHECK_RETRIES:-3}"

# Multi-environment configuration
DOCKER_ENVIRONMENTS=("dev" "staging" "prod")
DOCKER_DEFAULT_ENVIRONMENT="dev"

# GeuseMaker AI Stack components
declare -A GEUSEMAKER_STACK_COMPONENTS=( 
    [postgres]="postgres:16.1-alpine3.19"
    [n8n]="n8nio/n8n:1.19.4"
    [qdrant]="qdrant/qdrant:v1.7.3"
    [ollama]="ollama/ollama:0.1.17"
    [crawl4ai]="unclecode/crawl4ai:0.2.77"
    [redis]="redis:7.2-alpine"
    [nginx]="nginx:1.25-alpine"
)

# =============================================================================
# UNITY SERVICE INTERFACE IMPLEMENTATION
# =============================================================================

# Initialize Docker service (required Unity interface)
init_unity_docker_service() {
    local service_name="${1:-$UNITY_DOCKER_SERVICE_NAME}"
    
    _log_docker "INFO" "Initializing Unity Docker Service Complete v$UNITY_DOCKER_SERVICE_VERSION"
    
    # Create service state directories
    local directories=(
        "$UNITY_DOCKER_STATE_DIR"
        "$UNITY_DOCKER_COMPOSE_DIR"
        "$UNITY_DOCKER_LOGS_DIR"
        "$UNITY_DOCKER_CACHE_DIR"
        "$UNITY_DOCKER_CONFIG_DIR"
        "$UNITY_DOCKER_COMPOSE_DIR/templates"
        "$UNITY_DOCKER_COMPOSE_DIR/environments"
        "$UNITY_DOCKER_LOGS_DIR/containers"
        "$UNITY_DOCKER_LOGS_DIR/compose"
        "$UNITY_DOCKER_CACHE_DIR/images"
        "$UNITY_DOCKER_CACHE_DIR/volumes"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir" 2>/dev/null || {
            _emit_docker_event "system.error" "unity-docker" "{\"error\":\"Failed to create directory: $dir\"}" "high"
            return $UNITY_ERROR_FILESYSTEM
        }
    done
    
    # Initialize event system integration
    _init_docker_service_events
    
    # Validate Docker installation
    if ! _validate_docker_installation; then
        _emit_docker_event "system.error" "unity-docker" "{\"error\":\"Docker validation failed\"}" "high"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Initialize Docker daemon configuration
    _init_docker_daemon_config
    
    # Setup GPU support if available
    if _has_nvidia_gpu; then
        _setup_nvidia_docker_support
    fi
    
    # Initialize resource monitoring
    _init_resource_monitoring
    
    # Initialize log aggregation
    _init_log_aggregation
    
    # Generate default Docker Compose templates
    _generate_default_compose_templates
    
    # Register with Unity system
    if command -v unity_register_service >/dev/null 2>&1; then
        unity_register_service "$service_name" "$0" "docker" "config,aws"
    fi
    
    # Emit service initialization event
    _emit_docker_event "system.startup" "unity-docker" "{\"component\":\"$UNITY_DOCKER_SERVICE_NAME\",\"version\":\"$UNITY_DOCKER_SERVICE_VERSION\",\"startup_time\":$(date +%s)}" "medium"
    
    _log_docker "SUCCESS" "Unity Docker Service Complete initialized successfully"
    return $UNITY_SUCCESS
}

# Start Docker service (required Unity interface)
start_unity_docker_service() {
    _log_docker "INFO" "Starting Unity Docker Service Complete"
    
    # Start background monitoring
    _start_container_monitoring &
    _start_resource_monitoring &
    
    # Start log aggregation
    _start_log_aggregation &
    
    # Emit service start event
    _emit_docker_event "system.startup" "unity-docker" "{\"action\":\"service_started\"}" "medium"
    
    _log_docker "SUCCESS" "Unity Docker Service Complete started successfully"
    return $UNITY_SUCCESS
}

# Stop Docker service (required Unity interface)
stop_unity_docker_service() {
    _log_docker "INFO" "Stopping Unity Docker Service Complete"
    
    # Stop background processes
    pkill -f "_monitor_docker_containers" 2>/dev/null || true
    pkill -f "_monitor_docker_resources" 2>/dev/null || true
    pkill -f "_aggregate_docker_logs" 2>/dev/null || true
    
    # Emit service stop event
    _emit_docker_event "system.shutdown" "unity-docker" "{\"action\":\"service_stopped\"}" "medium"
    
    _log_docker "SUCCESS" "Unity Docker Service Complete stopped successfully"
    return $UNITY_SUCCESS
}

# Health check Docker service (required Unity interface)
health_unity_docker_service() {
    local health_status="healthy"
    local health_details=()
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        health_status="unhealthy"
        health_details+=("Docker daemon not accessible")
    fi
    
    # Check Docker Compose
    if ! $COMPOSE_CMD version >/dev/null 2>&1; then
        health_status="unhealthy"
        health_details+=("Docker Compose not available")
    fi
    
    # Check disk space
    local disk_usage
    disk_usage=$(df "$UNITY_DOCKER_STATE_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 85 ]]; then
        health_status="unhealthy"
        health_details+=("Disk usage high: ${disk_usage}%")
    fi
    
    # Return health status
    local health_json="{\"status\":\"$health_status\",\"details\":[\"$(IFS=','; echo "${health_details[*]}")\"],\"timestamp\":$(date +%s)}"
    echo "$health_json"
    
    [[ "$health_status" == "healthy" ]] && return $UNITY_SUCCESS || return $UNITY_ERROR_HEALTH
}

# Configure Docker service (required Unity interface)
config_unity_docker_service() {
    local config_action="${1:-show}"
    local config_key="${2:-}"
    local config_value="${3:-}"
    
    case "$config_action" in
        "show")
            _show_docker_service_config
            ;;
        "set")
            _set_docker_service_config "$config_key" "$config_value"
            ;;
        "get")
            _get_docker_service_config "$config_key"
            ;;
        "validate")
            _validate_docker_service_config
            ;;
        *)
            _log_docker "ERROR" "Unknown config action: $config_action"
            return $UNITY_ERROR_INVALID_INPUT
            ;;
    esac
}

# =============================================================================
# DOCKER COMPOSE FILE GENERATION
# =============================================================================

# Generate Docker Compose file for specific environment
generate_docker_compose() {
    local environment="${1:-$DOCKER_DEFAULT_ENVIRONMENT}"
    local stack_name="${2:-geusemaker}"
    local components="${3:-postgres,n8n,qdrant,ollama,crawl4ai,redis,nginx}"
    local gpu_enabled="${4:-auto}"
    local output_file="${5:-}"
    
    _log_docker "INFO" "Generating Docker Compose for environment: $environment"
    
    # Validate environment
    if ! _is_valid_environment "$environment"; then
        _log_docker "ERROR" "Invalid environment: $environment"
        return $UNITY_ERROR_INVALID_INPUT
    fi
    
    # Set output file if not specified
    if [[ -z "$output_file" ]]; then
        output_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.yml"
    fi
    
    # Parse components
    local -a component_list
    IFS=',' read -ra component_list <<< "$components"
    
    # Detect GPU support if auto
    if [[ "$gpu_enabled" == "auto" ]]; then
        gpu_enabled=$(_has_nvidia_gpu && echo "true" || echo "false")
    fi
    
    # Generate compose file header
    cat > "$output_file" << 'EOF'
# Auto-generated Docker Compose file by Unity Docker Service
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
# Environment: ENVIRONMENT_PLACEHOLDER
# Stack: STACK_NAME_PLACEHOLDER
# GPU Support: GPU_ENABLED_PLACEHOLDER

version: '3.8'

# =============================================================================
# EXTENSION CONFIGURATIONS
# =============================================================================

# Common service configuration
x-common-config: &common-config
  restart: unless-stopped
  networks:
    - ai_network
  logging:
    driver: json-file
    options:
      max-size: "DOCKER_LOG_MAX_SIZE_PLACEHOLDER"
      max-file: "DOCKER_LOG_MAX_FILE_PLACEHOLDER"
  labels:
    - com.unity.managed=true
    - com.unity.stack=STACK_NAME_PLACEHOLDER
    - com.unity.environment=ENVIRONMENT_PLACEHOLDER
    - com.unity.version=UNITY_DOCKER_SERVICE_VERSION_PLACEHOLDER

# Health check configuration
x-health-check: &health-check
  start_period: 60s
  interval: 30s
  timeout: 10s
  retries: 3

EOF
    
    # Add GPU configuration if enabled
    if [[ "$gpu_enabled" == "true" ]]; then
        cat >> "$output_file" << 'EOF'
# GPU configuration extension
x-gpu-config: &gpu-config
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
    - NVIDIA_DRIVER_CAPABILITIES=all

EOF
    fi
    
    # Start services section
    echo "services:" >> "$output_file"
    
    # Generate service definitions
    for component in "${component_list[@]}"; do
        case "$component" in
            "postgres")
                _generate_postgres_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            "n8n")
                _generate_n8n_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            "qdrant")
                _generate_qdrant_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            "ollama")
                _generate_ollama_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            "crawl4ai")
                _generate_crawl4ai_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            "redis")
                _generate_redis_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            "nginx")
                _generate_nginx_service "$output_file" "$environment" "$gpu_enabled"
                ;;
            *)
                _log_docker "WARN" "Unknown component: $component"
                ;;
        esac
    done
    
    # Generate networks section
    _generate_networks_section "$output_file" "$environment"
    
    # Generate volumes section
    _generate_volumes_section "$output_file" "$environment" "${component_list[@]}"
    
    # Generate secrets section for production
    if [[ "$environment" == "prod" ]]; then
        _generate_secrets_section "$output_file"
    fi
    
    # Perform variable substitution
    _substitute_compose_variables "$output_file" "$environment" "$stack_name" "$gpu_enabled"
    
    # Generate environment file
    _generate_environment_file "$environment" "$stack_name"
    
    # Emit compose generation event
    _emit_docker_event "docker.compose.generated" "unity-docker" "{\"environment\":\"$environment\",\"stack\":\"$stack_name\",\"file\":\"$output_file\",\"components\":[\"$(IFS=','; echo "${component_list[*]}")\"]}" "medium"
    
    _log_docker "SUCCESS" "Docker Compose file generated: $output_file"
    echo "$output_file"
    return $UNITY_SUCCESS
}

# =============================================================================
# CONTAINER LIFECYCLE MANAGEMENT
# =============================================================================

# Deploy Docker Compose stack with enhanced orchestration
deploy_docker_stack() {
    local compose_file="$1"
    local environment="${2:-$DOCKER_DEFAULT_ENVIRONMENT}"
    local stack_name="${3:-geusemaker}"
    local services="${4:-}"
    local wait_for_health="${5:-true}"
    local pull_images="${6:-true}"
    
    _log_docker "INFO" "Deploying Docker stack: $stack_name (environment: $environment)"
    
    # Validate compose file
    if [[ ! -f "$compose_file" ]]; then
        _log_docker "ERROR" "Compose file not found: $compose_file"
        return $UNITY_ERROR_FILE_NOT_FOUND
    fi
    
    # Emit deployment start event
    _emit_docker_event "deployment.started" "unity-docker" "{\"stack\":\"$stack_name\",\"environment\":\"$environment\",\"compose_file\":\"$compose_file\"}" "high"
    
    # Build compose command
    local env_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.env"
    local compose_cmd="$COMPOSE_CMD -f $compose_file"
    
    if [[ -f "$env_file" ]]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name"
    
    # Pull images if requested
    if [[ "$pull_images" == "true" ]]; then
        _log_docker "INFO" "Pulling Docker images..."
        if ! $compose_cmd pull --ignore-buildable 2>/dev/null; then
            _log_docker "WARN" "Failed to pull some images, continuing with deployment"
        fi
        
        _emit_docker_event "docker.images.pulled" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
    fi
    
    # Validate compose file
    if ! $compose_cmd config >/dev/null 2>&1; then
        _log_docker "ERROR" "Invalid Docker Compose configuration"
        _emit_docker_event "deployment.failed" "unity-docker" "{\"stack\":\"$stack_name\",\"error\":\"Invalid compose configuration\"}" "high"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Deploy services
    _log_docker "INFO" "Starting services..."
    local deploy_cmd="$compose_cmd up -d"
    
    if [[ -n "$services" ]]; then
        deploy_cmd="$deploy_cmd $services"
    fi
    
    if $deploy_cmd; then
        _log_docker "SUCCESS" "Services deployed successfully"
        
        # Track stack
        UNITY_DOCKER_STACKS["$stack_name"]="$compose_file|$environment|$(date +%s)"
        
        # Emit deployment success event
        _emit_docker_event "deployment.completed" "unity-docker" "{\"stack\":\"$stack_name\",\"environment\":\"$environment\"}" "high"
    else
        _log_docker "ERROR" "Failed to deploy services"
        _emit_docker_event "deployment.failed" "unity-docker" "{\"stack\":\"$stack_name\",\"error\":\"Service deployment failed\"}" "high"
        return $UNITY_ERROR_DEPLOYMENT
    fi
    
    # Wait for services to be healthy
    if [[ "$wait_for_health" == "true" ]]; then
        _log_docker "INFO" "Waiting for services to become healthy..."
        if _wait_for_stack_health "$compose_file" "$env_file" "$stack_name"; then
            _log_docker "SUCCESS" "All services are healthy"
            _emit_docker_event "monitor.service.healthy" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
        else
            _log_docker "WARN" "Some services did not become healthy within timeout"
            _emit_docker_event "monitor.service.unhealthy" "unity-docker" "{\"stack\":\"$stack_name\"}" "high"
        fi
    fi
    
    # Start monitoring for this stack
    _start_stack_monitoring "$stack_name" &
    
    _log_docker "SUCCESS" "Docker stack deployment completed: $stack_name"
    return $UNITY_SUCCESS
}

# Stop Docker Compose stack
stop_docker_stack() {
    local stack_name="$1"
    local remove_volumes="${2:-false}"
    local timeout="${3:-30}"
    
    _log_docker "INFO" "Stopping Docker stack: $stack_name"
    
    # Get stack information
    local stack_info="${UNITY_DOCKER_STACKS[$stack_name]:-}"
    if [[ -z "$stack_info" ]]; then
        _log_docker "WARN" "Stack not found in tracking: $stack_name"
        # Try to find compose file
        local compose_file
        compose_file=$(find "$UNITY_DOCKER_COMPOSE_DIR" -name "*${stack_name}*.yml" | head -1)
        if [[ -z "$compose_file" ]]; then
            _log_docker "ERROR" "Cannot find compose file for stack: $stack_name"
            return $UNITY_ERROR_FILE_NOT_FOUND
        fi
        stack_info="$compose_file|unknown|0"
    fi
    
    local compose_file="${stack_info%%|*}"
    local environment="${stack_info#*|}"
    environment="${environment%%|*}"
    
    # Emit stop event
    _emit_docker_event "docker.compose.stopping" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
    
    # Build compose command
    local env_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.env"
    local compose_cmd="$COMPOSE_CMD -f $compose_file"
    
    if [[ -f "$env_file" ]]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name"
    
    # Stop and remove containers
    local down_args=("--timeout" "$timeout")
    if [[ "$remove_volumes" == "true" ]]; then
        down_args+=("--volumes")
    fi
    
    if $compose_cmd down "${down_args[@]}"; then
        _log_docker "SUCCESS" "Stack stopped successfully: $stack_name"
        
        # Remove from tracking
        unset UNITY_DOCKER_STACKS["$stack_name"]
        
        # Emit stop success event
        _emit_docker_event "docker.compose.stopped" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
    else
        _log_docker "ERROR" "Failed to stop stack: $stack_name"
        _emit_docker_event "docker.compose.stop_failed" "unity-docker" "{\"stack\":\"$stack_name\"}" "high"
        return $UNITY_ERROR_DEPLOYMENT
    fi
    
    return $UNITY_SUCCESS
}

# Restart Docker Compose stack
restart_docker_stack() {
    local stack_name="$1"
    local wait_for_health="${2:-true}"
    
    _log_docker "INFO" "Restarting Docker stack: $stack_name"
    
    # Get stack information
    local stack_info="${UNITY_DOCKER_STACKS[$stack_name]:-}"
    if [[ -z "$stack_info" ]]; then
        _log_docker "ERROR" "Stack not found: $stack_name"
        return $UNITY_ERROR_NOT_FOUND
    fi
    
    local compose_file="${stack_info%%|*}"
    local environment="${stack_info#*|}"
    environment="${environment%%|*}"
    
    # Emit restart event
    _emit_docker_event "docker.compose.restarting" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
    
    # Restart stack
    if stop_docker_stack "$stack_name" "false" "30" && \
       deploy_docker_stack "$compose_file" "$environment" "$stack_name" "" "$wait_for_health" "false"; then
        _log_docker "SUCCESS" "Stack restarted successfully: $stack_name"
        _emit_docker_event "docker.compose.restarted" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
    else
        _log_docker "ERROR" "Failed to restart stack: $stack_name"
        _emit_docker_event "docker.compose.restart_failed" "unity-docker" "{\"stack\":\"$stack_name\"}" "high"
        return $UNITY_ERROR_DEPLOYMENT
    fi
    
    return $UNITY_SUCCESS
}

# Get Docker stack status
get_docker_stack_status() {
    local stack_name="$1"
    local format="${2:-json}"
    
    # Get stack information
    local stack_info="${UNITY_DOCKER_STACKS[$stack_name]:-}"
    if [[ -z "$stack_info" ]]; then
        case "$format" in
            "json")
                echo '{"status": "not_found", "error": "Stack not tracked"}'
                ;;
            *)
                echo "Stack $stack_name not found in tracking"
                ;;
        esac
        return $UNITY_ERROR_NOT_FOUND
    fi
    
    local compose_file="${stack_info%%|*}"
    local environment="${stack_info#*|}"
    environment="${environment%%|*}"
    local created_time="${stack_info##*|}"
    
    # Build compose command
    local env_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.env"
    local compose_cmd="$COMPOSE_CMD -f $compose_file"
    
    if [[ -f "$env_file" ]]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name"
    
    case "$format" in
        "json")
            local status_json
            status_json=$($compose_cmd ps --format json 2>/dev/null || echo '[]')
            local container_count
            container_count=$(echo "$status_json" | jq length 2>/dev/null || echo 0)
            local running_count
            running_count=$(echo "$status_json" | jq '[.[] | select(.State == "running")] | length' 2>/dev/null || echo 0)
            
            cat << EOF
{
  "stack_name": "$stack_name",
  "environment": "$environment",
  "compose_file": "$compose_file",
  "created_time": $created_time,
  "containers": {
    "total": $container_count,
    "running": $running_count
  },
  "services": $status_json
}
EOF
            ;;
        *)
            echo "Stack: $stack_name"
            echo "Environment: $environment"
            echo "Compose File: $compose_file"
            echo "Created: $(date -d @$created_time 2>/dev/null || date)"
            echo ""
            $compose_cmd ps
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# =============================================================================
# VOLUME AND NETWORK MANAGEMENT
# =============================================================================

# Create Docker network with Unity labels
create_docker_network() {
    local network_name="$1"
    local driver="${2:-bridge}"
    local subnet="${3:-}"
    local stack_name="${4:-geusemaker}"
    
    _log_docker "INFO" "Creating Docker network: $network_name"
    
    local create_cmd="docker network create"
    create_cmd="$create_cmd --driver $driver"
    create_cmd="$create_cmd --label com.unity.managed=true"
    create_cmd="$create_cmd --label com.unity.stack=$stack_name"
    create_cmd="$create_cmd --label com.unity.created=$(date +%s)"
    
    if [[ -n "$subnet" ]]; then
        create_cmd="$create_cmd --subnet $subnet"
    fi
    
    create_cmd="$create_cmd $network_name"
    
    if $create_cmd; then
        _log_docker "SUCCESS" "Network created: $network_name"
        UNITY_DOCKER_NETWORKS["$network_name"]="$driver|$subnet|$stack_name|$(date +%s)"
        _emit_docker_event "docker.network.created" "unity-docker" "{\"network\":\"$network_name\",\"driver\":\"$driver\",\"stack\":\"$stack_name\"}" "medium"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "Failed to create network: $network_name"
        return $UNITY_ERROR_DEPLOYMENT
    fi
}

# Remove Docker network
remove_docker_network() {
    local network_name="$1"
    local force="${2:-false}"
    
    _log_docker "INFO" "Removing Docker network: $network_name"
    
    local remove_cmd="docker network rm"
    if [[ "$force" == "true" ]]; then
        remove_cmd="$remove_cmd --force"
    fi
    remove_cmd="$remove_cmd $network_name"
    
    if $remove_cmd; then
        _log_docker "SUCCESS" "Network removed: $network_name"
        unset UNITY_DOCKER_NETWORKS["$network_name"]
        _emit_docker_event "docker.network.removed" "unity-docker" "{\"network\":\"$network_name\"}" "medium"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "Failed to remove network: $network_name"
        return $UNITY_ERROR_DEPLOYMENT
    fi
}

# Create Docker volume with Unity labels
create_docker_volume() {
    local volume_name="$1"
    local driver="${2:-local}"
    local mount_point="${3:-}"
    local stack_name="${4:-geusemaker}"
    
    _log_docker "INFO" "Creating Docker volume: $volume_name"
    
    local create_cmd="docker volume create"
    create_cmd="$create_cmd --driver $driver"
    create_cmd="$create_cmd --label com.unity.managed=true"
    create_cmd="$create_cmd --label com.unity.stack=$stack_name"
    create_cmd="$create_cmd --label com.unity.created=$(date +%s)"
    
    if [[ -n "$mount_point" ]]; then
        create_cmd="$create_cmd --opt type=none --opt o=bind --opt device=$mount_point"
    fi
    
    create_cmd="$create_cmd $volume_name"
    
    if $create_cmd; then
        _log_docker "SUCCESS" "Volume created: $volume_name"
        UNITY_DOCKER_VOLUMES["$volume_name"]="$driver|$mount_point|$stack_name|$(date +%s)"
        _emit_docker_event "docker.volume.created" "unity-docker" "{\"volume\":\"$volume_name\",\"driver\":\"$driver\",\"stack\":\"$stack_name\"}" "medium"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "Failed to create volume: $volume_name"
        return $UNITY_ERROR_DEPLOYMENT
    fi
}

# Remove Docker volume
remove_docker_volume() {
    local volume_name="$1"
    local force="${2:-false}"
    
    _log_docker "INFO" "Removing Docker volume: $volume_name"
    
    local remove_cmd="docker volume rm"
    if [[ "$force" == "true" ]]; then
        remove_cmd="$remove_cmd --force"
    fi
    remove_cmd="$remove_cmd $volume_name"
    
    if $remove_cmd; then
        _log_docker "SUCCESS" "Volume removed: $volume_name"
        unset UNITY_DOCKER_VOLUMES["$volume_name"]
        _emit_docker_event "docker.volume.removed" "unity-docker" "{\"volume\":\"$volume_name\"}" "medium"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "Failed to remove volume: $volume_name"
        return $UNITY_ERROR_DEPLOYMENT
    fi
}

# List Unity-managed networks
list_unity_networks() {
    local format="${1:-table}"
    
    case "$format" in
        "json")
            docker network ls --filter label=com.unity.managed=true --format json
            ;;
        *)
            docker network ls --filter label=com.unity.managed=true
            ;;
    esac
}

# List Unity-managed volumes
list_unity_volumes() {
    local format="${1:-table}"
    
    case "$format" in
        "json")
            docker volume ls --filter label=com.unity.managed=true --format json
            ;;
        *)
            docker volume ls --filter label=com.unity.managed=true
            ;;
    esac
}

# =============================================================================
# LOG AGGREGATION AND STREAMING
# =============================================================================

# Initialize log aggregation system
_init_log_aggregation() {
    _log_docker "INFO" "Initializing log aggregation system"
    
    # Create log aggregation directories
    mkdir -p "$UNITY_DOCKER_LOGS_DIR"/{containers,compose,system,aggregated}
    
    # Create log collection script
    cat > "$UNITY_DOCKER_LOGS_DIR/collect-logs.sh" << 'EOF'
#!/bin/bash
# Unity Docker Log Collection Script
set -euo pipefail

LOGS_DIR="$1"
STACK_NAME="${2:-all}"
RETENTION_HOURS="${3:-24}"

# Collect container logs
if [[ "$STACK_NAME" == "all" ]]; then
    docker ps --filter label=com.unity.managed=true --format "{{.Names}}" | while read -r container; do
        if [[ -n "$container" ]]; then
            docker logs --since "${RETENTION_HOURS}h" "$container" > "$LOGS_DIR/containers/${container}_$(date +%Y%m%d_%H%M%S).log" 2>&1 || true
        fi
    done
else
    docker ps --filter label=com.unity.stack="$STACK_NAME" --format "{{.Names}}" | while read -r container; do
        if [[ -n "$container" ]]; then
            docker logs --since "${RETENTION_HOURS}h" "$container" > "$LOGS_DIR/containers/${container}_$(date +%Y%m%d_%H%M%S).log" 2>&1 || true
        fi
    done
fi

# Collect Docker daemon logs
if [[ -f /var/log/docker.log ]]; then
    tail -n 1000 /var/log/docker.log > "$LOGS_DIR/system/docker_daemon_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null || true
fi

# Collect Docker events
docker events --since "${RETENTION_HOURS}h" --until now > "$LOGS_DIR/system/docker_events_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null || true
EOF
    
    chmod +x "$UNITY_DOCKER_LOGS_DIR/collect-logs.sh"
    
    # Create log rotation script
    cat > "$UNITY_DOCKER_LOGS_DIR/rotate-logs.sh" << EOF
#!/bin/bash
# Unity Docker Log Rotation Script
set -euo pipefail

LOGS_DIR="$UNITY_DOCKER_LOGS_DIR"
RETENTION_DAYS="${DOCKER_LOG_RETENTION_DAYS:-7}"

# Rotate container logs
find "\$LOGS_DIR/containers" -name "*.log" -type f -mtime +\$RETENTION_DAYS -delete 2>/dev/null || true

# Rotate system logs
find "\$LOGS_DIR/system" -name "*.log" -type f -mtime +\$RETENTION_DAYS -delete 2>/dev/null || true

# Compress logs older than 1 day
find "\$LOGS_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true
EOF
    
    chmod +x "$UNITY_DOCKER_LOGS_DIR/rotate-logs.sh"
}

# Start log aggregation process
_start_log_aggregation() {
    local collection_interval="${1:-3600}"  # 1 hour default
    
    while true; do
        "$UNITY_DOCKER_LOGS_DIR/collect-logs.sh" "$UNITY_DOCKER_LOGS_DIR" "all" "1"
        "$UNITY_DOCKER_LOGS_DIR/rotate-logs.sh"
        sleep "$collection_interval"
    done
}

# Stream logs from Docker stack
stream_docker_logs() {
    local stack_name="$1"
    local services="${2:-}"
    local follow="${3:-true}"
    local since="${4:-1h}"
    
    # Get stack information
    local stack_info="${UNITY_DOCKER_STACKS[$stack_name]:-}"
    if [[ -z "$stack_info" ]]; then
        _log_docker "ERROR" "Stack not found: $stack_name"
        return $UNITY_ERROR_NOT_FOUND
    fi
    
    local compose_file="${stack_info%%|*}"
    local environment="${stack_info#*|}"
    environment="${environment%%|*}"
    
    # Build compose command
    local env_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.env"
    local compose_cmd="$COMPOSE_CMD -f $compose_file"
    
    if [[ -f "$env_file" ]]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name logs"
    
    # Add options
    compose_cmd="$compose_cmd --since $since"
    if [[ "$follow" == "true" ]]; then
        compose_cmd="$compose_cmd --follow"
    fi
    
    # Add specific services if provided
    if [[ -n "$services" ]]; then
        compose_cmd="$compose_cmd $services"
    fi
    
    # Stream logs
    _log_docker "INFO" "Streaming logs for stack: $stack_name"
    $compose_cmd
}

# Analyze logs for errors and issues
analyze_docker_logs() {
    local stack_name="${1:-all}"
    local time_range="${2:-24h}"
    local output_file="${3:-}"
    
    _log_docker "INFO" "Analyzing Docker logs for stack: $stack_name"
    
    local analysis_report=""
    local error_count=0
    local warning_count=0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Analyze container logs
    local log_pattern
    if [[ "$stack_name" == "all" ]]; then
        log_pattern="$UNITY_DOCKER_LOGS_DIR/containers/*.log"
    else
        log_pattern="$UNITY_DOCKER_LOGS_DIR/containers/*${stack_name}*.log"
    fi
    
    for log_file in $log_pattern; do
        [[ -f "$log_file" ]] || continue
        
        local container_name
        container_name=$(basename "$log_file" | cut -d'_' -f1)
        
        local errors
        errors=$(grep -c -i "error\|exception\|fatal\|critical" "$log_file" 2>/dev/null || echo "0")
        
        local warnings
        warnings=$(grep -c -i "warn\|warning" "$log_file" 2>/dev/null || echo "0")
        
        if [[ $errors -gt 0 ]] || [[ $warnings -gt 0 ]]; then
            analysis_report+="\nContainer: $container_name\n"
            analysis_report+="  Errors: $errors\n"
            analysis_report+="  Warnings: $warnings\n"
            
            error_count=$((error_count + errors))
            warning_count=$((warning_count + warnings))
            
            # Show recent critical issues
            if [[ $errors -gt 0 ]]; then
                analysis_report+="  Recent Errors:\n"
                grep -i "error\|exception\|fatal\|critical" "$log_file" | tail -3 | sed 's/^/    /' >> analysis_report || true
            fi
        fi
    done
    
    # Generate summary
    local summary="Unity Docker Log Analysis Report\n"
    summary+="Generated: $timestamp\n"
    summary+="Stack: $stack_name\n"
    summary+="Time Range: $time_range\n"
    summary+="Total Errors: $error_count\n"
    summary+="Total Warnings: $warning_count\n"
    summary+="\nDetailed Analysis:\n"
    summary+="$analysis_report\n"
    
    if [[ -n "$output_file" ]]; then
        echo -e "$summary" > "$output_file"
        _log_docker "INFO" "Log analysis report saved to: $output_file"
    else
        echo -e "$summary"
    fi
    
    # Emit analysis event
    _emit_docker_event "monitor.logs.analyzed" "unity-docker" "{\"stack\":\"$stack_name\",\"errors\":$error_count,\"warnings\":$warning_count}" "medium"
    
    return $UNITY_SUCCESS
}

# =============================================================================
# CONTAINER HEALTH MONITORING
# =============================================================================

# Initialize container health monitoring
_start_container_monitoring() {
    local check_interval="${1:-30}"
    
    _log_docker "INFO" "Starting container health monitoring"
    
    while true; do
        _monitor_docker_containers
        sleep "$check_interval"
    done
}

# Monitor Docker containers health
_monitor_docker_containers() {
    # Get all Unity-managed containers
    local containers
    containers=$(docker ps --filter label=com.unity.managed=true --format "{{.Names}}" 2>/dev/null || echo "")
    
    if [[ -z "$containers" ]]; then
        return 0
    fi
    
    echo "$containers" | while read -r container; do
        [[ -n "$container" ]] || continue
        
        local health_status
        health_status=$(docker inspect "$container" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
        
        local running_status
        running_status=$(docker inspect "$container" --format='{{.State.Running}}' 2>/dev/null || echo "false")
        
        case "$health_status" in
            "healthy")
                # Container is healthy
                ;;
            "unhealthy")
                _log_docker "WARN" "Container $container is unhealthy"
                _emit_docker_event "monitor.service.unhealthy" "unity-docker" "{\"container\":\"$container\"}" "high"
                
                # Attempt auto-recovery if enabled
                if [[ "${DOCKER_AUTO_RECOVERY_ENABLED:-true}" == "true" ]]; then
                    _attempt_container_recovery "$container"
                fi
                ;;
            "starting")
                _log_docker "DEBUG" "Container $container health check is starting"
                ;;
            "none")
                # No health check defined, check if running
                if [[ "$running_status" != "true" ]]; then
                    _log_docker "WARN" "Container $container is not running"
                    _emit_docker_event "docker.container.stopped" "unity-docker" "{\"container\":\"$container\"}" "high"
                fi
                ;;
        esac
    done
}

# Attempt container recovery
_attempt_container_recovery() {
    local container="$1"
    local max_attempts="${2:-3}"
    
    _log_docker "INFO" "Attempting recovery for container: $container"
    
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        _log_docker "INFO" "Recovery attempt $attempt for container: $container"
        
        if docker restart "$container" >/dev/null 2>&1; then
            # Wait for health check
            local wait_count=0
            while [[ $wait_count -lt 12 ]]; do  # 2 minutes max
                local health_status
                health_status=$(docker inspect "$container" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
                
                if [[ "$health_status" == "healthy" ]] || [[ "$health_status" == "none" ]]; then
                    _log_docker "SUCCESS" "Container $container recovered successfully"
                    _emit_docker_event "monitor.service.recovered" "unity-docker" "{\"container\":\"$container\",\"attempt\":$attempt}" "medium"
                    return $UNITY_SUCCESS
                fi
                
                sleep 10
                wait_count=$((wait_count + 1))
            done
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            sleep 30  # Wait before next attempt
        fi
    done
    
    _log_docker "ERROR" "Failed to recover container after $max_attempts attempts: $container"
    _emit_docker_event "monitor.service.recovery_failed" "unity-docker" "{\"container\":\"$container\",\"attempts\":$max_attempts}" "high"
    return $UNITY_ERROR_RECOVERY
}

# Wait for stack health
_wait_for_stack_health() {
    local compose_file="$1"
    local env_file="$2"
    local stack_name="$3"
    local max_wait="${4:-300}"  # 5 minutes default
    
    local compose_cmd="$COMPOSE_CMD -f $compose_file"
    if [[ -n "$env_file" && -f "$env_file" ]]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    compose_cmd="$compose_cmd -p $stack_name"
    
    local wait_time=0
    local check_interval=10
    
    while [[ $wait_time -lt $max_wait ]]; do
        # Get service status
        local unhealthy_services
        unhealthy_services=$($compose_cmd ps --format json 2>/dev/null | jq -r '.[] | select(.Health != "healthy" and .Health != "" and .Health != null and .State == "running") | .Service' 2>/dev/null || echo "")
        
        if [[ -z "$unhealthy_services" ]]; then
            return $UNITY_SUCCESS
        fi
        
        _log_docker "INFO" "Waiting for services to be healthy: $(echo "$unhealthy_services" | tr '\n' ' ')"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    _log_docker "WARN" "Some services did not become healthy within ${max_wait}s"
    return $UNITY_ERROR_TIMEOUT
}

# Start stack-specific monitoring
_start_stack_monitoring() {
    local stack_name="$1"
    local check_interval="${2:-60}"
    
    _log_docker "INFO" "Starting monitoring for stack: $stack_name"
    
    while docker ps --filter label=com.unity.stack="$stack_name" --format "{{.Names}}" | grep -q .; do
        # Monitor stack containers
        local containers
        containers=$(docker ps --filter label=com.unity.stack="$stack_name" --format "{{.Names}}")
        
        local total_containers
        total_containers=$(echo "$containers" | wc -l)
        
        local running_containers
        running_containers=$(docker ps --filter label=com.unity.stack="$stack_name" --filter status=running --format "{{.Names}}" | wc -l)
        
        if [[ $running_containers -lt $total_containers ]]; then
            _log_docker "WARN" "Stack $stack_name: $running_containers/$total_containers containers running"
            _emit_docker_event "monitor.stack.degraded" "unity-docker" "{\"stack\":\"$stack_name\",\"running\":$running_containers,\"total\":$total_containers}" "high"
        fi
        
        sleep "$check_interval"
    done
    
    _log_docker "INFO" "Monitoring stopped for stack: $stack_name"
}

# =============================================================================
# IMAGE MANAGEMENT AND UPDATES
# =============================================================================

# Pull latest images for a stack
update_stack_images() {
    local stack_name="$1"
    local auto_restart="${2:-false}"
    
    _log_docker "INFO" "Updating images for stack: $stack_name"
    
    # Get stack information
    local stack_info="${UNITY_DOCKER_STACKS[$stack_name]:-}"
    if [[ -z "$stack_info" ]]; then
        _log_docker "ERROR" "Stack not found: $stack_name"
        return $UNITY_ERROR_NOT_FOUND
    fi
    
    local compose_file="${stack_info%%|*}"
    local environment="${stack_info#*|}"
    environment="${environment%%|*}"
    
    # Build compose command
    local env_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.env"
    local compose_cmd="$COMPOSE_CMD -f $compose_file"
    
    if [[ -f "$env_file" ]]; then
        compose_cmd="$compose_cmd --env-file $env_file"
    fi
    
    compose_cmd="$compose_cmd -p $stack_name"
    
    # Pull images
    _emit_docker_event "docker.images.updating" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
    
    if $compose_cmd pull; then
        _log_docker "SUCCESS" "Images updated for stack: $stack_name"
        _emit_docker_event "docker.images.updated" "unity-docker" "{\"stack\":\"$stack_name\"}" "medium"
        
        # Restart stack if requested
        if [[ "$auto_restart" == "true" ]]; then
            restart_docker_stack "$stack_name" "true"
        fi
    else
        _log_docker "ERROR" "Failed to update images for stack: $stack_name"
        _emit_docker_event "docker.images.update_failed" "unity-docker" "{\"stack\":\"$stack_name\"}" "high"
        return $UNITY_ERROR_DEPLOYMENT
    fi
    
    return $UNITY_SUCCESS
}

# Clean up unused Docker images
cleanup_docker_images() {
    local aggressive="${1:-false}"
    local max_age="${2:-24h}"
    
    _log_docker "INFO" "Cleaning up Docker images"
    
    local cleaned_space=0
    
    # Remove unused images
    if [[ "$aggressive" == "true" ]]; then
        _log_docker "INFO" "Performing aggressive cleanup..."
        local cleanup_output
        cleanup_output=$(docker system prune -af --filter "until=$max_age" 2>&1)
        _log_docker "INFO" "Cleanup result: $cleanup_output"
    else
        # Conservative cleanup
        local dangling_output
        dangling_output=$(docker image prune -f 2>&1)
        _log_docker "INFO" "Dangling images cleanup: $dangling_output"
        
        local unused_output
        unused_output=$(docker image prune -af --filter "until=$max_age" 2>&1)
        _log_docker "INFO" "Unused images cleanup: $unused_output"
    fi
    
    # Clean up build cache
    local build_cache_output
    build_cache_output=$(docker builder prune -f --filter "until=$max_age" 2>&1)
    _log_docker "INFO" "Build cache cleanup: $build_cache_output"
    
    # Show current space usage
    docker system df
    
    _emit_docker_event "docker.images.cleanup_completed" "unity-docker" "{\"aggressive\":\"$aggressive\",\"max_age\":\"$max_age\"}" "medium"
    
    _log_docker "SUCCESS" "Docker image cleanup completed"
    return $UNITY_SUCCESS
}

# List images used by Unity stacks
list_stack_images() {
    local stack_name="${1:-all}"
    local format="${2:-table}"
    
    if [[ "$stack_name" == "all" ]]; then
        case "$format" in
            "json")
                docker images --filter label=com.unity.managed=true --format json
                ;;
            *)
                docker images --filter label=com.unity.managed=true
                ;;
        esac
    else
        case "$format" in
            "json")
                docker images --filter label=com.unity.stack="$stack_name" --format json
                ;;
            *)
                docker images --filter label=com.unity.stack="$stack_name"
                ;;
        esac
    fi
}

# =============================================================================
# GPU SUPPORT FOR AI WORKLOADS
# =============================================================================

# Check if NVIDIA GPU is available
_has_nvidia_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi >/dev/null 2>&1
    else
        false
    fi
}

# Setup NVIDIA Docker support
_setup_nvidia_docker_support() {
    local force_install="${1:-false}"
    
    _log_docker "INFO" "Setting up NVIDIA Docker support"
    
    # Check if already configured
    if [[ "$force_install" != "true" ]] && _is_nvidia_docker_configured; then
        _log_docker "INFO" "NVIDIA Docker runtime already configured"
        return $UNITY_SUCCESS
    fi
    
    # Install NVIDIA Container Toolkit if needed
    if ! command -v nvidia-ctk >/dev/null 2>&1; then
        _install_nvidia_container_toolkit
    fi
    
    # Configure Docker daemon
    _configure_nvidia_docker_runtime
    
    # Validate setup
    if _validate_nvidia_docker_setup; then
        _log_docker "SUCCESS" "NVIDIA Docker support configured successfully"
        _emit_docker_event "docker.gpu.configured" "unity-docker" "{\"gpu_support\":true}" "medium"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "NVIDIA Docker setup validation failed"
        _emit_docker_event "docker.gpu.configuration_failed" "unity-docker" "{\"error\":\"Validation failed\"}" "high"
        return $UNITY_ERROR_PREREQUISITE
    fi
}

# Check if NVIDIA Docker is configured
_is_nvidia_docker_configured() {
    if [[ -f /etc/docker/daemon.json ]]; then
        grep -q "nvidia" /etc/docker/daemon.json 2>/dev/null
    else
        false
    fi
}

# Install NVIDIA Container Toolkit
_install_nvidia_container_toolkit() {
    _log_docker "INFO" "Installing NVIDIA Container Toolkit"
    
    # Detect distribution
    local distro=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    case "$distro" in
        ubuntu|debian)
            _install_nvidia_toolkit_ubuntu
            ;;
        amzn|rhel|centos|fedora)
            _install_nvidia_toolkit_rhel
            ;;
        *)
            _log_docker "WARN" "Unsupported distribution for NVIDIA toolkit: $distro"
            return $UNITY_ERROR_PREREQUISITE
            ;;
    esac
}

# Install NVIDIA toolkit on Ubuntu/Debian
_install_nvidia_toolkit_ubuntu() {
    local distribution
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    
    # Setup repository
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Install toolkit
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
}

# Install NVIDIA toolkit on RHEL-based systems
_install_nvidia_toolkit_rhel() {
    local distribution
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    
    # Setup repository
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | \
        sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    
    # Install toolkit
    sudo yum install -y nvidia-container-toolkit
}

# Configure NVIDIA Docker runtime
_configure_nvidia_docker_runtime() {
    _log_docker "INFO" "Configuring NVIDIA Docker runtime"
    
    # Configure using nvidia-ctk if available
    if command -v nvidia-ctk >/dev/null 2>&1; then
        sudo nvidia-ctk runtime configure --runtime=docker
    else
        # Manual configuration
        _configure_nvidia_runtime_manual
    fi
    
    # Restart Docker daemon
    sudo systemctl restart docker
    
    _log_docker "INFO" "NVIDIA Docker runtime configured"
}

# Manual NVIDIA runtime configuration
_configure_nvidia_runtime_manual() {
    local config_file="/etc/docker/daemon.json"
    
    # Create backup
    if [[ -f "$config_file" ]]; then
        sudo cp "$config_file" "${config_file}.backup"
    fi
    
    # Add NVIDIA runtime
    local nvidia_config='{"runtimes": {"nvidia": {"path": "nvidia-container-runtime", "runtimeArgs": []}}}'
    
    if [[ -f "$config_file" ]]; then
        # Merge with existing config
        local merged_config
        merged_config=$(jq -s '.[0] * .[1]' "$config_file" <(echo "$nvidia_config"))
        echo "$merged_config" | sudo tee "$config_file" > /dev/null
    else
        # Create new config
        echo "$nvidia_config" | sudo tee "$config_file" > /dev/null
    fi
}

# Validate NVIDIA Docker setup
_validate_nvidia_docker_setup() {
    _log_docker "INFO" "Validating NVIDIA Docker setup"
    
    # Test NVIDIA runtime
    if docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.2-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        _log_docker "SUCCESS" "NVIDIA Docker validation passed"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "NVIDIA Docker validation failed"
        return $UNITY_ERROR_VALIDATION
    fi
}

# =============================================================================
# INTERNAL HELPER FUNCTIONS
# =============================================================================

# Initialize Docker service events
_init_docker_service_events() {
    # Register event handlers for Docker service events
    if command -v unity_on_event >/dev/null 2>&1; then
        unity_on_event "deployment.*" "_handle_deployment_event" "priority=high"
        unity_on_event "docker.*" "_handle_docker_event" "priority=medium"
        unity_on_event "monitor.*" "_handle_monitor_event" "priority=medium"
    fi
}

# Handle deployment events
_handle_deployment_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    _log_docker "DEBUG" "Handling deployment event: $event_type from $event_source"
    
    case "$event_type" in
        "deployment.started")
            # Initialize deployment tracking
            ;;
        "deployment.completed")
            # Finalize deployment
            ;;
        "deployment.failed")
            # Handle deployment failure
            ;;
    esac
}

# Handle Docker-specific events
_handle_docker_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    _log_docker "DEBUG" "Handling Docker event: $event_type from $event_source"
    
    # Process Docker-specific events
    case "$event_type" in
        "docker.container.failed")
            # Handle container failure
            ;;
        "docker.compose.deploy_failed")
            # Handle compose deployment failure
            ;;
    esac
}

# Handle monitoring events
_handle_monitor_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    _log_docker "DEBUG" "Handling monitor event: $event_type from $event_source"
    
    # Process monitoring events
    case "$event_type" in
        "monitor.service.unhealthy")
            # Handle service health issues
            ;;
        "monitor.threshold.exceeded")
            # Handle threshold alerts
            ;;
    esac
}

# Emit Docker service events
_emit_docker_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local priority="${4:-medium}"
    
    if command -v unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "$event_type" "$event_source" "$event_data" "$priority"
    fi
}

# Docker service logging
_log_docker() {
    local level="$1"
    local message="$2"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "Docker: $message"
    else
        echo "[$level] Docker: $message" >&2
    fi
}

# Validate Docker installation
_validate_docker_installation() {
    local errors=0
    
    # Check Docker CLI
    if ! command -v docker >/dev/null 2>&1; then
        _log_docker "ERROR" "Docker CLI not found"
        errors=$((errors + 1))
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        _log_docker "ERROR" "Docker daemon not accessible"
        errors=$((errors + 1))
    fi
    
    # Check Docker Compose
    if ! $COMPOSE_CMD version >/dev/null 2>&1; then
        _log_docker "ERROR" "Docker Compose not available"
        errors=$((errors + 1))
    fi
    
    # Check Docker version
    local docker_version
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
    if ! _version_ge "$docker_version" "$UNITY_DOCKER_MIN_VERSION"; then
        _log_docker "WARN" "Docker version $docker_version is below recommended $UNITY_DOCKER_MIN_VERSION"
    fi
    
    return $errors
}

# Check if environment is valid
_is_valid_environment() {
    local environment="$1"
    
    for env in "${DOCKER_ENVIRONMENTS[@]}"; do
        if [[ "$env" == "$environment" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Version comparison function
_version_ge() {
    local version1="$1"
    local version2="$2"
    
    # Simple version comparison - extend as needed
    [[ "$(printf '%s\n' "$version2" "$version1" | sort -V | head -n1)" == "$version2" ]]
}

# Initialize Docker daemon configuration
_init_docker_daemon_config() {
    _log_docker "INFO" "Initializing Docker daemon configuration"
    
    # Check if daemon.json exists and is valid
    local config_file="/etc/docker/daemon.json"
    if [[ -f "$config_file" ]]; then
        if ! python3 -c "import json; json.load(open('$config_file'))" 2>/dev/null; then
            _log_docker "WARN" "Invalid Docker daemon configuration detected"
        fi
    fi
    
    # Store configuration info
    local config_info="{\"config_file\":\"$config_file\",\"log_driver\":\"json-file\",\"log_max_size\":\"$DOCKER_LOG_MAX_SIZE\"}"
    echo "$config_info" > "$UNITY_DOCKER_CONFIG_DIR/daemon-config.json"
}

# Initialize resource monitoring
_init_resource_monitoring() {
    _log_docker "INFO" "Initializing resource monitoring"
    
    # Create monitoring configuration
    cat > "$UNITY_DOCKER_CONFIG_DIR/monitoring.conf" << EOF
# Unity Docker Resource Monitoring Configuration
MONITORING_ENABLED=true
CHECK_INTERVAL=30
RESOURCE_THRESHOLD_CPU=80
RESOURCE_THRESHOLD_MEMORY=85
RESOURCE_THRESHOLD_DISK=90
AUTO_RECOVERY_ENABLED=true
RECOVERY_MAX_ATTEMPTS=3
EOF
}

# Start resource monitoring
_start_resource_monitoring() {
    local check_interval="${1:-60}"
    
    while true; do
        _monitor_docker_resources
        sleep "$check_interval"
    done
}

# Monitor Docker resources
_monitor_docker_resources() {
    # Monitor system resources
    local cpu_usage
    cpu_usage=$(docker stats --no-stream --format "table {{.CPUPerc}}" | tail -n +2 | sed 's/%//' | awk '{sum+=$1} END {print sum}')
    
    local memory_usage
    memory_usage=$(docker stats --no-stream --format "table {{.MemPerc}}" | tail -n +2 | sed 's/%//' | awk '{sum+=$1} END {print sum}')
    
    # Check thresholds
    local cpu_threshold="${RESOURCE_THRESHOLD_CPU:-80}"
    local memory_threshold="${RESOURCE_THRESHOLD_MEMORY:-85}"
    
    if (( $(echo "$cpu_usage > $cpu_threshold" | bc -l) )); then
        _emit_docker_event "monitor.threshold.exceeded" "unity-docker" "{\"metric\":\"cpu\",\"value\":$cpu_usage,\"threshold\":$cpu_threshold}" "high"
    fi
    
    if (( $(echo "$memory_usage > $memory_threshold" | bc -l) )); then
        _emit_docker_event "monitor.threshold.exceeded" "unity-docker" "{\"metric\":\"memory\",\"value\":$memory_usage,\"threshold\":$memory_threshold}" "high"
    fi
}

# Generate default Docker Compose templates
_generate_default_compose_templates() {
    _log_docker "INFO" "Generating default Docker Compose templates"
    
    # Generate templates for each environment
    for env in "${DOCKER_ENVIRONMENTS[@]}"; do
        generate_docker_compose "$env" "geusemaker-template" "postgres,n8n,qdrant,ollama,crawl4ai,redis,nginx" "auto" "$UNITY_DOCKER_COMPOSE_DIR/templates/geusemaker-${env}-template.yml"
    done
}

# Service configuration functions
_show_docker_service_config() {
    echo "Unity Docker Service Configuration:"
    echo "  Version: $UNITY_DOCKER_SERVICE_VERSION"
    echo "  Docker Version: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'N/A')"
    echo "  Compose Command: $COMPOSE_CMD"
    echo "  State Directory: $UNITY_DOCKER_STATE_DIR"
    echo "  GPU Support: $(_has_nvidia_gpu && echo 'Available' || echo 'Not Available')"
    echo "  Environments: ${DOCKER_ENVIRONMENTS[*]}"
    echo "  Default Environment: $DOCKER_DEFAULT_ENVIRONMENT"
}

_set_docker_service_config() {
    local key="$1"
    local value="$2"
    
    case "$key" in
        "default_environment")
            if _is_valid_environment "$value"; then
                DOCKER_DEFAULT_ENVIRONMENT="$value"
                echo "default_environment=$value" > "$UNITY_DOCKER_CONFIG_DIR/user-config.conf"
                _log_docker "INFO" "Default environment set to: $value"
            else
                _log_docker "ERROR" "Invalid environment: $value"
                return $UNITY_ERROR_INVALID_INPUT
            fi
            ;;
        *)
            _log_docker "ERROR" "Unknown configuration key: $key"
            return $UNITY_ERROR_INVALID_INPUT
            ;;
    esac
}

_get_docker_service_config() {
    local key="$1"
    
    case "$key" in
        "default_environment")
            echo "$DOCKER_DEFAULT_ENVIRONMENT"
            ;;
        "version")
            echo "$UNITY_DOCKER_SERVICE_VERSION"
            ;;
        *)
            _log_docker "ERROR" "Unknown configuration key: $key"
            return $UNITY_ERROR_INVALID_INPUT
            ;;
    esac
}

_validate_docker_service_config() {
    local errors=0
    
    # Validate default environment
    if ! _is_valid_environment "$DOCKER_DEFAULT_ENVIRONMENT"; then
        _log_docker "ERROR" "Invalid default environment: $DOCKER_DEFAULT_ENVIRONMENT"
        errors=$((errors + 1))
    fi
    
    # Validate directories exist
    for dir in "$UNITY_DOCKER_STATE_DIR" "$UNITY_DOCKER_COMPOSE_DIR" "$UNITY_DOCKER_LOGS_DIR"; do
        if [[ ! -d "$dir" ]]; then
            _log_docker "ERROR" "Missing directory: $dir"
            errors=$((errors + 1))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        _log_docker "SUCCESS" "Docker service configuration is valid"
        return $UNITY_SUCCESS
    else
        _log_docker "ERROR" "Docker service configuration validation failed ($errors errors)"
        return $UNITY_ERROR_VALIDATION
    fi
}

# Generate service definitions (placeholder functions - implement based on requirements)
_generate_postgres_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    cat >> "$output_file" << 'EOF'
  # PostgreSQL Database
  postgres:
    <<: *common-config
    image: postgres:16.1-alpine3.19
    container_name: geuse_postgres
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_DB=${POSTGRES_DB:-n8n}
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_MAX_CONNECTIONS=${POSTGRES_MAX_CONNECTIONS:-100}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${EFS_MOUNT_PATH:-./data/postgres}:/var/lib/postgresql/backup
    healthcheck:
      <<: *health-check
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n}"]
    deploy:
      resources:
        limits:
          memory: ${POSTGRES_MEMORY_LIMIT:-2G}
          cpus: '${POSTGRES_CPU_LIMIT:-1.0}'

EOF
}

_generate_n8n_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    cat >> "$output_file" << 'EOF'
  # n8n Workflow Automation
  n8n:
    <<: *common-config
    image: n8nio/n8n:1.19.4
    container_name: geuse_n8n
    ports:
      - "5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB:-n8n}
      - DB_POSTGRESDB_USER=${POSTGRES_USER:-postgres}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
    volumes:
      - n8n_data:/home/node/.n8n
      - ${EFS_MOUNT_PATH:-./data/n8n}:/home/node/.n8n/backup
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      <<: *health-check
      test: ["CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1"]

EOF
}

_generate_qdrant_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    cat >> "$output_file" << 'EOF'
  # Qdrant Vector Database
  qdrant:
    <<: *common-config
    image: qdrant/qdrant:v1.7.3
    container_name: geuse_qdrant
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant_data:/qdrant/storage
      - ${EFS_MOUNT_PATH:-./data/qdrant}:/qdrant/backup
    healthcheck:
      <<: *health-check
      test: ["CMD-SHELL", "curl -f http://localhost:6333/health || exit 1"]

EOF
}

_generate_ollama_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    if [[ "$gpu_enabled" == "true" ]]; then
        cat >> "$output_file" << 'EOF'
  # Ollama LLM Server
  ollama:
    <<: [*common-config, *gpu-config]
    image: ollama/ollama:0.1.17
    container_name: geuse_ollama
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_GPU_MEMORY_FRACTION=${OLLAMA_GPU_MEMORY_FRACTION:-0.80}
      - OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS:-2}
    volumes:
      - ollama_data:/root/.ollama
      - ${EFS_MOUNT_PATH:-./data/ollama}:/root/.ollama/backup
    healthcheck:
      <<: *health-check
      test: ["CMD-SHELL", "curl -f http://localhost:11434/api/tags || exit 1"]

EOF
    else
        cat >> "$output_file" << 'EOF'
  # Ollama LLM Server
  ollama:
    <<: *common-config
    image: ollama/ollama:0.1.17
    container_name: geuse_ollama
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS:-2}
    volumes:
      - ollama_data:/root/.ollama
      - ${EFS_MOUNT_PATH:-./data/ollama}:/root/.ollama/backup
    healthcheck:
      <<: *health-check
      test: ["CMD-SHELL", "curl -f http://localhost:11434/api/tags || exit 1"]

EOF
    fi
}

_generate_crawl4ai_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    cat >> "$output_file" << 'EOF'
  # Crawl4AI Web Scraping Service
  crawl4ai:
    <<: *common-config
    image: unclecode/crawl4ai:0.2.77
    container_name: geuse_crawl4ai
    ports:
      - "11235:11235"
    environment:
      - CRAWL4AI_RATE_LIMITING_ENABLED=${CRAWL4AI_RATE_LIMITING_ENABLED:-true}
      - CRAWL4AI_DEFAULT_LIMIT=${CRAWL4AI_DEFAULT_LIMIT:-1000/minute}
      - OLLAMA_HOST=ollama:11434
    volumes:
      - crawl4ai_data:/app/data
      - ${EFS_MOUNT_PATH:-./data/crawl4ai}:/app/backup
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      <<: *health-check
      test: ["CMD-SHELL", "curl -f http://localhost:11235/health || exit 1"]

EOF
}

_generate_redis_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    cat >> "$output_file" << 'EOF'
  # Redis Cache
  redis:
    <<: *common-config
    image: redis:7.2-alpine
    container_name: geuse_redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      <<: *health-check
      test: ["CMD", "redis-cli", "ping"]

EOF
}

_generate_nginx_service() {
    local output_file="$1"
    local environment="$2"
    local gpu_enabled="$3"
    
    cat >> "$output_file" << 'EOF'
  # Nginx Reverse Proxy
  nginx:
    <<: *common-config
    image: nginx:1.25-alpine
    container_name: geuse_nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - nginx_config:/etc/nginx/conf.d
      - nginx_certs:/etc/nginx/certs
    depends_on:
      - n8n
      - qdrant
      - ollama
    healthcheck:
      <<: *health-check
      test: ["CMD", "curl", "-f", "http://localhost/health"]

EOF
}

_generate_networks_section() {
    local output_file="$1"
    local environment="$2"
    
    cat >> "$output_file" << 'EOF'

# =============================================================================
# NETWORKS
# =============================================================================

networks:
  ai_network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: "geuse_ai_bridge"
    ipam:
      config:
        - subnet: "172.20.0.0/16"
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
      - com.unity.environment=ENVIRONMENT_PLACEHOLDER

EOF
}

_generate_volumes_section() {
    local output_file="$1"
    local environment="$2"
    shift 2
    local components=("$@")
    
    cat >> "$output_file" << 'EOF'

# =============================================================================
# VOLUMES
# =============================================================================

volumes:
EOF
    
    for component in "${components[@]}"; do
        case "$component" in
            "postgres")
                cat >> "$output_file" << 'EOF'
  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/postgres
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
            "n8n")
                cat >> "$output_file" << 'EOF'
  n8n_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/n8n
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
            "qdrant")
                cat >> "$output_file" << 'EOF'
  qdrant_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/qdrant
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
            "ollama")
                cat >> "$output_file" << 'EOF'
  ollama_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/ollama
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
            "crawl4ai")
                cat >> "$output_file" << 'EOF'
  crawl4ai_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/crawl4ai
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
            "redis")
                cat >> "$output_file" << 'EOF'
  redis_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/redis
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
            "nginx")
                cat >> "$output_file" << 'EOF'
  nginx_config:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/nginx/config
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
  nginx_certs:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/nginx/certs
    labels:
      - com.unity.managed=true
      - com.unity.stack=STACK_NAME_PLACEHOLDER
  
EOF
                ;;
        esac
    done
}

_generate_secrets_section() {
    local output_file="$1"
    
    cat >> "$output_file" << 'EOF'

# =============================================================================
# SECRETS (for production use)
# =============================================================================

secrets:
  postgres_password:
    file: ${SECRETS_DIR:-./secrets}/postgres_password.txt
  
  n8n_encryption_key:
    file: ${SECRETS_DIR:-./secrets}/n8n_encryption_key.txt
  
  n8n_jwt_secret:
    file: ${SECRETS_DIR:-./secrets}/n8n_jwt_secret.txt
  
  openai_api_key:
    file: ${SECRETS_DIR:-./secrets}/openai_api_key.txt

EOF
}

_substitute_compose_variables() {
    local output_file="$1"
    local environment="$2"
    local stack_name="$3"
    local gpu_enabled="$4"
    
    # Perform variable substitution
    sed -i "s/ENVIRONMENT_PLACEHOLDER/$environment/g" "$output_file"
    sed -i "s/STACK_NAME_PLACEHOLDER/$stack_name/g" "$output_file"
    sed -i "s/GPU_ENABLED_PLACEHOLDER/$gpu_enabled/g" "$output_file"
    sed -i "s/UNITY_DOCKER_SERVICE_VERSION_PLACEHOLDER/$UNITY_DOCKER_SERVICE_VERSION/g" "$output_file"
    sed -i "s/DOCKER_LOG_MAX_SIZE_PLACEHOLDER/$DOCKER_LOG_MAX_SIZE/g" "$output_file"
    sed -i "s/DOCKER_LOG_MAX_FILE_PLACEHOLDER/$DOCKER_LOG_MAX_FILE/g" "$output_file"
    
    # Replace date placeholder
    sed -i "s/\$(date.*)/$(date '+%Y-%m-%d %H:%M:%S')/g" "$output_file"
}

_generate_environment_file() {
    local environment="$1"
    local stack_name="$2"
    
    local env_file="$UNITY_DOCKER_COMPOSE_DIR/environments/${stack_name}-${environment}.env"
    
    cat > "$env_file" << EOF
# Unity Docker Environment File
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
# Environment: $environment
# Stack: $stack_name

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

ENVIRONMENT=$environment
STACK_NAME=$stack_name

# =============================================================================
# DATA DIRECTORIES
# =============================================================================

DATA_DIR=\${EFS_MOUNT_PATH:-./data}
SECRETS_DIR=\${SECRETS_PATH:-./secrets}

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

POSTGRES_DB=n8n
POSTGRES_USER=postgres
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD:-changeme}

# Environment-specific settings
EOF
    
    case "$environment" in
        "dev")
            cat >> "$env_file" << 'EOF'

# Development Environment Settings
POSTGRES_MAX_CONNECTIONS=50
POSTGRES_MEMORY_LIMIT=1G
POSTGRES_CPU_LIMIT=0.5

N8N_LOG_LEVEL=debug
N8N_MEMORY_LIMIT=512M
N8N_CPU_LIMIT=0.25

QDRANT_MEMORY_LIMIT=512M
QDRANT_CPU_LIMIT=0.25

OLLAMA_MEMORY_LIMIT=2G
OLLAMA_CPU_LIMIT=0.5
OLLAMA_MAX_LOADED_MODELS=1

CRAWL4AI_MEMORY_LIMIT=512M
CRAWL4AI_CPU_LIMIT=0.25

EOF
            ;;
        "staging")
            cat >> "$env_file" << 'EOF'

# Staging Environment Settings
POSTGRES_MAX_CONNECTIONS=100
POSTGRES_MEMORY_LIMIT=2G
POSTGRES_CPU_LIMIT=1.0

N8N_LOG_LEVEL=info
N8N_MEMORY_LIMIT=1G
N8N_CPU_LIMIT=0.5

QDRANT_MEMORY_LIMIT=1G
QDRANT_CPU_LIMIT=0.5

OLLAMA_MEMORY_LIMIT=4G
OLLAMA_CPU_LIMIT=1.0
OLLAMA_MAX_LOADED_MODELS=2

CRAWL4AI_MEMORY_LIMIT=1G
CRAWL4AI_CPU_LIMIT=0.5

EOF
            ;;
        "prod")
            cat >> "$env_file" << 'EOF'

# Production Environment Settings
POSTGRES_MAX_CONNECTIONS=200
POSTGRES_MEMORY_LIMIT=4G
POSTGRES_CPU_LIMIT=2.0

N8N_LOG_LEVEL=warn
N8N_MEMORY_LIMIT=2G
N8N_CPU_LIMIT=1.0

QDRANT_MEMORY_LIMIT=2G
QDRANT_CPU_LIMIT=1.0

OLLAMA_MEMORY_LIMIT=8G
OLLAMA_CPU_LIMIT=2.0
OLLAMA_MAX_LOADED_MODELS=3

CRAWL4AI_MEMORY_LIMIT=2G
CRAWL4AI_CPU_LIMIT=1.0

EOF
            ;;
    esac
    
    _log_docker "INFO" "Environment file generated: $env_file"
}

# =============================================================================
# UNITY SERVICE EXPORTS
# =============================================================================

# Export all major functions for external use
export -f init_unity_docker_service
export -f start_unity_docker_service
export -f stop_unity_docker_service
export -f health_unity_docker_service
export -f config_unity_docker_service
export -f generate_docker_compose
export -f deploy_docker_stack
export -f stop_docker_stack
export -f restart_docker_stack
export -f get_docker_stack_status
export -f create_docker_network
export -f remove_docker_network
export -f create_docker_volume
export -f remove_docker_volume
export -f list_unity_networks
export -f list_unity_volumes
export -f stream_docker_logs
export -f analyze_docker_logs
export -f update_stack_images
export -f cleanup_docker_images
export -f list_stack_images

# Mark service as loaded
_log_docker "SUCCESS" "Unity Docker Service Complete v$UNITY_DOCKER_SERVICE_VERSION loaded successfully"