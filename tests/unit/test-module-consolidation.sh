#!/usr/bin/env bash
# =============================================================================
# Module Consolidation Comprehensive Test Suite
# Tests the consolidated module architecture, dependency optimization,
# backward compatibility, and performance improvements
# =============================================================================

set -euo pipefail

# Standard test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"

# Source test framework
source "$SCRIPT_DIR/../lib/shell-test-framework.sh"

# Initialize test suite
test_init "Module Consolidation Test Suite"

# =============================================================================
# TEST SETUP AND HELPERS
# =============================================================================

setup_test_environment() {
    # Create temporary test directory
    export TEST_DIR="/tmp/test-module-consolidation-$$"
    mkdir -p "$TEST_DIR"
    
    # Backup original library loader if exists
    if [[ -f "$LIB_DIR/utils/library-loader.sh" ]]; then
        cp "$LIB_DIR/utils/library-loader.sh" "$TEST_DIR/library-loader.backup.sh"
    fi
}

cleanup_test_environment() {
    # Restore original library loader if needed
    if [[ -f "$TEST_DIR/library-loader.backup.sh" ]]; then
        cp "$TEST_DIR/library-loader.backup.sh" "$LIB_DIR/utils/library-loader.sh"
    fi
    
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

# Measure loading time
measure_loading_time() {
    local module="$1"
    local start_time end_time duration
    
    start_time=$(date +%s.%N)
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "$module"
    end_time=$(date +%s.%N)
    
    duration=$(echo "$end_time - $start_time" | bc)
    echo "$duration"
}

# =============================================================================
# ERROR HANDLING CONSOLIDATION TESTS
# =============================================================================

test_unified_error_module() {
    test_start "Unified Error Module Functionality"
    
    # Source the library loader
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "errors/error_types"
    
    # Test that all error functions are available
    local error_functions=(
        "error_argument_missing"
        "error_aws_api_rate_limited"
        "error_aws_cli_missing"
        "error_aws_credentials_invalid"
        "error_aws_quota_exceeded"
        "error_aws_region_invalid"
        "error_bash_version_invalid"
        "error_cleanup_failed"
        "error_command_not_found"
        "error_config_invalid"
        "error_deployment_rollback_required"
        "error_docker_compose_failure"
        "error_docker_not_running"
        "error_ec2_capacity_limit"
        "error_ec2_insufficient_capacity"
        "error_efs_mount_failed"
        "error_file_not_found"
        "error_health_check_failed"
        "error_iam_permission_denied"
        "error_invalid_instance_type"
        "error_library_load_failed"
        "error_network_timeout"
        "error_parameter_store_access"
        "error_permission_denied"
        "error_resource_limit_exceeded"
        "error_security_group_rule_invalid"
        "error_service_quota_exceeded"
        "error_spot_price_exceeded"
        "error_stack_already_exists"
        "error_stack_not_found"
        "error_state_file_corrupted"
        "error_subnet_capacity_exceeded"
        "error_validation_failed"
        "error_vpc_limit_exceeded"
    )
    
    local missing_functions=0
    for func in "${error_functions[@]}"; do
        if ! declare -f "$func" > /dev/null; then
            test_fail "Error function missing: $func"
            ((missing_functions++))
        fi
    done
    
    if [[ $missing_functions -eq 0 ]]; then
        test_pass "All error functions are available"
    fi
    
    # Test error code retrieval
    local error_code
    error_code=$(get_error_code "EC2_INSUFFICIENT_CAPACITY")
    assert_equals "$error_code" "EC2_001" "EC2 insufficient capacity error code"
    
    error_code=$(get_error_code "AWS_CREDENTIALS_INVALID")
    assert_equals "$error_code" "AWS_002" "AWS credentials invalid error code"
    
    # Test recovery strategies
    if should_retry_error "AWS_API_RATE_LIMITED" 3; then
        test_pass "AWS API rate limit retry strategy working"
    else
        test_fail "AWS API rate limit retry strategy failed"
    fi
    
    # Test error message generation
    local error_msg
    error_msg=$(error_ec2_insufficient_capacity "g4dn.xlarge" "us-east-1" 2>&1 || true)
    assert_contains "$error_msg" "EC2_INSUFFICIENT_CAPACITY" "Error message contains error type"
    assert_contains "$error_msg" "g4dn.xlarge" "Error message contains instance type"
}

# =============================================================================
# COMPUTE MODULE CONSOLIDATION TESTS
# =============================================================================

test_compute_module_consolidation() {
    test_start "Compute Module Consolidation"
    
    # Source the compute modules
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "compute/core" "compute/spot" "compute/launch" "compute/ami" "compute/provisioner"
    
    # Test core compute functions
    local core_functions=(
        "validate_instance_type"
        "get_instance_architecture"
        "is_gpu_instance"
        "get_instance_family"
        "calculate_required_disk_space"
        "check_instance_availability"
    )
    
    for func in "${core_functions[@]}"; do
        if declare -f "$func" > /dev/null; then
            test_pass "Core compute function available: $func"
        else
            test_fail "Core compute function missing: $func"
        fi
    done
    
    # Test spot instance functions
    local spot_functions=(
        "check_spot_pricing"
        "find_best_spot_price"
        "calculate_spot_savings"
        "handle_spot_interruption"
        "get_spot_price_history"
    )
    
    for func in "${spot_functions[@]}"; do
        if declare -f "$func" > /dev/null; then
            test_pass "Spot instance function available: $func"
        else
            test_fail "Spot instance function missing: $func"
        fi
    done
    
    # Test AMI functions
    local ami_functions=(
        "get_latest_ami"
        "validate_ami_id"
        "get_ami_architecture"
        "check_ami_availability"
    )
    
    for func in "${ami_functions[@]}"; do
        if declare -f "$func" > /dev/null; then
            test_pass "AMI function available: $func"
        else
            test_fail "AMI function missing: $func"
        fi
    done
}

test_compute_module_interfaces() {
    test_start "Compute Module Interfaces"
    
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "compute/core"
    
    # Test instance type validation
    local result
    result=$(validate_instance_type "g4dn.xlarge" 2>&1 || echo "FAILED")
    if [[ "$result" != "FAILED" ]]; then
        test_pass "Instance type validation working"
    else
        test_fail "Instance type validation failed"
    fi
    
    # Test architecture detection
    local arch
    arch=$(get_instance_architecture "t4g.micro" 2>&1 || echo "UNKNOWN")
    assert_equals "$arch" "arm64" "ARM instance architecture detection"
    
    arch=$(get_instance_architecture "t3.micro" 2>&1 || echo "UNKNOWN")
    assert_equals "$arch" "x86_64" "x86 instance architecture detection"
    
    # Test GPU detection
    if is_gpu_instance "g4dn.xlarge"; then
        test_pass "GPU instance detection working"
    else
        test_fail "GPU instance detection failed"
    fi
    
    if ! is_gpu_instance "t3.micro"; then
        test_pass "Non-GPU instance detection working"
    else
        test_fail "Non-GPU instance detection failed"
    fi
}

# =============================================================================
# DEPENDENCY OPTIMIZATION TESTS
# =============================================================================

test_dependency_groups() {
    test_start "Dependency Group Loading"
    
    source "$LIB_DIR/utils/library-loader.sh"
    
    # Test minimal deployment group
    initialize_script "test" "@minimal-deployment"
    
    local minimal_modules=(
        "core/variables"
        "core/logging"
        "core/errors"
        "core/validation"
        "infrastructure/vpc"
        "infrastructure/security"
        "compute/core"
        "compute/launch"
        "monitoring/health"
    )
    
    # Check that all modules are loaded
    for module in "${minimal_modules[@]}"; do
        local module_var="MODULE_$(echo "$module" | tr '[:lower:]/' '[:upper:]_')_LOADED"
        if [[ "${!module_var:-}" == "true" ]]; then
            test_pass "Module loaded in minimal group: $module"
        else
            test_fail "Module not loaded in minimal group: $module"
        fi
    done
    
    # Test spot deployment group
    unset LOADED_MODULES
    declare -A LOADED_MODULES=()
    
    initialize_script "test" "@spot-deployment"
    
    # Check spot-specific modules
    if [[ "${MODULE_COMPUTE_SPOT_LOADED:-}" == "true" ]]; then
        test_pass "Spot module loaded in spot deployment group"
    else
        test_fail "Spot module not loaded in spot deployment group"
    fi
    
    if [[ "${MODULE_COMPUTE_SPOT_OPTIMIZER_LOADED:-}" == "true" ]]; then
        test_pass "Spot optimizer loaded in spot deployment group"
    else
        test_fail "Spot optimizer not loaded in spot deployment group"
    fi
}

test_dependency_resolution() {
    test_start "Dependency Resolution"
    
    source "$LIB_DIR/utils/library-loader.sh"
    
    # Test that dependencies are resolved correctly
    unset LOADED_MODULES
    declare -A LOADED_MODULES=()
    
    # Load a module with dependencies
    initialize_script "test" "compute/spot"
    
    # Check that dependencies were loaded
    local dependencies=(
        "core/variables"
        "core/logging"
        "core/errors"
        "compute/core"
    )
    
    for dep in "${dependencies[@]}"; do
        local dep_var="MODULE_$(echo "$dep" | tr '[:lower:]/' '[:upper:]_')_LOADED"
        if [[ "${!dep_var:-}" == "true" ]]; then
            test_pass "Dependency loaded: $dep"
        else
            test_fail "Dependency not loaded: $dep"
        fi
    done
}

# =============================================================================
# BACKWARD COMPATIBILITY TESTS
# =============================================================================

test_backward_compatibility() {
    test_start "Backward Compatibility"
    
    # Test that old library names still work
    source "$LIB_DIR/utils/library-loader.sh"
    
    # Load using old names (should use compatibility wrappers)
    load_module "aws-deployment-common.sh"
    load_module "error-handling.sh"
    load_module "spot-instance.sh"
    
    # Check that functions are available
    if declare -f "log_info" > /dev/null; then
        test_pass "Legacy aws-deployment-common functions available"
    else
        test_fail "Legacy aws-deployment-common functions missing"
    fi
    
    if declare -f "handle_error" > /dev/null; then
        test_pass "Legacy error-handling functions available"
    else
        test_fail "Legacy error-handling functions missing"
    fi
    
    if declare -f "check_spot_pricing" > /dev/null; then
        test_pass "Legacy spot-instance functions available"
    else
        test_fail "Legacy spot-instance functions missing"
    fi
}

test_compatibility_wrappers() {
    test_start "Compatibility Wrapper Functions"
    
    # Source compatibility wrappers directly
    source "$LIB_DIR/modules/compatibility/legacy_wrapper.sh" 2>/dev/null || {
        test_skip "Compatibility wrapper not found"
        return
    }
    
    # Test wrapper functions
    local wrapper_functions=(
        "load_library"
        "source_library"
        "require_library"
    )
    
    for func in "${wrapper_functions[@]}"; do
        if declare -f "$func" > /dev/null; then
            test_pass "Wrapper function available: $func"
        else
            test_fail "Wrapper function missing: $func"
        fi
    done
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_loading_performance() {
    test_start "Module Loading Performance"
    
    # Measure loading time for individual modules
    local modules=(
        "core/variables"
        "core/logging"
        "errors/error_types"
        "compute/core"
        "infrastructure/vpc"
    )
    
    local total_time=0
    for module in "${modules[@]}"; do
        # Reset environment for clean test
        unset LOADED_MODULES
        declare -A LOADED_MODULES=()
        
        local load_time
        load_time=$(measure_loading_time "$module")
        total_time=$(echo "$total_time + $load_time" | bc)
        
        # Check if loading is reasonably fast (< 0.1 seconds)
        if (( $(echo "$load_time < 0.1" | bc -l) )); then
            test_pass "Module $module loads quickly ($load_time seconds)"
        else
            test_warn "Module $module loads slowly ($load_time seconds)"
        fi
    done
    
    local avg_time=$(echo "scale=4; $total_time / ${#modules[@]}" | bc)
    test_pass "Average module loading time: $avg_time seconds"
}

test_dependency_group_performance() {
    test_start "Dependency Group Loading Performance"
    
    # Reset environment
    unset LOADED_MODULES
    declare -A LOADED_MODULES=()
    
    # Measure loading time for dependency groups
    local start_time end_time duration
    
    start_time=$(date +%s.%N)
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "@minimal-deployment"
    end_time=$(date +%s.%N)
    
    duration=$(echo "$end_time - $start_time" | bc)
    
    # Check if group loading is reasonably fast (< 0.5 seconds)
    if (( $(echo "$duration < 0.5" | bc -l) )); then
        test_pass "Minimal deployment group loads quickly ($duration seconds)"
    else
        test_warn "Minimal deployment group loads slowly ($duration seconds)"
    fi
}

# =============================================================================
# MODULE INTERFACE TESTS
# =============================================================================

test_module_interfaces() {
    test_start "Module Interface Consistency"
    
    source "$LIB_DIR/utils/library-loader.sh"
    
    # Test that modules expose consistent interfaces
    local modules_to_test=(
        "core/variables:init_variables,get_variable,set_variable"
        "core/logging:log_info,log_warn,log_error,log_debug"
        "core/errors:handle_error,error_exit,trap_errors"
        "compute/core:validate_instance_type,get_instance_architecture"
        "infrastructure/vpc:create_vpc,configure_vpc,validate_vpc"
    )
    
    for module_spec in "${modules_to_test[@]}"; do
        local module="${module_spec%%:*}"
        local functions="${module_spec#*:}"
        
        # Load the module
        initialize_script "test" "$module"
        
        # Check each function
        IFS=',' read -ra func_array <<< "$functions"
        for func in "${func_array[@]}"; do
            if declare -f "$func" > /dev/null; then
                test_pass "Interface function available: $module::$func"
            else
                test_fail "Interface function missing: $module::$func"
            fi
        done
    done
}

test_module_isolation() {
    test_start "Module Isolation"
    
    # Test that modules don't pollute global namespace unnecessarily
    local vars_before vars_after new_vars
    
    # Get initial variable count
    vars_before=$(compgen -v | wc -l)
    
    # Load a module
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "compute/core"
    
    # Get final variable count
    vars_after=$(compgen -v | wc -l)
    new_vars=$((vars_after - vars_before))
    
    # Check that not too many variables were created
    if [[ $new_vars -lt 50 ]]; then
        test_pass "Module creates reasonable number of variables ($new_vars)"
    else
        test_warn "Module creates many variables ($new_vars)"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_full_stack_loading() {
    test_start "Full Stack Module Loading"
    
    source "$LIB_DIR/utils/library-loader.sh"
    
    # Load a complete deployment stack
    initialize_script "test" "@full-deployment"
    
    # Check that all major subsystems are loaded
    local subsystems=(
        "MODULE_CORE_VARIABLES_LOADED"
        "MODULE_CORE_LOGGING_LOADED"
        "MODULE_CORE_ERRORS_LOADED"
        "MODULE_INFRASTRUCTURE_VPC_LOADED"
        "MODULE_INFRASTRUCTURE_SECURITY_LOADED"
        "MODULE_INFRASTRUCTURE_ALB_LOADED"
        "MODULE_COMPUTE_CORE_LOADED"
        "MODULE_COMPUTE_LAUNCH_LOADED"
        "MODULE_APPLICATION_DOCKER_MANAGER_LOADED"
        "MODULE_MONITORING_HEALTH_LOADED"
    )
    
    local missing=0
    for subsystem in "${subsystems[@]}"; do
        if [[ "${!subsystem:-}" != "true" ]]; then
            test_fail "Subsystem not loaded: $subsystem"
            ((missing++))
        fi
    done
    
    if [[ $missing -eq 0 ]]; then
        test_pass "All subsystems loaded successfully"
    fi
}

test_error_recovery_integration() {
    test_start "Error Recovery Integration"
    
    source "$LIB_DIR/utils/library-loader.sh"
    initialize_script "test" "errors/error_types" "core/errors"
    
    # Test error handling pipeline
    local error_caught=false
    
    # Set up error trap
    trap_errors || true
    
    # Test that errors are properly caught and recovery is attempted
    (
        error_ec2_insufficient_capacity "g4dn.xlarge" "us-east-1"
    ) 2>&1 | grep -q "EC2_INSUFFICIENT_CAPACITY" && error_caught=true
    
    if [[ "$error_caught" == "true" ]]; then
        test_pass "Error handling and recovery integration working"
    else
        test_fail "Error handling and recovery integration failed"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    setup_test_environment
    
    # Run all test categories
    test_unified_error_module
    test_compute_module_consolidation
    test_compute_module_interfaces
    test_dependency_groups
    test_dependency_resolution
    test_backward_compatibility
    test_compatibility_wrappers
    test_loading_performance
    test_dependency_group_performance
    test_module_interfaces
    test_module_isolation
    test_full_stack_loading
    test_error_recovery_integration
    
    # Cleanup
    cleanup_test_environment
    
    # Show results
    test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi