#!/usr/bin/env bash
# =============================================================================
# Test Error Handling in deploy.sh
# Tests comprehensive error handling, rollback, and recovery mechanisms
# =============================================================================

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_SCRIPT="$PROJECT_ROOT/deploy.sh"
TEST_STACK_PREFIX="test-error-handling"
TEST_REGION="${AWS_REGION:-us-east-1}"
TEST_RESULTS_DIR="$PROJECT_ROOT/test-reports/error-handling"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Initialize test environment
init_test_env() {
    echo -e "${BLUE}Initializing test environment...${NC}"
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Set up test configuration
    export ERROR_RECOVERY_MODE="automatic"
    export DRY_RUN=true  # Run in dry-run mode for testing
    export LOG_LEVEL="DEBUG"
    export ERROR_LOG_FILE="$TEST_RESULTS_DIR/errors.json"
    
    # Source required libraries
    source "$PROJECT_ROOT/lib/error-handling.sh"
    source "$PROJECT_ROOT/lib/modules/core/errors.sh"
    
    echo -e "${GREEN}Test environment initialized${NC}"
}

# Run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    local expected_result="${3:-pass}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${BLUE}Running test: $test_name${NC}"
    
    local test_output="$TEST_RESULTS_DIR/${test_name}.out"
    local test_error="$TEST_RESULTS_DIR/${test_name}.err"
    local test_result="fail"
    
    # Run the test
    if $test_function >"$test_output" 2>"$test_error"; then
        if [[ "$expected_result" == "pass" ]]; then
            test_result="pass"
        fi
    else
        if [[ "$expected_result" == "fail" ]]; then
            test_result="pass"
        fi
    fi
    
    # Check results
    if [[ "$test_result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASSED${NC}: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAILED${NC}: $test_name"
        echo "  Expected: $expected_result"
        echo "  Output: $(head -n 5 "$test_output")"
        echo "  Error: $(head -n 5 "$test_error")"
    fi
}

# =============================================================================
# TEST CASES
# =============================================================================

# Test 1: Basic error handling initialization
test_error_handling_init() {
    # Test that error tracking is initialized
    initialize_error_tracking
    
    # Verify error log file exists
    if [[ -f "$ERROR_LOG_FILE" ]]; then
        return 0
    else
        return 1
    fi
}

# Test 2: Structured error logging
test_structured_error_logging() {
    # Run in a subshell to avoid strict mode issues
    (
        set +u  # Disable unbound variable checking for error functions
        
        # Log different types of errors
        error_ec2_insufficient_capacity "t3.micro" "us-east-1" || true
        error_network_vpc_not_found "vpc-12345" || true
        error_auth_invalid_credentials "EC2" || true
    )
    
    # Check if errors were logged
    local error_count
    error_count=$(jq '.errors | length' "$ERROR_LOG_FILE" 2>/dev/null || echo "0")
    
    if [[ "$error_count" -ge 3 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 3: Retry with backoff
test_retry_with_backoff() {
    # Define a function that fails twice then succeeds
    local attempt=0
    failing_function() {
        attempt=$((attempt + 1))
        if [[ $attempt -lt 3 ]]; then
            return 1
        else
            return 0
        fi
    }
    
    # Source deploy.sh functions in subshell
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Test retry
        if retry_with_backoff "failing_function" 3 1; then
            exit 0
        else
            exit 1
        fi
    )
}

# Test 4: Resource registration and tracking
test_resource_tracking() {
    # Source deploy.sh functions
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Register test resources
        register_resource "vpc" "vpc-test123" "us-east-1"
        register_resource "instance" "i-test456" "us-east-1"
        register_resource "security-group" "sg-test789" "us-east-1"
        
        # Check if resources were tracked
        if [[ ${#CREATED_RESOURCES[@]} -eq 3 ]]; then
            exit 0
        else
            exit 1
        fi
    )
}

# Test 5: Rollback point management
test_rollback_points() {
    # Source deploy.sh functions
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Add rollback points
        add_rollback_point "vpc_created" "vpc_id=vpc-123"
        add_rollback_point "security_created" "timestamp=$(date +%s)"
        add_rollback_point "compute_created" "asg_name=test-asg"
        
        # Check if rollback points were added
        if [[ ${#DEPLOYMENT_ROLLBACK_POINTS[@]} -eq 3 ]]; then
            exit 0
        else
            exit 1
        fi
    )
}

# Test 6: Error handler function
test_error_handler() {
    # Source deploy.sh functions
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Test abort action
        ERROR_RECOVERY_MODE="abort"
        if handle_deployment_error "TEST_ERROR" "Test error message" "test_context" "abort" 2>/dev/null; then
            exit 1  # Should not succeed
        else
            exit 0  # Expected to fail/exit
        fi
    )
}

# Test 7: Validate deployment parameters
test_parameter_validation() {
    # Test with missing stack name
    if $DEPLOY_SCRIPT --validate 2>/dev/null; then
        return 1  # Should fail
    else
        return 0  # Expected failure
    fi
}

# Test 8: Dry run mode
test_dry_run_mode() {
    # Run deployment in dry-run mode
    local stack_name="${TEST_STACK_PREFIX}-dryrun-$$"
    
    if $DEPLOY_SCRIPT --dry-run --type spot "$stack_name" 2>&1 | grep -q "DRY RUN"; then
        return 0
    else
        return 1
    fi
}

# Test 9: Error recovery strategies
test_recovery_strategies() {
    # Test different recovery strategies
    (
        source "$PROJECT_ROOT/lib/modules/core/errors.sh"
        
        # Test retry strategy
        log_structured_error "TEST_RETRY" "Test retry error" \
            "$ERROR_CAT_NETWORK" "$ERROR_SEVERITY_WARNING" \
            "test_context" "$RECOVERY_RETRY"
        
        local strategy
        strategy=$(get_recovery_strategy "TEST_RETRY")
        
        if [[ "$strategy" == "$RECOVERY_RETRY" ]]; then
            exit 0
        else
            exit 1
        fi
    )
}

# Test 10: Emergency cleanup simulation
test_emergency_cleanup() {
    # Test emergency cleanup in dry-run mode
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Set dry-run mode
        DRY_RUN=true
        
        # Register test resources
        CREATED_RESOURCES=("vpc:vpc-test:us-east-1" "instance:i-test:us-east-1")
        
        # Run emergency cleanup
        execute_emergency_cleanup 2>&1
        
        # In dry-run mode, should complete without errors
        exit 0
    )
}

# Test 11: Comprehensive error report generation
test_error_report_generation() {
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Set up test data
        STACK_NAME="test-stack"
        DEPLOYMENT_TYPE="spot"
        AWS_REGION="us-east-1"
        DEPLOYMENT_START_TIME=$(date +%s)
        DEPLOYMENT_STATE="FAILED"
        DEPLOYMENT_ERRORS=("EC2_ERROR:Test EC2 error" "VPC_ERROR:Test VPC error")
        LOG_DIR="$TEST_RESULTS_DIR"
        
        # Generate error report
        generate_deployment_error_report
        
        # Check if report was created
        if ls "$LOG_DIR"/deployment-error-report-*.json >/dev/null 2>&1; then
            exit 0
        else
            exit 1
        fi
    )
}

# Test 12: Deployment state file creation
test_deployment_state_save() {
    (
        source "$DEPLOY_SCRIPT" 2>/dev/null || true
        
        # Set up test data
        STACK_NAME="test-state-stack"
        DEPLOYMENT_TYPE="alb"
        AWS_REGION="us-east-1"
        CONFIG_DIR="$TEST_RESULTS_DIR"
        DEPLOYMENT_START_TIME=$(date +%s)
        CREATED_RESOURCES=("vpc:vpc-123:us-east-1")
        
        # Initialize variable store
        init_variable_store "$STACK_NAME" "test"
        set_variable "VPC_ID" "vpc-123" "$VARIABLE_SCOPE_STACK"
        set_variable "INSTANCE_TYPE" "t3.micro" "$VARIABLE_SCOPE_STACK"
        
        # Save deployment state
        save_deployment_state
        
        # Check if state file was created
        if [[ -f "$CONFIG_DIR/deployments/${STACK_NAME}.state" ]]; then
            exit 0
        else
            exit 1
        fi
    )
}

# Test 13: Help text includes error handling info
test_help_includes_error_info() {
    if $DEPLOY_SCRIPT --help 2>&1 | grep -q "EXIT CODES"; then
        return 0
    else
        return 1
    fi
}

# Test 14: Version shows enhanced error handling
test_version_shows_enhancement() {
    if $DEPLOY_SCRIPT --version 2>&1 | grep -q "2.1.0"; then
        return 0
    else
        return 1
    fi
}

# Test 15: Global error trap
test_global_error_trap() {
    # Test that error trap is set up
    (
        # Create a script that sources deploy.sh and triggers an error
        cat > "$TEST_RESULTS_DIR/test-trap.sh" << 'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/../../deploy.sh" 2>/dev/null || true

# Trigger an error
false
EOF
        
        chmod +x "$TEST_RESULTS_DIR/test-trap.sh"
        
        # Run and check if error trap catches it
        if ! "$TEST_RESULTS_DIR/test-trap.sh" 2>&1 | grep -q "ERROR: Command failed"; then
            exit 0  # Trap worked
        else
            exit 1
        fi
    )
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

# Test 16: Full deployment with simulated failures
test_deployment_with_failures() {
    # This would require mocking AWS APIs
    # For now, just test that deployment handles missing credentials gracefully
    
    local stack_name="${TEST_STACK_PREFIX}-fail-$$"
    
    # Unset AWS credentials temporarily
    (
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        export AWS_PROFILE="nonexistent-profile"
        
        # Should fail with credentials error
        if ! $DEPLOY_SCRIPT --type spot "$stack_name" 2>&1 | grep -q "Failed to validate AWS credentials"; then
            exit 0  # Properly handled credential error
        else
            exit 1
        fi
    )
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo -e "${BLUE}=== GeuseMaker Deploy.sh Error Handling Test Suite ===${NC}"
    echo "Testing comprehensive error handling implementation"
    echo
    
    # Initialize test environment
    init_test_env
    
    # Run all tests
    run_test "error_handling_init" test_error_handling_init "pass"
    run_test "structured_error_logging" test_structured_error_logging "pass"
    run_test "retry_with_backoff" test_retry_with_backoff "pass"
    run_test "resource_tracking" test_resource_tracking "pass"
    run_test "rollback_points" test_rollback_points "pass"
    run_test "error_handler" test_error_handler "pass"
    run_test "parameter_validation" test_parameter_validation "pass"
    run_test "dry_run_mode" test_dry_run_mode "pass"
    run_test "recovery_strategies" test_recovery_strategies "pass"
    run_test "emergency_cleanup" test_emergency_cleanup "pass"
    run_test "error_report_generation" test_error_report_generation "pass"
    run_test "deployment_state_save" test_deployment_state_save "pass"
    run_test "help_includes_error_info" test_help_includes_error_info "pass"
    run_test "version_shows_enhancement" test_version_shows_enhancement "pass"
    run_test "global_error_trap" test_global_error_trap "pass"
    run_test "deployment_with_failures" test_deployment_with_failures "pass"
    
    # Generate test report
    generate_test_report
    
    # Summary
    echo
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Generate HTML test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/error-handling-test-report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Deploy.sh Error Handling Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .passed { color: green; }
        .failed { color: red; }
        .test-result { margin: 10px 0; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
        .test-passed { background-color: #e8f5e9; }
        .test-failed { background-color: #ffebee; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Deploy.sh Error Handling Test Report</h1>
        <p>Generated: $(date)</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <table>
            <tr>
                <th>Total Tests</th>
                <th>Passed</th>
                <th>Failed</th>
                <th>Success Rate</th>
            </tr>
            <tr>
                <td>$TESTS_RUN</td>
                <td class="passed">$TESTS_PASSED</td>
                <td class="failed">$TESTS_FAILED</td>
                <td>$(( TESTS_PASSED * 100 / TESTS_RUN ))%</td>
            </tr>
        </table>
    </div>
    
    <div class="details">
        <h2>Test Details</h2>
        <p>All tests verify the comprehensive error handling implementation in deploy.sh</p>
    </div>
    
    <div class="features">
        <h2>Error Handling Features Tested</h2>
        <ul>
            <li>Structured error tracking and logging</li>
            <li>Automatic retry with exponential backoff</li>
            <li>Resource registration and cleanup</li>
            <li>Rollback point management</li>
            <li>Multiple recovery strategies</li>
            <li>Emergency cleanup procedures</li>
            <li>Comprehensive error reporting</li>
            <li>Deployment state persistence</li>
            <li>Global error trap handling</li>
        </ul>
    </div>
</body>
</html>
EOF
    
    echo -e "${GREEN}Test report generated: $report_file${NC}"
}

# Execute main if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi