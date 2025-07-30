#!/usr/bin/env bash
# =============================================================================
# Structured Logging Module
# Provides structured logging with JSON output, log aggregation, and analysis
# =============================================================================

# Prevent multiple sourcing
[ -n "${_STRUCTURED_LOGGING_SH_LOADED:-}" ] && return 0
_STRUCTURED_LOGGING_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# STRUCTURED LOG CONFIGURATION
# =============================================================================

# Log output formats
readonly LOG_FORMAT_JSON="json"
readonly LOG_FORMAT_PLAIN="plain"
readonly LOG_FORMAT_LOGFMT="logfmt"

# Log fields
readonly LOG_FIELD_TIMESTAMP="timestamp"
readonly LOG_FIELD_LEVEL="level"
readonly LOG_FIELD_MESSAGE="message"
readonly LOG_FIELD_CONTEXT="context"
readonly LOG_FIELD_CORRELATION_ID="correlation_id"
readonly LOG_FIELD_STACK_NAME="stack_name"
readonly LOG_FIELD_DEPLOYMENT_ID="deployment_id"
readonly LOG_FIELD_COMPONENT="component"
readonly LOG_FIELD_OPERATION="operation"
readonly LOG_FIELD_DURATION="duration"
readonly LOG_FIELD_ERROR_CODE="error_code"
readonly LOG_FIELD_ERROR_MESSAGE="error_message"
readonly LOG_FIELD_METADATA="metadata"

# Global configuration
STRUCTURED_LOG_FORMAT="${STRUCTURED_LOG_FORMAT:-$LOG_FORMAT_JSON}"
STRUCTURED_LOG_BUFFER_SIZE="${STRUCTURED_LOG_BUFFER_SIZE:-100}"
STRUCTURED_LOG_BUFFER=()
STRUCTURED_LOG_AGGREGATION_ENABLED="${STRUCTURED_LOG_AGGREGATION_ENABLED:-false}"
STRUCTURED_LOG_AGGREGATION_FILE="${STRUCTURED_LOG_AGGREGATION_FILE:-}"

# =============================================================================
# STRUCTURED LOGGING FUNCTIONS
# =============================================================================

# Initialize structured logging
init_structured_logging() {
    local log_format="${1:-$LOG_FORMAT_JSON}"
    local aggregation_file="${2:-}"
    local enable_buffering="${3:-false}"
    
    log_info "Initializing structured logging" "STRUCTURED_LOGGING"
    
    # Set log format
    STRUCTURED_LOG_FORMAT="$log_format"
    
    # Enable aggregation if file specified
    if [[ -n "$aggregation_file" ]]; then
        STRUCTURED_LOG_AGGREGATION_ENABLED=true
        STRUCTURED_LOG_AGGREGATION_FILE="$aggregation_file"
        
        # Create aggregation directory
        local agg_dir
        agg_dir=$(dirname "$aggregation_file")
        mkdir -p "$agg_dir"
        
        # Initialize aggregation file
        echo "[]" > "$aggregation_file"
    fi
    
    # Enable buffering if requested
    if [[ "$enable_buffering" == "true" ]]; then
        STRUCTURED_LOG_BUFFER=()
    fi
    
    # Set structured logging in core logging module
    set_structured_logging true
    
    log_info "Structured logging initialized with format: $log_format" "STRUCTURED_LOGGING"
    return 0
}

# Log structured event
log_structured_event() {
    local level="$1"
    local message="$2"
    local component="${3:-}"
    local operation="${4:-}"
    local metadata="${5:-}"
    
    # Build structured log entry
    local log_entry
    log_entry=$(build_structured_log_entry "$level" "$message" "$component" "$operation" "$metadata")
    
    # Output based on format
    case "$STRUCTURED_LOG_FORMAT" in
        "$LOG_FORMAT_JSON")
            output_json_log "$log_entry"
            ;;
        "$LOG_FORMAT_LOGFMT")
            output_logfmt_log "$log_entry"
            ;;
        "$LOG_FORMAT_PLAIN")
            output_plain_log "$log_entry"
            ;;
        *)
            output_json_log "$log_entry"
            ;;
    esac
    
    # Add to aggregation if enabled
    if [[ "$STRUCTURED_LOG_AGGREGATION_ENABLED" == "true" ]]; then
        aggregate_log_entry "$log_entry"
    fi
    
    # Add to buffer if enabled
    if [[ ${#STRUCTURED_LOG_BUFFER[@]} -ge 0 ]]; then
        buffer_log_entry "$log_entry"
    fi
}

# Build structured log entry
build_structured_log_entry() {
    local level="$1"
    local message="$2"
    local component="${3:-}"
    local operation="${4:-}"
    local metadata="${5:-{}}"
    
    # Get current context
    local stack_name="${STACK_NAME:-}"
    local deployment_id="${DEPLOYMENT_ID:-}"
    local correlation_id="$(get_correlation_id)"
    
    # Build JSON entry
    local log_entry
    log_entry=$(cat <<EOF
{
    "$LOG_FIELD_TIMESTAMP": "$(get_iso_timestamp)",
    "$LOG_FIELD_LEVEL": "$level",
    "$LOG_FIELD_MESSAGE": "$message",
    "$LOG_FIELD_CORRELATION_ID": "$correlation_id",
    "$LOG_FIELD_STACK_NAME": "$stack_name",
    "$LOG_FIELD_DEPLOYMENT_ID": "$deployment_id",
    "$LOG_FIELD_COMPONENT": "$component",
    "$LOG_FIELD_OPERATION": "$operation",
    "pid": "$$",
    "script": "${SCRIPT_NAME:-unknown}",
    "host": "$(hostname)",
    "user": "$(whoami)"
}
EOF
)
    
    # Add metadata if provided
    if [[ -n "$metadata" && "$metadata" != "{}" ]]; then
        log_entry=$(echo "$log_entry" | jq --argjson meta "$metadata" '. + {metadata: $meta}')
    fi
    
    echo "$log_entry"
}

# =============================================================================
# OUTPUT FORMATTERS
# =============================================================================

# Output JSON format log
output_json_log() {
    local log_entry="$1"
    
    if [[ "$CONSOLE_OUTPUT_ENABLED" == "true" ]]; then
        echo "$log_entry" | jq -c '.'
    fi
    
    if [[ "$LOG_FILE_ENABLED" == "true" && -n "$LOG_FILE" ]]; then
        echo "$log_entry" | jq -c '.' >> "$LOG_FILE"
    fi
}

# Output logfmt format log
output_logfmt_log() {
    local log_entry="$1"
    
    # Convert JSON to logfmt
    local logfmt_output
    logfmt_output=$(echo "$log_entry" | jq -r 'to_entries | map("\(.key)=\"\(.value)\"") | join(" ")')
    
    if [[ "$CONSOLE_OUTPUT_ENABLED" == "true" ]]; then
        echo "$logfmt_output"
    fi
    
    if [[ "$LOG_FILE_ENABLED" == "true" && -n "$LOG_FILE" ]]; then
        echo "$logfmt_output" >> "$LOG_FILE"
    fi
}

# Output plain text format log
output_plain_log() {
    local log_entry="$1"
    
    # Extract key fields for plain output
    local timestamp=$(echo "$log_entry" | jq -r '.timestamp')
    local level=$(echo "$log_entry" | jq -r '.level')
    local message=$(echo "$log_entry" | jq -r '.message')
    local component=$(echo "$log_entry" | jq -r '.component // ""')
    
    local plain_output="$timestamp [$level]"
    [[ -n "$component" ]] && plain_output+=" [$component]"
    plain_output+=" $message"
    
    if [[ "$CONSOLE_OUTPUT_ENABLED" == "true" ]]; then
        echo "$plain_output"
    fi
    
    if [[ "$LOG_FILE_ENABLED" == "true" && -n "$LOG_FILE" ]]; then
        echo "$plain_output" >> "$LOG_FILE"
    fi
}

# =============================================================================
# LOG AGGREGATION
# =============================================================================

# Aggregate log entry
aggregate_log_entry() {
    local log_entry="$1"
    
    if [[ ! -f "$STRUCTURED_LOG_AGGREGATION_FILE" ]]; then
        echo "[]" > "$STRUCTURED_LOG_AGGREGATION_FILE"
    fi
    
    # Add entry to aggregation file
    local temp_file="${STRUCTURED_LOG_AGGREGATION_FILE}.tmp"
    
    # Use jq to append to array
    jq --argjson entry "$log_entry" '. += [$entry]' "$STRUCTURED_LOG_AGGREGATION_FILE" > "$temp_file" && \
        mv "$temp_file" "$STRUCTURED_LOG_AGGREGATION_FILE"
}

# Query aggregated logs
query_aggregated_logs() {
    local query="${1:-.}"
    local aggregation_file="${2:-$STRUCTURED_LOG_AGGREGATION_FILE}"
    
    if [[ ! -f "$aggregation_file" ]]; then
        log_error "Aggregation file not found: $aggregation_file" "STRUCTURED_LOGGING"
        return 1
    fi
    
    jq "$query" "$aggregation_file"
}

# Get log statistics from aggregation
get_aggregated_log_stats() {
    local aggregation_file="${1:-$STRUCTURED_LOG_AGGREGATION_FILE}"
    
    if [[ ! -f "$aggregation_file" ]]; then
        log_error "Aggregation file not found: $aggregation_file" "STRUCTURED_LOGGING"
        return 1
    fi
    
    cat <<EOF
{
    "total_entries": $(jq 'length' "$aggregation_file"),
    "by_level": $(jq 'group_by(.level) | map({key: .[0].level, value: length}) | from_entries' "$aggregation_file"),
    "by_component": $(jq 'group_by(.component) | map({key: (.[0].component // "unknown"), value: length}) | from_entries' "$aggregation_file"),
    "errors": $(jq '[.[] | select(.level == "ERROR" or .level == "FATAL")] | length' "$aggregation_file"),
    "time_range": {
        "start": $(jq 'if length > 0 then .[0].timestamp else null end' "$aggregation_file"),
        "end": $(jq 'if length > 0 then .[-1].timestamp else null end' "$aggregation_file")
    }
}
EOF
}

# =============================================================================
# LOG BUFFERING
# =============================================================================

# Buffer log entry
buffer_log_entry() {
    local log_entry="$1"
    
    # Add to buffer
    STRUCTURED_LOG_BUFFER+=("$log_entry")
    
    # Check if buffer is full
    if [[ ${#STRUCTURED_LOG_BUFFER[@]} -ge $STRUCTURED_LOG_BUFFER_SIZE ]]; then
        flush_log_buffer
    fi
}

# Flush log buffer
flush_log_buffer() {
    if [[ ${#STRUCTURED_LOG_BUFFER[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Flushing log buffer with ${#STRUCTURED_LOG_BUFFER[@]} entries" "STRUCTURED_LOGGING"
    
    # Process buffered entries
    for entry in "${STRUCTURED_LOG_BUFFER[@]}"; do
        # Output based on format
        case "$STRUCTURED_LOG_FORMAT" in
            "$LOG_FORMAT_JSON")
                output_json_log "$entry"
                ;;
            "$LOG_FORMAT_LOGFMT")
                output_logfmt_log "$entry"
                ;;
            "$LOG_FORMAT_PLAIN")
                output_plain_log "$entry"
                ;;
        esac
    done
    
    # Clear buffer
    STRUCTURED_LOG_BUFFER=()
}

# =============================================================================
# DEPLOYMENT LOGGING
# =============================================================================

# Log deployment event
log_deployment_event() {
    local event_type="$1"
    local event_data="${2:-{}}"
    local component="${3:-deployment}"
    
    local message
    case "$event_type" in
        "start")
            message="Deployment started"
            ;;
        "complete")
            message="Deployment completed successfully"
            ;;
        "failed")
            message="Deployment failed"
            ;;
        "rollback")
            message="Deployment rolled back"
            ;;
        *)
            message="Deployment event: $event_type"
            ;;
    esac
    
    # Add event type to metadata
    local metadata
    metadata=$(echo "$event_data" | jq --arg type "$event_type" '. + {event_type: $type}')
    
    log_structured_event "INFO" "$message" "$component" "deployment_event" "$metadata"
}

# Log infrastructure event
log_infrastructure_event() {
    local resource_type="$1"
    local action="$2"
    local resource_id="${3:-}"
    local status="${4:-success}"
    local details="${5:-{}}"
    
    local message="Infrastructure $action: $resource_type"
    [[ -n "$resource_id" ]] && message+=" ($resource_id)"
    
    local metadata
    metadata=$(cat <<EOF
{
    "resource_type": "$resource_type",
    "action": "$action",
    "resource_id": "$resource_id",
    "status": "$status"
}
EOF
)
    
    # Merge with additional details
    if [[ "$details" != "{}" ]]; then
        metadata=$(echo "$metadata" | jq --argjson details "$details" '. + $details')
    fi
    
    local level="INFO"
    [[ "$status" == "failed" ]] && level="ERROR"
    
    log_structured_event "$level" "$message" "infrastructure" "$action" "$metadata"
}

# Log performance metric
log_performance_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-ms}"
    local component="${4:-performance}"
    local tags="${5:-{}}"
    
    local metadata
    metadata=$(cat <<EOF
{
    "metric_name": "$metric_name",
    "value": $value,
    "unit": "$unit"
}
EOF
)
    
    # Add tags if provided
    if [[ "$tags" != "{}" ]]; then
        metadata=$(echo "$metadata" | jq --argjson tags "$tags" '. + {tags: $tags}')
    fi
    
    log_structured_event "INFO" "Performance metric: $metric_name = $value $unit" "$component" "metric" "$metadata"
}

