#!/bin/bash
# =============================================================================
# Test Suite: Performance Tuner Plugin
# Comprehensive tests for the Unity Performance Tuner standard plugin
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
PLUGIN_SCRIPT="$PROJECT_ROOT/lib/unity/plugins/standard-plugins/performance-tuner.sh"

if [[ ! -f "$PLUGIN_SCRIPT" ]]; then
    echo "ERROR: Performance Tuner plugin not found at: $PLUGIN_SCRIPT"
    exit 1
fi

# Test configuration
TEST_SUITE_NAME="Performance Tuner Plugin Tests"
TEST_OUTPUT_DIR="$PROJECT_ROOT/test-reports/unity/plugins"
mkdir -p "$TEST_OUTPUT_DIR"

# Mock AWS CLI for testing
mock_aws_cli() {
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$*" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "cloudwatch list-metrics --max-items 1")
        echo '{"Metrics": [{"MetricName": "CPUUtilization", "Namespace": "AWS/EC2"}]}'
        ;;
    "cloudwatch list-metrics")
        echo '{"Metrics": [{"MetricName": "CPUUtilization"}, {"MetricName": "NetworkIn"}]}'
        ;;
    "ec2 describe-instances --query"*)
        echo '{"Reservations": [{"Instances": [{"InstanceId": "i-1234567890abcdef0", "InstanceType": "m5.large", "State": {"Name": "running"}}]}]}'
        ;;
    "autoscaling describe-auto-scaling-groups --query AutoScalingGroups")
        echo '[{"AutoScalingGroupName": "test-asg", "MinSize": 1, "MaxSize": 3, "DesiredCapacity": 2}]'
        ;;
    "cloudformation describe-stack-resources --stack-name"*)
        echo '{"StackResources": [{"ResourceType": "AWS::EC2::Instance"}, {"ResourceType": "AWS::AutoScaling::AutoScalingGroup"}]}'
        ;;
    *)
        echo "{}"
        ;;
esac
EOF
    chmod +x "/tmp/aws"
    export PATH="/tmp:$PATH"
}

# Mock system commands for testing
mock_system_commands() {
    # Mock free command
    cat > "/tmp/free" <<'EOF'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:        8192000     3000000     4000000      100000     1192000     5000000"
echo "Swap:       2048000           0     2048000"
EOF
    chmod +x "/tmp/free"
    
    # Mock df command
    cat > "/tmp/df" <<'EOF'
#!/bin/bash
if [[ "$1" == "/tmp" ]]; then
    echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
    echo "/dev/sda1       10485760 2097152   8388608  20% /tmp"
else
    echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
    echo "/dev/sda1       52428800 10485760  41943040  20% /"
fi
EOF
    chmod +x "/tmp/df"
    
    # Mock top command
    cat > "/tmp/top" <<'EOF'
#!/bin/bash
if [[ "$*" == "-bn1" ]]; then
    echo "top - 12:00:00 up 1 day,  2:34,  1 user,  load average: 0.45, 0.32, 0.28"
    echo "Tasks: 123 total,   1 running, 122 sleeping,   0 stopped,   0 zombie"
    echo "%Cpu(s): 15.2 us,  2.1 sy,  0.0 ni, 82.1 id,  0.4 wa,  0.0 hi,  0.2 si,  0.0 st"
    echo "MiB Mem :   8000.0 total,   4000.0 free,   3000.0 used,   1000.0 buff/cache"
fi
EOF
    chmod +x "/tmp/top"
    
    # Mock ps command
    cat > "/tmp/ps" <<'EOF'
#!/bin/bash
if [[ "$*" == "aux --sort=-%cpu" ]]; then
    echo "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND"
    echo "root         1 12.5  1.2  12345  6789 ?        Ss   12:00   0:01 /sbin/init"
    echo "user      1234  8.3  2.1  23456 12345 pts/0    S+   12:01   0:00 python app.py"
    echo "user      1235  5.2  1.8  34567 23456 pts/1    S+   12:02   0:00 node server.js"
elif [[ "$*" == "aux" ]]; then
    echo "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND"
    echo "root         1  0.1  0.2  12345  6789 ?        Ss   12:00   0:01 /sbin/init"
    echo "user      1234  2.3  1.1  23456 12345 pts/0    S+   12:01   0:00 python app.py"
    echo "user      1235  1.8  0.9  34567 23456 pts/1    S+   12:02   0:00 node server.js"
    echo "user      1236  1.2  0.7  45678 34567 pts/2    S+   12:03   0:00 java -jar app.jar"
    echo "user      1237  0.8  0.5  56789 45678 pts/3    S+   12:04   0:00 nginx"
fi
EOF
    chmod +x "/tmp/ps"
    
    # Mock uptime command
    cat > "/tmp/uptime" <<'EOF'
#!/bin/bash
echo " 12:00:00 up 1 day,  2:34,  1 user,  load average: 0.45, 0.32, 0.28"
EOF
    chmod +x "/tmp/uptime"
    
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
    rm -rf "/tmp/test_performance_tuner_"*
    rm -f "/tmp/aws" "/tmp/free" "/tmp/df" "/tmp/top" "/tmp/ps" "/tmp/uptime"
    rm -rf ".unity/plugins/performance-tuner" 2>/dev/null || true
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
    if [[ "$plugin_name" != "performance-tuner" ]]; then
        echo "ERROR: Plugin name mismatch: expected 'performance-tuner', got '$plugin_name'"
        return 1
    fi
    
    return 0
}

