#!/usr/bin/env bash
# =============================================================================
# Error Handling Library
# Comprehensive error handling patterns and utilities
# Requires: bash 5.3.3+
# =============================================================================

# Bash version validation - critical for error handling reliability
if [[ -z "${BASH_VERSION_VALIDATED:-}" ]]; then
    # Get the directory of this script for sourcing bash_version module
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/modules/core/bash_version.sh"
    require_bash_533 "error-handling.sh"
    export BASH_VERSION_VALIDATED=true
fi

# =============================================================================
# COLOR DEFINITIONS (fallback if not already defined)
# =============================================================================

# Color definitions - use parameter expansion to avoid conflicts
# These will be overridden by aws-deployment-common.sh if it's sourced later
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[0;33m}"
BLUE="${BLUE:-\033[0;34m}"
PURPLE="${PURPLE:-\033[0;35m}"
CYAN="${CYAN:-\033[0;36m}"
NC="${NC:-\033[0m}"

# =============================================================================
# ERROR HANDLING CONFIGURATION
# =============================================================================

# Error handling modes (only define if not already set)
if [[ -z "${ERROR_HANDLING_MODES_DEFINED:-}" ]]; then
    readonly ERROR_MODE_STRICT="strict"        # Exit on any error
    readonly ERROR_MODE_RESILIENT="resilient"  # Continue with warnings
    readonly ERROR_MODE_INTERACTIVE="interactive" # Prompt user on errors
    readonly ERROR_HANDLING_MODES_DEFINED=true
fi

# Enhanced error types using bash 5.3+ features
if [[ -z "${ERROR_TYPES_DEFINED:-}" ]]; then
    declare -A ERROR_TYPES=(
        [SYSTEM]="System error"
        [AWS]="AWS API error"
        [DOCKER]="Docker error"
        [NETWORK]="Network error"
        [VALIDATION]="Validation error"
        [SECURITY]="Security error"
        [DEPENDENCY]="Dependency error"
        [CONFIGURATION]="Configuration error"
        [RESOURCE]="Resource error"
        [TIMEOUT]="Timeout error"
        [PERMISSION]="Permission error"
        [QUOTA]="Quota/limit error"
        [DATA]="Data error"
        [USER]="User error"
        [UNKNOWN]="Unknown error"
    )
    readonly ERROR_TYPES
    export ERROR_TYPES_DEFINED=true
fi

# Logging levels with modern bash features
if [[ -z "${LOG_LEVELS_DEFINED:-}" ]]; then
    declare -A LOG_LEVELS=(
        [TRACE]=0
        [DEBUG]=1
        [INFO]=2
        [WARN]=3
        [ERROR]=4
        [FATAL]=5
    )
    declare -A LOG_LEVEL_COLORS=(
        [TRACE]="\033[0;37m"     # Light gray
        [DEBUG]="\033[0;36m"     # Cyan
        [INFO]="\033[0;32m"      # Green
        [WARN]="\033[0;33m"      # Yellow
        [ERROR]="\033[0;31m"     # Red
        [FATAL]="\033[1;31m"     # Bold red
    )
    readonly LOG_LEVELS LOG_LEVEL_COLORS
    export LOG_LEVELS_DEFINED=true
fi

# Performance monitoring variables
if [[ -z "${PERF_MONITORING_INITIALIZED:-}" ]]; then
    declare -A FUNCTION_TIMINGS
    declare -A FUNCTION_CALL_COUNTS
    declare -A CHECKPOINT_TIMES
    readonly FUNCTION_TIMINGS FUNCTION_CALL_COUNTS CHECKPOINT_TIMES
    export PERF_MONITORING_INITIALIZED=true
fi

# Default error handling configuration
export ERROR_HANDLING_MODE="${ERROR_HANDLING_MODE:-$ERROR_MODE_STRICT}"
export ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/GeuseMaker-errors.log}"
export ERROR_NOTIFICATION_ENABLED="${ERROR_NOTIFICATION_ENABLED:-false}"
export ERROR_CLEANUP_ENABLED="${ERROR_CLEANUP_ENABLED:-true}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export STRUCTURED_LOGGING="${STRUCTURED_LOGGING:-true}"
export PERFORMANCE_MONITORING="${PERFORMANCE_MONITORING:-false}"
export ERROR_ANALYTICS="${ERROR_ANALYTICS:-true}"

# =============================================================================
# ERROR LOGGING AND TRACKING
# =============================================================================

# Initialize error tracking with modern bash features
ERROR_COUNT=0
WARNING_COUNT=0
LAST_ERROR=""
ERROR_CONTEXT=""
ERROR_STACK=()
ERROR_HISTORY=()

# Error metadata tracking
if [[ -z "${ERROR_METADATA_INITIALIZED:-}" ]]; then
    declare -A ERROR_METADATA
    declare -A ERROR_TIMESTAMPS
    declare -A ERROR_LOCATIONS
    declare -A ERROR_RECOVERY_ATTEMPTS
    readonly ERROR_METADATA ERROR_TIMESTAMPS ERROR_LOCATIONS ERROR_RECOVERY_ATTEMPTS
    export ERROR_METADATA_INITIALIZED=true
fi

# Process and session tracking
SESSION_ID="$(date +%Y%m%d_%H%M%S)_$$"
START_TIME="$(date +%s.%N)"
PROCESS_HIERARCHY=()
CURRENT_OPERATION=""
OPERATION_STACK=()

# =============================================================================
# MODERN BASH 5.3+ UTILITY FUNCTIONS
# =============================================================================

# Get caller information with enhanced stack trace
get_caller_info() {
    local caller_index=2  # Skip this function and the calling log function
    local caller_func="${FUNCNAME[$caller_index]:-main}"
    local caller_file="${BASH_SOURCE[$caller_index]:-unknown}"
    local caller_line="${BASH_LINENO[$((caller_index-1))]:-0}"
    
    echo "${caller_func}@$(basename "$caller_file"):$caller_line"
}

# Initialize structured logging
init_structured_logging() {
    local log_file="$1"
    local enable_rotation="${2:-true}"
    
    # Create log directory if it doesn't exist
    local log_dir
    log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # Rotate log if it exists and rotation is enabled
    if [[ "$enable_rotation" == "true" && -f "$log_file" ]]; then
        local log_size
        log_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo 0)
        if (( log_size > 10485760 )); then  # 10MB
            mv "$log_file" "${log_file}.$(date +%Y%m%d_%H%M%S).old"
        fi
    fi
    
    # Initialize log with session header
    {
        echo "=== GeuseMaker Error Log Session Started ==="
        echo "Timestamp: $(date -Iseconds)"
        echo "Session ID: $SESSION_ID"
        echo "PID: $$"
        echo "Script: ${BASH_SOURCE[2]:-unknown}"
        echo "Mode: $ERROR_HANDLING_MODE"
        echo "Bash Version: $BASH_VERSION"
        echo "Platform: $(uname -s) $(uname -r)"
        echo "User: $(whoami)"
        echo "PWD: $PWD"
        echo "Arguments: $*"
        echo "============================================"
    } > "$log_file"
}

# Structured logging function
log_structured() {
    local level="$1"
    local message="$2"
    shift 2
    local attributes=("$@")
    
    # Check if log level is enabled
    local current_level_num="${LOG_LEVELS[$LOG_LEVEL]:-2}"
    local message_level_num="${LOG_LEVELS[$level]:-2}"
    
    if (( message_level_num < current_level_num )); then
        return 0
    fi
    
    local timestamp iso_timestamp caller_info
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    iso_timestamp=$(date -Iseconds)
    caller_info=$(get_caller_info)
    
    # Build structured log entry
    local log_entry
    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        # JSON-like structured format
        log_entry="{\"timestamp\":\"$iso_timestamp\",\"level\":\"$level\",\"message\":\"$message\",\"session_id\":\"$SESSION_ID\",\"caller\":\"$caller_info\",\"pid\":$$"
        
        for attr in "${attributes[@]}"; do
            if [[ "$attr" =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                log_entry="$log_entry,\"$key\":\"$value\""
            fi
        done
        
        log_entry="$log_entry}"
    else
        # Traditional format
        log_entry="[$timestamp] [$level] $message"
        for attr in "${attributes[@]}"; do
            log_entry="$log_entry [$attr]"
        done
    fi
    
    # Output to console with colors
    local color="${LOG_LEVEL_COLORS[$level]:-\033[0m}"
    echo -e "${color}$log_entry${NC}" >&2
    
    # Output to log file
    echo "$log_entry" >> "$ERROR_LOG_FILE"
}

# Initialize performance monitoring
init_performance_monitoring() {
    # Clear previous data
    FUNCTION_TIMINGS=()
    FUNCTION_CALL_COUNTS=()
    CHECKPOINT_TIMES=()
    
    # Set initial checkpoint
    CHECKPOINT_TIMES["session_start"]="$START_TIME"
    
    log_structured "DEBUG" "Performance monitoring initialized" \
        "start_time=$START_TIME"
}

# Initialize error analytics
init_error_analytics() {
    local analytics_file="${ERROR_LOG_FILE%.*}_analytics.json"
    
    # Initialize analytics file if it doesn't exist
    if [[ ! -f "$analytics_file" ]]; then
        echo '{"error_counts":{},"error_patterns":{},"recovery_success":{},"session_stats":{}}' > "$analytics_file"
    fi
    
    export ERROR_ANALYTICS_FILE="$analytics_file"
}

# Initialize resource monitoring
init_resource_monitoring() {
    # Check available memory and disk space
    local available_memory available_disk
    
    if command -v free >/dev/null 2>&1; then
        available_memory=$(free -m | awk 'NR==2{printf "%.1f", $7/1024}')
    else
        available_memory="unknown"
    fi
    
    if command -v df >/dev/null 2>&1; then
        available_disk=$(df -h . | awk 'NR==2{print $4}')
    else
        available_disk="unknown"
    fi
    
    log_structured "DEBUG" "Resource monitoring initialized" \
        "available_memory_gb=$available_memory" \
        "available_disk=$available_disk"
}

# Update error analytics
update_error_analytics() {
    local error_type="$1"
    local message="$2"
    local context="${3:-}"
    
    if [[ -z "$ERROR_ANALYTICS_FILE" ]]; then
        return 0
    fi
    
    # Use jq if available for JSON manipulation, otherwise use basic approach
    if command -v jq >/dev/null 2>&1; then
        local temp_file
        temp_file=$(mktemp)
        
        # Update error counts
        jq --arg type "$error_type" \
           '.error_counts[$type] = (.error_counts[$type] // 0) + 1' \
           "$ERROR_ANALYTICS_FILE" > "$temp_file" && \
        mv "$temp_file" "$ERROR_ANALYTICS_FILE"
    else
        # Basic analytics without jq
        echo "$(date -Iseconds): $error_type - $message" >> "${ERROR_ANALYTICS_FILE%.json}.log"
    fi
}

# Handle signal-based exits
handle_signal_exit() {
    local signal="$1"
    local exit_code=${2:-130}
    
    log_structured "WARN" "Received signal $signal, initiating graceful shutdown" \
        "signal=$signal" \
        "exit_code=$exit_code"
    
    # Perform cleanup
    cleanup_on_exit
    
    # Exit with appropriate code
    exit "$exit_code"
}

init_error_handling() {
    local mode="${1:-$ERROR_MODE_STRICT}"
    local log_file="${2:-$ERROR_LOG_FILE}"
    local options="${3:-}"
    
    export ERROR_HANDLING_MODE="$mode"
    export ERROR_LOG_FILE="$log_file"
    
    # Parse options
    local enable_profiling=false
    local enable_analytics=true
    local log_rotation=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable-profiling) enable_profiling=true; shift ;;
            --disable-analytics) enable_analytics=false; shift ;;
            --disable-log-rotation) log_rotation=false; shift ;;
            *) shift ;;
        esac
    done
    
    # Initialize structured error log
    init_structured_logging "$log_file" "$log_rotation"
    
    # Initialize performance monitoring if enabled
    if [[ "$enable_profiling" == "true" || "$PERFORMANCE_MONITORING" == "true" ]]; then
        init_performance_monitoring
    fi
    
    # Initialize error analytics if enabled
    if [[ "$enable_analytics" == "true" && "$ERROR_ANALYTICS" == "true" ]]; then
        init_error_analytics
    fi
    
    # Set up modern error trapping with enhanced diagnostics
    case "$mode" in
        "$ERROR_MODE_STRICT")
            set -euo pipefail -E  # -E ensures ERR trap is inherited by functions
            trap 'handle_script_error $? $LINENO "$BASH_COMMAND" "${FUNCNAME[*]}" "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}"' ERR
            ;;
        "$ERROR_MODE_RESILIENT")
            set -uo pipefail -E
            trap 'handle_script_error $? $LINENO "$BASH_COMMAND" "${FUNCNAME[*]}" "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}"' ERR
            ;;
        "$ERROR_MODE_INTERACTIVE")
            set -uo pipefail -E
            trap 'handle_script_error $? $LINENO "$BASH_COMMAND" "${FUNCNAME[*]}" "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}"' ERR
            ;;
    esac
    
    # Set up comprehensive signal handling
    trap 'handle_signal_exit SIGINT' INT
    trap 'handle_signal_exit SIGTERM' TERM
    trap 'handle_signal_exit SIGHUP' HUP
    trap 'cleanup_on_exit' EXIT
    
    # Set up resource monitoring
    init_resource_monitoring
    
    log_structured "INFO" "Error handling initialized" \
        "mode=$mode" \
        "log_file=$log_file" \
        "profiling=$enable_profiling" \
        "analytics=$enable_analytics" \
        "session_id=$SESSION_ID"
}

# =============================================================================
# ENHANCED LOGGING FUNCTIONS
# =============================================================================

log_error() {
    local message="$1"
    local context="${2:-}"
    local exit_code="${3:-1}"
    local error_type="${4:-UNKNOWN}"
    local recovery_suggestion="${5:-}"
    
    ((ERROR_COUNT++))
    LAST_ERROR="$message"
    ERROR_CONTEXT="$context"
    
    local timestamp error_id caller_info
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    error_id="${SESSION_ID}_$(printf '%04d' $ERROR_COUNT)"
    caller_info=$(get_caller_info)
    
    # Store error metadata
    ERROR_TIMESTAMPS["$error_id"]="$timestamp"
    ERROR_METADATA["$error_id"]="type=$error_type;context=$context;exit_code=$exit_code;caller=$caller_info"
    ERROR_LOCATIONS["$error_id"]="${BASH_SOURCE[1]:-unknown}:${BASH_LINENO[0]:-0}"
    
    # Log with structured format
    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        log_structured "ERROR" "$message" \
            "error_id=$error_id" \
            "error_type=$error_type" \
            "context=$context" \
            "exit_code=$exit_code" \
            "caller=$caller_info" \
            "recovery_suggestion=$recovery_suggestion"
    else
        # Legacy console output
        echo -e "${RED}[ERROR] $message${NC}" >&2
        if [ -n "$context" ]; then
            echo -e "${RED}        Context: $context${NC}" >&2
        fi
        if [ -n "$recovery_suggestion" ]; then
            echo -e "${YELLOW}        Suggestion: $recovery_suggestion${NC}" >&2
        fi
    fi
    
    # Add to error stack with enhanced information
    ERROR_STACK+=("[$timestamp] [$error_type] $message (ID: $error_id)")
    ERROR_HISTORY+=("$error_id")
    
    # Send notification if enabled
    if [ "$ERROR_NOTIFICATION_ENABLED" = "true" ]; then
        send_error_notification "$message" "$context" "$error_type" "$error_id"
    fi
    
    # Update error analytics
    if [[ "$ERROR_ANALYTICS" == "true" ]]; then
        update_error_analytics "$error_type" "$message" "$context"
    fi
    
    return "$exit_code"
}

log_warning() {
    local message="$1"
    local context="${2:-}"
    
    ((WARNING_COUNT++))
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to console
    echo -e "${YELLOW}[WARNING] $message${NC}" >&2
    if [ -n "$context" ]; then
        echo -e "${YELLOW}          Context: $context${NC}" >&2
    fi
    
    # Log to file
    echo "[$timestamp] WARNING: $message" >> "$ERROR_LOG_FILE"
    if [ -n "$context" ]; then
        echo "[$timestamp]          Context: $context" >> "$ERROR_LOG_FILE"
    fi
}

log_debug() {
    local message="$1"
    local context="${2:-}"
    
    # Only log debug messages if debug mode is enabled
    if [ "${DEBUG:-false}" = "true" ]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo -e "${CYAN}[DEBUG] $message${NC}" >&2
        if [ -n "$context" ]; then
            echo -e "${CYAN}        Context: $context${NC}" >&2
        fi
        
        echo "[$timestamp] DEBUG: $message" >> "$ERROR_LOG_FILE"
        if [ -n "$context" ]; then
            echo "[$timestamp]        Context: $context" >> "$ERROR_LOG_FILE"
        fi
    fi
}

# =============================================================================
# ERROR RECOVERY AND RETRY MECHANISMS
# =============================================================================

retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local description="$3"
    shift 3
    local command=("$@")
    
    local attempt=1
    local exit_code=0
    
    log_debug "Starting retry loop for: $description"
    
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            log_debug "Command succeeded on attempt $attempt"
            return 0
        else
            exit_code=$?
            log_warning "Attempt $attempt/$max_attempts failed (exit code: $exit_code)" "$description"
            
            if [ $attempt -lt $max_attempts ]; then
                log_debug "Waiting ${delay}s before retry..."
                sleep "$delay"
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "Command failed after $max_attempts attempts" "$description" "$exit_code"
    return "$exit_code"
}

retry_with_backoff() {
    local max_attempts="$1"
    local initial_delay="$2"
    local backoff_multiplier="$3"
    local description="$4"
    shift 4
    local command=("$@")
    
    local attempt=1
    local delay="$initial_delay"
    local exit_code=0
    
    log_debug "Starting exponential backoff retry for: $description"
    
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts (delay: ${delay}s): ${command[*]}"
        
        if "${command[@]}"; then
            log_debug "Command succeeded on attempt $attempt"
            return 0
        else
            exit_code=$?
            log_warning "Attempt $attempt/$max_attempts failed (exit code: $exit_code)" "$description"
            
            if [ $attempt -lt $max_attempts ]; then
                log_debug "Waiting ${delay}s before retry (exponential backoff)..."
                sleep "$delay"
                delay=$(echo "$delay * $backoff_multiplier" | bc -l | cut -d. -f1)
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "Command failed after $max_attempts attempts with exponential backoff" "$description" "$exit_code"
    return "$exit_code"
}

# =============================================================================
# SCRIPT ERROR HANDLING
# =============================================================================

handle_script_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    
    local script_name="${BASH_SOURCE[1]:-unknown script}"
    local function_name="${FUNCNAME[1]:-main}"
    
    log_error "Script error in $script_name:$line_number" \
              "Function: $function_name, Command: $command, Exit code: $exit_code" \
              "$exit_code"
    
    # Generate stack trace
    generate_stack_trace
    
    case "$ERROR_HANDLING_MODE" in
        "$ERROR_MODE_STRICT")
            log_error "Strict mode: Exiting due to error"
            exit "$exit_code"
            ;;
        "$ERROR_MODE_RESILIENT")
            log_warning "Resilient mode: Continuing despite error"
            return 0
            ;;
        "$ERROR_MODE_INTERACTIVE")
            handle_interactive_error "$exit_code" "$line_number" "$command"
            ;;
    esac
}

handle_interactive_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    
    echo
    warning "An error occurred. What would you like to do?"
    echo "1) Continue execution (ignore error)"
    echo "2) Retry the failed command"
    echo "3) Exit the script"
    echo "4) Drop to debug shell"
    echo
    
    while true; do
        read -p "Choose an option [1-4]: " -r choice
        case "$choice" in
            1)
                log_warning "User chose to continue despite error"
                return 0
                ;;
            2)
                log_debug "User chose to retry command: $command"
                if eval "$command"; then
                    success "Retry succeeded"
                    return 0
                else
                    log_error "Retry failed"
                    handle_interactive_error "$?" "$line_number" "$command"
                fi
                ;;
            3)
                log_warning "User chose to exit"
                exit "$exit_code"
                ;;
            4)
                log_debug "Dropping to debug shell"
                echo "Debug shell (type 'exit' to return):"
                bash --rcfile <(echo "PS1='DEBUG> '")
                ;;
            *)
                echo "Invalid choice. Please select 1-4."
                ;;
        esac
    done
}

# =============================================================================
# STACK TRACE AND DEBUGGING
# =============================================================================

generate_stack_trace() {
    local i=0
    log_error "Stack trace:"
    
    while caller $i >/dev/null 2>&1; do
        local line_info
        line_info=$(caller $i)
        local line_number="${line_info%% *}"
        local function_name="${line_info#* }"
        function_name="${function_name%% *}"
        local script_name="${line_info##* }"
        
        log_error "  [$i] $script_name:$line_number in $function_name()"
        ((i++))
    done
}

dump_environment() {
    log_debug "Environment dump requested"
    
    local env_file="/tmp/environment-dump-$$.txt"
    
    {
        echo "=== Environment Dump at $(date) ==="
        echo "Script: ${BASH_SOURCE[1]:-unknown}"
        echo "PID: $$"
        echo "PWD: $PWD"
        echo "User: $(whoami)"
        echo ""
        echo "=== Variables ==="
        env | sort
        echo ""
        echo "=== Function Stack ==="
        declare -F
        echo ""
        echo "=== Error Statistics ==="
        echo "Error Count: $ERROR_COUNT"
        echo "Warning Count: $WARNING_COUNT"
        echo "Last Error: $LAST_ERROR"
        echo "Error Context: $ERROR_CONTEXT"
    } > "$env_file"
    
    log_debug "Environment dumped to: $env_file"
    echo "$env_file"
}

# =============================================================================
# RESOURCE CLEANUP
# =============================================================================

register_cleanup_function() {
    local cleanup_function="$1"
    local description="${2:-Cleanup function}"
    
    if [ -z "${CLEANUP_FUNCTIONS:-}" ]; then
        CLEANUP_FUNCTIONS=""
    fi
    
    if [ -z "$CLEANUP_FUNCTIONS" ]; then
        CLEANUP_FUNCTIONS="$cleanup_function"
    else
        CLEANUP_FUNCTIONS="$CLEANUP_FUNCTIONS $cleanup_function"
    fi
    log_debug "Registered cleanup function: $cleanup_function ($description)"
}

cleanup_on_exit() {
    local exit_code=$?
    
    log_debug "Cleanup on exit triggered (exit code: $exit_code)"
    
    if [ "$ERROR_CLEANUP_ENABLED" = "true" ] && [ -n "${CLEANUP_FUNCTIONS:-}" ]; then
        local func_count=$(echo "$CLEANUP_FUNCTIONS" | wc -w)
        log_debug "Running $func_count cleanup functions..."
        
        for cleanup_func in $CLEANUP_FUNCTIONS; do
            log_debug "Running cleanup function: $cleanup_func"
            if ! "$cleanup_func"; then
                log_warning "Cleanup function failed: $cleanup_func"
            fi
        done
    fi
    
    # Final error summary
    if [ $ERROR_COUNT -gt 0 ] || [ $WARNING_COUNT -gt 0 ]; then
        log_debug "Session summary: $ERROR_COUNT errors, $WARNING_COUNT warnings"
        echo "Error log: $ERROR_LOG_FILE" >&2
    fi
}

# =============================================================================
# VALIDATION WITH ERROR HANDLING
# =============================================================================

validate_required_command() {
    local command="$1"
    local package_hint="${2:-}"
    local install_command="${3:-}"
    
    if ! command -v "$command" &> /dev/null; then
        local error_msg="Required command not found: $command"
        local context=""
        
        if [ -n "$package_hint" ]; then
            context="Package: $package_hint"
        fi
        
        if [ -n "$install_command" ]; then
            context="$context, Install with: $install_command"
        fi
        
        log_error "$error_msg" "$context"
        return 1
    fi
    
    log_debug "Command available: $command"
    return 0
}

validate_required_file() {
    local file_path="$1"
    local description="${2:-file}"
    local auto_create="${3:-false}"
    
    if [ ! -f "$file_path" ]; then
        if [ "$auto_create" = "true" ]; then
            log_warning "Creating missing $description: $file_path"
            touch "$file_path" || {
                log_error "Failed to create $description: $file_path"
                return 1
            }
        else
            log_error "Required $description not found: $file_path"
            return 1
        fi
    fi
    
    log_debug "File validated: $file_path"
    return 0
}

validate_required_directory() {
    local dir_path="$1"
    local description="${2:-directory}"
    local auto_create="${3:-false}"
    
    if [ ! -d "$dir_path" ]; then
        if [ "$auto_create" = "true" ]; then
            log_warning "Creating missing $description: $dir_path"
            mkdir -p "$dir_path" || {
                log_error "Failed to create $description: $dir_path"
                return 1
            }
        else
            log_error "Required $description not found: $dir_path"
            return 1
        fi
    fi
    
    log_debug "Directory validated: $dir_path"
    return 0
}

# =============================================================================
# AWS-SPECIFIC ERROR HANDLING
# =============================================================================

handle_aws_error() {
    local aws_command="$1"
    local error_output="$2"
    local exit_code="$3"
    
    # Parse common AWS error patterns
    local error_type=""
    local error_message=""
    local suggested_action=""
    
    if echo "$error_output" | grep -q "InvalidUserID.NotFound"; then
        error_type="Authentication Error"
        error_message="AWS credentials are invalid or expired"
        suggested_action="Run 'aws configure' or check your AWS credentials"
    elif echo "$error_output" | grep -q "UnauthorizedOperation"; then
        error_type="Permission Error"
        error_message="Insufficient permissions for the requested operation"
        suggested_action="Check IAM policies and permissions"
    elif echo "$error_output" | grep -q "RequestLimitExceeded"; then
        error_type="Rate Limiting"
        error_message="AWS API rate limit exceeded"
        suggested_action="Wait and retry, or reduce request frequency"
    elif echo "$error_output" | grep -q "InstanceLimitExceeded"; then
        error_type="Resource Limit"
        error_message="Instance limit exceeded in region"
        suggested_action="Try a different region or request limit increase"
    elif echo "$error_output" | grep -q "InsufficientInstanceCapacity"; then
        error_type="Capacity Error"
        error_message="Insufficient capacity for instance type"
        suggested_action="Try different instance type or availability zone"
    else
        error_type="AWS Error"
        error_message="Unknown AWS error"
        suggested_action="Check AWS documentation or contact support"
    fi
    
    log_error "$error_type: $error_message" \
              "Command: $aws_command, Suggested action: $suggested_action" \
              "$exit_code"
    
    return "$exit_code"
}

# =============================================================================
# NOTIFICATION SYSTEM
# =============================================================================

send_error_notification() {
    local error_message="$1"
    local context="${2:-}"
    
    # Simple notification implementations
    # In a real system, this could integrate with Slack, email, SNS, etc.
    
    if command -v notify-send &> /dev/null; then
        notify-send "GeuseMaker Error" "$error_message"
    fi
    
    # Log notification attempt
    log_debug "Error notification sent: $error_message"
}

# =============================================================================
# ERROR RECOVERY STRATEGIES
# =============================================================================

suggest_error_recovery() {
    local error_context="$1"
    local suggestions=()
    
    case "$error_context" in
        *"aws"*|*"AWS"*)
            suggestions+=(
                "Check AWS credentials: aws sts get-caller-identity"
                "Verify AWS region: aws configure get region"
                "Check service limits in AWS console"
                "Try a different availability zone"
            )
            ;;
        *"docker"*|*"Docker"*)
            suggestions+=(
                "Check Docker daemon: docker info"
                "Free up disk space: docker system prune"
                "Restart Docker service: sudo systemctl restart docker"
                "Check Docker permissions: sudo usermod -aG docker \$USER"
            )
            ;;
        *"ssh"*|*"SSH"*)
            suggestions+=(
                "Check key file permissions: chmod 600 keyfile.pem"
                "Verify security group allows SSH (port 22)"
                "Check instance public IP and connectivity"
                "Wait for instance to fully initialize"
            )
            ;;
        *"network"*|*"connection"*)
            suggestions+=(
                "Check internet connectivity"
                "Verify firewall settings"
                "Try different DNS servers"
                "Check proxy settings"
            )
            ;;
    esac
    
    if [ ${#suggestions[@]} -gt 0 ]; then
        log_warning "Recovery suggestions for '$error_context':"
        for suggestion in "${suggestions[@]}"; do
            log_warning "  • $suggestion"
        done
    fi
}

# =============================================================================
# ERROR REPORTING
# =============================================================================

generate_error_report() {
    local report_file="${1:-/tmp/error-report-$(date +%Y%m%d-%H%M%S).txt}"
    
    {
        echo "=== GeuseMaker Error Report ==="
        echo "Generated: $(date)"
        echo "Script: ${BASH_SOURCE[1]:-unknown}"
        echo "PID: $$"
        echo ""
        echo "=== Error Statistics ==="
        echo "Total Errors: $ERROR_COUNT"
        echo "Total Warnings: $WARNING_COUNT"
        echo "Last Error: $LAST_ERROR"
        echo "Error Context: $ERROR_CONTEXT"
        echo ""
        echo "=== Error Stack ==="
        for error in "${ERROR_STACK[@]}"; do
            echo "$error"
        done
        echo ""
        echo "=== System Information ==="
        echo "OS: $(uname -a)"
        echo "User: $(whoami)"
        echo "PWD: $PWD"
        echo "PATH: $PATH"
        echo ""
        echo "=== Environment Variables ==="
        env | grep -E '^(AWS_|STACK_|ERROR_|DEBUG)' | sort
        echo ""
        echo "=== Error Log ==="
        if [ -f "$ERROR_LOG_FILE" ]; then
            cat "$ERROR_LOG_FILE"
        else
            echo "Error log file not found: $ERROR_LOG_FILE"
        fi
    } > "$report_file"
    
    log_debug "Error report generated: $report_file"
    echo "$report_file"
}

# =============================================================================
# MODERN ERROR HANDLING INTEGRATION
# =============================================================================

# Source modern error handling extensions if available
source_modern_error_handling() {
    local lib_dir="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    local modern_lib="$lib_dir/modern-error-handling.sh"
    
    if [[ -f "$modern_lib" ]]; then
        source "$modern_lib"
        log_debug "Modern error handling extensions loaded"
        return 0
    else
        log_warning "Modern error handling extensions not found: $modern_lib"
        return 1
    fi
}

# Initialize modern error handling with compatibility check
init_enhanced_error_handling() {
    local enable_modern="${1:-auto}"
    local enable_monitoring="${2:-false}"
    local enable_safety="${3:-true}"
    
    # Check if we should enable modern features
    local use_modern=false
    if [[ "$enable_modern" == "auto" ]]; then
        # Auto-detect based on bash version
        if bash_533_available 2>/dev/null; then
            use_modern=true
        fi
    elif [[ "$enable_modern" == "true" ]]; then
        use_modern=true
    fi
    
    # Initialize basic error handling
    init_error_handling
    
    # Load modern extensions if requested and available
    if [[ "$use_modern" == "true" ]]; then
        if source_modern_error_handling; then
            init_modern_error_handling "$enable_monitoring" "$enable_safety"
            log_debug "Enhanced error handling with modern features enabled"
        else
            log_warning "Modern error handling requested but not available, using basic mode"
        fi
    else
        log_debug "Using basic error handling mode"
    fi
}
