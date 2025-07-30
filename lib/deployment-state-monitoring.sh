#!/usr/bin/env bash
# =============================================================================
# Deployment State Monitoring and Alerting
# Real-time monitoring, health checks, and alerting for deployment states
# =============================================================================

# Prevent multiple sourcing
if [[ "${DEPLOYMENT_STATE_MONITORING_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly DEPLOYMENT_STATE_MONITORING_LIB_LOADED=true

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================

# Health check intervals (seconds)
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"
readonly CRITICAL_CHECK_INTERVAL="${CRITICAL_CHECK_INTERVAL:-30}"
readonly METRIC_COLLECTION_INTERVAL="${METRIC_COLLECTION_INTERVAL:-10}"

# Alert thresholds
declare -gA MONITORING_THRESHOLDS
aa_set MONITORING_THRESHOLDS "deployment_duration_warning" "1800"    # 30 minutes
aa_set MONITORING_THRESHOLDS "deployment_duration_critical" "3600"   # 1 hour
aa_set MONITORING_THRESHOLDS "phase_duration_warning" "600"          # 10 minutes
aa_set MONITORING_THRESHOLDS "phase_duration_critical" "1200"        # 20 minutes
aa_set MONITORING_THRESHOLDS "resource_cpu_warning" "80"             # 80% CPU
aa_set MONITORING_THRESHOLDS "resource_cpu_critical" "95"            # 95% CPU
aa_set MONITORING_THRESHOLDS "resource_memory_warning" "80"          # 80% memory
aa_set MONITORING_THRESHOLDS "resource_memory_critical" "95"         # 95% memory
aa_set MONITORING_THRESHOLDS "failure_rate_warning" "10"             # 10% failure rate
aa_set MONITORING_THRESHOLDS "failure_rate_critical" "25"            # 25% failure rate

# Monitoring state
declare -gA MONITORING_STATE
declare -gA MONITORING_ALERTS
declare -gA MONITORING_METRICS

# =============================================================================
# REAL-TIME MONITORING
# =============================================================================

# Start deployment monitoring
start_deployment_monitoring() {
    local deployment_id="$1"
    local monitoring_level="${2:-standard}"  # standard, enhanced, critical
    
    log "Starting monitoring for deployment: $deployment_id (level: $monitoring_level)"
    
    # Initialize monitoring state
    aa_set MONITORING_STATE "${deployment_id}:active" "true"
    aa_set MONITORING_STATE "${deployment_id}:level" "$monitoring_level"
    aa_set MONITORING_STATE "${deployment_id}:started_at" "$(date +%s)"
    aa_set MONITORING_STATE "${deployment_id}:last_check" "0"
    aa_set MONITORING_STATE "${deployment_id}:check_count" "0"
    aa_set MONITORING_STATE "${deployment_id}:alert_count" "0"
    
    # Schedule monitoring based on level
    case "$monitoring_level" in
        "critical")
            schedule_monitoring_task "$deployment_id" "$CRITICAL_CHECK_INTERVAL"
            ;;
        "enhanced")
            schedule_monitoring_task "$deployment_id" "$((HEALTH_CHECK_INTERVAL / 2))"
            ;;
        *)
            schedule_monitoring_task "$deployment_id" "$HEALTH_CHECK_INTERVAL"
            ;;
    esac
    
    # Start metric collection
    start_metric_collection "$deployment_id"
    
    return 0
}

# Stop deployment monitoring
stop_deployment_monitoring() {
    local deployment_id="$1"
    
    log "Stopping monitoring for deployment: $deployment_id"
    
    # Mark as inactive
    aa_set MONITORING_STATE "${deployment_id}:active" "false"
    aa_set MONITORING_STATE "${deployment_id}:stopped_at" "$(date +%s)"
    
    # Cancel scheduled tasks
    cancel_monitoring_tasks "$deployment_id"
    
    # Generate final report
    generate_monitoring_report "$deployment_id" "final"
    
    return 0
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================

# Perform deployment health check
perform_deployment_health_check() {
    local deployment_id="$1"
    local check_type="${2:-comprehensive}"  # quick, standard, comprehensive
    
    local check_start=$(date +%s)
    local health_score=100
    local issues=()
    
    # Update check count
    local check_count=$(aa_get MONITORING_STATE "${deployment_id}:check_count" "0")
    check_count=$((check_count + 1))
    aa_set MONITORING_STATE "${deployment_id}:check_count" "$check_count"
    aa_set MONITORING_STATE "${deployment_id}:last_check" "$check_start"
    
    # Check deployment status
    local status=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status" "unknown")
    local status_health=$(check_deployment_status_health "$deployment_id" "$status")
    health_score=$((health_score - (100 - status_health)))
    
    # Check duration thresholds
    local duration_health=$(check_deployment_duration_health "$deployment_id")
    health_score=$((health_score - (100 - duration_health)))
    
    # Check phase progress
    if [[ "$check_type" != "quick" ]]; then
        local phase_health=$(check_phase_progress_health "$deployment_id")
        health_score=$((health_score - (100 - phase_health)))
    fi
    
    # Check resource usage
    if [[ "$check_type" == "comprehensive" ]]; then
        local resource_health=$(check_resource_usage_health "$deployment_id")
        health_score=$((health_score - (100 - resource_health)))
    fi
    
    # Ensure score is between 0 and 100
    [[ $health_score -lt 0 ]] && health_score=0
    [[ $health_score -gt 100 ]] && health_score=100
    
    # Record health score
    aa_set MONITORING_METRICS "${deployment_id}:health_score" "$health_score"
    aa_set MONITORING_METRICS "${deployment_id}:last_health_check" "$check_start"
    
    # Trigger alerts based on health score
    if [[ $health_score -lt 50 ]]; then
        trigger_health_alert "$deployment_id" "critical" "Health score critical: $health_score%"
    elif [[ $health_score -lt 75 ]]; then
        trigger_health_alert "$deployment_id" "warning" "Health score low: $health_score%"
    fi
    
    return 0
}

# Check deployment status health
check_deployment_status_health() {
    local deployment_id="$1"
    local status="$2"
    local health=100
    
    case "$status" in
        "failed"|"rolled_back")
            health=0
            trigger_health_alert "$deployment_id" "critical" "Deployment $status"
            ;;
        "paused")
            # Check how long it's been paused
            local pause_duration=$(get_state_duration "$deployment_id" "paused")
            if [[ $pause_duration -gt 1800 ]]; then  # 30 minutes
                health=50
                trigger_health_alert "$deployment_id" "warning" "Deployment paused for ${pause_duration}s"
            else
                health=75
            fi
            ;;
        "running")
            health=100
            ;;
        "completed")
            health=100
            ;;
        *)
            health=50
            ;;
    esac
    
    echo "$health"
}

# Check deployment duration health
check_deployment_duration_health() {
    local deployment_id="$1"
    local health=100
    
    local start_time=$(aa_get DEPLOYMENT_STATES "${deployment_id}:created_at" "0")
    local current_time=$(date +%s)
    local duration=$((current_time - start_time))
    
    local warning_threshold=$(aa_get MONITORING_THRESHOLDS "deployment_duration_warning")
    local critical_threshold=$(aa_get MONITORING_THRESHOLDS "deployment_duration_critical")
    
    if [[ $duration -gt $critical_threshold ]]; then
        health=25
        trigger_health_alert "$deployment_id" "critical" "Deployment duration exceeded critical threshold: ${duration}s > ${critical_threshold}s"
    elif [[ $duration -gt $warning_threshold ]]; then
        health=75
        trigger_health_alert "$deployment_id" "warning" "Deployment duration exceeded warning threshold: ${duration}s > ${warning_threshold}s"
    fi
    
    echo "$health"
}

# Check phase progress health
check_phase_progress_health() {
    local deployment_id="$1"
    local health=100
    
    local current_phase=$(aa_get DEPLOYMENT_STATES "${deployment_id}:current_phase" "")
    if [[ -z "$current_phase" ]]; then
        echo "$health"
        return
    fi
    
    # Check phase duration
    local phase_start=$(aa_get DEPLOYMENT_PROGRESS "${deployment_id}:${current_phase}:start_time" "0")
    if [[ $phase_start -gt 0 ]]; then
        local phase_duration=$(($(date +%s) - phase_start))
        local phase_warning=$(aa_get MONITORING_THRESHOLDS "phase_duration_warning")
        local phase_critical=$(aa_get MONITORING_THRESHOLDS "phase_duration_critical")
        
        if [[ $phase_duration -gt $phase_critical ]]; then
            health=50
            trigger_health_alert "$deployment_id" "critical" "Phase $current_phase duration critical: ${phase_duration}s"
        elif [[ $phase_duration -gt $phase_warning ]]; then
            health=75
            trigger_health_alert "$deployment_id" "warning" "Phase $current_phase duration warning: ${phase_duration}s"
        fi
    fi
    
    # Check phase progress
    local phase_progress=$(aa_get DEPLOYMENT_PROGRESS "${deployment_id}:${current_phase}:progress" "0")
    if [[ $phase_progress -eq 0 ]] && [[ $phase_start -gt 0 ]]; then
        local stall_duration=$(($(date +%s) - phase_start))
        if [[ $stall_duration -gt 300 ]]; then  # 5 minutes with no progress
            health=$((health - 25))
            trigger_health_alert "$deployment_id" "warning" "Phase $current_phase stalled at 0% for ${stall_duration}s"
        fi
    fi
    
    echo "$health"
}

# Check resource usage health
check_resource_usage_health() {
    local deployment_id="$1"
    local health=100
    
    # Get resource metrics
    local cpu_usage=$(aa_get DEPLOYMENT_METRICS "${deployment_id}:cpu_usage" "0")
    local memory_usage=$(aa_get DEPLOYMENT_METRICS "${deployment_id}:memory_usage" "0")
    
    # Check CPU thresholds
    local cpu_warning=$(aa_get MONITORING_THRESHOLDS "resource_cpu_warning")
    local cpu_critical=$(aa_get MONITORING_THRESHOLDS "resource_cpu_critical")
    
    if [[ $(echo "$cpu_usage > $cpu_critical" | bc -l) -eq 1 ]]; then
        health=$((health - 50))
        trigger_health_alert "$deployment_id" "critical" "CPU usage critical: ${cpu_usage}%"
    elif [[ $(echo "$cpu_usage > $cpu_warning" | bc -l) -eq 1 ]]; then
        health=$((health - 25))
        trigger_health_alert "$deployment_id" "warning" "CPU usage high: ${cpu_usage}%"
    fi
    
    # Check memory thresholds
    local mem_warning=$(aa_get MONITORING_THRESHOLDS "resource_memory_warning")
    local mem_critical=$(aa_get MONITORING_THRESHOLDS "resource_memory_critical")
    
    if [[ $(echo "$memory_usage > $mem_critical" | bc -l) -eq 1 ]]; then
        health=$((health - 50))
        trigger_health_alert "$deployment_id" "critical" "Memory usage critical: ${memory_usage}%"
    elif [[ $(echo "$memory_usage > $mem_warning" | bc -l) -eq 1 ]]; then
        health=$((health - 25))
        trigger_health_alert "$deployment_id" "warning" "Memory usage high: ${memory_usage}%"
    fi
    
    echo "$health"
}

# =============================================================================
# METRIC COLLECTION
# =============================================================================

# Start metric collection
start_metric_collection() {
    local deployment_id="$1"
    
    # Initialize metric collection
    aa_set MONITORING_METRICS "${deployment_id}:collection_active" "true"
    aa_set MONITORING_METRICS "${deployment_id}:collection_started" "$(date +%s)"
    
    # Schedule metric collection
    (
        while [[ "$(aa_get MONITORING_METRICS "${deployment_id}:collection_active")" == "true" ]]; do
            collect_deployment_metrics "$deployment_id"
            sleep "$METRIC_COLLECTION_INTERVAL"
        done
    ) &
    
    local collection_pid=$!
    aa_set MONITORING_STATE "${deployment_id}:collection_pid" "$collection_pid"
}

# Collect deployment metrics
collect_deployment_metrics() {
    local deployment_id="$1"
    local timestamp=$(date +%s)
    
    # Collect phase metrics
    local current_phase=$(aa_get DEPLOYMENT_STATES "${deployment_id}:current_phase" "")
    if [[ -n "$current_phase" ]]; then
        local phase_progress=$(aa_get DEPLOYMENT_PROGRESS "${deployment_id}:${current_phase}:progress" "0")
        record_metric "$deployment_id" "phase_progress" "$phase_progress" "$timestamp"
    fi
    
    # Collect overall progress
    local overall_progress=$(aa_get DEPLOYMENT_STATES "${deployment_id}:overall_progress" "0")
    record_metric "$deployment_id" "overall_progress" "$overall_progress" "$timestamp"
    
    # Collect resource metrics (simulated - would be actual in production)
    if command -v ps >/dev/null 2>&1; then
        # Simulate CPU usage
        local cpu_usage=$(echo "scale=2; $RANDOM % 100" | bc -l)
        record_metric "$deployment_id" "cpu_usage" "$cpu_usage" "$timestamp"
        
        # Simulate memory usage
        local memory_usage=$(echo "scale=2; $RANDOM % 100" | bc -l)
        record_metric "$deployment_id" "memory_usage" "$memory_usage" "$timestamp"
    fi
    
    # Calculate and record derived metrics
    calculate_derived_metrics "$deployment_id"
}

# Record metric
record_metric() {
    local deployment_id="$1"
    local metric_name="$2"
    local metric_value="$3"
    local timestamp="${4:-$(date +%s)}"
    
    # Store current value
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${metric_name}" "$metric_value"
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${metric_name}_timestamp" "$timestamp"
    
    # Store in time series (last 100 values)
    local series_key="${deployment_id}:${metric_name}_series"
    local current_series=$(aa_get MONITORING_METRICS "$series_key" "")
    
    # Append new value (timestamp:value format)
    current_series="${current_series}${timestamp}:${metric_value},"
    
    # Trim to last 100 values
    local value_count=$(echo "$current_series" | tr ',' '\n' | wc -l)
    if [[ $value_count -gt 100 ]]; then
        current_series=$(echo "$current_series" | tr ',' '\n' | tail -100 | tr '\n' ',')
    fi
    
    aa_set MONITORING_METRICS "$series_key" "$current_series"
}

# Calculate derived metrics
calculate_derived_metrics() {
    local deployment_id="$1"
    
    # Calculate deployment velocity (progress per minute)
    local series_key="${deployment_id}:overall_progress_series"
    local progress_series=$(aa_get MONITORING_METRICS "$series_key" "")
    
    if [[ -n "$progress_series" ]]; then
        # Get first and last values
        local first_entry=$(echo "$progress_series" | tr ',' '\n' | head -1)
        local last_entry=$(echo "$progress_series" | tr ',' '\n' | grep -v '^$' | tail -1)
        
        if [[ -n "$first_entry" && -n "$last_entry" ]]; then
            local first_time="${first_entry%%:*}"
            local first_progress="${first_entry##*:}"
            local last_time="${last_entry%%:*}"
            local last_progress="${last_entry##*:}"
            
            if [[ $last_time -gt $first_time ]]; then
                local time_diff=$((last_time - first_time))
                local progress_diff=$(echo "$last_progress - $first_progress" | bc -l)
                local velocity=$(echo "scale=2; $progress_diff / ($time_diff / 60)" | bc -l)
                
                record_metric "$deployment_id" "velocity" "$velocity"
            fi
        fi
    fi
    
    # Calculate estimated time to completion
    local current_progress=$(aa_get DEPLOYMENT_STATES "${deployment_id}:overall_progress" "0")
    local velocity=$(aa_get DEPLOYMENT_METRICS "${deployment_id}:velocity" "0")
    
    if [[ $(echo "$velocity > 0" | bc -l) -eq 1 ]] && [[ $(echo "$current_progress < 100" | bc -l) -eq 1 ]]; then
        local remaining_progress=$(echo "100 - $current_progress" | bc -l)
        local eta_minutes=$(echo "scale=0; $remaining_progress / $velocity" | bc -l)
        record_metric "$deployment_id" "eta_minutes" "$eta_minutes"
    fi
}

# =============================================================================
# ALERTING SYSTEM
# =============================================================================

# Trigger health alert
trigger_health_alert() {
    local deployment_id="$1"
    local severity="$2"      # info, warning, critical
    local message="$3"
    local timestamp=$(date +%s)
    
    # Check if alert is already active (deduplication)
    local alert_key="${deployment_id}:${severity}:$(echo "$message" | md5sum | cut -d' ' -f1)"
    local last_alert_time=$(aa_get MONITORING_ALERTS "${alert_key}:last_triggered" "0")
    
    # Suppress duplicate alerts within 5 minutes
    if [[ $((timestamp - last_alert_time)) -lt 300 ]]; then
        return 0
    fi
    
    # Record alert
    aa_set MONITORING_ALERTS "${alert_key}:deployment_id" "$deployment_id"
    aa_set MONITORING_ALERTS "${alert_key}:severity" "$severity"
    aa_set MONITORING_ALERTS "${alert_key}:message" "$message"
    aa_set MONITORING_ALERTS "${alert_key}:last_triggered" "$timestamp"
    aa_set MONITORING_ALERTS "${alert_key}:count" "$(($(aa_get MONITORING_ALERTS "${alert_key}:count" "0") + 1))"
    
    # Update alert count
    local alert_count=$(aa_get MONITORING_STATE "${deployment_id}:alert_count" "0")
    alert_count=$((alert_count + 1))
    aa_set MONITORING_STATE "${deployment_id}:alert_count" "$alert_count"
    
    # Log alert
    log "[$severity] Alert for $deployment_id: $message"
    
    # Trigger alert actions based on severity
    case "$severity" in
        "critical")
            handle_critical_alert "$deployment_id" "$message"
            ;;
        "warning")
            handle_warning_alert "$deployment_id" "$message"
            ;;
        "info")
            handle_info_alert "$deployment_id" "$message"
            ;;
    esac
    
    # Send notifications
    send_alert_notifications "$deployment_id" "$severity" "$message"
}

# Handle critical alerts
handle_critical_alert() {
    local deployment_id="$1"
    local message="$2"
    
    # Check if auto-remediation is enabled
    local auto_remediate=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:auto_remediate" "false")
    
    if [[ "$auto_remediate" == "true" ]]; then
        log "Attempting auto-remediation for critical alert: $message"
        attempt_auto_remediation "$deployment_id" "$message"
    fi
    
    # Escalate monitoring level
    aa_set MONITORING_STATE "${deployment_id}:level" "critical"
    
    # Increase check frequency
    reschedule_monitoring_task "$deployment_id" "$CRITICAL_CHECK_INTERVAL"
}

# Handle warning alerts
handle_warning_alert() {
    local deployment_id="$1"
    local message="$2"
    
    # Upgrade monitoring level if not already enhanced
    local current_level=$(aa_get MONITORING_STATE "${deployment_id}:level" "standard")
    if [[ "$current_level" == "standard" ]]; then
        aa_set MONITORING_STATE "${deployment_id}:level" "enhanced"
        reschedule_monitoring_task "$deployment_id" "$((HEALTH_CHECK_INTERVAL / 2))"
    fi
}

# Handle info alerts
handle_info_alert() {
    local deployment_id="$1"
    local message="$2"
    
    # Just log for now
    log "Info alert for $deployment_id: $message"
}

# Attempt auto-remediation
attempt_auto_remediation() {
    local deployment_id="$1"
    local issue="$2"
    
    # Implement remediation strategies based on issue
    case "$issue" in
        *"stalled"*)
            log "Attempting to restart stalled phase"
            # Logic to restart phase
            ;;
        *"resource"*"critical"*)
            log "Attempting to scale resources"
            # Logic to scale resources
            ;;
        *"duration exceeded"*)
            log "Checking for stuck processes"
            # Logic to check and fix stuck processes
            ;;
    esac
}

# Send alert notifications
send_alert_notifications() {
    local deployment_id="$1"
    local severity="$2"
    local message="$3"
    
    # Check if notifications are enabled
    local notifications_enabled=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:notifications_enabled" "false")
    if [[ "$notifications_enabled" != "true" ]]; then
        return 0
    fi
    
    # Get notification configuration
    local webhook_url=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:alert_webhook_url" "")
    if [[ -z "$webhook_url" ]]; then
        webhook_url="$STATE_ALERT_WEBHOOK_URL"
    fi
    
    if [[ -n "$webhook_url" ]] && command -v curl >/dev/null 2>&1; then
        local payload=$(cat <<EOF
{
    "deployment_id": "$deployment_id",
    "severity": "$severity",
    "message": "$message",
    "timestamp": $(date +%s),
    "metrics": {
        "health_score": $(aa_get MONITORING_METRICS "${deployment_id}:health_score" "0"),
        "overall_progress": $(aa_get DEPLOYMENT_STATES "${deployment_id}:overall_progress" "0"),
        "alert_count": $(aa_get MONITORING_STATE "${deployment_id}:alert_count" "0")
    }
}
EOF
)
        
        curl -s -X POST "$webhook_url" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1 || true
    fi
}

# =============================================================================
# MONITORING REPORTS
# =============================================================================

# Generate monitoring report
generate_monitoring_report() {
    local deployment_id="$1"
    local report_type="${2:-summary}"  # summary, detailed, final
    
    case "$report_type" in
        "summary")
            generate_summary_monitoring_report "$deployment_id"
            ;;
        "detailed")
            generate_detailed_monitoring_report "$deployment_id"
            ;;
        "final")
            generate_final_monitoring_report "$deployment_id"
            ;;
    esac
}

# Generate summary monitoring report
generate_summary_monitoring_report() {
    local deployment_id="$1"
    
    cat <<EOF
=== Monitoring Summary: $deployment_id ===
Status: $(aa_get DEPLOYMENT_STATES "${deployment_id}:status" "unknown")
Health Score: $(aa_get MONITORING_METRICS "${deployment_id}:health_score" "0")%
Progress: $(aa_get DEPLOYMENT_STATES "${deployment_id}:overall_progress" "0")%
Alerts: $(aa_get MONITORING_STATE "${deployment_id}:alert_count" "0")
Monitoring Level: $(aa_get MONITORING_STATE "${deployment_id}:level" "standard")
Last Check: $(date -d @$(aa_get MONITORING_STATE "${deployment_id}:last_check" "0") 2>/dev/null || echo "Never")
=========================================
EOF
}

# Generate detailed monitoring report
generate_detailed_monitoring_report() {
    local deployment_id="$1"
    
    # Summary section
    generate_summary_monitoring_report "$deployment_id"
    
    # Metrics section
    echo ""
    echo "=== Current Metrics ==="
    echo "CPU Usage: $(aa_get DEPLOYMENT_METRICS "${deployment_id}:cpu_usage" "N/A")%"
    echo "Memory Usage: $(aa_get DEPLOYMENT_METRICS "${deployment_id}:memory_usage" "N/A")%"
    echo "Velocity: $(aa_get DEPLOYMENT_METRICS "${deployment_id}:velocity" "N/A")% per minute"
    echo "ETA: $(aa_get DEPLOYMENT_METRICS "${deployment_id}:eta_minutes" "N/A") minutes"
    
    # Alert history
    echo ""
    echo "=== Recent Alerts ==="
    for alert_key in $(aa_keys MONITORING_ALERTS); do
        if [[ "$alert_key" =~ ^${deployment_id}: ]] && [[ "$alert_key" =~ :severity$ ]]; then
            local alert_id="${alert_key%:severity}"
            local severity=$(aa_get MONITORING_ALERTS "${alert_key}")
            local message=$(aa_get MONITORING_ALERTS "${alert_id}:message" "")
            local count=$(aa_get MONITORING_ALERTS "${alert_id}:count" "1")
            echo "[$severity] $message (count: $count)"
        fi
    done
}

# Generate final monitoring report
generate_final_monitoring_report() {
    local deployment_id="$1"
    
    local started_at=$(aa_get MONITORING_STATE "${deployment_id}:started_at" "0")
    local stopped_at=$(aa_get MONITORING_STATE "${deployment_id}:stopped_at" "$(date +%s)")
    local duration=$((stopped_at - started_at))
    
    cat <<EOF
=== Final Monitoring Report: $deployment_id ===
Monitoring Duration: ${duration}s
Total Health Checks: $(aa_get MONITORING_STATE "${deployment_id}:check_count" "0")
Total Alerts: $(aa_get MONITORING_STATE "${deployment_id}:alert_count" "0")
Final Health Score: $(aa_get MONITORING_METRICS "${deployment_id}:health_score" "0")%
Final Status: $(aa_get DEPLOYMENT_STATES "${deployment_id}:status" "unknown")

Alert Summary:
- Critical: $(count_alerts_by_severity "$deployment_id" "critical")
- Warning: $(count_alerts_by_severity "$deployment_id" "warning")
- Info: $(count_alerts_by_severity "$deployment_id" "info")

Performance Metrics:
- Average CPU: $(calculate_average_metric "$deployment_id" "cpu_usage")%
- Average Memory: $(calculate_average_metric "$deployment_id" "memory_usage")%
- Average Velocity: $(calculate_average_metric "$deployment_id" "velocity")% per minute
==============================================
EOF
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get state duration
get_state_duration() {
    local deployment_id="$1"
    local state="$2"
    
    local entered_at=$(aa_get DEPLOYMENT_TRANSITIONS "${deployment_id}:${state}_entered_at" "0")
    if [[ $entered_at -eq 0 ]]; then
        echo "0"
        return
    fi
    
    echo $(($(date +%s) - entered_at))
}

# Count alerts by severity
count_alerts_by_severity() {
    local deployment_id="$1"
    local severity="$2"
    local count=0
    
    for alert_key in $(aa_keys MONITORING_ALERTS); do
        if [[ "$alert_key" =~ ^${deployment_id}: ]] && [[ "$alert_key" =~ :severity$ ]]; then
            local alert_severity=$(aa_get MONITORING_ALERTS "$alert_key")
            if [[ "$alert_severity" == "$severity" ]]; then
                count=$((count + 1))
            fi
        fi
    done
    
    echo "$count"
}

# Calculate average metric
calculate_average_metric() {
    local deployment_id="$1"
    local metric_name="$2"
    
    local series_key="${deployment_id}:${metric_name}_series"
    local series=$(aa_get MONITORING_METRICS "$series_key" "")
    
    if [[ -z "$series" ]]; then
        echo "0"
        return
    fi
    
    local sum=0
    local count=0
    
    IFS=',' read -ra values <<< "$series"
    for entry in "${values[@]}"; do
        if [[ -n "$entry" ]] && [[ "$entry" =~ : ]]; then
            local value="${entry##*:}"
            sum=$(echo "$sum + $value" | bc -l)
            count=$((count + 1))
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        echo "scale=2; $sum / $count" | bc -l
    else
        echo "0"
    fi
}

# Schedule monitoring task
schedule_monitoring_task() {
    local deployment_id="$1"
    local interval="$2"
    
    # This would implement actual task scheduling
    # For now, just record the configuration
    aa_set MONITORING_STATE "${deployment_id}:check_interval" "$interval"
}

# Reschedule monitoring task
reschedule_monitoring_task() {
    local deployment_id="$1"
    local new_interval="$2"
    
    cancel_monitoring_tasks "$deployment_id"
    schedule_monitoring_task "$deployment_id" "$new_interval"
}

# Cancel monitoring tasks
cancel_monitoring_tasks() {
    local deployment_id="$1"
    
    # Stop metric collection
    aa_set MONITORING_METRICS "${deployment_id}:collection_active" "false"
    
    # Kill collection process if exists
    local collection_pid=$(aa_get MONITORING_STATE "${deployment_id}:collection_pid" "")
    if [[ -n "$collection_pid" ]] && kill -0 "$collection_pid" 2>/dev/null; then
        kill "$collection_pid" 2>/dev/null || true
    fi
}

# =============================================================================
# LIBRARY EXPORTS
# =============================================================================

# Export all functions
export -f start_deployment_monitoring stop_deployment_monitoring
export -f perform_deployment_health_check check_deployment_status_health
export -f check_deployment_duration_health check_phase_progress_health check_resource_usage_health
export -f start_metric_collection collect_deployment_metrics record_metric calculate_derived_metrics
export -f trigger_health_alert handle_critical_alert handle_warning_alert handle_info_alert
export -f attempt_auto_remediation send_alert_notifications
export -f generate_monitoring_report generate_summary_monitoring_report
export -f generate_detailed_monitoring_report generate_final_monitoring_report
export -f get_state_duration count_alerts_by_severity calculate_average_metric
export -f schedule_monitoring_task reschedule_monitoring_task cancel_monitoring_tasks

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "Deployment State Monitoring library loaded"
fi