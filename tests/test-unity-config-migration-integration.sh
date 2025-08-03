#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Migration Integration Test
# Comprehensive test suite for configuration migration system
# Tests integration with existing variable management and Unity system
# =============================================================================

set -euo pipefail

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

readonly TEST_NAME="Unity Configuration Migration Integration Test"
readonly TEST_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly CONFIG_ROOT="$PROJECT_ROOT/config"
readonly LIB_DIR="$PROJECT_ROOT/lib"

# Test directories
readonly TEST_DATA_DIR="$SCRIPT_DIR/data/config-migration"
readonly TEST_OUTPUT_DIR="$SCRIPT_DIR/output/config-migration"
readonly TEST_BACKUP_DIR="$TEST_OUTPUT_DIR/backups"

# Unity services
readonly UNITY_SERVICES_DIR="$LIB_DIR/unity/services"
readonly MIGRATION_SERVICE="$UNITY_SERVICES_DIR/unity-config-migration.sh"
readonly VALIDATION_ENGINE="$UNITY_SERVICES_DIR/config-validation-engine.sh"
readonly CACHE_MANAGER="$LIB_DIR/unity/utils/config-cache-manager.sh"
readonly OVERRIDE_MANAGER="$LIB_DIR/unity/utils/environment-override-manager.sh"
readonly MIGRATION_CLI="$PROJECT_ROOT/scripts/unity-config-migration-cli.sh"

# Test state
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0
declare -a TEST_RESULTS=()

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Enhanced test logging
log_test() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo "[$timestamp] [TEST] INFO: $message"
            ;;
        "PASS")
            echo "[$timestamp] [TEST] PASS: $message"
            ;;
        "FAIL")
            echo "[$timestamp] [TEST] FAIL: $message" >&2
            ;;
        "SKIP")
            echo "[$timestamp] [TEST] SKIP: $message"
            ;;
        "ERROR")
            echo "[$timestamp] [TEST] ERROR: $message" >&2
            ;;
        "DEBUG")
            [[ "${TEST_DEBUG:-false}" == "true" ]] && \
                echo "[$timestamp] [TEST] DEBUG: $message" >&2
            ;;
    esac
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        log_test "ERROR" "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"
    
    if [[ -n "$value" ]]; then
        return 0
    else
        log_test "ERROR" "$message: value is empty"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        log_test "ERROR" "$message: $file does not exist"
        return 1
    fi
}

assert_json_valid() {
    local json_file="$1"
    local message="${2:-JSON should be valid}"
    
    if command -v jq >/dev/null 2>&1 && jq '.' "$json_file" >/dev/null 2>&1; then
        return 0
    else
        log_test "ERROR" "$message: $json_file is not valid JSON"
        return 1
    fi
}

# Run test with error handling
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_test "INFO" "Running test: $test_name"
    
    if "$test_function"; then
        log_test "PASS" "$test_name"
        TEST_RESULTS+=("PASS: $test_name")
        ((TEST_PASSED++))
        return 0
    else
        log_test "FAIL" "$test_name"
        TEST_RESULTS+=("FAIL: $test_name")
        ((TEST_FAILED++))
        return 1
    fi
}

# Skip test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"
    
    log_test "SKIP" "$test_name - $reason"
    TEST_RESULTS+=("SKIP: $test_name - $reason")
    ((TEST_SKIPPED++))
}

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

# Setup test environment
setup_test_environment() {
    log_test "INFO" "Setting up test environment..."
    
    # Create test directories
    mkdir -p "$TEST_DATA_DIR" "$TEST_OUTPUT_DIR" "$TEST_BACKUP_DIR"
    
    # Create test configuration files
    create_test_config_files
    
    # Set test environment variables
    export CONFIG_ROOT="$TEST_OUTPUT_DIR/config"
    export CONFIG_CACHE_ROOT="$TEST_OUTPUT_DIR/.cache"
    export TEST_MODE="true"
    export CACHE_DEBUG="false"
    export OVERRIDE_DEBUG="false"
    export CONFIG_MIGRATION_DEBUG="false"
    
    # Copy original config to test directory
    cp -r "$CONFIG_ROOT" "$TEST_OUTPUT_DIR/"
    
    log_test "INFO" "Test environment setup completed"
}

# Create test configuration files
create_test_config_files() {
    mkdir -p "$TEST_DATA_DIR"
    
    # Create test defaults.yml
    cat > "$TEST_DATA_DIR/test-defaults.yml" << 'EOF'
global:
  project_name: TestProject
  region: us-east-1
  environment: test

deployment_variables:
  aws_region: us-east-1
  deployment_type: spot
  instance_type: t3.micro
  key_name: test-key
  volume_size: 20
  debug: false

applications:
  test_app:
    image: nginx:latest
    port: 8080
    resources:
      cpu_limit: "0.5"
      memory_limit: "512M"

security:
  container_security:
    run_as_non_root: true
  network_security:
    cors_strict_mode: false

monitoring:
  metrics:
    enabled: true
    retention_days: 7
  logging:
    level: info
EOF

    # Create test environment config
    cat > "$TEST_DATA_DIR/test-environment.yml" << 'EOF'
global:
  environment: test
  region: us-west-2

deployment_variables:
  debug: true
  instance_type: t3.small
  volume_size: 30

applications:
  test_app:
    resources:
      cpu_limit: "1.0"
      memory_limit: "1G"

monitoring:
  logging:
    level: debug
EOF

    # Create test .env file
    cat > "$TEST_DATA_DIR/test.env" << 'EOF'
# Test environment variables
AWS_REGION=us-west-1
DEPLOYMENT_TYPE=ondemand
INSTANCE_TYPE=t3.medium
VOLUME_SIZE=40
DEBUG=true
STACK_NAME=test-stack
EOF
}

# Cleanup test environment
cleanup_test_environment() {
    log_test "INFO" "Cleaning up test environment..."
    
    # Remove test directories
    rm -rf "$TEST_OUTPUT_DIR"
    
    # Unset test environment variables
    unset CONFIG_ROOT CONFIG_CACHE_ROOT TEST_MODE
    unset CACHE_DEBUG OVERRIDE_DEBUG CONFIG_MIGRATION_DEBUG
    
    log_test "INFO" "Test environment cleanup completed"
}

# =============================================================================
# UNIT TESTS FOR INDIVIDUAL COMPONENTS
# =============================================================================

# Test migration service loading
test_migration_service_loading() {
    log_test "DEBUG" "Testing migration service loading..."
    
    # Check if migration service file exists
    assert_file_exists "$MIGRATION_SERVICE" "Migration service should exist"
    
    # Load migration service
    if source "$MIGRATION_SERVICE" 2>/dev/null; then
        log_test "DEBUG" "Migration service loaded successfully"
    else
        log_test "ERROR" "Failed to load migration service"
        return 1
    fi
    
    # Check if key functions are available
    if declare -f initialize_config_migration >/dev/null 2>&1; then
        log_test "DEBUG" "initialize_config_migration function available"
    else
        log_test "ERROR" "initialize_config_migration function not available"
        return 1
    fi
    
    if declare -f discover_configuration_sources >/dev/null 2>&1; then
        log_test "DEBUG" "discover_configuration_sources function available"
    else
        log_test "ERROR" "discover_configuration_sources function not available"
        return 1
    fi
    
    return 0
}

# Test validation engine loading
test_validation_engine_loading() {
    log_test "DEBUG" "Testing validation engine loading..."
    
    # Check if validation engine file exists
    assert_file_exists "$VALIDATION_ENGINE" "Validation engine should exist"
    
    # Load validation engine
    if source "$VALIDATION_ENGINE" 2>/dev/null; then
        log_test "DEBUG" "Validation engine loaded successfully"
    else
        log_test "ERROR" "Failed to load validation engine"
        return 1
    fi
    
    # Check if key functions are available
    if declare -f initialize_validation_engine >/dev/null 2>&1; then
        log_test "DEBUG" "initialize_validation_engine function available"
    else
        log_test "ERROR" "initialize_validation_engine function not available"
        return 1
    fi
    
    return 0
}

# Test cache manager loading
test_cache_manager_loading() {
    log_test "DEBUG" "Testing cache manager loading..."
    
    # Check if cache manager file exists
    assert_file_exists "$CACHE_MANAGER" "Cache manager should exist"
    
    # Load cache manager
    if source "$CACHE_MANAGER" 2>/dev/null; then
        log_test "DEBUG" "Cache manager loaded successfully"
    else
        log_test "ERROR" "Failed to load cache manager"
        return 1
    fi
    
    # Check if key functions are available
    if declare -f init_cache_manager >/dev/null 2>&1; then
        log_test "DEBUG" "init_cache_manager function available"
    else
        log_test "ERROR" "init_cache_manager function not available"
        return 1
    fi
    
    return 0
}

