#!/usr/bin/env bash

# Progress Indicator Unit Tests
# Tests all functionality of the progress indicator module

set -euo pipefail

# Load test framework
source "$(dirname "${BASH_SOURCE[0]}")/../lib/shell-test-framework.sh"

# Load the progress module
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/utils/progress.sh"

# Test suite configuration
TEST_SUITE_NAME="Progress Indicators"
TEST_SUITE_DESCRIPTION="Unit tests for progress indicator functionality"

# Test data
declare -a TEST_CASES=()

# Helper function to capture progress output
capture_progress_output() {
    local test_script="$1"
    local output_file="/tmp/progress_test_output_$$"
    
    # Run test script and capture output
    bash -c "$test_script" > "$output_file" 2>&1
    local exit_code=$?
    
    # Return output and exit code
    echo "$(cat "$output_file")"
    rm -f "$output_file"
    return $exit_code
}

# Test 1: Progress initialization
test_progress_init() {
    local test_name="Progress Initialization"
    local test_description="Test that progress_init properly initializes the progress system"
    
    # Test basic initialization
    progress_init "Test initialization"
    
    # Verify state variables
    assert_equal "$PROGRESS_CURRENT_PERCENT" "0" "Initial percentage should be 0"
    assert_equal "$PROGRESS_CURRENT_DESCRIPTION" "Test initialization" "Description should be set"
    assert_equal "$PROGRESS_IS_ACTIVE" "true" "Progress should be active"
    assert_greater_than "$PROGRESS_START_TIME" "0" "Start time should be set"
    
    # Clean up
    progress_cleanup
    
    log_test_success "$test_name"
}

# Test 2: Progress update functionality
test_progress_update() {
    local test_name="Progress Update"
    local test_description="Test that progress_update properly updates progress"
    
    # Initialize progress
    progress_init "Test update"
    
    # Test percentage updates
    progress_update 25 "Quarter complete"
    assert_equal "$PROGRESS_CURRENT_PERCENT" "25" "Percentage should be updated to 25"
    assert_equal "$PROGRESS_CURRENT_DESCRIPTION" "Quarter complete" "Description should be updated"
    
    progress_update 50 "Halfway there"
    assert_equal "$PROGRESS_CURRENT_PERCENT" "50" "Percentage should be updated to 50"
    assert_equal "$PROGRESS_CURRENT_DESCRIPTION" "Halfway there" "Description should be updated"
    
    progress_update 100 "Complete"
    assert_equal "$PROGRESS_CURRENT_PERCENT" "100" "Percentage should be updated to 100"
    
    # Clean up
    progress_cleanup
    
    log_test_success "$test_name"
}

# Test 3: Progress validation
test_progress_validation() {
    local test_name="Progress Validation"
    local test_description="Test that progress validation works correctly"
    
    # Test valid percentages
    assert_true "progress_validate_percentage 0" "0 should be valid"
    assert_true "progress_validate_percentage 50" "50 should be valid"
    assert_true "progress_validate_percentage 100" "100 should be valid"
    
    # Test invalid percentages
    assert_false "progress_validate_percentage -1" "-1 should be invalid"
    assert_false "progress_validate_percentage 101" "101 should be invalid"
    assert_false "progress_validate_percentage abc" "abc should be invalid"
    assert_false "progress_validate_percentage 50.5" "50.5 should be invalid"
    
    log_test_success "$test_name"
}

# Test 4: Milestone detection
test_progress_milestones() {
    local test_name="Progress Milestones"
    local test_description="Test that milestone detection works correctly"
    
    # Test milestone percentages
    assert_true "progress_is_milestone 0" "0 should be a milestone"
    assert_true "progress_is_milestone 25" "25 should be a milestone"
    assert_true "progress_is_milestone 50" "50 should be a milestone"
    assert_true "progress_is_milestone 75" "75 should be a milestone"
    assert_true "progress_is_milestone 87" "87 should be a milestone"
    assert_true "progress_is_milestone 100" "100 should be a milestone"
    
    # Test non-milestone percentages
    assert_false "progress_is_milestone 10" "10 should not be a milestone"
    assert_false "progress_is_milestone 30" "30 should not be a milestone"
    assert_false "progress_is_milestone 60" "60 should not be a milestone"
    assert_false "progress_is_milestone 90" "90 should not be a milestone"
    
    log_test_success "$test_name"
}

# Test 5: Progress completion
test_progress_completion() {
    local test_name="Progress Completion"
    local test_description="Test that progress completion works correctly"
    
    # Test successful completion
    progress_init "Test completion"
    progress_update 50 "Halfway"
    
    local output=$(capture_progress_output "
        source $(dirname "${BASH_SOURCE[0]}")/../../lib/utils/progress.sh
        progress_init 'Test completion'
        progress_update 50 'Halfway'
        progress_complete true 'Successfully completed'
    ")
    
    # Verify completion message contains expected elements
    assert_contains "$output" "Completed" "Output should contain 'Completed'"
    assert_contains "$output" "Successfully completed" "Output should contain description"
    assert_contains "$output" "s)" "Output should contain duration"
    
    # Test failed completion
    output=$(capture_progress_output "
        source $(dirname "${BASH_SOURCE[0]}")/../../lib/utils/progress.sh
        progress_init 'Test failure'
        progress_update 30 'Failed'
        progress_complete false 'Operation failed'
    ")
    
    assert_contains "$output" "Failed" "Output should contain 'Failed'"
    assert_contains "$output" "Operation failed" "Output should contain failure description"
    
    log_test_success "$test_name"
}

# Test 6: Progress error handling
test_progress_error() {
    local test_name="Progress Error Handling"
    local test_description="Test that progress error handling works correctly"
    
    # Test error with invalid percentage
    progress_init "Test error"
    
    local output=$(capture_progress_output "
        source $(dirname "${BASH_SOURCE[0]}")/../../lib/utils/progress.sh
        progress_init 'Test error'
        progress_update 150 'Invalid percentage'
    ")
    
    assert_contains "$output" "Error" "Output should contain error message"
    assert_contains "$output" "Invalid percentage" "Output should contain error details"
    
    # Test error function
    output=$(capture_progress_output "
        source $(dirname "${BASH_SOURCE[0]}")/../../lib/utils/progress.sh
        progress_init 'Test error function'
        progress_error 'Test error message'
    ")
    
    assert_contains "$output" "Error" "Output should contain error message"
    assert_contains "$output" "Test error message" "Output should contain error details"
    
    log_test_success "$test_name"
}

# Test 7: Terminal compatibility
test_terminal_compatibility() {
    local test_name="Terminal Compatibility"
    local test_description="Test that progress works across different terminal types"
    
    # Test color detection
    progress_init "Test terminal"
    
    # Verify terminal detection sets appropriate values
    assert_not_empty "$PROGRESS_TERMINAL_TYPE" "Terminal type should be detected"
    
    # Test that progress functions work regardless of terminal type
    progress_update 25 "Test update"
    assert_equal "$PROGRESS_CURRENT_PERCENT" "25" "Progress should work in any terminal"
    
    progress_cleanup
    
    log_test_success "$test_name"
}

# Test 8: Progress utility functions
test_progress_utilities() {
    local test_name="Progress Utilities"
    local test_description="Test utility functions for progress state"
    
    # Initialize progress
    progress_init "Test utilities"
    progress_update 75 "Three quarters"
    
    # Test get functions
    assert_equal "$(progress_get_percentage)" "75" "get_percentage should return current percentage"
    assert_equal "$(progress_get_description)" "Three quarters" "get_description should return current description"
    assert_true "progress_is_active" "is_active should return true when active"
    
    # Test duration
    local duration=$(progress_get_duration)
    assert_greater_than "$duration" "0" "Duration should be greater than 0"
    
    # Clean up and test inactive state
    progress_cleanup
    assert_false "progress_is_active" "is_active should return false when inactive"
    
    log_test_success "$test_name"
}

# Test 9: Progress cleanup
test_progress_cleanup() {
    local test_name="Progress Cleanup"
    local test_description="Test that progress cleanup works correctly"
    
    # Initialize progress
    progress_init "Test cleanup"
    progress_update 50 "Halfway"
    
    # Verify active state
    assert_true "progress_is_active" "Progress should be active before cleanup"
    
    # Clean up
    progress_cleanup
    
    # Verify inactive state
    assert_false "progress_is_active" "Progress should be inactive after cleanup"
    
    log_test_success "$test_name"
}

# Test 10: Performance impact
test_performance_impact() {
    local test_name="Performance Impact"
    local test_description="Test that progress updates don't significantly impact performance"
    
    # Measure time without progress
    local start_time=$(date +%s%N)
    for i in {1..100}; do
        echo "Test iteration $i" > /dev/null
    done
    local no_progress_time=$(($(date +%s%N) - start_time))
    
    # Measure time with progress
    start_time=$(date +%s%N)
    progress_init "Performance test"
    for i in {1..100}; do
        progress_update $i "Iteration $i"
    done
    progress_cleanup
    local with_progress_time=$(($(date +%s%N) - start_time))
    
    # Calculate overhead (should be less than 50% increase)
    local overhead=$((with_progress_time * 100 / no_progress_time - 100))
    assert_less_than "$overhead" "50" "Progress overhead should be less than 50%"
    
    log_test_success "$test_name"
}

# Test 11: Visual appearance
test_visual_appearance() {
    local test_name="Visual Appearance"
    local test_description="Test that progress bars have professional appearance"
    
    # Test progress bar output format
    progress_init "Visual test"
    progress_update 50 "Halfway"
    
    local output=$(capture_progress_output "
        source $(dirname "${BASH_SOURCE[0]}")/../../lib/utils/progress.sh
        progress_init 'Visual test'
        progress_update 50 'Halfway'
        echo 'END'
    ")
    
    # Verify progress bar contains expected elements
    assert_contains "$output" "50%" "Output should contain percentage"
    assert_contains "$output" "Halfway" "Output should contain description"
    assert_contains "$output" "END" "Output should end properly"
    
    progress_cleanup
    
    log_test_success "$test_name"
}

# Test 12: Real-time updates
test_realtime_updates() {
    local test_name="Real-time Updates"
    local test_description="Test that progress updates in real-time without blocking"
    
    # Test rapid updates
    progress_init "Real-time test"
    
    for i in {0..100..10}; do
        progress_update $i "Update $i"
        # Small delay to simulate work
        sleep 0.01
    done
    
    progress_complete true "Real-time test completed"
    
    # Verify final state
    assert_equal "$(progress_get_percentage)" "100" "Final percentage should be 100"
    
    log_test_success "$test_name"
}

# Main test execution
main() {
    log_test_suite_start "$TEST_SUITE_NAME" "$TEST_SUITE_DESCRIPTION"
    
    # Run all tests
    test_progress_init
    test_progress_update
    test_progress_validation
    test_progress_milestones
    test_progress_completion
    test_progress_error
    test_terminal_compatibility
    test_progress_utilities
    test_progress_cleanup
    test_performance_impact
    test_visual_appearance
    test_realtime_updates
    
    log_test_suite_complete "$TEST_SUITE_NAME"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi