#!/usr/bin/env bash
# =============================================================================
# Unity Monitor Service - Unified Monitoring and Observability
# =============================================================================
# Provides comprehensive monitoring, health checks, alerting, and analytics
# Integrates all monitoring modules into a unified service interface
# Compatible with bash 3.x+ (macOS) and bash 4.x+ (Linux)
# =============================================================================

set -euo pipefail

# Service identification
readonly SERVICE_NAME="unity-monitor"
readonly SERVICE_VERSION="2.0.0"
readonly SERVICE_DESCRIPTION="Unified monitoring, telemetry, and observability service"

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core
source "$SCRIPT_DIR/../core/unity-core.sh"

# Source monitoring modules
source "$PROJECT_ROOT/lib/modules/monitoring/health.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/alerting.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/metrics.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/log_aggregation.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/structured_logging.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/observability.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/performance_metrics.sh"
source "$PROJECT_ROOT/lib/modules/monitoring/dashboards.sh"

# =============================================================================
# SERVICE CONFIGURATION
# =============================================================================

# Monitoring configuration
MONITOR_CONFIG_FILE="${MONITOR_CONFIG_FILE:-$PROJECT_ROOT/config/monitoring.yml}"
MONITOR_STATE_DIR="${MONITOR_STATE_DIR:-$PROJECT_ROOT/.unity/monitoring}"
MONITOR_METRICS_DIR="${MONITOR_METRICS_DIR:-$MONITOR_STATE_DIR/metrics}"
MONITOR_LOGS_DIR="${MONITOR_LOGS_DIR:-$MONITOR_STATE_DIR/logs}"
MONITOR_ALERTS_DIR="${MONITOR_ALERTS_DIR:-$MONITOR_STATE_DIR/alerts}"

# Health check configuration
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"
AUTO_RECOVERY_ENABLED="${AUTO_RECOVERY_ENABLED:-true}"

# Alert configuration
ALERT_CHANNELS_ENABLED="${ALERT_CHANNELS_ENABLED:-log,console}"
ALERT_THROTTLE_MINUTES="${ALERT_THROTTLE_MINUTES:-5}"
ALERT_AGGREGATION_ENABLED="${ALERT_AGGREGATION_ENABLED:-true}"

# Performance configuration
PERF_COLLECTION_INTERVAL="${PERF_COLLECTION_INTERVAL:-30}"
PERF_RETENTION_DAYS="${PERF_RETENTION_DAYS:-30}"
PERF_ANALYTICS_ENABLED="${PERF_ANALYTICS_ENABLED:-true}"

# Service state (bash 3/4 compatible)
MONITOR_SERVICE_INITIALIZED=false
MONITOR_SERVICE_RUNNING=false
declare -A MONITOR_HEALTH_STATUS 2>/dev/null || MONITOR_HEALTH_STATUS=()
declare -A MONITOR_ALERT_HISTORY 2>/dev/null || MONITOR_ALERT_HISTORY=()
declare -A MONITOR_METRIC_COLLECTORS 2>/dev/null || MONITOR_METRIC_COLLECTORS=()

# =============================================================================
# SERVICE INITIALIZATION
# =============================================================================

# Initialize monitoring service
unity_monitor_init() {
    unity_emit_event "MONITOR_SERVICE_INIT_STARTED" "$SERVICE_NAME"
    
    # Create directory structure
    local dirs=("$MONITOR_STATE_DIR" "$MONITOR_METRICS_DIR" "$MONITOR_LOGS_DIR" "$MONITOR_ALERTS_DIR")
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" || {
            unity_log "ERROR" "Failed to create directory: $dir"
            return $UNITY_ERROR_EXECUTION
        }
    done
    
    # Initialize monitoring subsystems
    _init_health_monitoring || return $?
    _init_alert_system || return $?
    _init_metrics_collection || return $?
    _init_log_aggregation || return $?
    _init_performance_analytics || return $?
    
    # Register event handlers
    _register_monitoring_handlers
    
    # Load saved state if exists
    _load_monitor_state
    
    MONITOR_SERVICE_INITIALIZED=true
    unity_emit_event "MONITOR_SERVICE_INIT_COMPLETED" "$SERVICE_NAME"
    unity_log "SUCCESS" "✅ Monitor Service initialized (v$SERVICE_VERSION)"
    return $UNITY_SUCCESS
}

# Initialize health monitoring subsystem
_init_health_monitoring() {
    unity_log "INFO" "Initializing health monitoring subsystem..."
    
    # Create health check registry
    local health_registry="$MONITOR_STATE_DIR/health_registry.conf"
    if [[ ! -f "$health_registry" ]]; then
        cat > "$health_registry" << 'EOF'
# Unity Health Check Registry
# Format: service:check_type:interval:timeout:retries
system:basic:60:30:3
aws:connectivity:300:60:2
docker:service:120:45:3
application:endpoint:60:30:3
infrastructure:resources:300:90:2
EOF
    fi
    
    # Initialize health status tracking
    echo "# Unity Health Status - $(date -Iseconds)" > "$MONITOR_STATE_DIR/health_status.txt"
    
    return $UNITY_SUCCESS
}

# Initialize alert system
_init_alert_system() {
    unity_log "INFO" "Initializing alert system..."
    
    # Configure alert channels
    IFS=',' read -ra channels <<< "$ALERT_CHANNELS_ENABLED"
    for channel in "${channels[@]}"; do
        case "$channel" in
            log|console)
                # Built-in channels, always available
                ;;
            webhook)
                if [[ -n "${ALERT_WEBHOOK_URL:-}" ]]; then
                    ALERT_CHANNELS+=("$ALERT_CHANNEL_WEBHOOK")
                fi
                ;;
            sns)
                if [[ -n "${ALERT_SNS_TOPIC:-}" ]]; then
                    ALERT_CHANNELS+=("$ALERT_CHANNEL_SNS")
                fi
                ;;
            slack)
                if [[ -n "${ALERT_SLACK_WEBHOOK:-}" ]]; then
                    ALERT_CHANNELS+=("$ALERT_CHANNEL_SLACK")
                fi
                ;;
            email)
                if [[ -n "${ALERT_EMAIL_ADDRESS:-}" ]]; then
                    ALERT_CHANNELS+=("$ALERT_CHANNEL_EMAIL")
                fi
                ;;
        esac
    done
    
    # Initialize alert history
    touch "$MONITOR_ALERTS_DIR/alert_history.log"
    
    return $UNITY_SUCCESS
}

# Initialize metrics collection
_init_metrics_collection() {
    unity_log "INFO" "Initializing metrics collection..."
    
    # Register default metric collectors
    _register_metric_collector "system" "_collect_system_metrics" "$PERF_COLLECTION_INTERVAL"
    _register_metric_collector "application" "_collect_application_metrics" "60"
    _register_metric_collector "aws" "_collect_aws_metrics" "300"
    
    # Initialize metrics storage
    local metrics_db="$MONITOR_METRICS_DIR/metrics.db"
    if [[ ! -f "$metrics_db" ]]; then
        echo "# Unity Metrics Database - $(date -Iseconds)" > "$metrics_db"
        echo "# timestamp,metric_name,value,unit,tags" >> "$metrics_db"
    fi
    
    return $UNITY_SUCCESS
}

# Initialize log aggregation
_init_log_aggregation() {
    unity_log "INFO" "Initializing log aggregation..."
    
    # Configure log sources
    local log_sources=(
        "system:/var/log/syslog"
        "application:$PROJECT_ROOT/logs"
        "deployment:$PROJECT_ROOT/deployment-logs"
        "unity:$PROJECT_ROOT/logs/unity"
    )
    
    # Create log aggregation config
    local agg_config="$MONITOR_STATE_DIR/log_aggregation.conf"
    printf "%s\n" "${log_sources[@]}" > "$agg_config"
    
    # Initialize log aggregation
    LOG_AGG_ENABLED=true
    LOG_AGG_STORAGE_DIR="$MONITOR_LOGS_DIR/aggregated"
    mkdir -p "$LOG_AGG_STORAGE_DIR"
    
    return $UNITY_SUCCESS
}

# Initialize performance analytics
_init_performance_analytics() {
    unity_log "INFO" "Initializing performance analytics..."
    
    # Create performance baseline
    local perf_baseline="$MONITOR_STATE_DIR/performance_baseline.json"
    if [[ ! -f "$perf_baseline" ]]; then
        cat > "$perf_baseline" << 'EOF'
{
  "deployment_time": {"p50": 180, "p95": 240, "p99": 300},
  "api_response_time": {"p50": 100, "p95": 500, "p99": 1000},
  "resource_usage": {
    "cpu": {"normal": 20, "warning": 70, "critical": 90},
    "memory": {"normal": 50, "warning": 80, "critical": 95},
    "disk": {"normal": 60, "warning": 80, "critical": 90}
  }
}
EOF
    fi
    
    return $UNITY_SUCCESS
}

# =============================================================================
# HEALTH CHECK ORCHESTRATION
# =============================================================================

# Run comprehensive health checks
unity_monitor_health_check() {
    local target="${1:-all}"
    local async="${2:-false}"
    
    unity_log "INFO" "🏥 Running health checks for: $target"
    unity_emit_event "HEALTH_CHECK_STARTED" "$SERVICE_NAME" "$target"
    
    local overall_status="healthy"
    local health_report=""
    
    # Run health checks based on target
    case "$target" in
        all)
            _check_system_health || overall_status="degraded"
            _check_service_health || overall_status="degraded"
            _check_infrastructure_health || overall_status="degraded"
            _check_application_health || overall_status="degraded"
            ;;
        system|service|infrastructure|application)
            "_check_${target}_health" || overall_status="unhealthy"
            ;;
        *)
            # Check specific service
            _check_specific_service_health "$target" || overall_status="unhealthy"
            ;;
    esac
    
    # Update health status
    _update_health_status "$target" "$overall_status"
    
    # Handle unhealthy status
    if [[ "$overall_status" != "healthy" ]] && [[ "$AUTO_RECOVERY_ENABLED" == "true" ]]; then
        unity_log "WARN" "Unhealthy status detected, initiating auto-recovery..."
        _initiate_auto_recovery "$target" "$overall_status"
    fi
    
    unity_emit_event "HEALTH_CHECK_COMPLETED" "$SERVICE_NAME" "$target:$overall_status"
    
    # Return status code based on health
    case "$overall_status" in
        healthy) return 0 ;;
        degraded) return 1 ;;
        unhealthy) return 2 ;;
        *) return 3 ;;
    esac
}

