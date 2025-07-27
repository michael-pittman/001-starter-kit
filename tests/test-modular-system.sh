#!/bin/bash
# =============================================================================
# Test Script for Modular Deployment System
# Tests compatibility and integration of new modular architecture
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓ PASS:${NC} $test_name"
    ((TESTS_PASSED++))
}

test_fail() {
    local test_name="$1"
    local reason="${2:-}"
    echo -e "${RED}✗ FAIL:${NC} $test_name"
    [ -n "$reason" ] && echo -e "  ${RED}Reason:${NC} $reason"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$test_name")
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -e "\n${BLUE}[TEST]${NC} $test_name"
    
    # Run test in subshell to isolate environment
    if (
        set -e
        cd "$PROJECT_ROOT"
        $test_function
    ) 2>/dev/null; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Test function returned non-zero status"
    fi
}

# =============================================================================
# MODULE SOURCING TESTS
# =============================================================================

test_module_sourcing() {
    # Test that modules can be sourced without errors
    local modules=(
        "lib/modules/core/errors.sh"
        "lib/modules/core/registry.sh"
        "lib/modules/config/variables.sh"
        "lib/modules/infrastructure/vpc.sh"
        "lib/modules/infrastructure/security.sh"
        "lib/modules/instances/ami.sh"
        "lib/modules/instances/launch.sh"
        "lib/modules/deployment/userdata.sh"
        "lib/modules/monitoring/health.sh"
        "lib/modules/cleanup/resources.sh"
    )
    
    for module in "${modules[@]}"; do
        if [ -f "$PROJECT_ROOT/$module" ]; then
            # Source in subshell to avoid pollution
            if ! (source "$PROJECT_ROOT/$module" 2>/dev/null); then
                echo "Failed to source: $module"
                return 1
            fi
        else
            echo "Module not found: $module"
            return 1
        fi
    done
    
    return 0
}

test_function_availability() {
    # Test that key functions are available after sourcing
    (
        # Source core modules
        source "$PROJECT_ROOT/lib/modules/core/errors.sh"
        source "$PROJECT_ROOT/lib/modules/core/registry.sh"
        source "$PROJECT_ROOT/lib/modules/config/variables.sh"
        
        # Check if functions exist
        type -t setup_error_handling >/dev/null || return 1
        type -t register_resource >/dev/null || return 1
        type -t set_variable >/dev/null || return 1
        
        return 0
    )
}

test_variable_management() {
    # Test variable management system
    (
        source "$PROJECT_ROOT/lib/modules/config/variables.sh"
        
        # Test setting and getting variables
        set_variable "TEST_VAR" "test_value" || return 1
        [ "$(get_variable TEST_VAR)" = "test_value" ] || return 1
        
        # Test validation
        set_variable "AWS_REGION" "us-east-1" || return 1
        ! set_variable "AWS_REGION" "invalid-region" || return 1
        
        return 0
    )
}

test_existing_script_compatibility() {
    # Test that existing scripts can use modular system
    (
        # Simulate script initialization
        export STACK_NAME="test-stack"
        export AWS_REGION="us-east-1"
        export DEPLOYMENT_TYPE="simple"
        
        # Source libraries in order
        source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
        source "$PROJECT_ROOT/lib/error-handling.sh"
        
        # Check that functions still work
        type -t log >/dev/null || return 1
        type -t error >/dev/null || return 1
        type -t check_common_prerequisites >/dev/null || return 1
        
        return 0
    )
}

test_registry_functionality() {
    # Test resource registry
    (
        source "$PROJECT_ROOT/lib/modules/core/registry.sh"
        
        # Initialize registry
        STACK_NAME="test-stack" initialize_registry || return 1
        
        # Register a resource
        register_resource "instances" "i-1234567890abcdef0" '{"type": "g4dn.xlarge"}' || return 1
        
        # Check if resource exists
        resource_exists "instances" "i-1234567890abcdef0" || return 1
        
        # Get resources
        local resources=$(get_resources "instances")
        [[ "$resources" =~ "i-1234567890abcdef0" ]] || return 1
        
        return 0
    )
}

