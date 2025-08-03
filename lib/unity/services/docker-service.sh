#!/bin/bash
# Unity Docker Service - Unified Docker operations interface

# Service metadata
SERVICE_NAME="docker"
SERVICE_VERSION="1.0.0"
SERVICE_DESCRIPTION="Unified Docker and container management"

# Docker service state
DOCKER_SERVICE_INITIALIZED=false
DOCKER_COMPOSE_FILES=()
DOCKER_HEALTH_CHECK_INTERVAL=30

# Initialize Docker service
init_docker_service() {
    unity_log "INFO" "Initializing Docker service..."
    
    # Validate Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        unity_log "ERROR" "Docker not found"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        unity_log "ERROR" "Docker daemon not running"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Check Docker Compose
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        unity_log "ERROR" "Docker Compose not found"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Load Docker configuration
    DOCKER_COMPOSE_FILES=("docker-compose.yml" "docker-compose.gpu-optimized.yml")
    
    DOCKER_SERVICE_INITIALIZED=true
    unity_log "INFO" "Docker service initialized successfully"
    return $UNITY_SUCCESS
}

# Start Docker service
start_docker_service() {
    if [[ "$DOCKER_SERVICE_INITIALIZED" != "true" ]]; then
        unity_log "ERROR" "Docker service not initialized"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    unity_log "INFO" "Starting Docker service monitoring..."
    
    # Start container health monitoring
    monitor_docker_containers &
    
    unity_emit_event "SERVICE_STARTED" "docker" ""
    return $UNITY_SUCCESS
}

# Stop Docker service
stop_docker_service() {
    unity_log "INFO" "Stopping Docker service..."
    
    # Stop background processes
    pkill -f "monitor_docker_containers" 2>/dev/null || true
    
    unity_emit_event "SERVICE_STOPPED" "docker" ""
    return $UNITY_SUCCESS
}

# Check Docker service health
health_docker_service() {
    local health_status="healthy"
    local health_details=""
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        health_status="unhealthy"
        health_details="Docker daemon not responding"
        echo "$health_status|$health_details"
        unity_emit_event "SERVICE_UNHEALTHY" "docker" "$health_details"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Check container health
    local unhealthy_containers=$(docker ps --filter health=unhealthy --format "{{.Names}}" 2>/dev/null | wc -l)
    if [[ $unhealthy_containers -gt 0 ]]; then
        health_status="degraded"
        health_details="$unhealthy_containers unhealthy containers"
    fi
    
    # Check disk space
    local disk_usage=$(df -h /var/lib/docker 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && $disk_usage -gt 90 ]]; then
        health_status="degraded"
        health_details="${health_details}; Docker disk usage at ${disk_usage}%"
    fi
    
    echo "$health_status|$health_details"
    
    if [[ "$health_status" == "unhealthy" ]]; then
        unity_emit_event "SERVICE_UNHEALTHY" "docker" "$health_details"
        return $UNITY_ERROR_EXECUTION
    fi
    
    return $UNITY_SUCCESS
}

# Configure Docker service
config_docker_service() {
    local action="${1:-get}"
    local key="$2"
    local value="$3"
    
    case "$action" in
        get)
            if [[ -z "$key" ]]; then
                # Return all configuration
                echo "compose_cmd=$DOCKER_COMPOSE_CMD"
                echo "compose_files=${DOCKER_COMPOSE_FILES[*]}"
                echo "health_check_interval=$DOCKER_HEALTH_CHECK_INTERVAL"
            else
                # Return specific configuration
                case "$key" in
                    compose_cmd) echo "$DOCKER_COMPOSE_CMD" ;;
                    compose_files) echo "${DOCKER_COMPOSE_FILES[*]}" ;;
                    health_check_interval) echo "$DOCKER_HEALTH_CHECK_INTERVAL" ;;
                    *) unity_log "WARN" "Unknown configuration key: $key" ;;
                esac
            fi
            ;;
            
        set)
            if [[ -z "$key" || -z "$value" ]]; then
                unity_log "ERROR" "Configuration key and value required"
                return $UNITY_ERROR_VALIDATION
            fi
            
            case "$key" in
                compose_files)
                    IFS=',' read -ra DOCKER_COMPOSE_FILES <<< "$value"
                    unity_log "INFO" "Set Docker Compose files to: ${DOCKER_COMPOSE_FILES[*]}"
                    ;;
                health_check_interval)
                    DOCKER_HEALTH_CHECK_INTERVAL="$value"
                    unity_log "INFO" "Set health check interval to: $value"
                    ;;
                *)
                    unity_log "ERROR" "Unknown configuration key: $key"
                    return $UNITY_ERROR_VALIDATION
                    ;;
            esac
            
            unity_emit_event "CONFIG_UPDATED" "docker" "$key=$value"
            ;;
            
        *)
            unity_log "ERROR" "Unknown action: $action"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# Docker-specific functions

