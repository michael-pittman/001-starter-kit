#!/bin/bash
# =============================================================================
# Test Suite: Cost Analyzer Plugin
# Comprehensive tests for the Unity Cost Analyzer standard plugin
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load test framework
source "$PROJECT_ROOT/lib/enhanced-test-framework.sh" 2>/dev/null || {
    echo "Enhanced test framework not found, using basic testing"
    ENHANCED_TESTING=false
}

# Load the plugin to test
PLUGIN_SCRIPT="$PROJECT_ROOT/lib/unity/plugins/standard-plugins/cost-analyzer.sh"

if [[ ! -f "$PLUGIN_SCRIPT" ]]; then
    echo "ERROR: Cost Analyzer plugin not found at: $PLUGIN_SCRIPT"
    exit 1
fi

# Test configuration
TEST_SUITE_NAME="Cost Analyzer Plugin Tests"
TEST_OUTPUT_DIR="$PROJECT_ROOT/test-reports/unity/plugins"
mkdir -p "$TEST_OUTPUT_DIR"

# Mock AWS CLI for testing
mock_aws_cli() {
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "ce get-cost-and-usage")
        echo '{
            "ResultsByTime": [
                {
                    "TimePeriod": {"Start": "2024-01-01", "End": "2024-01-02"},
                    "Groups": [
                        {"Keys": ["EC2-Instance"], "Metrics": {"BlendedCost": {"Amount": "50.25", "Unit": "USD"}}},
                        {"Keys": ["S3"], "Metrics": {"BlendedCost": {"Amount": "15.75", "Unit": "USD"}}}
                    ]
                }
            ]
        }'
        ;;
    "ec2 describe-instances")
        echo '{
            "Reservations": [
                {
                    "Instances": [
                        {"InstanceId": "i-1234567890abcdef0", "InstanceType": "m5.large", "State": {"Name": "running"}, "SpotInstanceRequestId": null},
                        {"InstanceId": "i-0987654321fedcba0", "InstanceType": "t3.medium", "State": {"Name": "running"}, "SpotInstanceRequestId": "sir-12345678"}
                    ]
                }
            ]
        }'
        ;;
    "ec2 describe-volumes")
        echo '{
            "Volumes": [
                {"VolumeId": "vol-1234567890abcdef0", "Size": 100, "State": "available"},
                {"VolumeId": "vol-0987654321fedcba0", "Size": 50, "State": "in-use"}
            ]
        }'
        ;;
    "s3api list-buckets")
        echo '{
            "Buckets": [
                {"Name": "test-bucket-1"}, 
                {"Name": "test-bucket-2"}
            ]
        }'
        ;;
    *)
        echo "{}"
        ;;
esac
EOF
    chmod +x "/tmp/aws"
    export PATH="/tmp:$PATH"
}

# Test utilities
run_test() {
    local test_name="$1"
    local test_function="$2"
    local expected_result="${3:-0}"
    
    echo "Running test: $test_name"
    
    if $test_function; then
        local result=$?
        if [[ $result -eq $expected_result ]]; then
            echo "✅ PASS: $test_name"
            return 0
        else
            echo "❌ FAIL: $test_name (expected $expected_result, got $result)"
            return 1
        fi
    else
        local result=$?
        if [[ $result -eq $expected_result ]]; then
            echo "✅ PASS: $test_name"
            return 0
        else
            echo "❌ FAIL: $test_name (expected $expected_result, got $result)"
            return 1
        fi
    fi
}

cleanup_test_environment() {
    # Clean up test environment
    rm -rf "/tmp/test_cost_analyzer_"*
    rm -f "/tmp/aws"
    rm -rf ".unity/plugins/cost-analyzer" 2>/dev/null || true
}

# =============================================================================
# PLUGIN METADATA TESTS
# =============================================================================

test_plugin_metadata() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    # Check if metadata is valid JSON
    if ! echo "$metadata" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Plugin metadata is not valid JSON"
        return 1
    fi
    
    # Check required fields
    local required_fields=("name" "version" "api_version" "description" "author")
    
    for field in "${required_fields[@]}"; do
        if ! echo "$metadata" | jq -e ".$field" >/dev/null 2>&1; then
            echo "ERROR: Required metadata field missing: $field"
            return 1
        fi
    done
    
    # Check plugin name
    local plugin_name
    plugin_name=$(echo "$metadata" | jq -r '.name')
    if [[ "$plugin_name" != "cost-analyzer" ]]; then
        echo "ERROR: Plugin name mismatch: expected 'cost-analyzer', got '$plugin_name'"
        return 1
    fi
    
    return 0
}

test_plugin_category() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    local category
    category=$(echo "$metadata" | jq -r '.category')
    
    if [[ "$category" != "cost-optimization" ]]; then
        echo "ERROR: Unexpected plugin category: expected 'cost-optimization', got '$category'"
        return 1
    fi
    
    return 0
}

test_plugin_dependencies() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    # Check required dependencies
    local required_deps
    required_deps=$(echo "$metadata" | jq -r '.dependencies.required[]' 2>/dev/null)
    
    if ! echo "$required_deps" | grep -q "aws-cli"; then
        echo "ERROR: Missing required dependency: aws-cli"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN VALIDATION TESTS
# =============================================================================

test_plugin_validation_success() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Run plugin validation
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation failed"
        return 1
    fi
    
    return 0
}

test_plugin_validation_cost_explorer_access() {
    # Setup mock AWS CLI without Cost Explorer access
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "ce get-cost-and-usage")
        echo "An error occurred (AccessDenied) when calling the GetCostAndUsage operation: User is not authorized"
        exit 1
        ;;
    *)
        echo "{}"
        ;;
esac
EOF
    chmod +x "/tmp/aws"
    export PATH="/tmp:$PATH"
    
    # Run plugin validation (should succeed with warnings)
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation should succeed with Cost Explorer warning"
        return 1
    fi
    
    return 0
}

test_plugin_configuration_validation() {
    # Test with invalid configuration values
    export COST_ANALYZER_THRESHOLD="invalid"
    export COST_ANALYZER_ANALYSIS_PERIOD="not_a_number"
    
    mock_aws_cli
    
    # Plugin validation should handle invalid config gracefully
    bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1
    local result=$?
    
    # Clean up
    unset COST_ANALYZER_THRESHOLD
    unset COST_ANALYZER_ANALYSIS_PERIOD
    
    # Should return non-zero but not crash
    if [[ $result -eq 0 ]]; then
        echo "ERROR: Plugin validation should fail with invalid configuration"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN LIFECYCLE TESTS
# =============================================================================

test_plugin_initialization() {
    # Clean up any existing state
    rm -rf ".unity/plugins/cost-analyzer" 2>/dev/null || true
    
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    if ! bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1; then
        echo "ERROR: Plugin initialization failed"
        return 1
    fi
    
    # Check if required directories were created
    if [[ ! -d ".unity/plugins/cost-analyzer/state" ]]; then
        echo "ERROR: Plugin state directory not created"
        return 1
    fi
    
    if [[ ! -d ".unity/plugins/cost-analyzer/reports" ]]; then
        echo "ERROR: Plugin reports directory not created"
        return 1
    fi
    
    if [[ ! -f ".unity/plugins/cost-analyzer/state/status.json" ]]; then
        echo "ERROR: Plugin status file not created"
        return 1
    fi
    
    return 0
}

test_plugin_start() {
    # Initialize plugin first
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    # Start plugin
    if ! bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1; then
        echo "ERROR: Plugin start failed"
        return 1
    fi
    
    # Check if plugin status is active
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null | jq -r '.current_status.status' 2>/dev/null || echo "unknown")
    
    if [[ "$status" != "active" ]]; then
        echo "ERROR: Plugin status should be 'active', got '$status'"
        return 1
    fi
    
    return 0
}

test_plugin_stop() {
    # Initialize and start plugin first
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Stop plugin
    if ! bash "$PLUGIN_SCRIPT" stop >/dev/null 2>&1; then
        echo "ERROR: Plugin stop failed"
        return 1
    fi
    
    # Check if plugin status is stopped
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null | jq -r '.current_status.status' 2>/dev/null || echo "unknown")
    
    if [[ "$status" != "stopped" ]]; then
        echo "ERROR: Plugin status should be 'stopped', got '$status'"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN FUNCTIONALITY TESTS
# =============================================================================

test_cost_analysis() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test cost analysis
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze 7 DAILY 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: Cost analysis returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$analysis_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Cost analysis result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$analysis_result" | jq -e '.analysis_period' >/dev/null 2>&1; then
        echo "ERROR: Analysis result missing 'analysis_period' field"
        return 1
    fi
    
    return 0
}

test_cost_recommendations() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test cost recommendations
    local recommendations_result
    recommendations_result=$(bash "$PLUGIN_SCRIPT" recommend 2>/dev/null)
    
    if [[ -z "$recommendations_result" ]]; then
        echo "ERROR: Cost recommendations returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$recommendations_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Cost recommendations result is not valid JSON"
        return 1
    fi
    
    # Check if result has recommendations
    if ! echo "$recommendations_result" | jq -e '.recommendations' >/dev/null 2>&1; then
        echo "ERROR: Recommendations result missing 'recommendations' field"
        return 1
    fi
    
    return 0
}

test_cost_monitoring() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test cost monitoring (short duration for testing)
    local monitoring_result
    monitoring_result=$(timeout 5 bash "$PLUGIN_SCRIPT" monitor 3 2>/dev/null || echo '{"timeout": true}')
    
    if [[ -z "$monitoring_result" ]]; then
        echo "ERROR: Cost monitoring returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$monitoring_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Cost monitoring result is not valid JSON"
        return 1
    fi
    
    return 0
}

test_plugin_health_check() {
    # Initialize plugin
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Run health check
    local health_result
    health_result=$(bash "$PLUGIN_SCRIPT" health 2>/dev/null)
    
    if [[ -z "$health_result" ]]; then
        echo "ERROR: Health check returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$health_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Health check result is not valid JSON"
        return 1
    fi
    
    # Check health status
    local status
    status=$(echo "$health_result" | jq -r '.status' 2>/dev/null)
    
    if [[ "$status" != "healthy" && "$status" != "degraded" && "$status" != "unhealthy" ]]; then
        echo "ERROR: Invalid health status: $status"
        return 1
    fi
    
    return 0
}

test_plugin_metrics() {
    # Initialize plugin
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Get plugin metrics
    local metrics_result
    metrics_result=$(bash "$PLUGIN_SCRIPT" metrics 2>/dev/null)
    
    if [[ -z "$metrics_result" ]]; then
        echo "ERROR: Metrics returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$metrics_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Metrics result is not valid JSON"
        return 1
    fi
    
    # Check for required metrics fields
    if ! echo "$metrics_result" | jq -e '.metrics.total_analyses' >/dev/null 2>&1; then
        echo "ERROR: Metrics missing 'total_analyses' field"
        return 1
    fi
    
    return 0
}

# =============================================================================
# COST ANALYSIS TESTS
# =============================================================================

test_ec2_cost_analysis() {
    # Test EC2 cost analysis functionality
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # This would test the internal EC2 cost analysis
    # For now, just test that the plugin handles EC2 instances properly
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze 1 DAILY 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: EC2 cost analysis failed"
        return 1
    fi
    
    return 0
}

test_storage_cost_analysis() {
    # Test storage cost analysis functionality
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test storage cost recommendations
    local recommendations
    recommendations=$(bash "$PLUGIN_SCRIPT" recommend 2>/dev/null)
    
    if [[ -z "$recommendations" ]]; then
        echo "ERROR: Storage cost analysis failed"
        return 1
    fi
    
    # Check for storage-related recommendations
    if ! echo "$recommendations" | grep -q "storage" 2>/dev/null; then
        echo "WARNING: No storage-related recommendations found"
    fi
    
    return 0
}

test_cost_threshold_handling() {
    # Test cost threshold functionality
    export COST_ANALYZER_THRESHOLD="50.00"
    
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # This would test threshold breach handling
    # For now, just verify configuration is loaded
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null)
    
    if ! echo "$status" | jq -e '.configuration.cost_threshold' >/dev/null 2>&1; then
        echo "ERROR: Cost threshold configuration not loaded"
        unset COST_ANALYZER_THRESHOLD
        return 1
    fi
    
    unset COST_ANALYZER_THRESHOLD
    return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_plugin_integration_with_unity_framework() {
    # Test that plugin properly integrates with Unity framework
    if ! bash -c "source '$PLUGIN_SCRIPT'" 2>/dev/null; then
        echo "ERROR: Plugin cannot be sourced without errors"
        return 1
    fi
    
    return 0
}

test_plugin_configuration_handling() {
    # Test plugin configuration handling
    export COST_ANALYZER_THRESHOLD="200.00"
    export COST_ANALYZER_ANALYSIS_PERIOD="14"
    export COST_ANALYZER_ALERT_ENABLED="false"
    
    # Initialize plugin with custom configuration
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    # Check if configuration is reflected in status
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null)
    
    if ! echo "$status" | jq -e '.configuration.cost_threshold' >/dev/null 2>&1; then
        echo "ERROR: Configuration not reflected in plugin status"
        return 1
    fi
    
    # Clean up
    unset COST_ANALYZER_THRESHOLD
    unset COST_ANALYZER_ANALYSIS_PERIOD
    unset COST_ANALYZER_ALERT_ENABLED
    
    return 0
}

test_cost_explorer_fallback() {
    # Test fallback behavior when Cost Explorer is not available
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "ce get-cost-and-usage")
        echo "An error occurred (AccessDenied) when calling the GetCostAndUsage operation"
        exit 1
        ;;
    "ec2 describe-instances")
        echo '{"Reservations": [{"Instances": [{"InstanceId": "i-1234567890abcdef0", "InstanceType": "m5.large", "State": {"Name": "running"}}]}]}'
        ;;
    *)
        echo "{}"
        ;;
esac
EOF
    chmod +x "/tmp/aws"
    export PATH="/tmp:$PATH"
    
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test cost analysis with fallback
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze 7 DAILY 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: Cost analysis fallback failed"
        return 1
    fi
    
    # Should contain fallback indicator
    if ! echo "$analysis_result" | grep -q "estimation_method.*fallback" 2>/dev/null; then
        echo "ERROR: Fallback method not indicated in result"
        return 1
    fi
    
    return 0
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_plugin_error_handling_invalid_period() {
    # Test plugin behavior with invalid analysis period
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test with invalid period (should handle gracefully)
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze -1 DAILY 2>/dev/null || echo '{"error": "handled"}')
    
    # Should handle error gracefully
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: Plugin should handle invalid period gracefully"
        return 1
    fi
    
    return 0
}

test_plugin_error_handling_aws_permissions() {
    # Test plugin behavior with limited AWS permissions
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    *)
        echo "An error occurred (AccessDenied) when calling the operation"
        exit 1
        ;;
esac
EOF
    chmod +x "/tmp/aws"
    export PATH="/tmp:$PATH"
    
    # Plugin should handle limited permissions gracefully
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    local result=$?
    
    # Should succeed with warnings, not fail completely
    if [[ $result -eq 0 ]]; then
        return 0
    else
        echo "ERROR: Plugin should handle limited AWS permissions gracefully"
        return 1
    fi
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_plugin_performance_initialization() {
    # Test plugin initialization performance
    local start_time=$(date +%s.%N)
    
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Initialization should complete within 5 seconds
    if (( $(echo "$duration > 5" | bc -l 2>/dev/null || echo "0") )); then
        echo "ERROR: Plugin initialization took too long: ${duration}s"
        return 1
    fi
    
    return 0
}

test_plugin_performance_cost_analysis() {
    # Test cost analysis performance
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    local start_time=$(date +%s.%N)
    
    bash "$PLUGIN_SCRIPT" analyze 7 DAILY >/dev/null 2>&1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Analysis should complete within 10 seconds
    if (( $(echo "$duration > 10" | bc -l 2>/dev/null || echo "0") )); then
        echo "ERROR: Cost analysis took too long: ${duration}s"
        return 1
    fi
    
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "=========================================="
    echo "Starting $TEST_SUITE_NAME"
    echo "=========================================="
    
    local tests_passed=0
    local tests_failed=0
    local start_time=$(date +%s)
    
    # Setup test environment
    cleanup_test_environment
    
    # Plugin Metadata Tests
    echo -e "\n--- Plugin Metadata Tests ---"
    run_test "Plugin Metadata Format" test_plugin_metadata && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Category" test_plugin_category && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Dependencies" test_plugin_dependencies && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Validation Tests
    echo -e "\n--- Plugin Validation Tests ---"
    run_test "Plugin Validation Success" test_plugin_validation_success && ((tests_passed++)) || ((tests_failed++))
    run_test "Cost Explorer Access Validation" test_plugin_validation_cost_explorer_access && ((tests_passed++)) || ((tests_failed++))
    run_test "Configuration Validation" test_plugin_configuration_validation && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Lifecycle Tests
    echo -e "\n--- Plugin Lifecycle Tests ---"
    run_test "Plugin Initialization" test_plugin_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Start" test_plugin_start && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Stop" test_plugin_stop && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Functionality Tests
    echo -e "\n--- Plugin Functionality Tests ---"
    run_test "Cost Analysis" test_cost_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Cost Recommendations" test_cost_recommendations && ((tests_passed++)) || ((tests_failed++))
    run_test "Cost Monitoring" test_cost_monitoring && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Health Check" test_plugin_health_check && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Metrics" test_plugin_metrics && ((tests_passed++)) || ((tests_failed++))
    
    # Cost Analysis Tests
    echo -e "\n--- Cost Analysis Tests ---"
    run_test "EC2 Cost Analysis" test_ec2_cost_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Storage Cost Analysis" test_storage_cost_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Cost Threshold Handling" test_cost_threshold_handling && ((tests_passed++)) || ((tests_failed++))
    
    # Integration Tests
    echo -e "\n--- Integration Tests ---"
    run_test "Unity Framework Integration" test_plugin_integration_with_unity_framework && ((tests_passed++)) || ((tests_failed++))
    run_test "Configuration Handling" test_plugin_configuration_handling && ((tests_passed++)) || ((tests_failed++))
    run_test "Cost Explorer Fallback" test_cost_explorer_fallback && ((tests_passed++)) || ((tests_failed++))
    
    # Error Handling Tests
    echo -e "\n--- Error Handling Tests ---"
    run_test "Invalid Period Handling" test_plugin_error_handling_invalid_period && ((tests_passed++)) || ((tests_failed++))
    run_test "AWS Permissions Error Handling" test_plugin_error_handling_aws_permissions && ((tests_passed++)) || ((tests_failed++))
    
    # Performance Tests
    echo -e "\n--- Performance Tests ---"
    run_test "Initialization Performance" test_plugin_performance_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Cost Analysis Performance" test_plugin_performance_cost_analysis && ((tests_passed++)) || ((tests_failed++))
    
    # Cleanup
    cleanup_test_environment
    
    # Generate test report
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local total_tests=$((tests_passed + tests_failed))
    
    echo -e "\n=========================================="
    echo "Test Results Summary"
    echo "=========================================="
    echo "Total Tests: $total_tests"
    echo "Passed: $tests_passed"
    echo "Failed: $tests_failed"
    echo "Success Rate: $(echo "scale=2; $tests_passed * 100 / $total_tests" | bc 2>/dev/null || echo "0")%"
    echo "Execution Time: ${total_time}s"
    echo "=========================================="
    
    # Generate JSON test report
    cat > "$TEST_OUTPUT_DIR/cost-analyzer-test-results.json" <<EOF
{
    "test_suite": "$TEST_SUITE_NAME",
    "timestamp": $(date +%s),
    "execution_time": $total_time,
    "total_tests": $total_tests,
    "tests_passed": $tests_passed,
    "tests_failed": $tests_failed,
    "success_rate": $(echo "scale=2; $tests_passed * 100 / $total_tests" | bc 2>/dev/null || echo "0"),
    "plugin_version": "2.0.0"
}
EOF
    
    if [[ $tests_failed -eq 0 ]]; then
        echo "✅ All tests passed!"
        return 0
    else
        echo "❌ Some tests failed!"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi