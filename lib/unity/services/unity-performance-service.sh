#!/bin/bash
# Unity Performance Optimization Service
# Provides comprehensive performance profiling, optimization, and monitoring

set -euo pipefail

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source dependencies - skip if already loaded (for testing)
if [[ -z "${log_info:-}" ]]; then
    if [[ -f "$PROJECT_ROOT/lib/modules/core/logging.sh" ]]; then
        source "$PROJECT_ROOT/lib/modules/core/logging.sh"
    else
        # Define minimal logging functions if not available
        log_info() { echo "[INFO] $*"; }
        log_warn() { echo "[WARN] $*"; }
        log_error() { echo "[ERROR] $*"; }
        log_debug() { [[ "${DEBUG:-}" == "true" ]] && echo "[DEBUG] $*"; }
    fi
fi

source "$PROJECT_ROOT/lib/unity/core/registry.sh" || {
    echo "Error: Failed to load Unity registry" >&2
    exit 1
}

source "$PROJECT_ROOT/lib/unity/events/event-bus.sh" || {
    echo "Error: Failed to load Unity event bus" >&2
    exit 1
}

# Performance service configuration
PERF_CACHE_DIR="${UNITY_CACHE_DIR:-$PROJECT_ROOT/.unity/cache}/performance"
PERF_PROFILE_DIR="${UNITY_DATA_DIR:-$PROJECT_ROOT/.unity/data}/profiles"
PERF_METRICS_FILE="$PERF_CACHE_DIR/metrics.json"
PERF_BENCHMARKS_FILE="$PERF_CACHE_DIR/benchmarks.json"

# Performance thresholds
PERF_INIT_TIME_THRESHOLD=2000  # 2 seconds
PERF_MEMORY_THRESHOLD=104857600  # 100MB
PERF_API_CACHE_TTL=3600  # 1 hour
PERF_CONFIG_CACHE_TTL=300  # 5 minutes

# Global performance state - bash 3/4 compatible
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    declare -A PERF_METRICS
    declare -A PERF_TIMERS
    declare -A PERF_CACHE
    declare -A LAZY_LOAD_REGISTRY
else
    # Bash 3 fallback - use prefix-based storage
    PERF_METRICS_KEYS=""
    PERF_TIMERS_KEYS=""
    PERF_CACHE_KEYS=""
    LAZY_LOAD_REGISTRY_KEYS=""
fi

# Helper functions for bash 3 compatibility
_perf_set_metric() {
    local key="$1"
    local value="$2"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        PERF_METRICS[$key]="$value"
    else
        eval "PERF_METRIC_${key}=\"$value\""
        if [[ ! " $PERF_METRICS_KEYS " =~ " $key " ]]; then
            PERF_METRICS_KEYS="$PERF_METRICS_KEYS $key"
        fi
    fi
}

_perf_get_metric() {
    local key="$1"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        echo "${PERF_METRICS[$key]:-0}"
    else
        local var_name="PERF_METRIC_${key}"
        echo "${!var_name:-0}"
    fi
}

_perf_set_timer() {
    local key="$1"
    local value="$2"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        PERF_TIMERS[$key]="$value"
    else
        eval "PERF_TIMER_${key}=\"$value\""
    fi
}

_perf_get_timer() {
    local key="$1"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        echo "${PERF_TIMERS[$key]:-0}"
    else
        local var_name="PERF_TIMER_${key}"
        echo "${!var_name:-0}"
    fi
}

_perf_unset_timer() {
    local key="$1"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        unset PERF_TIMERS[$key]
    else
        unset "PERF_TIMER_${key}"
    fi
}

_perf_set_cache() {
    local key="$1"
    local value="$2"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        PERF_CACHE[$key]="$value"
    else
        eval "PERF_CACHE_${key}=\"$value\""
        if [[ ! " $PERF_CACHE_KEYS " =~ " $key " ]]; then
            PERF_CACHE_KEYS="$PERF_CACHE_KEYS $key"
        fi
    fi
}

_perf_get_cache() {
    local key="$1"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        echo "${PERF_CACHE[$key]:-}"
    else
        local var_name="PERF_CACHE_${key}"
        echo "${!var_name:-}"
    fi
}

_perf_unset_cache() {
    local key="$1"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        unset PERF_CACHE[$key]
    else
        unset "PERF_CACHE_${key}"
        PERF_CACHE_KEYS="${PERF_CACHE_KEYS// $key / }"
    fi
}

_perf_set_lazy_load() {
    local key="$1"
    local value="$2"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        LAZY_LOAD_REGISTRY[$key]="$value"
    else
        eval "LAZY_LOAD_${key}=\"$value\""
        if [[ ! " $LAZY_LOAD_REGISTRY_KEYS " =~ " $key " ]]; then
            LAZY_LOAD_REGISTRY_KEYS="$LAZY_LOAD_REGISTRY_KEYS $key"
        fi
    fi
}

_perf_get_lazy_load() {
    local key="$1"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        echo "${LAZY_LOAD_REGISTRY[$key]:-}"
    else
        local var_name="LAZY_LOAD_${key}"
        echo "${!var_name:-}"
    fi
}

# Initialize performance service
unity_performance_init() {
    local service_name="${1:-performance}"
    
    log_info "Initializing Unity performance optimization service..."
    
    # Create directories
    mkdir -p "$PERF_CACHE_DIR" "$PERF_PROFILE_DIR"
    
    # Initialize metrics
    _perf_set_metric "init_time" "0"
    _perf_set_metric "memory_usage" "0"
    _perf_set_metric "api_calls" "0"
    _perf_set_metric "cache_hits" "0"
    _perf_set_metric "cache_misses" "0"
    
    # Register with Unity
    unity_register_service "$service_name" "Unity Performance Optimization Service" \
        "performance,profiling,optimization,caching,monitoring"
    
    # Register event handlers
    unity_event_on "service.starting" "perf_handle_service_starting"
    unity_event_on "service.started" "perf_handle_service_started"
    unity_event_on "api.call" "perf_handle_api_call"
    unity_event_on "config.loaded" "perf_handle_config_loaded"
    
    # Start background monitoring (skip in test mode)
    if [[ "${UNITY_TEST_MODE:-}" != "true" ]]; then
        perf_start_monitoring &
    fi
    
    log_info "Performance optimization service initialized"
    return 0
}

# Profile system performance
perf_profile_system() {
    local profile_name="${1:-system}"
    local profile_file="$PERF_PROFILE_DIR/${profile_name}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Starting performance profile: $profile_name"
    
    local profile_data=$(cat <<EOF
{
    "name": "$profile_name",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "system": {
        "bash_version": "$BASH_VERSION",
        "platform": "$(uname -s)",
        "architecture": "$(uname -m)",
        "memory_total": $(get_total_memory),
        "cpu_count": $(get_cpu_count)
    },
    "metrics": {
        "init_time": $(_perf_get_metric "init_time"),
        "memory_usage": $(_perf_get_metric "memory_usage"),
        "api_calls": $(_perf_get_metric "api_calls"),
        "cache_hits": $(_perf_get_metric "cache_hits"),
        "cache_misses": $(_perf_get_metric "cache_misses")
    },
    "bottlenecks": $(identify_bottlenecks)
}
EOF
)
    
    echo "$profile_data" > "$profile_file"
    log_info "Performance profile saved to: $profile_file"
    
    # Emit profile completed event
    unity_event_emit "performance.profile.completed" "$profile_file"
    
    return 0
}

# Start performance timer
perf_timer_start() {
    local timer_name="$1"
    # Use nanoseconds if available, otherwise fall back to seconds
    if date +%s%N >/dev/null 2>&1; then
        _perf_set_timer "$timer_name" "$(date +%s%N)"
    else
        _perf_set_timer "$timer_name" "$(date +%s)000000000"
    fi
}

# Stop performance timer and record metric
perf_timer_stop() {
    local timer_name="$1"
    local start_time="$(_perf_get_timer "$timer_name")"
    
    if [[ "$start_time" -eq 0 ]]; then
        log_warn "Timer not started: $timer_name"
        return 1
    fi
    
    # Use nanoseconds if available
    local end_time
    if date +%s%N >/dev/null 2>&1; then
        end_time=$(date +%s%N)
    else
        end_time=$(date +%s)000000000
    fi
    
    # Calculate duration in milliseconds
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    # Record metric
    _perf_set_metric "timer_${timer_name}" "$duration"
    
    # Clean up timer
    _perf_unset_timer "$timer_name"
    
    log_debug "Timer $timer_name: ${duration}ms"
    
    # Check for performance issues
    if [[ "$timer_name" == "init" && "$duration" -gt "$PERF_INIT_TIME_THRESHOLD" ]]; then
        log_warn "Initialization time exceeded threshold: ${duration}ms > ${PERF_INIT_TIME_THRESHOLD}ms"
        unity_event_emit "performance.threshold.exceeded" "init_time" "$duration"
    fi
    
    return 0
}

# Lazy load service
perf_lazy_load_service() {
    local service_name="$1"
    local service_path="$2"
    local load_priority="${3:-normal}"  # immediate, high, normal, low
    
    log_debug "Registering lazy-loaded service: $service_name (priority: $load_priority)"
    
    # Store in lazy load registry
    _perf_set_lazy_load "$service_name" "$service_path:$load_priority:pending"
    
    # Handle immediate priority
    if [[ "$load_priority" == "immediate" ]]; then
        perf_load_service_now "$service_name"
    fi
    
    return 0
}

# Load service on demand
perf_load_service_now() {
    local service_name="$1"
    local registry_entry="$(_perf_get_lazy_load "$service_name")"
    
    if [[ -z "$registry_entry" ]]; then
        log_error "Service not registered for lazy loading: $service_name"
        return 1
    fi
    
    local service_path="${registry_entry%%:*}"
    local status="${registry_entry##*:}"
    
    if [[ "$status" == "loaded" ]]; then
        log_debug "Service already loaded: $service_name"
        return 0
    fi
    
    log_info "Lazy loading service: $service_name"
    perf_timer_start "lazy_load_$service_name"
    
    # Source the service
    if source "$service_path"; then
        # Update status
        local priority="${registry_entry#*:}"
        priority="${priority%:*}"
        _perf_set_lazy_load "$service_name" "$service_path:$priority:loaded"
        
        perf_timer_stop "lazy_load_$service_name"
        unity_event_emit "service.lazy_loaded" "$service_name"
        return 0
    else
        log_error "Failed to load service: $service_name"
        return 1
    fi
}

# Cache AWS API response
perf_cache_aws_response() {
    local cache_key="$1"
    local response="$2"
    local ttl="${3:-$PERF_API_CACHE_TTL}"
    
    # Ensure response is valid JSON
    local json_data
    if echo "$response" | jq -c '.' >/dev/null 2>&1; then
        json_data=$(echo "$response" | jq -c '.')
    else
        # Escape response as string if not valid JSON
        json_data=$(echo "$response" | jq -Rs '.')
    fi
    
    # Create cache entry with proper JSON formatting
    local timestamp=$(date +%s)
    local cache_entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg ttl "$ttl" \
        --argjson data "$json_data" \
        '{timestamp: ($ts | tonumber), ttl: ($ttl | tonumber), data: $data}')
    
    # Store in memory cache
    _perf_set_cache "aws_$cache_key" "$cache_entry"
    
    # Store in file cache for persistence
    local cache_file="$PERF_CACHE_DIR/aws_$(echo "$cache_key" | sed 's/[^a-zA-Z0-9_-]/_/g').json"
    echo "$cache_entry" > "$cache_file"
    
    local writes=$(_perf_get_metric "cache_writes"); _perf_set_metric "cache_writes" "$((writes + 1))"
    log_debug "Cached AWS response: $cache_key (TTL: ${ttl}s)"
    
    return 0
}

# Get cached AWS response
perf_get_cached_aws_response() {
    local cache_key="$1"
    log_debug "Getting cache for key: aws_$cache_key"
    local cache_entry="$(_perf_get_cache "aws_$cache_key")"
    log_debug "Cache entry retrieved: ${cache_entry:0:50}..."
    
    # Check memory cache first
    if [[ -z "$cache_entry" ]]; then
        # Check file cache
        local cache_file="$PERF_CACHE_DIR/aws_$(echo "$cache_key" | sed 's/[^a-zA-Z0-9_-]/_/g').json"
        if [[ -f "$cache_file" ]]; then
            cache_entry=$(cat "$cache_file" 2>/dev/null || echo "")
        fi
    fi
    
    if [[ -z "$cache_entry" ]]; then
        local misses=$(_perf_get_metric "cache_misses"); _perf_set_metric "cache_misses" "$((misses + 1))"
        return 1
    fi
    
    # Check TTL
    local timestamp=$(echo "$cache_entry" | jq -r '.timestamp' 2>/dev/null || echo "0")
    local ttl=$(echo "$cache_entry" | jq -r '.ttl' 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    
    # Handle invalid timestamps
    if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then
        timestamp=0
    fi
    if [[ ! "$ttl" =~ ^[0-9]+$ ]]; then
        ttl=0
    fi
    
    local age=$((current_time - timestamp))
    
    if [[ "$age" -gt "$ttl" ]]; then
        log_debug "Cache expired for: $cache_key (age: ${age}s, ttl: ${ttl}s)"
        _perf_unset_cache "aws_$cache_key"
        local misses=$(_perf_get_metric "cache_misses"); _perf_set_metric "cache_misses" "$((misses + 1))"
        return 1
    fi
    
    # Return cached data
    echo "$cache_entry" | jq -r '.data' 2>/dev/null || echo "$cache_entry"
    local hits=$(_perf_get_metric "cache_hits"); _perf_set_metric "cache_hits" "$((hits + 1))"
    log_debug "Cache hit for: $cache_key (age: ${age}s)"
    
    return 0
}

# Batch AWS API calls
perf_batch_aws_calls() {
    local call_type="$1"
    shift
    local calls=("$@")
    
    log_info "Batching ${#calls[@]} AWS $call_type calls"
    
    case "$call_type" in
        "describe-instances")
            perf_batch_describe_instances "${calls[@]}"
            ;;
        "describe-vpcs")
            perf_batch_describe_vpcs "${calls[@]}"
            ;;
        "describe-security-groups")
            perf_batch_describe_security_groups "${calls[@]}"
            ;;
        *)
            log_warn "Unsupported batch call type: $call_type"
            return 1
            ;;
    esac
}

# Batch describe instances
perf_batch_describe_instances() {
    local instance_ids=("$@")
    local batch_size=50  # AWS limit
    local results=""
    
    for ((i=0; i<${#instance_ids[@]}; i+=batch_size)); do
        local batch=("${instance_ids[@]:i:batch_size}")
        local batch_key="instances_$(IFS=,; echo "${batch[*]}")"
        
        # Check cache first
        if local cached=$(perf_get_cached_aws_response "$batch_key"); then
            results+="$cached"
            continue
        fi
        
        # Make batched API call
        local response=$(aws ec2 describe-instances \
            --instance-ids "${batch[@]}" \
            --output json 2>/dev/null || echo "{}")
        
        # Cache response
        perf_cache_aws_response "$batch_key" "$response"
        
        results+="$response"
        
        # Rate limiting
        sleep 0.5
    done
    
    echo "$results"
}

# Monitor memory usage
perf_monitor_memory() {
    local pid="${1:-$$}"
    
    if command -v ps >/dev/null 2>&1; then
        local memory_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
        local memory_bytes=$((memory_kb * 1024))
        
        _perf_set_metric "memory_usage" "$memory_bytes"
        
        if [[ "$memory_bytes" -gt "$PERF_MEMORY_THRESHOLD" ]]; then
            log_warn "Memory usage exceeded threshold: $(format_bytes $memory_bytes) > $(format_bytes $PERF_MEMORY_THRESHOLD)"
            unity_event_emit "performance.threshold.exceeded" "memory" "$memory_bytes"
        fi
    fi
}

# Optimize data structures
perf_optimize_data_structure() {
    local data_type="$1"
    local data="$2"
    
    case "$data_type" in
        "json")
            # Compact JSON
            echo "$data" | jq -c '.'
            ;;
        "array")
            # Deduplicate array
            echo "$data" | tr ' ' '\n' | sort -u | tr '\n' ' '
            ;;
        "string")
            # Trim whitespace
            echo "$data" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        *)
            echo "$data"
            ;;
    esac
}

# Generate performance recommendations
perf_generate_recommendations() {
    local profile_file="${1:-latest}"
    
    if [[ "$profile_file" == "latest" ]]; then
        profile_file=$(ls -t "$PERF_PROFILE_DIR"/*.json 2>/dev/null | head -n1)
    fi
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile file not found: $profile_file"
        return 1
    fi
    
    local profile=$(cat "$profile_file")
    local recommendations=()
    
    # Check initialization time
    local init_time=$(echo "$profile" | jq -r '.metrics.init_time // 0')
    if [[ "$init_time" -gt "$PERF_INIT_TIME_THRESHOLD" ]]; then
        recommendations+=("Enable lazy loading for non-critical services to reduce initialization time")
    fi
    
    # Check memory usage
    local memory_usage=$(echo "$profile" | jq -r '.metrics.memory_usage // 0')
    if [[ "$memory_usage" -gt "$PERF_MEMORY_THRESHOLD" ]]; then
        recommendations+=("Implement data structure optimization to reduce memory footprint")
    fi
    
    # Check cache effectiveness
    local cache_hits=$(echo "$profile" | jq -r '.metrics.cache_hits // 0')
    local cache_misses=$(echo "$profile" | jq -r '.metrics.cache_misses // 0')
    local total_requests=$((cache_hits + cache_misses))
    
    if [[ "$total_requests" -gt 0 ]]; then
        local hit_rate=$((cache_hits * 100 / total_requests))
        if [[ "$hit_rate" -lt 80 ]]; then
            recommendations+=("Increase cache TTL or implement predictive caching (current hit rate: ${hit_rate}%)")
        fi
    fi
    
    # Check API call frequency
    local api_calls=$(echo "$profile" | jq -r '.metrics.api_calls // 0')
    if [[ "$api_calls" -gt 100 ]]; then
        recommendations+=("Enable API call batching to reduce number of requests")
    fi
    
    # Output recommendations
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        echo "No performance issues detected. System is operating within optimal parameters."
    else
        echo "Performance Optimization Recommendations:"
        for i in "${!recommendations[@]}"; do
            echo "$((i+1)). ${recommendations[$i]}"
        done
    fi
    
    return 0
}

# Identify performance bottlenecks
identify_bottlenecks() {
    local bottlenecks="[]"
    
    # Check timer metrics
    local metrics_to_check
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        metrics_to_check="${!PERF_METRICS[@]}"
    else
        metrics_to_check="$PERF_METRICS_KEYS"
    fi
    
    for metric in $metrics_to_check; do
        if [[ "$metric" =~ ^timer_ ]]; then
            local timer_name="${metric#timer_}"
            local duration="$(_perf_get_metric "$metric")"
            
            # Define thresholds for different operations
            local threshold=1000  # Default 1 second
            case "$timer_name" in
                "aws_api_"*) threshold=5000 ;;  # 5 seconds for AWS APIs
                "config_"*) threshold=500 ;;     # 500ms for config ops
                "cache_"*) threshold=100 ;;      # 100ms for cache ops
            esac
            
            if [[ "$duration" -gt "$threshold" ]]; then
                bottlenecks=$(echo "$bottlenecks" | jq ". + [{\"operation\": \"$timer_name\", \"duration\": $duration, \"threshold\": $threshold}]")
            fi
        fi
    done
    
    echo "$bottlenecks"
}

# Background performance monitoring
perf_start_monitoring() {
    while true; do
        # Monitor memory every 10 seconds
        perf_monitor_memory
        
        # Save metrics periodically
        perf_save_metrics
        
        # Clean expired cache entries
        perf_cleanup_cache
        
        sleep 10
    done
}

# Save performance metrics
perf_save_metrics() {
    local metrics_data=$(cat <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "metrics": {
        "init_time": $(_perf_get_metric "init_time"),
        "memory_usage": $(_perf_get_metric "memory_usage"),
        "api_calls": $(_perf_get_metric "api_calls"),
        "cache_hits": $(_perf_get_metric "cache_hits"),
        "cache_misses": $(_perf_get_metric "cache_misses"),
        "cache_writes": $(_perf_get_metric "cache_writes")
    }
}
EOF
)
    
    echo "$metrics_data" > "$PERF_METRICS_FILE"
}

# Clean up expired cache entries
perf_cleanup_cache() {
    local current_time=$(date +%s)
    local cleaned=0
    
    # Clean memory cache
    local cache_keys
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        cache_keys="${!PERF_CACHE[@]}"
    else
        cache_keys="$PERF_CACHE_KEYS"
    fi
    
    for key in $cache_keys; do
        local entry="$(_perf_get_cache "$key")"
        local timestamp=$(echo "$entry" | jq -r '.timestamp // 0')
        local ttl=$(echo "$entry" | jq -r '.ttl // 0')
        local age=$((current_time - timestamp))
        
        if [[ "$age" -gt "$ttl" ]]; then
            _perf_unset_cache "$key"
            ((cleaned++))
        fi
    done
    
    # Clean file cache
    find "$PERF_CACHE_DIR" -name "*.json" -type f -mmin +60 -delete 2>/dev/null || true
    
    if [[ "$cleaned" -gt 0 ]]; then
        log_debug "Cleaned $cleaned expired cache entries"
    fi
}

# Event handlers
perf_handle_service_starting() {
    local service_name="$1"
    perf_timer_start "service_start_$service_name"
}

perf_handle_service_started() {
    local service_name="$1"
    perf_timer_stop "service_start_$service_name"
}

perf_handle_api_call() {
    local api_type="$1"
    local calls=$(_perf_get_metric "api_calls"); _perf_set_metric "api_calls" "$((calls + 1))"
    perf_timer_start "aws_api_$api_type"
}

perf_handle_config_loaded() {
    local config_file="$1"
    log_debug "Configuration loaded: $config_file"
}

# Utility functions
get_total_memory() {
    if [[ -f /proc/meminfo ]]; then
        awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.memsize 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_cpu_count() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || echo "1"
    else
        echo "1"
    fi
}

format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while [[ "$bytes" -gt 1024 && "$unit" -lt 4 ]]; do
        bytes=$((bytes / 1024))
        ((unit++))
    done
    
    echo "${bytes}${units[$unit]}"
}

# Performance benchmarking
perf_run_benchmark() {
    local benchmark_name="${1:-full}"
    local iterations="${2:-10}"
    
    log_info "Running performance benchmark: $benchmark_name (iterations: $iterations)"
    
    local results=()
    
    case "$benchmark_name" in
        "full")
            results+=("$(perf_benchmark_lazy_loading "$iterations")")
            results+=("$(perf_benchmark_caching "$iterations")")
            results+=("$(perf_benchmark_api_batching "$iterations")")
            results+=("$(perf_benchmark_memory "$iterations")")
            ;;
        "lazy_loading")
            results+=("$(perf_benchmark_lazy_loading "$iterations")")
            ;;
        "caching")
            results+=("$(perf_benchmark_caching "$iterations")")
            ;;
        "api_batching")
            results+=("$(perf_benchmark_api_batching "$iterations")")
            ;;
        "memory")
            results+=("$(perf_benchmark_memory "$iterations")")
            ;;
        *)
            log_error "Unknown benchmark: $benchmark_name"
            return 1
            ;;
    esac
    
    # Save benchmark results
    local benchmark_data=$(cat <<EOF
{
    "name": "$benchmark_name",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "iterations": $iterations,
    "results": [$(IFS=,; echo "${results[*]}")]
}
EOF
)
    
    echo "$benchmark_data" > "$PERF_BENCHMARKS_FILE"
    log_info "Benchmark completed. Results saved to: $PERF_BENCHMARKS_FILE"
    
    # Emit benchmark completed event
    unity_event_emit "performance.benchmark.completed" "$benchmark_name"
    
    return 0
}

# Benchmark lazy loading
perf_benchmark_lazy_loading() {
    local iterations="$1"
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s)
        
        # Simulate lazy loading
        perf_lazy_load_service "test_service_$i" "/dev/null" "normal"
        
        local end=$(date +%s)
        total_time=$((total_time + (end - start)))
    done
    
    local avg_time=$((total_time / iterations))
    echo "{\"test\": \"lazy_loading\", \"avg_time_ms\": $avg_time}"
}

# Benchmark caching
perf_benchmark_caching() {
    local iterations="$1"
    local cache_hits=0
    local total_time=0
    
    # Warm up cache
    perf_cache_aws_response "benchmark_key" '{"data": "test"}' 3600
    
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s)
        
        if perf_get_cached_aws_response "benchmark_key" >/dev/null; then
            ((cache_hits++))
        fi
        
        local end=$(date +%s)
        total_time=$((total_time + (end - start)))
    done
    
    local avg_time=$((total_time / iterations))
    local hit_rate=$((cache_hits * 100 / iterations))
    echo "{\"test\": \"caching\", \"avg_time_ms\": $avg_time, \"hit_rate\": $hit_rate}"
}

# Benchmark API batching
perf_benchmark_api_batching() {
    local iterations="$1"
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s)
        
        # Simulate batched API calls
        local instance_ids=()
        for ((j=1; j<=10; j++)); do
            instance_ids+=("i-$(printf '%016x' $RANDOM)")
        done
        
        # Mock batching (actual AWS calls would be too expensive for benchmarking)
        sleep 0.01  # Simulate API latency
        
        local end=$(date +%s)
        total_time=$((total_time + (end - start)))
    done
    
    local avg_time=$((total_time / iterations))
    echo "{\"test\": \"api_batching\", \"avg_time_ms\": $avg_time}"
}

# Benchmark memory optimization
perf_benchmark_memory() {
    local iterations="$1"
    local total_memory=0
    
    for ((i=1; i<=iterations; i++)); do
        # Get current memory usage
        perf_monitor_memory
        total_memory=$((total_memory + $(_perf_get_metric "memory_usage")))
        
        # Simulate data structure operations
        local test_data=$(seq 1 1000 | tr '\n' ' ')
        local optimized=$(perf_optimize_data_structure "array" "$test_data")
        
        sleep 0.1
    done
    
    local avg_memory=$((total_memory / iterations))
    echo "{\"test\": \"memory\", \"avg_memory_bytes\": $avg_memory}"
}

# Main function for standalone execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "init")
            unity_performance_init
            ;;
        "profile")
            perf_profile_system "${2:-system}"
            ;;
        "benchmark")
            perf_run_benchmark "${2:-full}" "${3:-10}"
            ;;
        "recommendations")
            perf_generate_recommendations "${2:-latest}"
            ;;
        "cache")
            case "${2:-}" in
                "stats")
                    echo "Cache hits: $(_perf_get_metric "cache_hits")"
                    echo "Cache misses: $(_perf_get_metric "cache_misses")"
                    echo "Cache writes: $(_perf_get_metric "cache_writes")"
                    ;;
                "clear")
                    rm -rf "$PERF_CACHE_DIR"/*
                    echo "Cache cleared"
                    ;;
                *)
                    echo "Usage: $0 cache [stats|clear]"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Unity Performance Optimization Service"
            echo "Usage: $0 [init|profile|benchmark|recommendations|cache]"
            echo ""
            echo "Commands:"
            echo "  init                    Initialize performance service"
            echo "  profile [name]          Create performance profile"
            echo "  benchmark [type] [n]    Run performance benchmarks"
            echo "  recommendations [file]  Generate optimization recommendations"
            echo "  cache [stats|clear]     Manage performance cache"
            exit 1
            ;;
    esac
fi