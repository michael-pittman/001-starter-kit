#!/bin/bash
#
# Wrapper script for verify-backup.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./verify-backup-wrapper.sh <backup-file> [--detailed]
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the maintenance suite
source "$LIB_DIR/modules/maintenance/maintenance-suite.sh"

# Parse arguments
BACKUP_FILE=""
DETAILED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --detailed)
            DETAILED=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <backup-file> [--detailed]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Options:"
            echo "  --detailed   Show detailed backup contents"
            echo ""
            echo "Examples:"
            echo "  $0 backup/backup-20240115-120000.tar.gz"
            echo "  $0 backup/backup-20240115-120000.tar.gz --detailed"
            exit 0
            ;;
        *)
            if [[ -z "$BACKUP_FILE" ]]; then
                BACKUP_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file required" >&2
    echo "Usage: $0 <backup-file> [--detailed]"
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE" >&2
    exit 1
fi

# Build maintenance suite arguments
MAINTENANCE_ARGS=(
    "--operation=verify"
    "--backup-file=$BACKUP_FILE"
)

# Add optional arguments
[[ "$DETAILED" == "true" ]] && MAINTENANCE_ARGS+=("--verbose")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-verify' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Verify operation failed" >&2
    exit 1
}