#!/bin/bash
#
# Wrapper script for update-image-versions.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./update-image-versions-wrapper.sh <action> [environment] [use-latest]
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the maintenance suite
source "$LIB_DIR/modules/maintenance/maintenance-suite.sh"

# Parse arguments
ACTION="${1:-show}"
ENVIRONMENT="${2:-development}"
USE_LATEST="${3:-false}"

# Handle help
if [[ "$ACTION" == "--help" || "$ACTION" == "-h" ]]; then
    echo "Usage: $0 <action> [environment] [use-latest]"
    echo ""
    echo "This is a compatibility wrapper for the new maintenance suite."
    echo ""
    echo "Actions:"
    echo "  show     Display current image versions"
    echo "  update   Update image versions"
    echo "  test     Test image availability"
    echo "  restore  Restore from backup"
    echo ""
    echo "Environments:"
    echo "  development  Development environment (default)"
    echo "  production   Production environment"
    echo "  testing      Testing environment"
    echo ""
    echo "Examples:"
    echo "  $0 show"
    echo "  $0 update development true   # Update to latest dev versions"
    echo "  $0 update production false   # Update to pinned prod versions"
    echo "  $0 test"
    echo "  $0 restore backup-file"
    exit 0
fi

# Map legacy actions to maintenance suite operations
case "$ACTION" in
    show)
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=show"
        )
        ;;
    update)
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=update"
            "--environment=$ENVIRONMENT"
        )
        [[ "$USE_LATEST" == "true" ]] && MAINTENANCE_ARGS+=("--use-latest")
        ;;
    test)
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=test"
        )
        ;;
    restore)
        if [[ -z "$ENVIRONMENT" ]]; then
            echo "ERROR: Backup file required for restore action" >&2
            exit 1
        fi
        MAINTENANCE_ARGS=(
            "--operation=update"
            "--component=docker"
            "--action=restore"
            "--backup-file=$ENVIRONMENT"
        )
        ;;
    *)
        echo "ERROR: Invalid action: $ACTION" >&2
        echo "Valid actions: show, update, test, restore"
        exit 1
        ;;
esac

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-update' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Image version operation failed" >&2
    exit 1
}