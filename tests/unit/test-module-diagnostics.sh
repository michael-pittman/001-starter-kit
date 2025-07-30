#!/usr/bin/env bash
# =============================================================================
# Module Loading Diagnostics
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"

echo "=== Module Loading Diagnostics ==="
echo
echo "PROJECT_ROOT: $PROJECT_ROOT"
echo "LIB_DIR: $LIB_DIR"
echo

# Check if library loader exists
echo "Checking library loader..."
if [[ -f "$LIB_DIR/utils/library-loader.sh" ]]; then
    echo "✓ Library loader found"
    
    # Source it
    echo "Sourcing library loader..."
    # Don't pipe the source command as it runs in a subshell
    source "$LIB_DIR/utils/library-loader.sh" >/dev/null 2>&1
    
    # Check if functions exist
    echo
    echo "Checking functions..."
    for func in initialize_script load_module load_modules; do
        if declare -f "$func" >/dev/null; then
            echo "✓ Function exists: $func"
        else
            echo "✗ Function missing: $func"
        fi
    done
    
    # Check module directories
    echo
    echo "Checking module directories..."
    if [[ -d "$LIB_DIR/modules" ]]; then
        echo "✓ Modules directory exists"
        echo "  Contents:"
        ls -la "$LIB_DIR/modules/" | grep "^d" | awk '{print "    - " $NF}'
    else
        echo "✗ Modules directory missing"
    fi
    
    # Try loading a simple module
    echo
    echo "Testing module loading..."
    if initialize_script "test" "core/variables" 2>&1; then
        echo "✓ Module loaded successfully"
        
        # Check if module set its loaded flag
        if [[ "${MODULE_CORE_VARIABLES_LOADED:-}" == "true" ]]; then
            echo "✓ Module flag set correctly"
        else
            echo "✗ Module flag not set"
        fi
    else
        echo "✗ Module loading failed"
    fi
    
else
    echo "✗ Library loader not found at $LIB_DIR/utils/library-loader.sh"
fi

echo
echo "=== Diagnostics Complete ==="