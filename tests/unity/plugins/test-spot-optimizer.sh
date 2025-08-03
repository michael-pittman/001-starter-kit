#!/bin/bash
# =============================================================================
# Test Suite: Spot Optimizer Plugin
# Comprehensive tests for the Unity Spot Optimizer standard plugin
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
PLUGIN_SCRIPT="$PROJECT_ROOT/lib/unity/plugins/standard-plugins/spot-optimizer.sh"

if [[ ! -f "$PLUGIN_SCRIPT" ]]; then
    echo "ERROR: Spot Optimizer plugin not found at: $PLUGIN_SCRIPT"
    exit 1
fi

# Test configuration
TEST_SUITE_NAME="Spot Optimizer Plugin Tests"
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
    "ec2 describe-instances")
        echo '{"Reservations": [{"Instances": [{"InstanceId": "i-1234567890abcdef0", "InstanceType": "g4dn.xlarge", "State": {"Name": "running"}}]}]}'
        ;;
    "ec2 describe-spot-price-history")
        echo '{"SpotPriceHistory": [{"AvailabilityZone": "us-east-1a", "SpotPrice": "0.35", "Timestamp": "2024-01-01T00:00:00Z"}]}'
        ;;
    "ec2 describe-availability-zones")
        echo '{"AvailabilityZones": [{"ZoneName": "us-east-1a"}, {"ZoneName": "us-east-1b"}]}'
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
    rm -rf "/tmp/test_spot_optimizer_"*
    rm -f "/tmp/aws"
    rm -rf ".unity/plugins/spot-optimizer" 2>/dev/null || true
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
    if [[ "$plugin_name" != "spot-optimizer" ]]; then
        echo "ERROR: Plugin name mismatch: expected 'spot-optimizer', got '$plugin_name'"
        return 1
    fi
    
    return 0
}

test_plugin_api_version() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    local api_version
    api_version=$(echo "$metadata" | jq -r '.api_version')
    
    if [[ "$api_version" != "2.0" ]]; then
        echo "ERROR: Unexpected API version: expected '2.0', got '$api_version'"
        return 1
    fi
    
    return 0
}

test_plugin_capabilities() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    # Check extension points
    local extension_points
    extension_points=$(echo "$metadata" | jq -r '.capabilities.extension_points[]' 2>/dev/null)
    
    if ! echo "$extension_points" | grep -q "pre_deployment"; then
        echo "ERROR: Missing required extension point: pre_deployment"
        return 1
    fi
    
    if ! echo "$extension_points" | grep -q "post_deployment"; then
        echo "ERROR: Missing required extension point: post_deployment"
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

test_plugin_validation_missing_dependencies() {
    # Remove AWS CLI from PATH
    local original_path="$PATH"
    export PATH="/nonexistent"
    
    # Run plugin validation (should fail)
    if bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation should have failed with missing dependencies"
        export PATH="$original_path"
        return 1
    fi
    
    export PATH="$original_path"
    return 0
}

test_plugin_bash_version_compatibility() {
    # Test bash version validation
    local original_bash_version="$BASH_VERSION"
    
    # Mock old bash version
    export BASH_VERSION="3.2.0"
    
    # Plugin should still validate successfully
    mock_aws_cli
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin should be compatible with bash 3.2"
        export BASH_VERSION="$original_bash_version"
        return 1
    fi
    
    export BASH_VERSION="$original_bash_version"
    return 0
}

# =============================================================================
# PLUGIN LIFECYCLE TESTS
# =============================================================================

test_plugin_initialization() {
    # Clean up any existing state
    rm -rf ".unity/plugins/spot-optimizer" 2>/dev/null || true
    
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    if ! bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1; then
        echo "ERROR: Plugin initialization failed"
        return 1
    fi
    
    # Check if required directories were created
    if [[ ! -d ".unity/plugins/spot-optimizer/state" ]]; then
        echo "ERROR: Plugin state directory not created"
        return 1
    fi
    
    if [[ ! -d ".unity/plugins/spot-optimizer/logs" ]]; then
        echo "ERROR: Plugin logs directory not created"
        return 1
    fi
    
    if [[ ! -f ".unity/plugins/spot-optimizer/state/status.json" ]]; then
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

test_plugin_cleanup() {
    # Initialize plugin first
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    # Cleanup plugin
    if ! bash "$PLUGIN_SCRIPT" cleanup >/dev/null 2>&1; then
        echo "ERROR: Plugin cleanup failed"
        return 1
    fi
    
    # Check if plugin directories still exist (should be preserved by default)
    if [[ ! -d ".unity/plugins/spot-optimizer" ]]; then
        echo "ERROR: Plugin directory should be preserved by default"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN FUNCTIONALITY TESTS
# =============================================================================

test_spot_optimization() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test spot optimization
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize g4dn.xlarge us-east-1 2>/dev/null)
    
    if [[ -z "$optimization_result" ]]; then
        echo "ERROR: Spot optimization returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$optimization_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Spot optimization result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$optimization_result" | jq -e '.optimized' >/dev/null 2>&1; then
        echo "ERROR: Optimization result missing 'optimized' field"
        return 1
    fi
    
    return 0
}

