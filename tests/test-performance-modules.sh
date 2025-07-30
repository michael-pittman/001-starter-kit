#!/usr/bin/env bash
#
# Test Suite: Performance Modules
# Description: Comprehensive tests for all performance enhancement modules
# Version: 1.0.0
#

set -euo pipefail

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/lib/shell-test-framework.sh"

# Source performance modules
source "$PROJECT_ROOT/lib/modules/performance/parallel.sh"
source "$PROJECT_ROOT/lib/modules/performance/cache.sh"
source "$PROJECT_ROOT/lib/modules/performance/pool.sh"
source "$PROJECT_ROOT/lib/modules/performance/progress.sh"
source "$PROJECT_ROOT/lib/modules/performance/metrics.sh"
source "$PROJECT_ROOT/lib/modules/performance/integration.sh"

# Test configuration
TEST_SUITE_NAME="Performance Modules"
TEST_TEMP_DIR="/tmp/perf-test-$$"

# Setup
setup_suite() {
    mkdir -p "$TEST_TEMP_DIR"
    cd "$TEST_TEMP_DIR"
}

# Cleanup
cleanup_suite() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# Parallel Processing Tests
# ============================================================================

test_parallel_init() {
    test_start "Parallel module initialization"
    
    # Initialize module
    assert_success parallel_init 5 "Initialize with 5 max workers"
    
    # Verify state
    assert_equals "${PARALLEL_STATE[initialized]}" "true" "Module initialized"
    assert_equals "${PARALLEL_STATE[max_workers]}" "5" "Max workers set"
    
    test_pass
}

test_parallel_execute_simple() {
    test_start "Parallel execution of simple command"
    
    parallel_init
    
    # Execute simple command
    assert_success parallel_execute "test1" "echo 'Hello from parallel'" "Test echo"
    
    # Wait for completion
    assert_success parallel_wait "test1" 5
    
    # Check output
    local output=$(parallel_get_job_output "test1")
    assert_contains "$output" "Hello from parallel" "Command output correct"
    
    test_pass
}

test_parallel_batch_execution() {
    test_start "Parallel batch execution"
    
    parallel_init
    
    # Create test commands
    local commands=(
        "job1:sleep 0.1 && echo 'Job 1 done'"
        "job2:sleep 0.2 && echo 'Job 2 done'"
        "job3:sleep 0.1 && echo 'Job 3 done'"
    )
    
    # Execute batch
    assert_success parallel_batch "${commands[@]}"
    
    # Verify all completed
    assert_equals "$(parallel_get_job_status job1)" "completed" "Job 1 completed"
    assert_equals "$(parallel_get_job_status job2)" "completed" "Job 2 completed"
    assert_equals "$(parallel_get_job_status job3)" "completed" "Job 3 completed"
    
    # Cleanup
    parallel_cleanup all
    
    test_pass
}

test_parallel_error_handling() {
    test_start "Parallel error handling"
    
    parallel_init
    
    # Execute failing command
    assert_success parallel_execute "fail1" "exit 1" "Failing command"
    assert_success parallel_wait "fail1" 5
    
    # Check status
    assert_equals "$(parallel_get_job_status fail1)" "failed" "Job marked as failed"
    
    test_pass
}

# ============================================================================
# Caching Tests
# ============================================================================

test_cache_init() {
    test_start "Cache module initialization"
    
    # Initialize module
    assert_success cache_init "Initialize cache"
    
    # Verify state
    assert_equals "${CACHE_STATE[initialized]}" "true" "Module initialized"
    
    test_pass
}

test_cache_set_get() {
    test_start "Cache set and get operations"
    
    cache_init
    
    # Set value
    assert_success cache_set "test_key" "test_value" 60 "Test cache set"
    
    # Get value
    local value
    value=$(cache_get "test_key")
    assert_success "Get cached value"
    assert_equals "$value" "test_value" "Retrieved correct value"
    
    # Test cache miss
    assert_failure cache_get "nonexistent_key" "Cache miss returns failure"
    
    test_pass
}

test_cache_expiration() {
    test_start "Cache TTL expiration"
    
    cache_init
    
    # Set with 1 second TTL
    assert_success cache_set "expire_key" "expire_value" 1
    
    # Immediate get should work
    assert_success cache_get "expire_key" "Get before expiration"
    
    # Wait for expiration
    sleep 2
    
    # Should be expired
    assert_failure cache_get "expire_key" "Get after expiration fails"
    
    test_pass
}

test_cache_eviction() {
    test_start "Cache LRU eviction"
    
    cache_init
    
    # Set max items to 3 for testing
    CACHE_CONFIG[memory_max_items]=3
    
    # Add items to fill cache
    cache_set "item1" "value1"
    cache_set "item2" "value2"
    cache_set "item3" "value3"
    
    # Access item1 to make it recently used
    cache_get "item1" >/dev/null
    
    # Add new item to trigger eviction
    cache_set "item4" "value4"
    
    # item2 should be evicted (least recently used)
    assert_failure cache_get "item2" "LRU item evicted"
    assert_success cache_get "item1" "Recently used item retained"
    assert_success cache_get "item3" "Other item retained"
    assert_success cache_get "item4" "New item added"
    
    test_pass
}

# ============================================================================
# Connection Pooling Tests
# ============================================================================

test_pool_init() {
    test_start "Connection pool initialization"
    
    # Initialize module
    assert_success pool_init "Initialize connection pool"
    
    # Verify state
    assert_equals "${POOL_STATE[initialized]}" "true" "Module initialized"
    
    test_pass
}

test_pool_connection_reuse() {
    test_start "Connection pool reuse"
    
    pool_init
    
    # Get connection
    local conn1
    conn1=$(pool_get_aws_connection "ec2" "us-east-1")
    assert_success "Get first connection"
    
    # Release connection
    assert_success pool_release_connection "$conn1"
    
    # Get connection again - should reuse
    local conn2
    conn2=$(pool_get_aws_connection "ec2" "us-east-1")
    assert_success "Get second connection"
    
    # Check reuse stats
    local stats=$(pool_get_stats)
    assert_contains "$stats" "reused_connections=1" "Connection was reused"
    
    test_pass
}

# ============================================================================
# Progress Indicators Tests
# ============================================================================

test_progress_init() {
    test_start "Progress module initialization"
    
    # Disable ANSI for testing
    PROGRESS_CONFIG[color_enabled]="false"
    
    # Initialize module
    assert_success progress_init "Initialize progress"
    
    # Verify state
    assert_equals "${PROGRESS_STATE[initialized]}" "true" "Module initialized"
    
    test_pass
}

test_progress_spinner() {
    test_start "Progress spinner functionality"
    
    progress_init
    
    # Start spinner
    assert_success progress_spinner_start "Testing spinner" "test-spinner"
    
    # Let it run briefly
    sleep 0.5
    
    # Stop spinner
    assert_success progress_spinner_stop "Test complete" "success"
    
    test_pass
}

test_progress_bar() {
    test_start "Progress bar functionality"
    
    progress_init
    
    # Create progress bar
    assert_success progress_bar_create "test-bar" 10 "Test Progress"
    
    # Update progress
    assert_success progress_bar_update "test-bar" 5
    assert_success progress_bar_update "test-bar" 10
    
    # Complete
    assert_success progress_bar_complete "test-bar"
    
    test_pass
}

# ============================================================================
# Metrics Collection Tests
# ============================================================================

test_metrics_init() {
    test_start "Metrics module initialization"
    
    # Initialize module
    assert_success metrics_init "Initialize metrics"
    
    # Verify state
    assert_equals "${METRICS_STATE[initialized]}" "true" "Module initialized"
    
    test_pass
}

test_metrics_operation_timing() {
    test_start "Metrics operation timing"
    
    metrics_init
    
    # Start operation
    assert_success metrics_operation_start "test_op" "test" "type=unit_test"
    
    # Simulate work
    sleep 0.1
    
    # End operation
    assert_success metrics_operation_end "test_op" "test" "success"
    
    # Verify metrics recorded
    assert_not_empty "${METRICS_OPERATIONS[test:test_op:duration_ms]}" "Duration recorded"
    
    test_pass
}

test_metrics_counters() {
    test_start "Metrics counters"
    
    metrics_init
    
    # Increment counter
    assert_success metrics_counter_increment "test.counter" 1
    assert_success metrics_counter_increment "test.counter" 2
    
    # Check value
    assert_equals "${METRICS_COUNTERS[test.counter]}" "3" "Counter incremented correctly"
    
    test_pass
}

test_metrics_gauges() {
    test_start "Metrics gauges"
    
    metrics_init
    
    # Set gauge
    assert_success metrics_gauge_set "test.gauge" 42
    
    # Check value
    assert_equals "${METRICS_GAUGES[test.gauge]}" "42" "Gauge set correctly"
    
    test_pass
}

test_metrics_histogram() {
    test_start "Metrics histogram"
    
    metrics_init
    
    # Record values
    metrics_record_histogram "test.histogram" 10
    metrics_record_histogram "test.histogram" 20
    metrics_record_histogram "test.histogram" 30
    
    # Check statistics
    assert_equals "${METRICS_HISTOGRAMS[test.histogram:count]}" "3" "Count correct"
    assert_equals "${METRICS_HISTOGRAMS[test.histogram:min]}" "10" "Min correct"
    assert_equals "${METRICS_HISTOGRAMS[test.histogram:max]}" "30" "Max correct"
    assert_equals "${METRICS_HISTOGRAMS[test.histogram:avg]}" "20" "Average correct"
    
    test_pass
}

# ============================================================================
# Integration Tests
# ============================================================================

