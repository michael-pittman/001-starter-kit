#!/usr/bin/env bash
# =============================================================================
# Key-Value Store Compatibility Library
# Provides basic key-value functionality for bash 3.x+
# Uses files or environment variables instead of associative arrays
# =============================================================================

# Prevent multiple sourcing
if [[ "${KV_STORE_COMPAT_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly KV_STORE_COMPAT_LOADED=true

# Global prefix for environment variables
readonly KV_PREFIX="_KV_STORE_"

# Directory for file-based storage (fallback)
readonly KV_STORE_DIR="${TMPDIR:-/tmp}/kv_store_$$"

# Initialize the KV store
kv_init() {
    if [[ ! -d "$KV_STORE_DIR" ]]; then
        mkdir -p "$KV_STORE_DIR"
    fi
}

# Clean up KV store on exit
kv_cleanup() {
    if [[ -d "$KV_STORE_DIR" ]]; then
        rm -rf "$KV_STORE_DIR"
    fi
}

# Set a key-value pair
# Usage: kv_set "namespace" "key" "value"
kv_set() {
    local namespace="${1:-default}"
    local key="$2"
    local value="$3"
    
    # Sanitize namespace and key for use as variable names
    local safe_ns=$(echo "$namespace" | sed 's/[^a-zA-Z0-9_]/_/g')
    local safe_key=$(echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g')
    
    # Try to use environment variable first
    eval "${KV_PREFIX}${safe_ns}_${safe_key}='$value'"
    
    # Also write to file for persistence
    kv_init
    echo "$value" > "${KV_STORE_DIR}/${safe_ns}_${safe_key}"
}

# Get a value by key
# Usage: kv_get "namespace" "key" [default_value]
kv_get() {
    local namespace="${1:-default}"
    local key="$2"
    local default="${3:-}"
    
    # Sanitize namespace and key
    local safe_ns=$(echo "$namespace" | sed 's/[^a-zA-Z0-9_]/_/g')
    local safe_key=$(echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g')
    
    # Try environment variable first
    local var_name="${KV_PREFIX}${safe_ns}_${safe_key}"
    local value
    eval "value=\${${var_name}:-}"
    
    if [[ -n "$value" ]]; then
        echo "$value"
    elif [[ -f "${KV_STORE_DIR}/${safe_ns}_${safe_key}" ]]; then
        cat "${KV_STORE_DIR}/${safe_ns}_${safe_key}"
    else
        echo "$default"
    fi
}

# Check if a key exists
# Usage: kv_exists "namespace" "key"
kv_exists() {
    local namespace="${1:-default}"
    local key="$2"
    
    # Sanitize namespace and key
    local safe_ns=$(echo "$namespace" | sed 's/[^a-zA-Z0-9_]/_/g')
    local safe_key=$(echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g')
    
    # Check environment variable
    local var_name="${KV_PREFIX}${safe_ns}_${safe_key}"
    local value
    eval "value=\${${var_name}:-}"
    
    if [[ -n "$value" ]]; then
        return 0
    elif [[ -f "${KV_STORE_DIR}/${safe_ns}_${safe_key}" ]]; then
        return 0
    else
        return 1
    fi
}

# Delete a key-value pair
# Usage: kv_delete "namespace" "key"
kv_delete() {
    local namespace="${1:-default}"
    local key="$2"
    
    # Sanitize namespace and key
    local safe_ns=$(echo "$namespace" | sed 's/[^a-zA-Z0-9_]/_/g')
    local safe_key=$(echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g')
    
    # Remove environment variable
    local var_name="${KV_PREFIX}${safe_ns}_${safe_key}"
    unset "$var_name"
    
    # Remove file
    if [[ -f "${KV_STORE_DIR}/${safe_ns}_${safe_key}" ]]; then
        rm -f "${KV_STORE_DIR}/${safe_ns}_${safe_key}"
    fi
}

# Get all keys for a namespace
# Usage: kv_keys "namespace"
kv_keys() {
    local namespace="${1:-default}"
    local safe_ns=$(echo "$namespace" | sed 's/[^a-zA-Z0-9_]/_/g')
    
    # Get keys from environment variables
    env | grep "^${KV_PREFIX}${safe_ns}_" | sed "s/^${KV_PREFIX}${safe_ns}_//" | cut -d'=' -f1
    
    # Get keys from files
    if [[ -d "$KV_STORE_DIR" ]]; then
        find "$KV_STORE_DIR" -name "${safe_ns}_*" -type f 2>/dev/null | \
        sed "s|^${KV_STORE_DIR}/${safe_ns}_||" | sort -u
    fi
}

# Get all values for a namespace
# Usage: kv_values "namespace"
kv_values() {
    local namespace="${1:-default}"
    local key
    
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            kv_get "$namespace" "$key"
        fi
    done < <(kv_keys "$namespace")
}

# Get the size (number of keys) for a namespace
# Usage: kv_size "namespace"
kv_size() {
    local namespace="${1:-default}"
    kv_keys "$namespace" | wc -l
}

# Check if namespace is empty
# Usage: kv_is_empty "namespace"
kv_is_empty() {
    local namespace="${1:-default}"
    [[ $(kv_size "$namespace") -eq 0 ]]
}

# Clear all keys for a namespace
# Usage: kv_clear "namespace"
kv_clear() {
    local namespace="${1:-default}"
    local key
    
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            kv_delete "$namespace" "$key"
        fi
    done < <(kv_keys "$namespace")
}

# Merge two namespaces (source into target)
# Usage: kv_merge "target_namespace" "source_namespace"
kv_merge() {
    local target="$1"
    local source="$2"
    local key
    local value
    
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            value=$(kv_get "$source" "$key")
            kv_set "$target" "$key" "$value"
        fi
    done < <(kv_keys "$source")
}

# Export functions for use in other scripts
export -f kv_init kv_cleanup kv_set kv_get kv_exists kv_delete
export -f kv_keys kv_values kv_size kv_is_empty kv_clear kv_merge

# Set up cleanup on exit
trap kv_cleanup EXIT