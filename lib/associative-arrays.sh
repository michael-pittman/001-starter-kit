#!/usr/bin/env bash
# =============================================================================
# Associative Array Utilities Library
# Provides associative array functionality with fallback for older bash versions
# Works with bash 3.x+ using compatibility layer
# =============================================================================

# Prevent multiple sourcing
if [[ "${ASSOCIATIVE_ARRAYS_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly ASSOCIATIVE_ARRAYS_LIB_LOADED=true

# Check bash version and determine if we need compatibility mode
BASH_MAJOR_VERSION="${BASH_VERSION%%.*}"
BASH_MINOR_VERSION="${BASH_VERSION#*.}"
BASH_MINOR_VERSION="${BASH_MINOR_VERSION%%.*}"

# Bash 4.0+ has associative arrays, but nameref (-n) requires 4.3+
if [[ $BASH_MAJOR_VERSION -lt 4 ]] || { [[ $BASH_MAJOR_VERSION -eq 4 ]] && [[ $BASH_MINOR_VERSION -lt 3 ]]; }; then
    USE_COMPAT_MODE=true
    # Load compatibility layer for older bash versions
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/kv-store-compat.sh" ]]; then
        source "$SCRIPT_DIR/kv-store-compat.sh"
    else
        echo "ERROR: Compatibility layer required for bash < 4.3 but kv-store-compat.sh not found" >&2
        return 1
    fi
else
    USE_COMPAT_MODE=false
fi

# =============================================================================
# LIBRARY METADATA
# =============================================================================

readonly ASSOCIATIVE_ARRAYS_VERSION="1.0.0"

# =============================================================================
# CORE ASSOCIATIVE ARRAY OPERATIONS
# =============================================================================

# Get value from associative array with optional default
# Usage: aa_get array_name key [default_value]
aa_get() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_get "$1" "$2" "${3:-}"
    else
        # Use eval to access array dynamically (bash 4+ compatible)
        local array_name="$1"
        local key="$2"
        local default="${3:-}"
        
        # Use portable test for array key existence
        if eval "[[ \${$array_name[$key]+isset} ]]"; then
            eval "echo \"\${$array_name[$key]}\""
        else
            echo "$default"
        fi
    fi
}

# Set value in associative array
# Usage: aa_set array_name key value
aa_set() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_set "$1" "$2" "$3"
    else
        # Use eval to set array value (bash 4+ compatible)
        local array_name="$1"
        local key="$2"
        local value="$3"
        
        eval "$array_name[\"$key\"]=\"$value\""
    fi
}

# Check if key exists in associative array
# Usage: aa_has_key array_name key
aa_has_key() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_exists "$1" "$2"
    else
        # Use eval to check array key existence (bash 4+ compatible)
        local array_name="$1"
        local key="$2"
        
        eval "[[ \${$array_name[$key]+isset} ]]"
    fi
}

# Delete key from associative array
# Usage: aa_delete array_name key
aa_delete() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_delete "$1" "$2"
    else
        # Use eval to delete array key (bash 4+ compatible)
        local array_name="$1"
        local key="$2"
        
        eval "unset $array_name[\"$key\"]"
    fi
}

# Get all keys from associative array
# Usage: aa_keys array_name
aa_keys() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_keys "$1"
    else
        # Use eval to get array keys (bash 4+ compatible)
        local array_name="$1"
        
        eval "printf '%s\n' \"\${!$array_name[@]}\""
    fi
}

# Get all values from associative array
# Usage: aa_values array_name
aa_values() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_values "$1"
    else
        # Use eval to get array values (bash 4+ compatible)
        local array_name="$1"
        
        eval "printf '%s\n' \"\${$array_name[@]}\""
    fi
}

# Get array size
# Usage: aa_size array_name
aa_size() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_size "$1"
    else
        # Use eval to get array size (bash 4+ compatible)
        local array_name="$1"
        
        eval "echo \${#$array_name[@]}"
    fi
}

# Check if array is empty
# Usage: aa_is_empty array_name
aa_is_empty() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_is_empty "$1"
    else
        # Use eval to check if array is empty (bash 4+ compatible)
        local array_name="$1"
        
        eval "[[ \${#$array_name[@]} -eq 0 ]]"
    fi
}