# Test override manager loading
test_override_manager_loading() {
    log_test "DEBUG" "Testing override manager loading..."
    
    # Check if override manager file exists
    assert_file_exists "$OVERRIDE_MANAGER" "Override manager should exist"
    
    # Load override manager
    if source "$OVERRIDE_MANAGER" 2>/dev/null; then
        log_test "DEBUG" "Override manager loaded successfully"
    else
        log_test "ERROR" "Failed to load override manager"
        return 1
    fi
    
    # Check if key functions are available
    if declare -f initialize_override_manager >/dev/null 2>&1; then
        log_test "DEBUG" "initialize_override_manager function available"
    else
        log_test "ERROR" "initialize_override_manager function not available"
        return 1
    fi
    
    return 0
}

# =============================================================================
# FUNCTIONAL TESTS
# =============================================================================

# Test configuration discovery
test_configuration_discovery() {
    log_test "DEBUG" "Testing configuration discovery..."
    
    # Load migration service
    source "$MIGRATION_SERVICE" || return 1
    
    # Initialize migration system
    initialize_config_migration "test" || return 1
    
    # Run discovery
    local discovery_report
    discovery_report=$(discover_configuration_sources) || return 1
    
    # Validate discovery report
    assert_file_exists "$discovery_report" "Discovery report should be created"
    assert_json_valid "$discovery_report" "Discovery report should be valid JSON"
    
    # Check report content
    local yaml_configs_count=$(jq '.sources.yaml_configs | length' "$discovery_report" 2>/dev/null || echo "0")
    local env_files_count=$(jq '.sources.env_files | length' "$discovery_report" 2>/dev/null || echo "0")
    
    log_test "DEBUG" "Found $yaml_configs_count YAML configs and $env_files_count env files"
    
    # Should find at least the defaults.yml
    if [[ "$yaml_configs_count" -gt "0" ]]; then
        log_test "DEBUG" "YAML configurations discovered successfully"
    else
        log_test "ERROR" "No YAML configurations discovered"
        return 1
    fi
    
    return 0
}

# Test configuration validation
test_configuration_validation() {
    log_test "DEBUG" "Testing configuration validation..."
    
    # Load validation engine
    source "$VALIDATION_ENGINE" || return 1
    
    # Initialize validation engine
    initialize_validation_engine || return 1
    
    # Create a test configuration file
    local test_config="$TEST_OUTPUT_DIR/test-validation-config.yml"
    cp "$TEST_DATA_DIR/test-defaults.yml" "$test_config"
    
    # Run validation
    local validation_report
    validation_report=$(validate_config_file "$test_config") || return 1
    
    # Validate validation report
    assert_file_exists "$validation_report" "Validation report should be created"
    assert_json_valid "$validation_report" "Validation report should be valid JSON"
    
    # Check validation results
    local schema_valid=$(jq -r '.schema_valid' "$validation_report" 2>/dev/null || echo "false")
    local error_count=$(jq '.errors | length' "$validation_report" 2>/dev/null || echo "999")
    
    log_test "DEBUG" "Schema valid: $schema_valid, Errors: $error_count"
    
    # Should have valid schema
    if [[ "$schema_valid" == "true" ]]; then
        log_test "DEBUG" "Configuration validation passed"
    else
        log_test "ERROR" "Configuration validation failed"
        return 1
    fi
    
    return 0
}

# Test cache operations
test_cache_operations() {
    log_test "DEBUG" "Testing cache operations..."
    
    # Load cache manager
    source "$CACHE_MANAGER" || return 1
    
    # Initialize cache manager
    init_cache_manager || return 1
    
    # Test cache set operation
    local test_data="test configuration data"
    local cache_key="test_config_key"
    
    if cache_config "$cache_key" "$test_data" 300; then
        log_test "DEBUG" "Cache set operation successful"
    else
        log_test "ERROR" "Cache set operation failed"
        return 1
    fi
    
    # Test cache get operation
    local retrieved_data
    if retrieved_data=$(get_cached_config "$cache_key"); then
        log_test "DEBUG" "Cache get operation successful"
        
        # Verify data integrity
        if [[ "$retrieved_data" == "$test_data" ]]; then
            log_test "DEBUG" "Cached data integrity verified"
        else
            log_test "ERROR" "Cached data integrity check failed"
            return 1
        fi
    else
        log_test "ERROR" "Cache get operation failed"
        return 1
    fi
    
    # Test cache exists operation
    if is_config_cached "$cache_key"; then
        log_test "DEBUG" "Cache exists check successful"
    else
        log_test "ERROR" "Cache exists check failed"
        return 1
    fi
    
    # Test cache delete operation
    if delete_cached_config "$cache_key"; then
        log_test "DEBUG" "Cache delete operation successful"
    else
        log_test "ERROR" "Cache delete operation failed"
        return 1
    fi
    
    # Verify deletion
    if ! is_config_cached "$cache_key"; then
        log_test "DEBUG" "Cache deletion verified"
    else
        log_test "ERROR" "Cache deletion verification failed"
        return 1
    fi
    
    return 0
}

# Test environment overrides
test_environment_overrides() {
    log_test "DEBUG" "Testing environment overrides..."
    
    # Load override manager
    source "$OVERRIDE_MANAGER" || return 1
    
    # Initialize override manager
    initialize_override_manager || return 1
    
    # Create test environment configuration
    local env_config_dir="$TEST_OUTPUT_DIR/config/environments"
    mkdir -p "$env_config_dir"
    cp "$TEST_DATA_DIR/test-environment.yml" "$env_config_dir/test.yml"
    
    # Create test .env file
    cp "$TEST_DATA_DIR/test.env" "$TEST_OUTPUT_DIR/.env.test"
    
    # Set test environment variables
    export AWS_REGION="us-east-2"
    export INSTANCE_TYPE="t3.large"
    export DEBUG="true"
    
    # Test environment discovery
    local discovery_report
    discovery_report=$(get_environment_discovery) || return 1
    
    assert_file_exists "$discovery_report" "Environment discovery report should be created"
    assert_json_valid "$discovery_report" "Environment discovery report should be valid JSON"
    
    # Test configuration resolution
    local resolved_config
    resolved_config=$(resolve_environment_configuration "test" "$TEST_OUTPUT_DIR/resolved-test-config.yml") || return 1
    
    # Verify resolved configuration exists
    assert_file_exists "$TEST_OUTPUT_DIR/resolved-test-config.yml" "Resolved configuration should be created"
    
    # Verify overrides were applied
    if command -v yq >/dev/null 2>&1; then
        local resolved_region=$(yq eval '.global.region' "$TEST_OUTPUT_DIR/resolved-test-config.yml" 2>/dev/null || echo "")
        local resolved_instance_type=$(yq eval '.deployment_variables.instance_type' "$TEST_OUTPUT_DIR/resolved-test-config.yml" 2>/dev/null || echo "")
        
        log_test "DEBUG" "Resolved region: $resolved_region, instance type: $resolved_instance_type"
        
        # Environment variables should override file values
        if [[ "$resolved_region" == "us-east-2" ]]; then
            log_test "DEBUG" "Region override applied correctly"
        else
            log_test "ERROR" "Region override not applied correctly"
            return 1
        fi
        
        if [[ "$resolved_instance_type" == "t3.large" ]]; then
            log_test "DEBUG" "Instance type override applied correctly"
        else
            log_test "ERROR" "Instance type override not applied correctly"
            return 1
        fi
    fi
    
    # Clean up environment variables
    unset AWS_REGION INSTANCE_TYPE DEBUG
    
    return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

# Test full migration workflow
test_full_migration_workflow() {
    log_test "DEBUG" "Testing full migration workflow..."
    
    # Load all services
    source "$MIGRATION_SERVICE" || return 1
    source "$VALIDATION_ENGINE" || return 1
    source "$CACHE_MANAGER" || return 1
    source "$OVERRIDE_MANAGER" || return 1
    
    # Initialize all systems
    initialize_config_migration "test" || return 1
    initialize_validation_engine || return 1
    init_cache_manager || return 1
    initialize_override_manager || return 1
    
    # Step 1: Discovery
    log_test "DEBUG" "Step 1: Running configuration discovery..."
    local discovery_report
    discovery_report=$(discover_configuration_sources) || return 1
    assert_file_exists "$discovery_report" "Discovery report should exist"
    
    # Step 2: Validation
    log_test "DEBUG" "Step 2: Running configuration validation..."
    local validation_report
    validation_report=$(validate_configuration "$CONFIG_ROOT/defaults.yml") || return 1
    assert_file_exists "$validation_report" "Validation report should exist"
    
    # Step 3: Environment resolution
    log_test "DEBUG" "Step 3: Running environment resolution..."
    local resolved_config="$TEST_OUTPUT_DIR/migration-resolved-config.yml"
    resolve_environment_configuration "development" "$resolved_config" || return 1
    assert_file_exists "$resolved_config" "Resolved configuration should exist"
    
    # Step 4: Final validation
    log_test "DEBUG" "Step 4: Running final validation..."
    local final_validation
    final_validation=$(validate_configuration "$resolved_config") || return 1
    assert_file_exists "$final_validation" "Final validation report should exist"
    
    # Check final validation results
    local final_schema_valid=$(jq -r '.schema_valid' "$final_validation" 2>/dev/null || echo "false")
    if [[ "$final_schema_valid" == "true" ]]; then
        log_test "DEBUG" "Full migration workflow completed successfully"
        return 0
    else
        log_test "ERROR" "Full migration workflow validation failed"
        return 1
    fi
}

# Test CLI integration
test_cli_integration() {
    log_test "DEBUG" "Testing CLI integration..."
    
    # Check if CLI script exists and is executable
    assert_file_exists "$MIGRATION_CLI" "Migration CLI should exist"
    
    if [[ -x "$MIGRATION_CLI" ]]; then
        log_test "DEBUG" "Migration CLI is executable"
    else
        log_test "ERROR" "Migration CLI is not executable"
        return 1
    fi
    
    # Test CLI help command
    if "$MIGRATION_CLI" help >/dev/null 2>&1; then
        log_test "DEBUG" "CLI help command works"
    else
        log_test "ERROR" "CLI help command failed"
        return 1
    fi
    
    # Test CLI discovery command
    local cli_discovery_output="$TEST_OUTPUT_DIR/cli-discovery.json"
    if "$MIGRATION_CLI" discover json "$cli_discovery_output" >/dev/null 2>&1; then
        log_test "DEBUG" "CLI discovery command works"
        assert_file_exists "$cli_discovery_output" "CLI discovery output should exist"
    else
        log_test "ERROR" "CLI discovery command failed"
        return 1
    fi
    
    # Test CLI validation command
    if "$MIGRATION_CLI" validate "$CONFIG_ROOT/defaults.yml" summary >/dev/null 2>&1; then
        log_test "DEBUG" "CLI validation command works"
    else
        log_test "ERROR" "CLI validation command failed"
        return 1
    fi
    
    return 0
}

# Test integration with existing variable management
test_variable_management_integration() {
    log_test "DEBUG" "Testing integration with existing variable management..."
    
    # Load existing variable management
    local var_mgmt_file="$LIB_DIR/deployment-variable-management.sh"
    if [[ -f "$var_mgmt_file" ]]; then
        source "$var_mgmt_file" || return 1
        log_test "DEBUG" "Existing variable management loaded"
    else
        log_test "ERROR" "Existing variable management not found"
        return 1
    fi
    
    # Load Unity override manager
    source "$OVERRIDE_MANAGER" || return 1
    initialize_override_manager || return 1
    
    # Test that both systems can coexist
    if declare -f init_variable_store >/dev/null 2>&1; then
        log_test "DEBUG" "Existing variable management functions available"
    else
        log_test "ERROR" "Existing variable management functions not available"
        return 1
    fi
    
    if declare -f resolve_environment_configuration >/dev/null 2>&1; then
        log_test "DEBUG" "Unity override functions available"
    else
        log_test "ERROR" "Unity override functions not available"
        return 1
    fi
    
    # Test variable store initialization
    if init_variable_store "/aibuildkit" >/dev/null 2>&1; then
        log_test "DEBUG" "Variable store initialization works"
    else
        log_test "ERROR" "Variable store initialization failed"
        return 1
    fi
    
    # Test environment resolution
    local resolved_config="$TEST_OUTPUT_DIR/integration-resolved-config.yml"
    if resolve_environment_configuration "development" "$resolved_config" >/dev/null 2>&1; then
        log_test "DEBUG" "Environment resolution works with variable management"
        assert_file_exists "$resolved_config" "Integration resolved configuration should exist"
    else
        log_test "ERROR" "Environment resolution failed with variable management"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

# Test performance with large configurations
test_performance_large_configs() {
    log_test "DEBUG" "Testing performance with large configurations..."
    
    # Load all services
    source "$MIGRATION_SERVICE" || return 1
    source "$CACHE_MANAGER" || return 1
    
    # Initialize systems
    initialize_config_migration "test" || return 1
    init_cache_manager || return 1
    
    # Create a large test configuration
    local large_config="$TEST_OUTPUT_DIR/large-test-config.yml"
    cat > "$large_config" << 'EOF'
global:
  project_name: LargeTestProject
  region: us-east-1
EOF
    
    # Add many configuration sections
    for i in {1..100}; do
        cat >> "$large_config" << EOF
application_$i:
  name: app_$i
  image: nginx:latest
  port: $((8000 + i))
  resources:
    cpu_limit: "0.5"
    memory_limit: "512M"
  config:
    setting_1: value_1_$i
    setting_2: value_2_$i
    setting_3: value_3_$i
EOF
    done
    
    # Time the discovery operation
    local start_time=$(date +%s)
    local discovery_report
    discovery_report=$(discover_configuration_sources) || return 1
    local end_time=$(date +%s)
    local discovery_duration=$((end_time - start_time))
    
    log_test "DEBUG" "Discovery took $discovery_duration seconds"
    
    # Performance should be reasonable (under 30 seconds)
    if [[ "$discovery_duration" -lt "30" ]]; then
        log_test "DEBUG" "Discovery performance acceptable"
    else
        log_test "ERROR" "Discovery performance too slow: ${discovery_duration}s"
        return 1
    fi
    
    # Test cache performance
    local cache_key="large_config_test"
    local large_config_data=$(cat "$large_config")
    
    # Time cache set operation
    start_time=$(date +%s)
    cache_config "$cache_key" "$large_config_data" 300 || return 1
    end_time=$(date +%s)
    local cache_set_duration=$((end_time - start_time))
    
    log_test "DEBUG" "Cache set took $cache_set_duration seconds"
    
    # Time cache get operation
    start_time=$(date +%s)
    get_cached_config "$cache_key" >/dev/null || return 1
    end_time=$(date +%s)
    local cache_get_duration=$((end_time - start_time))
    
    log_test "DEBUG" "Cache get took $cache_get_duration seconds"
    
    # Cache operations should be fast (under 5 seconds each)
    if [[ "$cache_set_duration" -lt "5" ]] && [[ "$cache_get_duration" -lt "5" ]]; then
        log_test "DEBUG" "Cache performance acceptable"
    else
        log_test "ERROR" "Cache performance too slow: set=${cache_set_duration}s, get=${cache_get_duration}s"
        return 1
    fi
    
    return 0
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

# Test error handling scenarios
test_error_handling() {
    log_test "DEBUG" "Testing error handling scenarios..."
    
    # Load services
    source "$MIGRATION_SERVICE" || return 1
    source "$VALIDATION_ENGINE" || return 1
    
    # Test 1: Invalid configuration file
    log_test "DEBUG" "Testing invalid configuration file handling..."
    local invalid_config="$TEST_OUTPUT_DIR/invalid-config.yml"
    echo "invalid: yaml: content: [unclosed" > "$invalid_config"
    
    # Validation should fail gracefully
    local validation_result=0
    validate_config_file "$invalid_config" >/dev/null 2>&1 || validation_result=$?
    
    if [[ "$validation_result" -ne "0" ]]; then
        log_test "DEBUG" "Invalid configuration properly rejected"
    else
        log_test "ERROR" "Invalid configuration should have been rejected"
        return 1
    fi
    
    # Test 2: Missing configuration file
    log_test "DEBUG" "Testing missing configuration file handling..."
    local missing_config="$TEST_OUTPUT_DIR/missing-config.yml"
    
    # Validation should fail gracefully
    validation_result=0
    validate_config_file "$missing_config" >/dev/null 2>&1 || validation_result=$?
    
    if [[ "$validation_result" -ne "0" ]]; then
        log_test "DEBUG" "Missing configuration properly handled"
    else
        log_test "ERROR" "Missing configuration should have failed"
        return 1
    fi
    
    # Test 3: Permission denied scenario
    log_test "DEBUG" "Testing permission denied scenario..."
    local readonly_config="$TEST_OUTPUT_DIR/readonly-config.yml"
    echo "test: config" > "$readonly_config"
    chmod 000 "$readonly_config"
    
    # Should handle permission errors gracefully
    validation_result=0
    validate_config_file "$readonly_config" >/dev/null 2>&1 || validation_result=$?
    
    # Restore permissions for cleanup
    chmod 644 "$readonly_config"
    
    if [[ "$validation_result" -ne "0" ]]; then
        log_test "DEBUG" "Permission denied properly handled"
    else
        log_test "ERROR" "Permission denied should have failed"
        return 1
    fi
    
    return 0
}

# =============================================================================
# TEST EXECUTION AND REPORTING
# =============================================================================

# Run all tests
run_all_tests() {
    log_test "INFO" "Starting $TEST_NAME v$TEST_VERSION"
    log_test "INFO" "=========================================="
    
    # Setup test environment
    setup_test_environment
    
    # Unit tests
    log_test "INFO" "Running unit tests..."
    run_test "Migration Service Loading" test_migration_service_loading
    run_test "Validation Engine Loading" test_validation_engine_loading
    run_test "Cache Manager Loading" test_cache_manager_loading
    run_test "Override Manager Loading" test_override_manager_loading
    
    # Functional tests
    log_test "INFO" "Running functional tests..."
    
    # Check prerequisites for functional tests
    if ! command -v jq >/dev/null 2>&1; then
        skip_test "Configuration Discovery" "jq not available"
        skip_test "Configuration Validation" "jq not available"
        skip_test "Environment Overrides" "jq not available"
    else
        run_test "Configuration Discovery" test_configuration_discovery
        run_test "Configuration Validation" test_configuration_validation
        run_test "Environment Overrides" test_environment_overrides
    fi
    
    run_test "Cache Operations" test_cache_operations
    
    # Integration tests
    log_test "INFO" "Running integration tests..."
    if command -v jq >/dev/null 2>&1; then
        run_test "Full Migration Workflow" test_full_migration_workflow
        run_test "Variable Management Integration" test_variable_management_integration
    else
        skip_test "Full Migration Workflow" "jq not available"
        skip_test "Variable Management Integration" "jq not available"
    fi
    
    run_test "CLI Integration" test_cli_integration
    
    # Performance tests
    log_test "INFO" "Running performance tests..."
    run_test "Performance Large Configs" test_performance_large_configs
    
    # Error handling tests
    log_test "INFO" "Running error handling tests..."
    run_test "Error Handling" test_error_handling
    
    # Cleanup
    cleanup_test_environment
}

# Generate test report
generate_test_report() {
    local total_tests=$((TEST_PASSED + TEST_FAILED + TEST_SKIPPED))
    
    echo
    log_test "INFO" "=========================================="
    log_test "INFO" "Test Results Summary"
    log_test "INFO" "=========================================="
    log_test "INFO" "Total Tests: $total_tests"
    log_test "INFO" "Passed: $TEST_PASSED"
    log_test "INFO" "Failed: $TEST_FAILED"
    log_test "INFO" "Skipped: $TEST_SKIPPED"
    
    if [[ "$TEST_FAILED" -eq "0" ]]; then
        log_test "INFO" "Overall Result: PASS"
    else
        log_test "INFO" "Overall Result: FAIL"
    fi
    
    echo
    log_test "INFO" "Detailed Results:"
    for result in "${TEST_RESULTS[@]}"; do
        log_test "INFO" "  $result"
    done
    
    # Generate JSON report
    local json_report="$TEST_OUTPUT_DIR/test-report.json"
    cat > "$json_report" << EOF
{
  "test_suite": "$TEST_NAME",
  "version": "$TEST_VERSION",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "summary": {
    "total": $total_tests,
    "passed": $TEST_PASSED,
    "failed": $TEST_FAILED,
    "skipped": $TEST_SKIPPED,
    "success_rate": $(echo "scale=2; $TEST_PASSED * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
  },
  "results": $(printf '%s\n' "${TEST_RESULTS[@]}" | jq -R . | jq -s .)
}
EOF
    
    log_test "INFO" "Test report generated: $json_report"
    
    # Return appropriate exit code
    return "$TEST_FAILED"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Check for required tools
    local missing_tools=()
    command -v bc >/dev/null 2>&1 || missing_tools+=("bc")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_test "ERROR" "Missing required tools: ${missing_tools[*]}"
        log_test "INFO" "Install missing tools: brew install bc (macOS) or apt-get install bc (Ubuntu)"
        exit 2
    fi
    
    # Run tests
    run_all_tests
    
    # Generate report and exit with appropriate code
    generate_test_report
    exit $?
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi