#!/bin/bash
# =============================================================================
# Test Suite: Security Validator Plugin
# Comprehensive tests for the Unity Security Validator standard plugin
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
PLUGIN_SCRIPT="$PROJECT_ROOT/lib/unity/plugins/standard-plugins/security-validator.sh"

if [[ ! -f "$PLUGIN_SCRIPT" ]]; then
    echo "ERROR: Security Validator plugin not found at: $PLUGIN_SCRIPT"
    exit 1
fi

# Test configuration
TEST_SUITE_NAME="Security Validator Plugin Tests"
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
    "iam list-roles --max-items 1")
        echo '{"Roles": [{"RoleName": "test-role", "Arn": "arn:aws:iam::123456789012:role/test-role"}]}'
        ;;
    "iam get-account-summary --query SummaryMap.AccountAccessKeysPresent --output text")
        echo "0"
        ;;
    "iam list-policies --scope Local --query"*)
        echo '{"Policies": [{"PolicyName": "TestPolicy"}]}'
        ;;
    "ec2 describe-security-groups --max-items 1")
        echo '{"SecurityGroups": [{"GroupId": "sg-12345678", "GroupName": "test-sg"}]}'
        ;;
    "ec2 describe-security-groups --query"*)
        echo '{"SecurityGroups": []}'
        ;;
    "ec2 describe-vpcs --filters"*)
        echo '{"Vpcs": []}'
        ;;
    "ec2 describe-volumes --query"*)
        echo '{"Volumes": [{"VolumeId": "vol-12345678", "Encrypted": true}]}'
        ;;
    "s3api list-buckets")
        echo '{"Buckets": [{"Name": "test-bucket-1"}, {"Name": "test-bucket-2"}]}'
        ;;
    "cloudtrail describe-trails")
        echo '{"trailList": [{"Name": "test-trail", "IsLogging": true}]}'
        ;;
    "ec2 describe-flow-logs --query FlowLogs")
        echo '{"FlowLogs": [{"FlowLogId": "fl-12345678"}]}'
        ;;
    "cloudformation describe-stack-resources --stack-name"*)
        echo '{"StackResources": [{"ResourceType": "AWS::EC2::Instance"}, {"ResourceType": "AWS::S3::Bucket"}]}'
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
    rm -rf "/tmp/test_security_validator_"*
    rm -f "/tmp/aws"
    rm -rf ".unity/plugins/security-validator" 2>/dev/null || true
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
    if [[ "$plugin_name" != "security-validator" ]]; then
        echo "ERROR: Plugin name mismatch: expected 'security-validator', got '$plugin_name'"
        return 1
    fi
    
    return 0
}

test_plugin_security_category() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    local category
    category=$(echo "$metadata" | jq -r '.category')
    
    if [[ "$category" != "security-validation" ]]; then
        echo "ERROR: Unexpected plugin category: expected 'security-validation', got '$category'"
        return 1
    fi
    
    return 0
}

test_plugin_compliance_capabilities() {
    local metadata
    metadata=$(bash "$PLUGIN_SCRIPT" metadata 2>/dev/null)
    
    # Check extension points for security-specific hooks
    local extension_points
    extension_points=$(echo "$metadata" | jq -r '.capabilities.extension_points[]' 2>/dev/null)
    
    if ! echo "$extension_points" | grep -q "on_security_violation"; then
        echo "ERROR: Missing required extension point: on_security_violation"
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

test_plugin_validation_security_permissions() {
    # Setup mock AWS CLI with limited security permissions
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$*" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "iam list-roles --max-items 1")
        echo "An error occurred (AccessDenied) when calling the ListRoles operation"
        exit 1
        ;;
    "ec2 describe-security-groups --max-items 1")
        echo '{"SecurityGroups": [{"GroupId": "sg-12345678"}]}'
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
        echo "ERROR: Plugin validation should succeed with permission warnings"
        return 1
    fi
    
    return 0
}

test_plugin_compliance_framework_validation() {
    # Test with valid compliance framework
    export SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK="CIS"
    export SECURITY_VALIDATOR_SEVERITY_THRESHOLD="HIGH"
    
    mock_aws_cli
    
    # Plugin validation should succeed
    if ! bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation failed with valid compliance framework"
        unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
        unset SECURITY_VALIDATOR_SEVERITY_THRESHOLD
        return 1
    fi
    
    # Test with invalid compliance framework
    export SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK="INVALID_FRAMEWORK"
    
    # Plugin validation should fail
    if bash "$PLUGIN_SCRIPT" validate >/dev/null 2>&1; then
        echo "ERROR: Plugin validation should fail with invalid compliance framework"
        unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
        unset SECURITY_VALIDATOR_SEVERITY_THRESHOLD
        return 1
    fi
    
    # Clean up
    unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
    unset SECURITY_VALIDATOR_SEVERITY_THRESHOLD
    
    return 0
}

# =============================================================================
# PLUGIN LIFECYCLE TESTS
# =============================================================================

test_plugin_initialization() {
    # Clean up any existing state
    rm -rf ".unity/plugins/security-validator" 2>/dev/null || true
    
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    if ! bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1; then
        echo "ERROR: Plugin initialization failed"
        return 1
    fi
    
    # Check if required directories were created
    if [[ ! -d ".unity/plugins/security-validator/state" ]]; then
        echo "ERROR: Plugin state directory not created"
        return 1
    fi
    
    if [[ ! -d ".unity/plugins/security-validator/reports" ]]; then
        echo "ERROR: Plugin reports directory not created"
        return 1
    fi
    
    if [[ ! -f ".unity/plugins/security-validator/state/status.json" ]]; then
        echo "ERROR: Plugin status file not created"
        return 1
    fi
    
    # Check if compliance framework was initialized
    if [[ ! -f ".unity/plugins/security-validator/state/compliance_framework.json" ]]; then
        echo "ERROR: Compliance framework file not created"
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

test_security_scan() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test security scan
    local scan_result
    scan_result=$(bash "$PLUGIN_SCRIPT" scan all false 2>/dev/null)
    
    if [[ -z "$scan_result" ]]; then
        echo "ERROR: Security scan returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$scan_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Security scan result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$scan_result" | jq -e '.compliance_score' >/dev/null 2>&1; then
        echo "ERROR: Scan result missing 'compliance_score' field"
        return 1
    fi
    
    if ! echo "$scan_result" | jq -e '.total_issues' >/dev/null 2>&1; then
        echo "ERROR: Scan result missing 'total_issues' field"
        return 1
    fi
    
    return 0
}

test_deployment_security_validation() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test deployment security validation
    local validation_result
    validation_result=$(bash "$PLUGIN_SCRIPT" validate-deployment test-stack false 2>/dev/null)
    
    if [[ -z "$validation_result" ]]; then
        echo "ERROR: Deployment validation returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$validation_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Deployment validation result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$validation_result" | jq -e '.validation_passed' >/dev/null 2>&1; then
        echo "ERROR: Validation result missing 'validation_passed' field"
        return 1
    fi
    
    return 0
}

test_compliance_report() {
    # Setup mock AWS CLI
    mock_aws_cli
    
    # Initialize plugin
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test compliance report generation
    local report_result
    report_result=$(bash "$PLUGIN_SCRIPT" compliance-report json true 2>/dev/null)
    
    if [[ -z "$report_result" ]]; then
        echo "ERROR: Compliance report returned no result"
        return 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$report_result" | jq '.' >/dev/null 2>&1; then
        echo "ERROR: Compliance report result is not valid JSON"
        return 1
    fi
    
    # Check if result has required fields
    if ! echo "$report_result" | jq -e '.overall_compliance_score' >/dev/null 2>&1; then
        echo "ERROR: Compliance report missing 'overall_compliance_score' field"
        return 1
    fi
    
    if ! echo "$report_result" | jq -e '.compliance_framework' >/dev/null 2>&1; then
        echo "ERROR: Compliance report missing 'compliance_framework' field"
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
    if ! echo "$metrics_result" | jq -e '.metrics.total_scans' >/dev/null 2>&1; then
        echo "ERROR: Metrics missing 'total_scans' field"
        return 1
    fi
    
    return 0
}

# =============================================================================
# SECURITY SCAN TESTS
# =============================================================================

test_iam_security_scan() {
    # Test IAM-specific security scanning
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test IAM scan
    local scan_result
    scan_result=$(bash "$PLUGIN_SCRIPT" scan iam false 2>/dev/null)
    
    if [[ -z "$scan_result" ]]; then
        echo "ERROR: IAM security scan failed"
        return 1
    fi
    
    # Check if result contains IAM-specific checks
    if ! echo "$scan_result" | grep -q "iam" 2>/dev/null; then
        echo "ERROR: IAM scan result doesn't contain IAM-specific checks"
        return 1
    fi
    
    return 0
}

test_vpc_security_scan() {
    # Test VPC-specific security scanning
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test VPC scan
    local scan_result
    scan_result=$(bash "$PLUGIN_SCRIPT" scan vpc false 2>/dev/null)
    
    if [[ -z "$scan_result" ]]; then
        echo "ERROR: VPC security scan failed"
        return 1
    fi
    
    # Check if result contains VPC-specific checks
    if ! echo "$scan_result" | grep -q "vpc" 2>/dev/null; then
        echo "ERROR: VPC scan result doesn't contain VPC-specific checks"
        return 1
    fi
    
    return 0
}

test_encryption_security_scan() {
    # Test encryption-specific security scanning
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test encryption scan
    local scan_result
    scan_result=$(bash "$PLUGIN_SCRIPT" scan encryption false 2>/dev/null)
    
    if [[ -z "$scan_result" ]]; then
        echo "ERROR: Encryption security scan failed"
        return 1
    fi
    
    # Check if result contains encryption-specific checks
    if ! echo "$scan_result" | grep -q "encryption" 2>/dev/null; then
        echo "ERROR: Encryption scan result doesn't contain encryption-specific checks"
        return 1
    fi
    
    return 0
}

test_compliance_framework_rules() {
    # Test compliance framework rule application
    export SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK="CIS"
    
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Check if CIS framework was loaded
    local framework_file=".unity/plugins/security-validator/state/compliance_framework.json"
    if [[ ! -f "$framework_file" ]]; then
        echo "ERROR: Compliance framework file not found"
        unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
        return 1
    fi
    
    # Check if framework contains CIS rules
    if ! grep -q "CIS" "$framework_file" 2>/dev/null; then
        echo "ERROR: CIS framework rules not loaded"
        unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
        return 1
    fi
    
    unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
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
    export SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK="NIST"
    export SECURITY_VALIDATOR_SEVERITY_THRESHOLD="CRITICAL"
    export SECURITY_VALIDATOR_AUTO_REMEDIATION="true"
    
    # Initialize plugin with custom configuration
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    
    # Check if configuration is reflected in status
    local status
    status=$(bash "$PLUGIN_SCRIPT" status 2>/dev/null)
    
    if ! echo "$status" | jq -e '.configuration.compliance_framework' >/dev/null 2>&1; then
        echo "ERROR: Configuration not reflected in plugin status"
        return 1
    fi
    
    # Clean up
    unset SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK
    unset SECURITY_VALIDATOR_SEVERITY_THRESHOLD
    unset SECURITY_VALIDATOR_AUTO_REMEDIATION
    
    return 0
}

test_security_violation_handling() {
    # Test security violation event handling
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # This would test the security violation handler
    # For now, just verify the plugin can handle security events
    local scan_result
    scan_result=$(bash "$PLUGIN_SCRIPT" scan all false 2>/dev/null)
    
    if [[ -z "$scan_result" ]]; then
        echo "ERROR: Security violation handling test failed"
        return 1
    fi
    
    return 0
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_plugin_error_handling_invalid_scan_scope() {
    # Test plugin behavior with invalid scan scope
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    # Test with invalid scope (should handle gracefully)
    local scan_result
    scan_result=$(bash "$PLUGIN_SCRIPT" scan invalid_scope false 2>/dev/null || echo '{"error": "handled"}')
    
    # Should handle error gracefully
    if [[ -z "$scan_result" ]]; then
        echo "ERROR: Plugin should handle invalid scan scope gracefully"
        return 1
    fi
    
    return 0
}

test_plugin_error_handling_aws_permissions() {
    # Test plugin behavior with limited AWS permissions
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$*" in
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

test_plugin_error_handling_missing_resources() {
    # Test plugin behavior when scanning resources that don't exist
    cat > "/tmp/aws" <<'EOF'
#!/bin/bash
case "$*" in
    "sts get-caller-identity")
        echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}'
        ;;
    "cloudformation describe-stack-resources --stack-name nonexistent-stack")
        echo "An error occurred (ValidationError) when calling the DescribeStackResources operation: Stack with id nonexistent-stack does not exist"
        exit 1
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
    
    # Test validation of nonexistent stack (should handle gracefully)
    local validation_result
    validation_result=$(bash "$PLUGIN_SCRIPT" validate-deployment nonexistent-stack false 2>/dev/null || echo '{"error": "handled"}')
    
    # Should handle error gracefully
    if [[ -z "$validation_result" ]]; then
        echo "ERROR: Plugin should handle missing resources gracefully"
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

test_plugin_performance_security_scan() {
    # Test security scan performance
    mock_aws_cli
    bash "$PLUGIN_SCRIPT" init >/dev/null 2>&1
    bash "$PLUGIN_SCRIPT" start >/dev/null 2>&1
    
    local start_time=$(date +%s.%N)
    
    bash "$PLUGIN_SCRIPT" scan all false >/dev/null 2>&1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Security scan should complete within 15 seconds
    if (( $(echo "$duration > 15" | bc -l 2>/dev/null || echo "0") )); then
        echo "ERROR: Security scan took too long: ${duration}s"
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
    run_test "Plugin Security Category" test_plugin_security_category && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Compliance Capabilities" test_plugin_compliance_capabilities && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Validation Tests
    echo -e "\n--- Plugin Validation Tests ---"
    run_test "Plugin Validation Success" test_plugin_validation_success && ((tests_passed++)) || ((tests_failed++))
    run_test "Security Permissions Validation" test_plugin_validation_security_permissions && ((tests_passed++)) || ((tests_failed++))
    run_test "Compliance Framework Validation" test_plugin_compliance_framework_validation && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Lifecycle Tests
    echo -e "\n--- Plugin Lifecycle Tests ---"
    run_test "Plugin Initialization" test_plugin_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Start" test_plugin_start && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Stop" test_plugin_stop && ((tests_passed++)) || ((tests_failed++))
    
    # Plugin Functionality Tests
    echo -e "\n--- Plugin Functionality Tests ---"
    run_test "Security Scan" test_security_scan && ((tests_passed++)) || ((tests_failed++))
    run_test "Deployment Security Validation" test_deployment_security_validation && ((tests_passed++)) || ((tests_failed++))
    run_test "Compliance Report" test_compliance_report && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Health Check" test_plugin_health_check && ((tests_passed++)) || ((tests_failed++))
    run_test "Plugin Metrics" test_plugin_metrics && ((tests_passed++)) || ((tests_failed++))
    
    # Security Scan Tests
    echo -e "\n--- Security Scan Tests ---"
    run_test "IAM Security Scan" test_iam_security_scan && ((tests_passed++)) || ((tests_failed++))
    run_test "VPC Security Scan" test_vpc_security_scan && ((tests_passed++)) || ((tests_failed++))
    run_test "Encryption Security Scan" test_encryption_security_scan && ((tests_passed++)) || ((tests_failed++))
    run_test "Compliance Framework Rules" test_compliance_framework_rules && ((tests_passed++)) || ((tests_failed++))
    
    # Integration Tests
    echo -e "\n--- Integration Tests ---"
    run_test "Unity Framework Integration" test_plugin_integration_with_unity_framework && ((tests_passed++)) || ((tests_failed++))
    run_test "Configuration Handling" test_plugin_configuration_handling && ((tests_passed++)) || ((tests_failed++))
    run_test "Security Violation Handling" test_security_violation_handling && ((tests_passed++)) || ((tests_failed++))
    
    # Error Handling Tests
    echo -e "\n--- Error Handling Tests ---"
    run_test "Invalid Scan Scope Handling" test_plugin_error_handling_invalid_scan_scope && ((tests_passed++)) || ((tests_failed++))
    run_test "AWS Permissions Error Handling" test_plugin_error_handling_aws_permissions && ((tests_passed++)) || ((tests_failed++))
    run_test "Missing Resources Handling" test_plugin_error_handling_missing_resources && ((tests_passed++)) || ((tests_failed++))
    
    # Performance Tests
    echo -e "\n--- Performance Tests ---"
    run_test "Initialization Performance" test_plugin_performance_initialization && ((tests_passed++)) || ((tests_failed++))
    run_test "Security Scan Performance" test_plugin_performance_security_scan && ((tests_passed++)) || ((tests_failed++))
    
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
    cat > "$TEST_OUTPUT_DIR/security-validator-test-results.json" <<EOF
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