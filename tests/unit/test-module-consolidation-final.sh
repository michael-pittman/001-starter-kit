#!/usr/bin/env bash
# =============================================================================
# Module Consolidation Test - Final Version
# Tests module consolidation with proper output handling
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Module Consolidation Tests ==="
echo

# Source library loader (suppress usage output)
source "$LIB_DIR/utils/library-loader.sh" >/dev/null 2>&1

# Test 1: Core modules
echo -n "Testing core modules... "
# Capture output but allow the function to run normally
output=$(initialize_script "test" "core/variables" "core/logging" "core/errors" 2>&1)
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Test 2: Error functions
echo -n "Testing error consolidation... "
output=$(initialize_script "test" "errors/error_types" 2>&1)
if declare -f error_ec2_insufficient_capacity >/dev/null && \
   declare -f error_aws_api_rate_limited >/dev/null && \
   declare -f get_error_code >/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  Missing functions:"
    declare -f error_ec2_insufficient_capacity >/dev/null || echo "    - error_ec2_insufficient_capacity"
    declare -f error_aws_api_rate_limited >/dev/null || echo "    - error_aws_api_rate_limited"
    declare -f get_error_code >/dev/null || echo "    - get_error_code"
    ((TESTS_FAILED++))
fi

# Test 3: Compute modules
echo -n "Testing compute modules... "
output=$(initialize_script "test" "compute/core" "compute/spot" 2>&1)
if declare -f validate_instance_type >/dev/null && \
   declare -f check_spot_pricing >/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  Missing functions:"
    declare -f validate_instance_type >/dev/null || echo "    - validate_instance_type"
    declare -f check_spot_pricing >/dev/null || echo "    - check_spot_pricing"
    ((TESTS_FAILED++))
fi

# Test 4: Dependency groups
echo -n "Testing dependency groups... "
unset LOADED_MODULES
declare -A LOADED_MODULES=()
output=$(initialize_script "test" "@minimal-deployment" 2>&1)
if [[ $? -eq 0 ]]; then
    if [[ "${MODULE_CORE_VARIABLES_LOADED:-}" == "true" ]] && \
       [[ "${MODULE_INFRASTRUCTURE_VPC_LOADED:-}" == "true" ]] && \
       [[ "${MODULE_COMPUTE_CORE_LOADED:-}" == "true" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} (modules not loaded)"
        echo "  Expected modules:"
        [[ "${MODULE_CORE_VARIABLES_LOADED:-}" == "true" ]] || echo "    - core/variables"
        [[ "${MODULE_INFRASTRUCTURE_VPC_LOADED:-}" == "true" ]] || echo "    - infrastructure/vpc"
        [[ "${MODULE_COMPUTE_CORE_LOADED:-}" == "true" ]] || echo "    - compute/core"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${RED}✗ FAIL${NC} (group load failed)"
    ((TESTS_FAILED++))
fi

# Test 5: Backward compatibility
echo -n "Testing backward compatibility... "
output=$(load_module "aws-deployment-common.sh" 2>&1)
if [[ $? -eq 0 ]] && declare -f log_info >/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}"
    [[ $? -eq 0 ]] || echo "  Module loading failed"
    declare -f log_info >/dev/null || echo "  Function log_info missing"
    ((TESTS_FAILED++))
fi

# Test 6: Module functions from consolidated errors
echo -n "Testing specific error functions... "
error_functions=(
    "error_argument_missing"
    "error_aws_cli_missing"
    "error_ec2_insufficient_capacity"
    "error_stack_already_exists"
    "error_deployment_rollback_required"
)
missing=0
for func in "${error_functions[@]}"; do
    if ! declare -f "$func" >/dev/null; then
        ((missing++))
    fi
done
if [[ $missing -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC} ($missing functions missing)"
    ((TESTS_FAILED++))
fi

# Test 7: Performance check
echo -n "Testing loading performance... "
start_time=$(date +%s.%N 2>/dev/null || date +%s)
unset LOADED_MODULES
declare -A LOADED_MODULES=()
output=$(initialize_script "test" "core/variables" 2>&1)
end_time=$(date +%s.%N 2>/dev/null || date +%s)

# Handle systems without nanosecond precision
if [[ "$start_time" == *"."* ]]; then
    duration=$(echo "$end_time - $start_time" | bc)
    threshold="0.5"
else
    duration=$((end_time - start_time))
    threshold="1"
fi

if [[ $(echo "$duration < $threshold" | bc -l 2>/dev/null || echo 1) -eq 1 ]]; then
    echo -e "${GREEN}✓ PASS${NC} (${duration}s)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC} (${duration}s - too slow)"
    ((TESTS_FAILED++))
fi

# Summary
echo
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit 1
fi