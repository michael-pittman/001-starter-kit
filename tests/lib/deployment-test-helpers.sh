#!/usr/bin/env bash
# deployment-test-helpers.sh - Helper functions for deployment testing
# Provides simulation utilities, mock functions, and test helpers

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "deployment-test-helpers.sh" "core/variables" "core/logging"

# Guard against multiple inclusion
[[ -n "${_DEPLOYMENT_TEST_HELPERS_LOADED:-}" ]] && return 0
declare -g _DEPLOYMENT_TEST_HELPERS_LOADED=1

# Global test state
declare -gA TEST_STATE=(
    [resources_created]=0
    [resources_cleaned]=0
    [api_calls]=0
    [failures_injected]=0
    [retries_attempted]=0
)

# Mock resource tracking
declare -gA MOCK_RESOURCES=()

# Failure injection helpers
# -------------------------

inject_failure() {
    local failure_type="$1"
    local duration="${2:-1}"  # Number of calls to fail
    
    FAILURE_MODES["$failure_type"]=$duration
    ((TEST_STATE[failures_injected]++))
    
    log_test "Injected failure: $failure_type (duration: $duration)"
}

clear_failure() {
    local failure_type="$1"
    FAILURE_MODES["$failure_type"]=0
    log_test "Cleared failure: $failure_type"
}

should_fail() {
    local failure_type="$1"
    
    if [[ "${FAILURE_MODES[$failure_type]:-0}" -gt 0 ]]; then
        ((FAILURE_MODES[$failure_type]--))
        return 0
    fi
    return 1
}

# AWS API Simulation Helpers
# --------------------------

simulate_ec2_instance() {
    local instance_id="i-$(generate_id)"
    local state="${1:-running}"
    
    MOCK_RESOURCES["ec2:$instance_id"]=$(cat <<EOF
{
    "InstanceId": "$instance_id",
    "InstanceType": "g4dn.xlarge",
    "State": {"Name": "$state"},
    "PublicIpAddress": "$(generate_ip)",
    "PrivateIpAddress": "$(generate_private_ip)",
    "LaunchTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    echo "$instance_id"
}

simulate_vpc() {
    local vpc_id="vpc-$(generate_id)"
    
    MOCK_RESOURCES["vpc:$vpc_id"]=$(cat <<EOF
{
    "VpcId": "$vpc_id",
    "State": "available",
    "CidrBlock": "10.0.0.0/16",
    "IsDefault": false
}
EOF
)
    
    echo "$vpc_id"
}

simulate_efs() {
    local fs_id="fs-$(generate_id)"
    
    MOCK_RESOURCES["efs:$fs_id"]=$(cat <<EOF
{
    "FileSystemId": "$fs_id",
    "LifeCycleState": "available",
    "SizeInBytes": {"Value": 6144},
    "PerformanceMode": "generalPurpose"
}
EOF
)
    
    echo "$fs_id"
}

simulate_alb() {
    local lb_arn="arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-$(generate_id)/$(generate_id)"
    
    MOCK_RESOURCES["alb:$lb_arn"]=$(cat <<EOF
{
    "LoadBalancerArn": "$lb_arn",
    "DNSName": "test-$(generate_id).elb.amazonaws.com",
    "State": {"Code": "active"},
    "Type": "application",
    "Scheme": "internet-facing"
}
EOF
)
    
    echo "$lb_arn"
}

# Resource Management Helpers
# ---------------------------

register_resource_for_cleanup() {
    local resource_spec="$1"
    local resource_type="${resource_spec%%:*}"
    local resource_id="${resource_spec#*:}"
    
    MOCK_RESOURCES["cleanup:$resource_spec"]="pending"
    ((TEST_STATE[resources_created]++))
    
    log_test "Registered for cleanup: $resource_spec"
}

is_resource_cleaned_up() {
    local resource_spec="$1"
    
    [[ "${MOCK_RESOURCES[cleanup:$resource_spec]}" == "cleaned" ]]
}

cleanup_failed_deployment() {
    local cleaned=0
    
    for key in "${!MOCK_RESOURCES[@]}"; do
        if [[ "$key" =~ ^cleanup: ]]; then
            MOCK_RESOURCES["$key"]="cleaned"
            ((cleaned++))
            ((TEST_STATE[resources_cleaned]++))
        fi
    done
    
    log_test "Cleaned up $cleaned resources"
    return 0
}

# Deployment Simulation Helpers
# -----------------------------

handle_spot_instance_launch() {
    local instance_type="$1"
    local region="$2"
    
    ((TEST_STATE[api_calls]++))
    
    if should_fail "ec2_insufficient_capacity"; then
        echo "ERROR: Insufficient capacity for $instance_type in $region" >&2
        
        # Simulate retry
        ((TEST_STATE[retries_attempted]++))
        echo "Retrying with different availability zone..." >&2
        
        # Fail again to trigger fallback
        echo "ERROR: Still insufficient capacity" >&2
        echo "Falling back to on-demand instance..." >&2
        
        return 1
    fi
    
    local instance_id
    instance_id=$(simulate_ec2_instance "running")
    echo "Successfully launched spot instance: $instance_id"
    return 0
}

get_spot_price() {
    local instance_type="$1"
    local region="$2"
    
    ((TEST_STATE[api_calls]++))
    
    if should_fail "spot_price_too_high"; then
        echo "99.99"
    else
        # Return realistic spot prices
        case "$instance_type" in
            g4dn.xlarge) echo "0.21" ;;
            g5.xlarge) echo "0.18" ;;
            t3.medium) echo "0.015" ;;
            *) echo "0.10" ;;
        esac
    fi
}

should_use_ondemand() {
    local spot_price="$1"
    local threshold="${2:-1.0}"
    
    (( $(echo "$spot_price > $threshold" | bc -l) ))
}

check_service_quota() {
    local service="$1"
    local quota_code="$2"
    local region="$3"
    
    ((TEST_STATE[api_calls]++))
    
    if should_fail "quota_exceeded"; then
        echo "0"
    else
        echo "100"
    fi
}

validate_deployment_quotas() {
    local instance_type="$1"
    local region="$2"
    
    local quota
    quota=$(check_service_quota "ec2" "L-34B43A08" "$region")
    
    if [[ "$quota" -eq 0 ]]; then
        log_test "Quota validation failed: No available quota"
        return 1
    fi
    
    log_test "Quota validation passed: $quota available"
    return 0
}

validate_ami_availability() {
    local ami_id="$1"
    local region="$2"
    
    ((TEST_STATE[api_calls]++))
    
    if should_fail "ami_not_found"; then
        echo "ERROR: AMI not found: $ami_id" >&2
        return 1
    fi
    
    return 0
}

create_alb_with_fallback() {
    local alb_name="$1"
    local vpc_id="$2"
    
    ((TEST_STATE[api_calls]++))
    
    if should_fail "alb_creation_failed"; then
        echo "Warning: ALB creation failed, continuing without load balancer" >&2
        echo "Deployment will use direct instance access" >&2
        return 0  # Don't fail deployment
    fi
    
    local alb_arn
    alb_arn=$(simulate_alb)
    echo "Created ALB: $alb_arn"
    return 0
}

mount_efs_with_retry() {
    local fs_id="$1"
    local mount_point="$2"
    local attempt="${3:-1}"
    
    ((TEST_STATE[api_calls]++))
    
    if should_fail "efs_mount_failure"; then
        echo "ERROR: Failed to mount EFS $fs_id" >&2
        return 1
    fi
    
    echo "Successfully mounted EFS $fs_id at $mount_point"
    return 0
}

setup_fallback_storage() {
    local mount_point="$1"
    
    # Simulate local storage setup
    mkdir -p "$mount_point"
    echo "Set up local storage fallback at $mount_point"
    return 0
}

# Retry and Backoff Helpers
# -------------------------

calculate_backoff_delay() {
    local attempt="$1"
    local base_delay="${2:-1}"
    local max_delay="${3:-60}"
    
    local delay=$((base_delay * (2 ** attempt)))
    
    # Cap at max delay
    if [[ $delay -gt $max_delay ]]; then
        delay=$max_delay
    fi
    
    echo "$delay"
}

retry_with_backoff() {
    local max_attempts="$1"
    local command="$2"
    shift 2
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if $command "$@"; then
            return 0
        fi
        
        local delay
        delay=$(calculate_backoff_delay $attempt)
        log_test "Retry $((attempt + 1))/$max_attempts after ${delay}s"
        sleep "$delay"
        
        ((attempt++))
        ((TEST_STATE[retries_attempted]++))
    done
    
    return 1
}

launch_instance_with_failover() {
    local instance_type="$1"
    local region="$2"
    
    # Simulate launch
    if handle_spot_instance_launch "$instance_type" "$region"; then
        return 0
    fi
    
    # Failover handled in function
    return 1
}

# Service Degradation Helpers
# ---------------------------

can_degrade_service() {
    local service="$1"
    
    # Define which services can be degraded
    case "$service" in
        cloudfront|alb|monitoring)
            log_test "Service $service can be degraded"
            return 0
            ;;
        efs)
            log_test "Service $service can use local fallback"
            return 0
            ;;
        *)
            log_test "Service $service is critical, cannot degrade"
            return 1
            ;;
    esac
}

validate_core_services() {
    # Check critical services
    local core_services=("ec2" "docker" "network")
    
    for service in "${core_services[@]}"; do
        log_test "Validating core service: $service"
    done
    
    return 0
}

# Health Check Helpers
# --------------------

retry_health_check() {
    local service="$1"
    local port="$2"
    local max_attempts="${3:-3}"
    
    retry_with_backoff "$max_attempts" check_service_health "$service" "$port"
}

check_service_health() {
    local service="$1"
    local port="$2"
    
    ((TEST_STATE[api_calls]++))
    
    # Simulate health check
    if [[ $((RANDOM % 3)) -eq 0 ]]; then
        return 1  # Fail randomly
    fi
    
    return 0
}

# Deployment State Helpers
# ------------------------

init_deployment_state() {
    local stack_name="$1"
    
    declare -gA DEPLOYMENT_STATE=(
        [stack_name]="$stack_name"
        [phase]="initialization"
        [start_time]=$(date +%s)
        [status]="in_progress"
    )
    
    log_test "Initialized deployment state for $stack_name"
}

update_deployment_phase() {
    local phase="$1"
    local description="$2"
    
    DEPLOYMENT_STATE[phase]="$phase"
    DEPLOYMENT_STATE[phase_description]="$description"
    DEPLOYMENT_STATE[phase_start]=$(date +%s)
    
    log_test "Phase update: $phase - $description"
}

get_deployment_status() {
    echo "Phase: ${DEPLOYMENT_STATE[phase]}"
    echo "Status: ${DEPLOYMENT_STATE[status]}"
    echo "Duration: $(($(date +%s) - DEPLOYMENT_STATE[start_time]))s"
}

# Metrics Helpers
# ---------------

declare -gA DEPLOYMENT_METRICS=()

init_metrics_collection() {
    DEPLOYMENT_METRICS=()
    log_test "Initialized metrics collection"
}

record_metric() {
    local metric_name="$1"
    local value="$2"
    
    # Store as comma-separated values for multiple recordings
    if [[ -n "${DEPLOYMENT_METRICS[$metric_name]:-}" ]]; then
        DEPLOYMENT_METRICS["$metric_name"]="${DEPLOYMENT_METRICS[$metric_name]},$value"
    else
        DEPLOYMENT_METRICS["$metric_name"]="$value"
    fi
    
    log_test "Recorded metric: $metric_name=$value"
}

get_metrics_summary() {
    for metric in "${!DEPLOYMENT_METRICS[@]}"; do
        echo "$metric: ${DEPLOYMENT_METRICS[$metric]}"
    done
}

calculate_metric_average() {
    local metric_name="$1"
    local values="${DEPLOYMENT_METRICS[$metric_name]:-}"
    
    [[ -z "$values" ]] && return 1
    
    # Calculate average
    local sum=0
    local count=0
    
    IFS=',' read -ra value_array <<< "$values"
    for value in "${value_array[@]}"; do
        sum=$(echo "$sum + $value" | bc -l)
        ((count++))
    done
    
    echo "scale=2; $sum / $count" | bc -l
}

# Platform Compatibility Helpers
# ------------------------------

version_ge() {
    local version1="$1"
    local version2="$2"
    
    # Compare versions
    printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
}

parse_version() {
    local version="$1"
    local -n major_ref="$2"
    local -n minor_ref="$3"
    local -n patch_ref="${4:-_dummy}"
    
    # Extract version components
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))? ]]; then
        major_ref="${BASH_REMATCH[1]}"
        minor_ref="${BASH_REMATCH[2]}"
        patch_ref="${BASH_REMATCH[4]:-0}"
    else
        return 1
    fi
}

validate_aws_credentials() {
    # Check for AWS credentials
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -f ~/.aws/credentials ]]; then
        return 0
    fi
    return 1
}

check_iam_permission() {
    local permission="$1"
    
    # In test mode, simulate permission check
    if [[ "$TEST_MODE" == "simulation" ]]; then
        # Randomly deny some permissions
        if [[ $((RANDOM % 10)) -eq 0 ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Deployment Simulation Helpers
# -----------------------------

validate_deployment_prerequisites() {
    # Simulate prerequisite validation
    log_test "Validating deployment prerequisites"
    
    # Check bash version for enhanced features
    if ! version_ge "${BASH_VERSION}" "4.0.0"; then
        log_test "Info: Using bash 3.x compatibility mode"
    else
        log_test "Info: Enhanced bash features available"
    fi
    
    return 0
}

create_vpc_simulation() {
    local stack_name="$1"
    
    ((TEST_STATE[api_calls]++))
    
    local vpc_id
    vpc_id=$(simulate_vpc)
    
    log_test "Created VPC: $vpc_id"
    return 0
}

launch_instance_with_retry() {
    local instance_type="$1"
    local region="$2"
    
    retry_with_backoff 3 handle_spot_instance_launch "$instance_type" "$region"
}

deploy_services_simulation() {
    local instance_id="$1"
    
    log_test "Deploying services to instance $instance_id"
    
    # Simulate service deployment steps
    local services=("docker" "n8n" "ollama" "qdrant" "postgres")
    
    for service in "${services[@]}"; do
        log_test "  Deploying $service..."
        sleep 0.1
    done
    
    return 0
}

validate_deployment_health() {
    local stack_name="$1"
    
    log_test "Validating deployment health for $stack_name"
    
    # Simulate health checks
    if should_fail "health_check_failed"; then
        return 1
    fi
    
    return 0
}

simulate_deployment_scenario() {
    local options=("$@")
    
    log_test "Simulating deployment with options: ${options[*]}"
    
    # Parse options
    local use_spot=false
    local use_alb=false
    local use_cloudfront=false
    local multi_az=false
    
    for opt in "${options[@]}"; do
        case "$opt" in
            --spot) use_spot=true ;;
            --alb) use_alb=true ;;
            --cloudfront) use_cloudfront=true ;;
            --multi-az) multi_az=true ;;
        esac
    done
    
    # Simulate deployment based on options
    if [[ "$use_spot" == "true" ]]; then
        handle_spot_instance_launch "g4dn.xlarge" "us-east-1" || true
    fi
    
    if [[ "$use_alb" == "true" ]]; then
        create_alb_with_fallback "test-alb" "vpc-12345" || true
    fi
    
    return 0
}

# Utility Functions
# -----------------

generate_id() {
    # Generate random 8-character ID
    cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 8 | head -n 1
}

generate_ip() {
    # Generate random public IP
    echo "$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
}

generate_private_ip() {
    # Generate random private IP in 10.0.0.0/16
    echo "10.0.$((RANDOM % 256)).$((RANDOM % 256))"
}

log_test() {
    local message="$1"
    
    if [[ "${VERBOSE_OUTPUT:-false}" == "true" ]]; then
        echo "[TEST] $message" >&2
    fi
}

# Test Summary Function
# ---------------------

print_test_state_summary() {
    echo "Test Execution Summary:"
    echo "  Resources Created: ${TEST_STATE[resources_created]}"
    echo "  Resources Cleaned: ${TEST_STATE[resources_cleaned]}"
    echo "  API Calls Made: ${TEST_STATE[api_calls]}"
    echo "  Failures Injected: ${TEST_STATE[failures_injected]}"
    echo "  Retries Attempted: ${TEST_STATE[retries_attempted]}"
}

# Dummy variable for parse_version when patch not needed
declare _dummy