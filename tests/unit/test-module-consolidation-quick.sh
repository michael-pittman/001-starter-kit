#!/usr/bin/env bash
# =============================================================================
# Module Consolidation Quick Test
# Fast validation of module consolidation work
# =============================================================================

set -uo pipefail  # Remove -e to handle errors gracefully

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Simple test functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# =============================================================================
# QUICK TESTS
# =============================================================================

echo "=== Module Consolidation Quick Test ==="
echo

# Test 1: Library loader exists
info "Testing library loader..."
if [[ -f "$LIB_DIR/utils/library-loader.sh" ]]; then
    pass "Library loader exists"
    # Set environment to prevent usage display
    LIBRARY_LOADER_TESTING=true
    # Source library loader - it won't print usage if we're not the last source
    source "$LIB_DIR/utils/library-loader.sh" >/dev/null 2>&1 || true
else
    fail "Library loader missing"
    exit 1
fi

# Test 2: Can load core modules
info "Testing core module loading..."
if initialize_script "test" "core/variables" "core/logging" "core/errors" 2>/dev/null; then
    pass "Core modules loaded successfully"
else
    fail "Core modules failed to load"
fi

# Test 3: Error consolidation
info "Testing error consolidation..."
initialize_script "test" "errors/error_types" 2>/dev/null || true

error_functions=(
    "error_ec2_insufficient_capacity"
    "error_aws_api_rate_limited"
    "error_deployment_rollback_required"
)

all_found=true
for func in "${error_functions[@]}"; do
    if ! declare -f "$func" > /dev/null; then
        fail "Missing error function: $func"
        all_found=false
    fi
done

if [[ "$all_found" == "true" ]]; then
    pass "All tested error functions available"
fi

# Test 4: Compute module consolidation
info "Testing compute modules..."
initialize_script "test" "compute/core" "compute/spot" 2>/dev/null || true

compute_functions=(
    "validate_instance_type"
    "check_spot_pricing"
    "get_instance_architecture"
)

all_found=true
for func in "${compute_functions[@]}"; do
    if ! declare -f "$func" > /dev/null; then
        fail "Missing compute function: $func"
        all_found=false
    fi
done

if [[ "$all_found" == "true" ]]; then
    pass "All tested compute functions available"
fi

# Test 5: Dependency groups
info "Testing dependency groups..."
unset LOADED_MODULES
declare -A LOADED_MODULES=()

if initialize_script "test" "@minimal-deployment" 2>/dev/null; then
    pass "Dependency group @minimal-deployment loads"
    
    # Check a few key modules
    if [[ "${MODULE_CORE_VARIABLES_LOADED:-}" == "true" ]] && \
       [[ "${MODULE_COMPUTE_CORE_LOADED:-}" == "true" ]] && \
       [[ "${MODULE_INFRASTRUCTURE_VPC_LOADED:-}" == "true" ]]; then
        pass "Key modules loaded in dependency group"
    else
        fail "Some modules missing from dependency group"
    fi
else
    fail "Dependency group @minimal-deployment failed to load"
fi

# Test 6: Backward compatibility
info "Testing backward compatibility..."
if load_module "aws-deployment-common.sh" 2>/dev/null; then
    pass "Legacy module name still works"
else
    fail "Legacy module name failed"
fi

# Test 7: Module isolation
info "Testing module isolation..."
vars_before=$(compgen -v | wc -l)
initialize_script "test" "compute/ami" 2>/dev/null || true
vars_after=$(compgen -v | wc -l)
new_vars=$((vars_after - vars_before))

if [[ $new_vars -lt 30 ]]; then
    pass "Module creates reasonable number of variables ($new_vars)"
else
    fail "Module creates too many variables ($new_vars)"
fi

# Test 8: Performance check
info "Testing loading performance..."
start_time=$(date +%s.%N)
initialize_script "test" "core/variables" "core/logging" "core/errors" 2>/dev/null || true
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)

if (( $(echo "$duration < 0.2" | bc -l) )); then
    pass "Modules load quickly ($duration seconds)"
else
    fail "Modules load slowly ($duration seconds)"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi