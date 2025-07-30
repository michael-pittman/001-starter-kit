#!/usr/bin/env bash
# =============================================================================
# Infrastructure Base Module
# Common dependencies and utilities for infrastructure modules
# =============================================================================

# Prevent multiple sourcing
[ -n "${_INFRASTRUCTURE_BASE_SH_LOADED:-}" ] && return 0
declare -gr _INFRASTRUCTURE_BASE_SH_LOADED=1

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common dependencies using dependency groups
source "${SCRIPT_DIR}/../core/dependency-groups.sh"
load_dependency_group "CORE" "$SCRIPT_DIR/.."

# Ensure logging is available
if ! command -v log_info >/dev/null 2>&1; then
    # Basic logging fallback
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# =============================================================================
# COMMON INFRASTRUCTURE CONSTANTS
# =============================================================================

# Resource tagging standards
declare -gr INFRA_TAG_PROJECT="GeuseMaker"
declare -gr INFRA_TAG_MANAGED_BY="DeploymentScript"
declare -gr INFRA_TAG_COST_CENTER="Engineering"

# Default timeouts (in seconds)
declare -gr INFRA_WAIT_TIMEOUT_SHORT=60
declare -gr INFRA_WAIT_TIMEOUT_MEDIUM=300
declare -gr INFRA_WAIT_TIMEOUT_LONG=600

# Retry configuration
declare -gr INFRA_MAX_RETRIES=3
declare -gr INFRA_RETRY_DELAY=5

# =============================================================================
# COMMON INFRASTRUCTURE FUNCTIONS
# =============================================================================

# Generate infrastructure-specific tags
generate_infra_tags() {
    local stack_name="${1:-$STACK_NAME}"
    local resource_type="${2:-}"
    local environment="${3:-$ENVIRONMENT}"
    local additional_tags="${4:-}"
    
    # Base infrastructure tags
    local base_tags="{
        \"Name\": \"$stack_name\",
        \"Stack\": \"$stack_name\",
        \"Project\": \"$INFRA_TAG_PROJECT\",
        \"ManagedBy\": \"$INFRA_TAG_MANAGED_BY\",
        \"Environment\": \"$environment\",
        \"CreatedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }"
    
    # Add resource type if specified
    if [[ -n "$resource_type" ]]; then
        base_tags=$(echo "$base_tags" | jq --arg type "$resource_type" '. + {"ResourceType": $type}')
    fi
    
    # Merge additional tags if provided
    if [[ -n "$additional_tags" ]]; then
        base_tags=$(echo "$base_tags" | jq -s --argjson additional "$additional_tags" '.[0] * $additional')
    fi
    
    echo "$base_tags"
}

# Wait for infrastructure resource to reach desired state
wait_for_resource_state() {
    local resource_type="$1"
    local resource_id="$2"
    local desired_state="$3"
    local timeout="${4:-$INFRA_WAIT_TIMEOUT_MEDIUM}"
    
    log_info "Waiting for $resource_type $resource_id to reach state: $desired_state"
    
    local start_time=$(date +%s)
    local current_state=""
    
    while true; do
        # Get current state based on resource type
        case "$resource_type" in
            "instance")
                current_state=$(aws ec2 describe-instances \
                    --instance-ids "$resource_id" \
                    --query 'Reservations[0].Instances[0].State.Name' \
                    --output text 2>/dev/null || echo "unknown")
                ;;
            "vpc")
                current_state=$(aws ec2 describe-vpcs \
                    --vpc-ids "$resource_id" \
                    --query 'Vpcs[0].State' \
                    --output text 2>/dev/null || echo "unknown")
                ;;
            "security-group")
                # Security groups don't have state, check existence
                if aws ec2 describe-security-groups --group-ids "$resource_id" >/dev/null 2>&1; then
                    current_state="available"
                else
                    current_state="not-found"
                fi
                ;;
            *)
                log_error "Unknown resource type: $resource_type"
                return 1
                ;;
        esac
        
        # Check if desired state reached
        if [[ "$current_state" == "$desired_state" ]]; then
            log_info "$resource_type $resource_id reached desired state: $desired_state"
            return 0
        fi
        
        # Check timeout
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for $resource_type $resource_id to reach state: $desired_state (current: $current_state)"
            return 1
        fi
        
        # Wait before next check
        sleep 5
    done
}

# Retry infrastructure operation with exponential backoff
retry_infra_operation() {
    local operation_name="$1"
    shift
    local command=("$@")
    
    local attempt=1
    local delay=$INFRA_RETRY_DELAY
    
    while [[ $attempt -le $INFRA_MAX_RETRIES ]]; do
        log_info "Attempting $operation_name (attempt $attempt/$INFRA_MAX_RETRIES)"
        
        if "${command[@]}"; then
            log_info "$operation_name succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -lt $INFRA_MAX_RETRIES ]]; then
            log_warn "$operation_name failed on attempt $attempt, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "$operation_name failed after $INFRA_MAX_RETRIES attempts"
    return 1
}

# Validate AWS resource ID format
validate_resource_id() {
    local resource_type="$1"
    local resource_id="$2"
    
    local pattern=""
    case "$resource_type" in
        "vpc")
            pattern="^vpc-[0-9a-f]{8,17}$"
            ;;
        "subnet")
            pattern="^subnet-[0-9a-f]{8,17}$"
            ;;
        "security-group")
            pattern="^sg-[0-9a-f]{8,17}$"
            ;;
        "instance")
            pattern="^i-[0-9a-f]{8,17}$"
            ;;
        "ami")
            pattern="^ami-[0-9a-f]{8,17}$"
            ;;
        "volume")
            pattern="^vol-[0-9a-f]{8,17}$"
            ;;
        *)
            log_error "Unknown resource type for validation: $resource_type"
            return 1
            ;;
    esac
    
    if [[ ! "$resource_id" =~ $pattern ]]; then
        log_error "Invalid $resource_type ID format: $resource_id"
        return 1
    fi
    
    return 0
}

# Check if infrastructure resource exists
resource_exists_in_aws() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids "$resource_id" >/dev/null 2>&1
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids "$resource_id" >/dev/null 2>&1
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" >/dev/null 2>&1
            ;;
        "instance")
            aws ec2 describe-instances --instance-ids "$resource_id" >/dev/null 2>&1
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Get AWS account ID
get_aws_account_id() {
    aws sts get-caller-identity --query 'Account' --output text 2>/dev/null
}

# Get current AWS region
get_current_region() {
    echo "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
}

# Format AWS CLI output for better readability
format_aws_output() {
    local output="$1"
    local format="${2:-table}"
    
    case "$format" in
        "json")
            echo "$output" | jq '.' 2>/dev/null || echo "$output"
            ;;
        "table")
            echo "$output" | column -t -s $'\t'
            ;;
        "yaml")
            echo "$output" | jq -r 'to_entries | .[] | "\(.key): \(.value)"' 2>/dev/null || echo "$output"
            ;;
        *)
            echo "$output"
            ;;
    esac
}

# =============================================================================
# INFRASTRUCTURE ERROR HANDLING
# =============================================================================

# Handle common infrastructure errors
handle_infra_error() {
    local error_code="$1"
    local resource_type="$2"
    local resource_id="${3:-}"
    local context="${4:-}"
    
    case "$error_code" in
        "InvalidParameterValue")
            log_error "Invalid parameter value for $resource_type${resource_id:+ $resource_id}${context:+ - $context}"
            return $ERROR_INVALID_ARGUMENT
            ;;
        "ResourceNotFoundException")
            log_error "$resource_type not found${resource_id:+: $resource_id}${context:+ - $context}"
            return $ERROR_RESOURCE_NOT_FOUND
            ;;
        "LimitExceededException")
            log_error "AWS limit exceeded for $resource_type${context:+ - $context}"
            return $ERROR_LIMIT_EXCEEDED
            ;;
        "UnauthorizedOperation")
            log_error "Unauthorized operation on $resource_type${resource_id:+: $resource_id}${context:+ - $context}"
            return $ERROR_PERMISSION_DENIED
            ;;
        *)
            log_error "Infrastructure error: $error_code for $resource_type${resource_id:+: $resource_id}${context:+ - $context}"
            return $ERROR_AWS_API
            ;;
    esac
}

# Export for compatibility
export INFRASTRUCTURE_BASE_LOADED=1