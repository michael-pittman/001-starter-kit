#!/usr/bin/env bash
# =============================================================================
# Test script for deployment type selection in deploy.sh
# Validates Story 3.3 implementation
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_NAME="test-deployment-type-selection.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_spot_deployment_type() {
    local test_name="test_spot_deployment_type"
    echo "Testing spot deployment type configuration..."
    
    # Source deploy.sh functions in a subshell to avoid execution
    (
        # Prevent main execution
        BASH_SOURCE=("dummy")
        source "$PROJECT_ROOT/deploy.sh"
    ) || true
    
    # Reset variables
    ENABLE_SPOT=false
    ENABLE_MULTI_AZ=false
    MIN_CAPACITY=1
    MAX_CAPACITY=3
    INSTANCE_TYPE="t3.micro"
    
    # Configure spot deployment
    configure_spot_deployment
    
    # Assert configurations
    assert_equals "$ENABLE_SPOT" true "$test_name: ENABLE_SPOT should be true"
    assert_equals "$ENABLE_MULTI_AZ" true "$test_name: ENABLE_MULTI_AZ should be true"
    assert_equals "$MIN_CAPACITY" 2 "$test_name: MIN_CAPACITY should be 2"
    assert_equals "$MAX_CAPACITY" 10 "$test_name: MAX_CAPACITY should be 10"
    assert_equals "$INSTANCE_TYPE" "g4dn.xlarge" "$test_name: INSTANCE_TYPE should be g4dn.xlarge"
    
    echo "✓ Spot deployment type configuration test passed"
}

test_alb_deployment_type() {
    local test_name="test_alb_deployment_type"
    echo "Testing ALB deployment type configuration..."
    
    # Source deploy.sh functions
    source "$PROJECT_ROOT/deploy.sh"
    
    # Reset variables
    ENABLE_ALB=false
    ENABLE_MULTI_AZ=false
    ENABLE_MONITORING=false
    MIN_CAPACITY=1
    MAX_CAPACITY=3
    INSTANCE_TYPE="t3.micro"
    
    # Configure ALB deployment
    configure_alb_deployment
    
    # Assert configurations
    assert_equals "$ENABLE_ALB" true "$test_name: ENABLE_ALB should be true"
    assert_equals "$ENABLE_MULTI_AZ" true "$test_name: ENABLE_MULTI_AZ should be true"
    assert_equals "$ENABLE_MONITORING" true "$test_name: ENABLE_MONITORING should be true"
    assert_equals "$MIN_CAPACITY" 2 "$test_name: MIN_CAPACITY should be 2"
    assert_equals "$MAX_CAPACITY" 8 "$test_name: MAX_CAPACITY should be 8"
    assert_equals "$INSTANCE_TYPE" "g4dn.xlarge" "$test_name: INSTANCE_TYPE should be g4dn.xlarge"
    
    echo "✓ ALB deployment type configuration test passed"
}

test_cdn_deployment_type() {
    local test_name="test_cdn_deployment_type"
    echo "Testing CDN deployment type configuration..."
    
    # Source deploy.sh functions
    source "$PROJECT_ROOT/deploy.sh"
    
    # Reset variables
    ENABLE_ALB=false
    ENABLE_CDN=false
    ENABLE_MULTI_AZ=false
    ENABLE_MONITORING=false
    MIN_CAPACITY=1
    MAX_CAPACITY=3
    INSTANCE_TYPE="t3.micro"
    
    # Configure CDN deployment
    configure_cdn_deployment
    
    # Assert configurations
    assert_equals "$ENABLE_ALB" true "$test_name: ENABLE_ALB should be true"
    assert_equals "$ENABLE_CDN" true "$test_name: ENABLE_CDN should be true"
    assert_equals "$ENABLE_MULTI_AZ" true "$test_name: ENABLE_MULTI_AZ should be true"
    assert_equals "$ENABLE_MONITORING" true "$test_name: ENABLE_MONITORING should be true"
    assert_equals "$MIN_CAPACITY" 2 "$test_name: MIN_CAPACITY should be 2"
    assert_equals "$MAX_CAPACITY" 8 "$test_name: MAX_CAPACITY should be 8"
    assert_equals "$INSTANCE_TYPE" "g4dn.xlarge" "$test_name: INSTANCE_TYPE should be g4dn.xlarge"
    
    echo "✓ CDN deployment type configuration test passed"
}

test_full_deployment_type() {
    local test_name="test_full_deployment_type"
    echo "Testing full deployment type configuration..."
    
    # Source deploy.sh functions
    source "$PROJECT_ROOT/deploy.sh"
    
    # Reset variables
    ENABLE_SPOT=false
    ENABLE_ALB=false
    ENABLE_CDN=false
    ENABLE_EFS=false
    ENABLE_MULTI_AZ=false
    ENABLE_MONITORING=false
    ENABLE_BACKUP=false
    MIN_CAPACITY=1
    MAX_CAPACITY=3
    INSTANCE_TYPE="t3.micro"
    
    # Configure full deployment
    configure_full_deployment
    
    # Assert configurations
    assert_equals "$ENABLE_SPOT" true "$test_name: ENABLE_SPOT should be true"
    assert_equals "$ENABLE_ALB" true "$test_name: ENABLE_ALB should be true"
    assert_equals "$ENABLE_CDN" true "$test_name: ENABLE_CDN should be true"
    assert_equals "$ENABLE_EFS" true "$test_name: ENABLE_EFS should be true"
    assert_equals "$ENABLE_MULTI_AZ" true "$test_name: ENABLE_MULTI_AZ should be true"
    assert_equals "$ENABLE_MONITORING" true "$test_name: ENABLE_MONITORING should be true"
    assert_equals "$ENABLE_BACKUP" true "$test_name: ENABLE_BACKUP should be true"
    assert_equals "$MIN_CAPACITY" 2 "$test_name: MIN_CAPACITY should be 2"
    assert_equals "$MAX_CAPACITY" 10 "$test_name: MAX_CAPACITY should be 10"
    assert_equals "$INSTANCE_TYPE" "g4dn.xlarge" "$test_name: INSTANCE_TYPE should be g4dn.xlarge"
    
    echo "✓ Full deployment type configuration test passed"
}

test_deployment_type_argument_parsing() {
    local test_name="test_deployment_type_argument_parsing"
    echo "Testing deployment type argument parsing..."
    
    # Test spot type via --type argument
    output=$("$PROJECT_ROOT/deploy.sh" --type spot --dry-run test-stack 2>&1 || true)
    if [[ "$output" =~ "spot" ]]; then
        echo "✓ --type spot argument parsed correctly"
    else
        echo "✗ --type spot argument parsing failed"
        exit 1
    fi
    
    # Test alb type via --type argument
    output=$("$PROJECT_ROOT/deploy.sh" --type alb --dry-run test-stack 2>&1 || true)
    if [[ "$output" =~ "alb" ]]; then
        echo "✓ --type alb argument parsed correctly"
    else
        echo "✗ --type alb argument parsing failed"
        exit 1
    fi
    
    # Test cdn type via --type argument
    output=$("$PROJECT_ROOT/deploy.sh" --type cdn --dry-run test-stack 2>&1 || true)
    if [[ "$output" =~ "cdn" ]]; then
        echo "✓ --type cdn argument parsed correctly"
    else
        echo "✗ --type cdn argument parsing failed"
        exit 1
    fi
    
    # Test full type via --type argument
    output=$("$PROJECT_ROOT/deploy.sh" --type full --dry-run test-stack 2>&1 || true)
    if [[ "$output" =~ "full" ]]; then
        echo "✓ --type full argument parsed correctly"
    else
        echo "✗ --type full argument parsing failed"
        exit 1
    fi
    
    echo "✓ Deployment type argument parsing test passed"
}

test_invalid_deployment_type() {
    local test_name="test_invalid_deployment_type"
    echo "Testing invalid deployment type handling..."
    
    # Test invalid type
    output=$("$PROJECT_ROOT/deploy.sh" --type invalid test-stack 2>&1 || true)
    if [[ "$output" =~ "Invalid deployment type: invalid" ]]; then
        echo "✓ Invalid deployment type handled correctly"
    else
        echo "✗ Invalid deployment type not handled properly"
        exit 1
    fi
    
    echo "✓ Invalid deployment type test passed"
}

test_help_documentation() {
    local test_name="test_help_documentation"
    echo "Testing help documentation..."
    
    # Get help output
    output=$("$PROJECT_ROOT/deploy.sh" --help 2>&1 || true)
    
    # Check for deployment types in help
    assert_contains "$output" "DEPLOYMENT TYPES:" "$test_name: Help should contain DEPLOYMENT TYPES section"
    assert_contains "$output" "--type spot" "$test_name: Help should contain spot type"
    assert_contains "$output" "--type alb" "$test_name: Help should contain alb type"
    assert_contains "$output" "--type cdn" "$test_name: Help should contain cdn type"
    assert_contains "$output" "--type full" "$test_name: Help should contain full type"
    
    # Check for deployment type details
    assert_contains "$output" "DEPLOYMENT TYPE DETAILS:" "$test_name: Help should contain type details"
    assert_contains "$output" "70% cost savings" "$test_name: Help should mention spot savings"
    assert_contains "$output" "High-availability production workloads" "$test_name: Help should mention ALB use case"
    assert_contains "$output" "Global applications" "$test_name: Help should mention CDN use case"
    assert_contains "$output" "Mission-critical enterprise applications" "$test_name: Help should mention full use case"
    
    echo "✓ Help documentation test passed"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "=========================================="
    echo "Deployment Type Selection Tests"
    echo "=========================================="
    echo ""
    
    # Initialize test framework
    init_test_framework "deployment-type-selection"
    
    # Run tests
    run_test test_spot_deployment_type
    run_test test_alb_deployment_type
    run_test test_cdn_deployment_type
    run_test test_full_deployment_type
    run_test test_deployment_type_argument_parsing
    run_test test_invalid_deployment_type
    run_test test_help_documentation
    
    # Show results
    show_test_summary
    
    echo ""
    echo "=========================================="
    echo "All deployment type selection tests completed!"
    echo "=========================================="
}

# Execute main function
main "$@"