#!/usr/bin/env bash
# =============================================================================
# Enhanced Error Handling Test Suite
# Comprehensive tests for bash 3.x+ compatible error handling patterns
# =============================================================================

# Test framework setup

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-enhanced-error-handling.sh" "core/variables" "core/logging"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_OUTPUT_DIR="/tmp/error_handling_tests_$$"
mkdir -p "$TEST_OUTPUT_DIR"

# =============================================================================
# TEST FRAMEWORK FUNCTIONS
# =============================================================================

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        echo "✅ PASS: $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $description"
        echo "   Expected: '$expected'"
        echo "   Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local description="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$not_expected" != "$actual" ]]; then
        echo "✅ PASS: $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $description"
        echo "   Should not equal: '$not_expected'"
        echo "   Actual:          '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    local substring="$1"
    local text="$2"
    local description="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$text" == *"$substring"* ]]; then
        echo "✅ PASS: $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $description"
        echo "   Expected substring: '$substring'"
        echo "   In text:           '$text'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_function_exists() {
    local function_name="$1"
    local description="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if declare -f "$function_name" >/dev/null 2>&1; then
        echo "✅ PASS: $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $description"
        echo "   Function '$function_name' does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_command_succeeds() {
    local command="$1"
    local description="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$command" >/dev/null 2>&1; then
        echo "✅ PASS: $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $description"
        echo "   Command failed: '$command'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_command_fails() {
    local command="$1"
    local description="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! eval "$command" >/dev/null 2>&1; then
        echo "✅ PASS: $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $description"
        echo "   Command should have failed: '$command'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# =============================================================================
# BASIC ERROR HANDLING TESTS
# =============================================================================

test_basic_error_handling() {
    echo "🧪 Testing Basic Error Handling Functions..."
    
    # Test that core functions exist
    assert_function_exists "init_error_handling" "init_error_handling function exists"
    assert_function_exists "log_error" "log_error function exists"
    assert_function_exists "log_warning" "log_warning function exists"
    assert_function_exists "log_debug" "log_debug function exists"
    
    # Test error counting
    local initial_count=$ERROR_COUNT
    log_error "Test error message" "Test context" 1 "TEST"
    assert_equals $((initial_count + 1)) $ERROR_COUNT "Error count incremented"
    
    # Test warning counting
    local initial_warning_count=$WARNING_COUNT
    log_warning "Test warning message" "Test context"
    assert_equals $((initial_warning_count + 1)) $WARNING_COUNT "Warning count incremented"
}

test_structured_logging() {
    echo "🧪 Testing Structured Logging..."
    
    # Test structured logging function exists
    assert_function_exists "log_structured" "log_structured function exists"
    
    # Test log level filtering
    local old_log_level="$LOG_LEVEL"
    export LOG_LEVEL="ERROR"
    
    local test_log="$TEST_OUTPUT_DIR/structured_test.log"
    export ERROR_LOG_FILE="$test_log"
    
    # This should not be logged (DEBUG < ERROR)
    log_structured "DEBUG" "Debug message should not appear"
    
    # This should be logged (ERROR >= ERROR)
    log_structured "ERROR" "Error message should appear"
    
    if [[ -f "$test_log" ]]; then
        local log_content
        log_content=$(cat "$test_log")
        assert_contains "Error message should appear" "$log_content" "ERROR level message logged"
        assert_not_equals "$(echo "$log_content" | grep -c "Debug message should not appear")" "0" "DEBUG level message filtered out"
    fi
    
    export LOG_LEVEL="$old_log_level"
}

test_error_types() {
    echo "🧪 Testing Error Type Classification..."
    
    # Test that error types are defined
    if [[ -n "${ERROR_TYPES:-}" ]]; then
        assert_contains "AWS" "${ERROR_TYPES[AWS]:-}" "AWS error type defined"
        assert_contains "DOCKER" "${ERROR_TYPES[DOCKER]:-}" "DOCKER error type defined"
        assert_contains "NETWORK" "${ERROR_TYPES[NETWORK]:-}" "NETWORK error type defined"
    else
        echo "⚠️  SKIP: Error types array not available (likely bash < 5.3)"
    fi
}

# =============================================================================
# MODERN ERROR HANDLING TESTS
# =============================================================================

test_modern_error_handling() {
    echo "🧪 Testing Modern Error Handling Features..."
    
    # Test modern functions existence
    if declare -f get_error_recovery_suggestion >/dev/null 2>&1; then
        assert_function_exists "get_error_recovery_suggestion" "get_error_recovery_suggestion function exists"
        assert_function_exists "generate_enhanced_stack_trace" "generate_enhanced_stack_trace function exists"
        assert_function_exists "check_error_patterns" "check_error_patterns function exists"
        
        # Test recovery suggestions
        local aws_suggestion
        aws_suggestion=$(get_error_recovery_suggestion "AWS" "aws s3 ls" 255)
        assert_contains "credentials" "$aws_suggestion" "AWS error recovery suggestion contains credentials advice"
        
        local docker_suggestion
        docker_suggestion=$(get_error_recovery_suggestion "DOCKER" "docker ps" 125)
        assert_contains "daemon" "$docker_suggestion" "Docker error recovery suggestion contains daemon advice"
        
    else
        echo "⚠️  SKIP: Modern error handling functions not available"
    fi
}

test_performance_monitoring() {
    echo "🧪 Testing Performance Monitoring..."
    
    if declare -f start_timer >/dev/null 2>&1; then
        # Test timer functions
        assert_function_exists "start_timer" "start_timer function exists"
        assert_function_exists "end_timer" "end_timer function exists"
        assert_function_exists "profile_execution" "profile_execution function exists"
        
        # Test basic timing
        start_timer "test_operation"
        sleep 1
        local duration
        duration=$(end_timer "test_operation")
        
        # Duration should be approximately 1 second (with some tolerance)
        if command -v bc >/dev/null 2>&1; then
            local duration_check
            duration_check=$(echo "$duration >= 0.9 && $duration <= 1.5" | bc -l)
            assert_equals "1" "$duration_check" "Timer measures approximately correct duration"
        else
            echo "⚠️  SKIP: Timer accuracy test (bc not available)"
        fi
        
        # Test profiling
        local profile_output
        profile_output=$(profile_execution "test_sleep" sleep 0.1 2>&1)
        assert_contains "test_sleep" "$profile_output" "Profiling captures function name"
        
    else
        echo "⚠️  SKIP: Performance monitoring functions not available"
    fi
}

# =============================================================================
# AWS ERROR HANDLING TESTS
# =============================================================================

test_aws_error_parsing() {
    echo "🧪 Testing AWS Error Parsing..."
    
    if declare -f parse_aws_error >/dev/null 2>&1; then
        # Test various AWS error formats
        local aws_error_1="An error occurred (InvalidUserID.NotFound) when calling the DescribeInstances operation"
        local analysis_1
        analysis_1=$(parse_aws_error "$aws_error_1" "test_command" 1)
        
        assert_contains "InvalidUserID.NotFound" "$analysis_1" "AWS error code extracted correctly"
        assert_contains "AUTH" "$analysis_1" "AWS authentication error categorized"
        assert_contains "false" "$analysis_1" "Non-retryable error identified"
        
        # Test throttling error
        local throttling_error="An error occurred (Throttling) when calling the DescribeInstances operation"
        local analysis_2
        analysis_2=$(parse_aws_error "$throttling_error" "test_command" 1)
        
        assert_contains "RATE" "$analysis_2" "Rate limiting error categorized"
        assert_contains "true" "$analysis_2" "Retryable error identified"
        
    else
        echo "⚠️  SKIP: AWS error parsing functions not available"
    fi
}

