#!/usr/bin/env bash
# =============================================================================
# Monitoring System Comprehensive Tests
# Tests all monitoring modules and integration
# =============================================================================

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
TEST_OUTPUT_DIR="/tmp/monitoring_tests_$$"

# Source test framework
source "$TEST_DIR/lib/shell-test-framework.sh" || {
    echo "ERROR: Failed to load test framework" >&2
    exit 1
}

# Source monitoring modules
source "$LIB_DIR/modules/core/logging.sh"
source "$LIB_DIR/modules/core/errors.sh"
source "$LIB_DIR/modules/monitoring/structured_logging.sh"
source "$LIB_DIR/modules/monitoring/observability.sh"
source "$LIB_DIR/modules/monitoring/alerting.sh"
source "$LIB_DIR/modules/monitoring/performance_metrics.sh"
source "$LIB_DIR/modules/monitoring/dashboards.sh"
source "$LIB_DIR/modules/monitoring/debug_tools.sh"
source "$LIB_DIR/modules/monitoring/log_aggregation.sh"
source "$LIB_DIR/modules/monitoring/integration.sh"

# =============================================================================
# TEST HELPERS
# =============================================================================

setup_test_environment() {
    mkdir -p "$TEST_OUTPUT_DIR"
    export MONITORING_OUTPUT_DIR="$TEST_OUTPUT_DIR"
    export STACK_NAME="test-stack"
    export DEPLOYMENT_ID="test-deploy-123"
    export AWS_REGION="us-east-1"
}

cleanup_test_environment() {
    rm -rf "$TEST_OUTPUT_DIR"
}

# =============================================================================
# STRUCTURED LOGGING TESTS
# =============================================================================

test_structured_logging_initialization() {
    describe "Structured logging initialization"
    
    # Initialize with JSON format
    init_structured_logging "json" "$TEST_OUTPUT_DIR/logs.json" "true"
    
    assert_equals "$STRUCTURED_LOG_FORMAT" "json" "Log format should be JSON"
    assert_equals "$STRUCTURED_LOG_AGGREGATION_ENABLED" "false" "Aggregation should be disabled by default"
    assert_file_exists "$TEST_OUTPUT_DIR/logs.json" "Log file should be created"
}

test_structured_logging_events() {
    describe "Structured logging events"
    
    # Log various events
    log_structured_event "INFO" "Test message" "test" "unit_test" '{"key": "value"}'
    log_deployment_event "start" '{"test": true}'
    log_infrastructure_event "vpc" "create" "vpc-123" "success"
    
    # Check log file contains events
    local log_content=$(cat "$TEST_OUTPUT_DIR/logs.json" 2>/dev/null || echo "")
    assert_contains "$log_content" "Test message" "Log should contain test message"
    assert_contains "$log_content" "deployment_event" "Log should contain deployment event"
    assert_contains "$log_content" "vpc-123" "Log should contain infrastructure event"
}

test_structured_logging_aggregation() {
    describe "Log aggregation"
    
    # Enable aggregation
    STRUCTURED_LOG_AGGREGATION_ENABLED=true
    STRUCTURED_LOG_AGGREGATION_FILE="$TEST_OUTPUT_DIR/aggregated.json"
    echo "[]" > "$STRUCTURED_LOG_AGGREGATION_FILE"
    
    # Log multiple events
    for i in {1..5}; do
        log_structured_event "INFO" "Test event $i" "test" "aggregation"
    done
    
    # Check aggregation
    local agg_count=$(jq 'length' "$STRUCTURED_LOG_AGGREGATION_FILE")
    assert_equals "$agg_count" "5" "Should have 5 aggregated events"
}

# =============================================================================
# OBSERVABILITY TESTS
# =============================================================================

test_observability_initialization() {
    describe "Observability framework initialization"
    
    init_observability "standard" "metrics,logs" ""
    
    assert_equals "$OBSERVABILITY_ENABLED" "true" "Observability should be enabled"
    assert_equals "$OBSERVABILITY_LEVEL" "standard" "Level should be standard"
    assert_contains "${OBSERVABILITY_COMPONENTS[*]}" "metrics" "Should include metrics"
    assert_contains "${OBSERVABILITY_COMPONENTS[*]}" "logs" "Should include logs"
}

test_observability_tracing() {
    describe "Observability tracing"
    
    # Enable tracing
    TRACE_ENABLED=true
    TRACE_SAMPLING_RATE=1.0
    
    # Start and end trace
    local trace_id=$(start_trace "test_operation" "" '{"test": true}')
    assert_not_empty "$trace_id" "Should return trace ID"
    
    # Add annotation
    add_trace_annotation "$trace_id" "test_key" "test_value"
    
    # End trace
    end_trace "$trace_id" "ok"
    
    # Verify trace was recorded
    assert_equals "${#ACTIVE_TRACES[@]}" "0" "Active traces should be empty after ending"
}

test_observability_metrics() {
    describe "Observability metrics collection"
    
    # Record various metrics
    record_metric "test.counter" "5" "count" "test"
    record_metric "test.gauge" "75.5" "percent" "test"
    record_metric "test.histogram" "250" "ms" "test"
    
    # Start metrics collector (mock)
    collect_system_metrics
    collect_deployment_metrics
    
    # Verify metrics were recorded
    local metrics=$(query_aggregated_logs '[.[] | select(.operation == "metric")] | length' 2>/dev/null || echo "0")
    assert_greater_than "$metrics" "0" "Should have recorded metrics"
}

# =============================================================================
# ALERTING TESTS
# =============================================================================

test_alerting_initialization() {
    describe "Alerting system initialization"
    
    init_alerting "log,console" "" ""
    
    assert_equals "$ALERTING_ENABLED" "true" "Alerting should be enabled"
    assert_contains "${ALERT_CHANNELS[*]}" "log" "Should include log channel"
    assert_contains "${ALERT_CHANNELS[*]}" "console" "Should include console channel"
    assert_file_exists "$ALERT_HISTORY_FILE" "Alert history file should exist"
}

test_alert_creation_and_resolution() {
    describe "Alert creation and resolution"
    
    # Create alert
    local alert_id=$(create_alert "test_alert" "warning" "Test alert message" "test")
    assert_not_empty "$alert_id" "Should return alert ID"
    
    # Check active alerts
    local active_count=$(get_active_alerts | jq 'length')
    assert_equals "$active_count" "1" "Should have 1 active alert"
    
    # Resolve alert
    resolve_alert "$alert_id" "Test resolution"
    
    # Check alert is resolved
    active_count=$(get_active_alerts | jq 'length')
    assert_equals "$active_count" "0" "Should have 0 active alerts after resolution"
}

test_alert_rules() {
    describe "Alert rules evaluation"
    
    # Add test rule
    add_alert_rule "test_rule" "Test Rule" "error" '{"condition": "error_rate > 10"}'
    
    # Create context that triggers rule
    local context='{"error_rate": 15, "deployment_state": "running"}'
    
    # Evaluate rules
    evaluate_alert_rules "$context"
    
    # Check if alert was created
    local alerts=$(get_active_alerts | jq 'length')
    assert_greater_than "$alerts" "0" "Should have created alert from rule"
}

# =============================================================================
# PERFORMANCE METRICS TESTS
# =============================================================================

test_performance_metrics_initialization() {
    describe "Performance metrics initialization"
    
    init_performance_metrics "60" "true"
    
    assert_equals "$PERF_METRICS_ENABLED" "true" "Performance metrics should be enabled"
    assert_equals "$PERF_METRICS_INTERVAL" "60" "Collection interval should be 60s"
    assert_file_exists "$PERF_METRICS_STORAGE_FILE" "Storage file should exist"
}

