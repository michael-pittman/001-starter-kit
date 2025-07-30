#!/usr/bin/env bash
# =============================================================================
# Observability Framework Module
# Provides comprehensive observability with metrics, traces, and monitoring
# =============================================================================

# Prevent multiple sourcing
[ -n "${_OBSERVABILITY_SH_LOADED:-}" ] && return 0
_OBSERVABILITY_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/structured_logging.sh"
source "${SCRIPT_DIR}/metrics.sh"

# =============================================================================
# OBSERVABILITY CONFIGURATION
# =============================================================================

# Observability components
readonly OBS_COMPONENT_METRICS="metrics"
readonly OBS_COMPONENT_TRACES="traces"
readonly OBS_COMPONENT_LOGS="logs"
readonly OBS_COMPONENT_EVENTS="events"

# Observability levels
readonly OBS_LEVEL_BASIC="basic"
readonly OBS_LEVEL_STANDARD="standard"
readonly OBS_LEVEL_DETAILED="detailed"
readonly OBS_LEVEL_DEBUG="debug"

# Global configuration
OBSERVABILITY_ENABLED="${OBSERVABILITY_ENABLED:-true}"
OBSERVABILITY_LEVEL="${OBSERVABILITY_LEVEL:-$OBS_LEVEL_STANDARD}"
OBSERVABILITY_COMPONENTS=("$OBS_COMPONENT_METRICS" "$OBS_COMPONENT_LOGS")
OBSERVABILITY_EXPORT_ENABLED="${OBSERVABILITY_EXPORT_ENABLED:-false}"
OBSERVABILITY_EXPORT_ENDPOINT="${OBSERVABILITY_EXPORT_ENDPOINT:-}"

# Trace configuration
TRACE_ENABLED="${TRACE_ENABLED:-false}"
TRACE_SAMPLING_RATE="${TRACE_SAMPLING_RATE:-0.1}"
ACTIVE_TRACES=()

# Metrics collection intervals
METRICS_COLLECTION_INTERVAL="${METRICS_COLLECTION_INTERVAL:-60}"
METRICS_FLUSH_INTERVAL="${METRICS_FLUSH_INTERVAL:-300}"

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize observability framework
init_observability() {
    local level="${1:-$OBS_LEVEL_STANDARD}"
    local components="${2:-metrics,logs}"
    local export_endpoint="${3:-}"
    
    log_info "Initializing observability framework" "OBSERVABILITY"
    
    # Set observability level
    OBSERVABILITY_LEVEL="$level"
    
    # Parse components
    IFS=',' read -ra OBSERVABILITY_COMPONENTS <<< "$components"
    
    # Initialize structured logging
    init_structured_logging "json" "" "true"
    
    # Initialize metrics if enabled
    if [[ " ${OBSERVABILITY_COMPONENTS[@]} " =~ " $OBS_COMPONENT_METRICS " ]]; then
        init_monitoring_metrics "${STACK_NAME:-observability}" '{}'
    fi
    
    # Enable tracing if requested
    if [[ " ${OBSERVABILITY_COMPONENTS[@]} " =~ " $OBS_COMPONENT_TRACES " ]]; then
        TRACE_ENABLED=true
        log_info "Tracing enabled with sampling rate: $TRACE_SAMPLING_RATE" "OBSERVABILITY"
    fi
    
    # Configure export if endpoint provided
    if [[ -n "$export_endpoint" ]]; then
        OBSERVABILITY_EXPORT_ENABLED=true
        OBSERVABILITY_EXPORT_ENDPOINT="$export_endpoint"
        log_info "Observability export enabled to: $export_endpoint" "OBSERVABILITY"
    fi
    
    # Start background metrics collector if needed
    if [[ " ${OBSERVABILITY_COMPONENTS[@]} " =~ " $OBS_COMPONENT_METRICS " ]]; then
        start_metrics_collector
    fi
    
    log_info "Observability framework initialized at level: $level" "OBSERVABILITY"
    return 0
}

# =============================================================================
# TRACING
# =============================================================================

# Start trace
start_trace() {
    local trace_name="$1"
    local parent_trace="${2:-}"
    local attributes="${3:-{}}"
    
    if [[ "$TRACE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Check sampling
    if ! should_sample_trace; then
        return 0
    fi
    
    local trace_id=$(generate_trace_id)
    local span_id=$(generate_span_id)
    local start_time=$(date +%s.%N)
    
    # Create trace context
    local trace_context
    trace_context=$(cat <<EOF
{
    "trace_id": "$trace_id",
    "span_id": "$span_id",
    "trace_name": "$trace_name",
    "parent_trace": "$parent_trace",
    "start_time": $start_time,
    "attributes": $attributes
}
EOF
)
    
    # Store active trace
    ACTIVE_TRACES+=("$trace_context")
    
    # Log trace start
    log_structured_event "DEBUG" "Trace started: $trace_name" "tracing" "start" "$trace_context"
    
    echo "$trace_id:$span_id"
}

# End trace
end_trace() {
    local trace_span="$1"
    local status="${2:-ok}"
    local error_message="${3:-}"
    
    if [[ "$TRACE_ENABLED" != "true" || -z "$trace_span" ]]; then
        return 0
    fi
    
    local trace_id="${trace_span%:*}"
    local span_id="${trace_span#*:}"
    local end_time=$(date +%s.%N)
    
    # Find and update trace
    local updated_traces=()
    local trace_found=false
    
    for trace in "${ACTIVE_TRACES[@]}"; do
        local current_trace_id=$(echo "$trace" | jq -r '.trace_id')
        local current_span_id=$(echo "$trace" | jq -r '.span_id')
        
        if [[ "$current_trace_id" == "$trace_id" && "$current_span_id" == "$span_id" ]]; then
            # Calculate duration
            local start_time=$(echo "$trace" | jq -r '.start_time')
            local duration=$(echo "$end_time - $start_time" | bc -l)
            
            # Update trace with end information
            local updated_trace
            updated_trace=$(echo "$trace" | jq --arg status "$status" \
                --arg error "$error_message" \
                --argjson end_time "$end_time" \
                --argjson duration "$duration" \
                '. + {end_time: $end_time, duration: $duration, status: $status, error: $error}')
            
            # Log trace end
            log_structured_event "DEBUG" "Trace ended: $(echo "$trace" | jq -r '.trace_name')" "tracing" "end" "$updated_trace"
            
            # Export if enabled
            if [[ "$OBSERVABILITY_EXPORT_ENABLED" == "true" ]]; then
                export_trace "$updated_trace"
            fi
            
            trace_found=true
        else
            updated_traces+=("$trace")
        fi
    done
    
    ACTIVE_TRACES=("${updated_traces[@]}")
    
    if [[ "$trace_found" != "true" ]]; then
        log_warn "Trace not found: $trace_span" "OBSERVABILITY"
    fi
}

# Add trace annotation
add_trace_annotation() {
    local trace_span="$1"
    local key="$2"
    local value="$3"
    
    if [[ "$TRACE_ENABLED" != "true" || -z "$trace_span" ]]; then
        return 0
    fi
    
    local trace_id="${trace_span%:*}"
    local span_id="${trace_span#*:}"
    
    # Log annotation
    local annotation
    annotation=$(cat <<EOF
{
    "trace_id": "$trace_id",
    "span_id": "$span_id",
    "annotation": {
        "$key": "$value",
        "timestamp": $(date +%s.%N)
    }
}
EOF
)
    
    log_structured_event "DEBUG" "Trace annotation: $key=$value" "tracing" "annotation" "$annotation"
}

# =============================================================================
# METRICS COLLECTION
# =============================================================================

# Start metrics collector
start_metrics_collector() {
    if [[ "$OBSERVABILITY_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Starting metrics collector" "OBSERVABILITY"
    
    # Create metrics collection script
    local collector_script="/tmp/obs_metrics_collector_$$.sh"
    cat > "$collector_script" <<'EOF'
#!/usr/bin/env bash
while true; do
    # Collect system metrics
    collect_system_metrics
    
    # Collect deployment metrics
    collect_deployment_metrics
    
    # Sleep for collection interval
    sleep ${METRICS_COLLECTION_INTERVAL:-60}
done
EOF
    
    chmod +x "$collector_script"
    
    # Start collector in background
    nohup "$collector_script" > /tmp/obs_metrics_collector_$$.log 2>&1 &
    local collector_pid=$!
    
    # Store collector PID for cleanup
    echo "$collector_pid" > /tmp/obs_metrics_collector_$$.pid
    
    log_info "Metrics collector started with PID: $collector_pid" "OBSERVABILITY"
}

# Collect system metrics
collect_system_metrics() {
    local timestamp=$(date +%s)
    
    # CPU metrics
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    record_metric "system.cpu.usage" "$cpu_usage" "percent" "system"
    
    # Memory metrics
    local mem_info=$(free -m | grep "^Mem:")
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_usage=$(echo "scale=2; $mem_used * 100 / $mem_total" | bc)
    
    record_metric "system.memory.total" "$mem_total" "MB" "system"
    record_metric "system.memory.used" "$mem_used" "MB" "system"
    record_metric "system.memory.usage" "$mem_usage" "percent" "system"
    
    # Disk metrics
    local disk_info=$(df -h / | tail -1)
    local disk_usage=$(echo "$disk_info" | awk '{print $5}' | cut -d'%' -f1)
    
    record_metric "system.disk.usage" "$disk_usage" "percent" "system"
    
    # Network metrics (if available)
    if command -v ifstat >/dev/null 2>&1; then
        local network_stats=$(ifstat -t 1 1 | tail -1)
        local bytes_in=$(echo "$network_stats" | awk '{print $1}')
        local bytes_out=$(echo "$network_stats" | awk '{print $2}')
        
        record_metric "system.network.bytes_in" "$bytes_in" "KB/s" "system"
        record_metric "system.network.bytes_out" "$bytes_out" "KB/s" "system"
    fi
}

# Collect deployment metrics
collect_deployment_metrics() {
    local stack_name="${STACK_NAME:-}"
    
    if [[ -z "$stack_name" ]]; then
        return 0
    fi
    
    # Get deployment status
    local deployment_state=$(get_variable "DEPLOYMENT_STATE" "$VARIABLE_SCOPE_STACK")
    local deployment_phase=$(get_variable "DEPLOYMENT_PHASE" "$VARIABLE_SCOPE_STACK")
    
    # Record deployment state metric
    case "$deployment_state" in
        "running")
            record_metric "deployment.state" "1" "state" "deployment"
            ;;
        "completed")
            record_metric "deployment.state" "2" "state" "deployment"
            ;;
        "failed")
            record_metric "deployment.state" "3" "state" "deployment"
            ;;
        *)
            record_metric "deployment.state" "0" "state" "deployment"
            ;;
    esac
    
    # Get instance metrics if available
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$instance_id" ]]; then
        # Check instance health
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        if [[ "$instance_state" == "running" ]]; then
            record_metric "deployment.instance.healthy" "1" "bool" "deployment"
        else
            record_metric "deployment.instance.healthy" "0" "bool" "deployment"
        fi
    fi
    
    # Get service health metrics
    local services=("n8n" "qdrant" "ollama" "crawl4ai")
    local healthy_services=0
    local total_services=0
    
    for service in "${services[@]}"; do
        local enable_var="${service^^}_ENABLE"
        if [[ "${!enable_var}" != "false" ]]; then
            total_services=$((total_services + 1))
            
            # Check if service is healthy (simplified check)
            local service_healthy=$(check_service_health_simple "$service")
            if [[ "$service_healthy" == "true" ]]; then
                healthy_services=$((healthy_services + 1))
                record_metric "deployment.service.$service.healthy" "1" "bool" "deployment"
            else
                record_metric "deployment.service.$service.healthy" "0" "bool" "deployment"
            fi
        fi
    done
    
    # Calculate service health percentage
    if [[ $total_services -gt 0 ]]; then
        local health_percentage=$(echo "scale=2; $healthy_services * 100 / $total_services" | bc)
        record_metric "deployment.services.health_percentage" "$health_percentage" "percent" "deployment"
    fi
}

