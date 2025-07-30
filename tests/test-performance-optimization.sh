#!/bin/bash
# test-performance-optimization.sh - Tests for performance optimization implementation

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_NAME="test-performance-optimization"

# Load test framework
source "$SCRIPT_DIR/lib/shell-test-framework.sh"

# Load performance modules
source "$PROJECT_ROOT/lib/modules/performance/monitoring.sh"
source "$PROJECT_ROOT/lib/modules/performance/optimization.sh"
source "$PROJECT_ROOT/lib/modules/performance/caching.sh"
source "$PROJECT_ROOT/lib/modules/performance/parallel.sh"

# Test suite setup
setup_suite() {
    log_info "Setting up performance optimization test suite"
    
    # Create test directory
    TEST_TMP_DIR=$(mktemp -d "/tmp/${TEST_NAME}.XXXXXX")
    export PERF_METRICS_DIR="$TEST_TMP_DIR/metrics"
    export CACHE_DIR="$TEST_TMP_DIR/cache"
    export PARALLEL_VERBOSE=false
    
    # Initialize subsystems
    perf_init "test"
    cache_init 10  # 10MB cache for testing
    parallel_init 2  # Limited parallelism for testing
}

# Test suite teardown
teardown_suite() {
    log_info "Cleaning up performance optimization test suite"
    
    # Cleanup
    rm -rf "$TEST_TMP_DIR" 2>/dev/null || true
    
    # Kill any remaining background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Test performance monitoring
test_performance_monitoring() {
    start_test "Performance Monitoring"
    
    # Test initialization
    perf_init "monitoring_test"
    assert_file_exists "$PERF_METRICS_FILE" "Metrics file should be created"
    
    # Test phase timing
    perf_start_phase "test_phase"
    sleep 0.1
    perf_end_phase "test_phase"
    
    local duration=${PERF_PHASE_TIMES["test_phase_duration"]:-0}
    assert_true "[ \$(echo \"$duration > 0\" | bc -l) -eq 1 ]" "Phase duration should be recorded"
    
    # Test API call recording
    perf_record_api_call "describe-instances" "ec2" "0.5"
    assert_equals "${PERF_API_CALLS[ec2_describe-instances]}" "1" "API call should be recorded"
    
    # Test memory monitoring
    sleep 2  # Let memory monitor run
    assert_file_exists "${PERF_METRICS_DIR}/peak_memory" "Peak memory file should exist"
    
    # Test finalization
    perf_finalize
    local report_files=$(ls "$PERF_METRICS_DIR"/performance_report_*.txt 2>/dev/null | wc -l)
    assert_true "[ $report_files -gt 0 ]" "Performance report should be generated"
    
    pass_test
}

# Test optimization functions
test_optimization_functions() {
    start_test "Optimization Functions"
    
    # Test startup optimization
    perf_optimize_startup
    assert_equals "${PERF_ENV_CACHE[has_aws_cli]}" "true" "AWS CLI check should be cached"
    
    # Test module loading optimization
    perf_optimize_module_loading "$PROJECT_ROOT/lib/error-handling.sh"
    assert_equals "${PERF_LAZY_LOADED_MODULES[error-handling]}" "available" "Module should be marked as available"
    
    # Test cached API call
    local result1=$(perf_cached_api_call "test_key" echo "test_value")
    local result2=$(perf_cached_api_call "test_key" echo "different_value")
    assert_equals "$result1" "$result2" "Cached result should be returned"
    
    # Test memory optimization
    perf_optimize_memory
    
    # Test file operation optimization
    perf_optimize_file_ops
    perf_buffered_write "$TEST_TMP_DIR/test_file" "test content"
    perf_flush_file_buffer "$TEST_TMP_DIR/test_file"
    assert_file_contains "$TEST_TMP_DIR/test_file" "test content" "Buffered content should be written"
    
    pass_test
}

# Test caching system
test_caching_system() {
    start_test "Caching System"
    
    # Test basic cache operations
    cache_set "test_key" "test_value" 60
    local cached_value=$(cache_get "test_key")
    assert_equals "$cached_value" "test_value" "Cached value should be retrieved"
    
    # Test cache miss
    local missing=$(cache_get "nonexistent_key")
    assert_equals "$?" "1" "Cache miss should return error"
    
    # Test cache expiration
    cache_set "expire_key" "expire_value" 1  # 1 second TTL
    sleep 2
    local expired=$(cache_get "expire_key")
    assert_equals "$?" "1" "Expired cache entry should return error"
    
    # Test L1 cache
    cache_set "l1_key" "small_value" 60 "l1"
    assert_not_empty "${L1_CACHE[l1_key]}" "L1 cache should contain entry"
    
    # Test cache invalidation
    cache_set "pattern_key_1" "value1" 60
    cache_set "pattern_key_2" "value2" 60
    cache_invalidate_pattern "pattern_key"
    local invalidated=$(cache_get "pattern_key_1")
    assert_equals "$?" "1" "Invalidated entries should be removed"
    
    # Test cache statistics
    local stats=$(cache_stats 2>&1)
    assert_contains "$stats" "Hit Rate:" "Cache stats should show hit rate"
    
    pass_test
}

# Test parallel execution
test_parallel_execution() {
    start_test "Parallel Execution"
    
    # Test simple parallel execution
    local commands=(
        "echo 'job1'; sleep 0.1"
        "echo 'job2'; sleep 0.1"
        "echo 'job3'; sleep 0.1"
    )
    
    local start_time=$(date +%s.%N)
    parallel_execute "${commands[@]}"
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Should be faster than sequential (0.3s)
    assert_true "[ \$(echo \"$duration < 0.25\" | bc -l) -eq 1 ]" "Parallel execution should be faster than sequential"
    
    # Test job management
    local job_id=$(parallel_submit_job "echo 'test job'" "test_group")
    assert_not_empty "$job_id" "Job ID should be returned"
    
    parallel_wait_for_group "test_group"
    assert_equals "${PARALLEL_JOB_STATUS[$job_id]}" "completed" "Job should complete successfully"
    
    # Test job output
    local output=$(parallel_get_output "$job_id")
    assert_equals "$output" "test job" "Job output should be captured"
    
    # Test parallel statistics
    local stats=$(parallel_stats 2>&1)
    assert_contains "$stats" "Total Jobs:" "Parallel stats should show job count"
    
    pass_test
}

# Test AWS parallel operations
test_aws_parallel_operations() {
    start_test "AWS Parallel Operations"
    
    # Mock AWS CLI for testing
    aws() {
        case "$2" in
            "describe-spot-price-history")
                echo '{"SpotPrice": "0.1234", "InstanceType": "g4dn.xlarge"}'
                ;;
            "describe-regions")
                echo '{"RegionName": "us-east-1"}'
                ;;
            *)
                echo '{}'
                ;;
        esac
    }
    export -f aws
    
    # Test parallel spot price queries
    local regions=("us-east-1" "us-west-2")
    parallel_get_spot_prices "g4dn.xlarge" "${regions[@]}"
    
    assert_not_empty "${SPOT_PRICES_RESULT[us-east-1]}" "Spot prices should be collected"
    
    # Restore AWS function
    unset -f aws
    
    pass_test
}

# Test performance targets
test_performance_targets() {
    start_test "Performance Targets"
    
    # Set up test metrics
    PERF_PHASE_TIMES["startup_duration"]="1.5"
    PERF_PHASE_TIMES["deployment_duration"]="150"
    echo "80" > "${PERF_METRICS_DIR}/peak_memory"
    
    # Check targets
    local target_output=$(perf_check_targets 2>&1)
    
    assert_contains "$target_output" "✓ Startup Time:" "Startup time should meet target"
    assert_contains "$target_output" "✓ Deployment Time:" "Deployment time should meet target"
    assert_contains "$target_output" "✓ Peak Memory:" "Memory usage should meet target"
    
    # Test failing targets
    PERF_PHASE_TIMES["startup_duration"]="3.0"
    PERF_PHASE_TIMES["deployment_duration"]="300"
    echo "150" > "${PERF_METRICS_DIR}/peak_memory"
    
    target_output=$(perf_check_targets 2>&1)
    assert_contains "$target_output" "✗" "Failed targets should be marked"
    
    pass_test
}

# Test cache AWS operations
test_cache_aws_operations() {
    start_test "Cache AWS Operations"
    
    # Mock AWS response
    aws() {
        echo '{"test": "response"}'
    }
    export -f aws
    
    # Test AWS response caching
    local cache_key="aws_test_$(date +%s)"
    local result1=$(cache_aws_response "$cache_key" "aws ec2 describe-instances" 60)
    local result2=$(cache_aws_response "$cache_key" "aws ec2 describe-instances" 60)
    
    assert_equals "$result1" "$result2" "AWS responses should be cached"
    
    # Check cache hit
    local hit_count_before=${CACHE_STATS["hits"]}
    cache_aws_response "$cache_key" "aws ec2 describe-instances" 60
    local hit_count_after=${CACHE_STATS["hits"]}
    
    assert_true "[ $hit_count_after -gt $hit_count_before ]" "Cache hit count should increase"
    
    unset -f aws
    
    pass_test
}

# Test performance optimization script
test_performance_script() {
    start_test "Performance Optimization Script"
    
    # Test script exists and is executable
    local script_path="$PROJECT_ROOT/scripts/performance-optimization.sh"
    assert_file_exists "$script_path" "Performance optimization script should exist"
    assert_true "[ -x \"$script_path\" ]" "Script should be executable"
    
    # Test script help
    local help_output=$("$script_path" 2>&1 || true)
    assert_contains "$help_output" "Usage:" "Script should show usage"
    
    pass_test
}

# Test map-reduce pattern
test_map_reduce() {
    start_test "Map-Reduce Pattern"
    
    # Define map function
    test_map() {
        local input="$1"
        echo "$((input * 2))"
    }
    
    # Define reduce function
    test_reduce() {
        local sum=0
        for val in "$@"; do
            sum=$((sum + val))
        done
        echo "$sum"
    }
    
    export -f test_map test_reduce
    
    # Test map-reduce
    local result=$(parallel_map_reduce "test_map" "test_reduce" 1 2 3 4 5)
    assert_equals "$result" "30" "Map-reduce should calculate correct result (1+2+3+4+5)*2 = 30"
    
    unset -f test_map test_reduce
    
    pass_test
}

# Test performance debugging
test_performance_debugging() {
    start_test "Performance Debugging"
    
    # Test slow operation detection
    local warning_output=$(perf_debug_slow_operation "sleep 0.5" "0.1" 2>&1)
    assert_contains "$warning_output" "PERF WARNING:" "Slow operations should trigger warning"
    
    # Test fast operation (no warning)
    warning_output=$(perf_debug_slow_operation "echo 'fast'" "1.0" 2>&1)
    assert_not_contains "$warning_output" "PERF WARNING:" "Fast operations should not trigger warning"
    
    pass_test
}

# Test baseline comparison
test_baseline_comparison() {
    start_test "Baseline Comparison"
    
    # Save current metrics as baseline
    perf_save_baseline
    assert_file_exists "$PERF_BASELINE_FILE" "Baseline file should be created"
    
    # Modify metrics
    perf_update_metrics "total_duration" "120"
    
    # Compare to baseline
    if command -v jq >/dev/null 2>&1; then
        local comparison_output=$(perf_compare_baseline 2>&1)
        assert_contains "$comparison_output" "Performance Comparison" "Comparison should be shown"
    fi
    
    pass_test
}

# Test cache size enforcement
test_cache_size_enforcement() {
    start_test "Cache Size Enforcement"
    
    # Set small cache size for testing
    CACHE_MAX_SIZE=1024  # 1KB
    
    # Fill cache beyond limit
    for i in {1..10}; do
        cache_set "large_key_$i" "$(printf '%100s' | tr ' ' 'X')" 3600 "l2"
    done
    
    # Check evictions occurred
    assert_true "[ ${CACHE_STATS[evictions]} -gt 0 ]" "Cache evictions should occur when size limit exceeded"
    
    pass_test
}

# Run all tests
run_all_tests() {
    setup_suite
    
    run_test test_performance_monitoring
    run_test test_optimization_functions
    run_test test_caching_system
    run_test test_parallel_execution
    run_test test_aws_parallel_operations
    run_test test_performance_targets
    run_test test_cache_aws_operations
    run_test test_performance_script
    run_test test_map_reduce
    run_test test_performance_debugging
    run_test test_baseline_comparison
    run_test test_cache_size_enforcement
    
    teardown_suite
}

# Execute tests
main() {
    start_test_suite "$TEST_NAME"
    run_all_tests
    end_test_suite
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi