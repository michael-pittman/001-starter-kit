#!/usr/bin/env bash
# =============================================================================
# Simple test script for deployment type selection
# Validates Story 3.3 implementation
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_NAME="test-deployment-types-simple.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" =~ "$needle" ]]; then
        echo "✓ $message"
        ((TESTS_PASSED++))
    else
        echo "✗ $message"
        echo "  Expected to find: $needle"
        echo "  In: $haystack"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_help_output() {
    echo "Testing help output for deployment types..."
    
    local help_output
    help_output=$("$PROJECT_ROOT/deploy.sh" --help 2>&1 || true)
    
    # Check for deployment types section
    assert_contains "$help_output" "DEPLOYMENT TYPES:" "Help contains deployment types section"
    assert_contains "$help_output" "--type spot" "Help contains spot type"
    assert_contains "$help_output" "--type alb" "Help contains alb type"
    assert_contains "$help_output" "--type cdn" "Help contains cdn type"
    assert_contains "$help_output" "--type full" "Help contains full type"
    
    # Check for deployment type details
    assert_contains "$help_output" "70% cost savings" "Help mentions spot savings"
    assert_contains "$help_output" "High-availability" "Help mentions high availability"
    assert_contains "$help_output" "Global" "Help mentions global distribution"
    assert_contains "$help_output" "Enterprise" "Help mentions enterprise features"
}

test_invalid_deployment_type() {
    echo "Testing invalid deployment type handling..."
    
    local error_output
    error_output=$("$PROJECT_ROOT/deploy.sh" --type invalid test-stack 2>&1 || true)
    
    assert_contains "$error_output" "Invalid deployment type: invalid" "Invalid type error message"
    assert_contains "$error_output" "Valid types: spot, alb, cdn, full" "Valid types listed"
}

test_deployment_type_validation() {
    echo "Testing deployment type argument validation..."
    
    # Test each valid deployment type
    for type in spot alb cdn full; do
        local validate_output
        validate_output=$("$PROJECT_ROOT/deploy.sh" --type "$type" --validate test-stack 2>&1 || true)
        
        # Check that the command accepts the type (no "Invalid deployment type" error)
        if [[ ! "$validate_output" =~ "Invalid deployment type" ]]; then
            echo "✓ Deployment type '$type' is accepted"
            ((TESTS_PASSED++))
        else
            echo "✗ Deployment type '$type' was rejected"
            ((TESTS_FAILED++))
        fi
    done
}

test_version_output() {
    echo "Testing version output..."
    
    local version_output
    version_output=$("$PROJECT_ROOT/deploy.sh" --version 2>&1 || true)
    
    assert_contains "$version_output" "GeuseMaker Deployment Orchestrator" "Version contains project name"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "=========================================="
    echo "Deployment Type Selection Tests (Simple)"
    echo "=========================================="
    echo ""
    
    # Run tests
    test_help_output
    echo ""
    test_invalid_deployment_type
    echo ""
    test_deployment_type_validation
    echo ""
    test_version_output
    
    # Show summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        echo "✓ All tests passed!"
        exit 0
    else
        echo ""
        echo "✗ Some tests failed!"
        exit 1
    fi
}

# Execute main function
main "$@"