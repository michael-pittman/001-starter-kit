#!/usr/bin/env bash
# =============================================================================
# Performance Metrics Collection and Reporting Module
# Provides comprehensive performance metrics for deployments and systems
# =============================================================================

# Prevent multiple sourcing
[ -n "${_PERFORMANCE_METRICS_SH_LOADED:-}" ] && return 0
_PERFORMANCE_METRICS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/structured_logging.sh"
source "${SCRIPT_DIR}/metrics.sh"
source "${SCRIPT_DIR}/../performance/metrics.sh"

# =============================================================================
# METRIC CONFIGURATION
# =============================================================================

# Metric categories
readonly METRIC_CAT_DEPLOYMENT="deployment"
readonly METRIC_CAT_INFRASTRUCTURE="infrastructure"
readonly METRIC_CAT_APPLICATION="application"
readonly METRIC_CAT_SYSTEM="system"
readonly METRIC_CAT_CUSTOM="custom"

# Metric types
readonly METRIC_TYPE_COUNTER="counter"
readonly METRIC_TYPE_GAUGE="gauge"
readonly METRIC_TYPE_HISTOGRAM="histogram"
readonly METRIC_TYPE_SUMMARY="summary"

# Collection intervals
readonly COLLECT_INTERVAL_REALTIME=5
readonly COLLECT_INTERVAL_FAST=30
readonly COLLECT_INTERVAL_NORMAL=60
readonly COLLECT_INTERVAL_SLOW=300

# Global configuration
PERF_METRICS_ENABLED="${PERF_METRICS_ENABLED:-true}"
PERF_METRICS_INTERVAL="${PERF_METRICS_INTERVAL:-$COLLECT_INTERVAL_NORMAL}"
PERF_METRICS_STORAGE_FILE="/tmp/perf_metrics_$$.json"
PERF_METRICS_AGGREGATION_FILE="/tmp/perf_metrics_agg_$$.json"

# Metric storage
METRIC_COLLECTORS=()
METRIC_TIMESERIES=()

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize performance metrics
init_performance_metrics() {
    local interval="${1:-$COLLECT_INTERVAL_NORMAL}"
    local enable_aggregation="${2:-true}"
    
    log_info "Initializing performance metrics collection" "PERF_METRICS"
    
    # Set collection interval
    PERF_METRICS_INTERVAL="$interval"
    
    # Initialize storage
    echo "[]" > "$PERF_METRICS_STORAGE_FILE"
    echo "{}" > "$PERF_METRICS_AGGREGATION_FILE"
    
    # Register default collectors
    register_default_collectors
    
    # Start collection if enabled
    if [[ "$PERF_METRICS_ENABLED" == "true" ]]; then
        start_metrics_collection
    fi
    
    log_info "Performance metrics initialized (interval: ${interval}s)" "PERF_METRICS"
    return 0
}

# =============================================================================
# METRIC COLLECTORS
# =============================================================================

# Register default collectors
register_default_collectors() {
    log_info "Registering default metric collectors" "PERF_METRICS"
    
    # System metrics
    register_metric_collector "system_cpu" \
        "collect_cpu_metrics" \
        "$METRIC_CAT_SYSTEM" \
        "$COLLECT_INTERVAL_FAST"
    
    register_metric_collector "system_memory" \
        "collect_memory_metrics" \
        "$METRIC_CAT_SYSTEM" \
        "$COLLECT_INTERVAL_FAST"
    
    register_metric_collector "system_disk" \
        "collect_disk_metrics" \
        "$METRIC_CAT_SYSTEM" \
        "$COLLECT_INTERVAL_NORMAL"
    
    register_metric_collector "system_network" \
        "collect_network_metrics" \
        "$METRIC_CAT_SYSTEM" \
        "$COLLECT_INTERVAL_FAST"
    
    # Deployment metrics
    register_metric_collector "deployment_progress" \
        "collect_deployment_progress_metrics" \
        "$METRIC_CAT_DEPLOYMENT" \
        "$COLLECT_INTERVAL_FAST"
    
    register_metric_collector "deployment_duration" \
        "collect_deployment_duration_metrics" \
        "$METRIC_CAT_DEPLOYMENT" \
        "$COLLECT_INTERVAL_NORMAL"
    
    # Infrastructure metrics
    register_metric_collector "infrastructure_resources" \
        "collect_infrastructure_metrics" \
        "$METRIC_CAT_INFRASTRUCTURE" \
        "$COLLECT_INTERVAL_NORMAL"
    
    # Application metrics
    register_metric_collector "application_health" \
        "collect_application_health_metrics" \
        "$METRIC_CAT_APPLICATION" \
        "$COLLECT_INTERVAL_NORMAL"
}

