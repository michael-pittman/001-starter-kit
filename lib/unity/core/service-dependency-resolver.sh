#!/bin/bash
# Unity Service Dependency Resolver
# Implements topological sorting for correct service initialization order
# Ensures all dependencies are satisfied before service startup

set -euo pipefail

# Version detection for compatibility
BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"

# Service dependency graph (bash 3/4 compatible)
declare -A SERVICE_DEPENDENCIES 2>/dev/null || SERVICE_DEPENDENCIES=()
declare -A SERVICE_DEPENDENTS 2>/dev/null || SERVICE_DEPENDENTS=()
declare -A SERVICE_IN_DEGREE 2>/dev/null || SERVICE_IN_DEGREE=()
declare -A SERVICE_VISITED 2>/dev/null || SERVICE_VISITED=()

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

# Initialize dependency resolver
init_dependency_resolver() {
    log_debug "Initializing service dependency resolver"
    
    # Clear any existing state
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_DEPENDENCIES=()
        SERVICE_DEPENDENTS=()
        SERVICE_IN_DEGREE=()
        SERVICE_VISITED=()
    else
        # Bash 3: Clear variables
        for var in $(compgen -v | grep "^SERVICE_DEP_"); do
            unset "$var"
        done
    fi
    
    return 0
}

# Register service dependencies
register_service_dependencies() {
    local service_name="$1"
    shift
    local dependencies=("$@")
    
    log_debug "Registering dependencies for $service_name: ${dependencies[*]:-none}"
    
    # Store dependencies
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_DEPENDENCIES["$service_name"]="${dependencies[*]:-}"
        SERVICE_IN_DEGREE["$service_name"]="${#dependencies[@]}"
        SERVICE_VISITED["$service_name"]="false"
        
        # Update dependents for each dependency
        for dep in "${dependencies[@]}"; do
            if [[ -n "$dep" ]]; then
                local current_dependents="${SERVICE_DEPENDENTS[$dep]:-}"
                if [[ -n "$current_dependents" ]]; then
                    SERVICE_DEPENDENTS["$dep"]="$current_dependents,$service_name"
                else
                    SERVICE_DEPENDENTS["$dep"]="$service_name"
                fi
                
                # Initialize dependency if not exists
                if [[ -z "${SERVICE_IN_DEGREE[$dep]:-}" ]]; then
                    SERVICE_IN_DEGREE["$dep"]="0"
                    SERVICE_VISITED["$dep"]="false"
                fi
            fi
        done
    else
        # Bash 3 compatibility
        eval "SERVICE_DEP_${service_name}='${dependencies[*]:-}'"
        eval "SERVICE_DEP_${service_name}_COUNT='${#dependencies[@]}'"
        eval "SERVICE_DEP_${service_name}_VISITED='false'"
        
        # Store dependents
        for dep in "${dependencies[@]}"; do
            if [[ -n "$dep" ]]; then
                local dep_var="SERVICE_DEP_${dep}_DEPENDENTS"
                local current="${!dep_var:-}"
                if [[ -n "$current" ]]; then
                    eval "$dep_var='$current,$service_name'"
                else
                    eval "$dep_var='$service_name'"
                fi
                
                # Initialize if not exists
                local count_var="SERVICE_DEP_${dep}_COUNT"
                if [[ -z "${!count_var:-}" ]]; then
                    eval "$count_var='0'"
                    eval "SERVICE_DEP_${dep}_VISITED='false'"
                fi
            fi
        done
    fi
}

# Get service dependencies
get_service_dependencies() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${SERVICE_DEPENDENCIES[$service_name]:-}"
    else
        local dep_var="SERVICE_DEP_${service_name}"
        echo "${!dep_var:-}"
    fi
}

# Get service dependents
get_service_dependents() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${SERVICE_DEPENDENTS[$service_name]:-}"
    else
        local dep_var="SERVICE_DEP_${service_name}_DEPENDENTS"
        echo "${!dep_var:-}"
    fi
}

# Check if service is visited
is_service_visited() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        [[ "${SERVICE_VISITED[$service_name]:-false}" == "true" ]]
    else
        local visited_var="SERVICE_DEP_${service_name}_VISITED"
        [[ "${!visited_var:-false}" == "true" ]]
    fi
}

# Mark service as visited
mark_service_visited() {
    local service_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        SERVICE_VISITED["$service_name"]="true"
    else
        eval "SERVICE_DEP_${service_name}_VISITED='true'"
    fi
}

# Perform topological sort using Kahn's algorithm
topological_sort_services() {
    local -a sorted_services=()
    local -a queue=()
    
    log_debug "Starting topological sort of services"
    
    # Find all services with no dependencies (in-degree 0)
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        for service in "${!SERVICE_IN_DEGREE[@]}"; do
            if [[ "${SERVICE_IN_DEGREE[$service]}" -eq 0 ]]; then
                queue+=("$service")
                log_debug "Service $service has no dependencies, adding to queue"
            fi
        done
    else
        # Bash 3: iterate through all service variables
        for var in $(compgen -v | grep "^SERVICE_DEP_.*_COUNT$"); do
            if [[ "${!var}" -eq 0 ]]; then
                local service="${var#SERVICE_DEP_}"
                service="${service%_COUNT}"
                queue+=("$service")
                log_debug "Service $service has no dependencies, adding to queue"
            fi
        done
    fi
    
    # Process queue
    while [[ ${#queue[@]} -gt 0 ]]; do
        # Dequeue first service
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        sorted_services+=("$current")
        
        log_debug "Processing service: $current"
        
        # Get dependents of current service
        local dependents=$(get_service_dependents "$current")
        
        if [[ -n "$dependents" ]]; then
            # Process each dependent
            IFS=',' read -ra dep_array <<< "$dependents"
            for dependent in "${dep_array[@]}"; do
                # Decrease in-degree
                if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                    ((SERVICE_IN_DEGREE[$dependent]--))
                    if [[ "${SERVICE_IN_DEGREE[$dependent]}" -eq 0 ]]; then
                        queue+=("$dependent")
                        log_debug "Service $dependent now has no pending dependencies"
                    fi
                else
                    # Bash 3
                    local count_var="SERVICE_DEP_${dependent}_COUNT"
                    local current_count="${!count_var}"
                    ((current_count--))
                    eval "$count_var='$current_count'"
                    
                    if [[ "$current_count" -eq 0 ]]; then
                        queue+=("$dependent")
                        log_debug "Service $dependent now has no pending dependencies"
                    fi
                fi
            done
        fi
    done
    
    # Check for cycles
    local total_services
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        total_services="${#SERVICE_IN_DEGREE[@]}"
    else
        # Count services in bash 3
        total_services=$(compgen -v | grep "^SERVICE_DEP_.*_COUNT$" | wc -l)
    fi
    
    if [[ ${#sorted_services[@]} -ne $total_services ]]; then
        log_error "Circular dependency detected! Only ${#sorted_services[@]} of $total_services services could be sorted"
        
        # Find services involved in cycle
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            for service in "${!SERVICE_IN_DEGREE[@]}"; do
                local found=false
                for sorted in "${sorted_services[@]}"; do
                    if [[ "$service" == "$sorted" ]]; then
                        found=true
                        break
                    fi
                done
                if [[ "$found" == "false" ]]; then
                    log_error "Service $service is part of a dependency cycle"
                fi
            done
        fi
        
        return 1
    fi
    
    # Return sorted services
    echo "${sorted_services[@]}"
}

# Perform depth-first search to detect cycles
dfs_detect_cycle() {
    local service="$1"
    local -a path=("${@:2}")
    
    # Check if service is already in path (cycle detected)
    for p in "${path[@]}"; do
        if [[ "$p" == "$service" ]]; then
            log_error "Cycle detected: ${path[@]} -> $service"
            return 1
        fi
    done
    
    # Mark as visited
    mark_service_visited "$service"
    
    # Add to path
    path+=("$service")
    
    # Visit all dependencies
    local deps=$(get_service_dependencies "$service")
    if [[ -n "$deps" ]]; then
        IFS=' ' read -ra dep_array <<< "$deps"
        for dep in "${dep_array[@]}"; do
            if ! is_service_visited "$dep"; then
                if ! dfs_detect_cycle "$dep" "${path[@]}"; then
                    return 1
                fi
            fi
        done
    fi
    
    return 0
}

# Validate service dependencies (check for cycles)
validate_service_dependencies() {
    log_info "Validating service dependencies..."
    
    # Reset visited status
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        for service in "${!SERVICE_VISITED[@]}"; do
            SERVICE_VISITED["$service"]="false"
        done
    else
        for var in $(compgen -v | grep "^SERVICE_DEP_.*_VISITED$"); do
            eval "$var='false'"
        done
    fi
    
    # Check each service for cycles
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        for service in "${!SERVICE_DEPENDENCIES[@]}"; do
            if ! is_service_visited "$service"; then
                if ! dfs_detect_cycle "$service"; then
                    return 1
                fi
            fi
        done
    else
        for var in $(compgen -v | grep "^SERVICE_DEP_" | grep -v "_COUNT$" | grep -v "_VISITED$" | grep -v "_DEPENDENTS$"); do
            local service="${var#SERVICE_DEP_}"
            if ! is_service_visited "$service"; then
                if ! dfs_detect_cycle "$service"; then
                    return 1
                fi
            fi
        done
    fi
    
    log_info "Service dependency validation passed"
    return 0
}

# Get initialization order for services
get_service_initialization_order() {
    local requested_services=("$@")
    
    # If no services specified, get all services
    if [[ ${#requested_services[@]} -eq 0 ]]; then
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            requested_services=("${!SERVICE_DEPENDENCIES[@]}")
        else
            # Bash 3: extract service names
            for var in $(compgen -v | grep "^SERVICE_DEP_" | grep -v "_COUNT$" | grep -v "_VISITED$" | grep -v "_DEPENDENTS$"); do
                local service="${var#SERVICE_DEP_}"
                requested_services+=("$service")
            done
        fi
    fi
    
    # Perform topological sort
    local sorted_order
    sorted_order=$(topological_sort_services) || return 1
    
    # Filter to only requested services while maintaining order
    local -a filtered_order=()
    IFS=' ' read -ra sorted_array <<< "$sorted_order"
    
    for service in "${sorted_array[@]}"; do
        for requested in "${requested_services[@]}"; do
            if [[ "$service" == "$requested" ]]; then
                filtered_order+=("$service")
                break
            fi
        done
    done
    
    echo "${filtered_order[@]}"
}

# Define standard Unity service dependencies
define_unity_service_dependencies() {
    log_info "Defining Unity service dependencies"
    
    # Core services (no dependencies)
    register_service_dependencies "unity-config"
    register_service_dependencies "unity-events"
    
    # Performance depends on config
    register_service_dependencies "unity-performance" "unity-config"
    
    # AWS depends on config and performance
    register_service_dependencies "unity-aws" "unity-config" "unity-performance"
    
    # Docker depends on config
    register_service_dependencies "unity-docker" "unity-config"
    
    # Monitor depends on config, aws, docker, and events
    register_service_dependencies "unity-monitor" "unity-config" "unity-aws" "unity-docker" "unity-events"
    
    # Deployment depends on all infrastructure services
    register_service_dependencies "unity-deployment" "unity-config" "unity-aws" "unity-docker" "unity-monitor" "unity-events"
}

# Helper function to initialize services in dependency order
initialize_services_in_order() {
    local services=("$@")
    
    log_info "Initializing services in dependency order"
    
    # Get initialization order
    local init_order
    init_order=$(get_service_initialization_order "${services[@]}") || {
        log_error "Failed to determine service initialization order"
        return 1
    }
    
    log_info "Service initialization order: $init_order"
    
    # Initialize each service
    IFS=' ' read -ra ordered_services <<< "$init_order"
    for service in "${ordered_services[@]}"; do
        log_info "Initializing service: $service"
        
        # Call service-specific initialization function
        if type -t "init_${service}_service" >/dev/null 2>&1; then
            if ! "init_${service}_service"; then
                log_error "Failed to initialize service: $service"
                return 1
            fi
        else
            log_warn "No initialization function found for service: $service"
        fi
    done
    
    log_info "All services initialized successfully"
    return 0
}

# Export functions
export -f init_dependency_resolver
export -f register_service_dependencies
export -f get_service_dependencies
export -f get_service_dependents
export -f topological_sort_services
export -f validate_service_dependencies
export -f get_service_initialization_order
export -f define_unity_service_dependencies
export -f initialize_services_in_order

# Initialize if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Self-test
    log_info "Running dependency resolver self-test"
    
    init_dependency_resolver
    
    # Test with sample dependencies
    register_service_dependencies "A" "B" "C"
    register_service_dependencies "B" "D"
    register_service_dependencies "C" "D"
    register_service_dependencies "D"
    
    if validate_service_dependencies; then
        log_info "Dependency validation passed"
        
        order=$(get_service_initialization_order)
        log_info "Initialization order: $order"
    else
        log_error "Dependency validation failed"
    fi
fi