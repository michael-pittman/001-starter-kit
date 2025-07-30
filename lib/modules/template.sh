#!/usr/bin/env bash
#
# Module: template
# Description: Template module for creating new GeuseMaker modules
# Version: 1.0.0
# Dependencies: core/variables.sh, core/errors.sh, core/logging.sh
#
# This template provides the standard structure and patterns for creating
# new modules in the GeuseMaker modular deployment system.
#
# Usage:
#   1. Copy this file to a new module: cp template.sh yourmodule.sh
#   2. Update the module name, description, and dependencies
#   3. Implement required functions following the patterns below
#   4. Add module-specific error types if needed
#   5. Export public functions at the end of the file
#

set -euo pipefail

# Bash version compatibility
# Compatible with bash 3.x+

# Module directory detection
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

# Source dependencies with error handling
source_dependency() {
    local dep="$1"
    local dep_path="${MODULE_DIR}/${dep}"
    
    if [[ ! -f "$dep_path" ]]; then
        echo "ERROR: Required dependency not found: $dep_path" >&2
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$dep_path" || {
        echo "ERROR: Failed to source dependency: $dep_path" >&2
        return 1
    }
}

# Load core dependencies
source_dependency "core/variables.sh"
source_dependency "core/errors.sh"
source_dependency "core/logging.sh"

# Optional: Load additional dependencies
# source_dependency "core/registry.sh"
# source_dependency "core/validation.sh"

# Module state management using associative arrays
declare -gA TEMPLATE_STATE=(
    [initialized]="false"
    [config_loaded]="false"
    [resources_count]="0"
    [last_error]=""
    [last_operation]=""
)

# Module configuration (example)
declare -gA TEMPLATE_CONFIG=(
    [timeout]="300"
    [retry_count]="3"
    [retry_delay]="5"
    [debug_mode]="false"
    [validation_strict]="true"
)

# Module-specific error types
declare -gA TEMPLATE_ERROR_TYPES=(
    [TEMPLATE_INIT_FAILED]="Template module initialization failed"
    [TEMPLATE_CONFIG_INVALID]="Template configuration is invalid"
    [TEMPLATE_RESOURCE_NOT_FOUND]="Template resource not found"
    [TEMPLATE_OPERATION_FAILED]="Template operation failed"
    [TEMPLATE_VALIDATION_ERROR]="Template validation error"
)

# ============================================================================
# Initialization Functions
# ============================================================================

#
# Initialize the template module
# This function should be called before using any other module functions
#
# Returns:
#   0 - Success
#   1 - Initialization failed
#
template_init() {
    local config_file="${1:-}"
    
    log_info "[${MODULE_NAME}] Initializing module..."
    
    # Check if already initialized
    if [[ "${TEMPLATE_STATE[initialized]}" == "true" ]]; then
        log_debug "[${MODULE_NAME}] Module already initialized"
        return 0
    fi
    
    # Load configuration if provided
    if [[ -n "$config_file" ]]; then
        if ! template_load_config "$config_file"; then
            error_template_init_failed "Failed to load configuration from: $config_file"
            return 1
        fi
    fi
    
    # Perform module-specific initialization
    # Example: Create required directories, validate environment, etc.
    
    # Mark as initialized
    TEMPLATE_STATE[initialized]="true"
    TEMPLATE_STATE[last_operation]="init"
    
    log_info "[${MODULE_NAME}] Module initialized successfully"
    return 0
}

#
# Load module configuration from file
#
# Arguments:
#   $1 - Configuration file path
#
# Returns:
#   0 - Success
#   1 - Failed to load configuration
#
template_load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        error_template_config_invalid "Configuration file not found: $config_file"
        return 1
    fi
    
    log_debug "[${MODULE_NAME}] Loading configuration from: $config_file"
    
    # Example: Parse configuration file
    # This is a simple key=value parser, adjust based on your needs
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # Store in configuration array
        if [[ -n "${TEMPLATE_CONFIG[$key]+x}" ]]; then
            TEMPLATE_CONFIG[$key]="$value"
            log_debug "[${MODULE_NAME}] Set config: $key=$value"
        fi
    done < "$config_file"
    
    TEMPLATE_STATE[config_loaded]="true"
    return 0
}

# ============================================================================
# Core Functions
# ============================================================================

#
# Example core function - Process a resource
#
# Arguments:
#   $1 - Resource identifier
#   $2 - Operation type (create|update|delete)
#   $3 - Optional: Additional parameters
#
# Returns:
#   0 - Success
#   1 - Operation failed
#
template_process_resource() {
    local resource_id="$1"
    local operation="${2:-create}"
    local params="${3:-}"
    
    # Validate initialization
    if [[ "${TEMPLATE_STATE[initialized]}" != "true" ]]; then
        error_template_init_failed "Module not initialized. Call template_init() first."
        return 1
    fi
    
    log_info "[${MODULE_NAME}] Processing resource: $resource_id (operation: $operation)"
    
    # Update state
    TEMPLATE_STATE[last_operation]="process_resource"
    
    # Validate inputs
    if ! template_validate_resource_id "$resource_id"; then
        error_template_validation_error "Invalid resource ID: $resource_id"
        return 1
    fi
    
    # Perform operation with retry logic
    local attempt=1
    local max_attempts="${TEMPLATE_CONFIG[retry_count]}"
    local retry_delay="${TEMPLATE_CONFIG[retry_delay]}"
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "[${MODULE_NAME}] Attempt $attempt of $max_attempts"
        
        if template_execute_operation "$resource_id" "$operation" "$params"; then
            # Success
            ((TEMPLATE_STATE[resources_count]++))
            log_info "[${MODULE_NAME}] Successfully processed resource: $resource_id"
            return 0
        fi
        
        # Failed, check if we should retry
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "[${MODULE_NAME}] Operation failed, retrying in ${retry_delay}s..."
            sleep "$retry_delay"
        fi
        
        ((attempt++))
    done
    
    # All attempts failed
    error_template_operation_failed "Failed to process resource after $max_attempts attempts: $resource_id"
    return 1
}

#
# Validate resource identifier
#
# Arguments:
#   $1 - Resource ID to validate
#
# Returns:
#   0 - Valid
#   1 - Invalid
#
template_validate_resource_id() {
    local resource_id="$1"
    
    # Example validation: alphanumeric with hyphens, 3-63 characters
    if [[ ! "$resource_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{2,62}$ ]]; then
        return 1
    fi
    
    return 0
}

#
# Execute the actual operation (internal function)
#
# Arguments:
#   $1 - Resource ID
#   $2 - Operation type
#   $3 - Parameters
#
# Returns:
#   0 - Success
#   1 - Failed
#
template_execute_operation() {
    local resource_id="$1"
    local operation="$2"
    local params="$3"
    
    # This is where you would implement the actual operation logic
    # For template purposes, we'll simulate with a sleep
    
    case "$operation" in
        create)
            log_debug "[${MODULE_NAME}] Creating resource: $resource_id"
            # Simulate work
            sleep 1
            ;;
        update)
            log_debug "[${MODULE_NAME}] Updating resource: $resource_id"
            # Simulate work
            sleep 1
            ;;
        delete)
            log_debug "[${MODULE_NAME}] Deleting resource: $resource_id"
            # Simulate work
            sleep 1
            ;;
        *)
            log_error "[${MODULE_NAME}] Unknown operation: $operation"
            return 1
            ;;
    esac
    
    # Simulate occasional failures for demonstration
    # Remove this in actual implementation
    if [[ $((RANDOM % 10)) -eq 0 ]]; then
        log_debug "[${MODULE_NAME}] Simulated failure"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Query Functions
# ============================================================================