test_error_handling_integration() {
    # Test error handling integration
    (
        source "$PROJECT_ROOT/lib/modules/core/errors.sh"
        
        # Setup error handling
        setup_error_handling || return 1
        
        # Register cleanup handler
        register_cleanup_handler "echo 'Test cleanup'" || return 1
        
        # Test that trap is set
        trap -p ERR | grep -q "error_handler" || return 1
        
        return 0
    )
}

test_deployment_type_defaults() {
    # Test deployment type configuration
    (
        source "$PROJECT_ROOT/lib/modules/config/variables.sh"
        source "$PROJECT_ROOT/lib/aws-config.sh"
        
        # Test simple deployment defaults
        set_default_configuration "simple" || return 1
        [ "$USE_SPOT_INSTANCES" = "false" ] || return 1
        
        # Test spot deployment defaults
        set_default_configuration "spot" || return 1
        [ "$USE_SPOT_INSTANCES" = "true" ] || return 1
        
        return 0
    )
}

test_no_breaking_changes() {
    # Test for breaking changes in existing functionality
    (
        # Source libraries
        source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
        source "$PROJECT_ROOT/lib/spot-instance.sh"
        
        # Test that key functions have same signatures
        # This simulates what existing scripts expect
        
        # Test analyze_spot_pricing
        export AWS_REGION="us-east-1"
        local result
        result=$(analyze_spot_pricing "g4dn.xlarge" 2>&1) || true
        
        # Function should exist and not error on missing AWS
        type -t analyze_spot_pricing >/dev/null || return 1
        
        # Test get_optimal_spot_configuration
        type -t get_optimal_spot_configuration >/dev/null || return 1
        
        return 0
    )
}

test_bash_compatibility() {
    # Test bash 3.x compatibility
    (
        # Check for bash 4.x specific features that should not be used
        local files=(
            "$PROJECT_ROOT/lib/modules/core/registry.sh"
            "$PROJECT_ROOT/lib/modules/config/variables.sh"
            "$PROJECT_ROOT/lib/modules/core/errors.sh"
        )
        
        for file in "${files[@]}"; do
            # Check for associative arrays (bash 4.x)
            if grep -q "declare -A" "$file"; then
                echo "Found bash 4.x associative array in $file"
                return 1
            fi
            
            # Check for nameref (bash 4.3+)
            if grep -q "declare -n" "$file"; then
                echo "Found bash 4.3+ nameref in $file"
                return 1
            fi
        done
        
        return 0
    )
}

test_module_isolation() {
    # Test that modules don't pollute global namespace
    (
        # Get initial variable count
        local vars_before=$(set | wc -l)
        
        # Source a module
        source "$PROJECT_ROOT/lib/modules/core/registry.sh"
        
        # Check that only expected variables were added
        local vars_after=$(set | wc -l)
        local diff=$((vars_after - vars_before))
        
        # Should only add a few variables (registry-related)
        [ $diff -lt 20 ] || return 1
        
        return 0
    )
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

echo "============================================================================="
echo "Modular Deployment System Test Suite"
echo "============================================================================="
echo
echo "Testing modular system compatibility and integration..."

# Run all tests
run_test "Module Sourcing" test_module_sourcing
run_test "Function Availability" test_function_availability
run_test "Variable Management" test_variable_management
run_test "Existing Script Compatibility" test_existing_script_compatibility
run_test "Registry Functionality" test_registry_functionality
run_test "Error Handling Integration" test_error_handling_integration
run_test "Deployment Type Defaults" test_deployment_type_defaults
run_test "No Breaking Changes" test_no_breaking_changes
run_test "Bash Compatibility" test_bash_compatibility
run_test "Module Isolation" test_module_isolation

# =============================================================================
# RESULTS SUMMARY
# =============================================================================

echo
echo "============================================================================="
echo "Test Results Summary"
echo "============================================================================="
echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo
    echo "Failed Tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo
    echo -e "${RED}Some tests failed. The modular system may have compatibility issues.${NC}"
    exit 1
else
    echo
    echo -e "${GREEN}All tests passed! The modular system is compatible.${NC}"
    exit 0
fi