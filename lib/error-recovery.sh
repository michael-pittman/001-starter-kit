#!/usr/bin/env bash
#
# Enhanced Error Recovery Library
# Provides intelligent retry mechanisms, cleanup, and recovery strategies
#
# Dependencies: deployment-validation.sh, error-handling.sh
# Required Bash Version: 5.3+
#

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/core/bash_version.sh"
source "${SCRIPT_DIR}/modules/core/errors.sh"
source "${SCRIPT_DIR}/modules/core/variables.sh"
source "${SCRIPT_DIR}/error-handling.sh"

# Recovery configuration
declare -gA RECOVERY_CONFIG=(
    [max_retries]=3
    [base_delay]=5
    [max_delay]=300
    [exponential_base]=2
    [jitter_enabled]="true"
    [cleanup_on_failure]="true"
)

# Recovery state tracking
declare -gA RECOVERY_STATE=(
    [total_retries]=0
    [consecutive_failures]=0
    [last_error]=""
    [last_error_time]=""
)

# Error recovery strategies
declare -gA ERROR_RECOVERY_STRATEGIES=(
    [EC2_INSUFFICIENT_CAPACITY]="retry_with_alternative_instance"
    [AWS_RATE_LIMIT]="retry_with_exponential_backoff"
    [NETWORK_TIMEOUT]="retry_with_increased_timeout"
    [RESOURCE_EXISTS]="cleanup_and_retry"
    [QUOTA_EXCEEDED]="wait_for_quota_refresh"
    [AUTHENTICATION_ERROR]="refresh_credentials"
    [STACK_ROLLBACK]="analyze_and_recover"
)

# Retry with exponential backoff
retry_with_backoff() {
    local command="$1"
    local description="${2:-command}"
    local max_retries="${3:-${RECOVERY_CONFIG[max_retries]}}"
    
    local attempt=0
    local delay="${RECOVERY_CONFIG[base_delay]}"
    
    echo "Executing: $description"
    
    while [[ $attempt -lt $max_retries ]]; do
        if eval "$command"; then
            # Success - reset consecutive failures
            RECOVERY_STATE[consecutive_failures]=0
            return 0
        fi
        
        ((attempt++))
        RECOVERY_STATE[total_retries]=$((RECOVERY_STATE[total_retries] + 1))
        RECOVERY_STATE[consecutive_failures]=$((RECOVERY_STATE[consecutive_failures] + 1))
        RECOVERY_STATE[last_error_time]=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        if [[ $attempt -ge $max_retries ]]; then
            echo "✗ Failed after $max_retries attempts: $description"
            return 1
        fi
        
        # Calculate next delay with exponential backoff
        delay=$(calculate_backoff_delay "$attempt" "$delay")
        
        echo "⚠ Attempt $attempt/$max_retries failed. Retrying in ${delay}s..."
        sleep "$delay"
    done
    
    return 1
}

# Calculate backoff delay with jitter
calculate_backoff_delay() {
    local attempt="$1"
    local base_delay="${2:-${RECOVERY_CONFIG[base_delay]}}"
    
    local exponential_base="${RECOVERY_CONFIG[exponential_base]}"
    local max_delay="${RECOVERY_CONFIG[max_delay]}"
    
    # Calculate exponential delay
    local delay=$((base_delay * (exponential_base ** (attempt - 1))))
    
    # Apply max delay cap
    if [[ $delay -gt $max_delay ]]; then
        delay=$max_delay
    fi
    
    # Add jitter if enabled
    if [[ "${RECOVERY_CONFIG[jitter_enabled]}" == "true" ]]; then
        local jitter=$((RANDOM % (delay / 2)))
        delay=$((delay + jitter))
    fi
    
    echo "$delay"
}

# Intelligent error recovery based on error type
recover_from_error() {
    local error_code="$1"
    local error_context="${2:-}"
    
    echo "Attempting recovery for error: $error_code"
    
    # Get recovery strategy
    local strategy="${ERROR_RECOVERY_STRATEGIES[$error_code]:-retry_with_backoff}"
    
    case "$strategy" in
        "retry_with_alternative_instance")
            recover_ec2_capacity_error "$error_context"
            ;;
        "retry_with_exponential_backoff")
            recover_rate_limit_error "$error_context"
            ;;
        "retry_with_increased_timeout")
            recover_network_timeout "$error_context"
            ;;
        "cleanup_and_retry")
            recover_resource_exists "$error_context"
            ;;
        "wait_for_quota_refresh")
            recover_quota_exceeded "$error_context"
            ;;
        "refresh_credentials")
            recover_authentication_error "$error_context"
            ;;
        "analyze_and_recover")
            recover_stack_rollback "$error_context"
            ;;
        *)
            echo "⚠ No specific recovery strategy for $error_code, using default retry"
            return 1
            ;;
    esac
}

# EC2 capacity error recovery
recover_ec2_capacity_error() {
    local context="$1"
    local instance_type="${2:-g4dn.xlarge}"
    local region="${3:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Recovering from EC2 capacity error..."
    
    # Try alternative instance types
    local -a alternatives=(
        "g4dn.2xlarge"
        "g5.xlarge"
        "g5.2xlarge"
        "p3.2xlarge"
    )
    
    for alt_type in "${alternatives[@]}"; do
        echo "Trying alternative instance type: $alt_type"
        
        if check_instance_availability "$alt_type" "$region"; then
            export INSTANCE_TYPE="$alt_type"
            echo "✓ Using alternative instance type: $alt_type"
            return 0
        fi
    done
    
    # Try alternative regions
    local -a alt_regions=(
        "us-west-2"
        "eu-west-1"
        "ap-northeast-1"
    )
    
    for alt_region in "${alt_regions[@]}"; do
        [[ "$alt_region" == "$region" ]] && continue
        
        echo "Trying alternative region: $alt_region"
        
        if check_instance_availability "$instance_type" "$alt_region"; then
            export AWS_DEFAULT_REGION="$alt_region"
            echo "✓ Using alternative region: $alt_region"
            return 0
        fi
    done
    
    echo "✗ No alternative capacity found"
    return 1
}

# Rate limit error recovery
recover_rate_limit_error() {
    local context="$1"
    
    echo "Recovering from AWS rate limit error..."
    
    # Progressive delays for rate limiting
    local -a delays=(60 120 300 600)
    local delay_index=$((RECOVERY_STATE[consecutive_failures] % ${#delays[@]}))
    local wait_time="${delays[$delay_index]}"
    
    echo "⏳ Waiting ${wait_time}s for rate limit to reset..."
    sleep "$wait_time"
    
    # Reduce request rate
    export AWS_REQUEST_DELAY=2
    
    return 0
}

# Network timeout recovery
recover_network_timeout() {
    local context="$1"
    
    echo "Recovering from network timeout..."
    
    # Increase timeout values
    export AWS_CLI_TIMEOUT=300
    export CURL_TIMEOUT=300
    
    # Check network connectivity
    if ! check_network_connectivity; then
        echo "⚠ Network connectivity issues detected"
        echo "Waiting 30s for network to stabilize..."
        sleep 30
    fi
    
    return 0
}

# Resource exists error recovery
recover_resource_exists() {
    local context="$1"
    local resource_type="${2:-unknown}"
    local resource_id="${3:-}"
    
    echo "Recovering from resource exists error..."
    
    # Try to identify and clean up existing resource
    case "$resource_type" in
        "stack")
            if [[ -n "$resource_id" ]]; then
                echo "Attempting to delete existing stack: $resource_id"
                aws cloudformation delete-stack --stack-name "$resource_id" 2>/dev/null || true
                
                # Wait for deletion
                echo "Waiting for stack deletion..."
                aws cloudformation wait stack-delete-complete --stack-name "$resource_id" 2>/dev/null || true
            fi
            ;;
        "vpc")
            echo "Existing VPC detected, using it instead of creating new one"
            export USE_EXISTING_VPC="true"
            ;;
        *)
            echo "⚠ Cannot automatically clean up resource type: $resource_type"
            return 1
            ;;
    esac
    
    return 0
}

# Quota exceeded recovery
recover_quota_exceeded() {
    local context="$1"
    local service="${2:-ec2}"
    
    echo "Recovering from quota exceeded error..."
    
    # Check current usage
    case "$service" in
        "ec2")
            echo "Checking for instances to terminate..."
            cleanup_old_instances
            ;;
        "vpc")
            echo "Checking for unused VPCs..."
            cleanup_unused_vpcs
            ;;
        *)
            echo "⚠ No cleanup strategy for service: $service"
            ;;
    esac
    
    # Wait for quota refresh
    echo "⏳ Waiting 5 minutes for quota refresh..."
    sleep 300
    
    return 0
}

# Authentication error recovery
recover_authentication_error() {
    local context="$1"
    
    echo "Recovering from authentication error..."
    
    # Check if credentials are expired
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "✗ AWS credentials are invalid or expired"
        
        # Try to refresh credentials
        if [[ -n "${AWS_PROFILE:-}" ]]; then
            echo "Attempting to refresh credentials for profile: $AWS_PROFILE"
            
            # Check for SSO
            if aws configure get sso_start_url --profile "$AWS_PROFILE" &>/dev/null; then
                echo "Refreshing SSO credentials..."
                aws sso login --profile "$AWS_PROFILE"
            fi
        fi
        
        # Verify credentials again
        if aws sts get-caller-identity &>/dev/null; then
            echo "✓ Credentials refreshed successfully"
            return 0
        else
            echo "✗ Failed to refresh credentials"
            return 1
        fi
    fi
    
    return 0
}

# Stack rollback recovery
recover_stack_rollback() {
    local stack_name="$1"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Recovering from stack rollback..."
    
    # Get rollback reason
    local stack_events
    stack_events=$(aws cloudformation describe-stack-events \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.StackEvents[] | select(.ResourceStatus | contains("FAILED")) | "\(.LogicalResourceId): \(.ResourceStatusReason)"' | head -5)
    
    if [[ -n "$stack_events" ]]; then
        echo "Rollback reasons:"
        echo "$stack_events"
    fi
    
    # Delete the failed stack
    echo "Deleting failed stack..."
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$region" 2>/dev/null || true
    
    # Wait for deletion
    echo "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region "$region" 2>/dev/null || true
    
    echo "✓ Failed stack cleaned up"
    return 0
}

# Check instance availability
check_instance_availability() {
    local instance_type="$1"
    local region="$2"
    
    # Quick check using describe-instance-type-offerings
    aws ec2 describe-instance-type-offerings \
        --filters "Name=instance-type,Values=$instance_type" \
        --region "$region" \
        --output json 2>/dev/null | jq -e '.InstanceTypeOfferings | length > 0' &>/dev/null
}

# Cleanup old instances
cleanup_old_instances() {
    local age_hours="${1:-24}"
    local region="${AWS_DEFAULT_REGION:-us-east-1}"
    
    echo "Looking for instances older than ${age_hours} hours..."
    
    # Find old instances
    local old_instances
    old_instances=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running,stopped" \
        --region "$region" \
        --output json | jq -r --arg age "$age_hours" '.Reservations[].Instances[] | select(.LaunchTime | fromdateiso8601 < (now - ($age | tonumber * 3600))) | .InstanceId')
    
    if [[ -n "$old_instances" ]]; then
        echo "Found old instances to terminate:"
        echo "$old_instances"
        
        # Terminate instances
        echo "$old_instances" | xargs -I {} aws ec2 terminate-instances \
            --instance-ids {} \
            --region "$region" 2>/dev/null || true
        
        echo "✓ Cleanup initiated"
    else
        echo "No old instances found"
    fi
}

# Cleanup unused VPCs
cleanup_unused_vpcs() {
    local region="${AWS_DEFAULT_REGION:-us-east-1}"
    
    echo "Looking for unused VPCs..."
    
    # Find VPCs with no instances
    local unused_vpcs
    unused_vpcs=$(aws ec2 describe-vpcs \
        --region "$region" \
        --output json | jq -r '.Vpcs[] | select(.IsDefault == false) | .VpcId' | while read -r vpc_id; do
        instance_count=$(aws ec2 describe-instances \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,stopped" \
            --region "$region" \
            --output json | jq '.Reservations | length')
        
        if [[ "$instance_count" -eq 0 ]]; then
            echo "$vpc_id"
        fi
    done)
    
    if [[ -n "$unused_vpcs" ]]; then
        echo "Found unused VPCs:"
        echo "$unused_vpcs"
        echo "Note: Manual cleanup required for VPCs"
    else
        echo "No unused VPCs found"
    fi
}

# Recovery orchestrator
orchestrate_recovery() {
    local error_code="$1"
    local error_context="${2:-}"
    local max_recovery_attempts="${3:-3}"
    
    local recovery_attempt=0
    
    while [[ $recovery_attempt -lt $max_recovery_attempts ]]; do
        ((recovery_attempt++))
        
        echo "Recovery attempt $recovery_attempt/$max_recovery_attempts for $error_code"
        
        if recover_from_error "$error_code" "$error_context"; then
            echo "✓ Recovery successful"
            return 0
        fi
        
        echo "⚠ Recovery attempt $recovery_attempt failed"
        
        # Wait before next attempt
        local wait_time=$((recovery_attempt * 10))
        echo "Waiting ${wait_time}s before next recovery attempt..."
        sleep "$wait_time"
    done
    
    echo "✗ Recovery failed after $max_recovery_attempts attempts"
    return 1
}

# Graceful degradation handler
handle_graceful_degradation() {
    local feature="$1"
    local fallback="${2:-skip}"
    
    echo "⚠ Feature degradation: $feature"
    
    case "$fallback" in
        "skip")
            echo "Skipping feature: $feature"
            export "SKIP_${feature^^}=true"
            ;;
        "minimal")
            echo "Using minimal configuration for: $feature"
            export "${feature^^}_MODE=minimal"
            ;;
        "alternative")
            echo "Using alternative implementation for: $feature"
            export "${feature^^}_MODE=alternative"
            ;;
        *)
            echo "Unknown fallback: $fallback"
            return 1
            ;;
    esac
    
    return 0
}

# Health check with recovery
health_check_with_recovery() {
    local service="$1"
    local endpoint="$2"
    local max_retries="${3:-3}"
    
    if retry_with_backoff "curl -sf '$endpoint' >/dev/null" "Health check for $service" "$max_retries"; then
        echo "✓ $service is healthy"
        return 0
    else
        echo "✗ $service health check failed"
        
        # Attempt recovery
        case "$service" in
            "n8n")
                echo "Attempting to restart n8n service..."
                restart_service "n8n"
                ;;
            "ollama")
                echo "Attempting to restart ollama service..."
                restart_service "ollama"
                ;;
            *)
                echo "No recovery action for service: $service"
                ;;
        esac
        
        return 1
    fi
}

# Service restart helper
restart_service() {
    local service="$1"
    local instance_id="${2:-}"
    
    if [[ -z "$instance_id" ]]; then
        # Try to find instance
        instance_id=$(aws ec2 describe-instances \
            --filters "Name=instance-state-name,Values=running" \
                      "Name=tag:Service,Values=$service" \
            --output json | jq -r '.Reservations[0].Instances[0].InstanceId // empty')
    fi
    
    if [[ -n "$instance_id" ]]; then
        echo "Restarting $service on instance $instance_id..."
        
        aws ssm send-command \
            --instance-ids "$instance_id" \
            --document-name "AWS-RunShellScript" \
            --parameters "commands=['sudo systemctl restart $service || sudo docker restart $service']" \
            --output json &>/dev/null || true
        
        sleep 30
    fi
}

# Export functions
export -f retry_with_backoff
export -f calculate_backoff_delay
export -f recover_from_error
export -f recover_ec2_capacity_error
export -f recover_rate_limit_error
export -f recover_network_timeout
export -f recover_resource_exists
export -f recover_quota_exceeded
export -f recover_authentication_error
export -f recover_stack_rollback
export -f check_instance_availability
export -f cleanup_old_instances
export -f cleanup_unused_vpcs
export -f orchestrate_recovery
export -f handle_graceful_degradation
export -f health_check_with_recovery
export -f restart_service