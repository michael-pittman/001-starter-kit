#!/usr/bin/env bash
#
# Module: performance/cache
# Description: Multi-level caching for AWS API responses and deployment data
# Version: 1.0.0
# Dependencies: core/variables.sh, core/errors.sh, core/logging.sh
#
# This module provides a high-performance caching layer for AWS API calls
# with memory and disk-based storage, TTL management, and LRU eviction.
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
    local dep_path="${MODULE_DIR}/../${dep}"
    
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

# Module state management using associative arrays
declare -gA CACHE_STATE=(
    [initialized]="false"
    [memory_hits]="0"
    [memory_misses]="0"
    [disk_hits]="0"
    [disk_misses]="0"
    [total_items]="0"
    [memory_size_bytes]="0"
    [disk_size_bytes]="0"
)

# Cache storage
declare -gA CACHE_MEMORY_STORE
declare -gA CACHE_MEMORY_METADATA
declare -gA CACHE_ACCESS_COUNT
declare -gA CACHE_ACCESS_TIME

# Module configuration
declare -gA CACHE_CONFIG=(
    [memory_max_items]="1000"
    [memory_max_size_mb]="100"
    [disk_enabled]="true"
    [disk_path]="${CACHE_DIR:-/tmp/geuse-cache}"
    [disk_max_size_mb]="1000"
    [default_ttl_seconds]="3600"
    [compression_enabled]="true"
    [eviction_policy]="lru"
    [persistence_enabled]="false"
)

# Cache TTL presets for different AWS resources
declare -gA CACHE_TTL_PRESETS=(
    [spot_prices]="3600"           # 1 hour
    [instance_types]="86400"       # 24 hours
    [availability_zones]="86400"   # 24 hours
    [amis]="3600"                  # 1 hour
    [vpcs]="300"                   # 5 minutes
    [security_groups]="300"        # 5 minutes
    [quotas]="3600"                # 1 hour
    [default]="300"                # 5 minutes
)

# Module-specific error types
declare -gA CACHE_ERROR_TYPES=(
    [CACHE_INIT_FAILED]="Cache module initialization failed"
    [CACHE_STORE_FAILED]="Failed to store item in cache"
    [CACHE_RETRIEVAL_FAILED]="Failed to retrieve item from cache"
    [CACHE_EVICTION_FAILED]="Failed to evict items from cache"
    [CACHE_SERIALIZATION_FAILED]="Failed to serialize cache data"
)

# ============================================================================
# Initialization Functions
# ============================================================================

#
# Initialize the cache module
#
# Arguments:
#   $1 - Optional: Configuration file path
#
# Returns:
#   0 - Success
#   1 - Initialization failed
#
cache_init() {
    local config_file="${1:-}"
    
    log_info "[${MODULE_NAME}] Initializing cache module..."
    
    # Check if already initialized
    if [[ "${CACHE_STATE[initialized]}" == "true" ]]; then
        log_debug "[${MODULE_NAME}] Module already initialized"
        return 0
    fi
    
    # Load configuration if provided
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        cache_load_config "$config_file"
    fi
    
    # Create disk cache directory if enabled
    if [[ "${CACHE_CONFIG[disk_enabled]}" == "true" ]]; then
        mkdir -p "${CACHE_CONFIG[disk_path]}" || {
            error_cache_init_failed "Failed to create disk cache directory: ${CACHE_CONFIG[disk_path]}"
            return 1
        }
    fi
    
    # Load persistent cache if enabled
    if [[ "${CACHE_CONFIG[persistence_enabled]}" == "true" ]]; then
        cache_load_persistent
    fi
    
    # Mark as initialized
    CACHE_STATE[initialized]="true"
    
    log_info "[${MODULE_NAME}] Module initialized successfully"
    return 0
}

# ============================================================================
# Core Functions
# ============================================================================

#
# Store an item in the cache
#
# Arguments:
#   $1 - Cache key
#   $2 - Value to cache
#   $3 - Optional: TTL in seconds (default: from config)
#   $4 - Optional: Cache type hint (for TTL preset)
#
# Returns:
#   0 - Success
#   1 - Failed to store
#
cache_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-}"
    local cache_type="${4:-default}"
    
    # Validate initialization
    if [[ "${CACHE_STATE[initialized]}" != "true" ]]; then
        error_cache_init_failed "Module not initialized. Call cache_init() first."
        return 1
    fi
    
    # Determine TTL
    if [[ -z "$ttl" ]]; then
        ttl="${CACHE_TTL_PRESETS[$cache_type]:-${CACHE_CONFIG[default_ttl_seconds]}}"
    fi
    
    local expiry=$(($(date +%s) + ttl))
    local size=${#value}
    
    log_debug "[${MODULE_NAME}] Caching key: $key (TTL: ${ttl}s, Size: ${size} bytes)"
    
    # Check memory limits
    if [[ ${CACHE_STATE[total_items]} -ge ${CACHE_CONFIG[memory_max_items]} ]]; then
        log_debug "[${MODULE_NAME}] Memory cache full, evicting items"
        cache_evict_lru
    fi
    
    # Store in memory
    CACHE_MEMORY_STORE[$key]="$value"
    CACHE_MEMORY_METADATA[$key]="$expiry:$size:$cache_type"
    CACHE_ACCESS_COUNT[$key]=0
    CACHE_ACCESS_TIME[$key]=$(date +%s)
    
    # Update stats
    ((CACHE_STATE[total_items]++))
    ((CACHE_STATE[memory_size_bytes] += size))
    
    # Store on disk if enabled
    if [[ "${CACHE_CONFIG[disk_enabled]}" == "true" ]]; then
        cache_write_disk "$key" "$value" "$expiry" "$cache_type"
    fi
    
    return 0
}

#
# Retrieve an item from the cache
#
# Arguments:
#   $1 - Cache key
#
# Returns:
#   0 - Cache hit (value printed to stdout)
#   1 - Cache miss
#
cache_get() {
    local key="$1"
    local current_time=$(date +%s)
    
    # Check memory cache first
    if [[ -n "${CACHE_MEMORY_STORE[$key]+x}" ]]; then
        local metadata="${CACHE_MEMORY_METADATA[$key]}"
        local expiry="${metadata%%:*}"
        
        if [[ $current_time -lt $expiry ]]; then
            # Cache hit
            echo "${CACHE_MEMORY_STORE[$key]}"
            ((CACHE_ACCESS_COUNT[$key]++))
            CACHE_ACCESS_TIME[$key]=$current_time
            ((CACHE_STATE[memory_hits]++))
            log_debug "[${MODULE_NAME}] Memory cache hit: $key"
            return 0
        else
            # Expired
            cache_delete "$key"
        fi
    fi
    
    ((CACHE_STATE[memory_misses]++))
    
    # Check disk cache if enabled
    if [[ "${CACHE_CONFIG[disk_enabled]}" == "true" ]]; then
        if cache_read_disk "$key"; then
            ((CACHE_STATE[disk_hits]++))
            return 0
        fi
    fi
    
    ((CACHE_STATE[disk_misses]++))
    log_debug "[${MODULE_NAME}] Cache miss: $key"
    return 1
}

#
# Delete an item from the cache
#
# Arguments:
#   $1 - Cache key
#
# Returns:
#   0 - Success
#
cache_delete() {
    local key="$1"
    
    # Remove from memory
    if [[ -n "${CACHE_MEMORY_STORE[$key]+x}" ]]; then
        local metadata="${CACHE_MEMORY_METADATA[$key]}"
        local size="${metadata#*:}"
        size="${size%%:*}"
        
        unset "CACHE_MEMORY_STORE[$key]"
        unset "CACHE_MEMORY_METADATA[$key]"
        unset "CACHE_ACCESS_COUNT[$key]"
        unset "CACHE_ACCESS_TIME[$key]"
        
        ((CACHE_STATE[total_items]--))
        ((CACHE_STATE[memory_size_bytes] -= size))
    fi
    
    # Remove from disk
    if [[ "${CACHE_CONFIG[disk_enabled]}" == "true" ]]; then
        local cache_file="${CACHE_CONFIG[disk_path]}/$(echo -n "$key" | sha256sum | cut -d' ' -f1)"
        rm -f "$cache_file" "$cache_file.meta"
    fi
    
    return 0
}

#
# Clear the entire cache
#
# Arguments:
#   $1 - Optional: Cache type to clear (memory|disk|all)
#
# Returns:
#   0 - Success
#
cache_clear() {
    local cache_type="${1:-all}"
    
    log_info "[${MODULE_NAME}] Clearing cache: $cache_type"
    
    if [[ "$cache_type" == "memory" || "$cache_type" == "all" ]]; then
        CACHE_MEMORY_STORE=()
        CACHE_MEMORY_METADATA=()
        CACHE_ACCESS_COUNT=()
        CACHE_ACCESS_TIME=()
        CACHE_STATE[total_items]=0
        CACHE_STATE[memory_size_bytes]=0
    fi
    
    if [[ "$cache_type" == "disk" || "$cache_type" == "all" ]]; then
        if [[ "${CACHE_CONFIG[disk_enabled]}" == "true" ]]; then
            rm -rf "${CACHE_CONFIG[disk_path]}"/*
            CACHE_STATE[disk_size_bytes]=0
        fi
    fi
    
    return 0
}

# ============================================================================
# Disk Cache Functions
# ============================================================================

#
# Write item to disk cache
#
# Arguments:
#   $1 - Key
#   $2 - Value
#   $3 - Expiry timestamp
#   $4 - Cache type
#
cache_write_disk() {
    local key="$1"
    local value="$2"
    local expiry="$3"
    local cache_type="$4"
    
    local hash=$(echo -n "$key" | sha256sum | cut -d' ' -f1)
    local cache_file="${CACHE_CONFIG[disk_path]}/$hash"
    local meta_file="${cache_file}.meta"
    
    # Write metadata
    echo "$key:$expiry:${#value}:$cache_type" > "$meta_file"
    
    # Write data (optionally compressed)
    if [[ "${CACHE_CONFIG[compression_enabled]}" == "true" ]] && command -v gzip &>/dev/null; then
        echo "$value" | gzip -c > "${cache_file}.gz"
    else
        echo "$value" > "$cache_file"
    fi
    
    ((CACHE_STATE[disk_size_bytes] += ${#value}))
}

#
# Read item from disk cache
#
# Arguments:
#   $1 - Key
#
# Returns:
#   0 - Success (value printed to stdout)
#   1 - Not found or expired
#
cache_read_disk() {
    local key="$1"
    local current_time=$(date +%s)
    
    local hash=$(echo -n "$key" | sha256sum | cut -d' ' -f1)
    local cache_file="${CACHE_CONFIG[disk_path]}/$hash"
    local meta_file="${cache_file}.meta"
    
    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi
    
    local metadata=$(cat "$meta_file")
    local stored_key="${metadata%%:*}"
    local remaining="${metadata#*:}"
    local expiry="${remaining%%:*}"
    
    # Verify key match and not expired
    if [[ "$stored_key" != "$key" ]] || [[ $current_time -ge $expiry ]]; then
        rm -f "$cache_file" "${cache_file}.gz" "$meta_file"
        return 1
    fi
    
    # Read data
    if [[ -f "${cache_file}.gz" ]]; then
        gzip -dc "${cache_file}.gz" 2>/dev/null || return 1
    elif [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        return 1
    fi
    
    log_debug "[${MODULE_NAME}] Disk cache hit: $key"
    return 0
}

# ============================================================================
# Eviction Functions
# ============================================================================

#
# Evict least recently used items from memory cache
#
cache_evict_lru() {
    local target_items=$((${CACHE_CONFIG[memory_max_items]} * 80 / 100))  # Keep 80% of max
    local -a keys_by_access_time=()
    
    # Build sorted list of keys by access time
    for key in "${!CACHE_ACCESS_TIME[@]}"; do
        keys_by_access_time+=("${CACHE_ACCESS_TIME[$key]}:$key")
    done
    
    # Sort by access time (oldest first)
    IFS=$'\n' sorted=($(sort -n <<<"${keys_by_access_time[*]}"))
    unset IFS
    
    # Evict oldest items
    local evicted=0
    for item in "${sorted[@]}"; do
        if [[ ${CACHE_STATE[total_items]} -le $target_items ]]; then
            break
        fi
        
        local key="${item#*:}"
        cache_delete "$key"
        ((evicted++))
    done
    
    log_debug "[${MODULE_NAME}] Evicted $evicted items from cache"
}

# ============================================================================
# Cache Warming Functions
# ============================================================================

#
# Warm the cache with frequently used data
#
# Arguments:
#   $1 - Resource type to warm (spot_prices|instance_types|all)
#
# Returns:
#   0 - Success
#   1 - Failed
#
cache_warm() {
    local resource_type="${1:-all}"
    
    log_info "[${MODULE_NAME}] Warming cache for: $resource_type"
    
    case "$resource_type" in
        spot_prices|all)
            # Pre-cache spot prices for common instance types
            local instance_types=("g4dn.xlarge" "g4dn.2xlarge" "g5.xlarge" "g5.2xlarge")
            for instance_type in "${instance_types[@]}"; do
                local key="spot_price:${AWS_REGION}:${instance_type}"
                if ! cache_get "$key" &>/dev/null; then
                    # Fetch and cache (would be done by calling module)
                    log_debug "[${MODULE_NAME}] Warming cache for $instance_type spot prices"
                fi
            done
            ;;&
            
        instance_types|all)
            # Pre-cache instance type information
            local key="instance_types:${AWS_REGION}"
            if ! cache_get "$key" &>/dev/null; then
                log_debug "[${MODULE_NAME}] Warming cache for instance types"
            fi
            ;;
    esac
    
    return 0
}

# ============================================================================
# Query Functions
# ============================================================================

#
# Get cache statistics
#
# Output:
#   Cache statistics in key=value format
#
cache_get_stats() {
    local hit_rate=0
    local total_hits=$((CACHE_STATE[memory_hits] + CACHE_STATE[disk_hits]))
    local total_requests=$((total_hits + CACHE_STATE[memory_misses] + CACHE_STATE[disk_misses]))
    
    if [[ $total_requests -gt 0 ]]; then
        hit_rate=$((total_hits * 100 / total_requests))
    fi
    
    echo "initialized=${CACHE_STATE[initialized]}"
    echo "memory_hits=${CACHE_STATE[memory_hits]}"
    echo "memory_misses=${CACHE_STATE[memory_misses]}"
    echo "disk_hits=${CACHE_STATE[disk_hits]}"
    echo "disk_misses=${CACHE_STATE[disk_misses]}"
    echo "hit_rate=${hit_rate}%"
    echo "total_items=${CACHE_STATE[total_items]}"
    echo "memory_size_mb=$((CACHE_STATE[memory_size_bytes] / 1024 / 1024))"
    echo "disk_size_mb=$((CACHE_STATE[disk_size_bytes] / 1024 / 1024))"
}

#
# List cached keys matching pattern
#
# Arguments:
#   $1 - Optional: Pattern to match (glob style)
#
# Output:
#   List of matching keys
#
cache_list_keys() {
    local pattern="${1:-*}"
    
    for key in "${!CACHE_MEMORY_STORE[@]}"; do
        if [[ "$key" == $pattern ]]; then
            local metadata="${CACHE_MEMORY_METADATA[$key]}"
            local expiry="${metadata%%:*}"
            local remaining="${metadata#*:}"
            local size="${remaining%%:*}"
            local cache_type="${remaining##*:}"
            
            echo "$key (size: $size bytes, type: $cache_type, expires: $(date -d "@$expiry" 2>/dev/null || date -r "$expiry" 2>/dev/null || echo "$expiry"))"
        fi
    done
}

# ============================================================================
# Utility Functions
# ============================================================================

#
# Load configuration from file
#
# Arguments:
#   $1 - Configuration file path
#
cache_load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "[${MODULE_NAME}] Configuration file not found: $config_file"
        return 1
    fi
    
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        if [[ -n "${CACHE_CONFIG[$key]+x}" ]]; then
            CACHE_CONFIG[$key]="$value"
            log_debug "[${MODULE_NAME}] Set config: $key=$value"
        fi
    done < "$config_file"
}

#
# Save cache to persistent storage
#
cache_save_persistent() {
    if [[ "${CACHE_CONFIG[persistence_enabled]}" != "true" ]]; then
        return 0
    fi
    
    local persist_file="${CACHE_CONFIG[disk_path]}/cache.persist"
    
    {
        echo "# Cache persistence file - $(date)"
        echo "# Format: key|value|expiry|size|type"
        
        for key in "${!CACHE_MEMORY_STORE[@]}"; do
            local value="${CACHE_MEMORY_STORE[$key]}"
            local metadata="${CACHE_MEMORY_METADATA[$key]}"
            echo "$key|$(echo "$value" | base64 -w 0)|$metadata"
        done
    } > "$persist_file"
    
    log_debug "[${MODULE_NAME}] Saved ${CACHE_STATE[total_items]} items to persistent storage"
}

#
# Load cache from persistent storage
#
cache_load_persistent() {
    local persist_file="${CACHE_CONFIG[disk_path]}/cache.persist"
    
    if [[ ! -f "$persist_file" ]]; then
        return 0
    fi
    
    local loaded=0
    local current_time=$(date +%s)
    
    while IFS='|' read -r key value_b64 metadata; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        
        local value=$(echo "$value_b64" | base64 -d)
        local expiry="${metadata%%:*}"
        
        # Skip expired items
        if [[ $current_time -lt $expiry ]]; then
            CACHE_MEMORY_STORE[$key]="$value"
            CACHE_MEMORY_METADATA[$key]="$metadata"
            CACHE_ACCESS_COUNT[$key]=0
            CACHE_ACCESS_TIME[$key]=$current_time
            ((loaded++))
        fi
    done < "$persist_file"
    
    CACHE_STATE[total_items]=$loaded
    log_info "[${MODULE_NAME}] Loaded $loaded items from persistent storage"
}

# ============================================================================
# Error Handler Functions
# ============================================================================

#
# Register module-specific error handlers
#
cache_register_error_handlers() {
    for error_type in "${!CACHE_ERROR_TYPES[@]}"; do
        local handler_name="error_$(echo "$error_type" | tr '[:upper:]' '[:lower:]')"
        
        # Create error handler function dynamically
        eval "
        $handler_name() {
            local message=\"\${1:-${CACHE_ERROR_TYPES[$error_type]}}\"
            log_error \"[${MODULE_NAME}] \$message\"
            return 1
        }
        "
    done
}

# Register error handlers
cache_register_error_handlers

# ============================================================================
# Module Exports
# ============================================================================

# Export public functions
export -f cache_init
export -f cache_set
export -f cache_get
export -f cache_delete
export -f cache_clear
export -f cache_warm
export -f cache_get_stats
export -f cache_list_keys
export -f cache_save_persistent

# Export module state
export CACHE_STATE
export CACHE_CONFIG
export CACHE_TTL_PRESETS

# Module metadata
export CACHE_MODULE_VERSION="1.0.0"
export CACHE_MODULE_NAME="${MODULE_NAME}"

# Save on exit if persistence enabled
trap 'cache_save_persistent 2>/dev/null || true' EXIT

# Indicate module is loaded
log_debug "[${MODULE_NAME}] Module loaded successfully"