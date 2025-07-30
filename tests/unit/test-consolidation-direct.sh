#!/usr/bin/env bash
# =============================================================================
# Direct Module Consolidation Test
# Tests modules directly without standard library loading
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"
export MODULES_DIR="$LIB_DIR/modules"

# Source library loader quietly
source "$LIB_DIR/utils/library-loader.sh" >/dev/null 2>&1

echo "=== Direct Module Tests ==="
echo

# Test 1: Load core/variables directly
echo -n "1. Testing core/variables module... "
if load_module "core/variables" >/dev/null 2>&1; then
    if declare -f init_variables >/dev/null && [[ "${MODULE_CORE_VARIABLES_LOADED:-}" == "true" ]]; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (functions missing)"
    fi
else
    echo "✗ FAIL (load failed)"
fi

# Test 2: Load errors/error_types
echo -n "2. Testing errors/error_types module... "
if load_module "errors/error_types" >/dev/null 2>&1; then
    if declare -f error_ec2_insufficient_capacity >/dev/null && \
       declare -f get_error_code >/dev/null; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (functions missing)"
    fi
else
    echo "✗ FAIL (load failed)"
fi

# Test 3: Load compute/core
echo -n "3. Testing compute/core module... "
if load_module "compute/core" >/dev/null 2>&1; then
    if declare -f validate_instance_type >/dev/null; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (functions missing)"
    fi
else
    echo "✗ FAIL (load failed)"
fi

# Test 4: Load dependency group
echo -n "4. Testing dependency group @minimal-deployment... "
unset LOADED_MODULES
declare -A LOADED_MODULES=()
if load_module "@minimal-deployment" >/dev/null 2>&1; then
    loaded_count=0
    for key in "${!LOADED_MODULES[@]}"; do
        [[ "${LOADED_MODULES[$key]}" == "true" ]] && ((loaded_count++))
    done
    if [[ $loaded_count -gt 5 ]]; then
        echo "✓ PASS ($loaded_count modules loaded)"
    else
        echo "✗ FAIL (only $loaded_count modules loaded)"
    fi
else
    echo "✗ FAIL (load failed)"
fi

# Test 5: Check module file exists
echo -n "5. Testing module file existence... "
missing=0
for module in "core/variables.sh" "core/logging.sh" "errors/error_types.sh" "compute/core.sh"; do
    if [[ ! -f "$MODULES_DIR/$module" ]]; then
        ((missing++))
    fi
done
if [[ $missing -eq 0 ]]; then
    echo "✓ PASS"
else
    echo "✗ FAIL ($missing files missing)"
fi

echo
echo "=== Test Complete ==="