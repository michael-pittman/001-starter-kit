#!/bin/bash
# Unity Service Recovery System
# Implements error recovery, retry logic, and rollback mechanisms for services
# Ensures system resilience and automatic healing capabilities

set -euo pipefail

# Version detection for compatibility
BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"

# Recovery configuration
UNITY_RECOVERY_MAX_RETRIES="${UNITY_RECOVERY_MAX_RETRIES:-3}"
UNITY_RECOVERY_RETRY_DELAY="${UNITY_RECOVERY_RETRY_DELAY:-5}"
UNITY_RECOVERY_BACKOFF_MULTIPLIER="${UNITY_RECOVERY_BACKOFF_MULTIPLIER:-2}"
UNITY_RECOVERY_TIMEOUT="${UNITY_RECOVERY_TIMEOUT:-300}"  # 5 minutes

# Recovery state tracking (bash 3/4 compatible)
declare -A SERVICE_RECOVERY_STATE 2>/dev/null || SERVICE_RECOVERY_STATE=()
declare -A SERVICE_RECOVERY_ATTEMPTS 2>/dev/null || SERVICE_RECOVERY_ATTEMPTS=()
declare -A SERVICE_RECOVERY_STRATEGY 2>/dev/null || SERVICE_RECOVERY_STRATEGY=()
declare -A SERVICE_ROLLBACK_HANDLERS 2>/dev/null || SERVICE_ROLLBACK_HANDLERS=()

# Source logging if available
if [[ -f "${MODULES_DIR:-}/core/logging.sh" ]]; then
    source "${MODULES_DIR}/core/logging.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*" || true; }
fi

# Recovery strategies
RECOVERY_STRATEGY_RETRY="retry"
RECOVERY_STRATEGY_RESTART="restart"
RECOVERY_STRATEGY_FAILOVER="failover"
RECOVERY_STRATEGY_ROLLBACK="rollback"
RECOVERY_STRATEGY_NONE="none"

# Initialize recovery system
init_recovery_system() {
    log_debug "Initializing Unity recovery system"
    
    # Clear any existing recovery state
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_RECOVERY_STATE=()
        SERVICE_RECOVERY_ATTEMPTS=()
        SERVICE_RECOVERY_STRATEGY=()
        SERVICE_ROLLBACK_HANDLERS=()
    else
        # Bash 3: Clear variables
        for var in $(compgen -v | grep "^SERVICE_RECOVERY_"); do
            unset "$var"
        done
    fi
    
    # Create recovery state directory
    local recovery_dir="${UNITY_STATE_DIR:-/tmp/unity}/recovery"
    mkdir -p "$recovery_dir" 2>/dev/null || true
    
    return 0
}

# Register service recovery strategy
register_recovery_strategy() {
    local service_name="$1"
    local strategy="${2:-$RECOVERY_STRATEGY_RETRY}"
    local max_retries="${3:-$UNITY_RECOVERY_MAX_RETRIES}"
    
    log_debug "Registering recovery strategy for $service_name: $strategy (max retries: $max_retries)"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_RECOVERY_STRATEGY["$service_name"]="$strategy"
        SERVICE_RECOVERY_ATTEMPTS["$service_name"]="0"
        SERVICE_RECOVERY_STATE["$service_name"]="healthy"
    else
        # Bash 3 compatibility
        eval "SERVICE_RECOVERY_${service_name}_STRATEGY='$strategy'"
        eval "SERVICE_RECOVERY_${service_name}_ATTEMPTS='0'"
        eval "SERVICE_RECOVERY_${service_name}_STATE='healthy'"
        eval "SERVICE_RECOVERY_${service_name}_MAX_RETRIES='$max_retries'"
    fi
}

