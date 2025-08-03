#!/bin/bash
# =============================================================================
# Unity Config Service Unit Tests
# Comprehensive unit testing for Unity Config service functions
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework
unity_test_init "test-unity-config-service" "service-unit" "unity-config-service"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up test environment
setup_config_service_tests() {
    # Load the Config service
    source "$PROJECT_ROOT/lib/unity/services/unity-config-service.sh" 2>/dev/null || {
        log_error "Failed to load Unity Config service"
        return 1
    }
    
    # Create test configuration directory
    export TEST_CONFIG_DIR="/tmp/unity-config-test-$$"
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_CONFIG_DIR/.unity/state"
    mkdir -p "$TEST_CONFIG_DIR/config"
    
    # Set test-specific paths
    export UNITY_CONFIG_FILE="$TEST_CONFIG_DIR/config/unity.yml"
    export UNITY_CONFIG_CACHE_DIR="$TEST_CONFIG_DIR/.unity/state"
    export UNITY_CONFIG_CACHE="$UNITY_CONFIG_CACHE_DIR/config-cache.json"
    export PROJECT_ROOT="$TEST_CONFIG_DIR"
    
    # Create test configuration files
    _create_test_config_files
    
    # Mock external commands
    mock_function "python3" 'case "$1" in
        "-c")
            if [[ "$2" == *"yaml.safe_load"* ]]; then
                return 0  # Simulate valid YAML
            else
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac'
    
    mock_function "yq" 'case "$1" in
        "eval")
            case "$3" in
                "AWS_REGION") echo "us-west-2" ;;
                "STACK_NAME") echo "test-stack" ;;
                "INSTANCE_TYPE") echo "t3.medium" ;;
                "DEBUG") echo "true" ;;
                *) echo "" ;;
            esac
            ;;
        *)
            return 0
            ;;
    esac'
    
    mock_function "aws" 'case "$1" in
        "ssm")
            case "$2" in
                "get-parameters-by-path")
                    echo -e "/aibuildkit/TEST_PARAM\ttest-value"
                    ;;
                *)
                    return 0
                    ;;
            esac
            ;;
        *)
            return 0
            ;;
    esac'
    
    mock_function "jq" 'case "$1" in
        "-r")
            case "$2" in
                "keys[]") echo "TEST_VAR" ;;
                ".TEST_VAR.value") echo "test-value" ;;
                ".TEST_VAR.timestamp") echo "$(date +%s)" ;;
                *) echo "test-output" ;;
            esac
            ;;
        *)
            echo "test-json-output"
            ;;
    esac'
    
    # Set test environment variables
    export UNITY_CONFIG_LOG_LEVEL="debug"
    export UNITY_CONFIG_VALIDATION_MODE="strict"
    export UNITY_CONFIG_CACHE_TTL="300"
    export ENVIRONMENT="development"
    
    # Clear any existing configuration state
    unset UNITY_CONFIG_LOADED
    declare -gA UNITY_CONFIG_TYPES=()
    declare -gA UNITY_CONFIG_VALIDATORS=()
    declare -gA UNITY_CONFIG_DESCRIPTIONS=()
    declare -gA UNITY_CONFIG_CACHE_MAP=()
    declare -gA UNITY_CONFIG_CACHE_TIMESTAMPS=()
}

# Create test configuration files
_create_test_config_files() {
    # Create test unity.yml
    cat > "$UNITY_CONFIG_FILE" << 'EOF'
# Unity Test Configuration
AWS_REGION: us-west-2
STACK_NAME: test-stack
INSTANCE_TYPE: t3.medium
DEBUG: true
VERBOSE: false
DEPLOYMENT_TYPE: spot
EOF
    
    # Create test defaults.yml
    cat > "$TEST_CONFIG_DIR/config/defaults.yml" << 'EOF'
# Test Defaults Configuration
AWS_REGION: us-east-1
AWS_DEFAULT_REGION: us-east-1
STACK_NAME: default-stack
INSTANCE_TYPE: g4dn.xlarge
VOLUME_SIZE: 30
ENVIRONMENT: development
DEBUG: false
DRY_RUN: false
EOF
    
    # Create test .env.local file
    cat > "$TEST_CONFIG_DIR/.env.local" << 'EOF'
# Test Environment Variables
AWS_REGION=us-west-1
STACK_NAME=env-stack
DEBUG=true
VERBOSE=true
EOF
}

# Clean up test environment
cleanup_config_service_tests() {
    # Restore mocked functions
    local mock_functions=("python3" "yq" "aws" "jq")
    
    for func in "${mock_functions[@]}"; do
        restore_function "$func" 2>/dev/null || true
    done
    
    # Clean up test files
    if [[ -n "${TEST_CONFIG_DIR:-}" && -d "$TEST_CONFIG_DIR" ]]; then
        rm -rf "$TEST_CONFIG_DIR" 2>/dev/null || true
    fi
    
    # Clean up environment variables
    unset TEST_CONFIG_DIR UNITY_CONFIG_FILE UNITY_CONFIG_CACHE_DIR UNITY_CONFIG_CACHE
    unset UNITY_CONFIG_LOG_LEVEL UNITY_CONFIG_VALIDATION_MODE UNITY_CONFIG_CACHE_TTL
}

# =============================================================================
# UNITY CONFIG SERVICE INITIALIZATION TESTS
# =============================================================================

test_unity_config_service_init() {
    test_start "unity_config_service_init" "Test Unity Config service initialization"
    
    setup_config_service_tests
    
    # Test service initialization
    if unity_config_init >/dev/null 2>&1; then
        test_pass "Unity Config service initialized successfully"
        
        # Verify service is marked as loaded
        if [[ "${UNITY_CONFIG_LOADED:-}" == "true" ]]; then
            test_pass "Unity Config service marked as loaded"
        else
            test_warn "Unity Config service not marked as loaded"
        fi
    else
        test_fail "Unity Config service initialization failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_schema_initialization() {
    test_start "unity_config_schema_initialization" "Test configuration schema initialization"
    
    setup_config_service_tests
    
    # Initialize the schema
    _unity_config_init_schema >/dev/null 2>&1
    
    # Check if core variables are registered
    local core_vars=("AWS_REGION" "STACK_NAME" "INSTANCE_TYPE" "DEPLOYMENT_TYPE")
    local registered_count=0
    
    for var in "${core_vars[@]}"; do
        if [[ ${UNITY_CONFIG_TYPES["$var"]+isset} ]]; then
            ((registered_count++))
        fi
    done
    
    if [[ $registered_count -eq ${#core_vars[@]} ]]; then
        test_pass "Core configuration variables registered successfully ($registered_count/${#core_vars[@]})"
    else
        test_fail "Not all core variables registered ($registered_count/${#core_vars[@]})"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# CONFIGURATION LOADING TESTS
# =============================================================================

test_unity_config_load_env_files() {
    test_start "unity_config_load_env_files" "Test loading environment files"
    
    setup_config_service_tests
    
    # Initialize schema first
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test loading environment files
    if _unity_config_load_env_files >/dev/null 2>&1; then
        test_pass "Environment files loaded successfully"
        
        # Check if values were loaded from .env.local
        local loaded_value
        loaded_value=$(unity_config_get "AWS_REGION" 2>/dev/null)
        
        if [[ "$loaded_value" == "us-west-1" ]]; then
            test_pass "Environment file values loaded correctly"
        else
            test_warn "Environment file values not loaded as expected: got '$loaded_value'"
        fi
    else
        test_fail "Environment file loading failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_load_unity_config() {
    test_start "unity_config_load_unity_config" "Test loading Unity configuration file"
    
    setup_config_service_tests
    
    # Initialize schema first
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test loading Unity config
    if _unity_config_load_unity_config >/dev/null 2>&1; then
        test_pass "Unity configuration file loaded successfully"
        
        # Check if values were loaded
        local loaded_value
        loaded_value=$(unity_config_get "INSTANCE_TYPE" 2>/dev/null)
        
        if [[ "$loaded_value" == "t3.medium" ]]; then
            test_pass "Unity config values loaded correctly"
        else
            test_warn "Unity config values not loaded as expected: got '$loaded_value'"
        fi
    else
        test_fail "Unity configuration file loading failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_load_defaults() {
    test_start "unity_config_load_defaults" "Test loading default configuration"
    
    setup_config_service_tests
    
    # Initialize schema first
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test loading defaults
    if _unity_config_load_defaults_config >/dev/null 2>&1; then
        test_pass "Default configuration loaded successfully"
        
        # Check if default values are available
        local default_value
        default_value=$(unity_config_get "VOLUME_SIZE" 2>/dev/null)
        
        if [[ -n "$default_value" ]]; then
            test_pass "Default configuration values loaded"
        else
            test_warn "Default configuration values not found"
        fi
    else
        test_fail "Default configuration loading failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_load_hardcoded_defaults() {
    test_start "unity_config_load_hardcoded_defaults" "Test loading hardcoded defaults"
    
    setup_config_service_tests
    
    # Initialize schema first
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test loading hardcoded defaults
    if _unity_config_load_hardcoded_defaults >/dev/null 2>&1; then
        test_pass "Hardcoded defaults loaded successfully"
        
        # Check if hardcoded values are set
        local hardcoded_value
        hardcoded_value=$(unity_config_get "AWS_DEFAULT_REGION" 2>/dev/null)
        
        if [[ "$hardcoded_value" == "us-east-1" ]]; then
            test_pass "Hardcoded default values loaded correctly"
        else
            test_warn "Hardcoded default values not as expected: got '$hardcoded_value'"
        fi
    else
        test_fail "Hardcoded defaults loading failed"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# TYPE VALIDATION TESTS
# =============================================================================

test_unity_config_validate_boolean() {
    test_start "unity_config_validate_boolean" "Test boolean type validation"
    
    setup_config_service_tests
    
    # Initialize schema
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test valid boolean values
    local boolean_values=("true" "false" "yes" "no" "1" "0" "on" "off")
    local valid_count=0
    
    for value in "${boolean_values[@]}"; do
        local normalized
        normalized=$(_unity_config_validate_and_normalize "DEBUG" "$value" 2>/dev/null)
        
        if [[ "$normalized" == "true" || "$normalized" == "false" ]]; then
            ((valid_count++))
        fi
    done
    
    if [[ $valid_count -eq ${#boolean_values[@]} ]]; then
        test_pass "Boolean validation works correctly for all test values"
    else
        test_fail "Boolean validation failed for some values ($valid_count/${#boolean_values[@]})"
    fi
    
    # Test invalid boolean value
    if _unity_config_validate_and_normalize "DEBUG" "invalid" >/dev/null 2>&1; then
        test_fail "Boolean validation should have failed for invalid value"
    else
        test_pass "Boolean validation correctly rejected invalid value"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_validate_integer() {
    test_start "unity_config_validate_integer" "Test integer type validation"
    
    setup_config_service_tests
    
    # Initialize schema
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test valid integer values
    local integer_values=("0" "1" "100" "9999")
    local valid_count=0
    
    for value in "${integer_values[@]}"; do
        local normalized
        normalized=$(_unity_config_validate_and_normalize "VOLUME_SIZE" "$value" 2>/dev/null)
        
        if [[ "$normalized" == "$value" ]]; then
            ((valid_count++))
        fi
    done
    
    if [[ $valid_count -eq ${#integer_values[@]} ]]; then
        test_pass "Integer validation works correctly for all test values"
    else
        test_fail "Integer validation failed for some values ($valid_count/${#integer_values[@]})"
    fi
    
    # Test invalid integer values
    local invalid_values=("abc" "1.5" "-1" "1a")
    local invalid_rejected=0
    
    for value in "${invalid_values[@]}"; do
        if ! _unity_config_validate_and_normalize "VOLUME_SIZE" "$value" >/dev/null 2>&1; then
            ((invalid_rejected++))
        fi
    done
    
    if [[ $invalid_rejected -eq ${#invalid_values[@]} ]]; then
        test_pass "Integer validation correctly rejected all invalid values"
    else
        test_fail "Integer validation failed to reject some invalid values ($invalid_rejected/${#invalid_values[@]})"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_validate_enum() {
    test_start "unity_config_validate_enum" "Test enum type validation"
    
    setup_config_service_tests
    
    # Initialize schema
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test valid enum values for DEPLOYMENT_TYPE
    local valid_deployments=("spot" "ondemand" "simple" "enterprise")
    local valid_count=0
    
    for value in "${valid_deployments[@]}"; do
        local normalized
        normalized=$(_unity_config_validate_and_normalize "DEPLOYMENT_TYPE" "$value" 2>/dev/null)
        
        if [[ "$normalized" == "$value" ]]; then
            ((valid_count++))
        fi
    done
    
    if [[ $valid_count -eq ${#valid_deployments[@]} ]]; then
        test_pass "Enum validation works correctly for valid deployment types"
    else
        test_fail "Enum validation failed for valid deployment types ($valid_count/${#valid_deployments[@]})"
    fi
    
    # Test invalid enum value
    if _unity_config_validate_and_normalize "DEPLOYMENT_TYPE" "invalid-type" >/dev/null 2>&1; then
        test_fail "Enum validation should have failed for invalid deployment type"
    else
        test_pass "Enum validation correctly rejected invalid deployment type"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# CONFIGURATION ACCESS TESTS
# =============================================================================

test_unity_config_get() {
    test_start "unity_config_get" "Test configuration value retrieval"
    
    setup_config_service_tests
    
    # Initialize schema and load configuration
    _unity_config_init_schema >/dev/null 2>&1
    
    # Set a test value
    unity_config_set "STACK_NAME" "test-stack-get" >/dev/null 2>&1
    
    # Test getting the value
    local retrieved_value
    retrieved_value=$(unity_config_get "STACK_NAME" 2>/dev/null)
    
    if [[ "$retrieved_value" == "test-stack-get" ]]; then
        test_pass "Configuration value retrieved successfully"
    else
        test_fail "Configuration value retrieval failed: got '$retrieved_value'"
    fi
    
    # Test getting value with default
    local default_value
    default_value=$(unity_config_get "NONEXISTENT_VAR" "default-value" 2>/dev/null)
    
    if [[ "$default_value" == "default-value" ]]; then
        test_pass "Default value returned for nonexistent variable"
    else
        test_fail "Default value not returned correctly: got '$default_value'"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_set() {
    test_start "unity_config_set" "Test configuration value setting"
    
    setup_config_service_tests
    
    # Initialize schema
    _unity_config_init_schema >/dev/null 2>&1
    
    # Test setting a valid value
    if unity_config_set "STACK_NAME" "test-stack-set" >/dev/null 2>&1; then
        test_pass "Configuration value set successfully"
        
        # Verify the value was set
        local set_value
        set_value=$(unity_config_get "STACK_NAME" 2>/dev/null)
        
        if [[ "$set_value" == "test-stack-set" ]]; then
            test_pass "Set configuration value retrieved correctly"
        else
            test_fail "Set configuration value not retrieved correctly: got '$set_value'"
        fi
    else
        test_fail "Configuration value setting failed"
    fi
    
    # Test setting invalid value
    if unity_config_set "VOLUME_SIZE" "invalid-size" >/dev/null 2>&1; then
        test_fail "Should have failed to set invalid integer value"
    else
        test_pass "Correctly rejected invalid integer value"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# VALIDATION TESTS
# =============================================================================

test_unity_config_validate() {
    test_start "unity_config_validate" "Test configuration validation"
    
    setup_config_service_tests
    
    # Initialize and load valid configuration
    unity_config_init >/dev/null 2>&1
    
    # Test validation with valid configuration
    if unity_config_validate >/dev/null 2>&1; then
        test_pass "Configuration validation passed with valid config"
    else
        test_fail "Configuration validation failed with valid config"
    fi
    
    # Test validation with invalid configuration
    unity_config_set "VOLUME_SIZE" "invalid" >/dev/null 2>&1 || true
    
    if unity_config_validate >/dev/null 2>&1; then
        test_warn "Configuration validation should have failed with invalid config"
    else
        test_pass "Configuration validation correctly failed with invalid config"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_validate_cidr() {
    test_start "unity_config_validate_cidr" "Test CIDR block validation"
    
    setup_config_service_tests
    
    # Test valid CIDR blocks
    local valid_cidrs=("10.0.0.0/16" "192.168.1.0/24" "172.16.0.0/12")
    local valid_count=0
    
    for cidr in "${valid_cidrs[@]}"; do
        if _unity_config_validate_cidr "$cidr" >/dev/null 2>&1; then
            ((valid_count++))
        fi
    done
    
    if [[ $valid_count -eq ${#valid_cidrs[@]} ]]; then
        test_pass "CIDR validation works correctly for valid blocks"
    else
        test_fail "CIDR validation failed for some valid blocks ($valid_count/${#valid_cidrs[@]})"
    fi
    
    # Test invalid CIDR blocks
    local invalid_cidrs=("10.0.0.0/33" "256.1.1.1/24" "10.0.0/16" "not-a-cidr")
    local invalid_rejected=0
    
    for cidr in "${invalid_cidrs[@]}"; do
        if ! _unity_config_validate_cidr "$cidr" >/dev/null 2>&1; then
            ((invalid_rejected++))
        fi
    done
    
    if [[ $invalid_rejected -eq ${#invalid_cidrs[@]} ]]; then
        test_pass "CIDR validation correctly rejected all invalid blocks"
    else
        test_fail "CIDR validation failed to reject some invalid blocks ($invalid_rejected/${#invalid_cidrs[@]})"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# CACHING TESTS
# =============================================================================

test_unity_config_cache() {
    test_start "unity_config_cache" "Test configuration caching"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Set some values to cache
    unity_config_set "STACK_NAME" "cache-test" >/dev/null 2>&1
    unity_config_set "INSTANCE_TYPE" "t3.medium" >/dev/null 2>&1
    
    # Save cache
    if _unity_config_save_cache >/dev/null 2>&1; then
        test_pass "Configuration cache saved successfully"
        
        # Verify cache file was created
        if [[ -f "$UNITY_CONFIG_CACHE" ]]; then
            test_pass "Cache file created successfully"
        else
            test_fail "Cache file not created"
        fi
    else
        test_fail "Configuration cache save failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_clear_cache() {
    test_start "unity_config_clear_cache" "Test configuration cache clearing"
    
    setup_config_service_tests
    
    # Initialize service and create cache
    unity_config_init >/dev/null 2>&1
    unity_config_set "TEST_VAR" "test-value" >/dev/null 2>&1
    _unity_config_save_cache >/dev/null 2>&1
    
    # Clear cache
    if unity_config_clear_cache >/dev/null 2>&1; then
        test_pass "Configuration cache cleared successfully"
        
        # Verify cache file was removed
        if [[ ! -f "$UNITY_CONFIG_CACHE" ]]; then
            test_pass "Cache file removed successfully"
        else
            test_fail "Cache file not removed"
        fi
    else
        test_fail "Configuration cache clear failed"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# DYNAMIC RELOADING TESTS
# =============================================================================

test_unity_config_reload() {
    test_start "unity_config_reload" "Test configuration reloading"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test configuration reload
    if unity_config_reload >/dev/null 2>&1; then
        test_pass "Configuration reloaded successfully"
    else
        test_fail "Configuration reload failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_file_watching() {
    test_start "unity_config_file_watching" "Test configuration file watching"
    
    setup_config_service_tests
    
    # Initialize service and watchers
    unity_config_init >/dev/null 2>&1
    
    # Test file change detection (simulate by touching file)
    sleep 1  # Ensure time difference
    touch "$UNITY_CONFIG_FILE"
    
    # Check for changes
    if unity_config_check_for_changes >/dev/null 2>&1; then
        test_pass "Configuration file changes detected successfully"
    else
        test_warn "Configuration file changes not detected (may be expected)"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# EXPORT/IMPORT TESTS
# =============================================================================

test_unity_config_export() {
    test_start "unity_config_export" "Test configuration export"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test export to file
    local export_file="$TEST_CONFIG_DIR/export-test.yml"
    
    if unity_config_export "$export_file" "yaml" >/dev/null 2>&1; then
        test_pass "Configuration exported successfully"
        
        # Verify export file was created
        if [[ -f "$export_file" ]]; then
            test_pass "Export file created successfully"
        else
            test_fail "Export file not created"
        fi
    else
        test_fail "Configuration export failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_import() {
    test_start "unity_config_import" "Test configuration import"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Create test import file
    local import_file="$TEST_CONFIG_DIR/import-test.env"
    cat > "$import_file" << 'EOF'
STACK_NAME=imported-stack
INSTANCE_TYPE=imported-instance
DEBUG=true
EOF
    
    # Test import from file
    if unity_config_import "$import_file" "env" >/dev/null 2>&1; then
        test_pass "Configuration imported successfully"
        
        # Verify imported value
        local imported_value
        imported_value=$(unity_config_get "STACK_NAME" 2>/dev/null)
        
        if [[ "$imported_value" == "imported-stack" ]]; then
            test_pass "Imported configuration value retrieved correctly"
        else
            test_warn "Imported configuration value not as expected: got '$imported_value'"
        fi
    else
        test_fail "Configuration import failed"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# REPORTING TESTS
# =============================================================================

test_unity_config_show() {
    test_start "unity_config_show" "Test configuration display"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test showing configuration in different formats
    local formats=("table" "json" "yaml" "env")
    local format_success=0
    
    for format in "${formats[@]}"; do
        local output
        output=$(unity_config_show "$format" 2>/dev/null)
        
        if [[ -n "$output" ]]; then
            ((format_success++))
        fi
    done
    
    if [[ $format_success -eq ${#formats[@]} ]]; then
        test_pass "Configuration display works for all formats ($format_success/${#formats[@]})"
    else
        test_fail "Configuration display failed for some formats ($format_success/${#formats[@]})"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_show_schema() {
    test_start "unity_config_show_schema" "Test schema display"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test showing schema
    local schema_output
    schema_output=$(unity_config_show_schema "table" 2>/dev/null)
    
    if [[ -n "$schema_output" && "$schema_output" == *"VARIABLE"* ]]; then
        test_pass "Configuration schema displayed successfully"
    else
        test_fail "Configuration schema display failed or incomplete"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# UNITY SERVICE INTEGRATION TESTS
# =============================================================================

test_unity_config_execute() {
    test_start "unity_config_execute" "Test Unity Config service execution dispatcher"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test various operations
    local operations=("get STACK_NAME" "show table" "validate")
    local success_count=0
    
    for operation in "${operations[@]}"; do
        if unity_config_execute $operation >/dev/null 2>&1; then
            ((success_count++))
        fi
    done
    
    if [[ $success_count -eq ${#operations[@]} ]]; then
        test_pass "Unity Config execute dispatcher works for all operations"
    else
        test_warn "Unity Config execute dispatcher failed for some operations ($success_count/${#operations[@]})"
    fi
    
    # Test invalid operation
    if unity_config_execute "invalid-operation" >/dev/null 2>&1; then
        test_fail "Execute dispatcher should have failed for invalid operation"
    else
        test_pass "Execute dispatcher correctly rejected invalid operation"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_status() {
    test_start "unity_config_status" "Test Unity Config service status"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test service status
    if unity_config_status >/dev/null 2>&1; then
        test_pass "Unity Config service status retrieved successfully"
    else
        test_fail "Unity Config service status retrieval failed"
    fi
    
    cleanup_config_service_tests
}

test_unity_config_cleanup() {
    test_start "unity_config_cleanup" "Test Unity Config service cleanup"
    
    setup_config_service_tests
    
    # Initialize service
    unity_config_init >/dev/null 2>&1
    
    # Test service cleanup
    if unity_config_cleanup >/dev/null 2>&1; then
        test_pass "Unity Config service cleanup completed successfully"
    else
        test_fail "Unity Config service cleanup failed"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_config_error_handling() {
    test_start "config_error_handling" "Test Config service error handling"
    
    setup_config_service_tests
    
    # Test accessing unregistered variable in strict mode
    export UNITY_CONFIG_VALIDATION_MODE="strict"
    _unity_config_init_schema >/dev/null 2>&1
    
    if unity_config_get "UNREGISTERED_VAR" >/dev/null 2>&1; then
        test_fail "Expected function to fail with unregistered variable in strict mode"
    else
        test_pass "Function correctly handled unregistered variable in strict mode"
    fi
    
    cleanup_config_service_tests
}

test_config_lenient_mode() {
    test_start "config_lenient_mode" "Test Config service lenient mode"
    
    setup_config_service_tests
    
    # Test lenient mode behavior
    export UNITY_CONFIG_VALIDATION_MODE="lenient"
    _unity_config_init_schema >/dev/null 2>&1
    
    # This should succeed in lenient mode
    local result
    result=$(unity_config_get "UNREGISTERED_VAR" "default" 2>/dev/null)
    
    if [[ "$result" == "default" ]]; then
        test_pass "Lenient mode correctly returned default for unregistered variable"
    else
        test_fail "Lenient mode did not handle unregistered variable correctly"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_config_service_performance() {
    test_start "config_service_performance" "Test Unity Config service performance"
    
    setup_config_service_tests
    
    # Initialize service and measure performance
    local start_time=$(date +%s%N)
    unity_config_init >/dev/null 2>&1
    local end_time=$(date +%s%N)
    
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Check if initialization is reasonably fast (under 10 seconds)
    if [[ $duration_ms -lt 10000 ]]; then
        test_pass "Config service initialization performance acceptable: ${duration_ms}ms"
    else
        test_warn "Config service initialization slow: ${duration_ms}ms"
    fi
    
    cleanup_config_service_tests
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

# Register all test functions with the Unity test framework
unity_register_service_test "unity-config-service" "$PROJECT_ROOT/lib/unity/services/unity-config-service.sh" \
    "unity_config_init,unity_config_get,unity_config_set,unity_config_validate,unity_config_reload" \
    "service-unit"

# Run all test functions
main() {
    log_info "Running Unity Config Service Unit Tests"
    
    # Initialization tests
    test_unity_config_service_init
    test_unity_config_schema_initialization
    
    # Configuration loading tests
    test_unity_config_load_env_files
    test_unity_config_load_unity_config
    test_unity_config_load_defaults
    test_unity_config_load_hardcoded_defaults
    
    # Type validation tests
    test_unity_config_validate_boolean
    test_unity_config_validate_integer
    test_unity_config_validate_enum
    
    # Configuration access tests
    test_unity_config_get
    test_unity_config_set
    
    # Validation tests
    test_unity_config_validate
    test_unity_config_validate_cidr
    
    # Caching tests
    test_unity_config_cache
    test_unity_config_clear_cache
    
    # Dynamic reloading tests
    test_unity_config_reload
    test_unity_config_file_watching
    
    # Export/import tests
    test_unity_config_export
    test_unity_config_import
    
    # Reporting tests
    test_unity_config_show
    test_unity_config_show_schema
    
    # Unity service integration tests
    test_unity_config_execute
    test_unity_config_status
    test_unity_config_cleanup
    
    # Error handling tests
    test_config_error_handling
    test_config_lenient_mode
    
    # Performance tests
    test_config_service_performance
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi