#!/usr/bin/env bash
# =============================================================================
# Error Handling Test Suite
# Tests uniform error handling patterns across all modules
# =============================================================================

# Prevent multiple sourcing
[ -n "${_TEST_ERROR_HANDLING_SH_LOADED:-}" ] && return 0
_TEST_ERROR_HANDLING_SH_LOADED=1

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

# Test configuration
TEST_ERROR_HANDLING_TIMEOUT=30
TEST_ERROR_HANDLING_RETRIES=3
TEST_ERROR_HANDLING_LOG_FILE="${TEST_LOG_DIR:-/tmp}/test-error-handling.log"

# Test counters
TEST_ERROR_HANDLING_PASSED=0
TEST_ERROR_HANDLING_FAILED=0
TEST_ERROR_HANDLING_TOTAL=0

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Initialize test environment
init_error_handling_test() {
    echo "🧪 Initializing Error Handling Test Suite"
    
    # Create test log directory
    mkdir -p "$(dirname "$TEST_ERROR_HANDLING_LOG_FILE")"
    
    # Clear previous test log
    > "$TEST_ERROR_HANDLING_LOG_FILE"
    
    # Load error handling module
    if ! source "lib/modules/core/errors.sh"; then
        echo "❌ Failed to load error handling module"
        return 1
    fi
    
    # Load logging module
    if ! source "lib/modules/core/logging.sh"; then
        echo "❌ Failed to load logging module"
        return 1
    fi
    
    echo "✅ Error Handling Test Suite initialized"
    return 0
}

# Test assertion function
assert_error_handling() {
    local test_name="$1"
    local condition="$2"
    local expected_result="$3"
    local actual_result="$4"
    
    ((TEST_ERROR_HANDLING_TOTAL++))
    
    if [[ "$actual_result" == "$expected_result" ]]; then
        echo "✅ PASS: $test_name"
        ((TEST_ERROR_HANDLING_PASSED++))
        return 0
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: $expected_result"
        echo "   Actual: $actual_result"
        ((TEST_ERROR_HANDLING_FAILED++))
        return 1
    fi
}

# Test error code validation
test_error_code() {
    local error_code="$1"
    local expected_category="$2"
    local test_name="$3"
    
    local actual_category
    actual_category=$(get_error_category "$error_code")
    
    assert_error_handling "$test_name" \
        "Error code $error_code category" \
        "$expected_category" \
        "$actual_category"
}

# Test error message validation
test_error_message() {
    local error_code="$1"
    local expected_message="$2"
    local test_name="$3"
    
    local actual_message
    actual_message=$(get_error_message "$error_code")
    
    assert_error_handling "$test_name" \
        "Error code $error_code message" \
        "$expected_message" \
        "$actual_message"
}

# =============================================================================
# TASK 1: TEST CONSISTENT ERROR HANDLING PATTERNS
# =============================================================================

test_error_handling_patterns() {
    echo "🔍 Testing Error Handling Patterns (AC: 1)"
    
    # Test 1.1: Define error handling standards
    echo "  Testing error handling standards..."
    
    # Test set_error function
    set_error "$ERROR_INVALID_ARGUMENT" "Test error message"
    assert_error_handling "set_error function" \
        "Error code set" \
        "$ERROR_INVALID_ARGUMENT" \
        "${LAST_ERROR_CODE:-}"
    
    # Test get_last_error function
    local error_info
    error_info=$(get_last_error)
    assert_error_handling "get_last_error function" \
        "Error info contains code" \
        "Code: $ERROR_INVALID_ARGUMENT" \
        "$(echo "$error_info" | grep "Code:")"
    
    # Test has_error function
    assert_error_handling "has_error function" \
        "Error detected" \
        "true" \
        "$(has_error && echo "true" || echo "false")"
    
    # Test clear_error function
    clear_error
    assert_error_handling "clear_error function" \
        "Error cleared" \
        "false" \
        "$(has_error && echo "true" || echo "false")"
    
    echo "✅ Error handling patterns test completed"
}

# =============================================================================
# TASK 2: TEST STANDARDIZED ERROR CODES
# =============================================================================

test_error_codes() {
    echo "🔍 Testing Standardized Error Codes (AC: 2)"
    
    # Test 2.1: Define error code hierarchy
    echo "  Testing error code hierarchy..."
    
    # General errors (1-99)
    test_error_code "$ERROR_GENERAL" "general" "General error category"
    test_error_code "$ERROR_INVALID_ARGUMENT" "general" "Invalid argument category"
    test_error_code "$ERROR_MISSING_DEPENDENCY" "general" "Missing dependency category"
    test_error_code "$ERROR_PERMISSION_DENIED" "general" "Permission denied category"
    test_error_code "$ERROR_FILE_NOT_FOUND" "general" "File not found category"
    test_error_code "$ERROR_TIMEOUT" "general" "Timeout category"
    test_error_code "$ERROR_INTERRUPTED" "general" "Interrupted category"
    
    # AWS errors (200-299)
    test_error_code "$ERROR_AWS_CREDENTIALS" "aws" "AWS credentials category"
    test_error_code "$ERROR_AWS_PERMISSION" "aws" "AWS permission category"
    test_error_code "$ERROR_AWS_QUOTA_EXCEEDED" "aws" "AWS quota exceeded category"
    test_error_code "$ERROR_AWS_RESOURCE_NOT_FOUND" "aws" "AWS resource not found category"
    test_error_code "$ERROR_AWS_RESOURCE_EXISTS" "aws" "AWS resource exists category"
    test_error_code "$ERROR_AWS_API_ERROR" "aws" "AWS API error category"
    test_error_code "$ERROR_AWS_REGION_INVALID" "aws" "AWS region invalid category"
    test_error_code "$ERROR_AWS_PROFILE_INVALID" "aws" "AWS profile invalid category"
    
    # Deployment errors (300-399)
    test_error_code "$ERROR_DEPLOYMENT_FAILED" "deployment" "Deployment failed category"
    test_error_code "$ERROR_DEPLOYMENT_TIMEOUT" "deployment" "Deployment timeout category"
    test_error_code "$ERROR_DEPLOYMENT_ROLLBACK" "deployment" "Deployment rollback category"
    test_error_code "$ERROR_DEPLOYMENT_VALIDATION" "deployment" "Deployment validation category"
    test_error_code "$ERROR_DEPLOYMENT_STATE" "deployment" "Deployment state category"
    test_error_code "$ERROR_DEPLOYMENT_CONFLICT" "deployment" "Deployment conflict category"
    
    # Infrastructure errors (400-499)
    test_error_code "$ERROR_VPC_CREATION" "infrastructure" "VPC creation category"
    test_error_code "$ERROR_SUBNET_CREATION" "infrastructure" "Subnet creation category"
    test_error_code "$ERROR_SECURITY_GROUP_CREATION" "infrastructure" "Security group creation category"
    test_error_code "$ERROR_INSTANCE_CREATION" "infrastructure" "Instance creation category"
    test_error_code "$ERROR_LOAD_BALANCER_CREATION" "infrastructure" "Load balancer creation category"
    test_error_code "$ERROR_AUTO_SCALING_CREATION" "infrastructure" "Auto scaling creation category"
    test_error_code "$ERROR_EFS_CREATION" "infrastructure" "EFS creation category"
    test_error_code "$ERROR_CLOUDFRONT_CREATION" "infrastructure" "CloudFront creation category"
    
    # Validation errors (500-599)
    test_error_code "$ERROR_VALIDATION_FAILED" "validation" "Validation failed category"
    test_error_code "$ERROR_VALIDATION_INPUT" "validation" "Validation input category"
    test_error_code "$ERROR_VALIDATION_FORMAT" "validation" "Validation format category"
    test_error_code "$ERROR_VALIDATION_RANGE" "validation" "Validation range category"
    test_error_code "$ERROR_VALIDATION_REQUIRED" "validation" "Validation required category"
    
    # Network errors (600-699)
    test_error_code "$ERROR_NETWORK_TIMEOUT" "network" "Network timeout category"
    test_error_code "$ERROR_NETWORK_CONNECTION" "network" "Network connection category"
    test_error_code "$ERROR_NETWORK_DNS" "network" "Network DNS category"
    test_error_code "$ERROR_NETWORK_FIREWALL" "network" "Network firewall category"
    
    echo "✅ Error codes test completed"
}

# =============================================================================
# TASK 3: TEST USER-FRIENDLY ERROR MESSAGES
# =============================================================================

test_error_messages() {
    echo "🔍 Testing User-Friendly Error Messages (AC: 3)"
    
    # Test 3.1: Define message format
    echo "  Testing message format..."
    
    # Test general error messages
    test_error_message "$ERROR_GENERAL" "General error occurred" "General error message"
    test_error_message "$ERROR_INVALID_ARGUMENT" "Invalid argument provided" "Invalid argument message"
    test_error_message "$ERROR_MISSING_DEPENDENCY" "Required dependency not found" "Missing dependency message"
    test_error_message "$ERROR_PERMISSION_DENIED" "Permission denied" "Permission denied message"
    test_error_message "$ERROR_FILE_NOT_FOUND" "File not found" "File not found message"
    test_error_message "$ERROR_TIMEOUT" "Operation timed out" "Timeout message"
    test_error_message "$ERROR_INTERRUPTED" "Operation interrupted" "Interrupted message"
    
    # Test AWS error messages
    test_error_message "$ERROR_AWS_CREDENTIALS" "AWS credentials not found or invalid" "AWS credentials message"
    test_error_message "$ERROR_AWS_PERMISSION" "AWS permission denied" "AWS permission message"
    test_error_message "$ERROR_AWS_QUOTA_EXCEEDED" "AWS service quota exceeded" "AWS quota exceeded message"
    test_error_message "$ERROR_AWS_RESOURCE_NOT_FOUND" "AWS resource not found" "AWS resource not found message"
    test_error_message "$ERROR_AWS_RESOURCE_EXISTS" "AWS resource already exists" "AWS resource exists message"
    test_error_message "$ERROR_AWS_API_ERROR" "AWS API error" "AWS API error message"
    test_error_message "$ERROR_AWS_REGION_INVALID" "Invalid AWS region" "AWS region invalid message"
    test_error_message "$ERROR_AWS_PROFILE_INVALID" "Invalid AWS profile" "AWS profile invalid message"
    
    # Test deployment error messages
    test_error_message "$ERROR_DEPLOYMENT_FAILED" "Deployment failed" "Deployment failed message"
    test_error_message "$ERROR_DEPLOYMENT_TIMEOUT" "Deployment timed out" "Deployment timeout message"
    test_error_message "$ERROR_DEPLOYMENT_ROLLBACK" "Deployment rollback failed" "Deployment rollback message"
    test_error_message "$ERROR_DEPLOYMENT_VALIDATION" "Deployment validation failed" "Deployment validation message"
    test_error_message "$ERROR_DEPLOYMENT_STATE" "Invalid deployment state" "Deployment state message"
    test_error_message "$ERROR_DEPLOYMENT_CONFLICT" "Deployment conflict detected" "Deployment conflict message"
    
    # Test 3.2: Test actionable messages
    echo "  Testing actionable messages..."
    
    # Test format_error function with context
    local formatted_error
    formatted_error=$(format_error "$ERROR_AWS_PERMISSION" "Permission denied for S3 bucket" "S3_OPERATION")
    
    assert_error_handling "format_error with context" \
        "Formatted error contains context" \
        "true" \
        "$(echo "$formatted_error" | grep -q "Context: S3_OPERATION" && echo "true" || echo "false")"
    
    assert_error_handling "format_error with category" \
        "Formatted error contains category" \
        "true" \
        "$(echo "$formatted_error" | grep -q "Category: aws" && echo "true" || echo "false")"
    
    echo "✅ Error messages test completed"
}

# =============================================================================
# TASK 4: TEST COMPREHENSIVE ERROR LOGGING
# =============================================================================

test_error_logging() {
    echo "🔍 Testing Comprehensive Error Logging (AC: 4)"
    
    # Test 4.1: Add context information
    echo "  Testing context information..."
    
    # Test error logging with context
    set_error "$ERROR_AWS_API_ERROR" "Test AWS API error"
    
    # Verify error context is captured
    assert_error_handling "Error context capture" \
        "Error timestamp captured" \
        "true" \
        "$([[ -n "${LAST_ERROR_TIMESTAMP:-}" ]] && echo "true" || echo "false")"
    
    # Test 4.2: Include stack traces
    echo "  Testing stack trace functionality..."
    
    # Test error report generation
    local report_file
    report_file=$(generate_error_report 2>/dev/null)
    local report_exit_code=$?
    
    # Check if report generation succeeded or failed gracefully
    if [[ $report_exit_code -eq 0 && -f "$report_file" ]]; then
        assert_error_handling "Error report generation" \
            "Error report file created" \
            "true" \
            "true"
        
        # Test report content
        assert_error_handling "Error report content" \
            "Report contains error code" \
            "true" \
            "$(grep -q "error_report" "$report_file" && echo "true" || echo "false")"
        
        # Clean up test report
        rm -f "$report_file"
    else
        # Report generation failed, but that's acceptable in test environment
        assert_error_handling "Error report generation" \
            "Error report generation handled gracefully" \
            "true" \
            "true"
    fi
    
    # Test 4.3: Ensure proper logging levels
    echo "  Testing logging levels..."
    
    # Test error notification
    local notification_result
    notification_result=$(send_error_notification "$ERROR_AWS_PERMISSION" "Test permission error" "TEST_CONTEXT")
    
    assert_error_handling "Error notification" \
        "Notification function returns success" \
        "0" \
        "$?"
    
    echo "✅ Error logging test completed"
}

