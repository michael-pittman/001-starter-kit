#!/bin/bash
# =============================================================================
# Enhanced Error Handling System
# Provides context-aware error handling and recovery
# =============================================================================

# Prevent multiple sourcing
[ -n "${_ERRORS_SH_LOADED:-}" ] && return 0
_ERRORS_SH_LOADED=1

# =============================================================================
# ERROR CONTEXT MANAGEMENT
# =============================================================================

# Error context stack
ERROR_CONTEXT_STACK=()
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/deployment-errors-$$.log}"

# Initialize error handling
initialize_error_handling() {
    # Set up error trap
    trap 'handle_error $? "$BASH_SOURCE" "$LINENO" "$FUNCNAME"' ERR
    
    # Create error log
    mkdir -p "$(dirname "$ERROR_LOG_FILE")"
    echo "=== Error Log Started: $(date) ===" > "$ERROR_LOG_FILE"
}

# Push error context
push_error_context() {
    local context="$1"
    ERROR_CONTEXT_STACK+=("$context")
}

# Pop error context
pop_error_context() {
    if [ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]; then
        # Bash 3.x compatible array manipulation
        local last_index=$((${#ERROR_CONTEXT_STACK[@]} - 1))
        
        # If this is the last element, just clear the array
        if [ $last_index -eq 0 ]; then
            ERROR_CONTEXT_STACK=()
        else
            # Build new array without the last element
            local new_stack=()
            local i
            for ((i=0; i<last_index; i++)); do
                new_stack+=("${ERROR_CONTEXT_STACK[$i]}")
            done
            # Only assign if we have elements
            if [ ${#new_stack[@]} -gt 0 ]; then
                ERROR_CONTEXT_STACK=("${new_stack[@]}")
            else
                ERROR_CONTEXT_STACK=()
            fi
        fi
    fi
}

# Get current error context
get_error_context() {
    if [ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]; then
        # Bash 3.x compatible - get last element
        local last_index=$((${#ERROR_CONTEXT_STACK[@]} - 1))
        echo "${ERROR_CONTEXT_STACK[$last_index]}"
    else
        echo "unknown"
    fi
}

# =============================================================================
# ERROR HANDLERS
# =============================================================================

# Main error handler
handle_error() {
    local exit_code=$1
    local source_file="${2:-unknown}"
    local line_number="${3:-0}"
    local function_name="${4:-main}"
    
    # Log error details
    log_error_details "$exit_code" "$source_file" "$line_number" "$function_name"
    
    # Execute recovery if available
    local recovery_function="recover_from_${function_name}_error"
    if type -t "$recovery_function" >/dev/null 2>&1; then
        echo "Attempting recovery using: $recovery_function" >&2
        if $recovery_function "$exit_code"; then
            echo "Recovery successful" >&2
            return 0
        fi
    fi
    
    # Default error handling
    echo "FATAL ERROR: No recovery available" >&2
    return "$exit_code"
}

# Log error details
log_error_details() {
    local exit_code=$1
    local source_file=$2
    local line_number=$3
    local function_name=$4
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get current context
    local context=$(get_error_context)
    
    # Build error message
    local error_msg=$(cat <<EOF
================================================================================
ERROR DETECTED
--------------------------------------------------------------------------------
Timestamp: $timestamp
Exit Code: $exit_code
Source: $source_file:$line_number
Function: $function_name
Context: $context
Stack Trace: ${ERROR_CONTEXT_STACK[*]}
--------------------------------------------------------------------------------
EOF
)
    
    # Log to file
    echo "$error_msg" >> "$ERROR_LOG_FILE"
    
    # Log to stderr
    echo "$error_msg" >&2
}

# =============================================================================
# EXECUTION WITH ERROR CONTEXT
# =============================================================================

# Execute command with error context
with_error_context() {
    local context="$1"
    shift
    
    push_error_context "$context"
    
    # Execute command
    local exit_code=0
    "$@" || exit_code=$?
    
    pop_error_context
    
    return $exit_code
}

# Try-catch style execution
try_catch() {
    local try_block="$1"
    local catch_block="${2:-}"
    local finally_block="${3:-}"
    
    local exit_code=0
    
    # Try block
    if ! eval "$try_block"; then
        exit_code=$?
        
        # Catch block
        if [ -n "$catch_block" ]; then
            eval "$catch_block"
        fi
    fi
    
    # Finally block
    if [ -n "$finally_block" ]; then
        eval "$finally_block"
    fi
    
    return $exit_code
}

# =============================================================================
# RECOVERY STRATEGIES
# =============================================================================

# Retry with exponential backoff
retry_with_backoff() {
    local max_attempts="${1:-3}"
    local base_delay="${2:-1}"
    shift 2
    local command=("$@")
    
    local attempt=1
    local delay=$base_delay
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts..." >&2
        
        if "${command[@]}"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "Command failed, waiting ${delay}s before retry..." >&2
            sleep "$delay"
            delay=$((delay * 2))
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "All $max_attempts attempts failed" >&2
    return 1
}

# =============================================================================
# ERROR TYPES
# =============================================================================

# Define common error types (avoid readonly for compatibility)
ERROR_INVALID_ARGUMENT=1
ERROR_MISSING_DEPENDENCY=2
ERROR_AWS_API=3
ERROR_NETWORK=4
ERROR_TIMEOUT=5
ERROR_RESOURCE_NOT_FOUND=6
ERROR_PERMISSION_DENIED=7
ERROR_QUOTA_EXCEEDED=8
ERROR_VALIDATION_FAILED=9

# Throw typed error
throw_error() {
    local error_type=$1
    local error_message="$2"
    
    case $error_type in
        $ERROR_INVALID_ARGUMENT)
            echo "ERROR: Invalid Argument - $error_message" >&2
            ;;
        $ERROR_MISSING_DEPENDENCY)
            echo "ERROR: Missing Dependency - $error_message" >&2
            ;;
        $ERROR_AWS_API)
            echo "ERROR: AWS API Error - $error_message" >&2
            ;;
        $ERROR_NETWORK)
            echo "ERROR: Network Error - $error_message" >&2
            ;;
        $ERROR_TIMEOUT)
            echo "ERROR: Timeout - $error_message" >&2
            ;;
        $ERROR_RESOURCE_NOT_FOUND)
            echo "ERROR: Resource Not Found - $error_message" >&2
            ;;
        $ERROR_PERMISSION_DENIED)
            echo "ERROR: Permission Denied - $error_message" >&2
            ;;
        $ERROR_QUOTA_EXCEEDED)
            echo "ERROR: Quota Exceeded - $error_message" >&2
            ;;
        $ERROR_VALIDATION_FAILED)
            echo "ERROR: Validation Failed - $error_message" >&2
            ;;
        *)
            echo "ERROR: Unknown Error ($error_type) - $error_message" >&2
            ;;
    esac
    
    return $error_type
}

