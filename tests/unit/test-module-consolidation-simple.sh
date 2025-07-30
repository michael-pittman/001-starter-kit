#!/usr/bin/env bash
# =============================================================================
# Module Consolidation Simple Test
# Basic validation without output noise
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"

# Redirect all output during loading
exec 3>&1 4>&2
exec 1>/dev/null 2>&1

# Source library loader
source "$LIB_DIR/utils/library-loader.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# Restore output for results
exec 1>&3 2>&4

echo "=== Module Consolidation Tests ==="
echo

# Test 1: Core modules
echo -n "Testing core modules... "
exec 1>/dev/null 2>&1
if initialize_script "test" "core/variables" "core/logging" "core/errors"; then
    exec 1>&3 2>&4
    echo "✓ PASS"
    ((TESTS_PASSED++))
else
    exec 1>&3 2>&4
    echo "✗ FAIL"
    ((TESTS_FAILED++))
fi

# Test 2: Error functions
echo -n "Testing error consolidation... "
exec 1>/dev/null 2>&1
initialize_script "test" "errors/error_types"
if declare -f error_ec2_insufficient_capacity >/dev/null && \
   declare -f error_aws_api_rate_limited >/dev/null && \
   declare -f get_error_code >/dev/null; then
    exec 1>&3 2>&4
    echo "✓ PASS"
    ((TESTS_PASSED++))
else
    exec 1>&3 2>&4
    echo "✗ FAIL"
    ((TESTS_FAILED++))
fi

# Test 3: Compute modules
echo -n "Testing compute modules... "
exec 1>/dev/null 2>&1
initialize_script "test" "compute/core" "compute/spot"
if declare -f validate_instance_type >/dev/null && \
   declare -f check_spot_pricing >/dev/null; then
    exec 1>&3 2>&4
    echo "✓ PASS"
    ((TESTS_PASSED++))
else
    exec 1>&3 2>&4
    echo "✗ FAIL"
    ((TESTS_FAILED++))
fi

# Test 4: Dependency groups
echo -n "Testing dependency groups... "
exec 1>/dev/null 2>&1
unset LOADED_MODULES
declare -A LOADED_MODULES=()
if initialize_script "test" "@minimal-deployment"; then
    if [[ "${MODULE_CORE_VARIABLES_LOADED:-}" == "true" ]] && \
       [[ "${MODULE_INFRASTRUCTURE_VPC_LOADED:-}" == "true" ]]; then
        exec 1>&3 2>&4
        echo "✓ PASS"
        ((TESTS_PASSED++))
    else
        exec 1>&3 2>&4
        echo "✗ FAIL (modules not loaded)"
        ((TESTS_FAILED++))
    fi
else
    exec 1>&3 2>&4
    echo "✗ FAIL (group load failed)"
    ((TESTS_FAILED++))
fi

# Test 5: Backward compatibility
echo -n "Testing backward compatibility... "
exec 1>/dev/null 2>&1
if load_module "aws-deployment-common.sh"; then
    if declare -f log_info >/dev/null; then
        exec 1>&3 2>&4
        echo "✓ PASS"
        ((TESTS_PASSED++))
    else
        exec 1>&3 2>&4
        echo "✗ FAIL (functions missing)"
        ((TESTS_FAILED++))
    fi
else
    exec 1>&3 2>&4
    echo "✗ FAIL (module load failed)"
    ((TESTS_FAILED++))
fi

# Test 6: Performance (basic check)
echo -n "Testing loading performance... "
start_time=$(date +%s.%N)
exec 1>/dev/null 2>&1
unset LOADED_MODULES
declare -A LOADED_MODULES=()
initialize_script "test" "core/variables"
exec 1>&3 2>&4
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)

if (( $(echo "$duration < 0.5" | bc -l) )); then
    echo "✓ PASS ($duration seconds)"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL ($duration seconds - too slow)"
    ((TESTS_FAILED++))
fi

# Summary
echo
echo "=== Summary ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo
    echo "✓ All tests passed!"
    exit 0
else
    echo
    echo "✗ Some tests failed!"
    exit 1
fi