# Record metric
record_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-count}"
    local component="${4:-observability}"
    local tags="${5:-{}}"
    
    # Add observability level to tags
    tags=$(echo "$tags" | jq --arg level "$OBSERVABILITY_LEVEL" '. + {observability_level: $level}')
    
    # Log performance metric
    log_performance_metric "$metric_name" "$value" "$unit" "$component" "$tags"
    
    # Put custom CloudWatch metric if enabled
    if [[ " ${OBSERVABILITY_COMPONENTS[@]} " =~ " $OBS_COMPONENT_METRICS " ]]; then
        put_custom_metric "${METRICS_NAMESPACE:-GeuseMaker}" "$metric_name" "$value" "$unit"
    fi
}

# =============================================================================
# EVENT TRACKING
# =============================================================================

# Track observability event
track_event() {
    local event_name="$1"
    local event_data="${2:-{}}"
    local event_type="${3:-custom}"
    
    if [[ "$OBSERVABILITY_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Add event metadata
    local event_metadata
    event_metadata=$(cat <<EOF
{
    "event_name": "$event_name",
    "event_type": "$event_type",
    "timestamp": $(date +%s.%N),
    "observability_level": "$OBSERVABILITY_LEVEL"
}
EOF
)
    
    # Merge with event data
    local full_event_data
    full_event_data=$(echo "$event_metadata" | jq --argjson data "$event_data" '. + {data: $data}')
    
    # Log event
    log_structured_event "INFO" "Event: $event_name" "events" "$event_type" "$full_event_data"
    
    # Export if enabled
    if [[ "$OBSERVABILITY_EXPORT_ENABLED" == "true" ]]; then
        export_event "$full_event_data"
    fi
}

# Track deployment milestone
track_deployment_milestone() {
    local milestone="$1"
    local details="${2:-{}}"
    
    track_event "deployment_milestone" \
        "$(echo "$details" | jq --arg milestone "$milestone" '. + {milestone: $milestone}')" \
        "milestone"
}

# Track error event
track_error_event() {
    local error_code="$1"
    local error_message="$2"
    local context="${3:-{}}"
    
    local error_data
    error_data=$(cat <<EOF
{
    "error_code": "$error_code",
    "error_message": "$error_message",
    "error_category": "$(get_error_category "$error_code")",
    "error_severity": "$(get_error_severity "$error_code")",
    "recoverable": $(is_error_recoverable "$error_code")
}
EOF
)
    
    # Merge with context
    error_data=$(echo "$error_data" | jq --argjson ctx "$context" '. + {context: $ctx}')
    
    track_event "error" "$error_data" "error"
}

# =============================================================================
# OBSERVABILITY LEVEL MANAGEMENT
# =============================================================================

# Should collect metric based on observability level
should_collect_metric() {
    local metric_type="$1"
    
    case "$OBSERVABILITY_LEVEL" in
        "$OBS_LEVEL_BASIC")
            # Only critical metrics
            [[ "$metric_type" =~ ^(error|failure|critical) ]]
            ;;
        "$OBS_LEVEL_STANDARD")
            # Standard metrics
            [[ ! "$metric_type" =~ ^(debug|trace|verbose) ]]
            ;;
        "$OBS_LEVEL_DETAILED")
            # Most metrics except debug
            [[ ! "$metric_type" =~ ^(debug|trace) ]]
            ;;
        "$OBS_LEVEL_DEBUG")
            # All metrics
            true
            ;;
        *)
            true
            ;;
    esac
}