# Register metric collector
register_metric_collector() {
    local collector_id="$1"
    local collector_func="$2"
    local category="$3"
    local interval="${4:-$COLLECT_INTERVAL_NORMAL}"
    
    log_debug "Registering metric collector: $collector_id" "PERF_METRICS"
    
    local collector
    collector=$(cat <<EOF
{
    "id": "$collector_id",
    "function": "$collector_func",
    "category": "$category",
    "interval": $interval,
    "enabled": true,
    "last_run": 0
}
EOF
)
    
    METRIC_COLLECTORS+=("$collector")
}

# =============================================================================
# METRIC COLLECTION
# =============================================================================

# Start metrics collection
start_metrics_collection() {
    log_info "Starting metrics collection" "PERF_METRICS"
    
    # Create collection loop script
    local collector_script="/tmp/perf_metrics_collector_$$.sh"
    cat > "$collector_script" <<'EOF'
#!/usr/bin/env bash
source "${LIB_DIR:-/usr/local/lib}/modules/monitoring/performance_metrics.sh"

while true; do
    run_metric_collectors
    sleep ${PERF_METRICS_INTERVAL:-60}
done
EOF
    
    chmod +x "$collector_script"
    
    # Start collector in background
    nohup "$collector_script" > /tmp/perf_metrics_collector_$$.log 2>&1 &
    local collector_pid=$!
    
    # Store collector PID
    echo "$collector_pid" > /tmp/perf_metrics_collector_$$.pid
    
    log_info "Metrics collector started with PID: $collector_pid" "PERF_METRICS"
}

# Run metric collectors
run_metric_collectors() {
    local current_time=$(date +%s)
    
    for collector in "${METRIC_COLLECTORS[@]}"; do
        local enabled=$(echo "$collector" | jq -r '.enabled')
        if [[ "$enabled" != "true" ]]; then
            continue
        fi
        
        local collector_id=$(echo "$collector" | jq -r '.id')
        local collector_func=$(echo "$collector" | jq -r '.function')
        local interval=$(echo "$collector" | jq -r '.interval')
        local last_run=$(echo "$collector" | jq -r '.last_run')
        
        # Check if it's time to run
        if [[ $((current_time - last_run)) -ge $interval ]]; then
            log_debug "Running collector: $collector_id" "PERF_METRICS"
            
            # Run collector function
            if declare -f "$collector_func" >/dev/null 2>&1; then
                "$collector_func"
                
                # Update last run time
                update_collector_last_run "$collector_id" "$current_time"
            else
                log_warn "Collector function not found: $collector_func" "PERF_METRICS"
            fi
        fi
    done
}

# Update collector last run time
update_collector_last_run() {
    local collector_id="$1"
    local timestamp="$2"
    
    local updated_collectors=()
    for collector in "${METRIC_COLLECTORS[@]}"; do
        local id=$(echo "$collector" | jq -r '.id')
        if [[ "$id" == "$collector_id" ]]; then
            collector=$(echo "$collector" | jq --arg ts "$timestamp" '.last_run = ($ts | tonumber)')
        fi
        updated_collectors+=("$collector")
    done
    
    METRIC_COLLECTORS=("${updated_collectors[@]}")
}

# =============================================================================
# SYSTEM METRICS COLLECTORS
# =============================================================================

# Collect CPU metrics
collect_cpu_metrics() {
    local timestamp=$(date +%s)
    
    # Get CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    # Get load averages
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    local load_1m=$(echo "$load_avg" | awk -F',' '{print $1}' | xargs)
    local load_5m=$(echo "$load_avg" | awk -F',' '{print $2}' | xargs)
    local load_15m=$(echo "$load_avg" | awk -F',' '{print $3}' | xargs)
    
    # Record metrics
    record_performance_metric "system.cpu.usage" "$cpu_usage" "$METRIC_TYPE_GAUGE" "percent"
    record_performance_metric "system.cpu.load.1m" "$load_1m" "$METRIC_TYPE_GAUGE" "load"
    record_performance_metric "system.cpu.load.5m" "$load_5m" "$METRIC_TYPE_GAUGE" "load"
    record_performance_metric "system.cpu.load.15m" "$load_15m" "$METRIC_TYPE_GAUGE" "load"
    
    # Get CPU count
    local cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "1")
    record_performance_metric "system.cpu.count" "$cpu_count" "$METRIC_TYPE_GAUGE" "count"
}

# Collect memory metrics
collect_memory_metrics() {
    local timestamp=$(date +%s)
    
    # Get memory info
    if command -v free >/dev/null 2>&1; then
        # Linux
        local mem_info=$(free -m | grep "^Mem:")
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        local mem_used=$(echo "$mem_info" | awk '{print $3}')
        local mem_free=$(echo "$mem_info" | awk '{print $4}')
        local mem_available=$(echo "$mem_info" | awk '{print $7}')
    else
        # macOS
        local mem_total=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
        local mem_stats=$(vm_stat | grep "Pages")
        local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
        local mem_free=$(( $(echo "$mem_stats" | grep "free:" | awk '{print $3}' | tr -d '.') * page_size / 1024 / 1024 ))
        local mem_used=$(( mem_total - mem_free ))
        local mem_available=$mem_free
    fi
    
    # Calculate usage percentage
    local mem_usage_percent=$(echo "scale=2; $mem_used * 100 / $mem_total" | bc)
    
    # Record metrics
    record_performance_metric "system.memory.total" "$mem_total" "$METRIC_TYPE_GAUGE" "MB"
    record_performance_metric "system.memory.used" "$mem_used" "$METRIC_TYPE_GAUGE" "MB"
    record_performance_metric "system.memory.free" "$mem_free" "$METRIC_TYPE_GAUGE" "MB"
    record_performance_metric "system.memory.available" "$mem_available" "$METRIC_TYPE_GAUGE" "MB"
    record_performance_metric "system.memory.usage" "$mem_usage_percent" "$METRIC_TYPE_GAUGE" "percent"
}

# Collect disk metrics
collect_disk_metrics() {
    local timestamp=$(date +%s)
    
    # Get disk usage for root partition
    local disk_info=$(df -h / | tail -1)
    local disk_total=$(echo "$disk_info" | awk '{print $2}' | sed 's/[^0-9.]//g')
    local disk_used=$(echo "$disk_info" | awk '{print $3}' | sed 's/[^0-9.]//g')
    local disk_available=$(echo "$disk_info" | awk '{print $4}' | sed 's/[^0-9.]//g')
    local disk_usage_percent=$(echo "$disk_info" | awk '{print $5}' | cut -d'%' -f1)
    
    # Record metrics
    record_performance_metric "system.disk.total" "$disk_total" "$METRIC_TYPE_GAUGE" "GB"
    record_performance_metric "system.disk.used" "$disk_used" "$METRIC_TYPE_GAUGE" "GB"
    record_performance_metric "system.disk.available" "$disk_available" "$METRIC_TYPE_GAUGE" "GB"
    record_performance_metric "system.disk.usage" "$disk_usage_percent" "$METRIC_TYPE_GAUGE" "percent"
    
    # Get disk I/O stats if available
    if command -v iostat >/dev/null 2>&1; then
        local io_stats=$(iostat -d 1 2 | tail -n +4 | head -1)
        local read_kb=$(echo "$io_stats" | awk '{print $3}')
        local write_kb=$(echo "$io_stats" | awk '{print $4}')
        
        record_performance_metric "system.disk.io.read" "$read_kb" "$METRIC_TYPE_COUNTER" "KB/s"
        record_performance_metric "system.disk.io.write" "$write_kb" "$METRIC_TYPE_COUNTER" "KB/s"
    fi
}

# Collect network metrics
collect_network_metrics() {
    local timestamp=$(date +%s)
    
    # Get primary network interface
    local primary_interface
    if [[ "$(uname)" == "Darwin" ]]; then
        primary_interface=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
    else
        primary_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    fi
    
    if [[ -n "$primary_interface" ]]; then
        # Get network statistics
        if command -v ifstat >/dev/null 2>&1; then
            local net_stats=$(ifstat -i "$primary_interface" 1 1 | tail -1)
            local bytes_in=$(echo "$net_stats" | awk '{print $1}')
            local bytes_out=$(echo "$net_stats" | awk '{print $2}')
            
            record_performance_metric "system.network.bytes_in" "$bytes_in" "$METRIC_TYPE_COUNTER" "KB/s"
            record_performance_metric "system.network.bytes_out" "$bytes_out" "$METRIC_TYPE_COUNTER" "KB/s"
        fi
        
        # Get connection count
        local conn_count=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo "0")
        record_performance_metric "system.network.connections" "$conn_count" "$METRIC_TYPE_GAUGE" "count"
    fi
}

# =============================================================================
# DEPLOYMENT METRICS COLLECTORS
# =============================================================================

# Collect deployment progress metrics
collect_deployment_progress_metrics() {
    local stack_name="${STACK_NAME:-}"
    if [[ -z "$stack_name" ]]; then
        return 0
    fi
    
    # Get deployment state
    local deployment_state=$(get_variable "DEPLOYMENT_STATE" "$VARIABLE_SCOPE_STACK")
    local deployment_phase=$(get_variable "DEPLOYMENT_PHASE" "$VARIABLE_SCOPE_STACK")
    local deployment_progress=$(get_variable "DEPLOYMENT_PROGRESS" "$VARIABLE_SCOPE_STACK" || echo "0")
    
    # Convert state to numeric
    local state_value
    case "$deployment_state" in
        "initializing") state_value=1 ;;
        "running") state_value=2 ;;
        "completed") state_value=3 ;;
        "failed") state_value=4 ;;
        "rollback") state_value=5 ;;
        *) state_value=0 ;;
    esac
    
    # Record metrics
    record_performance_metric "deployment.state" "$state_value" "$METRIC_TYPE_GAUGE" "state"
    record_performance_metric "deployment.progress" "$deployment_progress" "$METRIC_TYPE_GAUGE" "percent"
    
    # Record phase timing
    local phase_start=$(get_variable "PHASE_START_TIME" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$phase_start" ]]; then
        local phase_duration=$(($(date +%s) - phase_start))
        record_performance_metric "deployment.phase.duration" "$phase_duration" "$METRIC_TYPE_GAUGE" "seconds" \
            "{\"phase\": \"$deployment_phase\"}"
    fi
}

# Collect deployment duration metrics
collect_deployment_duration_metrics() {
    local stack_name="${STACK_NAME:-}"
    if [[ -z "$stack_name" ]]; then
        return 0
    fi
    
    # Get deployment timing
    local deployment_start=$(get_variable "DEPLOYMENT_START_TIME" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$deployment_start" ]]; then
        local current_time=$(date +%s)
        local total_duration=$((current_time - deployment_start))
        
        record_performance_metric "deployment.total_duration" "$total_duration" "$METRIC_TYPE_GAUGE" "seconds"
    fi
    
    # Get phase durations
    local phases=("validation" "infrastructure" "compute" "application" "verification")
    for phase in "${phases[@]}"; do
        local phase_duration=$(get_variable "PHASE_${phase^^}_DURATION" "$VARIABLE_SCOPE_STACK")
        if [[ -n "$phase_duration" ]]; then
            record_performance_metric "deployment.phase.completed_duration" "$phase_duration" \
                "$METRIC_TYPE_GAUGE" "seconds" "{\"phase\": \"$phase\"}"
        fi
    done
}

# =============================================================================
# INFRASTRUCTURE METRICS COLLECTORS
# =============================================================================

# Collect infrastructure metrics
collect_infrastructure_metrics() {
    local stack_name="${STACK_NAME:-}"
    if [[ -z "$stack_name" ]]; then
        return 0
    fi
    
    # Count resources
    local vpc_count=0
    local subnet_count=0
    local instance_count=0
    local sg_count=0
    
    # Check VPC
    local vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$vpc_id" ]]; then
        vpc_count=1
        
        # Count subnets
        subnet_count=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'length(Subnets)' \
            --output text 2>/dev/null || echo "0")
    fi
    
    # Check instances
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$instance_id" ]]; then
        instance_count=1
        
        # Get instance metrics
        local instance_info=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0]' \
            2>/dev/null || echo "{}")
        
        if [[ "$instance_info" != "{}" ]]; then
            local instance_type=$(echo "$instance_info" | jq -r '.InstanceType // "unknown"')
            local instance_state=$(echo "$instance_info" | jq -r '.State.Name // "unknown"')
            
            # Record instance state
            local state_value
            case "$instance_state" in
                "running") state_value=1 ;;
                "stopped") state_value=0 ;;
                "terminated") state_value=-1 ;;
                *) state_value=0 ;;
            esac
            
            record_performance_metric "infrastructure.instance.state" "$state_value" \
                "$METRIC_TYPE_GAUGE" "state" "{\"instance_type\": \"$instance_type\"}"
        fi
    fi
    
    # Record resource counts
    record_performance_metric "infrastructure.vpc.count" "$vpc_count" "$METRIC_TYPE_GAUGE" "count"
    record_performance_metric "infrastructure.subnet.count" "$subnet_count" "$METRIC_TYPE_GAUGE" "count"
    record_performance_metric "infrastructure.instance.count" "$instance_count" "$METRIC_TYPE_GAUGE" "count"
    
    # Check ALB if exists
    local alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$alb_arn" ]]; then
        record_performance_metric "infrastructure.alb.count" "1" "$METRIC_TYPE_GAUGE" "count"
    fi
}

# =============================================================================
# APPLICATION METRICS COLLECTORS
# =============================================================================

# Collect application health metrics
collect_application_health_metrics() {
    local stack_name="${STACK_NAME:-}"
    if [[ -z "$stack_name" ]]; then
        return 0
    fi
    
    # Define services
    local services=("n8n" "qdrant" "ollama" "crawl4ai")
    local healthy_count=0
    local total_count=0
    
    for service in "${services[@]}"; do
        local enable_var="${service^^}_ENABLE"
        if [[ "${!enable_var}" != "false" ]]; then
            total_count=$((total_count + 1))
            
            # Simple health check (would be replaced with actual health checks)
            local is_healthy=1  # Assume healthy for now
            if [[ $is_healthy -eq 1 ]]; then
                healthy_count=$((healthy_count + 1))
            fi
            
            record_performance_metric "application.service.health" "$is_healthy" \
                "$METRIC_TYPE_GAUGE" "bool" "{\"service\": \"$service\"}"
        fi
    done
    
    # Calculate overall health percentage
    if [[ $total_count -gt 0 ]]; then
        local health_percentage=$(echo "scale=2; $healthy_count * 100 / $total_count" | bc)
        record_performance_metric "application.health.percentage" "$health_percentage" \
            "$METRIC_TYPE_GAUGE" "percent"
    fi
    
    # Record service counts
    record_performance_metric "application.service.total" "$total_count" "$METRIC_TYPE_GAUGE" "count"
    record_performance_metric "application.service.healthy" "$healthy_count" "$METRIC_TYPE_GAUGE" "count"
}

# =============================================================================
# METRIC RECORDING AND AGGREGATION
# =============================================================================

# Record performance metric
record_performance_metric() {
    local metric_name="$1"
    local value="$2"
    local metric_type="$3"
    local unit="${4:-count}"
    local labels="${5:-{}}"
    
    local timestamp=$(date +%s)
    
    # Create metric object
    local metric
    metric=$(cat <<EOF
{
    "name": "$metric_name",
    "value": $value,
    "type": "$metric_type",
    "unit": "$unit",
    "timestamp": $timestamp,
    "labels": $labels
}
EOF
)
    
    # Add to timeseries
    METRIC_TIMESERIES+=("$metric")
    
    # Store in file
    store_metric "$metric"
    
    # Update aggregations
    update_metric_aggregation "$metric"
    
    # Log as performance metric
    log_performance_metric "$metric_name" "$value" "$unit" "perf_metrics" "$labels"
}

# Store metric
store_metric() {
    local metric="$1"
    
    # Add to storage file
    local temp_file="${PERF_METRICS_STORAGE_FILE}.tmp"
    jq --argjson metric "$metric" '. += [$metric]' "$PERF_METRICS_STORAGE_FILE" > "$temp_file" && \
        mv "$temp_file" "$PERF_METRICS_STORAGE_FILE"
}

# Update metric aggregation
update_metric_aggregation() {
    local metric="$1"
    
    local metric_name=$(echo "$metric" | jq -r '.name')
    local value=$(echo "$metric" | jq -r '.value')
    local metric_type=$(echo "$metric" | jq -r '.type')
    
    # Get current aggregation
    local current_agg=$(jq --arg name "$metric_name" '.[$name] // {}' "$PERF_METRICS_AGGREGATION_FILE")
    
    # Update aggregation based on type
    case "$metric_type" in
        "$METRIC_TYPE_COUNTER")
            # For counters, track total
            local total=$(echo "$current_agg" | jq -r '.total // 0')
            total=$(echo "$total + $value" | bc)
            current_agg=$(echo "$current_agg" | jq --argjson total "$total" '.total = $total')
            ;;
        "$METRIC_TYPE_GAUGE")
            # For gauges, track min/max/avg
            local count=$(echo "$current_agg" | jq -r '.count // 0')
            local min=$(echo "$current_agg" | jq -r '.min // null')
            local max=$(echo "$current_agg" | jq -r '.max // null')
            local sum=$(echo "$current_agg" | jq -r '.sum // 0')
            
            count=$((count + 1))
            sum=$(echo "$sum + $value" | bc)
            
            if [[ "$min" == "null" ]] || (( $(echo "$value < $min" | bc -l) )); then
                min=$value
            fi
            
            if [[ "$max" == "null" ]] || (( $(echo "$value > $max" | bc -l) )); then
                max=$value
            fi
            
            local avg=$(echo "scale=2; $sum / $count" | bc)
            
            current_agg=$(echo "$current_agg" | jq \
                --argjson count "$count" \
                --argjson min "$min" \
                --argjson max "$max" \
                --argjson sum "$sum" \
                --argjson avg "$avg" \
                '.count = $count | .min = $min | .max = $max | .sum = $sum | .avg = $avg')
            ;;
    esac
    
    # Update last value and timestamp
    current_agg=$(echo "$current_agg" | jq \
        --argjson value "$value" \
        --argjson ts "$(date +%s)" \
        '.last_value = $value | .last_update = $ts')
    
    # Save aggregation
    local temp_file="${PERF_METRICS_AGGREGATION_FILE}.tmp"
    jq --arg name "$metric_name" --argjson agg "$current_agg" '.[$name] = $agg' \
        "$PERF_METRICS_AGGREGATION_FILE" > "$temp_file" && \
        mv "$temp_file" "$PERF_METRICS_AGGREGATION_FILE"
}

# =============================================================================
# METRIC QUERIES AND REPORTING
# =============================================================================

# Query metrics
query_metrics() {
    local metric_filter="${1:-.}"
    local time_window="${2:-3600}"  # Default 1 hour
    local aggregation="${3:-raw}"   # raw, avg, sum, min, max
    
    local current_time=$(date +%s)
    local start_time=$((current_time - time_window))
    
    # Filter metrics by time and pattern
    local query=".[] | select(.timestamp >= $start_time)"
    if [[ "$metric_filter" != "." ]]; then
        query+=" | select(.name | test(\"$metric_filter\"))"
    fi
    
    # Apply aggregation if requested
    case "$aggregation" in
        "avg")
            jq "[$query] | group_by(.name) | map({name: .[0].name, avg: ([.[].value] | add / length)})" \
                "$PERF_METRICS_STORAGE_FILE"
            ;;
        "sum")
            jq "[$query] | group_by(.name) | map({name: .[0].name, sum: ([.[].value] | add)})" \
                "$PERF_METRICS_STORAGE_FILE"
            ;;
        "min")
            jq "[$query] | group_by(.name) | map({name: .[0].name, min: ([.[].value] | min)})" \
                "$PERF_METRICS_STORAGE_FILE"
            ;;
        "max")
            jq "[$query] | group_by(.name) | map({name: .[0].name, max: ([.[].value] | max)})" \
                "$PERF_METRICS_STORAGE_FILE"
            ;;
        "raw")
            jq "[$query]" "$PERF_METRICS_STORAGE_FILE"
            ;;
    esac
}

# Get metric statistics
get_metric_statistics() {
    local metric_name="$1"
    local time_window="${2:-3600}"
    
    # Get aggregated stats
    local agg_stats=$(jq --arg name "$metric_name" '.[$name] // {}' "$PERF_METRICS_AGGREGATION_FILE")
    
    # Get recent values
    local recent_values=$(query_metrics "^$metric_name$" "$time_window" "raw")
    local recent_count=$(echo "$recent_values" | jq 'length')
    
    # Build statistics
    cat <<EOF
{
    "metric": "$metric_name",
    "aggregation": $agg_stats,
    "recent": {
        "count": $recent_count,
        "time_window": $time_window,
        "values": $(echo "$recent_values" | jq '[.[-10:]]')
    }
}
EOF
}

# Generate performance report
generate_performance_report() {
    local output_file="${1:-}"
    local time_window="${2:-3600}"
    
    log_info "Generating performance report" "PERF_METRICS"
    
    local report
    report=$(cat <<EOF
# Performance Metrics Report
Generated: $(date)
Time Window: $(($time_window / 60)) minutes

## System Metrics Summary
$(jq '.[] | select(startswith("system."))' "$PERF_METRICS_AGGREGATION_FILE" | jq -s '.')

## Deployment Metrics Summary
$(jq '.[] | select(startswith("deployment."))' "$PERF_METRICS_AGGREGATION_FILE" | jq -s '.')

## Infrastructure Metrics Summary
$(jq '.[] | select(startswith("infrastructure."))' "$PERF_METRICS_AGGREGATION_FILE" | jq -s '.')

## Application Metrics Summary
$(jq '.[] | select(startswith("application."))' "$PERF_METRICS_AGGREGATION_FILE" | jq -s '.')

## Top Metrics by Value (Last Hour)
$(query_metrics "." "$time_window" "raw" | jq 'sort_by(.value) | reverse | .[0:10]')

## Metric Trends
### CPU Usage
$(get_metric_statistics "system.cpu.usage" "$time_window")

### Memory Usage
$(get_metric_statistics "system.memory.usage" "$time_window")

### Deployment Progress
$(get_metric_statistics "deployment.progress" "$time_window")

## Registered Collectors
$(printf '[%s]' "$(IFS=','; echo "${METRIC_COLLECTORS[*]}")" | jq '.')
EOF
)
    
    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        log_info "Performance report generated: $output_file" "PERF_METRICS"
    else
        echo "$report"
    fi
}

# Export metrics to CloudWatch
export_metrics_to_cloudwatch() {
    local namespace="${1:-GeuseMaker}"
    local time_window="${2:-300}"  # Last 5 minutes
    
    log_info "Exporting metrics to CloudWatch" "PERF_METRICS"
    
    # Get recent metrics
    local metrics=$(query_metrics "." "$time_window" "raw")
    
    # Export each metric
    local metric
    while IFS= read -r metric; do
        local name=$(echo "$metric" | jq -r '.name')
        local value=$(echo "$metric" | jq -r '.value')
        local unit=$(echo "$metric" | jq -r '.unit')
        local timestamp=$(echo "$metric" | jq -r '.timestamp')
        
        # Convert timestamp to ISO format
        local iso_timestamp=$(date -u -d "@$timestamp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                            date -u -r "$timestamp" +%Y-%m-%dT%H:%M:%SZ)
        
        # Put metric to CloudWatch
        put_custom_metric "$namespace" "$name" "$value" "$unit"
    done < <(echo "$metrics" | jq -c '.[]')
    
    log_info "Metrics exported to CloudWatch" "PERF_METRICS"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup performance metrics
cleanup_performance_metrics() {
    log_info "Cleaning up performance metrics" "PERF_METRICS"
    
    # Stop collector if running
    if [[ -f "/tmp/perf_metrics_collector_$$.pid" ]]; then
        local collector_pid=$(cat "/tmp/perf_metrics_collector_$$.pid")
        kill "$collector_pid" 2>/dev/null || true
        rm -f "/tmp/perf_metrics_collector_$$.pid"
        rm -f "/tmp/perf_metrics_collector_$$.sh"
        rm -f "/tmp/perf_metrics_collector_$$.log"
    fi
    
    # Clear metrics
    METRIC_COLLECTORS=()
    METRIC_TIMESERIES=()
    
    # Remove temporary files
    rm -f "$PERF_METRICS_STORAGE_FILE"
    rm -f "$PERF_METRICS_AGGREGATION_FILE"
    
    log_info "Performance metrics cleanup complete" "PERF_METRICS"
}