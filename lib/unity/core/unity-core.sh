#!/bin/bash
# Unity Core System - Service Registry and Foundation
# Provides service registry, event bus, and core interfaces

# Version detection for compatibility
BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"

# Error codes
UNITY_SUCCESS=0
UNITY_ERROR_VALIDATION=10
UNITY_ERROR_PREREQUISITE=20
UNITY_ERROR_EXECUTION=30
UNITY_ERROR_CLEANUP=40

# Global state
UNITY_INITIALIZED=false
UNITY_SERVICES_DIR="${UNITY_SERVICES_DIR:-./lib/unity/services}"
UNITY_LOG_LEVEL="${UNITY_LOG_LEVEL:-INFO}"
UNITY_STATE_DIR=".unity/state"
UNITY_CONFIG_FILE="${UNITY_CONFIG_FILE:-./config/unity.yml}"

# Service registry (bash 3/4 compatible)
declare -A UNITY_SERVICES 2>/dev/null || UNITY_SERVICES=()
declare -A UNITY_SERVICE_STATUS 2>/dev/null || UNITY_SERVICE_STATUS=()
declare -A UNITY_EVENT_HANDLERS 2>/dev/null || UNITY_EVENT_HANDLERS=()

# Logging function with better error handling
unity_log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_dir="${UNITY_LOG_DIR:-logs/unity}"
    local log_file="$log_dir/core.log"
    
    # Create log directory if needed with fallback
    if ! mkdir -p "$log_dir" 2>/dev/null; then
        # Fallback to temp directory
        log_dir="${TMPDIR:-/tmp}/unity-logs"
        log_file="$log_dir/core.log"
        mkdir -p "$log_dir" 2>/dev/null || {
            # If all fails, just output to stderr
            echo "[UNITY:$level] $message" >&2
            return
        }
    fi
    
    # Log levels: ERROR, WARN, INFO, DEBUG, SUCCESS
    case "$level" in
        ERROR|WARN)
            echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || true
            echo "[UNITY:$level] $message" >&2
            ;;
        INFO|SUCCESS)
            if [[ "$UNITY_LOG_LEVEL" =~ ^(INFO|DEBUG)$ ]]; then
                echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || true
                echo "[UNITY:$level] $message"
            fi
            ;;
        DEBUG)
            if [[ "$UNITY_LOG_LEVEL" == "DEBUG" ]]; then
                echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || true
                echo "[UNITY:$level] $message"
            fi
            ;;
        *)
            echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || true
            echo "[UNITY:$level] $message"
            ;;
    esac
}

# Initialize Unity core system
unity_init() {
    if [[ "$UNITY_INITIALIZED" == "true" ]]; then
        unity_log "INFO" "Unity already initialized"
        return $UNITY_SUCCESS
    fi
    
    unity_log "INFO" "🚀 Initializing Unity Core System..."
    
    # Create necessary directories with proper permissions
    for dir in "$UNITY_SERVICES_DIR" "logs/unity" "$UNITY_STATE_DIR" ".unity/events"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            # Try with current directory if absolute path fails
            local base_dir="$(basename "$dir")"
            mkdir -p "./$base_dir" 2>/dev/null || true
        fi
    done
    
    # Ensure log directory is writable
    if [[ ! -w "logs/unity" ]] && [[ ! -w "./logs/unity" ]]; then
        unity_log "WARN" "Log directory not writable, using temp directory"
        export UNITY_LOG_DIR="${TMPDIR:-/tmp}/unity-logs"
        mkdir -p "$UNITY_LOG_DIR" 2>/dev/null || true
    fi
    
    # Initialize service registry
    echo "# Unity Service Registry" > "$UNITY_STATE_DIR/services.txt"
    echo "# Format: SERVICE_NAME:STATUS:PATH:PID" >> "$UNITY_STATE_DIR/services.txt"
    
    # Initialize dependency resolver if available
    if type -t init_dependency_resolver >/dev/null 2>&1; then
        init_dependency_resolver || {
            unity_log "WARN" "Dependency resolver initialization failed"
        }
        
        # Define Unity service dependencies
        if type -t define_unity_service_dependencies >/dev/null 2>&1; then
            define_unity_service_dependencies || {
                unity_log "WARN" "Failed to define service dependencies"
            }
        fi
    else
        unity_log "WARN" "Dependency resolver not loaded"
    fi
    
    # Initialize event system if available
    if type -t unity_init_events >/dev/null 2>&1; then
        unity_init_events || {
            unity_log "WARN" "Event system initialization failed, continuing without events"
        }
    else
        unity_log "WARN" "Event system not loaded, continuing without events"
    fi
    
    UNITY_INITIALIZED=true
    
    # Emit initialization event if event system is available
    if type -t unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "UNITY_CORE_INITIALIZED" "core" "Unity Core System v1.0" || true
    fi
    
    unity_log "SUCCESS" "✅ Unity Core System initialized"
    return $UNITY_SUCCESS
}

