#!/usr/bin/env bash
# =============================================================================
# Simple Test for deploy-spot-cdn Command - Core Failure Paths
# =============================================================================

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load required libraries
source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

set -euo pipefail

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

STACK_NAME="test-geuse002"
REGION="us-east-1"

# Test results tracking
declare -A TEST_RESULTS
declare -A FAILURE_PATHS
declare -A RECOVERY_SUGGESTIONS

# =============================================================================
# CORE FAILURE PATH TESTS
# =============================================================================

# Test 1: Bash Version Validation (CRITICAL)
test_bash_version() {
    local test_name="bash_version"
    log "Testing: $test_name"
    
    if ! bash -c 'source lib/modules/core/bash_version.sh && check_bash_version_enhanced'; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="Bash version check failed"
        RECOVERY_SUGGESTIONS["$test_name"]="Upgrade bash to 5.3+ or fix bash version module"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Bash version validation passed"
}

# Test 2: AWS CLI Demo Script (CRITICAL)
test_aws_cli_demo_script() {
    local test_name="aws_cli_demo_script"
    log "Testing: $test_name"
    
    # Test if script exists and is executable
    if [[ ! -x "$PROJECT_ROOT/scripts/aws-cli-v2-demo.sh" ]]; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI demo script not executable"
        RECOVERY_SUGGESTIONS["$test_name"]="Run 'chmod +x scripts/aws-cli-v2-demo.sh'"
        return 1
    fi
    
    # Test script syntax
    if ! bash -n "$PROJECT_ROOT/scripts/aws-cli-v2-demo.sh"; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI demo script has syntax errors"
        RECOVERY_SUGGESTIONS["$test_name"]="Fix syntax errors in aws-cli-v2-demo.sh"
        return 1
    fi
    
    # Test if script can be sourced without errors
    if ! bash -c "source '$PROJECT_ROOT/scripts/aws-cli-v2-demo.sh' >/dev/null 2>&1"; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI demo script has sourcing errors"
        RECOVERY_SUGGESTIONS["$test_name"]="Check library dependencies in aws-cli-v2-demo.sh"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ AWS CLI demo script validation passed"
}

# Test 3: Logging System (CRITICAL)
test_logging_system() {
    local test_name="logging_system"
    log "Testing: $test_name"
    
    # Test if log_structured function exists
    if ! declare -f log_structured >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="log_structured function not available"
        RECOVERY_SUGGESTIONS["$test_name"]="Ensure error-handling.sh is properly sourced"
        return 1
    fi
    
    # Test basic logging functionality
    if ! log_structured "INFO" "Test message" "test=true" >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="log_structured function failed"
        RECOVERY_SUGGESTIONS["$test_name"]="Check error-handling.sh implementation"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Logging system validation passed"
}

# Test 4: AWS CLI Installation (CRITICAL)
test_aws_cli_installation() {
    local test_name="aws_cli_installation"
    log "Testing: $test_name"
    
    if ! command -v aws >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI not installed"
        RECOVERY_SUGGESTIONS["$test_name"]="Install AWS CLI v2"
        return 1
    fi
    
    local aws_version
    aws_version=$(aws --version 2>&1 | head -1 | cut -d' ' -f1 | cut -d'/' -f2)
    
    if [[ ! "$aws_version" =~ ^2\. ]]; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI v1 detected ($aws_version), v2 required"
        RECOVERY_SUGGESTIONS["$test_name"]="Upgrade to AWS CLI v2"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ AWS CLI v2 installation check passed ($aws_version)"
}

# Test 5: AWS Credentials (CRITICAL)
test_aws_credentials() {
    local test_name="aws_credentials"
    log "Testing: $test_name"
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS credentials not configured or invalid"
        RECOVERY_SUGGESTIONS["$test_name"]="Run 'aws configure' or set AWS_PROFILE"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ AWS credentials validation passed"
}

# Test 6: Makefile Target (CRITICAL)
test_makefile_target() {
    local test_name="makefile_target"
    log "Testing: $test_name"
    
    if ! make -n deploy-spot-cdn STACK_NAME="$STACK_NAME" >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="Makefile target validation failed"
        RECOVERY_SUGGESTIONS["$test_name"]="Check Makefile syntax and dependencies"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Makefile target validation passed"
}

# Test 7: Required Libraries (CRITICAL)
test_required_libraries() {
    local test_name="required_libraries"
    log "Testing: $test_name"
    
    local required_libs=(
        "lib/error-handling.sh"
        "lib/aws-deployment-common.sh"
        "lib/aws-cli-v2.sh"
        "lib/modules/core/bash_version.sh"
        "lib/deployment-validation.sh"
    )
    
    for lib in "${required_libs[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$lib" ]]; then
            TEST_RESULTS["$test_name"]="FAILED"
            FAILURE_PATHS["$test_name"]="Required library missing: $lib"
            RECOVERY_SUGGESTIONS["$test_name"]="Restore missing library file: $lib"
            return 1
        fi
    done
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Required libraries check passed"
}

# =============================================================================
# FAILURE PATH ANALYSIS
# =============================================================================

analyze_failure_paths() {
    log "=== Core Failure Path Analysis ==="
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        ((total_tests++))
        case "${TEST_RESULTS[$test_name]}" in
            "PASSED")
                ((passed_tests++))
                ;;
            "FAILED")
                ((failed_tests++))
                error "❌ CRITICAL FAILURE: $test_name"
                error "   Issue: ${FAILURE_PATHS[$test_name]}"
                error "   Fix: ${RECOVERY_SUGGESTIONS[$test_name]}"
                ;;
        esac
    done
    
    echo
    log "=== Test Summary ==="
    info "Total critical tests: $total_tests"
    success "Passed: $passed_tests"
    if [[ $failed_tests -gt 0 ]]; then
        error "Failed: $failed_tests"
        echo
        error "🚨 DEPLOYMENT WILL FAIL - Fix the issues above first!"
        return 1
    else
        success "✅ All critical tests passed - deployment should work!"
        return 0
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "=== Deploy Spot CDN - Core Failure Path Test ==="
    log "Stack: $STACK_NAME"
    log "Region: $REGION"
    echo
    
    # Run all critical tests
    test_bash_version
    test_aws_cli_demo_script
    test_logging_system
    test_aws_cli_installation
    test_aws_credentials
    test_makefile_target
    test_required_libraries
    
    echo
    analyze_failure_paths
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 