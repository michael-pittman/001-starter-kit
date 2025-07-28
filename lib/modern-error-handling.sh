#!/usr/bin/env bash
# =============================================================================
# Modern Error Handling Extensions
# Advanced bash 5.3+ error handling patterns and utilities
# Requires: bash 5.3.3+
# =============================================================================

# Bash version validation - critical for modern features
if [[ -z "${BASH_VERSION_VALIDATED:-}" ]]; then
    # Get the directory of this script for sourcing bash_version module
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/modules/core/bash_version.sh"
    require_bash_533 "modern-error-handling.sh"
    export BASH_VERSION_VALIDATED=true
fi

# =============================================================================
# ADVANCED ERROR RECOVERY AND ANALYTICS
# =============================================================================

# Get error recovery suggestions based on error type and context
get_error_recovery_suggestion() {
    local error_type="$1"
    local command="$2"
    local exit_code="$3"
    
    case "$error_type" in
        "AWS")
            case "$exit_code" in
                255) echo "Check AWS credentials and network connectivity" ;;
                254) echo "Verify AWS CLI configuration and region settings" ;;
                253) echo "Check AWS service limits and quotas" ;;
                252) echo "Verify IAM permissions for the operation" ;;
                *) echo "Check AWS service status and retry with exponential backoff" ;;
            esac
            ;;
        "DOCKER")
            case "$exit_code" in
                125) echo "Check Docker daemon status and restart if needed" ;;
                126) echo "Verify Docker permissions and user group membership" ;;
                127) echo "Check if Docker is installed and in PATH" ;;
                1) echo "Free up disk space and restart Docker service" ;;
                *) echo "Check Docker logs and verify container configuration" ;;
            esac
            ;;
        "NETWORK")
            case "$exit_code" in
                6) echo "Could not resolve host - check DNS configuration" ;;
                7) echo "Failed to connect - check firewall and network settings" ;;
                28) echo "Operation timeout - check network speed and retry" ;;
                *) echo "Check internet connectivity, DNS resolution, and firewall settings" ;;
            esac
            ;;
        "PERMISSION")
            echo "Check file/directory permissions and user access rights"
            ;;
        "DEPENDENCY")
            echo "Install missing dependencies or check PATH configuration"
            ;;
        "QUOTA"|"RESOURCE")
            echo "Check system resources (disk space, memory, file handles) and quotas"
            ;;
        "TIMEOUT")
            echo "Increase timeout values or check for hanging processes"
            ;;
        *)
            echo "Check logs for detailed error information and retry if appropriate"
            ;;
    esac
}

# Enhanced stack trace generation with modern bash features
generate_enhanced_stack_trace() {
    local function_stack="$1"
    local source_stack="$2"
    local line_stack="$3"
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "ERROR" "Enhanced stack trace:" "trace_type=enhanced"
    else
        log_error "Enhanced stack trace:"
    fi
    
    if [[ -n "$function_stack" && -n "$source_stack" && -n "$line_stack" ]]; then
        # Parse the stacks using bash 5.3+ features
        IFS=' ' read -ra func_array <<< "$function_stack"
        IFS=' ' read -ra source_array <<< "$source_stack"
        IFS=' ' read -ra line_array <<< "$line_stack"
        
        local i=0
        for func in "${func_array[@]}"; do
            local source_file="${source_array[$i]:-unknown}"
            local line_num="${line_array[$i]:-0}"
            
            # Skip internal bash functions
            if [[ "$func" =~ ^(main|source|\.|bash)$ ]]; then
                ((i++))
                continue
            fi
            
            if declare -f log_structured >/dev/null 2>&1; then
                log_structured "ERROR" "  [$i] $(basename "$source_file"):$line_num in $func()" \
                    "stack_level=$i" \
                    "function=$func" \
                    "file=$(basename "$source_file")" \
                    "line=$line_num"
            else
                log_error "  [$i] $(basename "$source_file"):$line_num in $func()"
            fi
            ((i++))
        done
    else
        # Fallback to traditional stack trace
        if declare -f generate_stack_trace >/dev/null 2>&1; then
            generate_stack_trace
        else
            local i=1
            while caller $i >/dev/null 2>&1; do
                local line_info
                line_info=$(caller $i)
                local line_number="${line_info%% *}"
                local function_name="${line_info#* }"
                function_name="${function_name%% *}"
                local script_name="${line_info##* }"
                
                if declare -f log_structured >/dev/null 2>&1; then
                    log_structured "ERROR" "  [$i] $(basename "$script_name"):$line_number in $function_name()"
                else
                    log_error "  [$i] $(basename "$script_name"):$line_number in $function_name()"
                fi
                ((i++))
            done
        fi
    fi
}

# Check for error patterns and recurring issues using modern bash
check_error_patterns() {
    local error_type="$1"
    local command="$2"
    
    # Create a more sophisticated pattern key
    local command_signature
    command_signature=$(echo "$command" | sed -E 's/[[:space:]]+/ /g' | cut -d' ' -f1-3)
    local pattern_key="${error_type}_$(echo "$command_signature" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c1-50)"
    
    # Use modern bash features for pattern storage
    local pattern_file="/tmp/error_patterns_$$"
    local count=1
    
    if [[ -f "$pattern_file" ]]; then
        count=$(grep -c "^$pattern_key$" "$pattern_file" 2>/dev/null || echo 0)
        count=$((count + 1))
    fi
    
    echo "$pattern_key" >> "$pattern_file"
    
    # Alert on recurring patterns with escalating severity
    if (( count >= 5 )); then
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "ERROR" "Critical recurring error pattern detected - possible systemic issue" \
                "pattern=$pattern_key" \
                "count=$count" \
                "error_type=$error_type" \
                "severity=critical"
        else
            log_error "Critical recurring error pattern detected: $pattern_key (count: $count)"
        fi
    elif (( count >= 3 )); then
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "WARN" "Recurring error pattern detected" \
                "pattern=$pattern_key" \
                "count=$count" \
                "error_type=$error_type" \
                "severity=warning"
        else
            log_warning "Recurring error pattern detected: $pattern_key (count: $count)"
        fi
    fi
}

# =============================================================================
# PERFORMANCE MONITORING AND PROFILING
# =============================================================================

# Start timing a function or operation with high-precision timing
start_timer() {
    local timer_name="$1"
    local start_time
    
    # Use high-precision timing if available
    if command -v date >/dev/null 2>&1 && date +%s.%N >/dev/null 2>&1; then
        start_time=$(date +%s.%N)
    else
        start_time=$(date +%s)
    fi
    
    # Store in modern bash associative array if available
    if [[ -n "${CHECKPOINT_TIMES:-}" ]]; then
        CHECKPOINT_TIMES["${timer_name}_start"]="$start_time"
    else
        export "TIMER_${timer_name}_START=$start_time"
    fi
    
    if [[ "${PERFORMANCE_MONITORING:-false}" == "true" ]]; then
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "DEBUG" "Timer started" \
                "timer=$timer_name" \
                "start_time=$start_time"
        else
            log_debug "Timer started: $timer_name at $start_time"
        fi
    fi
}

# End timing and record duration with performance analysis
end_timer() {
    local timer_name="$1"
    local end_time duration
    
    # Use high-precision timing if available
    if command -v date >/dev/null 2>&1 && date +%s.%N >/dev/null 2>&1; then
        end_time=$(date +%s.%N)
    else
        end_time=$(date +%s)
    fi
    
    # Get start time from storage
    local start_time
    if [[ -n "${CHECKPOINT_TIMES:-}" ]]; then
        start_time="${CHECKPOINT_TIMES["${timer_name}_start"]:-${START_TIME:-$end_time}}"
        CHECKPOINT_TIMES["${timer_name}_end"]="$end_time"
    else
        local start_var="TIMER_${timer_name}_START"
        start_time="${!start_var:-${START_TIME:-$end_time}}"
        export "TIMER_${timer_name}_END=$end_time"
    fi
    
    # Calculate duration with high precision
    if command -v bc >/dev/null 2>&1; then
        duration=$(echo "scale=6; $end_time - $start_time" | bc -l 2>/dev/null || echo "0.0")
    else
        duration=$(awk "BEGIN {printf \"%.6f\", $end_time - $start_time}")
    fi
    
    # Store timing data
    if [[ -n "${FUNCTION_TIMINGS:-}" ]]; then
        FUNCTION_TIMINGS["$timer_name"]="$duration"
    else
        export "TIMING_${timer_name}=$duration"
    fi
    
    # Performance analysis and alerting
    local performance_alert=""
    if command -v bc >/dev/null 2>&1; then
        local duration_float=$(echo "$duration" | bc -l)
        if (( $(echo "$duration_float > 30.0" | bc -l) )); then
            performance_alert="slow"
        elif (( $(echo "$duration_float > 10.0" | bc -l) )); then
            performance_alert="moderate"
        fi
    fi
    
    if [[ "${PERFORMANCE_MONITORING:-false}" == "true" ]]; then
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "DEBUG" "Timer completed" \
                "timer=$timer_name" \
                "duration=${duration}s" \
                "end_time=$end_time" \
                "performance_alert=$performance_alert"
        else
            log_debug "Timer completed: $timer_name in ${duration}s${performance_alert:+ ($performance_alert)}"
        fi
    fi
    
    echo "$duration"
}

# Profile a command or function execution with comprehensive monitoring
profile_execution() {
    local name="$1"
    shift
    local command=("$@")
    
    # Pre-execution resource check
    local mem_before cpu_before
    if command -v free >/dev/null 2>&1; then
        mem_before=$(free -m | awk 'NR==2{print $3}')
    fi
    if command -v ps >/dev/null 2>&1; then
        cpu_before=$(ps -o %cpu= -p $$ | tr -d ' ' || echo "0")
    fi
    
    start_timer "$name"
    
    local exit_code=0
    local command_output=""
    
    # Execute command with output capture if needed
    if [[ "${PERFORMANCE_MONITORING:-false}" == "true" ]]; then
        command_output=$(time "${command[@]}" 2>&1) || exit_code=$?
    else
        "${command[@]}" || exit_code=$?
    fi
    
    local duration
    duration=$(end_timer "$name")
    
    # Post-execution resource check
    local mem_after cpu_after mem_diff
    if command -v free >/dev/null 2>&1; then
        mem_after=$(free -m | awk 'NR==2{print $3}')
        mem_diff=$((mem_after - mem_before))
    fi
    if command -v ps >/dev/null 2>&1; then
        cpu_after=$(ps -o %cpu= -p $$ | tr -d ' ' || echo "0")
    fi
    
    # Increment call count
    if [[ -n "${FUNCTION_CALL_COUNTS:-}" ]]; then
        local current_count="${FUNCTION_CALL_COUNTS[$name]:-0}"
        FUNCTION_CALL_COUNTS["$name"]=$((current_count + 1))
    else
        local count_var="COUNT_${name}"
        local current_count="${!count_var:-0}"
        export "$count_var=$((current_count + 1))"
    fi
    
    if [[ "${PERFORMANCE_MONITORING:-false}" == "true" ]]; then
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "INFO" "Function profiled" \
                "function=$name" \
                "duration=${duration}s" \
                "exit_code=$exit_code" \
                "memory_delta_mb=${mem_diff:-unknown}" \
                "cpu_before=${cpu_before:-unknown}" \
                "cpu_after=${cpu_after:-unknown}" \
                "call_count=${FUNCTION_CALL_COUNTS[$name]:-${!count_var:-1}}"
        else
            log_debug "Function profiled: $name (${duration}s, exit: $exit_code, mem: ${mem_diff:-?}MB)"
        fi
    fi
    
    return $exit_code
}

# Generate comprehensive performance report
generate_performance_report() {
    local report_file="${1:-/tmp/performance_report_$(date +%Y%m%d_%H%M%S).txt}"
    
    local session_duration
    if command -v bc >/dev/null 2>&1; then
        session_duration=$(echo "scale=3; $(date +%s.%N) - ${START_TIME:-0}" | bc -l 2>/dev/null || echo "unknown")
    else
        session_duration=$(awk "BEGIN {printf \"%.3f\", $(date +%s) - ${START_TIME:-0}}")
    fi
    
    {
        echo "=== GeuseMaker Enhanced Performance Report ==="
        echo "Generated: $(date -Iseconds)"
        echo "Session ID: ${SESSION_ID:-unknown}"
        echo "Total Session Time: ${session_duration}s"
        echo "Bash Version: $BASH_VERSION"
        echo "Platform: $(uname -s) $(uname -r)"
        echo "Memory: $(free -h 2>/dev/null | awk 'NR==2{print $2 " total, " $3 " used"}' || echo "unknown")"
        echo ""
        
        echo "=== Function Timings ==="
        # Display function timings with modern bash features
        if [[ -n "${FUNCTION_TIMINGS:-}" ]]; then
            for timer_name in "${!FUNCTION_TIMINGS[@]}"; do
                local duration="${FUNCTION_TIMINGS[$timer_name]}"
                local call_count="${FUNCTION_CALL_COUNTS[$timer_name]:-1}"
                local avg_duration
                if command -v bc >/dev/null 2>&1; then
                    avg_duration=$(echo "scale=4; $duration / $call_count" | bc -l 2>/dev/null || echo "$duration")
                else
                    avg_duration=$(awk "BEGIN {printf \"%.4f\", $duration / $call_count}")
                fi
                
                printf "%-30s: %8.4fs (calls: %d, avg: %8.4fs)\\n" \
                    "$timer_name" "$duration" "$call_count" "$avg_duration"
            done | sort -k2 -nr
        else
            echo "No timing data available (modern bash arrays not initialized)"
        fi
        
        echo ""
        echo "=== Performance Analysis ==="
        
        # Analyze slow operations
        local slow_operations=()
        if [[ -n "${FUNCTION_TIMINGS:-}" ]]; then
            for timer_name in "${!FUNCTION_TIMINGS[@]}"; do
                local duration="${FUNCTION_TIMINGS[$timer_name]}"
                if command -v bc >/dev/null 2>&1 && (( $(echo "$duration > 10.0" | bc -l) )); then
                    slow_operations+=("$timer_name: ${duration}s")
                fi
            done
        fi
        
        if [[ ${#slow_operations[@]} -gt 0 ]]; then
            echo "Slow Operations (>10s):"
            printf '%s\n' "${slow_operations[@]}"
        else
            echo "No slow operations detected"
        fi
        
        echo ""
        echo "=== System Resource Summary ==="
        echo "Disk Usage: $(df -h . 2>/dev/null | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}' || echo "unknown")"
        echo "Load Average: $(uptime 2>/dev/null | grep -o 'load average.*' || echo "unknown")"
        
        if command -v docker >/dev/null 2>&1; then
            echo "Docker Status: $(docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "not running")"
        fi
        
        echo ""
        echo "=== Recommendations ==="
        if [[ ${#slow_operations[@]} -gt 0 ]]; then
            echo "- Consider optimizing slow operations identified above"
            echo "- Review error patterns for operations that may be retrying"
        fi
        echo "- Monitor disk space and memory usage during operations"
        echo "- Consider enabling structured logging for better debugging"
        
    } > "$report_file"
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "INFO" "Performance report generated" \
            "report_file=$report_file" \
            "session_duration=${session_duration}s"
    else
        log_debug "Performance report generated: $report_file"
    fi
    
    echo "$report_file"
}

# =============================================================================
# AWS-SPECIFIC ERROR HANDLING WITH MODERN FEATURES
# =============================================================================

# Enhanced AWS error parsing with comprehensive error categorization
parse_aws_error() {
    local aws_output="$1"
    local command="$2"
    local exit_code="$3"
    
    # Modern error type detection using bash 5.3+ features
    local error_type="AWS"
    local error_subtype="UNKNOWN"
    local recovery_action=""
    local retry_suggested=false
    
    # Parse AWS CLI error patterns
    case "$aws_output" in
        *"InvalidUserID.NotFound"*|*"InvalidAccessKeyId"*)
            error_subtype="AUTHENTICATION"
            recovery_action="Check AWS credentials and run 'aws configure'"
            ;;
        *"UnauthorizedOperation"*|*"AccessDenied"*)
            error_subtype="AUTHORIZATION"
            recovery_action="Check IAM policies and permissions"
            ;;
        *"RequestLimitExceeded"*|*"Throttling"*|*"TooManyRequests"*)
            error_subtype="RATE_LIMIT"
            recovery_action="Implement exponential backoff and retry"
            retry_suggested=true
            ;;
        *"InsufficientInstanceCapacity"*|*"Unsupported"*)
            error_subtype="CAPACITY"
            recovery_action="Try different instance type or availability zone"
            ;;
        *"InstanceLimitExceeded"*|*"VcpuLimitExceeded"*)
            error_subtype="QUOTA"
            recovery_action="Request service limit increase or clean up resources"
            ;;
        *"InvalidParameterValue"*|*"ValidationException"*)
            error_subtype="VALIDATION"
            recovery_action="Check command parameters and API documentation"
            ;;
        *"ServiceUnavailable"*|*"InternalFailure"*)
            error_subtype="SERVICE_ERROR"
            recovery_action="Check AWS service health dashboard and retry"
            retry_suggested=true
            ;;
        *"NetworkingError"*|*"EndpointConnectionError"*)
            error_subtype="NETWORK"
            recovery_action="Check internet connectivity and AWS endpoints"
            retry_suggested=true
            ;;
    esac
    
    # Output structured error information
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "ERROR" "AWS error analyzed" \
            "error_type=$error_type" \
            "error_subtype=$error_subtype" \
            "command=$command" \
            "exit_code=$exit_code" \
            "recovery_action=$recovery_action" \
            "retry_suggested=$retry_suggested"
    fi
    
    # Return structured data for programmatic use
    echo "type:$error_type subtype:$error_subtype action:$recovery_action retry:$retry_suggested"
}

# Intelligent AWS retry with adaptive backoff
aws_retry_with_intelligence() {
    local max_attempts="${1:-5}"
    local base_delay="${2:-2}"
    local max_delay="${3:-60}"
    shift 3
    local aws_command=("$@")
    
    local attempt=1
    local delay="$base_delay"
    local exit_code=0
    
    start_timer "aws_retry_${aws_command[1]:-unknown}"
    
    while [ $attempt -le $max_attempts ]; do
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "DEBUG" "AWS command attempt" \
                "attempt=$attempt" \
                "max_attempts=$max_attempts" \
                "command=${aws_command[*]}"
        fi
        
        # Capture both stdout and stderr
        local output
        local temp_output
        temp_output=$(mktemp)
        
        if output=$("${aws_command[@]}" 2>"$temp_output"); then
            rm -f "$temp_output"
            end_timer "aws_retry_${aws_command[1]:-unknown}"
            
            if declare -f log_structured >/dev/null 2>&1; then
                log_structured "INFO" "AWS command succeeded" \
                    "attempt=$attempt" \
                    "command=${aws_command[1]:-unknown}"
            fi
            
            echo "$output"
            return 0
        else
            exit_code=$?
            local error_output
            error_output=$(cat "$temp_output")
            rm -f "$temp_output"
            
            # Parse error for intelligent retry decision
            local error_info
            error_info=$(parse_aws_error "$error_output" "${aws_command[*]}" "$exit_code")
            
            # Extract retry suggestion
            local retry_suggested
            retry_suggested=$(echo "$error_info" | grep -o "retry:[^[:space:]]*" | cut -d: -f2)
            
            if [[ "$retry_suggested" != "true" ]] || [[ $attempt -eq $max_attempts ]]; then
                end_timer "aws_retry_${aws_command[1]:-unknown}"
                
                if declare -f log_structured >/dev/null 2>&1; then
                    log_structured "ERROR" "AWS command failed (no retry)" \
                        "attempt=$attempt" \
                        "exit_code=$exit_code" \
                        "error_output=$error_output" \
                        "retry_suggested=$retry_suggested"
                else
                    log_error "AWS command failed after $attempt attempts: $error_output"
                fi
                
                return "$exit_code"
            fi
            
            # Calculate adaptive delay based on error type
            case "$error_output" in
                *"RequestLimitExceeded"*|*"Throttling"*)
                    delay=$((delay * 3))  # Aggressive backoff for rate limiting
                    ;;
                *"ServiceUnavailable"*)
                    delay=$((delay * 2))  # Standard exponential backoff
                    ;;
                *)
                    delay=$((delay + base_delay))  # Linear increase for other errors
                    ;;
            esac
            
            # Cap the delay
            if [[ $delay -gt $max_delay ]]; then
                delay=$max_delay
            fi
            
            if declare -f log_structured >/dev/null 2>&1; then
                log_structured "WARN" "AWS command failed, retrying" \
                    "attempt=$attempt" \
                    "next_delay=${delay}s" \
                    "error_type=$(echo "$error_info" | grep -o "subtype:[^[:space:]]*" | cut -d: -f2)"
            fi
            
            sleep "$delay"
            ((attempt++))
        fi
    done
    
    end_timer "aws_retry_${aws_command[1]:-unknown}"
    return "$exit_code"
}

# =============================================================================
# MODERN BASH SAFETY AND DEBUGGING FEATURES
# =============================================================================

