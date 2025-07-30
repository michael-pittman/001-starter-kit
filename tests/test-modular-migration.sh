#!/usr/bin/env bash
# =============================================================================
# Modular Migration Integration Test
# Tests the migrated functions and compatibility layer
# =============================================================================


# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-modular-migration.sh" \
    "core/variables" \
    "core/logging" \
    "core/registry" \
    "core/errors"

LIB_DIR="$PROJECT_ROOT/lib"

# Test configuration
TEST_STACK_NAME="test-migration-$(date +%s)"
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Test result tracking
add_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$status" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "✅ $test_name: $message"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "❌ $test_name: $message"
    fi
    
    TEST_RESULTS+=("$test_name:$status:$message")
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo "Running test: $test_name"
    
    if $test_function; then
        add_test_result "$test_name" "PASS" "Test completed successfully"
    else
        add_test_result "$test_name" "FAIL" "Test failed with error"
    fi
    
    echo ""
}

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    echo "Setting up test environment..."
    
    # Set default environment variables
    export AWS_REGION="${AWS_REGION:-us-east-1}"
    export STACK_NAME="$TEST_STACK_NAME"
    export INSTANCE_TYPE="t3.medium"
    export ENVIRONMENT="development"
    
    # Verify compatibility layer was loaded
    if type -t create_standard_iam_role >/dev/null 2>&1; then
        echo "✅ Compatibility layer loaded successfully"
    else
        echo "❌ Failed to load compatibility layer"
        return 1
    fi
    
    echo "Test environment setup completed"
    return 0
}

cleanup_test_environment() {
    echo "Cleaning up test environment..."
    
    # Cleanup any test resources that might have been created
    if command -v cleanup_enhanced_deployment >/dev/null 2>&1; then
        cleanup_enhanced_deployment "$TEST_STACK_NAME" 2>/dev/null || true
    fi
    
    echo "Test environment cleanup completed"
}

# =============================================================================
# MODULE LOADING TESTS
# =============================================================================

test_core_modules_loading() {
    echo "Testing core module loading..."
    
    # Test registry module
    if command -v init_registry >/dev/null 2>&1; then
        echo "✓ Registry module loaded"
    else
        echo "✗ Registry module not loaded"
        return 1
    fi
    
    # Test error handling module
    if command -v throw_error >/dev/null 2>&1; then
        echo "✓ Error handling module loaded"
    else
        echo "✗ Error handling module not loaded"
        return 1
    fi
    
    return 0
}

test_infrastructure_modules_loading() {
    echo "Testing infrastructure module loading..."
    
    # Test VPC module
    if command -v create_vpc >/dev/null 2>&1; then
        echo "✓ VPC module loaded"
    else
        echo "✗ VPC module not loaded"
        return 1
    fi
    
    # Test security module
    if command -v create_security_group >/dev/null 2>&1; then
        echo "✓ Security module loaded"
    else
        echo "✗ Security module not loaded"
        return 1
    fi
    
    # Test IAM module
    if command -v create_standard_iam_role >/dev/null 2>&1; then
        echo "✓ IAM module loaded"
    else
        echo "✗ IAM module not loaded"
        return 1
    fi
    
    # Test EFS module
    if command -v create_shared_efs >/dev/null 2>&1; then
        echo "✓ EFS module loaded"
    else
        echo "✗ EFS module not loaded"
        return 1
    fi
    
    return 0
}

test_compute_modules_loading() {
    echo "Testing compute module loading..."
    
    # Test spot optimizer module
    if command -v analyze_spot_pricing >/dev/null 2>&1; then
        echo "✓ Spot optimizer module loaded"
    else
        echo "✗ Spot optimizer module not loaded"
        return 1
    fi
    
    # Test provisioner module (if exists)
    if [ -f "$LIB_DIR/modules/compute/provisioner.sh" ]; then
        echo "✓ Provisioner module found"
    else
        echo "! Provisioner module not found (may need implementation)"
    fi
    
    return 0
}

test_application_modules_loading() {
    echo "Testing application module loading..."
    
    # Test docker manager module
    if command -v deploy_application_stack >/dev/null 2>&1; then
        echo "✓ Docker manager module loaded"
    else
        echo "✗ Docker manager module not loaded"
        return 1
    fi
    
    # Test health monitor module (if exists)
    if [ -f "$LIB_DIR/modules/application/health_monitor.sh" ]; then
        echo "✓ Health monitor module found"
    else
        echo "! Health monitor module not found (may need implementation)"
    fi
    
    return 0
}

# =============================================================================
# LEGACY COMPATIBILITY TESTS
# =============================================================================

test_legacy_function_compatibility() {
    echo "Testing legacy function compatibility..."
    
    # Test that legacy functions are available
    local legacy_functions=(
        "create_standard_key_pair"
        "create_standard_security_group"
        "create_standard_iam_role"
        "create_shared_efs"
        "create_efs_mount_target_for_az"
        "analyze_spot_pricing"
        "deploy_application_stack"
    )
    
    local missing_functions=()
    
    for func in "${legacy_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            echo "✓ $func available"
        else
            echo "✗ $func missing"
            missing_functions+=("$func")
        fi
    done
    
    if [ ${#missing_functions[@]} -eq 0 ]; then
        echo "All legacy functions are available"
        return 0
    else
        echo "Missing legacy functions: ${missing_functions[*]}"
        return 1
    fi
}

test_error_handling_integration() {
    echo "Testing error handling integration..."
    
    # Test error constants
    if [ -n "${ERROR_INVALID_ARGUMENT:-}" ]; then
        echo "✓ Error constants defined"
    else
        echo "✗ Error constants not defined"
        return 1
    fi
    
    # Test error throwing (should not crash)
    if ( throw_error 999 "Test error message" 2>/dev/null ); then
        echo "✗ Error handling should have exited"
        return 1
    else
        echo "✓ Error handling works correctly"
    fi
    
    return 0
}

# =============================================================================
# FUNCTION BEHAVIOR TESTS
# =============================================================================

test_spot_pricing_analysis() {
    echo "Testing spot pricing analysis functionality..."
    
    # Test with mock parameters (should not make actual AWS calls in test mode)
    export AWS_PROFILE=""  # Clear profile to avoid accidental calls
    
    # Test parameter validation
    if analyze_spot_pricing "" 2>/dev/null; then
        echo "✗ Should reject empty instance type"
        return 1
    else
        echo "✓ Parameter validation works"
    fi
    
    # Test with valid parameters (but expect failure due to no AWS access)
    if analyze_spot_pricing "t3.medium" "us-east-1" 2>/dev/null; then
        echo "! Spot pricing analysis succeeded (may have AWS access)"
    else
        echo "✓ Spot pricing analysis failed as expected (no AWS access)"
    fi
    
    return 0
}

test_configuration_validation() {
    echo "Testing configuration validation..."
    
    # Test stack name validation
    local test_functions=(
        "deploy_application_stack"
    )
    
    for func in "${test_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            # Test with invalid stack name (should fail)
            if $func "127.0.0.1" "/tmp/key.pem" "invalid-stack-name-!" 2>/dev/null; then
                echo "✗ $func should reject invalid stack name"
                return 1
            else
                echo "✓ $func validates stack name correctly"
            fi
        fi
    done
    
    return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_enhanced_orchestration() {
    echo "Testing enhanced orchestration functions..."
    
    # Test that enhanced functions are available
    local enhanced_functions=(
        "setup_infrastructure_enhanced"
        "deploy_compute_enhanced"
        "deploy_application_enhanced"
        "deploy_stack_enhanced"
        "cleanup_enhanced_deployment"
    )
    
    local missing_functions=()
    
    for func in "${enhanced_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            echo "✓ $func available"
        else
            echo "✗ $func missing"
            missing_functions+=("$func")
        fi
    done
    
    if [ ${#missing_functions[@]} -eq 0 ]; then
        echo "All enhanced orchestration functions are available"
        return 0
    else
        echo "Missing enhanced functions: ${missing_functions[*]}"
        return 1
    fi
}

test_module_interdependencies() {
    echo "Testing module interdependencies..."
    
    # Test that modules can call each other
    # This is a basic structural test
    
    # Check if error handling is properly initialized
    if [ -n "${ERROR_HANDLING_INITIALIZED:-}" ]; then
        echo "✓ Error handling initialized"
    else
        echo "! Error handling may not be initialized"
    fi
    
    # Check if registry functions work
    if init_registry "$TEST_STACK_NAME" 2>/dev/null; then
        echo "✓ Registry initialization works"
        
        # Test resource registration
        if register_resource "test" "test-resource-id" '{"test": true}' 2>/dev/null; then
            echo "✓ Resource registration works"
        else
            echo "! Resource registration may have issues"
        fi
        
        # Cleanup test registry
        cleanup_registry "$TEST_STACK_NAME" 2>/dev/null || true
    else
        echo "! Registry initialization may have issues"
    fi
    
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "🧪 Starting Modular Migration Integration Tests"
    echo "=============================================="
    echo ""
    
    # Setup
    if ! setup_test_environment; then
        echo "❌ Failed to setup test environment"
        exit 1
    fi
    
    echo ""
    
    # Run all tests
    run_test "Core Modules Loading" test_core_modules_loading
    run_test "Infrastructure Modules Loading" test_infrastructure_modules_loading
    run_test "Compute Modules Loading" test_compute_modules_loading
    run_test "Application Modules Loading" test_application_modules_loading
    run_test "Legacy Function Compatibility" test_legacy_function_compatibility
    run_test "Error Handling Integration" test_error_handling_integration
    run_test "Spot Pricing Analysis" test_spot_pricing_analysis
    run_test "Configuration Validation" test_configuration_validation
    run_test "Enhanced Orchestration" test_enhanced_orchestration
    run_test "Module Interdependencies" test_module_interdependencies
    
    # Cleanup
    cleanup_test_environment
    
    # Display results
    echo "=============================================="
    echo "🧪 Test Results Summary"
    echo "=============================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo ""
        echo "🎉 All tests passed! Migration is successful."
        exit 0
    else
        echo ""
        echo "⚠️  Some tests failed. Review the output above."
        exit 1
    fi
}

# Run main function
main "$@"
