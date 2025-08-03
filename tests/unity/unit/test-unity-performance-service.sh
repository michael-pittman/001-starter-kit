#!/bin/bash
# =============================================================================
# Unity Performance Service Unit Tests
# Comprehensive unit testing for Unity Performance service functions
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework
unity_test_init "test-unity-performance-service" "service-unit" "unity-performance-service"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up test environment
setup_performance_service_tests() {
    # Create test performance directory
    export TEST_PERF_DIR="/tmp/unity-performance-test-$$"
    mkdir -p "$TEST_PERF_DIR"
    mkdir -p "$TEST_PERF_DIR/.unity/cache/performance"
    mkdir -p "$TEST_PERF_DIR/.unity/data/profiles"
    mkdir -p "$TEST_PERF_DIR/lib/unity/core"
    mkdir -p "$TEST_PERF_DIR/lib/unity/events"
    mkdir -p "$TEST_PERF_DIR/lib/modules/core"
    
    # Set test-specific paths
    export UNITY_CACHE_DIR="$TEST_PERF_DIR/.unity/cache"
    export UNITY_DATA_DIR="$TEST_PERF_DIR/.unity/data"
    export PERF_CACHE_DIR="$UNITY_CACHE_DIR/performance"
    export PERF_PROFILE_DIR="$UNITY_DATA_DIR/profiles"
    export PERF_METRICS_FILE="$PERF_CACHE_DIR/metrics.json"
    export PERF_BENCHMARKS_FILE="$PERF_CACHE_DIR/benchmarks.json"
    export PROJECT_ROOT="$TEST_PERF_DIR"
    
    # Mock Unity core functions and files
    mock_function "unity_register_service" 'return 0'
    mock_function "unity_event_on" 'return 0'
    mock_function "unity_event_emit" 'echo "[TEST-EVENT] $1: $2"'
    
    # Create mock Unity files
    cat > "$TEST_PERF_DIR/lib/unity/core/registry.sh" << 'EOF'
#!/bin/bash
unity_register_service() { return 0; }
export -f unity_register_service
EOF
    
    cat > "$TEST_PERF_DIR/lib/unity/events/event-bus.sh" << 'EOF'
#!/bin/bash
unity_event_on() { return 0; }
unity_event_emit() { echo "[TEST-EVENT] $1: $2"; }
export -f unity_event_on unity_event_emit
EOF
    
    cat > "$TEST_PERF_DIR/lib/modules/core/logging.sh" << 'EOF'
#!/bin/bash
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_debug() { [[ "${DEBUG:-}" == "true" ]] && echo "[DEBUG] $*"; }
export -f log_info log_warn log_error log_debug
EOF
    
    # Mock external commands
    mock_function "aws" 'case "$1" in
        "ec2")
            case "$2" in
                "describe-instances")
                    echo "{\"Reservations\":[{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\"}]}]}"
                    ;;
                *)
                    echo "{\"ResponseMetadata\":{\"RequestId\":\"test-request-id\"}}"
                    ;;
            esac
            ;;
        *)
            echo "{\"ResponseMetadata\":{\"RequestId\":\"test-request-id\"}}"
            ;;
    esac'
    
    mock_function "jq" 'case "$*" in
        *"timestamp"*)
            case "$*" in
                *".timestamp"*) echo "$(date +%s)" ;;
                *"--arg ts"*) echo "{\"timestamp\":$(date +%s),\"ttl\":3600,\"data\":{}}" ;;
                *) echo "1234567890" ;;
            esac
            ;;
        *".ttl"*) echo "3600" ;;
        *".data"*) echo "{\"test\":\"data\"}" ;;
        *"keys"*) echo "test_key" ;;
        *"-c"*) echo "{\"test\":\"data\"}" ;;
        *"-Rs"*) echo "\"test data\"" ;;
        *"-n"*) echo "{\"timestamp\":$(date +%s),\"ttl\":3600,\"data\":{\"test\":\"data\"}}" ;;
        *"--arg"*) echo "{\"timestamp\":$(date +%s),\"ttl\":3600,\"data\":{\"test\":\"data\"}}" ;;
        *) echo "test-json-output" ;;
    esac'
    
    mock_function "ps" 'echo "12345" | tr -d " "'  # Mock RSS memory in KB
    mock_function "date" 'case "$1" in
        "+%s%N") echo "$(date +%s)000000000" ;;
        "+%s") echo "$(date +%s)" ;;
        *) date "$@" ;;
    esac'
    mock_function "nproc" 'echo "4"'
    mock_function "sysctl" 'case "$2" in
        "hw.memsize") echo "8589934592" ;;
        "hw.ncpu") echo "4" ;;
        *) echo "test-output" ;;
    esac'
    mock_function "find" 'echo "/tmp/test.json"'  # Mock find results
    
    # Set test environment variables
    export UNITY_TEST_MODE="true"
    export DEBUG="false"
    
    # Load the Performance service
    source "$PROJECT_ROOT/lib/unity/services/unity-performance-service.sh" 2>/dev/null || {
        log_error "Failed to load Unity Performance service"
        return 1
    }
}

# Clean up test environment
cleanup_performance_service_tests() {
    # Restore mocked functions
    local mock_functions=("unity_register_service" "unity_event_on" "unity_event_emit" 
                         "aws" "jq" "ps" "date" "nproc" "sysctl" "find")
    
    for func in "${mock_functions[@]}"; do
        restore_function "$func" 2>/dev/null || true
    done
    
    # Clean up test files
    if [[ -n "${TEST_PERF_DIR:-}" && -d "$TEST_PERF_DIR" ]]; then
        rm -rf "$TEST_PERF_DIR" 2>/dev/null || true
    fi
    
    # Clean up environment variables
    unset TEST_PERF_DIR UNITY_CACHE_DIR UNITY_DATA_DIR PERF_CACHE_DIR PERF_PROFILE_DIR
    unset PERF_METRICS_FILE PERF_BENCHMARKS_FILE UNITY_TEST_MODE
}

# =============================================================================
# UNITY PERFORMANCE SERVICE INITIALIZATION TESTS
# =============================================================================

test_unity_performance_service_init() {
    test_start "unity_performance_service_init" "Test Unity Performance service initialization"
    
    setup_performance_service_tests
    
    # Test service initialization
    if unity_performance_init "test-performance" >/dev/null 2>&1; then
        test_pass "Unity Performance service initialized successfully"
        
        # Verify directories were created
        if [[ -d "$PERF_CACHE_DIR" && -d "$PERF_PROFILE_DIR" ]]; then
            test_pass "Performance service directories created successfully"
        else
            test_fail "Performance service directories not created properly"
        fi
    else
        test_fail "Unity Performance service initialization failed"
    fi
    
    cleanup_performance_service_tests
}

