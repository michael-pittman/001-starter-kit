#!/bin/bash
#
# Wrapper script for test-network-validation.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./test-network-validation-wrapper.sh [STACK_NAME] [--comprehensive]
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the maintenance suite
source "$LIB_DIR/modules/maintenance/maintenance-suite.sh"

# Parse arguments
STACK_NAME=""
COMPREHENSIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --comprehensive)
            COMPREHENSIVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [STACK_NAME] [--comprehensive]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Tests network validation including:"
            echo "  - VPC connectivity"
            echo "  - Security group rules"
            echo "  - Load balancer health"
            echo "  - DNS resolution"
            echo "  - Service endpoints"
            echo ""
            echo "Options:"
            echo "  --comprehensive   Run extended network tests"
            echo ""
            echo "Examples:"
            echo "  $0                          # Test local network"
            echo "  $0 my-stack                 # Test stack network"
            echo "  $0 my-stack --comprehensive # Run all network tests"
            exit 0
            ;;
        *)
            if [[ -z "$STACK_NAME" ]]; then
                STACK_NAME="$1"
            fi
            shift
            ;;
    esac
done

# Build maintenance suite arguments
MAINTENANCE_ARGS=(
    "--operation=validate"
    "--validation-type=network"
)

# Add optional arguments
[[ -n "$STACK_NAME" ]] && MAINTENANCE_ARGS+=("--stack-name=$STACK_NAME")
[[ "$COMPREHENSIVE" == "true" ]] && MAINTENANCE_ARGS+=("--comprehensive")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-validate' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Network validation failed" >&2
    exit 1
}