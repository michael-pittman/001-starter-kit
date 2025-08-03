#!/bin/bash
# Automatic event cleanup script

EVENTS_DIR=".unity/events"
AUDIT_LOG="logs/unity/events-audit.log"
RETENTION_DAYS=30

# Clean up old processed events
find "$EVENTS_DIR/processed" -name "*.event" -mtime +7 -delete 2>/dev/null

# Clean up old audit logs
if [[ -f "$AUDIT_LOG" ]]; then
    # Keep only last RETENTION_DAYS days
    tail -n 1000 "$AUDIT_LOG" > "${AUDIT_LOG}.tmp" && mv "${AUDIT_LOG}.tmp" "$AUDIT_LOG"
fi

# Clean up old replay directories
find "$EVENTS_DIR/replay" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