# Check system health
_check_system_health() {
    unity_log "DEBUG" "Checking system health..."
    
    local status="healthy"
    local issues=()
    
    # CPU usage check
    local cpu_usage
    cpu_usage=$(_get_cpu_usage) || cpu_usage=0
    if (( cpu_usage > 90 )); then
        status="unhealthy"
        issues+=("High CPU usage: ${cpu_usage}%")
    elif (( cpu_usage > 70 )); then
        status="degraded"
        issues+=("Elevated CPU usage: ${cpu_usage}%")
    fi
    
    # Memory usage check
    local mem_usage
    mem_usage=$(_get_memory_usage) || mem_usage=0
    if (( mem_usage > 95 )); then
        status="unhealthy"
        issues+=("Critical memory usage: ${mem_usage}%")
    elif (( mem_usage > 80 )); then
        status="degraded"
        issues+=("High memory usage: ${mem_usage}%")
    fi
    
    # Disk usage check
    local disk_usage
    disk_usage=$(_get_disk_usage) || disk_usage=0
    if (( disk_usage > 90 )); then
        status="unhealthy"
        issues+=("Critical disk usage: ${disk_usage}%")
    elif (( disk_usage > 80 )); then
        status="degraded"
        issues+=("High disk usage: ${disk_usage}%")
    fi
    
    # Record metrics
    _record_metric "system.cpu.usage" "$cpu_usage" "percent"
    _record_metric "system.memory.usage" "$mem_usage" "percent"
    _record_metric "system.disk.usage" "$disk_usage" "percent"
    
    # Generate alert if needed
    if [[ "$status" != "healthy" ]]; then
        local severity="warning"
        [[ "$status" == "unhealthy" ]] && severity="critical"
        
        unity_monitor_alert "$severity" "System Health Issues" \
            "$(printf '%s\n' "${issues[@]}")"
    fi
    
    [[ "$status" == "healthy" ]]
}

# Check service health
_check_service_health() {
    unity_log "DEBUG" "Checking service health..."
    
    local status="healthy"
    local unhealthy_services=()
    
    # Check Docker services if available
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        local containers
        containers=$(docker ps --format "{{.Names}}:{{.Status}}" 2>/dev/null || echo "")
        
        while IFS=':' read -r name container_status; do
            if [[ -n "$name" ]] && [[ ! "$container_status" =~ Up ]]; then
                status="unhealthy"
                unhealthy_services+=("Docker container $name is not running")
            fi
        done <<< "$containers"
    fi
    
    # Check Unity services
    for service_name in "${!UNITY_SERVICE_STATUS[@]}"; do
        if [[ "${UNITY_SERVICE_STATUS[$service_name]}" != "running" ]]; then
            status="degraded"
            unhealthy_services+=("Unity service $service_name is not running")
        fi
    done
    
    # Generate alerts for unhealthy services
    if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
        unity_monitor_alert "error" "Service Health Issues" \
            "$(printf '%s\n' "${unhealthy_services[@]}")"
    fi
    
    [[ "$status" == "healthy" ]]
}

# Check infrastructure health
_check_infrastructure_health() {
    unity_log "DEBUG" "Checking infrastructure health..."
    
    local status="healthy"
    
    # Check AWS connectivity if AWS CLI is available
    if command -v aws &>/dev/null; then
        if ! aws sts get-caller-identity &>/dev/null 2>&1; then
            status="unhealthy"
            unity_monitor_alert "error" "AWS Connectivity Issue" \
                "Unable to connect to AWS services"
        fi
    fi
    
    # Check network connectivity
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null 2>&1; then
        status="degraded"
        unity_monitor_alert "warning" "Network Connectivity Issue" \
            "Unable to reach external networks"
    fi
    
    [[ "$status" == "healthy" ]]
}