# Enhanced Service Registry Functions
unity_register_service() {
    local service_name=$1
    local service_path=$2
    local service_type="${3:-standard}"
    local service_dependencies="${4:-}"
    
    if [[ -z "$service_name" || -z "$service_path" ]]; then
        unity_log "ERROR" "Service registration requires name and path"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Store service metadata
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        UNITY_SERVICES["$service_name"]="$service_path|$service_type|$service_dependencies"
        UNITY_SERVICE_STATUS["$service_name"]="registered"
    else
        # Bash 3.x compatibility
        eval "UNITY_SERVICE_${service_name}_PATH='$service_path'"
        eval "UNITY_SERVICE_${service_name}_TYPE='$service_type'"
        eval "UNITY_SERVICE_${service_name}_DEPS='$service_dependencies'"
        eval "UNITY_SERVICE_${service_name}_STATUS='registered'"
    fi
    
    # Also persist to file for recovery
    mkdir -p "$UNITY_STATE_DIR" 2>/dev/null || true
    echo "$service_name:registered:$service_path:$service_type:$service_dependencies" >> "$UNITY_STATE_DIR/services.txt"
    
    unity_emit_event "SERVICE_REGISTERED" "core" "$service_name"
    unity_log "INFO" "Registered service: $service_name (type: $service_type)"
    
    return $UNITY_SUCCESS
}

# Get service information
unity_get_service() {
    local service_name=$1
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${UNITY_SERVICES[$service_name]:-}"
    else
        local path_var="UNITY_SERVICE_${service_name}_PATH"
        local type_var="UNITY_SERVICE_${service_name}_TYPE"
        local deps_var="UNITY_SERVICE_${service_name}_DEPS"
        local path="${!path_var:-}"
        local type="${!type_var:-}"
        local deps="${!deps_var:-}"
        if [[ -n "$path" ]]; then
            echo "$path|$type|$deps"
        fi
    fi
}

