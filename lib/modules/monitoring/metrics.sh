#!/usr/bin/env bash
# =============================================================================
# Monitoring Metrics Module
# Handles CloudWatch metrics, alarms, and monitoring
# =============================================================================

# Prevent multiple sourcing
[ -n "${_MONITORING_METRICS_SH_LOADED:-}" ] && return 0
_MONITORING_METRICS_SH_LOADED=1

# =============================================================================
# METRICS CONFIGURATION
# =============================================================================

# Metrics configuration defaults
METRICS_DEFAULT_NAMESPACE="GeuseMaker"
METRICS_DEFAULT_INTERVAL=60
METRICS_DEFAULT_PERIOD=300
METRICS_DEFAULT_EVALUATION_PERIODS=2
METRICS_DEFAULT_THRESHOLD=80

# Alarm configuration defaults
ALARM_DEFAULT_ACTIONS_ENABLED=true
ALARM_DEFAULT_INSUFFICIENT_DATA_ACTIONS=()
ALARM_DEFAULT_OK_ACTIONS=()

# =============================================================================
# METRICS FUNCTIONS
# =============================================================================

# Initialize monitoring metrics
init_monitoring_metrics() {
    local stack_name="$1"
    local metrics_config="${2:-}"
    
    log_info "Initializing monitoring metrics for stack: $stack_name" "METRICS"
    
    # Parse metrics configuration
    local namespace=$(echo "$metrics_config" | jq -r '.namespace // "'$METRICS_DEFAULT_NAMESPACE'"')
    local enable_cloudwatch=$(echo "$metrics_config" | jq -r '.enable_cloudwatch // true')
    local enable_alarms=$(echo "$metrics_config" | jq -r '.enable_alarms // true')
    
    # Set metrics namespace
    set_variable "METRICS_NAMESPACE" "$namespace" "$VARIABLE_SCOPE_STACK"
    
    # Create CloudWatch dashboard if enabled
    if [[ "$enable_cloudwatch" == "true" ]]; then
        local dashboard_name
        dashboard_name=$(create_cloudwatch_dashboard "$stack_name" "$namespace")
        if [[ $? -eq 0 ]]; then
            set_variable "CLOUDWATCH_DASHBOARD_NAME" "$dashboard_name" "$VARIABLE_SCOPE_STACK"
        fi
    fi
    
    # Create alarms if enabled
    if [[ "$enable_alarms" == "true" ]]; then
        create_monitoring_alarms "$stack_name" "$namespace" "$metrics_config"
    fi
    
    log_info "Monitoring metrics initialized successfully" "METRICS"
    return 0
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    local stack_name="$1"
    local namespace="$2"
    
    log_info "Creating CloudWatch dashboard for stack: $stack_name" "METRICS"
    
    # Generate dashboard name
    local dashboard_name="${stack_name}-dashboard"
    
    # Get stack resources for dashboard widgets
    local vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    local auto_scaling_group_name=$(get_variable "AUTO_SCALING_GROUP_NAME" "$VARIABLE_SCOPE_STACK")
    local alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    
    # Create dashboard body
    local dashboard_body='{
        "widgets": [
            {
                "type": "metric",
                "x": 0,
                "y": 0,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "'$auto_scaling_group_name'"]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'${AWS_REGION:-us-east-1}'",
                    "title": "EC2 CPU Utilization",
                    "period": 300
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
                        ["AWS/EC2", "NetworkIn", "AutoScalingGroupName", "'$auto_scaling_group_name'"]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'${AWS_REGION:-us-east-1}'",
                    "title": "Network In",
                    "period": 300
                }
            }
        ]
    }'
    
    # Add ALB metrics if available
    if [[ -n "$alb_arn" ]]; then
        dashboard_body=$(echo "$dashboard_body" | jq '.widgets += [
            {
                "type": "metric",
                "x": 0,
                "y": 6,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "'$alb_arn'"]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'${AWS_REGION:-us-east-1}'",
                    "title": "ALB Request Count",
                    "period": 300
                }
            }
        ]')
    fi
    
    # Create dashboard
    if aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body "$dashboard_body" >/dev/null 2>&1; then
        log_info "CloudWatch dashboard created successfully: $dashboard_name" "METRICS"
        echo "$dashboard_name"
        return 0
    else
        log_error "Failed to create CloudWatch dashboard" "METRICS"
        return 1
    fi
}

# Create monitoring alarms
create_monitoring_alarms() {
    local stack_name="$1"
    local namespace="$2"
    local metrics_config="${3:-}"
    
    log_info "Creating monitoring alarms for stack: $stack_name" "METRICS"
    
    # Get stack resources
    local auto_scaling_group_name=$(get_variable "AUTO_SCALING_GROUP_NAME" "$VARIABLE_SCOPE_STACK")
    local alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    
    local alarm_success=true
    
    # Create CPU utilization alarm
    if [[ -n "$auto_scaling_group_name" ]]; then
        if ! create_cpu_alarm "$stack_name" "$auto_scaling_group_name"; then
            log_error "Failed to create CPU alarm" "METRICS"
            alarm_success=false
        fi
    fi
    
    # Create memory utilization alarm
    if [[ -n "$auto_scaling_group_name" ]]; then
        if ! create_memory_alarm "$stack_name" "$auto_scaling_group_name"; then
            log_error "Failed to create memory alarm" "METRICS"
            alarm_success=false
        fi
    fi
    
    # Create ALB alarm if available
    if [[ -n "$alb_arn" ]]; then
        if ! create_alb_alarm "$stack_name" "$alb_arn"; then
            log_error "Failed to create ALB alarm" "METRICS"
            alarm_success=false
        fi
    fi
    
    if [[ "$alarm_success" == "true" ]]; then
        log_info "Monitoring alarms created successfully" "METRICS"
        return 0
    else
        log_error "Some monitoring alarms failed to create" "METRICS"
        return 1
    fi
}

# Create CPU utilization alarm
create_cpu_alarm() {
    local stack_name="$1"
    local auto_scaling_group_name="$2"
    
    local alarm_name="${stack_name}-cpu-utilization"
    
    log_info "Creating CPU utilization alarm: $alarm_name" "METRICS"
    
    if aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "CPU utilization alarm for $stack_name" \
        --metric-name "CPUUtilization" \
        --namespace "AWS/EC2" \
        --statistic "Average" \
        --period 300 \
        --threshold 80 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "arn:aws:sns:${AWS_REGION:-us-east-1}:${AWS_ACCOUNT_ID:-}:${stack_name}-alerts" \
        --dimensions "Name=AutoScalingGroupName,Value=$auto_scaling_group_name" >/dev/null 2>&1; then
        log_info "CPU utilization alarm created successfully" "METRICS"
        return 0
    else
        log_error "Failed to create CPU utilization alarm" "METRICS"
        return 1
    fi
}

# Create memory utilization alarm
create_memory_alarm() {
    local stack_name="$1"
    local auto_scaling_group_name="$2"
    
    local alarm_name="${stack_name}-memory-utilization"
    
    log_info "Creating memory utilization alarm: $alarm_name" "METRICS"
    
    # Note: Memory metrics require custom CloudWatch agent
    # This is a placeholder for when custom metrics are available
    log_info "Memory alarm creation skipped (requires custom CloudWatch agent)" "METRICS"
    return 0
}

# Create ALB alarm
create_alb_alarm() {
    local stack_name="$1"
    local alb_arn="$2"
    
    local alarm_name="${stack_name}-alb-errors"
    
    log_info "Creating ALB error alarm: $alarm_name" "METRICS"
    
    if aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "ALB error rate alarm for $stack_name" \
        --metric-name "HTTPCode_ELB_5XX_Count" \
        --namespace "AWS/ApplicationELB" \
        --statistic "Sum" \
        --period 300 \
        --threshold 10 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "arn:aws:sns:${AWS_REGION:-us-east-1}:${AWS_ACCOUNT_ID:-}:${stack_name}-alerts" \
        --dimensions "Name=LoadBalancer,Value=$alb_arn" >/dev/null 2>&1; then
        log_info "ALB error alarm created successfully" "METRICS"
        return 0
    else
        log_error "Failed to create ALB error alarm" "METRICS"
        return 1
    fi
}

# =============================================================================
# METRICS HELPER FUNCTIONS
# =============================================================================

# Put custom metric
put_custom_metric() {
    local namespace="$1"
    local metric_name="$2"
    local value="$3"
    local unit="${4:-Count}"
    local dimensions="${5:-}"
    
    log_info "Putting custom metric: $namespace/$metric_name = $value" "METRICS"
    
    local metric_data='{
        "MetricName": "'$metric_name'",
        "Value": '$value',
        "Unit": "'$unit'",
        "Timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }'
    
    # Add dimensions if provided
    if [[ -n "$dimensions" ]]; then
        metric_data=$(echo "$metric_data" | jq --argjson dims "$dimensions" '.Dimensions = $dims')
    fi
    
    if aws cloudwatch put-metric-data \
        --namespace "$namespace" \
        --metric-data "$metric_data" >/dev/null 2>&1; then
        log_info "Custom metric put successfully" "METRICS"
        return 0
    else
        log_error "Failed to put custom metric" "METRICS"
        return 1
    fi
}

