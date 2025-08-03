#!/bin/bash
# Unity Monitor Service - Unified monitoring and observability

# Service metadata
SERVICE_NAME="monitor"
SERVICE_VERSION="1.0.0"
SERVICE_DESCRIPTION="Unified monitoring, metrics, and alerting"

# Monitor service state
MONITOR_SERVICE_INITIALIZED=false
MONITOR_METRICS_DIR=".unity/metrics"
MONITOR_ALERTS_DIR=".unity/alerts"
declare -A MONITOR_METRICS 2>/dev/null || MONITOR_METRICS=()
declare -A MONITOR_THRESHOLDS 2>/dev/null || MONITOR_THRESHOLDS=()

# Initialize Monitor service
init_monitor_service() {
    unity_log "INFO" "Initializing Monitor service..."
    
    # Create directories
    mkdir -p "$MONITOR_METRICS_DIR" "$MONITOR_ALERTS_DIR"
    
    # Set default thresholds
    set_default_thresholds
    
    # Register event handlers for monitoring
    unity_on_event "SERVICE_UNHEALTHY" handle_service_unhealthy
    unity_on_event "CONTAINER_UNHEALTHY" handle_container_unhealthy
    unity_on_event "QUOTA_WARNING" handle_quota_warning
    unity_on_event "COST_THRESHOLD_EXCEEDED" handle_cost_threshold
    
    MONITOR_SERVICE_INITIALIZED=true
    unity_log "INFO" "Monitor service initialized successfully"
    return $UNITY_SUCCESS
}

# Start Monitor service
start_monitor_service() {
    if [[ "$MONITOR_SERVICE_INITIALIZED" != "true" ]]; then
        unity_log "ERROR" "Monitor service not initialized"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    unity_log "INFO" "Starting Monitor service..."
    
    # Start metrics collection
    collect_system_metrics &
    
    # Start health monitoring
    monitor_system_health &
    
    unity_emit_event "SERVICE_STARTED" "monitor" ""
    return $UNITY_SUCCESS
}

# Stop Monitor service
stop_monitor_service() {
    unity_log "INFO" "Stopping Monitor service..."
    
    # Stop background processes
    pkill -f "collect_system_metrics" 2>/dev/null || true
    pkill -f "monitor_system_health" 2>/dev/null || true
    
    unity_emit_event "SERVICE_STOPPED" "monitor" ""
    return $UNITY_SUCCESS
}

# Check Monitor service health
health_monitor_service() {
    local health_status="healthy"
    local health_details=""
    
    # Check metrics directory
    if [[ ! -d "$MONITOR_METRICS_DIR" ]]; then
        health_status="degraded"
        health_details="Metrics directory missing"
    fi
    
    # Check if metrics are being collected
    local latest_metric=$(find "$MONITOR_METRICS_DIR" -type f -name "*.metric" -mmin -5 2>/dev/null | head -1)
    if [[ -z "$latest_metric" ]]; then
        health_status="degraded"
        health_details="${health_details}; No recent metrics"
    fi
    
    echo "$health_status|$health_details"
    
    if [[ "$health_status" == "unhealthy" ]]; then
        unity_emit_event "SERVICE_UNHEALTHY" "monitor" "$health_details"
        return $UNITY_ERROR_EXECUTION
    fi
    
    return $UNITY_SUCCESS
}

