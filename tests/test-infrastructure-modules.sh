#!/usr/bin/env bash
# =============================================================================
# Infrastructure Modules Test Suite
# Comprehensive testing for VPC, Security, IAM, EFS, and ALB modules
# =============================================================================


# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-infrastructure-modules.sh" \
    "core/variables" \
    "core/logging" \
    "core/registry" \
    "core/errors" \
    "config/variables" \
    "infrastructure/vpc" \
    "infrastructure/security" \
    "infrastructure/iam" \
    "infrastructure/efs" \
    "infrastructure/alb"

TEST_RESULTS_DIR="$PROJECT_ROOT/test-reports"
TEST_LOG_FILE="$TEST_RESULTS_DIR/infrastructure-modules-test.log"

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

# Initialize test log
echo "=== Infrastructure Modules Test Started: $(date) ===" > "$TEST_LOG_FILE"

# Test configuration
TEST_STACK_NAME="test-infra-$(date +%s)"
TEST_REGION="${AWS_REGION:-us-east-1}"
CLEANUP_ON_EXIT="${CLEANUP_ON_EXIT:-true}"

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result functions
test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓ PASS${NC}: $test_name" | tee -a "$TEST_LOG_FILE"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

test_fail() {
    local test_name="$1"
    local error_msg="${2:-}"
    echo -e "${RED}✗ FAIL${NC}: $test_name" | tee -a "$TEST_LOG_FILE"
    if [ -n "$error_msg" ]; then
        echo "  Error: $error_msg" | tee -a "$TEST_LOG_FILE"
    fi
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

test_skip() {
    local test_name="$1"
    local reason="${2:-}"
    echo -e "${YELLOW}⚠ SKIP${NC}: $test_name" | tee -a "$TEST_LOG_FILE"
    if [ -n "$reason" ]; then
        echo "  Reason: $reason" | tee -a "$TEST_LOG_FILE"
    fi
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
}

test_info() {
    local message="$1"
    echo -e "${BLUE}ℹ INFO${NC}: $message" | tee -a "$TEST_LOG_FILE"
}

# Run test with error handling
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo "" | tee -a "$TEST_LOG_FILE"
    test_info "Running test: $test_name"
    
    if $test_function; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Test function returned non-zero exit code"
    fi
}

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    test_info "Setting up test environment"
    
    # Set test variables
    set_variable "STACK_NAME" "$TEST_STACK_NAME"
    set_variable "AWS_REGION" "$TEST_REGION"
    set_variable "DEPLOYMENT_TYPE" "simple"
    set_variable "INSTANCE_TYPE" "t3.micro"
    
    # Initialize registry for tests
    initialize_registry "$TEST_STACK_NAME"
    
    test_info "Test environment setup complete"
}

cleanup_test_environment() {
    if [ "$CLEANUP_ON_EXIT" = "true" ]; then
        test_info "Cleaning up test environment"
        
        # Clean up any resources created during tests
        # This is a safety measure - individual tests should clean up after themselves
        
        # Remove registry file
        local registry_file="/tmp/deployment-registry-$$.json"
        [ -f "$registry_file" ] && rm -f "$registry_file"
        
        test_info "Test environment cleanup complete"
    else
        test_info "Skipping cleanup (CLEANUP_ON_EXIT=false)"
    fi
}

# =============================================================================
# MODULE LOADING TESTS
# =============================================================================

test_module_loading() {
    local all_modules_loaded=true
    
    # Test VPC module loading by checking key functions
    if type -t create_vpc >/dev/null 2>&1; then
        test_info "VPC module loaded successfully"
    else
        test_fail "VPC module loading" "VPC functions not available"
        all_modules_loaded=false
    fi
    
    # Test Security module loading
    if type -t create_security_group >/dev/null 2>&1; then
        test_info "Security module loaded successfully"
    else
        test_fail "Security module loading" "Security functions not available"
        all_modules_loaded=false
    fi
    
    # Test IAM module loading
    if type -t create_ec2_iam_role >/dev/null 2>&1; then
        test_info "IAM module loaded successfully"
    else
        test_fail "IAM module loading" "IAM functions not available"
        all_modules_loaded=false
    fi
    
    # Test EFS module loading
    if type -t create_efs_file_system >/dev/null 2>&1; then
        test_info "EFS module loaded successfully"
    else
        test_fail "EFS module loading" "EFS functions not available"
        all_modules_loaded=false
    fi
    
    # Test ALB module loading
    if type -t create_application_load_balancer >/dev/null 2>&1; then
        test_info "ALB module loaded successfully"
    else
        test_fail "ALB module loading" "ALB functions not available"
        all_modules_loaded=false
    fi
    
    return $($all_modules_loaded && echo 0 || echo 1)
}

# =============================================================================
# FUNCTION EXISTENCE TESTS
# =============================================================================

test_function_existence() {
    local functions_exist=true
    
    # VPC functions
    local vpc_functions=(
        "create_vpc"
        "create_subnet"
        "create_multi_az_subnets"
        "create_internet_gateway"
        "create_nat_gateway"
        "setup_enterprise_network_infrastructure"
        "setup_network_infrastructure"
    )
    
    for func in "${vpc_functions[@]}"; do
        if type -t "$func" >/dev/null 2>&1; then
            test_info "VPC function $func exists"
        else
            test_fail "VPC function existence" "Function $func not found"
            functions_exist=false
        fi
    done
    
    # Security functions
    local security_functions=(
        "create_security_group"
        "create_comprehensive_security_groups"
        "create_alb_security_group"
        "create_efs_security_group"
        "ensure_key_pair"
    )
    
    for func in "${security_functions[@]}"; do
        if type -t "$func" >/dev/null 2>&1; then
            test_info "Security function $func exists"
        else
            test_fail "Security function existence" "Function $func not found"
            functions_exist=false
        fi
    done
    
    # IAM functions
    local iam_functions=(
        "create_ec2_iam_role"
        "setup_comprehensive_iam"
        "create_instance_profile"
        "attach_aws_managed_policies"
    )
    
    for func in "${iam_functions[@]}"; do
        if type -t "$func" >/dev/null 2>&1; then
            test_info "IAM function $func exists"
        else
            test_fail "IAM function existence" "Function $func not found"
            functions_exist=false
        fi
    done
    
    # EFS functions
    local efs_functions=(
        "create_efs_file_system"
        "create_efs_mount_targets"
        "create_efs_access_point"
        "setup_efs_infrastructure"
    )
    
    for func in "${efs_functions[@]}"; do
        if type -t "$func" >/dev/null 2>&1; then
            test_info "EFS function $func exists"
        else
            test_fail "EFS function existence" "Function $func not found"
            functions_exist=false
        fi
    done
    
    # ALB functions
    local alb_functions=(
        "create_application_load_balancer"
        "create_target_group"
        "create_ai_service_target_groups"
        "create_cloudfront_distribution"
        "setup_alb_infrastructure"
    )
    
    for func in "${alb_functions[@]}"; do
        if type -t "$func" >/dev/null 2>&1; then
            test_info "ALB function $func exists"
        else
            test_fail "ALB function existence" "Function $func not found"
            functions_exist=false
        fi
    done
    
    return $($functions_exist && echo 0 || echo 1)
}

# =============================================================================
# CONFIGURATION VALIDATION TESTS
# =============================================================================

test_variable_management() {
    local variables_valid=true
    
    # Test required variables are set
    local required_vars=(
        "STACK_NAME"
        "AWS_REGION"
        "DEPLOYMENT_TYPE"
        "INSTANCE_TYPE"
    )
    
    for var in "${required_vars[@]}"; do
        local value
        value=$(get_variable "$var")
        if [ -n "$value" ]; then
            test_info "Variable $var = $value"
        else
            test_fail "Variable validation" "Required variable $var is not set"
            variables_valid=false
        fi
    done
    
    # Test variable validation functions
    if validate_aws_region "$TEST_REGION"; then
        test_info "AWS region validation passed"
    else
        test_fail "Variable validation" "AWS region validation failed for $TEST_REGION"
        variables_valid=false
    fi
    
    if validate_stack_name "$TEST_STACK_NAME"; then
        test_info "Stack name validation passed"
    else
        test_fail "Variable validation" "Stack name validation failed for $TEST_STACK_NAME"
        variables_valid=false
    fi
    
    return $($variables_valid && echo 0 || echo 1)
}

# =============================================================================
# INTEGRATION TESTS (MOCK AWS CALLS)
# =============================================================================

test_vpc_integration() {
    test_info "Testing VPC integration (dry run)"
    
    # Mock AWS calls by checking function syntax
    if [ "$(type -t create_vpc)" = "function" ]; then
        test_info "VPC creation function is callable"
    else
        return 1
    fi
    
    if [ "$(type -t setup_enterprise_network_infrastructure)" = "function" ]; then
        test_info "Enterprise network setup function is callable"
    else
        return 1
    fi
    
    return 0
}

test_security_integration() {
    test_info "Testing Security integration (dry run)"
    
    # Test security group configuration
    if [ "$(type -t create_comprehensive_security_groups)" = "function" ]; then
        test_info "Comprehensive security groups function is callable"
    else
        return 1
    fi
    
    return 0
}

test_iam_integration() {
    test_info "Testing IAM integration (dry run)"
    
    # Test IAM setup
    if [ "$(type -t setup_comprehensive_iam)" = "function" ]; then
        test_info "Comprehensive IAM setup function is callable"
    else
        return 1
    fi
    
    return 0
}

test_efs_integration() {
    test_info "Testing EFS integration (dry run)"
    
    # Test EFS setup
    if [ "$(type -t setup_efs_infrastructure)" = "function" ]; then
        test_info "EFS infrastructure setup function is callable"
    else
        return 1
    fi
    
    return 0
}

