#!/usr/bin/env bash
#
# Module: performance/metrics
# Description: Performance monitoring and metrics collection for deployment operations
# Version: 1.0.0
# Dependencies: core/variables.sh, core/errors.sh, core/logging.sh
#
# This module provides comprehensive performance monitoring, metrics collection,
# and reporting capabilities for AWS deployment operations.
#

set -euo pipefail

# Bash version compatibility
# Compatible with bash 3.x+

# Module directory detection
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

# Source dependencies with error handling
source_dependency() {
    local dep="$1"
    local dep_path="${MODULE_DIR}/../${dep}"
    
    if [[ ! -f "$dep_path" ]]; then
        echo "ERROR: Required dependency not found: $dep_path" >&2
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$dep_path" || {
        echo "ERROR: Failed to source dependency: $dep_path" >&2
        return 1
    }
}

# Load core dependencies
source_dependency "core/variables.sh"
source_dependency "core/errors.sh"
source_dependency "core/logging.sh"

# Module state management using associative arrays
declare -gA METRICS_STATE=(
    [initialized]="false"
    [collection_started]="false"
    [start_time]="0"
    [total_operations]="0"
    [successful_operations]="0"
    [failed_operations]="0"
    [metrics_file]="/tmp/geuse-metrics-$$.json"
)

# Metrics storage
declare -gA METRICS_OPERATIONS       # Operation timings
declare -gA METRICS_COUNTERS        # Event counters
declare -gA METRICS_GAUGES          # Current values
declare -gA METRICS_HISTOGRAMS      # Value distributions
declare -gA METRICS_TAGS            # Metric tags/labels

# Resource usage tracking
declare -gA METRICS_CPU_USAGE
declare -gA METRICS_MEMORY_USAGE
declare -gA METRICS_DISK_USAGE
declare -gA METRICS_NETWORK_USAGE

# Module configuration
declare -gA METRICS_CONFIG=(
    [collection_interval_seconds]="5"
    [flush_interval_seconds]="60"
    [max_metrics_per_type]="1000"
    [enable_resource_monitoring]="true"
    [enable_operation_timing]="true"
    [enable_cloudwatch_export]="false"
    [cloudwatch_namespace]="GeuseMaker/Performance"
    [output_format]="json"
    [metrics_retention_hours]="24"
)

# Operation categories
declare -gA METRICS_OPERATION_CATEGORIES=(
    [aws_api]="AWS API Calls"
    [deployment]="Deployment Operations"
    [validation]="Validation Checks"
    [provisioning]="Resource Provisioning"
    [configuration]="Configuration Tasks"
    [network]="Network Operations"
)

# Module-specific error types
declare -gA METRICS_ERROR_TYPES=(
    [METRICS_INIT_FAILED]="Metrics module initialization failed"
    [METRICS_COLLECTION_FAILED]="Failed to collect metrics"
    [METRICS_EXPORT_FAILED]="Failed to export metrics"
    [METRICS_INVALID_TYPE]="Invalid metric type"
)

# ============================================================================
# Initialization Functions
# ============================================================================

#
# Initialize the metrics module
#
# Returns:
#   0 - Success
#   1 - Initialization failed
#
metrics_init() {
    log_info "[${MODULE_NAME}] Initializing metrics module..."
    
    # Check if already initialized
    if [[ "${METRICS_STATE[initialized]}" == "true" ]]; then
        log_debug "[${MODULE_NAME}] Module already initialized"
        return 0
    fi
    
    # Set start time
    METRICS_STATE[start_time]=$(date +%s%N)
    
    # Initialize metrics file
    echo "{}" > "${METRICS_STATE[metrics_file]}"
    
    # Start resource monitoring if enabled
    if [[ "${METRICS_CONFIG[enable_resource_monitoring]}" == "true" ]]; then
        metrics_start_resource_monitoring &
    fi
    
    # Start periodic flush if configured
    if [[ "${METRICS_CONFIG[flush_interval_seconds]}" -gt 0 ]]; then
        metrics_start_periodic_flush &
    fi
    
    # Mark as initialized
    METRICS_STATE[initialized]="true"
    METRICS_STATE[collection_started]="true"
    
    log_info "[${MODULE_NAME}] Module initialized successfully"
    return 0
}

# ============================================================================
# Core Metrics Functions
# ============================================================================

#
# Start timing an operation
#
# Arguments:
#   $1 - Operation name
#   $2 - Optional: Category (default: general)
#   $3 - Optional: Tags (key=value,key=value)
#
# Returns:
#   0 - Success
#
metrics_operation_start() {
    local operation="$1"
    local category="${2:-general}"
    local tags="${3:-}"
    
    local start_time=$(date +%s%N)
    local operation_key="${category}:${operation}"
    
    METRICS_OPERATIONS[$operation_key:start]="$start_time"
    METRICS_OPERATIONS[$operation_key:status]="running"
    
    if [[ -n "$tags" ]]; then
        METRICS_TAGS[$operation_key]="$tags"
    fi
    
    log_debug "[${MODULE_NAME}] Started timing operation: $operation_key"
    ((METRICS_STATE[total_operations]++))
}

#
# End timing an operation
#
# Arguments:
#   $1 - Operation name
#   $2 - Optional: Category (default: general)
#   $3 - Optional: Status (success|failure)
#
# Returns:
#   0 - Success
#
metrics_operation_end() {
    local operation="$1"
    local category="${2:-general}"
    local status="${3:-success}"
    
    local end_time=$(date +%s%N)
    local operation_key="${category}:${operation}"
    
    local start_time="${METRICS_OPERATIONS[$operation_key:start]:-0}"
    if [[ "$start_time" -eq 0 ]]; then
        log_warn "[${MODULE_NAME}] No start time found for operation: $operation_key"
        return 1
    fi
    
    # Calculate duration in milliseconds
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    METRICS_OPERATIONS[$operation_key:end]="$end_time"
    METRICS_OPERATIONS[$operation_key:duration_ms]="$duration_ms"
    METRICS_OPERATIONS[$operation_key:status]="$status"
    
    # Update counters
    if [[ "$status" == "success" ]]; then
        ((METRICS_STATE[successful_operations]++))
    else
        ((METRICS_STATE[failed_operations]++))
    fi
    
    # Update histogram
    metrics_record_histogram "${category}_operation_duration" "$duration_ms"
    
    log_debug "[${MODULE_NAME}] Operation $operation_key completed in ${duration_ms}ms (status: $status)"
}

#
# Increment a counter metric
#
# Arguments:
#   $1 - Counter name
#   $2 - Optional: Increment value (default: 1)
#   $3 - Optional: Tags
#
# Returns:
#   0 - Success
#
metrics_counter_increment() {
    local counter_name="$1"
    local increment="${2:-1}"
    local tags="${3:-}"
    
    local current="${METRICS_COUNTERS[$counter_name]:-0}"
    METRICS_COUNTERS[$counter_name]=$((current + increment))
    
    if [[ -n "$tags" ]]; then
        METRICS_TAGS[counter:$counter_name]="$tags"
    fi
    
    log_debug "[${MODULE_NAME}] Counter $counter_name incremented by $increment (new value: ${METRICS_COUNTERS[$counter_name]})"
}

#
# Set a gauge metric
#
# Arguments:
#   $1 - Gauge name
#   $2 - Value
#   $3 - Optional: Tags
#
# Returns:
#   0 - Success
#
metrics_gauge_set() {
    local gauge_name="$1"
    local value="$2"
    local tags="${3:-}"
    
    METRICS_GAUGES[$gauge_name]="$value"
    METRICS_GAUGES[$gauge_name:timestamp]=$(date +%s)
    
    if [[ -n "$tags" ]]; then
        METRICS_TAGS[gauge:$gauge_name]="$tags"
    fi
    
    log_debug "[${MODULE_NAME}] Gauge $gauge_name set to $value"
}

#
# Record a value in a histogram
#
# Arguments:
#   $1 - Histogram name
#   $2 - Value
#
# Returns:
#   0 - Success
#
metrics_record_histogram() {
    local histogram_name="$1"
    local value="$2"
    
    # Get current values
    local values="${METRICS_HISTOGRAMS[$histogram_name:values]:-}"
    if [[ -n "$values" ]]; then
        values+=" "
    fi
    values+="$value"
    
    METRICS_HISTOGRAMS[$histogram_name:values]="$values"
    
    # Update statistics
    local count="${METRICS_HISTOGRAMS[$histogram_name:count]:-0}"
    local sum="${METRICS_HISTOGRAMS[$histogram_name:sum]:-0}"
    local min="${METRICS_HISTOGRAMS[$histogram_name:min]:-$value}"
    local max="${METRICS_HISTOGRAMS[$histogram_name:max]:-$value}"
    
    ((count++))
    sum=$((sum + value))
    
    if [[ $value -lt $min ]]; then
        min=$value
    fi
    if [[ $value -gt $max ]]; then
        max=$value
    fi
    
    METRICS_HISTOGRAMS[$histogram_name:count]="$count"
    METRICS_HISTOGRAMS[$histogram_name:sum]="$sum"
    METRICS_HISTOGRAMS[$histogram_name:min]="$min"
    METRICS_HISTOGRAMS[$histogram_name:max]="$max"
    METRICS_HISTOGRAMS[$histogram_name:avg]=$((sum / count))
}

# ============================================================================
# Resource Monitoring Functions
# ============================================================================

#
# Start resource monitoring
#
metrics_start_resource_monitoring() {
    local monitor_pid_file="/tmp/metrics-resource-monitor-$$.pid"
    local interval="${METRICS_CONFIG[collection_interval_seconds]}"
    
    {
        echo $$ > "$monitor_pid_file"
        
        while [[ "${METRICS_STATE[collection_started]}" == "true" ]]; do
            # Collect CPU usage
            if command -v top &>/dev/null; then
                local cpu_usage
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
                else
                    # Linux
                    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
                fi
                metrics_gauge_set "system.cpu.usage_percent" "${cpu_usage:-0}"
            fi
            
            # Collect memory usage
            if command -v free &>/dev/null; then
                # Linux
                local mem_info=$(free -m | grep "^Mem:")
                local total_mem=$(echo "$mem_info" | awk '{print $2}')
                local used_mem=$(echo "$mem_info" | awk '{print $3}')
                local mem_usage_percent=$((used_mem * 100 / total_mem))
                
                metrics_gauge_set "system.memory.total_mb" "$total_mem"
                metrics_gauge_set "system.memory.used_mb" "$used_mem"
                metrics_gauge_set "system.memory.usage_percent" "$mem_usage_percent"
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                local mem_info=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
                metrics_gauge_set "system.memory.free_pages" "${mem_info:-0}"
            fi
            
            # Collect disk usage
            local disk_info=$(df -h / | tail -1)
            local disk_usage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
            local disk_available=$(echo "$disk_info" | awk '{print $4}')
            
            metrics_gauge_set "system.disk.usage_percent" "${disk_usage:-0}"
            metrics_gauge_set "system.disk.available" "${disk_available:-0}"
            
            # Collect network stats (if available)
            if command -v netstat &>/dev/null; then
                local tcp_connections=$(netstat -an | grep -c "tcp.*ESTABLISHED" || echo 0)
                metrics_gauge_set "system.network.tcp_connections" "$tcp_connections"
            fi
            
            # Collect process info
            local process_count=$(ps aux | wc -l)
            metrics_gauge_set "system.process.count" "$process_count"
            
            sleep "$interval"
        done
    } &
    
    log_debug "[${MODULE_NAME}] Started resource monitoring (PID: $!)"
}

# ============================================================================
# AWS Metrics Integration
# ============================================================================

#
# Track AWS API call metrics
#
# Arguments:
#   $1 - Service name (ec2, s3, etc.)
#   $2 - Operation name
#   $3 - Duration in ms
#   $4 - Status (success|failure)
#
metrics_track_aws_api() {
    local service="$1"
    local operation="$2"
    local duration="$3"
    local status="$4"
    
    # Increment counters
    metrics_counter_increment "aws.api.calls.total"
    metrics_counter_increment "aws.api.calls.${service}.total"
    metrics_counter_increment "aws.api.calls.${service}.${operation}"
    
    if [[ "$status" == "failure" ]]; then
        metrics_counter_increment "aws.api.errors.total"
        metrics_counter_increment "aws.api.errors.${service}"
    fi
    
    # Record duration
    metrics_record_histogram "aws.api.duration.${service}" "$duration"
    
    # Update rate limiting metrics
    local current_time=$(date +%s)
    local rate_key="aws.api.rate.${service}"
    local last_call="${METRICS_GAUGES[$rate_key:last_call]:-0}"
    local interval=$((current_time - last_call))
    
    if [[ $interval -gt 0 ]]; then
        local rate=$((1000 / interval))  # Calls per second
        metrics_gauge_set "$rate_key" "$rate"
        METRICS_GAUGES[$rate_key:last_call]="$current_time"
    fi
}

# ============================================================================
# Reporting Functions
# ============================================================================

#
# Generate performance report
#
# Arguments:
#   $1 - Optional: Output format (json|text|markdown)
#
# Output:
#   Performance report in requested format
#
metrics_generate_report() {
    local format="${1:-${METRICS_CONFIG[output_format]}}"
    local report_time=$(date +%s)
    local elapsed=$((report_time - ${METRICS_STATE[start_time]} / 1000000000))
    
    case "$format" in
        json)
            metrics_report_json "$elapsed"
            ;;
        text)
            metrics_report_text "$elapsed"
            ;;
        markdown)
            metrics_report_markdown "$elapsed"
            ;;
        *)
            error_metrics_invalid_type "Unknown report format: $format"
            return 1
            ;;
    esac
}

#
# Generate JSON report
#
metrics_report_json() {
    local elapsed_seconds="$1"
    
    cat << EOF
{
    "timestamp": $(date +%s),
    "elapsed_seconds": $elapsed_seconds,
    "summary": {
        "total_operations": ${METRICS_STATE[total_operations]},
        "successful_operations": ${METRICS_STATE[successful_operations]},
        "failed_operations": ${METRICS_STATE[failed_operations]},
        "success_rate": $(awk "BEGIN {printf \"%.2f\", ${METRICS_STATE[successful_operations]} * 100 / ${METRICS_STATE[total_operations]}}")
    },
    "operations": $(metrics_operations_to_json),
    "counters": $(metrics_counters_to_json),
    "gauges": $(metrics_gauges_to_json),
    "histograms": $(metrics_histograms_to_json),
    "resource_usage": $(metrics_resource_usage_to_json)
}
EOF
}

#
# Generate text report
#
metrics_report_text() {
    local elapsed_seconds="$1"
    
    echo "=== Performance Metrics Report ==="
    echo "Generated: $(date)"
    echo "Elapsed Time: ${elapsed_seconds}s"
    echo ""
    
    echo "=== Summary ==="
    echo "Total Operations: ${METRICS_STATE[total_operations]}"
    echo "Successful: ${METRICS_STATE[successful_operations]}"
    echo "Failed: ${METRICS_STATE[failed_operations]}"
    
    if [[ ${METRICS_STATE[total_operations]} -gt 0 ]]; then
        local success_rate=$((${METRICS_STATE[successful_operations]} * 100 / ${METRICS_STATE[total_operations]}))
        echo "Success Rate: ${success_rate}%"
    fi
    echo ""
    
    echo "=== Top Operations by Duration ==="
    metrics_print_top_operations 10
    echo ""
    
    echo "=== Resource Usage ==="
    metrics_print_resource_usage
    echo ""
    
    echo "=== AWS API Metrics ==="
    metrics_print_aws_metrics
}

#
# Generate markdown report
#
metrics_report_markdown() {
    local elapsed_seconds="$1"
    
    cat << EOF
# Performance Metrics Report

**Generated:** $(date)  
**Elapsed Time:** ${elapsed_seconds}s

## Summary

| Metric | Value |
|--------|-------|
| Total Operations | ${METRICS_STATE[total_operations]} |
| Successful | ${METRICS_STATE[successful_operations]} |
| Failed | ${METRICS_STATE[failed_operations]} |
| Success Rate | $((${METRICS_STATE[successful_operations]} * 100 / ${METRICS_STATE[total_operations]}))% |

## Top Operations by Duration

$(metrics_print_top_operations_markdown 10)

## Resource Usage

$(metrics_print_resource_usage_markdown)

## AWS API Metrics

$(metrics_print_aws_metrics_markdown)
EOF
}

# ============================================================================
# Export Functions
# ============================================================================

#
# Export metrics to CloudWatch
#
# Returns:
#   0 - Success
#   1 - Failed
#
metrics_export_cloudwatch() {
    if [[ "${METRICS_CONFIG[enable_cloudwatch_export]}" != "true" ]]; then
        log_debug "[${MODULE_NAME}] CloudWatch export disabled"
        return 0
    fi
    
    local namespace="${METRICS_CONFIG[cloudwatch_namespace]}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    log_info "[${MODULE_NAME}] Exporting metrics to CloudWatch namespace: $namespace"
    
    # Export counters
    for counter in "${!METRICS_COUNTERS[@]}"; do
        local value="${METRICS_COUNTERS[$counter]}"
        
        aws cloudwatch put-metric-data \
            --namespace "$namespace" \
            --metric-name "$counter" \
            --value "$value" \
            --timestamp "$timestamp" \
            --region "${AWS_REGION:-us-east-1}" 2>/dev/null || {
                log_warn "[${MODULE_NAME}] Failed to export counter: $counter"
            }
    done
    
    # Export gauges
    for gauge in "${!METRICS_GAUGES[@]}"; do
        [[ "$gauge" =~ :timestamp$ ]] && continue
        [[ "$gauge" =~ :last_call$ ]] && continue
        
        local value="${METRICS_GAUGES[$gauge]}"
        
        aws cloudwatch put-metric-data \
            --namespace "$namespace" \
            --metric-name "$gauge" \
            --value "$value" \
            --timestamp "$timestamp" \
            --region "${AWS_REGION:-us-east-1}" 2>/dev/null || {
                log_warn "[${MODULE_NAME}] Failed to export gauge: $gauge"
            }
    done
    
    log_info "[${MODULE_NAME}] CloudWatch export completed"
}

# ============================================================================
# Utility Functions
# ============================================================================

#
# Print top operations by duration
#
metrics_print_top_operations() {
    local limit="${1:-10}"
    local -a operations_list=()
    
    # Collect operations with duration
    for key in "${!METRICS_OPERATIONS[@]}"; do
        if [[ "$key" =~ :duration_ms$ ]]; then
            local op_key="${key%:duration_ms}"
            local duration="${METRICS_OPERATIONS[$key]}"
            local status="${METRICS_OPERATIONS[$op_key:status]:-unknown}"
            operations_list+=("$duration|$op_key|$status")
        fi
    done
    
    # Sort and display
    printf "%-50s %10s %10s\n" "Operation" "Duration" "Status"
    printf "%s\n" "${operations_list[@]}" | sort -rn | head -n "$limit" | while IFS='|' read -r duration op_key status; do
        printf "%-50s %10sms %10s\n" "$op_key" "$duration" "$status"
    done
}

#
# Convert operations to JSON
#
metrics_operations_to_json() {
    local first=true
    echo -n "{"
    
    for key in "${!METRICS_OPERATIONS[@]}"; do
        if [[ "$key" =~ :duration_ms$ ]]; then
            local op_key="${key%:duration_ms}"
            local duration="${METRICS_OPERATIONS[$key]}"
            local status="${METRICS_OPERATIONS[$op_key:status]:-unknown}"
            
            [[ "$first" == "true" ]] && first=false || echo -n ","
            echo -n "\"$op_key\":{\"duration_ms\":$duration,\"status\":\"$status\"}"
        fi
    done
    
    echo -n "}"
}

#
# Start periodic metrics flush
#
metrics_start_periodic_flush() {
    local flush_pid_file="/tmp/metrics-flush-$$.pid"
    local interval="${METRICS_CONFIG[flush_interval_seconds]}"
    
    {
        echo $$ > "$flush_pid_file"
        
        while [[ "${METRICS_STATE[collection_started]}" == "true" ]]; do
            sleep "$interval"
            
            # Save metrics to file
            metrics_generate_report "json" > "${METRICS_STATE[metrics_file]}"
            
            # Export to CloudWatch if enabled
            metrics_export_cloudwatch
        done
    } &
    
    log_debug "[${MODULE_NAME}] Started periodic flush (PID: $!)"
}

#
# Stop metrics collection
#
metrics_stop() {
    log_info "[${MODULE_NAME}] Stopping metrics collection"
    
    METRICS_STATE[collection_started]="false"
    
    # Generate final report
    metrics_generate_report
    
    # Final CloudWatch export
    metrics_export_cloudwatch
    
    # Kill background processes
    pkill -f "metrics-resource-monitor-$$" 2>/dev/null || true
    pkill -f "metrics-flush-$$" 2>/dev/null || true
}

# ============================================================================
# Helper Functions
# ============================================================================

#
# Convert counters to JSON
#
metrics_counters_to_json() {
    local first=true
    echo -n "{"
    
    for counter in "${!METRICS_COUNTERS[@]}"; do
        [[ "$first" == "true" ]] && first=false || echo -n ","
        echo -n "\"$counter\":${METRICS_COUNTERS[$counter]}"
    done
    
    echo -n "}"
}

#
# Convert gauges to JSON
#
metrics_gauges_to_json() {
    local first=true
    echo -n "{"
    
    for gauge in "${!METRICS_GAUGES[@]}"; do
        [[ "$gauge" =~ :timestamp$ ]] && continue
        [[ "$gauge" =~ :last_call$ ]] && continue
        
        [[ "$first" == "true" ]] && first=false || echo -n ","
        echo -n "\"$gauge\":${METRICS_GAUGES[$gauge]}"
    done
    
    echo -n "}"
}

#
# Convert histograms to JSON
#
metrics_histograms_to_json() {
    local first=true
    echo -n "{"
    
    for histogram in "${!METRICS_HISTOGRAMS[@]}"; do
        if [[ "$histogram" =~ :count$ ]]; then
            local hist_name="${histogram%:count}"
            
            [[ "$first" == "true" ]] && first=false || echo -n ","
            echo -n "\"$hist_name\":{"
            echo -n "\"count\":${METRICS_HISTOGRAMS[$hist_name:count]},"
            echo -n "\"sum\":${METRICS_HISTOGRAMS[$hist_name:sum]},"
            echo -n "\"min\":${METRICS_HISTOGRAMS[$hist_name:min]},"
            echo -n "\"max\":${METRICS_HISTOGRAMS[$hist_name:max]},"
            echo -n "\"avg\":${METRICS_HISTOGRAMS[$hist_name:avg]}"
            echo -n "}"
        fi
    done
    
    echo -n "}"
}

#
# Convert resource usage to JSON
#
metrics_resource_usage_to_json() {
    echo -n "{"
    echo -n "\"cpu\":{\"usage_percent\":${METRICS_GAUGES[system.cpu.usage_percent]:-0}},"
    echo -n "\"memory\":{"
    echo -n "\"total_mb\":${METRICS_GAUGES[system.memory.total_mb]:-0},"
    echo -n "\"used_mb\":${METRICS_GAUGES[system.memory.used_mb]:-0},"
    echo -n "\"usage_percent\":${METRICS_GAUGES[system.memory.usage_percent]:-0}"
    echo -n "},"
    echo -n "\"disk\":{"
    echo -n "\"usage_percent\":${METRICS_GAUGES[system.disk.usage_percent]:-0},"
    echo -n "\"available\":\"${METRICS_GAUGES[system.disk.available]:-0}\""
    echo -n "},"
    echo -n "\"network\":{\"tcp_connections\":${METRICS_GAUGES[system.network.tcp_connections]:-0}},"
    echo -n "\"process\":{\"count\":${METRICS_GAUGES[system.process.count]:-0}}"
    echo -n "}"
}

# ============================================================================
# Error Handler Functions
# ============================================================================

#
# Register module-specific error handlers
#
metrics_register_error_handlers() {
    for error_type in "${!METRICS_ERROR_TYPES[@]}"; do
        local handler_name="error_$(echo "$error_type" | tr '[:upper:]' '[:lower:]')"
        
        # Create error handler function dynamically
        eval "
        $handler_name() {
            local message=\"\${1:-${METRICS_ERROR_TYPES[$error_type]}}\"
            log_error \"[${MODULE_NAME}] \$message\"
            return 1
        }
        "
    done
}

# Register error handlers
metrics_register_error_handlers

# ============================================================================
# Module Exports
# ============================================================================

# Export public functions
export -f metrics_init
export -f metrics_operation_start
export -f metrics_operation_end
export -f metrics_counter_increment
export -f metrics_gauge_set
export -f metrics_record_histogram
export -f metrics_track_aws_api
export -f metrics_generate_report
export -f metrics_export_cloudwatch
export -f metrics_stop

# Export module state
export METRICS_STATE
export METRICS_CONFIG

# Module metadata
export METRICS_MODULE_VERSION="1.0.0"
export METRICS_MODULE_NAME="${MODULE_NAME}"

# Cleanup on exit
trap 'metrics_stop 2>/dev/null || true' EXIT

# Indicate module is loaded
log_debug "[${MODULE_NAME}] Module loaded successfully"