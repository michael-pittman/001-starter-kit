#!/usr/bin/env bash
# =============================================================================
# Resource Cleanup Test Suite
# Comprehensive testing for resource cleanup functionality
# =============================================================================

set -euo pipefail

# Test configuration
TEST_STACK_NAME="test-cleanup-stack"
TEST_RESOURCES_FILE="/tmp/test-resources.json"
TEST_CLEANUP_LOG="/tmp/test-cleanup.log"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Initialize test environment
init_test_environment() {
    echo "🧪 Initializing test environment..."
    
    # Create test resources file
    cat > "$TEST_RESOURCES_FILE" << EOF
{
    "cloudfront": [
        {"id": "E1234567890ABCD", "name": "test-distribution", "type": "cloudfront"}
    ],
    "alb": [
        {"id": "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-alb/1234567890abcdef", "name": "test-alb", "type": "alb"}
    ],
    "efs": [
        {"id": "fs-12345678", "name": "test-efs", "type": "efs"}
    ],
    "compute": [
        {"id": "i-1234567890abcdef0", "name": "test-instance", "type": "compute"}
    ],
    "security": [
        {"id": "sg-12345678", "name": "test-security-group", "type": "security"}
    ],
    "vpc": [
        {"id": "vpc-12345678", "name": "test-vpc", "type": "vpc"}
    ]
}
EOF
    
    echo "✅ Test environment initialized"
}

# Cleanup test environment
cleanup_test_environment() {
    echo "🧹 Cleaning up test environment..."
    
    rm -f "$TEST_RESOURCES_FILE"
    rm -f "$TEST_CLEANUP_LOG"
    
    echo "✅ Test environment cleaned up"
}

# Run test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo ""
    echo "🔍 Running test: $test_name"
    echo "----------------------------------------"
    
    ((TESTS_TOTAL++))
    
    if "$test_function"; then
        echo "✅ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo "❌ FAIL: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Assert function
assert() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if eval "$condition"; then
        return 0
    else
        echo "❌ Assertion failed: $message"
        return 1
    fi
}

# =============================================================================
# TEST CASES
# =============================================================================

# Test 1: Cleanup initialization
test_cleanup_initialization() {
    echo "Testing cleanup initialization..."
    
    # Test initialization with valid stack name
    if initialize_cleanup "$TEST_STACK_NAME" "auto"; then
        assert "[[ -f \"${CONFIG_DIR:-./config}/cleanup/${TEST_STACK_NAME}-cleanup.json\" ]]" \
               "Cleanup state file should be created"
        return 0
    else
        return 1
    fi
}

# Test 2: Resource inventory loading
test_resource_inventory_loading() {
    echo "Testing resource inventory loading..."
    
    # Mock resource inventory
    export CLEANUP_RESOURCES="i-1234567890abcdef0|compute|test-instance
sg-12345678|security|test-security-group
vpc-12345678|vpc|test-vpc"
    
    # Test loading
    if load_resource_inventory "$TEST_STACK_NAME"; then
        assert "[[ -n \"${CLEANUP_RESOURCES:-}\" ]]" \
               "Resource inventory should be loaded"
        assert "[[ \$(echo \"\$CLEANUP_RESOURCES\" | wc -l) -eq 3 ]]" \
               "Should have 3 resources loaded"
        return 0
    else
        return 1
    fi
}

# Test 3: Cleanup order validation
test_cleanup_order_validation() {
    echo "Testing cleanup order validation..."
    
    # Test cleanup order
    local expected_order="cloudfront
alb
efs
compute
security
vpc"
    
    local actual_order
    actual_order=$(get_resources_in_cleanup_order "$TEST_STACK_NAME")
    
    if [[ "$actual_order" == "$expected_order" ]]; then
        echo "✅ Cleanup order is correct"
        return 0
    else
        echo "❌ Cleanup order mismatch"
        echo "Expected: $expected_order"
        echo "Actual: $actual_order"
        return 1
    fi
}

# Test 4: Automatic cleanup execution
test_automatic_cleanup_execution() {
    echo "Testing automatic cleanup execution..."
    
    # Mock resources
    export CLEANUP_RESOURCES="i-1234567890abcdef0|compute|test-instance
sg-12345678|security|test-security-group"
    
    # Test automatic cleanup (dry run mode)
    if execute_automatic_cleanup "$TEST_STACK_NAME" "false"; then
        echo "✅ Automatic cleanup execution successful"
        return 0
    else
        echo "❌ Automatic cleanup execution failed"
        return 1
    fi
}

# Test 5: Manual cleanup execution
test_manual_cleanup_execution() {
    echo "Testing manual cleanup execution..."
    
    # Mock resources
    export CLEANUP_RESOURCES="vpc-12345678|vpc|test-vpc"
    
    # Test manual cleanup (with force flag to skip confirmation)
    if execute_manual_cleanup "$TEST_STACK_NAME" "true"; then
        echo "✅ Manual cleanup execution successful"
        return 0
    else
        echo "❌ Manual cleanup execution failed"
        return 1
    fi
}

# Test 6: Emergency cleanup execution
test_emergency_cleanup_execution() {
    echo "Testing emergency cleanup execution..."
    
    # Mock resources
    export CLEANUP_RESOURCES="i-1234567890abcdef0|compute|test-instance
sg-12345678|security|test-security-group
vpc-12345678|vpc|test-vpc"
    
    # Test emergency cleanup
    if execute_emergency_cleanup "$TEST_STACK_NAME"; then
        echo "✅ Emergency cleanup execution successful"
        return 0
    else
        echo "❌ Emergency cleanup execution failed"
        return 1
    fi
}

# Test 7: Dry run cleanup execution
test_dry_run_cleanup_execution() {
    echo "Testing dry run cleanup execution..."
    
    # Mock resources
    export CLEANUP_RESOURCES="i-1234567890abcdef0|compute|test-instance
sg-12345678|security|test-security-group"
    
    # Test dry run cleanup
    if execute_dry_run_cleanup "$TEST_STACK_NAME"; then
        echo "✅ Dry run cleanup execution successful"
        return 0
    else
        echo "❌ Dry run cleanup execution failed"
        return 1
    fi
}

# Test 8: Resource type cleanup
test_resource_type_cleanup() {
    echo "Testing resource type cleanup..."
    
    # Mock resources for compute type
    export CLEANUP_RESOURCES="i-1234567890abcdef0|compute|test-instance"
    
    # Test compute resource cleanup
    if cleanup_resource_type "$TEST_STACK_NAME" "compute" "false"; then
        echo "✅ Resource type cleanup successful"
        return 0
    else
        echo "❌ Resource type cleanup failed"
        return 1
    fi
}

# Test 9: Safe resource deletion
test_safe_resource_deletion() {
    echo "Testing safe resource deletion..."
    
    # Test safe deletion of compute resource
    if delete_resource_safely "i-1234567890abcdef0" "compute" "false"; then
        echo "✅ Safe resource deletion successful"
        return 0
    else
        echo "❌ Safe resource deletion failed"
        return 1
    fi
}

# Test 10: Force resource deletion
test_force_resource_deletion() {
    echo "Testing force resource deletion..."
    
    # Test force deletion of security group
    if force_delete_resource "sg-12345678" "security"; then
        echo "✅ Force resource deletion successful"
        return 0
    else
        echo "❌ Force resource deletion failed"
        return 1
    fi
}

# Test 11: Cleanup prerequisites validation
test_cleanup_prerequisites_validation() {
    echo "Testing cleanup prerequisites validation..."
    
    # Test prerequisites validation
    if validate_cleanup_prerequisites "$TEST_STACK_NAME"; then
        echo "✅ Cleanup prerequisites validation successful"
        return 0
    else
        echo "❌ Cleanup prerequisites validation failed"
        return 1
    fi
}

# Test 12: Cleanup finalization
test_cleanup_finalization() {
    echo "Testing cleanup finalization..."
    
    # Test cleanup finalization
    if finalize_cleanup "$TEST_STACK_NAME"; then
        echo "✅ Cleanup finalization successful"
        return 0
    else
        echo "❌ Cleanup finalization failed"
        return 1
    fi
}

# Test 13: Resource dependency checking
test_resource_dependency_checking() {
    echo "Testing resource dependency checking..."
    
    # Test dependency checking
    if check_resource_dependencies "i-1234567890abcdef0" "compute"; then
        echo "✅ Resource dependency checking successful"
        return 0
    else
        echo "❌ Resource dependency checking failed"
        return 1
    fi
}

# Test 14: Resource inventory management
test_resource_inventory_management() {
    echo "Testing resource inventory management..."
    
    # Mock resources
    export CLEANUP_RESOURCES="i-1234567890abcdef0|compute|test-instance
sg-12345678|security|test-security-group"
    
    # Test removing resource from inventory
    remove_resource_from_inventory "i-1234567890abcdef0" "compute"
    
    if [[ $(echo "$CLEANUP_RESOURCES" | wc -l) -eq 1 ]]; then
        echo "✅ Resource inventory management successful"
        return 0
    else
        echo "❌ Resource inventory management failed"
        return 1
    fi
}

# Test 15: Cleanup state management
test_cleanup_state_management() {
    echo "Testing cleanup state management..."
    
    # Test state creation
    create_cleanup_state "$TEST_STACK_NAME" "auto"
    
    if [[ -f "${CONFIG_DIR:-./config}/cleanup/${TEST_STACK_NAME}-cleanup.json" ]]; then
        echo "✅ Cleanup state management successful"
        return 0
    else
        echo "❌ Cleanup state management failed"
        return 1
    fi
}

# Test 16: Error handling in cleanup
test_error_handling_in_cleanup() {
    echo "Testing error handling in cleanup..."
    
    # Test cleanup with invalid stack name
    if ! cleanup_resources "invalid-stack" "auto"; then
        echo "✅ Error handling in cleanup successful"
        return 0
    else
        echo "❌ Error handling in cleanup failed"
        return 1
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

# Main test runner
main() {
    echo "🚀 Starting Resource Cleanup Test Suite"
    echo "========================================"
    
    # Initialize test environment
    init_test_environment
    
    # Source the cleanup module
    source "${SCRIPT_DIR:-.}/lib/modules/cleanup/resources.sh"
    
    # Run all tests
    run_test "Cleanup Initialization" test_cleanup_initialization
    run_test "Resource Inventory Loading" test_resource_inventory_loading
    run_test "Cleanup Order Validation" test_cleanup_order_validation
    run_test "Automatic Cleanup Execution" test_automatic_cleanup_execution
    run_test "Manual Cleanup Execution" test_manual_cleanup_execution
    run_test "Emergency Cleanup Execution" test_emergency_cleanup_execution
    run_test "Dry Run Cleanup Execution" test_dry_run_cleanup_execution
    run_test "Resource Type Cleanup" test_resource_type_cleanup
    run_test "Safe Resource Deletion" test_safe_resource_deletion
    run_test "Force Resource Deletion" test_force_resource_deletion
    run_test "Cleanup Prerequisites Validation" test_cleanup_prerequisites_validation
    run_test "Cleanup Finalization" test_cleanup_finalization
    run_test "Resource Dependency Checking" test_resource_dependency_checking
    run_test "Resource Inventory Management" test_resource_inventory_management
    run_test "Cleanup State Management" test_cleanup_state_management
    run_test "Error Handling in Cleanup" test_error_handling_in_cleanup
    
    # Print test results
    echo ""
    echo "📊 Test Results Summary"
    echo "======================="
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "🎉 All tests passed!"
        cleanup_test_environment
        exit 0
    else
        echo "❌ Some tests failed!"
        cleanup_test_environment
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi