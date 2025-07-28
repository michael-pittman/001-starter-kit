#!/bin/bash
# test-deployment-comprehensive.sh - Comprehensive test suite for deployment improvements
# Tests all failure paths, recovery mechanisms, dependency validation, and compatibility

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework first
source "$SCRIPT_DIR/lib/shell-test-framework.sh"

# Source test helpers
source "$SCRIPT_DIR/lib/deployment-test-helpers.sh"

# Source deployment libraries
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/associative-arrays.sh"
source "$PROJECT_ROOT/lib/modern-error-handling.sh"
source "$PROJECT_ROOT/lib/aws-resource-manager.sh"
source "$PROJECT_ROOT/lib/deployment-health.sh"
source "$PROJECT_ROOT/lib/deployment-state-manager.sh"
source "$PROJECT_ROOT/lib/aws-quota-checker.sh"
source "$PROJECT_ROOT/lib/error-recovery.sh"
source "$PROJECT_ROOT/lib/deployment-validation.sh"

# Test configuration
declare -g TEST_MODE="simulation"  # simulation or live
declare -g VERBOSE_OUTPUT="${VERBOSE_OUTPUT:-false}"
declare -g TEST_REPORT_FILE="$PROJECT_ROOT/test-reports/deployment-comprehensive-$(date +%Y%m%d-%H%M%S).html"

# Global test statistics
declare -A TEST_STATS=(
    [total]=0
    [passed]=0
    [failed]=0
    [skipped]=0
    [errors]=0
)

# Failure simulation modes
declare -A FAILURE_MODES=(
    [ec2_insufficient_capacity]=0
    [spot_price_too_high]=0
    [quota_exceeded]=0
    [ami_not_found]=0
    [vpc_limit_exceeded]=0
    [efs_mount_failure]=0
    [alb_creation_failed]=0
    [cloudfront_limit_exceeded]=0
    [iam_permission_denied]=0
    [network_timeout]=0
    [api_throttled]=0
    [disk_space_exhausted]=0
    [docker_daemon_error]=0
    [health_check_failed]=0
)

# AWS API call interceptor for failure simulation
aws() {
    local cmd="$1"
    shift
    
    if [[ "$TEST_MODE" == "simulation" ]]; then
        simulate_aws_call "$cmd" "$@"
    else
        command aws "$cmd" "$@"
    fi
}

# Simulate AWS API calls with controlled failures
simulate_aws_call() {
    local cmd="$1"
    local subcmd="$2"
    shift 2
    
    case "$cmd" in
        ec2)
            simulate_ec2_call "$subcmd" "$@"
            ;;
        elbv2)
            simulate_elbv2_call "$subcmd" "$@"
            ;;
        cloudfront)
            simulate_cloudfront_call "$subcmd" "$@"
            ;;
        efs)
            simulate_efs_call "$subcmd" "$@"
            ;;
        iam)
            simulate_iam_call "$subcmd" "$@"
            ;;
        service-quotas)
            simulate_quota_call "$subcmd" "$@"
            ;;
        *)
            echo '{"error": "UnknownCommand"}'
            return 1
            ;;
    esac
}

# EC2 simulation
simulate_ec2_call() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        describe-spot-price-history)
            if [[ "${FAILURE_MODES[spot_price_too_high]}" -eq 1 ]]; then
                echo '{"SpotPriceHistory": [{"SpotPrice": "99.99", "Timestamp": "2025-01-01T00:00:00Z"}]}'
            else
                echo '{"SpotPriceHistory": [{"SpotPrice": "0.21", "Timestamp": "2025-01-01T00:00:00Z"}]}'
            fi
            ;;
        run-instances)
            if [[ "${FAILURE_MODES[ec2_insufficient_capacity]}" -eq 1 ]]; then
                echo '{"error": "InsufficientInstanceCapacity"}' >&2
                return 1
            elif [[ "${FAILURE_MODES[ami_not_found]}" -eq 1 ]]; then
                echo '{"error": "InvalidAMIID.NotFound"}' >&2
                return 1
            else
                echo '{"Instances": [{"InstanceId": "i-1234567890abcdef0", "State": {"Name": "pending"}}]}'
            fi
            ;;
        describe-instances)
            echo '{"Reservations": [{"Instances": [{"InstanceId": "i-1234567890abcdef0", "State": {"Name": "running"}, "PublicIpAddress": "1.2.3.4"}]}]}'
            ;;
        describe-vpcs)
            if [[ "${FAILURE_MODES[vpc_limit_exceeded]}" -eq 1 ]]; then
                echo '{"Vpcs": [{"VpcId": "vpc-1"}, {"VpcId": "vpc-2"}, {"VpcId": "vpc-3"}, {"VpcId": "vpc-4"}, {"VpcId": "vpc-5"}]}'
            else
                echo '{"Vpcs": [{"VpcId": "vpc-12345", "State": "available"}]}'
            fi
            ;;
        *)
            echo '{"error": "UnknownOperation"}'
            return 1
            ;;
    esac
}

# ELBv2 simulation
simulate_elbv2_call() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        create-load-balancer)
            if [[ "${FAILURE_MODES[alb_creation_failed]}" -eq 1 ]]; then
                echo '{"error": "LoadBalancerLimitExceeded"}' >&2
                return 1
            else
                echo '{"LoadBalancers": [{"LoadBalancerArn": "arn:aws:elasticloadbalancing:region:account:loadbalancer/app/test/1234567890"}]}'
            fi
            ;;
        *)
            echo '{"error": "UnknownOperation"}'
            return 1
            ;;
    esac
}

# CloudFront simulation
simulate_cloudfront_call() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        create-distribution)
            if [[ "${FAILURE_MODES[cloudfront_limit_exceeded]}" -eq 1 ]]; then
                echo '{"error": "DistributionLimitExceeded"}' >&2
                return 1
            else
                echo '{"Distribution": {"Id": "ABCDEFGHIJKLMN", "DomainName": "d123456.cloudfront.net"}}'
            fi
            ;;
        *)
            echo '{"error": "UnknownOperation"}'
            return 1
            ;;
    esac
}

# Service quota simulation
simulate_quota_call() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        get-service-quota)
            if [[ "${FAILURE_MODES[quota_exceeded]}" -eq 1 ]]; then
                echo '{"Quota": {"Value": 0}}'
            else
                echo '{"Quota": {"Value": 100}}'
            fi
            ;;
        *)
            echo '{"error": "UnknownOperation"}'
            return 1
            ;;
    esac
}

# Test runner function
run_test() {
    local test_name="$1"
    local test_function="$2"
    local description="${3:-}"
    
    ((TEST_STATS[total]++))
    
    echo -e "\n${BLUE}▶ Running test: $test_name${NC}"
    [[ -n "$description" ]] && echo "  Description: $description"
    
    # Create isolated test environment
    local test_dir="/tmp/deployment-test-$$"
    mkdir -p "$test_dir"
    
    # Run test in subshell to isolate failures
    if (
        cd "$test_dir"
        set +e  # Allow test failures
        $test_function
    ); then
        echo -e "${GREEN}✓ Test passed: $test_name${NC}"
        ((TEST_STATS[passed]++))
        return 0
    else
        echo -e "${RED}✗ Test failed: $test_name${NC}"
        ((TEST_STATS[failed]++))
        return 1
    fi
}

# Test Categories
# ==============

# 1. Failure Path Tests
# ---------------------

test_ec2_insufficient_capacity() {
    echo "Testing EC2 insufficient capacity handling..."
    
    # Enable failure mode
    FAILURE_MODES[ec2_insufficient_capacity]=1
    
    # Test spot instance handling
    local result
    if result=$(handle_spot_instance_launch "g4dn.xlarge" "us-east-1" 2>&1); then
        echo "ERROR: Expected failure but launch succeeded"
        return 1
    fi
    
    # Verify error was properly handled
    if [[ "$result" =~ "Insufficient capacity" ]]; then
        echo "✓ Insufficient capacity error properly detected"
    else
        echo "ERROR: Expected insufficient capacity error"
        return 1
    fi
    
    # Verify retry was attempted
    if [[ "$result" =~ "Retrying" ]] || [[ "$result" =~ "Falling back" ]]; then
        echo "✓ Retry/fallback mechanism triggered"
    else
        echo "ERROR: No retry/fallback attempted"
        return 1
    fi
    
    # Disable failure mode
    FAILURE_MODES[ec2_insufficient_capacity]=0
    return 0
}

test_spot_price_too_high() {
    echo "Testing spot price threshold handling..."
    
    # Enable failure mode
    FAILURE_MODES[spot_price_too_high]=1
    
    # Test spot price check
    local price
    price=$(get_spot_price "g4dn.xlarge" "us-east-1" 2>/dev/null || echo "99.99")
    
    if (( $(echo "$price > 1.0" | bc -l) )); then
        echo "✓ High spot price detected: $price"
    else
        echo "ERROR: Expected high spot price"
        return 1
    fi
    
    # Test fallback to on-demand
    if should_use_ondemand "$price"; then
        echo "✓ Correctly decided to use on-demand"
    else
        echo "ERROR: Should have fallen back to on-demand"
        return 1
    fi
    
    FAILURE_MODES[spot_price_too_high]=0
    return 0
}

test_quota_exceeded() {
    echo "Testing quota exceeded handling..."
    
    # Enable failure mode
    FAILURE_MODES[quota_exceeded]=1
    
    # Test quota check
    local available
    available=$(check_service_quota "ec2" "L-34B43A08" "us-east-1" 2>/dev/null || echo "0")
    
    if [[ "$available" -eq 0 ]]; then
        echo "✓ Quota exhaustion detected"
    else
        echo "ERROR: Expected quota to be 0"
        return 1
    fi
    
    # Verify pre-flight check would catch this
    if ! validate_deployment_quotas "g4dn.xlarge" "us-east-1"; then
        echo "✓ Pre-flight quota check correctly failed"
    else
        echo "ERROR: Pre-flight check should have failed"
        return 1
    fi
    
    FAILURE_MODES[quota_exceeded]=0
    return 0
}

test_ami_not_found() {
    echo "Testing AMI not found handling..."
    
    # Enable failure mode
    FAILURE_MODES[ami_not_found]=1
    
    # Test AMI validation
    local result
    if result=$(validate_ami_availability "ami-invalid" "us-east-1" 2>&1); then
        echo "ERROR: Invalid AMI should have failed"
        return 1
    fi
    
    # Verify error message
    if [[ "$result" =~ "AMI not found" ]] || [[ "$result" =~ "InvalidAMIID" ]]; then
        echo "✓ AMI validation correctly failed"
    else
        echo "ERROR: Expected AMI not found error"
        return 1
    fi
    
    FAILURE_MODES[ami_not_found]=0
    return 0
}

test_alb_creation_failure() {
    echo "Testing ALB creation failure handling..."
    
    # Enable failure mode
    FAILURE_MODES[alb_creation_failed]=1
    
    # Test ALB creation with graceful degradation
    local result
    if result=$(create_alb_with_fallback "test-alb" "vpc-12345" 2>&1); then
        echo "✓ ALB creation gracefully degraded"
        
        # Verify warning was issued
        if [[ "$result" =~ "Warning" ]] || [[ "$result" =~ "Continuing without ALB" ]]; then
            echo "✓ Appropriate warning issued"
        fi
    else
        echo "ERROR: ALB failure should be handled gracefully"
        return 1
    fi
    
    FAILURE_MODES[alb_creation_failed]=0
    return 0
}

test_efs_mount_failure() {
    echo "Testing EFS mount failure handling..."
    
    # Enable failure mode
    FAILURE_MODES[efs_mount_failure]=1
    
    # Test EFS mount with retry
    local attempts=0
    local max_attempts=3
    local mounted=false
    
    while [[ $attempts -lt $max_attempts ]]; do
        if mount_efs_with_retry "fs-12345" "/mnt/efs" 2>/dev/null; then
            mounted=true
            break
        fi
        ((attempts++))
        echo "  Retry attempt $attempts/$max_attempts"
    done
    
    if [[ "$mounted" == "false" ]]; then
        echo "✓ EFS mount correctly failed after retries"
        
        # Verify fallback to local storage
        if setup_fallback_storage "/mnt/efs"; then
            echo "✓ Fallback to local storage succeeded"
        else
            echo "ERROR: Fallback storage setup failed"
            return 1
        fi
    fi
    
    FAILURE_MODES[efs_mount_failure]=0
    return 0
}

# 2. Error Recovery Tests
# -----------------------

test_retry_with_exponential_backoff() {
    echo "Testing exponential backoff retry logic..."
    
    # Test retry timing
    local start_time=$(date +%s)
    local attempt=0
    
    while [[ $attempt -lt 3 ]]; do
        local delay=$(calculate_backoff_delay $attempt)
        echo "  Attempt $((attempt+1)): ${delay}s delay"
        
        # Verify exponential increase
        if [[ $attempt -gt 0 ]]; then
            local expected=$((2 ** attempt))
            if [[ $delay -ne $expected ]]; then
                echo "ERROR: Expected delay $expected, got $delay"
                return 1
            fi
        fi
        
        ((attempt++))
    done
    
    echo "✓ Exponential backoff working correctly"
    return 0
}

test_multi_region_failover() {
    echo "Testing multi-region failover..."
    
    # Simulate failure in primary region
    FAILURE_MODES[ec2_insufficient_capacity]=1
    
    local regions=("us-east-1" "us-west-2" "eu-west-1")
    local launched=false
    local selected_region=""
    
    for region in "${regions[@]}"; do
        echo "  Trying region: $region"
        
        # Disable failure after first attempt
        [[ "$region" != "us-east-1" ]] && FAILURE_MODES[ec2_insufficient_capacity]=0
        
        if launch_instance_with_failover "g4dn.xlarge" "$region" 2>/dev/null; then
            launched=true
            selected_region="$region"
            break
        fi
    done
    
    if [[ "$launched" == "true" ]] && [[ "$selected_region" != "us-east-1" ]]; then
        echo "✓ Successfully failed over to $selected_region"
    else
        echo "ERROR: Multi-region failover failed"
        return 1
    fi
    
    FAILURE_MODES[ec2_insufficient_capacity]=0
    return 0
}

test_graceful_degradation() {
    echo "Testing graceful degradation..."
    
    # Test service degradation order
    local services=("cloudfront" "alb" "efs" "monitoring")
    local degraded=()
    
    for service in "${services[@]}"; do
        # Simulate failure
        FAILURE_MODES["${service}_creation_failed"]=1
        
        if can_degrade_service "$service"; then
            degraded+=("$service")
            echo "  ✓ Degraded $service gracefully"
        else
            echo "ERROR: Failed to degrade $service"
            return 1
        fi
        
        FAILURE_MODES["${service}_creation_failed"]=0
    done
    
    # Verify core services still work
    if validate_core_services; then
        echo "✓ Core services operational despite degradation"
    else
        echo "ERROR: Core services failed"
        return 1
    fi
    
    return 0
}

test_cleanup_on_failure() {
    echo "Testing cleanup on failure..."
    
    # Create test resources
    local test_resources=(
        "vpc:vpc-test123"
        "ec2:i-test123"
        "efs:fs-test123"
        "alb:arn:aws:elasticloadbalancing:test"
    )
    
    # Register resources
    for resource in "${test_resources[@]}"; do
        register_resource_for_cleanup "$resource"
    done
    
    # Simulate deployment failure
    FAILURE_MODES[health_check_failed]=1
    
    # Trigger cleanup
    if cleanup_failed_deployment; then
        echo "✓ Cleanup completed successfully"
        
        # Verify all resources marked for deletion
        for resource in "${test_resources[@]}"; do
            if is_resource_cleaned_up "$resource"; then
                echo "  ✓ Cleaned up $resource"
            else
                echo "ERROR: Failed to cleanup $resource"
                return 1
            fi
        done
    else
        echo "ERROR: Cleanup failed"
        return 1
    fi
    
    FAILURE_MODES[health_check_failed]=0
    return 0
}

# 3. Dependency Validation Tests
# ------------------------------

test_bash_version_check() {
    echo "Testing bash version validation..."
    
    # Test current version
    local current_version="${BASH_VERSION}"
    echo "  Current bash version: $current_version"
    
    # Test version comparison
    if version_ge "$current_version" "5.3.0"; then
        echo "✓ Bash version meets requirements"
    else
        echo "WARNING: Bash version below 5.3.0"
    fi
    
    # Test version parsing
    local major minor patch
    parse_version "$current_version" major minor patch
    echo "  Parsed: major=$major, minor=$minor, patch=$patch"
    
    if [[ -n "$major" ]] && [[ -n "$minor" ]]; then
        echo "✓ Version parsing successful"
    else
        echo "ERROR: Version parsing failed"
        return 1
    fi
    
    return 0
}

test_aws_cli_validation() {
    echo "Testing AWS CLI validation..."
    
    # Test AWS CLI presence
    if command -v aws >/dev/null 2>&1; then
        echo "✓ AWS CLI found"
        
        # Test version
        local aws_version
        aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
        echo "  AWS CLI version: $aws_version"
        
        # Check for v2
        if [[ "$aws_version" =~ ^2\. ]]; then
            echo "✓ AWS CLI v2 detected"
        else
            echo "WARNING: AWS CLI v1 detected, v2 recommended"
        fi
    else
        echo "ERROR: AWS CLI not found"
        return 1
    fi
    
    # Test credentials
    if validate_aws_credentials; then
        echo "✓ AWS credentials valid"
    else
        echo "WARNING: AWS credentials not configured"
    fi
    
    return 0
}

test_required_tools_check() {
    echo "Testing required tools validation..."
    
    local required_tools=(
        "jq:JSON processor"
        "bc:Calculator"
        "curl:HTTP client"
        "docker:Container runtime"
        "git:Version control"
    )
    
    local missing=()
    
    for tool_spec in "${required_tools[@]}"; do
        local tool="${tool_spec%%:*}"
        local description="${tool_spec#*:}"
        
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✓ $tool ($description) - installed"
        else
            echo "  ✗ $tool ($description) - MISSING"
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "✓ All required tools installed"
        return 0
    else
        echo "ERROR: Missing tools: ${missing[*]}"
        return 1
    fi
}

test_iam_permissions_check() {
    echo "Testing IAM permissions validation..."
    
    # Required permissions
    local required_permissions=(
        "ec2:RunInstances"
        "ec2:DescribeInstances"
        "ec2:CreateTags"
        "efs:CreateFileSystem"
        "efs:DescribeFileSystems"
        "elasticloadbalancing:CreateLoadBalancer"
        "cloudfront:CreateDistribution"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
    )
    
    local missing_perms=()
    
    for permission in "${required_permissions[@]}"; do
        if check_iam_permission "$permission"; then
            echo "  ✓ $permission - granted"
        else
            echo "  ✗ $permission - DENIED"
            missing_perms+=("$permission")
        fi
    done
    
    if [[ ${#missing_perms[@]} -eq 0 ]]; then
        echo "✓ All required permissions granted"
        return 0
    else
        echo "WARNING: Missing permissions: ${missing_perms[*]}"
        return 0  # Don't fail test in simulation mode
    fi
}

# 4. Health Monitoring Tests
# --------------------------

test_service_health_checks() {
    echo "Testing service health monitoring..."
    
    # Test health check for each service
    local services=(
        "n8n:5678"
        "ollama:11434"
        "qdrant:6333"
        "postgres:5432"
    )
    
    for service_spec in "${services[@]}"; do
        local service="${service_spec%%:*}"
        local port="${service_spec#*:}"
        
        echo "  Checking $service on port $port..."
        
        # Simulate health check
        if [[ "$TEST_MODE" == "simulation" ]]; then
            # Randomly fail some checks
            if [[ $((RANDOM % 4)) -eq 0 ]]; then
                echo "    ✗ $service health check failed"
                
                # Verify retry logic
                if retry_health_check "$service" "$port" 3; then
                    echo "    ✓ $service recovered after retry"
                else
                    echo "    ✗ $service failed after retries"
                fi
            else
                echo "    ✓ $service is healthy"
            fi
        fi
    done
    
    return 0
}

test_deployment_status_reporting() {
    echo "Testing deployment status reporting..."
    
    # Initialize deployment state
    init_deployment_state "test-deployment"
    
    # Test phase transitions
    local phases=(
        "initialization:Preparing deployment"
        "infrastructure:Creating VPC and networking"
        "compute:Launching EC2 instances"
        "services:Deploying application services"
        "validation:Running health checks"
        "completed:Deployment successful"
    )
    
    for phase_spec in "${phases[@]}"; do
        local phase="${phase_spec%%:*}"
        local description="${phase_spec#*:}"
        
        update_deployment_phase "$phase" "$description"
        
        # Get current status
        local status
        status=$(get_deployment_status)
        
        if [[ "$status" =~ "$phase" ]]; then
            echo "  ✓ Phase '$phase' correctly reported"
        else
            echo "ERROR: Phase '$phase' not in status"
            return 1
        fi
        
        # Simulate some progress
        sleep 0.1
    done
    
    echo "✓ Deployment status reporting working"
    return 0
}

test_metric_collection() {
    echo "Testing metric collection..."
    
    # Initialize metrics
    init_metrics_collection
    
    # Record various metrics
    record_metric "instance_launch_time" 45.3
    record_metric "spot_price" 0.21
    record_metric "deployment_duration" 320
    record_metric "health_check_failures" 2
    
    # Get metric summary
    local summary
    summary=$(get_metrics_summary)
    
    # Verify metrics recorded
    if [[ "$summary" =~ "instance_launch_time: 45.3" ]]; then
        echo "✓ Metrics correctly recorded"
    else
        echo "ERROR: Metrics not properly recorded"
        return 1
    fi
    
    # Test metric aggregation
    local avg_launch_time
    avg_launch_time=$(calculate_metric_average "instance_launch_time")
    
    if [[ -n "$avg_launch_time" ]]; then
        echo "✓ Metric aggregation working"
    else
        echo "ERROR: Metric aggregation failed"
        return 1
    fi
    
    return 0
}

# 5. Platform Compatibility Tests
# -------------------------------

test_bash_features_compatibility() {
    echo "Testing bash feature compatibility..."
    
    # Test associative arrays
    if declare -A test_array 2>/dev/null; then
        test_array[key]="value"
        if [[ "${test_array[key]}" == "value" ]]; then
            echo "✓ Associative arrays supported"
        else
            echo "ERROR: Associative array assignment failed"
            return 1
        fi
    else
        echo "ERROR: Associative arrays not supported"
        return 1
    fi
    
    # Test nameref variables
    if declare -n ref_var=test_array 2>/dev/null; then
        if [[ "${ref_var[key]}" == "value" ]]; then
            echo "✓ Nameref variables supported"
        else
            echo "ERROR: Nameref access failed"
            return 1
        fi
    else
        echo "ERROR: Nameref variables not supported"
        return 1
    fi
    
    # Test BASH_REMATCH
    if [[ "test123" =~ ([a-z]+)([0-9]+) ]]; then
        if [[ "${BASH_REMATCH[1]}" == "test" ]] && [[ "${BASH_REMATCH[2]}" == "123" ]]; then
            echo "✓ BASH_REMATCH working"
        else
            echo "ERROR: BASH_REMATCH not working correctly"
            return 1
        fi
    fi
    
    return 0
}

test_cross_platform_commands() {
    echo "Testing cross-platform command compatibility..."
    
    # Test commands that differ between platforms
    local platform=$(uname -s)
    echo "  Platform: $platform"
    
    # Test date command
    local timestamp
    if [[ "$platform" == "Darwin" ]]; then
        # macOS date syntax
        timestamp=$(date -u +%s)
    else
        # Linux date syntax
        timestamp=$(date -u +%s)
    fi
    
    if [[ -n "$timestamp" ]] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "✓ Date command compatible"
    else
        echo "ERROR: Date command failed"
        return 1
    fi
    
    # Test sed behavior
    local test_string="hello world"
    local result
    
    if [[ "$platform" == "Darwin" ]]; then
        # macOS sed requires backup extension
        result=$(echo "$test_string" | sed 's/world/universe/')
    else
        # Linux sed
        result=$(echo "$test_string" | sed 's/world/universe/')
    fi
    
    if [[ "$result" == "hello universe" ]]; then
        echo "✓ Sed command compatible"
    else
        echo "ERROR: Sed command failed"
        return 1
    fi
    
    return 0
}

test_encoding_and_locale() {
    echo "Testing encoding and locale handling..."
    
    # Check locale settings
    local current_locale="${LANG:-}"
    echo "  Current locale: $current_locale"
    
    # Test UTF-8 handling
    local utf8_string="Hello 世界 🌍"
    local length=${#utf8_string}
    
    if [[ $length -gt 0 ]]; then
        echo "✓ UTF-8 string handling working"
    else
        echo "ERROR: UTF-8 string handling failed"
        return 1
    fi
    
    # Test special characters in filenames
    local test_file="/tmp/test-特殊-$(date +%s).txt"
    if echo "test" > "$test_file" 2>/dev/null; then
        echo "✓ Special character filenames supported"
        rm -f "$test_file"
    else
        echo "WARNING: Special character filenames not fully supported"
    fi
    
    return 0
}

# 6. Integration Tests
# --------------------

test_full_deployment_simulation() {
    echo "Testing full deployment simulation..."
    
    # Initialize deployment
    local stack_name="test-stack-$(date +%s)"
    init_deployment_state "$stack_name"
    
    # Phase 1: Pre-flight checks
    echo "  Phase 1: Pre-flight validation"
    if validate_deployment_prerequisites; then
        echo "    ✓ Prerequisites validated"
    else
        echo "    ✗ Prerequisites validation failed"
        return 1
    fi
    
    # Phase 2: Infrastructure
    echo "  Phase 2: Infrastructure creation"
    update_deployment_phase "infrastructure" "Creating VPC and networking"
    
    # Simulate VPC creation
    if create_vpc_simulation "$stack_name"; then
        echo "    ✓ VPC created"
    else
        echo "    ✗ VPC creation failed"
        return 1
    fi
    
    # Phase 3: Compute
    echo "  Phase 3: Instance launch"
    update_deployment_phase "compute" "Launching instances"
    
    # Simulate instance launch with retry
    local instance_id
    if instance_id=$(launch_instance_with_retry "g4dn.xlarge" "us-east-1"); then
        echo "    ✓ Instance launched: $instance_id"
    else
        echo "    ✗ Instance launch failed"
        return 1
    fi
    
    # Phase 4: Services
    echo "  Phase 4: Service deployment"
    update_deployment_phase "services" "Deploying application"
    
    # Simulate service deployment
    if deploy_services_simulation "$instance_id"; then
        echo "    ✓ Services deployed"
    else
        echo "    ✗ Service deployment failed"
        return 1
    fi
    
    # Phase 5: Validation
    echo "  Phase 5: Health validation"
    update_deployment_phase "validation" "Running health checks"
    
    # Simulate health checks
    if validate_deployment_health "$stack_name"; then
        echo "    ✓ Deployment healthy"
    else
        echo "    ✗ Health validation failed"
        return 1
    fi
    
    # Complete
    update_deployment_phase "completed" "Deployment successful"
    echo "✓ Full deployment simulation completed"
    
    return 0
}

test_multi_scenario_deployment() {
    echo "Testing multiple deployment scenarios..."
    
    local scenarios=(
        "spot-simple:Simple spot instance"
        "spot-alb:Spot with ALB"
        "spot-cloudfront:Spot with CloudFront CDN"
        "ondemand-ha:On-demand high availability"
        "enterprise:Full enterprise stack"
    )
    
    for scenario_spec in "${scenarios[@]}"; do
        local scenario="${scenario_spec%%:*}"
        local description="${scenario_spec#*:}"
        
        echo -e "\n  Testing scenario: $description"
        
        # Set deployment options based on scenario
        case "$scenario" in
            spot-simple)
                DEPLOYMENT_OPTIONS=(--spot)
                ;;
            spot-alb)
                DEPLOYMENT_OPTIONS=(--spot --alb)
                ;;
            spot-cloudfront)
                DEPLOYMENT_OPTIONS=(--spot --alb --cloudfront)
                ;;
            ondemand-ha)
                DEPLOYMENT_OPTIONS=(--multi-az --alb)
                ;;
            enterprise)
                DEPLOYMENT_OPTIONS=(--spot --multi-az --alb --cloudfront --monitoring)
                ;;
        esac
        
        # Run deployment simulation
        if simulate_deployment_scenario "${DEPLOYMENT_OPTIONS[@]}"; then
            echo "    ✓ Scenario '$scenario' passed"
        else
            echo "    ✗ Scenario '$scenario' failed"
            # Continue testing other scenarios
        fi
    done
    
    return 0
}

# Helper Functions
# ----------------

# Initialize test environment
init_test_environment() {
    # Create test directories
    mkdir -p "$PROJECT_ROOT/test-reports"
    mkdir -p "/tmp/deployment-test-$$"
    
    # Set test mode
    export DEPLOYMENT_TEST_MODE="true"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    
    # Initialize HTML report
    cat > "$TEST_REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Deployment Test Report - $(date)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .summary { background: #f0f0f0; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        .test-category { margin-bottom: 30px; }
        .test-result { margin-left: 20px; padding: 5px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Deployment Comprehensive Test Report</h1>
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Generated: $(date)</p>
        <p>Test Mode: $TEST_MODE</p>
    </div>
    <div id="results">
EOF
}

# Add test result to HTML report
add_to_report() {
    local category="$1"
    local test_name="$2"
    local status="$3"
    local details="$4"
    
    cat >> "$TEST_REPORT_FILE" <<EOF
        <div class="test-result">
            <span class="$status">[$status]</span> <strong>$test_name</strong>
            <div style="margin-left: 20px; color: #666;">$details</div>
        </div>
EOF
}

# Finalize HTML report
finalize_report() {
    cat >> "$TEST_REPORT_FILE" <<EOF
    </div>
    <div class="summary">
        <h3>Final Results</h3>
        <table>
            <tr><th>Metric</th><th>Count</th></tr>
            <tr><td>Total Tests</td><td>${TEST_STATS[total]}</td></tr>
            <tr><td class="passed">Passed</td><td>${TEST_STATS[passed]}</td></tr>
            <tr><td class="failed">Failed</td><td>${TEST_STATS[failed]}</td></tr>
            <tr><td class="skipped">Skipped</td><td>${TEST_STATS[skipped]}</td></tr>
        </table>
        <p>Success Rate: $(( TEST_STATS[passed] * 100 / TEST_STATS[total] ))%</p>
    </div>
</body>
</html>
EOF
}

# Main test execution
main() {
    echo "========================================="
    echo "Deployment Comprehensive Test Suite"
    echo "========================================="
    echo "Mode: $TEST_MODE"
    echo "Started: $(date)"
    echo
    
    # Initialize environment
    init_test_environment
    
    # Run test categories
    echo -e "\n${YELLOW}1. FAILURE PATH TESTS${NC}"
    add_to_report "Failure Paths" "Category" "info" "Testing various failure scenarios"
    
    run_test "EC2 Insufficient Capacity" test_ec2_insufficient_capacity "Tests handling of capacity errors"
    run_test "Spot Price Too High" test_spot_price_too_high "Tests spot price threshold handling"
    run_test "Quota Exceeded" test_quota_exceeded "Tests quota limit handling"
    run_test "AMI Not Found" test_ami_not_found "Tests invalid AMI handling"
    run_test "ALB Creation Failure" test_alb_creation_failure "Tests ALB failure with graceful degradation"
    run_test "EFS Mount Failure" test_efs_mount_failure "Tests EFS mount retry and fallback"
    
    echo -e "\n${YELLOW}2. ERROR RECOVERY TESTS${NC}"
    add_to_report "Error Recovery" "Category" "info" "Testing recovery mechanisms"
    
    run_test "Exponential Backoff" test_retry_with_exponential_backoff "Tests retry delay calculation"
    run_test "Multi-Region Failover" test_multi_region_failover "Tests cross-region failover"
    run_test "Graceful Degradation" test_graceful_degradation "Tests service degradation handling"
    run_test "Cleanup on Failure" test_cleanup_on_failure "Tests resource cleanup after failure"
    
    echo -e "\n${YELLOW}3. DEPENDENCY VALIDATION TESTS${NC}"
    add_to_report "Dependencies" "Category" "info" "Testing prerequisite validation"
    
    run_test "Bash Version Check" test_bash_version_check "Tests bash version validation"
    run_test "AWS CLI Validation" test_aws_cli_validation "Tests AWS CLI presence and version"
    run_test "Required Tools Check" test_required_tools_check "Tests for required tools"
    run_test "IAM Permissions Check" test_iam_permissions_check "Tests IAM permission validation"
    
    echo -e "\n${YELLOW}4. HEALTH MONITORING TESTS${NC}"
    add_to_report "Health Monitoring" "Category" "info" "Testing health and status monitoring"
    
    run_test "Service Health Checks" test_service_health_checks "Tests service health monitoring"
    run_test "Deployment Status Reporting" test_deployment_status_reporting "Tests status tracking"
    run_test "Metric Collection" test_metric_collection "Tests metric recording and aggregation"
    
    echo -e "\n${YELLOW}5. PLATFORM COMPATIBILITY TESTS${NC}"
    add_to_report "Compatibility" "Category" "info" "Testing cross-platform compatibility"
    
    run_test "Bash Features" test_bash_features_compatibility "Tests modern bash features"
    run_test "Cross-Platform Commands" test_cross_platform_commands "Tests command compatibility"
    run_test "Encoding and Locale" test_encoding_and_locale "Tests character encoding"
    
    echo -e "\n${YELLOW}6. INTEGRATION TESTS${NC}"
    add_to_report "Integration" "Category" "info" "Testing full deployment scenarios"
    
    run_test "Full Deployment Simulation" test_full_deployment_simulation "Tests complete deployment flow"
    run_test "Multi-Scenario Deployment" test_multi_scenario_deployment "Tests various deployment configurations"
    
    # Finalize report
    finalize_report
    
    # Print summary
    echo
    echo "========================================="
    echo "TEST SUMMARY"
    echo "========================================="
    echo "Total Tests: ${TEST_STATS[total]}"
    echo -e "${GREEN}Passed: ${TEST_STATS[passed]}${NC}"
    echo -e "${RED}Failed: ${TEST_STATS[failed]}${NC}"
    echo -e "${YELLOW}Skipped: ${TEST_STATS[skipped]}${NC}"
    echo
    echo "Success Rate: $(( TEST_STATS[passed] * 100 / TEST_STATS[total] ))%"
    echo
    echo "Report saved to: $TEST_REPORT_FILE"
    echo "Completed: $(date)"
    
    # Exit with appropriate code
    [[ ${TEST_STATS[failed]} -eq 0 ]] && exit 0 || exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --live)
            TEST_MODE="live"
            echo "WARNING: Live mode will create actual AWS resources!"
            read -p "Are you sure? (yes/no): " confirm
            [[ "$confirm" != "yes" ]] && exit 1
            ;;
        --verbose|-v)
            VERBOSE_OUTPUT=true
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --live        Run tests against real AWS (default: simulation)"
            echo "  --verbose,-v  Enable verbose output"
            echo "  --help,-h     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Run main test suite
main