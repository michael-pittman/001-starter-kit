#!/bin/bash
#
# Wrapper script for simple-update-images.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./simple-update-images-wrapper.sh [update|show|validate|test] [-v]
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the maintenance suite
source "$LIB_DIR/modules/maintenance/maintenance-suite.sh"

# Parse arguments
ACTION="update"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [update|show|validate|test] [-v]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Quick Docker image updater that updates all images to latest tags."
            echo ""
            echo "Actions:"
            echo "  update    Update all images to latest and validate (default)"
            echo "  show      Display current image versions"
            echo "  validate  Validate Docker Compose configuration"
            echo "  test      Test validation functionality"
            echo ""
            echo "Options:"
            echo "  -v, --verbose  Enable verbose output"
            echo ""
            echo "Examples:"
            echo "  $0                  # Update to latest"
            echo "  $0 show            # Show current versions"
            echo "  $0 validate        # Validate configuration"
            echo "  $0 -v update       # Update with verbose output"
            exit 0
            ;;
        update|show|validate|test)
            ACTION="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Map simple actions to maintenance suite operations
case "$ACTION" in
    update)
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=update"
            "--use-latest"
            "--simple-mode"
        )
        ;;
    show)
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=show"
        )
        ;;
    validate)
        MAINTENANCE_ARGS=(
            "--operation=validate"
            "--validation-type=docker-compose"
        )
        ;;
    test)
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=test"
        )
        ;;
esac

# Add verbose flag if needed
[[ "$VERBOSE" == "true" ]] && MAINTENANCE_ARGS+=("--verbose")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-update-simple' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Operation failed" >&2
    exit 1
}