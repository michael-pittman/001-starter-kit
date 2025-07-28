#!/usr/local/bin/bash
# =============================================================================
# Framework Validation Test
# Simple test to validate the enhanced testing framework functionality
# =============================================================================

set -euo pipefail

# Source the enhanced test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/shell-test-framework.sh"

# Simple validation tests
test_basic_assertions() {
    assert_equals "hello" "hello" "Basic string equality"
    assert_not_equals "hello" "world" "String inequality"
    assert_contains "hello world" "world" "String contains"
    assert_not_contains "hello world" "foo" "String not contains"
    assert_empty "" "Empty string"
    assert_not_empty "content" "Non-empty string"
}

test_file_operations() {
    local temp_file
    temp_file=$(create_temp_file "test" "content")
    assert_file_exists "$temp_file" "Temp file should exist"
    
    local temp_dir
    temp_dir=$(create_temp_dir "test")
    assert_dir_exists "$temp_dir" "Temp dir should exist"
}

test_command_assertions() {
    assert_command_succeeds "echo 'test'" "Echo should succeed"
    assert_command_fails "false" "False should fail"
    assert_output_contains "echo 'hello world'" "world" "Output should contain text"
}

test_enhanced_features() {
    # Test that enhanced features work
    if [[ -n "${TEST_SESSION_ID:-}" ]]; then
        test_pass "Session ID is set: $TEST_SESSION_ID"
    else
        test_fail "Session ID should be set"
    fi
    
    if [[ ${TEST_COUNTERS[total]} -gt 0 ]]; then
        test_pass "Test counters are working"
    else
        test_fail "Test counters should be working"
    fi
}

# Run the validation
main() {
    echo "Framework Validation Test"
    echo "========================="
    
    test_init "framework-validation" "validation"
    
    run_all_tests "test_"
    
    test_cleanup
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi