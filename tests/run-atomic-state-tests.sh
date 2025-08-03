#!/bin/bash
# Unity Atomic State Management Test Runner
# Executes comprehensive tests for atomic state management and deployment integration

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load test framework
source "$SCRIPT_DIR/lib/test-framework.sh"

# Test configuration
OVERALL_TEST_SUITE="Unity Atomic State Management - Complete Test Suite"
TEST_RESULTS_DIR="$SCRIPT_DIR/results/atomic-state"
TEST_LOG_FILE="$TEST_RESULTS_DIR/atomic-state-tests.log"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Setup logging
exec 1> >(tee -a "$TEST_LOG_FILE")
exec 2> >(tee -a "$TEST_LOG_FILE" >&2)

echo "======================================================================"
echo "Unity Atomic State Management - Complete Test Suite"
echo "Started: $(date)"
echo "======================================================================"
echo ""

# Test suites to run
declare -a TEST_SUITES=(
    "$SCRIPT_DIR/unity/atomic-state/test-unity-atomic-state.sh"
    "$SCRIPT_DIR/unity/deployment/test-deployment-atomic-state.sh"
)

# Track overall results
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()

# Function to run a test suite
run_test_suite() {
    local test_suite="$1"
    local suite_name="$(basename "$test_suite" .sh)"
    
    echo "========================================"
    echo "Running: $suite_name"
    echo "========================================"
    echo ""
    
    if [[ -f "$test_suite" && -x "$test_suite" ]]; then
        # Run the test suite and capture results
        local suite_start_time=$(date +%s)
        local suite_output
        local suite_exit_code=0
        
        suite_output=$("$test_suite" 2>&1) || suite_exit_code=$?
        
        local suite_end_time=$(date +%s)
        local suite_duration=$((suite_end_time - suite_start_time))
        
        echo "$suite_output"
        echo ""
        
        # Parse results from output
        local suite_tests=0
        local suite_passed=0
        local suite_failed=0
        
        if echo "$suite_output" | grep -q "Tests run:"; then
            suite_tests=$(echo "$suite_output" | grep "Tests run:" | sed 's/.*Tests run: \([0-9]*\).*/\1/')
            suite_passed=$(echo "$suite_output" | grep "Tests run:" | sed 's/.*Passed: \([0-9]*\).*/\1/')
            suite_failed=$(echo "$suite_output" | grep "Tests run:" | sed 's/.*Failed: \([0-9]*\).*/\1/')
        fi
        
        # Update totals
        TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))
        TOTAL_PASSED=$((TOTAL_PASSED + suite_passed))
        TOTAL_FAILED=$((TOTAL_FAILED + suite_failed))
        
        if [[ $suite_exit_code -ne 0 || $suite_failed -gt 0 ]]; then
            FAILED_SUITES+=("$suite_name")
        fi
        
        echo "Suite Results: $suite_name"
        echo "  Duration: ${suite_duration}s"
        echo "  Tests: $suite_tests, Passed: $suite_passed, Failed: $suite_failed"
        echo ""
        
    else
        echo "ERROR: Test suite not found or not executable: $test_suite"
        FAILED_SUITES+=("$suite_name (not found)")
        echo ""
    fi
}

# Pre-flight checks
echo "Pre-flight Checks:"
echo "=================="

# Check if Unity core is available
if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-core.sh" ]]; then
    echo "✓ Unity core system found"
else
    echo "✗ Unity core system not found"
    exit 1
fi

# Check if atomic state system is available
if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-atomic-state.sh" ]]; then
    echo "✓ Unity atomic state system found"
else
    echo "✗ Unity atomic state system not found"
    exit 1
fi

# Check if deployment service is available
if [[ -f "$PROJECT_ROOT/lib/unity/services/unity-deployment-service.sh" ]]; then
    echo "✓ Unity deployment service found"
else
    echo "✗ Unity deployment service not found"
    exit 1
fi

# Check required commands
local missing_commands=()
for cmd in find grep sed awk jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [[ "$cmd" != "jq" ]]; then  # jq is optional
            missing_commands+=("$cmd")
        fi
    fi
done

if [[ ${#missing_commands[@]} -gt 0 ]]; then
    echo "✗ Missing required commands: ${missing_commands[*]}"
    exit 1
else
    echo "✓ All required commands available"
fi

echo ""

# Run all test suites
echo "Running Test Suites:"
echo "==================="
echo ""

for test_suite in "${TEST_SUITES[@]}"; do
    run_test_suite "$test_suite"
done

# Summary
echo "======================================================================"
echo "Overall Test Results"
echo "======================================================================"
echo ""
echo "Total Tests Run: $TOTAL_TESTS"
echo "Passed: $TOTAL_PASSED"
echo "Failed: $TOTAL_FAILED"
echo ""

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo "Failed Test Suites:"
    for failed_suite in "${FAILED_SUITES[@]}"; do
        echo "  - $failed_suite"
    done
    echo ""
fi

# Calculate success rate
if [[ $TOTAL_TESTS -gt 0 ]]; then
    local success_rate=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
    echo "Success Rate: ${success_rate}%"
else
    echo "Success Rate: N/A (no tests run)"
fi

echo ""
echo "Completed: $(date)"
echo "Test log: $TEST_LOG_FILE"
echo ""

# Create summary report
cat > "$TEST_RESULTS_DIR/summary.txt" <<EOF
Unity Atomic State Management Test Summary
Generated: $(date)

Test Results:
- Total Tests: $TOTAL_TESTS
- Passed: $TOTAL_PASSED
- Failed: $TOTAL_FAILED
- Success Rate: $((TOTAL_TESTS > 0 ? TOTAL_PASSED * 100 / TOTAL_TESTS : 0))%

Failed Suites: ${#FAILED_SUITES[@]}
$(printf "  - %s\n" "${FAILED_SUITES[@]}")

Test Details:
$(printf "  - %s\n" "${TEST_SUITES[@]}")

For detailed logs, see: $TEST_LOG_FILE
EOF

# Exit with appropriate code
if [[ $TOTAL_FAILED -eq 0 && ${#FAILED_SUITES[@]} -eq 0 ]]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "❌ Some tests failed. Check the logs for details."
    exit 1
fi