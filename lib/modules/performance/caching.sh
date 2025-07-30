#!/bin/bash
# performance/caching.sh - Intelligent caching system for performance optimization

# Cache configuration
declare -g CACHE_DIR="${CACHE_DIR:-/tmp/geuse-cache}"
declare -g CACHE_ENABLED=true
declare -g CACHE_VERBOSE=false

# Cache statistics
declare -g -A CACHE_STATS=(
    ["hits"]=0
    ["misses"]=0
    ["evictions"]=0
    ["size_bytes"]=0
)

# Cache metadata tracking
declare -g -A CACHE_METADATA

# Initialize cache system
cache_init() {
    local cache_size_mb="${1:-100}"
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
    
    # Set cache size limit
    declare -g CACHE_MAX_SIZE=$((cache_size_mb * 1024 * 1024))
    
    # Initialize cache index
    cache_rebuild_index
    
    # Start cache maintenance
    cache_start_maintenance &
}

# Multi-tier cache implementation
declare -g -A L1_CACHE  # Memory cache (fastest)
declare -g -A L2_CACHE  # File cache (persistent)
declare -g L1_CACHE_MAX_ITEMS=100
declare -g L1_CACHE_MAX_SIZE=10485760  # 10MB

# Set cache entry with TTL
cache_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-3600}"  # Default 1 hour
    local tier="${4:-auto}"  # auto, l1, l2
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Determine cache tier
    if [[ "$tier" == "auto" ]]; then
        local value_size=${#value}
        if [[ $value_size -lt 1024 && ${#L1_CACHE[@]} -lt $L1_CACHE_MAX_ITEMS ]]; then
            tier="l1"
        else
            tier="l2"
        fi
    fi
    
    local expire_time=$(($(date +%s) + ttl))
    
    case "$tier" in
        "l1")
            # Memory cache
            L1_CACHE[$key]="$expire_time|$value"
            cache_enforce_l1_limits
            ;;
        "l2")
            # File cache
            local cache_file="$CACHE_DIR/$(echo -n "$key" | sha256sum | cut -d' ' -f1)"
            {
                echo "$expire_time"
                echo "$key"
                echo "$value"
            } > "$cache_file"
            
            # Update metadata
            CACHE_METADATA[$key]="$cache_file|$expire_time|${#value}"
            
            # Update cache size
            CACHE_STATS["size_bytes"]=$((${CACHE_STATS["size_bytes"]} + ${#value}))
            
            # Enforce cache size limits
            cache_enforce_size_limit
            ;;
    esac
    
    [[ "$CACHE_VERBOSE" == "true" ]] && echo "CACHE: Set $key (tier: $tier, ttl: $ttl)" >&2
}

# Get cache entry
cache_get() {
    local key="$1"
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 1
    fi
    
    # Check L1 cache first
    if [[ -n "${L1_CACHE[$key]}" ]]; then
        local entry="${L1_CACHE[$key]}"
        local expire_time="${entry%%|*}"
        local value="${entry#*|}"
        
        if [[ $(date +%s) -lt $expire_time ]]; then
            CACHE_STATS["hits"]=$((${CACHE_STATS["hits"]} + 1))
            echo "$value"
            return 0
        else
            # Expired, remove from L1
            unset L1_CACHE[$key]
        fi
    fi
    
    # Check L2 cache
    if [[ -n "${CACHE_METADATA[$key]}" ]]; then
        local metadata="${CACHE_METADATA[$key]}"
        local cache_file="${metadata%%|*}"
        local expire_time=$(echo "$metadata" | cut -d'|' -f2)
        
        if [[ -f "$cache_file" ]] && [[ $(date +%s) -lt $expire_time ]]; then
            # Read from file cache
            local stored_expire=$(sed -n '1p' "$cache_file")
            local stored_key=$(sed -n '2p' "$cache_file")
            
            if [[ "$stored_key" == "$key" ]] && [[ $(date +%s) -lt $stored_expire ]]; then
                CACHE_STATS["hits"]=$((${CACHE_STATS["hits"]} + 1))
                sed -n '3,$p' "$cache_file"
                
                # Promote to L1 if frequently accessed
                cache_maybe_promote_to_l1 "$key" "$cache_file"
                return 0
            fi
        fi
        
        # Expired or invalid, clean up
        cache_delete "$key"
    fi
    
    CACHE_STATS["misses"]=$((${CACHE_STATS["misses"]} + 1))
    return 1
}

# Delete cache entry
cache_delete() {
    local key="$1"
    
    # Remove from L1
    unset L1_CACHE[$key] 2>/dev/null || true
    
    # Remove from L2
    if [[ -n "${CACHE_METADATA[$key]}" ]]; then
        local metadata="${CACHE_METADATA[$key]}"
        local cache_file="${metadata%%|*}"
        local size=$(echo "$metadata" | cut -d'|' -f3)
        
        rm -f "$cache_file" 2>/dev/null || true
        unset CACHE_METADATA[$key]
        
        # Update cache size
        CACHE_STATS["size_bytes"]=$((${CACHE_STATS["size_bytes"]} - size))
    fi
}

# Invalidate cache entries by pattern
cache_invalidate_pattern() {
    local pattern="$1"
    
    # Invalidate L1 entries
    for key in "${!L1_CACHE[@]}"; do
        if [[ "$key" =~ $pattern ]]; then
            unset L1_CACHE[$key]
        fi
    done
    
    # Invalidate L2 entries
    for key in "${!CACHE_METADATA[@]}"; do
        if [[ "$key" =~ $pattern ]]; then
            cache_delete "$key"
        fi
    done
}

# AWS-specific cache functions
cache_aws_response() {
    local cache_key="$1"
    local aws_command="$2"
    local ttl="${3:-300}"  # Default 5 minutes for AWS responses
    
    # Try to get from cache
    local cached_response
    if cached_response=$(cache_get "$cache_key"); then
        echo "$cached_response"
        return 0
    fi
    
    # Execute AWS command and cache result
    local response
    response=$(eval "$aws_command" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]] && [[ -n "$response" ]]; then
        cache_set "$cache_key" "$response" "$ttl"
        echo "$response"
    fi
    
    return $exit_code
}

# Spot price caching with intelligent TTL
cache_spot_prices() {
    local region="$1"
    local instance_types="$2"
    
    # Use longer TTL for stable prices, shorter for volatile
    local base_ttl=3600  # 1 hour
    local cache_key="spot_prices:${region}:$(echo -n "$instance_types" | sha256sum | cut -d' ' -f1)"
    
    # Check price volatility from history
    local volatility=$(cache_get "spot_volatility:$region" || echo "normal")
    case "$volatility" in
        "high")
            base_ttl=900  # 15 minutes
            ;;
        "low")
            base_ttl=7200  # 2 hours
            ;;
    esac
    
    cache_aws_response "$cache_key" \
        "aws ec2 describe-spot-price-history --region $region --instance-types $instance_types --query 'SpotPriceHistory[0:10]'" \
        "$base_ttl"
}

# EC2 instance caching
cache_ec2_instances() {
    local region="$1"
    local filters="$2"
    local cache_key="ec2_instances:${region}:$(echo -n "$filters" | sha256sum | cut -d' ' -f1)"
    
    cache_aws_response "$cache_key" \
        "aws ec2 describe-instances --region $region $filters --query 'Reservations[*].Instances[*]'" \
        "60"  # 1 minute TTL for instance data
}

# AMI caching with longer TTL
cache_ami_info() {
    local region="$1"
    local ami_id="$2"
    local cache_key="ami:${region}:${ami_id}"
    
    cache_aws_response "$cache_key" \
        "aws ec2 describe-images --region $region --image-ids $ami_id" \
        "86400"  # 24 hour TTL for AMI data
}

# Cache maintenance functions
cache_enforce_size_limit() {
    local current_size=${CACHE_STATS["size_bytes"]}
    
    if [[ $current_size -gt $CACHE_MAX_SIZE ]]; then
        # Calculate how much to free
        local target_size=$((CACHE_MAX_SIZE * 80 / 100))  # Free to 80% of max
        local to_free=$((current_size - target_size))
        
        # Sort cache entries by last access time and remove oldest
        local entries_to_remove=()
        
        # Create temporary file for sorting
        local temp_file=$(mktemp)
        for key in "${!CACHE_METADATA[@]}"; do
            local metadata="${CACHE_METADATA[$key]}"
            local cache_file="${metadata%%|*}"
            local size=$(echo "$metadata" | cut -d'|' -f3)
            local access_time=$(stat -f %a "$cache_file" 2>/dev/null || stat -c %X "$cache_file" 2>/dev/null || echo 0)
            echo "$access_time|$key|$size" >> "$temp_file"
        done
        
        # Sort by access time and remove oldest entries
        local freed=0
        while IFS='|' read -r access_time key size; do
            if [[ $freed -ge $to_free ]]; then
                break
            fi
            
            cache_delete "$key"
            freed=$((freed + size))
            CACHE_STATS["evictions"]=$((${CACHE_STATS["evictions"]} + 1))
        done < <(sort -n "$temp_file")
        
        rm -f "$temp_file"
    fi
}

# Enforce L1 cache limits
cache_enforce_l1_limits() {
    while [[ ${#L1_CACHE[@]} -gt $L1_CACHE_MAX_ITEMS ]]; do
        # Remove oldest entry
        local oldest_key=""
        local oldest_time=$(date +%s)
        
        for key in "${!L1_CACHE[@]}"; do
            local entry="${L1_CACHE[$key]}"
            local expire_time="${entry%%|*}"
            if [[ $expire_time -lt $oldest_time ]]; then
                oldest_time=$expire_time
                oldest_key=$key
            fi
        done
        
        if [[ -n "$oldest_key" ]]; then
            unset L1_CACHE[$oldest_key]
        else
            break
        fi
    done
}

# Promote frequently accessed items to L1
declare -g -A CACHE_ACCESS_COUNT

cache_maybe_promote_to_l1() {
    local key="$1"
    local cache_file="$2"
    
    # Track access count
    CACHE_ACCESS_COUNT[$key]=$((${CACHE_ACCESS_COUNT[$key]:-0} + 1))
    
    # Promote if accessed frequently
    if [[ ${CACHE_ACCESS_COUNT[$key]} -ge 3 ]]; then
        local value=$(sed -n '3,$p' "$cache_file")
        if [[ ${#value} -lt 1024 ]]; then
            local expire_time=$(sed -n '1p' "$cache_file")
            L1_CACHE[$key]="$expire_time|$value"
            cache_enforce_l1_limits
        fi
        
        # Reset counter
        CACHE_ACCESS_COUNT[$key]=0
    fi
}

# Cache statistics and reporting
cache_stats() {
    echo "=== Cache Statistics ==="
    echo "Hits:      ${CACHE_STATS["hits"]}"
    echo "Misses:    ${CACHE_STATS["misses"]}"
    echo "Hit Rate:  $(cache_calculate_hit_rate)%"
    echo "Evictions: ${CACHE_STATS["evictions"]}"
    echo "L1 Items:  ${#L1_CACHE[@]}"
    echo "L2 Items:  ${#CACHE_METADATA[@]}"
    echo "Size:      $(cache_format_size ${CACHE_STATS["size_bytes"]})"
    echo "Max Size:  $(cache_format_size $CACHE_MAX_SIZE)"
}

cache_calculate_hit_rate() {
    local hits=${CACHE_STATS["hits"]}
    local misses=${CACHE_STATS["misses"]}
    local total=$((hits + misses))
    
    if [[ $total -eq 0 ]]; then
        echo "0"
    else
        echo "scale=2; ($hits * 100) / $total" | bc -l
    fi
}

cache_format_size() {
    local bytes="$1"
    
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc)KB"
    else
        echo "$(echo "scale=2; $bytes / 1048576" | bc)MB"
    fi
}

# Cache persistence functions
cache_save() {
    local save_file="${1:-$CACHE_DIR/cache.index}"
    
    {
        # Save cache metadata
        echo "# Cache index saved at $(date)"
        echo "# Format: key|file|expire|size"
        
        for key in "${!CACHE_METADATA[@]}"; do
            echo "$key|${CACHE_METADATA[$key]}"
        done
    } > "$save_file"
}

cache_load() {
    local save_file="${1:-$CACHE_DIR/cache.index}"
    
    if [[ ! -f "$save_file" ]]; then
        return 1
    fi
    
    # Clear current metadata
    CACHE_METADATA=()
    
    # Load from file
    while IFS='|' read -r key metadata; do
        if [[ "$key" =~ ^[^#] ]]; then
            CACHE_METADATA[$key]="$metadata"
        fi
    done < "$save_file"
}

# Cache maintenance daemon
cache_start_maintenance() {
    while true; do
        sleep 300  # Run every 5 minutes
        
        # Clean expired entries
        cache_clean_expired
        
        # Save cache index
        cache_save
        
        # Update statistics
        if [[ "$CACHE_VERBOSE" == "true" ]]; then
            cache_stats >&2
        fi
    done
}

cache_clean_expired() {
    local current_time=$(date +%s)
    local cleaned=0
    
    # Clean L1 cache
    for key in "${!L1_CACHE[@]}"; do
        local entry="${L1_CACHE[$key]}"
        local expire_time="${entry%%|*}"
        
        if [[ $current_time -gt $expire_time ]]; then
            unset L1_CACHE[$key]
            cleaned=$((cleaned + 1))
        fi
    done
    
    # Clean L2 cache
    for key in "${!CACHE_METADATA[@]}"; do
        local metadata="${CACHE_METADATA[$key]}"
        local expire_time=$(echo "$metadata" | cut -d'|' -f2)
        
        if [[ $current_time -gt $expire_time ]]; then
            cache_delete "$key"
            cleaned=$((cleaned + 1))
        fi
    done
    
    [[ "$CACHE_VERBOSE" == "true" ]] && echo "CACHE: Cleaned $cleaned expired entries" >&2
}

# Rebuild cache index from files
cache_rebuild_index() {
    CACHE_METADATA=()
    CACHE_STATS["size_bytes"]=0
    
    if [[ -d "$CACHE_DIR" ]]; then
        for cache_file in "$CACHE_DIR"/*; do
            if [[ -f "$cache_file" ]] && [[ "$(basename "$cache_file")" != "cache.index" ]]; then
                local expire_time=$(sed -n '1p' "$cache_file" 2>/dev/null || echo 0)
                local key=$(sed -n '2p' "$cache_file" 2>/dev/null || echo "")
                
                if [[ -n "$key" ]] && [[ $(date +%s) -lt $expire_time ]]; then
                    local size=$(stat -f %z "$cache_file" 2>/dev/null || stat -c %s "$cache_file" 2>/dev/null || echo 0)
                    CACHE_METADATA[$key]="$cache_file|$expire_time|$size"
                    CACHE_STATS["size_bytes"]=$((${CACHE_STATS["size_bytes"]} + size))
                else
                    # Clean up expired file
                    rm -f "$cache_file"
                fi
            fi
        done
    fi
}

# Export cache functions
export -f cache_init
export -f cache_set
export -f cache_get
export -f cache_delete
export -f cache_invalidate_pattern
export -f cache_aws_response
export -f cache_spot_prices
export -f cache_stats