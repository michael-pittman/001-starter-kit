#!/usr/bin/env bash
# =============================================================================
# AWS CLI v2 Integration Tests
# Comprehensive testing for AWS CLI v2 enhancements
# Requires: bash 5.3.3+, AWS CLI v2
# =============================================================================

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load required libraries
source "$PROJECT_ROOT/lib/modules/core/bash_version.sh"
require_bash_533 "test-aws-cli-v2.sh"

source "$PROJECT_ROOT/lib/aws-cli-v2.sh"
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

set -euo pipefail

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

# Test results tracking
TEST_RESULTS_FILE="${PROJECT_ROOT}/test-reports/aws-cli-v2-test-results-$(date +%Y%m%d-%H%M%S).json"
TEST_SUMMARY_FILE="${PROJECT_ROOT}/test-reports/aws-cli-v2-test-summary.html"
mkdir -p "$(dirname "$TEST_RESULTS_FILE")"

# Test counters
TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# Test results array
declare -a TEST_RESULTS=()

# =============================================================================
# TEST FRAMEWORK FUNCTIONS
# =============================================================================

# Run a test with proper error handling
run_test() {
    local test_name="$1"
    local test_function="$2"
    local test_category="${3:-general}"
    
    ((TEST_COUNT++))
    local test_start_time=$(date +%s)
    
    info "Running test: $test_name"
    
    local test_result="FAILED"
    local test_output=""
    local test_error=""
    
    # Capture test output and errors
    if test_output=$("$test_function" 2>&1); then
        test_result="PASSED"
        ((TEST_PASSED++))
        success "✓ $test_name"
    else
        test_error="$test_output"
        ((TEST_FAILED++))
        error "✗ $test_name"
        if [[ -n "$test_error" ]]; then
            error "Error details: $test_error"
        fi
    fi
    
    local test_end_time=$(date +%s)
    local test_duration=$((test_end_time - test_start_time))
    
    # Store test result
    local test_result_json
    test_result_json=$(jq -n \
        --arg name "$test_name" \
        --arg function "$test_function" \
        --arg category "$test_category" \
        --arg result "$test_result" \
        --arg duration "$test_duration" \
        --arg output "$test_output" \
        --arg error "$test_error" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            name: $name,
            function: $function,
            category: $category,
            result: $result,
            duration: ($duration | tonumber),
            output: $output,
            error: $error,
            timestamp: $timestamp
        }')
    
    TEST_RESULTS+=("$test_result_json")
}

# Skip a test with reason
skip_test() {
    local test_name="$1"
    local reason="${2:-No reason provided}"
    
    ((TEST_COUNT++))
    ((TEST_SKIPPED++))
    
    warning "⊘ Skipped: $test_name - $reason"
    
    # Store skipped test result
    local test_result_json
    test_result_json=$(jq -n \
        --arg name "$test_name" \
        --arg reason "$reason" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            name: $name,
            function: "skipped",
            category: "skipped",
            result: "SKIPPED",
            duration: 0,
            output: "",
            error: $reason,
            timestamp: $timestamp
        }')
    
    TEST_RESULTS+=("$test_result_json")
}

# =============================================================================
# AWS CLI V2 TESTS
# =============================================================================

# Test 1: AWS CLI v2 version detection
test_aws_cli_v2_version() {
    require_aws_cli_v2
}

# Test 2: Credential validation
test_credential_validation() {
    validate_aws_credentials "${AWS_PROFILE:-default}" "${AWS_REGION:-us-east-1}"
}

# Test 3: Region validation
test_region_validation() {
    validate_aws_region "${AWS_REGION:-us-east-1}"
}

# Test 4: Basic AWS CLI with retry
test_aws_cli_with_retry() {
    aws_cli_with_retry ec2 describe-regions --max-items 1 >/dev/null
}

# Test 5: Pagination functionality
test_pagination() {
    # Test with a service that supports pagination
    aws_paginate ec2 describe-availability-zones --max-items 2 >/dev/null
}

# Test 6: Caching functionality
test_caching() {
    # Clear any existing cache for this test
    local cache_key="ec2:describe-regions:$(echo '--max-items 1' | sha256sum | cut -d' ' -f1)"
    local cache_file="$AWS_CACHE_DIR/$(echo "$cache_key" | tr '/' '_')"
    rm -f "$cache_file"
    
    # First call should create cache
    aws_cli_cached 300 ec2 describe-regions --max-items 1 >/dev/null
    
    # Verify cache file was created
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    # Second call should use cache
    aws_cli_cached 300 ec2 describe-regions --max-items 1 >/dev/null
    
    return 0
}

# Test 7: Circuit breaker functionality
test_circuit_breaker() {
    init_circuit_breaker "test_service" 2 30
    
    # Test normal operation
    if ! check_circuit_breaker "test_service"; then
        return 1
    fi
    
    # Record success
    record_circuit_breaker_result "test_service" "true"
    
    # Verify state is still closed
    local state="${AWS_SERVICE_CIRCUIT_BREAKERS["test_service:state"]}"
    if [[ "$state" != "0" ]]; then  # CB_CLOSED = 0
        return 1
    fi
    
    return 0
}

# Test 8: Rate limiting
test_rate_limiting() {
    # Test that rate limiting doesn't prevent normal operations
    enforce_rate_limit "test_api" 10
    enforce_rate_limit "test_api" 10
    
    # Should complete without errors
    return 0
}

# Test 9: Service health check
test_service_health_check() {
    # Test a minimal health check
    aws_service_health_check "ec2"
}

# Test 10: Cache cleanup
test_cache_cleanup() {
    # Create a test cache file
    local test_cache_file="$AWS_CACHE_DIR/test_cache_file"
    mkdir -p "$AWS_CACHE_DIR"
    echo "test data" > "$test_cache_file"
    
    # Run cleanup (should not remove recent files)
    cleanup_aws_cache 7
    
    # Verify test file still exists
    if [[ ! -f "$test_cache_file" ]]; then
        return 1
    fi
    
    # Clean up
    rm -f "$test_cache_file"
    return 0
}

# Test 11: Error handling patterns
test_error_handling() {
    # Test retryable error detection
    if ! is_retryable_error "RequestLimitExceeded: Rate exceeded"; then
        return 1
    fi
    
    if is_retryable_error "UnauthorizedOperation: Access denied"; then
        return 1
    fi
    
    return 0
}

# Test 12: Exponential backoff calculation
test_exponential_backoff() {
    local delay1
    delay1=$(calculate_exponential_backoff 1 1 60)
    
    local delay2
    delay2=$(calculate_exponential_backoff 2 1 60)
    
    # Delay should increase
    if [[ $delay2 -le $delay1 ]]; then
        return 1
    fi
    
    return 0
}

# Test 13: Integration with existing libraries
test_library_integration() {
    # Test that new functions are available from aws-config.sh
    if ! declare -f set_default_configuration >/dev/null 2>&1; then
        return 1
    fi
    
    # Test that spot instance functions work
    if ! declare -f analyze_spot_pricing >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 14: SSO session handling (if applicable)
test_sso_session() {
    # This test only runs if SSO is configured
    local profile="${AWS_PROFILE:-default}"
    local sso_start_url
    sso_start_url=$(aws configure get sso_start_url --profile "$profile" 2>/dev/null || echo "")
    
    if [[ -z "$sso_start_url" ]]; then
        # Not an SSO profile, test passes
        return 0
    fi
    
    # Test SSO session refresh (non-interactive)
    refresh_aws_sso_session "$profile"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

# Integration test: Full workflow simulation
test_full_workflow_integration() {
    # Initialize AWS CLI v2 environment
    if ! init_aws_cli_v2 "${AWS_PROFILE:-default}" "${AWS_REGION:-us-east-1}"; then
        return 1
    fi
    
    # Test a series of AWS operations
    aws_cli_with_retry ec2 describe-regions --max-items 2 >/dev/null
    aws_cli_cached 300 ec2 describe-availability-zones --max-items 1 >/dev/null
    
    # Test health check
    aws_service_health_check "ec2" >/dev/null
    
    return 0
}

# Integration test: Parameter store operations
test_parameter_store_integration() {
    # Test parameter store functions work with new CLI
    local test_param="/test/aws-cli-v2-integration"
    local test_value="test-value-$(date +%s)"
    
    # Create test parameter
    if aws_cli_with_retry ssm put-parameter \
        --name "$test_param" \
        --value "$test_value" \
        --type "String" \
        --overwrite >/dev/null 2>&1; then
        
        # Verify parameter exists
        local retrieved_value
        retrieved_value=$(aws_cli_with_retry ssm get-parameter \
            --name "$test_param" \
            --query 'Parameter.Value' \
            --output text)
        
        # Clean up
        aws_cli_with_retry ssm delete-parameter --name "$test_param" >/dev/null 2>&1
        
        # Verify value matches
        if [[ "$retrieved_value" == "$test_value" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# =============================================================================
# TEST EXECUTION AND REPORTING
# =============================================================================

# Run all tests
run_all_tests() {
    log "Starting AWS CLI v2 integration tests..."
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        skip_test "ALL" "AWS CLI not installed"
        return 1
    fi
    
    # Check if we have AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        skip_test "ALL" "No valid AWS credentials found"
        return 1
    fi
    
    # Unit tests
    info "Running unit tests..."
    run_test "AWS CLI v2 Version Detection" "test_aws_cli_v2_version" "unit"
    run_test "Credential Validation" "test_credential_validation" "unit"
    run_test "Region Validation" "test_region_validation" "unit"
    run_test "AWS CLI with Retry" "test_aws_cli_with_retry" "unit"
    run_test "Pagination Functionality" "test_pagination" "unit"
    run_test "Caching Functionality" "test_caching" "unit"
    run_test "Circuit Breaker" "test_circuit_breaker" "unit"
    run_test "Rate Limiting" "test_rate_limiting" "unit"
    run_test "Service Health Check" "test_service_health_check" "unit"
    run_test "Cache Cleanup" "test_cache_cleanup" "unit"
    run_test "Error Handling" "test_error_handling" "unit"
    run_test "Exponential Backoff" "test_exponential_backoff" "unit"
    run_test "Library Integration" "test_library_integration" "unit"
    run_test "SSO Session Handling" "test_sso_session" "unit"
    
    # Integration tests
    info "Running integration tests..."
    run_test "Full Workflow Integration" "test_full_workflow_integration" "integration"
    run_test "Parameter Store Integration" "test_parameter_store_integration" "integration"
}

# Generate test report
generate_test_report() {
    log "Generating test reports..."
    
    # Create JSON report
    local test_results_json
    test_results_json=$(printf '%s\n' "${TEST_RESULTS[@]}" | jq -s '.')
    
    local report_json
    report_json=$(jq -n \
        --argjson results "$test_results_json" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg total "$TEST_COUNT" \
        --arg passed "$TEST_PASSED" \
        --arg failed "$TEST_FAILED" \
        --arg skipped "$TEST_SKIPPED" \
        '{
            metadata: {
                timestamp: $timestamp,
                total_tests: ($total | tonumber),
                passed: ($passed | tonumber),
                failed: ($failed | tonumber),
                skipped: ($skipped | tonumber),
                success_rate: (($passed | tonumber) / ($total | tonumber) * 100 | floor)
            },
            results: $results
        }')
    
    echo "$report_json" > "$TEST_RESULTS_FILE"
    
    # Generate HTML summary
    generate_html_summary
    
    success "Test reports generated:"
    info "  JSON: $TEST_RESULTS_FILE"
    info "  HTML: $TEST_SUMMARY_FILE"
}

# Generate HTML summary report
generate_html_summary() {
    cat > "$TEST_SUMMARY_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS CLI v2 Integration Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .summary { display: flex; gap: 20px; margin-bottom: 20px; }
        .metric { background: #fff; border: 1px solid #ddd; padding: 15px; border-radius: 5px; text-align: center; flex: 1; }
        .metric h3 { margin: 0 0 10px 0; }
        .metric .value { font-size: 24px; font-weight: bold; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .skipped { color: #ffc107; }
        .test-results { background: #fff; border: 1px solid #ddd; border-radius: 5px; }
        .test-result { padding: 15px; border-bottom: 1px solid #eee; }
        .test-result:last-child { border-bottom: none; }
        .test-name { font-weight: bold; margin-bottom: 5px; }
        .test-meta { font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>AWS CLI v2 Integration Test Report</h1>
        <p>Generated on: $(date)</p>
        <p>Test Environment: AWS Profile: ${AWS_PROFILE:-default}, Region: ${AWS_REGION:-us-east-1}</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Tests</h3>
            <div class="value">$TEST_COUNT</div>
        </div>
        <div class="metric">
            <h3>Passed</h3>
            <div class="value passed">$TEST_PASSED</div>
        </div>
        <div class="metric">
            <h3>Failed</h3>
            <div class="value failed">$TEST_FAILED</div>
        </div>
        <div class="metric">
            <h3>Skipped</h3>
            <div class="value skipped">$TEST_SKIPPED</div>
        </div>
        <div class="metric">
            <h3>Success Rate</h3>
            <div class="value">$(( TEST_COUNT > 0 ? TEST_PASSED * 100 / TEST_COUNT : 0 ))%</div>
        </div>
    </div>
    
    <div class="test-results">
        <h2>Test Results</h2>
EOF

    # Add individual test results
    for result in "${TEST_RESULTS[@]}"; do
        local name
        name=$(echo "$result" | jq -r '.name')
        local test_result
        test_result=$(echo "$result" | jq -r '.result')
        local duration
        duration=$(echo "$result" | jq -r '.duration')
        local category
        category=$(echo "$result" | jq -r '.category')
        local error
        error=$(echo "$result" | jq -r '.error')
        
        local result_class=""
        case "$test_result" in
            "PASSED") result_class="passed" ;;
            "FAILED") result_class="failed" ;;
            "SKIPPED") result_class="skipped" ;;
        esac
        
        cat >> "$TEST_SUMMARY_FILE" << EOF
        <div class="test-result">
            <div class="test-name $result_class">$name - $test_result</div>
            <div class="test-meta">Category: $category | Duration: ${duration}s</div>
EOF
        
        if [[ "$test_result" == "FAILED" ]] && [[ -n "$error" ]] && [[ "$error" != "null" ]]; then
            echo "            <div class="test-meta">Error: $error</div>" >> "$TEST_SUMMARY_FILE"
        fi
        
        echo "        </div>" >> "$TEST_SUMMARY_FILE"
    done
    
    cat >> "$TEST_SUMMARY_FILE" << EOF
    </div>
</body>
</html>
EOF
}

# Print test summary
print_test_summary() {
    echo
    info "=== AWS CLI v2 Integration Test Summary ==="
    info "Total Tests: $TEST_COUNT"
    success "Passed: $TEST_PASSED"
    if [[ $TEST_FAILED -gt 0 ]]; then
        error "Failed: $TEST_FAILED"
    else
        info "Failed: $TEST_FAILED"
    fi
    if [[ $TEST_SKIPPED -gt 0 ]]; then
        warning "Skipped: $TEST_SKIPPED"
    else
        info "Skipped: $TEST_SKIPPED"
    fi
    
    if [[ $TEST_COUNT -gt 0 ]]; then
        local success_rate=$((TEST_PASSED * 100 / TEST_COUNT))
        info "Success Rate: ${success_rate}%"
    fi
    echo
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "AWS CLI v2 Integration Test Suite"
    
    # Run all tests
    run_all_tests
    
    # Generate reports
    generate_test_report
    
    # Print summary
    print_test_summary
    
    # Return appropriate exit code
    if [[ $TEST_FAILED -gt 0 ]]; then
        error "Some tests failed. Check the reports for details."
        return 1
    else
        success "All tests passed successfully!"
        return 0
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
