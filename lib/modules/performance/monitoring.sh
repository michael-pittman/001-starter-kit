#!/bin/bash
# performance/monitoring.sh - Performance monitoring and baseline measurement framework

# Performance baseline targets
declare -g PERF_TARGET_STARTUP_TIME=2      # seconds
declare -g PERF_TARGET_DEPLOYMENT_TIME=180 # seconds (3 minutes)
declare -g PERF_TARGET_MEMORY_PEAK=100     # MB
declare -g PERF_TARGET_API_REDUCTION=50    # percent reduction

# Performance metrics storage
declare -g PERF_METRICS_DIR="${PERF_METRICS_DIR:-/tmp/geuse-performance}"
declare -g PERF_METRICS_FILE="${PERF_METRICS_DIR}/metrics.json"
declare -g PERF_BASELINE_FILE="${PERF_METRICS_DIR}/baseline.json"

# Performance timing variables
declare -g PERF_START_TIME
declare -g PERF_PHASE_START
declare -g -A PERF_PHASE_TIMES
declare -g -A PERF_API_CALLS
declare -g -A PERF_MEMORY_USAGE

# Initialize performance monitoring
perf_init() {
    local context="${1:-default}"
    
    # Create metrics directory
    mkdir -p "$PERF_METRICS_DIR"
    
    # Initialize start time
    PERF_START_TIME=$(date +%s.%N)
    
    # Initialize metrics file
    cat > "$PERF_METRICS_FILE" <<EOF
{
    "context": "$context",
    "start_time": "$PERF_START_TIME",
    "pid": $$,
    "phases": {},
    "api_calls": {},
    "memory": {},
    "system": {
        "cpu_cores": $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1),
        "total_memory": $(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "unknown"),
        "os": "$(uname -s)",
        "arch": "$(uname -m)"
    }
}
EOF
    
    # Start memory monitoring in background
    perf_monitor_memory &
    local monitor_pid=$!
    echo "$monitor_pid" > "${PERF_METRICS_DIR}/monitor.pid"
}

# Start timing a phase
perf_start_phase() {
    local phase_name="$1"
    PERF_PHASE_START=$(date +%s.%N)
    PERF_PHASE_TIMES["${phase_name}_start"]=$PERF_PHASE_START
}

# End timing a phase
perf_end_phase() {
    local phase_name="$1"
    local end_time=$(date +%s.%N)
    local start_time=${PERF_PHASE_TIMES["${phase_name}_start"]}
    
    if [[ -n "$start_time" ]]; then
        local duration=$(echo "$end_time - $start_time" | bc -l)
        PERF_PHASE_TIMES["${phase_name}_duration"]=$duration
        
        # Update metrics file
        perf_update_metrics "phases.$phase_name" "$duration"
    fi
}

# Record an API call
perf_record_api_call() {
    local api_type="$1"
    local service="${2:-aws}"
    local duration="${3:-0}"
    
    # Increment call count
    local key="${service}_${api_type}"
    local current_count=${PERF_API_CALLS[$key]:-0}
    PERF_API_CALLS[$key]=$((current_count + 1))
    
    # Update metrics
    perf_update_metrics "api_calls.$key.count" "${PERF_API_CALLS[$key]}"
    if [[ "$duration" != "0" ]]; then
        perf_update_metrics "api_calls.$key.total_duration" "$duration"
    fi
}

# Monitor memory usage (runs in background)
perf_monitor_memory() {
    local interval=1
    local peak_memory=0
    
    while true; do
        # Get current memory usage
        local current_memory
        if [[ "$(uname -s)" == "Darwin" ]]; then
            # macOS
            current_memory=$(ps -o rss= -p $$ 2>/dev/null | awk '{print int($1/1024)}')
        else
            # Linux
            current_memory=$(ps -o rss= -p $$ 2>/dev/null | awk '{print int($1/1024)}')
        fi
        
        if [[ -n "$current_memory" ]] && [[ "$current_memory" -gt "$peak_memory" ]]; then
            peak_memory=$current_memory
            echo "$peak_memory" > "${PERF_METRICS_DIR}/peak_memory"
        fi
        
        sleep $interval
    done
}

# Update metrics file
perf_update_metrics() {
    local key="$1"
    local value="$2"
    
    if [[ -f "$PERF_METRICS_FILE" ]]; then
        # Use jq if available, otherwise use simple replacement
        if command -v jq >/dev/null 2>&1; then
            local tmp_file="${PERF_METRICS_FILE}.tmp"
            jq ".${key} = ${value}" "$PERF_METRICS_FILE" > "$tmp_file" && mv "$tmp_file" "$PERF_METRICS_FILE"
        fi
    fi
}

# Finalize performance monitoring
perf_finalize() {
    local end_time=$(date +%s.%N)
    local total_duration=$(echo "$end_time - $PERF_START_TIME" | bc -l)
    
    # Stop memory monitor
    if [[ -f "${PERF_METRICS_DIR}/monitor.pid" ]]; then
        local monitor_pid=$(cat "${PERF_METRICS_DIR}/monitor.pid")
        kill "$monitor_pid" 2>/dev/null || true
        rm -f "${PERF_METRICS_DIR}/monitor.pid"
    fi
    
    # Get peak memory
    local peak_memory=0
    if [[ -f "${PERF_METRICS_DIR}/peak_memory" ]]; then
        peak_memory=$(cat "${PERF_METRICS_DIR}/peak_memory")
    fi
    
    # Update final metrics
    perf_update_metrics "total_duration" "$total_duration"
    perf_update_metrics "memory.peak_mb" "$peak_memory"
    
    # Generate performance report
    perf_generate_report
}

# Generate performance report
perf_generate_report() {
    local report_file="${PERF_METRICS_DIR}/performance_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== GeuseMaker Performance Report ==="
        echo "Generated: $(date)"
        echo ""
        
        # Overall metrics
        echo "Overall Performance:"
        local total_duration=${PERF_PHASE_TIMES["total_duration"]:-0}
        echo "  Total Duration: ${total_duration}s"
        
        # Phase breakdown
        echo ""
        echo "Phase Breakdown:"
        for phase in "${!PERF_PHASE_TIMES[@]}"; do
            if [[ "$phase" == *"_duration" ]]; then
                local phase_name=${phase%_duration}
                local duration=${PERF_PHASE_TIMES[$phase]}
                printf "  %-30s: %8.3fs\n" "$phase_name" "$duration"
            fi
        done
        
        # API call statistics
        echo ""
        echo "API Call Statistics:"
        for api_key in "${!PERF_API_CALLS[@]}"; do
            local count=${PERF_API_CALLS[$api_key]}
            printf "  %-30s: %8d calls\n" "$api_key" "$count"
        done
        
        # Memory usage
        echo ""
        echo "Memory Usage:"
        local peak_memory=$(cat "${PERF_METRICS_DIR}/peak_memory" 2>/dev/null || echo 0)
        echo "  Peak Memory: ${peak_memory}MB"
        
        # Performance targets
        echo ""
        echo "Performance Target Comparison:"
        perf_check_targets
        
    } > "$report_file"
    
    echo "$report_file"
}

# Check performance against targets
perf_check_targets() {
    local startup_time=${PERF_PHASE_TIMES["startup_duration"]:-999}
    local deployment_time=${PERF_PHASE_TIMES["deployment_duration"]:-999}
    local peak_memory=$(cat "${PERF_METRICS_DIR}/peak_memory" 2>/dev/null || echo 999)
    
    # Startup time check
    if (( $(echo "$startup_time < $PERF_TARGET_STARTUP_TIME" | bc -l) )); then
        echo "  ✓ Startup Time: ${startup_time}s (target: <${PERF_TARGET_STARTUP_TIME}s)"
    else
        echo "  ✗ Startup Time: ${startup_time}s (target: <${PERF_TARGET_STARTUP_TIME}s)"
    fi
    
    # Deployment time check
    if (( $(echo "$deployment_time < $PERF_TARGET_DEPLOYMENT_TIME" | bc -l) )); then
        echo "  ✓ Deployment Time: ${deployment_time}s (target: <${PERF_TARGET_DEPLOYMENT_TIME}s)"
    else
        echo "  ✗ Deployment Time: ${deployment_time}s (target: <${PERF_TARGET_DEPLOYMENT_TIME}s)"
    fi
    
    # Memory usage check
    if [[ "$peak_memory" -lt "$PERF_TARGET_MEMORY_PEAK" ]]; then
        echo "  ✓ Peak Memory: ${peak_memory}MB (target: <${PERF_TARGET_MEMORY_PEAK}MB)"
    else
        echo "  ✗ Peak Memory: ${peak_memory}MB (target: <${PERF_TARGET_MEMORY_PEAK}MB)"
    fi
}

# Save current metrics as baseline
perf_save_baseline() {
    if [[ -f "$PERF_METRICS_FILE" ]]; then
        cp "$PERF_METRICS_FILE" "$PERF_BASELINE_FILE"
        echo "Performance baseline saved to: $PERF_BASELINE_FILE"
    fi
}

# Compare current performance to baseline
perf_compare_baseline() {
    if [[ ! -f "$PERF_BASELINE_FILE" ]]; then
        echo "No baseline found. Run with --save-baseline first."
        return 1
    fi
    
    echo "=== Performance Comparison ==="
    echo "Comparing current run to baseline..."
    
    # This would use jq to compare JSON files if available
    if command -v jq >/dev/null 2>&1; then
        # Compare key metrics
        local baseline_duration=$(jq -r '.total_duration // 0' "$PERF_BASELINE_FILE")
        local current_duration=$(jq -r '.total_duration // 0' "$PERF_METRICS_FILE")
        local improvement=$(echo "scale=2; (($baseline_duration - $current_duration) / $baseline_duration) * 100" | bc -l)
        
        echo "Total Duration:"
        echo "  Baseline: ${baseline_duration}s"
        echo "  Current:  ${current_duration}s"
        echo "  Change:   ${improvement}% improvement"
    fi
}

# Performance profiling helpers
perf_profile_function() {
    local func_name="$1"
    shift
    
    local start_time=$(date +%s.%N)
    "$func_name" "$@"
    local result=$?
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc -l)
    PERF_PHASE_TIMES["func_${func_name}_duration"]=$duration
    
    return $result
}

# CloudWatch metrics integration
perf_send_to_cloudwatch() {
    local namespace="${1:-GeuseMaker/Performance}"
    local stack_name="${2:-default}"
    
    if [[ -f "$PERF_METRICS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        # Extract key metrics
        local total_duration=$(jq -r '.total_duration // 0' "$PERF_METRICS_FILE")
        local peak_memory=$(jq -r '.memory.peak_mb // 0' "$PERF_METRICS_FILE")
        
        # Send metrics to CloudWatch
        aws cloudwatch put-metric-data \
            --namespace "$namespace" \
            --metric-data \
                MetricName=DeploymentDuration,Value=$total_duration,Unit=Seconds,Dimensions=Stack=$stack_name \
                MetricName=PeakMemoryUsage,Value=$peak_memory,Unit=Megabytes,Dimensions=Stack=$stack_name \
            2>/dev/null || true
    fi
}