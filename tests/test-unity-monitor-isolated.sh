#!/usr/bin/env bash
# =============================================================================
# Isolated Test for Unity Monitor Service
# Tests monitoring functionality in a completely isolated environment
# =============================================================================

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create isolated test environment
TEST_DIR="/tmp/unity-monitor-test-$$"
export UNITY_STATE_DIR="$TEST_DIR/.unity/state"
export UNITY_SERVICES_DIR="$PROJECT_ROOT/lib/unity/services"
export UNITY_LOG_LEVEL="ERROR"  # Reduce noise
export MONITOR_STATE_DIR="$TEST_DIR/.unity/monitoring"
export MONITOR_METRICS_DIR="$MONITOR_STATE_DIR/metrics"
export MONITOR_LOGS_DIR="$MONITOR_STATE_DIR/logs"
export MONITOR_ALERTS_DIR="$MONITOR_STATE_DIR/alerts"

# Create all required directories
mkdir -p "$UNITY_STATE_DIR/events" "$TEST_DIR/logs/unity" || {
    echo "Failed to create test directories"
    exit 1
}

# Source only what we need
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
source "$PROJECT_ROOT/lib/unity/services/unity-monitor-service.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Simple test runner
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo "✅ PASSED"
        ((TESTS_PASSED++))
    else
        echo "❌ FAILED"
        ((TESTS_FAILED++))
    fi
}

# Cleanup function
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "================================================================="
echo "Unity Monitor Service Isolated Test"
echo "Bash Version: $BASH_VERSION"
echo "Test Directory: $TEST_DIR"
echo "================================================================="
echo

# Test 1: Service initialization
run_test "Service initialization" "unity_monitor_init"

# Test 2: Health check execution
run_test "Health check execution" "unity_monitor_health_check system false"

# Test 3: Alert generation
run_test "Alert generation" "unity_monitor_alert info 'Test Alert' 'Test message'"

# Test 4: Metrics collection
run_test "Metrics collection" "unity_monitor_collect_metrics false"

# Test 5: Service status
run_test "Service status check" "unity_monitor_status"

# Test 6: Trace creation
run_test "Distributed tracing" "trace_id=\$(unity_monitor_start_trace 'test_op'); unity_monitor_end_trace \"\$trace_id\" success"

# Test 7: Check directories were created
run_test "Directory structure" "[[ -d '$MONITOR_METRICS_DIR' && -d '$MONITOR_ALERTS_DIR' && -d '$MONITOR_LOGS_DIR' ]]"

# Test 8: Check metrics were recorded
run_test "Metrics recording" "[[ -f '$MONITOR_METRICS_DIR/metrics.db' ]]"

# Test 9: Check alerts were logged
run_test "Alert logging" "[[ -f '$MONITOR_ALERTS_DIR/alerts.log' ]]"

# Test 10: Service lifecycle
run_test "Service lifecycle" "unity_monitor_start && unity_monitor_stop"

echo
echo "================================================================="
echo "Test Summary:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "  Total: $((TESTS_PASSED + TESTS_FAILED))"
echo "================================================================="

exit $([[ $TESTS_FAILED -eq 0 ]] && echo 0 || echo 1)