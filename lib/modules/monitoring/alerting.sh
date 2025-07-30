#!/usr/bin/env bash
# =============================================================================
# Alerting System Module
# Provides comprehensive alerting for deployment issues and system events
# =============================================================================

# Prevent multiple sourcing
[ -n "${_ALERTING_SH_LOADED:-}" ] && return 0
_ALERTING_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/structured_logging.sh"
source "${SCRIPT_DIR}/metrics.sh"

# =============================================================================
# ALERT CONFIGURATION
# =============================================================================

# Alert severities
readonly ALERT_SEVERITY_INFO="info"
readonly ALERT_SEVERITY_WARNING="warning"
readonly ALERT_SEVERITY_ERROR="error"
readonly ALERT_SEVERITY_CRITICAL="critical"

# Alert states
readonly ALERT_STATE_PENDING="pending"
readonly ALERT_STATE_FIRING="firing"
readonly ALERT_STATE_RESOLVED="resolved"
readonly ALERT_STATE_SILENCED="silenced"

# Alert channels
readonly ALERT_CHANNEL_LOG="log"
readonly ALERT_CHANNEL_CONSOLE="console"
readonly ALERT_CHANNEL_WEBHOOK="webhook"
readonly ALERT_CHANNEL_SNS="sns"
readonly ALERT_CHANNEL_EMAIL="email"
readonly ALERT_CHANNEL_SLACK="slack"

# Global configuration
ALERTING_ENABLED="${ALERTING_ENABLED:-true}"
ALERT_CHANNELS=("$ALERT_CHANNEL_LOG" "$ALERT_CHANNEL_CONSOLE")
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
ALERT_SNS_TOPIC="${ALERT_SNS_TOPIC:-}"
ALERT_EMAIL_ADDRESS="${ALERT_EMAIL_ADDRESS:-}"
ALERT_SLACK_WEBHOOK="${ALERT_SLACK_WEBHOOK:-}"

# Alert storage
ALERT_HISTORY_FILE="/tmp/alerts_history_$$.json"
ALERT_RULES_FILE="/tmp/alert_rules_$$.json"
ACTIVE_ALERTS=()
ALERT_SILENCE_RULES=()

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize alerting system
init_alerting() {
    local channels="${1:-log,console}"
    local webhook_url="${2:-}"
    local sns_topic="${3:-}"
    
    log_info "Initializing alerting system" "ALERTING"
    
    # Parse alert channels
    IFS=',' read -ra ALERT_CHANNELS <<< "$channels"
    
    # Configure webhook if provided
    if [[ -n "$webhook_url" ]]; then
        ALERT_WEBHOOK_URL="$webhook_url"
        if [[ ! " ${ALERT_CHANNELS[@]} " =~ " $ALERT_CHANNEL_WEBHOOK " ]]; then
            ALERT_CHANNELS+=("$ALERT_CHANNEL_WEBHOOK")
        fi
    fi
    
    # Configure SNS if provided
    if [[ -n "$sns_topic" ]]; then
        ALERT_SNS_TOPIC="$sns_topic"
        if [[ ! " ${ALERT_CHANNELS[@]} " =~ " $ALERT_CHANNEL_SNS " ]]; then
            ALERT_CHANNELS+=("$ALERT_CHANNEL_SNS")
        fi
    fi
    
    # Initialize alert storage
    echo "[]" > "$ALERT_HISTORY_FILE"
    echo "[]" > "$ALERT_RULES_FILE"
    
    # Load default alert rules
    load_default_alert_rules
    
    log_info "Alerting system initialized with channels: ${ALERT_CHANNELS[*]}" "ALERTING"
    return 0
}

# =============================================================================
# ALERT MANAGEMENT
# =============================================================================

# Create alert
create_alert() {
    local alert_name="$1"
    local severity="$2"
    local message="$3"
    local component="${4:-}"
    local metadata="${5:-{}}"
    
    if [[ "$ALERTING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Creating alert: $alert_name" "ALERTING"
    
    # Generate alert ID
    local alert_id="alert_$(date +%s)_${RANDOM}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Check if alert should be silenced
    if is_alert_silenced "$alert_name" "$severity" "$component"; then
        log_info "Alert silenced: $alert_name" "ALERTING"
        return 0
    fi
    
    # Create alert object
    local alert
    alert=$(cat <<EOF
{
    "id": "$alert_id",
    "name": "$alert_name",
    "severity": "$severity",
    "state": "$ALERT_STATE_FIRING",
    "message": "$message",
    "component": "$component",
    "timestamp": "$timestamp",
    "stack_name": "${STACK_NAME:-}",
    "deployment_id": "${DEPLOYMENT_ID:-}",
    "metadata": $metadata
}
EOF
)
    
    # Add to active alerts
    ACTIVE_ALERTS+=("$alert")
    
    # Record in history
    record_alert_history "$alert"
    
    # Send alert through configured channels
    send_alert "$alert"
    
    # Check if alert should trigger auto-remediation
    check_auto_remediation "$alert"
    
    echo "$alert_id"
}

# Resolve alert
resolve_alert() {
    local alert_id="$1"
    local resolution_message="${2:-Alert resolved}"
    
    log_info "Resolving alert: $alert_id" "ALERTING"
    
    local updated_alerts=()
    local alert_found=false
    
    for alert in "${ACTIVE_ALERTS[@]}"; do
        local current_id=$(echo "$alert" | jq -r '.id')
        if [[ "$current_id" == "$alert_id" ]]; then
            # Update alert state
            alert=$(echo "$alert" | jq --arg state "$ALERT_STATE_RESOLVED" \
                --arg msg "$resolution_message" \
                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '. + {state: $state, resolved_at: $ts, resolution_message: $msg}')
            
            # Send resolution notification
            send_alert_resolution "$alert"
            
            # Record in history
            record_alert_history "$alert"
            
            alert_found=true
        else
            updated_alerts+=("$alert")
        fi
    done
    
    ACTIVE_ALERTS=("${updated_alerts[@]}")
    
    if [[ "$alert_found" != "true" ]]; then
        log_warn "Alert not found: $alert_id" "ALERTING"
        return 1
    fi
    
    return 0
}

# =============================================================================
# ALERT RULES
# =============================================================================

# Load default alert rules
load_default_alert_rules() {
    log_info "Loading default alert rules" "ALERTING"
    
    # Deployment failure rule
    add_alert_rule "deployment_failure" \
        "Deployment Failure" \
        "$ALERT_SEVERITY_CRITICAL" \
        '{"condition": "deployment_state == failed"}'
    
    # High error rate rule
    add_alert_rule "high_error_rate" \
        "High Error Rate" \
        "$ALERT_SEVERITY_ERROR" \
        '{"condition": "error_rate > 10", "window": 300}'
    
    # Resource exhaustion rule
    add_alert_rule "resource_exhaustion" \
        "Resource Exhaustion" \
        "$ALERT_SEVERITY_WARNING" \
        '{"condition": "cpu_usage > 90 or memory_usage > 90 or disk_usage > 95"}'
    
    # Service health rule
    add_alert_rule "service_unhealthy" \
        "Service Unhealthy" \
        "$ALERT_SEVERITY_ERROR" \
        '{"condition": "service_health < 100", "threshold": 2}'
    
    # Spot instance interruption rule
    add_alert_rule "spot_interruption" \
        "Spot Instance Interruption" \
        "$ALERT_SEVERITY_WARNING" \
        '{"condition": "spot_interruption_notice == true"}'
    
    # Security violation rule
    add_alert_rule "security_violation" \
        "Security Violation" \
        "$ALERT_SEVERITY_CRITICAL" \
        '{"condition": "unauthorized_access == true or security_group_modified == true"}'
}

# Add alert rule
add_alert_rule() {
    local rule_id="$1"
    local rule_name="$2"
    local severity="$3"
    local conditions="${4:-{}}"
    
    log_debug "Adding alert rule: $rule_id" "ALERTING"
    
    # Create rule object
    local rule
    rule=$(cat <<EOF
{
    "id": "$rule_id",
    "name": "$rule_name",
    "severity": "$severity",
    "enabled": true,
    "conditions": $conditions,
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    # Add to rules file
    local temp_file="${ALERT_RULES_FILE}.tmp"
    jq --argjson rule "$rule" '. += [$rule]' "$ALERT_RULES_FILE" > "$temp_file" && \
        mv "$temp_file" "$ALERT_RULES_FILE"
}

# Evaluate alert rules
evaluate_alert_rules() {
    local context="${1:-{}}"
    
    if [[ "$ALERTING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_debug "Evaluating alert rules" "ALERTING"
    
    # Get all enabled rules
    local rules=$(jq '[.[] | select(.enabled == true)]' "$ALERT_RULES_FILE")
    
    # Evaluate each rule
    local rule
    while IFS= read -r rule; do
        local rule_id=$(echo "$rule" | jq -r '.id')
        local rule_name=$(echo "$rule" | jq -r '.name')
        local severity=$(echo "$rule" | jq -r '.severity')
        local conditions=$(echo "$rule" | jq '.conditions')
        
        # Check if rule conditions are met
        if evaluate_rule_conditions "$conditions" "$context"; then
            # Check if alert already exists
            if ! is_alert_active "$rule_id"; then
                create_alert "$rule_id" "$severity" "$rule_name triggered" "rules" "$conditions"
            fi
        else
            # Check if alert should be auto-resolved
            local alert_id=$(get_active_alert_id "$rule_id")
            if [[ -n "$alert_id" ]]; then
                resolve_alert "$alert_id" "Conditions no longer met"
            fi
        fi
    done < <(echo "$rules" | jq -c '.[]')
}

# Evaluate rule conditions
evaluate_rule_conditions() {
    local conditions="$1"
    local context="$2"
    
    # This is a simplified evaluation - in production, would use a proper expression evaluator
    local condition_expr=$(echo "$conditions" | jq -r '.condition // "true"')
    
    # Extract values from context
    local deployment_state=$(echo "$context" | jq -r '.deployment_state // "unknown"')
    local error_rate=$(echo "$context" | jq -r '.error_rate // 0')
    local cpu_usage=$(echo "$context" | jq -r '.cpu_usage // 0')
    local memory_usage=$(echo "$context" | jq -r '.memory_usage // 0')
    local disk_usage=$(echo "$context" | jq -r '.disk_usage // 0')
    local service_health=$(echo "$context" | jq -r '.service_health // 100')
    
    # Simple condition evaluation
    case "$condition_expr" in
        *"deployment_state == failed"*)
            [[ "$deployment_state" == "failed" ]]
            ;;
        *"error_rate > 10"*)
            (( $(echo "$error_rate > 10" | bc -l) ))
            ;;
        *"cpu_usage > 90"*)
            (( $(echo "$cpu_usage > 90" | bc -l) ))
            ;;
        *"service_health < 100"*)
            (( $(echo "$service_health < 100" | bc -l) ))
            ;;
        *)
            false
            ;;
    esac
}

# =============================================================================
# ALERT DELIVERY
# =============================================================================

# Send alert
send_alert() {
    local alert="$1"
    
    log_info "Sending alert through configured channels" "ALERTING"
    
    # Send through each configured channel
    for channel in "${ALERT_CHANNELS[@]}"; do
        case "$channel" in
            "$ALERT_CHANNEL_LOG")
                send_alert_to_log "$alert"
                ;;
            "$ALERT_CHANNEL_CONSOLE")
                send_alert_to_console "$alert"
                ;;
            "$ALERT_CHANNEL_WEBHOOK")
                send_alert_to_webhook "$alert"
                ;;
            "$ALERT_CHANNEL_SNS")
                send_alert_to_sns "$alert"
                ;;
            "$ALERT_CHANNEL_EMAIL")
                send_alert_to_email "$alert"
                ;;
            "$ALERT_CHANNEL_SLACK")
                send_alert_to_slack "$alert"
                ;;
        esac
    done
}

# Send alert to log
send_alert_to_log() {
    local alert="$1"
    
    local severity=$(echo "$alert" | jq -r '.severity')
    local message=$(echo "$alert" | jq -r '.message')
    local component=$(echo "$alert" | jq -r '.component // ""')
    
    # Log as structured event
    log_structured_event "${severity^^}" "ALERT: $message" "alerting" "alert" "$alert"
}

# Send alert to console
send_alert_to_console() {
    local alert="$1"
    
    local severity=$(echo "$alert" | jq -r '.severity')
    local name=$(echo "$alert" | jq -r '.name')
    local message=$(echo "$alert" | jq -r '.message')
    local timestamp=$(echo "$alert" | jq -r '.timestamp')
    
    # Color based on severity
    local color
    case "$severity" in
        "$ALERT_SEVERITY_CRITICAL")
            color="\033[1;31m"  # Bold red
            ;;
        "$ALERT_SEVERITY_ERROR")
            color="\033[31m"    # Red
            ;;
        "$ALERT_SEVERITY_WARNING")
            color="\033[33m"    # Yellow
            ;;
        "$ALERT_SEVERITY_INFO")
            color="\033[36m"    # Cyan
            ;;
        *)
            color="\033[0m"     # Default
            ;;
    esac
    
    # Print alert
    echo -e "\n${color}================================================================================"
    echo -e " ALERT [$severity] - $name"
    echo -e "================================================================================"
    echo -e " Time: $timestamp"
    echo -e " Message: $message"
    echo -e "================================================================================\033[0m\n"
}

# Send alert to webhook
send_alert_to_webhook() {
    local alert="$1"
    
    if [[ -z "$ALERT_WEBHOOK_URL" ]]; then
        log_warn "Webhook URL not configured" "ALERTING"
        return 1
    fi
    
    # Send alert via curl
    curl -s -X POST "$ALERT_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$alert" || {
        log_error "Failed to send alert to webhook" "ALERTING"
        return 1
    }
}

# Send alert to SNS
send_alert_to_sns() {
    local alert="$1"
    
    if [[ -z "$ALERT_SNS_TOPIC" ]]; then
        log_warn "SNS topic not configured" "ALERTING"
        return 1
    fi
    
    local subject=$(echo "$alert" | jq -r '"[\(.severity)] \(.name)"')
    local message=$(echo "$alert" | jq -r '.message')
    
    # Send to SNS
    aws sns publish \
        --topic-arn "$ALERT_SNS_TOPIC" \
        --subject "$subject" \
        --message "$message" || {
        log_error "Failed to send alert to SNS" "ALERTING"
        return 1
    }
}

# Send alert to Slack
send_alert_to_slack() {
    local alert="$1"
    
    if [[ -z "$ALERT_SLACK_WEBHOOK" ]]; then
        log_warn "Slack webhook not configured" "ALERTING"
        return 1
    fi
    
    local severity=$(echo "$alert" | jq -r '.severity')
    local name=$(echo "$alert" | jq -r '.name')
    local message=$(echo "$alert" | jq -r '.message')
    
    # Color based on severity
    local color
    case "$severity" in
        "$ALERT_SEVERITY_CRITICAL") color="danger" ;;
        "$ALERT_SEVERITY_ERROR") color="danger" ;;
        "$ALERT_SEVERITY_WARNING") color="warning" ;;
        "$ALERT_SEVERITY_INFO") color="good" ;;
        *) color="#439FE0" ;;
    esac
    
    # Create Slack message
    local slack_message
    slack_message=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "Alert: $name",
            "text": "$message",
            "fields": [
                {
                    "title": "Severity",
                    "value": "$severity",
                    "short": true
                },
                {
                    "title": "Stack",
                    "value": "${STACK_NAME:-N/A}",
                    "short": true
                }
            ],
            "footer": "GeuseMaker Alerting",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    # Send to Slack
    curl -s -X POST "$ALERT_SLACK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$slack_message" || {
        log_error "Failed to send alert to Slack" "ALERTING"
        return 1
    }
}

# Send alert resolution
send_alert_resolution() {
    local alert="$1"
    
    log_info "Sending alert resolution notification" "ALERTING"
    
    # Update message for resolution
    alert=$(echo "$alert" | jq '.message = "RESOLVED: " + .message')
    
    # Send through configured channels
    send_alert "$alert"
}

# =============================================================================
# ALERT SILENCING
# =============================================================================

# Add silence rule
add_silence_rule() {
    local pattern="$1"
    local duration="${2:-3600}"  # Default 1 hour
    local reason="${3:-Manual silence}"
    
    log_info "Adding silence rule for pattern: $pattern" "ALERTING"
    
    local silence_rule
    silence_rule=$(cat <<EOF
{
    "pattern": "$pattern",
    "created_at": $(date +%s),
    "expires_at": $(($(date +%s) + duration)),
    "reason": "$reason"
}
EOF
)
    
    ALERT_SILENCE_RULES+=("$silence_rule")
}

# Check if alert is silenced
is_alert_silenced() {
    local alert_name="$1"
    local severity="$2"
    local component="$3"
    
    local current_time=$(date +%s)
    
    for rule in "${ALERT_SILENCE_RULES[@]}"; do
        local pattern=$(echo "$rule" | jq -r '.pattern')
        local expires_at=$(echo "$rule" | jq -r '.expires_at')
        
        # Check if rule is still active
        if [[ $current_time -lt $expires_at ]]; then
            # Check if pattern matches
            if [[ "$alert_name" =~ $pattern ]] || \
               [[ "$severity" =~ $pattern ]] || \
               [[ "$component" =~ $pattern ]]; then
                return 0
            fi
        fi
    done
    
    return 1
}

# =============================================================================
# AUTO-REMEDIATION
# =============================================================================

# Check auto-remediation
check_auto_remediation() {
    local alert="$1"
    
    local alert_name=$(echo "$alert" | jq -r '.name')
    local severity=$(echo "$alert" | jq -r '.severity')
    
    log_debug "Checking auto-remediation for alert: $alert_name" "ALERTING"
    
    # Define remediation actions
    case "$alert_name" in
        "deployment_failure")
            if [[ "$severity" == "$ALERT_SEVERITY_CRITICAL" ]]; then
                log_info "Triggering deployment rollback" "ALERTING"
                # Would trigger rollback here
            fi
            ;;
        "resource_exhaustion")
            log_info "Triggering resource cleanup" "ALERTING"
            # Would trigger cleanup here
            ;;
        "service_unhealthy")
            log_info "Triggering service restart" "ALERTING"
            # Would trigger service restart here
            ;;
    esac
}

# =============================================================================
# ALERT UTILITIES
# =============================================================================

# Get active alerts
get_active_alerts() {
    local severity_filter="${1:-}"
    local component_filter="${2:-}"
    
    if [[ ${#ACTIVE_ALERTS[@]} -eq 0 ]]; then
        echo "[]"
        return 0
    fi
    
    local filtered_alerts="[]"
    
    for alert in "${ACTIVE_ALERTS[@]}"; do
        local include=true
        
        # Apply severity filter
        if [[ -n "$severity_filter" ]]; then
            local alert_severity=$(echo "$alert" | jq -r '.severity')
            [[ "$alert_severity" != "$severity_filter" ]] && include=false
        fi
        
        # Apply component filter
        if [[ -n "$component_filter" ]]; then
            local alert_component=$(echo "$alert" | jq -r '.component // ""')
            [[ "$alert_component" != "$component_filter" ]] && include=false
        fi
        
        if [[ "$include" == "true" ]]; then
            filtered_alerts=$(echo "$filtered_alerts" | jq --argjson alert "$alert" '. += [$alert]')
        fi
    done
    
    echo "$filtered_alerts"
}

# Check if alert is active
is_alert_active() {
    local alert_name="$1"
    
    for alert in "${ACTIVE_ALERTS[@]}"; do
        local current_name=$(echo "$alert" | jq -r '.name')
        local state=$(echo "$alert" | jq -r '.state')
        if [[ "$current_name" == "$alert_name" && "$state" == "$ALERT_STATE_FIRING" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Get active alert ID
get_active_alert_id() {
    local alert_name="$1"
    
    for alert in "${ACTIVE_ALERTS[@]}"; do
        local current_name=$(echo "$alert" | jq -r '.name')
        local state=$(echo "$alert" | jq -r '.state')
        if [[ "$current_name" == "$alert_name" && "$state" == "$ALERT_STATE_FIRING" ]]; then
            echo "$alert" | jq -r '.id'
            return 0
        fi
    done
    
    return 1
}

# Record alert history
record_alert_history() {
    local alert="$1"
    
    # Add to history file
    local temp_file="${ALERT_HISTORY_FILE}.tmp"
    jq --argjson alert "$alert" '. += [$alert]' "$ALERT_HISTORY_FILE" > "$temp_file" && \
        mv "$temp_file" "$ALERT_HISTORY_FILE"
}

# Get alert history
get_alert_history() {
    local time_window="${1:-3600}"  # Default 1 hour
    local severity_filter="${2:-}"
    
    local current_time=$(date +%s)
    local start_time=$((current_time - time_window))
    
    # Filter history
    local query=".[] | select(.timestamp >= \"$start_time\")"
    [[ -n "$severity_filter" ]] && query+=" | select(.severity == \"$severity_filter\")"
    
    jq "[$query]" "$ALERT_HISTORY_FILE"
}

# Generate alert report
generate_alert_report() {
    local output_file="${1:-}"
    
    log_info "Generating alert report" "ALERTING"
    
    local report
    report=$(cat <<EOF
# Alert Report
Generated: $(date)

## Active Alerts
$(get_active_alerts | jq '.')

## Alert Summary (Last Hour)
{
    "total": $(get_alert_history 3600 | jq 'length'),
    "by_severity": $(get_alert_history 3600 | jq 'group_by(.severity) | map({key: .[0].severity, value: length}) | from_entries'),
    "by_component": $(get_alert_history 3600 | jq 'group_by(.component) | map({key: (.[0].component // "unknown"), value: length}) | from_entries')
}

## Alert Summary (Last 24 Hours)
{
    "total": $(get_alert_history 86400 | jq 'length'),
    "by_severity": $(get_alert_history 86400 | jq 'group_by(.severity) | map({key: .[0].severity, value: length}) | from_entries'),
    "by_state": $(get_alert_history 86400 | jq 'group_by(.state) | map({key: .[0].state, value: length}) | from_entries')
}

## Recent Critical Alerts
$(get_alert_history 86400 "$ALERT_SEVERITY_CRITICAL" | jq '.[-5:]')

## Alert Rules
$(cat "$ALERT_RULES_FILE" | jq '.')

## Silence Rules
$(printf '[%s]' "$(IFS=','; echo "${ALERT_SILENCE_RULES[*]}")" | jq '.')
EOF
)
    
    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        log_info "Alert report generated: $output_file" "ALERTING"
    else
        echo "$report"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup alerting
cleanup_alerting() {
    log_info "Cleaning up alerting system" "ALERTING"
    
    # Clear active alerts
    ACTIVE_ALERTS=()
    ALERT_SILENCE_RULES=()
    
    # Remove temporary files
    rm -f "$ALERT_HISTORY_FILE"
    rm -f "$ALERT_RULES_FILE"
    
    log_info "Alerting system cleanup complete" "ALERTING"
}