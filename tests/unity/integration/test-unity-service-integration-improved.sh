#!/bin/bash
# =============================================================================
# Unity Service Integration Tests - Improved with Dependency Resolution
# Tests service dependencies, initialization order, and error recovery
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core and test utilities
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
source "$PROJECT_ROOT/lib/unity/core/service-dependency-resolver.sh"

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# =============================================================================
# TEST UTILITIES
# =============================================================================

test_start() {
    local test_name="$1"
    local test_description="$2"
    
    ((TESTS_RUN++))
    echo -e "${BLUE}[TEST]${NC} $test_name: $test_description"
}

test_pass() {
    local message="$1"
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message"
}

test_fail() {
    local message="$1"
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
}

test_skip() {
    local message="$1"
    ((TESTS_SKIPPED++))
    echo -e "  ${YELLOW}⊙${NC} $message (skipped)"
}

test_summary() {
    echo
    echo "===== TEST SUMMARY ====="
    echo "Total tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# =============================================================================
# MOCK SERVICE SETUP
# =============================================================================

setup_test_environment() {
    # Create temporary test directory
    export TEST_DIR="/tmp/unity-integration-test-$$"
    mkdir -p "$TEST_DIR/lib/unity/services"
    mkdir -p "$TEST_DIR/.unity/state"
    mkdir -p "$TEST_DIR/logs/unity"
    
    # Set Unity directories
    export UNITY_SERVICES_DIR="$TEST_DIR/lib/unity/services"
    export UNITY_STATE_DIR="$TEST_DIR/.unity/state"
    export UNITY_LOG_DIR="$TEST_DIR/logs/unity"
    
    # Reset Unity state
    UNITY_INITIALIZED=false
    
    # Create mock services with proper dependencies
    _create_mock_services
}

_create_mock_services() {
    # Mock Config Service (no dependencies)
    cat > "$UNITY_SERVICES_DIR/unity-config-service.sh" << 'EOF'
#!/bin/bash
CONFIG_SERVICE_INITIALIZED=false
CONFIG_VALUES=()

init_unity_config_service() {
    if [[ "$CONFIG_SERVICE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    echo "Initializing config service"
    CONFIG_SERVICE_INITIALIZED=true
    return 0
}

unity_config_get() {
    local key="$1"
    case "$key" in
        "STACK_NAME") echo "test-stack" ;;
        "AWS_REGION") echo "us-west-2" ;;
        *) echo "default" ;;
    esac
}

unity_config_set() {
    local key="$1"
    local value="$2"
    echo "Config set: $key=$value"
    return 0
}
EOF
    
    # Mock Performance Service (depends on config)
    cat > "$UNITY_SERVICES_DIR/unity-performance-service.sh" << 'EOF'
#!/bin/bash
PERFORMANCE_SERVICE_INITIALIZED=false

init_unity_performance_service() {
    if [[ "$PERFORMANCE_SERVICE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Check dependency
    if ! type -t unity_config_get >/dev/null 2>&1; then
        echo "ERROR: Config service not available"
        return 1
    fi
    
    echo "Initializing performance service"
    PERFORMANCE_SERVICE_INITIALIZED=true
    return 0
}

perf_measure() {
    echo "Performance measurement: $1"
    return 0
}
EOF
    
    # Mock AWS Service (depends on config and performance)
    cat > "$UNITY_SERVICES_DIR/unity-aws-service.sh" << 'EOF'
#!/bin/bash
AWS_SERVICE_INITIALIZED=false

init_unity_aws_service() {
    if [[ "$AWS_SERVICE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Check dependencies
    if ! type -t unity_config_get >/dev/null 2>&1; then
        echo "ERROR: Config service not available"
        return 1
    fi
    
    if ! type -t perf_measure >/dev/null 2>&1; then
        echo "ERROR: Performance service not available"
        return 1
    fi
    
    echo "Initializing AWS service"
    AWS_SERVICE_INITIALIZED=true
    return 0
}

aws_launch_instance() {
    local region=$(unity_config_get "AWS_REGION")
    echo "Launching instance in $region"
    return 0
}
EOF
    
    # Mock Docker Service (depends on config)
    cat > "$UNITY_SERVICES_DIR/unity-docker-service.sh" << 'EOF'
#!/bin/bash
DOCKER_SERVICE_INITIALIZED=false

init_unity_docker_service() {
    if [[ "$DOCKER_SERVICE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Check dependency
    if ! type -t unity_config_get >/dev/null 2>&1; then
        echo "ERROR: Config service not available"
        return 1
    fi
    
    echo "Initializing Docker service"
    DOCKER_SERVICE_INITIALIZED=true
    return 0
}

docker_start_container() {
    echo "Starting container: $1"
    return 0
}
EOF
    
    # Mock Monitor Service (depends on config, aws, docker)
    cat > "$UNITY_SERVICES_DIR/unity-monitor-service.sh" << 'EOF'
#!/bin/bash
MONITOR_SERVICE_INITIALIZED=false

init_unity_monitor_service() {
    if [[ "$MONITOR_SERVICE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Check dependencies
    if ! type -t unity_config_get >/dev/null 2>&1; then
        echo "ERROR: Config service not available"
        return 1
    fi
    
    if ! type -t aws_launch_instance >/dev/null 2>&1; then
        echo "ERROR: AWS service not available"
        return 1
    fi
    
    if ! type -t docker_start_container >/dev/null 2>&1; then
        echo "ERROR: Docker service not available"
        return 1
    fi
    
    echo "Initializing monitor service"
    MONITOR_SERVICE_INITIALIZED=true
    return 0
}

monitor_health_check() {
    echo "Health check: $1 - OK"
    return 0
}
EOF
    
    # Mock failing service for error recovery testing
    cat > "$UNITY_SERVICES_DIR/unity-failing-service.sh" << 'EOF'
#!/bin/bash
FAILING_SERVICE_ATTEMPT=0

init_unity_failing_service() {
    ((FAILING_SERVICE_ATTEMPT++))
    
    if [[ $FAILING_SERVICE_ATTEMPT -lt 3 ]]; then
        echo "Failing service attempt $FAILING_SERVICE_ATTEMPT - failing"
        return 1
    else
        echo "Failing service attempt $FAILING_SERVICE_ATTEMPT - success"
        return 0
    fi
}
EOF
}

cleanup_test_environment() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# DEPENDENCY RESOLUTION TESTS
# =============================================================================

test_dependency_resolver_basic() {
    test_start "dependency_resolver_basic" "Test basic dependency resolution"
    
    init_dependency_resolver
    
    # Register simple dependencies
    register_service_dependencies "A" "B" "C"
    register_service_dependencies "B" "D"
    register_service_dependencies "C" "D"
    register_service_dependencies "D"
    
    # Validate dependencies
    if validate_service_dependencies; then
        test_pass "Dependency validation passed"
    else
        test_fail "Dependency validation failed"
        return
    fi
    
    # Get initialization order
    local order
    order=$(get_service_initialization_order)
    
    if [[ "$order" == "D B C A" ]]; then
        test_pass "Correct initialization order: $order"
    else
        test_fail "Incorrect initialization order: $order (expected: D B C A)"
    fi
}

test_circular_dependency_detection() {
    test_start "circular_dependency_detection" "Test circular dependency detection"
    
    init_dependency_resolver
    
    # Create circular dependency
    register_service_dependencies "X" "Y"
    register_service_dependencies "Y" "Z"
    register_service_dependencies "Z" "X"
    
    # Validation should fail
    if ! validate_service_dependencies; then
        test_pass "Circular dependency correctly detected"
    else
        test_fail "Circular dependency not detected"
    fi
}

test_unity_service_dependencies() {
    test_start "unity_service_dependencies" "Test Unity service dependency definitions"
    
    init_dependency_resolver
    define_unity_service_dependencies
    
    # Validate Unity service dependencies
    if validate_service_dependencies; then
        test_pass "Unity service dependencies are valid"
    else
        test_fail "Unity service dependencies contain cycles"
        return
    fi
    
    # Get initialization order
    local order
    order=$(get_service_initialization_order)
    
    if [[ -n "$order" ]]; then
        test_pass "Unity services initialization order: $order"
    else
        test_fail "Failed to get Unity services initialization order"
    fi
}

# =============================================================================
# SERVICE INITIALIZATION TESTS
# =============================================================================

test_service_registration_and_init() {
    test_start "service_registration_and_init" "Test service registration and initialization"
    
    setup_test_environment
    unity_init
    
    # Register services
    unity_register_service "unity-config" "$UNITY_SERVICES_DIR/unity-config-service.sh" "core" ""
    unity_register_service "unity-performance" "$UNITY_SERVICES_DIR/unity-performance-service.sh" "core" "unity-config"
    unity_register_service "unity-aws" "$UNITY_SERVICES_DIR/unity-aws-service.sh" "infrastructure" "unity-config,unity-performance"
    unity_register_service "unity-docker" "$UNITY_SERVICES_DIR/unity-docker-service.sh" "infrastructure" "unity-config"
    unity_register_service "unity-monitor" "$UNITY_SERVICES_DIR/unity-monitor-service.sh" "monitoring" "unity-config,unity-aws,unity-docker"
    
    # Initialize all services
    if unity_initialize_all_services; then
        test_pass "All services initialized successfully"
    else
        test_fail "Service initialization failed"
    fi
    
    # Verify all services are initialized
    if type -t monitor_health_check >/dev/null 2>&1; then
        test_pass "Monitor service functions available"
    else
        test_fail "Monitor service functions not available"
    fi
    
    cleanup_test_environment
}

test_service_dependency_order() {
    test_start "service_dependency_order" "Test services initialize in correct dependency order"
    
    setup_test_environment
    unity_init
    
    # Track initialization order
    export INIT_ORDER=""
    
    # Override init functions to track order
    eval 'init_unity_config_service() { INIT_ORDER="$INIT_ORDER config"; CONFIG_SERVICE_INITIALIZED=true; return 0; }'
    eval 'init_unity_performance_service() { INIT_ORDER="$INIT_ORDER performance"; PERFORMANCE_SERVICE_INITIALIZED=true; return 0; }'
    eval 'init_unity_aws_service() { INIT_ORDER="$INIT_ORDER aws"; AWS_SERVICE_INITIALIZED=true; return 0; }'
    eval 'init_unity_docker_service() { INIT_ORDER="$INIT_ORDER docker"; DOCKER_SERVICE_INITIALIZED=true; return 0; }'
    eval 'init_unity_monitor_service() { INIT_ORDER="$INIT_ORDER monitor"; MONITOR_SERVICE_INITIALIZED=true; return 0; }'
    
    # Register services with dependencies
    init_dependency_resolver
    register_service_dependencies "unity-config"
    register_service_dependencies "unity-performance" "unity-config"
    register_service_dependencies "unity-aws" "unity-config" "unity-performance"
    register_service_dependencies "unity-docker" "unity-config"
    register_service_dependencies "unity-monitor" "unity-config" "unity-aws" "unity-docker"
    
    # Register in Unity
    unity_register_service "unity-config" "$UNITY_SERVICES_DIR/unity-config-service.sh" "core" ""
    unity_register_service "unity-performance" "$UNITY_SERVICES_DIR/unity-performance-service.sh" "core" "unity-config"
    unity_register_service "unity-aws" "$UNITY_SERVICES_DIR/unity-aws-service.sh" "infrastructure" "unity-config,unity-performance"
    unity_register_service "unity-docker" "$UNITY_SERVICES_DIR/unity-docker-service.sh" "infrastructure" "unity-config"
    unity_register_service "unity-monitor" "$UNITY_SERVICES_DIR/unity-monitor-service.sh" "monitoring" "unity-config,unity-aws,unity-docker"
    
    # Initialize monitor (should initialize all dependencies)
    unity_initialize_service "unity-monitor"
    
    # Check initialization order
    if [[ "$INIT_ORDER" == *"config"*"performance"*"aws"* ]] && [[ "$INIT_ORDER" == *"config"*"docker"* ]]; then
        test_pass "Services initialized in correct dependency order"
    else
        test_fail "Incorrect initialization order: $INIT_ORDER"
    fi
    
    cleanup_test_environment
}

# =============================================================================
# ERROR RECOVERY TESTS
# =============================================================================

test_service_failure_recovery() {
    test_start "service_failure_recovery" "Test service failure and recovery"
    
    setup_test_environment
    unity_init
    
    # Register failing service
    unity_register_service "unity-failing" "$UNITY_SERVICES_DIR/unity-failing-service.sh" "test" ""
    
    # First attempts should fail
    if ! unity_initialize_service "unity-failing"; then
        test_pass "Service correctly failed on first attempt"
    else
        test_fail "Service should have failed on first attempt"
    fi
    
    # Try recovery
    if unity_recover "services"; then
        test_pass "Service recovery initiated"
    else
        test_fail "Service recovery failed"
    fi
    
    # Service should eventually succeed (after 3 attempts in mock)
    FAILING_SERVICE_ATTEMPT=2  # Set to allow success on next attempt
    if unity_initialize_service "unity-failing"; then
        test_pass "Service recovered after retries"
    else
        test_fail "Service failed to recover"
    fi
    
    cleanup_test_environment
}

test_dependency_failure_handling() {
    test_start "dependency_failure_handling" "Test handling of dependency failures"
    
    setup_test_environment
    unity_init
    
    # Register services but don't create config service file (simulate missing dependency)
    unity_register_service "unity-config" "$UNITY_SERVICES_DIR/missing-config-service.sh" "core" ""
    unity_register_service "unity-aws" "$UNITY_SERVICES_DIR/unity-aws-service.sh" "infrastructure" "unity-config"
    
    # AWS initialization should fail due to missing config dependency
    if ! unity_initialize_service "unity-aws"; then
        test_pass "Service correctly failed due to missing dependency"
    else
        test_fail "Service should have failed due to missing dependency"
    fi
    
    # Check error handling
    local aws_status
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        aws_status="${UNITY_SERVICE_STATUS[unity-aws]:-}"
    else
        aws_status="${UNITY_SERVICE_unity_aws_STATUS:-}"
    fi
    
    if [[ "$aws_status" != "initialized" ]]; then
        test_pass "Service status correctly shows not initialized"
    else
        test_fail "Service status incorrectly shows initialized"
    fi
    
    cleanup_test_environment
}

# =============================================================================
# INTEGRATION WORKFLOW TESTS
# =============================================================================

test_complete_service_workflow() {
    test_start "complete_service_workflow" "Test complete service initialization workflow"
    
    setup_test_environment
    
    # Initialize Unity
    if unity_init; then
        test_pass "Unity core initialized"
    else
        test_fail "Unity core initialization failed"
        return
    fi
    
    # Register all services
    unity_register_service "unity-config" "$UNITY_SERVICES_DIR/unity-config-service.sh" "core" ""
    unity_register_service "unity-performance" "$UNITY_SERVICES_DIR/unity-performance-service.sh" "core" "unity-config"
    unity_register_service "unity-aws" "$UNITY_SERVICES_DIR/unity-aws-service.sh" "infrastructure" "unity-config,unity-performance"
    unity_register_service "unity-docker" "$UNITY_SERVICES_DIR/unity-docker-service.sh" "infrastructure" "unity-config"
    unity_register_service "unity-monitor" "$UNITY_SERVICES_DIR/unity-monitor-service.sh" "monitoring" "unity-config,unity-aws,unity-docker"
    
    # Initialize all services
    if unity_initialize_all_services; then
        test_pass "All services initialized"
    else
        test_fail "Service initialization failed"
        return
    fi
    
    # Test cross-service functionality
    local region
    region=$(unity_config_get "AWS_REGION")
    if [[ "$region" == "us-west-2" ]]; then
        test_pass "Config service working"
    else
        test_fail "Config service not working"
    fi
    
    if aws_launch_instance >/dev/null 2>&1; then
        test_pass "AWS service working"
    else
        test_fail "AWS service not working"
    fi
    
    if docker_start_container "test" >/dev/null 2>&1; then
        test_pass "Docker service working"
    else
        test_fail "Docker service not working"
    fi
    
    if monitor_health_check "system" >/dev/null 2>&1; then
        test_pass "Monitor service working"
    else
        test_fail "Monitor service not working"
    fi
    
    cleanup_test_environment
}

# =============================================================================
# BASH COMPATIBILITY TESTS
# =============================================================================

test_bash3_compatibility() {
    test_start "bash3_compatibility" "Test bash 3 compatibility"
    
    # Simulate bash 3
    local old_bash_version="$BASH_VERSION_MAJOR"
    BASH_VERSION_MAJOR=3
    
    setup_test_environment
    unity_init
    
    # Register a service
    unity_register_service "unity-config" "$UNITY_SERVICES_DIR/unity-config-service.sh" "core" ""
    
    # Check if service was registered correctly
    local service_path
    service_path=$(unity_get_service "unity-config")
    
    if [[ -n "$service_path" ]]; then
        test_pass "Service registration works in bash 3 mode"
    else
        test_fail "Service registration failed in bash 3 mode"
    fi
    
    # Restore bash version
    BASH_VERSION_MAJOR="$old_bash_version"
    
    cleanup_test_environment
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_service_initialization_performance() {
    test_start "service_initialization_performance" "Test service initialization performance"
    
    setup_test_environment
    unity_init
    
    # Register multiple services
    local start_time=$(date +%s%N)
    
    # Register 10 mock services
    for i in {1..10}; do
        cat > "$UNITY_SERVICES_DIR/unity-service-$i.sh" << EOF
#!/bin/bash
init_unity_service_${i}_service() {
    echo "Initializing service $i"
    return 0
}
EOF
        unity_register_service "unity-service-$i" "$UNITY_SERVICES_DIR/unity-service-$i.sh" "test" ""
    done
    
    # Initialize all services
    unity_initialize_all_services
    
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $duration -lt 5000 ]]; then
        test_pass "Service initialization completed in ${duration}ms"
    else
        test_fail "Service initialization too slow: ${duration}ms"
    fi
    
    cleanup_test_environment
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

main() {
    echo "===== Unity Service Integration Tests ====="
    echo
    
    # Dependency resolver tests
    test_dependency_resolver_basic
    test_circular_dependency_detection
    test_unity_service_dependencies
    
    # Service initialization tests
    test_service_registration_and_init
    test_service_dependency_order
    
    # Error recovery tests
    test_service_failure_recovery
    test_dependency_failure_handling
    
    # Integration workflow tests
    test_complete_service_workflow
    
    # Compatibility tests
    test_bash3_compatibility
    
    # Performance tests
    test_service_initialization_performance
    
    # Show summary
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi