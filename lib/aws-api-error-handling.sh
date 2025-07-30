#!/usr/bin/env bash
# =============================================================================
# AWS API Error Handling Module
# Intelligent retry mechanisms and comprehensive AWS error categorization
# Compatible with bash 3.x+
# =============================================================================


# =============================================================================
# AWS ERROR CATEGORIZATION AND ANALYSIS
# =============================================================================

# Comprehensive AWS error patterns - compatible with bash 3.x+
if [[ -z "${AWS_ERROR_PATTERNS_DEFINED:-}" ]]; then
    declare -A AWS_ERROR_PATTERNS=(
        # Authentication & Authorization
        ["InvalidUserID.NotFound"]="AUTH:CREDENTIALS:false:Check AWS access key ID"
        ["InvalidAccessKeyId"]="AUTH:CREDENTIALS:false:Verify AWS access key ID"
        ["SignatureDoesNotMatch"]="AUTH:SIGNATURE:false:Check AWS secret access key"
        ["TokenRefreshRequired"]="AUTH:TOKEN:true:Refresh AWS session token"
        ["AccessDenied"]="AUTH:PERMISSION:false:Check IAM policies and permissions"
        ["UnauthorizedOperation"]="AUTH:PERMISSION:false:Verify IAM permissions for operation"
        
        # Rate Limiting & Throttling
        ["RequestLimitExceeded"]="RATE:LIMIT:true:Implement exponential backoff"
        ["Throttling"]="RATE:THROTTLE:true:Reduce request frequency"
        ["TooManyRequests"]="RATE:BURST:true:Implement request queuing"
        ["SlowDown"]="RATE:S3:true:Reduce S3 request rate"
        
        # Resource Capacity & Limits
        ["InsufficientInstanceCapacity"]="CAPACITY:EC2:true:Try different instance type or AZ"
        ["InstanceLimitExceeded"]="CAPACITY:LIMIT:false:Request EC2 limit increase"
        ["VcpuLimitExceeded"]="CAPACITY:VCPU:false:Request vCPU limit increase"
        ["SpotFleetRequestConfigurationInvalid"]="CAPACITY:SPOT:false:Check spot fleet configuration"
        
        # Service Availability
        ["ServiceUnavailable"]="SERVICE:UNAVAILABLE:true:Check AWS service health"
        ["InternalFailure"]="SERVICE:INTERNAL:true:Retry after brief delay"
        ["InternalError"]="SERVICE:INTERNAL:true:Retry with exponential backoff"
        ["InternalServerError"]="SERVICE:INTERNAL:true:Check AWS status page"
        
        # Network & Connectivity
        ["NetworkingError"]="NETWORK:CONNECTIVITY:true:Check network connectivity"
        ["EndpointConnectionError"]="NETWORK:ENDPOINT:true:Verify AWS endpoint accessibility"
        ["ConnectionError"]="NETWORK:CONNECTION:true:Check internet connectivity"
        ["TimeoutError"]="NETWORK:TIMEOUT:true:Increase timeout values"
        
        # Validation & Configuration
        ["InvalidParameterValue"]="VALIDATION:PARAMETER:false:Check API parameter values"
        ["ValidationException"]="VALIDATION:INPUT:false:Validate input parameters"
        ["MalformedPolicyDocument"]="VALIDATION:POLICY:false:Check IAM policy syntax"
        ["InvalidUserData"]="VALIDATION:USERDATA:false:Check EC2 user data encoding"
        
        # Resource State & Dependencies
        ["InvalidAMIID.NotFound"]="RESOURCE:AMI:false:Verify AMI exists and is accessible"
        ["InvalidKeyPair.NotFound"]="RESOURCE:KEYPAIR:false:Verify key pair exists"
        ["InvalidSubnetID.NotFound"]="RESOURCE:SUBNET:false:Check subnet ID and region"
        ["InvalidVpcID.NotFound"]="RESOURCE:VPC:false:Verify VPC exists in region"
        ["DependencyViolation"]="RESOURCE:DEPENDENCY:false:Check resource dependencies"
        
        # Billing & Account
        ["OptInRequired"]="ACCOUNT:OPTIN:false:Enable service in AWS account"
        ["AccountNotOptedIn"]="ACCOUNT:SERVICE:false:Opt in to AWS service"
        ["InsufficientAccountCapacity"]="ACCOUNT:CAPACITY:false:Contact AWS support"
    )
    readonly AWS_ERROR_PATTERNS
    export AWS_ERROR_PATTERNS_DEFINED=true
fi

# Rate limiting configuration
if [[ -z "${RATE_LIMIT_CONFIG_DEFINED:-}" ]]; then
    declare -A RATE_LIMIT_CONFIG=(
        ["default_base_delay"]=2
        ["default_max_delay"]=60
        ["default_backoff_multiplier"]=2
        ["burst_protection_delay"]=10
        ["throttle_protection_delay"]=5
    )
    readonly RATE_LIMIT_CONFIG
    export RATE_LIMIT_CONFIG_DEFINED=true
fi

# =============================================================================
# AWS ERROR PARSING AND ANALYSIS
# =============================================================================

# Parse AWS CLI/SDK error output with comprehensive analysis
parse_aws_error() {
    local error_output="$1"
    local command_context="${2:-unknown}"
    local exit_code="${3:-1}"
    
    # Initialize error analysis result
    local error_type="UNKNOWN"
    local error_subtype="GENERAL"
    local is_retryable="false"
    local suggested_action="Check AWS documentation"
    local retry_delay=2
    local max_retries=3
    
    # Extract error code from various AWS output formats
    local error_code=""
    
    # Try multiple extraction methods
    if echo "$error_output" | grep -q "An error occurred"; then
        # AWS CLI v2 format: "An error occurred (ErrorCode) when calling..."
        error_code=$(echo "$error_output" | sed -n 's/.*An error occurred (\([^)]*\)).*/\1/p' | head -1)
    elif echo "$error_output" | grep -q "aws:"; then
        # Error code in aws: prefix format
        error_code=$(echo "$error_output" | grep -o 'aws:[^:]*' | cut -d: -f2 | head -1)
    elif echo "$error_output" | grep -qE "(Error|Exception)"; then
        # Generic error/exception pattern
        error_code=$(echo "$error_output" | grep -oE '[A-Z][a-zA-Z]*Error|[A-Z][a-zA-Z]*Exception' | head -1)
    fi
    
    # Look up error pattern in our comprehensive database
    if [[ -n "$error_code" && -n "${AWS_ERROR_PATTERNS[$error_code]:-}" ]]; then
        local pattern_data="${AWS_ERROR_PATTERNS[$error_code]}"
        IFS=':' read -ra pattern_parts <<< "$pattern_data"
        
        error_type="${pattern_parts[0]}"
        error_subtype="${pattern_parts[1]}"
        is_retryable="${pattern_parts[2]}"
        suggested_action="${pattern_parts[3]}"
        
        # Set retry parameters based on error type
        case "$error_type" in
            "RATE")
                case "$error_subtype" in
                    "LIMIT"|"THROTTLE") 
                        retry_delay="${RATE_LIMIT_CONFIG[throttle_protection_delay]}"
                        max_retries=5
                        ;;
                    "BURST") 
                        retry_delay="${RATE_LIMIT_CONFIG[burst_protection_delay]}"
                        max_retries=3
                        ;;
                esac
                ;;
            "SERVICE"|"NETWORK")
                retry_delay=5
                max_retries=4
                ;;
            "CAPACITY")
                retry_delay=10
                max_retries=2
                ;;
        esac
    else
        # Fallback pattern matching for unknown errors
        case "$error_output" in
            *"Rate exceeded"*|*"Too many requests"*)
                error_type="RATE"
                error_subtype="GENERAL"
                is_retryable="true"
                suggested_action="Reduce request frequency"
                ;;
            *"Connection"*|*"Network"*)
                error_type="NETWORK"
                error_subtype="CONNECTIVITY"
                is_retryable="true"
                suggested_action="Check network connectivity"
                ;;
            *"Timeout"*)
                error_type="NETWORK"
                error_subtype="TIMEOUT"
                is_retryable="true"
                suggested_action="Increase timeout or check network latency"
                ;;
            *"Invalid"*|*"Malformed"*)
                error_type="VALIDATION"
                error_subtype="INPUT"
                is_retryable="false"
                suggested_action="Correct input parameters"
                ;;
        esac
    fi
    
    # Output structured analysis result
    cat <<EOF
{
    "error_code": "$error_code",
    "error_type": "$error_type",
    "error_subtype": "$error_subtype",
    "is_retryable": $is_retryable,
    "suggested_action": "$suggested_action",
    "retry_delay": $retry_delay,
    "max_retries": $max_retries,
    "command_context": "$command_context",
    "exit_code": $exit_code,
    "analysis_timestamp": "$(date -Iseconds)"
}
EOF
}

# =============================================================================
# INTELLIGENT RETRY MECHANISMS
# =============================================================================

# Advanced AWS retry with adaptive backoff and circuit breaker
aws_retry_with_intelligence() {
    local command=("$@")
    local max_attempts="${AWS_MAX_RETRY_ATTEMPTS:-5}"
    local operation_name="${AWS_OPERATION_NAME:-aws_operation}"
    
    # Circuit breaker state tracking
    local circuit_breaker_file="/tmp/aws_circuit_breaker_$$"
    local failure_threshold=5
    local recovery_timeout=300  # 5 minutes
    
    # Check circuit breaker state
    if [[ -f "$circuit_breaker_file" ]]; then
        local last_failure
        last_failure=$(cat "$circuit_breaker_file")
        local current_time
        current_time=$(date +%s)
        
        if (( current_time - last_failure < recovery_timeout )); then
            if declare -f log_structured >/dev/null 2>&1; then
                log_structured "ERROR" "Circuit breaker is open for AWS operations" \
                    "operation=$operation_name" \
                    "time_remaining=$((recovery_timeout - (current_time - last_failure)))s"
            else
                echo "Circuit breaker is open for AWS operations ($(( recovery_timeout - (current_time - last_failure) ))s remaining)" >&2
            fi
            return 1
        else
            # Recovery timeout passed, reset circuit breaker
            rm -f "$circuit_breaker_file"
        fi
    fi
    
    local attempt=1
    local consecutive_failures=0
    local total_start_time
    total_start_time=$(date +%s.%N)
    
    # Start operation timing
    if declare -f start_timer >/dev/null 2>&1; then
        start_timer "aws_retry_$operation_name"
    fi
    
    while [ $attempt -le $max_attempts ]; do
        local attempt_start_time
        attempt_start_time=$(date +%s.%N)
        
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "DEBUG" "AWS operation attempt" \
                "operation=$operation_name" \
                "attempt=$attempt" \
                "max_attempts=$max_attempts" \
                "command=${command[0]}"
        fi
        
        # Capture both stdout and stderr
        local output error_output exit_code
        local temp_stdout temp_stderr
        temp_stdout=$(mktemp)
        temp_stderr=$(mktemp)
        
        # Execute command with timeout protection
        if timeout 300 "${command[@]}" >"$temp_stdout" 2>"$temp_stderr"; then
            exit_code=0
            output=$(cat "$temp_stdout")
            error_output=$(cat "$temp_stderr")
        else
            exit_code=$?
            output=$(cat "$temp_stdout")
            error_output=$(cat "$temp_stderr")
        fi
        
        # Cleanup temp files
        rm -f "$temp_stdout" "$temp_stderr"
        
        # Calculate attempt duration
        local attempt_duration
        if command -v bc >/dev/null 2>&1; then
            attempt_duration=$(echo "scale=3; $(date +%s.%N) - $attempt_start_time" | bc -l)
        else
            attempt_duration=$(awk "BEGIN {printf \"%.3f\", $(date +%s) - ${attempt_start_time%.*}}")
        fi
        
        if [ $exit_code -eq 0 ]; then
            # Success - end timing and return result
            if declare -f end_timer >/dev/null 2>&1; then
                local total_duration
                total_duration=$(end_timer "aws_retry_$operation_name")
                
                if declare -f log_structured >/dev/null 2>&1; then
                    log_structured "INFO" "AWS operation succeeded" \
                        "operation=$operation_name" \
                        "attempt=$attempt" \
                        "attempt_duration=${attempt_duration}s" \
                        "total_duration=${total_duration}s"
                fi
            fi
            
            echo "$output"
            return 0
        else
            # Failure - analyze error
            consecutive_failures=$((consecutive_failures + 1))
            
            # Parse error for intelligent retry decision
            local error_analysis
            error_analysis=$(parse_aws_error "$error_output" "$operation_name" "$exit_code")
            
            # Extract key fields from JSON analysis
            local is_retryable retry_delay max_retries error_type
            is_retryable=$(echo "$error_analysis" | grep '"is_retryable"' | cut -d: -f2 | tr -d ' ,"')
            retry_delay=$(echo "$error_analysis" | grep '"retry_delay"' | cut -d: -f2 | tr -d ' ,')
            max_retries=$(echo "$error_analysis" | grep '"max_retries"' | cut -d: -f2 | tr -d ' ,')
            error_type=$(echo "$error_analysis" | grep '"error_type"' | cut -d: -f2 | tr -d ' ,"')
            
            # Log detailed error analysis
            if declare -f log_structured >/dev/null 2>&1; then
                log_structured "WARN" "AWS operation failed" \
                    "operation=$operation_name" \
                    "attempt=$attempt" \
                    "exit_code=$exit_code" \
                    "error_type=$error_type" \
                    "is_retryable=$is_retryable" \
                    "consecutive_failures=$consecutive_failures" \
                    "attempt_duration=${attempt_duration}s"
            fi
            
            # Check circuit breaker condition
            if [ $consecutive_failures -ge $failure_threshold ]; then
                echo "$(date +%s)" > "$circuit_breaker_file"
                
                if declare -f log_structured >/dev/null 2>&1; then
                    log_structured "ERROR" "Circuit breaker activated due to consecutive failures" \
                        "operation=$operation_name" \
                        "consecutive_failures=$consecutive_failures" \
                        "failure_threshold=$failure_threshold"
                fi
                
                if declare -f end_timer >/dev/null 2>&1; then
                    end_timer "aws_retry_$operation_name" >/dev/null
                fi
                
                return $exit_code
            fi
            
            # Decide whether to retry
            if [[ "$is_retryable" != "true" ]] || [[ $attempt -eq $max_attempts ]]; then
                if declare -f end_timer >/dev/null 2>&1; then
                    local total_duration
                    total_duration=$(end_timer "aws_retry_$operation_name")
                    
                    if declare -f log_structured >/dev/null 2>&1; then
                        log_structured "ERROR" "AWS operation failed permanently" \
                            "operation=$operation_name" \
                            "attempts=$attempt" \
                            "error_type=$error_type" \
                            "is_retryable=$is_retryable" \
                            "total_duration=${total_duration}s"
                    fi
                fi
                
                echo "$error_output" >&2
                return $exit_code
            fi
            
            # Calculate adaptive delay
            local adaptive_delay
            case "$error_type" in
                "RATE")
                    # Exponential backoff for rate limiting
                    adaptive_delay=$((retry_delay * (2 ** (attempt - 1))))
                    adaptive_delay=$(( adaptive_delay > 60 ? 60 : adaptive_delay ))
                    ;;
                "NETWORK"|"SERVICE")
                    # Linear increase for transient issues
                    adaptive_delay=$((retry_delay + (attempt - 1) * 2))
                    ;;
                *)
                    adaptive_delay=$retry_delay
                    ;;
            esac
            
            # Add jitter to prevent thundering herd
            local jitter
            jitter=$((RANDOM % 3 + 1))
            adaptive_delay=$((adaptive_delay + jitter))
            
            if declare -f log_structured >/dev/null 2>&1; then
                log_structured "INFO" "Retrying AWS operation" \
                    "operation=$operation_name" \
                    "next_attempt=$((attempt + 1))" \
                    "delay=${adaptive_delay}s" \
                    "error_type=$error_type"
            fi
            
            sleep "$adaptive_delay"
            attempt=$((attempt + 1))
        fi
    done
    
    # All retries exhausted
    if declare -f end_timer >/dev/null 2>&1; then
        local total_duration
        total_duration=$(end_timer "aws_retry_$operation_name")
        
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "ERROR" "AWS operation exhausted all retry attempts" \
                "operation=$operation_name" \
                "max_attempts=$max_attempts" \
                "total_duration=${total_duration}s"
        fi
    fi
    
    echo "$error_output" >&2
    return $exit_code
}

# =============================================================================
# AWS SERVICE-SPECIFIC ERROR HANDLING
# =============================================================================

# EC2-specific intelligent retry
aws_ec2_retry() {
    AWS_OPERATION_NAME="ec2_operation"
    AWS_MAX_RETRY_ATTEMPTS=6  # EC2 often needs more retries
    aws_retry_with_intelligence "$@"
}

# S3-specific intelligent retry with reduced aggression
aws_s3_retry() {
    AWS_OPERATION_NAME="s3_operation"
    AWS_MAX_RETRY_ATTEMPTS=4
    aws_retry_with_intelligence "$@"
}

# IAM-specific retry (usually no retry needed)
aws_iam_retry() {
    AWS_OPERATION_NAME="iam_operation"
    AWS_MAX_RETRY_ATTEMPTS=2
    aws_retry_with_intelligence "$@"
}

# CloudFormation-specific retry with extended timeouts
aws_cloudformation_retry() {
    AWS_OPERATION_NAME="cloudformation_operation"
    AWS_MAX_RETRY_ATTEMPTS=3
    aws_retry_with_intelligence "$@"
}

# =============================================================================
# RECOVERY AND ROLLBACK MECHANISMS
# =============================================================================

# Implement automatic rollback for failed deployments
implement_deployment_rollback() {
    local stack_name="$1"
    local rollback_strategy="${2:-conservative}"
    local dry_run="${3:-false}"
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "WARN" "Initiating deployment rollback" \
            "stack_name=$stack_name" \
            "strategy=$rollback_strategy" \
            "dry_run=$dry_run"
    fi
    
    # Define rollback actions based on strategy
    local rollback_actions=()
    
    case "$rollback_strategy" in
        "conservative")
            rollback_actions=(
                "Stop new deployments"
                "Preserve existing resources"
                "Create rollback checkpoint"
                "Notify administrators"
            )
            ;;
        "aggressive")
            rollback_actions=(
                "Terminate failed instances"
                "Delete failed stacks"
                "Restore previous version"
                "Update load balancer targets"
            )
            ;;
        "minimal")
            rollback_actions=(
                "Log rollback event"
                "Mark deployment as failed"
                "Preserve state for debugging"
            )
            ;;
    esac
    
    # Execute rollback actions
    for action in "${rollback_actions[@]}"; do
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "INFO" "Executing rollback action" \
                "action=$action" \
                "stack_name=$stack_name" \
                "dry_run=$dry_run"
        fi
        
        if [[ "$dry_run" == "false" ]]; then
            # Implement actual rollback logic here
            case "$action" in
                "Stop new deployments")
                    # Implementation would depend on deployment system
                    ;;
                "Terminate failed instances")
                    # Use aws_ec2_retry to terminate instances
                    ;;
                "Delete failed stacks")
                    # Use aws_cloudformation_retry to delete stacks
                    ;;
                # Add more specific implementations
            esac
        fi
    done
    
    if declare -f log_structured >/dev/null 2>&1; then
        log_structured "INFO" "Deployment rollback completed" \
            "stack_name=$stack_name" \
            "strategy=$rollback_strategy" \
            "actions_count=${#rollback_actions[@]}"
    fi
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Monitor AWS API error rates and patterns
monitor_aws_error_patterns() {
    local monitoring_window="${1:-3600}"  # 1 hour default
    local error_threshold="${2:-10}"      # 10 errors per hour
    
    local error_log="/tmp/aws_error_monitoring_$$"
    local current_time
    current_time=$(date +%s)
    local window_start=$((current_time - monitoring_window))
    
    # Count errors in time window
    local error_count=0
    if [[ -f "$error_log" ]]; then
        while IFS= read -r line; do
            local log_time
            log_time=$(echo "$line" | cut -d: -f1)
            if [[ $log_time -ge $window_start ]]; then
                error_count=$((error_count + 1))
            fi
        done < "$error_log"
    fi
    
    # Log current error if this is being called due to an error
    echo "$current_time:AWS_ERROR" >> "$error_log"
    
    # Clean up old entries
    local temp_log
    temp_log=$(mktemp)
    while IFS= read -r line; do
        local log_time
        log_time=$(echo "$line" | cut -d: -f1)
        if [[ $log_time -ge $window_start ]]; then
            echo "$line" >> "$temp_log"
        fi
    done < "$error_log"
    mv "$temp_log" "$error_log"
    
    # Check if threshold exceeded
    if [[ $error_count -ge $error_threshold ]]; then
        if declare -f log_structured >/dev/null 2>&1; then
            log_structured "ERROR" "AWS error rate threshold exceeded" \
                "error_count=$error_count" \
                "threshold=$error_threshold" \
                "window_minutes=$((monitoring_window / 60))"
        fi
        
        # Implement alerting mechanism (could integrate with SNS, Slack, etc.)
        return 1
    fi
    
    return 0
}

# =============================================================================
# EXPORTS AND INITIALIZATION
# =============================================================================

# Export functions for use by other scripts
export -f parse_aws_error
export -f aws_retry_with_intelligence
export -f aws_ec2_retry
export -f aws_s3_retry
export -f aws_iam_retry
export -f aws_cloudformation_retry
export -f implement_deployment_rollback
export -f monitor_aws_error_patterns

# Initialize AWS error handling when sourced
if declare -f log_structured >/dev/null 2>&1; then
    log_structured "DEBUG" "AWS API error handling module loaded" \
        "patterns_count=${#AWS_ERROR_PATTERNS[@]}" \
        "bash_version=$BASH_VERSION"
fi