# Check application health
_check_application_health() {
    unity_log "DEBUG" "Checking application health..."
    
    local status="healthy"
    local app_issues=()
    
    # Check application endpoints if configured
    if [[ -f "$MONITOR_STATE_DIR/app_endpoints.conf" ]]; then
        while IFS='|' read -r name url expected_code timeout; do
            if [[ -n "$name" ]] && [[ -n "$url" ]]; then
                local response_code
                response_code=$(curl -s -o /dev/null -w "%{http_code}" \
                    --max-time "${timeout:-5}" "$url" 2>/dev/null || echo "000")
                
                if [[ "$response_code" != "${expected_code:-200}" ]]; then
                    status="unhealthy"
                    app_issues+=("$name endpoint failed (HTTP $response_code)")
                fi
                
                # Record endpoint metric
                _record_metric "app.endpoint.$name.response_code" "$response_code" "code"
            fi
        done < "$MONITOR_STATE_DIR/app_endpoints.conf"
    fi
    
    # Alert on issues
    if [[ ${#app_issues[@]} -gt 0 ]]; then
        unity_monitor_alert "error" "Application Health Issues" \
            "$(printf '%s\n' "${app_issues[@]}")"
    fi
    
    [[ "$status" == "healthy" ]]
}

# Update health status in tracking file
_update_health_status() {
    local target="$1"
    local status="$2"
    local timestamp=$(date -Iseconds)
    
    # Update health status file
    echo "$timestamp|$target|$status" >> "$MONITOR_STATE_DIR/health_status.txt"
    
    # Update in-memory status if bash 4+
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        MONITOR_HEALTH_STATUS["$target"]="$status"
    fi
}

# Check specific service health
_check_specific_service_health() {
    local service="$1"
    unity_log "DEBUG" "Checking health for specific service: $service"
    
    # Default implementation - can be extended
    return 0
}

# =============================================================================
# INTELLIGENT ALERT MANAGEMENT
# =============================================================================

# Send alert with intelligent routing and throttling
unity_monitor_alert() {
    local severity="${1:-warning}"
    local title="$2"
    local message="$3"
    local tags="${4:-}"
    
    # Check alert throttling
    local alert_key="${severity}:${title}"
    if _is_alert_throttled "$alert_key"; then
        unity_log "DEBUG" "Alert throttled: $title"
        return $UNITY_SUCCESS
    fi
    
    # Create alert record
    local timestamp=$(date -Iseconds)
    local alert_id="alert_$(date +%s)_$$"
    local alert_file="$MONITOR_ALERTS_DIR/$alert_id.json"
    
    cat > "$alert_file" << EOF
{
  "id": "$alert_id",
  "timestamp": "$timestamp",
  "severity": "$severity",
  "title": "$title",
  "message": "$message",
  "tags": "$tags",
  "status": "active"
}
EOF
    
    # Route alert to configured channels
    for channel in "${ALERT_CHANNELS[@]}"; do
        case "$channel" in
            log)
                _send_alert_to_log "$severity" "$title" "$message"
                ;;
            console)
                _send_alert_to_console "$severity" "$title" "$message"
                ;;
            webhook)
                _send_alert_to_webhook "$severity" "$title" "$message" "$alert_id"
                ;;
            sns)
                _send_alert_to_sns "$severity" "$title" "$message"
                ;;
            slack)
                _send_alert_to_slack "$severity" "$title" "$message"
                ;;
            email)
                _send_alert_to_email "$severity" "$title" "$message"
                ;;
        esac
    done
    
    # Update alert history
    _update_alert_history "$alert_key"
    
    # Emit alert event
    unity_emit_event "ALERT_SENT" "$SERVICE_NAME" "$alert_id:$severity:$title"
    
    return $UNITY_SUCCESS
}

# Check if alert is throttled
_is_alert_throttled() {
    local alert_key="$1"
    local throttle_file="$MONITOR_STATE_DIR/alert_throttle.txt"
    
    if [[ ! -f "$throttle_file" ]]; then
        return 1  # Not throttled
    fi
    
    # Check last alert time
    local last_alert_time
    last_alert_time=$(grep "^$alert_key:" "$throttle_file" 2>/dev/null | cut -d: -f2)
    
    if [[ -n "$last_alert_time" ]]; then
        local current_time=$(date +%s)
        local throttle_seconds=$((ALERT_THROTTLE_MINUTES * 60))
        
        if (( current_time - last_alert_time < throttle_seconds )); then
            return 0  # Throttled
        fi
    fi
    
    return 1  # Not throttled
}

# Update alert history
_update_alert_history() {
    local alert_key="$1"
    local current_time=$(date +%s)
    local throttle_file="$MONITOR_STATE_DIR/alert_throttle.txt"
    
    # Update throttle file
    if [[ -f "$throttle_file" ]]; then
        grep -v "^$alert_key:" "$throttle_file" > "$throttle_file.tmp" || true
        mv "$throttle_file.tmp" "$throttle_file"
    fi
    
    echo "$alert_key:$current_time" >> "$throttle_file"
}

# =============================================================================
# PERFORMANCE ANALYTICS AND METRICS
# =============================================================================

# Collect and analyze performance metrics
unity_monitor_collect_metrics() {
    local async="${1:-true}"
    
    unity_log "DEBUG" "Collecting performance metrics..."
    
    if [[ "$async" == "true" ]]; then
        # Run collectors asynchronously
        for collector_name in "${!MONITOR_METRIC_COLLECTORS[@]}"; do
            local collector_func="${MONITOR_METRIC_COLLECTORS[$collector_name]}"
            ( $collector_func ) &
        done
        
        # Don't wait for async collectors
        unity_log "DEBUG" "Async metric collection initiated"
    else
        # Run collectors synchronously
        for collector_name in "${!MONITOR_METRIC_COLLECTORS[@]}"; do
            local collector_func="${MONITOR_METRIC_COLLECTORS[$collector_name]}"
            $collector_func || unity_log "WARN" "Metric collector failed: $collector_name"
        done
    fi
    
    return $UNITY_SUCCESS
}

# Register metric collector
_register_metric_collector() {
    local name="$1"
    local func="$2"
    local interval="${3:-60}"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        MONITOR_METRIC_COLLECTORS["$name"]="$func"
    else
        # Bash 3 fallback
        echo "$name:$func:$interval" >> "$MONITOR_STATE_DIR/metric_collectors.conf"
    fi
}

# Collect system metrics
_collect_system_metrics() {
    local timestamp=$(date -Iseconds)
    
    # CPU metrics
    local cpu_usage=$(_get_cpu_usage)
    _record_metric "system.cpu.usage" "$cpu_usage" "percent"
    
    # Memory metrics
    local mem_usage=$(_get_memory_usage)
    local mem_total=$(_get_memory_total)
    local mem_free=$(_get_memory_free)
    _record_metric "system.memory.usage" "$mem_usage" "percent"
    _record_metric "system.memory.total" "$mem_total" "megabytes"
    _record_metric "system.memory.free" "$mem_free" "megabytes"
    
    # Disk metrics
    local disk_usage=$(_get_disk_usage)
    _record_metric "system.disk.usage" "$disk_usage" "percent"
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    _record_metric "system.load.1min" "$load_avg" "load"
    
    # Process count
    local proc_count=$(ps aux | wc -l)
    _record_metric "system.processes.count" "$proc_count" "count"
}