# Enhanced script safety with modern bash features
enable_enhanced_safety() {
    # Enable all safety features
    set -euo pipefail
    
    # Enable extended debugging if supported
    if [[ $- =~ x ]]; then
        set -T  # Enable DEBUG and RETURN trap inheritance
    fi
    
    # Set up comprehensive error handling
    if declare -f handle_script_error >/dev/null 2>&1; then
        trap 'handle_script_error $? $LINENO "$BASH_COMMAND" "${FUNCNAME[*]}" "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}"' ERR
    fi
    
    # Set up signal handling
    trap 'handle_signal_exit SIGINT 130' INT
    trap 'handle_signal_exit SIGTERM 143' TERM
    trap 'handle_signal_exit SIGHUP 129' HUP
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "DEBUG" "Enhanced safety mode enabled" \
            "bash_options=${-}" \
            "error_handling=comprehensive"
    fi
}

# Resource leak detection and prevention
monitor_resource_usage() {
    local threshold_memory_mb="${1:-1000}"
    local threshold_disk_percent="${2:-85}"
    local check_interval="${3:-60}"
    
    # Background monitoring function
    {
        while true; do
            # Check memory usage
            if command -v free >/dev/null 2>&1; then
                local memory_used_mb
                memory_used_mb=$(free -m | awk 'NR==2{print $3}')
                
                if [[ $memory_used_mb -gt $threshold_memory_mb ]]; then
                    if declare -f log_structured >/dev/null 2>&1; then
                        log_structured "WARN" "High memory usage detected" \
                            "memory_used_mb=$memory_used_mb" \
                            "threshold_mb=$threshold_memory_mb"
                    fi
                fi
            fi
            
            # Check disk usage
            if command -v df >/dev/null 2>&1; then
                local disk_percent
                disk_percent=$(df . | awk 'NR==2{print $5}' | tr -d '%')
                
                if [[ $disk_percent -gt $threshold_disk_percent ]]; then
                    if declare -f log_structured >/dev/null 2>&1; then
                        log_structured "WARN" "High disk usage detected" \
                            "disk_percent=$disk_percent%" \
                            "threshold_percent=$threshold_disk_percent%"
                    fi
                fi
            fi
            
            sleep "$check_interval"
        done
    } &
    
    # Store monitoring PID for cleanup
    RESOURCE_MONITOR_PID=$!
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "DEBUG" "Resource monitoring started" \
            "monitor_pid=$RESOURCE_MONITOR_PID" \
            "memory_threshold_mb=$threshold_memory_mb" \
            "disk_threshold_percent=$threshold_disk_percent"
    fi
}

# Stop resource monitoring
stop_resource_monitoring() {
    if [[ -n "${RESOURCE_MONITOR_PID:-}" ]]; then
        kill "$RESOURCE_MONITOR_PID" 2>/dev/null || true
        unset RESOURCE_MONITOR_PID
        
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "DEBUG" "Resource monitoring stopped"
        fi
    fi
}

# =============================================================================
# MODERN ERROR HANDLING INITIALIZATION
# =============================================================================

# Initialize all modern error handling features
init_modern_error_handling() {
    local enable_monitoring="${1:-false}"
    local enable_safety="${2:-true}"
    local monitoring_thresholds="${3:-}"
    
    # Enable enhanced safety features
    if [[ "$enable_safety" == "true" ]]; then
        enable_enhanced_safety
    fi
    
    # Start resource monitoring if requested
    if [[ "$enable_monitoring" == "true" ]]; then
        if [[ -n "$monitoring_thresholds" ]]; then
            # Parse thresholds: "memory_mb:disk_percent:interval"
            IFS=':' read -ra thresholds <<< "$monitoring_thresholds"
            monitor_resource_usage "${thresholds[0]:-1000}" "${thresholds[1]:-85}" "${thresholds[2]:-60}"
        else
            monitor_resource_usage
        fi
    fi
    
    # Register cleanup function
    if declare -f register_cleanup_function >/dev/null 2>&1; then
        register_cleanup_function stop_resource_monitoring "Stop resource monitoring"
    fi
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "INFO" "Modern error handling initialized" \
            "monitoring_enabled=$enable_monitoring" \
            "safety_enabled=$enable_safety" \
            "bash_version=$BASH_VERSION"
    fi
}

# Export functions for use by other scripts
export -f get_error_recovery_suggestion
export -f generate_enhanced_stack_trace
export -f check_error_patterns
export -f start_timer
export -f end_timer
export -f profile_execution
export -f generate_performance_report
export -f parse_aws_error
export -f aws_retry_with_intelligence
export -f enable_enhanced_safety
export -f monitor_resource_usage
export -f stop_resource_monitoring
export -f init_modern_error_handling