# Register rollback handler
register_rollback_handler() {
    local service_name="$1"
    local rollback_function="$2"
    
    log_debug "Registering rollback handler for $service_name: $rollback_function"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_ROLLBACK_HANDLERS["$service_name"]="$rollback_function"
    else
        eval "SERVICE_RECOVERY_${service_name}_ROLLBACK='$rollback_function'"
    fi
}

# Get service recovery state
get_recovery_state() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${SERVICE_RECOVERY_STATE[$service_name]:-healthy}"
    else
        local state_var="SERVICE_RECOVERY_${service_name}_STATE"
        echo "${!state_var:-healthy}"
    fi
}

# Set service recovery state
set_recovery_state() {
    local service_name="$1"
    local state="$2"
    
    log_debug "Setting recovery state for $service_name: $state"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_RECOVERY_STATE["$service_name"]="$state"
    else
        eval "SERVICE_RECOVERY_${service_name}_STATE='$state'"
    fi
    
    # Emit state change event if available
    if type -t unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "SERVICE_RECOVERY_STATE_CHANGED" "$service_name" "$state"
    fi
}

# Get recovery attempts
get_recovery_attempts() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${SERVICE_RECOVERY_ATTEMPTS[$service_name]:-0}"
    else
        local attempts_var="SERVICE_RECOVERY_${service_name}_ATTEMPTS"
        echo "${!attempts_var:-0}"
    fi
}

# Increment recovery attempts
increment_recovery_attempts() {
    local service_name="$1"
    local current_attempts=$(get_recovery_attempts "$service_name")
    local new_attempts=$((current_attempts + 1))
    
    log_debug "Incrementing recovery attempts for $service_name: $new_attempts"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_RECOVERY_ATTEMPTS["$service_name"]="$new_attempts"
    else
        eval "SERVICE_RECOVERY_${service_name}_ATTEMPTS='$new_attempts'"
    fi
    
    echo "$new_attempts"
}

# Reset recovery attempts
reset_recovery_attempts() {
    local service_name="$1"
    
    log_debug "Resetting recovery attempts for $service_name"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_RECOVERY_ATTEMPTS["$service_name"]="0"
    else
        eval "SERVICE_RECOVERY_${service_name}_ATTEMPTS='0'"
    fi
}

# Get recovery strategy
get_recovery_strategy() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${SERVICE_RECOVERY_STRATEGY[$service_name]:-$RECOVERY_STRATEGY_RETRY}"
    else
        local strategy_var="SERVICE_RECOVERY_${service_name}_STRATEGY"
        echo "${!strategy_var:-$RECOVERY_STRATEGY_RETRY}"
    fi
}

# Calculate backoff delay
calculate_backoff_delay() {
    local attempts="$1"
    local base_delay="${2:-$UNITY_RECOVERY_RETRY_DELAY}"
    local multiplier="${3:-$UNITY_RECOVERY_BACKOFF_MULTIPLIER}"
    
    # Exponential backoff with jitter
    local delay=$((base_delay * (multiplier ** (attempts - 1))))
    local jitter=$((RANDOM % 3))
    
    echo $((delay + jitter))
}

# Attempt service recovery
attempt_service_recovery() {
    local service_name="$1"
    local error_code="${2:-1}"
    local error_context="${3:-unknown}"
    
    log_info "Attempting recovery for service: $service_name (error: $error_code, context: $error_context)"
    
    # Get recovery strategy
    local strategy=$(get_recovery_strategy "$service_name")
    local attempts=$(increment_recovery_attempts "$service_name")
    local max_retries="${UNITY_RECOVERY_MAX_RETRIES}"
    
    # Check max retries
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        # Already have max_retries from config
        true
    else
        local max_var="SERVICE_RECOVERY_${service_name}_MAX_RETRIES"
        max_retries="${!max_var:-$UNITY_RECOVERY_MAX_RETRIES}"
    fi
    
    if [[ $attempts -gt $max_retries ]]; then
        log_error "Max recovery attempts exceeded for $service_name"
        set_recovery_state "$service_name" "failed"
        
        # Attempt rollback if available
        if execute_rollback "$service_name"; then
            log_info "Rollback completed for $service_name"
        fi
        
        return 1
    fi
    
    # Set recovering state
    set_recovery_state "$service_name" "recovering"
    
    # Execute recovery strategy
    case "$strategy" in
        "$RECOVERY_STRATEGY_RETRY")
            recover_with_retry "$service_name" "$attempts"
            ;;
        "$RECOVERY_STRATEGY_RESTART")
            recover_with_restart "$service_name" "$attempts"
            ;;
        "$RECOVERY_STRATEGY_FAILOVER")
            recover_with_failover "$service_name" "$attempts"
            ;;
        "$RECOVERY_STRATEGY_ROLLBACK")
            recover_with_rollback "$service_name"
            ;;
        "$RECOVERY_STRATEGY_NONE")
            log_info "No recovery strategy for $service_name"
            set_recovery_state "$service_name" "failed"
            return 1
            ;;
        *)
            log_warn "Unknown recovery strategy: $strategy"
            recover_with_retry "$service_name" "$attempts"
            ;;
    esac
}

# Retry recovery strategy
recover_with_retry() {
    local service_name="$1"
    local attempts="$2"
    
    log_info "Executing retry recovery for $service_name (attempt $attempts)"
    
    # Calculate backoff delay
    local delay=$(calculate_backoff_delay "$attempts")
    log_info "Waiting ${delay}s before retry..."
    sleep "$delay"
    
    # Attempt to reinitialize service
    if type -t unity_initialize_service >/dev/null 2>&1; then
        if unity_initialize_service "$service_name"; then
            log_info "Service $service_name recovered successfully"
            set_recovery_state "$service_name" "healthy"
            reset_recovery_attempts "$service_name"
            return 0
        else
            log_error "Retry recovery failed for $service_name"
            return 1
        fi
    else
        log_error "Unity initialize service function not available"
        return 1
    fi
}

# Restart recovery strategy
recover_with_restart() {
    local service_name="$1"
    local attempts="$2"
    
    log_info "Executing restart recovery for $service_name (attempt $attempts)"
    
    # Stop service if running
    if type -t "stop_${service_name}_service" >/dev/null 2>&1; then
        "stop_${service_name}_service" 2>/dev/null || true
    fi
    
    # Clear service state
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        if [[ -n "${UNITY_SERVICE_STATUS[$service_name]:-}" ]]; then
            UNITY_SERVICE_STATUS["$service_name"]="stopped"
        fi
    else
        local status_var="UNITY_SERVICE_${service_name}_STATUS"
        if [[ -n "${!status_var:-}" ]]; then
            eval "$status_var='stopped'"
        fi
    fi
    
    # Wait before restart
    local delay=$(calculate_backoff_delay "$attempts")
    sleep "$delay"
    
    # Reinitialize service
    if type -t unity_initialize_service >/dev/null 2>&1; then
        if unity_initialize_service "$service_name"; then
            log_info "Service $service_name restarted successfully"
            set_recovery_state "$service_name" "healthy"
            reset_recovery_attempts "$service_name"
            return 0
        else
            log_error "Restart recovery failed for $service_name"
            return 1
        fi
    else
        log_error "Unity initialize service function not available"
        return 1
    fi
}

# Failover recovery strategy
recover_with_failover() {
    local service_name="$1"
    local attempts="$2"
    
    log_info "Executing failover recovery for $service_name (attempt $attempts)"
    
    # Check if failover handler exists
    if type -t "failover_${service_name}_service" >/dev/null 2>&1; then
        if "failover_${service_name}_service"; then
            log_info "Service $service_name failed over successfully"
            set_recovery_state "$service_name" "failover"
            reset_recovery_attempts "$service_name"
            return 0
        else
            log_error "Failover recovery failed for $service_name"
            return 1
        fi
    else
        log_warn "No failover handler for $service_name, falling back to retry"
        recover_with_retry "$service_name" "$attempts"
    fi
}

# Rollback recovery strategy
recover_with_rollback() {
    local service_name="$1"
    
    log_info "Executing rollback recovery for $service_name"
    
    if execute_rollback "$service_name"; then
        set_recovery_state "$service_name" "rolled_back"
        reset_recovery_attempts "$service_name"
        return 0
    else
        log_error "Rollback recovery failed for $service_name"
        set_recovery_state "$service_name" "failed"
        return 1
    fi
}

# Execute rollback handler
execute_rollback() {
    local service_name="$1"
    
    # Get rollback handler
    local rollback_handler
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        rollback_handler="${SERVICE_ROLLBACK_HANDLERS[$service_name]:-}"
    else
        local rollback_var="SERVICE_RECOVERY_${service_name}_ROLLBACK"
        rollback_handler="${!rollback_var:-}"
    fi
    
    if [[ -n "$rollback_handler" ]]; then
        log_info "Executing rollback handler for $service_name: $rollback_handler"
        
        if type -t "$rollback_handler" >/dev/null 2>&1; then
            if "$rollback_handler" "$service_name"; then
                log_info "Rollback successful for $service_name"
                return 0
            else
                log_error "Rollback handler failed for $service_name"
                return 1
            fi
        else
            log_error "Rollback handler not found: $rollback_handler"
            return 1
        fi
    else
        # Try default rollback
        if type -t "rollback_${service_name}_service" >/dev/null 2>&1; then
            if "rollback_${service_name}_service"; then
                log_info "Default rollback successful for $service_name"
                return 0
            else
                log_error "Default rollback failed for $service_name"
                return 1
            fi
        else
            log_warn "No rollback handler available for $service_name"
            return 1
        fi
    fi
}

# Health check with recovery
service_health_check_with_recovery() {
    local service_name="$1"
    
    # Check if health check function exists
    if type -t "health_${service_name}_service" >/dev/null 2>&1; then
        if "health_${service_name}_service"; then
            # Service is healthy
            if [[ "$(get_recovery_state "$service_name")" != "healthy" ]]; then
                log_info "Service $service_name recovered to healthy state"
                set_recovery_state "$service_name" "healthy"
                reset_recovery_attempts "$service_name"
            fi
            return 0
        else
            # Service is unhealthy
            log_warn "Service $service_name health check failed"
            attempt_service_recovery "$service_name" 1 "health_check_failed"
            return 1
        fi
    else
        # No health check available
        log_debug "No health check available for $service_name"
        return 0
    fi
}

# Monitor all services with recovery
monitor_services_with_recovery() {
    local check_interval="${1:-30}"  # Default 30 seconds
    
    log_info "Starting service monitoring with recovery (interval: ${check_interval}s)"
    
    while true; do
        # Get all registered services
        local services=()
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            services=("${!SERVICE_RECOVERY_STATE[@]}")
        else
            # Bash 3: extract service names
            for var in $(compgen -v | grep "^SERVICE_RECOVERY_.*_STATE$"); do
                local service="${var#SERVICE_RECOVERY_}"
                service="${service%_STATE}"
                services+=("$service")
            done
        fi
        
        # Check each service
        for service in "${services[@]}"; do
            service_health_check_with_recovery "$service" || true
        done
        
        # Wait for next check
        sleep "$check_interval"
    done
}

# Batch recovery for multiple services
batch_service_recovery() {
    local failed_services=("$@")
    local recovery_results=()
    
    log_info "Starting batch recovery for ${#failed_services[@]} services"
    
    for service in "${failed_services[@]}"; do
        if attempt_service_recovery "$service"; then
            recovery_results+=("$service:success")
        else
            recovery_results+=("$service:failed")
        fi
    done
    
    # Report results
    local success_count=0
    local fail_count=0
    
    for result in "${recovery_results[@]}"; do
        if [[ "$result" == *":success" ]]; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    log_info "Batch recovery complete: $success_count succeeded, $fail_count failed"
    
    return $fail_count
}

# Create recovery checkpoint
create_recovery_checkpoint() {
    local checkpoint_name="${1:-checkpoint-$(date +%s)}"
    local checkpoint_dir="${UNITY_STATE_DIR:-/tmp/unity}/recovery/checkpoints"
    
    mkdir -p "$checkpoint_dir"
    
    log_info "Creating recovery checkpoint: $checkpoint_name"
    
    # Save current service states
    local checkpoint_file="$checkpoint_dir/$checkpoint_name.state"
    {
        echo "# Unity Recovery Checkpoint"
        echo "# Created: $(date)"
        echo
        
        # Save service states
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            for service in "${!SERVICE_RECOVERY_STATE[@]}"; do
                echo "SERVICE:$service:${SERVICE_RECOVERY_STATE[$service]}:${SERVICE_RECOVERY_ATTEMPTS[$service]}"
            done
        else
            for var in $(compgen -v | grep "^SERVICE_RECOVERY_.*_STATE$"); do
                local service="${var#SERVICE_RECOVERY_}"
                service="${service%_STATE}"
                local state="${!var}"
                local attempts_var="SERVICE_RECOVERY_${service}_ATTEMPTS"
                local attempts="${!attempts_var:-0}"
                echo "SERVICE:$service:$state:$attempts"
            done
        fi
    } > "$checkpoint_file"
    
    log_info "Checkpoint saved to: $checkpoint_file"
    return 0
}

# Restore from checkpoint
restore_from_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_dir="${UNITY_STATE_DIR:-/tmp/unity}/recovery/checkpoints"
    local checkpoint_file="$checkpoint_dir/$checkpoint_name.state"
    
    if [[ ! -f "$checkpoint_file" ]]; then
        log_error "Checkpoint not found: $checkpoint_name"
        return 1
    fi
    
    log_info "Restoring from checkpoint: $checkpoint_name"
    
    # Read checkpoint and restore states
    while IFS=':' read -r type name state attempts; do
        if [[ "$type" == "SERVICE" ]]; then
            if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                SERVICE_RECOVERY_STATE["$name"]="$state"
                SERVICE_RECOVERY_ATTEMPTS["$name"]="$attempts"
            else
                eval "SERVICE_RECOVERY_${name}_STATE='$state'"
                eval "SERVICE_RECOVERY_${name}_ATTEMPTS='$attempts'"
            fi
            
            log_debug "Restored $name: state=$state, attempts=$attempts"
        fi
    done < <(grep "^SERVICE:" "$checkpoint_file")
    
    log_info "Checkpoint restored successfully"
    return 0
}

# Export recovery functions
export -f init_recovery_system
export -f register_recovery_strategy
export -f register_rollback_handler
export -f get_recovery_state
export -f set_recovery_state
export -f attempt_service_recovery
export -f service_health_check_with_recovery
export -f monitor_services_with_recovery
export -f batch_service_recovery
export -f create_recovery_checkpoint
export -f restore_from_checkpoint

# Initialize if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Self-test
    log_info "Running recovery system self-test"
    
    init_recovery_system
    
    # Test recovery state management
    register_recovery_strategy "test-service" "$RECOVERY_STRATEGY_RETRY" 3
    
    if [[ "$(get_recovery_state "test-service")" == "healthy" ]]; then
        log_info "Recovery state management: OK"
    else
        log_error "Recovery state management: FAILED"
    fi
    
    # Test recovery attempts
    increment_recovery_attempts "test-service"
    if [[ "$(get_recovery_attempts "test-service")" == "1" ]]; then
        log_info "Recovery attempts tracking: OK"
    else
        log_error "Recovery attempts tracking: FAILED"
    fi
fi