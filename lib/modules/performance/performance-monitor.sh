#!/usr/bin/env bash
# =============================================================================
# Performance Monitoring System
# Track and optimize deployment performance metrics
# Compatible with bash 3.x+
# =============================================================================

# Load dependencies
if [[ -n "$LIB_DIR" ]]; then
    source "$LIB_DIR/associative-arrays.sh" 2>/dev/null || true
    source "$LIB_DIR/modules/core/logging.sh" 2>/dev/null || true
fi

# =============================================================================
# GLOBAL PERFORMANCE METRICS
# =============================================================================

# Performance tracking arrays
declare -gA PERF_METRICS
declare -gA PERF_TIMERS
declare -gA PERF_COUNTERS
declare -gA PERF_AVERAGES
declare -gA PERF_THRESHOLDS

# Default thresholds (in seconds)
declare -g PERF_SLOW_OPERATION_THRESHOLD=30
declare -g PERF_CRITICAL_OPERATION_THRESHOLD=300

# =============================================================================
# TIMER OPERATIONS
# =============================================================================

# Start a performance timer
perf_timer_start() {
    local timer_name="$1"
    local description="${2:-}"
    
    local start_time=$(date +%s%N)  # nanoseconds for precision
    aa_set PERF_TIMERS "${timer_name}:start" "$start_time"
    aa_set PERF_TIMERS "${timer_name}:description" "$description"
    aa_set PERF_TIMERS "${timer_name}:status" "running"
    
    [[ -n "$description" ]] && log "Starting timer: $timer_name - $description"
}

# Stop a performance timer
perf_timer_stop() {
    local timer_name="$1"
    
    local start_time=$(aa_get PERF_TIMERS "${timer_name}:start" "")
    if [[ -z "$start_time" ]]; then
        warning "Timer not found: $timer_name"
        return 1
    fi
    
    local end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    local duration_s=$((duration_ms / 1000))
    
    aa_set PERF_TIMERS "${timer_name}:end" "$end_time"
    aa_set PERF_TIMERS "${timer_name}:duration_ms" "$duration_ms"
    aa_set PERF_TIMERS "${timer_name}:duration_s" "$duration_s"
    aa_set PERF_TIMERS "${timer_name}:status" "completed"
    
    # Update metrics
    update_timer_metrics "$timer_name" "$duration_ms"
    
    # Check thresholds
    check_performance_threshold "$timer_name" "$duration_s"
    
    log "Timer stopped: $timer_name - ${duration_ms}ms (${duration_s}s)"
    return 0
}

# Get timer duration
perf_timer_get() {
    local timer_name="$1"
    local unit="${2:-ms}"  # ms, s, or ns
    
    local duration_ms=$(aa_get PERF_TIMERS "${timer_name}:duration_ms" "")
    if [[ -z "$duration_ms" ]]; then
        echo "0"
        return 1
    fi
    
    case "$unit" in
        ms) echo "$duration_ms" ;;
        s) echo "$((duration_ms / 1000))" ;;
        ns) echo "$((duration_ms * 1000000))" ;;
        *) echo "$duration_ms" ;;
    esac
}

# =============================================================================
# COUNTER OPERATIONS
# =============================================================================

# Increment a performance counter
perf_counter_inc() {
    local counter_name="$1"
    local increment="${2:-1}"
    
    local current=$(aa_get PERF_COUNTERS "$counter_name" "0")
    local new_value=$((current + increment))
    aa_set PERF_COUNTERS "$counter_name" "$new_value"
    
    return 0
}

# Get counter value
perf_counter_get() {
    local counter_name="$1"
    aa_get PERF_COUNTERS "$counter_name" "0"
}

# Reset counter
perf_counter_reset() {
    local counter_name="$1"
    aa_set PERF_COUNTERS "$counter_name" "0"
}

# =============================================================================
# METRIC OPERATIONS
# =============================================================================

# Record a metric value
perf_metric_record() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-}"
    
    local timestamp=$(date +%s)
    local key="${metric_name}:${timestamp}"
    
    aa_set PERF_METRICS "$key" "$value"
    aa_set PERF_METRICS "${key}:unit" "$unit"
    
    # Update running statistics
    update_metric_stats "$metric_name" "$value"
}

# Update timer metrics
update_timer_metrics() {
    local timer_name="$1"
    local duration_ms="$2"
    
    # Update counter
    perf_counter_inc "${timer_name}:count"
    
    # Update total time
    local total_ms=$(aa_get PERF_METRICS "${timer_name}:total_ms" "0")
    total_ms=$((total_ms + duration_ms))
    aa_set PERF_METRICS "${timer_name}:total_ms" "$total_ms"
    
    # Update min/max
    local min_ms=$(aa_get PERF_METRICS "${timer_name}:min_ms" "")
    local max_ms=$(aa_get PERF_METRICS "${timer_name}:max_ms" "0")
    
    if [[ -z "$min_ms" ]] || [[ $duration_ms -lt $min_ms ]]; then
        aa_set PERF_METRICS "${timer_name}:min_ms" "$duration_ms"
    fi
    
    if [[ $duration_ms -gt $max_ms ]]; then
        aa_set PERF_METRICS "${timer_name}:max_ms" "$duration_ms"
    fi
    
    # Update average
    local count=$(perf_counter_get "${timer_name}:count")
    if [[ $count -gt 0 ]]; then
        local avg_ms=$((total_ms / count))
        aa_set PERF_METRICS "${timer_name}:avg_ms" "$avg_ms"
    fi
}

# Update metric statistics
update_metric_stats() {
    local metric_name="$1"
    local value="$2"
    
    # Update counter
    perf_counter_inc "${metric_name}:samples"
    
    # Update sum
    local sum=$(aa_get PERF_METRICS "${metric_name}:sum" "0")
    sum=$(echo "$sum + $value" | bc -l 2>/dev/null || echo "$((sum + value))")
    aa_set PERF_METRICS "${metric_name}:sum" "$sum"
    
    # Update min/max
    local min=$(aa_get PERF_METRICS "${metric_name}:min" "")
    local max=$(aa_get PERF_METRICS "${metric_name}:max" "")
    
    if [[ -z "$min" ]] || (( $(echo "$value < $min" | bc -l 2>/dev/null || echo 0) )); then
        aa_set PERF_METRICS "${metric_name}:min" "$value"
    fi
    
    if [[ -z "$max" ]] || (( $(echo "$value > $max" | bc -l 2>/dev/null || echo 0) )); then
        aa_set PERF_METRICS "${metric_name}:max" "$value"
    fi
    
    # Update average
    local samples=$(perf_counter_get "${metric_name}:samples")
    if [[ $samples -gt 0 ]]; then
        local avg=$(echo "scale=2; $sum / $samples" | bc -l 2>/dev/null || echo "0")
        aa_set PERF_METRICS "${metric_name}:avg" "$avg"
    fi
}

# =============================================================================
# THRESHOLD MONITORING
# =============================================================================

# Set performance threshold
perf_set_threshold() {
    local operation="$1"
    local threshold_seconds="$2"
    local action="${3:-warn}"  # warn, error, or custom function
    
    aa_set PERF_THRESHOLDS "${operation}:threshold" "$threshold_seconds"
    aa_set PERF_THRESHOLDS "${operation}:action" "$action"
}

# Check performance threshold
check_performance_threshold() {
    local operation="$1"
    local duration_s="$2"
    
    local threshold=$(aa_get PERF_THRESHOLDS "${operation}:threshold" "$PERF_SLOW_OPERATION_THRESHOLD")
    local action=$(aa_get PERF_THRESHOLDS "${operation}:action" "warn")
    
    if [[ $duration_s -gt $threshold ]]; then
        case "$action" in
            warn)
                warning "Operation '$operation' took ${duration_s}s (threshold: ${threshold}s)"
                ;;
            error)
                error "Operation '$operation' exceeded threshold: ${duration_s}s > ${threshold}s"
                ;;
            *)
                # Custom action function
                if command -v "$action" >/dev/null 2>&1; then
                    "$action" "$operation" "$duration_s" "$threshold"
                fi
                ;;
        esac
    fi
}

# =============================================================================
# AWS OPERATION TRACKING
# =============================================================================

# Track AWS API call performance
track_aws_api_call() {
    local service="$1"
    local operation="$2"
    local start_time="$3"
    local end_time="${4:-$(date +%s%N)}"
    
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    # Record metric
    perf_metric_record "aws_api:${service}:${operation}" "$duration_ms" "ms"
    
    # Increment counter
    perf_counter_inc "aws_api_calls"
    perf_counter_inc "aws_api:${service}:calls"
    
    # Track slow calls
    if [[ $duration_ms -gt 5000 ]]; then
        perf_counter_inc "aws_api_slow_calls"
        log "Slow AWS API call: ${service}:${operation} took ${duration_ms}ms"
    fi
}

# Track deployment phase
track_deployment_phase() {
    local phase="$1"
    local action="$2"  # start or stop
    
    case "$action" in
        start)
            perf_timer_start "deployment:${phase}" "Deployment phase: $phase"
            ;;
        stop)
            perf_timer_stop "deployment:${phase}"
            ;;
    esac
}

# =============================================================================
# REPORTING
# =============================================================================

# Generate performance report
perf_generate_report() {
    local report_type="${1:-summary}"  # summary, detailed, or json
    
    case "$report_type" in
        summary)
            generate_summary_report
            ;;
        detailed)
            generate_detailed_report
            ;;
        json)
            generate_json_report
            ;;
        *)
            generate_summary_report
            ;;
    esac
}

# Generate summary report
generate_summary_report() {
    echo "=== Performance Summary Report ==="
    echo "Generated: $(date)"
    echo ""
    
    # Timer statistics
    echo "Operation Timings:"
    echo "-----------------"
    for timer in $(aa_keys PERF_TIMERS | grep -E '^[^:]+:start$' | sed 's/:start$//' | sort -u); do
        local count=$(perf_counter_get "${timer}:count")
        if [[ $count -gt 0 ]]; then
            local avg_ms=$(aa_get PERF_METRICS "${timer}:avg_ms" "0")
            local min_ms=$(aa_get PERF_METRICS "${timer}:min_ms" "0")
            local max_ms=$(aa_get PERF_METRICS "${timer}:max_ms" "0")
            local total_ms=$(aa_get PERF_METRICS "${timer}:total_ms" "0")
            
            printf "%-40s: count=%d, avg=%dms, min=%dms, max=%dms, total=%ds\n" \
                "$timer" "$count" "$avg_ms" "$min_ms" "$max_ms" "$((total_ms / 1000))"
        fi
    done
    echo ""
    
    # AWS API statistics
    local total_api_calls=$(perf_counter_get "aws_api_calls")
    if [[ $total_api_calls -gt 0 ]]; then
        echo "AWS API Performance:"
        echo "-------------------"
        echo "Total API Calls: $total_api_calls"
        echo "Slow API Calls: $(perf_counter_get "aws_api_slow_calls")"
        
        # Per-service breakdown
        for service in $(aa_keys PERF_COUNTERS | grep -E '^aws_api:[^:]+:calls$' | sed 's/^aws_api://;s/:calls$//' | sort -u); do
            local service_calls=$(perf_counter_get "aws_api:${service}:calls")
            printf "  %-20s: %d calls\n" "$service" "$service_calls"
        done
        echo ""
    fi
    
    # General counters
    echo "Performance Counters:"
    echo "--------------------"
    for counter in $(aa_keys PERF_COUNTERS | grep -v ':' | sort); do
        local value=$(perf_counter_get "$counter")
        if [[ $value -gt 0 ]]; then
            printf "%-30s: %d\n" "$counter" "$value"
        fi
    done
}

# Generate detailed report
generate_detailed_report() {
    generate_summary_report
    echo ""
    echo "=== Detailed Performance Data ==="
    echo ""
    
    # All timers with full details
    echo "Timer Details:"
    echo "--------------"
    for timer in $(aa_keys PERF_TIMERS | grep -E '^[^:]+:start$' | sed 's/:start$//' | sort -u); do
        local description=$(aa_get PERF_TIMERS "${timer}:description" "")
        local status=$(aa_get PERF_TIMERS "${timer}:status" "")
        local duration_s=$(aa_get PERF_TIMERS "${timer}:duration_s" "0")
        
        echo "Timer: $timer"
        [[ -n "$description" ]] && echo "  Description: $description"
        echo "  Status: $status"
        if [[ "$status" == "completed" ]]; then
            echo "  Duration: ${duration_s}s"
        fi
        echo ""
    done
    
    # Metric samples
    echo "Metric Samples:"
    echo "---------------"
    for metric in $(aa_keys PERF_METRICS | grep -E '^[^:]+:samples$' | sed 's/:samples$//' | sort -u); do
        local samples=$(perf_counter_get "${metric}:samples")
        local avg=$(aa_get PERF_METRICS "${metric}:avg" "0")
        local min=$(aa_get PERF_METRICS "${metric}:min" "0")
        local max=$(aa_get PERF_METRICS "${metric}:max" "0")
        
        echo "Metric: $metric"
        echo "  Samples: $samples"
        echo "  Average: $avg"
        echo "  Min: $min"
        echo "  Max: $max"
        echo ""
    done
}

# Generate JSON report
generate_json_report() {
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"timers\": {"
    
    local first=true
    for timer in $(aa_keys PERF_TIMERS | grep -E '^[^:]+:start$' | sed 's/:start$//' | sort -u); do
        [[ "$first" != "true" ]] && echo ","
        first=false
        
        local count=$(perf_counter_get "${timer}:count")
        local avg_ms=$(aa_get PERF_METRICS "${timer}:avg_ms" "0")
        local min_ms=$(aa_get PERF_METRICS "${timer}:min_ms" "0")
        local max_ms=$(aa_get PERF_METRICS "${timer}:max_ms" "0")
        local total_ms=$(aa_get PERF_METRICS "${timer}:total_ms" "0")
        
        echo -n "    \"$timer\": {"
        echo -n "\"count\": $count, "
        echo -n "\"avg_ms\": $avg_ms, "
        echo -n "\"min_ms\": $min_ms, "
        echo -n "\"max_ms\": $max_ms, "
        echo -n "\"total_ms\": $total_ms"
        echo -n "}"
    done
    
    echo ""
    echo "  },"
    echo "  \"counters\": {"
    
    first=true
    for counter in $(aa_keys PERF_COUNTERS | sort); do
        [[ "$first" != "true" ]] && echo ","
        first=false
        
        local value=$(perf_counter_get "$counter")
        echo -n "    \"$counter\": $value"
    done
    
    echo ""
    echo "  }"
    echo "}"
}

# =============================================================================
# OPTIMIZATION RECOMMENDATIONS
# =============================================================================

# Analyze performance and provide recommendations
perf_analyze() {
    local recommendations=()
    
    # Check for slow operations
    for timer in $(aa_keys PERF_TIMERS | grep -E '^[^:]+:start$' | sed 's/:start$//' | sort -u); do
        local avg_ms=$(aa_get PERF_METRICS "${timer}:avg_ms" "0")
        if [[ $avg_ms -gt 30000 ]]; then
            recommendations+=("Operation '$timer' is slow (avg: ${avg_ms}ms). Consider optimization.")
        fi
    done
    
    # Check AWS API call volume
    local total_api_calls=$(perf_counter_get "aws_api_calls")
    if [[ $total_api_calls -gt 1000 ]]; then
        recommendations+=("High AWS API call volume ($total_api_calls). Consider implementing caching.")
    fi
    
    # Check for slow API calls
    local slow_calls=$(perf_counter_get "aws_api_slow_calls")
    if [[ $slow_calls -gt 10 ]]; then
        recommendations+=("Multiple slow AWS API calls detected ($slow_calls). Check network and AWS service health.")
    fi
    
    # Display recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo "=== Performance Optimization Recommendations ==="
        for rec in "${recommendations[@]}"; do
            echo "• $rec"
        done
    else
        echo "Performance is within acceptable parameters."
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

# Clear all performance data
perf_clear() {
    aa_clear PERF_METRICS
    aa_clear PERF_TIMERS
    aa_clear PERF_COUNTERS
    aa_clear PERF_AVERAGES
    aa_clear PERF_THRESHOLDS
    
    log "Performance data cleared"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize performance monitoring
init_performance_monitor() {
    # Set default thresholds
    perf_set_threshold "deployment" 300 "warn"
    perf_set_threshold "aws_api_call" 10 "warn"
    perf_set_threshold "spot_price_check" 30 "warn"
    
    # Initialize counters
    perf_counter_reset "aws_api_calls"
    perf_counter_reset "aws_api_slow_calls"
}

# Auto-initialize if sourced
init_performance_monitor