#!/usr/bin/env bash
# =============================================================================
# Log Aggregation and Analysis System Module  
# Provides centralized log collection, aggregation, and analysis capabilities
# =============================================================================

# Prevent multiple sourcing
[ -n "${_LOG_AGGREGATION_SH_LOADED:-}" ] && return 0
_LOG_AGGREGATION_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/structured_logging.sh"

# =============================================================================
# AGGREGATION CONFIGURATION
# =============================================================================

# Log sources
readonly LOG_SOURCE_SYSTEM="system"
readonly LOG_SOURCE_APPLICATION="application"
readonly LOG_SOURCE_DEPLOYMENT="deployment"
readonly LOG_SOURCE_INFRASTRUCTURE="infrastructure"
readonly LOG_SOURCE_CUSTOM="custom"

# Aggregation modes
readonly AGG_MODE_REALTIME="realtime"
readonly AGG_MODE_BATCH="batch"
readonly AGG_MODE_STREAM="stream"

# Analysis types
readonly ANALYSIS_TYPE_PATTERN="pattern"
readonly ANALYSIS_TYPE_ANOMALY="anomaly"
readonly ANALYSIS_TYPE_TREND="trend"
readonly ANALYSIS_TYPE_CORRELATION="correlation"

# Global configuration
LOG_AGG_ENABLED="${LOG_AGG_ENABLED:-true}"
LOG_AGG_MODE="${LOG_AGG_MODE:-$AGG_MODE_BATCH}"
LOG_AGG_STORAGE_DIR="${LOG_AGG_STORAGE_DIR:-/tmp/log_aggregation_$$}"
LOG_AGG_RETENTION_DAYS="${LOG_AGG_RETENTION_DAYS:-7}"
LOG_AGG_BATCH_SIZE="${LOG_AGG_BATCH_SIZE:-1000}"
LOG_AGG_FLUSH_INTERVAL="${LOG_AGG_FLUSH_INTERVAL:-300}"

# Storage files
LOG_AGG_MASTER_FILE="$LOG_AGG_STORAGE_DIR/master.jsonl"
LOG_AGG_INDEX_FILE="$LOG_AGG_STORAGE_DIR/index.json"
LOG_AGG_PATTERNS_FILE="$LOG_AGG_STORAGE_DIR/patterns.json"

# Active collectors
LOG_COLLECTORS=()
LOG_PARSERS=()

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize log aggregation
init_log_aggregation() {
    local mode="${1:-$AGG_MODE_BATCH}"
    local storage_dir="${2:-$LOG_AGG_STORAGE_DIR}"
    local retention="${3:-$LOG_AGG_RETENTION_DAYS}"
    
    log_info "Initializing log aggregation system" "LOG_AGG"
    
    # Set configuration
    LOG_AGG_MODE="$mode"
    LOG_AGG_STORAGE_DIR="$storage_dir"
    LOG_AGG_RETENTION_DAYS="$retention"
    
    # Create storage directory
    mkdir -p "$LOG_AGG_STORAGE_DIR"
    
    # Initialize storage files
    echo "" > "$LOG_AGG_MASTER_FILE"
    echo '{}' > "$LOG_AGG_INDEX_FILE"
    echo '[]' > "$LOG_AGG_PATTERNS_FILE"
    
    # Register default collectors
    register_default_collectors
    
    # Register default parsers
    register_default_parsers
    
    # Start aggregation based on mode
    case "$mode" in
        "$AGG_MODE_REALTIME")
            start_realtime_aggregation
            ;;
        "$AGG_MODE_BATCH")
            start_batch_aggregation
            ;;
        "$AGG_MODE_STREAM")
            start_stream_aggregation
            ;;
    esac
    
    log_info "Log aggregation initialized (mode: $mode)" "LOG_AGG"
    return 0
}

# =============================================================================
# LOG COLLECTORS
# =============================================================================

# Register default collectors
register_default_collectors() {
    log_info "Registering default log collectors" "LOG_AGG"
    
    # System logs collector
    register_log_collector "system_logs" \
        "collect_system_logs" \
        "$LOG_SOURCE_SYSTEM" \
        '{"paths": ["/var/log/syslog", "/var/log/messages"]}'
    
    # Application logs collector
    register_log_collector "app_logs" \
        "collect_application_logs" \
        "$LOG_SOURCE_APPLICATION" \
        '{"paths": ["/var/log/n8n.log", "/var/log/ollama.log"]}'
    
    # Deployment logs collector
    register_log_collector "deployment_logs" \
        "collect_deployment_logs" \
        "$LOG_SOURCE_DEPLOYMENT" \
        '{"paths": ["$DEBUG_OUTPUT_DIR/debug.log"]}'
    
    # CloudWatch logs collector
    register_log_collector "cloudwatch_logs" \
        "collect_cloudwatch_logs" \
        "$LOG_SOURCE_INFRASTRUCTURE" \
        '{"log_groups": ["/aws/ec2/instance"]}'
}

# Register log collector
register_log_collector() {
    local collector_id="$1"
    local collector_func="$2"
    local source_type="$3"
    local config="${4:-{}}"
    
    log_debug "Registering log collector: $collector_id" "LOG_AGG"
    
    local collector
    collector=$(cat <<EOF
{
    "id": "$collector_id",
    "function": "$collector_func",
    "source": "$source_type",
    "config": $config,
    "enabled": true,
    "last_position": 0
}
EOF
)
    
    LOG_COLLECTORS+=("$collector")
}

# Collect system logs
collect_system_logs() {
    local collector_config="$1"
    local last_position="$2"
    
    local paths=$(echo "$collector_config" | jq -r '.paths[]')
    local collected_logs=()
    
    for log_path in $paths; do
        if [[ -f "$log_path" ]]; then
            # Read new lines since last position
            local new_lines=$(tail -n +$((last_position + 1)) "$log_path" 2>/dev/null)
            
            if [[ -n "$new_lines" ]]; then
                while IFS= read -r line; do
                    local parsed_log=$(parse_system_log "$line")
                    if [[ -n "$parsed_log" ]]; then
                        collected_logs+=("$parsed_log")
                    fi
                done <<< "$new_lines"
            fi
        fi
    done
    
    printf '%s\n' "${collected_logs[@]}"
}

# Collect application logs
collect_application_logs() {
    local collector_config="$1"
    local last_position="$2"
    
    local paths=$(echo "$collector_config" | jq -r '.paths[]')
    local collected_logs=()
    
    for log_path in $paths; do
        if [[ -f "$log_path" ]]; then
            # For Docker logs, use docker logs command
            if [[ "$log_path" =~ docker ]]; then
                local service_name=$(basename "$log_path" .log)
                local logs=$(docker logs "$service_name" --since "5m" 2>&1 || true)
                
                if [[ -n "$logs" ]]; then
                    while IFS= read -r line; do
                        local parsed_log=$(parse_application_log "$line" "$service_name")
                        if [[ -n "$parsed_log" ]]; then
                            collected_logs+=("$parsed_log")
                        fi
                    done <<< "$logs"
                fi
            else
                # Regular file reading
                local new_lines=$(tail -n +$((last_position + 1)) "$log_path" 2>/dev/null)
                
                if [[ -n "$new_lines" ]]; then
                    while IFS= read -r line; do
                        local parsed_log=$(parse_application_log "$line")
                        if [[ -n "$parsed_log" ]]; then
                            collected_logs+=("$parsed_log")
                        fi
                    done <<< "$new_lines"
                fi
            fi
        fi
    done
    
    printf '%s\n' "${collected_logs[@]}"
}

# Collect deployment logs
collect_deployment_logs() {
    local collector_config="$1"
    local last_position="$2"
    
    # Get logs from structured logging
    local logs=$(query_aggregated_logs ".[${last_position}:]" 2>/dev/null || echo "[]")
    
    if [[ "$logs" != "[]" ]]; then
        echo "$logs" | jq -c '.[]'
    fi
}

# Collect CloudWatch logs
collect_cloudwatch_logs() {
    local collector_config="$1"
    local last_position="$2"
    
    local log_groups=$(echo "$collector_config" | jq -r '.log_groups[]')
    local collected_logs=()
    
    # Calculate time window
    local end_time=$(date +%s000)
    local start_time=$((end_time - 300000))  # Last 5 minutes
    
    for log_group in $log_groups; do
        # Get log events from CloudWatch
        local events=$(aws logs filter-log-events \
            --log-group-name "$log_group" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --query 'events[].{timestamp:timestamp,message:message}' \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$events" != "[]" ]]; then
            echo "$events" | jq -c '.[] | {source: "cloudwatch", log_group: "'$log_group'", timestamp: (.timestamp/1000), message: .message}'
        fi
    done
}

# =============================================================================
# LOG PARSERS
# =============================================================================

# Register default parsers
register_default_parsers() {
    log_info "Registering default log parsers" "LOG_AGG"
    
    # Syslog parser
    register_log_parser "syslog" \
        "parse_syslog_format" \
        '^([A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\S+)\[?(\d*)\]?:\s+(.*)$'
    
    # JSON parser
    register_log_parser "json" \
        "parse_json_format" \
        '^\{.*\}$'
    
    # Apache/Nginx parser
    register_log_parser "access_log" \
        "parse_access_log_format" \
        '^(\S+)\s+(\S+)\s+(\S+)\s+\[(.*?)\]\s+"(.*?)"\s+(\d+)\s+(\d+)'
    
    # Application log parser
    register_log_parser "app_log" \
        "parse_app_log_format" \
        '^\[(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\]\s+\[(\w+)\]\s+(.*)$'
}

# Register log parser
register_log_parser() {
    local parser_id="$1"
    local parser_func="$2"
    local pattern="$3"
    
    log_debug "Registering log parser: $parser_id" "LOG_AGG"
    
    local parser
    parser=$(cat <<EOF
{
    "id": "$parser_id",
    "function": "$parser_func",
    "pattern": "$pattern",
    "enabled": true
}
EOF
)
    
    LOG_PARSERS+=("$parser")
}

# Parse system log
parse_system_log() {
    local line="$1"
    
    # Try each parser
    for parser in "${LOG_PARSERS[@]}"; do
        local parser_func=$(echo "$parser" | jq -r '.function')
        if declare -f "$parser_func" >/dev/null 2>&1; then
            local parsed=$("$parser_func" "$line")
            if [[ -n "$parsed" && "$parsed" != "null" ]]; then
                return 0
            fi
        fi
    done
    
    # Fallback to raw format
    echo "{\"timestamp\": $(date +%s), \"message\": \"$line\", \"source\": \"system\"}"
}

# Parse syslog format
parse_syslog_format() {
    local line="$1"
    
    if [[ "$line" =~ ^([A-Za-z]{3}\s+[0-9]{1,2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2})\s+([^\s]+)\s+([^\s\[]+)(\[[0-9]+\])?:\s+(.*)$ ]]; then
        local timestamp="${BASH_REMATCH[1]}"
        local hostname="${BASH_REMATCH[2]}"
        local program="${BASH_REMATCH[3]}"
        local pid="${BASH_REMATCH[4]}"
        local message="${BASH_REMATCH[5]}"
        
        # Convert timestamp to epoch
        local epoch_time=$(date -d "$timestamp" +%s 2>/dev/null || date +%s)
        
        cat <<EOF
{
    "timestamp": $epoch_time,
    "hostname": "$hostname",
    "program": "$program",
    "pid": "${pid//[\[\]]/}",
    "message": "$message",
    "source": "syslog",
    "format": "syslog"
}
EOF
    fi
}

# Parse JSON format
parse_json_format() {
    local line="$1"
    
    if echo "$line" | jq '.' >/dev/null 2>&1; then
        # Add source if not present
        echo "$line" | jq '. + {source: "json", format: "json"}'
    fi
}

# Parse application log
parse_application_log() {
    local line="$1"
    local service="${2:-unknown}"
    
    # Try to parse structured format
    if [[ "$line" =~ ^\[([^\]]+)\]\s*\[([^\]]+)\]\s*(.*)$ ]]; then
        local timestamp="${BASH_REMATCH[1]}"
        local level="${BASH_REMATCH[2]}"
        local message="${BASH_REMATCH[3]}"
        
        # Convert timestamp
        local epoch_time=$(date -d "$timestamp" +%s 2>/dev/null || date +%s)
        
        cat <<EOF
{
    "timestamp": $epoch_time,
    "level": "$level",
    "message": "$message",
    "service": "$service",
    "source": "application",
    "format": "structured"
}
EOF
    else
        # Fallback to raw
        cat <<EOF
{
    "timestamp": $(date +%s),
    "message": "$line",
    "service": "$service",
    "source": "application",
    "format": "raw"
}
EOF
    fi
}

# =============================================================================
# AGGREGATION MODES
# =============================================================================

# Start realtime aggregation
start_realtime_aggregation() {
    log_info "Starting realtime log aggregation" "LOG_AGG"
    
    # Create aggregation loop
    (
        while true; do
            aggregate_logs
            sleep 1
        done
    ) &
    
    local agg_pid=$!
    echo "$agg_pid" > "$LOG_AGG_STORAGE_DIR/aggregator.pid"
    
    log_info "Realtime aggregator started (PID: $agg_pid)" "LOG_AGG"
}

# Start batch aggregation
start_batch_aggregation() {
    log_info "Starting batch log aggregation" "LOG_AGG"
    
    # Create batch aggregation loop
    (
        while true; do
            aggregate_logs
            sleep "$LOG_AGG_FLUSH_INTERVAL"
        done
    ) &
    
    local agg_pid=$!
    echo "$agg_pid" > "$LOG_AGG_STORAGE_DIR/aggregator.pid"
    
    log_info "Batch aggregator started (PID: $agg_pid)" "LOG_AGG"
}

# Start stream aggregation
start_stream_aggregation() {
    log_info "Starting stream log aggregation" "LOG_AGG"
    
    # Create named pipes for streaming
    local stream_pipe="$LOG_AGG_STORAGE_DIR/stream.pipe"
    mkfifo "$stream_pipe"
    
    # Start stream processor
    (
        while true; do
            if read -r log_entry < "$stream_pipe"; then
                process_log_entry "$log_entry"
            fi
        done
    ) &
    
    local agg_pid=$!
    echo "$agg_pid" > "$LOG_AGG_STORAGE_DIR/aggregator.pid"
    
    log_info "Stream aggregator started (PID: $agg_pid)" "LOG_AGG"
}

# =============================================================================
# AGGREGATION FUNCTIONS
# =============================================================================

# Aggregate logs
aggregate_logs() {
    log_debug "Running log aggregation cycle" "LOG_AGG"
    
    local total_collected=0
    
    # Run each collector
    for collector in "${LOG_COLLECTORS[@]}"; do
        local enabled=$(echo "$collector" | jq -r '.enabled')
        if [[ "$enabled" != "true" ]]; then
            continue
        fi
        
        local collector_id=$(echo "$collector" | jq -r '.id')
        local collector_func=$(echo "$collector" | jq -r '.function')
        local config=$(echo "$collector" | jq '.config')
        local last_position=$(echo "$collector" | jq -r '.last_position')
        
        log_debug "Running collector: $collector_id" "LOG_AGG"
        
        # Run collector
        if declare -f "$collector_func" >/dev/null 2>&1; then
            local logs=$("$collector_func" "$config" "$last_position")
            
            if [[ -n "$logs" ]]; then
                # Process collected logs
                while IFS= read -r log_entry; do
                    if [[ -n "$log_entry" ]]; then
                        process_log_entry "$log_entry"
                        total_collected=$((total_collected + 1))
                    fi
                done <<< "$logs"
                
                # Update collector position
                update_collector_position "$collector_id" "$total_collected"
            fi
        fi
    done
    
    log_debug "Aggregation cycle complete (collected: $total_collected)" "LOG_AGG"
    
    # Run analysis if enough logs collected
    if [[ $total_collected -gt 0 ]]; then
        run_log_analysis
    fi
}

# Process log entry
process_log_entry() {
    local log_entry="$1"
    
    # Enrich log entry
    local enriched_log=$(enrich_log_entry "$log_entry")
    
    # Store in master file
    echo "$enriched_log" >> "$LOG_AGG_MASTER_FILE"
    
    # Update index
    update_log_index "$enriched_log"
    
    # Check for patterns
    detect_log_patterns "$enriched_log"
}

# Enrich log entry
enrich_log_entry() {
    local log_entry="$1"
    
    # Add aggregation metadata
    local enriched=$(echo "$log_entry" | jq --arg id "$(generate_log_id)" \
        --arg agg_time "$(date +%s)" \
        --arg stack "${STACK_NAME:-}" \
        --arg deployment "${DEPLOYMENT_ID:-}" \
        '. + {
            log_id: $id,
            aggregated_at: ($agg_time | tonumber),
            stack_name: $stack,
            deployment_id: $deployment
        }')
    
    echo "$enriched"
}

# Update log index
update_log_index() {
    local log_entry="$1"
    
    # Extract indexable fields
    local timestamp=$(echo "$log_entry" | jq -r '.timestamp // 0')
    local source=$(echo "$log_entry" | jq -r '.source // "unknown"')
    local level=$(echo "$log_entry" | jq -r '.level // "info"')
    
    # Update index
    local temp_file="${LOG_AGG_INDEX_FILE}.tmp"
    jq --arg source "$source" \
       --arg level "$level" \
       --argjson ts "$timestamp" \
       '.
        | .sources[$source] = ((.sources[$source] // 0) + 1)
        | .levels[$level] = ((.levels[$level] // 0) + 1)
        | .last_timestamp = (if $ts > .last_timestamp then $ts else .last_timestamp end)
        | .total_count = ((.total_count // 0) + 1)' \
       "$LOG_AGG_INDEX_FILE" > "$temp_file" && \
       mv "$temp_file" "$LOG_AGG_INDEX_FILE"
}

# =============================================================================
# PATTERN DETECTION
# =============================================================================

# Detect log patterns
detect_log_patterns() {
    local log_entry="$1"
    
    local message=$(echo "$log_entry" | jq -r '.message // ""')
    local level=$(echo "$log_entry" | jq -r '.level // "info"')
    
    # Check for error patterns
    if [[ "$level" =~ ^(error|fatal|critical)$ ]]; then
        detect_error_pattern "$message"
    fi
    
    # Check for anomaly patterns
    detect_anomaly_pattern "$log_entry"
    
    # Check for performance patterns
    if [[ "$message" =~ (latency|duration|response.time|elapsed) ]]; then
        detect_performance_pattern "$log_entry"
    fi
}

# Detect error pattern
detect_error_pattern() {
    local message="$1"
    
    # Common error patterns
    local patterns=(
        "out of memory"
        "connection refused"
        "timeout"
        "permission denied"
        "not found"
        "failed to"
        "unable to"
        "exception"
        "stack trace"
    )
    
    for pattern in "${patterns[@]}"; do
        if [[ "${message,,}" =~ $pattern ]]; then
            record_pattern "error" "$pattern" "$message"
        fi
    done
}

# Detect anomaly pattern
detect_anomaly_pattern() {
    local log_entry="$1"
    
    # Check for unusual patterns
    local timestamp=$(echo "$log_entry" | jq -r '.timestamp // 0')
    local source=$(echo "$log_entry" | jq -r '.source // "unknown"')
    
    # Check for burst patterns (many logs in short time)
    check_burst_pattern "$source" "$timestamp"
    
    # Check for gap patterns (long silence)
    check_gap_pattern "$source" "$timestamp"
}

# Record pattern
record_pattern() {
    local pattern_type="$1"
    local pattern_name="$2"
    local sample="$3"
    
    local pattern
    pattern=$(cat <<EOF
{
    "type": "$pattern_type",
    "name": "$pattern_name",
    "timestamp": $(date +%s),
    "count": 1,
    "sample": "$sample"
}
EOF
)
    
    # Add to patterns file
    local temp_file="${LOG_AGG_PATTERNS_FILE}.tmp"
    jq --argjson pattern "$pattern" '. += [$pattern]' "$LOG_AGG_PATTERNS_FILE" > "$temp_file" && \
        mv "$temp_file" "$LOG_AGG_PATTERNS_FILE"
}

# =============================================================================
# LOG ANALYSIS
# =============================================================================

# Run log analysis
run_log_analysis() {
    log_debug "Running log analysis" "LOG_AGG"
    
    # Analyze patterns
    analyze_patterns
    
    # Analyze trends
    analyze_trends
    
    # Analyze correlations
    analyze_correlations
    
    # Generate insights
    generate_insights
}

# Analyze patterns
analyze_patterns() {
    # Get pattern statistics
    local pattern_stats=$(jq '
        group_by(.type) | 
        map({
            type: .[0].type,
            count: length,
            patterns: group_by(.name) | map({name: .[0].name, count: length})
        })' "$LOG_AGG_PATTERNS_FILE")
    
    # Store analysis results
    echo "$pattern_stats" > "$LOG_AGG_STORAGE_DIR/pattern_analysis.json"
}

# Analyze trends
analyze_trends() {
    # Analyze log volume trends
    local volume_trend=$(jq '
        group_by(.timestamp | (. / 300 | floor)) |
        map({
            time_bucket: (.[0].timestamp | (. / 300 | floor) * 300),
            count: length,
            levels: group_by(.level) | map({level: .[0].level, count: length}) | from_entries
        })' "$LOG_AGG_MASTER_FILE" | tail -1000)
    
    # Store trend analysis
    echo "$volume_trend" > "$LOG_AGG_STORAGE_DIR/trend_analysis.json"
}

# Analyze correlations
analyze_correlations() {
    # Find correlated events
    local correlations=$(jq -s '
        .[0] as $errors |
        .[1] as $all |
        $errors | map(.timestamp as $error_time |
            {
                error: .,
                related: ($all | map(select(.timestamp >= ($error_time - 60) and .timestamp <= ($error_time + 60)))
            }
        )' \
        <(grep '"level":"error"' "$LOG_AGG_MASTER_FILE" | tail -100) \
        <(tail -1000 "$LOG_AGG_MASTER_FILE"))
    
    # Store correlation analysis
    echo "$correlations" > "$LOG_AGG_STORAGE_DIR/correlation_analysis.json"
}

# Generate insights
generate_insights() {
    local insights=()
    
    # Check for error spikes
    local error_rate=$(jq -r '
        [.[] | select(.timestamp > (now - 300) and .level == "error")] | length' \
        "$LOG_AGG_MASTER_FILE")
    
    if [[ $error_rate -gt 10 ]]; then
        insights+=("High error rate detected: $error_rate errors in last 5 minutes")
    fi
    
    # Check for pattern anomalies
    local anomaly_count=$(jq '[.[] | select(.type == "anomaly")] | length' "$LOG_AGG_PATTERNS_FILE")
    if [[ $anomaly_count -gt 0 ]]; then
        insights+=("$anomaly_count anomalies detected")
    fi
    
    # Store insights
    printf '{"timestamp": %s, "insights": [' "$(date +%s)" > "$LOG_AGG_STORAGE_DIR/insights.json"
    local first=true
    for insight in "${insights[@]}"; do
        [[ "$first" == "true" ]] && first=false || printf ','
        printf '"%s"' "$insight"
    done >> "$LOG_AGG_STORAGE_DIR/insights.json"
    echo ']}' >> "$LOG_AGG_STORAGE_DIR/insights.json"
}

# =============================================================================
# QUERY FUNCTIONS
# =============================================================================

# Query aggregated logs
query_logs() {
    local query="${1:-.}"
    local time_window="${2:-3600}"
    local limit="${3:-100}"
    
    local current_time=$(date +%s)
    local start_time=$((current_time - time_window))
    
    # Build jq query
    local jq_query=".[] | select(.timestamp >= $start_time)"
    
    # Add custom query if provided
    if [[ "$query" != "." ]]; then
        jq_query+=" | select($query)"
    fi
    
    # Apply limit
    jq_query="[$jq_query] | .[-$limit:]"
    
    # Execute query
    jq "$jq_query" "$LOG_AGG_MASTER_FILE"
}

# Search logs
search_logs() {
    local search_term="$1"
    local time_window="${2:-3600}"
    local case_sensitive="${3:-false}"
    
    local search_flag="contains"
    [[ "$case_sensitive" == "false" ]] && search_flag="ascii_downcase | contains(\"${search_term,,}\")"
    
    query_logs ".message | $search_flag" "$time_window"
}

# Get log statistics
get_log_statistics() {
    local time_window="${1:-3600}"
    
    local stats=$(cat <<EOF
{
    "total_logs": $(wc -l < "$LOG_AGG_MASTER_FILE"),
    "index": $(cat "$LOG_AGG_INDEX_FILE"),
    "patterns": $(jq 'length' "$LOG_AGG_PATTERNS_FILE"),
    "storage_size": "$(du -h "$LOG_AGG_STORAGE_DIR" | tail -1 | awk '{print $1}')",
    "time_window": $time_window,
    "recent_stats": $(query_logs "." "$time_window" 10000 | jq '
        {
            count: length,
            by_level: group_by(.level) | map({key: .[0].level, value: length}) | from_entries,
            by_source: group_by(.source) | map({key: .[0].source, value: length}) | from_entries
        }')
}
EOF
)
    
    echo "$stats" | jq '.'
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

# Generate aggregation report
generate_aggregation_report() {
    local output_file="${1:-}"
    local time_window="${2:-86400}"  # 24 hours
    
    log_info "Generating log aggregation report" "LOG_AGG"
    
    local report
    report=$(cat <<EOF
# Log Aggregation Report
Generated: $(date)
Time Window: $((time_window / 3600)) hours

## Summary Statistics
$(get_log_statistics "$time_window")

## Pattern Analysis
$(cat "$LOG_AGG_STORAGE_DIR/pattern_analysis.json" 2>/dev/null || echo "No pattern analysis available")

## Trend Analysis
$(cat "$LOG_AGG_STORAGE_DIR/trend_analysis.json" 2>/dev/null || echo "No trend analysis available")

## Recent Insights
$(cat "$LOG_AGG_STORAGE_DIR/insights.json" 2>/dev/null || echo "No insights available")

## Top Error Messages
$(query_logs '.level == "error"' "$time_window" 1000 | jq '
    group_by(.message) | 
    map({message: .[0].message, count: length}) | 
    sort_by(.count) | reverse | .[0:10]')

## Log Sources Distribution
$(query_logs "." "$time_window" 10000 | jq '
    group_by(.source) | 
    map({source: .[0].source, count: length, percentage: (length * 100 / (.[0] | length))}) |
    sort_by(.count) | reverse')

## Hourly Log Volume
$(query_logs "." "$time_window" 100000 | jq '
    group_by(.timestamp | (. / 3600 | floor)) |
    map({
        hour: (.[0].timestamp | (. / 3600 | floor) * 3600 | strftime("%Y-%m-%d %H:00")),
        count: length
    })')
EOF
)
    
    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        log_info "Aggregation report generated: $output_file" "LOG_AGG"
    else
        echo "$report"
    fi
}

# =============================================================================
# UTILITIES
# =============================================================================

# Generate log ID
generate_log_id() {
    echo "log_$(date +%s%N)_${RANDOM}"
}

# Update collector position
update_collector_position() {
    local collector_id="$1"
    local new_position="$2"
    
    local updated_collectors=()
    for collector in "${LOG_COLLECTORS[@]}"; do
        local id=$(echo "$collector" | jq -r '.id')
        if [[ "$id" == "$collector_id" ]]; then
            collector=$(echo "$collector" | jq --argjson pos "$new_position" '.last_position = $pos')
        fi
        updated_collectors+=("$collector")
    done
    
    LOG_COLLECTORS=("${updated_collectors[@]}")
}

# Check burst pattern
check_burst_pattern() {
    local source="$1"
    local timestamp="$2"
    
    # Count logs from same source in last minute
    local recent_count=$(jq --arg source "$source" \
        --argjson start "$((timestamp - 60))" \
        '[.[] | select(.source == $source and .timestamp >= $start)] | length' \
        "$LOG_AGG_MASTER_FILE" | tail -1000)
    
    if [[ $recent_count -gt 100 ]]; then
        record_pattern "anomaly" "burst" "High log volume from $source: $recent_count/min"
    fi
}

# Check gap pattern
check_gap_pattern() {
    local source="$1"
    local timestamp="$2"
    
    # Get last log time for source
    local last_time=$(jq -r --arg source "$source" \
        '.[] | select(.source == $source) | .timestamp' \
        "$LOG_AGG_MASTER_FILE" | tail -2 | head -1)
    
    if [[ -n "$last_time" ]]; then
        local gap=$((timestamp - last_time))
        if [[ $gap -gt 300 ]]; then  # 5 minute gap
            record_pattern "anomaly" "gap" "Log gap detected for $source: ${gap}s"
        fi
    fi
}

# Rotate logs
rotate_logs() {
    log_info "Rotating aggregated logs" "LOG_AGG"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_dir="$LOG_AGG_STORAGE_DIR/archive"
    mkdir -p "$archive_dir"
    
    # Archive current logs
    if [[ -s "$LOG_AGG_MASTER_FILE" ]]; then
        gzip -c "$LOG_AGG_MASTER_FILE" > "$archive_dir/master_$timestamp.jsonl.gz"
        echo "" > "$LOG_AGG_MASTER_FILE"
    fi
    
    # Clean old archives based on retention
    find "$archive_dir" -name "*.gz" -mtime +$LOG_AGG_RETENTION_DAYS -delete
    
    log_info "Log rotation complete" "LOG_AGG"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup log aggregation
cleanup_log_aggregation() {
    log_info "Cleaning up log aggregation" "LOG_AGG"
    
    # Stop aggregator if running
    if [[ -f "$LOG_AGG_STORAGE_DIR/aggregator.pid" ]]; then
        local agg_pid=$(cat "$LOG_AGG_STORAGE_DIR/aggregator.pid")
        kill "$agg_pid" 2>/dev/null || true
        rm -f "$LOG_AGG_STORAGE_DIR/aggregator.pid"
    fi
    
    # Generate final report
    generate_aggregation_report "$LOG_AGG_STORAGE_DIR/final_report.txt"
    
    # Clear collectors and parsers
    LOG_COLLECTORS=()
    LOG_PARSERS=()
    
    log_info "Log aggregation cleanup complete" "LOG_AGG"
}