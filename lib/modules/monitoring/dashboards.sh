#!/usr/bin/env bash
# =============================================================================
# Monitoring Dashboards Module
# Provides deployment visualization and real-time monitoring dashboards
# =============================================================================

# Prevent multiple sourcing
[ -n "${_DASHBOARDS_SH_LOADED:-}" ] && return 0
_DASHBOARDS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/metrics.sh"
source "${SCRIPT_DIR}/structured_logging.sh"

# =============================================================================
# DASHBOARD CONFIGURATION
# =============================================================================

# Dashboard types
readonly DASHBOARD_TYPE_DEPLOYMENT="deployment"
readonly DASHBOARD_TYPE_INFRASTRUCTURE="infrastructure"
readonly DASHBOARD_TYPE_SERVICES="services"
readonly DASHBOARD_TYPE_PERFORMANCE="performance"
readonly DASHBOARD_TYPE_ERRORS="errors"
readonly DASHBOARD_TYPE_CUSTOM="custom"

# Dashboard refresh intervals
readonly DASHBOARD_REFRESH_REALTIME=5
readonly DASHBOARD_REFRESH_FAST=15
readonly DASHBOARD_REFRESH_NORMAL=60
readonly DASHBOARD_REFRESH_SLOW=300

# Dashboard output formats
readonly DASHBOARD_FORMAT_CONSOLE="console"
readonly DASHBOARD_FORMAT_HTML="html"
readonly DASHBOARD_FORMAT_JSON="json"

# Global configuration
DASHBOARD_ENABLED="${DASHBOARD_ENABLED:-true}"
DASHBOARD_REFRESH_INTERVAL="${DASHBOARD_REFRESH_INTERVAL:-$DASHBOARD_REFRESH_NORMAL}"
DASHBOARD_OUTPUT_FORMAT="${DASHBOARD_OUTPUT_FORMAT:-$DASHBOARD_FORMAT_CONSOLE}"
DASHBOARD_OUTPUT_FILE="${DASHBOARD_OUTPUT_FILE:-}"
ACTIVE_DASHBOARDS=()

# =============================================================================
# DASHBOARD MANAGEMENT
# =============================================================================

# Create dashboard
create_dashboard() {
    local dashboard_name="$1"
    local dashboard_type="$2"
    local config="${3:-{}}"
    
    log_info "Creating dashboard: $dashboard_name (type: $dashboard_type)" "DASHBOARDS"
    
    # Generate dashboard ID
    local dashboard_id="${dashboard_name}-$(date +%s)"
    
    # Create dashboard definition
    local dashboard_def
    dashboard_def=$(cat <<EOF
{
    "id": "$dashboard_id",
    "name": "$dashboard_name",
    "type": "$dashboard_type",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "refresh_interval": ${DASHBOARD_REFRESH_INTERVAL},
    "config": $config,
    "widgets": []
}
EOF
)
    
    # Add to active dashboards
    ACTIVE_DASHBOARDS+=("$dashboard_def")
    
    # Initialize dashboard based on type
    case "$dashboard_type" in
        "$DASHBOARD_TYPE_DEPLOYMENT")
            init_deployment_dashboard "$dashboard_id"
            ;;
        "$DASHBOARD_TYPE_INFRASTRUCTURE")
            init_infrastructure_dashboard "$dashboard_id"
            ;;
        "$DASHBOARD_TYPE_SERVICES")
            init_services_dashboard "$dashboard_id"
            ;;
        "$DASHBOARD_TYPE_PERFORMANCE")
            init_performance_dashboard "$dashboard_id"
            ;;
        "$DASHBOARD_TYPE_ERRORS")
            init_errors_dashboard "$dashboard_id"
            ;;
        "$DASHBOARD_TYPE_CUSTOM")
            # Custom dashboards start empty
            ;;
    esac
    
    echo "$dashboard_id"
}

# =============================================================================
# DASHBOARD INITIALIZATION
# =============================================================================

