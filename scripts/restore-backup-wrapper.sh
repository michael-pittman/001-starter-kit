#!/bin/bash
#
# Wrapper script for restore-backup.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./restore-backup-wrapper.sh <backup-file> [--verify] [--dry-run]
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
VERIFY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            VERIFY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <backup-file> [--verify] [--dry-run]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Options:"
            echo "  --verify     Verify backup integrity before restoring"
            echo "  --dry-run    Show what would be restored without doing it"
            echo ""
            echo "Examples:"
            echo "  $0 backup/backup-20240115-120000.tar.gz"
            echo "  $0 backup/backup-20240115-120000.tar.gz --verify"
            echo "  $0 backup/backup-20240115-120000.tar.gz --dry-run"
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
    echo "Usage: $0 <backup-file> [--verify] [--dry-run]"
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE" >&2
    exit 1
fi

# Build maintenance suite arguments
MAINTENANCE_ARGS=(
    "--operation=restore"
    "--backup-file=$BACKUP_FILE"
)

# Add optional arguments
[[ "$VERIFY" == "true" ]] && MAINTENANCE_ARGS+=("--verify")
[[ "$DRY_RUN" == "true" ]] && MAINTENANCE_ARGS+=("--dry-run")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-restore' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Restore operation failed" >&2
    exit 1
}