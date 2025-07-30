#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Unified Error Handling System
# Consolidates all error handling into a single, comprehensive system
# =============================================================================

# Prevent multiple sourcing
if [[ "${UNIFIED_ERROR_HANDLING_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly UNIFIED_ERROR_HANDLING_LOADED=true

# =============================================================================
# ERROR CODE DEFINITIONS
# =============================================================================

# Error code ranges
readonly ERROR_GENERAL_MIN=100
readonly ERROR_GENERAL_MAX=199
readonly ERROR_AWS_MIN=200
readonly ERROR_AWS_MAX=299
readonly ERROR_VALIDATION_MIN=300
readonly ERROR_VALIDATION_MAX=399
readonly ERROR_RESOURCE_MIN=400
readonly ERROR_RESOURCE_MAX=499
readonly ERROR_CONFIG_MIN=500
readonly ERROR_CONFIG_MAX=599

# Comprehensive error codes (bash 3.x compatible)
# General errors (100-199)
readonly ERROR_UNKNOWN=100
readonly ERROR_INVALID_ARGUMENT=101
readonly ERROR_MISSING_DEPENDENCY=102
readonly ERROR_PERMISSION_DENIED=103
readonly ERROR_TIMEOUT=104
readonly ERROR_NETWORK_ERROR=105
readonly ERROR_FILE_NOT_FOUND=106
readonly ERROR_DIRECTORY_NOT_FOUND=107
readonly ERROR_OPERATION_FAILED=108

# AWS errors (200-299)
readonly ERROR_AWS_API_ERROR=200
readonly ERROR_AWS_CREDENTIALS=201
readonly ERROR_AWS_THROTTLED=202
readonly ERROR_AWS_SERVICE_ERROR=203
readonly ERROR_INSUFFICIENT_CAPACITY=210
readonly ERROR_SPOT_PRICE_HIGH=211
readonly ERROR_SPOT_INTERRUPTED=212
readonly ERROR_VPC_LIMIT=220
readonly ERROR_SUBNET_EXHAUSTED=221
readonly ERROR_SECURITY_GROUP_LIMIT=222

# Validation errors (300-399)
readonly ERROR_VALIDATION_FAILED=300
readonly ERROR_INVALID_FORMAT=301
readonly ERROR_OUT_OF_RANGE=302
readonly ERROR_MISSING_REQUIRED=303
readonly ERROR_TYPE_MISMATCH=304

# Resource errors (400-499)
readonly ERROR_RESOURCE_NOT_FOUND=400
readonly ERROR_RESOURCE_EXISTS=401
readonly ERROR_RESOURCE_LIMIT=402
readonly ERROR_RESOURCE_CONFLICT=403
readonly ERROR_RESOURCE_BUSY=404

# Configuration errors (500-599)
readonly ERROR_CONFIG_INVALID=500
readonly ERROR_CONFIG_MISSING=501
readonly ERROR_VARIABLE_UNSET=502
readonly ERROR_TYPE_MISMATCH_CONFIG=503

# =============================================================================
# GLOBAL STATE MANAGEMENT
# =============================================================================

# Global error state
LAST_ERROR_CODE=0
LAST_ERROR_MESSAGE=""
LAST_ERROR_CONTEXT=""
LAST_ERROR_SOURCE=""
LAST_ERROR_FUNCTION=""
LAST_ERROR_LINE=0
ERROR_RECOVERY_ATTEMPTED=false
ERROR_RECOVERY_STRATEGY=""

# Error statistics
ERROR_COUNT=0
ERROR_START_TIME=$(date +%s)
declare -a ERROR_HISTORY=()

# Configuration
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/geuse-errors.log}"
ERROR_JSON_LOG="${ERROR_JSON_LOG:-/tmp/geuse-errors.json}"
ERROR_INTERACTIVE="${ERROR_INTERACTIVE:-false}"
ERROR_MAX_RETRIES="${ERROR_MAX_RETRIES:-3}"
ERROR_BACKOFF_BASE="${ERROR_BACKOFF_BASE:-2}"

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

# Initialize error handling
init_error_handling() {
    local mode="${1:-strict}"
    
    # Set error trap
    trap 'handle_error $? "${BASH_SOURCE[0]}" "${LINENO}" "${FUNCNAME[0]:-main}"' ERR
    
    # Set exit trap for cleanup
    trap 'cleanup_on_exit' EXIT
    
    # Set interrupt trap
    trap 'handle_interrupt' INT TERM
    
    # Configure based on mode
    case "$mode" in
        strict)
            set -euo pipefail
            ;;
        resilient)
            set -uo pipefail
            ;;
        debug)
            set -euxo pipefail
            export ERROR_INTERACTIVE=true
            ;;
    esac
    
    # Create log directory
    mkdir -p "$(dirname "$ERROR_LOG_FILE")"
    
    # Log initialization
    log_error_internal "INFO" "Unified error handling initialized (mode: $mode)"
}

# Main error handler
handle_error() {
    local exit_code=$1
    local source_file="${2:-unknown}"
    local line_number="${3:-0}"
    local function_name="${4:-unknown}"
    
    # Update global state
    LAST_ERROR_CODE=$exit_code
    LAST_ERROR_SOURCE="$source_file"
    LAST_ERROR_LINE=$line_number
    LAST_ERROR_FUNCTION="$function_name"
    LAST_ERROR_CONTEXT="$source_file:$line_number in $function_name"
    ((ERROR_COUNT++))
    
    # Add to error history
    ERROR_HISTORY+=("$(date +%s):$exit_code:$LAST_ERROR_CONTEXT")
    
    # Log structured error
    log_structured_error
    
    # Attempt recovery if not already tried
    if [[ "$ERROR_RECOVERY_ATTEMPTED" == "false" ]]; then
        ERROR_RECOVERY_ATTEMPTED=true
        if attempt_error_recovery "$exit_code"; then
            # Recovery successful
            return 0
        fi
    fi
    
    # Interactive mode
    if [[ "$ERROR_INTERACTIVE" == "true" ]] && [[ -t 0 ]]; then
        handle_interactive_error
    fi
    
    return $exit_code
}

# Throw error with context
throw_error() {
    local error_code="${1:-100}"
    local error_message="${2:-Unknown error}"
    local recovery_strategy="${3:-ABORT}"
    
    LAST_ERROR_CODE=$error_code
    LAST_ERROR_MESSAGE=$error_message
    ERROR_RECOVERY_STRATEGY=$recovery_strategy
    
    # Log error
    log_error_internal "ERROR" "[$error_code] $error_message"
    
    # Exit with error code
    exit $error_code
}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Internal logging function
log_error_internal() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$ERROR_LOG_FILE"
    
    # Log to stderr if error or higher
    if [[ "$level" == "ERROR" ]] || [[ "$level" == "FATAL" ]]; then
        echo "[$level] $message" >&2
    fi
}

# Structured error logging
log_structured_error() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local correlation_id="${CORRELATION_ID:-$(uuidgen 2>/dev/null || echo "unknown")}"
    
    # Create JSON log entry
    local json_entry=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "level": "ERROR",
    "correlation_id": "$correlation_id",
    "error": {
        "code": $LAST_ERROR_CODE,
        "message": "$LAST_ERROR_MESSAGE",
        "source": "$LAST_ERROR_SOURCE",
        "line": $LAST_ERROR_LINE,
        "function": "$LAST_ERROR_FUNCTION",
        "context": "$LAST_ERROR_CONTEXT",
        "stack_trace": "$(get_stack_trace)"
    },
    "stats": {
        "error_count": $ERROR_COUNT,
        "uptime_seconds": $(($(date +%s) - ERROR_START_TIME))
    }
}
EOF
)
    
    # Append to JSON log
    echo "$json_entry" >> "$ERROR_JSON_LOG"
}

# Get stack trace
get_stack_trace() {
    local frame=0
    local stack=""
    
    while caller $frame >/dev/null 2>&1; do
        stack+="$(caller $frame)"$'\n'
        ((frame++))
    done
    
    echo "$stack" | head -n -2  # Remove this function and handle_error from trace
}

# =============================================================================
# RECOVERY FUNCTIONS
# =============================================================================

# Attempt error recovery
attempt_error_recovery() {
    local error_code=$1
    local strategy="${ERROR_RECOVERY_STRATEGY:-AUTO}"
    
    # Auto-determine strategy if needed
    if [[ "$strategy" == "AUTO" ]]; then
        strategy=$(determine_recovery_strategy "$error_code")
    fi
    
    case "$strategy" in
        RETRY)
            return $(retry_with_backoff)
            ;;
        FALLBACK)
            return $(use_fallback_value)
            ;;
        CONTINUE)
            log_and_continue
            return 0
            ;;
        ESCALATE)
            escalate_to_operator
            return 1
            ;;
        ABORT|*)
            cleanup_and_exit
            return 1
            ;;
    esac
}

# Determine recovery strategy based on error code
determine_recovery_strategy() {
    local error_code=$1
    
    case $error_code in
        $ERROR_AWS_THROTTLED|$ERROR_NETWORK_ERROR|$ERROR_TIMEOUT)
            echo "RETRY"
            ;;
        $ERROR_INSUFFICIENT_CAPACITY|$ERROR_SPOT_PRICE_HIGH)
            echo "FALLBACK"
            ;;
        $ERROR_VALIDATION_FAILED|$ERROR_INVALID_FORMAT)
            echo "ABORT"
            ;;
        *)
            echo "ABORT"
            ;;
    esac
}

# Retry with exponential backoff
retry_with_backoff() {
    local retry_count="${RETRY_COUNT:-0}"
    local max_retries="${ERROR_MAX_RETRIES:-3}"
    
    if [[ $retry_count -ge $max_retries ]]; then
        log_error_internal "ERROR" "Max retries ($max_retries) exceeded"
        return 1
    fi
    
    local delay=$((ERROR_BACKOFF_BASE ** retry_count))
    log_error_internal "INFO" "Retrying after ${delay}s delay (attempt $((retry_count + 1))/$max_retries)"
    
    sleep "$delay"
    
    # Set retry count for next attempt
    export RETRY_COUNT=$((retry_count + 1))
    
    return 0
}

# Use fallback value or behavior
use_fallback_value() {
    log_error_internal "INFO" "Using fallback strategy"
    
    # Implementation depends on context
    # This should be overridden by specific error handlers
    return 0
}

# Log and continue execution
log_and_continue() {
    log_error_internal "WARNING" "Error logged, continuing execution"
    ERROR_RECOVERY_ATTEMPTED=false
}

# Escalate to operator
escalate_to_operator() {
    log_error_internal "ERROR" "Error requires manual intervention"
    
    # Send notification if configured
    if [[ -n "${ERROR_NOTIFICATION_WEBHOOK:-}" ]]; then
        send_error_notification
    fi
}

# Cleanup and exit
cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]] && [[ $ERROR_COUNT -gt 0 ]]; then
        log_error_internal "INFO" "Cleanup on exit (code: $exit_code, errors: $ERROR_COUNT)"
        
        # Run cleanup hooks
        for hook in "${ERROR_CLEANUP_HOOKS[@]:-}"; do
            if [[ -n "$hook" ]] && declare -f "$hook" >/dev/null; then
                "$hook" || true
            fi
        done
    fi
}

# =============================================================================
# INTERACTIVE ERROR HANDLING
# =============================================================================

handle_interactive_error() {
    echo ""
    echo "ERROR DETECTED!"
    echo "==============="
    echo "Code: $LAST_ERROR_CODE"
    echo "Location: $LAST_ERROR_CONTEXT"
    echo "Message: ${LAST_ERROR_MESSAGE:-No message}"
    echo ""
    echo "Options:"
    echo "  r) Retry the operation"
    echo "  c) Continue execution"
    echo "  s) Show stack trace"
    echo "  d) Drop to debug shell"
    echo "  q) Quit"
    echo ""
    
    local choice
    read -rp "Select option: " choice
    
    case "$choice" in
        r)
            ERROR_RECOVERY_ATTEMPTED=false
            return 0
            ;;
        c)
            log_and_continue
            return 0
            ;;
        s)
            echo "Stack trace:"
            get_stack_trace
            handle_interactive_error
            ;;
        d)
            echo "Dropping to debug shell. Type 'exit' to continue."
            bash || true
            handle_interactive_error
            ;;
        q|*)
            exit $LAST_ERROR_CODE
            ;;
    esac
}

# =============================================================================
# AWS-SPECIFIC ERROR HANDLING
# =============================================================================

# Handle AWS API errors
handle_aws_error() {
    local aws_error="$1"
    local operation="${2:-unknown}"
    
    case "$aws_error" in
        *"InsufficientInstanceCapacity"*)
            LAST_ERROR_CODE=$ERROR_INSUFFICIENT_CAPACITY
            LAST_ERROR_MESSAGE="No capacity available for requested instance type"
            ERROR_RECOVERY_STRATEGY="FALLBACK"
            ;;
        *"RequestLimitExceeded"*)
            LAST_ERROR_CODE=$ERROR_AWS_THROTTLED
            LAST_ERROR_MESSAGE="AWS API rate limit exceeded"
            ERROR_RECOVERY_STRATEGY="RETRY"
            ;;
        *"UnauthorizedOperation"*)
            LAST_ERROR_CODE=$ERROR_AWS_CREDENTIALS
            LAST_ERROR_MESSAGE="AWS credentials lack required permissions"
            ERROR_RECOVERY_STRATEGY="ABORT"
            ;;
        *)
            LAST_ERROR_CODE=$ERROR_AWS_API_ERROR
            LAST_ERROR_MESSAGE="AWS API error: $aws_error"
            ERROR_RECOVERY_STRATEGY="ABORT"
            ;;
    esac
    
    log_error_internal "ERROR" "AWS error in $operation: $LAST_ERROR_MESSAGE"
    return $LAST_ERROR_CODE
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get error message for code
get_error_message() {
    local code=$1
    
    case $code in
        $ERROR_UNKNOWN) echo "Unknown error" ;;
        $ERROR_INVALID_ARGUMENT) echo "Invalid argument" ;;
        $ERROR_MISSING_DEPENDENCY) echo "Missing dependency" ;;
        $ERROR_PERMISSION_DENIED) echo "Permission denied" ;;
        $ERROR_TIMEOUT) echo "Operation timed out" ;;
        $ERROR_NETWORK_ERROR) echo "Network error" ;;
        $ERROR_AWS_CREDENTIALS) echo "AWS credentials error" ;;
        $ERROR_AWS_THROTTLED) echo "AWS API throttled" ;;
        $ERROR_INSUFFICIENT_CAPACITY) echo "Insufficient capacity" ;;
        $ERROR_VALIDATION_FAILED) echo "Validation failed" ;;
        $ERROR_RESOURCE_NOT_FOUND) echo "Resource not found" ;;
        $ERROR_CONFIG_INVALID) echo "Invalid configuration" ;;
        *) echo "Error code: $code" ;;
    esac
}

# Check if error is recoverable
is_error_recoverable() {
    local code=$1
    
    case $code in
        $ERROR_AWS_THROTTLED|$ERROR_NETWORK_ERROR|$ERROR_TIMEOUT|\
        $ERROR_INSUFFICIENT_CAPACITY|$ERROR_RESOURCE_BUSY)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Clear error state
clear_error_state() {
    LAST_ERROR_CODE=0
    LAST_ERROR_MESSAGE=""
    LAST_ERROR_CONTEXT=""
    LAST_ERROR_SOURCE=""
    LAST_ERROR_FUNCTION=""
    LAST_ERROR_LINE=0
    ERROR_RECOVERY_ATTEMPTED=false
    ERROR_RECOVERY_STRATEGY=""
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all functions
export -f init_error_handling
export -f handle_error
export -f throw_error
export -f handle_aws_error
export -f get_error_message
export -f is_error_recoverable
export -f clear_error_state

# Export for backward compatibility
export -f log_error_internal
export -f attempt_error_recovery

log_error_internal "INFO" "Unified error handling system loaded"