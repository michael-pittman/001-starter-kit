#!/usr/bin/env bash
# =============================================================================
# Epic 5 Simple Integration Test Suite
# Focused testing of core consolidated suites
# =============================================================================

set -euo pipefail

# Test configuration
readonly TEST_NAME="Epic 5 Simple Integration Tests"
readonly TEST_VERSION="1.0.0"
readonly TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Initialize test environment
init_test_environment() {
    echo "=== Epic 5 Simple Integration Test Suite ==="
    echo "Version: $TEST_VERSION"
    echo "Timestamp: $TEST_TIMESTAMP"
    echo "============================================"
    
    # Set project root
    export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export LIB_DIR="$PROJECT_ROOT/lib"
    export MODULES_DIR="$PROJECT_ROOT/lib/modules"
    
    echo "Project Root: $PROJECT_ROOT"
    echo "Library Directory: $LIB_DIR"
    echo "Modules Directory: $MODULES_DIR"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    local test_description="${3:-}"
    
    ((TOTAL_TESTS++))
    
    echo -e "\n${BLUE}[TEST $TOTAL_TESTS]${NC} $test_name"
    [[ -n "$test_description" ]] && echo -e "${YELLOW}Description:${NC} $test_description"
    
    if eval "$test_function"; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED_TESTS++))
    fi
}

# Test suite functions

test_library_loader_compatibility() {
    echo "Testing library loader compatibility"
    
    # Test library loader
    source "$LIB_DIR/utils/library-loader.sh" || return 1
    
    # Verify core variables are set
    [[ -n "$PROJECT_ROOT" ]] || return 1
    [[ -n "$LIB_DIR" ]] || return 1
    [[ -n "$MODULES_DIR" ]] || return 1
    
    echo "Library loader compatibility test passed"
    return 0
}

test_error_handling_compatibility() {
    echo "Testing error handling compatibility"
    
    # Test error handling library
    source "$LIB_DIR/error-handling.sh" || return 1
    
    # Test basic error handling functions
    if declare -f log >/dev/null 2>&1; then
        echo "Error handling functions available"
    else
        echo "Error handling functions not found"
        return 1
    fi
    
    echo "Error handling compatibility test passed"
    return 0
}

test_associative_arrays_compatibility() {
    echo "Testing associative arrays compatibility"
    
    # Test associative arrays library
    source "$LIB_DIR/associative-arrays.sh" || return 1
    
    # Test basic associative array functionality
    declare -A test_array
    test_array["key1"]="value1"
    test_array["key2"]="value2"
    
    if [[ "${test_array[key1]}" == "value1" ]]; then
        echo "Associative arrays working correctly"
    else
        echo "Associative arrays not working"
        return 1
    fi
    
    echo "Associative arrays compatibility test passed"
    return 0
}

test_aws_cli_compatibility() {
    echo "Testing AWS CLI compatibility"
    
    # Test AWS CLI library
    source "$LIB_DIR/aws-cli-v2.sh" || return 1
    
    # Test AWS CLI availability
    if command -v aws >/dev/null 2>&1; then
        echo "AWS CLI available"
        
        # Test basic AWS functionality (if credentials available)
        if aws sts get-caller-identity >/dev/null 2>&1; then
            echo "AWS credentials configured"
        else
            echo "AWS credentials not configured (expected in test environment)"
        fi
    else
        echo "AWS CLI not available (expected in test environment)"
    fi
    
    echo "AWS CLI compatibility test passed"
    return 0
}

test_validation_suite_loading() {
    echo "Testing validation suite loading"
    
    # Check if validation suite exists
    if [[ -f "$MODULES_DIR/validation/validation-suite.sh" ]]; then
        echo "Validation suite file exists"
        
        # Test loading validation suite
        source "$MODULES_DIR/validation/validation-suite.sh" || return 1
        
        echo "Validation suite loaded successfully"
    else
        echo "Validation suite not found, checking for alternative locations"
        
        # Check alternative locations
        local found=false
        for location in "$LIB_DIR/validation-suite.sh" "$PROJECT_ROOT/validation-suite.sh"; do
            if [[ -f "$location" ]]; then
                echo "Found validation suite at: $location"
                source "$location" || return 1
                found=true
                break
            fi
        done
        
        if [[ "$found" != "true" ]]; then
            echo "Validation suite not found in any expected location"
            return 1
        fi
    fi
    
    echo "Validation suite loading test passed"
    return 0
}

test_health_suite_loading() {
    echo "Testing health suite loading"
    
    # Check if health suite exists
    if [[ -f "$MODULES_DIR/health/health-suite.sh" ]]; then
        echo "Health suite file exists"
        
        # Test loading health suite
        source "$MODULES_DIR/health/health-suite.sh" || return 1
        
        echo "Health suite loaded successfully"
    else
        echo "Health suite not found, checking for alternative locations"
        
        # Check alternative locations
        local found=false
        for location in "$LIB_DIR/health-suite.sh" "$PROJECT_ROOT/health-suite.sh"; do
            if [[ -f "$location" ]]; then
                echo "Found health suite at: $location"
                source "$location" || return 1
                found=true
                break
            fi
        done
        
        if [[ "$found" != "true" ]]; then
            echo "Health suite not found in any expected location"
            return 1
        fi
    fi
    
    echo "Health suite loading test passed"
    return 0
}

test_setup_suite_loading() {
    echo "Testing setup suite loading"
    
    # Check if setup suite exists
    if [[ -f "$MODULES_DIR/config/setup-suite.sh" ]]; then
        echo "Setup suite file exists"
        
        # Test loading setup suite
        source "$MODULES_DIR/config/setup-suite.sh" || return 1
        
        echo "Setup suite loaded successfully"
    else
        echo "Setup suite not found, checking for alternative locations"
        
        # Check alternative locations
        local found=false
        for location in "$LIB_DIR/setup-suite.sh" "$PROJECT_ROOT/setup-suite.sh"; do
            if [[ -f "$location" ]]; then
                echo "Found setup suite at: $location"
                source "$location" || return 1
                found=true
                break
            fi
        done
        
        if [[ "$found" != "true" ]]; then
            echo "Setup suite not found in any expected location"
            return 1
        fi
    fi
    
    echo "Setup suite loading test passed"
    return 0
}

test_maintenance_suite_loading() {
    echo "Testing maintenance suite loading"
    
    # Check if maintenance suite exists
    if [[ -f "$MODULES_DIR/maintenance/maintenance-suite.sh" ]]; then
        echo "Maintenance suite file exists"
        
        # Test loading maintenance suite
        source "$MODULES_DIR/maintenance/maintenance-suite.sh" || return 1
        
        echo "Maintenance suite loaded successfully"
    else
        echo "Maintenance suite not found, checking for alternative locations"
        
        # Check alternative locations
        local found=false
        for location in "$LIB_DIR/maintenance-suite.sh" "$PROJECT_ROOT/maintenance-suite.sh"; do
            if [[ -f "$location" ]]; then
                echo "Found maintenance suite at: $location"
                source "$location" || return 1
                found=true
                break
            fi
        done
        
        if [[ "$found" != "true" ]]; then
            echo "Maintenance suite not found in any expected location"
            return 1
        fi
    fi
    
    echo "Maintenance suite loading test passed"
    return 0
}

test_bash_version_compatibility() {
    echo "Testing bash version compatibility"
    
    echo "Current bash version: $BASH_VERSION"
    
    # Test basic bash features
    local test_array=("item1" "item2" "item3")
    if [[ "${#test_array[@]}" -eq 3 ]]; then
        echo "Basic array functionality working"
    else
        echo "Basic array functionality not working"
        return 1
    fi
    
    # Test associative arrays if available
    if [[ ${BASH_VERSION%%.*} -ge 4 ]]; then
        echo "Bash 4+ detected, testing associative arrays"
        declare -A test_assoc
        test_assoc["key"]="value"
        if [[ "${test_assoc[key]}" == "value" ]]; then
            echo "Associative arrays working"
        else
            echo "Associative arrays not working"
            return 1
        fi
    else
        echo "Bash 3.x detected, associative arrays not available"
    fi
    
    echo "Bash version compatibility test passed"
    return 0
}

test_platform_compatibility() {
    echo "Testing platform compatibility"
    
    # Detect platform
    local platform=$(uname -s)
    local architecture=$(uname -m)
    
    echo "Platform: $platform"
    echo "Architecture: $architecture"
    
    # Test platform-specific functionality
    case "$platform" in
        Darwin)
            echo "Testing macOS compatibility"
            # Test macOS-specific commands
            if command -v sw_vers >/dev/null 2>&1; then
                echo "macOS version detection working"
            fi
            ;;
        Linux)
            echo "Testing Linux compatibility"
            # Test Linux-specific commands
            if command -v uname >/dev/null 2>&1; then
                echo "Linux system detection working"
            fi
            ;;
        *)
            echo "Testing generic platform compatibility"
            ;;
    esac
    
    echo "Platform compatibility test passed"
    return 0
}

# Generate test report
generate_test_report() {
    echo -e "\n=== Epic 5 Simple Integration Test Report ==="
    echo "Timestamp: $TEST_TIMESTAMP"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed! Epic 5 integration testing successful.${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed. Epic 5 integration testing needs attention.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    init_test_environment
    
    echo -e "\n${BLUE}=== Core Library Tests ===${NC}"
    run_test "Library Loader Compatibility" test_library_loader_compatibility "Test library loader functionality"
    run_test "Error Handling Compatibility" test_error_handling_compatibility "Test error handling library"
    run_test "Associative Arrays Compatibility" test_associative_arrays_compatibility "Test associative arrays library"
    run_test "AWS CLI Compatibility" test_aws_cli_compatibility "Test AWS CLI library"
    
    echo -e "\n${BLUE}=== Suite Loading Tests ===${NC}"
    run_test "Validation Suite Loading" test_validation_suite_loading "Test validation suite loading"
    run_test "Health Suite Loading" test_health_suite_loading "Test health suite loading"
    run_test "Setup Suite Loading" test_setup_suite_loading "Test setup suite loading"
    run_test "Maintenance Suite Loading" test_maintenance_suite_loading "Test maintenance suite loading"
    
    echo -e "\n${BLUE}=== Compatibility Tests ===${NC}"
    run_test "Bash Version Compatibility" test_bash_version_compatibility "Test bash version compatibility"
    run_test "Platform Compatibility" test_platform_compatibility "Test platform compatibility"
    
    # Generate final report
    generate_test_report
}

# Execute main function
main "$@" 