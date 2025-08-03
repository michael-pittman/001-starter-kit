#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Cache Manager
# High-performance caching system for configuration data with TTL and invalidation
# Compatible with bash 3.x+ and enterprise deployment patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL CONSTANTS AND CONFIGURATION
# =============================================================================

readonly CACHE_MANAGER_VERSION="1.0.0"
readonly CONFIG_ROOT="${CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../config" && pwd)}"
readonly CACHE_ROOT_DIR="${CONFIG_CACHE_ROOT:-$CONFIG_ROOT/.cache}"
readonly CACHE_CONFIG_DIR="$CACHE_ROOT_DIR/config"
readonly CACHE_METADATA_DIR="$CACHE_ROOT_DIR/metadata"
readonly CACHE_LOCKS_DIR="$CACHE_ROOT_DIR/locks"

# Cache configuration
readonly DEFAULT_TTL="${CONFIG_CACHE_TTL:-3600}"  # 1 hour
readonly MAX_CACHE_SIZE="${CONFIG_CACHE_MAX_SIZE:-100}"  # Max entries
readonly CACHE_CLEANUP_INTERVAL="${CONFIG_CACHE_CLEANUP_INTERVAL:-300}"  # 5 minutes
readonly CACHE_COMPRESSION="${CONFIG_CACHE_COMPRESSION:-false}"  # Enable gzip compression
readonly CACHE_ENCRYPTION="${CONFIG_CACHE_ENCRYPTION:-false}"  # Enable encryption (future)

# Cache statistics
readonly CACHE_STATS_FILE="$CACHE_METADATA_DIR/cache-stats.json"
readonly CACHE_INDEX_FILE="$CACHE_METADATA_DIR/cache-index.json"

# =============================================================================
# BASH VERSION COMPATIBILITY
# =============================================================================

# Check bash version for associative arrays
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    BASH_4_PLUS=true
    declare -A CACHE_MEMORY_STORE
    declare -A CACHE_LOCKS
else
    BASH_4_PLUS=false
    # Use prefix-based variables for bash 3.x
    CACHE_MEMORY_PREFIX="CACHE_MEM_"
    CACHE_LOCKS_PREFIX="CACHE_LOCK_"
fi

# =============================================================================
# LOGGING AND ERROR HANDLING
# =============================================================================

# Enhanced logging for cache operations
log_cache() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo "[$timestamp] [CACHE-MANAGER] ERROR: $message" >&2
            ;;
        "WARN")
            echo "[$timestamp] [CACHE-MANAGER] WARN: $message" >&2
            ;;
        "INFO")
            [[ "${CACHE_DEBUG:-false}" != "false" ]] && \
                echo "[$timestamp] [CACHE-MANAGER] INFO: $message" >&2
            ;;
        "DEBUG")
            [[ "${CACHE_DEBUG:-false}" == "true" ]] && \
                echo "[$timestamp] [CACHE-MANAGER] DEBUG: $message" >&2
            ;;
    esac
}

# Cache error handler
cache_error() {
    local error_code="$1"
    local error_message="$2"
    local suggestion="${3:-}"
    
    log_cache "ERROR" "Cache operation failed with code $error_code: $error_message"
    [[ -n "$suggestion" ]] && log_cache "INFO" "Suggestion: $suggestion"
    return "$error_code"
}

# =============================================================================
# CACHE INITIALIZATION AND MANAGEMENT
# =============================================================================

# Initialize cache system
initialize_cache_system() {
    log_cache "INFO" "Initializing configuration cache system v$CACHE_MANAGER_VERSION"
    
    # Create cache directories
    mkdir -p "$CACHE_CONFIG_DIR" "$CACHE_METADATA_DIR" "$CACHE_LOCKS_DIR"
    
    # Initialize cache index if it doesn't exist
    if [[ ! -f "$CACHE_INDEX_FILE" ]]; then
        cat > "$CACHE_INDEX_FILE" << 'EOF'
{
  "version": "1.0.0",
  "created_at": "",
  "last_cleanup": "",
  "entries": {},
  "stats": {
    "total_entries": 0,
    "total_size_bytes": 0,
    "last_access": "",
    "hit_count": 0,
    "miss_count": 0,
    "eviction_count": 0
  }
}
EOF
        # Update creation timestamp
        update_cache_index ".created_at" "\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\""
    fi
    
    # Initialize cache statistics
    if [[ ! -f "$CACHE_STATS_FILE" ]]; then
        cat > "$CACHE_STATS_FILE" << 'EOF'
{
  "cache_version": "1.0.0",
  "initialized_at": "",
  "performance": {
    "hit_rate": 0.0,
    "miss_rate": 0.0,
    "average_lookup_time_ms": 0.0,
    "cache_efficiency": 0.0
  },
  "operations": {
    "total_gets": 0,
    "total_sets": 0,
    "total_deletes": 0,
    "total_invalidations": 0,
    "total_cleanups": 0
  },
  "storage": {
    "current_entries": 0,
    "current_size_bytes": 0,
    "max_size_reached": 0,
    "compression_ratio": 1.0
  }
}
EOF
        # Update initialization timestamp
        update_cache_stats ".initialized_at" "\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\""
    fi
    
    # Start background cleanup if enabled
    if [[ "${CACHE_AUTO_CLEANUP:-true}" == "true" ]]; then
        start_cache_cleanup_daemon
    fi
    
    log_cache "INFO" "Cache system initialized successfully"
}

# =============================================================================
# CORE CACHE OPERATIONS
# =============================================================================

# Set cache entry
cache_set() {
    local cache_key="$1"
    local data="$2"
    local ttl="${3:-$DEFAULT_TTL}"
    local tags="${4:-}"  # Comma-separated tags for grouping
    
    log_cache "DEBUG" "Setting cache entry: $cache_key (TTL: ${ttl}s)"
    
    # Validate inputs
    if [[ -z "$cache_key" ]]; then
        cache_error 400 "Cache key cannot be empty"
        return 1
    fi
    
    # Create cache entry metadata
    local current_time=$(date +%s)
    local expires_at=$((current_time + ttl))
    local data_size=$(echo "$data" | wc -c | tr -d ' ')
    local cache_file="$CACHE_CONFIG_DIR/${cache_key}.cache"
    local metadata_file="$CACHE_METADATA_DIR/${cache_key}.meta"
    
    # Check cache size limits
    if ! check_cache_size_limit "$data_size"; then
        log_cache "WARN" "Cache size limit reached, performing cleanup"
        cleanup_cache_entries
    fi
    
    # Acquire lock for this cache key
    acquire_cache_lock "$cache_key" || {
        cache_error 423 "Failed to acquire cache lock for key: $cache_key"
        return 1
    }
    
    # Store data (with optional compression)
    if [[ "$CACHE_COMPRESSION" == "true" ]] && command -v gzip >/dev/null 2>&1; then
        echo "$data" | gzip > "${cache_file}.gz" || {
            release_cache_lock "$cache_key"
            cache_error 500 "Failed to compress and store cache data"
            return 1
        }
        cache_file="${cache_file}.gz"
    else
        echo "$data" > "$cache_file" || {
            release_cache_lock "$cache_key"
            cache_error 500 "Failed to store cache data"
            return 1
        }
    fi
    
    # Create metadata
    cat > "$metadata_file" << EOF
{
  "key": "$cache_key",
  "created_at": $current_time,
  "expires_at": $expires_at,
  "ttl": $ttl,
  "size_bytes": $data_size,
  "compressed": $([ "$CACHE_COMPRESSION" == "true" ] && echo "true" || echo "false"),
  "tags": "$(echo "$tags" | tr ',' ' ')",
  "access_count": 0,
  "last_accessed": $current_time,
  "checksum": "$(echo "$data" | sha256sum | cut -d' ' -f1 2>/dev/null || echo "unknown")"
}
EOF
    
    # Update cache index
    update_cache_index ".entries[\"$cache_key\"]" "$(cat "$metadata_file")"
    
    # Update statistics
    increment_cache_stat "operations.total_sets"
    increment_cache_stat "storage.current_entries"
    add_to_cache_stat "storage.current_size_bytes" "$data_size"
    
    # Release lock
    release_cache_lock "$cache_key"
    
    log_cache "DEBUG" "Cache entry stored successfully: $cache_key"
    return 0
}

