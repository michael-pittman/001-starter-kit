#!/bin/bash
# Enhanced Error Handling System
# Provides structured error types and recovery strategies

set -euo pipefail

# Prevent multiple sourcing
[ -n "${_ERROR_TYPES_SH_LOADED:-}" ] && return 0
_ERROR_TYPES_SH_LOADED=1

# =============================================================================
# ERROR TYPE DEFINITIONS
# =============================================================================

# Error severity levels
readonly ERROR_SEVERITY_INFO=0
readonly ERROR_SEVERITY_WARNING=1
readonly ERROR_SEVERITY_ERROR=2
readonly ERROR_SEVERITY_CRITICAL=3

# Error categories
readonly ERROR_CAT_VALIDATION="validation"
readonly ERROR_CAT_INFRASTRUCTURE="infrastructure"
readonly ERROR_CAT_NETWORK="network"
readonly ERROR_CAT_AUTHENTICATION="authentication"
readonly ERROR_CAT_AUTHORIZATION="authorization"
readonly ERROR_CAT_CAPACITY="capacity"
readonly ERROR_CAT_TIMEOUT="timeout"
readonly ERROR_CAT_DEPENDENCY="dependency"
readonly ERROR_CAT_CONFIGURATION="configuration"

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
# ERROR TRACKING
# =============================================================================

# ERROR_REGISTRY, ERROR_RECOVERY_STRATEGIES, ERROR_COUNT removed
# Already replaced with function-based approach above

# Initialize ERROR_LOG_FILE if not set
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/deployment-errors.json}"

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
# ERROR LOGGING FUNCTIONS
# =============================================================================

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
    
    # Append to structured log
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
}

# =============================================================================
# PREDEFINED ERROR TYPES
# =============================================================================

# EC2 Instance Errors
error_ec2_insufficient_capacity() {
    local instance_type="$1"
    local region="$2"
    local context="Instance type: $instance_type, Region: $region"
    
    log_structured_error \
        "EC2_INSUFFICIENT_CAPACITY" \
        "Insufficient capacity for instance type $instance_type in region $region" \
        "$ERROR_CAT_CAPACITY" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_FALLBACK"
}

error_ec2_instance_limit_exceeded() {
    local instance_type="$1"
    local context="Instance type: $instance_type"
    
    log_structured_error \
        "EC2_INSTANCE_LIMIT_EXCEEDED" \
        "Instance limit exceeded for type $instance_type" \
        "$ERROR_CAT_CAPACITY" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_MANUAL"
}

error_ec2_spot_bid_too_low() {
    local bid_price="$1"
    local current_price="$2"
    local context="Bid: $bid_price, Current: $current_price"
    
    log_structured_error \
        "EC2_SPOT_BID_TOO_LOW" \
        "Spot bid price too low: $bid_price < $current_price" \
        "$ERROR_CAT_CAPACITY" \
        "$ERROR_SEVERITY_WARNING" \
        "$context" \
        "$RECOVERY_RETRY"
}

# Network Errors
error_network_vpc_not_found() {
    local vpc_id="$1"
    local context="VPC ID: $vpc_id"
    
    log_structured_error \
        "NETWORK_VPC_NOT_FOUND" \
        "VPC not found: $vpc_id" \
        "$ERROR_CAT_NETWORK" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_FALLBACK"
}

error_network_security_group_invalid() {
    local sg_id="$1"
    local context="Security Group ID: $sg_id"
    
    log_structured_error \
        "NETWORK_SECURITY_GROUP_INVALID" \
        "Invalid security group: $sg_id" \
        "$ERROR_CAT_NETWORK" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_RETRY"
}

# Authentication/Authorization Errors
error_auth_invalid_credentials() {
    local service="$1"
    local context="Service: $service"
    
    log_structured_error \
        "AUTH_INVALID_CREDENTIALS" \
        "Invalid AWS credentials for $service" \
        "$ERROR_CAT_AUTHENTICATION" \
        "$ERROR_SEVERITY_CRITICAL" \
        "$context" \
        "$RECOVERY_MANUAL"
}

error_auth_insufficient_permissions() {
    local action="$1"
    local resource="$2"
    local context="Action: $action, Resource: $resource"
    
    log_structured_error \
        "AUTH_INSUFFICIENT_PERMISSIONS" \
        "Insufficient permissions for $action on $resource" \
        "$ERROR_CAT_AUTHORIZATION" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_MANUAL"
}

# Configuration Errors
error_config_invalid_variable() {
    local variable="$1"
    local value="$2"
    local context="Variable: $variable, Value: $value"
    
    log_structured_error \
        "CONFIG_INVALID_VARIABLE" \
        "Invalid variable value: $variable=$value" \
        "$ERROR_CAT_CONFIGURATION" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_ABORT"
}

error_config_missing_parameter() {
    local parameter="$1"
    local context="Parameter: $parameter"
    
    log_structured_error \
        "CONFIG_MISSING_PARAMETER" \
        "Missing required parameter: $parameter" \
        "$ERROR_CAT_CONFIGURATION" \
        "$ERROR_SEVERITY_ERROR" \
        "$context" \
        "$RECOVERY_ABORT"
}

# Timeout Errors
error_timeout_operation() {
    local operation="$1"
    local timeout="$2"
    local context="Operation: $operation, Timeout: ${timeout}s"
    
    log_structured_error \
        "TIMEOUT_OPERATION" \
        "Operation timed out: $operation (${timeout}s)" \
        "$ERROR_CAT_TIMEOUT" \
        "$ERROR_SEVERITY_WARNING" \
        "$context" \
        "$RECOVERY_RETRY"
}

# Dependency Errors
error_dependency_not_ready() {
    local dependency="$1"
    local dependent="$2"
    local context="Dependency: $dependency, Dependent: $dependent"
    
    log_structured_error \
        "DEPENDENCY_NOT_READY" \
        "Dependency not ready: $dependency for $dependent" \
        "$ERROR_CAT_DEPENDENCY" \
        "$ERROR_SEVERITY_WARNING" \
        "$context" \
        "$RECOVERY_RETRY"
}

# =============================================================================
# ERROR ANALYSIS
# =============================================================================

get_error_count() {
    local error_code="$1"
    local count="$(get_error_data "$error_code" "COUNT")"
    echo "${count:-0}"
}

get_recovery_strategy() {
    local error_code="$1"
    local strategy="$(get_error_data "$error_code" "RECOVERY_STRATEGIES")"
    echo "${strategy:-$RECOVERY_ABORT}"
}

should_retry_error() {
    local error_code="$1"
    local max_retries="${2:-3}"
    
    local strategy=$(get_recovery_strategy "$error_code")
    local count=$(get_error_count "$error_code")
    
    [[ "$strategy" == "$RECOVERY_RETRY" ]] && [[ "$count" -lt "$max_retries" ]]
}

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
    local output_file="${1:-error-report.json}"
    
    if [[ -f "$ERROR_LOG_FILE" ]]; then
        cp "$ERROR_LOG_FILE" "$output_file"
        echo "Error report generated: $output_file"
    else
        echo '{"errors": []}' > "$output_file"
        echo "Empty error report generated: $output_file"
    fi
}

# Initialize on source
initialize_error_tracking