# =============================================================================
# ERROR LOGGING
# =============================================================================

# Log structured error
log_structured_error() {
    local error_code="$1"
    local error_message="$2"
    local component="${3:-}"
    local operation="${4:-}"
    local stack_trace="${5:-}"
    
    local metadata
    metadata=$(cat <<EOF
{
    "error_code": "$error_code",
    "error_category": "$(get_error_category "$error_code")",
    "error_severity": "$(get_error_severity "$error_code")",
    "recoverable": $(is_error_recoverable "$error_code")
}
EOF
)
    
    # Add stack trace if provided
    if [[ -n "$stack_trace" ]]; then
        metadata=$(echo "$metadata" | jq --arg trace "$stack_trace" '. + {stack_trace: $trace}')
    fi
    
    log_structured_event "ERROR" "$error_message" "$component" "$operation" "$metadata"
}

# =============================================================================
# LOG ANALYSIS
# =============================================================================

# Analyze log patterns
analyze_log_patterns() {
    local aggregation_file="${1:-$STRUCTURED_LOG_AGGREGATION_FILE}"
    local time_window="${2:-3600}"  # Default 1 hour
    
    if [[ ! -f "$aggregation_file" ]]; then
        log_error "Aggregation file not found: $aggregation_file" "STRUCTURED_LOGGING"
        return 1
    fi
    
    local current_time=$(date +%s)
    local start_time=$((current_time - time_window))
    
    # Analyze patterns
    cat <<EOF
{
    "time_window_seconds": $time_window,
    "error_rate": $(jq --arg start "$start_time" '[.[] | select(.timestamp >= $start and (.level == "ERROR" or .level == "FATAL"))] | length' "$aggregation_file"),
    "top_errors": $(jq --arg start "$start_time" '[.[] | select(.timestamp >= $start and .level == "ERROR") | .message] | group_by(.) | map({message: .[0], count: length}) | sort_by(.count) | reverse | .[0:5]' "$aggregation_file"),
    "slowest_operations": $(jq --arg start "$start_time" '[.[] | select(.timestamp >= $start and .metadata.duration != null)] | sort_by(.metadata.duration) | reverse | .[0:5] | map({operation: .operation, duration: .metadata.duration, component: .component})' "$aggregation_file"),
    "busiest_components": $(jq --arg start "$start_time" '[.[] | select(.timestamp >= $start)] | group_by(.component) | map({component: (.[0].component // "unknown"), count: length}) | sort_by(.count) | reverse | .[0:5]' "$aggregation_file")
}
EOF
}

# Generate log report
generate_log_report() {
    local aggregation_file="${1:-$STRUCTURED_LOG_AGGREGATION_FILE}"
    local output_file="${2:-}"
    
    if [[ ! -f "$aggregation_file" ]]; then
        log_error "Aggregation file not found: $aggregation_file" "STRUCTURED_LOGGING"
        return 1
    fi
    
    local report
    report=$(cat <<EOF
# Log Analysis Report
Generated: $(date)

## Summary Statistics
$(get_aggregated_log_stats "$aggregation_file" | jq '.')

## Pattern Analysis (Last Hour)
$(analyze_log_patterns "$aggregation_file" 3600 | jq '.')

## Pattern Analysis (Last 24 Hours)
$(analyze_log_patterns "$aggregation_file" 86400 | jq '.')

## Recent Errors
$(query_aggregated_logs '[.[] | select(.level == "ERROR" or .level == "FATAL")] | .[-10:]' "$aggregation_file" | jq '.')

## Performance Metrics
$(query_aggregated_logs '[.[] | select(.operation == "metric" and .metadata.metric_name != null)] | group_by(.metadata.metric_name) | map({metric: .[0].metadata.metric_name, avg: ([.[].metadata.value] | add / length), min: ([.[].metadata.value] | min), max: ([.[].metadata.value] | max), count: length})' "$aggregation_file" | jq '.')
EOF
)
    
    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        log_info "Log report generated: $output_file" "STRUCTURED_LOGGING"
    else
        echo "$report"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup structured logging
cleanup_structured_logging() {
    log_info "Cleaning up structured logging" "STRUCTURED_LOGGING"
    
    # Flush any remaining buffered logs
    flush_log_buffer
    
    # Reset configuration
    STRUCTURED_LOG_FORMAT="$LOG_FORMAT_JSON"
    STRUCTURED_LOG_BUFFER=()
    STRUCTURED_LOG_AGGREGATION_ENABLED=false
    
    log_info "Structured logging cleanup complete" "STRUCTURED_LOGGING"
}