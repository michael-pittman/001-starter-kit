#!/usr/bin/env bash
# =============================================================================
# Core Errors Module
# Unified error handling with structured error types and recovery mechanisms
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CORE_ERRORS_SH_LOADED:-}" ] && return 0
_CORE_ERRORS_SH_LOADED=1

# =============================================================================
# ERROR CODES AND CATEGORIES
# =============================================================================

# Success
ERROR_SUCCESS=0

# General errors (1-99)
ERROR_GENERAL=1
ERROR_INVALID_ARGUMENT=2
ERROR_MISSING_DEPENDENCY=3
ERROR_PERMISSION_DENIED=4
ERROR_FILE_NOT_FOUND=5
ERROR_TIMEOUT=6
ERROR_INTERRUPTED=7

# Configuration errors (100-199)
ERROR_CONFIG_INVALID=100
ERROR_CONFIG_MISSING=101
ERROR_CONFIG_PARSE=102
ERROR_CONFIG_VALIDATION=103
ERROR_CONFIG_INVALID_VARIABLE=104
ERROR_CONFIG_MISSING_PARAMETER=105

# AWS errors (200-299)
ERROR_AWS_CREDENTIALS=200
ERROR_AWS_PERMISSION=201
ERROR_AWS_QUOTA_EXCEEDED=202
ERROR_AWS_RESOURCE_NOT_FOUND=203
ERROR_AWS_RESOURCE_EXISTS=204
ERROR_AWS_API_ERROR=205
ERROR_AWS_REGION_INVALID=206
ERROR_AWS_PROFILE_INVALID=207

# EC2 specific errors (250-299)
ERROR_EC2_INSUFFICIENT_CAPACITY=250
ERROR_EC2_INSTANCE_LIMIT_EXCEEDED=251
ERROR_EC2_SPOT_BID_TOO_LOW=252

# Deployment errors (300-399)
ERROR_DEPLOYMENT_FAILED=300
ERROR_DEPLOYMENT_TIMEOUT=301
ERROR_DEPLOYMENT_ROLLBACK=302
ERROR_DEPLOYMENT_VALIDATION=303
ERROR_DEPLOYMENT_STATE=304
ERROR_DEPLOYMENT_CONFLICT=305
ERROR_DEPLOYMENT_DEPENDENCY_NOT_READY=306

# Infrastructure errors (400-499)
ERROR_VPC_CREATION=400
ERROR_SUBNET_CREATION=401
ERROR_SECURITY_GROUP_CREATION=402
ERROR_INSTANCE_CREATION=403
ERROR_LOAD_BALANCER_CREATION=404
ERROR_AUTO_SCALING_CREATION=405
ERROR_EFS_CREATION=406
ERROR_CLOUDFRONT_CREATION=407

# Validation errors (500-599)
ERROR_VALIDATION_FAILED=500
ERROR_VALIDATION_INPUT=501
ERROR_VALIDATION_FORMAT=502
ERROR_VALIDATION_RANGE=503
ERROR_VALIDATION_REQUIRED=504

# Network errors (600-699)
ERROR_NETWORK_TIMEOUT=600
ERROR_NETWORK_CONNECTION=601
ERROR_NETWORK_DNS=602
ERROR_NETWORK_FIREWALL=603
ERROR_NETWORK_VPC_NOT_FOUND=604
ERROR_NETWORK_SECURITY_GROUP_INVALID=605

# =============================================================================
# ERROR SEVERITY AND RECOVERY
# =============================================================================

# Error severity levels
readonly ERROR_SEVERITY_INFO=0
readonly ERROR_SEVERITY_WARNING=1
readonly ERROR_SEVERITY_ERROR=2
readonly ERROR_SEVERITY_CRITICAL=3

# Error categories
readonly ERROR_CAT_GENERAL="general"
readonly ERROR_CAT_VALIDATION="validation"
readonly ERROR_CAT_INFRASTRUCTURE="infrastructure"
readonly ERROR_CAT_NETWORK="network"
readonly ERROR_CAT_AUTHENTICATION="authentication"
readonly ERROR_CAT_AUTHORIZATION="authorization"
readonly ERROR_CAT_CAPACITY="capacity"
readonly ERROR_CAT_TIMEOUT="timeout"
readonly ERROR_CAT_DEPENDENCY="dependency"
readonly ERROR_CAT_CONFIGURATION="configuration"
readonly ERROR_CAT_AWS="aws"
readonly ERROR_CAT_DEPLOYMENT="deployment"

# Error recovery strategies
readonly RECOVERY_RETRY="retry"
readonly RECOVERY_FALLBACK="fallback"
readonly RECOVERY_SKIP="skip"
readonly RECOVERY_ABORT="abort"
readonly RECOVERY_MANUAL="manual"

# Color codes for logging (avoid redeclaration)
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly NC='\033[0m' # No Color
fi

# =============================================================================
# ERROR TRACKING AND STATE
# =============================================================================

# Initialize ERROR_LOG_FILE if not set
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/deployment-errors.json}"

# Error context stack for better debugging
declare -a ERROR_CONTEXT_STACK=()

# Function-based error data management for bash 3.x compatibility
get_error_data() {
    local key="$1"
    local type="$2"
    local varname="ERROR_${type}_${key}"
    echo "${!varname:-}"
}

set_error_data() {
    local key="$1"
    local type="$2"
    local value="$3"
    local varname="ERROR_${type}_${key}"
    local keys_var="ERROR_${type}_KEYS"
    
    # Export the value
    export "${varname}=${value}"
    
    # Add to keys list if not already present
    local current_keys
    eval "current_keys=\"\${${keys_var}:-}\""
    if [[ " $current_keys " != *" $key "* ]]; then
        export "${keys_var}=${current_keys} ${key}"
    fi
}

get_error_keys() {
    local type="$1"
    local keys_var="ERROR_${type}_KEYS"
    echo "${!keys_var}"
}

# Initialize error tracking
initialize_error_tracking() {
    cat > "$ERROR_LOG_FILE" <<EOF
{
    "session_id": "$$",
    "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "errors": []
}
EOF
}

# =============================================================================
# ERROR MESSAGES
# =============================================================================

# Error message mapping function
get_error_message() {
    local error_code="$1"
    
    case "$error_code" in
        # General errors
        "$ERROR_GENERAL") echo "General error occurred" ;;
        "$ERROR_INVALID_ARGUMENT") echo "Invalid argument provided" ;;
        "$ERROR_MISSING_DEPENDENCY") echo "Required dependency not found" ;;
        "$ERROR_PERMISSION_DENIED") echo "Permission denied" ;;
        "$ERROR_FILE_NOT_FOUND") echo "File not found" ;;
        "$ERROR_TIMEOUT") echo "Operation timed out" ;;
        "$ERROR_INTERRUPTED") echo "Operation interrupted" ;;
        
        # Configuration errors
        "$ERROR_CONFIG_INVALID") echo "Invalid configuration" ;;
        "$ERROR_CONFIG_MISSING") echo "Configuration file missing" ;;
        "$ERROR_CONFIG_PARSE") echo "Configuration parse error" ;;
        "$ERROR_CONFIG_VALIDATION") echo "Configuration validation failed" ;;
        "$ERROR_CONFIG_INVALID_VARIABLE") echo "Invalid variable value" ;;
        "$ERROR_CONFIG_MISSING_PARAMETER") echo "Missing required parameter" ;;
        
        # AWS errors
        "$ERROR_AWS_CREDENTIALS") echo "AWS credentials not found or invalid" ;;
        "$ERROR_AWS_PERMISSION") echo "AWS permission denied" ;;
        "$ERROR_AWS_QUOTA_EXCEEDED") echo "AWS service quota exceeded" ;;
        "$ERROR_AWS_RESOURCE_NOT_FOUND") echo "AWS resource not found" ;;
        "$ERROR_AWS_RESOURCE_EXISTS") echo "AWS resource already exists" ;;
        "$ERROR_AWS_API_ERROR") echo "AWS API error" ;;
        "$ERROR_AWS_REGION_INVALID") echo "Invalid AWS region" ;;
        "$ERROR_AWS_PROFILE_INVALID") echo "Invalid AWS profile" ;;
        
        # EC2 specific errors
        "$ERROR_EC2_INSUFFICIENT_CAPACITY") echo "Insufficient EC2 capacity" ;;
        "$ERROR_EC2_INSTANCE_LIMIT_EXCEEDED") echo "EC2 instance limit exceeded" ;;
        "$ERROR_EC2_SPOT_BID_TOO_LOW") echo "Spot bid price too low" ;;
        
        # Deployment errors
        "$ERROR_DEPLOYMENT_FAILED") echo "Deployment failed" ;;
        "$ERROR_DEPLOYMENT_TIMEOUT") echo "Deployment timed out" ;;
        "$ERROR_DEPLOYMENT_ROLLBACK") echo "Deployment rollback failed" ;;
        "$ERROR_DEPLOYMENT_VALIDATION") echo "Deployment validation failed" ;;
        "$ERROR_DEPLOYMENT_STATE") echo "Invalid deployment state" ;;
        "$ERROR_DEPLOYMENT_CONFLICT") echo "Deployment conflict detected" ;;
        "$ERROR_DEPLOYMENT_DEPENDENCY_NOT_READY") echo "Deployment dependency not ready" ;;
        
        # Infrastructure errors
        "$ERROR_VPC_CREATION") echo "VPC creation failed" ;;
        "$ERROR_SUBNET_CREATION") echo "Subnet creation failed" ;;
        "$ERROR_SECURITY_GROUP_CREATION") echo "Security group creation failed" ;;
        "$ERROR_INSTANCE_CREATION") echo "Instance creation failed" ;;
        "$ERROR_LOAD_BALANCER_CREATION") echo "Load balancer creation failed" ;;
        "$ERROR_AUTO_SCALING_CREATION") echo "Auto scaling group creation failed" ;;
        "$ERROR_EFS_CREATION") echo "EFS creation failed" ;;
        "$ERROR_CLOUDFRONT_CREATION") echo "CloudFront creation failed" ;;
        
        # Validation errors
        "$ERROR_VALIDATION_FAILED") echo "Validation failed" ;;
        "$ERROR_VALIDATION_INPUT") echo "Invalid input" ;;
        "$ERROR_VALIDATION_FORMAT") echo "Invalid format" ;;
        "$ERROR_VALIDATION_RANGE") echo "Value out of range" ;;
        "$ERROR_VALIDATION_REQUIRED") echo "Required field missing" ;;
        
        # Network errors
        "$ERROR_NETWORK_TIMEOUT") echo "Network timeout" ;;
        "$ERROR_NETWORK_CONNECTION") echo "Network connection failed" ;;
        "$ERROR_NETWORK_DNS") echo "DNS resolution failed" ;;
        "$ERROR_NETWORK_FIREWALL") echo "Firewall blocked connection" ;;
        "$ERROR_NETWORK_VPC_NOT_FOUND") echo "VPC not found" ;;
        "$ERROR_NETWORK_SECURITY_GROUP_INVALID") echo "Invalid security group" ;;
        
        *) echo "Unknown error" ;;
    esac
}

# =============================================================================
# ERROR CONTEXT MANAGEMENT
# =============================================================================

# Push error context
push_error_context() {
    local context="$1"
    ERROR_CONTEXT_STACK+=("$context")
}

# Pop error context
pop_error_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        unset 'ERROR_CONTEXT_STACK[-1]'
    fi
}

# Get current error context
get_error_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        echo "${ERROR_CONTEXT_STACK[-1]}"
    else
        echo ""
    fi
}

# Execute with error context
with_error_context() {
    local context="$1"
    shift
    
    push_error_context "$context"
    local result=0
    "$@" || result=$?
    pop_error_context
    
    return $result
}

# =============================================================================
# ERROR HANDLING FUNCTIONS
# =============================================================================

# Set error code
set_error() {
    local error_code="$1"
    local message="${2:-}"
    
    # Set the error code
    export LAST_ERROR_CODE="$error_code"
    
    # Set error message
    if [[ -n "$message" ]]; then
        export LAST_ERROR_MESSAGE="$message"
    else
        export LAST_ERROR_MESSAGE="$(get_error_message "$error_code")"
    fi
    
    # Set error timestamp
    export LAST_ERROR_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Set error context
    export LAST_ERROR_CONTEXT="$(get_error_context)"
    
    # Log the error
    log_error "Error $error_code: ${LAST_ERROR_MESSAGE}" "ERROR_HANDLING"
}

# Throw error with structured logging
throw_error() {
    local error_code="$1"
    local error_message="${2:-$(get_error_message "$error_code")}"
    local error_category="${3:-$(get_error_category "$error_code")}"
    local severity="${4:-$ERROR_SEVERITY_ERROR}"
    local recovery_strategy="${5:-$(get_default_recovery_strategy "$error_code")}"
    
    # Set error state
    set_error "$error_code" "$error_message"
    
    # Log structured error
    log_structured_error "$error_code" "$error_message" "$error_category" "$severity" "$(get_error_context)" "$recovery_strategy"
    
    # Return error code
    return "$error_code"
}

# Log structured error
log_structured_error() {
    local error_code="$1"
    local error_message="$2"
    local error_category="${3:-unknown}"
    local severity="${4:-$ERROR_SEVERITY_ERROR}"
    local context="${5:-}"
    local recovery_strategy="${6:-$RECOVERY_ABORT}"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local severity_name
    
    case "$severity" in
        $ERROR_SEVERITY_INFO) severity_name="INFO" ;;
        $ERROR_SEVERITY_WARNING) severity_name="WARNING" ;;
        $ERROR_SEVERITY_ERROR) severity_name="ERROR" ;;
        $ERROR_SEVERITY_CRITICAL) severity_name="CRITICAL" ;;
        *) severity_name="UNKNOWN" ;;
    esac
    
    # Update error count
    local current_count="$(get_error_data "$error_code" "COUNT")"
    current_count="${current_count:-0}"
    set_error_data "$error_code" "COUNT" "$((current_count + 1))"
    
    # Store recovery strategy
    set_error_data "$error_code" "RECOVERY_STRATEGIES" "$recovery_strategy"
    
    # Log to console with color
    local color
    case "$severity" in
        $ERROR_SEVERITY_INFO) color="$BLUE" ;;
        $ERROR_SEVERITY_WARNING) color="$YELLOW" ;;
        $ERROR_SEVERITY_ERROR) color="$RED" ;;
        $ERROR_SEVERITY_CRITICAL) color="$PURPLE" ;;
        *) color="$NC" ;;
    esac
    
    echo -e "${color}[$severity_name]${NC} [$error_code] $error_message" >&2
    if [[ -n "$context" ]]; then
        echo -e "${color}  Context:${NC} $context" >&2
    fi
    echo -e "${color}  Recovery:${NC} $recovery_strategy" >&2
    
    # Append to structured log if jq is available
    if command -v jq >/dev/null 2>&1 && [[ -f "$ERROR_LOG_FILE" ]]; then
        local temp_file=$(mktemp)
        jq --arg code "$error_code" \
           --arg message "$error_message" \
           --arg category "$error_category" \
           --arg severity "$severity_name" \
           --arg timestamp "$timestamp" \
           --arg context "$context" \
           --arg recovery "$recovery_strategy" \
           '.errors += [{
               "code": $code,
               "message": $message,
               "category": $category,
               "severity": $severity,
               "timestamp": $timestamp,
               "context": $context,
               "recovery_strategy": $recovery,
               "count": 1
           }]' "$ERROR_LOG_FILE" > "$temp_file" && \
        mv "$temp_file" "$ERROR_LOG_FILE"
    fi
}

