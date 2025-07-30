#!/usr/bin/env bash
# =============================================================================
# Test Dependency Optimization
# Verifies the dependency group system works correctly
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$PROJECT_ROOT/lib/modules"

# Source test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# Test suite setup
describe "Dependency Optimization Tests"

# =============================================================================
# TEST: Dependency Groups Module
# =============================================================================

test_dependency_groups_module() {
    describe "Dependency Groups Module"
    
    # Source the module
    source "$MODULES_DIR/core/dependency-groups.sh"
    
    # Test: Module is loaded
    assert_true "[[ -n \"\${_CORE_DEPENDENCY_GROUPS_SH_LOADED:-}\" ]]" \
        "Dependency groups module should be loaded"
    
    # Test: List dependency groups
    local groups
    groups=$(list_dependency_groups)
    assert_contains "$groups" "base" "Should list base dependency group"
    assert_contains "$groups" "core" "Should list core dependency group"
    assert_contains "$groups" "infrastructure" "Should list infrastructure dependency group"
    assert_contains "$groups" "application" "Should list application dependency group"
    
    # Test: Get dependency group
    local base_deps
    base_deps=$(get_dependency_group "BASE")
    assert_contains "$base_deps" "core/errors.sh" "Base group should include errors.sh"
    assert_contains "$base_deps" "core/registry.sh" "Base group should include registry.sh"
    
    # Test: Check module loaded function
    assert_false "is_module_loaded 'core/test-nonexistent.sh'" \
        "Non-existent module should not be loaded"
}

# =============================================================================
# TEST: Infrastructure Base Module
# =============================================================================

test_infrastructure_base_module() {
    describe "Infrastructure Base Module"
    
    # Reset loaded state
    unset _INFRASTRUCTURE_BASE_SH_LOADED
    unset _CORE_ERRORS_SH_LOADED
    unset _CORE_REGISTRY_SH_LOADED
    unset _CORE_VARIABLES_SH_LOADED
    
    # Source the module
    source "$MODULES_DIR/infrastructure/base.sh"
    
    # Test: Module is loaded
    assert_true "[[ -n \"\${_INFRASTRUCTURE_BASE_SH_LOADED:-}\" ]]" \
        "Infrastructure base module should be loaded"
    
    # Test: Dependencies are loaded
    assert_true "[[ -n \"\${_CORE_ERRORS_SH_LOADED:-}\" ]]" \
        "Core errors module should be loaded as dependency"
    assert_true "[[ -n \"\${_CORE_REGISTRY_SH_LOADED:-}\" ]]" \
        "Core registry module should be loaded as dependency"
    assert_true "[[ -n \"\${_CORE_VARIABLES_SH_LOADED:-}\" ]]" \
        "Core variables module should be loaded as dependency"
    
    # Test: Infrastructure constants
    assert_equals "$INFRA_TAG_PROJECT" "GeuseMaker" \
        "Infrastructure project tag should be set"
    assert_equals "$INFRA_MAX_RETRIES" "3" \
        "Infrastructure max retries should be set"
    
    # Test: Infrastructure functions
    assert_function_exists "generate_infra_tags" \
        "generate_infra_tags function should exist"
    assert_function_exists "wait_for_resource_state" \
        "wait_for_resource_state function should exist"
    assert_function_exists "retry_infra_operation" \
        "retry_infra_operation function should exist"
}

# =============================================================================
# TEST: Application Base Module
# =============================================================================

test_application_base_module() {
    describe "Application Base Module"
    
    # Reset loaded state
    unset _APPLICATION_BASE_SH_LOADED
    unset _CORE_ERRORS_SH_LOADED
    unset _CORE_REGISTRY_SH_LOADED
    unset _CORE_VARIABLES_SH_LOADED
    
    # Source the module
    source "$MODULES_DIR/application/base.sh"
    
    # Test: Module is loaded
    assert_true "[[ -n \"\${_APPLICATION_BASE_SH_LOADED:-}\" ]]" \
        "Application base module should be loaded"
    
    # Test: Dependencies are loaded
    assert_true "[[ -n \"\${_CORE_ERRORS_SH_LOADED:-}\" ]]" \
        "Core errors module should be loaded as dependency"
    assert_true "[[ -n \"\${_CORE_REGISTRY_SH_LOADED:-}\" ]]" \
        "Core registry module should be loaded as dependency"
    assert_true "[[ -n \"\${_CORE_VARIABLES_SH_LOADED:-}\" ]]" \
        "Core variables module should be loaded as dependency"
    
    # Test: Application constants
    assert_equals "$APP_PORT_N8N" "5678" \
        "N8N port should be set correctly"
    assert_equals "$APP_PORT_OLLAMA" "11434" \
        "Ollama port should be set correctly"
    assert_equals "$APP_DOCKER_NETWORK" "ai-stack" \
        "Docker network should be set correctly"
    
    # Test: Application functions
    assert_function_exists "check_service_health" \
        "check_service_health function should exist"
    assert_function_exists "wait_for_service" \
        "wait_for_service function should exist"
    assert_function_exists "validate_app_config" \
        "validate_app_config function should exist"
}

# =============================================================================
# TEST: Dependency Loading Performance
# =============================================================================

test_dependency_loading_performance() {
    describe "Dependency Loading Performance"
    
    # Test: Multiple loads of same dependency group
    local start_time end_time elapsed
    
    # First load (cold)
    unset _CORE_ERRORS_SH_LOADED
    unset _CORE_REGISTRY_SH_LOADED
    start_time=$(date +%s%N)
    source "$MODULES_DIR/core/dependency-groups.sh"
    load_dependency_group "BASE" "$MODULES_DIR"
    end_time=$(date +%s%N)
    local first_load_time=$(( (end_time - start_time) / 1000000 ))
    
    # Second load (warm - should be faster due to loaded checks)
    start_time=$(date +%s%N)
    load_dependency_group "BASE" "$MODULES_DIR"
    end_time=$(date +%s%N)
    local second_load_time=$(( (end_time - start_time) / 1000000 ))
    
    # Second load should be significantly faster
    assert_true "[[ $second_load_time -lt $((first_load_time / 2)) ]]" \
        "Second load should be faster than half of first load time"
    
    echo "  First load time: ${first_load_time}ms"
    echo "  Second load time: ${second_load_time}ms"
}

# =============================================================================
# TEST: Circular Dependency Detection
# =============================================================================

test_circular_dependency_detection() {
    describe "Circular Dependency Detection"
    
    source "$MODULES_DIR/core/dependency-groups.sh"
    
    # Test: Module dependency resolution
    local deps
    deps=$(get_module_dependencies "infrastructure/vpc.sh" deps 2>&1) || true
    assert_not_contains "$deps" "infrastructure/vpc.sh" \
        "Module should not depend on itself"
    
    # Test: Dependency resolution with no circular deps
    local resolved
    resolved=$(resolve_module_dependencies "infrastructure/vpc.sh" 2>&1)
    local exit_code=$?
    assert_equals "$exit_code" "0" \
        "Dependency resolution should succeed for valid module"
}

# =============================================================================
# TEST: Module Updates
# =============================================================================

test_updated_modules() {
    describe "Updated Modules"
    
    # Test: VPC module uses dependency groups
    local vpc_content
    vpc_content=$(grep -A5 "load_dependency_group" "$MODULES_DIR/infrastructure/vpc.sh" 2>/dev/null || true)
    assert_not_empty "$vpc_content" \
        "VPC module should use dependency groups"
    
    # Test: Security module uses dependency groups
    local security_content
    security_content=$(grep -A5 "load_dependency_group" "$MODULES_DIR/infrastructure/security.sh" 2>/dev/null || true)
    assert_not_empty "$security_content" \
        "Security module should use dependency groups"
    
    # Test: Docker manager uses dependency groups
    local docker_content
    docker_content=$(grep -A5 "load_dependency_group" "$MODULES_DIR/application/docker_manager.sh" 2>/dev/null || true)
    assert_not_empty "$docker_content" \
        "Docker manager module should use dependency groups"
}

# =============================================================================
# TEST: Legacy Compatibility
# =============================================================================

test_legacy_compatibility() {
    describe "Legacy Compatibility"
    
    # Reset loaded state
    unset DEPENDENCY_GROUPS_LOADED
    unset _CORE_DEPENDENCY_GROUPS_SH_LOADED
    
    source "$MODULES_DIR/core/dependency-groups.sh"
    
    # Test: Legacy functions still work
    assert_function_exists "source_error_handling" \
        "Legacy source_error_handling should exist"
    assert_function_exists "source_resource_management" \
        "Legacy source_resource_management should exist"
    assert_function_exists "source_application_stack" \
        "Legacy source_application_stack should exist"
    
    # Test: Legacy compatibility export
    assert_equals "$DEPENDENCY_GROUPS_LOADED" "1" \
        "Legacy DEPENDENCY_GROUPS_LOADED should be set"
    
    # Test: Legacy functions actually load dependencies
    unset _CORE_ERRORS_SH_LOADED
    source_error_handling
    assert_true "[[ -n \"\${_CORE_ERRORS_SH_LOADED:-}\" ]]" \
        "Legacy function should load errors module"
}

# =============================================================================
# RUN TESTS
# =============================================================================

# Clear any previous state
unset _CORE_DEPENDENCY_GROUPS_SH_LOADED
unset _INFRASTRUCTURE_BASE_SH_LOADED
unset _APPLICATION_BASE_SH_LOADED

echo "Starting Dependency Optimization Tests..."
echo "========================================"

test_dependency_groups_module
test_infrastructure_base_module
test_application_base_module
test_dependency_loading_performance
test_circular_dependency_detection
test_updated_modules
test_legacy_compatibility

# Print summary
print_test_summary

# Exit with appropriate code
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo "All dependency optimization tests passed!"
    exit 0
else
    echo "Some tests failed. Please review the output above."
    exit 1
fi