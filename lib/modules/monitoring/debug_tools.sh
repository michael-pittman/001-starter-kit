#!/usr/bin/env bash
# =============================================================================
# Debugging and Troubleshooting Tools Module
# Provides comprehensive debugging capabilities for deployments
# =============================================================================

# Prevent multiple sourcing
[ -n "${_DEBUG_TOOLS_SH_LOADED:-}" ] && return 0
_DEBUG_TOOLS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/logging.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/structured_logging.sh"
source "${SCRIPT_DIR}/health.sh"

# =============================================================================
# DEBUG CONFIGURATION
# =============================================================================

# Debug levels
readonly DEBUG_LEVEL_NONE=0
readonly DEBUG_LEVEL_BASIC=1
readonly DEBUG_LEVEL_DETAILED=2
readonly DEBUG_LEVEL_VERBOSE=3
readonly DEBUG_LEVEL_TRACE=4

# Debug modes
readonly DEBUG_MODE_LIVE="live"
readonly DEBUG_MODE_SNAPSHOT="snapshot"
readonly DEBUG_MODE_REPLAY="replay"

# Debug output formats
readonly DEBUG_FORMAT_TEXT="text"
readonly DEBUG_FORMAT_JSON="json"
readonly DEBUG_FORMAT_HTML="html"

# Global configuration
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
DEBUG_LEVEL="${DEBUG_LEVEL:-$DEBUG_LEVEL_BASIC}"
DEBUG_MODE="${DEBUG_MODE:-$DEBUG_MODE_LIVE}"
DEBUG_OUTPUT_DIR="${DEBUG_OUTPUT_DIR:-/tmp/debug_$$}"
DEBUG_CAPTURE_ENABLED="${DEBUG_CAPTURE_ENABLED:-false}"
DEBUG_BREAKPOINTS=()

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize debug tools
init_debug_tools() {
    local debug_level="${1:-$DEBUG_LEVEL_BASIC}"
    local output_dir="${2:-$DEBUG_OUTPUT_DIR}"
    local enable_capture="${3:-false}"
    
    log_info "Initializing debug tools" "DEBUG"
    
    # Set debug configuration
    DEBUG_ENABLED=true
    DEBUG_LEVEL="$debug_level"
    DEBUG_OUTPUT_DIR="$output_dir"
    DEBUG_CAPTURE_ENABLED="$enable_capture"
    
    # Create debug output directory
    mkdir -p "$DEBUG_OUTPUT_DIR"
    
    # Initialize debug log
    init_debug_log
    
    # Set up signal handlers for debugging
    setup_debug_signal_handlers
    
    # Enable verbose logging if debug level is high
    if [[ $DEBUG_LEVEL -ge $DEBUG_LEVEL_DETAILED ]]; then
        set_log_level "DEBUG"
    fi
    
    log_info "Debug tools initialized (level: $debug_level)" "DEBUG"
    return 0
}

# Initialize debug log
init_debug_log() {
    local debug_log="$DEBUG_OUTPUT_DIR/debug.log"
    
    # Create debug log header
    cat > "$debug_log" <<EOF
==============================================
Debug Session Started: $(date)
Stack: ${STACK_NAME:-unknown}
Debug Level: $DEBUG_LEVEL
Debug Mode: $DEBUG_MODE
==============================================

EOF
    
    # Enable file logging to debug log
    set_file_logging true "$debug_log"
}

# =============================================================================
# DEBUG FUNCTIONS
# =============================================================================

# Debug log function
debug_log() {
    local level="$1"
    local message="$2"
    local context="${3:-DEBUG}"
    
    if [[ "$DEBUG_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Check if we should log at this level
    if [[ $level -gt $DEBUG_LEVEL ]]; then
        return 0
    fi
    
    # Add debug context
    local debug_context="DEBUG:$context"
    
    # Include stack trace for verbose debugging
    if [[ $DEBUG_LEVEL -ge $DEBUG_LEVEL_VERBOSE ]]; then
        local stack_trace=$(get_stack_trace 2)
        message="$message\nStack: $stack_trace"
    fi
    
    log_debug "$message" "$debug_context"
}

# Debug variable
debug_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    
    debug_log $DEBUG_LEVEL_BASIC "Variable: $var_name = '$var_value'" "VARS"
}

# Debug function entry
debug_function_entry() {
    local func_name="${FUNCNAME[1]}"
    local args="$*"
    
    debug_log $DEBUG_LEVEL_DETAILED "Entering function: $func_name" "FUNC"
    debug_log $DEBUG_LEVEL_VERBOSE "Arguments: $args" "FUNC"
    
    # Start function timer if tracing
    if [[ $DEBUG_LEVEL -ge $DEBUG_LEVEL_TRACE ]]; then
        start_timer "func_$func_name"
    fi
}

# Debug function exit
debug_function_exit() {
    local func_name="${FUNCNAME[1]}"
    local exit_code="${1:-0}"
    
    debug_log $DEBUG_LEVEL_DETAILED "Exiting function: $func_name (code: $exit_code)" "FUNC"
    
    # End function timer if tracing
    if [[ $DEBUG_LEVEL -ge $DEBUG_LEVEL_TRACE ]]; then
        end_timer "func_$func_name"
    fi
}

# =============================================================================
# BREAKPOINTS
# =============================================================================

# Set breakpoint
set_breakpoint() {
    local breakpoint_name="$1"
    local condition="${2:-true}"
    
    debug_log $DEBUG_LEVEL_BASIC "Setting breakpoint: $breakpoint_name" "BREAK"
    
    local breakpoint
    breakpoint=$(cat <<EOF
{
    "name": "$breakpoint_name",
    "condition": "$condition",
    "enabled": true,
    "hit_count": 0
}
EOF
)
    
    DEBUG_BREAKPOINTS+=("$breakpoint")
}

# Check breakpoint
check_breakpoint() {
    local breakpoint_name="$1"
    
    if [[ "$DEBUG_ENABLED" != "true" ]]; then
        return 1
    fi
    
    for bp in "${DEBUG_BREAKPOINTS[@]}"; do
        local name=$(echo "$bp" | jq -r '.name')
        local enabled=$(echo "$bp" | jq -r '.enabled')
        local condition=$(echo "$bp" | jq -r '.condition')
        
        if [[ "$name" == "$breakpoint_name" && "$enabled" == "true" ]]; then
            # Evaluate condition
            if eval "$condition"; then
                debug_log $DEBUG_LEVEL_BASIC "Breakpoint hit: $breakpoint_name" "BREAK"
                
                # Update hit count
                update_breakpoint_hit_count "$breakpoint_name"
                
                # Enter debug shell
                enter_debug_shell "$breakpoint_name"
                
                return 0
            fi
        fi
    done
    
    return 1
}

# Enter debug shell
enter_debug_shell() {
    local context="${1:-debug}"
    
    echo "=== DEBUG SHELL ==="
    echo "Context: $context"
    echo "Type 'help' for commands, 'exit' to continue"
    echo "==================="
    
    local cmd
    while true; do
        read -p "debug> " cmd
        
        case "$cmd" in
            "exit")
                break
                ;;
            "help")
                show_debug_help
                ;;
            "vars")
                show_variables
                ;;
            "stack")
                show_stack_trace
                ;;
            "state")
                show_deployment_state
                ;;
            "logs")
                show_recent_logs
                ;;
            "dump")
                create_debug_dump
                ;;
            *)
                # Execute command
                eval "$cmd"
                ;;
        esac
    done
}

# =============================================================================
# DEBUG DIAGNOSTICS
# =============================================================================

# Run diagnostics
run_diagnostics() {
    local output_file="${1:-$DEBUG_OUTPUT_DIR/diagnostics.txt}"
    
    log_info "Running diagnostics" "DEBUG"
    
    {
        echo "=== DEPLOYMENT DIAGNOSTICS ==="
        echo "Generated: $(date)"
        echo "Stack: ${STACK_NAME:-unknown}"
        echo ""
        
        echo "=== Environment ==="
        show_environment
        echo ""
        
        echo "=== Variables ==="
        show_variables
        echo ""
        
        echo "=== Deployment State ==="
        show_deployment_state
        echo ""
        
        echo "=== System Resources ==="
        show_system_resources
        echo ""
        
        echo "=== AWS Resources ==="
        show_aws_resources
        echo ""
        
        echo "=== Recent Errors ==="
        show_recent_errors
        echo ""
        
        echo "=== Health Checks ==="
        run_health_checks
        echo ""
    } > "$output_file"
    
    log_info "Diagnostics saved to: $output_file" "DEBUG"
}

# Show environment
show_environment() {
    echo "Platform: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "Hostname: $(hostname)"
    echo "User: $(whoami)"
    echo "Shell: $SHELL"
    echo "Bash Version: ${BASH_VERSION}"
    echo "AWS CLI: $(aws --version 2>&1 | head -1)"
    echo "Region: ${AWS_REGION:-not set}"
    echo "Profile: ${AWS_PROFILE:-default}"
}

# Show variables
show_variables() {
    echo "Stack Variables:"
    # Show key deployment variables
    local vars=("STACK_NAME" "DEPLOYMENT_ID" "DEPLOYMENT_STATE" "DEPLOYMENT_PHASE" 
                "VPC_ID" "INSTANCE_ID" "ALB_ARN" "INSTANCE_TYPE")
    
    for var in "${vars[@]}"; do
        printf "  %-20s: %s\n" "$var" "${!var:-<not set>}"
    done
}

# Show deployment state
show_deployment_state() {
    local state=$(get_variable "DEPLOYMENT_STATE" "$VARIABLE_SCOPE_STACK")
    local phase=$(get_variable "DEPLOYMENT_PHASE" "$VARIABLE_SCOPE_STACK")
    local progress=$(get_variable "DEPLOYMENT_PROGRESS" "$VARIABLE_SCOPE_STACK")
    
    echo "State: ${state:-unknown}"
    echo "Phase: ${phase:-unknown}"
    echo "Progress: ${progress:-0}%"
    
    # Show phase history
    echo "\nPhase History:"
    local phases=("validation" "infrastructure" "compute" "application" "verification")
    for phase in "${phases[@]}"; do
        local start_time=$(get_variable "PHASE_${phase^^}_START" "$VARIABLE_SCOPE_STACK")
        local end_time=$(get_variable "PHASE_${phase^^}_END" "$VARIABLE_SCOPE_STACK")
        local duration=$(get_variable "PHASE_${phase^^}_DURATION" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$start_time" ]]; then
            printf "  %-15s: " "$phase"
            if [[ -n "$end_time" ]]; then
                echo "Completed (${duration:-0}s)"
            else
                echo "In Progress"
            fi
        fi
    done
}

# Show system resources
show_system_resources() {
    # CPU
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Memory
    if command -v free >/dev/null 2>&1; then
        free -h | grep -E "^(Mem|Swap):"
    fi
    
    # Disk
    echo "\nDisk Usage:"
    df -h | grep -E "^(/dev/|Filesystem)"
    
    # Network
    echo "\nNetwork Interfaces:"
    ip addr show 2>/dev/null | grep -E "^[0-9]+:" || ifconfig -a 2>/dev/null | grep -E "^[a-z]"
}

# Show AWS resources
show_aws_resources() {
    local vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$vpc_id" ]]; then
        echo "VPC: $vpc_id"
        
        # Get VPC details
        aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query 'Vpcs[0].{State:State,CIDR:CidrBlock}' \
            --output text 2>/dev/null || echo "  Unable to get VPC details"
    fi
    
    if [[ -n "$instance_id" ]]; then
        echo "\nInstance: $instance_id"
        
        # Get instance details
        aws ec2 describe-instances --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].{Type:InstanceType,State:State.Name,IP:PublicIpAddress}' \
            --output text 2>/dev/null || echo "  Unable to get instance details"
    fi
}

# Show recent errors
show_recent_errors() {
    local error_count=$(query_aggregated_logs '[.[] | select(.level == "ERROR")] | length' 2>/dev/null || echo "0")
    echo "Total Errors: $error_count"
    
    if [[ "$error_count" -gt 0 ]]; then
        echo "\nRecent Errors:"
        query_aggregated_logs '[.[] | select(.level == "ERROR")] | .[-5:] | .[] | "\(.timestamp) - \(.message)"' 2>/dev/null | \
            while IFS= read -r line; do
                echo "  $line"
            done
    fi
}

# Run health checks
run_health_checks() {
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$instance_id" ]]; then
        echo "Running health checks for instance: $instance_id"
        check_instance_health "$instance_id" "all" || echo "Health check failed"
    else
        echo "No instance to check"
    fi
}

# =============================================================================
# DEBUG CAPTURE
# =============================================================================

# Start debug capture
start_debug_capture() {
    if [[ "$DEBUG_CAPTURE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log_info "Starting debug capture" "DEBUG"
    
    # Create capture directory
    local capture_dir="$DEBUG_OUTPUT_DIR/capture"
    mkdir -p "$capture_dir"
    
    # Start capturing system metrics
    capture_system_metrics "$capture_dir" &
    local metrics_pid=$!
    echo "$metrics_pid" > "$capture_dir/metrics.pid"
    
    # Start capturing logs
    capture_logs "$capture_dir" &
    local logs_pid=$!
    echo "$logs_pid" > "$capture_dir/logs.pid"
}

# Capture system metrics
capture_system_metrics() {
    local capture_dir="$1"
    local interval=5
    
    while true; do
        {
            echo "=== $(date) ==="
            echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
            echo "Memory: $(free -m | grep "^Mem:" | awk '{print $3 "/" $2 " MB"}')"
            echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
            echo ""
        } >> "$capture_dir/metrics.log"
        
        sleep $interval
    done
}

# Capture logs
capture_logs() {
    local capture_dir="$1"
    
    # Tail various log files
    tail -f /var/log/syslog \
            /var/log/cloud-init.log \
            /var/log/cloud-init-output.log \
            2>/dev/null > "$capture_dir/system.log" &
}

# Stop debug capture
stop_debug_capture() {
    log_info "Stopping debug capture" "DEBUG"
    
    local capture_dir="$DEBUG_OUTPUT_DIR/capture"
    
    # Stop metrics capture
    if [[ -f "$capture_dir/metrics.pid" ]]; then
        kill $(cat "$capture_dir/metrics.pid") 2>/dev/null || true
        rm -f "$capture_dir/metrics.pid"
    fi
    
    # Stop log capture
    if [[ -f "$capture_dir/logs.pid" ]]; then
        kill $(cat "$capture_dir/logs.pid") 2>/dev/null || true
        rm -f "$capture_dir/logs.pid"
    fi
}

# =============================================================================
# DEBUG DUMP
# =============================================================================

# Create debug dump
create_debug_dump() {
    local dump_name="${1:-debug_dump_$(date +%Y%m%d_%H%M%S)}"
    local dump_dir="$DEBUG_OUTPUT_DIR/$dump_name"
    
    log_info "Creating debug dump: $dump_name" "DEBUG"
    
    # Create dump directory
    mkdir -p "$dump_dir"
    
    # Run diagnostics
    run_diagnostics "$dump_dir/diagnostics.txt"
    
    # Collect logs
    collect_debug_logs "$dump_dir"
    
    # Collect configuration
    collect_debug_config "$dump_dir"
    
    # Collect metrics
    collect_debug_metrics "$dump_dir"
    
    # Create archive
    local archive_file="$DEBUG_OUTPUT_DIR/${dump_name}.tar.gz"
    tar -czf "$archive_file" -C "$DEBUG_OUTPUT_DIR" "$dump_name"
    
    log_info "Debug dump created: $archive_file" "DEBUG"
    echo "$archive_file"
}

# Collect debug logs
collect_debug_logs() {
    local dump_dir="$1"
    local logs_dir="$dump_dir/logs"
    
    mkdir -p "$logs_dir"
    
    # Copy debug log
    cp "$DEBUG_OUTPUT_DIR/debug.log" "$logs_dir/" 2>/dev/null || true
    
    # Copy aggregated logs
    if [[ -f "$STRUCTURED_LOG_AGGREGATION_FILE" ]]; then
        cp "$STRUCTURED_LOG_AGGREGATION_FILE" "$logs_dir/aggregated.json"
    fi
    
    # Get recent system logs
    if [[ -f "/var/log/syslog" ]]; then
        tail -n 1000 /var/log/syslog > "$logs_dir/syslog.tail"
    fi
}

# Collect debug configuration
collect_debug_config() {
    local dump_dir="$1"
    local config_dir="$dump_dir/config"
    
    mkdir -p "$config_dir"
    
    # Save environment variables
    env | sort > "$config_dir/environment.txt"
    
    # Save deployment configuration
    {
        echo "Stack Name: ${STACK_NAME:-unknown}"
        echo "Deployment ID: ${DEPLOYMENT_ID:-unknown}"
        echo "AWS Region: ${AWS_REGION:-unknown}"
        echo "Instance Type: ${INSTANCE_TYPE:-unknown}"
        echo "Key Name: ${KEY_NAME:-unknown}"
    } > "$config_dir/deployment.txt"
}

# Collect debug metrics
collect_debug_metrics() {
    local dump_dir="$1"
    local metrics_dir="$dump_dir/metrics"
    
    mkdir -p "$metrics_dir"
    
    # Copy performance metrics
    if [[ -f "$PERF_METRICS_STORAGE_FILE" ]]; then
        cp "$PERF_METRICS_STORAGE_FILE" "$metrics_dir/performance.json"
    fi
    
    # Copy metric aggregations
    if [[ -f "$PERF_METRICS_AGGREGATION_FILE" ]]; then
        cp "$PERF_METRICS_AGGREGATION_FILE" "$metrics_dir/aggregations.json"
    fi
}

# =============================================================================
# TROUBLESHOOTING FUNCTIONS
# =============================================================================

# Troubleshoot deployment
troubleshoot_deployment() {
    local issue_type="${1:-general}"
    
    log_info "Running deployment troubleshooting: $issue_type" "DEBUG"
    
    case "$issue_type" in
        "timeout")
            troubleshoot_timeout
            ;;
        "failed")
            troubleshoot_failure
            ;;
        "network")
            troubleshoot_network
            ;;
        "permissions")
            troubleshoot_permissions
            ;;
        "resources")
            troubleshoot_resources
            ;;
        "general")
            troubleshoot_general
            ;;
        *)
            log_error "Unknown issue type: $issue_type" "DEBUG"
            ;;
    esac
}

# Troubleshoot timeout
troubleshoot_timeout() {
    echo "=== Troubleshooting Deployment Timeout ==="
    
    # Check current phase
    local phase=$(get_variable "DEPLOYMENT_PHASE" "$VARIABLE_SCOPE_STACK")
    echo "Current Phase: $phase"
    
    # Check phase duration
    local phase_start=$(get_variable "PHASE_START_TIME" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$phase_start" ]]; then
        local duration=$(($(date +%s) - phase_start))
        echo "Phase Duration: ${duration}s"
    fi
    
    # Check for common timeout causes
    echo "\nChecking common timeout causes:"
    
    # Network connectivity
    echo -n "  - Network connectivity: "
    if ping -c 1 google.com >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi
    
    # AWS API access
    echo -n "  - AWS API access: "
    if aws sts get-caller-identity >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi
    
    # Instance status
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$instance_id" ]]; then
        echo -n "  - Instance status: "
        local state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        echo "${state:-unknown}"
    fi
}

# Troubleshoot failure
troubleshoot_failure() {
    echo "=== Troubleshooting Deployment Failure ==="
    
    # Get last error
    echo "\nLast Error:"
    local last_error=$(query_aggregated_logs '[.[] | select(.level == "ERROR")] | .[-1]' 2>/dev/null)
    if [[ -n "$last_error" && "$last_error" != "null" ]]; then
        echo "$last_error" | jq '{timestamp, message, metadata}'
    else
        echo "  No errors found in logs"
    fi
    
    # Check resource creation
    echo "\nResource Status:"
    local resources=("VPC_ID" "SUBNET_ID" "INSTANCE_ID" "SECURITY_GROUP_ID")
    for resource in "${resources[@]}"; do
        local value=$(get_variable "$resource" "$VARIABLE_SCOPE_STACK")
        printf "  %-20s: %s\n" "$resource" "${value:-not created}"
    done
    
    # Check quotas
    echo "\nAWS Quotas:"
    check_basic_quotas
}

# Check basic quotas
check_basic_quotas() {
    # Check VPC quota
    local vpc_count=$(aws ec2 describe-vpcs --query 'length(Vpcs)' --output text 2>/dev/null || echo "unknown")
    echo "  VPCs: $vpc_count / 5 (default limit)"
    
    # Check instance quota
    local instance_count=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running,pending" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null || echo "unknown")
    echo "  Running Instances: $instance_count"
}

# =============================================================================
# UTILITIES
# =============================================================================

# Get stack trace
get_stack_trace() {
    local skip="${1:-1}"
    local trace=""
    
    for ((i=skip; i<${#FUNCNAME[@]}; i++)); do
        trace+="  at ${FUNCNAME[$i]} (${BASH_SOURCE[$i]}:${BASH_LINENO[$i-1]})\n"
    done
    
    echo -e "$trace"
}

# Show recent logs
show_recent_logs() {
    local lines="${1:-20}"
    
    echo "=== Recent Logs ==="
    if [[ -f "$DEBUG_OUTPUT_DIR/debug.log" ]]; then
        tail -n "$lines" "$DEBUG_OUTPUT_DIR/debug.log"
    else
        echo "No debug log found"
    fi
}

# Show debug help
show_debug_help() {
    cat <<EOF
Debug Shell Commands:
  help    - Show this help
  vars    - Show variables
  stack   - Show stack trace
  state   - Show deployment state
  logs    - Show recent logs
  dump    - Create debug dump
  exit    - Exit debug shell
  
You can also run any shell command.
EOF
}

# Setup debug signal handlers
setup_debug_signal_handlers() {
    # USR1 - Create debug dump
    trap 'create_debug_dump "signal_dump_$(date +%s)"' USR1
    
    # USR2 - Toggle debug level
    trap 'toggle_debug_level' USR2
}

# Toggle debug level
toggle_debug_level() {
    case "$DEBUG_LEVEL" in
        $DEBUG_LEVEL_NONE)
            DEBUG_LEVEL=$DEBUG_LEVEL_BASIC
            ;;
        $DEBUG_LEVEL_BASIC)
            DEBUG_LEVEL=$DEBUG_LEVEL_DETAILED
            ;;
        $DEBUG_LEVEL_DETAILED)
            DEBUG_LEVEL=$DEBUG_LEVEL_VERBOSE
            ;;
        $DEBUG_LEVEL_VERBOSE)
            DEBUG_LEVEL=$DEBUG_LEVEL_TRACE
            ;;
        $DEBUG_LEVEL_TRACE)
            DEBUG_LEVEL=$DEBUG_LEVEL_BASIC
            ;;
    esac
    
    log_info "Debug level changed to: $DEBUG_LEVEL" "DEBUG"
}

# Update breakpoint hit count
update_breakpoint_hit_count() {
    local breakpoint_name="$1"
    
    local updated_breakpoints=()
    for bp in "${DEBUG_BREAKPOINTS[@]}"; do
        local name=$(echo "$bp" | jq -r '.name')
        if [[ "$name" == "$breakpoint_name" ]]; then
            local hit_count=$(echo "$bp" | jq -r '.hit_count')
            hit_count=$((hit_count + 1))
            bp=$(echo "$bp" | jq --argjson count "$hit_count" '.hit_count = $count')
        fi
        updated_breakpoints+=("$bp")
    done
    
    DEBUG_BREAKPOINTS=("${updated_breakpoints[@]}")
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup debug tools
cleanup_debug_tools() {
    log_info "Cleaning up debug tools" "DEBUG"
    
    # Stop debug capture if running
    stop_debug_capture
    
    # Create final debug dump if enabled
    if [[ "$DEBUG_ENABLED" == "true" && "$DEBUG_CAPTURE_ENABLED" == "true" ]]; then
        create_debug_dump "final_dump"
    fi
    
    # Clear breakpoints
    DEBUG_BREAKPOINTS=()
    
    # Disable debug mode
    DEBUG_ENABLED=false
    
    log_info "Debug tools cleanup complete" "DEBUG"
}