#!/usr/bin/env bash
# =============================================================================
# Test Enhanced Deployment Script
# Validates the enhanced deployment functionality with ALB/CloudFront
# =============================================================================

# Initialize library loader
SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

# Source the errors module for version checking
if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
    source "$LIB_DIR_TEMP/modules/core/errors.sh"
else
    # Fallback warning if errors module not found
    echo "WARNING: Could not load errors module" >&2
fi

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-enhanced-deployment.sh" "core/variables" "core/logging"

TEST_STACK_NAME="test-enhanced-$(date +%s)"
ENHANCED_SCRIPT="$PROJECT_ROOT/scripts/deploy-spot-cdn-enhanced.sh"
MODULAR_SCRIPT="$PROJECT_ROOT/scripts/aws-deployment-modular.sh"

# =============================================================================
# TEST SUITES
# =============================================================================

test_enhanced_script_exists() {
    test_start "Enhanced deployment script exists"
    
    if [ -f "$ENHANCED_SCRIPT" ]; then
        test_pass "Enhanced script found"
    else
        test_fail "Enhanced script not found: $ENHANCED_SCRIPT"
    fi
}

test_enhanced_script_executable() {
    test_start "Enhanced deployment script is executable"
    
    if [ -x "$ENHANCED_SCRIPT" ]; then
        test_pass "Script is executable"
    else
        test_fail "Script is not executable"
    fi
}

test_enhanced_script_help() {
    test_start "Enhanced script help functionality"
    
    local output
    output=$("$ENHANCED_SCRIPT" --help 2>&1 || true)
    
    if echo "$output" | grep -q "Enhanced deployment script"; then
        test_pass "Help text is comprehensive"
    else
        test_fail "Help text missing or incomplete"
    fi
}

test_dry_run_mode() {
    test_start "Dry run mode"
    
    local output
    output=$("$ENHANCED_SCRIPT" --dry-run test-dry-run 2>&1 || true)
    
    if echo "$output" | grep -q "DRY RUN"; then
        test_pass "Dry run mode works correctly"
    else
        test_fail "Dry run mode not functioning"
    fi
}

test_dependency_validation() {
    test_start "AWS service dependency validation"
    
    # This test runs in dry-run mode to avoid actual AWS calls
    local output
    output=$("$ENHANCED_SCRIPT" --dry-run test-deps 2>&1 || true)
    
    if echo "$output" | grep -q "Validating AWS Service Dependencies"; then
        test_pass "Dependency validation implemented"
    else
        test_fail "Dependency validation missing"
    fi
}

test_alb_fallback_logic() {
    test_start "ALB fallback logic"
    
    # Test that the script handles ALB failures gracefully
    local output
    output=$("$ENHANCED_SCRIPT" --dry-run --no-alb test-fallback 2>&1 || true)
    
    if echo "$output" | grep -q "deployment without load balancing"; then
        test_pass "ALB fallback logic present"
    else
        test_fail "ALB fallback logic missing"
    fi
}

test_cloudfront_integration() {
    test_start "CloudFront integration"
    
    local output
    output=$("$ENHANCED_SCRIPT" --dry-run --enable-cloudfront test-cf 2>&1 || true)
    
    if echo "$output" | grep -q "CloudFront"; then
        test_pass "CloudFront integration available"
    else
        test_fail "CloudFront integration missing"
    fi
}

test_modular_script_cloudfront() {
    test_start "Modular script CloudFront support"
    
    local output
    output=$("$MODULAR_SCRIPT" --help 2>&1 || true)
    
    if echo "$output" | grep -q "cloudfront"; then
        test_pass "Modular script supports CloudFront"
    else
        test_fail "Modular script missing CloudFront support"
    fi
}

test_alb_module_enhancements() {
    test_start "ALB module enhancements"
    
    local alb_module="$PROJECT_ROOT/lib/modules/infrastructure/alb.sh"
    
    if grep -q "setup_alb_infrastructure_with_retries" "$alb_module"; then
        test_pass "ALB module has retry functionality"
    else
        test_fail "ALB module missing retry functionality"
    fi
}

test_cloudfront_module_exists() {
    test_start "CloudFront module exists"
    
    local cf_module="$PROJECT_ROOT/lib/modules/infrastructure/cloudfront.sh"
    
    if [ -f "$cf_module" ]; then
        test_pass "CloudFront module found"
    else
        test_fail "CloudFront module missing: $cf_module"
    fi
}

test_makefile_targets() {
    test_start "Makefile enhanced targets"
    
    local makefile="$PROJECT_ROOT/Makefile"
    local targets_found=0
    
    for target in "deploy-spot-cdn" "deploy-spot-cdn-multi-az" "deploy-spot-cdn-full"; do
        if grep -q "^$target:" "$makefile"; then
            ((targets_found++))
        fi
    done
    
    if [ $targets_found -eq 3 ]; then
        test_pass "All enhanced Makefile targets present"
    else
        test_fail "Missing Makefile targets (found: $targets_found/3)"
    fi
}

test_error_messages() {
    test_start "Enhanced error messages"
    
    # Test missing stack name error
    local output
    output=$("$ENHANCED_SCRIPT" 2>&1 || true)
    
    if echo "$output" | grep -q "Stack name is required"; then
        test_pass "Clear error messages implemented"
    else
        test_fail "Error messages need improvement"
    fi
}

test_deployment_plan_output() {
    test_start "Deployment plan output"
    
    local output
    output=$("$ENHANCED_SCRIPT" --dry-run test-plan 2>&1 || true)
    
    if echo "$output" | grep -q "Deployment Plan"; then
        test_pass "Deployment plan display implemented"
    else
        test_fail "Deployment plan display missing"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "=== Testing Enhanced Deployment Functionality ==="
    echo ""
    
    # Initialize test counters
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # Run all tests
    test_enhanced_script_exists
    test_enhanced_script_executable
    test_enhanced_script_help
    test_dry_run_mode
    test_dependency_validation
    test_alb_fallback_logic
    test_cloudfront_integration
    test_modular_script_cloudfront
    test_alb_module_enhancements
    test_cloudfront_module_exists
    test_makefile_targets
    test_error_messages
    test_deployment_plan_output
    
    # Print summary
    echo ""
    echo "=== Test Summary ==="
    echo "Total Tests: $TEST_COUNT"
    echo "Passed: $PASS_COUNT"
    echo "Failed: $FAIL_COUNT"
    echo ""
    
    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo "✅ All tests passed!"
        return 0
    else
        echo "❌ Some tests failed"
        return 1
    fi
}

# Execute tests
main "$@"
