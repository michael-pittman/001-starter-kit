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

# Circuit breaker configuration (configurable via env vars)
DOCKER_CB_MAX_FAILURES="${DOCKER_CB_MAX_FAILURES:-5}"           # Max consecutive failures before opening circuit
DOCKER_CB_TIMEOUT="${DOCKER_CB_TIMEOUT:-300}"                  # Timeout in seconds before attempting recovery
DOCKER_CB_RETRY_INTERVAL="${DOCKER_CB_RETRY_INTERVAL:-60}"     # Initial retry interval in seconds
DOCKER_CB_MAX_RETRY_INTERVAL="${DOCKER_CB_MAX_RETRY_INTERVAL:-1800}" # Max retry interval (30 minutes)
DOCKER_CB_BACKOFF_MULTIPLIER="${DOCKER_CB_BACKOFF_MULTIPLIER:-2}" # Exponential backoff multiplier

# Circuit breaker state
DOCKER_CB_STATE="CLOSED"           # CLOSED, OPEN, HALF_OPEN
DOCKER_CB_FAILURE_COUNT=0          # Current consecutive failure count
DOCKER_CB_LAST_FAILURE_TIME=0      # Timestamp of last failure
DOCKER_CB_CURRENT_RETRY_INTERVAL=0 # Current retry interval for exponential backoff
DOCKER_CB_RECOVERY_ATTEMPTS=0      # Number of recovery attempts made

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
    
    # Check circuit breaker state first
    if [[ "$DOCKER_CB_STATE" == "OPEN" ]]; then
        health_status="degraded"
        health_details="Circuit breaker OPEN (failures: $DOCKER_CB_FAILURE_COUNT)"
    elif [[ "$DOCKER_CB_STATE" == "HALF_OPEN" ]]; then
        health_status="degraded"
        health_details="Circuit breaker HALF_OPEN (recovery attempt)"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        health_status="unhealthy"
        health_details="${health_details}${health_details:+; }Docker daemon not responding"
        echo "$health_status|$health_details"
        unity_emit_event "SERVICE_UNHEALTHY" "docker" "$health_details"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Check container health
    local unhealthy_containers=$(docker ps --filter health=unhealthy --format "{{.Names}}" 2>/dev/null | wc -l)
    if [[ $unhealthy_containers -gt 0 ]]; then
        health_status="degraded"
        health_details="${health_details}${health_details:+; }$unhealthy_containers unhealthy containers"
    fi
    
    # Check disk space
    local disk_usage=$(df -h /var/lib/docker 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && $disk_usage -gt 90 ]]; then
        health_status="degraded"
        health_details="${health_details}${health_details:+; }Docker disk usage at ${disk_usage}%"
    fi
    
    # Include circuit breaker statistics
    if [[ "$DOCKER_CB_FAILURE_COUNT" -gt 0 ]] || [[ "$DOCKER_CB_STATE" != "CLOSED" ]]; then
        health_details="${health_details}${health_details:+; }CB: state=$DOCKER_CB_STATE, failures=$DOCKER_CB_FAILURE_COUNT"
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
                echo "# Circuit Breaker Configuration"
                echo "cb_max_failures=$DOCKER_CB_MAX_FAILURES"
                echo "cb_timeout=$DOCKER_CB_TIMEOUT"
                echo "cb_retry_interval=$DOCKER_CB_RETRY_INTERVAL"
                echo "cb_max_retry_interval=$DOCKER_CB_MAX_RETRY_INTERVAL"
                echo "cb_backoff_multiplier=$DOCKER_CB_BACKOFF_MULTIPLIER"
                echo "# Circuit Breaker Status"
                docker_cb_get_status
            else
                # Return specific configuration
                case "$key" in
                    compose_cmd) echo "$DOCKER_COMPOSE_CMD" ;;
                    compose_files) echo "${DOCKER_COMPOSE_FILES[*]}" ;;
                    health_check_interval) echo "$DOCKER_HEALTH_CHECK_INTERVAL" ;;
                    cb_max_failures) echo "$DOCKER_CB_MAX_FAILURES" ;;
                    cb_timeout) echo "$DOCKER_CB_TIMEOUT" ;;
                    cb_retry_interval) echo "$DOCKER_CB_RETRY_INTERVAL" ;;
                    cb_max_retry_interval) echo "$DOCKER_CB_MAX_RETRY_INTERVAL" ;;
                    cb_backoff_multiplier) echo "$DOCKER_CB_BACKOFF_MULTIPLIER" ;;
                    cb_status) docker_cb_get_status ;;
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
                    if [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]]; then
                        DOCKER_HEALTH_CHECK_INTERVAL="$value"
                        unity_log "INFO" "Set health check interval to: $value seconds"
                    else
                        unity_log "ERROR" "Health check interval must be a positive integer"
                        return $UNITY_ERROR_VALIDATION
                    fi
                    ;;
                cb_max_failures)
                    if [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]]; then
                        DOCKER_CB_MAX_FAILURES="$value"
                        unity_log "INFO" "Set circuit breaker max failures to: $value"
                        unity_emit_event "DOCKER_CB_CONFIG_UPDATED" "docker" "max_failures=$value"
                    else
                        unity_log "ERROR" "Circuit breaker max failures must be a positive integer"
                        return $UNITY_ERROR_VALIDATION
                    fi
                    ;;
                cb_timeout)
                    if [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]]; then
                        DOCKER_CB_TIMEOUT="$value"
                        unity_log "INFO" "Set circuit breaker timeout to: $value seconds"
                        unity_emit_event "DOCKER_CB_CONFIG_UPDATED" "docker" "timeout=$value"
                    else
                        unity_log "ERROR" "Circuit breaker timeout must be a positive integer"
                        return $UNITY_ERROR_VALIDATION
                    fi
                    ;;
                cb_retry_interval)
                    if [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]]; then
                        DOCKER_CB_RETRY_INTERVAL="$value"
                        unity_log "INFO" "Set circuit breaker retry interval to: $value seconds"
                        unity_emit_event "DOCKER_CB_CONFIG_UPDATED" "docker" "retry_interval=$value"
                    else
                        unity_log "ERROR" "Circuit breaker retry interval must be a positive integer"
                        return $UNITY_ERROR_VALIDATION
                    fi
                    ;;
                cb_reset)
                    if [[ "$value" == "true" ]] || [[ "$value" == "1" ]]; then
                        unity_log "INFO" "Manually resetting Docker circuit breaker"
                        docker_cb_record_success
                        unity_emit_event "DOCKER_CB_MANUAL_RESET" "docker" "admin_initiated"
                    else
                        unity_log "ERROR" "Circuit breaker reset value must be 'true' or '1'"
                        return $UNITY_ERROR_VALIDATION
                    fi
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

# Circuit Breaker Implementation for Docker Health Monitoring
# 
# This implements a robust circuit breaker pattern to prevent resource exhaustion
# when Docker monitoring encounters repeated failures. The circuit breaker has
# three states:
# 
# 1. CLOSED: Normal operation, failures are counted
# 2. OPEN: Circuit breaker triggered, monitoring paused with exponential backoff
# 3. HALF_OPEN: Testing recovery, single attempt allowed
#
# Features:
# - Configurable failure threshold and timeouts
# - Exponential backoff with maximum retry interval
# - Comprehensive event emission for monitoring integration
# - Manual reset capability via configuration
# - Detailed status reporting and logging
#
# Environment Variables (Configuration):
# - DOCKER_CB_MAX_FAILURES: Max consecutive failures (default: 5)
# - DOCKER_CB_TIMEOUT: Initial timeout before recovery (default: 300s)
# - DOCKER_CB_RETRY_INTERVAL: Initial retry interval (default: 60s)
# - DOCKER_CB_MAX_RETRY_INTERVAL: Max retry interval (default: 1800s)
# - DOCKER_CB_BACKOFF_MULTIPLIER: Exponential backoff multiplier (default: 2)

# Record a successful operation - reset circuit breaker
docker_cb_record_success() {
    if [[ "$DOCKER_CB_FAILURE_COUNT" -gt 0 ]] || [[ "$DOCKER_CB_STATE" != "CLOSED" ]]; then
        unity_log "INFO" "Docker monitoring recovered - resetting circuit breaker"
        unity_emit_event "DOCKER_CIRCUIT_BREAKER_RESET" "docker" "previous_failures=$DOCKER_CB_FAILURE_COUNT"
    fi
    
    DOCKER_CB_STATE="CLOSED"
    DOCKER_CB_FAILURE_COUNT=0
    DOCKER_CB_LAST_FAILURE_TIME=0
    DOCKER_CB_CURRENT_RETRY_INTERVAL=0
    DOCKER_CB_RECOVERY_ATTEMPTS=0
}

# Record a failure and potentially open circuit breaker
docker_cb_record_failure() {
    local failure_reason="${1:-unknown}"
    local current_time=$(date +%s)
    
    DOCKER_CB_FAILURE_COUNT=$((DOCKER_CB_FAILURE_COUNT + 1))
    DOCKER_CB_LAST_FAILURE_TIME=$current_time
    
    unity_log "WARN" "Docker monitoring failure #$DOCKER_CB_FAILURE_COUNT: $failure_reason"
    
    if [[ $DOCKER_CB_FAILURE_COUNT -ge $DOCKER_CB_MAX_FAILURES ]]; then
        # Open the circuit breaker
        DOCKER_CB_STATE="OPEN"
        DOCKER_CB_CURRENT_RETRY_INTERVAL=$DOCKER_CB_RETRY_INTERVAL
        
        unity_log "ERROR" "Docker circuit breaker OPENED after $DOCKER_CB_FAILURE_COUNT consecutive failures"
        unity_emit_event "DOCKER_CIRCUIT_BREAKER_OPENED" "docker" "failures=$DOCKER_CB_FAILURE_COUNT,reason=$failure_reason"
        
        # Emit critical alert for monitoring systems
        unity_emit_event "DOCKER_MONITORING_CRITICAL" "docker" "circuit_breaker_opened,failures=$DOCKER_CB_FAILURE_COUNT"
    else
        unity_emit_event "DOCKER_MONITORING_DEGRADED" "docker" "failure_count=$DOCKER_CB_FAILURE_COUNT,reason=$failure_reason"
    fi
}

# Check if circuit breaker allows operation
docker_cb_can_proceed() {
    local current_time=$(date +%s)
    
    case "$DOCKER_CB_STATE" in
        "CLOSED")
            return 0  # Can proceed normally
            ;;
        "OPEN")
            # Check if timeout period has elapsed
            local time_since_failure=$((current_time - DOCKER_CB_LAST_FAILURE_TIME))
            if [[ $time_since_failure -ge $DOCKER_CB_CURRENT_RETRY_INTERVAL ]]; then
                # Move to half-open state for recovery attempt
                DOCKER_CB_STATE="HALF_OPEN"
                DOCKER_CB_RECOVERY_ATTEMPTS=$((DOCKER_CB_RECOVERY_ATTEMPTS + 1))
                
                unity_log "INFO" "Docker circuit breaker moving to HALF_OPEN for recovery attempt #$DOCKER_CB_RECOVERY_ATTEMPTS"
                unity_emit_event "DOCKER_CIRCUIT_BREAKER_HALF_OPEN" "docker" "attempt=$DOCKER_CB_RECOVERY_ATTEMPTS"
                
                return 0  # Allow one attempt
            else
                local wait_time=$((DOCKER_CB_CURRENT_RETRY_INTERVAL - time_since_failure))
                unity_log "DEBUG" "Docker circuit breaker OPEN - waiting ${wait_time}s before retry"
                return 1  # Cannot proceed yet
            fi
            ;;
        "HALF_OPEN")
            return 0  # Allow the recovery attempt
            ;;
        *)
            unity_log "ERROR" "Unknown circuit breaker state: $DOCKER_CB_STATE"
            return 1
            ;;
    esac
}

# Handle failure in half-open state
docker_cb_handle_half_open_failure() {
    local failure_reason="${1:-unknown}"
    
    # Back to open state with exponential backoff
    DOCKER_CB_STATE="OPEN"
    DOCKER_CB_FAILURE_COUNT=$((DOCKER_CB_FAILURE_COUNT + 1))
    DOCKER_CB_LAST_FAILURE_TIME=$(date +%s)
    
    # Apply exponential backoff
    DOCKER_CB_CURRENT_RETRY_INTERVAL=$((DOCKER_CB_CURRENT_RETRY_INTERVAL * DOCKER_CB_BACKOFF_MULTIPLIER))
    if [[ $DOCKER_CB_CURRENT_RETRY_INTERVAL -gt $DOCKER_CB_MAX_RETRY_INTERVAL ]]; then
        DOCKER_CB_CURRENT_RETRY_INTERVAL=$DOCKER_CB_MAX_RETRY_INTERVAL
    fi
    
    unity_log "ERROR" "Docker recovery attempt failed - circuit breaker back to OPEN (retry in ${DOCKER_CB_CURRENT_RETRY_INTERVAL}s)"
    unity_emit_event "DOCKER_CIRCUIT_BREAKER_RECOVERY_FAILED" "docker" "attempt=$DOCKER_CB_RECOVERY_ATTEMPTS,next_retry=${DOCKER_CB_CURRENT_RETRY_INTERVAL}s,reason=$failure_reason"
}

# Get circuit breaker status for monitoring
docker_cb_get_status() {
    local current_time=$(date +%s)
    local time_since_failure=0
    
    if [[ $DOCKER_CB_LAST_FAILURE_TIME -gt 0 ]]; then
        time_since_failure=$((current_time - DOCKER_CB_LAST_FAILURE_TIME))
    fi
    
    echo "state=$DOCKER_CB_STATE"
    echo "failure_count=$DOCKER_CB_FAILURE_COUNT"
    echo "recovery_attempts=$DOCKER_CB_RECOVERY_ATTEMPTS"
    echo "time_since_last_failure=${time_since_failure}s"
    echo "current_retry_interval=${DOCKER_CB_CURRENT_RETRY_INTERVAL}s"
    echo "max_failures=$DOCKER_CB_MAX_FAILURES"
}

# Monitor container health with circuit breaker protection
monitor_docker_containers() {
    unity_log "INFO" "Starting Docker container monitoring with circuit breaker protection"
    unity_emit_event "DOCKER_MONITORING_STARTED" "docker" "circuit_breaker_enabled=true"
    
    local monitoring_iteration=0
    local successful_checks=0
    
    while true; do
        monitoring_iteration=$((monitoring_iteration + 1))
        
        # Check if circuit breaker allows proceeding
        if ! docker_cb_can_proceed; then
            # Circuit breaker is open, wait for the specified interval
            unity_log "DEBUG" "Circuit breaker OPEN - sleeping ${DOCKER_CB_CURRENT_RETRY_INTERVAL}s before next attempt"
            sleep "$DOCKER_CB_CURRENT_RETRY_INTERVAL"
            continue
        fi
        
        # Perform health check with error handling
        local check_start_time=$(date +%s)
        local check_failed=false
        local failure_reason=""
        local containers=""
        local container_count=0
        
        unity_log "DEBUG" "Performing Docker health check #$monitoring_iteration (CB state: $DOCKER_CB_STATE)"
        
        # Attempt to get Docker daemon status first
        if ! docker info >/dev/null 2>&1; then
            check_failed=true
            failure_reason="docker_daemon_unresponsive"
            unity_log "ERROR" "Docker daemon not responding during health check"
        else
            # Get running containers with timeout protection
            if ! containers=$(timeout 30 docker ps --format "{{.Names}}" 2>&1); then
                check_failed=true
                failure_reason="docker_ps_timeout"
                unity_log "ERROR" "Docker ps command timed out or failed"
            else
                container_count=$(echo "$containers" | wc -w)
                unity_log "DEBUG" "Found $container_count running containers"
                
                # Check individual container health
                local unhealthy_containers=0
                local failed_containers=0
                
                for container in $containers; do
                    if [[ -z "$container" ]]; then
                        continue
                    fi
                    
                    # Check container status with timeout
                    local status=""
                    local health=""
                    
                    if ! status=$(timeout 10 docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null); then
                        unity_log "WARN" "Failed to inspect container status: $container"
                        failed_containers=$((failed_containers + 1))
                        continue
                    fi
                    
                    if ! health=$(timeout 10 docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null); then
                        health="none"  # Container might not have health checks defined
                    fi
                    
                    # Evaluate container state
                    if [[ "$status" != "running" ]]; then
                        unity_emit_event "CONTAINER_DOWN" "docker" "$container:$status"
                        unity_log "WARN" "Container not running: $container ($status)"
                        failed_containers=$((failed_containers + 1))
                    elif [[ "$health" == "unhealthy" ]]; then
                        unity_emit_event "CONTAINER_UNHEALTHY" "docker" "$container"
                        unity_log "WARN" "Container unhealthy: $container"
                        unhealthy_containers=$((unhealthy_containers + 1))
                    fi
                done
                
                # Evaluate overall health check result
                if [[ $failed_containers -gt 0 ]]; then
                    failure_reason="containers_failed:$failed_containers"
                    unity_log "WARN" "Health check found $failed_containers failed containers"
                fi
                
                if [[ $unhealthy_containers -gt 0 ]]; then
                    unity_log "WARN" "Health check found $unhealthy_containers unhealthy containers"
                    # Unhealthy containers are a warning but not a circuit breaker failure
                fi
            fi
        fi
        
        local check_duration=$(($(date +%s) - check_start_time))
        
        # Handle the result based on circuit breaker state
        if [[ "$check_failed" == "true" ]]; then
            unity_log "ERROR" "Docker health check failed after ${check_duration}s: $failure_reason"
            unity_emit_event "DOCKER_HEALTH_CHECK_FAILED" "docker" "iteration=$monitoring_iteration,duration=${check_duration}s,reason=$failure_reason"
            
            if [[ "$DOCKER_CB_STATE" == "HALF_OPEN" ]]; then
                # Recovery attempt failed
                docker_cb_handle_half_open_failure "$failure_reason"
            else
                # Regular failure
                docker_cb_record_failure "$failure_reason"
            fi
            
            # If circuit breaker just opened, sleep longer before continuing
            if [[ "$DOCKER_CB_STATE" == "OPEN" ]]; then
                unity_log "INFO" "Circuit breaker opened - will retry in ${DOCKER_CB_CURRENT_RETRY_INTERVAL}s"
                sleep "$DOCKER_CB_CURRENT_RETRY_INTERVAL"
                continue
            fi
        else
            # Health check succeeded
            successful_checks=$((successful_checks + 1))
            unity_log "DEBUG" "Docker health check #$monitoring_iteration successful (${check_duration}s, containers: $container_count)"
            unity_emit_event "DOCKER_HEALTH_CHECK_SUCCESS" "docker" "iteration=$monitoring_iteration,duration=${check_duration}s,containers=$container_count"
            
            # Record success (this may reset the circuit breaker)
            docker_cb_record_success
        fi
        
        # Emit periodic status updates
        if [[ $((monitoring_iteration % 10)) -eq 0 ]]; then
            unity_log "INFO" "Docker monitoring status: iteration=$monitoring_iteration, successful_checks=$successful_checks, CB_state=$DOCKER_CB_STATE"
            unity_emit_event "DOCKER_MONITORING_STATUS" "docker" "$(docker_cb_get_status | tr '\n' ',' | sed 's/,$//')"
        fi
        
        # Normal sleep interval between checks
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

# Export circuit breaker functions
export -f docker_cb_record_success
export -f docker_cb_record_failure
export -f docker_cb_can_proceed
export -f docker_cb_handle_half_open_failure
export -f docker_cb_get_status