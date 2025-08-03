#!/bin/bash
# Unity Monitoring Service - Complete implementation with CloudWatch integration
# Provides real-time metrics, alerts, dashboards, and comprehensive monitoring

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || {
    echo "Error: Failed to load Unity core" >&2
    exit 1
}

# Service metadata
SERVICE_NAME="unity-monitoring"
SERVICE_VERSION="1.0.0"
SERVICE_TYPE="monitoring"

# Monitoring configuration
MONITORING_NAMESPACE="Unity/GeuseMaker"
MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"  # seconds
MONITORING_RETENTION="${MONITORING_RETENTION:-7}"  # days
MONITORING_PID=""

# Metric types
declare -A METRIC_DEFINITIONS
METRIC_DEFINITIONS=(
    ["ServiceHealth"]="Average|Percent|0-100"
    ["EventLatency"]="Average|Milliseconds|0-10000"
    ["DeploymentTime"]="Average|Seconds|0-3600"
    ["ResourceCount"]="Sum|Count|0-1000"
    ["ErrorRate"]="Average|Percent|0-100"
    ["CostPerHour"]="Average|USD|0-1000"
    ["CPUUtilization"]="Average|Percent|0-100"
    ["MemoryUtilization"]="Average|Percent|0-100"
    ["DiskUtilization"]="Average|Percent|0-100"
    ["NetworkThroughput"]="Average|Bytes/Second|0-1000000000"
)

# Alert thresholds
declare -A ALERT_THRESHOLDS
ALERT_THRESHOLDS=(
    ["ServiceHealth"]="<80:warning,<50:critical"
    ["EventLatency"]=">1000:warning,>5000:critical"
    ["ErrorRate"]=">5:warning,>10:critical"
    ["CostPerHour"]=">100:warning,>500:critical"
    ["CPUUtilization"]=">80:warning,>90:critical"
    ["MemoryUtilization"]=">80:warning,>90:critical"
    ["DiskUtilization"]=">80:warning,>90:critical"
)

# Initialize monitoring service
init_unity_monitoring_service() {
    unity_log "INFO" "Initializing Unity Monitoring Service v$SERVICE_VERSION"
    
    # Create monitoring directories
    mkdir -p "$PROJECT_ROOT/.unity/monitoring/metrics"
    mkdir -p "$PROJECT_ROOT/.unity/monitoring/alerts"
    mkdir -p "$PROJECT_ROOT/.unity/monitoring/dashboards"
    mkdir -p "$PROJECT_ROOT/logs/unity/monitoring"
    
    # Initialize CloudWatch namespace
    if ! setup_cloudwatch_namespace; then
        unity_log "WARN" "CloudWatch setup failed, using local monitoring only"
    fi
    
    # Register event handlers
    unity_on_event "SERVICE_HEALTH_CHECK" handle_health_check_event
    unity_on_event "DEPLOYMENT_COMPLETED" handle_deployment_event
    unity_on_event "ERROR_OCCURRED" handle_error_event
    unity_on_event "RESOURCE_CREATED" handle_resource_event
    
    # Set service status
    unity_set_service_status "$SERVICE_NAME" "initialized"
    
    unity_emit_event "SERVICE_INITIALIZED" "$SERVICE_NAME" "version:$SERVICE_VERSION"
    
    return 0
}

# Start monitoring service
start_unity_monitoring_service() {
    unity_log "INFO" "Starting Unity Monitoring Service"
    
    # Start background monitoring
    start_monitoring_daemon
    
    # Start metric collection
    start_metric_collection
    
    # Start alert monitoring
    start_alert_monitoring
    
    # Update service status
    unity_set_service_status "$SERVICE_NAME" "running"
    
    unity_emit_event "SERVICE_STARTED" "$SERVICE_NAME" ""
    
    return 0
}

# Stop monitoring service
stop_unity_monitoring_service() {
    unity_log "INFO" "Stopping Unity Monitoring Service"
    
    # Stop monitoring daemon
    if [[ -n "$MONITORING_PID" ]] && kill -0 "$MONITORING_PID" 2>/dev/null; then
        kill "$MONITORING_PID"
        wait "$MONITORING_PID" 2>/dev/null || true
    fi
    
    # Flush pending metrics
    flush_metrics_to_cloudwatch
    
    # Update service status
    unity_set_service_status "$SERVICE_NAME" "stopped"
    
    unity_emit_event "SERVICE_STOPPED" "$SERVICE_NAME" ""
    
    return 0
}

# Health check
health_unity_monitoring_service() {
    local health_status="healthy"
    local health_details=""
    
    # Check monitoring daemon
    if [[ -n "$MONITORING_PID" ]] && ! kill -0 "$MONITORING_PID" 2>/dev/null; then
        health_status="unhealthy"
        health_details="Monitoring daemon not running"
    fi
    
    # Check CloudWatch connectivity
    if ! aws cloudwatch list-metrics --namespace "$MONITORING_NAMESPACE" --max-items 1 >/dev/null 2>&1; then
        health_status="degraded"
        health_details="${health_details:+$health_details, }CloudWatch unavailable"
    fi
    
    # Check metric backlog
    local backlog_count=$(find "$PROJECT_ROOT/.unity/monitoring/metrics" -name "*.json" 2>/dev/null | wc -l)
    if [[ $backlog_count -gt 100 ]]; then
        health_status="degraded"
        health_details="${health_details:+$health_details, }High metric backlog: $backlog_count"
    fi
    
    echo "$health_status|$health_details"
    return 0
}

# Configuration management
config_unity_monitoring_service() {
    local action="${1:-get}"
    local key="${2:-}"
    local value="${3:-}"
    
    case "$action" in
        get)
            if [[ -z "$key" ]]; then
                # Return all configuration
                echo "namespace: $MONITORING_NAMESPACE"
                echo "interval: $MONITORING_INTERVAL"
                echo "retention: $MONITORING_RETENTION"
            else
                # Return specific key
                case "$key" in
                    namespace) echo "$MONITORING_NAMESPACE" ;;
                    interval) echo "$MONITORING_INTERVAL" ;;
                    retention) echo "$MONITORING_RETENTION" ;;
                    *) unity_log "ERROR" "Unknown configuration key: $key"; return 1 ;;
                esac
            fi
            ;;
        set)
            case "$key" in
                namespace) MONITORING_NAMESPACE="$value" ;;
                interval) MONITORING_INTERVAL="$value" ;;
                retention) MONITORING_RETENTION="$value" ;;
                *) unity_log "ERROR" "Unknown configuration key: $key"; return 1 ;;
            esac
            ;;
        reload)
            # Reload configuration and restart monitoring
            stop_unity_monitoring_service
            init_unity_monitoring_service
            start_unity_monitoring_service
            ;;
    esac
}

#############################################
# CloudWatch Integration
#############################################

