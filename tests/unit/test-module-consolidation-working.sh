#!/usr/bin/env bash
# =============================================================================
# Module Consolidation Working Test
# Tests with correct function names and expectations
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"

# Source library loader
source "$LIB_DIR/utils/library-loader.sh" >/dev/null 2>&1

echo "=== Module Consolidation Test ==="
echo

PASSED=0
FAILED=0

# Test 1: Core Variables Module
echo -n "1. Testing core/variables module... "
load_module "core/variables" >/dev/null 2>&1
if declare -f init_variable_store >/dev/null && \
   declare -f set_variable >/dev/null && \
   declare -f get_variable >/dev/null; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Test 2: Core Logging Module
echo -n "2. Testing core/logging module... "
load_module "core/logging" >/dev/null 2>&1
if declare -f log >/dev/null || declare -f log_info >/dev/null; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Test 3: Error Types Module
echo -n "3. Testing errors/error_types module... "
load_module "errors/error_types" >/dev/null 2>&1
if declare -f error_ec2_insufficient_capacity >/dev/null && \
   declare -f error_aws_api_rate_limited >/dev/null && \
   declare -f get_error_code >/dev/null; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Test 4: Compute Core Module
echo -n "4. Testing compute/core module... "
load_module "compute/core" >/dev/null 2>&1
if declare -f validate_instance_type >/dev/null || \
   declare -f get_instance_architecture >/dev/null; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Test 5: Check loaded modules tracking
echo -n "5. Testing module tracking... "
loaded_count=${#LOADED_MODULES[@]}
if [[ $loaded_count -gt 0 ]]; then
    echo "✓ PASS ($loaded_count modules tracked)"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Test 6: Dependency Groups
echo -n "6. Testing dependency groups... "
if [[ -f "$MODULES_DIR/core/dependency-groups.sh" ]]; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Test 7: Module Files Exist
echo -n "7. Testing consolidated module files... "
modules_to_check=(
    "core/variables.sh"
    "core/logging.sh"
    "core/errors.sh"
    "errors/error_types.sh"
    "compute/core.sh"
    "compute/spot.sh"
    "compute/ami.sh"
    "infrastructure/vpc.sh"
    "infrastructure/security.sh"
)
missing=0
for module in "${modules_to_check[@]}"; do
    [[ ! -f "$MODULES_DIR/$module" ]] && ((missing++))
done
if [[ $missing -eq 0 ]]; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL ($missing files missing)"
    ((FAILED++))
fi

# Test 8: Legacy Compatibility
echo -n "8. Testing legacy compatibility... "
# The library loader should handle old-style library names
if load_module "aws-deployment-common.sh" >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASSED++))
else
    echo "✗ FAIL"
    ((FAILED++))
fi

# Summary
echo
echo "=== Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo
if [[ $FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    
    # Show which modules are loaded for debugging
    echo
    echo "Loaded modules:"
    for module in "${!LOADED_MODULES[@]}"; do
        echo "  - $module"
    done
    exit 1
fi