#!/bin/bash
#
# Wrapper script for health-check-advanced.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./health-check-advanced-wrapper.sh <STACK_NAME> [--detailed] [--fix-issues]
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
DETAILED=false
FIX_ISSUES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --detailed)
            DETAILED=true
            shift
            ;;
        --fix-issues)
            FIX_ISSUES=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <STACK_NAME> [--detailed] [--fix-issues]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Performs comprehensive health checks on deployment including:"
            echo "  - Service status and connectivity"
            echo "  - Resource utilization"
            echo "  - Docker container health"
            echo "  - Database connections"
            echo "  - EFS mount status"
            echo "  - Network connectivity"
            echo ""
            echo "Options:"
            echo "  --detailed    Show detailed health information"
            echo "  --fix-issues  Attempt to fix detected issues"
            echo ""
            echo "Examples:"
            echo "  $0 my-stack"
            echo "  $0 my-stack --detailed"
            echo "  $0 my-stack --fix-issues"
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

# Validate arguments
if [[ -z "$STACK_NAME" ]]; then
    echo "ERROR: Stack name required" >&2
    echo "Usage: $0 <STACK_NAME> [--detailed] [--fix-issues]"
    exit 1
fi

# Build maintenance suite arguments
MAINTENANCE_ARGS=(
    "--operation=health"
    "--stack-name=$STACK_NAME"
)

# Add optional arguments
[[ "$DETAILED" == "true" ]] && MAINTENANCE_ARGS+=("--verbose")
[[ "$FIX_ISSUES" == "true" ]] && MAINTENANCE_ARGS+=("--auto-fix")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-health' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Health check failed" >&2
    exit 1
}