# Should sample trace
should_sample_trace() {
    local random_value=$(echo "scale=2; $RANDOM / 32767" | bc -l)
    (( $(echo "$random_value < $TRACE_SAMPLING_RATE" | bc -l) ))
}

# Get observability context
get_observability_context() {
    cat <<EOF
{
    "enabled": $OBSERVABILITY_ENABLED,
    "level": "$OBSERVABILITY_LEVEL",
    "components": $(printf '[%s]' "$(IFS=','; echo "${OBSERVABILITY_COMPONENTS[*]}")"),
    "trace_enabled": $TRACE_ENABLED,
    "trace_sampling_rate": $TRACE_SAMPLING_RATE,
    "export_enabled": $OBSERVABILITY_EXPORT_ENABLED,
    "export_endpoint": "$OBSERVABILITY_EXPORT_ENDPOINT",
    "stack_name": "${STACK_NAME:-}",
    "deployment_id": "${DEPLOYMENT_ID:-}",
    "correlation_id": "$(get_correlation_id)"
}
EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export trace
export_trace() {
    local trace_data="$1"
    
    if [[ "$OBSERVABILITY_EXPORT_ENABLED" != "true" || -z "$OBSERVABILITY_EXPORT_ENDPOINT" ]]; then
        return 0
    fi
    
    # Send trace to export endpoint
    curl -s -X POST "$OBSERVABILITY_EXPORT_ENDPOINT/traces" \
        -H "Content-Type: application/json" \
        -d "$trace_data" || {
        log_warn "Failed to export trace" "OBSERVABILITY"
    }
}

# Export event
export_event() {
    local event_data="$1"
    
    if [[ "$OBSERVABILITY_EXPORT_ENABLED" != "true" || -z "$OBSERVABILITY_EXPORT_ENDPOINT" ]]; then
        return 0
    fi
    
    # Send event to export endpoint
    curl -s -X POST "$OBSERVABILITY_EXPORT_ENDPOINT/events" \
        -H "Content-Type: application/json" \
        -d "$event_data" || {
        log_warn "Failed to export event" "OBSERVABILITY"
    }
}

# Export metrics batch
export_metrics_batch() {
    local metrics_file="${1:-}"
    
    if [[ "$OBSERVABILITY_EXPORT_ENABLED" != "true" || -z "$OBSERVABILITY_EXPORT_ENDPOINT" ]]; then
        return 0
    fi
    
    if [[ ! -f "$metrics_file" ]]; then
        log_warn "Metrics file not found: $metrics_file" "OBSERVABILITY"
        return 1
    fi
    
    # Send metrics batch to export endpoint
    curl -s -X POST "$OBSERVABILITY_EXPORT_ENDPOINT/metrics" \
        -H "Content-Type: application/json" \
        -d "@$metrics_file" || {
        log_warn "Failed to export metrics batch" "OBSERVABILITY"
    }
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Generate trace ID
generate_trace_id() {
    # Generate 128-bit hex trace ID
    printf '%032x' "$(date +%s%N)$RANDOM"
}

# Generate span ID
generate_span_id() {
    # Generate 64-bit hex span ID
    printf '%016x' "$(date +%s%N)$RANDOM"
}

# Check service health (simplified)
check_service_health_simple() {
    local service="$1"
    
    # This is a simplified check - in production, would check actual service endpoints
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$instance_id" ]]; then
        # For now, just check if instance is running
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        [[ "$instance_state" == "running" ]] && echo "true" || echo "false"
    else
        echo "false"
    fi
}

# =============================================================================
# OBSERVABILITY REPORT
# =============================================================================

# Generate observability report
generate_observability_report() {
    local output_file="${1:-}"
    
    log_info "Generating observability report" "OBSERVABILITY"
    
    local report
    report=$(cat <<EOF
# Observability Report
Generated: $(date)

## Configuration
$(get_observability_context | jq '.')

## Active Traces
Total: ${#ACTIVE_TRACES[@]}

## Metrics Summary
$(get_aggregated_log_stats | jq 'select(.by_component.observability != null)')

## Recent Events
$(query_aggregated_logs '[.[] | select(.component == "events")] | .[-10:]' | jq '.')

## System Metrics (Latest)
$(query_aggregated_logs '[.[] | select(.operation == "metric" and .component == "system")] | group_by(.metadata.metric_name) | map({metric: .[0].metadata.metric_name, latest: .[-1].metadata.value, unit: .[-1].metadata.unit})' | jq '.')

## Deployment Metrics (Latest)
$(query_aggregated_logs '[.[] | select(.operation == "metric" and .component == "deployment")] | group_by(.metadata.metric_name) | map({metric: .[0].metadata.metric_name, latest: .[-1].metadata.value, unit: .[-1].metadata.unit})' | jq '.')
EOF
)
    
    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        log_info "Observability report generated: $output_file" "OBSERVABILITY"
    else
        echo "$report"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup observability
cleanup_observability() {
    log_info "Cleaning up observability framework" "OBSERVABILITY"
    
    # Stop metrics collector if running
    if [[ -f "/tmp/obs_metrics_collector_$$.pid" ]]; then
        local collector_pid=$(cat "/tmp/obs_metrics_collector_$$.pid")
        kill "$collector_pid" 2>/dev/null || true
        rm -f "/tmp/obs_metrics_collector_$$.pid"
        rm -f "/tmp/obs_metrics_collector_$$.sh"
        rm -f "/tmp/obs_metrics_collector_$$.log"
    fi
    
    # Export final traces
    for trace in "${ACTIVE_TRACES[@]}"; do
        local trace_id=$(echo "$trace" | jq -r '.trace_id')
        local span_id=$(echo "$trace" | jq -r '.span_id')
        end_trace "$trace_id:$span_id" "cancelled" "Observability cleanup"
    done
    
    # Clear traces
    ACTIVE_TRACES=()
    
    # Cleanup structured logging
    cleanup_structured_logging
    
    log_info "Observability framework cleanup complete" "OBSERVABILITY"
}