# Validate Docker Compose files
validate_docker_compose() {
    local compose_file="${1:-docker-compose.yml}"
    
    unity_log "INFO" "Validating Docker Compose file: $compose_file"
    
    if [[ ! -f "$compose_file" ]]; then
        unity_log "ERROR" "Compose file not found: $compose_file"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Validate syntax
    if ! $DOCKER_COMPOSE_CMD -f "$compose_file" config >/dev/null 2>&1; then
        unity_log "ERROR" "Invalid Docker Compose syntax in: $compose_file"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Check for required services
    local required_services=("n8n" "ollama" "qdrant" "postgres")
    for service in "${required_services[@]}"; do
        if ! $DOCKER_COMPOSE_CMD -f "$compose_file" config --services | grep -q "^$service$"; then
            unity_log "WARN" "Required service missing: $service"
        fi
    done
    
    unity_log "INFO" "Docker Compose validation successful"
    return $UNITY_SUCCESS
}

# Start containers
start_docker_containers() {
    local compose_file="${1:-docker-compose.yml}"
    local stack_name="${2:-unity}"
    
    unity_log "INFO" "Starting Docker containers from: $compose_file"
    
    # Validate compose file first
    validate_docker_compose "$compose_file" || return $?
    
    # Start containers
    if $DOCKER_COMPOSE_CMD -f "$compose_file" -p "$stack_name" up -d; then
        unity_log "INFO" "Docker containers started successfully"
        unity_emit_event "CONTAINERS_STARTED" "docker" "$stack_name"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "Failed to start Docker containers"
        return $UNITY_ERROR_EXECUTION
    fi
}

# Stop containers
stop_docker_containers() {
    local compose_file="${1:-docker-compose.yml}"
    local stack_name="${2:-unity}"
    
    unity_log "INFO" "Stopping Docker containers"
    
    if $DOCKER_COMPOSE_CMD -f "$compose_file" -p "$stack_name" down; then
        unity_log "INFO" "Docker containers stopped successfully"
        unity_emit_event "CONTAINERS_STOPPED" "docker" "$stack_name"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "Failed to stop Docker containers"
        return $UNITY_ERROR_EXECUTION
    fi
}

# Monitor container health
monitor_docker_containers() {
    while true; do
        unity_log "DEBUG" "Checking container health..."
        
        # Get all running containers
        local containers=$(docker ps --format "{{.Names}}")
        
        for container in $containers; do
            # Check container status
            local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            
            if [[ "$status" != "running" ]]; then
                unity_emit_event "CONTAINER_DOWN" "docker" "$container:$status"
                unity_log "WARN" "Container not running: $container ($status)"
            elif [[ "$health" == "unhealthy" ]]; then
                unity_emit_event "CONTAINER_UNHEALTHY" "docker" "$container"
                unity_log "WARN" "Container unhealthy: $container"
            fi
        done
        
        sleep "$DOCKER_HEALTH_CHECK_INTERVAL"
    done
}

# Get container logs
get_docker_logs() {
    local container="$1"
    local lines="${2:-100}"
    
    unity_log "INFO" "Getting logs for container: $container"
    
    if docker logs --tail "$lines" "$container" 2>&1; then
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "Failed to get logs for container: $container"
        return $UNITY_ERROR_EXECUTION
    fi
}

# Export service functions
export -f init_docker_service
export -f start_docker_service
export -f stop_docker_service
export -f health_docker_service
export -f config_docker_service
export -f validate_docker_compose
export -f start_docker_containers
export -f stop_docker_containers
export -f monitor_docker_containers
export -f get_docker_logs