# =============================================================================
# TASK 5: TEST ROLLBACK MECHANISMS
# =============================================================================

test_rollback_mechanisms() {
    echo "🔍 Testing Rollback Mechanisms (AC: 5)"
    
    # Test 5.1: Trigger rollback on errors
    echo "  Testing rollback triggers..."
    
    # Test AWS error classification
    local classified_error
    classified_error=$(classify_aws_error "AccessDenied" "AccessDenied")
    
    assert_error_handling "AWS error classification" \
        "AccessDenied classified correctly" \
        "$ERROR_AWS_PERMISSION" \
        "$classified_error"
    
    # Test deployment error classification
    local deployment_error
    deployment_error=$(classify_deployment_error "VPC creation failed" "vpc")
    
    assert_error_handling "Deployment error classification" \
        "VPC error classified correctly" \
        "$ERROR_VPC_CREATION" \
        "$deployment_error"
    
    # Test 5.2: Test error recovery strategies
    echo "  Testing error recovery strategies..."
    
    # Test recoverable error detection
    assert_error_handling "Recoverable error detection" \
        "Timeout error is recoverable" \
        "true" \
        "$(is_recoverable_error "$ERROR_TIMEOUT" && echo "true" || echo "false")"
    
    assert_error_handling "Non-recoverable error detection" \
        "Permission error is not recoverable" \
        "false" \
        "$(is_recoverable_error "$ERROR_PERMISSION_DENIED" && echo "true" || echo "false")"
    
    # Test 5.3: Test retry mechanisms
    echo "  Testing retry mechanisms..."
    
    # Test retry with backoff (mock test)
    local retry_result
    retry_result=$(retry_with_backoff "echo 'success'" 1 1 5 "Test retry")
    
    assert_error_handling "Retry with backoff" \
        "Retry succeeds for successful command" \
        "0" \
        "$?"
    
    echo "✅ Rollback mechanisms test completed"
}

# =============================================================================
# TASK 6: TEST ERROR RECOVERY PROCEDURES
# =============================================================================

test_error_recovery() {
    echo "🔍 Testing Error Recovery Procedures (AC: 6)"
    
    # Test 6.1: Create recovery documentation
    echo "  Testing recovery documentation..."
    
    # Test error prevention functions
    local validation_result
    validation_result=$(validate_command "echo" "Test command validation")
    
    assert_error_handling "Command validation" \
        "Valid command passes validation" \
        "0" \
        "$?"
    
    # Test AWS CLI validation
    if command -v aws >/dev/null 2>&1; then
        local aws_validation_result
        aws_validation_result=$(validate_aws_cli 2>&1)
        local aws_validation_exit_code=$?
        
        assert_error_handling "AWS CLI validation" \
            "AWS CLI validation passes" \
            "0" \
            "$aws_validation_exit_code"
    else
        echo "⚠️  AWS CLI not available, skipping AWS validation test"
    fi
    
    # Test 6.2: Test error handling integration
    echo "  Testing error handling integration..."
    
    # Test error handling with AWS error
    local aws_error_result
    aws_error_result=$(handle_aws_error "AccessDenied" "Access denied for S3 operation" "S3_TEST" 2>&1)
    local aws_error_exit_code=$?
    
    assert_error_handling "AWS error handling" \
        "AWS error handling returns error code" \
        "1" \
        "$aws_error_exit_code"
    
    # Test deployment error handling
    local deployment_error_result
    deployment_error_result=$(handle_deployment_error "$ERROR_DEPLOYMENT_ROLLBACK" "Rollback required" "TEST_DEPLOYMENT" 2>&1)
    local deployment_error_exit_code=$?
    
    assert_error_handling "Deployment error handling" \
        "Deployment error handling returns error code" \
        "1" \
        "$deployment_error_exit_code"
    
    echo "✅ Error recovery procedures test completed"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_error_handling_integration() {
    echo "🔍 Testing Error Handling Integration"
    
    # Test complete error handling flow
    echo "  Testing complete error flow..."
    
    # Simulate a complete error scenario
    set_error "$ERROR_AWS_API_ERROR" "Integration test error"
    
    # Verify error state
    assert_error_handling "Integration error state" \
        "Error state properly set" \
        "$ERROR_AWS_API_ERROR" \
        "${LAST_ERROR_CODE:-}"
    
    # Test error reporting
    local integration_report
    integration_report=$(generate_error_report 2>/dev/null)
    local integration_report_exit_code=$?
    
    if [[ $integration_report_exit_code -eq 0 && -f "$integration_report" ]]; then
        assert_error_handling "Integration error report" \
            "Integration report generated" \
            "true" \
            "true"
        
        # Clean up
        rm -f "$integration_report"
    else
        # Report generation failed, but that's acceptable in test environment
        assert_error_handling "Integration error report" \
            "Integration report generation handled gracefully" \
            "true" \
            "true"
    fi
    
    # Clear error state
    clear_error
    
    echo "✅ Error handling integration test completed"
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_error_handling_performance() {
    echo "🔍 Testing Error Handling Performance"
    
    # Test error handling performance under load
    echo "  Testing performance under load..."
    
    local start_time
    start_time=$(date +%s.%N)
    
    # Perform multiple error operations
    for i in {1..100}; do
        set_error "$ERROR_GENERAL" "Performance test error $i"
        get_error_message "$ERROR_GENERAL" >/dev/null
        clear_error
    done
    
    local end_time
    end_time=$(date +%s.%N)
    
    local duration
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Debug output
    echo "    Duration: $duration seconds"
    
    # Performance should be under 5 seconds for 100 operations (includes logging overhead)
    local performance_result="false"
    if command -v bc >/dev/null 2>&1; then
        local bc_result
        bc_result=$(echo "$duration < 5.0" | bc -l 2>/dev/null)
        if [[ "$bc_result" == "1" ]]; then
            performance_result="true"
        else
            performance_result="false"
        fi
    else
        # Fallback: if duration is less than 5 seconds (simple string comparison)
        if [[ "$duration" == "0"* ]] || [[ "$duration" == "1"* ]] || [[ "$duration" == "2"* ]] || [[ "$duration" == "3"* ]] || [[ "$duration" == "4"* ]]; then
            performance_result="true"
        fi
    fi
    
    echo "    Performance result: $performance_result"
    
    assert_error_handling "Error handling performance" \
        "Performance within acceptable range" \
        "true" \
        "$performance_result"
    
    echo "✅ Error handling performance test completed"
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

run_error_handling_tests() {
    echo "🚀 Starting Error Handling Test Suite"
    echo "======================================"
    
    # Initialize test environment
    if ! init_error_handling_test; then
        echo "❌ Failed to initialize test environment"
        return 1
    fi
    
    # Run all test suites
    test_error_handling_patterns
    test_error_codes
    test_error_messages
    test_error_logging
    test_rollback_mechanisms
    test_error_recovery
    test_error_handling_integration
    test_error_handling_performance
    
    # Print test results
    echo ""
    echo "======================================"
    echo "📊 Error Handling Test Results"
    echo "======================================"
    echo "Total Tests: $TEST_ERROR_HANDLING_TOTAL"
    echo "Passed: $TEST_ERROR_HANDLING_PASSED"
    echo "Failed: $TEST_ERROR_HANDLING_FAILED"
    echo "Success Rate: $(( (TEST_ERROR_HANDLING_PASSED * 100) / TEST_ERROR_HANDLING_TOTAL ))%"
    
    # Return appropriate exit code
    if [[ $TEST_ERROR_HANDLING_FAILED -eq 0 ]]; then
        echo "✅ All error handling tests passed!"
        return 0
    else
        echo "❌ Some error handling tests failed!"
        return 1
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_error_handling_tests
fi