#!/usr/bin/env bash
# =============================================================================
# Infrastructure Integration Test
# Tests the integration of all infrastructure modules in deploy.sh
# =============================================================================

set -euo pipefail

# Load test framework
source "$(dirname "${BASH_SOURCE[0]}")/lib/shell-test-framework.sh"

# Test configuration
TEST_NAME="Infrastructure Integration Test"
TEST_DESCRIPTION="Validates that all infrastructure modules are properly integrated in deploy.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_vpc_module_integration() {
    local test_name="VPC Module Integration"
    local test_description="Tests VPC module integration in deploy.sh"
    
    test_start "$test_name" "$test_description"
    
    # Check if VPC module is loaded
    if ! grep -q "infrastructure/vpc" deploy.sh; then
        test_fail "VPC module not found in deploy.sh"
        return 1
    fi
    
    # Check if VPC creation function is called
    if ! grep -q "create_vpc_with_subnets" deploy.sh; then
        test_fail "VPC creation function not found in deploy.sh"
        return 1
    fi
    
    # Check if VPC configuration options are available
    if ! grep -q "VPC_CIDR" deploy.sh; then
        test_fail "VPC CIDR configuration not found in deploy.sh"
        return 1
    fi
    
    test_pass "VPC module integration validated"
}

test_compute_module_integration() {
    local test_name="Compute Module Integration"
    local test_description="Tests compute module integration in deploy.sh"
    
    test_start "$test_name" "$test_description"
    
    # Check if compute module is loaded
    if ! grep -q "infrastructure/compute" deploy.sh; then
        test_fail "Compute module not found in deploy.sh"
        return 1
    fi
    
    # Check if compute creation function is called
    if ! grep -q "create_compute_infrastructure" deploy.sh; then
        test_fail "Compute creation function not found in deploy.sh"
        return 1
    fi
    
    # Check if compute configuration options are available
    if ! grep -q "INSTANCE_TYPE" deploy.sh; then
        test_fail "Instance type configuration not found in deploy.sh"
        return 1
    fi
    
    test_pass "Compute module integration validated"
}

test_alb_module_integration() {
    local test_name="ALB Module Integration"
    local test_description="Tests ALB module integration in deploy.sh"
    
    test_start "$test_name" "$test_description"
    
    # Check if ALB module is loaded
    if ! grep -q "infrastructure/alb" deploy.sh; then
        test_fail "ALB module not found in deploy.sh"
        return 1
    fi
    
    # Check if ALB creation function is called
    if ! grep -q "create_alb_with_target_group" deploy.sh; then
        test_fail "ALB creation function not found in deploy.sh"
        return 1
    fi
    
    # Check if ALB configuration options are available
    if ! grep -q "ALB_INTERNAL" deploy.sh; then
        test_fail "ALB internal configuration not found in deploy.sh"
        return 1
    fi
    
    test_pass "ALB module integration validated"
}

test_cloudfront_module_integration() {
    local test_name="CloudFront Module Integration"
    local test_description="Tests CloudFront module integration in deploy.sh"
    
    test_start "$test_name" "$test_description"
    
    # Check if CloudFront module is loaded
    if ! grep -q "infrastructure/cloudfront" deploy.sh; then
        test_fail "CloudFront module not found in deploy.sh"
        return 1
    fi
    
    # Check if CloudFront creation function is called
    if ! grep -q "create_cloudfront_distribution" deploy.sh; then
        test_fail "CloudFront creation function not found in deploy.sh"
        return 1
    fi
    
    # Check if CloudFront configuration options are available
    if ! grep -q "CLOUDFRONT_PRICE_CLASS" deploy.sh; then
        test_fail "CloudFront price class configuration not found in deploy.sh"
        return 1
    fi
    
    test_pass "CloudFront module integration validated"
}

test_efs_module_integration() {
    local test_name="EFS Module Integration"
    local test_description="Tests EFS module integration in deploy.sh"
    
    test_start "$test_name" "$test_description"
    
    # Check if EFS module is loaded
    if ! grep -q "infrastructure/efs" deploy.sh; then
        test_fail "EFS module not found in deploy.sh"
        return 1
    fi
    
    # Check if EFS creation function is called
    if ! grep -q "setup_efs_infrastructure" deploy.sh; then
        test_fail "EFS creation function not found in deploy.sh"
        return 1
    fi
    
    # Check if EFS configuration options are available
    if ! grep -q "EFS_ENCRYPTION" deploy.sh; then
        test_fail "EFS encryption configuration not found in deploy.sh"
        return 1
    fi
    
    test_pass "EFS module integration validated"
}

test_security_module_integration() {
    local test_name="Security Module Integration"
    local test_description="Tests security module integration in deploy.sh"
    
    test_start "$test_name" "$test_description"
    
    # Check if security module is loaded
    if ! grep -q "infrastructure/security" deploy.sh; then
        test_fail "Security module not found in deploy.sh"
        return 1
    fi
    
    # Check if security creation function is called
    if ! grep -q "create_comprehensive_security_groups" deploy.sh; then
        test_fail "Security creation function not found in deploy.sh"
        return 1
    fi
    
    # Check if IAM role creation function is called
    if ! grep -q "create_iam_role" deploy.sh; then
        test_fail "IAM role creation function not found in deploy.sh"
        return 1
    fi
    
    test_pass "Security module integration validated"
}

test_configuration_options() {
    local test_name="Configuration Options"
    local test_description="Tests that all configuration options are properly handled"
    
    test_start "$test_name" "$test_description"
    
    # Check for VPC configuration options
    local vpc_options=("--vpc-cidr" "--public-subnets" "--private-subnets")
    for option in "${vpc_options[@]}"; do
        if ! grep -q "$option" deploy.sh; then
            test_fail "VPC configuration option $option not found in deploy.sh"
            return 1
        fi
    done
    
    # Check for compute configuration options
    local compute_options=("--instance-type" "--min-capacity" "--max-capacity")
    for option in "${compute_options[@]}"; do
        if ! grep -q "$option" deploy.sh; then
            test_fail "Compute configuration option $option not found in deploy.sh"
            return 1
        fi
    done
    
    # Check for infrastructure configuration options
    local infra_options=("--efs-encryption" "--alb-internal" "--cloudfront-price-class")
    for option in "${infra_options[@]}"; do
        if ! grep -q "$option" deploy.sh; then
            test_fail "Infrastructure configuration option $option not found in deploy.sh"
            return 1
        fi
    done
    
    test_pass "All configuration options validated"
}

test_variable_store_integration() {
    local test_name="Variable Store Integration"
    local test_description="Tests that configuration variables are properly stored and retrieved"
    
    test_start "$test_name" "$test_description"
    
    # Check that variables are set in deployment state
    if ! grep -q "set_variable.*VPC_CIDR" deploy.sh; then
        test_fail "VPC_CIDR variable not set in deployment state"
        return 1
    fi
    
    if ! grep -q "set_variable.*INSTANCE_TYPE" deploy.sh; then
        test_fail "INSTANCE_TYPE variable not set in deployment state"
        return 1
    fi
    
    # Check that variables are retrieved in infrastructure creation
    if ! grep -q "get_variable.*VPC_CIDR" deploy.sh; then
        test_fail "VPC_CIDR variable not retrieved in infrastructure creation"
        return 1
    fi
    
    if ! grep -q "get_variable.*INSTANCE_TYPE" deploy.sh; then
        test_fail "INSTANCE_TYPE variable not retrieved in infrastructure creation"
        return 1
    fi
    
    test_pass "Variable store integration validated"
}

test_destruction_integration() {
    local test_name="Destruction Integration"
    local test_description="Tests that destruction functions are properly integrated"
    
    test_start "$test_name" "$test_description"
    
    # Check that destruction functions use proper module functions
    if ! grep -q "delete_cloudfront_distribution" deploy.sh; then
        test_fail "CloudFront destruction function not properly integrated"
        return 1
    fi
    
    if ! grep -q "delete_alb" deploy.sh; then
        test_fail "ALB destruction function not properly integrated"
        return 1
    fi
    
    if ! grep -q "cleanup_efs_comprehensive" deploy.sh; then
        test_fail "EFS destruction function not properly integrated"
        return 1
    fi
    
    if ! grep -q "delete_compute_infrastructure" deploy.sh; then
        test_fail "Compute destruction function not properly integrated"
        return 1
    fi
    
    if ! grep -q "delete_vpc" deploy.sh; then
        test_fail "VPC destruction function not properly integrated"
        return 1
    fi
    
    test_pass "Destruction integration validated"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "Running $TEST_NAME"
    echo "Description: $TEST_DESCRIPTION"
    echo ""
    
    # Run all tests
    test_vpc_module_integration
    test_compute_module_integration
    test_alb_module_integration
    test_cloudfront_module_integration
    test_efs_module_integration
    test_security_module_integration
    test_configuration_options
    test_variable_store_integration
    test_destruction_integration
    
    # Print test summary
    print_test_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi