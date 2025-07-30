#!/bin/bash
# performance-optimization.sh - Main performance optimization script for GeuseMaker

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Load required libraries
load_library() {
    local library="$1"
    local library_path="${LIB_DIR}/${library}"
    [ ! -f "$library_path" ] && { echo "ERROR: Required library not found: $library_path" >&2; exit 1; }
    source "$library_path" || { echo "ERROR: Failed to source library: $library_path" >&2; exit 1; }
}

# Core libraries
load_library "modules/core/logging.sh"
load_library "modules/performance/monitoring.sh"
load_library "modules/performance/optimization.sh"
load_library "modules/performance/caching.sh"
load_library "modules/performance/parallel.sh"

# Script variables
declare -g OPTIMIZATION_MODE="${1:-analyze}"
declare -g STACK_NAME="${2:-}"
declare -g OPTIMIZATION_LEVEL="${3:-standard}"
declare -g REPORT_FORMAT="${4:-text}"

# Usage function
usage() {
    cat << EOF
Usage: $0 <mode> [stack_name] [optimization_level] [report_format]

Modes:
  analyze     - Analyze current performance and generate report
  optimize    - Apply performance optimizations
  benchmark   - Run performance benchmarks
  monitor     - Real-time performance monitoring
  compare     - Compare performance to baseline
  
Parameters:
  stack_name        - Stack name for context (optional)
  optimization_level - minimal|standard|aggressive (default: standard)
  report_format     - text|json|html (default: text)

Examples:
  $0 analyze                         # Analyze current performance
  $0 optimize prod-stack aggressive  # Apply aggressive optimizations
  $0 benchmark dev-stack             # Run benchmarks on dev stack
  $0 monitor prod-stack              # Monitor prod stack performance
  $0 compare                         # Compare to baseline

Environment Variables:
  PERF_CACHE_SIZE    - Cache size in MB (default: 100)
  PERF_MAX_PARALLEL  - Max parallel jobs (default: 4)
  PERF_VERBOSE       - Enable verbose output (default: false)
EOF
    exit 1
}

# Initialize performance optimization
init_performance_optimization() {
    log_info "Initializing performance optimization system..."
    
    # Initialize subsystems
    perf_init "$STACK_NAME"
    cache_init "${PERF_CACHE_SIZE:-100}"
    parallel_init "${PERF_MAX_PARALLEL:-auto}"
    
    # Apply startup optimizations
    perf_optimize_startup
    
    log_success "Performance optimization initialized"
}

# Analyze current performance
analyze_performance() {
    log_info "Analyzing system performance..."
    
    perf_start_phase "analysis"
    
    # Analyze script loading performance
    analyze_script_loading
    
    # Analyze AWS API usage
    analyze_api_usage
    
    # Analyze memory usage
    analyze_memory_usage
    
    # Analyze cache effectiveness
    analyze_cache_effectiveness
    
    perf_end_phase "analysis"
    
    # Generate report
    generate_performance_report
}

# Analyze script loading performance
analyze_script_loading() {
    log_info "Analyzing script loading performance..."
    
    local start_time=$(date +%s.%N)
    
    # Simulate typical library loading
    local libraries=(
        "aws-deployment-common.sh"
        "error-handling.sh"
        "associative-arrays.sh"
        "aws-cli-v2.sh"
        "spot-instance.sh"
    )
    
    for lib in "${libraries[@]}"; do
        local lib_start=$(date +%s.%N)
        source "$LIB_DIR/$lib" 2>/dev/null || true
        local lib_end=$(date +%s.%N)
        local lib_duration=$(echo "$lib_end - $lib_start" | bc -l)
        
        log_debug "Library $lib loaded in ${lib_duration}s"
        perf_update_metrics "library_load.$lib" "$lib_duration"
    done
    
    local end_time=$(date +%s.%N)
    local total_duration=$(echo "$end_time - $start_time" | bc -l)
    
    log_info "Total library loading time: ${total_duration}s"
    perf_update_metrics "total_library_load_time" "$total_duration"
}

# Analyze AWS API usage
analyze_api_usage() {
    log_info "Analyzing AWS API usage patterns..."
    
    # Check for redundant API calls
    local api_patterns=(
        "ec2:describe-instances"
        "ec2:describe-spot-price-history"
        "ec2:describe-regions"
        "ec2:describe-availability-zones"
        "iam:get-role"
    )
    
    for pattern in "${api_patterns[@]}"; do
        local service="${pattern%%:*}"
        local action="${pattern#*:}"
        
        # Simulate API call tracking
        perf_record_api_call "$action" "$service"
    done
    
    # Analyze cache hit rates for API calls
    local cache_stats=$(cache_stats)
    log_info "Cache statistics: $cache_stats"
}

# Analyze memory usage
analyze_memory_usage() {
    log_info "Analyzing memory usage patterns..."
    
    # Get current memory usage
    local current_memory
    if [[ "$(uname -s)" == "Darwin" ]]; then
        current_memory=$(ps -o rss= -p $$ | awk '{print int($1/1024)}')
    else
        current_memory=$(ps -o rss= -p $$ | awk '{print int($1/1024)}')
    fi
    
    log_info "Current memory usage: ${current_memory}MB"
    
    # Check for memory leaks in associative arrays
    local array_sizes=(
        "SPOT_PRICES:${#SPOT_PRICES[@]}"
        "INSTANCE_CONFIGS:${#INSTANCE_CONFIGS[@]}"
        "DEPLOYMENT_STATE:${#DEPLOYMENT_STATE[@]}"
    )
    
    for array_info in "${array_sizes[@]}"; do
        local array_name="${array_info%%:*}"
        local array_size="${array_info#*:}"
        log_debug "Array $array_name size: $array_size"
    done
}

# Analyze cache effectiveness
analyze_cache_effectiveness() {
    log_info "Analyzing cache effectiveness..."
    
    # Test cache performance
    local test_key="perf_test_$(date +%s)"
    local test_value="This is a test value for performance analysis"
    
    # Test cache write performance
    local write_start=$(date +%s.%N)
    cache_set "$test_key" "$test_value" 60
    local write_end=$(date +%s.%N)
    local write_duration=$(echo "$write_end - $write_start" | bc -l)
    
    # Test cache read performance
    local read_start=$(date +%s.%N)
    cache_get "$test_key" >/dev/null
    local read_end=$(date +%s.%N)
    local read_duration=$(echo "$read_end - $read_start" | bc -l)
    
    log_info "Cache write time: ${write_duration}s"
    log_info "Cache read time: ${read_duration}s"
    
    # Clean up test entry
    cache_delete "$test_key"
}

# Apply performance optimizations
apply_optimizations() {
    log_info "Applying performance optimizations (level: $OPTIMIZATION_LEVEL)..."
    
    perf_start_phase "optimization"
    
    # Apply core optimizations
    perf_apply_all_optimizations "$OPTIMIZATION_LEVEL"
    
    # Optimize specific components
    case "$OPTIMIZATION_LEVEL" in
        "aggressive")
            optimize_aggressive
            ;;
        "standard")
            optimize_standard
            ;;
        "minimal")
            optimize_minimal
            ;;
    esac
    
    perf_end_phase "optimization"
    
    log_success "Optimizations applied successfully"
}

# Aggressive optimization mode
optimize_aggressive() {
    log_info "Applying aggressive optimizations..."
    
    # Enable all caching
    export CACHE_ENABLED=true
    export PERF_OPTIMIZE_MEMORY=true
    export PERF_OPTIMIZE_API_CALLS=true
    export PERF_OPTIMIZE_PARALLEL=true
    
    # Increase cache sizes
    export CACHE_MAX_SIZE=$((200 * 1024 * 1024))  # 200MB
    export L1_CACHE_MAX_ITEMS=500
    
    # Maximize parallelization
    export PARALLEL_MAX_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)
    
    # Enable API call batching
    export PERF_API_BATCH_SIZE=50
    
    # Pre-warm caches
    prewarm_caches
}

# Standard optimization mode
optimize_standard() {
    log_info "Applying standard optimizations..."
    
    # Enable essential caching
    export CACHE_ENABLED=true
    export PERF_OPTIMIZE_API_CALLS=true
    
    # Moderate cache sizes
    export CACHE_MAX_SIZE=$((100 * 1024 * 1024))  # 100MB
    export L1_CACHE_MAX_ITEMS=200
    
    # Balanced parallelization
    export PARALLEL_MAX_JOBS=4
    
    # Enable API call batching
    export PERF_API_BATCH_SIZE=20
}

# Minimal optimization mode
optimize_minimal() {
    log_info "Applying minimal optimizations..."
    
    # Enable basic optimizations only
    export CACHE_ENABLED=true
    
    # Small cache sizes
    export CACHE_MAX_SIZE=$((50 * 1024 * 1024))  # 50MB
    export L1_CACHE_MAX_ITEMS=50
    
    # Limited parallelization
    export PARALLEL_MAX_JOBS=2
}

# Pre-warm caches with common data
prewarm_caches() {
    log_info "Pre-warming caches..."
    
    # Cache common regions
    local regions=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1")
    
    # Pre-fetch spot prices in parallel
    parallel_get_spot_prices "g4dn.xlarge" "${regions[@]}"
    
    # Cache AMI information
    for region in "${regions[@]}"; do
        cache_ami_info "$region" "ami-latest"
    done
    
    log_success "Cache pre-warming complete"
}

# Run performance benchmarks
run_benchmarks() {
    log_info "Running performance benchmarks..."
    
    perf_start_phase "benchmark"
    
    # Benchmark 1: Script loading time
    benchmark_script_loading
    
    # Benchmark 2: AWS API call performance
    benchmark_api_calls
    
    # Benchmark 3: Parallel execution
    benchmark_parallel_execution
    
    # Benchmark 4: Cache performance
    benchmark_cache_performance
    
    perf_end_phase "benchmark"
    
    # Generate benchmark report
    generate_benchmark_report
}

# Benchmark script loading
benchmark_script_loading() {
    log_info "Benchmarking script loading performance..."
    
    local iterations=10
    local total_time=0
    
    for i in $(seq 1 $iterations); do
        local start=$(date +%s.%N)
        
        # Simulate script loading
        bash -c "source $LIB_DIR/aws-deployment-common.sh" 2>/dev/null
        
        local end=$(date +%s.%N)
        local duration=$(echo "$end - $start" | bc -l)
        total_time=$(echo "$total_time + $duration" | bc -l)
    done
    
    local avg_time=$(echo "scale=4; $total_time / $iterations" | bc -l)
    log_info "Average script loading time: ${avg_time}s"
    
    perf_update_metrics "benchmark.script_loading_avg" "$avg_time"
}

# Benchmark API calls
benchmark_api_calls() {
    log_info "Benchmarking AWS API call performance..."
    
    # Test with and without caching
    local regions=("us-east-1" "us-west-2")
    
    # Without cache
    cache_invalidate_pattern "spot_prices"
    local start=$(date +%s.%N)
    for region in "${regions[@]}"; do
        aws ec2 describe-spot-price-history \
            --region "$region" \
            --instance-types "g4dn.xlarge" \
            --max-results 1 \
            2>/dev/null || true
    done
    local end=$(date +%s.%N)
    local no_cache_time=$(echo "$end - $start" | bc -l)
    
    # With cache
    start=$(date +%s.%N)
    for region in "${regions[@]}"; do
        cache_spot_prices "$region" "g4dn.xlarge"
    done
    end=$(date +%s.%N)
    local with_cache_time=$(echo "$end - $start" | bc -l)
    
    log_info "API calls without cache: ${no_cache_time}s"
    log_info "API calls with cache: ${with_cache_time}s"
    
    local improvement=$(echo "scale=2; (($no_cache_time - $with_cache_time) / $no_cache_time) * 100" | bc -l)
    log_info "Cache improvement: ${improvement}%"
}

# Benchmark parallel execution
benchmark_parallel_execution() {
    log_info "Benchmarking parallel execution..."
    
    # Test function for benchmarking
    test_operation() {
        sleep 0.5
        echo "Operation $1 completed"
    }
    
    # Sequential execution
    local start=$(date +%s.%N)
    for i in {1..8}; do
        test_operation "$i" >/dev/null
    done
    local end=$(date +%s.%N)
    local sequential_time=$(echo "$end - $start" | bc -l)
    
    # Parallel execution
    local commands=()
    for i in {1..8}; do
        commands+=("test_operation $i")
    done
    
    start=$(date +%s.%N)
    parallel_execute "${commands[@]}" >/dev/null
    end=$(date +%s.%N)
    local parallel_time=$(echo "$end - $start" | bc -l)
    
    log_info "Sequential execution: ${sequential_time}s"
    log_info "Parallel execution: ${parallel_time}s"
    
    local speedup=$(echo "scale=2; $sequential_time / $parallel_time" | bc -l)
    log_info "Speedup: ${speedup}x"
}

# Benchmark cache performance
benchmark_cache_performance() {
    log_info "Benchmarking cache performance..."
    
    local iterations=1000
    local key_prefix="bench_"
    
    # Write benchmark
    local start=$(date +%s.%N)
    for i in $(seq 1 $iterations); do
        cache_set "${key_prefix}${i}" "value_$i" 300
    done
    local end=$(date +%s.%N)
    local write_time=$(echo "$end - $start" | bc -l)
    
    # Read benchmark
    start=$(date +%s.%N)
    for i in $(seq 1 $iterations); do
        cache_get "${key_prefix}${i}" >/dev/null
    done
    end=$(date +%s.%N)
    local read_time=$(echo "$end - $start" | bc -l)
    
    log_info "Cache writes: $iterations in ${write_time}s"
    log_info "Cache reads: $iterations in ${read_time}s"
    
    local write_rate=$(echo "scale=2; $iterations / $write_time" | bc -l)
    local read_rate=$(echo "scale=2; $iterations / $read_time" | bc -l)
    
    log_info "Write rate: ${write_rate} ops/sec"
    log_info "Read rate: ${read_rate} ops/sec"
    
    # Cleanup
    for i in $(seq 1 $iterations); do
        cache_delete "${key_prefix}${i}"
    done
}

# Monitor real-time performance
monitor_performance() {
    log_info "Starting real-time performance monitoring..."
    
    # Initialize monitoring
    perf_init "$STACK_NAME"
    
    # Monitoring loop
    while true; do
        clear
        echo "=== GeuseMaker Performance Monitor ==="
        echo "Stack: ${STACK_NAME:-default}"
        echo "Time: $(date)"
        echo ""
        
        # Display current metrics
        display_current_metrics
        
        # Display cache statistics
        echo ""
        cache_stats
        
        # Display parallel execution stats
        echo ""
        parallel_stats
        
        # Update CloudWatch metrics if stack specified
        if [[ -n "$STACK_NAME" ]]; then
            perf_send_to_cloudwatch "GeuseMaker/Performance" "$STACK_NAME"
        fi
        
        # Sleep before next update
        sleep 5
    done
}

# Display current metrics
display_current_metrics() {
    echo "Current Performance Metrics:"
    
    # Memory usage
    local current_memory
    if [[ "$(uname -s)" == "Darwin" ]]; then
        current_memory=$(ps -o rss= -p $$ | awk '{print int($1/1024)}')
    else
        current_memory=$(ps -o rss= -p $$ | awk '{print int($1/1024)}')
    fi
    echo "  Memory Usage: ${current_memory}MB"
    
    # CPU usage
    local cpu_usage=$(ps -o %cpu= -p $$ | tr -d ' ')
    echo "  CPU Usage: ${cpu_usage}%"
    
    # Active processes
    local active_procs=$(jobs -r | wc -l)
    echo "  Active Background Jobs: $active_procs"
}

# Generate performance report
generate_performance_report() {
    local report_file="${PERF_METRICS_DIR}/performance_report_$(date +%Y%m%d_%H%M%S).${REPORT_FORMAT}"
    
    case "$REPORT_FORMAT" in
        "json")
            cp "$PERF_METRICS_FILE" "$report_file"
            ;;
        "html")
            generate_html_report "$report_file"
            ;;
        "text"|*)
            local text_report=$(perf_generate_report)
            cp "$text_report" "$report_file"
            ;;
    esac
    
    log_success "Performance report generated: $report_file"
    
    # Display summary
    echo ""
    echo "=== Performance Summary ==="
    perf_check_targets
}

# Generate HTML report
generate_html_report() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>GeuseMaker Performance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .metric { margin: 10px 0; padding: 10px; background: #f0f0f0; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>GeuseMaker Performance Report</h1>
    <div class="metric">
        <h2>Performance Metrics</h2>
        <div id="metrics"></div>
    </div>
    <script>
        // Load metrics from JSON
        fetch('metrics.json')
            .then(response => response.json())
            .then(data => {
                document.getElementById('metrics').innerHTML = JSON.stringify(data, null, 2);
            });
    </script>
</body>
</html>
EOF
}

# Generate benchmark report
generate_benchmark_report() {
    log_info "Generating benchmark report..."
    
    local report_file="${PERF_METRICS_DIR}/benchmark_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== GeuseMaker Benchmark Report ==="
        echo "Generated: $(date)"
        echo ""
        echo "System Information:"
        echo "  OS: $(uname -s)"
        echo "  Architecture: $(uname -m)"
        echo "  CPU Cores: $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 'unknown')"
        echo ""
        echo "Benchmark Results:"
        
        # Include metrics from performance monitoring
        if [[ -f "$PERF_METRICS_FILE" ]] && command -v jq >/dev/null 2>&1; then
            jq -r '.benchmark | to_entries[] | "  \(.key): \(.value)"' "$PERF_METRICS_FILE" 2>/dev/null || true
        fi
    } > "$report_file"
    
    log_success "Benchmark report generated: $report_file"
}

# Compare to baseline
compare_to_baseline() {
    log_info "Comparing performance to baseline..."
    
    # Run current analysis
    analyze_performance
    
    # Compare to baseline
    perf_compare_baseline
    
    # Generate comparison report
    local report_file="${PERF_METRICS_DIR}/comparison_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== Performance Comparison Report ==="
        echo "Generated: $(date)"
        echo ""
        
        perf_compare_baseline
    } > "$report_file"
    
    log_success "Comparison report generated: $report_file"
}

# Main execution
main() {
    # Validate mode
    case "$OPTIMIZATION_MODE" in
        "analyze"|"optimize"|"benchmark"|"monitor"|"compare")
            ;;
        *)
            usage
            ;;
    esac
    
    # Initialize
    init_performance_optimization
    
    # Execute based on mode
    case "$OPTIMIZATION_MODE" in
        "analyze")
            analyze_performance
            ;;
        "optimize")
            apply_optimizations
            ;;
        "benchmark")
            run_benchmarks
            ;;
        "monitor")
            monitor_performance
            ;;
        "compare")
            compare_to_baseline
            ;;
    esac
    
    # Finalize and generate reports
    perf_finalize
}

# Export functions for testing
export -f test_operation

# Run main function
main "$@"