#!/usr/bin/env bash
# =============================================================================
# AWS CLI v2 Enhanced Library
# Modern AWS CLI v2 compliance with best practices
# Requires: bash 5.3.3+, AWS CLI v2
# =============================================================================

# Bash version validation
if [[ -z "${BASH_VERSION_VALIDATED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/modules/core/bash_version.sh"
    require_bash_533 "aws-cli-v2.sh"
    export BASH_VERSION_VALIDATED=true
fi

# Load common logging functions
source "$SCRIPT_DIR/aws-deployment-common.sh"

# =============================================================================
# AWS CLI V2 CONFIGURATION AND VALIDATION
# =============================================================================

# AWS CLI v2 version requirement
require_aws_cli_v2() {
    local min_version="2.0.0"
    
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI is not installed. Please install AWS CLI v2"
        return 1
    fi
    
    local aws_version
    aws_version=$(aws --version 2>&1 | head -1 | cut -d' ' -f1 | cut -d'/' -f2)
    
    if [[ ! "$aws_version" =~ ^2\. ]]; then
        error "AWS CLI v1 detected ($aws_version). This library requires AWS CLI v2 ($min_version or higher)"
        error "Please upgrade to AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        return 1
    fi
    
    success "AWS CLI v2 detected: $aws_version"
    return 0
}

# =============================================================================
# ENHANCED CREDENTIAL AND PROFILE MANAGEMENT
# =============================================================================

# Validate AWS credentials with enhanced error handling
validate_aws_credentials() {
    local profile="${1:-default}"
    local region="${2:-$AWS_REGION}"
    
    log "Validating AWS credentials for profile: $profile"
    
    # Set profile environment variable if not default
    if [[ "$profile" != "default" ]]; then
        export AWS_PROFILE="$profile"
    fi
    
    # Set region if provided
    if [[ -n "$region" ]]; then
        export AWS_DEFAULT_REGION="$region"
    fi
    
    # Test credentials with simple AWS CLI call (more reliable than retry mechanism)
    if aws sts get-caller-identity --output json >/dev/null 2>&1; then
        local caller_identity
        caller_identity=$(aws sts get-caller-identity --output json)
        
        local account_id user_arn
        account_id=$(echo "$caller_identity" | jq -r '.Account // "unknown"')
        user_arn=$(echo "$caller_identity" | jq -r '.Arn // "unknown"')
        
        success "AWS credentials validated successfully"
        info "  Account ID: $account_id"
        info "  User/Role: $user_arn"
        info "  Profile: $profile"
        info "  Region: ${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo 'not set')}"
        return 0
    else
        error "AWS credential validation failed"
        error "Please check your AWS credentials and configuration"
        error "Common fixes:"
        error "  1. Run 'aws configure' to set up credentials"
        error "  2. Set AWS_PROFILE environment variable"
        error "  3. Check ~/.aws/credentials and ~/.aws/config files"
        error "  4. Verify IAM permissions"
        return 1
    fi
}

# Enhanced region validation with availability zone checking
validate_aws_region() {
    local region="${1:-$AWS_DEFAULT_REGION}"
    
    if [[ -z "$region" ]]; then
        error "No AWS region specified. Set AWS_DEFAULT_REGION or use --region parameter"
        return 1
    fi
    
    log "Validating AWS region: $region"
    
    # Check if region exists and is accessible (simplified approach)
    if aws ec2 describe-availability-zones --region "$region" --output json >/dev/null 2>&1; then
        local az_count
        az_count=$(aws ec2 describe-availability-zones --region "$region" --query 'length(AvailabilityZones)' --output text)
        
        success "AWS region $region validated successfully"
        info "  Available zones: $az_count"
        
        # Set region as default for session
        export AWS_DEFAULT_REGION="$region"
        return 0
    else
        error "AWS region $region is not accessible or does not exist"
        error "Available regions for your account:"
        aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n' | head -10 || true
        return 1
    fi
}

# =============================================================================
# ADVANCED AWS CLI WRAPPER WITH RETRY LOGIC
# =============================================================================

# Enhanced AWS CLI wrapper with comprehensive error handling and retries
aws_cli_with_retry() {
    local service="$1"
    local operation="$2"
    shift 2
    local args=("$@")
    
    local max_attempts=5
    local base_delay=1
    local max_delay=60
    local attempt=1
    
    # Rate limiting: track and enforce API call limits
    local rate_limit_key="${service}_${operation}"
    enforce_rate_limit "$rate_limit_key"
    
    while [[ $attempt -le $max_attempts ]]; do
        local start_time=$(date +%s)
        
        # Execute AWS CLI command with timeout (macOS compatible)
        local aws_result aws_exit_code
        set +e
        if command -v timeout >/dev/null 2>&1; then
            aws_result=$(timeout 300 aws "$service" "$operation" "${args[@]}" 2>&1)
            aws_exit_code=$?
        else
            # macOS doesn't have timeout by default, use gtimeout if available or skip timeout
            if command -v gtimeout >/dev/null 2>&1; then
                aws_result=$(gtimeout 300 aws "$service" "$operation" "${args[@]}" 2>&1)
                aws_exit_code=$?
            else
                aws_result=$(aws "$service" "$operation" "${args[@]}" 2>&1)
                aws_exit_code=$?
            fi
        fi
        set -e
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Log API call for monitoring
        log_aws_api_call "$service" "$operation" "$aws_exit_code" "$duration" "$attempt"
        
        case $aws_exit_code in
            0)
                # Success
                echo "$aws_result"
                return 0
                ;;
            130|143)
                # Timeout or interrupt
                error "AWS CLI command timed out or was interrupted (attempt $attempt/$max_attempts)"
                ;;
            254)
                # Rate limiting or throttling
                local delay
                delay=$(calculate_exponential_backoff "$attempt" "$base_delay" "$max_delay")
                warning "AWS API rate limit exceeded. Backing off for ${delay}s (attempt $attempt/$max_attempts)"
                sleep "$delay"
                ;;
            253)
                # Service unavailable
                local delay
                delay=$(calculate_exponential_backoff "$attempt" "$base_delay" "$max_delay")
                warning "AWS service temporarily unavailable. Retrying in ${delay}s (attempt $attempt/$max_attempts)"
                sleep "$delay"
                ;;
            252)
                # Authentication error - don't retry
                error "AWS authentication failed. Please check your credentials"
                echo "$aws_result" >&2
                return $aws_exit_code
                ;;
            251)
                # Authorization error - don't retry
                error "AWS authorization failed. Please check your IAM permissions"
                echo "$aws_result" >&2
                return $aws_exit_code
                ;;
            *)
                # Other errors - check if retryable
                if is_retryable_error "$aws_result"; then
                    local delay
                    delay=$(calculate_exponential_backoff "$attempt" "$base_delay" "$max_delay")
                    warning "Retryable AWS error detected. Retrying in ${delay}s (attempt $attempt/$max_attempts)"
                    warning "Error: $(echo "$aws_result" | head -1)"
                    sleep "$delay"
                else
                    error "Non-retryable AWS error encountered"
                    echo "$aws_result" >&2
                    return $aws_exit_code
                fi
                ;;
        esac
        
        ((attempt++))
    done
    
    error "AWS CLI command failed after $max_attempts attempts: aws $service $operation"
    return 1
}