#
# Get current module state
#
# Arguments:
#   $1 - Optional: Specific state key to retrieve
#
# Returns:
#   0 - Always succeeds
#
# Output:
#   If key specified: Value of that key
#   If no key: All state in key=value format
#
template_get_state() {
    local key="${1:-}"
    
    if [[ -n "$key" ]]; then
        echo "${TEMPLATE_STATE[$key]:-}"
    else
        # Output all state
        for k in "${!TEMPLATE_STATE[@]}"; do
            echo "$k=${TEMPLATE_STATE[$k]}"
        done | sort
    fi
    
    return 0
}

#
# Get module configuration
#
# Arguments:
#   $1 - Optional: Specific config key to retrieve
#
# Returns:
#   0 - Always succeeds
#
# Output:
#   Configuration value(s)
#
template_get_config() {
    local key="${1:-}"
    
    if [[ -n "$key" ]]; then
        echo "${TEMPLATE_CONFIG[$key]:-}"
    else
        # Output all config
        for k in "${!TEMPLATE_CONFIG[@]}"; do
            echo "$k=${TEMPLATE_CONFIG[$k]}"
        done | sort
    fi
    
    return 0
}

# ============================================================================
# Utility Functions
# ============================================================================

#
# Reset module state
# Useful for testing or reinitializing
#
# Returns:
#   0 - Always succeeds
#
template_reset() {
    log_info "[${MODULE_NAME}] Resetting module state"
    
    TEMPLATE_STATE[initialized]="false"
    TEMPLATE_STATE[config_loaded]="false"
    TEMPLATE_STATE[resources_count]="0"
    TEMPLATE_STATE[last_error]=""
    TEMPLATE_STATE[last_operation]=""
    
    # Reset configuration to defaults
    TEMPLATE_CONFIG[timeout]="300"
    TEMPLATE_CONFIG[retry_count]="3"
    TEMPLATE_CONFIG[retry_delay]="5"
    TEMPLATE_CONFIG[debug_mode]="false"
    TEMPLATE_CONFIG[validation_strict]="true"
    
    return 0
}

#
# Enable debug mode for verbose logging
#
# Arguments:
#   $1 - true|false (optional, defaults to true)
#
# Returns:
#   0 - Always succeeds
#
template_debug_mode() {
    local enable="${1:-true}"
    
    TEMPLATE_CONFIG[debug_mode]="$enable"
    
    if [[ "$enable" == "true" ]]; then
        log_info "[${MODULE_NAME}] Debug mode enabled"
    else
        log_info "[${MODULE_NAME}] Debug mode disabled"
    fi
    
    return 0
}

# ============================================================================
# Error Handler Functions
# ============================================================================

#
# Register module-specific error handlers
#
template_register_error_handlers() {
    for error_type in "${!TEMPLATE_ERROR_TYPES[@]}"; do
        local handler_name="error_$(echo "$error_type" | tr '[:upper:]' '[:lower:]')"
        
        # Create error handler function dynamically
        eval "
        $handler_name() {
            local message=\"\${1:-${TEMPLATE_ERROR_TYPES[$error_type]}}\"
            TEMPLATE_STATE[last_error]=\"\$message\"
            log_error \"[${MODULE_NAME}] \$message\"
            return 1
        }
        "
    done
}

# Register error handlers
template_register_error_handlers

# ============================================================================
# Module Exports
# ============================================================================

# Export public functions
# Only export functions that should be accessible from other modules
export -f template_init
export -f template_load_config
export -f template_process_resource
export -f template_get_state
export -f template_get_config
export -f template_reset
export -f template_debug_mode

# Export module state for advanced usage
# Note: Direct manipulation discouraged, use provided functions
export TEMPLATE_STATE
export TEMPLATE_CONFIG

# Module metadata
export TEMPLATE_MODULE_VERSION="1.0.0"
export TEMPLATE_MODULE_NAME="${MODULE_NAME}"

# Indicate module is loaded
log_debug "[${MODULE_NAME}] Module loaded successfully"