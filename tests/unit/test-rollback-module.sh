#!/usr/bin/env bash
# =============================================================================
# Unit Test: Rollback Module
# Tests the deployment rollback module functionality
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework and dependencies
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/variable-management.sh"

source "$PROJECT_ROOT/lib/modules/deployment/rollback.sh"

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

TEST_STACK="test-rollback-unit"
export VARIABLE_STORE_FILE="/tmp/test-rollback-unit.json"

# Mock AWS CLI for unit testing
aws() {
    echo "MOCK: aws $*" >&2
    return 0
}

# =============================================================================
# UNIT TESTS
# =============================================================================

test_rollback_trigger_registration() {
    test_start "Rollback Trigger Registration"
    
    # Register a custom trigger
    register_rollback_trigger "custom_test" "test_condition" "test_action" 100
    
    if [[ -n "${ROLLBACK_TRIGGERS[custom_test]}" ]]; then
        test_pass "Trigger registered successfully"
    else
        test_fail "Trigger registration failed"
    fi
}

test_rollback_state_transitions() {
    test_start "Rollback State Transitions"
    
    # Test state transitions
    set_rollback_state "$TEST_STACK" "$ROLLBACK_STATE_INITIALIZING"
    local state=$(get_rollback_state "$TEST_STACK")
    
    if [[ "$state" == "initializing" ]]; then
        test_pass "State transition successful"
    else
        test_fail "State transition failed: expected 'initializing', got '$state'"
    fi
}

test_rollback_snapshot_creation() {
    test_start "Rollback Snapshot Creation"
    
    # Create test data
    mkdir -p "${CONFIG_DIR:-./config}/rollback_snapshots"
    set_variable "TEST_VAR" "test_value" "$VARIABLE_SCOPE_STACK"
    
    # Create snapshot
    if create_rollback_snapshot "$TEST_STACK" "unit_test"; then
        test_pass "Snapshot created successfully"
    else
        test_fail "Snapshot creation failed"
    fi
}

test_resource_deletion_retry() {
    test_start "Resource Deletion Retry Logic"
    
    # Mock a failing delete function
    delete_resource() {
        log_info "Mock delete attempt for $1: $2" "TEST"
        return 1
    }
    
    # Test retry with immediate failure (no actual retries in unit test)
    if ! delete_resource_with_retry "test_type" "test_id" 1 0; then
        test_pass "Retry logic handles failures correctly"
    else
        test_fail "Retry logic did not fail as expected"
    fi
}

test_rollback_metrics_recording() {
    test_start "Rollback Metrics Recording"
    
    # Record test metrics
    ROLLBACK_METRICS["${TEST_STACK}_start_time"]=$(date +%s)
    ROLLBACK_METRICS["${TEST_STACK}_trigger"]="unit_test"
    
    # Record success
    record_rollback_success "$TEST_STACK"
    
    if [[ "${ROLLBACK_METRICS["${TEST_STACK}_status"]}" == "success" ]]; then
        test_pass "Metrics recorded successfully"
    else
        test_fail "Metrics recording failed"
    fi
}

test_rollback_verification_logic() {
    test_start "Rollback Verification Logic"
    
    # Mock empty resource list
    list_stack_resources() {
        echo ""
    }
    
    # Mock empty variables
    get_stack_variables() {
        echo "{}"
    }
    
    if verify_rollback "$TEST_STACK" "test"; then
        test_pass "Verification logic works correctly"
    else
        test_fail "Verification logic failed"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup() {
    rm -f "$VARIABLE_STORE_FILE"
    rm -rf "${CONFIG_DIR:-./config}/rollback_snapshots/test-*"
    rm -rf "${CONFIG_DIR:-./config}/rollback_reports/rollback_test-*"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting Rollback Module Unit Tests" "TEST"
    
    # Initialize test counters
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Create test environment
    mkdir -p "$(dirname "$VARIABLE_STORE_FILE")"
    echo '{"stacks":{}}' > "$VARIABLE_STORE_FILE"
    
    # Run tests
    test_section "Rollback Module Unit Tests"
    test_rollback_trigger_registration
    test_rollback_state_transitions
    test_rollback_snapshot_creation
    test_resource_deletion_retry
    test_rollback_metrics_recording
    test_rollback_verification_logic
    
    # Cleanup
    cleanup
    
    # Print summary
    test_summary
    
    # Return status
    [[ $TESTS_FAILED -eq 0 ]] && return 0 || return 1
}

# Execute tests
main "$@"