# Collect application metrics
_collect_application_metrics() {
    local timestamp=$(date -Iseconds)
    
    # Unity service metrics
    local active_services=0
    local total_services=0
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        total_services=${#UNITY_SERVICES[@]}
        for status in "${UNITY_SERVICE_STATUS[@]}"; do
            [[ "$status" == "running" ]] && ((active_services++))
        done
    else
        # Bash 3 fallback
        total_services=$(wc -l < "$UNITY_STATE_DIR/services.txt" 2>/dev/null || echo 0)
        active_services=$(grep -c "running" "$UNITY_STATE_DIR/service_status.txt" 2>/dev/null || echo 0)
    fi
    
    _record_metric "app.unity.services.total" "$total_services" "count"
    _record_metric "app.unity.services.active" "$active_services" "count"
    
    # Event metrics
    local event_count=$(find "$UNITY_STATE_DIR/events" -name "*.event" -mmin -5 2>/dev/null | wc -l)
    _record_metric "app.unity.events.recent" "$event_count" "count"
}

# Collect AWS metrics
_collect_aws_metrics() {
    if ! command -v aws &>/dev/null; then
        return $UNITY_SUCCESS
    fi
    
    local timestamp=$(date -Iseconds)
    
    # EC2 instance count
    local instance_count
    instance_count=$(aws ec2 describe-instances \
        --query 'length(Reservations[].Instances[?State.Name==`running`])' \
        --output text 2>/dev/null || echo 0)
    _record_metric "aws.ec2.instances.running" "$instance_count" "count"
    
    # Stack status
    if [[ -n "${STACK_NAME:-}" ]]; then
        local stack_status
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        local status_code=0
        case "$stack_status" in
            *COMPLETE) status_code=1 ;;
            *PROGRESS) status_code=2 ;;
            *FAILED) status_code=3 ;;
        esac
        
        _record_metric "aws.stack.status" "$status_code" "code" "stack:$STACK_NAME"
    fi
}

# Record metric
_record_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-value}"
    local tags="${4:-}"
    local timestamp=$(date -Iseconds)
    
    # Store in metrics database
    echo "$timestamp,$metric_name,$value,$unit,$tags" >> "$MONITOR_METRICS_DIR/metrics.db"
    
    # Store in time-series format for quick access
    local date_dir="$MONITOR_METRICS_DIR/$(date +%Y/%m/%d)"
    mkdir -p "$date_dir"
    echo "$timestamp,$value" >> "$date_dir/$metric_name.tsv"
    
    # Check thresholds and generate alerts if needed
    _check_metric_thresholds "$metric_name" "$value"
}

# Check metric thresholds
_check_metric_thresholds() {
    local metric_name="$1"
    local value="$2"
    
    # Check against performance baseline thresholds
    case "$metric_name" in
        system.cpu.usage)
            if (( value > 90 )); then
                unity_monitor_alert "critical" "High CPU Usage" "CPU usage at ${value}%"
            elif (( value > 70 )); then
                unity_monitor_alert "warning" "Elevated CPU Usage" "CPU usage at ${value}%"
            fi
            ;;
        system.memory.usage)
            if (( value > 95 )); then
                unity_monitor_alert "critical" "Critical Memory Usage" "Memory usage at ${value}%"
            elif (( value > 80 )); then
                unity_monitor_alert "warning" "High Memory Usage" "Memory usage at ${value}%"
            fi
            ;;
        system.disk.usage)
            if (( value > 90 )); then
                unity_monitor_alert "critical" "Critical Disk Usage" "Disk usage at ${value}%"
            elif (( value > 80 )); then
                unity_monitor_alert "warning" "High Disk Usage" "Disk usage at ${value}%"
            fi
            ;;
    esac
}

# =============================================================================
# LOG MANAGEMENT AND ANALYSIS
# =============================================================================

# Aggregate logs from multiple sources
unity_monitor_aggregate_logs() {
    local sources="${1:-all}"
    local output_format="${2:-json}"
    
    unity_log "INFO" "Aggregating logs from sources: $sources"
    
    # Initialize log aggregation
    init_log_aggregation || return $?
    
    # Start aggregation based on mode
    case "$LOG_AGG_MODE" in
        "realtime")
            start_realtime_aggregation "$sources"
            ;;
        "batch")
            aggregate_logs "$sources"
            ;;
        "stream")
            start_stream_aggregation "$sources"
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# Analyze logs for patterns and anomalies
unity_monitor_analyze_logs() {
    local analysis_type="${1:-pattern}"
    local time_range="${2:-1h}"
    
    unity_log "INFO" "Analyzing logs - Type: $analysis_type, Range: $time_range"
    
    # Use the analyze_patterns function which exists in log_aggregation.sh
    case "$analysis_type" in
        pattern|anomaly|trend|correlation)
            # Call the generic analyze_patterns function with parameters
            analyze_patterns "$analysis_type" "$time_range"
            ;;
        *)
            unity_log "ERROR" "Unknown analysis type: $analysis_type"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# =============================================================================
