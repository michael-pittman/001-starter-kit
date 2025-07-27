#!/bin/bash
# Core Variable Management System
# Provides type-safe variable management with validation and sanitization
# Prevents unbound variable errors and invalid export identifiers

set -euo pipefail

# Initialize variable registry arrays (bash 3.x compatible)
# Note: In bash 3.x, associative arrays are not available
# We'll use a function-based approach for compatibility

# Global variable arrays - initialized as empty
VARIABLE_REGISTRY_KEYS=""
VARIABLE_VALIDATORS_KEYS=""
VARIABLE_DEFAULTS_KEYS=""
VARIABLE_VALUES_KEYS=""
VARIABLE_REQUIRED_KEYS=""

# Function-based associative array implementation for bash 3.x compatibility
get_registry_value() {
    local key="$1"
    local type="$2"
    local varname="VARIABLE_${type}_${key}"
    echo "${!varname:-}"
}

set_registry_value() {
    local key="$1"
    local type="$2"
    local value="$3"
    local varname="VARIABLE_${type}_${key}"
    local keys_var="VARIABLE_${type}_KEYS"
    
    # Export the value
    export "${varname}=${value}"
    
    # Add to keys list if not already present
    local current_keys="${!keys_var}"
    if [[ " $current_keys " != *" $key "* ]]; then
        export "${keys_var}=${current_keys} ${key}"
    fi
}

get_registry_keys() {
    local type="$1"
    local keys_var="VARIABLE_${type}_KEYS"
    echo "${!keys_var}"
}

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }

# Sanitize variable name for safe export
# Removes invalid characters and ensures valid bash identifier
sanitize_variable_name() {
    local name="$1"
    local sanitized
    
    # Replace invalid characters with underscores
    sanitized=$(echo "$name" | sed 's/[^a-zA-Z0-9_]/_/g')
    
    # Ensure it doesn't start with a number
    if [[ "$sanitized" =~ ^[0-9] ]]; then
        sanitized="_${sanitized}"
    fi
    
    # Ensure it's not empty
    if [[ -z "$sanitized" ]]; then
        sanitized="_INVALID_"
    fi
    
    echo "$sanitized"
}

# Register a variable with optional validation and default value
register_variable() {
    local name="$1"
    local description="${2:-}"
    local default="${3:-}"
    local validator="${4:-}"
    local required="${5:-false}"
    
    # Sanitize the name for internal use
    local safe_name=$(sanitize_variable_name "$name")
    
    set_registry_value "$safe_name" "REGISTRY" "$description"
    set_registry_value "$safe_name" "DEFAULTS" "$default"
    set_registry_value "$safe_name" "REQUIRED" "$required"
    
    if [[ -n "$validator" ]]; then
        set_registry_value "$safe_name" "VALIDATORS" "$validator"
    fi
    
    # Set default value if not already set
    if [[ "$required" == "false" ]] && [[ -n "$default" ]]; then
        set_registry_value "$safe_name" "VALUES" "$default"
    fi
}

# Set a variable with validation
set_variable() {
    local name="$1"
    local value="${2:-}"
    
    local safe_name=$(sanitize_variable_name "$name")
    
    # Check if variable is registered
    if [[ -z "$(get_registry_value "$safe_name" "REGISTRY")" ]]; then
        log_warn "Variable '$name' (sanitized: '$safe_name') is not registered"
    fi
    
    # Validate value if validator exists
    local validator="$(get_registry_value "$safe_name" "VALIDATORS")"
    if [[ -n "$validator" ]]; then
        if ! $validator "$value"; then
            log_error "Validation failed for variable '$name' with value '$value'"
            return 1
        fi
    fi
    
    # Store the value
    set_registry_value "$safe_name" "VALUES" "$value"
    
    # Export with safe name
    export "${safe_name}=${value}"
    
    return 0
}

# Get a variable value with fallback
get_variable() {
    local name="$1"
    local fallback="${2:-}"
    
    local safe_name=$(sanitize_variable_name "$name")
    
    # Check if variable exists
    local current_value="$(get_registry_value "$safe_name" "VALUES")"
    if [[ -n "$current_value" ]]; then
        echo "$current_value"
    elif [[ -n "$fallback" ]]; then
        echo "$fallback"
    elif [[ "$(get_registry_value "$safe_name" "REQUIRED")" == "true" ]]; then
        log_error "Required variable '$name' is not set"
        return 1
    else
        echo "$(get_registry_value "$safe_name" "DEFAULTS")"
    fi
}

# Export all registered variables
export_variables() {
    local safe_name value
    local keys="$(get_registry_keys "VALUES")"
    
    for safe_name in $keys; do
        if [[ -n "$safe_name" ]]; then
            value="$(get_registry_value "$safe_name" "VALUES")"
            if [[ -n "$value" ]]; then
                export "${safe_name}=${value}"
            fi
        fi
    done
}

# Validate all required variables are set
validate_required_variables() {
    local safe_name
    local missing=""
    local keys="$(get_registry_keys "REQUIRED")"
    
    for safe_name in $keys; do
        if [[ -n "$safe_name" ]]; then
            local is_required="$(get_registry_value "$safe_name" "REQUIRED")"
            local current_value="$(get_registry_value "$safe_name" "VALUES")"
            if [[ "$is_required" == "true" ]] && [[ -z "$current_value" ]]; then
                missing="$missing $safe_name"
            fi
        fi
    done
    
    if [[ -n "$missing" ]]; then
        log_error "Missing required variables:$missing"
        return 1
    fi
    
    return 0
}

# Load variables from environment with prefix
load_from_environment() {
    local prefix="${1:-AWS_}"
    local env_var safe_name value
    
    while IFS= read -r env_var; do
        if [[ "$env_var" =~ ^${prefix}(.+)=(.*)$ ]]; then
            safe_name=$(sanitize_variable_name "${BASH_REMATCH[1]}")
            value="${BASH_REMATCH[2]}"
            set_variable "$safe_name" "$value"
        fi
    done < <(env | grep "^${prefix}")
}

# Built-in validators
validate_aws_resource_id() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] || [[ "$value" =~ ^[a-zA-Z0-9]$ ]]
}

validate_aws_region() {
    local value="$1"
    [[ "$value" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]
}

validate_stack_name() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]] && [[ ${#value} -le 128 ]]
}

validate_instance_type() {
    local value="$1"
    [[ "$value" =~ ^[a-z][0-9][a-z]?\.[a-z0-9]+$ ]]
}

validate_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge 1 ]] && [[ "$value" -le 65535 ]]
}

validate_boolean() {
    local value="$1"
    [[ "$value" =~ ^(true|false|yes|no|1|0)$ ]]
}

validate_url() {
    local value="$1"
    [[ "$value" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(:[0-9]+)?(/.*)?$ ]]
}

# Print variable summary
print_variable_summary() {
    local safe_name value required
    local keys="$(get_registry_keys "REGISTRY")"
    
    echo "=== Variable Summary ==="
    for safe_name in $keys; do
        if [[ -n "$safe_name" ]]; then
            value="$(get_registry_value "$safe_name" "VALUES")"
            required="$(get_registry_value "$safe_name" "REQUIRED")"
            value="${value:-<not set>}"
            echo "  $safe_name: $value $([ "$required" == "true" ] && echo "[REQUIRED]" || echo "")"
        fi
    done
    echo "======================="
}