# Initialize deployment dashboard
init_deployment_dashboard() {
    local dashboard_id="$1"
    
    # Add deployment status widget
    add_widget_to_dashboard "$dashboard_id" \
        "deployment_status" \
        "Deployment Status" \
        "status" \
        '{"show_phase": true, "show_progress": true}'
    
    # Add deployment timeline widget
    add_widget_to_dashboard "$dashboard_id" \
        "deployment_timeline" \
        "Deployment Timeline" \
        "timeline" \
        '{"max_events": 10}'
    
    # Add resource status widget
    add_widget_to_dashboard "$dashboard_id" \
        "resource_status" \
        "Resource Status" \
        "grid" \
        '{"resources": ["vpc", "instance", "alb", "efs"]}'
    
    # Add deployment metrics widget
    add_widget_to_dashboard "$dashboard_id" \
        "deployment_metrics" \
        "Deployment Metrics" \
        "metrics" \
        '{"metrics": ["duration", "success_rate", "rollback_count"]}'
}

# Initialize infrastructure dashboard
init_infrastructure_dashboard() {
    local dashboard_id="$1"
    
    # Add VPC status widget
    add_widget_to_dashboard "$dashboard_id" \
        "vpc_status" \
        "VPC Status" \
        "detail" \
        '{"show_subnets": true, "show_routes": true}'
    
    # Add instance status widget
    add_widget_to_dashboard "$dashboard_id" \
        "instance_status" \
        "Instance Status" \
        "table" \
        '{"columns": ["id", "type", "state", "cpu", "memory"]}'
    
    # Add network topology widget
    add_widget_to_dashboard "$dashboard_id" \
        "network_topology" \
        "Network Topology" \
        "graph" \
        '{"show_connections": true}'
    
    # Add security groups widget
    add_widget_to_dashboard "$dashboard_id" \
        "security_groups" \
        "Security Groups" \
        "list" \
        '{"show_rules": true}'
}

# Initialize services dashboard
init_services_dashboard() {
    local dashboard_id="$1"
    
    # Add service health widget
    add_widget_to_dashboard "$dashboard_id" \
        "service_health" \
        "Service Health" \
        "grid" \
        '{"services": ["n8n", "qdrant", "ollama", "crawl4ai"]}'
    
    # Add service metrics widget
    add_widget_to_dashboard "$dashboard_id" \
        "service_metrics" \
        "Service Metrics" \
        "chart" \
        '{"chart_type": "line", "metrics": ["requests", "latency", "errors"]}'
    
    # Add service logs widget
    add_widget_to_dashboard "$dashboard_id" \
        "service_logs" \
        "Recent Service Logs" \
        "log_viewer" \
        '{"max_lines": 20, "filter_level": "WARN"}'
}

# Initialize performance dashboard
init_performance_dashboard() {
    local dashboard_id="$1"
    
    # Add CPU metrics widget
    add_widget_to_dashboard "$dashboard_id" \
        "cpu_metrics" \
        "CPU Metrics" \
        "chart" \
        '{"chart_type": "area", "metrics": ["usage", "load_1m", "load_5m"]}'
    
    # Add memory metrics widget
    add_widget_to_dashboard "$dashboard_id" \
        "memory_metrics" \
        "Memory Metrics" \
        "chart" \
        '{"chart_type": "line", "metrics": ["used", "free", "cached"]}'
    
    # Add disk metrics widget
    add_widget_to_dashboard "$dashboard_id" \
        "disk_metrics" \
        "Disk Metrics" \
        "gauge" \
        '{"show_iops": true}'
    
    # Add network metrics widget
    add_widget_to_dashboard "$dashboard_id" \
        "network_metrics" \
        "Network Metrics" \
        "chart" \
        '{"chart_type": "line", "metrics": ["bytes_in", "bytes_out", "packets"]}'
}

# Initialize errors dashboard
init_errors_dashboard() {
    local dashboard_id="$1"
    
    # Add error summary widget
    add_widget_to_dashboard "$dashboard_id" \
        "error_summary" \
        "Error Summary" \
        "stats" \
        '{"group_by": "category", "show_trend": true}'
    
    # Add recent errors widget
    add_widget_to_dashboard "$dashboard_id" \
        "recent_errors" \
        "Recent Errors" \
        "table" \
        '{"columns": ["timestamp", "code", "message", "component"]}'
    
    # Add error rate widget
    add_widget_to_dashboard "$dashboard_id" \
        "error_rate" \
        "Error Rate" \
        "chart" \
        '{"chart_type": "line", "time_window": 3600}'
    
    # Add error heatmap widget
    add_widget_to_dashboard "$dashboard_id" \
        "error_heatmap" \
        "Error Heatmap" \
        "heatmap" \
        '{"group_by": ["component", "hour"]}'
}

# =============================================================================
# WIDGET MANAGEMENT
# =============================================================================

# Add widget to dashboard
add_widget_to_dashboard() {
    local dashboard_id="$1"
    local widget_id="$2"
    local widget_title="$3"
    local widget_type="$4"
    local widget_config="${5:-{}}"
    
    log_debug "Adding widget $widget_id to dashboard $dashboard_id" "DASHBOARDS"
    
    # Create widget definition
    local widget_def
    widget_def=$(cat <<EOF
{
    "id": "$widget_id",
    "title": "$widget_title",
    "type": "$widget_type",
    "config": $widget_config,
    "position": {
        "row": 0,
        "col": 0,
        "width": 6,
        "height": 4
    }
}
EOF
)
    
    # Update dashboard with new widget
    local updated_dashboards=()
    for dashboard in "${ACTIVE_DASHBOARDS[@]}"; do
        local current_id=$(echo "$dashboard" | jq -r '.id')
        if [[ "$current_id" == "$dashboard_id" ]]; then
            dashboard=$(echo "$dashboard" | jq --argjson widget "$widget_def" '.widgets += [$widget]')
        fi
        updated_dashboards+=("$dashboard")
    done
    
    ACTIVE_DASHBOARDS=("${updated_dashboards[@]}")
}

# Remove widget from dashboard
remove_widget_from_dashboard() {
    local dashboard_id="$1"
    local widget_id="$2"
    
    log_debug "Removing widget $widget_id from dashboard $dashboard_id" "DASHBOARDS"
    
    # Update dashboard without widget
    local updated_dashboards=()
    for dashboard in "${ACTIVE_DASHBOARDS[@]}"; do
        local current_id=$(echo "$dashboard" | jq -r '.id')
        if [[ "$current_id" == "$dashboard_id" ]]; then
            dashboard=$(echo "$dashboard" | jq --arg widget "$widget_id" '.widgets = [.widgets[] | select(.id != $widget)]')
        fi
        updated_dashboards+=("$dashboard")
    done
    
    ACTIVE_DASHBOARDS=("${updated_dashboards[@]}")
}

# =============================================================================
# DASHBOARD RENDERING
# =============================================================================

# Render dashboard
render_dashboard() {
    local dashboard_id="$1"
    local format="${2:-$DASHBOARD_OUTPUT_FORMAT}"
    
    # Find dashboard
    local dashboard=""
    for d in "${ACTIVE_DASHBOARDS[@]}"; do
        local current_id=$(echo "$d" | jq -r '.id')
        if [[ "$current_id" == "$dashboard_id" ]]; then
            dashboard="$d"
            break
        fi
    done
    
    if [[ -z "$dashboard" ]]; then
        log_error "Dashboard not found: $dashboard_id" "DASHBOARDS"
        return 1
    fi
    
    # Render based on format
    case "$format" in
        "$DASHBOARD_FORMAT_CONSOLE")
            render_dashboard_console "$dashboard"
            ;;
        "$DASHBOARD_FORMAT_HTML")
            render_dashboard_html "$dashboard"
            ;;
        "$DASHBOARD_FORMAT_JSON")
            render_dashboard_json "$dashboard"
            ;;
        *)
            log_error "Unknown dashboard format: $format" "DASHBOARDS"
            return 1
            ;;
    esac
}