# Configure Monitor service
config_monitor_service() {
    local action="${1:-get}"
    local key="$2"
    local value="$3"
    
    case "$action" in
        get)
            if [[ -z "$key" ]]; then
                # Return all configuration
                echo "metrics_interval=${MONITOR_METRICS_INTERVAL:-60}"
                echo "health_check_interval=${MONITOR_HEALTH_INTERVAL:-30}"
                echo "retention_days=${MONITOR_RETENTION_DAYS:-30}"
            else
                # Return specific configuration
                case "$key" in
                    metrics_interval) echo "${MONITOR_METRICS_INTERVAL:-60}" ;;
                    health_check_interval) echo "${MONITOR_HEALTH_INTERVAL:-30}" ;;
                    retention_days) echo "${MONITOR_RETENTION_DAYS:-30}" ;;
                    threshold_*) get_threshold "${key#threshold_}" ;;
                    *) unity_log "WARN" "Unknown configuration key: $key" ;;
                esac
            fi
            ;;
            
        set)
            if [[ -z "$key" || -z "$value" ]]; then
                unity_log "ERROR" "Configuration key and value required"
                return $UNITY_ERROR_VALIDATION
            fi
            
            case "$key" in
                metrics_interval)
                    MONITOR_METRICS_INTERVAL="$value"
                    unity_log "INFO" "Set metrics interval to: $value"
                    ;;
                health_check_interval)
                    MONITOR_HEALTH_INTERVAL="$value"
                    unity_log "INFO" "Set health check interval to: $value"
                    ;;
                retention_days)
                    MONITOR_RETENTION_DAYS="$value"
                    unity_log "INFO" "Set retention days to: $value"
                    ;;
                threshold_*)
                    set_threshold "${key#threshold_}" "$value"
                    ;;
                *)
                    unity_log "ERROR" "Unknown configuration key: $key"
                    return $UNITY_ERROR_VALIDATION
                    ;;
            esac
            
            unity_emit_event "CONFIG_UPDATED" "monitor" "$key=$value"
            ;;
            
        *)
            unity_log "ERROR" "Unknown action: $action"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# Monitor-specific functions

# Set default thresholds
set_default_thresholds() {
    set_threshold "cpu_percent" "80"
    set_threshold "memory_percent" "90"
    set_threshold "disk_percent" "90"
    set_threshold "container_restart_count" "5"
    set_threshold "error_rate_per_minute" "10"
    set_threshold "cost_daily_usd" "100"
}

# Get threshold value
get_threshold() {
    local metric="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${MONITOR_THRESHOLDS[$metric]:-0}"
    else
        local var_name="MONITOR_THRESHOLD_${metric}"
        echo "${!var_name:-0}"
    fi
}

# Set threshold value
set_threshold() {
    local metric="$1"
    local value="$2"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        MONITOR_THRESHOLDS["$metric"]="$value"
    else
        local var_name="MONITOR_THRESHOLD_${metric}"
        eval "$var_name='$value'"
    fi
    
    unity_log "INFO" "Set threshold: $metric = $value"
}

# Collect system metrics
collect_system_metrics() {
    local interval="${MONITOR_METRICS_INTERVAL:-60}"
    
    while true; do
        unity_log "DEBUG" "Collecting system metrics..."
        
        local timestamp=$(date +%s)
        local metrics_file="$MONITOR_METRICS_DIR/${timestamp}.metric"
        
        {
            echo "timestamp=$timestamp"
            
            # CPU usage
            if command -v top >/dev/null 2>&1; then
                local cpu_usage=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "0")
                echo "cpu_percent=$cpu_usage"
                record_metric "cpu_percent" "$cpu_usage"
            fi
            
            # Memory usage
            if command -v free >/dev/null 2>&1; then
                local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
                echo "memory_percent=$memory_usage"
                record_metric "memory_percent" "$memory_usage"
            elif command -v vm_stat >/dev/null 2>&1; then
                # macOS
                local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
                local pages_active=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
                local pages_inactive=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
                local pages_wired=$(vm_stat | grep "Pages wired" | awk '{print $4}' | sed 's/\.//')
                local total_pages=$((pages_free + pages_active + pages_inactive + pages_wired))
                local used_pages=$((pages_active + pages_wired))
                local memory_usage=$((used_pages * 100 / total_pages))
                echo "memory_percent=$memory_usage"
                record_metric "memory_percent" "$memory_usage"
            fi
            
            # Disk usage
            local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
            echo "disk_percent=$disk_usage"
            record_metric "disk_percent" "$disk_usage"
            
            # Docker container count
            if command -v docker >/dev/null 2>&1; then
                local container_count=$(docker ps -q | wc -l)
                echo "container_count=$container_count"
                record_metric "container_count" "$container_count"
            fi
            
            # Service statuses
            for service in $(unity_list_services | grep "^  -" | awk '{print $2}' | sed 's/://'); do
                local status
                if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
                    status="${UNITY_SERVICE_STATUS[$service]:-unknown}"
                else
                    local status_var="UNITY_SERVICE_${service}_STATUS"
                    status="${!status_var:-unknown}"
                fi
                echo "service_${service}_status=$status"
            done
            
        } > "$metrics_file"
        
        # Check thresholds
        check_metric_thresholds
        
        # Clean old metrics
        find "$MONITOR_METRICS_DIR" -name "*.metric" -mtime +${MONITOR_RETENTION_DAYS:-30} -delete 2>/dev/null || true
        
        sleep "$interval"
    done
}

# Monitor system health
monitor_system_health() {
    local interval="${MONITOR_HEALTH_INTERVAL:-30}"
    
    while true; do
        unity_log "DEBUG" "Checking system health..."
        
        # Check all services
        for service in $(unity_list_services | grep "^  -" | awk '{print $2}' | sed 's/://'); do
            if type -t "health_${service}_service" >/dev/null 2>&1; then
                local health_result=$("health_${service}_service" 2>&1)
                local health_status="${health_result%%|*}"
                local health_details="${health_result#*|}"
                
                if [[ "$health_status" != "healthy" ]]; then
                    unity_log "WARN" "Service $service is $health_status: $health_details"
                    create_alert "service_health" "$service is $health_status" "high"
                fi
            fi
        done
        
        sleep "$interval"
    done
}

# Record metric value
record_metric() {
    local metric_name="$1"
    local metric_value="$2"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        MONITOR_METRICS["$metric_name"]="$metric_value"
    else
        local var_name="MONITOR_METRIC_${metric_name}"
        eval "$var_name='$metric_value'"
    fi
}

# Check metric thresholds
check_metric_thresholds() {
    unity_log "DEBUG" "Checking metric thresholds..."
    
    # Check CPU
    local cpu_usage=$(get_metric_value "cpu_percent")
    local cpu_threshold=$(get_threshold "cpu_percent")
    if [[ -n "$cpu_usage" && "$cpu_usage" -gt "$cpu_threshold" ]]; then
        create_alert "cpu_high" "CPU usage at ${cpu_usage}%" "medium"
    fi
    
    # Check Memory
    local memory_usage=$(get_metric_value "memory_percent")
    local memory_threshold=$(get_threshold "memory_percent")
    if [[ -n "$memory_usage" && "$memory_usage" -gt "$memory_threshold" ]]; then
        create_alert "memory_high" "Memory usage at ${memory_usage}%" "high"
    fi
    
    # Check Disk
    local disk_usage=$(get_metric_value "disk_percent")
    local disk_threshold=$(get_threshold "disk_percent")
    if [[ -n "$disk_usage" && "$disk_usage" -gt "$disk_threshold" ]]; then
        create_alert "disk_high" "Disk usage at ${disk_usage}%" "high"
    fi
}

# Get metric value
get_metric_value() {
    local metric_name="$1"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${MONITOR_METRICS[$metric_name]:-}"
    else
        local var_name="MONITOR_METRIC_${metric_name}"
        echo "${!var_name:-}"
    fi
}

# Create alert
create_alert() {
    local alert_type="$1"
    local alert_message="$2"
    local severity="${3:-medium}"
    local timestamp=$(date +%s)
    
    local alert_file="$MONITOR_ALERTS_DIR/${timestamp}_${alert_type}.alert"
    
    {
        echo "timestamp=$timestamp"
        echo "type=$alert_type"
        echo "message=$alert_message"
        echo "severity=$severity"
    } > "$alert_file"
    
    unity_log "WARN" "Alert: [$severity] $alert_message"
    unity_emit_event "ALERT_CREATED" "monitor" "$alert_type:$severity:$alert_message"
    
    # Send to configured channels
    send_alert_notifications "$alert_type" "$alert_message" "$severity"
}

# Send alert notifications
send_alert_notifications() {
    local alert_type="$1"
    local alert_message="$2"
    local severity="$3"
    
    # Log channel (always enabled)
    unity_log "ALERT" "[$severity] $alert_type: $alert_message"
    
    # Webhook channel
    local webhook_url=$(get_config_value "WEBHOOK_URL")
    if [[ -n "$webhook_url" && "$severity" == "critical" ]]; then
        send_webhook_alert "$webhook_url" "$alert_type" "$alert_message" "$severity"
    fi
}

# Send webhook alert
send_webhook_alert() {
    local webhook_url="$1"
    local alert_type="$2"
    local alert_message="$3"
    local severity="$4"
    
    if command -v curl >/dev/null 2>&1; then
        local payload=$(cat <<EOF
{
    "alert_type": "$alert_type",
    "message": "$alert_message",
    "severity": "$severity",
    "timestamp": "$(date -Iseconds)",
    "source": "unity-monitor"
}
EOF
)
        
        curl -s -X POST "$webhook_url" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            >/dev/null 2>&1 || unity_log "WARN" "Failed to send webhook alert"
    fi
}

# Event handlers
handle_service_unhealthy() {
    local event="$1"
    local service="$2"
    local details="$3"
    
    create_alert "service_unhealthy" "Service $service is unhealthy: $details" "high"
}

handle_container_unhealthy() {
    local event="$1"
    local container="$2"
    
    create_alert "container_unhealthy" "Container $container is unhealthy" "medium"
}

handle_quota_warning() {
    local event="$1"
    local service="$2"
    local details="$3"
    
    create_alert "quota_warning" "$details" "medium"
}

handle_cost_threshold() {
    local event="$1"
    local service="$2"
    local details="$3"
    
    create_alert "cost_threshold" "Cost threshold exceeded: $details" "high"
}

# Generate metrics report
generate_metrics_report() {
    local report_type="${1:-daily}"
    local output_file="${2:-$MONITOR_METRICS_DIR/report_$(date +%Y%m%d).txt}"
    
    unity_log "INFO" "Generating $report_type metrics report..."
    
    {
        echo "Unity Metrics Report"
        echo "==================="
        echo "Generated: $(date)"
        echo "Report Type: $report_type"
        echo ""
        
        echo "Service Status:"
        echo "--------------"
        unity_list_services
        echo ""
        
        echo "System Metrics:"
        echo "--------------"
        echo "CPU Usage: $(get_metric_value cpu_percent)%"
        echo "Memory Usage: $(get_metric_value memory_percent)%"
        echo "Disk Usage: $(get_metric_value disk_percent)%"
        echo "Container Count: $(get_metric_value container_count)"
        echo ""
        
        echo "Recent Alerts:"
        echo "-------------"
        find "$MONITOR_ALERTS_DIR" -name "*.alert" -mtime -1 -exec basename {} \; | head -10
        
    } > "$output_file"
    
    unity_log "INFO" "Report generated: $output_file"
    return $UNITY_SUCCESS
}

# Export service functions
export -f init_monitor_service
export -f start_monitor_service
export -f stop_monitor_service
export -f health_monitor_service
export -f config_monitor_service
export -f collect_system_metrics
export -f monitor_system_health
export -f record_metric
export -f get_metric_value
export -f check_metric_thresholds
export -f create_alert
export -f send_alert_notifications
export -f generate_metrics_report
export -f get_threshold
export -f set_threshold