# DISTRIBUTED TRACING
# =============================================================================

# Start trace for operation
unity_monitor_start_trace() {
    local operation="$1"
    local parent_trace_id="${2:-}"
    
    # Generate trace ID
    local trace_id="trace_$(date +%s%N)_$$"
    local span_id="span_$(date +%s%N)_$$"
    
    # Create trace record
    local trace_file="$MONITOR_STATE_DIR/traces/$trace_id.json"
    mkdir -p "$(dirname "$trace_file")"
    
    cat > "$trace_file" << EOF
{
  "trace_id": "$trace_id",
  "span_id": "$span_id",
  "parent_trace_id": "$parent_trace_id",
  "operation": "$operation",
  "start_time": "$(date -Iseconds)",
  "status": "active",
  "tags": {}
}
EOF
    
    # Export trace context
    export UNITY_TRACE_ID="$trace_id"
    export UNITY_SPAN_ID="$span_id"
    
    echo "$trace_id"
}

# End trace
unity_monitor_end_trace() {
    local trace_id="${1:-$UNITY_TRACE_ID}"
    local status="${2:-success}"
    
    if [[ -z "$trace_id" ]]; then
        return $UNITY_ERROR_VALIDATION
    fi
    
    local trace_file="$MONITOR_STATE_DIR/traces/$trace_id.json"
    if [[ ! -f "$trace_file" ]]; then
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Update trace with end time and status
    local end_time=$(date -Iseconds)
    local temp_file="$trace_file.tmp"
    
    jq --arg end_time "$end_time" --arg status "$status" \
        '.end_time = $end_time | .status = $status' \
        "$trace_file" > "$temp_file" && mv "$temp_file" "$trace_file"
    
    return $UNITY_SUCCESS
}

# =============================================================================
# AUTO-RECOVERY MECHANISMS
# =============================================================================

# Initiate auto-recovery for unhealthy components
_initiate_auto_recovery() {
    local target="$1"
    local status="$2"
    
    unity_log "INFO" "🔧 Initiating auto-recovery for $target (status: $status)"
    unity_emit_event "AUTO_RECOVERY_STARTED" "$SERVICE_NAME" "$target"
    
    local recovery_success=false
    
    case "$target" in
        system)
            _recover_system_health && recovery_success=true
            ;;
        service)
            _recover_service_health && recovery_success=true
            ;;
        infrastructure)
            _recover_infrastructure_health && recovery_success=true
            ;;
        application)
            _recover_application_health && recovery_success=true
            ;;
        *)
            _recover_specific_service "$target" && recovery_success=true
            ;;
    esac
    
    if [[ "$recovery_success" == "true" ]]; then
        unity_log "SUCCESS" "✅ Auto-recovery completed successfully for $target"
        unity_monitor_alert "info" "Auto-Recovery Success" \
            "Successfully recovered $target from $status state"
    else
        unity_log "ERROR" "❌ Auto-recovery failed for $target"
        unity_monitor_alert "critical" "Auto-Recovery Failed" \
            "Failed to recover $target from $status state. Manual intervention required."
    fi
    
    unity_emit_event "AUTO_RECOVERY_COMPLETED" "$SERVICE_NAME" "$target:$recovery_success"
}

# Recover system health issues
_recover_system_health() {
    unity_log "INFO" "Attempting system health recovery..."
    
    # Clear system caches if memory is high
    local mem_usage=$(_get_memory_usage)
    if (( mem_usage > 80 )); then
        unity_log "INFO" "Clearing system caches..."
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi
    
    # Clean up disk space if needed
    local disk_usage=$(_get_disk_usage)
    if (( disk_usage > 80 )); then
        unity_log "INFO" "Cleaning up disk space..."
        # Clean old logs
        find "$PROJECT_ROOT/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
        find "$MONITOR_METRICS_DIR" -name "*.tsv" -mtime +30 -delete 2>/dev/null || true
    fi
    
    # Recheck health
    _check_system_health
}

# Recover service health issues
_recover_service_health() {
    unity_log "INFO" "Attempting service health recovery..."
    
    # Try to restart stopped Unity services
    for service_name in "${!UNITY_SERVICE_STATUS[@]}"; do
        if [[ "${UNITY_SERVICE_STATUS[$service_name]}" != "running" ]]; then
            unity_log "INFO" "Attempting to restart service: $service_name"
            # Attempt service restart logic here
        fi
    done
    
    # Check Docker containers if available
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        # Restart stopped containers
        local stopped_containers
        stopped_containers=$(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null || echo "")
        
        while IFS= read -r container; do
            if [[ -n "$container" ]]; then
                unity_log "INFO" "Attempting to restart container: $container"
                docker start "$container" 2>/dev/null || true
            fi
        done <<< "$stopped_containers"
    fi
    
    # Recheck health
    _check_service_health
}

# Recover infrastructure health issues
_recover_infrastructure_health() {
    unity_log "INFO" "Attempting infrastructure health recovery..."
    
    # Check and refresh AWS credentials if needed
    if command -v aws &>/dev/null; then
        unity_log "INFO" "Refreshing AWS credentials..."
        # Attempt to refresh credentials
        aws sts get-caller-identity &>/dev/null || {
            unity_log "WARN" "AWS credential refresh failed"
            return 1
        }
    fi
    
    # Check network connectivity
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        unity_log "INFO" "Attempting network recovery..."
        # Basic network recovery attempts
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS network recovery
            sudo dscacheutil -flushcache 2>/dev/null || true
        else
            # Linux network recovery
            sudo systemctl restart NetworkManager 2>/dev/null || \
            sudo service network-manager restart 2>/dev/null || true
        fi
    fi
    
    # Recheck health
    _check_infrastructure_health
}