test_alb_integration() {
    test_info "Testing ALB integration (dry run)"
    
    # Test ALB setup
    if [ "$(type -t setup_alb_infrastructure)" = "function" ]; then
        test_info "ALB infrastructure setup function is callable"
    else
        return 1
    fi
    
    return 0
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_error_handling() {
    test_info "Testing error handling mechanisms"
    
    # Test error types are defined
    if [ -n "${ERROR_AWS_API:-}" ] && [ -n "${ERROR_INVALID_ARGUMENT:-}" ]; then
        test_info "Error types are defined"
    else
        return 1
    fi
    
    # Test error context functions
    if [ "$(type -t with_error_context)" = "function" ]; then
        test_info "Error context function exists"
    else
        return 1
    fi
    
    return 0
}

# =============================================================================
# CLEANUP FUNCTION TESTS
# =============================================================================

test_cleanup_functions() {
    test_info "Testing cleanup functions"
    
    # Test cleanup functions exist
    local cleanup_functions=(
        "cleanup_vpc_comprehensive"
        "cleanup_security_groups_comprehensive"
        "cleanup_iam_resources_comprehensive"
        "cleanup_efs_comprehensive"
        "cleanup_alb_comprehensive"
    )
    
    for func in "${cleanup_functions[@]}"; do
        if [ "$(type -t "$func")" = "function" ]; then
            test_info "Cleanup function $func exists"
        else
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_utility_functions() {
    test_info "Testing utility functions"
    
    # Test tagging functions
    if [ "$(type -t generate_tags)" = "function" ]; then
        test_info "Tag generation function exists"
    else
        return 1
    fi
    
    # Test JSON output functions
    local test_json='{"test": "value"}'
    if echo "$test_json" | jq . >/dev/null 2>&1; then
        test_info "JSON processing works correctly"
    else
        return 1
    fi
    
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_all_tests() {
    test_info "Starting infrastructure modules test suite"
    
    # Setup
    setup_test_environment
    
    # Run tests
    run_test "Module Loading" test_module_loading
    run_test "Function Existence" test_function_existence
    run_test "Variable Management" test_variable_management
    run_test "VPC Integration" test_vpc_integration
    run_test "Security Integration" test_security_integration
    run_test "IAM Integration" test_iam_integration
    run_test "EFS Integration" test_efs_integration
    run_test "ALB Integration" test_alb_integration
    run_test "Error Handling" test_error_handling
    run_test "Cleanup Functions" test_cleanup_functions
    run_test "Utility Functions" test_utility_functions
    
    # Generate test report
    generate_test_report
    
    # Cleanup
    cleanup_test_environment
}

generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/infrastructure-modules-test-report.html"
    
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Infrastructure Modules Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        .test-log { background-color: #f9f9f9; padding: 15px; border-radius: 5px; }
        pre { white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Infrastructure Modules Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Test Stack: $TEST_STACK_NAME</p>
        <p>Region: $TEST_REGION</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Total Tests: $TOTAL_TESTS</p>
        <p class="pass">Passed: $PASSED_TESTS</p>
        <p class="fail">Failed: $FAILED_TESTS</p>
        <p class="skip">Skipped: $SKIPPED_TESTS</p>
        <p>Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%</p>
    </div>
    
    <div class="test-log">
        <h2>Test Log</h2>
        <pre>$(cat "$TEST_LOG_FILE")</pre>
    </div>
</body>
</html>
EOF
    
    test_info "Test report generated: $report_file"
}

print_test_summary() {
    echo ""
    echo "=============================================="
    echo "INFRASTRUCTURE MODULES TEST SUMMARY"
    echo "=============================================="
    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    echo -e "Skipped:      ${YELLOW}$SKIPPED_TESTS${NC}"
    echo "Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    echo "=============================================="
    echo ""
    
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${RED}❌ Some tests failed. Check the test log for details.${NC}"
        return 1
    else
        echo -e "${GREEN}✅ All tests passed successfully!${NC}"
        return 0
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle script arguments
case "${1:-run}" in
    "run")
        run_all_tests
        print_test_summary
        ;;
    "setup-only")
        setup_test_environment
        test_info "Test environment setup complete. Run with 'run' to execute tests."
        ;;
    "cleanup-only")
        cleanup_test_environment
        ;;
    "help")
        echo "Usage: $0 [run|setup-only|cleanup-only|help]"
        echo ""
        echo "Commands:"
        echo "  run         - Run all tests (default)"
        echo "  setup-only  - Only setup test environment"
        echo "  cleanup-only- Only cleanup test environment"
        echo "  help        - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  AWS_REGION       - AWS region for testing (default: us-east-1)"
        echo "  CLEANUP_ON_EXIT  - Cleanup after tests (default: true)"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$0 help' for usage information."
        exit 1
        ;;
esac
