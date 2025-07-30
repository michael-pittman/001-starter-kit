#!/usr/bin/env bash
# =============================================================================
# Test Framework for Error Message Clarity
# Tests the clear error message implementation
# Part of Story 5.3 Task 3
# =============================================================================

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework with bash 3 compatibility
export BASH_VERSION_COMPAT="3"
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# Source error modules
source "$PROJECT_ROOT/lib/modules/errors/error_types.sh"
source "$PROJECT_ROOT/lib/modules/errors/clear_messages.sh"

# Test suite metadata
TEST_SUITE_NAME="Error Message Clarity Tests"
TEST_SUITE_DESC="Tests for user-friendly error messages and recovery guidance"

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

capture_error_output() {
    local error_function="$1"
    shift
    local args=("$@")
    
    local temp_file
    temp_file=$(mktemp)
    
    # Capture stderr output
    {
        "$error_function" "${args[@]}" 2>&1 || true
    } > "$temp_file" 2>&1
    
    cat "$temp_file"
    rm -f "$temp_file"
}

assert_error_contains() {
    local output="$1"
    local expected="$2"
    local description="${3:-Error should contain expected text}"
    
    if [[ "$output" == *"$expected"* ]]; then
        test_pass "$description"
    else
        test_fail "$description" "Expected to find '$expected' in output"
    fi
}

assert_error_clarity_score() {
    local message="$1"
    local min_score="$2"
    local description="${3:-Message should have minimum clarity score}"
    
    local score
    score=$(test_message_clarity "$message")
    local numeric_score="${score%%/*}"
    
    if [[ $numeric_score -ge $min_score ]]; then
        test_pass "$description (score: $score)"
    else
        test_fail "$description" "Score $score is below minimum $min_score"
    fi
}

# =============================================================================
# TEST CASES
# =============================================================================

test_error_message_format() {
    test_start "Error message format validation"
    
    # Test that clear messages include all required components
    local message
    message=$(format_clear_error_message "EC2_INSUFFICIENT_CAPACITY" "g4dn.xlarge in us-east-1")
    
    # Should include what happened
    assert_error_contains "$message" "Unable to launch EC2 instance" \
        "Message should explain what happened"
    
    # Should include why
    assert_error_contains "$message" "Why" \
        "Message should explain why the error occurred"
    
    # Should include how to fix
    assert_error_contains "$message" "How to fix" \
        "Message should provide fix instructions"
    
    # Should include example
    assert_error_contains "$message" "Example" \
        "Message should provide an example"
    
    test_end
}

test_error_recovery_suggestions() {
    test_start "Error recovery suggestions"
    
    # Test retry suggestion
    local suggestion
    suggestion=$(get_clear_recovery_suggestion "$RECOVERY_RETRY" "NETWORK_ERROR")
    assert_error_contains "$suggestion" "Try running the command again" \
        "Retry suggestion should be clear"
    
    # Test manual intervention suggestion
    suggestion=$(get_clear_recovery_suggestion "$RECOVERY_MANUAL" "AUTH_ERROR")
    assert_error_contains "$suggestion" "Manual intervention required" \
        "Manual intervention suggestion should be clear"
    
    # Test fallback suggestion
    suggestion=$(get_clear_recovery_suggestion "$RECOVERY_FALLBACK" "CAPACITY_ERROR")
    assert_error_contains "$suggestion" "automatically try an alternative" \
        "Fallback suggestion should be clear"
    
    test_end
}

test_error_message_clarity_levels() {
    test_start "Error message clarity levels"
    
    # Test technical level
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_TECHNICAL
    local tech_msg
    tech_msg=$(format_clear_error_message "AUTH_INVALID_CREDENTIALS" "EC2")
    assert_error_contains "$tech_msg" "AUTH_INVALID_CREDENTIALS" \
        "Technical format should include error code"
    
    # Test standard level
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_STANDARD
    local std_msg
    std_msg=$(format_clear_error_message "AUTH_INVALID_CREDENTIALS" "EC2")
    assert_error_contains "$std_msg" "Why:" \
        "Standard format should include why section"
    assert_error_contains "$std_msg" "Fix:" \
        "Standard format should include fix section"
    
    # Test user-friendly level
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_USER_FRIENDLY
    local friendly_msg
    friendly_msg=$(format_clear_error_message "AUTH_INVALID_CREDENTIALS" "EC2")
    assert_error_contains "$friendly_msg" "What happened:" \
        "User-friendly format should include what happened"
    assert_error_contains "$friendly_msg" "📋" \
        "User-friendly format should include emoji indicators"
    
    test_end
}

test_error_message_clarity_scoring() {
    test_start "Error message clarity scoring"
    
    # Test technical jargon detection
    local tech_message="API error: SDK timeout errno 500"
    local score
    score=$(test_message_clarity "$tech_message")
    local numeric_score="${score%%/*}"
    test_assert "[[ $numeric_score -lt 5 ]]" \
        "Technical message should have low clarity score"
    
    # Test user-friendly message
    local friendly_message="Unable to connect to AWS. Try checking your internet connection. Example: ping google.com"
    assert_error_clarity_score "$friendly_message" 6 \
        "User-friendly message should have high clarity score"
    
    # Test actionable guidance
    local actionable_message="Check your AWS credentials by running 'aws configure'"
    assert_error_contains "$actionable_message" "Check" \
        "Actionable messages should contain action verbs"
    
    test_end
}

test_specific_error_types() {
    test_start "Specific error type messages"
    
    # Set user-friendly mode
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_USER_FRIENDLY
    
    # Test EC2 capacity error
    local output
    output=$(capture_error_output error_ec2_insufficient_capacity "g4dn.xlarge" "us-east-1")
    assert_error_contains "$output" "doesn't have enough capacity" \
        "EC2 capacity error should explain the issue clearly"
    assert_error_contains "$output" "Try a different instance type" \
        "EC2 capacity error should suggest alternatives"
    
    # Test authentication error
    output=$(capture_error_output error_auth_invalid_credentials "EC2")
    assert_error_contains "$output" "authentication failed" \
        "Auth error should be clear about authentication"
    assert_error_contains "$output" "aws configure" \
        "Auth error should suggest configuration command"
    
    # Test network error
    output=$(capture_error_output error_network_vpc_not_found "vpc-12345")
    assert_error_contains "$output" "Cannot find the specified VPC" \
        "Network error should clearly state the problem"
    assert_error_contains "$output" "Check the VPC ID" \
        "Network error should suggest verification steps"
    
    test_end
}

test_error_context_integration() {
    test_start "Error context integration"
    
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_USER_FRIENDLY
    
    # Test context substitution
    local message
    message=$(format_clear_error_message "EC2_INSUFFICIENT_CAPACITY" "g4dn.xlarge in us-east-1")
    assert_error_contains "$message" "g4dn.xlarge" \
        "Error message should include context (instance type)"
    assert_error_contains "$message" "us-east-1" \
        "Error message should include context (region)"
    
    test_end
}

test_interactive_resolution_features() {
    test_start "Interactive resolution features"
    
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_USER_FRIENDLY
    
    # Test retry prompt
    local prompt
    prompt=$(offer_interactive_resolution "EC2_INSUFFICIENT_CAPACITY" "$RECOVERY_RETRY" 2>&1 || true)
    assert_error_contains "$prompt" "retry" \
        "Retry prompt should offer retry option"
    
    # Test manual intervention prompt
    prompt=$(offer_interactive_resolution "AUTH_INVALID_CREDENTIALS" "$RECOVERY_MANUAL" 2>&1 || true)
    assert_error_contains "$prompt" "troubleshooting" \
        "Manual prompt should offer troubleshooting"
    
    test_end
}

test_progress_context_messages() {
    test_start "Progress and context messages"
    
    ERROR_MESSAGE_CLARITY=$MSG_CLARITY_USER_FRIENDLY
    
    # Test progress indication
    local output
    output=$(show_error_context_progress "Launching EC2 instance" 2 5 2>&1)
    assert_error_contains "$output" "Step 2 of 5" \
        "Progress should show current step"
    assert_error_contains "$output" "Launching EC2 instance" \
        "Progress should show operation"
    
    # Test operation context
    output=$(provide_operation_context "Attempting spot instance launch" "high" 2>&1)
    assert_error_contains "$output" "might fail" \
        "High-risk operations should warn about potential failure"
    
    test_end
}

test_error_message_consistency() {
    test_start "Error message consistency"
    
    # Ensure all predefined errors have clear messages
    local errors=(
        "EC2_INSUFFICIENT_CAPACITY"
        "EC2_INSTANCE_LIMIT_EXCEEDED"
        "NETWORK_VPC_NOT_FOUND"
        "AUTH_INVALID_CREDENTIALS"
        "AUTH_INSUFFICIENT_PERMISSIONS"
        "CONFIG_MISSING_PARAMETER"
        "DEPENDENCY_NOT_READY"
        "TIMEOUT_OPERATION"
    )
    
    for error_code in "${errors[@]}"; do
        if [[ -n "${CLEAR_ERROR_MESSAGES[$error_code]:-}" ]]; then
            test_pass "Clear message defined for $error_code"
        else
            test_fail "Clear message missing for $error_code"
        fi
    done
    
    test_end
}

test_error_message_performance() {
    test_start "Error message performance"
    
    # Test that error formatting doesn't significantly impact performance
    local start_time end_time duration
    
    start_time=$(date +%s.%N)
    for i in {1..100}; do
        format_clear_error_message "EC2_INSUFFICIENT_CAPACITY" "test" >/dev/null 2>&1
    done
    end_time=$(date +%s.%N)
    
    duration=$(echo "$end_time - $start_time" | bc)
    
    # Should complete 100 formats in under 1 second
    if (( $(echo "$duration < 1.0" | bc -l) )); then
        test_pass "Error formatting performance is acceptable ($duration seconds for 100 operations)"
    else
        test_fail "Error formatting too slow" "$duration seconds for 100 operations"
    fi
    
    test_end
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_suite_start
    
    # Run all tests
    test_error_message_format
    test_error_recovery_suggestions
    test_error_message_clarity_levels
    test_error_message_clarity_scoring
    test_specific_error_types
    test_error_context_integration
    test_interactive_resolution_features
    test_progress_context_messages
    test_error_message_consistency
    test_error_message_performance
    
    test_suite_end
}

# Execute tests
main "$@"