#!/usr/bin/env bash
# =============================================================================
# Application Base Module
# Common dependencies and utilities for application modules
# =============================================================================

# Prevent multiple sourcing
[ -n "${_APPLICATION_BASE_SH_LOADED:-}" ] && return 0
declare -gr _APPLICATION_BASE_SH_LOADED=1

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common dependencies using dependency groups
source "${SCRIPT_DIR}/../core/dependency-groups.sh"
load_dependency_group "CORE" "$SCRIPT_DIR/.."
load_module_dependency "config/variables.sh" "$SCRIPT_DIR/.."

# Ensure logging is available
if ! command -v log_info >/dev/null 2>&1; then
    # Basic logging fallback
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# =============================================================================
# APPLICATION CONSTANTS
# =============================================================================

# Application service ports
declare -gr APP_PORT_N8N=5678
declare -gr APP_PORT_OLLAMA=11434
declare -gr APP_PORT_QDRANT=6333
declare -gr APP_PORT_CRAWL4AI=11235
declare -gr APP_PORT_POSTGRES=5432

# Health check configuration
declare -gr APP_HEALTH_CHECK_INTERVAL=30
declare -gr APP_HEALTH_CHECK_TIMEOUT=5
declare -gr APP_HEALTH_CHECK_RETRIES=3
declare -gr APP_STARTUP_GRACE_PERIOD=300

# Docker configuration
declare -gr APP_DOCKER_NETWORK="ai-stack"
declare -gr APP_DOCKER_COMPOSE_VERSION="2.21.0"
declare -gr APP_DOCKER_RESTART_POLICY="unless-stopped"

# Resource limits
declare -gr APP_DEFAULT_MEMORY_LIMIT="2G"
declare -gr APP_DEFAULT_CPU_LIMIT="1.0"

# =============================================================================
# COMMON APPLICATION FUNCTIONS
# =============================================================================

# Check if a service is healthy
check_service_health() {
    local service_name="$1"
    local port="$2"
    local endpoint="${3:-/health}"
    local timeout="${4:-$APP_HEALTH_CHECK_TIMEOUT}"
    
    log_info "Checking health of $service_name on port $port"
    
    # Try curl with timeout
    if curl -sf -m "$timeout" "http://localhost:$port$endpoint" >/dev/null 2>&1; then
        log_info "$service_name is healthy"
        return 0
    else
        log_warn "$service_name health check failed"
        return 1
    fi
}

# Wait for service to become healthy
wait_for_service() {
    local service_name="$1"
    local port="$2"
    local max_wait="${3:-$APP_STARTUP_GRACE_PERIOD}"
    local endpoint="${4:-/health}"
    
    log_info "Waiting for $service_name to become healthy (max ${max_wait}s)"
    
    local start_time=$(date +%s)
    local attempt=1
    
    while true; do
        if check_service_health "$service_name" "$port" "$endpoint"; then
            local elapsed=$(($(date +%s) - start_time))
            log_info "$service_name became healthy after ${elapsed}s"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $max_wait ]]; then
            log_error "$service_name failed to become healthy within ${max_wait}s"
            return 1
        fi
        
        log_info "Attempt $attempt: $service_name not ready yet, waiting..."
        sleep $APP_HEALTH_CHECK_INTERVAL
        ((attempt++))
    done
}

# Get Docker container status
get_container_status() {
    local container_name="$1"
    
    docker inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null || echo "not-found"
}

# Check if container is running
is_container_running() {
    local container_name="$1"
    
    [[ "$(get_container_status "$container_name")" == "running" ]]
}

# Get container logs
get_container_logs() {
    local container_name="$1"
    local lines="${2:-100}"
    local since="${3:-5m}"
    
    docker logs "$container_name" --tail "$lines" --since "$since" 2>&1
}

# Parse Docker Compose service configuration
parse_compose_service() {
    local compose_file="$1"
    local service_name="$2"
    local property="${3:-}"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    # Use yq if available, otherwise try basic parsing
    if command -v yq >/dev/null 2>&1; then
        if [[ -n "$property" ]]; then
            yq eval ".services.$service_name.$property" "$compose_file" 2>/dev/null
        else
            yq eval ".services.$service_name" "$compose_file" 2>/dev/null
        fi
    else
        log_warn "yq not found, using basic parsing"
        # Basic grep-based parsing for simple cases
        if [[ -n "$property" ]]; then
            grep -A 10 "^  $service_name:" "$compose_file" | grep "    $property:" | cut -d':' -f2- | xargs
        fi
    fi
}

# Generate application-specific environment file
generate_app_env_file() {
    local stack_name="$1"
    local output_file="$2"
    local additional_vars="${3:-}"
    
    log_info "Generating application environment file: $output_file"
    
    # Base environment variables
    cat > "$output_file" << EOF
# Generated environment file for $stack_name
# Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Stack configuration
STACK_NAME=$stack_name
ENVIRONMENT=${ENVIRONMENT:-production}
AWS_REGION=${AWS_REGION:-us-east-1}

# Application ports
N8N_PORT=$APP_PORT_N8N
OLLAMA_PORT=$APP_PORT_OLLAMA
QDRANT_PORT=$APP_PORT_QDRANT
CRAWL4AI_PORT=$APP_PORT_CRAWL4AI
POSTGRES_PORT=$APP_PORT_POSTGRES

# Docker configuration
DOCKER_NETWORK=$APP_DOCKER_NETWORK
RESTART_POLICY=$APP_DOCKER_RESTART_POLICY

# Resource limits
DEFAULT_MEMORY_LIMIT=$APP_DEFAULT_MEMORY_LIMIT
DEFAULT_CPU_LIMIT=$APP_DEFAULT_CPU_LIMIT

EOF
    
    # Add additional variables if provided
    if [[ -n "$additional_vars" ]]; then
        echo "" >> "$output_file"
        echo "# Additional configuration" >> "$output_file"
        echo "$additional_vars" >> "$output_file"
    fi
    
    # Add secrets from Parameter Store if available
    if command -v aws >/dev/null 2>&1; then
        log_info "Attempting to load secrets from Parameter Store"
        
        local secrets=(
            "OPENAI_API_KEY=/aibuildkit/OPENAI_API_KEY"
            "N8N_ENCRYPTION_KEY=/aibuildkit/n8n/ENCRYPTION_KEY"
            "POSTGRES_PASSWORD=/aibuildkit/POSTGRES_PASSWORD"
            "WEBHOOK_URL=/aibuildkit/WEBHOOK_URL"
        )
        
        echo "" >> "$output_file"
        echo "# Secrets from Parameter Store" >> "$output_file"
        
        for secret_mapping in "${secrets[@]}"; do
            local var_name="${secret_mapping%%=*}"
            local param_name="${secret_mapping#*=}"
            
            local value
            value=$(aws ssm get-parameter --name "$param_name" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || true)
            
            if [[ -n "$value" && "$value" != "null" ]]; then
                echo "${var_name}='${value}'" >> "$output_file"
            else
                echo "# ${var_name}=<not-found-in-parameter-store>" >> "$output_file"
            fi
        done
    fi
    
    chmod 600 "$output_file"  # Restrict permissions for security
    log_info "Environment file generated successfully"
}

# Validate application configuration
validate_app_config() {
    local compose_file="${1:-docker-compose.yml}"
    
    log_info "Validating application configuration"
    
    # Check if compose file exists
    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    # Validate Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        return 1
    fi
    
    # Validate Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        return 1
    fi
    
    # Validate compose file syntax
    if ! docker compose -f "$compose_file" config >/dev/null 2>&1; then
        log_error "Invalid Docker Compose configuration"
        return 1
    fi
    
    # Check required services are defined
    local required_services=("n8n" "ollama" "postgres")
    for service in "${required_services[@]}"; do
        if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
            log_warn "Required service '$service' not found in compose file"
        fi
    done
    
    log_info "Application configuration validated successfully"
    return 0
}

# =============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# =============================================================================

# Start application services
start_app_services() {
    local compose_file="${1:-docker-compose.yml}"
    local services="${2:-}"  # Space-separated list of services, empty for all
    
    log_info "Starting application services"
    
    if [[ -n "$services" ]]; then
        docker compose -f "$compose_file" up -d $services
    else
        docker compose -f "$compose_file" up -d
    fi
}

# Stop application services
stop_app_services() {
    local compose_file="${1:-docker-compose.yml}"
    local services="${2:-}"  # Space-separated list of services, empty for all
    
    log_info "Stopping application services"
    
    if [[ -n "$services" ]]; then
        docker compose -f "$compose_file" stop $services
    else
        docker compose -f "$compose_file" stop
    fi
}

# Restart application service
restart_app_service() {
    local service_name="$1"
    local compose_file="${2:-docker-compose.yml}"
    
    log_info "Restarting service: $service_name"
    
    docker compose -f "$compose_file" restart "$service_name"
}

# Get application service logs
get_app_logs() {
    local service_name="${1:-}"
    local compose_file="${2:-docker-compose.yml}"
    local lines="${3:-100}"
    
    if [[ -n "$service_name" ]]; then
        docker compose -f "$compose_file" logs --tail "$lines" "$service_name"
    else
        docker compose -f "$compose_file" logs --tail "$lines"
    fi
}

# Export for compatibility
export APPLICATION_BASE_LOADED=1