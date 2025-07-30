#!/usr/bin/env bash
# =============================================================================
# Core Logging Module
# Uniform logging standards and levels
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CORE_LOGGING_SH_LOADED:-}" ] && return 0
_CORE_LOGGING_SH_LOADED=1

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Log levels (in order of severity)
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_FATAL=4

# Default log level
DEFAULT_LOG_LEVEL="INFO"

# Log level mapping function
get_log_level_value() {
    local level="$1"
    case "$level" in
        "DEBUG") echo "$LOG_LEVEL_DEBUG" ;;
        "INFO") echo "$LOG_LEVEL_INFO" ;;
        "WARN") echo "$LOG_LEVEL_WARN" ;;
        "ERROR") echo "$LOG_LEVEL_ERROR" ;;
        "FATAL") echo "$LOG_LEVEL_FATAL" ;;
        *) echo "$LOG_LEVEL_INFO" ;;
    esac
}

# Color codes for terminal output
get_log_color() {
    local level="$1"
    case "$level" in
        "DEBUG") echo "\033[36m" ;;  # Cyan
        "INFO") echo "\033[32m" ;;   # Green
        "WARN") echo "\033[33m" ;;   # Yellow
        "ERROR") echo "\033[31m" ;;  # Red
        "FATAL") echo "\033[35m" ;;  # Magenta
        *) echo "\033[0m" ;;         # Reset
    esac
}

# Log format templates
LOG_FORMAT_TIMESTAMP="%Y-%m-%d %H:%M:%S"
LOG_FORMAT_ISO_TIMESTAMP="%Y-%m-%dT%H:%M:%SZ"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Current log level
CURRENT_LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"

# Log file configuration
LOG_FILE=""
LOG_FILE_ENABLED=false
LOG_FILE_ROTATION_ENABLED=true
LOG_FILE_MAX_SIZE_MB=100
LOG_FILE_MAX_FILES=5

# Console output configuration
CONSOLE_OUTPUT_ENABLED=true
CONSOLE_COLORS_ENABLED=true

# Structured logging
STRUCTURED_LOGGING_ENABLED=false
LOG_CORRELATION_ID=""

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize logging system
init_logging() {
    local log_file="${1:-}"
    local log_level="${2:-$DEFAULT_LOG_LEVEL}"
    local enable_console="${3:-true}"
    local enable_file="${4:-false}"
    local enable_structured="${5:-false}"
    
    # Set log level
    set_log_level "$log_level"
    
    # Configure console output
    if [[ "$enable_console" == "true" ]]; then
        CONSOLE_OUTPUT_ENABLED=true
    else
        CONSOLE_OUTPUT_ENABLED=false
    fi
    
    # Configure file logging
    if [[ "$enable_file" == "true" && -n "$log_file" ]]; then
        LOG_FILE="$log_file"
        LOG_FILE_ENABLED=true
        
        # Create log directory
        local log_dir
        log_dir=$(dirname "$log_file")
        mkdir -p "$log_dir"
        
        # Initialize log file
        echo "$(get_timestamp) [INFO] Logging initialized - Level: $CURRENT_LOG_LEVEL" >> "$log_file"
    fi
    
    # Configure structured logging
    if [[ "$enable_structured" == "true" ]]; then
        STRUCTURED_LOGGING_ENABLED=true
        LOG_CORRELATION_ID=$(generate_correlation_id)
    fi
    
    # Log initialization message (this will use the configured settings)
    log_message "INFO" "Logging system initialized"
}

# Set log level
set_log_level() {
    local level="${1:-$DEFAULT_LOG_LEVEL}"
    
    # Convert to uppercase
    level=$(echo "$level" | tr '[:lower:]' '[:upper:]')
    
    # Validate log level
    if [[ -z "$(get_log_level_value "$level")" ]]; then
        echo "Invalid log level: $level. Using default: $DEFAULT_LOG_LEVEL" >&2
        level="$DEFAULT_LOG_LEVEL"
    fi
    
    CURRENT_LOG_LEVEL="$level"
    export LOG_LEVEL="$level"
}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Main logging function
log_message() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    
    # Check if we should log this level
    if ! should_log_level "$level"; then
        return 0
    fi
    
    # Format message
    local formatted_message
    formatted_message=$(format_log_message "$level" "$message" "$context")
    
    # Output to console
    if [[ "$CONSOLE_OUTPUT_ENABLED" == "true" ]]; then
        output_to_console "$level" "$formatted_message"
    fi
    
    # Output to file
    if [[ "$LOG_FILE_ENABLED" == "true" && -n "$LOG_FILE" ]]; then
        output_to_file "$formatted_message"
    fi
}

# Log level specific functions
log_debug() {
    log_message "DEBUG" "$1" "${2:-}"
}

log_info() {
    log_message "INFO" "$1" "${2:-}"
}

log_warn() {
    log_message "WARN" "$1" "${2:-}"
}

log_error() {
    log_message "ERROR" "$1" "${2:-}"
}

log_fatal() {
    log_message "FATAL" "$1" "${2:-}"
    exit 1
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if we should log at the given level
should_log_level() {
    local level="$1"
    local current_level_value="$(get_log_level_value "$CURRENT_LOG_LEVEL")"
    local message_level_value="$(get_log_level_value "$level")"
    
    [[ $message_level_value -ge $current_level_value ]]
}

# Format log message
format_log_message() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    
    local timestamp
    timestamp=$(get_timestamp)
    
    local correlation_id=""
    if [[ "$STRUCTURED_LOGGING_ENABLED" == "true" && -n "$LOG_CORRELATION_ID" ]]; then
        correlation_id=" [CID:$LOG_CORRELATION_ID]"
    fi
    
    local context_part=""
    if [[ -n "$context" ]]; then
        context_part=" [$context]"
    fi
    
    if [[ "$STRUCTURED_LOGGING_ENABLED" == "true" ]]; then
        # Structured JSON format
        cat << EOF
{
    "timestamp": "$(get_iso_timestamp)",
    "level": "$level",
    "message": "$message",
    "context": "$context",
    "correlation_id": "$LOG_CORRELATION_ID",
    "pid": "$$",
    "script": "${SCRIPT_NAME:-unknown}"
}
EOF
    else
        # Standard format
        echo "$timestamp [$level]$correlation_id$context_part $message"
    fi
}

# Output to console with colors
output_to_console() {
    local level="$1"
    local message="$2"
    
    if [[ "$CONSOLE_COLORS_ENABLED" == "true" && -t 1 ]]; then
            local color="$(get_log_color "$level")"
    local reset="\033[0m"
        echo -e "${color}${message}${reset}"
    else
        echo "$message"
    fi
}

# Output to file
output_to_file() {
    local message="$1"
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$message" >> "$LOG_FILE"
        
        # Check if we need to rotate the log file
        if [[ "$LOG_FILE_ROTATION_ENABLED" == "true" ]]; then
            check_log_rotation
        fi
    fi
}

# Get current timestamp
get_timestamp() {
    date "+$LOG_FORMAT_TIMESTAMP"
}

# Get ISO timestamp
get_iso_timestamp() {
    date -u "+$LOG_FORMAT_ISO_TIMESTAMP"
}

# Generate correlation ID
generate_correlation_id() {
    local timestamp
    timestamp=$(date +%s%N | cut -b1-13)
    local random
    random=$(printf "%04x" $RANDOM)
    echo "${timestamp}-${random}"
}

# Set correlation ID
set_correlation_id() {
    local correlation_id="$1"
    LOG_CORRELATION_ID="$correlation_id"
}

# Get correlation ID
get_correlation_id() {
    echo "$LOG_CORRELATION_ID"
}

# =============================================================================
# LOG ROTATION
# =============================================================================

# Check if log rotation is needed
check_log_rotation() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    
    local file_size_mb
    file_size_mb=$(get_file_size_mb "$LOG_FILE")
    
    if [[ $file_size_mb -gt $LOG_FILE_MAX_SIZE_MB ]]; then
        rotate_log_file
    fi
}

# Get file size in MB
get_file_size_mb() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local size_bytes
        size_bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        echo $((size_bytes / 1024 / 1024))
    else
        echo "0"
    fi
}

# Rotate log file
rotate_log_file() {
    local base_file="$LOG_FILE"
    local max_files=$LOG_FILE_MAX_FILES
    
    # Remove oldest log file if we've reached the limit
    if [[ -f "${base_file}.${max_files}" ]]; then
        rm -f "${base_file}.${max_files}"
    fi
    
    # Rotate existing log files
    for ((i=max_files-1; i>=1; i--)); do
        if [[ -f "${base_file}.${i}" ]]; then
            mv "${base_file}.${i}" "${base_file}.$((i+1))"
        fi
    done
    
    # Move current log file
    if [[ -f "$base_file" ]]; then
        mv "$base_file" "${base_file}.1"
    fi
    
    # Create new log file
    touch "$base_file"
    
    log_info "Log file rotated: $base_file"
}

# =============================================================================
# STRUCTURED LOGGING
# =============================================================================

# Log structured data
log_structured() {
    local level="$1"
    local message="$2"
    local data="$3"
    local context="${4:-}"
    
    if [[ "$STRUCTURED_LOGGING_ENABLED" == "true" ]]; then
        local structured_message
        structured_message=$(format_structured_message "$level" "$message" "$data" "$context")
        log_message "$level" "$structured_message" "$context"
    else
        # Fall back to regular logging
        log_message "$level" "$message" "$context"
    fi
}

# Format structured message
format_structured_message() {
    local level="$1"
    local message="$2"
    local data="$3"
    local context="$4"
    
    cat << EOF
{
    "timestamp": "$(get_iso_timestamp)",
    "level": "$level",
    "message": "$message",
    "context": "$context",
    "correlation_id": "$LOG_CORRELATION_ID",
    "pid": "$$",
    "script": "${SCRIPT_NAME:-unknown}",
    "data": $data
}
EOF
}

# =============================================================================
# CONTEXT LOGGING
# =============================================================================

# Log with context
log_with_context() {
    local level="$1"
    local message="$2"
    local context="$3"
    
    log_message "$level" "$message" "$context"
}

# Log function entry
log_function_entry() {
    local function_name="$1"
    local args="$2"
    
    log_debug "Entering function: $function_name" "FUNCTION"
    if [[ -n "$args" ]]; then
        log_debug "Arguments: $args" "FUNCTION"
    fi
}

# Log function exit
log_function_exit() {
    local function_name="$1"
    local exit_code="${2:-0}"
    
    if [[ $exit_code -eq 0 ]]; then
        log_debug "Exiting function: $function_name (success)" "FUNCTION"
    else
        log_debug "Exiting function: $function_name (error code: $exit_code)" "FUNCTION"
    fi
}

# =============================================================================
# PERFORMANCE LOGGING
# =============================================================================

# Performance timing variables
PERFORMANCE_TIMERS_FILE="/tmp/performance_timers_$$.json"

# Start performance timer
start_timer() {
    local timer_name="$1"
    local start_time=$(date +%s.%N)
    
    # Create timers file if it doesn't exist
    if [[ ! -f "$PERFORMANCE_TIMERS_FILE" ]]; then
        echo "{}" > "$PERFORMANCE_TIMERS_FILE"
    fi
    
    # Add timer using jq
    if command -v jq >/dev/null 2>&1; then
        jq --arg name "$timer_name" --arg time "$start_time" '. + {($name): $time}' "$PERFORMANCE_TIMERS_FILE" > "${PERFORMANCE_TIMERS_FILE}.tmp" && mv "${PERFORMANCE_TIMERS_FILE}.tmp" "$PERFORMANCE_TIMERS_FILE"
    else
        # Fallback without jq
        echo "$timer_name:$start_time" >> "${PERFORMANCE_TIMERS_FILE}.fallback"
    fi
    
    log_debug "Timer started: $timer_name" "PERFORMANCE"
}

# End performance timer
end_timer() {
    local timer_name="$1"
    local start_time=""
    
    # Get start time
    if command -v jq >/dev/null 2>&1 && [[ -f "$PERFORMANCE_TIMERS_FILE" ]]; then
        start_time=$(jq -r --arg name "$timer_name" '.[$name] // empty' "$PERFORMANCE_TIMERS_FILE")
    else
        # Fallback without jq
        start_time=$(grep "^$timer_name:" "${PERFORMANCE_TIMERS_FILE}.fallback" 2>/dev/null | cut -d: -f2)
    fi
    
    if [[ -n "$start_time" ]]; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        log_info "Timer completed: $timer_name (${duration}s)" "PERFORMANCE"
        
        # Remove timer
        if command -v jq >/dev/null 2>&1; then
            jq --arg name "$timer_name" 'del(.[$name])' "$PERFORMANCE_TIMERS_FILE" > "${PERFORMANCE_TIMERS_FILE}.tmp" && mv "${PERFORMANCE_TIMERS_FILE}.tmp" "$PERFORMANCE_TIMERS_FILE"
        else
            # Fallback without jq
            sed -i.tmp "/^$timer_name:/d" "${PERFORMANCE_TIMERS_FILE}.fallback" 2>/dev/null
        fi
    else
        log_warn "Timer not found: $timer_name" "PERFORMANCE"
    fi
}

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Enable/disable console output
set_console_output() {
    local enabled="$1"
    CONSOLE_OUTPUT_ENABLED="$enabled"
}

# Enable/disable console colors
set_console_colors() {
    local enabled="$1"
    CONSOLE_COLORS_ENABLED="$enabled"
}

# Enable/disable file logging
set_file_logging() {
    local enabled="$1"
    local log_file="${2:-}"
    
    LOG_FILE_ENABLED="$enabled"
    if [[ -n "$log_file" ]]; then
        LOG_FILE="$log_file"
    fi
}

# Enable/disable structured logging
set_structured_logging() {
    local enabled="$1"
    STRUCTURED_LOGGING_ENABLED="$enabled"
    
    if [[ "$enabled" == "true" && -z "$LOG_CORRELATION_ID" ]]; then
        LOG_CORRELATION_ID=$(generate_correlation_id)
    fi
}

# Configure log rotation
set_log_rotation() {
    local enabled="$1"
    local max_size_mb="${2:-100}"
    local max_files="${3:-5}"
    
    LOG_FILE_ROTATION_ENABLED="$enabled"
    LOG_FILE_MAX_SIZE_MB="$max_size_mb"
    LOG_FILE_MAX_FILES="$max_files"
}

# =============================================================================
# LOG ANALYSIS
# =============================================================================

# Get log statistics
get_log_stats() {
    local log_file="${1:-$LOG_FILE}"
    
    if [[ ! -f "$log_file" ]]; then
        echo "Log file not found: $log_file"
        return 1
    fi
    
    echo "Log Statistics for: $log_file"
    echo "  Total lines: $(wc -l < "$log_file")"
    echo "  File size: $(du -h "$log_file" | cut -f1)"
    echo "  Level breakdown:"
    echo "    DEBUG: $(grep -c "\[DEBUG\]" "$log_file" 2>/dev/null || echo "0")"
    echo "    INFO:  $(grep -c "\[INFO\]" "$log_file" 2>/dev/null || echo "0")"
    echo "    WARN:  $(grep -c "\[WARN\]" "$log_file" 2>/dev/null || echo "0")"
    echo "    ERROR: $(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo "0")"
    echo "    FATAL: $(grep -c "\[FATAL\]" "$log_file" 2>/dev/null || echo "0")"
}

# Search logs
search_logs() {
    local pattern="$1"
    local log_file="${2:-$LOG_FILE}"
    local context="${3:-}"
    
    if [[ ! -f "$log_file" ]]; then
        log_error "Log file not found: $log_file"
        return 1
    fi
    
    local search_cmd="grep -E '$pattern' '$log_file'"
    if [[ -n "$context" ]]; then
        search_cmd="$search_cmd | grep '$context'"
    fi
    
    eval "$search_cmd"
}

# Get recent logs
get_recent_logs() {
    local lines="${1:-50}"
    local log_file="${2:-$LOG_FILE}"
    
    if [[ ! -f "$log_file" ]]; then
        log_error "Log file not found: $log_file"
        return 1
    fi
    
    tail -n "$lines" "$log_file"
} 