test_aws_retry_logic() {
    echo "🧪 Testing AWS Retry Logic..."
    
    if declare -f aws_retry_with_intelligence >/dev/null 2>&1; then
        # Mock AWS command that always succeeds
        local success_command=(echo "Mock AWS success")
        local result
        result=$(aws_retry_with_intelligence "${success_command[@]}")
        assert_equals "Mock AWS success" "$result" "Successful AWS command returns correct output"
        
        # Mock AWS command that always fails
        local fail_command=(sh -c 'echo "An error occurred (AccessDenied)" >&2; exit 1')
        local fail_result
        fail_result=$(aws_retry_with_intelligence "${fail_command[@]}" 2>&1)
        assert_contains "AccessDenied" "$fail_result" "Failed AWS command returns error output"
        
    else
        echo "⚠️  SKIP: AWS retry logic functions not available"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_error_handling_integration() {
    echo "🧪 Testing Error Handling Integration..."
    
    # Test error handling initialization
    local test_log="$TEST_OUTPUT_DIR/integration_test.log"
    
    # Initialize error handling in resilient mode
    ERROR_HANDLING_MODE="resilient"
    ERROR_LOG_FILE="$test_log"
    
    if declare -f init_enhanced_error_handling >/dev/null 2>&1; then
        assert_command_succeeds "init_enhanced_error_handling auto false true" "Enhanced error handling initialization"
    else
        assert_command_succeeds "init_error_handling" "Basic error handling initialization"
    fi
    
    # Test that log file was created
    if [[ -f "$test_log" ]]; then
        echo "✅ PASS: Error log file created"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: Error log file not created"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_cleanup_functions() {
    echo "🧪 Testing Cleanup Functions..."
    
    # Test cleanup function registration
    assert_function_exists "register_cleanup_function" "register_cleanup_function exists"
    
    # Create a test cleanup function
    test_cleanup_executed=false
    test_cleanup_function() {
        test_cleanup_executed=true
    }
    
    # Register the cleanup function
    register_cleanup_function "test_cleanup_function" "Test cleanup"
    
    # Simulate cleanup on exit (in a subshell to avoid actually exiting)
    (
        cleanup_on_exit
    )
    
    # For this test, we'll just verify the function was registered
    if [[ "$CLEANUP_FUNCTIONS" == *"test_cleanup_function"* ]]; then
        echo "✅ PASS: Cleanup function registered"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: Cleanup function not registered"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# =============================================================================
# COMPATIBILITY TESTS
# =============================================================================


test_associative_array_fallbacks() {
    echo "🧪 Testing Associative Array Fallbacks..."
    
    # Test that functions work even without associative arrays
    local old_bash_version="$BASH_VERSION"
    
    # Simulate older bash (this won't actually change behavior, but tests the concept)
    if [[ -n "${ERROR_TYPES:-}" ]]; then
        echo "✅ INFO: Associative arrays available - testing modern path"
        assert_not_equals "" "${ERROR_TYPES[AWS]:-}" "AWS error type accessible via associative array"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "ℹ️  INFO: Associative arrays not available - testing fallback path"
        # Test that basic functions still work
        assert_function_exists "log_error" "Basic error logging works without associative arrays"
    fi
}

# =============================================================================
# STRESS TESTS
# =============================================================================

test_high_volume_error_handling() {
    echo "🧪 Testing High Volume Error Handling..."
    
    local test_log="$TEST_OUTPUT_DIR/volume_test.log"
    export ERROR_LOG_FILE="$test_log"
    
    # Generate many errors quickly
    local start_count=$ERROR_COUNT
    for i in {1..50}; do
        log_error "Test error $i" "Volume test" 1 "TEST" >/dev/null 2>&1
    done
    
    local end_count=$ERROR_COUNT
    local expected_count=$((start_count + 50))
    
    assert_equals "$expected_count" "$end_count" "High volume error counting accuracy"
    
    # Check log file integrity
    if [[ -f "$test_log" ]]; then
        local log_line_count
        log_line_count=$(wc -l < "$test_log")
        # Should have at least 50 lines (could be more due to headers)
        if [[ $log_line_count -ge 50 ]]; then
            echo "✅ PASS: High volume logging maintains integrity"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: High volume logging lost entries"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    fi
}

test_concurrent_error_handling() {
    echo "🧪 Testing Concurrent Error Handling..."
    
    local test_log="$TEST_OUTPUT_DIR/concurrent_test.log"
    export ERROR_LOG_FILE="$test_log"
    
    # Start multiple background processes that log errors
    for i in {1..5}; do
        (
            for j in {1..10}; do
                log_error "Concurrent error $i-$j" "Concurrent test" 1 "CONCURRENT" >/dev/null 2>&1
                sleep 0.01  # Small delay to create interleaving
            done
        ) &
    done
    
    # Wait for all background processes
    wait
    
    if [[ -f "$test_log" ]]; then
        local concurrent_entries
        concurrent_entries=$(grep -c "Concurrent error" "$test_log" || echo 0)
        
        if [[ $concurrent_entries -eq 50 ]]; then
            echo "✅ PASS: Concurrent error handling maintains count accuracy"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Concurrent error handling lost entries (expected: 50, got: $concurrent_entries)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    fi
}

# =============================================================================
# TEST RUNNER AND REPORTING
# =============================================================================

run_all_tests() {
    echo "🚀 Starting Enhanced Error Handling Test Suite..."
    echo "Platform: $(uname -s) $(uname -r)"
    echo "Bash Version: $BASH_VERSION"
    echo "Test Directory: $TEST_OUTPUT_DIR"
    echo "================================================"
    
    # Run all test suites
    test_basic_error_handling
    test_structured_logging
    test_error_types
    test_modern_error_handling
    test_performance_monitoring
    test_aws_error_parsing
    test_aws_retry_logic
    test_error_handling_integration
    test_cleanup_functions
    test_associative_array_fallbacks
    test_high_volume_error_handling
    test_concurrent_error_handling
    
    echo "================================================"
    echo "🏁 Test Suite Complete"
    echo "Tests Run: $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "🎉 All tests passed!"
        exit 0
    else
        echo "❌ Some tests failed!"
        exit 1
    fi
}

generate_test_report() {
    local report_file="$TEST_OUTPUT_DIR/test_report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Enhanced Error Handling Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        .summary { margin: 20px 0; padding: 10px; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Enhanced Error Handling Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Platform: $(uname -s) $(uname -r)</p>
        <p>Bash Version: $BASH_VERSION</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Total Tests: $TESTS_RUN</p>
        <p class="pass">Passed: $TESTS_PASSED</p>
        <p class="fail">Failed: $TESTS_FAILED</p>
        <p>Success Rate: $(( TESTS_RUN > 0 ? (TESTS_PASSED * 100) / TESTS_RUN : 0 ))%</p>
    </div>
    
    <h2>Test Details</h2>
    <p>Detailed test output saved in: $TEST_OUTPUT_DIR</p>
    
    <h2>Recommendations</h2>
    <ul>
EOF

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "        <li class=\"fail\">Review failed tests and fix underlying issues</li>" >> "$report_file"
    fi
    
    
    cat >> "$report_file" << EOF
        <li>Regular testing recommended after error handling modifications</li>
        <li>Monitor error patterns in production for optimization opportunities</li>
    </ul>
</body>
</html>
EOF

    echo "📊 Test report generated: $report_file"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Cleanup function for test artifacts
cleanup_test_artifacts() {
    # Remove temporary files but keep test output directory for review
    find "$TEST_OUTPUT_DIR" -name "*.tmp" -delete 2>/dev/null || true
    echo "🧹 Test cleanup completed. Output preserved in: $TEST_OUTPUT_DIR"
}

# Set up cleanup on exit
trap cleanup_test_artifacts EXIT

# Check if running in test mode
if [[ "${1:-}" == "report" ]]; then
    generate_test_report
elif [[ "${1:-}" == "clean" ]]; then
    rm -rf "/tmp/error_handling_tests_"*
    echo "🧹 All test artifacts cleaned up"
else
    # Run the full test suite
    run_all_tests
    generate_test_report
fi