# Get cache entry
cache_get() {
    local cache_key="$1"
    local update_access_time="${2:-true}"
    
    log_cache "DEBUG" "Getting cache entry: $cache_key"
    
    # Validate inputs
    if [[ -z "$cache_key" ]]; then
        cache_error 400 "Cache key cannot be empty"
        return 1
    fi
    
    local metadata_file="$CACHE_METADATA_DIR/${cache_key}.meta"
    local cache_file="$CACHE_CONFIG_DIR/${cache_key}.cache"
    
    # Check if metadata exists
    if [[ ! -f "$metadata_file" ]]; then
        increment_cache_stat "operations.total_gets"
        increment_cache_stat "stats.miss_count"
        log_cache "DEBUG" "Cache miss: $cache_key"
        return 1
    fi
    
    # Check if entry has expired
    local current_time=$(date +%s)
    local expires_at=$(jq -r '.expires_at' "$metadata_file" 2>/dev/null || echo "0")
    
    if [[ "$current_time" -gt "$expires_at" ]]; then
        log_cache "DEBUG" "Cache entry expired: $cache_key"
        cache_delete "$cache_key"
        increment_cache_stat "operations.total_gets"
        increment_cache_stat "stats.miss_count"
        return 1
    fi
    
    # Check if compressed
    local compressed=$(jq -r '.compressed' "$metadata_file" 2>/dev/null || echo "false")
    if [[ "$compressed" == "true" ]]; then
        cache_file="${cache_file}.gz"
    fi
    
    # Check if data file exists
    if [[ ! -f "$cache_file" ]]; then
        log_cache "WARN" "Cache data file missing for key: $cache_key"
        cache_delete "$cache_key"
        increment_cache_stat "operations.total_gets"
        increment_cache_stat "stats.miss_count"
        return 1
    fi
    
    # Acquire lock for reading
    acquire_cache_lock "$cache_key" || {
        cache_error 423 "Failed to acquire cache lock for key: $cache_key"
        return 1
    }
    
    # Read and return data
    local data
    if [[ "$compressed" == "true" ]] && command -v gunzip >/dev/null 2>&1; then
        data=$(gunzip -c "$cache_file" 2>/dev/null) || {
            release_cache_lock "$cache_key"
            cache_error 500 "Failed to decompress cache data"
            return 1
        }
    else
        data=$(cat "$cache_file" 2>/dev/null) || {
            release_cache_lock "$cache_key"
            cache_error 500 "Failed to read cache data"
            return 1
        }
    fi
    
    # Update access statistics if requested
    if [[ "$update_access_time" == "true" ]]; then
        # Update metadata
        jq ".access_count += 1 | .last_accessed = $current_time" "$metadata_file" > "${metadata_file}.tmp" && \
            mv "${metadata_file}.tmp" "$metadata_file"
        
        # Update index
        update_cache_index ".entries[\"$cache_key\"]" "$(cat "$metadata_file")"
    fi
    
    # Update statistics
    increment_cache_stat "operations.total_gets"
    increment_cache_stat "stats.hit_count"
    
    # Release lock
    release_cache_lock "$cache_key"
    
    # Output data
    echo "$data"
    log_cache "DEBUG" "Cache hit: $cache_key"
    return 0
}

# Delete cache entry
cache_delete() {
    local cache_key="$1"
    
    log_cache "DEBUG" "Deleting cache entry: $cache_key"
    
    # Validate inputs
    if [[ -z "$cache_key" ]]; then
        cache_error 400 "Cache key cannot be empty"
        return 1
    fi
    
    local metadata_file="$CACHE_METADATA_DIR/${cache_key}.meta"
    local cache_file="$CACHE_CONFIG_DIR/${cache_key}.cache"
    local cache_file_gz="$CACHE_CONFIG_DIR/${cache_key}.cache.gz"
    
    # Acquire lock
    acquire_cache_lock "$cache_key" || {
        cache_error 423 "Failed to acquire cache lock for key: $cache_key"
        return 1
    }
    
    # Get size before deletion for statistics
    local size_bytes="0"
    if [[ -f "$metadata_file" ]]; then
        size_bytes=$(jq -r '.size_bytes' "$metadata_file" 2>/dev/null || echo "0")
    fi
    
    # Remove files
    rm -f "$cache_file" "$cache_file_gz" "$metadata_file"
    
    # Update cache index
    update_cache_index "del(.entries[\"$cache_key\"])" ""
    
    # Update statistics
    increment_cache_stat "operations.total_deletes"
    decrement_cache_stat "storage.current_entries"
    subtract_from_cache_stat "storage.current_size_bytes" "$size_bytes"
    
    # Release lock
    release_cache_lock "$cache_key"
    
    log_cache "DEBUG" "Cache entry deleted: $cache_key"
    return 0
}

# Check if cache entry exists and is valid
cache_exists() {
    local cache_key="$1"
    
    # Try to get the entry (without updating access time)
    cache_get "$cache_key" "false" >/dev/null 2>&1
    return $?
}

# =============================================================================
# CACHE INVALIDATION AND CLEANUP
# =============================================================================

# Invalidate cache entries by pattern
cache_invalidate_pattern() {
    local pattern="$1"
    local deleted_count=0
    
    log_cache "INFO" "Invalidating cache entries matching pattern: $pattern"
    
    # Find matching keys
    local matching_keys=()
    if [[ -f "$CACHE_INDEX_FILE" ]]; then
        while IFS= read -r key; do
            if [[ "$key" == $pattern ]]; then
                matching_keys+=("$key")
            fi
        done < <(jq -r '.entries | keys[]' "$CACHE_INDEX_FILE" 2>/dev/null || true)
    fi
    
    # Delete matching entries
    for key in "${matching_keys[@]}"; do
        if cache_delete "$key"; then
            ((deleted_count++))
        fi
    done
    
    # Update statistics
    add_to_cache_stat "operations.total_invalidations" "$deleted_count"
    
    log_cache "INFO" "Invalidated $deleted_count cache entries"
    return 0
}

# Invalidate cache entries by tags
cache_invalidate_tags() {
    local tags="$1"  # Comma-separated tags
    local deleted_count=0
    
    log_cache "INFO" "Invalidating cache entries with tags: $tags"
    
    # Convert tags to array
    IFS=',' read -ra tag_array <<< "$tags"
    
    # Find entries with matching tags
    local matching_keys=()
    if [[ -f "$CACHE_INDEX_FILE" ]]; then
        for tag in "${tag_array[@]}"; do
            while IFS= read -r key; do
                local entry_tags=$(jq -r ".entries[\"$key\"].tags" "$CACHE_INDEX_FILE" 2>/dev/null || echo "")
                if [[ "$entry_tags" == *"$tag"* ]]; then
                    matching_keys+=("$key")
                fi
            done < <(jq -r '.entries | keys[]' "$CACHE_INDEX_FILE" 2>/dev/null || true)
        done
    fi
    
    # Remove duplicates and delete entries
    local unique_keys=($(printf '%s\n' "${matching_keys[@]}" | sort -u))
    for key in "${unique_keys[@]}"; do
        if cache_delete "$key"; then
            ((deleted_count++))
        fi
    done
    
    # Update statistics
    add_to_cache_stat "operations.total_invalidations" "$deleted_count"
    
    log_cache "INFO" "Invalidated $deleted_count cache entries by tags"
    return 0
}

# Clean up expired cache entries
cleanup_expired_entries() {
    local current_time=$(date +%s)
    local cleaned_count=0
    
    log_cache "INFO" "Cleaning up expired cache entries..."
    
    # Find expired entries
    local expired_keys=()
    if [[ -f "$CACHE_INDEX_FILE" ]]; then
        while IFS= read -r key; do
            local expires_at=$(jq -r ".entries[\"$key\"].expires_at" "$CACHE_INDEX_FILE" 2>/dev/null || echo "0")
            if [[ "$current_time" -gt "$expires_at" ]]; then
                expired_keys+=("$key")
            fi
        done < <(jq -r '.entries | keys[]' "$CACHE_INDEX_FILE" 2>/dev/null || true)
    fi
    
    # Delete expired entries
    for key in "${expired_keys[@]}"; do
        if cache_delete "$key"; then
            ((cleaned_count++))
        fi
    done
    
    # Update cleanup timestamp
    update_cache_index ".last_cleanup" "\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\""
    
    # Update statistics
    add_to_cache_stat "operations.total_cleanups" "1"
    add_to_cache_stat "stats.eviction_count" "$cleaned_count"
    
    log_cache "INFO" "Cleaned up $cleaned_count expired cache entries"
    return 0
}

# Clean up cache entries by size (LRU eviction)
cleanup_cache_entries() {
    local target_size="${1:-$((MAX_CACHE_SIZE * 80 / 100))}"  # 80% of max size
    local current_count=$(get_cache_stat "storage.current_entries")
    
    if [[ "$current_count" -le "$target_size" ]]; then
        log_cache "DEBUG" "Cache size within limits ($current_count <= $target_size)"
        return 0
    fi
    
    log_cache "INFO" "Cleaning up cache entries (current: $current_count, target: $target_size)"
    
    # Get entries sorted by last access time (oldest first)
    local entries_to_remove=$((current_count - target_size))
    local removed_count=0
    
    if [[ -f "$CACHE_INDEX_FILE" ]]; then
        while IFS= read -r key && [[ "$removed_count" -lt "$entries_to_remove" ]]; do
            if cache_delete "$key"; then
                ((removed_count++))
            fi
        done < <(jq -r '.entries | to_entries | sort_by(.value.last_accessed) | .[].key' "$CACHE_INDEX_FILE" 2>/dev/null || true)
    fi
    
    # Update statistics
    add_to_cache_stat "stats.eviction_count" "$removed_count"
    
    log_cache "INFO" "Removed $removed_count cache entries via LRU eviction"
    return 0
}

# Full cache cleanup (expired + size limits)
cleanup_cache_full() {
    log_cache "INFO" "Performing full cache cleanup..."
    
    # Clean expired entries first
    cleanup_expired_entries
    
    # Then clean by size if needed
    cleanup_cache_entries
    
    # Update performance statistics
    calculate_cache_performance_stats
    
    log_cache "INFO" "Full cache cleanup completed"
}

# =============================================================================
# CACHE STATISTICS AND MONITORING
# =============================================================================

# Get cache statistics
get_cache_stats() {
    local stat_name="${1:-}"
    
    if [[ ! -f "$CACHE_STATS_FILE" ]]; then
        echo "0"
        return 1
    fi
    
    if [[ -n "$stat_name" ]]; then
        jq -r ".$stat_name" "$CACHE_STATS_FILE" 2>/dev/null || echo "0"
    else
        cat "$CACHE_STATS_FILE"
    fi
}

# Update cache statistics
update_cache_stats() {
    local path="$1"
    local value="$2"
    
    if [[ -f "$CACHE_STATS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        local temp_file="${CACHE_STATS_FILE}.tmp"
        jq "$path = $value" "$CACHE_STATS_FILE" > "$temp_file" && \
            mv "$temp_file" "$CACHE_STATS_FILE"
    fi
}

# Increment cache statistic
increment_cache_stat() {
    local stat_path="$1"
    local increment="${2:-1}"
    
    if [[ -f "$CACHE_STATS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        local temp_file="${CACHE_STATS_FILE}.tmp"
        jq ".$stat_path += $increment" "$CACHE_STATS_FILE" > "$temp_file" && \
            mv "$temp_file" "$CACHE_STATS_FILE"
    fi
}

# Decrement cache statistic
decrement_cache_stat() {
    local stat_path="$1"
    local decrement="${2:-1}"
    
    increment_cache_stat "$stat_path" "-$decrement"
}

# Add to cache statistic
add_to_cache_stat() {
    local stat_path="$1"
    local value="$2"
    
    increment_cache_stat "$stat_path" "$value"
}

# Subtract from cache statistic
subtract_from_cache_stat() {
    local stat_path="$1"
    local value="$2"
    
    increment_cache_stat "$stat_path" "-$value"
}

# Calculate performance statistics
calculate_cache_performance_stats() {
    local total_gets=$(get_cache_stat "operations.total_gets")
    local hit_count=$(get_cache_stat "stats.hit_count")
    local miss_count=$(get_cache_stat "stats.miss_count")
    
    if [[ "$total_gets" -gt "0" ]]; then
        local hit_rate=$(echo "scale=4; $hit_count / $total_gets" | bc -l 2>/dev/null || echo "0")
        local miss_rate=$(echo "scale=4; $miss_count / $total_gets" | bc -l 2>/dev/null || echo "0")
        
        update_cache_stats ".performance.hit_rate" "$hit_rate"
        update_cache_stats ".performance.miss_rate" "$miss_rate"
        
        # Calculate cache efficiency (hit rate weighted by recency)
        local efficiency=$(echo "scale=4; $hit_rate * 0.9" | bc -l 2>/dev/null || echo "0")
        update_cache_stats ".performance.cache_efficiency" "$efficiency"
    fi
}

# Get cache status summary
get_cache_status() {
    local format="${1:-summary}"
    
    case "$format" in
        "json")
            get_cache_stats
            ;;
        "summary")
            local current_entries=$(get_cache_stat "storage.current_entries")
            local current_size=$(get_cache_stat "storage.current_size_bytes")
            local hit_rate=$(get_cache_stat "performance.hit_rate")
            local total_gets=$(get_cache_stat "operations.total_gets")
            
            echo "Cache Status Summary"
            echo "==================="
            echo "Entries: $current_entries / $MAX_CACHE_SIZE"
            echo "Size: $(( current_size / 1024 ))KB"
            echo "Hit Rate: $(echo "$hit_rate * 100" | bc -l 2>/dev/null || echo "0")%"
            echo "Total Lookups: $total_gets"
            ;;
        "detailed")
            echo "Detailed Cache Statistics"
            echo "========================"
            get_cache_stats | jq '.'
            ;;
    esac
}

# =============================================================================
# CACHE LOCKING MECHANISM
# =============================================================================

# Acquire cache lock
acquire_cache_lock() {
    local cache_key="$1"
    local timeout="${2:-10}"  # 10 second timeout
    local lock_file="$CACHE_LOCKS_DIR/${cache_key}.lock"
    
    local start_time=$(date +%s)
    
    while true; do
        # Try to create lock file
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            # Store lock info in memory for bash 4+
            if [[ "$BASH_4_PLUS" == "true" ]]; then
                CACHE_LOCKS["$cache_key"]="$$"
            else
                local lock_var="${CACHE_LOCKS_PREFIX}${cache_key}"
                eval "${lock_var}=$$"
            fi
            
            log_cache "DEBUG" "Acquired cache lock: $cache_key"
            return 0
        fi
        
        # Check for timeout
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -gt "$timeout" ]]; then
            log_cache "WARN" "Cache lock timeout for key: $cache_key"
            return 1
        fi
        
        # Check if lock is stale (process no longer exists)
        if [[ -f "$lock_file" ]]; then
            local lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                log_cache "DEBUG" "Removing stale lock: $cache_key (PID: $lock_pid)"
                rm -f "$lock_file"
                continue
            fi
        fi
        
        # Wait a bit before retrying
        sleep 0.1
    done
}

# Release cache lock
release_cache_lock() {
    local cache_key="$1"
    local lock_file="$CACHE_LOCKS_DIR/${cache_key}.lock"
    
    # Remove lock file
    rm -f "$lock_file"
    
    # Remove from memory store
    if [[ "$BASH_4_PLUS" == "true" ]]; then
        unset CACHE_LOCKS["$cache_key"]
    else
        local lock_var="${CACHE_LOCKS_PREFIX}${cache_key}"
        unset "$lock_var"
    fi
    
    log_cache "DEBUG" "Released cache lock: $cache_key"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Update cache index
update_cache_index() {
    local path="$1"
    local value="$2"
    
    if [[ -f "$CACHE_INDEX_FILE" ]] && command -v jq >/dev/null 2>&1; then
        local temp_file="${CACHE_INDEX_FILE}.tmp"
        if [[ -n "$value" ]]; then
            jq "$path = $value" "$CACHE_INDEX_FILE" > "$temp_file" && \
                mv "$temp_file" "$CACHE_INDEX_FILE"
        else
            jq "$path" "$CACHE_INDEX_FILE" > "$temp_file" && \
                mv "$temp_file" "$CACHE_INDEX_FILE"
        fi
    fi
}

# Check cache size limits
check_cache_size_limit() {
    local new_entry_size="$1"
    local current_entries=$(get_cache_stat "storage.current_entries")
    local current_size=$(get_cache_stat "storage.current_size_bytes")
    
    # Check entry count limit
    if [[ "$current_entries" -ge "$MAX_CACHE_SIZE" ]]; then
        return 1
    fi
    
    # Check total size limit (if configured)
    if [[ -n "${CONFIG_CACHE_MAX_SIZE_BYTES:-}" ]]; then
        local new_total_size=$((current_size + new_entry_size))
        if [[ "$new_total_size" -gt "$CONFIG_CACHE_MAX_SIZE_BYTES" ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Start background cleanup daemon
start_cache_cleanup_daemon() {
    local daemon_pid_file="$CACHE_METADATA_DIR/cleanup-daemon.pid"
    
    # Check if daemon is already running
    if [[ -f "$daemon_pid_file" ]]; then
        local daemon_pid=$(cat "$daemon_pid_file" 2>/dev/null || echo "")
        if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
            log_cache "DEBUG" "Cache cleanup daemon already running (PID: $daemon_pid)"
            return 0
        fi
    fi
    
    # Start daemon in background
    (
        echo $$ > "$daemon_pid_file"
        while true; do
            sleep "$CACHE_CLEANUP_INTERVAL"
            cleanup_expired_entries >/dev/null 2>&1 || true
        done
    ) &
    
    local daemon_pid=$!
    echo "$daemon_pid" > "$daemon_pid_file"
    
    log_cache "INFO" "Started cache cleanup daemon (PID: $daemon_pid)"
}

# Stop background cleanup daemon
stop_cache_cleanup_daemon() {
    local daemon_pid_file="$CACHE_METADATA_DIR/cleanup-daemon.pid"
    
    if [[ -f "$daemon_pid_file" ]]; then
        local daemon_pid=$(cat "$daemon_pid_file" 2>/dev/null || echo "")
        if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid" 2>/dev/null || true
            rm -f "$daemon_pid_file"
            log_cache "INFO" "Stopped cache cleanup daemon (PID: $daemon_pid)"
        else
            rm -f "$daemon_pid_file"
        fi
    fi
}

# =============================================================================
# PUBLIC API FUNCTIONS
# =============================================================================

# Initialize cache manager
init_cache_manager() {
    initialize_cache_system
}

# Cache configuration data
cache_config() {
    cache_set "$@"
}

# Get cached configuration data
get_cached_config() {
    cache_get "$@"
}

# Delete cached configuration
delete_cached_config() {
    cache_delete "$@"
}

# Check if configuration is cached
is_config_cached() {
    cache_exists "$@"
}

# Invalidate cached configurations
invalidate_cached_configs() {
    local pattern_or_tags="$1"
    local invalidation_type="${2:-pattern}"  # pattern or tags
    
    case "$invalidation_type" in
        "pattern")
            cache_invalidate_pattern "$pattern_or_tags"
            ;;
        "tags")
            cache_invalidate_tags "$pattern_or_tags"
            ;;
        *)
            cache_error 400 "Invalid invalidation type: $invalidation_type"
            return 1
            ;;
    esac
}

# Clean up cache
cleanup_config_cache() {
    local cleanup_type="${1:-full}"  # full, expired, or size
    
    case "$cleanup_type" in
        "full")
            cleanup_cache_full
            ;;
        "expired")
            cleanup_expired_entries
            ;;
        "size")
            cleanup_cache_entries
            ;;
        *)
            cache_error 400 "Invalid cleanup type: $cleanup_type"
            return 1
            ;;
    esac
}

# Get cache status and statistics
cache_status() {
    get_cache_status "$@"
}

# Export functions for use in other scripts
export -f init_cache_manager
export -f cache_config
export -f get_cached_config
export -f delete_cached_config
export -f is_config_cached
export -f invalidate_cached_configs
export -f cleanup_config_cache
export -f cache_status

# Clean up on script exit
trap 'stop_cache_cleanup_daemon 2>/dev/null || true' EXIT

log_cache "DEBUG" "Unity Configuration Cache Manager loaded successfully"