# Initialize a service with better dependency handling
unity_initialize_service() {
    local service_name=$1
    local _depth="${2:-0}"  # Track recursion depth to prevent infinite loops
    
    # Check recursion depth
    if [[ $_depth -gt 10 ]]; then
        unity_log "ERROR" "Circular dependency detected for service: $service_name"
        return $UNITY_ERROR_VALIDATION
    fi
    
    unity_log "INFO" "Initializing service: $service_name"
    
    # Check if already initialized
    local current_status
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        current_status="${UNITY_SERVICE_STATUS[$service_name]:-}"
    else
        local status_var="UNITY_SERVICE_${service_name}_STATUS"
        current_status="${!status_var:-}"
    fi
    
    if [[ "$current_status" == "initialized" ]]; then
        unity_log "DEBUG" "Service already initialized: $service_name"
        return $UNITY_SUCCESS
    fi
    
    # Get service info
    local service_info=$(unity_get_service "$service_name")
    if [[ -z "$service_info" ]]; then
        unity_log "ERROR" "Service not found: $service_name"
        return $UNITY_ERROR_VALIDATION
    fi
    
    local service_path="${service_info%%|*}"
    local remaining="${service_info#*|}"
    local service_type="${remaining%%|*}"
    local service_deps="${remaining#*|}"
    
    # Register dependencies with resolver if available
    if type -t register_service_dependencies >/dev/null 2>&1 && [[ -n "$service_deps" && "$service_deps" != "$service_type" ]]; then
        # Split dependencies properly for bash 3 compatibility
        local deps_array=()
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            IFS=',' read -ra deps_array <<< "$service_deps"
        else
            # Bash 3 compatible splitting
            while IFS=',' read -r dep; do
                deps_array+=("$dep")
            done <<< "$service_deps"
        fi
        
        register_service_dependencies "$service_name" "${deps_array[@]}"
    fi
    
    # Use dependency resolver if available
    if type -t get_service_initialization_order >/dev/null 2>&1; then
        # Get initialization order for this service and its dependencies
        local init_order
        init_order=$(get_service_initialization_order "$service_name") || {
            unity_log "WARN" "Failed to get initialization order, falling back to recursive initialization"
            # Fall back to existing recursive logic
        }
        
        if [[ -n "$init_order" ]]; then
            # Initialize services in order
            IFS=' ' read -ra ordered_services <<< "$init_order"
            for svc in "${ordered_services[@]}"; do
                local svc_status
                if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                    svc_status="${UNITY_SERVICE_STATUS[$svc]:-}"
                else
                    local status_var="UNITY_SERVICE_${svc}_STATUS"
                    svc_status="${!status_var:-}"
                fi
                
                if [[ "$svc_status" != "initialized" ]]; then
                    unity_log "INFO" "Initializing service in dependency order: $svc"
                    unity_initialize_service "$svc" $((_depth + 1)) || {
                        unity_log "ERROR" "Failed to initialize service: $svc"
                        return $UNITY_ERROR_PREREQUISITE
                    }
                fi
            done
            return $UNITY_SUCCESS
        fi
    fi
    
    # Fallback: Check dependencies using existing logic
    if [[ -n "$service_deps" && "$service_deps" != "$service_type" ]]; then
        # Split dependencies properly for bash 3 compatibility
        local deps_array=()
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            IFS=',' read -ra deps_array <<< "$service_deps"
        else
            # Bash 3 compatible splitting
            while IFS=',' read -r dep; do
                deps_array+=("$dep")
            done <<< "$service_deps"
        fi
        
        for dep in "${deps_array[@]}"; do
            # Trim whitespace
            dep="${dep// /}"
            if [[ -n "$dep" ]]; then
                local dep_status
                if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                    dep_status="${UNITY_SERVICE_STATUS[$dep]:-}"
                else
                    local status_var="UNITY_SERVICE_${dep}_STATUS"
                    dep_status="${!status_var:-}"
                fi
                
                if [[ "$dep_status" != "initialized" ]]; then
                    unity_log "INFO" "Initializing dependency: $dep"
                    unity_initialize_service "$dep" $((_depth + 1)) || {
                        unity_log "ERROR" "Failed to initialize dependency: $dep"
                        return $UNITY_ERROR_PREREQUISITE
                    }
                fi
            fi
        done
    fi
    
    # Source the service with error handling
    if [[ -f "$service_path" ]]; then
        # Temporarily disable strict mode for sourcing
        local old_opts="$-"
        set +euo pipefail 2>/dev/null || true
        
        source "$service_path" || {
            unity_log "ERROR" "Failed to source service: $service_name from $service_path"
            # Restore options
            [[ "$old_opts" == *e* ]] && set -e
            [[ "$old_opts" == *u* ]] && set -u  
            [[ "$old_opts" == *o* ]] && set -o pipefail 2>/dev/null || true
            return $UNITY_ERROR_EXECUTION
        }
        
        # Restore options
        [[ "$old_opts" == *e* ]] && set -e
        [[ "$old_opts" == *u* ]] && set -u
        [[ "$old_opts" == *o* ]] && set -o pipefail 2>/dev/null || true
        
        # Call service init function if exists
        if type -t "init_${service_name}_service" >/dev/null 2>&1; then
            "init_${service_name}_service" || {
                unity_log "ERROR" "Service initialization failed: $service_name"
                return $UNITY_ERROR_EXECUTION
            }
        elif type -t "init_unity_${service_name}_service" >/dev/null 2>&1; then
            # Try alternative naming convention
            "init_unity_${service_name}_service" || {
                unity_log "ERROR" "Service initialization failed: $service_name"
                return $UNITY_ERROR_EXECUTION
            }
        fi
        
        # Update status
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            UNITY_SERVICE_STATUS["$service_name"]="initialized"
        else
            eval "UNITY_SERVICE_${service_name}_STATUS='initialized'"
        fi
        
        # Emit event if available
        if type -t unity_emit_event >/dev/null 2>&1; then
            unity_emit_event "SERVICE_INITIALIZED" "$service_name" "" || true
        fi
        
        unity_log "INFO" "Service initialized: $service_name"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "Service file not found: $service_path"
        return $UNITY_ERROR_PREREQUISITE
    fi
}

