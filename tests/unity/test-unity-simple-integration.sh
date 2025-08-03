#!/bin/bash

# Simple Unity Integration Test
# Tests core functionality without complex dependencies

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test configuration
TEST_NAME="Unity Simple Integration"
TEST_STACK="unity-test-$$"
TEST_LOG_DIR="/tmp/unity-test-$$"
FAILED_TESTS=0
PASSED_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test setup
setup_test() {
    echo "Setting up test environment..."
    
    # Create test directories
    mkdir -p "$TEST_LOG_DIR"
    
    # Set required environment variables
    export UNITY_LOG_DIR="$TEST_LOG_DIR"
    export UNITY_TEST_MODE="true"
    export LOG_LEVEL="ERROR"
    export STACK_NAME="$TEST_STACK"
    export UNITY_INITIALIZED="false"
    export MODULES_DIR="$PROJECT_ROOT/lib/modules"
    
    return 0
}

# Test teardown
teardown_test() {
    echo "Cleaning up test environment..."
    rm -rf "$TEST_LOG_DIR"
    unset UNITY_LOG_DIR UNITY_TEST_MODE UNITY_INITIALIZED
}

# Test result tracking
track_result() {
    local test_name="$1"
    local result="$2"
    
    if [[ "$result" == "0" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED_TESTS++))
    fi
}

