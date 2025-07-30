#!/usr/bin/env bash
# =============================================================================
# AWS API Caching System
# High-performance caching layer for AWS API calls with intelligent TTL management
# Compatible with bash 3.x+
# =============================================================================

# Load dependencies
if [[ -n "$LIB_DIR" ]]; then
    source "$LIB_DIR/associative-arrays.sh" 2>/dev/null || true
fi

# =============================================================================
# GLOBAL CACHE CONFIGURATION
# =============================================================================

# Global cache arrays
declare -gA AWS_API_CACHE
declare -gA AWS_API_CACHE_METADATA
declare -gA AWS_API_CACHE_STATS

# Default TTL values (in seconds)
declare -g AWS_CACHE_DEFAULT_TTL=300          # 5 minutes
declare -g AWS_CACHE_SPOT_PRICE_TTL=3600      # 1 hour
declare -g AWS_CACHE_INSTANCE_TYPE_TTL=86400  # 24 hours
declare -g AWS_CACHE_AZ_TTL=3600              # 1 hour
declare -g AWS_CACHE_AMI_TTL=86400            # 24 hours
declare -g AWS_CACHE_SUBNET_TTL=1800          # 30 minutes
declare -g AWS_CACHE_VPC_TTL=3600             # 1 hour

# Cache size limits
declare -g AWS_CACHE_MAX_ENTRIES=1000
declare -g AWS_CACHE_CLEANUP_THRESHOLD=900

# =============================================================================
# CACHE KEY GENERATION
# =============================================================================

# Generate consistent cache key from AWS CLI command
generate_cache_key() {
    local service="$1"
    local command="$2"
    local region="${3:-$AWS_REGION}"
    shift 3
    local params="$*"
    
    # Normalize parameters for consistent keys
    local normalized_params
    normalized_params=$(echo "$params" | tr ' ' '_' | tr -d '\n' | sed 's/__*/_/g')
    
    # Create cache key
    local cache_key="${service}:${command}:${region}:${normalized_params}"
    echo "$cache_key"
}

# =============================================================================
# CACHE OPERATIONS
# =============================================================================

# Store value in cache with TTL
cache_put() {
    local key="$1"
    local value="$2"
    local ttl="${3:-$AWS_CACHE_DEFAULT_TTL}"
    
    # Store value
    aa_set AWS_API_CACHE "$key" "$value"
    
    # Store metadata
    local timestamp=$(date +%s)
    aa_set AWS_API_CACHE_METADATA "${key}:timestamp" "$timestamp"
    aa_set AWS_API_CACHE_METADATA "${key}:ttl" "$ttl"
    aa_set AWS_API_CACHE_METADATA "${key}:hits" "0"
    
    # Update stats
    local total_puts=$(aa_get AWS_API_CACHE_STATS "total_puts" "0")
    aa_set AWS_API_CACHE_STATS "total_puts" $((total_puts + 1))
    
    # Check if cleanup needed
    local cache_size=$(aa_size AWS_API_CACHE)
    if [[ $cache_size -gt $AWS_CACHE_CLEANUP_THRESHOLD ]]; then
        cache_cleanup
    fi
}

# Get value from cache if not expired
cache_get() {
    local key="$1"
    
    # Check if key exists
    if ! aa_has_key AWS_API_CACHE "$key"; then
        return 1
    fi
    
    # Check expiration
    local timestamp=$(aa_get AWS_API_CACHE_METADATA "${key}:timestamp" "0")
    local ttl=$(aa_get AWS_API_CACHE_METADATA "${key}:ttl" "$AWS_CACHE_DEFAULT_TTL")
    local current_time=$(date +%s)
    local age=$((current_time - timestamp))
    
    if [[ $age -gt $ttl ]]; then
        # Expired - remove from cache
        cache_evict "$key"
        return 1
    fi
    
    # Update hit count
    local hits=$(aa_get AWS_API_CACHE_METADATA "${key}:hits" "0")
    aa_set AWS_API_CACHE_METADATA "${key}:hits" $((hits + 1))
    
    # Update stats
    local total_hits=$(aa_get AWS_API_CACHE_STATS "total_hits" "0")
    aa_set AWS_API_CACHE_STATS "total_hits" $((total_hits + 1))
    
    # Return value
    aa_get AWS_API_CACHE "$key"
    return 0
}

# Remove entry from cache
cache_evict() {
    local key="$1"
    
    aa_unset AWS_API_CACHE "$key"
    aa_unset AWS_API_CACHE_METADATA "${key}:timestamp"
    aa_unset AWS_API_CACHE_METADATA "${key}:ttl"
    aa_unset AWS_API_CACHE_METADATA "${key}:hits"
}

# Clean up expired entries
cache_cleanup() {
    local current_time=$(date +%s)
    local evicted=0
    
    for key in $(aa_keys AWS_API_CACHE); do
        local timestamp=$(aa_get AWS_API_CACHE_METADATA "${key}:timestamp" "0")
        local ttl=$(aa_get AWS_API_CACHE_METADATA "${key}:ttl" "$AWS_CACHE_DEFAULT_TTL")
        local age=$((current_time - timestamp))
        
        if [[ $age -gt $ttl ]]; then
            cache_evict "$key"
            evicted=$((evicted + 1))
        fi
    done
    
    # If still over limit, evict least recently used
    local cache_size=$(aa_size AWS_API_CACHE)
    if [[ $cache_size -gt $AWS_CACHE_MAX_ENTRIES ]]; then
        # Get entries sorted by hits (least used first)
        local entries_to_evict=$((cache_size - AWS_CACHE_MAX_ENTRIES + 100))
        local count=0
        
        # Simple LRU eviction
        for key in $(aa_keys AWS_API_CACHE); do
            if [[ $count -lt $entries_to_evict ]]; then
                cache_evict "$key"
                evicted=$((evicted + 1))
                count=$((count + 1))
            else
                break
            fi
        done
    fi
    
    # Update cleanup stats
    local total_cleanups=$(aa_get AWS_API_CACHE_STATS "total_cleanups" "0")
    local total_evictions=$(aa_get AWS_API_CACHE_STATS "total_evictions" "0")
    aa_set AWS_API_CACHE_STATS "total_cleanups" $((total_cleanups + 1))
    aa_set AWS_API_CACHE_STATS "total_evictions" $((total_evictions + evicted))
    
    [[ $evicted -gt 0 ]] && log "Cache cleanup: evicted $evicted entries"
}

# =============================================================================
# CACHED AWS CLI WRAPPER
# =============================================================================

# Execute AWS CLI command with caching
aws_cli_cached() {
    local ttl="${1:-$AWS_CACHE_DEFAULT_TTL}"
    shift
    local service="$1"
    local command="$2"
    shift 2
    local params=("$@")
    
    # Generate cache key
    local cache_key
    cache_key=$(generate_cache_key "$service" "$command" "$AWS_REGION" "${params[@]}")
    
    # Try to get from cache
    local cached_result
    if cached_result=$(cache_get "$cache_key"); then
        # Cache hit
        local total_misses=$(aa_get AWS_API_CACHE_STATS "total_misses" "0")
        aa_set AWS_API_CACHE_STATS "total_misses" $((total_misses + 1))
        echo "$cached_result"
        return 0
    fi
    
    # Cache miss - execute AWS CLI
    local result
    result=$(aws "$service" "$command" "${params[@]}" 2>&1)
    local exit_code=$?
    
    # Only cache successful results
    if [[ $exit_code -eq 0 ]]; then
        cache_put "$cache_key" "$result" "$ttl"
    fi
    
    echo "$result"
    return $exit_code
}

# =============================================================================
# SPECIALIZED CACHING FUNCTIONS
# =============================================================================

# Get spot prices with intelligent caching
get_spot_prices_cached() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    local availability_zones=("${@:3}")
    
    # Use longer TTL for spot prices
    aws_cli_cached "$AWS_CACHE_SPOT_PRICE_TTL" ec2 describe-spot-price-history \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-items 10 \
        --region "$region" \
        --query 'SpotPriceHistory[].[AvailabilityZone,SpotPrice,Timestamp]' \
        --output text
}

# Get instance type details with caching
get_instance_types_cached() {
    local instance_types=("$@")
    local region="${AWS_REGION:-us-east-1}"
    
    # Use longer TTL for instance type data
    if [[ ${#instance_types[@]} -eq 0 ]]; then
        aws_cli_cached "$AWS_CACHE_INSTANCE_TYPE_TTL" ec2 describe-instance-types \
            --region "$region" \
            --query 'InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,GpuInfo.Gpus[0].Count,GpuInfo.Gpus[0].MemoryInfo.SizeInMiB]' \
            --output text
    else
        aws_cli_cached "$AWS_CACHE_INSTANCE_TYPE_TTL" ec2 describe-instance-types \
            --instance-types "${instance_types[@]}" \
            --region "$region" \
            --query 'InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,GpuInfo.Gpus[0].Count,GpuInfo.Gpus[0].MemoryInfo.SizeInMiB]' \
            --output text
    fi
}

# Get availability zones with caching
get_availability_zones_cached() {
    local region="${1:-$AWS_REGION}"
    
    aws_cli_cached "$AWS_CACHE_AZ_TTL" ec2 describe-availability-zones \
        --region "$region" \
        --query 'AvailabilityZones[].[ZoneName,State]' \
        --output text
}

# Get AMIs with caching
get_amis_cached() {
    local region="${1:-$AWS_REGION}"
    local owner="${2:-amazon}"
    local name_pattern="${3:-*}"
    
    aws_cli_cached "$AWS_CACHE_AMI_TTL" ec2 describe-images \
        --owners "$owner" \
        --filters "Name=name,Values=$name_pattern" "Name=state,Values=available" \
        --region "$region" \
        --query 'Images | sort_by(@, &CreationDate) | [-5:].[ImageId,Name,CreationDate]' \
        --output text
}

# =============================================================================
# CACHE STATISTICS AND MONITORING
# =============================================================================

# Get cache statistics
get_cache_stats() {
    local total_entries=$(aa_size AWS_API_CACHE)
    local total_hits=$(aa_get AWS_API_CACHE_STATS "total_hits" "0")
    local total_misses=$(aa_get AWS_API_CACHE_STATS "total_misses" "0")
    local total_puts=$(aa_get AWS_API_CACHE_STATS "total_puts" "0")
    local total_evictions=$(aa_get AWS_API_CACHE_STATS "total_evictions" "0")
    local total_cleanups=$(aa_get AWS_API_CACHE_STATS "total_cleanups" "0")
    
    local hit_rate=0
    if [[ $((total_hits + total_misses)) -gt 0 ]]; then
        hit_rate=$(echo "scale=2; $total_hits * 100 / ($total_hits + $total_misses)" | bc -l 2>/dev/null || echo "0")
    fi
    
    cat <<EOF
AWS API Cache Statistics:
========================
Total Entries: $total_entries / $AWS_CACHE_MAX_ENTRIES
Cache Hit Rate: ${hit_rate}%
Total Hits: $total_hits
Total Misses: $total_misses
Total Puts: $total_puts
Total Evictions: $total_evictions
Total Cleanups: $total_cleanups
EOF
}

# Clear entire cache
clear_cache() {
    aa_clear AWS_API_CACHE
    aa_clear AWS_API_CACHE_METADATA
    aa_clear AWS_API_CACHE_STATS
    log "AWS API cache cleared"
}

# =============================================================================
# CACHE WARMUP
# =============================================================================

# Warm up cache with common data
warmup_cache() {
    local region="${1:-$AWS_REGION}"
    
    log "Warming up AWS API cache for region: $region"
    
    # Get availability zones
    get_availability_zones_cached "$region" >/dev/null
    
    # Get common instance types
    local common_instance_types=("t3.micro" "t3.small" "t3.medium" "g4dn.xlarge" "g4dn.2xlarge" "g5.xlarge")
    get_instance_types_cached "${common_instance_types[@]}" >/dev/null
    
    # Get spot prices for common GPU instances
    for instance_type in "g4dn.xlarge" "g4dn.2xlarge" "g5.xlarge"; do
        get_spot_prices_cached "$instance_type" "$region" >/dev/null
    done
    
    log "Cache warmup complete"
}

# =============================================================================
# BATCH OPERATIONS
# =============================================================================

# Batch get multiple cached values
batch_cache_get() {
    local keys=("$@")
    local results=()
    
    for key in "${keys[@]}"; do
        local value
        if value=$(cache_get "$key"); then
            results+=("$key:$value")
        fi
    done
    
    printf '%s\n' "${results[@]}"
}

# Batch put multiple values
batch_cache_put() {
    local ttl="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        cache_put "$key" "$value" "$ttl"
    done
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize cache system
init_aws_cache() {
    # Set cache configuration from environment
    AWS_CACHE_DEFAULT_TTL="${AWS_CACHE_DEFAULT_TTL:-300}"
    AWS_CACHE_SPOT_PRICE_TTL="${AWS_CACHE_SPOT_PRICE_TTL:-3600}"
    AWS_CACHE_INSTANCE_TYPE_TTL="${AWS_CACHE_INSTANCE_TYPE_TTL:-86400}"
    AWS_CACHE_MAX_ENTRIES="${AWS_CACHE_MAX_ENTRIES:-1000}"
    
    # Initialize stats
    aa_set AWS_API_CACHE_STATS "initialized" "$(date +%s)"
    aa_set AWS_API_CACHE_STATS "total_hits" "0"
    aa_set AWS_API_CACHE_STATS "total_misses" "0"
    aa_set AWS_API_CACHE_STATS "total_puts" "0"
    aa_set AWS_API_CACHE_STATS "total_evictions" "0"
    aa_set AWS_API_CACHE_STATS "total_cleanups" "0"
}

# Auto-initialize if sourced
init_aws_cache