# Setup CloudWatch namespace
setup_cloudwatch_namespace() {
    unity_log "INFO" "Setting up CloudWatch namespace: $MONITORING_NAMESPACE"
    
    # Test CloudWatch access
    if ! aws cloudwatch list-metrics --max-items 1 >/dev/null 2>&1; then
        unity_log "ERROR" "No CloudWatch access"
        return 1
    fi
    
    # Create initial metric to establish namespace
    aws cloudwatch put-metric-data \
        --namespace "$MONITORING_NAMESPACE" \
        --metric-name "ServiceStartup" \
        --value 1 \
        --timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        --dimensions Service=$SERVICE_NAME || return 1
    
    return 0
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    local stack_name="$1"
    local dashboard_name="Unity-$stack_name"
    
    unity_log "INFO" "Creating CloudWatch dashboard: $dashboard_name"
    
    local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$MONITORING_NAMESPACE", "ServiceHealth", { "stat": "Average" } ],
                    [ ".", "EventLatency", { "stat": "Average", "yAxis": "right" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION:-us-east-1}",
                "title": "Service Health & Latency"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$MONITORING_NAMESPACE", "ErrorRate", { "stat": "Average" } ],
                    [ ".", "ResourceCount", { "stat": "Sum", "yAxis": "right" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION:-us-east-1}",
                "title": "Errors & Resources"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$MONITORING_NAMESPACE", "CPUUtilization", { "stat": "Average" } ],
                    [ ".", "MemoryUtilization", { "stat": "Average" } ],
                    [ ".", "DiskUtilization", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION:-us-east-1}",
                "title": "Resource Utilization"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$MONITORING_NAMESPACE", "CostPerHour", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION:-us-east-1}",
                "title": "Cost Tracking"
            }
        }
    ]
}
EOF
)
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body "$dashboard_body" || {
        unity_log "ERROR" "Failed to create dashboard"
        return 1
    }
    
    unity_log "INFO" "Dashboard created successfully"
    unity_emit_event "DASHBOARD_CREATED" "$SERVICE_NAME" "$dashboard_name"
    
    return 0
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    local stack_name="$1"
    
    unity_log "INFO" "Creating CloudWatch alarms for stack: $stack_name"
    
    # Create alarm for each threshold
    for metric_name in "${!ALERT_THRESHOLDS[@]}"; do
        local thresholds="${ALERT_THRESHOLDS[$metric_name]}"
        
        # Parse thresholds
        IFS=',' read -ra threshold_pairs <<< "$thresholds"
        for threshold_pair in "${threshold_pairs[@]}"; do
            IFS=':' read -r condition level <<< "$threshold_pair"
            
            local operator="GreaterThanThreshold"
            local threshold_value="${condition#>}"
            if [[ "$condition" =~ ^< ]]; then
                operator="LessThanThreshold"
                threshold_value="${condition#<}"
            fi
            
            local alarm_name="Unity-$stack_name-$metric_name-$level"
            
            aws cloudwatch put-metric-alarm \
                --alarm-name "$alarm_name" \
                --alarm-description "Unity $metric_name $level alarm" \
                --metric-name "$metric_name" \
                --namespace "$MONITORING_NAMESPACE" \
                --statistic Average \
                --period 300 \
                --threshold "$threshold_value" \
                --comparison-operator "$operator" \
                --evaluation-periods 2 \
                --treat-missing-data notBreaching || {
                unity_log "WARN" "Failed to create alarm: $alarm_name"
                continue
            }
            
            unity_log "DEBUG" "Created alarm: $alarm_name"
        done
    done
    
    unity_emit_event "ALARMS_CREATED" "$SERVICE_NAME" "$stack_name"
    return 0
}

#############################################
# Metric Collection
#############################################

# Start monitoring daemon
start_monitoring_daemon() {
    unity_log "INFO" "Starting monitoring daemon"
    
    # Start background process
    (
        while true; do
            # Collect system metrics
            collect_system_metrics
            
            # Collect service metrics
            collect_service_metrics
            
            # Collect event metrics
            collect_event_metrics
            
            # Process alert conditions
            process_alert_conditions
            
            # Push metrics to CloudWatch
            push_metrics_to_cloudwatch
            
            sleep "$MONITORING_INTERVAL"
        done
    ) &
    
    MONITORING_PID=$!
    unity_log "INFO" "Monitoring daemon started with PID: $MONITORING_PID"
}

# Collect system metrics
collect_system_metrics() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    # CPU utilization
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    record_metric "CPUUtilization" "$cpu_usage" "$timestamp" "System=Host"
    
    # Memory utilization
    local mem_usage=$(free | grep Mem | awk '{print ($2-$7)/$2 * 100.0}' 2>/dev/null || echo "0")
    record_metric "MemoryUtilization" "$mem_usage" "$timestamp" "System=Host"
    
    # Disk utilization
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    record_metric "DiskUtilization" "$disk_usage" "$timestamp" "System=Host"
    
    # Network throughput (simplified)
    if [[ -f /proc/net/dev ]]; then
        local net_rx=$(awk '/eth0:|ens5:/ {print $2}' /proc/net/dev 2>/dev/null || echo "0")
        local net_tx=$(awk '/eth0:|ens5:/ {print $10}' /proc/net/dev 2>/dev/null || echo "0")
        record_metric "NetworkThroughput" "$((net_rx + net_tx))" "$timestamp" "System=Host,Direction=Total"
    fi
}

# Collect service metrics
collect_service_metrics() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    # Collect metrics for each Unity service
    for service in $(unity_list_services); do
        # Get service health
        if command -v health_${service}_service >/dev/null 2>&1; then
            local health_result=$(health_${service}_service 2>/dev/null || echo "unknown|")
            local health_status="${health_result%%|*}"
            
            local health_value=0
            case "$health_status" in
                healthy) health_value=100 ;;
                degraded) health_value=50 ;;
                unhealthy) health_value=0 ;;
            esac
            
            record_metric "ServiceHealth" "$health_value" "$timestamp" "Service=$service"
        fi
    done
}

# Collect event metrics
collect_event_metrics() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    # Calculate event latency from recent events
    if [[ -f "$PROJECT_ROOT/logs/unity/events.log" ]]; then
        local avg_latency=$(tail -100 "$PROJECT_ROOT/logs/unity/events.log" 2>/dev/null | \
            grep -oP 'latency:\K\d+' | \
            awk '{sum+=$1} END {if(NR>0) print sum/NR; else print 0}')
        
        record_metric "EventLatency" "${avg_latency:-0}" "$timestamp" "EventBus=Unity"
    fi
    
    # Calculate error rate
    local error_count=$(tail -1000 "$PROJECT_ROOT/logs/unity/core.log" 2>/dev/null | \
        grep -c "ERROR" || echo "0")
    local total_logs=1000
    local error_rate=$((error_count * 100 / total_logs))
    
    record_metric "ErrorRate" "$error_rate" "$timestamp" "LogSource=Unity"
}

# Record metric
record_metric() {
    local metric_name="$1"
    local value="$2"
    local timestamp="${3:-$(date -u +%Y-%m-%dT%H:%M:%S.000Z)}"
    local dimensions="${4:-}"
    
    # Create metric file
    local metric_file="$PROJECT_ROOT/.unity/monitoring/metrics/${metric_name}-$(date +%s).json"
    
    cat > "$metric_file" << EOF
{
    "MetricName": "$metric_name",
    "Value": $value,
    "Timestamp": "$timestamp",
    "Dimensions": "$dimensions",
    "Unit": "${METRIC_DEFINITIONS[$metric_name]%%|*}"
}
EOF
    
    unity_log "DEBUG" "Recorded metric: $metric_name=$value"
}

# Push metrics to CloudWatch
push_metrics_to_cloudwatch() {
    local metric_files=("$PROJECT_ROOT/.unity/monitoring/metrics"/*.json)
    
    if [[ ${#metric_files[@]} -eq 0 ]] || [[ ! -e "${metric_files[0]}" ]]; then
        return 0
    fi
    
    unity_log "DEBUG" "Pushing ${#metric_files[@]} metrics to CloudWatch"
    
    # Batch metrics for efficient upload
    local batch_size=20
    local batch_count=0
    local metric_data="["
    
    for metric_file in "${metric_files[@]}"; do
        if [[ ! -f "$metric_file" ]]; then
            continue
        fi
        
        local metric_json=$(cat "$metric_file")
        local metric_name=$(echo "$metric_json" | jq -r '.MetricName')
        local value=$(echo "$metric_json" | jq -r '.Value')
        local timestamp=$(echo "$metric_json" | jq -r '.Timestamp')
        local dimensions=$(echo "$metric_json" | jq -r '.Dimensions')
        
        # Build dimension array
        local dimension_array=""
        if [[ -n "$dimensions" ]]; then
            IFS=',' read -ra dim_pairs <<< "$dimensions"
            for dim_pair in "${dim_pairs[@]}"; do
                IFS='=' read -r name value <<< "$dim_pair"
                dimension_array="${dimension_array:+$dimension_array,}{\"Name\":\"$name\",\"Value\":\"$value\"}"
            done
        fi
        
        if [[ $batch_count -gt 0 ]]; then
            metric_data+=","
        fi
        
        metric_data+="{\"MetricName\":\"$metric_name\",\"Value\":$value,\"Timestamp\":\"$timestamp\""
        if [[ -n "$dimension_array" ]]; then
            metric_data+=",\"Dimensions\":[$dimension_array]"
        fi
        metric_data+="}"
        
        ((batch_count++))
        
        # Send batch when full
        if [[ $batch_count -ge $batch_size ]]; then
            metric_data+="]"
            
            if aws cloudwatch put-metric-data \
                --namespace "$MONITORING_NAMESPACE" \
                --metric-data "$metric_data" 2>/dev/null; then
                
                # Remove processed files
                for ((i=0; i<batch_count; i++)); do
                    rm -f "${metric_files[$i]}"
                done
            fi
            
            # Reset batch
            batch_count=0
            metric_data="["
        fi
    done
    
    # Send remaining metrics
    if [[ $batch_count -gt 0 ]]; then
        metric_data+="]"
        
        if aws cloudwatch put-metric-data \
            --namespace "$MONITORING_NAMESPACE" \
            --metric-data "$metric_data" 2>/dev/null; then
            
            # Remove processed files
            for metric_file in "${metric_files[@]}"; do
                rm -f "$metric_file"
            done
        fi
    fi
}

# Flush all metrics
flush_metrics_to_cloudwatch() {
    unity_log "INFO" "Flushing all metrics to CloudWatch"
    push_metrics_to_cloudwatch
}

#############################################
# Alert Management
#############################################

# Start alert monitoring
start_alert_monitoring() {
    unity_log "INFO" "Starting alert monitoring"
    
    # Monitor CloudWatch alarms
    if command -v aws >/dev/null 2>&1; then
        (
            while true; do
                check_cloudwatch_alarms
                sleep 60
            done
        ) &
    fi
}

# Check CloudWatch alarms
check_cloudwatch_alarms() {
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "Unity-" \
        --state-value ALARM \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$alarms" ]]; then
        for alarm in $alarms; do
            handle_alarm_state "$alarm" "ALARM"
        done
    fi
}

# Process alert conditions
process_alert_conditions() {
    # Check each metric against thresholds
    for metric_name in "${!ALERT_THRESHOLDS[@]}"; do
        local current_value=$(get_current_metric_value "$metric_name")
        if [[ -z "$current_value" ]]; then
            continue
        fi
        
        local thresholds="${ALERT_THRESHOLDS[$metric_name]}"
        IFS=',' read -ra threshold_pairs <<< "$thresholds"
        
        for threshold_pair in "${threshold_pairs[@]}"; do
            IFS=':' read -r condition level <<< "$threshold_pair"
            
            if evaluate_threshold "$current_value" "$condition"; then
                create_alert "$metric_name" "$level" "$current_value" "$condition"
            fi
        done
    done
}

# Get current metric value
get_current_metric_value() {
    local metric_name="$1"
    
    # Get latest metric from local cache
    local latest_file=$(ls -t "$PROJECT_ROOT/.unity/monitoring/metrics/${metric_name}-"*.json 2>/dev/null | head -1)
    
    if [[ -n "$latest_file" && -f "$latest_file" ]]; then
        jq -r '.Value' "$latest_file" 2>/dev/null
    fi
}

# Evaluate threshold condition
evaluate_threshold() {
    local value="$1"
    local condition="$2"
    
    if [[ "$condition" =~ ^[<>] ]]; then
        local operator="${condition:0:1}"
        local threshold="${condition:1}"
        
        if [[ "$operator" == ">" ]]; then
            (( $(echo "$value > $threshold" | bc -l) ))
        else
            (( $(echo "$value < $threshold" | bc -l) ))
        fi
    else
        return 1
    fi
}

# Create alert
create_alert() {
    local metric_name="$1"
    local severity="$2"
    local value="$3"
    local condition="$4"
    
    local alert_id="alert-$(date +%s)-$$"
    local alert_file="$PROJECT_ROOT/.unity/monitoring/alerts/$alert_id.json"
    
    cat > "$alert_file" << EOF
{
    "id": "$alert_id",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "metric": "$metric_name",
    "severity": "$severity",
    "value": $value,
    "condition": "$condition",
    "status": "active"
}
EOF
    
    unity_log "$severity" "Alert: $metric_name $condition (value: $value)"
    unity_emit_event "ALERT_TRIGGERED" "$SERVICE_NAME" "$metric_name:$severity:$value"
    
    # Execute alert handler if defined
    if command -v handle_monitoring_alert >/dev/null 2>&1; then
        handle_monitoring_alert "$metric_name" "$severity" "$value"
    fi
}

# Handle alarm state
handle_alarm_state() {
    local alarm_name="$1"
    local state="$2"
    
    unity_log "WARN" "CloudWatch alarm in $state state: $alarm_name"
    unity_emit_event "CLOUDWATCH_ALARM" "$SERVICE_NAME" "$alarm_name:$state"
}

#############################################
# Report Generation
#############################################

# Generate monitoring report
generate_monitoring_report() {
    local stack_name="${1:-all}"
    local period="${2:-24}"  # hours
    local format="${3:-text}"  # text, json, html
    
    unity_log "INFO" "Generating monitoring report for: $stack_name (last ${period}h)"
    
    local report_file="$PROJECT_ROOT/.unity/monitoring/reports/report-$(date +%Y%m%d-%H%M%S).$format"
    mkdir -p "$(dirname "$report_file")"
    
    case "$format" in
        json)
            generate_json_report "$stack_name" "$period" > "$report_file"
            ;;
        html)
            generate_html_report "$stack_name" "$period" > "$report_file"
            ;;
        *)
            generate_text_report "$stack_name" "$period" > "$report_file"
            ;;
    esac
    
    unity_log "INFO" "Report generated: $report_file"
    echo "$report_file"
}

# Generate text report
generate_text_report() {
    local stack_name="$1"
    local period="$2"
    
    cat << EOF
Unity Monitoring Report
======================
Generated: $(date)
Stack: $stack_name
Period: Last $period hours

System Metrics
--------------
$(get_metric_summary "CPUUtilization" "$period")
$(get_metric_summary "MemoryUtilization" "$period")
$(get_metric_summary "DiskUtilization" "$period")

Service Metrics
---------------
$(get_metric_summary "ServiceHealth" "$period")
$(get_metric_summary "EventLatency" "$period")
$(get_metric_summary "ErrorRate" "$period")

Cost Metrics
------------
$(get_metric_summary "CostPerHour" "$period")

Active Alerts
-------------
$(list_active_alerts)

Recommendations
---------------
$(generate_recommendations)
EOF
}

# Get metric summary
get_metric_summary() {
    local metric_name="$1"
    local period="$2"
    
    # Get CloudWatch statistics
    local stats=$(aws cloudwatch get-metric-statistics \
        --namespace "$MONITORING_NAMESPACE" \
        --metric-name "$metric_name" \
        --start-time "$(date -u -d "$period hours ago" +%Y-%m-%dT%H:%M:%S.000Z)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        --period 3600 \
        --statistics Average,Maximum,Minimum \
        --query 'Datapoints[*].[Average,Maximum,Minimum]' \
        --output text 2>/dev/null || echo "N/A N/A N/A")
    
    local avg=$(echo "$stats" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "N/A"}')
    local max=$(echo "$stats" | awk '{if(NR==1 || $2>max) max=$2} END {print max}')
    local min=$(echo "$stats" | awk '{if(NR==1 || $3<min) min=$3} END {print min}')
    
    echo "$metric_name: Avg=$avg, Max=$max, Min=$min"
}

# List active alerts
list_active_alerts() {
    local alert_count=0
    
    for alert_file in "$PROJECT_ROOT/.unity/monitoring/alerts"/*.json; do
        if [[ -f "$alert_file" ]]; then
            local status=$(jq -r '.status' "$alert_file" 2>/dev/null)
            if [[ "$status" == "active" ]]; then
                local metric=$(jq -r '.metric' "$alert_file")
                local severity=$(jq -r '.severity' "$alert_file")
                local value=$(jq -r '.value' "$alert_file")
                echo "- $metric: $severity (value: $value)"
                ((alert_count++))
            fi
        fi
    done
    
    if [[ $alert_count -eq 0 ]]; then
        echo "No active alerts"
    fi
}

# Generate recommendations
generate_recommendations() {
    local recommendations=()
    
    # Check CPU usage
    local cpu_avg=$(get_current_metric_value "CPUUtilization")
    if [[ -n "$cpu_avg" ]] && (( $(echo "$cpu_avg > 80" | bc -l) )); then
        recommendations+=("- High CPU usage detected. Consider scaling up or optimizing workloads.")
    fi
    
    # Check error rate
    local error_rate=$(get_current_metric_value "ErrorRate")
    if [[ -n "$error_rate" ]] && (( $(echo "$error_rate > 5" | bc -l) )); then
        recommendations+=("- Elevated error rate. Review application logs for issues.")
    fi
    
    # Check cost
    local cost_per_hour=$(get_current_metric_value "CostPerHour")
    if [[ -n "$cost_per_hour" ]] && (( $(echo "$cost_per_hour > 100" | bc -l) )); then
        recommendations+=("- High hourly costs. Consider spot instances or resource optimization.")
    fi
    
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        echo "No recommendations at this time."
    else
        printf '%s\n' "${recommendations[@]}"
    fi
}

#############################################
# Event Handlers
#############################################

# Handle health check events
handle_health_check_event() {
    local event="$1"
    local source="$2"
    local data="$3"
    
    # Extract service and status
    local service="${data%%:*}"
    local status="${data#*:}"
    
    # Record health metric
    local health_value=0
    case "$status" in
        healthy) health_value=100 ;;
        degraded) health_value=50 ;;
        unhealthy) health_value=0 ;;
    esac
    
    record_metric "ServiceHealth" "$health_value" "" "Service=$service"
}

# Handle deployment events
handle_deployment_event() {
    local event="$1"
    local source="$2"
    local data="$3"
    
    # Extract deployment time
    if [[ "$data" =~ duration:([0-9]+) ]]; then
        local duration="${BASH_REMATCH[1]}"
        record_metric "DeploymentTime" "$duration" "" "Source=$source"
    fi
}

# Handle error events
handle_error_event() {
    local event="$1"
    local source="$2"
    local data="$3"
    
    # Increment error counter
    local error_count_file="$PROJECT_ROOT/.unity/monitoring/error_count"
    local error_count=0
    
    if [[ -f "$error_count_file" ]]; then
        error_count=$(cat "$error_count_file")
    fi
    
    ((error_count++))
    echo "$error_count" > "$error_count_file"
    
    # Create alert for critical errors
    if [[ "$data" =~ critical|fatal ]]; then
        create_alert "CriticalError" "critical" "1" ">0"
    fi
}

# Handle resource events
handle_resource_event() {
    local event="$1"
    local source="$2"
    local data="$3"
    
    # Count resources
    local resource_count=$(unity_list_resources | wc -l)
    record_metric "ResourceCount" "$resource_count" "" "Source=$source"
}

#############################################
# Utility Functions
#############################################

# Get metric statistics
get_metric_statistics() {
    local metric_name="$1"
    local start_time="${2:-$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z)}"
    local end_time="${3:-$(date -u +%Y-%m-%dT%H:%M:%S.000Z)}"
    local period="${4:-300}"
    local statistics="${5:-Average}"
    
    aws cloudwatch get-metric-statistics \
        --namespace "$MONITORING_NAMESPACE" \
        --metric-name "$metric_name" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period "$period" \
        --statistics "$statistics" \
        --query 'Datapoints[*].[Timestamp,Average]' \
        --output text 2>/dev/null
}

# List all metrics
list_unity_metrics() {
    aws cloudwatch list-metrics \
        --namespace "$MONITORING_NAMESPACE" \
        --query 'Metrics[*].MetricName' \
        --output text 2>/dev/null | tr '\t' '\n' | sort -u
}

# Delete old metrics
cleanup_old_metrics() {
    local retention_days="${1:-$MONITORING_RETENTION}"
    
    unity_log "INFO" "Cleaning up metrics older than $retention_days days"
    
    # CloudWatch automatically handles retention
    # Clean up local files
    find "$PROJECT_ROOT/.unity/monitoring" -name "*.json" -mtime "+$retention_days" -delete
}

# Export functions
export -f init_unity_monitoring_service
export -f start_unity_monitoring_service
export -f stop_unity_monitoring_service
export -f health_unity_monitoring_service
export -f config_unity_monitoring_service
export -f create_cloudwatch_dashboard
export -f create_cloudwatch_alarms
export -f record_metric
export -f generate_monitoring_report
export -f get_metric_statistics
export -f list_unity_metrics