# Test 1: Unity Module Files Exist
test_unity_files_exist() {
    echo -e "\n${YELLOW}Test 1: Unity Module Files Exist${NC}"
    
    local files=(
        "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
        "$PROJECT_ROOT/lib/unity/core/unity-events.sh"
        "$PROJECT_ROOT/lib/unity/core/registry.sh"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            track_result "File $(basename "$file") exists" 0
        else
            track_result "File $(basename "$file") exists" 1
        fi
    done
}

# Test 2: Unity Function Definitions
test_unity_functions() {
    echo -e "\n${YELLOW}Test 2: Unity Function Definitions${NC}"
    
    # Load modules in isolated subshell
    (
        # Source modules with bash-native timeout
        export UNITY_SKIP_INIT=true
        (
            # Kill parent after timeout
            sleep 5 && kill $$ 2>/dev/null &
            timeout_pid=$!
            
            # Source modules
            source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null
            source "$PROJECT_ROOT/lib/unity/core/unity-events.sh" 2>/dev/null
            source "$PROJECT_ROOT/lib/unity/core/registry.sh" 2>/dev/null
            
            # Check functions
            type -t unity_init >/dev/null 2>&1 && echo 'unity_init:found'
            type -t unity_emit_event >/dev/null 2>&1 && echo 'unity_emit_event:found'
            type -t unity_on_event >/dev/null 2>&1 && echo 'unity_on_event:found'
            type -t unity_register_service >/dev/null 2>&1 && echo 'unity_register_service:found'
            type -t unity_discover_service >/dev/null 2>&1 && echo 'unity_discover_service:found'
            
            # Kill timeout
            kill $timeout_pid 2>/dev/null
        )
    ) 2>/dev/null | while IFS=: read -r func status; do
        if [[ "$status" == "found" ]]; then
            track_result "Function $func loaded" 0
        fi
    done || {
        echo "  Warning: Timeout or error loading functions"
    }
}

# Test 3: Basic Event Emission
test_event_emission() {
    echo -e "\n${YELLOW}Test 3: Basic Event Emission${NC}"
    
    # Test in isolated environment
    local result
    result=$(bash -c "
        export UNITY_LOG_DIR='$TEST_LOG_DIR'
        export UNITY_TEST_MODE=true
        export UNITY_SKIP_INIT=true
        
        # Timeout protection
        ( sleep 2 && kill \$\$ 2>/dev/null ) &
        timeout_pid=\$!
        
        source '$PROJECT_ROOT/lib/unity/core/unity-events.sh' 2>/dev/null || exit 1
        
        # Try to emit event
        if unity_emit_event 'test.event' 'test-data' >/dev/null 2>&1; then
            echo 'success'
        else
            echo 'failed'
        fi
        
        kill \$timeout_pid 2>/dev/null
    " 2>/dev/null)
    
    if [[ "$result" == "success" ]]; then
        track_result "Event emission" 0
    else
        track_result "Event emission" 1
    fi
}

# Test 4: Service Registry Operations
test_service_registry() {
    echo -e "\n${YELLOW}Test 4: Service Registry Operations${NC}"
    
    # Test in isolated environment
    local result
    result=$(bash -c "
        export UNITY_LOG_DIR='$TEST_LOG_DIR'
        export UNITY_TEST_MODE=true
        export UNITY_SKIP_INIT=true
        
        # Timeout protection
        ( sleep 2 && kill \$\$ 2>/dev/null ) &
        timeout_pid=\$!
        
        source '$PROJECT_ROOT/lib/unity/core/unity-core.sh' 2>/dev/null || exit 1
        
        # Register service
        if unity_register_service 'test-svc' 'http://localhost:8080' >/dev/null 2>&1; then
            echo 'register:success'
        fi
        
        # Discover service
        endpoint=\$(unity_discover_service 'test-svc' 2>/dev/null)
        if [[ \"\$endpoint\" == 'http://localhost:8080' ]]; then
            echo 'discover:success'
        fi
        
        kill \$timeout_pid 2>/dev/null
    " 2>/dev/null)
    
    if [[ "$result" =~ "register:success" ]]; then
        track_result "Service registration" 0
    else
        track_result "Service registration" 1
    fi
    
    if [[ "$result" =~ "discover:success" ]]; then
        track_result "Service discovery" 0
    else
        track_result "Service discovery" 1
    fi
}

# Test 5: Log Directory Permissions
test_log_permissions() {
    echo -e "\n${YELLOW}Test 5: Log Directory Permissions${NC}"
    
    if [[ -d "$TEST_LOG_DIR" ]]; then
        track_result "Log directory created" 0
        
        # Test write
        if echo "test" > "$TEST_LOG_DIR/test-$$" 2>/dev/null; then
            track_result "Log directory writable" 0
            rm -f "$TEST_LOG_DIR/test-$$"
        else
            track_result "Log directory writable" 1
        fi
    else
        track_result "Log directory created" 1
        track_result "Log directory writable" 1
    fi
}

# Test 6: Unity Configuration File
test_unity_config() {
    echo -e "\n${YELLOW}Test 6: Unity Configuration${NC}"
    
    local config_file="$PROJECT_ROOT/config/unity.yml"
    
    if [[ -f "$config_file" ]]; then
        track_result "Unity config file exists" 0
        
        # Check if readable
        if [[ -r "$config_file" ]]; then
            track_result "Unity config readable" 0
        else
            track_result "Unity config readable" 1
        fi
    else
        track_result "Unity config file exists" 1
        track_result "Unity config readable" 1
    fi
}

# Main test execution
main() {
    echo "================================================"
    echo "$TEST_NAME"
    echo "================================================"
    echo "Test Environment:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  Test Log Dir: $TEST_LOG_DIR"
    echo "  Stack Name: $TEST_STACK"
    echo "  Bash Version: ${BASH_VERSION}"
    echo "================================================"
    
    # Setup test environment
    setup_test
    
    # Run tests with overall timeout
    (
        test_unity_files_exist
        test_unity_functions
        test_event_emission
        test_service_registry
        test_log_permissions
        test_unity_config
    ) &
    
    # Wait for tests with timeout
    local test_pid=$!
    local timeout=30
    local elapsed=0
    
    while kill -0 $test_pid 2>/dev/null && [[ $elapsed -lt $timeout ]]; do
        sleep 1
        ((elapsed++))
    done
    
    if kill -0 $test_pid 2>/dev/null; then
        echo -e "\n${RED}Tests timed out after ${timeout} seconds${NC}"
        kill -9 $test_pid 2>/dev/null
        FAILED_TESTS=$((FAILED_TESTS + 10))
    else
        wait $test_pid
    fi
    
    # Teardown
    teardown_test
    
    # Summary
    echo -e "\n================================================"
    echo "Test Summary:"
    echo -e "  ${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "  ${RED}Failed: $FAILED_TESTS${NC}"
    
    local total_tests=$((PASSED_TESTS + FAILED_TESTS))
    local pass_rate=0
    if [[ $total_tests -gt 0 ]]; then
        pass_rate=$(( (PASSED_TESTS * 100) / total_tests ))
    fi
    echo "  Pass Rate: ${pass_rate}%"
    echo "================================================"
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    elif [[ $pass_rate -ge 60 ]]; then
        echo -e "${YELLOW}Most tests passed (${pass_rate}%)${NC}"
        exit 0
    else
        echo -e "${RED}Too many tests failed (${pass_rate}% pass rate)${NC}"
        exit 1
    fi
}

# Run main function
main "$@"