# Discover available services
unity_discover_service() {
    local service_name=$1
    
    if [[ -f "$UNITY_STATE_DIR/services.txt" ]] && grep -q "^$service_name:" "$UNITY_STATE_DIR/services.txt"; then
        unity_log "INFO" "✅ Service found: $service_name"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "❌ Service not found: $service_name"
        return $UNITY_ERROR_VALIDATION
    fi
}

# Handle errors uniformly with recovery options
unity_handle_error() {
    local error_code=$1
    local error_context=$2
    local error_message="${3:-Unknown error}"
    local recovery_action="${4:-}"
    
    unity_log "ERROR" "❌ ERROR [$error_code] in $error_context: $error_message"
    
    # Emit error event if available
    if type -t unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "ERROR" "$error_context" "$error_code:$error_message" || true
    fi
    
    # Attempt recovery if specified
    if [[ -n "$recovery_action" ]]; then
        unity_log "INFO" "Attempting recovery: $recovery_action"
        case "$recovery_action" in
            "retry")
                return $UNITY_ERROR_EXECUTION  # Signal retry needed
                ;;
            "reinit")
                # Try to reinitialize the service
                local service_name="${error_context#service:}"
                if [[ "$service_name" != "$error_context" ]]; then
                    unity_log "INFO" "Attempting to reinitialize service: $service_name"
                    sleep 2  # Brief delay before retry
                    unity_initialize_service "$service_name"
                    return $?
                fi
                ;;
            "cleanup")
                # Clean up and reset state
                unity_cleanup_failed_service "$error_context"
                ;;
            *)
                # Custom recovery action
                if type -t "$recovery_action" >/dev/null 2>&1; then
                    "$recovery_action" "$error_context" "$error_code"
                fi
                ;;
        esac
    fi
    
    return $error_code
}

# Clean up failed service state
unity_cleanup_failed_service() {
    local service_context=$1
    local service_name="${service_context#service:}"
    
    if [[ "$service_name" == "$service_context" ]]; then
        # Not a service context
        return
    fi
    
    unity_log "INFO" "Cleaning up failed service: $service_name"
    
    # Update service status
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        UNITY_SERVICE_STATUS["$service_name"]="failed"
    else
        eval "UNITY_SERVICE_${service_name}_STATUS='failed'"
    fi
    
    # Remove from active services
    if [[ -f "$UNITY_STATE_DIR/services.txt" ]]; then
        grep -v "^$service_name:" "$UNITY_STATE_DIR/services.txt" > "$UNITY_STATE_DIR/services.txt.tmp" || true
        mv "$UNITY_STATE_DIR/services.txt.tmp" "$UNITY_STATE_DIR/services.txt" 2>/dev/null || true
    fi
    
    # Emit cleanup event
    if type -t unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "SERVICE_CLEANUP" "$service_name" "failed" || true
    fi
}