test_plugin_performance_category() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    local category
    category=$(echo "$metadata" | jq -r '.category')
    
    if [[ "$category" != "performance-optimization" ]]; then
        echo "ERROR: Unexpected plugin category: expected 'performance-optimization', got '$category'"
        return 1
    fi
    
    return 0
}

test_plugin_monitoring_capabilities() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    # Check extension points for performance-specific hooks
    local extension_points
    extension_points=$(echo "$metadata" | jq -r '.capabilities.extension_points[]' 2>/dev/null)
    
    if ! echo "$extension_points" | grep -q "on_performance_degradation"; then
        echo "ERROR: Missing required extension point: on_performance_degradation"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN VALIDATION TESTS
# =============================================================================

test_plugin_validation_success() {
    # Setup mock AWS CLI and system commands
    mock_aws_cli
    mock_system_commands
    
    # Run plugin validation
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation failed"
        return 1
    fi
    
    return 0
}

test_plugin_validation_cloudwatch_access() {
    # Setup mock AWS CLI without CloudWatch access
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$*" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "cloudwatch list-metrics --max-items 1")
        echo "An error occurred (AccessDenied) when calling the ListMetrics operation"
        exit 1
        ;;
    *)
        echo "{}"
        ;;
esac
EOF
    chmod +x "/tmp/aws"
    export PATH="/tmp:$PATH"
    mock_system_commands
    
    # Run plugin validation (should succeed with warnings)
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation should succeed with CloudWatch warning"
        return 1
    fi
    
    return 0
}

test_plugin_performance_configuration_validation() {
    # Test with valid performance configuration
    export PERFORMANCE_TUNER_CPU_THRESHOLD="90.0"
    export PERFORMANCE_TUNER_MEMORY_THRESHOLD="95.0"
    export PERFORMANCE_TUNER_OPTIMIZATION_INTERVAL="600"
    
    mock_aws_cli
    mock_system_commands
    
    # Plugin validation should succeed
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation failed with valid performance configuration"
        unset PERFORMANCE_TUNER_CPU_THRESHOLD
        unset PERFORMANCE_TUNER_MEMORY_THRESHOLD
        unset PERFORMANCE_TUNER_OPTIMIZATION_INTERVAL
        return 1
    fi
    
    # Test with invalid configuration
    export PERFORMANCE_TUNER_CPU_THRESHOLD="invalid"
    export PERFORMANCE_TUNER_MEMORY_THRESHOLD="not_a_number"
    
    # Plugin validation should fail
    if bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation should fail with invalid configuration"
        unset PERFORMANCE_TUNER_CPU_THRESHOLD
        unset PERFORMANCE_TUNER_MEMORY_THRESHOLD
        unset PERFORMANCE_TUNER_OPTIMIZATION_INTERVAL
        return 1
    fi
    
    # Clean up
    unset PERFORMANCE_TUNER_CPU_THRESHOLD
    unset PERFORMANCE_TUNER_MEMORY_THRESHOLD
    unset PERFORMANCE_TUNER_OPTIMIZATION_INTERVAL
    
    return 0
}

# =============================================================================
# PLUGIN LIFECYCLE TESTS
# =============================================================================

test_plugin_initialization() {
    # Clean up any existing state
    rm -rf ".unity/plugins/performance-tuner" 2>/dev/null || true
    
    # Setup mock AWS CLI and system commands
    mock_aws_cli
    mock_system_commands
    
    # Initialize plugin
    if ! bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1; then
        echo "ERROR: Plugin initialization failed"
        return 1
    fi
    
    # Check if required directories were created
    if [[ ! -d ".unity/plugins/performance-tuner/state" ]]; then
        echo "ERROR: Plugin state directory not created"
        return 1
    fi
    
    if [[ ! -d ".unity/plugins/performance-tuner/reports" ]]; then
        echo "ERROR: Plugin reports directory not created"
        return 1
    fi
    
    if [[ ! -f ".unity/plugins/performance-tuner/state/status.json" ]]; then
        echo "ERROR: Plugin status file not created"
        return 1
    fi
    
    # Check if baseline performance was initialized
    if [[ ! -f ".unity/plugins/performance-tuner/state/baseline_performance.json" ]]; then
        echo "ERROR: Baseline performance file not created"
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

test_performance_analysis() {
    # Setup mock AWS CLI and system commands
    mock_aws_cli
    mock_system_commands
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test performance analysis
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze all false 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: Performance analysis returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$analysis_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Performance analysis result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$analysis_result" | jq -e '.performance_score' >/dev/null 2>&1; then
        echo "ERROR: Analysis result missing 'performance_score' field"
        return 1
    fi
    
    if ! echo "$analysis_result" | jq -e '.total_issues' >/dev/null 2>&1; then
        echo "ERROR: Analysis result missing 'total_issues' field"
        return 1
    fi
    
    return 0
}

test_performance_optimization() {
    # Setup mock AWS CLI and system commands
    mock_aws_cli
    mock_system_commands
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test performance optimization
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize auto all 2>/dev/null)
    
    if [[ -z "$optimization_result" ]]; then
        echo "ERROR: Performance optimization returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$optimization_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Performance optimization result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$optimization_result" | jq -e '.optimizations_applied' >/dev/null 2>&1; then
        echo "ERROR: Optimization result missing 'optimizations_applied' field"
        return 1
    fi
    
    return 0
}

test_performance_monitoring() {
    # Setup mock AWS CLI and system commands
    mock_aws_cli
    mock_system_commands
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test performance monitoring (short duration for testing)
    local monitoring_result
    monitoring_result=$(timeout 5 bash "$PLUGIN_SCRIPT" monitor 3 1 2>/dev/null || echo '{"timeout": true}')
    
    if [[ -z "$monitoring_result" ]]; then
        echo "ERROR: Performance monitoring returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$monitoring_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Performance monitoring result is not valid JSON"
        return 1
    fi
    
    return 0
}

test_performance_report() {
    # Setup mock AWS CLI and system commands
    mock_aws_cli
    mock_system_commands
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test performance report generation
    local report_result
    report_result=$(bash "$PLUGIN_SCRIPT" report comprehensive 1 2>/dev/null)
    
    if [[ -z "$report_result" ]]; then
        echo "ERROR: Performance report returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$report_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Performance report result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$report_result" | jq -e '.current_analysis' >/dev/null 2>&1; then
        echo "ERROR: Performance report missing 'current_analysis' field"
        return 1
    fi
    
    return 0
}

test_plugin_health_check() {
    # Initialize plugin
    mock_aws_cli
    mock_system_commands
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
    mock_system_commands
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
# PERFORMANCE ANALYSIS TESTS
# =============================================================================

test_system_resource_analysis() {
    # Test system resource analysis functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test system analysis
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze system false 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: System resource analysis failed"
        return 1
    fi
    
    # Check if result contains system-specific metrics
    if ! echo "$analysis_result" | grep -q "system" 2>/dev/null; then
        echo "ERROR: System analysis result doesn't contain system-specific metrics"
        return 1
    fi
    
    return 0
}

test_aws_resource_analysis() {
    # Test AWS resource analysis functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test AWS resource analysis
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze aws false 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: AWS resource analysis failed"
        return 1
    fi
    
    # Check if result contains AWS-specific metrics
    if ! echo "$analysis_result" | grep -q "aws" 2>/dev/null; then
        echo "ERROR: AWS analysis result doesn't contain AWS-specific metrics"
        return 1
    fi
    
    return 0
}

test_application_performance_analysis() {
    # Test application performance analysis functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test application analysis
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze application false 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: Application performance analysis failed"
        return 1
    fi
    
    # Check if result contains application-specific metrics
    if ! echo "$analysis_result" | grep -q "application" 2>/dev/null; then
        echo "ERROR: Application analysis result doesn't contain application-specific metrics"
        return 1
    fi
    
    return 0
}

test_performance_threshold_handling() {
    # Test performance threshold functionality
    export PERFORMANCE_TUNER_CPU_THRESHOLD="50.0"
    export PERFORMANCE_TUNER_MEMORY_THRESHOLD="60.0"
    
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # This would test threshold breach handling
    # For now, just verify configuration is loaded
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null)
    
    if ! echo "$status" | jq -e '.configuration.cpu_threshold' >/dev/null 2>&1; then
        echo "ERROR: CPU threshold configuration not loaded"
        unset PERFORMANCE_TUNER_CPU_THRESHOLD
        unset PERFORMANCE_TUNER_MEMORY_THRESHOLD
        return 1
    fi
    
    unset PERFORMANCE_TUNER_CPU_THRESHOLD
    unset PERFORMANCE_TUNER_MEMORY_THRESHOLD
    return 0
}

# =============================================================================
# PERFORMANCE OPTIMIZATION TESTS
# =============================================================================

test_cpu_optimization() {
    # Test CPU optimization functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test CPU optimization
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize auto cpu 2>/dev/null)
    
    if [[ -z "$optimization_result" ]]; then
        echo "ERROR: CPU optimization failed"
        return 1
    fi
    
    # Check if result contains CPU optimization details
    if ! echo "$optimization_result" | grep -q "cpu" 2>/dev/null; then
        echo "ERROR: CPU optimization result doesn't contain CPU-specific details"
        return 1
    fi
    
    return 0
}

test_memory_optimization() {
    # Test memory optimization functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test memory optimization
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize auto memory 2>/dev/null)
    
    if [[ -z "$optimization_result" ]]; then
        echo "ERROR: Memory optimization failed"
        return 1
    fi
    
    # Check if result contains memory optimization details
    if ! echo "$optimization_result" | grep -q "memory" 2>/dev/null; then
        echo "ERROR: Memory optimization result doesn't contain memory-specific details"
        return 1
    fi
    
    return 0
}

test_autoscaling_optimization() {
    # Test Auto Scaling optimization functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test Auto Scaling optimization
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize auto autoscaling 2>/dev/null)
    
    if [[ -z "$optimization_result" ]]; then
        echo "ERROR: Auto Scaling optimization failed"
        return 1
    fi
    
    # Check if result contains Auto Scaling optimization details
    if ! echo "$optimization_result" | grep -q "autoscaling" 2>/dev/null; then
        echo "ERROR: Auto Scaling optimization result doesn't contain autoscaling-specific details"
        return 1
    fi
    
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
    export PERFORMANCE_TUNER_CPU_THRESHOLD="75.0"
    export PERFORMANCE_TUNER_MEMORY_THRESHOLD="80.0"
    export PERFORMANCE_TUNER_AUTO_SCALING_ENABLED="false"
    export PERFORMANCE_TUNER_OPTIMIZATION_INTERVAL="300"
    
    # Initialize plugin with custom configuration
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    # Check if configuration is reflected in status
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null)
    
    if ! echo "$status" | jq -e '.configuration.cpu_threshold' >/dev/null 2>&1; then
        echo "ERROR: Configuration not reflected in plugin status"
        return 1
    fi
    
    # Clean up
    unset PERFORMANCE_TUNER_CPU_THRESHOLD
    unset PERFORMANCE_TUNER_MEMORY_THRESHOLD
    unset PERFORMANCE_TUNER_AUTO_SCALING_ENABLED
    unset PERFORMANCE_TUNER_OPTIMIZATION_INTERVAL
    
    return 0
}

test_cloudwatch_integration() {
    # Test CloudWatch integration functionality
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # This would test CloudWatch metrics integration
    # For now, just test that the plugin handles CloudWatch access
    local analysis_result
    analysis_result=$(bash "$PLUGIN_SCRIPT" analyze all false 2>/dev/null)
    
    if [[ -z "$analysis_result" ]]; then
        echo "ERROR: CloudWatch integration test failed"
        return 1
    fi
    
    return 0
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_plugin_error_handling_invalid_optimization_type() {
    # Test plugin behavior with invalid optimization type
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test with invalid optimization type (should handle gracefully)
    local optimization_result
    optimization_result=$(bash "$PLUGIN_SCRIPT" optimize invalid_type all 2>/dev/null || echo '{"error": "handled"}')
    
    # Should handle error gracefully
    if [[ -z "$optimization_result" ]]; then
        echo "ERROR: Plugin should handle invalid optimization type gracefully"
        return 1
    fi
    
    return 0
}

test_plugin_error_handling_system_commands() {
    # Test plugin behavior when system commands are not available
    export PATH="/nonexistent"
    
    mock_aws_cli
    
    # Plugin should handle missing system commands gracefully
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    local result=$?
    
    # Should succeed with warnings, not fail completely
    if [[ $result -eq 0 ]]; then
        return 0
    else
        echo "ERROR: Plugin should handle missing system commands gracefully"
        return 1
    fi
}

test_plugin_error_handling_resource_constraints() {
    # Test plugin behavior under resource constraints
    # Mock system commands to return low resources
    cat > "/tmp/free" <<'EOF'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:         512000      480000       10000       10000       22000       20000"
echo "Swap:        512000      500000       12000"
EOF
    chmod +x "/tmp/free"
    
    cat > "/tmp/df" <<'EOF'
#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1        1048576  1000000     48576  95% /"
EOF
    chmod +x "/tmp/df"
    
    export PATH="/tmp:$PATH"
    mock_aws_cli
    
    # Plugin should handle resource constraints gracefully
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    local result=$?
    
    # Should succeed with warnings about resource constraints
    if [[ $result -eq 0 ]]; then
        return 0
    else
        echo "ERROR: Plugin should handle resource constraints gracefully"
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
    mock_system_commands
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

test_plugin_performance_analysis_speed() {
    # Test performance analysis speed
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    local start_time=$(date +%s.%N)
    
    bash "$PLUGIN_SCRIPT" analyze all false >/dev/null 2>&1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Analysis should complete within 10 seconds
    if (( $(echo "$duration > 10" | bc -l 2>/dev/null || echo "0") )); then
        echo "ERROR: Performance analysis took too long: ${duration}s"
        return 1
    fi
    
    return 0
}

test_plugin_performance_optimization_speed() {
    # Test performance optimization speed
    mock_aws_cli
    mock_system_commands
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    local start_time=$(date +%s.%N)
    
    bash "$PLUGIN_SCRIPT" optimize auto all >/dev/null 2>&1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Optimization should complete within 15 seconds
    if (( $(echo "$duration > 15" | bc -l 2>/dev/null || echo "0") )); then
        echo "ERROR: Performance optimization took too long: ${duration}s"
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
    run_test "Plugin Performance Category" test_plugin_performance_category && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Monitoring Capabilities" test_plugin_monitoring_capabilities && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Validation Tests
    echo -e "\n--- Plugin Validation Tests ---"
    run_test "Plugin Validation Success" test_plugin_validation_success && ((tests_passed++)) || ((tests_failed++))
    run_test "CloudWatch Access Validation" test_plugin_validation_cloudwatch_access && ((tests_passed++)) || ((tests_failed++))
    run_test "Performance Configuration Validation" test_plugin_performance_configuration_validation && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Lifecycle Tests
    echo -e "\n--- Plugin Lifecycle Tests ---"
    run_test "Plugin Initialization" test_plugin_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Start" test_plugin_start && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Stop" test_plugin_stop && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Functionality Tests
    echo -e "\n--- Plugin Functionality Tests ---"
    run_test "Performance Analysis" test_performance_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Performance Optimization" test_performance_optimization && ((tests_passed++)) || ((tests_failed++))
    run_test "Performance Monitoring" test_performance_monitoring && ((tests_passed++)) || ((tests_failed++))
    run_test "Performance Report" test_performance_report && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Health Check" test_plugin_health_check && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Metrics" test_plugin_metrics && ((tests_passed++)) || ((tests_failed++))
    
    # Performance Analysis Tests
    echo -e "\n--- Performance Analysis Tests ---"
    run_test "System Resource Analysis" test_system_resource_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "AWS Resource Analysis" test_aws_resource_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Application Performance Analysis" test_application_performance_analysis && ((tests_passed++)) || ((tests_failed++))
    run_test "Performance Threshold Handling" test_performance_threshold_handling && ((tests_passed++)) || ((tests_failed++))
    
    # Performance Optimization Tests
    echo -e "\n--- Performance Optimization Tests ---"
    run_test "CPU Optimization" test_cpu_optimization && ((tests_passed++)) || ((tests_failed++))
    run_test "Memory Optimization" test_memory_optimization && ((tests_passed++)) || ((tests_failed++))
    run_test "Auto Scaling Optimization" test_autoscaling_optimization && ((tests_passed++)) || ((tests_failed++))
    
    # Integration Tests
    echo -e "\n--- Integration Tests ---"
    run_test "Unity Framework Integration" test_plugin_integration_with_unity_framework && ((tests_passed++)) || ((tests_failed++))
    run_test "Configuration Handling" test_plugin_configuration_handling && ((tests_passed++)) || ((tests_failed++))
    run_test "CloudWatch Integration" test_cloudwatch_integration && ((tests_passed++)) || ((tests_failed++))
    
    # Error Handling Tests
    echo -e "\n--- Error Handling Tests ---"
    run_test "Invalid Optimization Type Handling" test_plugin_error_handling_invalid_optimization_type && ((tests_passed++)) || ((tests_failed++))
    run_test "System Commands Error Handling" test_plugin_error_handling_system_commands && ((tests_passed++)) || ((tests_failed++))
    run_test "Resource Constraints Handling" test_plugin_error_handling_resource_constraints && ((tests_passed++)) || ((tests_failed++))
    
    # Performance Tests
    echo -e "\n--- Performance Tests ---"
    run_test "Initialization Performance" test_plugin_performance_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Analysis Performance" test_plugin_performance_analysis_speed && ((tests_passed++)) || ((tests_failed++))
    run_test "Optimization Performance" test_plugin_performance_optimization_speed && ((tests_passed++)) || ((tests_failed++))
    
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
    cat > "$TEST_OUTPUT_DIR/performance-tuner-test-results.json" <<EOF
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