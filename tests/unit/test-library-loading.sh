#!/usr/bin/env bash
# =============================================================================
# Test Script: Library Loading Standard Validation
# Tests the library loading standard implementation across various scenarios
# =============================================================================

set -uo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Load required modules through the library system
load_module "core/variables"
load_module "core/logging"
safe_source "aws-deployment-common.sh" true "AWS deployment common"

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    # Ensure we're in project root but don't set -e which might cause early exit
    if (cd "$PROJECT_ROOT" && $test_function); then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Test function returned non-zero status"
    fi
}

print_header() {
    echo -e "\n${CYAN}=== Library Loading Standard Tests ===${NC}"
    echo -e "${CYAN}Testing library loading patterns and error handling${NC}\n"
}

print_summary() {
    echo -e "\n${CYAN}=== Test Summary ===${NC}"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo -e "\n${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}- $test${NC}"
        done
    fi
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        return 1
    fi
}

# =============================================================================
# TEST SETUP
# =============================================================================

# Create temporary test environment
TEST_TMP_DIR="/tmp/library-loading-test-$$"
TEST_SCRIPT_DIR="$TEST_TMP_DIR/scripts"
TEST_LIB_DIR="$TEST_TMP_DIR/lib"
TEST_SUBDIR="$TEST_TMP_DIR/scripts/subdir"

