#!/usr/bin/env bash
# =============================================================================
# Comprehensive Test for deploy-spot-cdn Command
# Tests all potential failure paths and validation phases
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

# Get script directory and project root

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-deploy-spot-cdn-comprehensive.sh" "core/variables" "core/logging"

TEST_NAME="deploy-spot-cdn-comprehensive"
STACK_NAME="test-geuse002"
REGION="us-east-1"

# Test results tracking
declare -A TEST_RESULTS
declare -A FAILURE_PATHS
declare -A RECOVERY_SUGGESTIONS

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

# Test 1: Security Validation
test_security_validation() {
    local test_name="security_validation"
    log "Running test: $test_name"
    
    if ! bash -c 'source lib/deployment-validation.sh && validate_deployment_prerequisites "test-stack" "us-east-1"'; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="Security validation failed"
        RECOVERY_SUGGESTIONS["$test_name"]="Check file permissions, dependencies, and security settings"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Security validation passed"
}

# Test 2: AWS CLI Installation Check
test_aws_cli_installation() {
    local test_name="aws_cli_installation"
    log "Running test: $test_name"
    
    if ! command -v aws >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI not installed"
        RECOVERY_SUGGESTIONS["$test_name"]="Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
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

# Test 3: AWS Credentials Validation
test_aws_credentials() {
    local test_name="aws_credentials"
    log "Running test: $test_name"
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS credentials not configured or invalid"
        RECOVERY_SUGGESTIONS["$test_name"]="Run 'aws configure' or set AWS_PROFILE environment variable"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ AWS credentials validation passed"
}

# Test 4: AWS CLI Demo Script Functionality
test_aws_cli_demo_script() {
    local test_name="aws_cli_demo_script"
    log "Running test: $test_name"
    
    # Test if the script exists and is executable (now in archive)
    if [[ ! -x "$PROJECT_ROOT/archive/demos/aws-cli-v2-demo.sh" ]]; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI demo script not executable"
        RECOVERY_SUGGESTIONS["$test_name"]="Run 'chmod +x archive/demos/aws-cli-v2-demo.sh'"
        return 1
    fi
    
    # Test script syntax
    if ! bash -n "$PROJECT_ROOT/archive/demos/aws-cli-v2-demo.sh"; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="AWS CLI demo script has syntax errors"
        RECOVERY_SUGGESTIONS["$test_name"]="Fix syntax errors in archive/demos/aws-cli-v2-demo.sh"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ AWS CLI demo script validation passed"
}

# Test 5: Deployment Script Validation
test_deployment_script() {
    local test_name="deployment_script"
    log "Running test: $test_name"
    
    if [[ ! -x "$PROJECT_ROOT/scripts/deploy-spot-cdn-enhanced.sh" ]]; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="Deployment script not executable"
        RECOVERY_SUGGESTIONS["$test_name"]="Run 'chmod +x scripts/deploy-spot-cdn-enhanced.sh'"
        return 1
    fi
    
    # Test script syntax
    if ! bash -n "$PROJECT_ROOT/scripts/deploy-spot-cdn-enhanced.sh"; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="Deployment script has syntax errors"
        RECOVERY_SUGGESTIONS["$test_name"]="Fix syntax errors in deploy-spot-cdn-enhanced.sh"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Deployment script validation passed"
}

# Test 6: Required Libraries Check
test_required_libraries() {
    local test_name="required_libraries"
    log "Running test: $test_name"
    
    local required_libs=(
        "lib/error-handling.sh"
        "lib/aws-deployment-common.sh"
        "lib/aws-cli-v2.sh"
        "lib/deployment-validation.sh"
    )
    
    for lib in "${required_libs[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$lib" ]]; then
            TEST_RESULTS["$test_name"]="FAILED"
            FAILURE_PATHS["$test_name"]="Required library missing: $lib"
            RECOVERY_SUGGESTIONS["$test_name"]="Restore missing library file: $lib"
            return 1
        fi
        
        # Test if library can be sourced
        if ! bash -c "source '$PROJECT_ROOT/$lib' >/dev/null 2>&1"; then
            TEST_RESULTS["$test_name"]="FAILED"
            FAILURE_PATHS["$test_name"]="Library has errors: $lib"
            RECOVERY_SUGGESTIONS["$test_name"]="Fix errors in library: $lib"
            return 1
        fi
    done
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Required libraries check passed"
}

# Test 7: Makefile Target Validation
test_makefile_target() {
    local test_name="makefile_target"
    log "Running test: $test_name"
    
    if ! make -n deploy-spot-cdn STACK_NAME="$STACK_NAME" >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="Makefile target validation failed"
        RECOVERY_SUGGESTIONS["$test_name"]="Check Makefile syntax and target dependencies"
        return 1
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Makefile target validation passed"
}

# Test 8: AWS Service Quotas Check
test_aws_service_quotas() {
    local test_name="aws_service_quotas"
    log "Running test: $test_name"
    
    # Check if we can query AWS service quotas
    if ! aws service-quotas list-services --region "$REGION" --max-items 1 >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="WARNING"
        FAILURE_PATHS["$test_name"]="Cannot query AWS service quotas"
        RECOVERY_SUGGESTIONS["$test_name"]="Check IAM permissions for service-quotas"
        return 0  # Warning, not failure
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ AWS service quotas check passed"
}

# Test 9: Network Connectivity
test_network_connectivity() {
    local test_name="network_connectivity"
    log "Running test: $test_name"
    
    # Test basic internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="FAILED"
        FAILURE_PATHS["$test_name"]="No internet connectivity"
        RECOVERY_SUGGESTIONS["$test_name"]="Check network connection and firewall settings"
        return 1
    fi
    
    # Test AWS endpoint connectivity
    if ! curl -s --max-time 10 https://ec2.$REGION.amazonaws.com >/dev/null 2>&1; then
        TEST_RESULTS["$test_name"]="WARNING"
        FAILURE_PATHS["$test_name"]="Cannot reach AWS EC2 endpoint"
        RECOVERY_SUGGESTIONS["$test_name"]="Check firewall/proxy settings for AWS endpoints"
        return 0  # Warning, not failure
    fi
    
    TEST_RESULTS["$test_name"]="PASSED"
    success "✓ Network connectivity check passed"
}

# =============================================================================
# COMPREHENSIVE FAILURE PATH ANALYSIS
# =============================================================================

analyze_failure_paths() {
    log "=== Comprehensive Failure Path Analysis ==="
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local warning_tests=0
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        ((total_tests++))
        case "${TEST_RESULTS[$test_name]}" in
            "PASSED")
                ((passed_tests++))
                ;;
            "FAILED")
                ((failed_tests++))
                error "❌ Test failed: $test_name"
                error "   Failure: ${FAILURE_PATHS[$test_name]}"
                error "   Recovery: ${RECOVERY_SUGGESTIONS[$test_name]}"
                ;;
            "WARNING")
                ((warning_tests++))
                warning "⚠️  Test warning: $test_name"
                warning "   Issue: ${FAILURE_PATHS[$test_name]}"
                warning "   Suggestion: ${RECOVERY_SUGGESTIONS[$test_name]}"
                ;;
        esac
    done
    
    echo
    log "=== Test Summary ==="
    info "Total tests: $total_tests"
    success "Passed: $passed_tests"
    if [[ $failed_tests -gt 0 ]]; then
        error "Failed: $failed_tests"
    fi
    if [[ $warning_tests -gt 0 ]]; then
        warning "Warnings: $warning_tests"
    fi
    
    # Determine overall status
    if [[ $failed_tests -eq 0 ]]; then
        success "✓ All critical tests passed"
        return 0
    else
        error "❌ $failed_tests critical test(s) failed"
        return 1
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log "Starting comprehensive test for deploy-spot-cdn command"
    log "Stack name: $STACK_NAME"
    log "Region: $REGION"
    echo
    
    # Run all tests
    test_security_validation
    test_aws_cli_installation
    test_aws_credentials
    test_aws_cli_demo_script
    test_deployment_script
    test_required_libraries
    test_makefile_target
    test_aws_service_quotas
    test_network_connectivity
    
    echo
    analyze_failure_paths
    
    # Generate detailed report
    generate_test_report
}

# Generate detailed test report
generate_test_report() {
    local report_file="$PROJECT_ROOT/test-reports/deploy-spot-cdn-test-report.md"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
# Deploy Spot CDN Comprehensive Test Report

**Generated:** $(date)
**Stack Name:** $STACK_NAME
**Region:** $REGION

## Test Results Summary

EOF
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local status_icon
        case "$status" in
            "PASSED") status_icon="✅" ;;
            "FAILED") status_icon="❌" ;;
            "WARNING") status_icon="⚠️" ;;
        esac
        
        cat >> "$report_file" << EOF
- $status_icon **$test_name**: $status
EOF
        
        if [[ "$status" != "PASSED" ]]; then
            cat >> "$report_file" << EOF
  - **Issue**: ${FAILURE_PATHS[$test_name]}
  - **Recovery**: ${RECOVERY_SUGGESTIONS[$test_name]}
EOF
        fi
    done
    
    cat >> "$report_file" << EOF

## Recommendations

1. **Fix all FAILED tests** before attempting deployment
2. **Address WARNING tests** for optimal performance
3. **Run this test again** after making changes
4. **Check AWS credentials** and permissions
5. **Verify network connectivity** to AWS endpoints

## Next Steps

If all tests pass:
\`\`\`bash
make deploy-spot-cdn STACK_NAME=$STACK_NAME
\`\`\`

If tests fail:
1. Follow the recovery suggestions above
2. Re-run this test: \`./tests/test-deploy-spot-cdn-comprehensive.sh\`
3. Check the detailed logs for specific error messages
EOF
    
    success "✓ Test report generated: $report_file"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