# Calculate exponential backoff with jitter
calculate_exponential_backoff() {
    local attempt="$1"
    local base_delay="$2"
    local max_delay="$3"
    
    # Exponential backoff: base_delay * (2^(attempt-1))
    local delay=$((base_delay * (1 << (attempt - 1))))
    
    # Cap at max_delay
    if [[ $delay -gt $max_delay ]]; then
        delay=$max_delay
    fi
    
    # Add jitter (random 0-25% of delay)
    local jitter=$((delay / 4))
    if command -v shuf >/dev/null 2>&1; then
        local random_jitter
        random_jitter=$(shuf -i 0-"$jitter" -n 1)
        delay=$((delay + random_jitter))
    fi
    
    echo "$delay"
}

# Check if AWS error is retryable
is_retryable_error() {
    local error_message="$1"
    
    # Common retryable error patterns
    local retryable_patterns=(
        "RequestLimitExceeded"
        "Throttling"
        "ThrottlingException"
        "ServiceUnavailable"
        "InternalError"
        "InternalFailure"
        "RequestTimeout"
        "RequestTimeoutException"
        "Network error"
        "Connection reset"
        "Connection timed out"
        "Name resolution failed"
        "Could not connect"
    )
    
    for pattern in "${retryable_patterns[@]}"; do
        if echo "$error_message" | grep -qi "$pattern"; then
            return 0
        fi
    done
    
    return 1
}

# =============================================================================
# RATE LIMITING AND API CALL MONITORING
# =============================================================================

# Rate limiting implementation
declare -A AWS_API_CALL_TIMESTAMPS
declare -A AWS_API_CALL_COUNTS

# Enforce rate limiting for AWS API calls
enforce_rate_limit() {
    local api_key="$1"
    local max_calls_per_minute="${2:-100}"  # Conservative default
    local current_time=$(date +%s)
    local minute_window=$((current_time / 60))
    local rate_key="${api_key}_${minute_window}"
    
    # Get current call count for this minute
    local current_count="${AWS_API_CALL_COUNTS[$rate_key]:-0}"
    
    if [[ $current_count -ge $max_calls_per_minute ]]; then
        local sleep_time=$((60 - (current_time % 60)))
        warning "Rate limit reached for $api_key. Sleeping for ${sleep_time}s"
        sleep "$sleep_time"
        # Reset for new minute
        minute_window=$(date +%s)
        minute_window=$((minute_window / 60))
        rate_key="${api_key}_${minute_window}"
        current_count=0
    fi
    
    # Increment counter
    AWS_API_CALL_COUNTS[$rate_key]=$((current_count + 1))
    
    # Add small delay between API calls
    local last_call_time="${AWS_API_CALL_TIMESTAMPS[$api_key]:-0}"
    local min_interval=0.1
    local time_since_last_call=$(echo "$current_time - $last_call_time" | bc -l 2>/dev/null || echo "1")
    
    if command -v bc >/dev/null 2>&1 && (( $(echo "$time_since_last_call < $min_interval" | bc -l) )); then
        local sleep_time
        sleep_time=$(echo "$min_interval - $time_since_last_call" | bc -l)
        sleep "$sleep_time"
    fi
    
    AWS_API_CALL_TIMESTAMPS[$api_key]="$current_time"
}

# Log AWS API calls for monitoring and debugging
log_aws_api_call() {
    local service="$1"
    local operation="$2"
    local exit_code="$3"
    local duration="$4"
    local attempt="$5"
    
    local log_entry="$(date -u +%Y-%m-%dT%H:%M:%SZ) $service:$operation exit_code=$exit_code duration=${duration}s attempt=$attempt"
    
    # Log to file if LOG_AWS_CALLS is set
    if [[ -n "${LOG_AWS_CALLS:-}" ]]; then
        echo "$log_entry" >> "${LOG_AWS_CALLS}"
    fi
    
    # Debug logging
    if [[ "${DEBUG:-false}" == "true" ]]; then
        info "AWS API: $log_entry"
    fi
}

# =============================================================================
# PAGINATION HELPERS FOR AWS CLI V2
# =============================================================================

# Enhanced pagination wrapper for AWS CLI v2
aws_paginate() {
    local service="$1"
    local operation="$2"
    shift 2
    local args=("$@")
    
    # Check if operation supports pagination
    if ! supports_pagination "$service" "$operation"; then
        # Fallback to regular call
        aws_cli_with_retry "$service" "$operation" "${args[@]}"
        return $?
    fi
    
    log "Using pagination for aws $service $operation"
    
    # Use AWS CLI v2 built-in pagination with --max-items and --starting-token
    local max_items="${AWS_CLI_MAX_ITEMS:-1000}"
    local all_results="[]"
    local next_token=""
    local page=1
    
    while true; do
        info "Fetching page $page (max-items: $max_items)"
        
        local page_args=("${args[@]}" --max-items "$max_items" --output json)
        
        # Add starting token if we have one
        if [[ -n "$next_token" ]]; then
            page_args+=(--starting-token "$next_token")
        fi
        
        local page_result
        page_result=$(aws_cli_with_retry "$service" "$operation" "${page_args[@]}")
        
        if [[ $? -ne 0 ]]; then
            error "Pagination failed on page $page"
            return 1
        fi
        
        # Extract results and next token
        local page_data next_token_json
        page_data=$(echo "$page_result" | jq -c 'del(.NextToken)')
        next_token_json=$(echo "$page_result" | jq -r '.NextToken // empty')
        
        # Merge results
        if command -v jq >/dev/null 2>&1; then
            all_results=$(echo "$all_results $page_data" | jq -s '.[0] * .[1]')
        else
            # Fallback without jq
            echo "$page_result"
        fi
        
        # Check if we have more pages
        if [[ -z "$next_token_json" ]] || [[ "$next_token_json" == "null" ]]; then
            break
        fi
        
        next_token="$next_token_json"
        ((page++))
        
        # Safety check to prevent infinite loops
        if [[ $page -gt 100 ]]; then
            warning "Pagination stopped after 100 pages to prevent infinite loop"
            break
        fi
    done
    
    success "Pagination completed: $page pages processed"
    echo "$all_results"
    return 0
}

# Check if AWS service operation supports pagination
supports_pagination() {
    local service="$1"
    local operation="$2"
    
    # Common paginated operations
    case "$service:$operation" in
        "ec2:describe-instances"|\
        "ec2:describe-security-groups"|\
        "ec2:describe-subnets"|\
        "ec2:describe-vpcs"|\
        "ec2:describe-availability-zones"|\
        "ec2:describe-images"|\
        "ec2:describe-spot-instance-requests"|\
        "ec2:describe-spot-price-history"|\
        "elbv2:describe-load-balancers"|\
        "elbv2:describe-target-groups"|\
        "efs:describe-file-systems"|\
        "ssm:describe-parameters"|\
        "ssm:get-parameters-by-path"|\
        "cloudformation:describe-stacks"|\
        "cloudformation:describe-stack-events"|\
        "cloudfront:list-distributions"|\
        "iam:list-roles"|\
        "iam:list-policies")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# ENHANCED ERROR HANDLING AND CIRCUIT BREAKER
# =============================================================================

# Circuit breaker implementation for AWS services
declare -A AWS_SERVICE_CIRCUIT_BREAKERS
declare -A AWS_SERVICE_FAILURE_COUNTS
declare -A AWS_SERVICE_LAST_FAILURE_TIME

# Circuit breaker states
readonly CB_CLOSED=0
readonly CB_OPEN=1
readonly CB_HALF_OPEN=2

# Initialize circuit breaker for a service
init_circuit_breaker() {
    local service="$1"
    local failure_threshold="${2:-5}"
    local timeout_duration="${3:-60}"
    
    AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]=$CB_CLOSED
    AWS_SERVICE_CIRCUIT_BREAKERS["${service}:threshold"]="$failure_threshold"
    AWS_SERVICE_CIRCUIT_BREAKERS["${service}:timeout"]="$timeout_duration"
    AWS_SERVICE_FAILURE_COUNTS["$service"]=0
    AWS_SERVICE_LAST_FAILURE_TIME["$service"]=0
}

# Check circuit breaker state before making AWS call
check_circuit_breaker() {
    local service="$1"
    
    # Initialize if not exists
    if [[ -z "${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]:-}" ]]; then
        init_circuit_breaker "$service"
    fi
    
    local state="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]}"
    local threshold="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:threshold"]}"
    local timeout="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:timeout"]}"
    local failure_count="${AWS_SERVICE_FAILURE_COUNTS["$service"]}"
    local last_failure="${AWS_SERVICE_LAST_FAILURE_TIME["$service"]}"
    local current_time=$(date +%s)
    
    case $state in
        $CB_CLOSED)
            # Normal operation
            return 0
            ;;
        $CB_OPEN)
            # Check if timeout has passed
            if [[ $((current_time - last_failure)) -gt $timeout ]]; then
                # Move to half-open
                AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]=$CB_HALF_OPEN
                info "Circuit breaker for $service moved to HALF-OPEN state"
                return 0
            else
                warning "Circuit breaker for $service is OPEN. Calls blocked."
                return 1
            fi
            ;;
        $CB_HALF_OPEN)
            # Allow one call to test
            return 0
            ;;
    esac
}

# Record circuit breaker result
record_circuit_breaker_result() {
    local service="$1"
    local success="$2"  # true/false
    
    local state="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]}"
    local threshold="${AWS_SERVICE_CIRCUIT_BREAKERS["${service}:threshold"]}"
    local current_time=$(date +%s)
    
    if [[ "$success" == "true" ]]; then
        # Success - reset failure count and close circuit
        AWS_SERVICE_FAILURE_COUNTS["$service"]=0
        if [[ $state != $CB_CLOSED ]]; then
            AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]=$CB_CLOSED
            success "Circuit breaker for $service moved to CLOSED state"
        fi
    else
        # Failure - increment count
        local failure_count="${AWS_SERVICE_FAILURE_COUNTS["$service"]}"
        ((failure_count++))
        AWS_SERVICE_FAILURE_COUNTS["$service"]="$failure_count"
        AWS_SERVICE_LAST_FAILURE_TIME["$service"]="$current_time"
        
        # Check if we should open the circuit
        if [[ $failure_count -ge $threshold ]] && [[ $state == $CB_CLOSED ]]; then
            AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]=$CB_OPEN
            warning "Circuit breaker for $service moved to OPEN state after $failure_count failures"
        elif [[ $state == $CB_HALF_OPEN ]]; then
            AWS_SERVICE_CIRCUIT_BREAKERS["${service}:state"]=$CB_OPEN
            warning "Circuit breaker for $service moved back to OPEN state"
        fi
    fi
}

# =============================================================================
# MODERN AUTHENTICATION AND SSO SUPPORT
# =============================================================================

# Setup AWS SSO authentication
setup_aws_sso() {
    local sso_start_url="$1"
    local sso_region="$2"
    local profile_name="${3:-sso}"
    
    if [[ -z "$sso_start_url" ]] || [[ -z "$sso_region" ]]; then
        error "setup_aws_sso requires sso_start_url and sso_region parameters"
        return 1
    fi
    
    log "Setting up AWS SSO authentication"
    
    # Configure SSO profile
    aws configure set sso_start_url "$sso_start_url" --profile "$profile_name"
    aws configure set sso_region "$sso_region" --profile "$profile_name"
    aws configure set region "$sso_region" --profile "$profile_name"
    aws configure set output json --profile "$profile_name"
    
    # Initiate SSO login
    if aws sso login --profile "$profile_name"; then
        success "AWS SSO login successful for profile: $profile_name"
        export AWS_PROFILE="$profile_name"
        
        # Validate the SSO session
        if validate_aws_credentials "$profile_name"; then
            success "AWS SSO setup completed successfully"
            return 0
        else
            error "AWS SSO validation failed"
            return 1
        fi
    else
        error "AWS SSO login failed"
        return 1
    fi
}

# Check and refresh AWS SSO session
refresh_aws_sso_session() {
    local profile="${1:-$AWS_PROFILE}"
    
    if [[ -z "$profile" ]]; then
        error "No AWS profile specified for SSO refresh"
        return 1
    fi
    
    # Check if profile uses SSO
    local sso_start_url
    sso_start_url=$(aws configure get sso_start_url --profile "$profile" 2>/dev/null)
    
    if [[ -z "$sso_start_url" ]]; then
        # Not an SSO profile, skip
        return 0
    fi
    
    log "Checking AWS SSO session for profile: $profile"
    
    # Test current session
    if aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
        info "AWS SSO session is valid"
        return 0
    else
        warning "AWS SSO session expired. Attempting refresh..."
        
        # Try to refresh session
        if aws sso login --profile "$profile"; then
            success "AWS SSO session refreshed successfully"
            return 0
        else
            error "Failed to refresh AWS SSO session"
            return 1
        fi
    fi
}

# =============================================================================
# INTELLIGENT CACHING SYSTEM
# =============================================================================

# Initialize cache directory
AWS_CACHE_DIR="${AWS_CACHE_DIR:-${HOME}/.cache/geuse-maker-aws}"
mkdir -p "$AWS_CACHE_DIR"

# Cache AWS API responses with TTL
cache_aws_response() {
    local cache_key="$1"
    local response="$2"
    local ttl_seconds="${3:-3600}"  # 1 hour default
    
    local cache_file="$AWS_CACHE_DIR/$(echo "$cache_key" | tr '/' '_')"
    local timestamp=$(date +%s)
    
    # Create cache entry with metadata
    local cache_entry
    cache_entry=$(jq -n \
        --arg timestamp "$timestamp" \
        --arg ttl "$ttl_seconds" \
        --argjson data "$response" \
        '{timestamp: $timestamp | tonumber, ttl: $ttl | tonumber, data: $data}')
    
    echo "$cache_entry" > "$cache_file"
}

# Retrieve cached AWS response if valid
get_cached_aws_response() {
    local cache_key="$1"
    local cache_file="$AWS_CACHE_DIR/$(echo "$cache_key" | tr '/' '_')"
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    local cache_content
    cache_content=$(cat "$cache_file" 2>/dev/null) || return 1
    
    local timestamp ttl current_time
    timestamp=$(echo "$cache_content" | jq -r '.timestamp // 0')
    ttl=$(echo "$cache_content" | jq -r '.ttl // 0')
    current_time=$(date +%s)
    
    # Check if cache is still valid
    if [[ $((current_time - timestamp)) -lt $ttl ]]; then
        echo "$cache_content" | jq -r '.data'
        return 0
    else
        # Cache expired, remove file
        rm -f "$cache_file"
        return 1
    fi
}

# Cached AWS CLI wrapper
aws_cli_cached() {
    local cache_ttl="${1:-3600}"
    shift
    local service="$1"
    local operation="$2"
    shift 2
    local args=("$@")
    
    # Create cache key from command
    local cache_key="${service}:${operation}:$(echo "${args[*]}" | sha256sum | cut -d' ' -f1)"
    
    # Try to get cached response
    local cached_response
    if cached_response=$(get_cached_aws_response "$cache_key"); then
        info "Using cached response for aws $service $operation"
        echo "$cached_response"
        return 0
    fi
    
    # No valid cache, make API call
    local response
    if response=$(aws_cli_with_retry "$service" "$operation" "${args[@]}"); then
        # Cache successful response
        cache_aws_response "$cache_key" "$response" "$cache_ttl"
        echo "$response"
        return 0
    else
        return $?
    fi
}

# Clean up expired cache entries
cleanup_aws_cache() {
    local cache_retention_days="${1:-7}"
    
    if [[ ! -d "$AWS_CACHE_DIR" ]]; then
        return 0
    fi
    
    log "Cleaning up AWS cache older than $cache_retention_days days"
    
    find "$AWS_CACHE_DIR" -type f -mtime +"$cache_retention_days" -delete 2>/dev/null || true
    
    local remaining_files
    remaining_files=$(find "$AWS_CACHE_DIR" -type f | wc -l)
    info "AWS cache cleanup completed. $remaining_files files remaining."
}

# =============================================================================
# HEALTH CHECKS AND MONITORING
# =============================================================================

# Comprehensive AWS service health check
aws_service_health_check() {
    local services=("${@:-ec2 elbv2 efs ssm cloudformation}")
    local overall_status=0
    
    log "Performing AWS service health check"
    
    for service in ${services[*]}; do
        info "Checking $service service health..."
        
        # Initialize circuit breaker
        init_circuit_breaker "$service"
        
        # Check circuit breaker state
        if ! check_circuit_breaker "$service"; then
            warning "Service $service is unavailable (circuit breaker open)"
            overall_status=1
            continue
        fi
        
        # Perform service-specific health check
        local health_check_result=0
        case "$service" in
            "ec2")
                aws_cli_with_retry "ec2" "describe-regions" --max-items 1 >/dev/null 2>&1 || health_check_result=1
                ;;
            "elbv2")
                aws_cli_with_retry "elbv2" "describe-load-balancers" --max-items 1 >/dev/null 2>&1 || health_check_result=1
                ;;
            "efs")
                aws_cli_with_retry "efs" "describe-file-systems" --max-items 1 >/dev/null 2>&1 || health_check_result=1
                ;;
            "ssm")
                aws_cli_with_retry "ssm" "describe-parameters" --max-items 1 >/dev/null 2>&1 || health_check_result=1
                ;;
            "cloudformation")
                aws_cli_with_retry "cloudformation" "describe-stacks" --max-items 1 >/dev/null 2>&1 || health_check_result=1
                ;;
            *)
                warning "Unknown service for health check: $service"
                health_check_result=1
                ;;
        esac
        
        # Record result in circuit breaker
        if [[ $health_check_result -eq 0 ]]; then
            record_circuit_breaker_result "$service" "true"
            success "Service $service is healthy"
        else
            record_circuit_breaker_result "$service" "false"
            error "Service $service is unhealthy"
            overall_status=1
        fi
    done
    
    if [[ $overall_status -eq 0 ]]; then
        success "All AWS services are healthy"
    else
        warning "Some AWS services are unhealthy"
    fi
    
    return $overall_status
}

# =============================================================================
# INITIALIZATION AND VALIDATION
# =============================================================================

# Initialize AWS CLI v2 environment
init_aws_cli_v2() {
    local profile="${1:-default}"
    local region="${2:-us-east-1}"
    
    log "Initializing AWS CLI v2 environment"
    
    # Validate AWS CLI v2
    if ! require_aws_cli_v2; then
        return 1
    fi
    
    # Set up environment
    export AWS_CLI_AUTO_PROMPT=off
    export AWS_PAGER=""  # Disable pager for non-interactive use
    export AWS_MAX_ATTEMPTS=1  # We handle retries ourselves
    export AWS_RETRY_MODE=standard
    
    # Validate credentials and region
    if ! validate_aws_credentials "$profile" "$region"; then
        return 1
    fi
    
    if ! validate_aws_region "$region"; then
        return 1
    fi
    
    # Check SSO session if applicable
    refresh_aws_sso_session "$profile" || true
    
    # Perform health check
    if ! aws_service_health_check; then
        warning "Some AWS services are not healthy, but continuing..."
    fi
    
    # Clean up old cache
    cleanup_aws_cache
    
    success "AWS CLI v2 environment initialized successfully"
    return 0
}

# Export key functions for use by other scripts
export -f aws_cli_with_retry
export -f aws_paginate
export -f aws_cli_cached
export -f validate_aws_credentials
export -f validate_aws_region
export -f init_aws_cli_v2
export -f aws_service_health_check