setup_test_environment() {
    # Create directory structure
    mkdir -p "$TEST_SCRIPT_DIR"
    mkdir -p "$TEST_LIB_DIR"
    mkdir -p "$TEST_SUBDIR"
    mkdir -p "$TEST_TMP_DIR/lib/modules/core"
    
    # Create marker file for project root detection
    echo "Test CLAUDE.md" > "$TEST_TMP_DIR/CLAUDE.md"
    
    # Create test libraries
    cat > "$TEST_LIB_DIR/test-core.sh" << 'EOF'
[[ -n "${TEST_CORE_LOADED:-}" ]] && return 0
declare -r TEST_CORE_LOADED=1
declare -r TEST_CORE_VERSION="1.0.0"
test_core_function() { echo "test-core-function"; }
EOF

    cat > "$TEST_LIB_DIR/test-dependent.sh" << 'EOF'
[[ -n "${TEST_DEPENDENT_LOADED:-}" ]] && return 0
if [[ -z "${TEST_CORE_LOADED:-}" ]]; then
    echo "Error: test-core.sh must be loaded first" >&2
    return 1
fi
declare -r TEST_DEPENDENT_LOADED=1
test_dependent_function() { echo "test-dependent-function"; }
EOF

    cat > "$TEST_LIB_DIR/test-optional.sh" << 'EOF'
[[ -n "${TEST_OPTIONAL_LOADED:-}" ]] && return 0
declare -r TEST_OPTIONAL_LOADED=1
test_optional_function() { echo "test-optional-function"; }
EOF


    cat > "$TEST_TMP_DIR/lib/modules/core/test-module.sh" << 'EOF'
[[ -n "${TEST_MODULE_LOADED:-}" ]] && return 0
declare -r TEST_MODULE_LOADED=1
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    echo "Error: PROJECT_ROOT not defined" >&2
    return 1
fi
test_module_function() { echo "test-module-function"; }
EOF

    chmod +x "$TEST_LIB_DIR"/*.sh
    chmod +x "$TEST_TMP_DIR/lib/modules/core"/*.sh
}

cleanup_test_environment() {
    rm -rf "$TEST_TMP_DIR"
}

# =============================================================================
# PATH RESOLUTION TESTS
# =============================================================================

test_standard_path_resolution() {
    cat > "$TEST_SCRIPT_DIR/test-script.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "PROJECT_ROOT=$PROJECT_ROOT"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-script.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-script.sh")
    
    if [[ "$output" == *"SCRIPT_DIR=$TEST_SCRIPT_DIR"* ]] && 
       [[ "$output" == *"PROJECT_ROOT=$TEST_TMP_DIR"* ]]; then
        return 0
    else
        echo "Expected SCRIPT_DIR=$TEST_SCRIPT_DIR and PROJECT_ROOT=$TEST_TMP_DIR"
        echo "Got: $output"
        return 1
    fi
}

test_subdirectory_path_resolution() {
    cat > "$TEST_SUBDIR/test-script.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "PROJECT_ROOT=$PROJECT_ROOT"
EOF
    chmod +x "$TEST_SUBDIR/test-script.sh"
    
    local output
    output=$("$TEST_SUBDIR/test-script.sh")
    
    if [[ "$output" == *"SCRIPT_DIR=$TEST_SUBDIR"* ]] && 
       [[ "$output" == *"PROJECT_ROOT=$TEST_TMP_DIR"* ]]; then
        return 0
    else
        echo "Expected SCRIPT_DIR=$TEST_SUBDIR and PROJECT_ROOT=$TEST_TMP_DIR"
        echo "Got: $output"
        return 1
    fi
}

test_dynamic_root_detection() {
    cat > "$TEST_SUBDIR/test-dynamic.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_project_root() {
    local current_dir="$1"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/CLAUDE.md" ]] && [[ -d "$current_dir/lib" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    return 1
}

PROJECT_ROOT="$(find_project_root "$SCRIPT_DIR")"
echo "PROJECT_ROOT=$PROJECT_ROOT"
EOF
    chmod +x "$TEST_SUBDIR/test-dynamic.sh"
    
    local output
    output=$("$TEST_SUBDIR/test-dynamic.sh")
    
    if [[ "$output" == *"PROJECT_ROOT=$TEST_TMP_DIR"* ]]; then
        return 0
    else
        echo "Expected PROJECT_ROOT=$TEST_TMP_DIR"
        echo "Got: $output"
        return 1
    fi
}

test_symlink_path_resolution() {
    # Create a symlink to test script
    ln -s "$TEST_SCRIPT_DIR/test-script.sh" "$TEST_TMP_DIR/test-symlink.sh"
    
    cat > "$TEST_SCRIPT_DIR/test-script.sh" << 'EOF'
set -euo pipefail
if command -v readlink >/dev/null 2>&1; then
    REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(dirname "$REAL_SCRIPT")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "PROJECT_ROOT=$PROJECT_ROOT"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-script.sh"
    
    local output
    output=$("$TEST_TMP_DIR/test-symlink.sh")
    
    # Handle macOS /tmp symlink to /private/tmp
    local expected_root="$TEST_TMP_DIR"
    local alt_root="${TEST_TMP_DIR/#\/tmp\//\/private\/tmp\/}"
    
    if [[ "$output" == *"PROJECT_ROOT=$expected_root"* ]] || 
       [[ "$output" == *"PROJECT_ROOT=$alt_root"* ]]; then
        return 0
    else
        echo "Expected PROJECT_ROOT=$expected_root or $alt_root"
        echo "Got: $output"
        return 1
    fi
}

# =============================================================================
# LIBRARY LOADING TESTS
# =============================================================================

test_basic_loading() {
    cat > "$TEST_SCRIPT_DIR/test-basic-load.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/test-core.sh"
test_core_function
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-basic-load.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-basic-load.sh")
    
    if [[ "$output" == "test-core-function" ]]; then
        return 0
    else
        echo "Expected: test-core-function"
        echo "Got: $output"
        return 1
    fi
}

test_loading_order() {
    cat > "$TEST_SCRIPT_DIR/test-order.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/test-core.sh"
source "$PROJECT_ROOT/lib/test-dependent.sh"
test_dependent_function
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-order.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-order.sh")
    
    if [[ "$output" == "test-dependent-function" ]]; then
        return 0
    else
        echo "Expected: test-dependent-function"
        echo "Got: $output"
        return 1
    fi
}

test_wrong_order() {
    cat > "$TEST_SCRIPT_DIR/test-wrong-order.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/test-dependent.sh" 2>&1
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-wrong-order.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-wrong-order.sh" 2>&1 || true)
    
    if [[ "$output" == *"test-core.sh must be loaded first"* ]]; then
        return 0
    else
        echo "Expected error about test-core.sh loading"
        echo "Got: $output"
        return 1
    fi
}

test_double_source_prevention() {
    cat > "$TEST_SCRIPT_DIR/test-double-source.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/test-core.sh"
echo "First load: TEST_CORE_LOADED=$TEST_CORE_LOADED"
source "$PROJECT_ROOT/lib/test-core.sh"
echo "Second load: TEST_CORE_LOADED=$TEST_CORE_LOADED"
echo "Function available: $(test_core_function)"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-double-source.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-double-source.sh")
    
    if [[ "$output" == *"First load: TEST_CORE_LOADED=1"* ]] &&
       [[ "$output" == *"Second load: TEST_CORE_LOADED=1"* ]] &&
       [[ "$output" == *"Function available: test-core-function"* ]]; then
        return 0
    else
        echo "Expected double source prevention to work"
        echo "Got: $output"
        return 1
    fi
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_missing_library() {
    cat > "$TEST_SCRIPT_DIR/test-missing.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$PROJECT_ROOT/lib/non-existent.sh" ]]; then
    echo "Error: Required library not found: $PROJECT_ROOT/lib/non-existent.sh" >&2
    exit 1
fi
source "$PROJECT_ROOT/lib/non-existent.sh"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-missing.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-missing.sh" 2>&1 || true)
    
    if [[ "$output" == *"Required library not found"* ]] &&
       [[ "$output" == *"non-existent.sh"* ]]; then
        return 0
    else
        echo "Expected missing library error"
        echo "Got: $output"
        return 1
    fi
}

test_load_library_helper() {
    cat > "$TEST_SCRIPT_DIR/test-helper.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

load_library() {
    local lib_path="$1"
    if [[ ! -f "$lib_path" ]]; then
        echo "Error: Cannot load library: $lib_path" >&2
        echo "Current directory: $(pwd)" >&2
        echo "Script directory: $SCRIPT_DIR" >&2
        echo "Project root: $PROJECT_ROOT" >&2
        return 1
    fi
    source "$lib_path"
}

load_library "$PROJECT_ROOT/lib/test-core.sh" && echo "Core loaded successfully"
load_library "$PROJECT_ROOT/lib/missing.sh" || echo "Missing library handled"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-helper.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-helper.sh" 2>&1)
    
    if [[ "$output" == *"Core loaded successfully"* ]] &&
       [[ "$output" == *"Cannot load library"* ]] &&
       [[ "$output" == *"Missing library handled"* ]]; then
        return 0
    else
        echo "Expected helper function to work correctly"
        echo "Got: $output"
        return 1
    fi
}

test_optional_loading() {
    cat > "$TEST_SCRIPT_DIR/test-optional.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Try to load optional library
if [[ -f "$PROJECT_ROOT/lib/test-optional.sh" ]]; then
    source "$PROJECT_ROOT/lib/test-optional.sh"
    OPTIONAL_AVAILABLE=true
    echo "Optional feature loaded"
else
    OPTIONAL_AVAILABLE=false
    echo "Optional feature not available"
fi

# Try missing optional
if [[ -f "$PROJECT_ROOT/lib/missing-optional.sh" ]]; then
    source "$PROJECT_ROOT/lib/missing-optional.sh"
    MISSING_AVAILABLE=true
else
    MISSING_AVAILABLE=false
    echo "Missing optional handled gracefully"
fi

echo "OPTIONAL_AVAILABLE=$OPTIONAL_AVAILABLE"
echo "MISSING_AVAILABLE=$MISSING_AVAILABLE"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-optional.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-optional.sh")
    
    if [[ "$output" == *"Optional feature loaded"* ]] &&
       [[ "$output" == *"Missing optional handled gracefully"* ]] &&
       [[ "$output" == *"OPTIONAL_AVAILABLE=true"* ]] &&
       [[ "$output" == *"MISSING_AVAILABLE=false"* ]]; then
        return 0
    else
        echo "Expected optional loading to work"
        echo "Got: $output"
        return 1
    fi
}

# =============================================================================
# DEPENDENCY RESOLUTION TESTS
# =============================================================================

test_dependency_checking() {
    cat > "$TEST_SCRIPT_DIR/test-deps.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

check_dependencies() {
    local missing=0
    local deps=(
        "lib/test-core.sh"
        "lib/test-dependent.sh"
        "lib/missing-dep.sh"
    )
    
    for dep in "${deps[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$dep" ]]; then
            echo "Missing dependency: $dep"
            ((missing++))
        else
            echo "Found dependency: $dep"
        fi
    done
    
    return $missing
}

if ! check_dependencies; then
    echo "Some dependencies are missing"
fi
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-deps.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-deps.sh" 2>&1 || true)
    
    if [[ "$output" == *"Found dependency: lib/test-core.sh"* ]] &&
       [[ "$output" == *"Found dependency: lib/test-dependent.sh"* ]] &&
       [[ "$output" == *"Missing dependency: lib/missing-dep.sh"* ]] &&
       [[ "$output" == *"Some dependencies are missing"* ]]; then
        return 0
    else
        echo "Expected dependency checking to work"
        echo "Got: $output"
        return 1
    fi
}

# =============================================================================
# MODULE LOADING TESTS
# =============================================================================

test_module_loading() {
    cat > "$TEST_SCRIPT_DIR/test-module.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/modules/core/test-module.sh"
test_module_function
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-module.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-module.sh")
    
    if [[ "$output" == "test-module-function" ]]; then
        return 0
    else
        echo "Expected: test-module-function"
        echo "Got: $output"
        return 1
    fi
}

test_module_no_root() {
    cat > "$TEST_SCRIPT_DIR/test-module-fail.sh" << 'EOF'
set -euo pipefail
source "$1" 2>&1
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-module-fail.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-module-fail.sh" "$TEST_TMP_DIR/lib/modules/core/test-module.sh" 2>&1 || true)
    
    if [[ "$output" == *"PROJECT_ROOT not defined"* ]]; then
        return 0
    else
        echo "Expected PROJECT_ROOT error"
        echo "Got: $output"
        return 1
    fi
}

test_module_category_loading() {
    # Create additional test modules
    echo '[[ -n "${MODULE1_LOADED:-}" ]] && return 0; declare -r MODULE1_LOADED=1' > "$TEST_TMP_DIR/lib/modules/core/module1.sh"
    echo '[[ -n "${MODULE2_LOADED:-}" ]] && return 0; declare -r MODULE2_LOADED=1' > "$TEST_TMP_DIR/lib/modules/core/module2.sh"
    chmod +x "$TEST_TMP_DIR/lib/modules/core"/*.sh
    
    # Direct test without script generation to avoid output capture issues
    local loaded_count=0
    export PROJECT_ROOT="$TEST_TMP_DIR"
    
    # Load modules directly
    for module in "$TEST_TMP_DIR/lib/modules/core"/*.sh; do
        if [[ -f "$module" ]]; then
            if source "$module"; then
                ((loaded_count++))
            fi
        fi
    done
    
    # Check results
    if [[ $loaded_count -eq 3 ]] &&
       [[ -n "${TEST_MODULE_LOADED:-}" ]] &&
       [[ -n "${MODULE1_LOADED:-}" ]] &&
       [[ -n "${MODULE2_LOADED:-}" ]]; then
        # Variables are readonly, so we can't unset them
        return 0
    else
        echo "Expected 3 modules to load"
        echo "Got: loaded_count=$loaded_count"
        echo "TEST_MODULE_LOADED=${TEST_MODULE_LOADED:-not set}"
        echo "MODULE1_LOADED=${MODULE1_LOADED:-not set}"
        echo "MODULE2_LOADED=${MODULE2_LOADED:-not set}"
        return 1
    fi
}


# =============================================================================
# WORKING DIRECTORY TESTS
# =============================================================================

test_different_cwd() {
    cat > "$TEST_SCRIPT_DIR/test-cwd.sh" << 'EOF'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Initial CWD: $(pwd)"
cd /tmp
echo "Changed CWD: $(pwd)"

source "$PROJECT_ROOT/lib/test-core.sh"
test_core_function
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-cwd.sh"
    
    local output
    output=$(cd / && "$TEST_SCRIPT_DIR/test-cwd.sh")
    
    if [[ "$output" == *"Initial CWD: /"* ]] &&
       [[ "$output" == *"Changed CWD: /tmp"* ]] &&
       [[ "$output" == *"test-core-function"* ]]; then
        return 0
    else
        echo "Expected CWD independence"
        echo "Got: $output"
        return 1
    fi
}

# =============================================================================
# COMPREHENSIVE INTEGRATION TEST
# =============================================================================

test_full_workflow() {
    cat > "$TEST_SCRIPT_DIR/test-full.sh" << 'EOF'
set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load libraries directly (no function wrapper)
echo "Loading: lib/test-core.sh"
source "$PROJECT_ROOT/lib/test-core.sh"

echo "Loading: lib/test-dependent.sh"
source "$PROJECT_ROOT/lib/test-dependent.sh"

# Optional library
if [[ -f "$PROJECT_ROOT/lib/test-optional.sh" ]]; then
    echo "Loading: lib/test-optional.sh"
    source "$PROJECT_ROOT/lib/test-optional.sh"
    HAS_OPTIONAL=true
else
    HAS_OPTIONAL=false
fi

# Use functions
echo "Core: $(test_core_function)"
echo "Dependent: $(test_dependent_function)"
[[ "$HAS_OPTIONAL" == "true" ]] && echo "Optional: $(test_optional_function)"

echo "All libraries loaded successfully"
EOF
    chmod +x "$TEST_SCRIPT_DIR/test-full.sh"
    
    local output
    output=$("$TEST_SCRIPT_DIR/test-full.sh" 2>&1)
    
    if [[ "$output" == *"Loading: lib/test-core.sh"* ]] &&
       [[ "$output" == *"Loading: lib/test-dependent.sh"* ]] &&
       [[ "$output" == *"Loading: lib/test-optional.sh"* ]] &&
       [[ "$output" == *"Core: test-core-function"* ]] &&
       [[ "$output" == *"Dependent: test-dependent-function"* ]] &&
       [[ "$output" == *"Optional: test-optional-function"* ]] &&
       [[ "$output" == *"All libraries loaded successfully"* ]]; then
        return 0
    else
        echo "Expected full workflow to complete"
        echo "Got: $output"
        return 1
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

# Print header
print_header

# Run setup
echo -e "${CYAN}Setting up test environment...${NC}"
setup_test_environment

# Define all tests
echo -e "\n${CYAN}Running tests...${NC}"

# Path resolution tests
run_test "Standard path resolution from scripts directory" test_standard_path_resolution
run_test "Path resolution from subdirectory" test_subdirectory_path_resolution
run_test "Dynamic project root detection" test_dynamic_root_detection
run_test "Path resolution with symlinks" test_symlink_path_resolution

# Library loading tests
run_test "Basic library loading" test_basic_loading
run_test "Loading order validation" test_loading_order
run_test "Wrong loading order fails" test_wrong_order
run_test "Double sourcing prevention" test_double_source_prevention

# Error handling tests
run_test "Missing library error handling" test_missing_library
run_test "Load library helper function" test_load_library_helper
run_test "Optional library loading" test_optional_loading

# Dependency resolution tests
run_test "Dependency checking" test_dependency_checking

# Module loading tests
run_test "Module loading with PROJECT_ROOT check" test_module_loading
run_test "Module loading without PROJECT_ROOT fails" test_module_no_root
run_test "Module category loading" test_module_category_loading

# Working directory tests
run_test "Loading from different working directory" test_different_cwd

# Integration test
run_test "Full library loading workflow" test_full_workflow

# Print summary
print_summary

# Cleanup
cleanup_test_environment
