#!/usr/bin/env bash
# =============================================================================
# Monitoring Integration Module
# Integrates monitoring capabilities into deployment scripts
# =============================================================================

# Prevent multiple sourcing
[ -n "${_MONITORING_INTEGRATION_SH_LOADED:-}" ] && return 0
_MONITORING_INTEGRATION_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/structured_logging.sh"
source "${SCRIPT_DIR}/observability.sh"
source "${SCRIPT_DIR}/alerting.sh"
source "${SCRIPT_DIR}/performance_metrics.sh"
source "${SCRIPT_DIR}/dashboards.sh"
source "${SCRIPT_DIR}/debug_tools.sh"
source "${SCRIPT_DIR}/log_aggregation.sh"

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================

# Monitoring profiles
readonly MONITOR_PROFILE_MINIMAL="minimal"
readonly MONITOR_PROFILE_STANDARD="standard"
readonly MONITOR_PROFILE_COMPREHENSIVE="comprehensive"
readonly MONITOR_PROFILE_DEBUG="debug"

# Global configuration
MONITORING_ENABLED="${MONITORING_ENABLED:-true}"
MONITORING_PROFILE="${MONITORING_PROFILE:-$MONITOR_PROFILE_STANDARD}"
MONITORING_OUTPUT_DIR="${MONITORING_OUTPUT_DIR:-/tmp/monitoring_$$}"

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize monitoring for deployment
init_deployment_monitoring() {
    local stack_name="${1:-$STACK_NAME}"
    local profile="${2:-$MONITORING_PROFILE}"
    local output_dir="${3:-$MONITORING_OUTPUT_DIR}"
    
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        log_info "Monitoring disabled" "MONITOR"
        return 0
    fi
    
    log_info "Initializing deployment monitoring" "MONITOR"
    
    # Set monitoring context
    export MONITORING_PROFILE="$profile"
    export MONITORING_OUTPUT_DIR="$output_dir"
    export DEPLOYMENT_ID="deploy_$(date +%s)_${RANDOM}"
    
    # Create output directory
    mkdir -p "$MONITORING_OUTPUT_DIR"
    
    # Initialize components based on profile
    case "$profile" in
        "$MONITOR_PROFILE_MINIMAL")
            init_minimal_monitoring
            ;;
        "$MONITOR_PROFILE_STANDARD")
            init_standard_monitoring
            ;;
        "$MONITOR_PROFILE_COMPREHENSIVE")
            init_comprehensive_monitoring
            ;;
        "$MONITOR_PROFILE_DEBUG")
            init_debug_monitoring
            ;;
        *)
            init_standard_monitoring
            ;;
    esac
    
    # Create deployment dashboard
    local dashboard_id=$(create_dashboard "deployment-$stack_name" "$DASHBOARD_TYPE_DEPLOYMENT")
    export DEPLOYMENT_DASHBOARD_ID="$dashboard_id"
    
    log_info "Deployment monitoring initialized (profile: $profile)" "MONITOR"
    return 0
}

# Initialize minimal monitoring
init_minimal_monitoring() {
    # Basic structured logging
    init_structured_logging "plain" "" "false"
    
    # Basic alerting for critical issues
    init_alerting "log" "" ""
    
    # Basic metrics
    init_performance_metrics "$COLLECT_INTERVAL_SLOW" "false"
}

# Initialize standard monitoring
init_standard_monitoring() {
    # Structured logging with JSON
    init_structured_logging "json" "$MONITORING_OUTPUT_DIR/logs.json" "true"
    
    # Observability framework
    init_observability "$OBS_LEVEL_STANDARD" "metrics,logs" ""
    
    # Alerting system
    init_alerting "log,console" "${ALERT_WEBHOOK_URL:-}" "${ALERT_SNS_TOPIC:-}"
    
    # Performance metrics
    init_performance_metrics "$COLLECT_INTERVAL_NORMAL" "true"
    
    # Log aggregation
    init_log_aggregation "$AGG_MODE_BATCH" "$MONITORING_OUTPUT_DIR/aggregation" "7"
}

# Initialize comprehensive monitoring
init_comprehensive_monitoring() {
    # Full structured logging
    init_structured_logging "json" "$MONITORING_OUTPUT_DIR/logs.json" "true"
    
    # Full observability
    init_observability "$OBS_LEVEL_DETAILED" "metrics,logs,traces,events" ""
    
    # Full alerting
    init_alerting "log,console,webhook" "${ALERT_WEBHOOK_URL:-}" "${ALERT_SNS_TOPIC:-}"
    
    # Detailed performance metrics
    init_performance_metrics "$COLLECT_INTERVAL_FAST" "true"
    
    # Real-time log aggregation
    init_log_aggregation "$AGG_MODE_REALTIME" "$MONITORING_OUTPUT_DIR/aggregation" "30"
    
    # Enable dashboards
    export DASHBOARD_ENABLED=true
    export DASHBOARD_REFRESH_INTERVAL="$DASHBOARD_REFRESH_FAST"
}

