#!/bin/bash
# =============================================================================
# Unity AWS Service Unit Tests
# Comprehensive unit testing for Unity AWS service functions
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework
unity_test_init "test-unity-aws-service" "service-unit" "unity-aws-service"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up test environment
setup_aws_service_tests() {
    # Load the AWS service
    source "$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh" 2>/dev/null || {
        log_error "Failed to load Unity AWS service"
        return 1
    }
    
    # Mock AWS CLI for testing
    mock_function "aws" 'case "$1" in
        "ec2")
            case "$2" in
                "describe-instances")
                    echo "{\"Reservations\":[{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\",\"State\":{\"Name\":\"running\"}}]}]}"
                    ;;
                "run-instances")
                    echo "{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\"}]}"
                    ;;
                "describe-spot-price-history")
                    echo "0.10	us-west-2a"
                    ;;
                "describe-vpcs")
                    echo "{\"Vpcs\":[{\"VpcId\":\"vpc-12345678\",\"CidrBlock\":\"10.0.0.0/16\"}]}"
                    ;;
                "create-vpc")
                    echo "{\"Vpc\":{\"VpcId\":\"vpc-12345678\"}}"
                    ;;
                *)
                    echo "mocked-ec2-output"
                    ;;
            esac
            ;;
        "elbv2")
            case "$2" in
                "create-load-balancer")
                    echo "{\"LoadBalancers\":[{\"LoadBalancerArn\":\"arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/test-alb/1234567890123456\"}]}"
                    ;;
                *)
                    echo "mocked-elbv2-output"
                    ;;
            esac
            ;;
        "cloudfront")
            echo "{\"Distribution\":{\"Id\":\"E1234567890123\"}}"
            ;;
        "efs")
            echo "{\"FileSystemId\":\"fs-12345678\"}"
            ;;
        *)
            echo "mocked-aws-output"
            ;;
    esac'
    
    # Mock other dependencies
    mock_function "bc" 'echo "scale=2; $*" | sed "s/.*=//"'
    mock_function "date" 'echo "1234567890"'
}

# Clean up test environment
cleanup_aws_service_tests() {
    # Restore mocked functions
    restore_function "aws"
    restore_function "bc"
    restore_function "date"
}

# =============================================================================
# UNITY AWS SERVICE INITIALIZATION TESTS
# =============================================================================

test_unity_aws_service_init() {
    test_start "unity_aws_service_init" "Test Unity AWS service initialization"
    
    setup_aws_service_tests
    
    # Test service initialization
    if init_unity_aws_service "test-service" >/dev/null 2>&1; then
        test_pass "Unity AWS service initialized successfully"
    else
        test_fail "Unity AWS service initialization failed"
    fi
    
    cleanup_aws_service_tests
}