# Get last error
get_last_error() {
    echo "Code: ${LAST_ERROR_CODE:-0}"
    echo "Message: ${LAST_ERROR_MESSAGE:-No error}"
    echo "Timestamp: ${LAST_ERROR_TIMESTAMP:-}"
    echo "Context: ${LAST_ERROR_CONTEXT:-}"
}

# Clear last error
clear_error() {
    unset LAST_ERROR_CODE
    unset LAST_ERROR_MESSAGE
    unset LAST_ERROR_TIMESTAMP
    unset LAST_ERROR_CONTEXT
}

# Check if error occurred
has_error() {
    [[ -n "${LAST_ERROR_CODE:-}" && "${LAST_ERROR_CODE:-0}" -ne 0 ]]
}

# =============================================================================
# ERROR RECOVERY FUNCTIONS
# =============================================================================

# Get default recovery strategy for error code
get_default_recovery_strategy() {
    local error_code="$1"
    
    case "$error_code" in
        # Retryable errors
        $ERROR_TIMEOUT|$ERROR_NETWORK_TIMEOUT|$ERROR_EC2_INSUFFICIENT_CAPACITY|$ERROR_DEPLOYMENT_DEPENDENCY_NOT_READY)
            echo "$RECOVERY_RETRY"
            ;;
        # Fallback errors
        $ERROR_AWS_RESOURCE_NOT_FOUND|$ERROR_NETWORK_VPC_NOT_FOUND|$ERROR_EC2_SPOT_BID_TOO_LOW)
            echo "$RECOVERY_FALLBACK"
            ;;
        # Skip errors
        $ERROR_AWS_RESOURCE_EXISTS)
            echo "$RECOVERY_SKIP"
            ;;
        # Manual intervention required
        $ERROR_AWS_CREDENTIALS|$ERROR_AWS_PERMISSION|$ERROR_PERMISSION_DENIED|$ERROR_EC2_INSTANCE_LIMIT_EXCEEDED)
            echo "$RECOVERY_MANUAL"
            ;;
        # Default to abort
        *)
            echo "$RECOVERY_ABORT"
            ;;
    esac
}

# Retry function with exponential backoff
retry_with_backoff() {
    local command="$1"
    local max_attempts="${2:-3}"
    local base_delay="${3:-1}"
    local max_delay="${4:-60}"
    local description="${5:-Command}"
    
    local attempt=1
    local delay=$base_delay
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: $description" "RETRY"
        
        if eval "$command"; then
            log_info "Success on attempt $attempt: $description" "RETRY"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Failed after $max_attempts attempts: $description" "RETRY"
            return 1
        fi
        
        log_warn "Attempt $attempt failed, retrying in ${delay}s: $description" "RETRY"
        sleep "$delay"
        
        # Exponential backoff with max delay
        delay=$((delay * 2))
        if [[ $delay -gt $max_delay ]]; then
            delay=$max_delay
        fi
        
        ((attempt++))
    done
}

# Retry AWS command
retry_aws_command() {
    local aws_command="$1"
    local max_attempts="${2:-3}"
    local description="${3:-AWS command}"
    
    # AWS specific retry logic
    local command_with_retry="aws $aws_command"
    
    retry_with_backoff "$command_with_retry" "$max_attempts" 2 30 "$description"
}

# =============================================================================
# ERROR CLASSIFICATION
# =============================================================================

# Get error category
get_error_category() {
    local error_code="$1"
    
    if [[ $error_code -ge 1 && $error_code -lt 100 ]]; then
        echo "$ERROR_CAT_GENERAL"
    elif [[ $error_code -ge 100 && $error_code -lt 200 ]]; then
        echo "$ERROR_CAT_CONFIGURATION"
    elif [[ $error_code -ge 200 && $error_code -lt 250 ]]; then
        echo "$ERROR_CAT_AWS"
    elif [[ $error_code -ge 250 && $error_code -lt 300 ]]; then
        echo "$ERROR_CAT_CAPACITY"
    elif [[ $error_code -ge 300 && $error_code -lt 400 ]]; then
        echo "$ERROR_CAT_DEPLOYMENT"
    elif [[ $error_code -ge 400 && $error_code -lt 500 ]]; then
        echo "$ERROR_CAT_INFRASTRUCTURE"
    elif [[ $error_code -ge 500 && $error_code -lt 600 ]]; then
        echo "$ERROR_CAT_VALIDATION"
    elif [[ $error_code -ge 600 && $error_code -lt 700 ]]; then
        echo "$ERROR_CAT_NETWORK"
    else
        echo "general"
    fi
}

# Classify AWS error
classify_aws_error() {
    local error_message="$1"
    local error_code="$2"
    
    case "$error_code" in
        "AccessDenied"|"UnauthorizedOperation")
            echo "$ERROR_AWS_PERMISSION"
            ;;
        "QuotaExceeded"|"ServiceQuotaExceededException")
            echo "$ERROR_AWS_QUOTA_EXCEEDED"
            ;;
        "NoSuchEntity"|"ResourceNotFoundException")
            echo "$ERROR_AWS_RESOURCE_NOT_FOUND"
            ;;
        "ResourceAlreadyExistsException"|"AlreadyExistsException")
            echo "$ERROR_AWS_RESOURCE_EXISTS"
            ;;
        "InvalidParameterValue"|"ValidationException")
            echo "$ERROR_VALIDATION_FAILED"
            ;;
        "ThrottlingException"|"TooManyRequestsException")
            echo "$ERROR_AWS_API_ERROR"
            ;;
        "InsufficientInstanceCapacity")
            echo "$ERROR_EC2_INSUFFICIENT_CAPACITY"
            ;;
        "InstanceLimitExceeded")
            echo "$ERROR_EC2_INSTANCE_LIMIT_EXCEEDED"
            ;;
        *)
            echo "$ERROR_AWS_API_ERROR"
            ;;
    esac
}

# Classify deployment error
classify_deployment_error() {
    local error_message="$1"
    local context="$2"
    
    case "$context" in
        "vpc")
            echo "$ERROR_VPC_CREATION"
            ;;
        "subnet")
            echo "$ERROR_SUBNET_CREATION"
            ;;
        "security-group")
            echo "$ERROR_SECURITY_GROUP_CREATION"
            ;;
        "instance")
            echo "$ERROR_INSTANCE_CREATION"
            ;;
        "load-balancer")
            echo "$ERROR_LOAD_BALANCER_CREATION"
            ;;
        "auto-scaling")
            echo "$ERROR_AUTO_SCALING_CREATION"
            ;;
        "efs")
            echo "$ERROR_EFS_CREATION"
            ;;
        "cloudfront")
            echo "$ERROR_CLOUDFRONT_CREATION"
            ;;
        "rollback")
            echo "$ERROR_DEPLOYMENT_ROLLBACK"
            ;;
        "validation")
            echo "$ERROR_DEPLOYMENT_VALIDATION"
            ;;
        *)
            echo "$ERROR_DEPLOYMENT_FAILED"
            ;;
    esac
}

# =============================================================================
# ERROR RECOVERY STRATEGIES
# =============================================================================

# Handle AWS error
handle_aws_error() {
    local error_code="$1"
    local error_message="$2"
    local context="$3"
    
    local classified_error
    classified_error=$(classify_aws_error "$error_message" "$error_code")
    
    local recovery_strategy
    recovery_strategy=$(get_default_recovery_strategy "$classified_error")
    
    throw_error "$classified_error" "$error_message" "$ERROR_CAT_AWS" "$ERROR_SEVERITY_ERROR" "$recovery_strategy"
}

# Handle deployment error
handle_deployment_error() {
    local error_code="$1"
    local error_message="$2"
    local context="$3"
    
    local classified_error
    classified_error=$(classify_deployment_error "$error_message" "$context")
    
    local recovery_strategy
    recovery_strategy=$(get_default_recovery_strategy "$classified_error")
    
    throw_error "$classified_error" "$error_message" "$ERROR_CAT_DEPLOYMENT" "$ERROR_SEVERITY_ERROR" "$recovery_strategy"
    
    # Trigger rollback if needed
    if [[ "$classified_error" == "$ERROR_DEPLOYMENT_ROLLBACK" ]]; then
        trigger_rollback
    fi
}

# =============================================================================
# PREDEFINED ERROR FUNCTIONS
# =============================================================================

# EC2 Instance Errors
error_ec2_insufficient_capacity() {
    local instance_type="$1"
    local region="$2"
    local context="Instance type: $instance_type, Region: $region"
    
    with_error_context "$context" \
        throw_error "$ERROR_EC2_INSUFFICIENT_CAPACITY" \
            "Insufficient capacity for instance type $instance_type in region $region" \
            "$ERROR_CAT_CAPACITY" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_FALLBACK"
}

error_ec2_instance_limit_exceeded() {
    local instance_type="$1"
    local context="Instance type: $instance_type"
    
    with_error_context "$context" \
        throw_error "$ERROR_EC2_INSTANCE_LIMIT_EXCEEDED" \
            "Instance limit exceeded for type $instance_type" \
            "$ERROR_CAT_CAPACITY" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_MANUAL"
}

error_ec2_spot_bid_too_low() {
    local bid_price="$1"
    local current_price="$2"
    local context="Bid: $bid_price, Current: $current_price"
    
    with_error_context "$context" \
        throw_error "$ERROR_EC2_SPOT_BID_TOO_LOW" \
            "Spot bid price too low: $bid_price < $current_price" \
            "$ERROR_CAT_CAPACITY" \
            "$ERROR_SEVERITY_WARNING" \
            "$RECOVERY_RETRY"
}

# Network Errors
error_network_vpc_not_found() {
    local vpc_id="$1"
    local context="VPC ID: $vpc_id"
    
    with_error_context "$context" \
        throw_error "$ERROR_NETWORK_VPC_NOT_FOUND" \
            "VPC not found: $vpc_id" \
            "$ERROR_CAT_NETWORK" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_FALLBACK"
}

error_network_security_group_invalid() {
    local sg_id="$1"
    local context="Security Group ID: $sg_id"
    
    with_error_context "$context" \
        throw_error "$ERROR_NETWORK_SECURITY_GROUP_INVALID" \
            "Invalid security group: $sg_id" \
            "$ERROR_CAT_NETWORK" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_RETRY"
}

# Authentication/Authorization Errors
error_auth_invalid_credentials() {
    local service="$1"
    local context="Service: $service"
    
    with_error_context "$context" \
        throw_error "$ERROR_AWS_CREDENTIALS" \
            "Invalid AWS credentials for $service" \
            "$ERROR_CAT_AUTHENTICATION" \
            "$ERROR_SEVERITY_CRITICAL" \
            "$RECOVERY_MANUAL"
}

error_auth_insufficient_permissions() {
    local action="$1"
    local resource="$2"
    local context="Action: $action, Resource: $resource"
    
    with_error_context "$context" \
        throw_error "$ERROR_AWS_PERMISSION" \
            "Insufficient permissions for $action on $resource" \
            "$ERROR_CAT_AUTHORIZATION" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_MANUAL"
}

# Configuration Errors
error_config_invalid_variable() {
    local variable="$1"
    local value="$2"
    local context="Variable: $variable, Value: $value"
    
    with_error_context "$context" \
        throw_error "$ERROR_CONFIG_INVALID_VARIABLE" \
            "Invalid variable value: $variable=$value" \
            "$ERROR_CAT_CONFIGURATION" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_ABORT"
}

error_config_missing_parameter() {
    local parameter="$1"
    local context="Parameter: $parameter"
    
    with_error_context "$context" \
        throw_error "$ERROR_CONFIG_MISSING_PARAMETER" \
            "Missing required parameter: $parameter" \
            "$ERROR_CAT_CONFIGURATION" \
            "$ERROR_SEVERITY_ERROR" \
            "$RECOVERY_ABORT"
}

# Validation Errors

# Timeout Errors
error_timeout_operation() {
    local operation="$1"
    local timeout="$2"
    local context="Operation: $operation, Timeout: ${timeout}s"
    
    with_error_context "$context" \
        throw_error "$ERROR_TIMEOUT" \
            "Operation timed out: $operation (${timeout}s)" \
            "$ERROR_CAT_TIMEOUT" \
            "$ERROR_SEVERITY_WARNING" \
            "$RECOVERY_RETRY"
}

# Dependency Errors
error_dependency_not_ready() {
    local dependency="$1"
    local dependent="$2"
    local context="Dependency: $dependency, Dependent: $dependent"
    
    with_error_context "$context" \
        throw_error "$ERROR_DEPLOYMENT_DEPENDENCY_NOT_READY" \
            "Dependency not ready: $dependency for $dependent" \
            "$ERROR_CAT_DEPENDENCY" \
            "$ERROR_SEVERITY_WARNING" \
            "$RECOVERY_RETRY"
}

# =============================================================================
# ERROR ANALYSIS AND REPORTING
# =============================================================================

# Get error count
get_error_count() {
    local error_code="$1"
    local count="$(get_error_data "$error_code" "COUNT")"
    echo "${count:-0}"
}

# Get recovery strategy
get_recovery_strategy() {
    local error_code="$1"
    local strategy="$(get_error_data "$error_code" "RECOVERY_STRATEGIES")"
    echo "${strategy:-$RECOVERY_ABORT}"
}

# Should retry error
should_retry_error() {
    local error_code="$1"
    local max_retries="${2:-3}"
    
    local strategy=$(get_recovery_strategy "$error_code")
    local count=$(get_error_count "$error_code")
    
    [[ "$strategy" == "$RECOVERY_RETRY" ]] && [[ "$count" -lt "$max_retries" ]]
}

# Check if error is recoverable
is_recoverable_error() {
    local error_code="$1"
    local strategy=$(get_recovery_strategy "$error_code")
    
    case "$strategy" in
        $RECOVERY_RETRY|$RECOVERY_FALLBACK|$RECOVERY_SKIP)
            return 0  # Recoverable
            ;;
        $RECOVERY_ABORT|$RECOVERY_MANUAL)
            return 1  # Not recoverable
            ;;
        *)
            return 1  # Default to not recoverable
            ;;
    esac
}

# Print error summary
print_error_summary() {
    echo "=== Error Summary ==="
    
    local error_keys="$(get_error_keys "COUNT")"
    if [[ -z "$error_keys" ]]; then
        echo "No errors recorded"
        return
    fi
    
    for error_code in $error_keys; do
        if [[ -n "$error_code" ]]; then
            local count="$(get_error_data "$error_code" "COUNT")"
            local strategy="$(get_error_data "$error_code" "RECOVERY_STRATEGIES")"
            echo "  $error_code: $count occurrences (strategy: $strategy)"
        fi
    done
    
    echo "===================="
}

# Generate error report
generate_error_report() {
    local report_file="${1:-}"
    
    if [[ -z "$report_file" ]]; then
        # Use a writable directory for error reports
        local report_dir="${LOG_DIR:-/tmp}"
        if [[ ! -w "$report_dir" ]]; then
            report_dir="/tmp"
        fi
        report_file="${report_dir}/error-report-$(date +%Y%m%d-%H%M%S).json"
    fi
    
    # Create report directory
    local report_dir
    report_dir=$(dirname "$report_file")
    if [[ ! -d "$report_dir" ]]; then
        mkdir -p "$report_dir" 2>/dev/null || {
            log_error "Failed to create report directory: $report_dir" "ERROR_REPORTING"
            return 1
        }
    fi
    
    # Check if we can write to the report file
    if [[ ! -w "$report_dir" ]]; then
        log_error "Cannot write to report directory: $report_dir" "ERROR_REPORTING"
        return 1
    fi
    
    # If structured log exists, use it as base
    if [[ -f "$ERROR_LOG_FILE" ]]; then
        cp "$ERROR_LOG_FILE" "$report_file"
    else
        # Generate JSON report from scratch
        cat > "$report_file" << EOF
{
    "error_report": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "stack_name": "$(get_variable STACK_NAME 2>/dev/null || echo 'unknown')",
        "aws_region": "$(get_variable AWS_REGION 2>/dev/null || echo 'unknown')",
        "deployment_type": "$(get_variable DEPLOYMENT_TYPE 2>/dev/null || echo 'unknown')",
        "last_error": {
            "code": "${LAST_ERROR_CODE:-0}",
            "message": "${LAST_ERROR_MESSAGE:-}",
            "timestamp": "${LAST_ERROR_TIMESTAMP:-}",
            "context": "${LAST_ERROR_CONTEXT:-}"
        },
        "system_info": {
            "script": "${SCRIPT_NAME:-unknown}",
            "pid": "$$",
            "user": "$(whoami)",
            "hostname": "$(hostname)",
            "os": "$(uname -s)",
        },
        "aws_info": {
            "profile": "$(get_variable AWS_PROFILE 2>/dev/null || echo 'unknown')",
            "region": "$(get_variable AWS_REGION 2>/dev/null || echo 'unknown')",
            "account_id": "$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'unknown')"
        }
    }
}
EOF
    fi
    
    if [[ $? -eq 0 ]]; then
        log_info "Error report generated: $report_file" "ERROR_REPORTING"
        echo "$report_file"
        return 0
    else
        log_error "Failed to generate error report: $report_file" "ERROR_REPORTING"
        return 1
    fi
}

# Send error notification
send_error_notification() {
    local error_code="${1:-$LAST_ERROR_CODE}"
    local error_message="${2:-$LAST_ERROR_MESSAGE}"
    local context="${3:-}"
    
    # Generate error report
    local report_file
    report_file=$(generate_error_report)
    
    # Log notification
    log_error "Error notification: Code=$error_code, Message=$error_message" "ERROR_NOTIFICATION"
    
    # Send notifications if webhook URL is configured
    local webhook_url="${NOTIFICATION_WEBHOOK_URL:-}"
    if [[ -n "$webhook_url" ]]; then
        # Send notification via webhook (supports Slack, Discord, etc.)
        local notification_payload
        notification_payload=$(cat <<EOF
{
    "error_code": "$error_code",
    "error_message": "$error_message",
    "context": "$context",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "stack_name": "${STACK_NAME:-unknown}",
    "region": "${AWS_REGION:-unknown}",
    "report_file": "$report_file"
}
EOF
        )
        
        # Send notification asynchronously to avoid blocking
        if command -v curl >/dev/null 2>&1; then
            (curl -s -X POST "$webhook_url" \
                -H "Content-Type: application/json" \
                -d "$notification_payload" \
                >/dev/null 2>&1 || true) &
            log_debug "Sent error notification to webhook" "ERROR_NOTIFICATION"
        fi
    fi
    
    # Write to system log if available
    if command -v logger >/dev/null 2>&1; then
        logger -t "GeuseMaker" -p user.err "Error: $error_code - $error_message"
    fi
    
    return 0
}

# =============================================================================
# ERROR PREVENTION
# =============================================================================

# Validate command before execution
validate_command() {
    local command="$1"
    local description="$2"
    
    # Check if command exists
    if ! command -v "$command" >/dev/null 2>&1; then
        throw_error "$ERROR_MISSING_DEPENDENCY" "Command not found: $command" "$ERROR_CAT_DEPENDENCY" "$ERROR_SEVERITY_ERROR" "$RECOVERY_ABORT"
        return 1
    fi
    
    return 0
}

# Validate AWS CLI
validate_aws_cli() {
    if ! validate_command "aws" "AWS CLI"; then
        return 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>/dev/null | cut -d' ' -f1 | cut -d'/' -f2)
    
    if [[ -z "$aws_version" ]]; then
        throw_error "$ERROR_MISSING_DEPENDENCY" "AWS CLI not properly installed" "$ERROR_CAT_DEPENDENCY" "$ERROR_SEVERITY_ERROR" "$RECOVERY_ABORT"
        return 1
    fi
    
    log_info "AWS CLI version: $aws_version" "VALIDATION"
    return 0
}

# Validate required tools
validate_required_tools() {
    local tools=("jq" "curl" "wget")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        throw_error "$ERROR_MISSING_DEPENDENCY" "Missing tools: ${missing_tools[*]}" "$ERROR_CAT_DEPENDENCY" "$ERROR_SEVERITY_ERROR" "$RECOVERY_ABORT"
        return 1
    fi
    
    return 0
}

# =============================================================================
# ROLLBACK FUNCTIONS
# =============================================================================

# Trigger rollback
trigger_rollback() {
    local stack_name="${1:-$(get_variable STACK_NAME)}"
    local region="${2:-$(get_variable AWS_REGION)}"
    
    log_warn "Triggering rollback for stack: $stack_name" "ROLLBACK"
    
    # Set rollback state
    if command -v set_deployment_state >/dev/null 2>&1; then
        set_deployment_state "ROLLING_BACK"
    fi
    
    # Execute rollback
    if perform_rollback "$stack_name" "$region"; then
        log_info "Rollback completed successfully" "ROLLBACK"
        if command -v set_deployment_state >/dev/null 2>&1; then
            set_deployment_state "ROLLED_BACK"
        fi
    else
        log_error "Rollback failed" "ROLLBACK"
        if command -v set_deployment_state >/dev/null 2>&1; then
            set_deployment_state "ROLLBACK_FAILED"
        fi
        return 1
    fi
}

# Perform rollback
perform_rollback() {
    local stack_name="$1"
    local region="$2"
    
    log_info "Performing rollback for: $stack_name in $region" "ROLLBACK"
    
    # Get deployment state
    local deployment_state=""
    if command -v get_deployment_state >/dev/null 2>&1; then
        deployment_state=$(get_deployment_state "$stack_name" "$region")
    fi
    
    # Rollback based on state
    case "$deployment_state" in
        "VPC_CREATED")
            command -v rollback_vpc >/dev/null 2>&1 && rollback_vpc "$stack_name" "$region"
            ;;
        "SECURITY_CREATED")
            command -v rollback_security >/dev/null 2>&1 && rollback_security "$stack_name" "$region"
            command -v rollback_vpc >/dev/null 2>&1 && rollback_vpc "$stack_name" "$region"
            ;;
        "COMPUTE_CREATED")
            command -v rollback_compute >/dev/null 2>&1 && rollback_compute "$stack_name" "$region"
            command -v rollback_security >/dev/null 2>&1 && rollback_security "$stack_name" "$region"
            command -v rollback_vpc >/dev/null 2>&1 && rollback_vpc "$stack_name" "$region"
            ;;
        "ALB_CREATED")
            command -v rollback_alb >/dev/null 2>&1 && rollback_alb "$stack_name" "$region"
            command -v rollback_compute >/dev/null 2>&1 && rollback_compute "$stack_name" "$region"
            command -v rollback_security >/dev/null 2>&1 && rollback_security "$stack_name" "$region"
            command -v rollback_vpc >/dev/null 2>&1 && rollback_vpc "$stack_name" "$region"
            ;;
        "CDN_CREATED")
            command -v rollback_cdn >/dev/null 2>&1 && rollback_cdn "$stack_name" "$region"
            command -v rollback_alb >/dev/null 2>&1 && rollback_alb "$stack_name" "$region"
            command -v rollback_compute >/dev/null 2>&1 && rollback_compute "$stack_name" "$region"
            command -v rollback_security >/dev/null 2>&1 && rollback_security "$stack_name" "$region"
            command -v rollback_vpc >/dev/null 2>&1 && rollback_vpc "$stack_name" "$region"
            ;;
        *)
            log_warn "Unknown deployment state for rollback: $deployment_state" "ROLLBACK"
            return 1
            ;;
    esac
}

# =============================================================================
# ERROR UTILITIES
# =============================================================================

# Format error for display
format_error() {
    local error_code="$1"
    local error_message="$2"
    local context="${3:-}"
    
    local category
    category=$(get_error_category "$error_code")
    
    local formatted_error="[ERROR-$error_code] $error_message"
    if [[ -n "$context" ]]; then
        formatted_error="$formatted_error (Context: $context)"
    fi
    formatted_error="$formatted_error (Category: $category)"
    
    echo "$formatted_error"
}

# Initialize on source
initialize_error_tracking

# Source clear messages module if available
if [[ -f "${BASH_SOURCE[0]%/*}/../errors/clear_messages.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/../errors/clear_messages.sh"
fi