# Recover application health issues
_recover_application_health() {
    unity_log "INFO" "Attempting application health recovery..."
    
    # Application-specific recovery logic
    # This is a placeholder - implement based on specific application needs
    
    # Recheck health
    _check_application_health
}

# Recover specific service
_recover_specific_service() {
    local service="$1"
    unity_log "INFO" "Attempting recovery for specific service: $service"
    
    # Service-specific recovery logic
    case "$service" in
        unity-*)
            # Unity service recovery
            unity_log "INFO" "Attempting Unity service recovery for: $service"
            ;;
        *)
            # Generic service recovery
            unity_log "INFO" "Generic recovery for: $service"
            ;;
    esac
    
    return 0
}

# =============================================================================
# SERVICE INTERFACE FUNCTIONS
# =============================================================================

# Start monitoring service
unity_monitor_start() {
    if [[ "$MONITOR_SERVICE_INITIALIZED" != "true" ]]; then
        unity_monitor_init || return $?
    fi
    
    unity_log "INFO" "Starting Unity Monitor Service..."
    MONITOR_SERVICE_RUNNING=true
    
    # Start background monitoring tasks
    _start_health_check_scheduler &
    _start_metric_collection_scheduler &
    _start_log_aggregation_daemon &
    
    unity_emit_event "MONITOR_SERVICE_STARTED" "$SERVICE_NAME"
    return $UNITY_SUCCESS
}

# Stop monitoring service
unity_monitor_stop() {
    unity_log "INFO" "Stopping Unity Monitor Service..."
    MONITOR_SERVICE_RUNNING=false
    
    # Stop background tasks
    pkill -f "_start_health_check_scheduler" 2>/dev/null || true
    pkill -f "_start_metric_collection_scheduler" 2>/dev/null || true
    pkill -f "_start_log_aggregation_daemon" 2>/dev/null || true
    
    # Save current state
    _save_monitor_state
    
    unity_emit_event "MONITOR_SERVICE_STOPPED" "$SERVICE_NAME"
    return $UNITY_SUCCESS
}

# Get monitoring service status
unity_monitor_status() {
    unity_log "INFO" "📊 Unity Monitor Service Status:"
    unity_log "INFO" "  - Version: $SERVICE_VERSION"
    unity_log "INFO" "  - Initialized: $MONITOR_SERVICE_INITIALIZED"
    unity_log "INFO" "  - Running: $MONITOR_SERVICE_RUNNING"
    unity_log "INFO" "  - Alert Channels: ${ALERT_CHANNELS[*]}"
    
    if [[ -f "$MONITOR_STATE_DIR/health_status.txt" ]]; then
        unity_log "INFO" "  - Latest Health Status:"
        tail -5 "$MONITOR_STATE_DIR/health_status.txt" | while read -r line; do
            [[ -n "$line" ]] && [[ ! "$line" =~ ^# ]] && unity_log "INFO" "    $line"
        done
    fi
    
    # Show recent metrics
    if [[ -d "$MONITOR_METRICS_DIR" ]]; then
        local metric_count=$(find "$MONITOR_METRICS_DIR" -name "*.tsv" -mmin -60 | wc -l)
        unity_log "INFO" "  - Metrics collected (last hour): $metric_count"
    fi
    
    # Show recent alerts
    if [[ -d "$MONITOR_ALERTS_DIR" ]]; then
        local alert_count=$(find "$MONITOR_ALERTS_DIR" -name "*.json" -mmin -60 | wc -l)
        unity_log "INFO" "  - Alerts generated (last hour): $alert_count"
    fi
    
    return $UNITY_SUCCESS
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get CPU usage percentage
_get_cpu_usage() {
    local cpu_usage=0
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        cpu_usage=$(top -l 1 -s 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' 2>/dev/null || echo 0)
    else
        # Linux
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo 0)
    fi
    
    # Ensure integer
    printf "%.0f" "$cpu_usage" 2>/dev/null || echo 0
}

# Get memory usage percentage
_get_memory_usage() {
    local mem_usage=0
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - using vm_stat
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
        local pages_total=$(sysctl -n hw.memsize | awk '{print $1/4096}')
        if [[ -n "$pages_free" ]] && [[ -n "$pages_total" ]]; then
            mem_usage=$(awk "BEGIN {printf \"%.0f\", (1 - $pages_free / $pages_total) * 100}")
        fi
    else
        # Linux
        mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}' 2>/dev/null || echo 0)
    fi
    
    echo "$mem_usage"
}

# Get disk usage percentage
_get_disk_usage() {
    df -h . 2>/dev/null | awk 'NR==2{print $5}' | sed 's/%//' || echo 0
}

# Get total memory in MB
_get_memory_total() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo $(($(sysctl -n hw.memsize) / 1024 / 1024))
    else
        # Linux
        free -m | grep Mem | awk '{print $2}'
    fi
}

# Get free memory in MB
_get_memory_free() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
        echo $((pages_free * 4096 / 1024 / 1024))
    else
        # Linux
        free -m | grep Mem | awk '{print $4}'
    fi
}

