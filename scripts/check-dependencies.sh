#!/usr/bin/env bash
# =============================================================================
# Dependency Check Script
# BACKWARD COMPATIBILITY WRAPPER - Delegates to validation-suite.sh
# =============================================================================

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if new validation suite exists
VALIDATION_SUITE="$PROJECT_ROOT/lib/modules/validation/validation-suite.sh"

if [[ -f "$VALIDATION_SUITE" ]]; then
    # Use new validation suite
    echo "Note: Using new consolidated validation suite" >&2
    exec "$VALIDATION_SUITE" --type dependencies "$@"
else
    # Fallback to original implementation
    echo "Warning: Validation suite not found, using legacy implementation" >&2
    
    # Initialize library loader
    SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

    # Source the errors module
    if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
        source "$LIB_DIR_TEMP/modules/core/errors.sh"
    else
        # Fallback warning if errors module not found
        echo "WARNING: Could not load errors module" >&2
    fi

    # Standard library loader
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    # Source the library loader
    source "$PROJECT_ROOT/lib/utils/library-loader.sh"

    # Load required modules through the library system
    load_module "deployment-validation"

    # Run dependency check
    check_dependencies
fi