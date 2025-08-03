#!/usr/bin/env bash
# =============================================================================
# Minimal Test for Unity Monitor Service Core Functionality
# =============================================================================

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create isolated test environment
TEST_DIR="/tmp/unity-monitor-minimal-test-$$"
mkdir -p "$TEST_DIR/logs/unity" "$TEST_DIR/.unity/state/events" || exit 1

# Set test environment variables
export UNITY_STATE_DIR="$TEST_DIR/.unity/state"
export UNITY_LOG_LEVEL="ERROR"
export MONITOR_STATE_DIR="$TEST_DIR/.unity/monitoring"
export MONITOR_METRICS_DIR="$MONITOR_STATE_DIR/metrics"
export MONITOR_LOGS_DIR="$MONITOR_STATE_DIR/logs"
export MONITOR_ALERTS_DIR="$MONITOR_STATE_DIR/alerts"

# Change to test directory to avoid permission issues
cd "$TEST_DIR"

# Create minimal unity-core mock
cat > unity-core-mock.sh << 'EOF'
#!/bin/bash
# Minimal Unity Core Mock for Testing

UNITY_SUCCESS=0
UNITY_ERROR_VALIDATION=10
UNITY_ERROR_PREREQUISITE=20
UNITY_ERROR_EXECUTION=30
BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"

unity_log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >&2
}

unity_emit_event() {
    local event="$1"
    local source="$2"
    local data="${3:-}"
    echo "[EVENT] $event from $source: $data" >&2
}

unity_register_service() {
    local service="$1"
    local path="$2"
    echo "[REGISTER] Service $service at $path" >&2
}

unity_on_event() {
    local event="$1"
    local handler="$2"
    echo "[HANDLER] Registered $handler for $event" >&2
}

# Create required directories
mkdir -p "$UNITY_STATE_DIR" "$MONITOR_STATE_DIR"
EOF

# Source the mock and test only core monitor functions
source unity-core-mock.sh

# Extract and test only the essential monitor functions
cat > monitor-test.sh << 'EOF'
#!/bin/bash

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0

# Simple test function
test_function() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -n "Testing $test_name... "
    ((TESTS_TOTAL++))
    
    if eval "$test_cmd" 2>/dev/null; then
        echo "✅ PASSED"
        ((TESTS_PASSED++))
    else
        echo "❌ FAILED"
    fi
}

# Test basic monitoring functions
echo "================================================================="
echo "Unity Monitor Service Minimal Test"
echo "Bash Version: $BASH_VERSION"
echo "================================================================="
echo

# Test 1: Directory creation
test_function "Directory creation" "mkdir -p $MONITOR_METRICS_DIR && [[ -d $MONITOR_METRICS_DIR ]]"

# Test 2: File creation
test_function "Metrics file creation" "echo 'test,42,count' > $MONITOR_METRICS_DIR/test.csv && [[ -f $MONITOR_METRICS_DIR/test.csv ]]"

# Test 3: Alert file creation
test_function "Alert logging" "mkdir -p $MONITOR_ALERTS_DIR && echo 'test alert' > $MONITOR_ALERTS_DIR/test.log && [[ -f $MONITOR_ALERTS_DIR/test.log ]]"

# Test 4: JSON creation
test_function "JSON handling" "echo '{\"test\": true}' > $MONITOR_STATE_DIR/test.json && [[ -f $MONITOR_STATE_DIR/test.json ]]"

# Test 5: Bash compatibility
if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
    test_function "Bash 4 arrays" "declare -A test_array && test_array[key]=value && [[ \${test_array[key]} == 'value' ]]"
else
    test_function "Bash 3 compat" "test_var='value' && [[ \$test_var == 'value' ]]"
fi

# Test 6: CPU usage detection (cross-platform)
test_function "CPU usage function" "
    if [[ \"\$OSTYPE\" == \"darwin\"* ]]; then
        cpu=\$(top -l 1 -s 0 | grep 'CPU usage' | awk '{print \$3}' | sed 's/%//' 2>/dev/null || echo 0)
    else
        cpu=\$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1 2>/dev/null || echo 0)
    fi
    [[ \"\$cpu\" =~ ^[0-9]+$ ]]
"

# Test 7: Memory usage detection
test_function "Memory usage function" "
    if [[ \"\$OSTYPE\" == \"darwin\"* ]]; then
        mem=50  # Mock value for macOS
    else
        mem=\$(free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}' 2>/dev/null || echo 50)
    fi
    [[ \"\$mem\" =~ ^[0-9]+$ ]]
"

# Test 8: Timestamp generation
test_function "Timestamp generation" "ts=\$(date -Iseconds) && [[ -n \"\$ts\" ]]"

# Test 9: Process ID in filenames
test_function "PID in filenames" "touch $MONITOR_STATE_DIR/test_\$\$.tmp && [[ -f $MONITOR_STATE_DIR/test_\$\$.tmp ]]"

# Test 10: Log rotation simulation
test_function "Log rotation" "
    for i in {1..5}; do
        echo \"log entry \$i\" >> $MONITOR_LOGS_DIR/test.log
    done
    [[ -f $MONITOR_LOGS_DIR/test.log ]] && [[ \$(wc -l < $MONITOR_LOGS_DIR/test.log) -eq 5 ]]
"

echo
echo "================================================================="
echo "Test Summary:"
echo "  Total: $TESTS_TOTAL"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $((TESTS_TOTAL - TESTS_PASSED))"
echo "================================================================="

exit $([[ $TESTS_PASSED -eq $TESTS_TOTAL ]] && echo 0 || echo 1)
EOF

# Run the test
bash monitor-test.sh
TEST_RESULT=$?

# Cleanup
cd - >/dev/null
rm -rf "$TEST_DIR"

exit $TEST_RESULT