#!/usr/bin/env bash
# =============================================================================
# Test Unity Monitor Service
# Tests the unified monitoring service functionality and bash compatibility
# =============================================================================

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the monitor service
source "$PROJECT_ROOT/lib/unity/services/unity-monitor-service.sh"

# Test configuration
TEST_MONITOR_STATE_DIR="/tmp/unity-monitor-test-$$"
MONITOR_STATE_DIR="$TEST_MONITOR_STATE_DIR"
MONITOR_METRICS_DIR="$TEST_MONITOR_STATE_DIR/metrics"
MONITOR_LOGS_DIR="$TEST_MONITOR_STATE_DIR/logs"
MONITOR_ALERTS_DIR="$TEST_MONITOR_STATE_DIR/alerts"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Run test
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    echo -n "Testing $test_name... "
    ((TESTS_TOTAL++))
    
    if $test_func >/dev/null 2>&1; then
        echo "✅ PASSED"
        ((TESTS_PASSED++))
    else
        echo "❌ FAILED"
        ((TESTS_FAILED++))
        # Show error details
        $test_func 2>&1 | sed 's/^/  /' || true
    fi
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_MONITOR_STATE_DIR" 2>/dev/null || true
}

# Setup test environment
setup_test_env() {
    cleanup_test_env
    mkdir -p "$TEST_MONITOR_STATE_DIR"
}

# =============================================================================
# INITIALIZATION TESTS
# =============================================================================

test_monitor_init() {
    setup_test_env
    
    # Initialize monitor service
    unity_monitor_init || return 1
    
    # Verify directories created
    [[ -d "$MONITOR_STATE_DIR" ]] || return 1
    [[ -d "$MONITOR_METRICS_DIR" ]] || return 1
    [[ -d "$MONITOR_LOGS_DIR" ]] || return 1
    [[ -d "$MONITOR_ALERTS_DIR" ]] || return 1
    
    # Verify initialization files
    [[ -f "$MONITOR_STATE_DIR/health_registry.conf" ]] || return 1
    [[ -f "$MONITOR_STATE_DIR/health_status.txt" ]] || return 1
    [[ -f "$MONITOR_ALERTS_DIR/alert_history.log" ]] || return 1
    [[ -f "$MONITOR_METRICS_DIR/metrics.db" ]] || return 1
    
    # Verify service is marked as initialized
    [[ "$MONITOR_SERVICE_INITIALIZED" == "true" ]] || return 1
    
    return 0
}

# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================

test_health_check_system() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Run system health check
    unity_monitor_health_check "system" "false" || true
    
    # Verify health status was updated
    [[ -f "$MONITOR_STATE_DIR/health_status.txt" ]] || return 1
    
    # Verify metrics were recorded
    grep -q "system.cpu.usage" "$MONITOR_METRICS_DIR/metrics.db" || return 1
    grep -q "system.memory.usage" "$MONITOR_METRICS_DIR/metrics.db" || return 1
    grep -q "system.disk.usage" "$MONITOR_METRICS_DIR/metrics.db" || return 1
    
    return 0
}

test_health_check_all() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Run comprehensive health check
    unity_monitor_health_check "all" "false" || true
    
    # Verify health status file exists and has content
    [[ -s "$MONITOR_STATE_DIR/health_status.txt" ]] || return 1
    
    return 0
}

# =============================================================================
# ALERT MANAGEMENT TESTS
# =============================================================================

test_alert_basic() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Send a test alert
    unity_monitor_alert "warning" "Test Alert" "This is a test message" || return 1
    
    # Verify alert was logged
    [[ -f "$MONITOR_ALERTS_DIR/alerts.log" ]] || return 1
    grep -q "Test Alert" "$MONITOR_ALERTS_DIR/alerts.log" || return 1
    
    # Verify alert file was created
    local alert_files=$(find "$MONITOR_ALERTS_DIR" -name "alert_*.json" | wc -l)
    [[ $alert_files -gt 0 ]] || return 1
    
    return 0
}

test_alert_throttling() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Send first alert
    unity_monitor_alert "error" "Throttle Test" "First message" || return 1
    
    # Try to send same alert immediately (should be throttled)
    unity_monitor_alert "error" "Throttle Test" "Second message" || return 1
    
    # Count alert files - should only be 1 due to throttling
    local alert_count=$(find "$MONITOR_ALERTS_DIR" -name "alert_*.json" | wc -l)
    [[ $alert_count -eq 1 ]] || return 1
    
    return 0
}

# =============================================================================
# METRICS COLLECTION TESTS
# =============================================================================

test_metrics_collection() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Collect metrics synchronously
    unity_monitor_collect_metrics "false" || return 1
    
    # Verify metrics were recorded
    [[ -s "$MONITOR_METRICS_DIR/metrics.db" ]] || return 1
    
    # Check for system metrics
    grep -q "system.cpu.usage" "$MONITOR_METRICS_DIR/metrics.db" || return 1
    grep -q "system.memory.usage" "$MONITOR_METRICS_DIR/metrics.db" || return 1
    
    return 0
}

test_metric_recording() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Record test metric
    _record_metric "test.metric" "42" "count" "test:true" || return 1
    
    # Verify metric was recorded
    grep -q "test.metric,42,count,test:true" "$MONITOR_METRICS_DIR/metrics.db" || return 1
    
    # Verify time-series file was created
    local today=$(date +%Y/%m/%d)
    [[ -f "$MONITOR_METRICS_DIR/$today/test.metric.tsv" ]] || return 1
    
    return 0
}

# =============================================================================
# LOG AGGREGATION TESTS
# =============================================================================

test_log_aggregation_init() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Verify log aggregation was initialized
    [[ -f "$MONITOR_STATE_DIR/log_aggregation.conf" ]] || return 1
    [[ -d "$MONITOR_LOGS_DIR/aggregated" ]] || return 1
    
    return 0
}

# =============================================================================
# TRACING TESTS
# =============================================================================

test_distributed_tracing() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Start a trace
    local trace_id=$(unity_monitor_start_trace "test_operation")
    [[ -n "$trace_id" ]] || return 1
    
    # Verify trace file was created
    [[ -f "$MONITOR_STATE_DIR/traces/$trace_id.json" ]] || return 1
    
    # End the trace
    unity_monitor_end_trace "$trace_id" "success" || return 1
    
    # Verify trace was updated
    grep -q '"status": "success"' "$MONITOR_STATE_DIR/traces/$trace_id.json" || return 1
    
    return 0
}

# =============================================================================
# BASH COMPATIBILITY TESTS
# =============================================================================

test_bash3_compatibility() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Test metric collector registration (bash 3 fallback)
    if [[ "$BASH_VERSION_MAJOR" -lt 4 ]]; then
        # Should use file-based storage
        [[ -f "$MONITOR_STATE_DIR/metric_collectors.conf" ]] || return 1
    fi
    
    # Test basic functionality works
    unity_monitor_alert "info" "Bash 3 Test" "Testing bash 3 compatibility" || return 1
    
    return 0
}

test_cross_platform_metrics() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Test CPU usage collection
    local cpu_usage=$(_get_cpu_usage)
    [[ "$cpu_usage" =~ ^[0-9]+$ ]] || return 1
    
    # Test memory usage collection
    local mem_usage=$(_get_memory_usage)
    [[ "$mem_usage" =~ ^[0-9]+$ ]] || return 1
    
    # Test disk usage collection
    local disk_usage=$(_get_disk_usage)
    [[ "$disk_usage" =~ ^[0-9]+$ ]] || return 1
    
    return 0
}

# =============================================================================
# SERVICE LIFECYCLE TESTS
# =============================================================================

test_service_lifecycle() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Start service
    unity_monitor_start || return 1
    [[ "$MONITOR_SERVICE_RUNNING" == "true" ]] || return 1
    
    # Get status
    unity_monitor_status || return 1
    
    # Stop service
    unity_monitor_stop || return 1
    [[ "$MONITOR_SERVICE_RUNNING" == "false" ]] || return 1
    
    # Verify state was saved
    [[ -f "$MONITOR_STATE_DIR/monitor_state.json" ]] || return 1
    
    return 0
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance_baseline() {
    setup_test_env
    unity_monitor_init || return 1
    
    # Verify performance baseline was created
    [[ -f "$MONITOR_STATE_DIR/performance_baseline.json" ]] || return 1
    
    # Verify it contains expected structure
    grep -q "deployment_time" "$MONITOR_STATE_DIR/performance_baseline.json" || return 1
    grep -q "api_response_time" "$MONITOR_STATE_DIR/performance_baseline.json" || return 1
    grep -q "resource_usage" "$MONITOR_STATE_DIR/performance_baseline.json" || return 1
    
    return 0
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

main() {
    echo "================================================================="
    echo "Unity Monitor Service Test Suite"
    echo "================================================================="
    echo "Bash Version: $BASH_VERSION"
    echo "Platform: $OSTYPE"
    echo "================================================================="
    echo
    
    # Run initialization tests
    echo "Initialization Tests:"
    run_test "Service Initialization" test_monitor_init
    echo
    
    # Run health check tests
    echo "Health Check Tests:"
    run_test "System Health Check" test_health_check_system
    run_test "Comprehensive Health Check" test_health_check_all
    echo
    
    # Run alert management tests
    echo "Alert Management Tests:"
    run_test "Basic Alert" test_alert_basic
    run_test "Alert Throttling" test_alert_throttling
    echo
    
    # Run metrics collection tests
    echo "Metrics Collection Tests:"
    run_test "Metrics Collection" test_metrics_collection
    run_test "Metric Recording" test_metric_recording
    echo
    
    # Run log aggregation tests
    echo "Log Aggregation Tests:"
    run_test "Log Aggregation Init" test_log_aggregation_init
    echo
    
    # Run tracing tests
    echo "Distributed Tracing Tests:"
    run_test "Distributed Tracing" test_distributed_tracing
    echo
    
    # Run compatibility tests
    echo "Compatibility Tests:"
    run_test "Bash 3 Compatibility" test_bash3_compatibility
    run_test "Cross-Platform Metrics" test_cross_platform_metrics
    echo
    
    # Run lifecycle tests
    echo "Service Lifecycle Tests:"
    run_test "Service Lifecycle" test_service_lifecycle
    echo
    
    # Run performance tests
    echo "Performance Tests:"
    run_test "Performance Baseline" test_performance_baseline
    echo
    
    # Summary
    echo "================================================================="
    echo "Test Summary:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "================================================================="
    
    # Cleanup
    cleanup_test_env
    
    # Exit with appropriate code
    [[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
}

# Run tests
main "$@"