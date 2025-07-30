#!/bin/bash
#
# Wrapper script for backup-system.sh
# Provides backward compatibility by calling the new maintenance suite
#
# Usage: ./backup-system-wrapper.sh [STACK_NAME] [--full|--config|--data] [--compress]
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
BACKUP_TYPE="full"
COMPRESS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            BACKUP_TYPE="full"
            shift
            ;;
        --config)
            BACKUP_TYPE="config"
            shift
            ;;
        --data)
            BACKUP_TYPE="data"
            shift
            ;;
        --compress)
            COMPRESS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [STACK_NAME] [--full|--config|--data] [--compress]"
            echo ""
            echo "This is a compatibility wrapper for the new maintenance suite."
            echo ""
            echo "Options:"
            echo "  --full       Backup everything (default)"
            echo "  --config     Backup configuration files only"
            echo "  --data       Backup data directories only"
            echo "  --compress   Compress backup archive"
            echo ""
            echo "If STACK_NAME is provided, it will also backup stack-specific resources."
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
    "--operation=backup"
    "--backup-type=$BACKUP_TYPE"
)

# Add optional arguments
[[ -n "$STACK_NAME" ]] && MAINTENANCE_ARGS+=("--stack-name=$STACK_NAME")
[[ "$COMPRESS" == "true" ]] && MAINTENANCE_ARGS+=("--compress")

# Show deprecation notice
echo "NOTE: This is a compatibility wrapper. Use 'make maintenance-backup' for the new interface."
echo ""

# Execute maintenance operation
run_maintenance "${MAINTENANCE_ARGS[@]}" || {
    echo "ERROR: Backup operation failed" >&2
    exit 1
}

echo ""
echo "Backup completed. Use './verify-backup-wrapper.sh' to verify the backup."