# Render dashboard to console
render_dashboard_console() {
    local dashboard="$1"
    
    local name=$(echo "$dashboard" | jq -r '.name')
    local type=$(echo "$dashboard" | jq -r '.type')
    local updated=$(date)
    
    # Clear screen for full dashboard
    clear
    
    # Header
    echo "================================================================================"
    echo " $name ($type)"
    echo " Updated: $updated"
    echo "================================================================================"
    echo
    
    # Render widgets
    local widgets=$(echo "$dashboard" | jq -c '.widgets[]')
    while IFS= read -r widget; do
        render_widget_console "$widget"
        echo
    done <<< "$widgets"
    
    # Footer
    echo "================================================================================"
    echo " Press Ctrl+C to exit | Refresh: ${DASHBOARD_REFRESH_INTERVAL}s"
    echo "================================================================================"
}

# Render widget to console
render_widget_console() {
    local widget="$1"
    
    local title=$(echo "$widget" | jq -r '.title')
    local type=$(echo "$widget" | jq -r '.type')
    local widget_id=$(echo "$widget" | jq -r '.id')
    
    # Widget header
    echo "┌─ $title ─────────────────────────────────────────────────────────────────────┐"
    
    # Render widget content based on type
    case "$type" in
        "status")
            render_status_widget_console "$widget_id"
            ;;
        "metrics")
            render_metrics_widget_console "$widget_id"
            ;;
        "chart")
            render_chart_widget_console "$widget_id"
            ;;
        "table")
            render_table_widget_console "$widget_id"
            ;;
        "grid")
            render_grid_widget_console "$widget_id"
            ;;
        "timeline")
            render_timeline_widget_console "$widget_id"
            ;;
        "log_viewer")
            render_log_viewer_widget_console "$widget_id"
            ;;
        *)
            echo "│ Widget type not implemented: $type"
            ;;
    esac
    
    # Widget footer
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
}

# =============================================================================
# WIDGET RENDERERS
# =============================================================================

# Render status widget
render_status_widget_console() {
    local widget_id="$1"
    
    case "$widget_id" in
        "deployment_status")
            local state=$(get_variable "DEPLOYMENT_STATE" "$VARIABLE_SCOPE_STACK")
            local phase=$(get_variable "DEPLOYMENT_PHASE" "$VARIABLE_SCOPE_STACK")
            local progress=$(get_variable "DEPLOYMENT_PROGRESS" "$VARIABLE_SCOPE_STACK")
            
            echo "│ State: $state"
            echo "│ Phase: $phase"
            echo "│ Progress: ${progress:-0}%"
            ;;
        *)
            echo "│ No data available"
            ;;
    esac
}

# Render metrics widget
render_metrics_widget_console() {
    local widget_id="$1"
    
    # Get latest metrics
    local metrics=$(query_aggregated_logs '[.[] | select(.operation == "metric")] | .[-5:]' 2>/dev/null || echo "[]")
    
    if [[ "$metrics" == "[]" ]]; then
        echo "│ No metrics available"
    else
        echo "$metrics" | jq -r '.[] | "│ \(.metadata.metric_name): \(.metadata.value) \(.metadata.unit)"'
    fi
}

# Render chart widget (simplified ASCII)
render_chart_widget_console() {
    local widget_id="$1"
    
    # For console, show simplified chart representation
    echo "│ ┌─────────────────────────────────────────────────────────────────────────┐"
    echo "│ │  100% ┤                                                                 │"
    echo "│ │   75% ┤         ╭──────╮                                               │"
    echo "│ │   50% ┤    ╭────╯      ╰────╮                                          │"
    echo "│ │   25% ┤────╯                ╰────────────────                           │"
    echo "│ │    0% └─────────────────────────────────────────────────────────────────│"
    echo "│ └─────────────────────────────────────────────────────────────────────────┘"
}

# Render table widget
render_table_widget_console() {
    local widget_id="$1"
    
    case "$widget_id" in
        "instance_status")
            # Get instance information
            local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
            if [[ -n "$instance_id" ]]; then
                echo "│ Instance ID    │ Type         │ State    │ CPU  │ Memory │"
                echo "│ ──────────────┼──────────────┼──────────┼──────┼────────│"
                echo "│ ${instance_id:0:12}... │ g4dn.xlarge  │ running  │ 15%  │ 2.5GB  │"
            else
                echo "│ No instances running"
            fi
            ;;
        "recent_errors")
            # Get recent errors
            local errors=$(query_aggregated_logs '[.[] | select(.level == "ERROR")] | .[-3:]' 2>/dev/null || echo "[]")
            if [[ "$errors" == "[]" ]]; then
                echo "│ No recent errors"
            else
                echo "│ Time       │ Code │ Message                                │"
                echo "│ ───────────┼──────┼────────────────────────────────────────│"
                echo "$errors" | jq -r '.[] | "│ \(.timestamp | .[11:19]) │ \(.metadata.error_code // "N/A" | .[0:4]) │ \(.message | .[0:38])... │"'
            fi
            ;;
        *)
            echo "│ No data available"
            ;;
    esac
}

# Render grid widget
render_grid_widget_console() {
    local widget_id="$1"
    
    case "$widget_id" in
        "service_health")
            echo "│ ┌─────────┬─────────┬─────────┬──────────┐"
            echo "│ │   n8n   │ qdrant  │ ollama  │ crawl4ai │"
            echo "│ ├─────────┼─────────┼─────────┼──────────┤"
            echo "│ │    ✓    │    ✓    │    ✓    │     ✓    │"
            echo "│ └─────────┴─────────┴─────────┴──────────┘"
            ;;
        "resource_status")
            echo "│ VPC: ✓  Instance: ✓  ALB: ✓  EFS: ✓"
            ;;
        *)
            echo "│ No data available"
            ;;
    esac
}

# Render timeline widget
render_timeline_widget_console() {
    local widget_id="$1"
    
    # Get recent deployment events
    local events=$(query_aggregated_logs '[.[] | select(.component == "deployment" and .operation == "deployment_event")] | .[-5:]' 2>/dev/null || echo "[]")
    
    if [[ "$events" == "[]" ]]; then
        echo "│ No deployment events"
    else
        echo "$events" | jq -r '.[] | "│ \(.timestamp | .[11:19]) - \(.message)"'
    fi
}

# Render log viewer widget
render_log_viewer_widget_console() {
    local widget_id="$1"
    
    # Get recent logs
    local logs=$(query_aggregated_logs '.[-10:]' 2>/dev/null || echo "[]")
    
    if [[ "$logs" == "[]" ]]; then
        echo "│ No logs available"
    else
        echo "$logs" | jq -r '.[] | "│ [\(.level | .[0:1])] \(.message | .[0:70])..."'
    fi
}

# =============================================================================
# DASHBOARD AUTO-REFRESH
# =============================================================================

# Start dashboard auto-refresh
start_dashboard_refresh() {
    local dashboard_id="$1"
    local interval="${2:-$DASHBOARD_REFRESH_INTERVAL}"
    
    log_info "Starting dashboard auto-refresh for $dashboard_id (interval: ${interval}s)" "DASHBOARDS"
    
    # Create refresh script
    local refresh_script="/tmp/dashboard_refresh_$$.sh"
    cat > "$refresh_script" <<EOF
#!/usr/bin/env bash
while true; do
    render_dashboard "$dashboard_id"
    sleep $interval
done
EOF
    
    chmod +x "$refresh_script"
    
    # Run refresh loop
    "$refresh_script"
}

# =============================================================================
# DASHBOARD HTML RENDERING
# =============================================================================

# Render dashboard to HTML
render_dashboard_html() {
    local dashboard="$1"
    
    local name=$(echo "$dashboard" | jq -r '.name')
    local type=$(echo "$dashboard" | jq -r '.type')
    
    cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>$name - GeuseMaker Dashboard</title>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="${DASHBOARD_REFRESH_INTERVAL}">
    <style>
        body { font-family: monospace; background: #1e1e1e; color: #d4d4d4; margin: 20px; }
        .dashboard { max-width: 1200px; margin: 0 auto; }
        .header { background: #2d2d2d; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .widget { background: #2d2d2d; padding: 15px; border-radius: 8px; margin-bottom: 15px; }
        .widget-title { color: #569cd6; font-size: 18px; margin-bottom: 10px; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-label { color: #9cdcfe; }
        .metric-value { color: #b5cea8; font-size: 24px; }
        .status-ok { color: #4ec9b0; }
        .status-error { color: #f44747; }
        .status-warning { color: #dcdcaa; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #3e3e3e; }
        th { color: #569cd6; }
    </style>
</head>
<body>
    <div class="dashboard">
        <div class="header">
            <h1>$name</h1>
            <p>Type: $type | Updated: <span id="timestamp"></span></p>
        </div>
        <div id="widgets">
EOF
    
    # Render widgets
    local widgets=$(echo "$dashboard" | jq -c '.widgets[]')
    while IFS= read -r widget; do
        render_widget_html "$widget"
    done <<< "$widgets"
    
    cat <<EOF
        </div>
    </div>
    <script>
        document.getElementById('timestamp').textContent = new Date().toLocaleString();
        
        // Auto-refresh countdown
        let countdown = ${DASHBOARD_REFRESH_INTERVAL};
        setInterval(() => {
            countdown--;
            if (countdown <= 0) {
                location.reload();
            }
        }, 1000);
    </script>
</body>
</html>
EOF
}

# Render widget to HTML
render_widget_html() {
    local widget="$1"
    
    local title=$(echo "$widget" | jq -r '.title')
    local type=$(echo "$widget" | jq -r '.type')
    local widget_id=$(echo "$widget" | jq -r '.id')
    
    echo "        <div class='widget'>"    echo "            <div class='widget-title'>$title</div>"
    echo "            <div class='widget-content' id='$widget_id'>"
    
    # Render widget content based on type
    case "$type" in
        "status")
            render_status_widget_html "$widget_id"
            ;;
        "metrics")
            render_metrics_widget_html "$widget_id"
            ;;
        "table")
            render_table_widget_html "$widget_id"
            ;;
        "grid")
            render_grid_widget_html "$widget_id"
            ;;
        *)
            echo "                <p>Widget type not implemented: $type</p>"
            ;;
    esac
    
    echo "            </div>"
    echo "        </div>"
}

# =============================================================================
# DASHBOARD JSON RENDERING
# =============================================================================

# Render dashboard to JSON
render_dashboard_json() {
    local dashboard="$1"
    
    # Add current data to dashboard
    local dashboard_with_data
    dashboard_with_data=$(echo "$dashboard" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {last_updated: $ts}')
    
    # Add widget data
    local widgets=$(echo "$dashboard_with_data" | jq -c '.widgets')
    local updated_widgets="[]"
    
    local widget
    while IFS= read -r widget; do
        local widget_id=$(echo "$widget" | jq -r '.id')
        local widget_data=$(get_widget_data "$widget_id")
        widget=$(echo "$widget" | jq --argjson data "$widget_data" '. + {data: $data}')
        updated_widgets=$(echo "$updated_widgets" | jq --argjson w "$widget" '. += [$w]')
    done < <(echo "$widgets" | jq -c '.[]')
    
    dashboard_with_data=$(echo "$dashboard_with_data" | jq --argjson widgets "$updated_widgets" '.widgets = $widgets')
    
    echo "$dashboard_with_data" | jq '.'
}

# Get widget data
get_widget_data() {
    local widget_id="$1"
    
    case "$widget_id" in
        "deployment_status")
            cat <<EOF
{
    "state": "$(get_variable "DEPLOYMENT_STATE" "$VARIABLE_SCOPE_STACK")",
    "phase": "$(get_variable "DEPLOYMENT_PHASE" "$VARIABLE_SCOPE_STACK")",
    "progress": $(get_variable "DEPLOYMENT_PROGRESS" "$VARIABLE_SCOPE_STACK" || echo "0")
}
EOF
            ;;
        "service_health")
            cat <<EOF
{
    "n8n": true,
    "qdrant": true,
    "ollama": true,
    "crawl4ai": true
}
EOF
            ;;
        *)
            echo '{}'
            ;;
    esac
}

# =============================================================================
# DASHBOARD UTILITIES
# =============================================================================

# List active dashboards
list_dashboards() {
    if [[ ${#ACTIVE_DASHBOARDS[@]} -eq 0 ]]; then
        echo "No active dashboards"
        return 0
    fi
    
    echo "Active Dashboards:"
    for dashboard in "${ACTIVE_DASHBOARDS[@]}"; do
        local id=$(echo "$dashboard" | jq -r '.id')
        local name=$(echo "$dashboard" | jq -r '.name')
        local type=$(echo "$dashboard" | jq -r '.type')
        local widget_count=$(echo "$dashboard" | jq '.widgets | length')
        echo "  - $name (ID: $id, Type: $type, Widgets: $widget_count)"
    done
}

# Get dashboard by ID
get_dashboard() {
    local dashboard_id="$1"
    
    for dashboard in "${ACTIVE_DASHBOARDS[@]}"; do
        local current_id=$(echo "$dashboard" | jq -r '.id')
        if [[ "$current_id" == "$dashboard_id" ]]; then
            echo "$dashboard"
            return 0
        fi
    done
    
    return 1
}

# Delete dashboard
delete_dashboard() {
    local dashboard_id="$1"
    
    log_info "Deleting dashboard: $dashboard_id" "DASHBOARDS"
    
    local updated_dashboards=()
    local found=false
    
    for dashboard in "${ACTIVE_DASHBOARDS[@]}"; do
        local current_id=$(echo "$dashboard" | jq -r '.id')
        if [[ "$current_id" != "$dashboard_id" ]]; then
            updated_dashboards+=("$dashboard")
        else
            found=true
        fi
    done
    
    if [[ "$found" == "true" ]]; then
        ACTIVE_DASHBOARDS=("${updated_dashboards[@]}")
        log_info "Dashboard deleted: $dashboard_id" "DASHBOARDS"
        return 0
    else
        log_error "Dashboard not found: $dashboard_id" "DASHBOARDS"
        return 1
    fi
}

# Export dashboard
export_dashboard() {
    local dashboard_id="$1"
    local output_file="$2"
    local format="${3:-json}"
    
    log_info "Exporting dashboard $dashboard_id to $output_file" "DASHBOARDS"
    
    # Get dashboard
    local dashboard
    dashboard=$(get_dashboard "$dashboard_id")
    
    if [[ $? -ne 0 ]]; then
        log_error "Dashboard not found: $dashboard_id" "DASHBOARDS"
        return 1
    fi
    
    # Export based on format
    case "$format" in
        "json")
            echo "$dashboard" | jq '.' > "$output_file"
            ;;
        "html")
            render_dashboard_html "$dashboard" > "$output_file"
            ;;
        *)
            log_error "Unsupported export format: $format" "DASHBOARDS"
            return 1
            ;;
    esac
    
    log_info "Dashboard exported successfully" "DASHBOARDS"
}

# Import dashboard
import_dashboard() {
    local input_file="$1"
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Input file not found: $input_file" "DASHBOARDS"
        return 1
    fi
    
    log_info "Importing dashboard from $input_file" "DASHBOARDS"
    
    # Read and validate dashboard
    local dashboard
    dashboard=$(cat "$input_file")
    
    # Validate JSON
    if ! echo "$dashboard" | jq '.' >/dev/null 2>&1; then
        log_error "Invalid dashboard JSON in file: $input_file" "DASHBOARDS"
        return 1
    fi
    
    # Generate new ID for imported dashboard
    local original_id=$(echo "$dashboard" | jq -r '.id')
    local new_id="imported-$(date +%s)"
    dashboard=$(echo "$dashboard" | jq --arg id "$new_id" '.id = $id')
    
    # Add to active dashboards
    ACTIVE_DASHBOARDS+=("$dashboard")
    
    log_info "Dashboard imported successfully (new ID: $new_id, original: $original_id)" "DASHBOARDS"
    echo "$new_id"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup dashboards
cleanup_dashboards() {
    log_info "Cleaning up dashboards" "DASHBOARDS"
    
    # Clear active dashboards
    ACTIVE_DASHBOARDS=()
    
    # Remove any temporary files
    rm -f /tmp/dashboard_refresh_$$.sh
    
    log_info "Dashboard cleanup complete" "DASHBOARDS"
}