# =============================================================================
# VALIDATION HELPERS
# =============================================================================

# Validate required command
require_command() {
    local command="$1"
    local package="${2:-$command}"
    
    if ! command -v "$command" &> /dev/null; then
        throw_error $ERROR_MISSING_DEPENDENCY "Command '$command' not found. Please install $package."
    fi
}

# Validate required variable
require_variable() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    
    if [ -z "$var_value" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "Required variable '$var_name' is not set"
    fi
}

# Validate file exists
require_file() {
    local file_path="$1"
    
    if [ ! -f "$file_path" ]; then
        throw_error $ERROR_RESOURCE_NOT_FOUND "Required file not found: $file_path"
    fi
}

# =============================================================================
# AWS ERROR HANDLING
# =============================================================================

# Handle AWS CLI errors
handle_aws_error() {
    local exit_code=$1
    local output="$2"
    
    # Parse common AWS errors
    if [[ "$output" =~ "UnauthorizedOperation" ]]; then
        throw_error $ERROR_PERMISSION_DENIED "AWS operation not authorized. Check IAM permissions."
    elif [[ "$output" =~ "RequestLimitExceeded" ]]; then
        echo "AWS rate limit exceeded, will retry with backoff..." >&2
        return $ERROR_AWS_API
    elif [[ "$output" =~ "ServiceQuotaExceededException" ]]; then
        throw_error $ERROR_QUOTA_EXCEEDED "AWS service quota exceeded. Request quota increase."
    elif [[ "$output" =~ "InvalidParameterValue" ]]; then
        throw_error $ERROR_INVALID_ARGUMENT "Invalid AWS parameter: $output"
    else
        throw_error $ERROR_AWS_API "AWS API error: $output"
    fi
}

# Execute AWS command with error handling
aws_with_error_handling() {
    local output
    local exit_code
    
    output=$(aws "$@" 2>&1) || exit_code=$?
    
    if [ -n "${exit_code:-}" ] && [ "$exit_code" -ne 0 ]; then
        handle_aws_error "$exit_code" "$output"
        return $exit_code
    fi
    
    echo "$output"
    return 0
}

# =============================================================================
# CLEANUP ON ERROR
# =============================================================================

# Register cleanup handler
register_cleanup_handler() {
    local handler="$1"
    
    # Add to cleanup handlers
    CLEANUP_HANDLERS+=("$handler")
}

# Execute cleanup handlers
execute_cleanup_handlers() {
    echo "Executing cleanup handlers..." >&2
    
    # Check if array has elements to avoid bash 3.x issues with empty arrays
    if [ ${#CLEANUP_HANDLERS[@]} -gt 0 ]; then
        for handler in "${CLEANUP_HANDLERS[@]}"; do
            echo "Running cleanup: $handler" >&2
            $handler || echo "Cleanup handler failed: $handler" >&2
        done
    fi
    return 0
}

# Initialize cleanup handlers array
CLEANUP_HANDLERS=()

# Set up cleanup trap
trap 'execute_cleanup_handlers' EXIT

# Initialize error handling on source
initialize_error_handling