# =============================================================================
# ADVANCED OPERATIONS
# =============================================================================

# Merge two associative arrays
# Usage: aa_merge target_array source_array
aa_merge() {
    local target="$1"
    local source="$2"
    
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_merge "$1" "$2"
    else
        # Use eval to merge arrays (bash 4+ compatible)
        local key
        local value
        
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                value=$(aa_get "$source" "$key")
                aa_set "$target" "$key" "$value"
            fi
        done < <(aa_keys "$source")
    fi
}

# Copy associative array
# Usage: aa_copy source_array target_array
aa_copy() {
    local source="$1"
    local target="$2"
    
    # Clear target array first
    aa_clear "$target"
    
    # Copy all key-value pairs
    aa_merge "$target" "$source"
}

# Clear all entries from associative array
# Usage: aa_clear array_name
aa_clear() {
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode
        kv_clear "$1"
    else
        # Use eval to clear array (bash 4+ compatible)
        local array_name="$1"
        
        eval "unset $array_name"
        eval "declare -A $array_name"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print associative array in a readable format
# Usage: aa_print array_name [prefix]
aa_print() {
    local array_name="$1"
    local prefix="${2:-}"
    
    if aa_is_empty "$array_name"; then
        echo "${prefix}Array '$array_name' is empty"
        return 0
    fi
    
    echo "${prefix}Array '$array_name' contents:"
    local key
    local value
    
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            value=$(aa_get "$array_name" "$key")
            echo "${prefix}  [$key] = '$value'"
        fi
    done < <(aa_keys "$array_name")
}

# Export associative array to environment variables
# Usage: aa_export array_name [prefix]
aa_export() {
    local array_name="$1"
    local prefix="${2:-${array_name}_}"
    
    local key
    local value
    
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            value=$(aa_get "$array_name" "$key")
            # Sanitize key for environment variable
            local safe_key=$(echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g')
            export "${prefix}${safe_key}"="$value"
        fi
    done < <(aa_keys "$array_name")
}

# Import associative array from environment variables
# Usage: aa_import array_name [prefix]
aa_import() {
    local array_name="$1"
    local prefix="${2:-${array_name}_}"
    
    # Get all environment variables with the prefix
    local env_var
    while IFS= read -r env_var; do
        if [[ -n "$env_var" ]]; then
            local key="${env_var#${prefix}}"
            local value="${!env_var}"
            aa_set "$array_name" "$key" "$value"
        fi
    done < <(env | grep "^${prefix}" | cut -d'=' -f1)
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate associative array name
# Usage: aa_validate_name array_name
aa_validate_name() {
    local array_name="$1"
    
    # Check if name is valid bash identifier
    if [[ "$array_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 0
    else
        echo "Error: Invalid array name '$array_name'" >&2
        return 1
    fi
}

# Validate key name
# Usage: aa_validate_key key
aa_validate_key() {
    local key="$1"
    
    # Check if key is not empty
    if [[ -n "$key" ]]; then
        return 0
    else
        echo "Error: Empty key not allowed" >&2
        return 1
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize associative array with default values
# Usage: aa_init array_name [key1=value1] [key2=value2] ...
aa_init() {
    local array_name="$1"
    shift
    
    # Validate array name
    if ! aa_validate_name "$array_name"; then
        return 1
    fi
    
    # Clear array first
    aa_clear "$array_name"
    
    # Set initial values
    local pair
    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            aa_set "$array_name" "$key" "$value"
        fi
    done
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all functions for use in other scripts
export -f aa_get aa_set aa_has_key aa_delete aa_keys aa_values
export -f aa_size aa_is_empty aa_merge aa_copy aa_clear
export -f aa_print aa_export aa_import aa_validate_name aa_validate_key aa_init

# =============================================================================
# COMPATIBILITY MODE DETECTION
# =============================================================================

if [[ "$USE_COMPAT_MODE" == "true" ]]; then
    echo "INFO: Associative arrays library loaded in compatibility mode (v$ASSOCIATIVE_ARRAYS_VERSION)" >&2
else
    echo "INFO: Associative arrays library loaded in native mode (v$ASSOCIATIVE_ARRAYS_VERSION)" >&2
fi