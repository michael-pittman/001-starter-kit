#!/usr/bin/env bash
# =============================================================================
# Module Consolidation Test - Main test directory version
# Tests module consolidation functionality
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"
export MODULES_DIR="$LIB_DIR/modules"

# Simple test framework
PASSED=0
FAILED=0

pass() {
    echo "✓ $1"
    ((PASSED++))
}

fail() {
    echo "✗ $1"
    ((FAILED++))
}

echo "=== Module Consolidation Test ==="
echo

# Test 1: Library loader exists
echo "Testing library infrastructure..."
if [[ -f "$LIB_DIR/utils/library-loader.sh" ]]; then
    pass "Library loader exists"
else
    fail "Library loader missing"
fi

# Test 2: Module directories exist
if [[ -d "$MODULES_DIR" ]]; then
    module_count=$(find "$MODULES_DIR" -name "*.sh" -type f | wc -l)
    pass "Modules directory exists with $module_count modules"
else
    fail "Modules directory missing"
fi

# Test 3: Core modules exist
echo
echo "Testing core modules..."
core_modules=(
    "core/variables.sh"
    "core/logging.sh"
    "core/errors.sh"
    "core/validation.sh"
    "core/registry.sh"
)
for module in "${core_modules[@]}"; do
    if [[ -f "$MODULES_DIR/$module" ]]; then
        pass "Core module exists: $module"
    else
        fail "Core module missing: $module"
    fi
done

# Test 4: Error consolidation
echo
echo "Testing error consolidation..."
if [[ -f "$MODULES_DIR/errors/error_types.sh" ]]; then
    # Check for key error functions
    error_count=$(grep -c "^error_[a-z_]*(" "$MODULES_DIR/errors/error_types.sh" || echo 0)
    if [[ $error_count -gt 20 ]]; then
        pass "Error types module has $error_count error functions"
    else
        fail "Error types module has only $error_count error functions"
    fi
else
    fail "Error types module missing"
fi

# Test 5: Compute modules
echo
echo "Testing compute modules..."
compute_modules=(
    "compute/core.sh"
    "compute/spot.sh"
    "compute/ami.sh"
    "compute/provisioner.sh"
    "compute/spot_optimizer.sh"
)
for module in "${compute_modules[@]}"; do
    if [[ -f "$MODULES_DIR/$module" ]]; then
        pass "Compute module exists: $module"
    else
        fail "Compute module missing: $module"
    fi
done

# Test 6: Dependency groups
echo
echo "Testing dependency groups..."
if [[ -f "$MODULES_DIR/core/dependency-groups.sh" ]]; then
    # Check for dependency group definitions
    if grep -q "@minimal-deployment" "$MODULES_DIR/core/dependency-groups.sh"; then
        pass "Dependency groups defined"
    else
        fail "Dependency groups not properly defined"
    fi
else
    fail "Dependency groups module missing"
fi

# Test 7: Legacy compatibility
echo
echo "Testing backward compatibility..."
legacy_files=(
    "aws-deployment-common.sh"
    "error-handling.sh"
    "spot-instance.sh"
)
for file in "${legacy_files[@]}"; do
    if [[ -f "$LIB_DIR/$file" ]]; then
        # Check if it's a wrapper
        if grep -q "compatibility wrapper\|load_module" "$LIB_DIR/$file" 2>/dev/null; then
            pass "Legacy wrapper exists: $file"
        else
            fail "Legacy file not a proper wrapper: $file"
        fi
    else
        fail "Legacy compatibility missing: $file"
    fi
done

# Test 8: Module structure
echo
echo "Testing module structure..."
# Check that modules follow the correct pattern
sample_module="$MODULES_DIR/core/variables.sh"
if [[ -f "$sample_module" ]]; then
    if grep -q "^\[ -n \"\${_.*_SH_LOADED:-}\" \] && return 0" "$sample_module"; then
        pass "Modules use proper guard pattern"
    else
        fail "Modules missing proper guard pattern"
    fi
else
    fail "Cannot check module structure"
fi

# Summary
echo
echo "=== Test Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo
TOTAL=$((PASSED + FAILED))
if [[ $FAILED -eq 0 ]]; then
    echo "✓ All $TOTAL tests passed!"
    exit 0
else
    echo "✗ $FAILED of $TOTAL tests failed"
    exit 1
fi