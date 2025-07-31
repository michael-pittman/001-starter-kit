#!/usr/bin/env bash
# =============================================================================
# Unit tests for deployment-variable-management.sh
# Tests init_variable_store and load_environment_config functions
# =============================================================================

set -eo pipefail

# Setup test environment
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Simple assertion function
assert_equals() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$actual" == "$expected" ]]; then
        return 0
    else
        echo "❌ $message: expected '$expected', got '$actual'"
        return 1
    fi
}

# Source the library to test
source "$LIB_DIR/deployment-variable-management.sh" || {
    echo "ERROR: Failed to load deployment-variable-management.sh" >&2
    exit 1
}

# Test init_variable_store function
test_init_variable_store() {
    echo "Testing init_variable_store function..."
    
    # Reset state
    VARIABLE_STORE_INITIALIZED="false"
    
    # Test initialization
    if init_variable_store; then
        assert_equals "$VARIABLE_STORE_INITIALIZED" "true" "Variable store should be initialized"
        echo "✅ init_variable_store: Basic initialization passed"
    else
        echo "❌ init_variable_store: Basic initialization failed"
        return 1
    fi
    
    # Test double initialization prevention
    local output
    output=$(init_variable_store 2>&1)
    if [[ "$output" == *"already initialized"* ]] || [[ -z "$output" ]]; then
        echo "✅ init_variable_store: Double initialization prevention passed"
    else
        echo "❌ init_variable_store: Double initialization prevention failed"
        return 1
    fi
    
    # Test that standard variables are registered
    if declare -f is_variable_registered >/dev/null 2>&1; then
        if is_variable_registered "STACK_NAME"; then
            echo "✅ init_variable_store: Standard variables registered"
        else
            echo "❌ init_variable_store: Standard variables not registered"
            return 1
        fi
    fi
    
    return 0
}

# Test load_environment_config function
test_load_environment_config() {
    echo "Testing load_environment_config function..."
    
    # Reset state
    ENVIRONMENT_CONFIG_LOADED="false"
    
    # Create test env file
    local test_env_file=".env.test"
    cat > "$test_env_file" << EOF
TEST_VAR="test_value"
STACK_NAME="test-stack"
AWS_REGION="us-west-2"
EOF
    
    # Test loading development environment (default)
    if load_environment_config; then
        assert_equals "$ENVIRONMENT_CONFIG_LOADED" "true" "Environment config should be loaded"
        echo "✅ load_environment_config: Basic loading passed"
    else
        echo "❌ load_environment_config: Basic loading failed"
        rm -f "$test_env_file"
        return 1
    fi
    
    # Test loading specific environment
    ENVIRONMENT_CONFIG_LOADED="false"
    if load_environment_config "test"; then
        echo "✅ load_environment_config: Specific environment loading passed"
    else
        echo "❌ load_environment_config: Specific environment loading failed"
        rm -f "$test_env_file"
        return 1
    fi
    
    # Clean up
    rm -f "$test_env_file"
    
    return 0
}

# Test init_deployment_variables convenience function
test_init_deployment_variables() {
    echo "Testing init_deployment_variables function..."
    
    # Reset state
    VARIABLE_STORE_INITIALIZED="false"
    ENVIRONMENT_CONFIG_LOADED="false"
    
    # Test combined initialization
    if init_deployment_variables "production"; then
        assert_equals "$VARIABLE_STORE_INITIALIZED" "true" "Variable store should be initialized"
        assert_equals "$ENVIRONMENT_CONFIG_LOADED" "true" "Environment config should be loaded"
        echo "✅ init_deployment_variables: Combined initialization passed"
    else
        echo "❌ init_deployment_variables: Combined initialization failed"
        return 1
    fi
    
    return 0
}

# Test integration with existing scripts
test_integration_compatibility() {
    echo "Testing integration compatibility..."
    
    # Test that functions are exported
    if declare -f init_variable_store >/dev/null 2>&1; then
        echo "✅ integration: init_variable_store is available"
    else
        echo "❌ integration: init_variable_store is not available"
        return 1
    fi
    
    if declare -f load_environment_config >/dev/null 2>&1; then
        echo "✅ integration: load_environment_config is available"
    else
        echo "❌ integration: load_environment_config is not available"  
        return 1
    fi
    
    return 0
}

# Run all tests
run_tests() {
    local failed=0
    
    echo "=== Running Deployment Variable Management Tests ==="
    echo
    
    test_init_variable_store || ((failed++))
    echo
    
    test_load_environment_config || ((failed++))
    echo
    
    test_init_deployment_variables || ((failed++))
    echo
    
    test_integration_compatibility || ((failed++))
    echo
    
    echo "=== Test Summary ==="
    if [[ $failed -eq 0 ]]; then
        echo "✅ All tests passed!"
        return 0
    else
        echo "❌ $failed test(s) failed"
        return 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi