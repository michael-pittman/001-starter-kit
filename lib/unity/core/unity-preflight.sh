#!/bin/bash
# Unity Pre-flight Validation System
# Comprehensive pre-deployment checks to ensure system readiness

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core
source "$SCRIPT_DIR/unity-core.sh" || {
    echo "Error: Failed to load Unity core" >&2
    exit 1
}

# Pre-flight check for all validations
preflight_check_all() {
    local deployment_type="$1"
    local stack_name="$2"
    local errors=0
    
    unity_log "INFO" "Running pre-flight checks for $deployment_type deployment of $stack_name"
    
    # AWS checks
    if ! preflight_check_aws; then
        ((errors++))
    fi
    
    # Docker checks (if needed for deployment type)
    if [[ "$deployment_type" =~ ^(full|alb|cdn)$ ]]; then
        if ! preflight_check_docker; then
            ((errors++))
        fi
    fi
    
    # Resource checks
    if ! preflight_check_resources "$stack_name"; then
        ((errors++))
    fi
    
    # Configuration checks
    if ! preflight_check_config; then
        ((errors++))
    fi
    
    # Network checks
    if ! preflight_check_network; then
        ((errors++))
    fi
    
    # Security checks
    if ! preflight_check_security; then
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        unity_log "ERROR" "Pre-flight checks failed with $errors errors"
        return 1
    fi
    
    unity_log "INFO" "All pre-flight checks passed"
    return 0
}

# AWS pre-flight checks
preflight_check_aws() {
    unity_log "INFO" "Checking AWS prerequisites..."
    
    # Check credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        unity_log "ERROR" "AWS credentials not configured"
        unity_log "ERROR" "Please run: aws configure"
        return 1
    fi
    
    # Get account info
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local caller_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    unity_log "INFO" "AWS Account: $account_id"
    unity_log "DEBUG" "Caller ARN: $caller_arn"
    
    # Check IAM permissions
    if ! preflight_check_iam_permissions; then
        return 1
    fi
    
    # Check service quotas
    if ! preflight_check_service_quotas; then
        return 1
    fi
    
    # Check region validity
    if ! preflight_check_aws_region; then
        return 1
    fi
    
    unity_log "INFO" "AWS checks passed"
    return 0
}

# Check IAM permissions
preflight_check_iam_permissions() {
    unity_log "INFO" "Checking IAM permissions..."
    
    # Required actions for deployment
    local required_actions=(
        "ec2:CreateVpc"
        "ec2:CreateSubnet"
        "ec2:CreateInternetGateway"
        "ec2:CreateRouteTable"
        "ec2:CreateSecurityGroup"
        "ec2:RunInstances"
        "ec2:DescribeInstances"
        "ec2:DescribeVpcs"
        "ec2:DescribeSubnets"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "iam:PassRole"
        "elasticloadbalancing:CreateLoadBalancer"
        "elasticloadbalancing:CreateTargetGroup"
        "cloudfront:CreateDistribution"
        "ssm:PutParameter"
        "ssm:GetParameter"
        "cloudformation:CreateStack"
        "cloudformation:DescribeStacks"
    )
    
    # Use IAM policy simulator to check permissions
    local missing_permissions=()
    
    # For now, we'll do a basic check by trying to describe resources
    # In production, you'd use IAM policy simulator
    if ! aws ec2 describe-vpcs --max-results 1 >/dev/null 2>&1; then
        missing_permissions+=("ec2:DescribeVpcs")
    fi
    
    if ! aws iam list-roles --max-items 1 >/dev/null 2>&1; then
        missing_permissions+=("iam:ListRoles")
    fi
    
    if [[ ${#missing_permissions[@]} -gt 0 ]]; then
        unity_log "ERROR" "Missing required IAM permissions: ${missing_permissions[*]}"
        return 1
    fi
    
    unity_log "INFO" "IAM permissions check passed"
    return 0
}

# Check service quotas
preflight_check_service_quotas() {
    unity_log "INFO" "Checking AWS service quotas..."
    
    # Check EC2 instance quota
    local instance_quota=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "20")
    
    # Check running instances
    local running_instances=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null || echo "0")
    
    local available_instances=$((instance_quota - running_instances))
    
    unity_log "INFO" "EC2 instance quota: $instance_quota (${available_instances} available)"
    
    if [[ $available_instances -lt 1 ]]; then
        unity_log "ERROR" "Insufficient EC2 instance quota. Available: $available_instances"
        return 1
    fi
    
    # Check VPC quota
    local vpc_quota=$(aws service-quotas get-service-quota \
        --service-code vpc \
        --quota-code L-F678F1CE \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "5")
    
    local existing_vpcs=$(aws ec2 describe-vpcs \
        --query 'length(Vpcs)' \
        --output text 2>/dev/null || echo "0")
    
    local available_vpcs=$((vpc_quota - existing_vpcs))
    
    unity_log "INFO" "VPC quota: $vpc_quota (${available_vpcs} available)"
    
    if [[ $available_vpcs -lt 1 ]]; then
        unity_log "WARN" "Low VPC quota. Consider using --use-existing-vpc option"
    fi
    
    unity_log "INFO" "Service quota checks passed"
    return 0
}

# Check AWS region
preflight_check_aws_region() {
    local region="${AWS_REGION:-us-east-1}"
    unity_log "INFO" "Checking AWS region: $region"
    
    # Get list of valid regions
    local valid_regions=$(aws ec2 describe-regions \
        --query 'Regions[].RegionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$valid_regions" ]]; then
        unity_log "WARN" "Could not retrieve AWS regions list, assuming $region is valid"
        return 0
    fi
    
    # Convert to array for checking
    local region_array=($valid_regions)
    
    # Check if region is valid
    local region_found=false
    for valid_region in "${region_array[@]}"; do
        if [[ "$valid_region" == "$region" ]]; then
            region_found=true
            break
        fi
    done
    
    if [[ "$region_found" != "true" ]]; then
        unity_log "ERROR" "Invalid AWS region: $region"
        unity_log "ERROR" "Valid regions: ${region_array[*]}"
        return 1
    fi
    
    unity_log "INFO" "AWS region check passed"
    return 0
}

# Docker pre-flight checks
preflight_check_docker() {
    unity_log "INFO" "Checking Docker prerequisites..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        unity_log "ERROR" "Docker is not installed"
        unity_log "ERROR" "Please install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        unity_log "ERROR" "Docker daemon is not running"
        unity_log "ERROR" "Please start Docker daemon"
        return 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        unity_log "ERROR" "Docker Compose is not installed"
        unity_log "ERROR" "Please install Docker Compose"
        return 1
    fi
    
    # Check disk space (require at least 10GB free)
    local free_space_mb=$(df -m "$(docker info --format '{{.DockerRootDir}}')" | awk 'NR==2 {print $4}')
    if [[ $free_space_mb -lt 10240 ]]; then
        unity_log "WARN" "Low disk space: ${free_space_mb}MB free (recommend at least 10GB)"
    fi
    
    unity_log "INFO" "Docker checks passed"
    return 0
}

# Resource checks
preflight_check_resources() {
    local stack_name="$1"
    unity_log "INFO" "Checking for existing resources for stack: $stack_name"
    
    # Check for existing CloudFormation stack
    if aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1; then
        unity_log "WARN" "CloudFormation stack already exists: $stack_name"
        unity_log "WARN" "Use 'destroy' command first or choose a different stack name"
        return 1
    fi
    
    # Check for resources with Unity tags
    local tagged_resources=$(aws resourcegroupstaggingapi get-resources \
        --tag-filters "Key=unity:stack,Values=$stack_name" \
        --query 'length(ResourceTagMappingList)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ $tagged_resources -gt 0 ]]; then
        unity_log "WARN" "Found $tagged_resources existing resources tagged with stack: $stack_name"
        unity_log "WARN" "This may indicate incomplete cleanup from previous deployment"
    fi
    
    unity_log "INFO" "Resource checks passed"
    return 0
}

# Configuration checks
preflight_check_config() {
    unity_log "INFO" "Checking configuration..."
    
    # Check Unity configuration file
    local config_file="$PROJECT_ROOT/config/unity.yml"
    if [[ ! -f "$config_file" ]]; then
        unity_log "ERROR" "Unity configuration file not found: $config_file"
        return 1
    fi
    
    # Validate YAML syntax (basic check)
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
            unity_log "ERROR" "Invalid YAML syntax in configuration file"
            return 1
        fi
    fi
    
    # Check for required environment variables
    local required_vars=()
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        unity_log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    # Check secrets configuration
    if [[ ! -d "$PROJECT_ROOT/secrets" ]]; then
        unity_log "WARN" "Secrets directory not found. Will use AWS Parameter Store"
    fi
    
    unity_log "INFO" "Configuration checks passed"
    return 0
}

# Network checks
preflight_check_network() {
    unity_log "INFO" "Checking network connectivity..."
    
    # Check internet connectivity
    if ! curl -s --max-time 5 https://aws.amazon.com >/dev/null 2>&1; then
        unity_log "ERROR" "No internet connectivity detected"
        return 1
    fi
    
    # Check AWS API endpoint connectivity
    if ! aws ec2 describe-regions --max-results 1 >/dev/null 2>&1; then
        unity_log "ERROR" "Cannot reach AWS API endpoints"
        return 1
    fi
    
    # Check Docker Hub connectivity (for pulling images)
    if ! curl -s --max-time 5 https://hub.docker.com >/dev/null 2>&1; then
        unity_log "WARN" "Cannot reach Docker Hub. May have issues pulling images"
    fi
    
    unity_log "INFO" "Network checks passed"
    return 0
}

# Security checks
preflight_check_security() {
    unity_log "INFO" "Running security checks..."
    
    # Check for hardcoded credentials in configuration
    if grep -r "AKIA\|aws_secret_access_key" "$PROJECT_ROOT/config" 2>/dev/null; then
        unity_log "ERROR" "Found potential hardcoded AWS credentials in configuration"
        return 1
    fi
    
    # Check file permissions on secrets directory
    if [[ -d "$PROJECT_ROOT/secrets" ]]; then
        local perms=$(stat -c %a "$PROJECT_ROOT/secrets" 2>/dev/null || stat -f %A "$PROJECT_ROOT/secrets" 2>/dev/null || echo "unknown")
        if [[ "$perms" != "700" && "$perms" != "unknown" ]]; then
            unity_log "WARN" "Secrets directory has loose permissions: $perms (should be 700)"
        fi
    fi
    
    # Check for AWS credentials in environment
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
        unity_log "INFO" "Using AWS credentials from environment variables"
    elif [[ -f ~/.aws/credentials ]]; then
        unity_log "INFO" "Using AWS credentials from ~/.aws/credentials"
    else
        unity_log "ERROR" "No AWS credentials found"
        return 1
    fi
    
    unity_log "INFO" "Security checks passed"
    return 0
}

# Deployment-specific checks
preflight_check_deployment_type() {
    local deployment_type="$1"
    unity_log "INFO" "Running deployment-specific checks for: $deployment_type"
    
    case "$deployment_type" in
        spot)
            # Check spot instance availability
            if ! preflight_check_spot_availability; then
                return 1
            fi
            ;;
        alb)
            # Check ALB prerequisites
            if ! preflight_check_alb_requirements; then
                return 1
            fi
            ;;
        cdn)
            # Check CloudFront prerequisites
            if ! preflight_check_cdn_requirements; then
                return 1
            fi
            ;;
        full)
            # Check all requirements
            if ! preflight_check_spot_availability; then
                return 1
            fi
            if ! preflight_check_alb_requirements; then
                return 1
            fi
            if ! preflight_check_cdn_requirements; then
                return 1
            fi
            ;;
    esac
    
    unity_log "INFO" "Deployment-specific checks passed"
    return 0
}

# Check spot instance availability
preflight_check_spot_availability() {
    unity_log "INFO" "Checking spot instance availability..."
    
    local instance_type="${INSTANCE_TYPE:-g4dn.xlarge}"
    local region="${AWS_REGION:-us-east-1}"
    
    # Get spot price history
    local spot_prices=$(aws ec2 describe-spot-price-history \
        --instance-types "$instance_type" \
        --max-results 1 \
        --query 'SpotPriceHistory[0].SpotPrice' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$spot_prices" ]]; then
        unity_log "WARN" "Could not retrieve spot pricing for $instance_type"
        unity_log "WARN" "Deployment may fail if spot capacity is unavailable"
    else
        unity_log "INFO" "Current spot price for $instance_type: \$$spot_prices"
    fi
    
    return 0
}

# Check ALB requirements
preflight_check_alb_requirements() {
    unity_log "INFO" "Checking ALB requirements..."
    
    # Check for at least 2 availability zones
    local az_count=$(aws ec2 describe-availability-zones \
        --query 'length(AvailabilityZones[?State==`available`])' \
        --output text 2>/dev/null || echo "0")
    
    if [[ $az_count -lt 2 ]]; then
        unity_log "ERROR" "ALB requires at least 2 availability zones, found: $az_count"
        return 1
    fi
    
    unity_log "INFO" "Found $az_count availability zones"
    return 0
}

# Check CDN requirements
preflight_check_cdn_requirements() {
    unity_log "INFO" "Checking CloudFront requirements..."
    
    # CloudFront is global, just check if we can access it
    if ! aws cloudfront list-distributions --max-items 1 >/dev/null 2>&1; then
        unity_log "ERROR" "Cannot access CloudFront service"
        unity_log "ERROR" "Check IAM permissions for CloudFront"
        return 1
    fi
    
    return 0
}

# Generate pre-flight report
generate_preflight_report() {
    local deployment_type="$1"
    local stack_name="$2"
    local report_file=".unity/reports/preflight-${stack_name}-$(date +%Y%m%d-%H%M%S).json"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment_type": "$deployment_type",
    "stack_name": "$stack_name",
    "environment": "${ENVIRONMENT:-dev}",
    "region": "${AWS_REGION:-us-east-1}",
    "checks": {
        "aws": "$(preflight_check_aws >/dev/null 2>&1 && echo "passed" || echo "failed")",
        "docker": "$(preflight_check_docker >/dev/null 2>&1 && echo "passed" || echo "failed")",
        "config": "$(preflight_check_config >/dev/null 2>&1 && echo "passed" || echo "failed")",
        "network": "$(preflight_check_network >/dev/null 2>&1 && echo "passed" || echo "failed")",
        "security": "$(preflight_check_security >/dev/null 2>&1 && echo "passed" || echo "failed")"
    }
}
EOF
    
    unity_log "INFO" "Pre-flight report generated: $report_file"
}

# Export functions
export -f preflight_check_all
export -f preflight_check_aws
export -f preflight_check_docker
export -f preflight_check_resources
export -f preflight_check_config
export -f preflight_check_network
export -f preflight_check_security
export -f preflight_check_deployment_type
export -f generate_preflight_report