# Initialize debug monitoring
init_debug_monitoring() {
    # Initialize comprehensive monitoring first
    init_comprehensive_monitoring
    
    # Enable debug tools
    init_debug_tools "$DEBUG_LEVEL_VERBOSE" "$MONITORING_OUTPUT_DIR/debug" "true"
    
    # Enable tracing
    export TRACE_ENABLED=true
    export TRACE_SAMPLING_RATE=1.0
    
    # Enable debug capture
    start_debug_capture
}

# =============================================================================
# DEPLOYMENT HOOKS
# =============================================================================

# Pre-deployment monitoring
monitor_pre_deployment() {
    local stack_name="${1:-$STACK_NAME}"
    
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Starting pre-deployment monitoring" "MONITOR"
    
    # Record deployment start
    log_deployment_event "start" '{"stack_name": "'$stack_name'"}'
    
    # Start deployment trace
    local trace_id=$(start_trace "deployment" "" '{"stack": "'$stack_name'"}')
    export DEPLOYMENT_TRACE_ID="$trace_id"
    
    # Record initial metrics
    record_performance_metric "deployment.start_time" "$(date +%s)" "$METRIC_TYPE_GAUGE" "seconds"
    
    # Create pre-deployment snapshot
    create_monitoring_snapshot "pre_deployment"
    
    # Check system health
    check_system_health_for_deployment
}

# Monitor deployment phase
monitor_deployment_phase() {
    local phase="$1"
    local action="${2:-start}"
    
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    case "$action" in
        "start")
            log_info "Starting phase: $phase" "MONITOR"
            
            # Log phase start
            log_structured_event "INFO" "Deployment phase started: $phase" "deployment" "phase_start" \
                '{"phase": "'$phase'"}'            
            # Start phase trace
            local phase_trace=$(start_trace "phase_$phase" "$DEPLOYMENT_TRACE_ID" \
                '{"phase": "'$phase'"}')
            export "PHASE_TRACE_${phase^^}"="$phase_trace"
            
            # Record phase start time
            export "PHASE_START_${phase^^}"="$(date +%s)"
            record_performance_metric "deployment.phase.start" "$(date +%s)" \
                "$METRIC_TYPE_GAUGE" "timestamp" '{"phase": "'$phase'"}'            
            # Track deployment milestone
            track_deployment_milestone "phase_${phase}_start" '{"phase": "'$phase'"}'            ;;
        
        "end")
            log_info "Completed phase: $phase" "MONITOR"
            
            # Calculate phase duration
            local start_var="PHASE_START_${phase^^}"
            local start_time="${!start_var:-0}"
            local duration=$(($(date +%s) - start_time))
            
            # Log phase completion
            log_structured_event "INFO" "Deployment phase completed: $phase" "deployment" "phase_end" \
                '{"phase": "'$phase'", "duration": '$duration'}'            
            # End phase trace
            local trace_var="PHASE_TRACE_${phase^^}"
            local phase_trace="${!trace_var}"
            if [[ -n "$phase_trace" ]]; then
                end_trace "$phase_trace" "ok"
            fi
            
            # Record phase metrics
            record_performance_metric "deployment.phase.duration" "$duration" \
                "$METRIC_TYPE_GAUGE" "seconds" '{"phase": "'$phase'"}'            
            export "PHASE_DURATION_${phase^^}"="$duration"
            
            # Track milestone
            track_deployment_milestone "phase_${phase}_complete" \
                '{"phase": "'$phase'", "duration": '$duration'}'            ;;
        
        "error")
            log_error "Phase failed: $phase" "MONITOR"
            
            # End phase trace with error
            local trace_var="PHASE_TRACE_${phase^^}"
            local phase_trace="${!trace_var}"
            if [[ -n "$phase_trace" ]]; then
                end_trace "$phase_trace" "error" "Phase failed"
            fi
            
            # Create error alert
            create_alert "deployment_phase_failed" "$ALERT_SEVERITY_ERROR" \
                "Deployment phase failed: $phase" "deployment" \
                '{"phase": "'$phase'", "stack": "'$STACK_NAME'"}'            ;;
    esac
}

# Post-deployment monitoring
monitor_post_deployment() {
    local status="${1:-success}"
    local message="${2:-}"
    
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Running post-deployment monitoring" "MONITOR"
    
    # End deployment trace
    if [[ -n "$DEPLOYMENT_TRACE_ID" ]]; then
        end_trace "$DEPLOYMENT_TRACE_ID" "$status" "$message"
    fi
    
    # Record deployment end
    log_deployment_event "complete" '{"status": "'$status'", "message": "'$message'"}'    
    # Calculate total duration
    local start_metric=$(query_metrics "deployment.start_time" 3600 "raw" | jq -r '.[0].value // 0')
    local total_duration=$(($(date +%s) - start_metric))
    record_performance_metric "deployment.total_duration" "$total_duration" \
        "$METRIC_TYPE_GAUGE" "seconds"
    
    # Create post-deployment snapshot
    create_monitoring_snapshot "post_deployment"
    
    # Generate deployment report
    generate_deployment_report
    
    # Resolve any active deployment alerts
    if [[ "$status" == "success" ]]; then
        resolve_deployment_alerts
    fi
}

# =============================================================================
# MONITORING OPERATIONS
# =============================================================================

# Monitor AWS operation
monitor_aws_operation() {
    local operation="$1"
    local resource_type="$2"
    local resource_id="${3:-}"
    shift 3
    local command="$@"
    
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        # Just execute the command
        eval "$command"
        return $?
    fi
    
    # Start operation trace
    local trace=$(start_trace "aws_$operation" "" \
        '{"operation": "'$operation'", "resource_type": "'$resource_type'", "resource_id": "'$resource_id'"}')
    
    # Record operation start
    local start_time=$(date +%s)
    log_structured_event "DEBUG" "AWS operation started: $operation $resource_type" \
        "aws" "operation_start" '{"operation": "'$operation'", "resource_type": "'$resource_type'"}'    
    # Execute command
    local exit_code=0
    local output
    output=$(eval "$command" 2>&1) || exit_code=$?
    
    # Calculate duration
    local duration=$(($(date +%s) - start_time))
    
    # End trace
    if [[ $exit_code -eq 0 ]]; then
        end_trace "$trace" "ok"
        
        # Log success
        log_infrastructure_event "$resource_type" "$operation" "$resource_id" "success" \
            '{"duration": '$duration'}'        
        # Record metrics
        record_performance_metric "aws.operation.duration" "$duration" \
            "$METRIC_TYPE_HISTOGRAM" "seconds" \
            '{"operation": "'$operation'", "resource_type": "'$resource_type'"}'    else
        end_trace "$trace" "error" "Command failed with exit code $exit_code"
        
        # Log failure
        log_infrastructure_event "$resource_type" "$operation" "$resource_id" "failed" \
            '{"duration": '$duration', "exit_code": '$exit_code', "error": "'$output'"}'        
        # Create alert for critical operations
        if [[ "$operation" =~ ^(create|delete|modify)$ ]]; then
            create_alert "aws_operation_failed" "$ALERT_SEVERITY_ERROR" \
                "AWS operation failed: $operation $resource_type" "infrastructure" \
                '{"operation": "'$operation'", "resource_type": "'$resource_type'", "exit_code": '$exit_code'}'        fi
    fi
    
    # Output the result
    echo "$output"
    return $exit_code
}

# Monitor service health
monitor_service_health() {
    local service="$1"
    local expected_state="${2:-healthy}"
    
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Check service health
    local health_status="unknown"
    local health_details="{}"
    
    case "$service" in
        "n8n")
            health_status=$(check_n8n_health)
            ;;
        "qdrant")
            health_status=$(check_qdrant_health)
            ;;
        "ollama")
            health_status=$(check_ollama_health)
            ;;
        "crawl4ai")
            health_status=$(check_crawl4ai_health)
            ;;
    esac
    
    # Record health metric
    local health_value=0
    [[ "$health_status" == "healthy" ]] && health_value=1
    
    record_performance_metric "service.health" "$health_value" \
        "$METRIC_TYPE_GAUGE" "bool" '{"service": "'$service'"}'    
    # Log health status
    log_structured_event "INFO" "Service health check: $service = $health_status" \
        "health" "check" '{"service": "'$service'", "status": "'$health_status'"}'    
    # Create alert if unhealthy
    if [[ "$health_status" != "$expected_state" ]]; then
        create_alert "service_unhealthy" "$ALERT_SEVERITY_WARNING" \
            "Service unhealthy: $service" "application" \
            '{"service": "'$service'", "status": "'$health_status'", "expected": "'$expected_state'"}'    fi
    
    [[ "$health_status" == "$expected_state" ]]
}