# Recover Unity system from errors
unity_recover() {
    local recovery_type="${1:-full}"
    
    unity_log "INFO" "🔧 Starting Unity recovery: $recovery_type"
    
    case "$recovery_type" in
        "full")
            # Full system recovery
            unity_log "INFO" "Performing full system recovery..."
            
            # Reset initialization state
            UNITY_INITIALIZED=false
            
            # Clear service states
            if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                UNITY_SERVICES=()
                UNITY_SERVICE_STATUS=()
            else
                # Clear bash 3 variables
                for var in $(compgen -v | grep "^UNITY_SERVICE_"); do
                    unset "$var"
                done
            fi
            
            # Reinitialize
            unity_init
            ;;
        "services")
            # Recover only services
            unity_log "INFO" "Recovering services..."
            
            # Get list of failed services
            local failed_services=()
            if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                for service in "${!UNITY_SERVICE_STATUS[@]}"; do
                    if [[ "${UNITY_SERVICE_STATUS[$service]}" == "failed" ]]; then
                        failed_services+=("$service")
                    fi
                done
            else
                for var in $(compgen -v | grep "^UNITY_SERVICE_.*_STATUS$"); do
                    if [[ "${!var}" == "failed" ]]; then
                        local service="${var#UNITY_SERVICE_}"
                        service="${service%_STATUS}"
                        failed_services+=("$service")
                    fi
                done
            fi
            
            # Attempt to reinitialize failed services
            for service in "${failed_services[@]}"; do
                unity_log "INFO" "Attempting to recover service: $service"
                unity_initialize_service "$service"
            done
            ;;
        "events")
            # Recover event system
            unity_log "INFO" "Recovering event system..."
            if type -t unity_init_events >/dev/null 2>&1; then
                unity_init_events true
            fi
            ;;
    esac
    
    unity_log "INFO" "✅ Recovery completed"
}

# List all registered services
unity_list_services() {
    local service_type="${1:-all}"
    
    unity_log "INFO" "Registered Services (type: $service_type):"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        for service in "${!UNITY_SERVICES[@]}"; do
            local service_info="${UNITY_SERVICES[$service]}"
            local type="${service_info#*|}"
            type="${type%%|*}"
            local status="${UNITY_SERVICE_STATUS[$service]:-unknown}"
            
            if [[ "$service_type" == "all" || "$type" == "$service_type" ]]; then
                unity_log "INFO" "  - $service: $status (type: $type)"
            fi
        done
    else
        # Bash 3.x: iterate through all variables
        for var in $(compgen -v | grep "^UNITY_SERVICE_.*_PATH$"); do
            local service="${var#UNITY_SERVICE_}"
            service="${service%_PATH}"
            local type_var="UNITY_SERVICE_${service}_TYPE"
            local status_var="UNITY_SERVICE_${service}_STATUS"
            local type="${!type_var:-standard}"
            local status="${!status_var:-unknown}"
            
            if [[ "$service_type" == "all" || "$type" == "$service_type" ]]; then
                unity_log "INFO" "  - $service: $status (type: $type)"
            fi
        done
    fi
}

# Standard Service Interface Contract
# All services must implement these functions:
# - init_<service>_service() - Initialize the service
# - start_<service>_service() - Start the service  
# - stop_<service>_service() - Stop the service
# - health_<service>_service() - Check service health
# - config_<service>_service() - Get/set service configuration

# Service lifecycle management
unity_start_service() {
    local service_name=$1
    
    # Check if service is initialized
    local status
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        status="${UNITY_SERVICE_STATUS[$service_name]:-}"
    else
        local status_var="UNITY_SERVICE_${service_name}_STATUS"
        status="${!status_var:-}"
    fi
    
    if [[ "$status" != "initialized" ]]; then
        unity_log "ERROR" "Service not initialized: $service_name"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Call service start function
    if type -t "start_${service_name}_service" >/dev/null 2>&1; then
        "start_${service_name}_service" || {
            unity_log "ERROR" "Failed to start service: $service_name"
            return $UNITY_ERROR_EXECUTION
        }
        
        # Update status
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            UNITY_SERVICE_STATUS["$service_name"]="running"
        else
            eval "UNITY_SERVICE_${service_name}_STATUS='running'"
        fi
        
        unity_emit_event "SERVICE_STARTED" "$service_name" ""
        unity_log "INFO" "Service started: $service_name"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "No start function for service: $service_name"
        return $UNITY_ERROR_VALIDATION
    fi
}

# Get service metrics
unity_get_service_metrics() {
    local service_name="${1:-all}"
    local metrics=""
    
    if [[ "$service_name" == "all" ]]; then
        unity_log "INFO" "Service Metrics:"
        for service in $(unity_list_services | grep -o "^  - [^:]*" | sed 's/  - //'); do
            local status
            if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                status="${UNITY_SERVICE_STATUS[$service]:-unknown}"
            else
                local status_var="UNITY_SERVICE_${service}_STATUS"
                status="${!status_var:-unknown}"
            fi
            unity_log "INFO" "  $service: status=$status"
        done
    else
        local status
        if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
            status="${UNITY_SERVICE_STATUS[$service_name]:-unknown}"
        else
            local status_var="UNITY_SERVICE_${service_name}_STATUS"
            status="${!status_var:-unknown}"
        fi
        unity_log "INFO" "$service_name: status=$status"
    fi
}

# Initialize all registered services in dependency order
unity_initialize_all_services() {
    unity_log "INFO" "Initializing all registered services"
    
    # Get all registered services
    local -a all_services=()
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        all_services=("${!UNITY_SERVICES[@]}")
    else
        # Bash 3: extract service names
        for var in $(compgen -v | grep "^UNITY_SERVICE_.*_PATH$"); do
            local service="${var#UNITY_SERVICE_}"
            service="${service%_PATH}"
            all_services+=("$service")
        done
    fi
    
    # Use dependency resolver if available
    if type -t initialize_services_in_order >/dev/null 2>&1; then
        initialize_services_in_order "${all_services[@]}" || {
            unity_log "ERROR" "Failed to initialize services in dependency order"
            return $UNITY_ERROR_EXECUTION
        }
    else
        # Fallback: initialize services one by one
        for service in "${all_services[@]}"; do
            unity_initialize_service "$service" || {
                unity_log "ERROR" "Failed to initialize service: $service"
                # Continue with other services
            }
        done
    fi
    
    unity_log "SUCCESS" "All services initialized successfully"
    return $UNITY_SUCCESS
}

# Export core functions
export -f unity_init
export -f unity_register_service
export -f unity_get_service
export -f unity_initialize_service
export -f unity_initialize_all_services
export -f unity_discover_service
export -f unity_handle_error
export -f unity_cleanup_failed_service
export -f unity_recover
export -f unity_list_services
export -f unity_start_service
export -f unity_get_service_metrics
export -f unity_log

# Source dependency resolver
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/service-dependency-resolver.sh" ]]; then
    # Temporarily disable strict mode for sourcing
    set +euo pipefail 2>/dev/null || true
    source "$SCRIPT_DIR/service-dependency-resolver.sh" || {
        unity_log "WARN" "Failed to load dependency resolver, continuing without dependency management"
    }
    # Re-enable strict mode if it was set
    set -euo pipefail 2>/dev/null || true
else
    unity_log "WARN" "Dependency resolver not found: $SCRIPT_DIR/service-dependency-resolver.sh"
fi

# Source event system with error handling
if [[ -f "$SCRIPT_DIR/unity-events.sh" ]]; then
    # Temporarily disable strict mode for sourcing
    set +euo pipefail 2>/dev/null || true
    source "$SCRIPT_DIR/unity-events.sh" || {
        unity_log "WARN" "Failed to load event system, continuing without events"
    }
    # Re-enable strict mode if it was set
    set -euo pipefail 2>/dev/null || true
else
    unity_log "WARN" "Event system file not found: $SCRIPT_DIR/unity-events.sh"
fi

# Create stub functions if event system failed to load
if ! type -t unity_emit_event >/dev/null 2>&1; then
    unity_emit_event() {
        # Stub function when event system is not available
        return 0
    }
    export -f unity_emit_event
fi

if ! type -t unity_init_events >/dev/null 2>&1; then
    unity_init_events() {
        # Stub function when event system is not available
        return 0
    }
    export -f unity_init_events
fi
