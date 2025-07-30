#!/bin/bash
#
# Maintenance Notifications Module
# Notification system for maintenance operations
#

# =============================================================================
# NOTIFICATION CONFIGURATION
# =============================================================================

# Notification methods
declare -a NOTIFICATION_METHODS=("log" "webhook" "email" "slack")

# Default notification settings
declare -g NOTIFICATION_LOG_FILE="${MAINTENANCE_PROJECT_ROOT}/logs/maintenance-notifications.log"
declare -g NOTIFICATION_WEBHOOK_URL="${WEBHOOK_URL:-}"
declare -g NOTIFICATION_EMAIL_TO="${MAINTENANCE_EMAIL:-}"
declare -g NOTIFICATION_SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"

# Notification levels
declare -A NOTIFICATION_LEVELS=(
    ["info"]="ℹ️"
    ["success"]="✅"
    ["warning"]="⚠️"
    ["error"]="❌"
    ["critical"]="🚨"
)

# Operation status emojis
declare -A OPERATION_STATUS_EMOJIS=(
    ["started"]="🚀"
    ["in_progress"]="⏳"
    ["completed"]="✅"
    ["failed"]="❌"
    ["cancelled"]="🚫"
    ["rollback"]="↩️"
)

# =============================================================================
# MAIN NOTIFICATION FUNCTION
# =============================================================================

# Send notification
send_notification() {
    local level="$1"
    local title="$2"
    local message="$3"
    local details="${4:-}"
    
    if [[ "$MAINTENANCE_NOTIFY" != true ]]; then
        return 0
    fi
    
    # Create notification payload
    local notification=$(create_notification_payload "$level" "$title" "$message" "$details")
    
    # Send via configured methods
    if [[ "$NOTIFICATION_METHOD" == "all" ]]; then
        for method in "${NOTIFICATION_METHODS[@]}"; do
            send_via_method "$method" "$notification"
        done
    else
        send_via_method "${NOTIFICATION_METHOD:-log}" "$notification"
    fi
}

# Create notification payload
create_notification_payload() {
    local level="$1"
    local title="$2"
    local message="$3"
    local details="$4"
    
    local emoji="${NOTIFICATION_LEVELS[$level]:-ℹ️}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create JSON payload
    cat << EOF
{
    "timestamp": "${timestamp}",
    "level": "${level}",
    "emoji": "${emoji}",
    "title": "${title}",
    "message": "${message}",
    "details": "${details}",
    "host": "$(hostname)",
    "user": "$(whoami)",
    "stack": "${MAINTENANCE_STACK_NAME:-unknown}",
    "operation": "${MAINTENANCE_OPERATION:-unknown}",
    "target": "${MAINTENANCE_TARGET:-unknown}"
}
EOF
}

# Send via specific method
send_via_method() {
    local method="$1"
    local payload="$2"
    
    case "$method" in
        log)
            send_to_log "$payload"
            ;;
        webhook)
            send_to_webhook "$payload"
            ;;
        email)
            send_to_email "$payload"
            ;;
        slack)
            send_to_slack "$payload"
            ;;
        *)
            log_maintenance "WARNING" "Unknown notification method: $method"
            ;;
    esac
}

# =============================================================================
# NOTIFICATION METHODS
# =============================================================================

# Send to log file
send_to_log() {
    local payload="$1"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$NOTIFICATION_LOG_FILE")"
    
    # Extract key fields
    local timestamp=$(echo "$payload" | jq -r '.timestamp')
    local level=$(echo "$payload" | jq -r '.level')
    local title=$(echo "$payload" | jq -r '.title')
    local message=$(echo "$payload" | jq -r '.message')
    
    # Write to log
    echo "[$timestamp] [$level] $title - $message" >> "$NOTIFICATION_LOG_FILE"
    
    # Also write full JSON for parsing
    echo "$payload" >> "${NOTIFICATION_LOG_FILE}.json"
}

# Send to webhook
send_to_webhook() {
    local payload="$1"
    
    if [[ -z "$NOTIFICATION_WEBHOOK_URL" ]]; then
        log_maintenance "DEBUG" "Webhook URL not configured"
        return 0
    fi
    
    # Send webhook
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$NOTIFICATION_WEBHOOK_URL" \
        2>/dev/null || {
        log_maintenance "WARNING" "Failed to send webhook notification"
    }
}

# Send to email
send_to_email() {
    local payload="$1"
    
    if [[ -z "$NOTIFICATION_EMAIL_TO" ]]; then
        log_maintenance "DEBUG" "Email recipient not configured"
        return 0
    fi
    
    # Check if mail command exists
    if ! command -v mail &> /dev/null; then
        log_maintenance "WARNING" "Mail command not available"
        return 0
    fi
    
    # Extract fields
    local title=$(echo "$payload" | jq -r '.title')
    local message=$(echo "$payload" | jq -r '.message')
    local details=$(echo "$payload" | jq -r '.details // ""')
    
    # Create email body
    local email_body="Maintenance Notification

Title: $title
Message: $message

Details:
$details

Full Details:
$payload"
    
    # Send email
    echo "$email_body" | mail -s "[Maintenance] $title" "$NOTIFICATION_EMAIL_TO" 2>/dev/null || {
        log_maintenance "WARNING" "Failed to send email notification"
    }
}

# Send to Slack
send_to_slack() {
    local payload="$1"
    
    if [[ -z "$NOTIFICATION_SLACK_WEBHOOK" ]]; then
        log_maintenance "DEBUG" "Slack webhook not configured"
        return 0
    fi
    
    # Extract fields
    local emoji=$(echo "$payload" | jq -r '.emoji')
    local title=$(echo "$payload" | jq -r '.title')
    local message=$(echo "$payload" | jq -r '.message')
    local level=$(echo "$payload" | jq -r '.level')
    local operation=$(echo "$payload" | jq -r '.operation')
    local target=$(echo "$payload" | jq -r '.target')
    local details=$(echo "$payload" | jq -r '.details // ""')
    
    # Determine color based on level
    local color="good"
    case "$level" in
        error|critical)
            color="danger"
            ;;
        warning)
            color="warning"
            ;;
    esac
    
    # Create Slack payload
    local slack_payload=$(cat << EOF
{
    "text": "$emoji $title",
    "attachments": [
        {
            "color": "$color",
            "fields": [
                {
                    "title": "Message",
                    "value": "$message",
                    "short": false
                },
                {
                    "title": "Operation",
                    "value": "$operation",
                    "short": true
                },
                {
                    "title": "Target",
                    "value": "$target",
                    "short": true
                }
            ],
            "footer": "Maintenance System",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    # Send to Slack
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$slack_payload" \
        "$NOTIFICATION_SLACK_WEBHOOK" \
        2>/dev/null || {
        log_maintenance "WARNING" "Failed to send Slack notification"
    }
}

# =============================================================================
# OPERATION NOTIFICATIONS
# =============================================================================

# Notify operation start
notify_operation_start() {
    local operation="$1"
    local target="$2"
    
    local emoji="${OPERATION_STATUS_EMOJIS[started]}"
    local title="$emoji Maintenance Operation Started"
    local message="Starting $operation operation on $target"
    
    local details=$(cat << EOF
Operation: $operation
Target: $target
Dry Run: ${MAINTENANCE_DRY_RUN}
Backup Enabled: ${MAINTENANCE_BACKUP}
Rollback Enabled: ${MAINTENANCE_ROLLBACK}
Started At: $(date)
EOF
)
    
    send_notification "info" "$title" "$message" "$details"
}

# Notify operation progress
notify_operation_progress() {
    local operation="$1"
    local target="$2"
    local progress="$3"
    local current_task="$4"
    
    local emoji="${OPERATION_STATUS_EMOJIS[in_progress]}"
    local title="$emoji Operation Progress: ${progress}%"
    local message="$operation on $target - $current_task"
    
    send_notification "info" "$title" "$message"
}

# Notify operation completion
notify_operation_complete() {
    local operation="$1"
    local target="$2"
    local status="$3"
    local summary="$4"
    
    local emoji="${OPERATION_STATUS_EMOJIS[$status]}"
    local level="success"
    
    if [[ "$status" == "failed" ]]; then
        level="error"
    elif [[ "$status" == "cancelled" ]]; then
        level="warning"
    fi
    
    local title="$emoji Maintenance Operation ${status^}"
    local message="$operation on $target has $status"
    
    send_notification "$level" "$title" "$message" "$summary"
}

# Notify safety warning
notify_safety_warning() {
    local warning_type="$1"
    local details="$2"
    
    local title="⚠️ Safety Warning: $warning_type"
    local message="A safety check has triggered a warning"
    
    send_notification "warning" "$title" "$message" "$details"
}

# Notify critical error
notify_critical_error() {
    local error_type="$1"
    local error_message="$2"
    local stack_trace="${3:-}"
    
    local title="🚨 Critical Error: $error_type"
    local message="A critical error has occurred"
    
    local details=$(cat << EOF
Error: $error_message
Operation: ${MAINTENANCE_OPERATION:-unknown}
Target: ${MAINTENANCE_TARGET:-unknown}
Stack Trace:
$stack_trace
EOF
)
    
    send_notification "critical" "$title" "$message" "$details"
}

# Notify backup status
notify_backup_status() {
    local backup_type="$1"
    local status="$2"
    local backup_id="${3:-}"
    
    local emoji="📦"
    if [[ "$status" == "failed" ]]; then
        emoji="❌"
    elif [[ "$status" == "completed" ]]; then
        emoji="✅"
    fi
    
    local title="$emoji Backup $status"
    local message="$backup_type backup has $status"
    
    local details=""
    if [[ -n "$backup_id" ]]; then
        details="Backup ID: $backup_id"
    fi
    
    local level="info"
    if [[ "$status" == "failed" ]]; then
        level="error"
    elif [[ "$status" == "completed" ]]; then
        level="success"
    fi
    
    send_notification "$level" "$title" "$message" "$details"
}

# Notify rollback status
notify_rollback_status() {
    local rollback_type="$1"
    local status="$2"
    local rollback_id="${3:-}"
    
    local emoji="${OPERATION_STATUS_EMOJIS[rollback]}"
    if [[ "$status" == "failed" ]]; then
        emoji="❌"
    elif [[ "$status" == "completed" ]]; then
        emoji="✅"
    fi
    
    local title="$emoji Rollback $status"
    local message="$rollback_type rollback has $status"
    
    local details=""
    if [[ -n "$rollback_id" ]]; then
        details="Rollback ID: $rollback_id"
    fi
    
    local level="warning"
    if [[ "$status" == "failed" ]]; then
        level="critical"
    elif [[ "$status" == "completed" ]]; then
        level="success"
    fi
    
    send_notification "$level" "$title" "$message" "$details"
}

# =============================================================================
# SUMMARY NOTIFICATIONS
# =============================================================================

# Send operation summary
send_operation_summary() {
    local operation="$1"
    local target="$2"
    local counters="$3"
    
    # Parse counters
    local processed=$(echo "$counters" | jq -r '.processed // 0')
    local fixed=$(echo "$counters" | jq -r '.fixed // 0')
    local failed=$(echo "$counters" | jq -r '.failed // 0')
    local skipped=$(echo "$counters" | jq -r '.skipped // 0')
    
    # Determine overall status
    local status="completed"
    local emoji="✅"
    local level="success"
    
    if [[ $failed -gt 0 ]]; then
        status="completed with errors"
        emoji="⚠️"
        level="warning"
    fi
    
    if [[ $fixed -eq 0 ]] && [[ $failed -eq 0 ]]; then
        status="completed (no changes)"
        emoji="ℹ️"
        level="info"
    fi
    
    local title="$emoji Maintenance Summary"
    local message="$operation on $target has $status"
    
    local details=$(cat << EOF
Operation: $operation
Target: $target
Status: $status

Results:
- Processed: $processed
- Fixed: $fixed
- Failed: $failed
- Skipped: $skipped

Duration: ${MAINTENANCE_DURATION:-unknown}
Completed At: $(date)
EOF
)
    
    send_notification "$level" "$title" "$message" "$details"
}

# =============================================================================
# NOTIFICATION MANAGEMENT
# =============================================================================

# Test notification system
test_notifications() {
    log_maintenance "INFO" "Testing notification system..."
    
    send_notification "info" "🧪 Test Notification" "This is a test of the notification system" "All configured notification methods will receive this test"
    
    log_maintenance "SUCCESS" "Test notification sent"
}

# List configured notifications
list_notifications() {
    echo "Configured Notification Methods:"
    echo "==============================="
    
    echo ""
    echo "Log File:"
    echo "  Status: Always enabled"
    echo "  Path: $NOTIFICATION_LOG_FILE"
    
    echo ""
    echo "Webhook:"
    if [[ -n "$NOTIFICATION_WEBHOOK_URL" ]]; then
        echo "  Status: Configured"
        echo "  URL: ${NOTIFICATION_WEBHOOK_URL:0:30}..."
    else
        echo "  Status: Not configured"
        echo "  Set WEBHOOK_URL environment variable"
    fi
    
    echo ""
    echo "Email:"
    if [[ -n "$NOTIFICATION_EMAIL_TO" ]]; then
        echo "  Status: Configured"
        echo "  Recipient: $NOTIFICATION_EMAIL_TO"
    else
        echo "  Status: Not configured"
        echo "  Set MAINTENANCE_EMAIL environment variable"
    fi
    
    echo ""
    echo "Slack:"
    if [[ -n "$NOTIFICATION_SLACK_WEBHOOK" ]]; then
        echo "  Status: Configured"
        echo "  Webhook: ${NOTIFICATION_SLACK_WEBHOOK:0:30}..."
    else
        echo "  Status: Not configured"
        echo "  Set SLACK_WEBHOOK_URL environment variable"
    fi
}

# View recent notifications
view_recent_notifications() {
    local count="${1:-10}"
    
    if [[ -f "$NOTIFICATION_LOG_FILE" ]]; then
        echo "Recent Notifications (last $count):"
        echo "=================================="
        tail -n "$count" "$NOTIFICATION_LOG_FILE"
    else
        echo "No notifications found"
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f send_notification
export -f create_notification_payload
export -f send_via_method
export -f send_to_log
export -f send_to_webhook
export -f send_to_email
export -f send_to_slack
export -f notify_operation_start
export -f notify_operation_progress
export -f notify_operation_complete
export -f notify_safety_warning
export -f notify_critical_error
export -f notify_backup_status
export -f notify_rollback_status
export -f send_operation_summary
export -f test_notifications
export -f list_notifications
export -f view_recent_notifications