test_unity_aws_service_version() {
    test_start "unity_aws_service_version" "Test Unity AWS service version"
    
    setup_aws_service_tests
    
    # Check version variable exists
    if [[ -n "${UNITY_AWS_SERVICE_VERSION:-}" ]]; then
        test_pass "Unity AWS service version is defined: $UNITY_AWS_SERVICE_VERSION"
    else
        test_fail "Unity AWS service version is not defined"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# EC2 INSTANCE MANAGEMENT TESTS
# =============================================================================

test_launch_ec2_instance_spot() {
    test_start "launch_ec2_instance_spot" "Test launching spot EC2 instance"
    
    setup_aws_service_tests
    
    # Test spot instance launch
    local instance_id
    instance_id=$(launch_ec2_instance "t3.medium" "spot" "test-stack" 2>/dev/null)
    
    if [[ "$instance_id" == "i-1234567890abcdef0" ]]; then
        test_pass "Spot EC2 instance launched successfully: $instance_id"
    else
        test_fail "Spot EC2 instance launch failed or returned unexpected ID: $instance_id"
    fi
    
    cleanup_aws_service_tests
}

test_launch_ec2_instance_ondemand() {
    test_start "launch_ec2_instance_ondemand" "Test launching on-demand EC2 instance"
    
    setup_aws_service_tests
    
    # Test on-demand instance launch
    local instance_id
    instance_id=$(launch_ec2_instance "t3.medium" "on-demand" "test-stack" 2>/dev/null)
    
    if [[ "$instance_id" == "i-1234567890abcdef0" ]]; then
        test_pass "On-demand EC2 instance launched successfully: $instance_id"
    else
        test_fail "On-demand EC2 instance launch failed or returned unexpected ID: $instance_id"
    fi
    
    cleanup_aws_service_tests
}

test_launch_ec2_instance_invalid_type() {
    test_start "launch_ec2_instance_invalid_type" "Test launching EC2 instance with invalid deployment type"
    
    setup_aws_service_tests
    
    # Test invalid deployment type
    if launch_ec2_instance "t3.medium" "invalid-type" "test-stack" >/dev/null 2>&1; then
        test_fail "EC2 instance launch should have failed with invalid deployment type"
    else
        test_pass "EC2 instance launch correctly failed with invalid deployment type"
    fi
    
    cleanup_aws_service_tests
}

test_get_optimal_spot_config() {
    test_start "get_optimal_spot_config" "Test getting optimal spot instance configuration"
    
    setup_aws_service_tests
    
    # Test spot configuration retrieval
    local spot_config
    spot_config=$(get_optimal_spot_config "t3.medium" 2>/dev/null)
    
    if [[ -n "$spot_config" && "$spot_config" == *"|"* ]]; then
        test_pass "Optimal spot configuration retrieved: $spot_config"
    else
        test_fail "Failed to retrieve optimal spot configuration: $spot_config"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# VPC MANAGEMENT TESTS
# =============================================================================

test_create_or_get_vpc() {
    test_start "create_or_get_vpc" "Test creating or getting VPC"
    
    setup_aws_service_tests
    
    # Test VPC creation/retrieval
    local vpc_id
    vpc_id=$(create_or_get_vpc "test-stack" "10.0.0.0/16" 2>/dev/null)
    
    if [[ "$vpc_id" == "vpc-12345678" ]]; then
        test_pass "VPC created/retrieved successfully: $vpc_id"
    else
        test_fail "VPC creation/retrieval failed or returned unexpected ID: $vpc_id"
    fi
    
    cleanup_aws_service_tests
}

test_get_available_cidr() {
    test_start "get_available_cidr" "Test getting available CIDR block"
    
    setup_aws_service_tests
    
    # Test CIDR block generation
    local cidr_block
    cidr_block=$(get_available_cidr 2>/dev/null)
    
    if [[ -n "$cidr_block" && "$cidr_block" == *".0.0/16" ]]; then
        test_pass "Available CIDR block generated: $cidr_block"
    else
        test_fail "Failed to generate available CIDR block: $cidr_block"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# ALB MANAGEMENT TESTS
# =============================================================================

test_create_alb() {
    test_start "create_alb" "Test creating Application Load Balancer"
    
    setup_aws_service_tests
    
    # Mock additional ALB dependencies
    mock_function "get_or_create_alb_security_group" 'echo "sg-12345678"'
    
    # Test ALB creation
    local alb_arn
    alb_arn=$(create_alb "test-stack" "vpc-12345678" "subnet-12345678,subnet-87654321" 2>/dev/null)
    
    if [[ "$alb_arn" == *"loadbalancer/app/"* ]]; then
        test_pass "ALB created successfully: $alb_arn"
    else
        test_fail "ALB creation failed or returned unexpected ARN: $alb_arn"
    fi
    
    restore_function "get_or_create_alb_security_group"
    cleanup_aws_service_tests
}

# =============================================================================
# CLOUDFRONT MANAGEMENT TESTS
# =============================================================================

test_create_cloudfront() {
    test_start "create_cloudfront" "Test creating CloudFront distribution"
    
    setup_aws_service_tests
    
    # Test CloudFront creation
    local dist_id
    dist_id=$(create_cloudfront "test-stack" "example.com" 2>/dev/null)
    
    if [[ "$dist_id" == "E1234567890123" ]]; then
        test_pass "CloudFront distribution created successfully: $dist_id"
    else
        test_fail "CloudFront distribution creation failed or returned unexpected ID: $dist_id"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# EFS MANAGEMENT TESTS
# =============================================================================

test_create_or_get_efs() {
    test_start "create_or_get_efs" "Test creating or getting EFS file system"
    
    setup_aws_service_tests
    
    # Test EFS creation/retrieval
    local efs_id
    efs_id=$(create_or_get_efs "test-stack" "vpc-12345678" 2>/dev/null)
    
    if [[ "$efs_id" == "fs-12345678" ]]; then
        test_pass "EFS file system created/retrieved successfully: $efs_id"
    else
        test_fail "EFS file system creation/retrieval failed or returned unexpected ID: $efs_id"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# COST OPTIMIZATION TESTS
# =============================================================================

test_calculate_deployment_cost() {
    test_start "calculate_deployment_cost" "Test calculating deployment cost"
    
    setup_aws_service_tests
    
    # Initialize cost tracking
    init_unity_aws_service "test-service" >/dev/null 2>&1
    
    # Mock cost tracking
    track_cost "ec2-spot" "i-1234567890abcdef0" "0.10"
    track_cost "alb" "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/test-alb/1234567890123456" "0.0225"
    
    # Test cost calculation
    local total_cost
    total_cost=$(calculate_deployment_cost "test-stack" "720" 2>/dev/null)
    
    if [[ -n "$total_cost" && "$total_cost" != "0" ]]; then
        test_pass "Deployment cost calculated successfully: \$$total_cost"
    else
        test_fail "Deployment cost calculation failed or returned zero: $total_cost"
    fi
    
    cleanup_aws_service_tests
}

test_optimize_deployment_costs() {
    test_start "optimize_deployment_costs" "Test optimizing deployment costs"
    
    setup_aws_service_tests
    
    # Test cost optimization
    if optimize_deployment_costs "test-stack" >/dev/null 2>&1; then
        test_pass "Cost optimization completed successfully"
    else
        test_fail "Cost optimization failed"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# QUOTA MANAGEMENT TESTS
# =============================================================================

test_check_ec2_quota() {
    test_start "check_ec2_quota" "Test checking EC2 quota"
    
    setup_aws_service_tests
    
    # Mock service quotas
    mock_function "aws" 'case "$1 $2" in
        "service-quotas get-service-quota")
            echo "{\"Quota\":{\"Value\":20}}"
            ;;
        "ec2 describe-instances")
            echo "{\"Reservations\":[{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\"}]}]}"
            ;;
        *)
            echo "mocked-aws-output"
            ;;
    esac'
    
    # Test quota check
    if check_ec2_quota "t3.medium" >/dev/null 2>&1; then
        test_pass "EC2 quota check passed"
    else
        test_fail "EC2 quota check failed"
    fi
    
    cleanup_aws_service_tests
}

test_check_vpc_quota() {
    test_start "check_vpc_quota" "Test checking VPC quota"
    
    setup_aws_service_tests
    
    # Test VPC quota check
    if check_vpc_quota >/dev/null 2>&1; then
        test_pass "VPC quota check passed"
    else
        test_fail "VPC quota check failed"
    fi
    
    cleanup_aws_service_tests
}

test_check_alb_quota() {
    test_start "check_alb_quota" "Test checking ALB quota"
    
    setup_aws_service_tests
    
    # Test ALB quota check
    if check_alb_quota >/dev/null 2>&1; then
        test_pass "ALB quota check passed"
    else
        test_fail "ALB quota check failed"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# RESOURCE MANAGEMENT TESTS
# =============================================================================

test_track_resource() {
    test_start "track_resource" "Test resource tracking"
    
    setup_aws_service_tests
    
    # Initialize service
    init_unity_aws_service "test-service" >/dev/null 2>&1
    
    # Test resource tracking
    track_resource "ec2" "i-1234567890abcdef0" "test-stack"
    
    # Verify resource is tracked (check if function completes without error)
    if [[ $? -eq 0 ]]; then
        test_pass "Resource tracking completed successfully"
    else
        test_fail "Resource tracking failed"
    fi
    
    cleanup_aws_service_tests
}

test_track_cost() {
    test_start "track_cost" "Test cost tracking"
    
    setup_aws_service_tests
    
    # Initialize service
    init_unity_aws_service "test-service" >/dev/null 2>&1
    
    # Test cost tracking
    track_cost "ec2-spot" "i-1234567890abcdef0" "0.10"
    
    # Verify cost tracking completes without error
    if [[ $? -eq 0 ]]; then
        test_pass "Cost tracking completed successfully"
    else
        test_fail "Cost tracking failed"
    fi
    
    cleanup_aws_service_tests
}

test_list_stack_resources() {
    test_start "list_stack_resources" "Test listing stack resources"
    
    setup_aws_service_tests
    
    # Initialize service and track some resources
    init_unity_aws_service "test-service" >/dev/null 2>&1
    track_resource "ec2" "i-1234567890abcdef0" "test-stack"
    track_resource "vpc" "vpc-12345678" "test-stack"
    
    # Test resource listing
    if list_stack_resources "test-stack" >/dev/null 2>&1; then
        test_pass "Stack resources listed successfully"
    else
        test_fail "Stack resources listing failed"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_find_existing_vpc() {
    test_start "find_existing_vpc" "Test finding existing VPC"
    
    setup_aws_service_tests
    
    # Test finding existing VPC
    local vpc_id
    vpc_id=$(find_existing_vpc "test-stack" 2>/dev/null)
    
    # Since we're mocking, we expect either empty result or our mock VPC ID
    if [[ -z "$vpc_id" || "$vpc_id" == "vpc-12345678" ]]; then
        test_pass "VPC search completed successfully"
    else
        test_fail "VPC search returned unexpected result: $vpc_id"
    fi
    
    cleanup_aws_service_tests
}

test_get_ondemand_price() {
    test_start "get_ondemand_price" "Test getting on-demand price"
    
    setup_aws_service_tests
    
    # Test price retrieval for known instance type
    local price
    price=$(get_ondemand_price "t3.medium" 2>/dev/null)
    
    if [[ -n "$price" && "$price" != "0" ]]; then
        test_pass "On-demand price retrieved successfully: \$$price"
    else
        test_fail "On-demand price retrieval failed: $price"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_aws_service_error_handling() {
    test_start "aws_service_error_handling" "Test Unity AWS service error handling"
    
    setup_aws_service_tests
    
    # Mock AWS CLI to return error
    mock_function "aws" 'exit 1'
    
    # Test error handling in EC2 launch
    if launch_ec2_instance "t3.medium" "spot" "test-stack" >/dev/null 2>&1; then
        test_fail "Expected function to fail with mocked AWS error"
    else
        test_pass "Function correctly handled AWS CLI error"
    fi
    
    cleanup_aws_service_tests
}

test_invalid_parameters() {
    test_start "invalid_parameters" "Test handling of invalid parameters"
    
    setup_aws_service_tests
    
    # Test with empty stack name
    if launch_ec2_instance "t3.medium" "spot" "" >/dev/null 2>&1; then
        test_warn "Function should validate empty stack name"
    else
        test_pass "Function correctly rejected empty stack name"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_service_performance() {
    test_start "service_performance" "Test Unity AWS service performance"
    
    setup_aws_service_tests
    
    # Initialize service and measure performance
    local start_time=$(date +%s%N)
    init_unity_aws_service "test-service" >/dev/null 2>&1
    local end_time=$(date +%s%N)
    
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Check if initialization is reasonably fast (under 5 seconds)
    if [[ $duration_ms -lt 5000 ]]; then
        test_pass "Service initialization performance acceptable: ${duration_ms}ms"
    else
        test_warn "Service initialization slow: ${duration_ms}ms"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# INTEGRATION READINESS TESTS
# =============================================================================

test_unity_cli_integration() {
    test_start "unity_cli_integration" "Test Unity CLI integration readiness"
    
    setup_aws_service_tests
    
    # Test if CLI function exists and works
    if command -v unity_aws >/dev/null 2>&1; then
        if unity_aws help >/dev/null 2>&1; then
            test_pass "Unity CLI integration ready"
        else
            test_fail "Unity CLI help command failed"
        fi
    else
        test_skip "Unity CLI function not available"
    fi
    
    cleanup_aws_service_tests
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

# Register all test functions with the Unity test framework
unity_register_service_test "unity-aws-service" "$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh" \
    "init_unity_aws_service,launch_ec2_instance,create_or_get_vpc,create_alb,create_cloudfront,create_or_get_efs" \
    "service-unit"

# Run all test functions
main() {
    log_info "Running Unity AWS Service Unit Tests"
    
    # Initialization tests
    test_unity_aws_service_init
    test_unity_aws_service_version
    
    # EC2 management tests
    test_launch_ec2_instance_spot
    test_launch_ec2_instance_ondemand
    test_launch_ec2_instance_invalid_type
    test_get_optimal_spot_config
    
    # VPC management tests
    test_create_or_get_vpc
    test_get_available_cidr
    
    # ALB management tests
    test_create_alb
    
    # CloudFront management tests
    test_create_cloudfront
    
    # EFS management tests
    test_create_or_get_efs
    
    # Cost optimization tests
    test_calculate_deployment_cost
    test_optimize_deployment_costs
    
    # Quota management tests
    test_check_ec2_quota
    test_check_vpc_quota
    test_check_alb_quota
    
    # Resource management tests
    test_track_resource
    test_track_cost
    test_list_stack_resources
    
    # Utility function tests
    test_find_existing_vpc
    test_get_ondemand_price
    
    # Error handling tests
    test_aws_service_error_handling
    test_invalid_parameters
    
    # Performance tests
    test_service_performance
    
    # Integration readiness tests
    test_unity_cli_integration
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi