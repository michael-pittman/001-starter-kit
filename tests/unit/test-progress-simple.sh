#!/usr/bin/env bash

# Simple Progress Indicator Tests
# Basic validation of progress indicator functionality

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Simple assertion functions
assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (expected: '$expected', got: '$actual')"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$condition"; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if ! eval "$condition"; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Load the progress module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/lib/utils/progress.sh"

echo -e "${BLUE}${BOLD}Progress Indicator Tests${NC}"
echo "=================================="

# Test 1: Progress initialization
echo -e "\n${YELLOW}Test 1: Progress Initialization${NC}"
progress_init "Test initialization"
assert_equal "0" "$PROGRESS_CURRENT_PERCENT" "Initial percentage should be 0"
assert_equal "Test initialization" "$PROGRESS_CURRENT_DESCRIPTION" "Description should be set"
assert_equal "true" "$PROGRESS_IS_ACTIVE" "Progress should be active"
assert_true "[[ $PROGRESS_START_TIME -gt 0 ]]" "Start time should be set"
progress_cleanup

# Test 2: Progress update
echo -e "\n${YELLOW}Test 2: Progress Update${NC}"
progress_init "Test update"
progress_update 25 "Quarter complete"
assert_equal "25" "$PROGRESS_CURRENT_PERCENT" "Percentage should be updated to 25"
assert_equal "Quarter complete" "$PROGRESS_CURRENT_DESCRIPTION" "Description should be updated"
progress_update 100 "Complete"
assert_equal "100" "$PROGRESS_CURRENT_PERCENT" "Percentage should be updated to 100"
progress_cleanup

# Test 3: Progress validation
echo -e "\n${YELLOW}Test 3: Progress Validation${NC}"
assert_true "progress_validate_percentage 0" "0 should be valid"
assert_true "progress_validate_percentage 50" "50 should be valid"
assert_true "progress_validate_percentage 100" "100 should be valid"
assert_false "progress_validate_percentage -1" "-1 should be invalid"
assert_false "progress_validate_percentage 101" "101 should be invalid"
assert_false "progress_validate_percentage abc" "abc should be invalid"

# Test 4: Milestone detection
echo -e "\n${YELLOW}Test 4: Milestone Detection${NC}"
assert_true "progress_is_milestone 0" "0 should be a milestone"
assert_true "progress_is_milestone 25" "25 should be a milestone"
assert_true "progress_is_milestone 50" "50 should be a milestone"
assert_true "progress_is_milestone 75" "75 should be a milestone"
assert_true "progress_is_milestone 87" "87 should be a milestone"
assert_true "progress_is_milestone 100" "100 should be a milestone"
assert_false "progress_is_milestone 10" "10 should not be a milestone"
assert_false "progress_is_milestone 30" "30 should not be a milestone"

# Test 5: Progress utilities
echo -e "\n${YELLOW}Test 5: Progress Utilities${NC}"
progress_init "Test utilities"
progress_update 75 "Three quarters"
assert_equal "75" "$(progress_get_percentage)" "get_percentage should return current percentage"
assert_equal "Three quarters" "$(progress_get_description)" "get_description should return current description"
assert_true "progress_is_active" "is_active should return true when active"
assert_true "[[ $(progress_get_duration) -gt 0 ]]" "Duration should be greater than 0"
progress_cleanup
assert_false "progress_is_active" "is_active should return false when inactive"

# Test 6: Progress completion
echo -e "\n${YELLOW}Test 6: Progress Completion${NC}"
progress_init "Test completion"
progress_update 50 "Halfway"
progress_complete true "Successfully completed"
assert_equal "false" "$PROGRESS_IS_ACTIVE" "Progress should be inactive after completion"

# Test 7: Progress error handling
echo -e "\n${YELLOW}Test 7: Progress Error Handling${NC}"
progress_init "Test error"
# This should not cause an error since we're testing the function directly
progress_error "Test error message"
assert_equal "false" "$PROGRESS_IS_ACTIVE" "Progress should be inactive after error"

# Test 8: Visual demonstration
echo -e "\n${YELLOW}Test 8: Visual Demonstration${NC}"
echo "Demonstrating progress bar functionality:"
progress_init "Testing progress bar"
for i in {0..100..10}; do
    progress_update $i "Processing step $i"
    sleep 0.1
done
progress_complete true "Visual test completed"

# Test summary
echo -e "\n${BLUE}${BOLD}Test Summary${NC}"
echo "==========="
echo -e "Total tests: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}${BOLD}Some tests failed!${NC}"
    exit 1
fi