# Save monitoring state
_save_monitor_state() {
    local state_file="$MONITOR_STATE_DIR/monitor_state.json"
    
    cat > "$state_file" << EOF
{
  "version": "$SERVICE_VERSION",
  "last_save": "$(date -Iseconds)",
  "initialized": $MONITOR_SERVICE_INITIALIZED,
  "running": $MONITOR_SERVICE_RUNNING,
  "alert_channels": $(printf '"%s",' "${ALERT_CHANNELS[@]}" | sed 's/,$//')
}
EOF
}

# Load monitoring state
_load_monitor_state() {
    local state_file="$MONITOR_STATE_DIR/monitor_state.json"
    
    if [[ -f "$state_file" ]]; then
        unity_log "DEBUG" "Loading saved monitoring state..."
        # State loading logic here if needed
    fi
}

# Register monitoring event handlers
_register_monitoring_handlers() {
    # Register handlers for system events
    unity_on_event "SERVICE_STARTED" "_handle_service_started"
    unity_on_event "SERVICE_STOPPED" "_handle_service_stopped"
    unity_on_event "SERVICE_ERROR" "_handle_service_error"
    unity_on_event "DEPLOYMENT_STARTED" "_handle_deployment_started"
    unity_on_event "DEPLOYMENT_COMPLETED" "_handle_deployment_completed"
    unity_on_event "DEPLOYMENT_FAILED" "_handle_deployment_failed"
}

# =============================================================================
# BACKGROUND SCHEDULERS
# =============================================================================

# Health check scheduler
_start_health_check_scheduler() {
    while [[ "$MONITOR_SERVICE_RUNNING" == "true" ]]; do
        unity_monitor_health_check "all" "false" || true
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Metric collection scheduler
_start_metric_collection_scheduler() {
    while [[ "$MONITOR_SERVICE_RUNNING" == "true" ]]; do
        unity_monitor_collect_metrics "false" || true
        sleep "$PERF_COLLECTION_INTERVAL"
    done
}

# Log aggregation daemon
_start_log_aggregation_daemon() {
    while [[ "$MONITOR_SERVICE_RUNNING" == "true" ]]; do
        unity_monitor_aggregate_logs "all" "json" || true
        sleep 60  # Run every minute
    done
}

# =============================================================================
# ALERT CHANNEL IMPLEMENTATIONS
# =============================================================================

# Send alert to log
_send_alert_to_log() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    echo "[$(date -Iseconds)] [$severity] $title: $message" >> "$MONITOR_ALERTS_DIR/alerts.log"
}

# Send alert to console
_send_alert_to_console() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    local color=""
    case "$severity" in
        info) color="\033[36m" ;;      # Cyan
        warning) color="\033[33m" ;;   # Yellow
        error) color="\033[31m" ;;     # Red
        critical) color="\033[35m" ;;  # Magenta
    esac
    
    local NC="\033[0m"  # No Color
    echo -e "${color}[ALERT:$severity] $title${NC}\n$message" >&2
}

# Send alert to webhook
_send_alert_to_webhook() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local alert_id="$4"
    
    if [[ -z "$ALERT_WEBHOOK_URL" ]]; then
        return $UNITY_SUCCESS
    fi
    
    local payload=$(cat << EOF
{
  "alert_id": "$alert_id",
  "severity": "$severity",
  "title": "$title",
  "message": "$message",
  "timestamp": "$(date -Iseconds)",
  "source": "unity-monitor"
}
EOF
)
    
    curl -s -X POST "$ALERT_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" &>/dev/null || true
}

# Send alert to SNS
_send_alert_to_sns() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    if [[ -z "$ALERT_SNS_TOPIC" ]] || ! command -v aws &>/dev/null; then
        return $UNITY_SUCCESS
    fi
    
    aws sns publish \
        --topic-arn "$ALERT_SNS_TOPIC" \
        --subject "[$severity] $title" \
        --message "$message" &>/dev/null || true
}

# Send alert to Slack
_send_alert_to_slack() {
    local severity="$1"
    local title="$2"
    local message="$3"
    
    if [[ -z "$ALERT_SLACK_WEBHOOK" ]]; then
        return $UNITY_SUCCESS
    fi
    
    local color=""
    case "$severity" in
        info) color="#36a64f" ;;
        warning) color="#ff9900" ;;
        error) color="#ff0000" ;;
        critical) color="#990099" ;;
    esac
    
    local payload=$(cat << EOF
{
  "attachments": [{
    "color": "$color",
    "title": "$title",
    "text": "$message",
    "footer": "Unity Monitor",
    "ts": $(date +%s)
  }]
}
EOF
)
    
    curl -s -X POST "$ALERT_SLACK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" &>/dev/null || true
}

# =============================================================================
# SERVICE REGISTRATION
# =============================================================================

# Register service with Unity
unity_register_service "$SERVICE_NAME" "$(basename "${BASH_SOURCE[0]}")"

# Export public functions
export -f unity_monitor_init
export -f unity_monitor_start
export -f unity_monitor_stop
export -f unity_monitor_status
export -f unity_monitor_health_check
export -f unity_monitor_alert
export -f unity_monitor_collect_metrics
export -f unity_monitor_aggregate_logs
export -f unity_monitor_analyze_logs
export -f unity_monitor_start_trace
export -f unity_monitor_end_trace