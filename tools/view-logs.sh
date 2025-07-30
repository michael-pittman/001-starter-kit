#!/usr/bin/env bash
# View deployment logs

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "view-logs.sh" "core/variables" "core/logging"

# Get log file from argument or use latest
LOG_FILE="${1:-}"

if [[ -z "$LOG_FILE" ]]; then
    # Find the most recent log file
    LOG_FILE=$(find "$PROJECT_ROOT/logs" -name "deployment-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$LOG_FILE" ]]; then
        error "No deployment logs found in logs/ directory"
        exit 1
    fi
fi

if [[ ! -f "$LOG_FILE" ]]; then
    error "Log file not found: $LOG_FILE"
    exit 1
fi

log "Viewing log file: $LOG_FILE"
log "File size: $(du -h "$LOG_FILE" | cut -f1)"

# Display log contents with line numbers
cat -n "$LOG_FILE"