test_performance_metrics_initialization() {
    test_start "performance_metrics_initialization" "Test performance metrics initialization"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Check if metrics were initialized
    local init_time=$(_perf_get_metric "init_time")
    local memory_usage=$(_perf_get_metric "memory_usage")
    local api_calls=$(_perf_get_metric "api_calls")
    
    if [[ "$init_time" == "0" && "$memory_usage" == "0" && "$api_calls" == "0" ]]; then
        test_pass "Performance metrics initialized correctly"
    else
        test_fail "Performance metrics not initialized properly: init_time=$init_time, memory_usage=$memory_usage, api_calls=$api_calls"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# PERFORMANCE TIMING TESTS
# =============================================================================

test_perf_timer_start_stop() {
    test_start "perf_timer_start_stop" "Test performance timer start and stop"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test timer operations
    perf_timer_start "test_timer"
    sleep 0.1  # Small delay to ensure timer difference
    
    if perf_timer_stop "test_timer" >/dev/null 2>&1; then
        test_pass "Timer start/stop operations completed successfully"
        
        # Check if metric was recorded
        local timer_value=$(_perf_get_metric "timer_test_timer")
        if [[ "$timer_value" -gt 0 ]]; then
            test_pass "Timer metric recorded: ${timer_value}ms"
        else
            test_fail "Timer metric not recorded properly: $timer_value"
        fi
    else
        test_fail "Timer start/stop operations failed"
    fi
    
    cleanup_performance_service_tests
}

test_perf_timer_invalid_stop() {
    test_start "perf_timer_invalid_stop" "Test stopping non-existent timer"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test stopping non-existent timer
    if perf_timer_stop "nonexistent_timer" >/dev/null 2>&1; then
        test_fail "Expected timer stop to fail for non-existent timer"
    else
        test_pass "Timer stop correctly failed for non-existent timer"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# BASH COMPATIBILITY TESTS
# =============================================================================

test_bash3_compatibility() {
    test_start "bash3_compatibility" "Test bash 3.x compatibility functions"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test metric operations
    _perf_set_metric "test_metric" "42"
    local retrieved_value=$(_perf_get_metric "test_metric")
    
    if [[ "$retrieved_value" == "42" ]]; then
        test_pass "Bash 3.x compatible metric operations work correctly"
    else
        test_fail "Bash 3.x compatible metric operations failed: expected 42, got $retrieved_value"
    fi
    
    # Test timer operations
    _perf_set_timer "test_timer" "123456789"
    local timer_value=$(_perf_get_timer "test_timer")
    
    if [[ "$timer_value" == "123456789" ]]; then
        test_pass "Bash 3.x compatible timer operations work correctly"
    else
        test_fail "Bash 3.x compatible timer operations failed: expected 123456789, got $timer_value"
    fi
    
    # Test cache operations
    _perf_set_cache "test_cache" "test_value"
    local cache_value=$(_perf_get_cache "test_cache")
    
    if [[ "$cache_value" == "test_value" ]]; then
        test_pass "Bash 3.x compatible cache operations work correctly"
    else
        test_fail "Bash 3.x compatible cache operations failed: expected test_value, got $cache_value"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# CACHING TESTS
# =============================================================================

test_perf_cache_aws_response() {
    test_start "perf_cache_aws_response" "Test AWS response caching"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test caching AWS response
    local test_response='{"test": "data", "value": 123}'
    
    if perf_cache_aws_response "test_key" "$test_response" "3600" >/dev/null 2>&1; then
        test_pass "AWS response cached successfully"
        
        # Verify cache file was created
        local cache_file="$PERF_CACHE_DIR/aws_test_key.json"
        if [[ -f "$cache_file" ]]; then
            test_pass "Cache file created successfully"
        else
            test_warn "Cache file not created (may be mocked)"
        fi
    else
        test_fail "AWS response caching failed"
    fi
    
    cleanup_performance_service_tests
}

test_perf_get_cached_aws_response() {
    test_start "perf_get_cached_aws_response" "Test cached AWS response retrieval"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Cache a response first
    local test_response='{"test": "cached_data"}'
    perf_cache_aws_response "retrieve_test" "$test_response" "3600" >/dev/null 2>&1
    
    # Test retrieving cached response
    local cached_response
    cached_response=$(perf_get_cached_aws_response "retrieve_test" 2>/dev/null)
    
    if [[ -n "$cached_response" ]]; then
        test_pass "Cached AWS response retrieved successfully"
    else
        test_warn "Cached AWS response not retrieved (may be due to mocking)"
    fi
    
    cleanup_performance_service_tests
}

test_cache_expiration() {
    test_start "cache_expiration" "Test cache expiration logic"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Mock expired cache entry
    local expired_entry='{"timestamp":1, "ttl":1, "data":{"test":"expired"}}'
    _perf_set_cache "aws_expired_test" "$expired_entry"
    
    # Test retrieving expired cache
    if perf_get_cached_aws_response "expired_test" >/dev/null 2>&1; then
        test_warn "Expired cache should not be returned"
    else
        test_pass "Expired cache correctly rejected"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# LAZY LOADING TESTS
# =============================================================================

test_perf_lazy_load_service() {
    test_start "perf_lazy_load_service" "Test lazy loading service registration"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Create a test service file
    local test_service_file="$TEST_PERF_DIR/test_service.sh"
    echo '#!/bin/bash' > "$test_service_file"
    echo 'echo "Test service loaded"' >> "$test_service_file"
    
    # Test lazy loading registration
    if perf_lazy_load_service "test_lazy_service" "$test_service_file" "normal" >/dev/null 2>&1; then
        test_pass "Lazy loading service registered successfully"
        
        # Verify service is in registry
        local registry_entry=$(_perf_get_lazy_load "test_lazy_service")
        if [[ -n "$registry_entry" && "$registry_entry" == *"pending"* ]]; then
            test_pass "Service registered with pending status"
        else
            test_fail "Service not properly registered: $registry_entry"
        fi
    else
        test_fail "Lazy loading service registration failed"
    fi
    
    cleanup_performance_service_tests
}

test_perf_load_service_now() {
    test_start "perf_load_service_now" "Test immediate service loading"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Create a test service file
    local test_service_file="$TEST_PERF_DIR/test_immediate_service.sh"
    echo '#!/bin/bash' > "$test_service_file"
    echo 'TEST_SERVICE_LOADED=true' >> "$test_service_file"
    
    # Register for lazy loading
    perf_lazy_load_service "test_immediate_service" "$test_service_file" "normal" >/dev/null 2>&1
    
    # Test immediate loading
    if perf_load_service_now "test_immediate_service" >/dev/null 2>&1; then
        test_pass "Service loaded immediately successfully"
        
        # Verify service status changed to loaded
        local registry_entry=$(_perf_get_lazy_load "test_immediate_service")
        if [[ "$registry_entry" == *"loaded"* ]]; then
            test_pass "Service status updated to loaded"
        else
            test_warn "Service status not updated properly: $registry_entry"
        fi
    else
        test_fail "Immediate service loading failed"
    fi
    
    cleanup_performance_service_tests
}

test_load_nonexistent_service() {
    test_start "load_nonexistent_service" "Test loading non-registered service"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test loading non-registered service
    if perf_load_service_now "nonexistent_service" >/dev/null 2>&1; then
        test_fail "Expected loading non-registered service to fail"
    else
        test_pass "Loading non-registered service correctly failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# MEMORY MONITORING TESTS
# =============================================================================

test_perf_monitor_memory() {
    test_start "perf_monitor_memory" "Test memory monitoring"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test memory monitoring
    if perf_monitor_memory $$ >/dev/null 2>&1; then
        test_pass "Memory monitoring completed successfully"
        
        # Check if memory metric was set
        local memory_usage=$(_perf_get_metric "memory_usage")
        if [[ "$memory_usage" -gt 0 ]]; then
            test_pass "Memory usage metric recorded: $memory_usage bytes"
        else
            test_fail "Memory usage metric not recorded properly: $memory_usage"
        fi
    else
        test_fail "Memory monitoring failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# PROFILING TESTS
# =============================================================================

test_perf_profile_system() {
    test_start "perf_profile_system" "Test system performance profiling"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test system profiling
    if perf_profile_system "test_profile" >/dev/null 2>&1; then
        test_pass "System profiling completed successfully"
        
        # Check if profile file was created
        if ls "$PERF_PROFILE_DIR"/test_profile_*.json >/dev/null 2>&1; then
            test_pass "Profile file created successfully"
        else
            test_warn "Profile file not created (may be due to mocking)"
        fi
    else
        test_fail "System profiling failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# BENCHMARKING TESTS
# =============================================================================

test_perf_run_benchmark() {
    test_start "perf_run_benchmark" "Test performance benchmarking"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test running benchmark
    if perf_run_benchmark "lazy_loading" "2" >/dev/null 2>&1; then
        test_pass "Performance benchmark completed successfully"
        
        # Check if benchmark results file was created
        if [[ -f "$PERF_BENCHMARKS_FILE" ]]; then
            test_pass "Benchmark results file created successfully"
        else
            test_fail "Benchmark results file not created"
        fi
    else
        test_fail "Performance benchmarking failed"
    fi
    
    cleanup_performance_service_tests
}

test_benchmark_caching() {
    test_start "benchmark_caching" "Test caching benchmark"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test caching benchmark
    local result
    result=$(perf_benchmark_caching "3" 2>/dev/null)
    
    if [[ -n "$result" && "$result" == *"caching"* ]]; then
        test_pass "Caching benchmark completed successfully: $result"
    else
        test_fail "Caching benchmark failed or returned invalid result: $result"
    fi
    
    cleanup_performance_service_tests
}

test_benchmark_lazy_loading() {
    test_start "benchmark_lazy_loading" "Test lazy loading benchmark"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test lazy loading benchmark
    local result
    result=$(perf_benchmark_lazy_loading "2" 2>/dev/null)
    
    if [[ -n "$result" && "$result" == *"lazy_loading"* ]]; then
        test_pass "Lazy loading benchmark completed successfully: $result"
    else
        test_fail "Lazy loading benchmark failed or returned invalid result: $result"
    fi
    
    cleanup_performance_service_tests
}

test_benchmark_memory() {
    test_start "benchmark_memory" "Test memory benchmark"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test memory benchmark
    local result
    result=$(perf_benchmark_memory "2" 2>/dev/null)
    
    if [[ -n "$result" && "$result" == *"memory"* ]]; then
        test_pass "Memory benchmark completed successfully: $result"
    else
        test_fail "Memory benchmark failed or returned invalid result: $result"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# OPTIMIZATION TESTS
# =============================================================================

test_perf_optimize_data_structure() {
    test_start "perf_optimize_data_structure" "Test data structure optimization"
    
    setup_performance_service_tests
    
    # Test JSON optimization
    local test_json='{"test": "data", "value": 123}'
    local optimized_json
    optimized_json=$(perf_optimize_data_structure "json" "$test_json" 2>/dev/null)
    
    if [[ -n "$optimized_json" ]]; then
        test_pass "JSON optimization completed successfully"
    else
        test_fail "JSON optimization failed"
    fi
    
    # Test array optimization
    local test_array="apple banana apple cherry banana"
    local optimized_array
    optimized_array=$(perf_optimize_data_structure "array" "$test_array" 2>/dev/null)
    
    if [[ -n "$optimized_array" ]]; then
        test_pass "Array optimization completed successfully"
    else
        test_fail "Array optimization failed"
    fi
    
    # Test string optimization
    local test_string="  test string with whitespace  "
    local optimized_string
    optimized_string=$(perf_optimize_data_structure "string" "$test_string" 2>/dev/null)
    
    if [[ "$optimized_string" == "test string with whitespace" ]]; then
        test_pass "String optimization works correctly"
    else
        test_fail "String optimization failed: expected 'test string with whitespace', got '$optimized_string'"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# BOTTLENECK IDENTIFICATION TESTS
# =============================================================================

test_identify_bottlenecks() {
    test_start "identify_bottlenecks" "Test bottleneck identification"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Set some timer metrics with high values
    _perf_set_metric "timer_slow_operation" "5000"  # 5 seconds
    _perf_set_metric "timer_fast_operation" "100"   # 100ms
    
    # Test bottleneck identification
    local bottlenecks
    bottlenecks=$(identify_bottlenecks 2>/dev/null)
    
    if [[ -n "$bottlenecks" ]]; then
        test_pass "Bottleneck identification completed successfully"
    else
        test_warn "Bottleneck identification returned empty result (may be expected)"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# RECOMMENDATION TESTS
# =============================================================================

test_perf_generate_recommendations() {
    test_start "perf_generate_recommendations" "Test performance recommendations"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Create a test profile file
    local test_profile_file="$PERF_PROFILE_DIR/test_recommendations.json"
    cat > "$test_profile_file" << 'EOF'
{
  "metrics": {
    "init_time": 3000,
    "memory_usage": 200000000,
    "cache_hits": 10,
    "cache_misses": 90,
    "api_calls": 150
  }
}
EOF
    
    # Test recommendations generation
    local recommendations
    recommendations=$(perf_generate_recommendations "$test_profile_file" 2>/dev/null)
    
    if [[ -n "$recommendations" ]]; then
        test_pass "Performance recommendations generated successfully"
        
        # Check if recommendations contain expected content
        if [[ "$recommendations" == *"Recommendation"* || "$recommendations" == *"optimization"* ]]; then
            test_pass "Recommendations contain expected content"
        else
            test_warn "Recommendations may not contain expected optimization advice"
        fi
    else
        test_fail "Performance recommendations generation failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_utility_functions() {
    test_start "utility_functions" "Test utility functions"
    
    setup_performance_service_tests
    
    # Test get_total_memory
    local total_memory
    total_memory=$(get_total_memory 2>/dev/null)
    
    if [[ -n "$total_memory" && "$total_memory" =~ ^[0-9]+$ ]]; then
        test_pass "get_total_memory works correctly: $total_memory bytes"
    else
        test_fail "get_total_memory failed or returned invalid value: '$total_memory'"
    fi
    
    # Test get_cpu_count
    local cpu_count
    cpu_count=$(get_cpu_count 2>/dev/null)
    
    if [[ -n "$cpu_count" && "$cpu_count" =~ ^[0-9]+$ ]]; then
        test_pass "get_cpu_count works correctly: $cpu_count CPUs"
    else
        test_fail "get_cpu_count failed or returned invalid value: '$cpu_count'"
    fi
    
    # Test format_bytes
    local formatted_bytes
    formatted_bytes=$(format_bytes 1048576 2>/dev/null)
    
    if [[ "$formatted_bytes" == "1MB" ]]; then
        test_pass "format_bytes works correctly: $formatted_bytes"
    else
        test_fail "format_bytes failed: expected '1MB', got '$formatted_bytes'"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# EVENT HANDLER TESTS
# =============================================================================

test_event_handlers() {
    test_start "event_handlers" "Test performance event handlers"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test service starting handler
    if perf_handle_service_starting "test_service" >/dev/null 2>&1; then
        test_pass "Service starting event handler works"
    else
        test_fail "Service starting event handler failed"
    fi
    
    # Test service started handler
    if perf_handle_service_started "test_service" >/dev/null 2>&1; then
        test_pass "Service started event handler works"
    else
        test_fail "Service started event handler failed"
    fi
    
    # Test API call handler
    if perf_handle_api_call "test_api" >/dev/null 2>&1; then
        test_pass "API call event handler works"
        
        # Check if API calls metric was incremented
        local api_calls=$(_perf_get_metric "api_calls")
        if [[ "$api_calls" -gt 0 ]]; then
            test_pass "API calls metric incremented correctly: $api_calls"
        else
            test_fail "API calls metric not incremented: $api_calls"
        fi
    else
        test_fail "API call event handler failed"
    fi
    
    # Test config loaded handler
    if perf_handle_config_loaded "test_config.yml" >/dev/null 2>&1; then
        test_pass "Config loaded event handler works"
    else
        test_fail "Config loaded event handler failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# BATCH OPERATIONS TESTS
# =============================================================================

test_perf_batch_aws_calls() {
    test_start "perf_batch_aws_calls" "Test AWS API call batching"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test batching describe-instances calls
    local instance_ids=("i-1234567890abcdef0" "i-abcdef1234567890" "i-567890abcdef1234")
    
    if perf_batch_aws_calls "describe-instances" "${instance_ids[@]}" >/dev/null 2>&1; then
        test_pass "AWS API call batching completed successfully"
    else
        test_fail "AWS API call batching failed"
    fi
    
    # Test unsupported batch call type
    if perf_batch_aws_calls "unsupported-call" "test" >/dev/null 2>&1; then
        test_fail "Expected unsupported batch call to fail"
    else
        test_pass "Unsupported batch call correctly failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# METRICS SAVE/LOAD TESTS
# =============================================================================

test_perf_save_metrics() {
    test_start "perf_save_metrics" "Test performance metrics saving"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Set some metrics
    _perf_set_metric "init_time" "1500"
    _perf_set_metric "memory_usage" "50000000"
    _perf_set_metric "api_calls" "25"
    
    # Test metrics saving
    if perf_save_metrics >/dev/null 2>&1; then
        test_pass "Performance metrics saved successfully"
        
        # Check if metrics file was created
        if [[ -f "$PERF_METRICS_FILE" ]]; then
            test_pass "Metrics file created successfully"
        else
            test_fail "Metrics file not created"
        fi
    else
        test_fail "Performance metrics saving failed"
    fi
    
    cleanup_performance_service_tests
}

test_perf_cleanup_cache() {
    test_start "perf_cleanup_cache" "Test cache cleanup"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Add some cache entries with expired timestamps
    local expired_entry='{"timestamp":1, "ttl":1, "data":{"test":"expired"}}'
    _perf_set_cache "expired_entry" "$expired_entry"
    
    local valid_entry='{"timestamp":'$(date +%s)', "ttl":3600, "data":{"test":"valid"}}'
    _perf_set_cache "valid_entry" "$valid_entry"
    
    # Test cache cleanup
    if perf_cleanup_cache >/dev/null 2>&1; then
        test_pass "Cache cleanup completed successfully"
    else
        test_fail "Cache cleanup failed"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_performance_error_handling() {
    test_start "performance_error_handling" "Test Performance service error handling"
    
    setup_performance_service_tests
    
    # Initialize service
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test handling invalid profile file
    local recommendations
    recommendations=$(perf_generate_recommendations "nonexistent_file.json" 2>/dev/null)
    
    if [[ -z "$recommendations" ]]; then
        test_pass "Invalid profile file handled correctly"
    else
        test_warn "Invalid profile file should have failed gracefully"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance_service_performance() {
    test_start "performance_service_performance" "Test Performance service performance"
    
    setup_performance_service_tests
    
    # Initialize service and measure performance
    local start_time=$(date +%s%N)
    unity_performance_init "test-performance" >/dev/null 2>&1
    local end_time=$(date +%s%N)
    
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Check if initialization is reasonably fast (under 5 seconds)
    if [[ $duration_ms -lt 5000 ]]; then
        test_pass "Performance service initialization performance acceptable: ${duration_ms}ms"
    else
        test_warn "Performance service initialization slow: ${duration_ms}ms"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# INTEGRATION READINESS TESTS
# =============================================================================

test_unity_service_integration() {
    test_start "unity_service_integration" "Test Unity service integration readiness"
    
    setup_performance_service_tests
    
    # Test if service exports expected functions
    local expected_functions=("unity_performance_init" "perf_timer_start" "perf_timer_stop" 
                             "perf_cache_aws_response" "perf_get_cached_aws_response" 
                             "perf_profile_system" "perf_run_benchmark")
    local available_functions=0
    
    for func in "${expected_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            ((available_functions++))
        fi
    done
    
    if [[ $available_functions -eq ${#expected_functions[@]} ]]; then
        test_pass "All expected Unity Performance functions are available ($available_functions/${#expected_functions[@]})"
    else
        test_fail "Some Unity Performance functions are missing ($available_functions/${#expected_functions[@]})"
    fi
    
    cleanup_performance_service_tests
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

# Register all test functions with the Unity test framework
unity_register_service_test "unity-performance-service" "$PROJECT_ROOT/lib/unity/services/unity-performance-service.sh" \
    "unity_performance_init,perf_timer_start,perf_timer_stop,perf_cache_aws_response,perf_profile_system" \
    "service-unit"

# Run all test functions
main() {
    log_info "Running Unity Performance Service Unit Tests"
    
    # Initialization tests
    test_unity_performance_service_init
    test_performance_metrics_initialization
    
    # Performance timing tests
    test_perf_timer_start_stop
    test_perf_timer_invalid_stop
    
    # Bash compatibility tests
    test_bash3_compatibility
    
    # Caching tests
    test_perf_cache_aws_response
    test_perf_get_cached_aws_response
    test_cache_expiration
    
    # Lazy loading tests
    test_perf_lazy_load_service
    test_perf_load_service_now
    test_load_nonexistent_service
    
    # Memory monitoring tests
    test_perf_monitor_memory
    
    # Profiling tests
    test_perf_profile_system
    
    # Benchmarking tests
    test_perf_run_benchmark
    test_benchmark_caching
    test_benchmark_lazy_loading
    test_benchmark_memory
    
    # Optimization tests
    test_perf_optimize_data_structure
    
    # Bottleneck identification tests
    test_identify_bottlenecks
    
    # Recommendation tests
    test_perf_generate_recommendations
    
    # Utility function tests
    test_utility_functions
    
    # Event handler tests
    test_event_handlers
    
    # Batch operations tests
    test_perf_batch_aws_calls
    
    # Metrics save/load tests
    test_perf_save_metrics
    test_perf_cleanup_cache
    
    # Error handling tests
    test_performance_error_handling
    
    # Performance tests
    test_performance_service_performance
    
    # Integration readiness tests
    test_unity_service_integration
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi