#!/bin/bash
# =============================================================================
# Application Health Monitor Module
# Provides comprehensive health checking, performance monitoring,
# log aggregation, and alerting for AI application stack
# =============================================================================

# Prevent multiple sourcing
[ -n "${_HEALTH_MONITOR_SH_LOADED:-}" ] && return 0
_HEALTH_MONITOR_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../config/variables.sh"

# =============================================================================
# HEALTH CHECK SYSTEM
# =============================================================================

# Comprehensive health check for all services
check_application_health() {
    local output_format="${1:-text}"  # text, json, prometheus
    local include_details="${2:-true}"
    local timeout="${3:-30}"
    
    with_error_context "check_application_health" \
        _check_application_health_impl "$output_format" "$include_details" "$timeout"
}

_check_application_health_impl() {
    local output_format="$1"
    local include_details="$2"
    local timeout="$3"
    
    echo "Performing comprehensive application health check..." >&2
    
    # Initialize health data structure
    local health_data
    health_data=$(initialize_health_data)
    
    # Check each service
    health_data=$(check_service_health "$health_data" "postgres" "5432" "/healthz" "$timeout")
    health_data=$(check_service_health "$health_data" "n8n" "5678" "/healthz" "$timeout")
    health_data=$(check_service_health "$health_data" "ollama" "11434" "/api/tags" "$timeout")
    health_data=$(check_service_health "$health_data" "qdrant" "6333" "/healthz" "$timeout")
    health_data=$(check_service_health "$health_data" "crawl4ai" "11235" "/health" "$timeout")
    
    # Check system resources
    health_data=$(check_system_resources "$health_data")
    
    # Check GPU resources if available
    if has_gpu; then
        health_data=$(check_gpu_resources "$health_data")
    fi
    
    # Check application metrics
    if [ "$include_details" = "true" ]; then
        health_data=$(check_application_metrics "$health_data")
    fi
    
    # Calculate overall health status
    health_data=$(calculate_overall_health "$health_data")
    
    # Output in requested format
    output_health_report "$health_data" "$output_format"
}

# Initialize health data structure
initialize_health_data() {
    cat << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "overall_status": "unknown",
    "services": {},
    "system": {},
    "gpu": {},
    "metrics": {},
    "alerts": []
}
EOF
}

# Check individual service health
check_service_health() {
    local health_data="$1"
    local service_name="$2"
    local port="$3"
    local health_endpoint="$4"
    local timeout="$5"
    
    local service_status="unknown"
    local response_time=0
    local error_message=""
    local details="{}"
    
    # Check if service is accessible
    local start_time
    start_time=$(date +%s.%N)
    
    if nc -z "localhost" "$port" 2>/dev/null; then
        # Service port is open, check health endpoint
        local health_url="http://localhost:${port}${health_endpoint}"
        local response
        
        if response=$(timeout "$timeout" curl -f -s "$health_url" 2>&1); then
            service_status="healthy"
            
            # Calculate response time
            local end_time
            end_time=$(date +%s.%N)
            response_time=$(echo "$end_time - $start_time" | bc)
            
            # Get service-specific details
            details=$(get_service_details "$service_name" "$port")
        else
            service_status="unhealthy"
            error_message="Health endpoint failed: $response"
        fi
    else
        service_status="down"
        error_message="Service port $port not accessible"
    fi
    
    # Update health data
    echo "$health_data" | jq --arg service "$service_name" \
        --arg status "$service_status" \
        --argjson response_time "$response_time" \
        --arg error "$error_message" \
        --argjson details "$details" \
        '.services[$service] = {
            "status": $status,
            "response_time_ms": ($response_time * 1000 | floor),
            "error": $error,
            "details": $details,
            "last_checked": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Get service-specific details
get_service_details() {
    local service_name="$1"
    local port="$2"
    
    case "$service_name" in
        "postgres")
            get_postgres_details "$port"
            ;;
        "n8n")
            get_n8n_details "$port"
            ;;
        "ollama")
            get_ollama_details "$port"
            ;;
        "qdrant")
            get_qdrant_details "$port"
            ;;
        "crawl4ai")
            get_crawl4ai_details "$port"
            ;;
        *)
            echo "{}"
            ;;
    esac
}

# Get PostgreSQL details
get_postgres_details() {
    local port="$1"
    
    # Try to get database info
    local db_info="{}"
    
    if command -v psql >/dev/null 2>&1; then
        local connections
        connections=$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h localhost -p "$port" -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
        
        local db_size
        db_size=$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h localhost -p "$port" -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-n8n}'));" 2>/dev/null | xargs || echo "unknown")
        
        db_info=$(cat << EOF
{
    "active_connections": $connections,
    "database_size": "$db_size",
    "version": "16.1"
}
EOF
)
    fi
    
    echo "$db_info"
}

# Get n8n details
get_n8n_details() {
    local port="$1"
    
    local n8n_info="{}"
    
    # Try to get n8n metrics
    if workflows=$(curl -s "http://localhost:${port}/api/v1/workflows" 2>/dev/null | jq length 2>/dev/null); then
        n8n_info=$(cat << EOF
{
    "workflow_count": $workflows,
    "api_version": "v1"
}
EOF
)
    fi
    
    echo "$n8n_info"
}

# Get Ollama details
get_ollama_details() {
    local port="$1"
    
    local ollama_info="{}"
    
    # Get available models
    if models=$(curl -s "http://localhost:${port}/api/tags" 2>/dev/null | jq -c '.models' 2>/dev/null); then
        local model_count
        model_count=$(echo "$models" | jq length 2>/dev/null || echo "0")
        
        ollama_info=$(cat << EOF
{
    "model_count": $model_count,
    "models": $models
}
EOF
)
    fi
    
    echo "$ollama_info"
}

# Get Qdrant details
get_qdrant_details() {
    local port="$1"
    
    local qdrant_info="{}"
    
    # Get collection info
    if collections=$(curl -s "http://localhost:${port}/collections" 2>/dev/null | jq -c '.result.collections' 2>/dev/null); then
        local collection_count
        collection_count=$(echo "$collections" | jq length 2>/dev/null || echo "0")
        
        qdrant_info=$(cat << EOF
{
    "collection_count": $collection_count,
    "collections": $collections
}
EOF
)
    fi
    
    echo "$qdrant_info"
}

# Get Crawl4AI details
get_crawl4ai_details() {
    local port="$1"
    
    local crawl4ai_info="{}"
    
    # Try to get status info
    if status=$(curl -s "http://localhost:${port}/status" 2>/dev/null | jq -c '.' 2>/dev/null); then
        crawl4ai_info="$status"
    else
        crawl4ai_info='{"status": "running"}'
    fi
    
    echo "$crawl4ai_info"
}

# Check system resources
check_system_resources() {
    local health_data="$1"
    
    # Get CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | head -1)
    
    # Get memory usage
    local memory_info
    memory_info=$(free | grep Mem)
    local memory_total memory_used memory_available
    memory_total=$(echo "$memory_info" | awk '{print $2}')
    memory_used=$(echo "$memory_info" | awk '{print $3}')
    memory_available=$(echo "$memory_info" | awk '{print $7}')
    local memory_usage_percent
    memory_usage_percent=$(echo "scale=1; $memory_used * 100 / $memory_total" | bc)
    
    # Get disk usage
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
    
    # Get load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    # Determine system health status
    local system_status="healthy"
    local warnings=()
    
    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        system_status="warning"
        warnings+=("High CPU usage: ${cpu_usage}%")
    fi
    
    if (( $(echo "$memory_usage_percent > 90" | bc -l) )); then
        system_status="warning"
        warnings+=("High memory usage: ${memory_usage_percent}%")
    fi
    
    if (( disk_usage > 90 )); then
        system_status="critical"
        warnings+=("High disk usage: ${disk_usage}%")
    fi
    
    # Update health data
    echo "$health_data" | jq --arg status "$system_status" \
        --argjson cpu "$cpu_usage" \
        --argjson memory_percent "$memory_usage_percent" \
        --argjson memory_total "$memory_total" \
        --argjson memory_used "$memory_used" \
        --argjson memory_available "$memory_available" \
        --argjson disk_usage "$disk_usage" \
        --argjson load_avg "$load_avg" \
        --argjson warnings "$(printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .)" \
        '.system = {
            "status": $status,
            "cpu_usage_percent": $cpu,
            "memory": {
                "usage_percent": $memory_percent,
                "total_kb": $memory_total,
                "used_kb": $memory_used,
                "available_kb": $memory_available
            },
            "disk_usage_percent": $disk_usage,
            "load_average": $load_avg,
            "warnings": $warnings
        }'
}

# Check GPU resources
check_gpu_resources() {
    local health_data="$1"
    
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "$health_data" | jq '.gpu = {"status": "not_available", "message": "nvidia-smi not found"}'
        return
    fi
    
    # Get GPU metrics
    local gpu_data
    gpu_data=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit --format=csv,noheader,nounits 2>/dev/null)
    
    if [ -z "$gpu_data" ]; then
        echo "$health_data" | jq '.gpu = {"status": "error", "message": "Failed to get GPU metrics"}'
        return
    fi
    
    # Parse GPU data
    local gpu_util memory_used memory_total temp power_draw power_limit
    IFS=',' read -r gpu_util memory_used memory_total temp power_draw power_limit <<< "$gpu_data"
    
    # Remove extra spaces
    gpu_util=$(echo "$gpu_util" | xargs)
    memory_used=$(echo "$memory_used" | xargs)
    memory_total=$(echo "$memory_total" | xargs)
    temp=$(echo "$temp" | xargs)
    power_draw=$(echo "$power_draw" | xargs)
    power_limit=$(echo "$power_limit" | xargs)
    
    # Calculate memory usage percentage
    local memory_usage_percent
    memory_usage_percent=$(echo "scale=1; $memory_used * 100 / $memory_total" | bc)
    
    # Determine GPU health status
    local gpu_status="healthy"
    local gpu_warnings=()
    
    if (( $(echo "$temp > 85" | bc -l) )); then
        gpu_status="warning"
        gpu_warnings+=("High GPU temperature: ${temp}°C")
    fi
    
    if (( $(echo "$memory_usage_percent > 95" | bc -l) )); then
        gpu_status="warning"
        gpu_warnings+=("High GPU memory usage: ${memory_usage_percent}%")
    fi
    
    if (( $(echo "$power_draw > $power_limit * 0.95" | bc -l) )); then
        gpu_status="warning"
        gpu_warnings+=("High power usage: ${power_draw}W/${power_limit}W")
    fi
    
    # Update health data
    echo "$health_data" | jq --arg status "$gpu_status" \
        --argjson util "$gpu_util" \
        --argjson mem_used "$memory_used" \
        --argjson mem_total "$memory_total" \
        --argjson mem_percent "$memory_usage_percent" \
        --argjson temp "$temp" \
        --argjson power "$power_draw" \
        --argjson power_limit "$power_limit" \
        --argjson warnings "$(printf '%s\n' "${gpu_warnings[@]}" | jq -R . | jq -s .)" \
        '.gpu = {
            "status": $status,
            "utilization_percent": $util,
            "memory": {
                "used_mb": $mem_used,
                "total_mb": $mem_total,
                "usage_percent": $mem_percent
            },
            "temperature_c": $temp,
            "power": {
                "draw_w": $power,
                "limit_w": $power_limit
            },
            "warnings": $warnings
        }'
}

# Check application metrics
check_application_metrics() {
    local health_data="$1"
    
    # Get Docker container stats
    local container_stats
    container_stats=$(get_container_stats)
    
    # Get AI model performance
    local model_performance
    model_performance=$(get_model_performance)
    
    # Get database performance
    local db_performance
    db_performance=$(get_database_performance)
    
    # Update health data
    echo "$health_data" | jq --argjson containers "$container_stats" \
        --argjson models "$model_performance" \
        --argjson database "$db_performance" \
        '.metrics = {
            "containers": $containers,
            "ai_models": $models,
            "database": $database,
            "collected_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Get Docker container statistics
get_container_stats() {
    local stats="{}"
    
    if command -v docker >/dev/null 2>&1; then
        # Get container resource usage
        local container_data
        container_data=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | tail -n +2)
        
        if [ -n "$container_data" ]; then
            local containers_json="[]"
            
            while IFS=$'\t' read -r container cpu_perc mem_usage mem_perc net_io block_io; do
                if [ -n "$container" ]; then
                    local container_obj
                    container_obj=$(cat << EOF
{
    "name": "$container",
    "cpu_percent": "$(echo "$cpu_perc" | sed 's/%//')",
    "memory_usage": "$mem_usage",
    "memory_percent": "$(echo "$mem_perc" | sed 's/%//')",
    "network_io": "$net_io",
    "block_io": "$block_io"
}
EOF
)
                    containers_json=$(echo "$containers_json" | jq ". += [$container_obj]")
                fi
            done <<< "$container_data"
            
            stats=$(cat << EOF
{
    "containers": $containers_json,
    "total_containers": $(echo "$containers_json" | jq length)
}
EOF
)
        fi
    fi
    
    echo "$stats"
}

# Get AI model performance metrics
get_model_performance() {
    local performance="{}"
    
    # Test model response times
    if curl -f -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        local models
        models=$(curl -s http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null || echo "")
        
        if [ -n "$models" ]; then
            local model_metrics="[]"
            
            # Test first 3 models to avoid excessive testing
            echo "$models" | head -3 | while read -r model; do
                if [ -n "$model" ]; then
                    local start_time end_time response_time
                    start_time=$(date +%s.%N)
                    
                    if curl -s -X POST http://localhost:11434/api/generate \
                        -H "Content-Type: application/json" \
                        -d "{\"model\": \"$model\", \"prompt\": \"test\", \"stream\": false}" \
                        >/dev/null 2>&1; then
                        
                        end_time=$(date +%s.%N)
                        response_time=$(echo "$end_time - $start_time" | bc)
                        
                        local model_metric
                        model_metric=$(cat << EOF
{
    "model": "$model",
    "response_time_ms": $(echo "$response_time * 1000" | bc | cut -d. -f1),
    "status": "healthy"
}
EOF
)
                        model_metrics=$(echo "$model_metrics" | jq ". += [$model_metric]")
                    fi
                fi
            done
            
            performance=$(cat << EOF
{
    "model_tests": $model_metrics,
    "total_models": $(echo "$models" | wc -l)
}
EOF
)
        fi
    fi
    
    echo "$performance"
}

# Get database performance metrics
get_database_performance() {
    local performance="{}"
    
    if command -v psql >/dev/null 2>&1 && [ -n "${POSTGRES_PASSWORD:-}" ]; then
        # Get database statistics
        local query="SELECT count(*) as connections FROM pg_stat_activity;"
        local connections
        connections=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "$query" 2>/dev/null | xargs || echo "0")
        
        performance=$(cat << EOF
{
    "active_connections": $connections,
    "max_connections": 200
}
EOF
)
    fi
    
    echo "$performance"
}

# Calculate overall health status
calculate_overall_health() {
    local health_data="$1"
    
    # Extract service statuses
    local service_statuses
    service_statuses=$(echo "$health_data" | jq -r '.services | to_entries[] | .value.status' 2>/dev/null)
    
    # Extract system status
    local system_status
    system_status=$(echo "$health_data" | jq -r '.system.status // "unknown"' 2>/dev/null)
    
    # Extract GPU status
    local gpu_status
    gpu_status=$(echo "$health_data" | jq -r '.gpu.status // "not_available"' 2>/dev/null)
    
    # Determine overall status
    local overall_status="healthy"
    local critical_issues=()
    local warnings=()
    
    # Check service statuses
    while read -r status; do
        case "$status" in
            "down"|"critical")
                overall_status="critical"
                critical_issues+=("Service is down or critical")
                ;;
            "unhealthy"|"degraded")
                if [ "$overall_status" != "critical" ]; then
                    overall_status="warning"
                fi
                warnings+=("Service is unhealthy")
                ;;
        esac
    done <<< "$service_statuses"
    
    # Check system status
    if [ "$system_status" = "critical" ]; then
        overall_status="critical"
        critical_issues+=("System resources critical")
    elif [ "$system_status" = "warning" ] && [ "$overall_status" != "critical" ]; then
        overall_status="warning"
        warnings+=("System resources under pressure")
    fi
    
    # Check GPU status
    if [ "$gpu_status" = "warning" ] && [ "$overall_status" != "critical" ]; then
        overall_status="warning"
        warnings+=("GPU resources under pressure")
    fi
    
    # Compile alerts
    local all_alerts=()
    all_alerts+=("${critical_issues[@]}")
    all_alerts+=("${warnings[@]}")
    
    # Update health data
    echo "$health_data" | jq --arg status "$overall_status" \
        --argjson alerts "$(printf '%s\n' "${all_alerts[@]}" | jq -R . | jq -s .)" \
        '.overall_status = $status | .alerts = $alerts'
}

# Output health report in specified format
output_health_report() {
    local health_data="$1"
    local format="$2"
    
    case "$format" in
        "json")
            echo "$health_data" | jq .
            ;;
        "prometheus")
            output_prometheus_metrics "$health_data"
            ;;
        "summary")
            output_health_summary "$health_data"
            ;;
        *)
            output_health_text "$health_data"
            ;;
    esac
}

# Output health report in text format
output_health_text() {
    local health_data="$1"
    
    local overall_status
    overall_status=$(echo "$health_data" | jq -r '.overall_status')
    
    local timestamp
    timestamp=$(echo "$health_data" | jq -r '.timestamp')
    
    echo "=== Application Health Report ==="
    echo "Timestamp: $timestamp"
    echo "Overall Status: $overall_status"
    echo ""
    
    # Services status
    echo "Services:"
    echo "$health_data" | jq -r '.services | to_entries[] | "  \(.key): \(.value.status) (\(.value.response_time_ms)ms)"'
    echo ""
    
    # System resources
    echo "System Resources:"
    local cpu_usage memory_usage disk_usage
    cpu_usage=$(echo "$health_data" | jq -r '.system.cpu_usage_percent // "N/A"')
    memory_usage=$(echo "$health_data" | jq -r '.system.memory.usage_percent // "N/A"')
    disk_usage=$(echo "$health_data" | jq -r '.system.disk_usage_percent // "N/A"')
    
    echo "  CPU: ${cpu_usage}%"
    echo "  Memory: ${memory_usage}%"
    echo "  Disk: ${disk_usage}%"
    echo ""
    
    # GPU resources
    if echo "$health_data" | jq -e '.gpu.status' >/dev/null 2>&1; then
        echo "GPU Resources:"
        local gpu_util gpu_mem_usage gpu_temp
        gpu_util=$(echo "$health_data" | jq -r '.gpu.utilization_percent // "N/A"')
        gpu_mem_usage=$(echo "$health_data" | jq -r '.gpu.memory.usage_percent // "N/A"')
        gpu_temp=$(echo "$health_data" | jq -r '.gpu.temperature_c // "N/A"')
        
        echo "  Utilization: ${gpu_util}%"
        echo "  Memory: ${gpu_mem_usage}%"
        echo "  Temperature: ${gpu_temp}°C"
        echo ""
    fi
    
    # Alerts
    local alerts
    alerts=$(echo "$health_data" | jq -r '.alerts[]?' 2>/dev/null)
    if [ -n "$alerts" ]; then
        echo "Alerts:"
        echo "$alerts" | sed 's/^/  - /'
        echo ""
    fi
}

# Output health summary
output_health_summary() {
    local health_data="$1"
    
    local overall_status
    overall_status=$(echo "$health_data" | jq -r '.overall_status')
    
    local healthy_services unhealthy_services
    healthy_services=$(echo "$health_data" | jq -r '[.services | to_entries[] | select(.value.status == "healthy")] | length')
    unhealthy_services=$(echo "$health_data" | jq -r '[.services | to_entries[] | select(.value.status != "healthy")] | length')
    
    local cpu_usage memory_usage
    cpu_usage=$(echo "$health_data" | jq -r '.system.cpu_usage_percent // 0')
    memory_usage=$(echo "$health_data" | jq -r '.system.memory.usage_percent // 0')
    
    echo "Status: $overall_status | Services: ${healthy_services}/${$((healthy_services + unhealthy_services))} healthy | CPU: ${cpu_usage}% | Memory: ${memory_usage}%"
}

# Output Prometheus metrics
output_prometheus_metrics() {
    local health_data="$1"
    
    echo "# HELP application_health_status Overall application health status (1=healthy, 0.5=warning, 0=critical)"
    echo "# TYPE application_health_status gauge"
    
    local overall_status
    overall_status=$(echo "$health_data" | jq -r '.overall_status')
    
    local status_value
    case "$overall_status" in
        "healthy") status_value=1 ;;
        "warning") status_value=0.5 ;;
        *) status_value=0 ;;
    esac
    
    echo "application_health_status $status_value"
    echo ""
    
    # Service metrics
    echo "# HELP service_health_status Service health status (1=healthy, 0=unhealthy)"
    echo "# TYPE service_health_status gauge"
    
    echo "$health_data" | jq -r '.services | to_entries[] | "service_health_status{service=\"\(.key)\"} \(if .value.status == "healthy" then 1 else 0 end)"'
    echo ""
    
    # System metrics
    if echo "$health_data" | jq -e '.system' >/dev/null 2>&1; then
        echo "# HELP system_cpu_usage_percent CPU usage percentage"
        echo "# TYPE system_cpu_usage_percent gauge"
        echo "system_cpu_usage_percent $(echo "$health_data" | jq -r '.system.cpu_usage_percent // 0')"
        echo ""
        
        echo "# HELP system_memory_usage_percent Memory usage percentage"
        echo "# TYPE system_memory_usage_percent gauge"
        echo "system_memory_usage_percent $(echo "$health_data" | jq -r '.system.memory.usage_percent // 0')"
        echo ""
        
        echo "# HELP system_disk_usage_percent Disk usage percentage"
        echo "# TYPE system_disk_usage_percent gauge"
        echo "system_disk_usage_percent $(echo "$health_data" | jq -r '.system.disk_usage_percent // 0')"
        echo ""
    fi
    
    # GPU metrics
    if echo "$health_data" | jq -e '.gpu.utilization_percent' >/dev/null 2>&1; then
        echo "# HELP gpu_utilization_percent GPU utilization percentage"
        echo "# TYPE gpu_utilization_percent gauge"
        echo "gpu_utilization_percent $(echo "$health_data" | jq -r '.gpu.utilization_percent')"
        echo ""
        
        echo "# HELP gpu_memory_usage_percent GPU memory usage percentage"
        echo "# TYPE gpu_memory_usage_percent gauge"
        echo "gpu_memory_usage_percent $(echo "$health_data" | jq -r '.gpu.memory.usage_percent')"
        echo ""
        
        echo "# HELP gpu_temperature_celsius GPU temperature in Celsius"
        echo "# TYPE gpu_temperature_celsius gauge"
        echo "gpu_temperature_celsius $(echo "$health_data" | jq -r '.gpu.temperature_c')"
        echo ""
    fi
}

# =============================================================================
# PERFORMANCE MONITORING
# =============================================================================

# Start continuous performance monitoring
start_performance_monitoring() {
    local interval="${1:-60}"  # seconds
    local output_dir="${2:-/shared/monitoring}"
    local enable_gpu="${3:-true}"
    
    with_error_context "start_performance_monitoring" \
        _start_performance_monitoring_impl "$interval" "$output_dir" "$enable_gpu"
}

_start_performance_monitoring_impl() {
    local interval="$1"
    local output_dir="$2"
    local enable_gpu="$3"
    
    echo "Starting performance monitoring (interval: ${interval}s)..." >&2
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Create monitoring script
    cat > "$output_dir/performance-monitor.sh" << EOF
#!/bin/bash
# Performance monitoring daemon

set -euo pipefail

INTERVAL=$interval
OUTPUT_DIR="$output_dir"
ENABLE_GPU="$enable_gpu"

# Create data files
METRICS_FILE="\$OUTPUT_DIR/metrics.jsonl"
ALERTS_FILE="\$OUTPUT_DIR/alerts.log"

echo "Starting performance monitoring at \$(date)" >> "\$ALERTS_FILE"

while true; do
    # Collect metrics
    TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # System metrics
    CPU_USAGE=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1)
    MEMORY_INFO=\$(free | grep Mem)
    MEMORY_TOTAL=\$(echo "\$MEMORY_INFO" | awk '{print \$2}')
    MEMORY_USED=\$(echo "\$MEMORY_INFO" | awk '{print \$3}')
    MEMORY_PERCENT=\$(echo "scale=1; \$MEMORY_USED * 100 / \$MEMORY_TOTAL" | bc)
    DISK_USAGE=\$(df -h / | awk 'NR==2{print \$5}' | sed 's/%//')
    LOAD_AVG=\$(uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | sed 's/,//')
    
    # GPU metrics
    GPU_METRICS="{}"
    if [ "\$ENABLE_GPU" = "true" ] && command -v nvidia-smi >/dev/null 2>&1; then
        GPU_DATA=\$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "")
        if [ -n "\$GPU_DATA" ]; then
            IFS=',' read -r GPU_UTIL GPU_MEM_USED GPU_MEM_TOTAL GPU_TEMP <<< "\$GPU_DATA"
            GPU_UTIL=\$(echo "\$GPU_UTIL" | xargs)
            GPU_MEM_USED=\$(echo "\$GPU_MEM_USED" | xargs)
            GPU_MEM_TOTAL=\$(echo "\$GPU_MEM_TOTAL" | xargs)
            GPU_TEMP=\$(echo "\$GPU_TEMP" | xargs)
            GPU_MEM_PERCENT=\$(echo "scale=1; \$GPU_MEM_USED * 100 / \$GPU_MEM_TOTAL" | bc)
            
            GPU_METRICS=\$(cat << EOJ
{
    "utilization": \$GPU_UTIL,
    "memory_used_mb": \$GPU_MEM_USED,
    "memory_total_mb": \$GPU_MEM_TOTAL,
    "memory_percent": \$GPU_MEM_PERCENT,
    "temperature_c": \$GPU_TEMP
}
EOJ
)
        fi
    fi
    
    # Create metrics record
    METRICS_RECORD=\$(cat << EOJ
{
    "timestamp": "\$TIMESTAMP",
    "system": {
        "cpu_percent": \$CPU_USAGE,
        "memory_percent": \$MEMORY_PERCENT,
        "disk_percent": \$DISK_USAGE,
        "load_average": \$LOAD_AVG
    },
    "gpu": \$GPU_METRICS
}
EOJ
)
    
    # Write metrics
    echo "\$METRICS_RECORD" >> "\$METRICS_FILE"
    
    # Check for alerts
    if (( \$(echo "\$CPU_USAGE > 90" | bc -l) )); then
        echo "\$TIMESTAMP ALERT: High CPU usage: \${CPU_USAGE}%" >> "\$ALERTS_FILE"
    fi
    
    if (( \$(echo "\$MEMORY_PERCENT > 90" | bc -l) )); then
        echo "\$TIMESTAMP ALERT: High memory usage: \${MEMORY_PERCENT}%" >> "\$ALERTS_FILE"
    fi
    
    if (( \$DISK_USAGE > 90 )); then
        echo "\$TIMESTAMP ALERT: High disk usage: \${DISK_USAGE}%" >> "\$ALERTS_FILE"
    fi
    
    # GPU alerts
    if [ "\$ENABLE_GPU" = "true" ] && [ -n "\$GPU_TEMP" ]; then
        if (( \$(echo "\$GPU_TEMP > 85" | bc -l) )); then
            echo "\$TIMESTAMP ALERT: High GPU temperature: \${GPU_TEMP}°C" >> "\$ALERTS_FILE"
        fi
    fi
    
    # Clean up old metrics (keep last 1000 entries)
    if [ \$(wc -l < "\$METRICS_FILE") -gt 1000 ]; then
        tail -n 1000 "\$METRICS_FILE" > "\$METRICS_FILE.tmp"
        mv "\$METRICS_FILE.tmp" "\$METRICS_FILE"
    fi
    
    sleep \$INTERVAL
done
EOF
    
    chmod +x "$output_dir/performance-monitor.sh"
    
    # Start monitoring in background
    nohup "$output_dir/performance-monitor.sh" > "$output_dir/monitor.log" 2>&1 &
    local monitor_pid=$!
    
    echo "$monitor_pid" > "$output_dir/monitor.pid"
    echo "Performance monitoring started (PID: $monitor_pid)" >&2
    
    # Register cleanup handler
    register_cleanup_handler "stop_performance_monitoring '$output_dir'"
}

# Stop performance monitoring
stop_performance_monitoring() {
    local output_dir="${1:-/shared/monitoring}"
    
    if [ -f "$output_dir/monitor.pid" ]; then
        local pid
        pid=$(cat "$output_dir/monitor.pid")
        
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "Performance monitoring stopped (PID: $pid)" >&2
        fi
        
        rm -f "$output_dir/monitor.pid"
    fi
}

# Generate performance report
generate_performance_report() {
    local output_dir="${1:-/shared/monitoring}"
    local time_range="${2:-1h}"  # 1h, 6h, 24h
    local format="${3:-text}"
    
    with_error_context "generate_performance_report" \
        _generate_performance_report_impl "$output_dir" "$time_range" "$format"
}

_generate_performance_report_impl() {
    local output_dir="$1"
    local time_range="$2"
    local format="$3"
    
    local metrics_file="$output_dir/metrics.jsonl"
    
    if [ ! -f "$metrics_file" ]; then
        echo "No metrics data found at $metrics_file" >&2
        return 1
    fi
    
    echo "Generating performance report for last $time_range..." >&2
    
    # Calculate time threshold
    local hours
    case "$time_range" in
        "1h") hours=1 ;;
        "6h") hours=6 ;;
        "24h") hours=24 ;;
        *) hours=1 ;;
    esac
    
    local threshold_time
    threshold_time=$(date -u -d "$hours hours ago" +%Y-%m-%dT%H:%M:%SZ)
    
    # Filter metrics by time range
    local filtered_metrics
    filtered_metrics=$(awk -v threshold="$threshold_time" '
        {
            if (match($0, /"timestamp": "([^"]*)"/, arr)) {
                if (arr[1] >= threshold) {
                    print $0
                }
            }
        }
    ' "$metrics_file")
    
    if [ -z "$filtered_metrics" ]; then
        echo "No metrics found for the specified time range" >&2
        return 1
    fi
    
    # Calculate statistics
    local stats
    stats=$(echo "$filtered_metrics" | jq -s '
        {
            "time_range": "'"$time_range"'",
            "sample_count": length,
            "cpu": {
                "avg": (map(.system.cpu_percent) | add / length),
                "max": (map(.system.cpu_percent) | max),
                "min": (map(.system.cpu_percent) | min)
            },
            "memory": {
                "avg": (map(.system.memory_percent) | add / length),
                "max": (map(.system.memory_percent) | max),
                "min": (map(.system.memory_percent) | min)
            },
            "disk": {
                "avg": (map(.system.disk_percent) | add / length),
                "max": (map(.system.disk_percent) | max),
                "min": (map(.system.disk_percent) | min)
            }
        } +
        if (.[0].gpu and (.[0].gpu | keys | length > 0)) then
        {
            "gpu": {
                "utilization": {
                    "avg": (map(.gpu.utilization // 0) | add / length),
                    "max": (map(.gpu.utilization // 0) | max),
                    "min": (map(.gpu.utilization // 0) | min)
                },
                "memory": {
                    "avg": (map(.gpu.memory_percent // 0) | add / length),
                    "max": (map(.gpu.memory_percent // 0) | max),
                    "min": (map(.gpu.memory_percent // 0) | min)
                },
                "temperature": {
                    "avg": (map(.gpu.temperature_c // 0) | add / length),
                    "max": (map(.gpu.temperature_c // 0) | max),
                    "min": (map(.gpu.temperature_c // 0) | min)
                }
            }
        }
        else {} end
    ')
    
    # Output report in requested format
    case "$format" in
        "json")
            echo "$stats" | jq .
            ;;
        *)
            output_performance_text_report "$stats"
            ;;
    esac
}

# Output performance report in text format
output_performance_text_report() {
    local stats="$1"
    
    local time_range sample_count
    time_range=$(echo "$stats" | jq -r '.time_range')
    sample_count=$(echo "$stats" | jq -r '.sample_count')
    
    echo "=== Performance Report (Last $time_range) ==="
    echo "Samples: $sample_count"
    echo ""
    
    echo "CPU Usage:"
    echo "  Average: $(echo "$stats" | jq -r '.cpu.avg | round')%"
    echo "  Maximum: $(echo "$stats" | jq -r '.cpu.max')%"
    echo "  Minimum: $(echo "$stats" | jq -r '.cpu.min')%"
    echo ""
    
    echo "Memory Usage:"
    echo "  Average: $(echo "$stats" | jq -r '.memory.avg | round')%"
    echo "  Maximum: $(echo "$stats" | jq -r '.memory.max')%"
    echo "  Minimum: $(echo "$stats" | jq -r '.memory.min')%"
    echo ""
    
    echo "Disk Usage:"
    echo "  Average: $(echo "$stats" | jq -r '.disk.avg | round')%"
    echo "  Maximum: $(echo "$stats" | jq -r '.disk.max')%"
    echo "  Minimum: $(echo "$stats" | jq -r '.disk.min')%"
    echo ""
    
    # GPU metrics if available
    if echo "$stats" | jq -e '.gpu' >/dev/null 2>&1; then
        echo "GPU Utilization:"
        echo "  Average: $(echo "$stats" | jq -r '.gpu.utilization.avg | round')%"
        echo "  Maximum: $(echo "$stats" | jq -r '.gpu.utilization.max')%"
        echo "  Minimum: $(echo "$stats" | jq -r '.gpu.utilization.min')%"
        echo ""
        
        echo "GPU Memory:"
        echo "  Average: $(echo "$stats" | jq -r '.gpu.memory.avg | round')%"
        echo "  Maximum: $(echo "$stats" | jq -r '.gpu.memory.max')%"
        echo "  Minimum: $(echo "$stats" | jq -r '.gpu.memory.min')%"
        echo ""
        
        echo "GPU Temperature:"
        echo "  Average: $(echo "$stats" | jq -r '.gpu.temperature.avg | round')°C"
        echo "  Maximum: $(echo "$stats" | jq -r '.gpu.temperature.max')°C"
        echo "  Minimum: $(echo "$stats" | jq -r '.gpu.temperature.min')°C"
        echo ""
    fi
}

# =============================================================================
# LOG AGGREGATION
# =============================================================================

# Setup centralized log aggregation
setup_log_aggregation() {
    local log_dir="${1:-/shared/logs}"
    local retention_days="${2:-7}"
    local enable_rotation="${3:-true}"
    
    with_error_context "setup_log_aggregation" \
        _setup_log_aggregation_impl "$log_dir" "$retention_days" "$enable_rotation"
}

_setup_log_aggregation_impl() {
    local log_dir="$1"
    local retention_days="$2"
    local enable_rotation="$3"
    
    echo "Setting up log aggregation..." >&2
    
    # Create log directory structure
    mkdir -p "$log_dir"/{application,system,docker,errors}
    
    # Create log collection script
    create_log_collector "$log_dir" "$enable_rotation"
    
    # Setup log rotation
    if [ "$enable_rotation" = "true" ]; then
        setup_log_rotation "$log_dir" "$retention_days"
    fi
    
    # Create log analysis tools
    create_log_analysis_tools "$log_dir"
    
    echo "Log aggregation setup completed" >&2
}

# Create log collector script
create_log_collector() {
    local log_dir="$1"
    local enable_rotation="$2"
    
    cat > "$log_dir/collect-logs.sh" << EOF
#!/bin/bash
# Log collection script

set -euo pipefail

LOG_DIR="$log_dir"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)

# Collect Docker logs
echo "Collecting Docker container logs..."
for container in \$(docker ps --format "{{.Names}}" 2>/dev/null || echo ""); do
    if [ -n "\$container" ]; then
        docker logs --tail=1000 "\$container" > "\$LOG_DIR/docker/\${container}_\${TIMESTAMP}.log" 2>&1 || true
    fi
done

# Collect system logs
echo "Collecting system logs..."
if [ -f /var/log/syslog ]; then
    tail -n 1000 /var/log/syslog > "\$LOG_DIR/system/syslog_\${TIMESTAMP}.log" 2>/dev/null || true
fi

if [ -f /var/log/kern.log ]; then
    tail -n 1000 /var/log/kern.log > "\$LOG_DIR/system/kern_\${TIMESTAMP}.log" 2>/dev/null || true
fi

# Collect application-specific logs
echo "Collecting application logs..."

# n8n logs
if docker ps --format "{{.Names}}" | grep -q "n8n"; then
    docker exec n8n-ai find /home/node/.n8n/logs -name "*.log" -exec cat {} \; > "\$LOG_DIR/application/n8n_\${TIMESTAMP}.log" 2>/dev/null || true
fi

# GPU logs
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -q > "\$LOG_DIR/system/gpu_info_\${TIMESTAMP}.log" 2>/dev/null || true
fi

echo "Log collection completed: \$TIMESTAMP"
EOF
    
    chmod +x "$log_dir/collect-logs.sh"
}

# Setup log rotation
setup_log_rotation() {
    local log_dir="$1"
    local retention_days="$2"
    
    cat > "$log_dir/rotate-logs.sh" << EOF
#!/bin/bash
# Log rotation script

set -euo pipefail

LOG_DIR="$log_dir"
RETENTION_DAYS="$retention_days"

echo "Starting log rotation (retention: \$RETENTION_DAYS days)..."

# Clean up old logs
find "\$LOG_DIR" -name "*.log" -type f -mtime +\$RETENTION_DAYS -delete 2>/dev/null || true

# Compress logs older than 1 day
find "\$LOG_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

echo "Log rotation completed"
EOF
    
    chmod +x "$log_dir/rotate-logs.sh"
    
    # Create cron job for log rotation
    echo "0 2 * * * $log_dir/rotate-logs.sh" > "$log_dir/logrotate.cron"
}

# Create log analysis tools
create_log_analysis_tools() {
    local log_dir="$1"
    
    # Error analyzer
    cat > "$log_dir/analyze-errors.sh" << 'EOF'
#!/bin/bash
# Error log analyzer

set -euo pipefail

LOG_DIR="${1:-/shared/logs}"

echo "=== Error Log Analysis ==="
echo "Timestamp: $(date)"
echo ""

# Analyze Docker logs for errors
echo "Docker Container Errors:"
find "$LOG_DIR/docker" -name "*.log" -type f -exec grep -l -i "error\|exception\|fatal\|critical" {} \; | while read -r logfile; do
    container_name=$(basename "$logfile" | cut -d'_' -f1)
    error_count=$(grep -c -i "error\|exception\|fatal\|critical" "$logfile" || echo "0")
    echo "  $container_name: $error_count errors"
    
    # Show recent errors
    if [ "$error_count" -gt 0 ]; then
        echo "    Recent errors:"
        grep -i "error\|exception\|fatal\|critical" "$logfile" | tail -3 | sed 's/^/      /'
    fi
done

echo ""

# Analyze system logs for errors
echo "System Errors:"
find "$LOG_DIR/system" -name "*.log" -type f -exec grep -l -i "error\|failed\|critical" {} \; | while read -r logfile; do
    log_type=$(basename "$logfile" | cut -d'_' -f1)
    error_count=$(grep -c -i "error\|failed\|critical" "$logfile" || echo "0")
    echo "  $log_type: $error_count errors"
done

echo ""

# Analyze application logs
echo "Application Errors:"
find "$LOG_DIR/application" -name "*.log" -type f -exec grep -l -i "error\|exception\|warn" {} \; | while read -r logfile; do
    app_name=$(basename "$logfile" | cut -d'_' -f1)
    error_count=$(grep -c -i "error\|exception\|warn" "$logfile" || echo "0")
    echo "  $app_name: $error_count issues"
done

echo ""
echo "=== Analysis Complete ==="
EOF
    
    chmod +x "$log_dir/analyze-errors.sh"
    
    # Performance log analyzer
    cat > "$log_dir/analyze-performance.sh" << 'EOF'
#!/bin/bash
# Performance log analyzer

set -euo pipefail

LOG_DIR="${1:-/shared/logs}"

echo "=== Performance Log Analysis ==="
echo "Timestamp: $(date)"
echo ""

# Analyze Docker resource usage from logs
echo "Container Resource Issues:"
find "$LOG_DIR/docker" -name "*.log" -type f -exec grep -l -i "memory\|cpu\|disk.*full\|out of memory" {} \; | while read -r logfile; do
    container_name=$(basename "$logfile" | cut -d'_' -f1)
    echo "  $container_name: Resource issues detected"
    
    # Show resource-related messages
    grep -i "memory\|cpu\|disk.*full\|out of memory" "$logfile" | tail -2 | sed 's/^/    /'
done

echo ""

# GPU performance issues
echo "GPU Performance Issues:"
find "$LOG_DIR/system" -name "gpu_*.log" -type f | while read -r logfile; do
    if grep -q "temperature" "$logfile" 2>/dev/null; then
        max_temp=$(grep "GPU Current Temp" "$logfile" | awk '{print $5}' | sort -n | tail -1 || echo "N/A")
        echo "  Max GPU Temperature: $max_temp"
    fi
done

echo ""
echo "=== Performance Analysis Complete ==="
EOF
    
    chmod +x "$log_dir/analyze-performance.sh"
}

# =============================================================================
# ALERTING SYSTEM
# =============================================================================

# Setup alerting system
setup_alerting() {
    local webhook_url="${1:-}"
    local email_address="${2:-}"
    local alert_thresholds="${3:-}"
    
    with_error_context "setup_alerting" \
        _setup_alerting_impl "$webhook_url" "$email_address" "$alert_thresholds"
}

_setup_alerting_impl() {
    local webhook_url="$1"
    local email_address="$2"
    local alert_thresholds="$3"
    
    echo "Setting up alerting system..." >&2
    
    # Create alerts directory
    local alerts_dir="/shared/alerts"
    mkdir -p "$alerts_dir"
    
    # Create alert configuration
    create_alert_config "$alerts_dir" "$webhook_url" "$email_address" "$alert_thresholds"
    
    # Create alerting script
    create_alerting_script "$alerts_dir"
    
    # Setup alert monitoring
    setup_alert_monitoring "$alerts_dir"
    
    echo "Alerting system setup completed" >&2
}

# Create alert configuration
create_alert_config() {
    local alerts_dir="$1"
    local webhook_url="$2"
    local email_address="$3"
    local alert_thresholds="$4"
    
    # Default thresholds if not provided
    if [ -z "$alert_thresholds" ]; then
        alert_thresholds=$(cat << EOF
{
    "cpu_warning": 80,
    "cpu_critical": 95,
    "memory_warning": 85,
    "memory_critical": 95,
    "disk_warning": 85,
    "disk_critical": 95,
    "gpu_temp_warning": 80,
    "gpu_temp_critical": 90,
    "service_down_critical": true
}
EOF
)
    fi
    
    # Create alert configuration
    cat > "$alerts_dir/config.json" << EOF
{
    "notifications": {
        "webhook_url": "$webhook_url",
        "email_address": "$email_address"
    },
    "thresholds": $alert_thresholds,
    "cooldown_minutes": 15,
    "enabled": true
}
EOF
}

# Create alerting script
create_alerting_script() {
    local alerts_dir="$1"
    
    cat > "$alerts_dir/alert-manager.sh" << 'EOF'
#!/bin/bash
# Alert manager script

set -euo pipefail

ALERTS_DIR="${1:-/shared/alerts}"
CONFIG_FILE="$ALERTS_DIR/config.json"
STATE_FILE="$ALERTS_DIR/state.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Alert configuration not found: $CONFIG_FILE"
    exit 1
fi

# Load configuration
WEBHOOK_URL=$(jq -r '.notifications.webhook_url // ""' "$CONFIG_FILE")
EMAIL_ADDRESS=$(jq -r '.notifications.email_address // ""' "$CONFIG_FILE")
COOLDOWN_MINUTES=$(jq -r '.cooldown_minutes // 15' "$CONFIG_FILE")

# Initialize state file
if [ ! -f "$STATE_FILE" ]; then
    echo '{"last_alerts": {}}' > "$STATE_FILE"
fi

# Function to check cooldown
check_cooldown() {
    local alert_key="$1"
    local current_time=$(date +%s)
    local last_alert_time=$(jq -r ".last_alerts[\"$alert_key\"] // 0" "$STATE_FILE")
    local cooldown_seconds=$((COOLDOWN_MINUTES * 60))
    
    if [ $((current_time - last_alert_time)) -lt $cooldown_seconds ]; then
        return 1  # Still in cooldown
    fi
    
    return 0  # Cooldown expired
}

# Function to update alert state
update_alert_state() {
    local alert_key="$1"
    local current_time=$(date +%s)
    
    jq ".last_alerts[\"$alert_key\"] = $current_time" "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Function to send alert
send_alert() {
    local level="$1"
    local title="$2"
    local message="$3"
    local alert_key="$4"
    
    # Check cooldown
    if ! check_cooldown "$alert_key"; then
        echo "Alert $alert_key is in cooldown, skipping"
        return 0
    fi
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local alert_payload=$(cat << EOJ
{
    "timestamp": "$timestamp",
    "level": "$level",
    "title": "$title",
    "message": "$message",
    "source": "ai-application-monitor"
}
EOJ
)
    
    echo "Sending alert: $title"
    
    # Send webhook notification
    if [ -n "$WEBHOOK_URL" ]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$alert_payload" \
            2>/dev/null || echo "Failed to send webhook alert"
    fi
    
    # Send email notification (requires mail command)
    if [ -n "$EMAIL_ADDRESS" ] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "[$level] $title" "$EMAIL_ADDRESS" 2>/dev/null || echo "Failed to send email alert"
    fi
    
    # Update alert state
    update_alert_state "$alert_key"
    
    # Log alert
    echo "$timestamp [$level] $title: $message" >> "$ALERTS_DIR/alerts.log"
}

# Get health data and check thresholds
HEALTH_DATA=$(check_application_health json)

# Load thresholds
CPU_WARNING=$(jq -r '.thresholds.cpu_warning // 80' "$CONFIG_FILE")
CPU_CRITICAL=$(jq -r '.thresholds.cpu_critical // 95' "$CONFIG_FILE")
MEMORY_WARNING=$(jq -r '.thresholds.memory_warning // 85' "$CONFIG_FILE")
MEMORY_CRITICAL=$(jq -r '.thresholds.memory_critical // 95' "$CONFIG_FILE")
DISK_WARNING=$(jq -r '.thresholds.disk_warning // 85' "$CONFIG_FILE")
DISK_CRITICAL=$(jq -r '.thresholds.disk_critical // 95' "$CONFIG_FILE")
GPU_TEMP_WARNING=$(jq -r '.thresholds.gpu_temp_warning // 80' "$CONFIG_FILE")
GPU_TEMP_CRITICAL=$(jq -r '.thresholds.gpu_temp_critical // 90' "$CONFIG_FILE")

# Check system metrics
CPU_USAGE=$(echo "$HEALTH_DATA" | jq -r '.system.cpu_usage_percent // 0')
MEMORY_USAGE=$(echo "$HEALTH_DATA" | jq -r '.system.memory.usage_percent // 0')
DISK_USAGE=$(echo "$HEALTH_DATA" | jq -r '.system.disk_usage_percent // 0')

# CPU alerts
if (( $(echo "$CPU_USAGE >= $CPU_CRITICAL" | bc -l) )); then
    send_alert "CRITICAL" "High CPU Usage" "CPU usage is at ${CPU_USAGE}% (critical threshold: ${CPU_CRITICAL}%)" "cpu_critical"
elif (( $(echo "$CPU_USAGE >= $CPU_WARNING" | bc -l) )); then
    send_alert "WARNING" "Elevated CPU Usage" "CPU usage is at ${CPU_USAGE}% (warning threshold: ${CPU_WARNING}%)" "cpu_warning"
fi

# Memory alerts
if (( $(echo "$MEMORY_USAGE >= $MEMORY_CRITICAL" | bc -l) )); then
    send_alert "CRITICAL" "High Memory Usage" "Memory usage is at ${MEMORY_USAGE}% (critical threshold: ${MEMORY_CRITICAL}%)" "memory_critical"
elif (( $(echo "$MEMORY_USAGE >= $MEMORY_WARNING" | bc -l) )); then
    send_alert "WARNING" "Elevated Memory Usage" "Memory usage is at ${MEMORY_USAGE}% (warning threshold: ${MEMORY_WARNING}%)" "memory_warning"
fi

# Disk alerts
if (( $(echo "$DISK_USAGE >= $DISK_CRITICAL" | bc -l) )); then
    send_alert "CRITICAL" "High Disk Usage" "Disk usage is at ${DISK_USAGE}% (critical threshold: ${DISK_CRITICAL}%)" "disk_critical"
elif (( $(echo "$DISK_USAGE >= $DISK_WARNING" | bc -l) )); then
    send_alert "WARNING" "Elevated Disk Usage" "Disk usage is at ${DISK_USAGE}% (warning threshold: ${DISK_WARNING}%)" "disk_warning"
fi

# GPU temperature alerts
GPU_TEMP=$(echo "$HEALTH_DATA" | jq -r '.gpu.temperature_c // 0')
if [ "$GPU_TEMP" != "0" ]; then
    if (( $(echo "$GPU_TEMP >= $GPU_TEMP_CRITICAL" | bc -l) )); then
        send_alert "CRITICAL" "High GPU Temperature" "GPU temperature is at ${GPU_TEMP}°C (critical threshold: ${GPU_TEMP_CRITICAL}°C)" "gpu_temp_critical"
    elif (( $(echo "$GPU_TEMP >= $GPU_TEMP_WARNING" | bc -l) )); then
        send_alert "WARNING" "Elevated GPU Temperature" "GPU temperature is at ${GPU_TEMP}°C (warning threshold: ${GPU_TEMP_WARNING}°C)" "gpu_temp_warning"
    fi
fi

# Service health alerts
echo "$HEALTH_DATA" | jq -r '.services | to_entries[] | select(.value.status != "healthy") | "\(.key):\(.value.status)"' | while IFS=':' read -r service status; do
    if [ "$status" = "down" ] || [ "$status" = "critical" ]; then
        send_alert "CRITICAL" "Service Down" "Service $service is $status" "service_${service}_down"
    elif [ "$status" = "unhealthy" ] || [ "$status" = "degraded" ]; then
        send_alert "WARNING" "Service Unhealthy" "Service $service is $status" "service_${service}_unhealthy"
    fi
done
EOF
    
    chmod +x "$alerts_dir/alert-manager.sh"
}

# Setup alert monitoring
setup_alert_monitoring() {
    local alerts_dir="$1"
    
    # Create cron job for alerts
    echo "*/5 * * * * $alerts_dir/alert-manager.sh" > "$alerts_dir/alerts.cron"
    
    # Create alert dashboard
    cat > "$alerts_dir/dashboard.sh" << 'EOF'
#!/bin/bash
# Alert dashboard

set -euo pipefail

ALERTS_DIR="${1:-/shared/alerts}"
ALERTS_LOG="$ALERTS_DIR/alerts.log"

echo "=== Alert Dashboard ==="
echo "Last updated: $(date)"
echo ""

if [ -f "$ALERTS_LOG" ]; then
    echo "Recent Alerts (last 24 hours):"
    
    # Get alerts from last 24 hours
    YESTERDAY=$(date -d '24 hours ago' +%Y-%m-%d)
    
    if grep "$YESTERDAY\|$(date +%Y-%m-%d)" "$ALERTS_LOG" 2>/dev/null | tail -20; then
        echo ""
    else
        echo "No recent alerts"
        echo ""
    fi
    
    echo "Alert Summary:"
    echo "  Critical: $(grep -c "CRITICAL" "$ALERTS_LOG" 2>/dev/null || echo "0")"
    echo "  Warning: $(grep -c "WARNING" "$ALERTS_LOG" 2>/dev/null || echo "0")"
    echo "  Total: $(wc -l < "$ALERTS_LOG" 2>/dev/null || echo "0")"
else
    echo "No alerts recorded yet"
fi

echo ""
echo "=== Dashboard Complete ==="
EOF
    
    chmod +x "$alerts_dir/dashboard.sh"
}

# =============================================================================
# UTILITIES
# =============================================================================

# Check if system has GPU
has_gpu() {
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1
}

# Get current health status
get_health_status() {
    check_application_health "summary" "false" "10"
}

# Export health metrics for external monitoring
export_health_metrics() {
    local output_file="${1:-/shared/health-metrics.prom}"
    
    check_application_health "prometheus" "true" "30" > "$output_file"
    echo "Health metrics exported to: $output_file" >&2
}

# Create health check endpoint script for load balancers
create_health_endpoint() {
    local port="${1:-8080}"
    local bind_address="${2:-0.0.0.0}"
    
    cat > /shared/health-endpoint.sh << EOF
#!/bin/bash
# Simple health check endpoint for load balancers

# Start simple HTTP server for health checks
while true; do
    HEALTH_STATUS=\$(get_health_status)
    
    if echo "\$HEALTH_STATUS" | grep -q "Status: healthy"; then
        RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nOK"
    else
        RESPONSE="HTTP/1.1 503 Service Unavailable\r\nContent-Type: text/plain\r\n\r\nUnhealthy"
    fi
    
    echo -e "\$RESPONSE" | nc -l -p $port -q 1
done
EOF
    
    chmod +x /shared/health-endpoint.sh
    echo "Health endpoint script created. Run with: /shared/health-endpoint.sh" >&2
}