# Get metric statistics
get_metric_statistics() {
    local namespace="$1"
    local metric_name="$2"
    local start_time="$3"
    local end_time="$4"
    local period="${5:-300}"
    local statistics="${6:-Average}"
    local dimensions="${7:-}"
    
    log_info "Getting metric statistics: $namespace/$metric_name" "METRICS"
    
    local command="aws cloudwatch get-metric-statistics \
        --namespace \"$namespace\" \
        --metric-name \"$metric_name\" \
        --start-time \"$start_time\" \
        --end-time \"$end_time\" \
        --period $period \
        --statistics $statistics"
    
    # Add dimensions if provided
    if [[ -n "$dimensions" ]]; then
        command="$command --dimensions $dimensions"
    fi
    
    local result
    result=$(eval "$command" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$result"
        return 0
    else
        log_error "Failed to get metric statistics" "METRICS"
        return 1
    fi
}

# List alarms
list_alarms() {
    local stack_name="${1:-}"
    
    log_info "Listing CloudWatch alarms" "METRICS"
    
    local command="aws cloudwatch describe-alarms"
    
    if [[ -n "$stack_name" ]]; then
        command="$command --alarm-name-prefix \"$stack_name\""
    fi
    
    local result
    result=$(eval "$command" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$result"
        return 0
    else
        log_error "Failed to list alarms" "METRICS"
        return 1
    fi
}

# Get alarm state
get_alarm_state() {
    local alarm_name="$1"
    
    log_info "Getting alarm state: $alarm_name" "METRICS"
    
    local state
    state=$(aws cloudwatch describe-alarms \
        --alarm-names "$alarm_name" \
        --query 'MetricAlarms[0].StateValue' \
        --output text 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$state"
        return 0
    else
        log_error "Failed to get alarm state" "METRICS"
        return 1
    fi
}

# Set alarm state
set_alarm_state() {
    local alarm_name="$1"
    local state="$2"
    local reason="${3:-Manual state change}"
    
    log_info "Setting alarm state: $alarm_name -> $state" "METRICS"
    
    if aws cloudwatch set-alarm-state \
        --alarm-name "$alarm_name" \
        --state-value "$state" \
        --state-reason "$reason" >/dev/null 2>&1; then
        log_info "Alarm state set successfully" "METRICS"
        return 0
    else
        log_error "Failed to set alarm state" "METRICS"
        return 1
    fi
}

# =============================================================================
# METRICS CLEANUP FUNCTIONS
# =============================================================================

# Delete monitoring metrics
delete_monitoring_metrics() {
    local stack_name="$1"
    
    log_info "Deleting monitoring metrics for stack: $stack_name" "METRICS"
    
    local delete_success=true
    
    # Delete CloudWatch dashboard
    local dashboard_name=$(get_variable "CLOUDWATCH_DASHBOARD_NAME" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$dashboard_name" ]]; then
        if ! delete_cloudwatch_dashboard "$dashboard_name"; then
            log_error "Failed to delete CloudWatch dashboard" "METRICS"
            delete_success=false
        fi
    fi
    
    # Delete alarms
    if ! delete_stack_alarms "$stack_name"; then
        log_error "Failed to delete stack alarms" "METRICS"
        delete_success=false
    fi
    
    if [[ "$delete_success" == "true" ]]; then
        log_info "Monitoring metrics deleted successfully" "METRICS"
        return 0
    else
        log_error "Some monitoring metrics failed to delete" "METRICS"
        return 1
    fi
}

# Delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    local dashboard_name="$1"
    
    log_info "Deleting CloudWatch dashboard: $dashboard_name" "METRICS"
    
    if aws cloudwatch delete-dashboards \
        --dashboard-names "$dashboard_name" >/dev/null 2>&1; then
        log_info "CloudWatch dashboard deleted successfully" "METRICS"
        return 0
    else
        log_error "Failed to delete CloudWatch dashboard" "METRICS"
        return 1
    fi
}

# Delete stack alarms
delete_stack_alarms() {
    local stack_name="$1"
    
    log_info "Deleting alarms for stack: $stack_name" "METRICS"
    
    # Get all alarms for the stack
    local alarms
    alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$stack_name" \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null)
    
    if [[ -n "$alarms" ]]; then
        for alarm in $alarms; do
            if aws cloudwatch delete-alarms --alarm-names "$alarm" >/dev/null 2>&1; then
                log_info "Alarm deleted: $alarm" "METRICS"
            else
                log_error "Failed to delete alarm: $alarm" "METRICS"
                return 1
            fi
        done
    fi
    
    log_info "Stack alarms deleted successfully" "METRICS"
    return 0
} 