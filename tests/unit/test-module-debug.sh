#!/usr/bin/env bash
# Debug module loading

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"
export MODULES_DIR="$LIB_DIR/modules"

# Source library loader
source "$LIB_DIR/utils/library-loader.sh" >/dev/null 2>&1

echo "=== Module Loading Debug ==="
echo
echo "LIB_DIR: $LIB_DIR"
echo "MODULES_DIR: $MODULES_DIR"
echo

# Test direct file sourcing
echo "1. Testing direct source of core/variables.sh:"
if [[ -f "$MODULES_DIR/core/variables.sh" ]]; then
    echo "   File exists: ✓"
    source "$MODULES_DIR/core/variables.sh"
    if declare -f init_variables >/dev/null; then
        echo "   Functions loaded: ✓"
    else
        echo "   Functions loaded: ✗"
    fi
else
    echo "   File exists: ✗"
fi

echo
echo "2. Testing load_module function:"
# Clear loaded modules
unset LOADED_MODULES
declare -A LOADED_MODULES=()

# Enable debugging
set -x
load_module "core/variables" 2>&1 | head -20
set +x

echo
echo "3. Checking LOADED_MODULES array:"
for key in "${!LOADED_MODULES[@]}"; do
    echo "   $key = ${LOADED_MODULES[$key]}"
done

echo
echo "4. Checking if init_variables function exists:"
if declare -f init_variables >/dev/null; then
    echo "   ✓ Function exists"
else
    echo "   ✗ Function missing"
fi