test_deployment_analysis() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test deployment analysis
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze test-stack 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: Deployment analysis returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$analysis_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Deployment analysis result is not valid JSON"
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
    if ! echo "$metrics_result" | jq -e '.metrics.total_optimizations' >/dev/null 2>&1; then
        echo "ERROR: Metrics missing 'total_optimizations' field"
        return 1
    fi
    
    return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_plugin_integration_with_unity_framework() {
    # Test that plugin properly integrates with Unity framework
    # This would test extension point registration, event handling, etc.
    
    # For now, just test that plugin can be loaded without errors
    if ! bash -c "source '$PLUGIN_SCRIPT'" 2>/dev/null; then
        echo "ERROR: Plugin cannot be sourced without errors"
        return 1
    fi
    
    return 0
}

test_plugin_configuration_handling() {
    # Test plugin configuration handling
    
    # Set test configuration
    export SPOT_OPTIMIZER_MAX_PRICE="0.75"
    export SPOT_OPTIMIZER_SAVINGS_TARGET="50"
    
    # Initialize plugin with custom configuration
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    # Check if configuration is reflected in status
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null)
    
    if ! echo "$status" | jq -e '.configuration.max_spot_price' >/dev/null 2>&1; then
        echo "ERROR: Configuration not reflected in plugin status"
        return 1
    fi
    
    # Clean up
    unset SPOT_OPTIMIZER_MAX_PRICE
    unset SPOT_OPTIMIZER_SAVINGS_TARGET
    
    return 0
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_plugin_error_handling_invalid_instance_type() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test optimization with invalid instance type (should handle gracefully)
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize "" us-east-1 2>/dev/null)
    
    # Should return error result but not crash
    if [[ -z "$optimization_result" ]]; then
        return 0  # Expected to fail gracefully
    fi
    
    # If it returns a result, it should indicate failure
    if echo "$optimization_result" | jq -e '.optimized == true' >/dev/null 2>&1; then
        echo "ERROR: Plugin should not optimize empty instance type"
        return 1
    fi
    
    return 0
}

test_plugin_error_handling_aws_credentials() {
    # Test plugin behavior without AWS credentials
    
    # Remove AWS credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    
    # Plugin validation should fail gracefully
    if bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation should fail without AWS credentials"
        return 1
    fi
    
    return 0
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

test_plugin_performance_spot_optimization() {
    # Test spot optimization performance
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    local start_time=$(date +%s.%N)
    
    bash "$PLUGIN_SCRIPT" optimize g4dn.xlarge us-east-1 >/dev/null 2>&1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Optimization should complete within 10 seconds
    if (( $(echo "$duration > 10" | bc -l 2>/dev/null || echo "0") )); then
        echo "ERROR: Spot optimization took too long: ${duration}s"
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
    run_test "Plugin API Version" test_plugin_api_version && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Capabilities" test_plugin_capabilities && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Validation Tests
    echo -e "\n--- Plugin Validation Tests ---"
    run_test "Plugin Validation Success" test_plugin_validation_success && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Validation Missing Dependencies" test_plugin_validation_missing_dependencies && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Bash Compatibility" test_plugin_bash_version_compatibility && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Lifecycle Tests
    echo -e "\n--- Plugin Lifecycle Tests ---"
    run_test "Plugin Initialization" test_plugin_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Start" test_plugin_start && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Stop" test_plugin_stop && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Cleanup" test_plugin_cleanup && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Functionality Tests
    echo -e "\n--- Plugin Functionality Tests ---"
    run_test "Spot Optimization" test_spot_optimization && ((tests_passed++)) || ((tests_failed++))
    run_test "Deployment Analysis" test_deployment_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Health Check" test_plugin_health_check && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Metrics" test_plugin_metrics && ((tests_passed++)) || ((tests_failed++))
    
    # Integration Tests
    echo -e "\n--- Integration Tests ---"
    run_test "Unity Framework Integration" test_plugin_integration_with_unity_framework && ((tests_passed++)) || ((tests_failed++))
    run_test "Configuration Handling" test_plugin_configuration_handling && ((tests_passed++)) || ((tests_failed++))
    
    # Error Handling Tests
    echo -e "\n--- Error Handling Tests ---"
    run_test "Invalid Instance Type Handling" test_plugin_error_handling_invalid_instance_type && ((tests_passed++)) || ((tests_failed++))
    run_test "AWS Credentials Error Handling" test_plugin_error_handling_aws_credentials && ((tests_passed++)) || ((tests_failed++))
    
    # Performance Tests
    echo -e "\n--- Performance Tests ---"
    run_test "Initialization Performance" test_plugin_performance_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Spot Optimization Performance" test_plugin_performance_spot_optimization && ((tests_passed++)) || ((tests_failed++))
    
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
    cat > "$TEST_OUTPUT_DIR/spot-optimizer-test-results.json" <<EOF
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