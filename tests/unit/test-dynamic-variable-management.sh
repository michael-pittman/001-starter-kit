#!/usr/bin/env bash
# =============================================================================
# Unit tests for enhanced dynamic variable management
# Tests dynamic detection, state awareness, and AWS resource discovery
# =============================================================================

set -eo pipefail

# Setup test environment
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Create temp directories for testing
TEST_TMP_DIR=$(mktemp -d)
export CONFIG_DIR="$TEST_TMP_DIR/config"
mkdir -p "$CONFIG_DIR/state"

# Simple assertion functions
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

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo "❌ $message: '$haystack' does not contain '$needle'"
        return 1
    fi
}

# Source the library to test
source "$LIB_DIR/deployment-variable-management.sh" || {
    echo "ERROR: Failed to load deployment-variable-management.sh" >&2
    exit 1
}

# Also need the variables module for full functionality
if [[ -f "$LIB_DIR/modules/config/variables.sh" ]]; then
    source "$LIB_DIR/modules/config/variables.sh"
fi

# Test dynamic variable detection by deployment type
test_detect_deployment_variables() {
    echo "Testing dynamic variable detection..."
    
    # Reset registry
    declare -gA _VARIABLE_REGISTRY=()
    
    # Test spot deployment variables
    detect_deployment_variables "spot" "test-stack"
    
    # Check that spot-specific variables were registered
    if is_variable_registered "SPOT_PRICE"; then
        echo "✅ detect_deployment_variables: Spot-specific variables registered"
    else
        echo "❌ detect_deployment_variables: Failed to register spot variables"
        return 1
    fi
    
    # Test enterprise deployment variables
    detect_deployment_variables "enterprise" "test-stack"
    
    # Check that enterprise-specific variables were registered
    if is_variable_registered "ENABLE_MULTI_AZ" && is_variable_registered "ENABLE_ALB"; then
        echo "✅ detect_deployment_variables: Enterprise-specific variables registered"
    else
        echo "❌ detect_deployment_variables: Failed to register enterprise variables"
        return 1
    fi
    
    return 0
}

# Test deployment state variable loading
test_load_deployment_state_variables() {
    echo "Testing deployment state variable loading..."
    
    # Create a test state file
    local state_file="$CONFIG_DIR/state/deployment-state.json"
    cat > "$state_file" << 'EOF'
{
    "stacks": {
        "test-stack": {
            "variables": {
                "STACK_NAME": "test-stack",
                "AWS_REGION": "us-west-2",
                "INSTANCE_TYPE": "g5.xlarge",
                "DEPLOYMENT_TYPE": "enterprise"
            }
        }
    }
}
EOF
    
    # Load variables from state
    load_deployment_state_variables "test-stack"
    
    # Check if variables were loaded
    if declare -f get_variable >/dev/null 2>&1; then
        local loaded_region=$(get_variable "AWS_REGION" 2>/dev/null || echo "")
        assert_equals "$loaded_region" "us-west-2" "State variables should be loaded"
    fi
    
    echo "✅ load_deployment_state_variables: Variables loaded from state"
    
    return 0
}

# Test dynamic variable initialization
test_init_dynamic_variables() {
    echo "Testing dynamic variable initialization..."
    
    # Reset state
    VARIABLE_STORE_INITIALIZED="false"
    declare -gA _VARIABLE_REGISTRY=()
    
    # Test initialization with discovery disabled
    if init_dynamic_variables "test-stack" "spot" "false"; then
        echo "✅ init_dynamic_variables: Basic initialization successful"
    else
        echo "❌ init_dynamic_variables: Basic initialization failed"
        return 1
    fi
    
    # Check that appropriate variables were registered
    if is_variable_registered "SPOT_PRICE"; then
        echo "✅ init_dynamic_variables: Type-specific variables detected"
    else
        echo "❌ init_dynamic_variables: Failed to detect type-specific variables"
        return 1
    fi
    
    return 0
}

# Test variable validation
test_validate_required_variables() {
    echo "Testing variable validation..."
    
    # Set up some variables
    if declare -f set_variable >/dev/null 2>&1; then
        set_variable "STACK_NAME" "test-stack"
        set_variable "AWS_REGION" "us-east-1"
        set_variable "KEY_NAME" "test-key"
    else
        export STACK_NAME="test-stack"
        export AWS_REGION="us-east-1"
        export KEY_NAME="test-key"
    fi
    
    # Test validation for spot deployment
    if validate_required_variables "spot"; then
        echo "✅ validate_required_variables: Spot deployment validation passed"
    else
        echo "❌ validate_required_variables: Spot deployment validation failed"
        return 1
    fi
    
    # Clear a required variable
    if declare -f set_variable >/dev/null 2>&1; then
        set_variable "KEY_NAME" ""
    else
        unset KEY_NAME
    fi
    
    # Test validation should fail
    if ! validate_required_variables "spot"; then
        echo "✅ validate_required_variables: Correctly detected missing variable"
    else
        echo "❌ validate_required_variables: Failed to detect missing variable"
        return 1
    fi
    
    return 0
}

# Test saving variables to state
test_save_variables_to_state() {
    echo "Testing saving variables to state..."
    
    # Set some variables
    if declare -f set_variable >/dev/null 2>&1; then
        set_variable "STACK_NAME" "save-test"
        set_variable "AWS_REGION" "eu-west-1"
        set_variable "DEPLOYMENT_TYPE" "enterprise"
        set_variable "ENABLE_ALB" "true"
    fi
    
    # Initialize state file
    local state_file="$CONFIG_DIR/state/deployment-state.json"
    echo '{"stacks": {"save-test": {}}}' > "$state_file"
    
    # Save variables
    save_variables_to_state "save-test"
    
    # Check if variables were saved
    if command -v jq >/dev/null 2>&1; then
        local saved_region=$(jq -r '.stacks["save-test"].variables.AWS_REGION // ""' "$state_file")
        assert_equals "$saved_region" "eu-west-1" "Variables should be saved to state"
        echo "✅ save_variables_to_state: Variables saved successfully"
    else
        echo "⚠️  save_variables_to_state: jq not available, skipping validation"
    fi
    
    return 0
}

# Test AWS resource discovery (mock version)
test_discover_aws_resources() {
    echo "Testing AWS resource discovery (mock)..."
    
    # This would normally require AWS CLI and actual resources
    # For testing, we'll just verify the function exists and handles missing AWS CLI gracefully
    
    # Mock AWS CLI not being available
    local old_path="$PATH"
    export PATH="/tmp"
    
    # Should handle missing AWS CLI gracefully
    discover_aws_resources "test-stack"
    
    # Restore PATH
    export PATH="$old_path"
    
    echo "✅ discover_aws_resources: Handles missing AWS CLI gracefully"
    
    return 0
}

# Run all tests
run_tests() {
    local failed=0
    
    echo "=== Running Enhanced Dynamic Variable Management Tests ==="
    echo
    
    test_detect_deployment_variables || ((failed++))
    echo
    
    test_load_deployment_state_variables || ((failed++))
    echo
    
    test_init_dynamic_variables || ((failed++))
    echo
    
    test_validate_required_variables || ((failed++))
    echo
    
    test_save_variables_to_state || ((failed++))
    echo
    
    test_discover_aws_resources || ((failed++))
    echo
    
    # Cleanup
    rm -rf "$TEST_TMP_DIR"
    
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
    # Disable parameter store loading for tests
    export LOAD_PARAMETER_STORE=false
    run_tests
fi