test_integration_init() {
    test_start "Integration module initialization"
    
    # Initialize all modules
    assert_success perf_init_all "test-stack"
    
    # Verify all modules initialized
    assert_equals "${PARALLEL_STATE[initialized]}" "true" "Parallel initialized"
    assert_equals "${CACHE_STATE[initialized]}" "true" "Cache initialized"
    assert_equals "${POOL_STATE[initialized]}" "true" "Pool initialized"
    assert_equals "${PROGRESS_STATE[initialized]}" "true" "Progress initialized"
    assert_equals "${METRICS_STATE[initialized]}" "true" "Metrics initialized"
    
    test_pass
}

test_integration_perf_aws() {
    test_start "Performance-enhanced AWS CLI"
    
    perf_init_all
    
    # Mock AWS command for testing
    aws() {
        case "$1" in
            ec2)
                case "$2" in
                    describe-regions)
                        echo '{"Regions": [{"RegionName": "us-east-1"}]}'
                        ;;
                esac
                ;;
        esac
    }
    export -f aws
    
    # First call - should cache miss
    local result1
    result1=$(perf_aws ec2 describe-regions)
    assert_success "First AWS call"
    
    # Second call - should cache hit
    local result2
    result2=$(perf_aws ec2 describe-regions)
    assert_success "Second AWS call"
    
    # Results should be identical
    assert_equals "$result1" "$result2" "Cached result matches"
    
    test_pass
}

test_integration_parallel_deploy() {
    test_start "Parallel deployment integration"
    
    perf_init_all
    
    # Create test deployment tasks
    local tasks=(
        "task1:echo 'Deploying VPC'"
        "task2:echo 'Creating security groups'"
        "task3:echo 'Setting up IAM roles'"
    )
    
    # Execute parallel deployment
    assert_success perf_parallel_deploy "${tasks[@]}"
    
    # Verify all tasks completed
    local stats=$(parallel_get_stats)
    assert_contains "$stats" "completed_jobs=3" "All jobs completed"
    
    test_pass
}

# ============================================================================
# Performance Benchmark Tests
# ============================================================================

test_performance_benchmark() {
    test_start "Performance module benchmarks"
    
    perf_init_all
    
    # Benchmark cache operations
    local cache_start=$(date +%s%N)
    for i in {1..1000}; do
        cache_set "bench_key_$i" "bench_value_$i"
        cache_get "bench_key_$i" >/dev/null
    done
    local cache_end=$(date +%s%N)
    local cache_duration_ms=$(( (cache_end - cache_start) / 1000000 ))
    
    echo "Cache benchmark: 2000 operations in ${cache_duration_ms}ms"
    assert_less_than "$cache_duration_ms" "2000" "Cache operations under 2s"
    
    # Benchmark parallel execution
    local parallel_start=$(date +%s%N)
    local parallel_tasks=()
    for i in {1..10}; do
        parallel_tasks+=("job$i:sleep 0.1")
    done
    parallel_batch "${parallel_tasks[@]}"
    local parallel_end=$(date +%s%N)
    local parallel_duration_ms=$(( (parallel_end - parallel_start) / 1000000 ))
    
    echo "Parallel benchmark: 10 jobs in ${parallel_duration_ms}ms"
    assert_less_than "$parallel_duration_ms" "500" "Parallel execution under 500ms"
    
    test_pass
}

# ============================================================================
# Error Handling Tests
# ============================================================================

test_error_handling() {
    test_start "Performance module error handling"
    
    # Test uninitialized module errors
    assert_failure cache_get "key" "Cache get fails when uninitialized"
    assert_failure parallel_execute "job" "cmd" "Parallel execute fails when uninitialized"
    assert_failure pool_get_aws_connection "ec2" "Pool get fails when uninitialized"
    
    test_pass
}

# ============================================================================
# Run Test Suite
# ============================================================================

# Setup
setup_suite

# Run tests
run_test_suite() {
    test_suite_start "$TEST_SUITE_NAME"
    
    # Parallel processing tests
    run_test test_parallel_init
    run_test test_parallel_execute_simple
    run_test test_parallel_batch_execution
    run_test test_parallel_error_handling
    
    # Caching tests
    run_test test_cache_init
    run_test test_cache_set_get
    run_test test_cache_expiration
    run_test test_cache_eviction
    
    # Connection pooling tests
    run_test test_pool_init
    run_test test_pool_connection_reuse
    
    # Progress indicator tests
    run_test test_progress_init
    run_test test_progress_spinner
    run_test test_progress_bar
    
    # Metrics collection tests
    run_test test_metrics_init
    run_test test_metrics_operation_timing
    run_test test_metrics_counters
    run_test test_metrics_gauges
    run_test test_metrics_histogram
    
    # Integration tests
    run_test test_integration_init
    run_test test_integration_perf_aws
    run_test test_integration_parallel_deploy
    
    # Performance benchmarks
    run_test test_performance_benchmark
    
    # Error handling
    run_test test_error_handling
    
    test_suite_end
}

# Execute test suite
run_test_suite

# Cleanup
cleanup_suite

# Exit with appropriate code
exit $TEST_FAILURES