# =============================================================================
# MONITORING UTILITIES
# =============================================================================

# Create monitoring snapshot
create_monitoring_snapshot() {
    local snapshot_name="$1"
    local snapshot_dir="$MONITORING_OUTPUT_DIR/snapshots/$snapshot_name"
    
    log_info "Creating monitoring snapshot: $snapshot_name" "MONITOR"
    
    mkdir -p "$snapshot_dir"
    
    # Save current metrics
    generate_performance_report "$snapshot_dir/metrics.txt" 300
    
    # Save log statistics
    get_log_statistics 300 > "$snapshot_dir/log_stats.json"
    
    # Save active alerts
    get_active_alerts > "$snapshot_dir/alerts.json"
    
    # Save system state
    {
        echo "=== System State ==="
        echo "Date: $(date)"
        echo "Uptime: $(uptime)"
        echo "Memory: $(free -h 2>/dev/null | grep Mem: || vm_stat | head -5)"
        echo "Disk: $(df -h /)"
    } > "$snapshot_dir/system_state.txt"
    
    log_info "Snapshot created: $snapshot_dir" "MONITOR"
}

# Check system health for deployment
check_system_health_for_deployment() {
    log_info "Checking system health for deployment" "MONITOR"
    
    local health_ok=true
    
    # Check CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        log_warn "High CPU usage: ${cpu_usage}%" "MONITOR"
        create_alert "high_cpu_pre_deployment" "$ALERT_SEVERITY_WARNING" \
            "High CPU usage before deployment: ${cpu_usage}%" "system"
        health_ok=false
    fi
    
    # Check memory
    local mem_usage=$(free | grep Mem | awk '{print ($3/$2) * 100}')
    if (( $(echo "$mem_usage > 80" | bc -l) )); then
        log_warn "High memory usage: ${mem_usage}%" "MONITOR"
        create_alert "high_memory_pre_deployment" "$ALERT_SEVERITY_WARNING" \
            "High memory usage before deployment: ${mem_usage}%" "system"
        health_ok=false
    fi
    
    # Check disk space
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    if [[ $disk_usage -gt 90 ]]; then
        log_warn "Low disk space: ${disk_usage}% used" "MONITOR"
        create_alert "low_disk_pre_deployment" "$ALERT_SEVERITY_WARNING" \
            "Low disk space before deployment: ${disk_usage}% used" "system"
        health_ok=false
    fi
    
    if [[ "$health_ok" == "true" ]]; then
        log_info "System health check passed" "MONITOR"
    else
        log_warn "System health check detected issues" "MONITOR"
    fi
    
    return 0  # Don't fail deployment, just warn
}

# Generate deployment report
generate_deployment_report() {
    local report_file="$MONITORING_OUTPUT_DIR/deployment_report.txt"
    
    log_info "Generating deployment report" "MONITOR"
    
    {
        echo "=== DEPLOYMENT REPORT ==="
        echo "Generated: $(date)"
        echo "Stack: ${STACK_NAME:-unknown}"
        echo "Deployment ID: ${DEPLOYMENT_ID:-unknown}"
        echo "Profile: ${MONITORING_PROFILE:-unknown}"
        echo ""
        
        echo "=== DEPLOYMENT SUMMARY ==="
        local total_duration=$(query_metrics "deployment.total_duration" 3600 "raw" | \
            jq -r '.[0].value // "N/A"')
        echo "Total Duration: ${total_duration}s"
        echo ""
        
        echo "=== PHASE DURATIONS ==="
        query_metrics "deployment.phase.duration" 3600 "raw" | \
            jq -r '.[] | "\(.labels.phase): \(.value)s"' | sort
        echo ""
        
        echo "=== AWS OPERATIONS ==="
        query_metrics "aws.operation.duration" 3600 "raw" | \
            jq -r 'group_by(.labels.operation) | 
                map("\(.[0].labels.operation): count=\(length), avg=\([.[].value] | add/length | floor)s")[]'
        echo ""
        
        echo "=== SERVICE HEALTH ==="
        query_metrics "service.health" 300 "raw" | \
            jq -r 'group_by(.labels.service) | 
                map({service: .[0].labels.service, status: (if .[0].value == 1 then "healthy" else "unhealthy" end)}) |
                .[] | "\(.service): \(.status)"'
        echo ""
        
        echo "=== ALERTS ==="
        get_active_alerts | jq -r '.[] | "[\(.severity)] \(.name): \(.message)"'
        echo ""
        
        echo "=== ERRORS ==="
        query_logs '.level == "ERROR"' 3600 10 | \
            jq -r '.[] | "\(.timestamp | strftime("%H:%M:%S")) - \(.message)"'
        echo ""
        
        echo "=== PERFORMANCE METRICS ==="
        generate_performance_report "" 3600 | grep -A20 "System Metrics Summary"
    } > "$report_file"
    
    log_info "Deployment report generated: $report_file" "MONITOR"
    
    # Display summary
    echo ""
    echo "Deployment Report Summary:"
    grep -E "(Total Duration|healthy|ERROR|CRITICAL)" "$report_file" | head -10
    echo ""
    echo "Full report: $report_file"
}

# Resolve deployment alerts
resolve_deployment_alerts() {
    log_info "Resolving deployment alerts" "MONITOR"
    
    # Get active deployment alerts
    local alerts=$(get_active_alerts "" "deployment" | jq -r '.[] | .id')
    
    for alert_id in $alerts; do
        resolve_alert "$alert_id" "Deployment completed successfully"
    done
}

# =============================================================================
# SERVICE HEALTH CHECKS
# =============================================================================

# Check n8n health
check_n8n_health() {
    local instance_ip=$(get_variable "INSTANCE_PUBLIC_IP" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$instance_ip" ]]; then
        if curl -s -f "http://${instance_ip}:5678/healthz" >/dev/null 2>&1; then
            echo "healthy"
        else
            echo "unhealthy"
        fi
    else
        echo "unknown"
    fi
}

# Check Qdrant health
check_qdrant_health() {
    local instance_ip=$(get_variable "INSTANCE_PUBLIC_IP" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$instance_ip" ]]; then
        if curl -s -f "http://${instance_ip}:6333/health" >/dev/null 2>&1; then
            echo "healthy"
        else
            echo "unhealthy"
        fi
    else
        echo "unknown"
    fi
}

# Check Ollama health
check_ollama_health() {
    local instance_ip=$(get_variable "INSTANCE_PUBLIC_IP" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$instance_ip" ]]; then
        if curl -s -f "http://${instance_ip}:11434/api/health" >/dev/null 2>&1; then
            echo "healthy"
        else
            echo "unhealthy"
        fi
    else
        echo "unknown"
    fi
}

# Check Crawl4AI health
check_crawl4ai_health() {
    local instance_ip=$(get_variable "INSTANCE_PUBLIC_IP" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$instance_ip" ]]; then
        if curl -s -f "http://${instance_ip}:11235/health" >/dev/null 2>&1; then
            echo "healthy"
        else
            echo "unhealthy"
        fi
    else
        echo "unknown"
    fi
}

# =============================================================================
# MONITORING CLEANUP
# =============================================================================

# Cleanup deployment monitoring
cleanup_deployment_monitoring() {
    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Cleaning up deployment monitoring" "MONITOR"
    
    # Stop debug capture if running
    if [[ "$MONITORING_PROFILE" == "$MONITOR_PROFILE_DEBUG" ]]; then
        stop_debug_capture
    fi
    
    # Generate final reports
    generate_deployment_report
    generate_aggregation_report "$MONITORING_OUTPUT_DIR/log_aggregation_report.txt"
    generate_performance_report "$MONITORING_OUTPUT_DIR/performance_report.txt"
    generate_observability_report "$MONITORING_OUTPUT_DIR/observability_report.txt"
    
    # Export metrics to CloudWatch if configured
    if [[ -n "${CLOUDWATCH_METRICS_NAMESPACE:-}" ]]; then
        export_metrics_to_cloudwatch "$CLOUDWATCH_METRICS_NAMESPACE"
    fi
    
    # Cleanup components
    cleanup_log_aggregation
    cleanup_performance_metrics
    cleanup_observability
    cleanup_alerting
    cleanup_dashboards
    cleanup_debug_tools
    cleanup_structured_logging
    
    # Archive monitoring data
    if [[ -d "$MONITORING_OUTPUT_DIR" ]]; then
        local archive_name="monitoring_${STACK_NAME}_${DEPLOYMENT_ID}_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "/tmp/$archive_name" -C "$(dirname "$MONITORING_OUTPUT_DIR")" "$(basename "$MONITORING_OUTPUT_DIR")"
        log_info "Monitoring data archived: /tmp/$archive_name" "MONITOR"
    fi
    
    log_info "Deployment monitoring cleanup complete" "MONITOR"
}