test_metric_collection() {
    describe "Metric collection and aggregation"
    
    # Record various metrics
    record_performance_metric "test.counter" "10" "counter" "count"
    record_performance_metric "test.gauge" "50" "gauge" "percent"
    record_performance_metric "test.gauge" "60" "gauge" "percent"
    record_performance_metric "test.gauge" "70" "gauge" "percent"
    
    # Check aggregation
    local agg=$(jq '."test.gauge"' "$PERF_METRICS_AGGREGATION_FILE")
    local avg=$(echo "$agg" | jq -r '.avg')
    assert_equals "$avg" "60" "Average should be 60"
    
    local min=$(echo "$agg" | jq -r '.min')
    assert_equals "$min" "50" "Minimum should be 50"
    
    local max=$(echo "$agg" | jq -r '.max')
    assert_equals "$max" "70" "Maximum should be 70"
}

test_metric_queries() {
    describe "Metric queries"
    
    # Query metrics
    local metrics=$(query_metrics "test\." 3600 "raw")
    local count=$(echo "$metrics" | jq 'length')
    assert_greater_than "$count" "0" "Should return metrics"
    
    # Get statistics
    local stats=$(get_metric_statistics "test.gauge" 3600)
    assert_contains "$stats" "aggregation" "Should contain aggregation data"
}

# =============================================================================
# DASHBOARD TESTS
# =============================================================================

test_dashboard_creation() {
    describe "Dashboard creation and management"
    
    # Create dashboard
    local dashboard_id=$(create_dashboard "test-dashboard" "deployment")
    assert_not_empty "$dashboard_id" "Should return dashboard ID"
    
    # List dashboards
    local count=${#ACTIVE_DASHBOARDS[@]}
    assert_equals "$count" "1" "Should have 1 active dashboard"
    
    # Add widget
    add_widget_to_dashboard "$dashboard_id" "test_widget" "Test Widget" "status"
    
    # Get dashboard
    local dashboard=$(get_dashboard "$dashboard_id")
    local widget_count=$(echo "$dashboard" | jq '.widgets | length')
    assert_greater_than "$widget_count" "0" "Dashboard should have widgets"
}

test_dashboard_rendering() {
    describe "Dashboard rendering"
    
    # Create and render dashboard
    local dashboard_id=$(create_dashboard "render-test" "deployment")
    
    # Test JSON rendering
    local json_output=$(render_dashboard "$dashboard_id" "json")
    assert_contains "$json_output" "render-test" "JSON should contain dashboard name"
    
    # Test console rendering (capture output)
    local console_output=$(render_dashboard "$dashboard_id" "console" 2>&1)
    assert_contains "$console_output" "render-test" "Console output should contain dashboard name"
}

# =============================================================================
# DEBUG TOOLS TESTS
# =============================================================================

test_debug_tools_initialization() {
    describe "Debug tools initialization"
    
    init_debug_tools "basic" "$TEST_OUTPUT_DIR/debug" "false"
    
    assert_equals "$DEBUG_ENABLED" "true" "Debug should be enabled"
    assert_equals "$DEBUG_LEVEL" "1" "Debug level should be basic (1)"
    assert_directory_exists "$DEBUG_OUTPUT_DIR" "Debug output directory should exist"
}

test_debug_logging() {
    describe "Debug logging"
    
    # Log at various levels
    debug_log 1 "Basic debug message" "TEST"
    debug_log 2 "Detailed debug message" "TEST"
    debug_log 3 "Verbose debug message" "TEST"
    
    # Check debug log
    local log_content=$(cat "$DEBUG_OUTPUT_DIR/debug.log" 2>/dev/null || echo "")
    assert_contains "$log_content" "Basic debug message" "Should contain basic message"
    assert_not_contains "$log_content" "Detailed debug message" "Should not contain detailed message at basic level"
}

test_debug_diagnostics() {
    describe "Debug diagnostics"
    
    # Run diagnostics
    run_diagnostics "$TEST_OUTPUT_DIR/diagnostics.txt"
    
    assert_file_exists "$TEST_OUTPUT_DIR/diagnostics.txt" "Diagnostics file should exist"
    
    local diag_content=$(cat "$TEST_OUTPUT_DIR/diagnostics.txt")
    assert_contains "$diag_content" "Environment" "Should contain environment section"
    assert_contains "$diag_content" "Variables" "Should contain variables section"
}

# =============================================================================
# LOG AGGREGATION TESTS
# =============================================================================

test_log_aggregation_initialization() {
    describe "Log aggregation initialization"
    
    init_log_aggregation "batch" "$TEST_OUTPUT_DIR/aggregation" "7"
    
    assert_equals "$LOG_AGG_ENABLED" "true" "Log aggregation should be enabled"
    assert_equals "$LOG_AGG_MODE" "batch" "Mode should be batch"
    assert_directory_exists "$LOG_AGG_STORAGE_DIR" "Storage directory should exist"
}

test_log_collection() {
    describe "Log collection and parsing"
    
    # Create test log file
    echo "Test log line 1" > "$TEST_OUTPUT_DIR/test.log"
    echo "ERROR: Test error" >> "$TEST_OUTPUT_DIR/test.log"
    
    # Register test collector
    register_log_collector "test_collector" "collect_test_logs" "custom" \
        '{"paths": ["'$TEST_OUTPUT_DIR'/test.log"]}'
    
    # Define test collector function
    collect_test_logs() {
        local config="$1"
        local last_pos="$2"
        cat "$TEST_OUTPUT_DIR/test.log"
    }
    
    # Run aggregation
    aggregate_logs
    
    # Check master file
    local log_count=$(wc -l < "$LOG_AGG_MASTER_FILE")
    assert_greater_than "$log_count" "0" "Should have collected logs"
}

test_log_analysis() {
    describe "Log analysis and pattern detection"
    
    # Add test logs with patterns
    for i in {1..5}; do
        echo '{"timestamp": '$(date +%s)', "level": "ERROR", "message": "Connection refused"}' >> "$LOG_AGG_MASTER_FILE"
    done
    
    # Run analysis
    run_log_analysis
    
    # Check pattern detection
    local patterns=$(jq 'length' "$LOG_AGG_PATTERNS_FILE")
    assert_greater_than "$patterns" "0" "Should have detected patterns"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_monitoring_integration() {
    describe "Monitoring integration with deployment"
    
    # Initialize deployment monitoring
    init_deployment_monitoring "test-stack" "standard"
    
    # Simulate deployment phases
    monitor_pre_deployment "test-stack"
    
    monitor_deployment_phase "infrastructure" "start"
    sleep 0.1
    monitor_deployment_phase "infrastructure" "end"
    
    monitor_deployment_phase "compute" "start"
    sleep 0.1
    monitor_deployment_phase "compute" "end"
    
    monitor_post_deployment "success"
    
    # Check monitoring output
    assert_file_exists "$MONITORING_OUTPUT_DIR/deployment_report.txt" "Deployment report should exist"
}

test_aws_operation_monitoring() {
    describe "AWS operation monitoring"
    
    # Mock AWS command
    aws() {
        echo '{"VpcId": "vpc-123456"}'
        return 0
    }
    
    # Monitor AWS operation
    local output=$(monitor_aws_operation "create" "vpc" "" "aws ec2 create-vpc --cidr-block 10.0.0.0/16")
    
    assert_contains "$output" "vpc-123456" "Should capture AWS output"
    
    # Check metrics were recorded
    local metrics=$(query_metrics "aws\.operation" 300 "raw" | jq 'length')
    assert_greater_than "$metrics" "0" "Should have recorded AWS operation metrics"
}

test_service_health_monitoring() {
    describe "Service health monitoring"
    
    # Mock health check functions
    check_n8n_health() { echo "healthy"; }
    check_qdrant_health() { echo "unhealthy"; }
    
    # Monitor service health
    monitor_service_health "n8n" "healthy"
    local n8n_result=$?
    assert_equals "$n8n_result" "0" "n8n health check should pass"
    
    monitor_service_health "qdrant" "healthy" || true
    
    # Check alerts
    local alerts=$(get_active_alerts "" "application" | jq 'length')
    assert_greater_than "$alerts" "0" "Should have created alert for unhealthy service"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_monitoring_error_handling() {
    describe "Monitoring error handling"
    
    # Test with invalid configuration
    init_structured_logging "invalid_format" "" "true" || true
    assert_equals "$STRUCTURED_LOG_FORMAT" "json" "Should default to JSON on invalid format"
    
    # Test with missing files
    query_aggregated_logs "." "/nonexistent/file" || true
    
    # Test with invalid metrics
    record_performance_metric "" "" "" "" || true
    
    # Verify system is still functional
    log_info "System still operational after errors" "TEST"
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

test_monitoring_cleanup() {
    describe "Monitoring cleanup"
    
    # Initialize all components
    init_deployment_monitoring "cleanup-test" "comprehensive"
    
    # Create some data
    log_structured_event "INFO" "Test event" "test" "cleanup"
    create_alert "test_alert" "info" "Test alert" "test"
    record_performance_metric "test.metric" "100" "gauge" "ms"
    
    # Run cleanup
    cleanup_deployment_monitoring
    
    # Verify cleanup
    assert_equals "${#ACTIVE_ALERTS[@]}" "0" "Active alerts should be cleared"
    assert_equals "${#METRIC_COLLECTORS[@]}" "0" "Metric collectors should be cleared"
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_monitoring_performance() {
    describe "Monitoring performance under load"
    
    local start_time=$(date +%s)
    
    # Generate load
    for i in {1..100}; do
        log_structured_event "INFO" "Load test event $i" "performance" "test"
        record_performance_metric "load.test" "$i" "gauge" "count"
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    assert_less_than "$duration" "5" "Should handle 100 events in less than 5 seconds"
    
    # Check data integrity
    local event_count=$(query_aggregated_logs "." 300 10000 | jq 'length')
    assert_greater_than "$event_count" "99" "Should have recorded all events"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_monitoring_tests() {
    echo "Running Monitoring System Tests"
    echo "================================"
    
    setup_test_environment
    
    # Run test suites
    run_test_suite "Structured Logging" \
        test_structured_logging_initialization \
        test_structured_logging_events \
        test_structured_logging_aggregation
    
    run_test_suite "Observability" \
        test_observability_initialization \
        test_observability_tracing \
        test_observability_metrics
    
    run_test_suite "Alerting" \
        test_alerting_initialization \
        test_alert_creation_and_resolution \
        test_alert_rules
    
    run_test_suite "Performance Metrics" \
        test_performance_metrics_initialization \
        test_metric_collection \
        test_metric_queries
    
    run_test_suite "Dashboards" \
        test_dashboard_creation \
        test_dashboard_rendering
    
    run_test_suite "Debug Tools" \
        test_debug_tools_initialization \
        test_debug_logging \
        test_debug_diagnostics
    
    run_test_suite "Log Aggregation" \
        test_log_aggregation_initialization \
        test_log_collection \
        test_log_analysis
    
    run_test_suite "Integration" \
        test_monitoring_integration \
        test_aws_operation_monitoring \
        test_service_health_monitoring
    
    run_test_suite "Error Handling" \
        test_monitoring_error_handling
    
    run_test_suite "Cleanup" \
        test_monitoring_cleanup
    
    run_test_suite "Performance" \
        test_monitoring_performance
    
    cleanup_test_environment
    
    print_test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_monitoring_tests
fi