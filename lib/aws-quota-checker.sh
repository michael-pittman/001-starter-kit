#!/usr/bin/env bash
#
# AWS Service Quota Checker
# Validates AWS service quotas before deployment to prevent failures
#
# Dependencies: aws-cli, jq
# Compatible with bash 3.x+
#

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aws-cli-v2.sh"

# Quota tracking
declare -gA SERVICE_QUOTAS
declare -gA CURRENT_USAGE
declare -gA QUOTA_WARNINGS
declare -gA QUOTA_REQUIREMENTS

# Default quota requirements for deployment
QUOTA_REQUIREMENTS=(
    [ec2_instances]=2
    [vpc_count]=1
    [elastic_ips]=1
    [security_groups]=5
    [efs_filesystems]=1
    [nat_gateways]=1
    [internet_gateways]=1
    [route_tables]=3
    [subnets]=4
    [alb_count]=1
)

# Initialize quota checker
init_quota_checker() {
    SERVICE_QUOTAS=(
        [ec2_instances]=0
        [ec2_vcpus]=0
        [vpc_count]=0
        [elastic_ips]=0
        [security_groups]=0
        [efs_filesystems]=0
        [nat_gateways]=0
        [internet_gateways]=0
        [route_tables]=0
        [subnets]=0
        [alb_count]=0
        [cloudformation_stacks]=0
    )
    
    CURRENT_USAGE=(
        [ec2_instances]=0
        [ec2_vcpus]=0
        [vpc_count]=0
        [elastic_ips]=0
        [security_groups]=0
        [efs_filesystems]=0
        [nat_gateways]=0
        [internet_gateways]=0
        [route_tables]=0
        [subnets]=0
        [alb_count]=0
        [cloudformation_stacks]=0
    )
    
    QUOTA_WARNINGS=()
}

# Get EC2 instance quotas
check_ec2_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking EC2 quotas in $region..."
    
    # Get Running On-Demand instances quota
    local instance_quota
    instance_quota=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Quota.Value // 5')
    
    SERVICE_QUOTAS[ec2_instances]="$instance_quota"
    
    # Get vCPU quota for standard instances
    local vcpu_quota
    vcpu_quota=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Quota.Value // 32')
    
    SERVICE_QUOTAS[ec2_vcpus]="$vcpu_quota"
    
    # Get current usage
    local running_instances
    running_instances=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running,pending" \
        --region "$region" \
        --output json | jq '[.Reservations[].Instances[]] | length')
    
    CURRENT_USAGE[ec2_instances]="$running_instances"
    
    # Calculate vCPU usage
    local vcpu_usage
    vcpu_usage=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running,pending" \
        --region "$region" \
        --output json | jq '[.Reservations[].Instances[].CpuOptions.CoreCount // 1] | add // 0')
    
    CURRENT_USAGE[ec2_vcpus]="$vcpu_usage"
    
    # Check spot instance quotas
    check_spot_quotas "$region"
}

# Check spot instance quotas
check_spot_quotas() {
    local region="$1"
    
    echo "Checking Spot instance quotas..."
    
    # Get spot instance request quota
    local spot_quota
    spot_quota=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-34B43A08 \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Quota.Value // 20')
    
    SERVICE_QUOTAS[spot_requests]="$spot_quota"
    
    # Get current spot usage
    local spot_usage
    spot_usage=$(aws ec2 describe-spot-instance-requests \
        --filters "Name=state,Values=active,open" \
        --region "$region" \
        --output json 2>/dev/null | jq '.SpotInstanceRequests | length')
    
    CURRENT_USAGE[spot_requests]="$spot_usage"
}

# Check VPC quotas
check_vpc_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking VPC quotas in $region..."
    
    # VPC quota (default is 5)
    SERVICE_QUOTAS[vpc_count]=5
    
    # Get current VPC count
    local vpc_count
    vpc_count=$(aws ec2 describe-vpcs \
        --region "$region" \
        --output json | jq '.Vpcs | length')
    
    CURRENT_USAGE[vpc_count]="$vpc_count"
    
    # Internet Gateway quota (one per VPC)
    SERVICE_QUOTAS[internet_gateways]=5
    
    local igw_count
    igw_count=$(aws ec2 describe-internet-gateways \
        --region "$region" \
        --output json | jq '.InternetGateways | length')
    
    CURRENT_USAGE[internet_gateways]="$igw_count"
    
    # NAT Gateway quota
    SERVICE_QUOTAS[nat_gateways]=5
    
    local nat_count
    nat_count=$(aws ec2 describe-nat-gateways \
        --filter "Name=state,Values=available,pending" \
        --region "$region" \
        --output json | jq '.NatGateways | length')
    
    CURRENT_USAGE[nat_gateways]="$nat_count"
}

# Check Elastic IP quotas
check_eip_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking Elastic IP quotas..."
    
    # Default EIP quota is 5
    SERVICE_QUOTAS[elastic_ips]=5
    
    # Get current EIP usage
    local eip_count
    eip_count=$(aws ec2 describe-addresses \
        --region "$region" \
        --output json | jq '.Addresses | length')
    
    CURRENT_USAGE[elastic_ips]="$eip_count"
}

# Check Security Group quotas
check_security_group_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking Security Group quotas..."
    
    # Default SG quota per VPC is 2500
    SERVICE_QUOTAS[security_groups]=2500
    
    # Get current SG count
    local sg_count
    sg_count=$(aws ec2 describe-security-groups \
        --region "$region" \
        --output json | jq '.SecurityGroups | length')
    
    CURRENT_USAGE[security_groups]="$sg_count"
}

# Check EFS quotas
check_efs_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking EFS quotas..."
    
    # Get EFS file system quota
    local efs_quota
    efs_quota=$(aws service-quotas get-service-quota \
        --service-code elasticfilesystem \
        --quota-code L-848C634D \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.Quota.Value // 1000')
    
    SERVICE_QUOTAS[efs_filesystems]="$efs_quota"
    
    # Get current EFS usage
    local efs_count
    efs_count=$(aws efs describe-file-systems \
        --region "$region" \
        --output json 2>/dev/null | jq '.FileSystems | length' || echo "0")
    
    CURRENT_USAGE[efs_filesystems]="$efs_count"
}

# Check ALB quotas
check_alb_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking ALB quotas..."
    
    # Default ALB quota
    SERVICE_QUOTAS[alb_count]=50
    
    # Get current ALB usage
    local alb_count
    alb_count=$(aws elbv2 describe-load-balancers \
        --region "$region" \
        --output json 2>/dev/null | jq '.LoadBalancers | length' || echo "0")
    
    CURRENT_USAGE[alb_count]="$alb_count"
}

# Check CloudFormation quotas
check_cloudformation_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Checking CloudFormation quotas..."
    
    # Default stack quota is 200
    SERVICE_QUOTAS[cloudformation_stacks]=200
    
    # Get current stack count
    local stack_count
    stack_count=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --region "$region" \
        --output json | jq '.StackSummaries | length')
    
    CURRENT_USAGE[cloudformation_stacks]="$stack_count"
}

# Analyze quota availability
analyze_quota_availability() {
    local deployment_type="${1:-standard}"
    
    echo -e "\n=== Quota Analysis ==="
    
    local has_warnings=false
    local has_errors=false
    
    # Adjust requirements based on deployment type
    case "$deployment_type" in
        "multi-az")
            QUOTA_REQUIREMENTS[subnets]=6
            QUOTA_REQUIREMENTS[nat_gateways]=2
            ;;
        "enterprise")
            QUOTA_REQUIREMENTS[subnets]=6
            QUOTA_REQUIREMENTS[nat_gateways]=2
            QUOTA_REQUIREMENTS[alb_count]=1
            ;;
    esac
    
    # Check each quota
    for quota_type in "${!QUOTA_REQUIREMENTS[@]}"; do
        local required="${QUOTA_REQUIREMENTS[$quota_type]}"
        local limit="${SERVICE_QUOTAS[$quota_type]:-0}"
        local current="${CURRENT_USAGE[$quota_type]:-0}"
        local available=$((limit - current))
        
        printf "%-25s Current: %3d / Limit: %3d | Available: %3d | Required: %3d" \
            "$quota_type:" "$current" "$limit" "$available" "$required"
        
        if [[ $available -lt $required ]]; then
            echo " ✗"
            QUOTA_WARNINGS[$quota_type]="Insufficient quota: need $required, have $available available"
            has_errors=true
        elif [[ $available -lt $((required * 2)) ]]; then
            echo " ⚠"
            QUOTA_WARNINGS[$quota_type]="Low quota: only $available available"
            has_warnings=true
        else
            echo " ✓"
        fi
    done
    
    echo ""
    
    # Report warnings and errors
    if [[ ${#QUOTA_WARNINGS[@]} -gt 0 ]]; then
        echo "Quota Issues:"
        for quota_type in "${!QUOTA_WARNINGS[@]}"; do
            echo "  - $quota_type: ${QUOTA_WARNINGS[$quota_type]}"
        done
        echo ""
    fi
    
    if [[ "$has_errors" == "true" ]]; then
        echo "✗ Quota check failed - insufficient quotas for deployment"
        return 1
    elif [[ "$has_warnings" == "true" ]]; then
        echo "⚠ Quota check passed with warnings"
        return 0
    else
        echo "✓ All quotas sufficient for deployment"
        return 0
    fi
}

# Request quota increase
request_quota_increase() {
    local service_code="$1"
    local quota_code="$2"
    local desired_value="$3"
    local region="${4:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    echo "Requesting quota increase for $service_code/$quota_code to $desired_value..."
    
    aws service-quotas request-service-quota-increase \
        --service-code "$service_code" \
        --quota-code "$quota_code" \
        --desired-value "$desired_value" \
        --region "$region" \
        --output json 2>/dev/null || {
        echo "Failed to request quota increase"
        return 1
    }
    
    echo "✓ Quota increase requested"
}

# Generate quota report
generate_quota_report() {
    local output_file="${1:-quota-report.json}"
    local region="${2:-${AWS_DEFAULT_REGION:-us-east-1}}"
    
    local report_data
    report_data=$(jq -n \
        --argjson quotas "$(printf '%s\n' "${!SERVICE_QUOTAS[@]}" | jq -R . | jq -s 'map(. as $k | {($k): $SERVICE_QUOTAS[$k]}) | add')" \
        --argjson usage "$(printf '%s\n' "${!CURRENT_USAGE[@]}" | jq -R . | jq -s 'map(. as $k | {($k): $CURRENT_USAGE[$k]}) | add')" \
        --argjson warnings "$(printf '%s\n' "${!QUOTA_WARNINGS[@]}" | jq -R . | jq -s 'map(. as $k | {($k): $QUOTA_WARNINGS[$k]}) | add')" \
        --arg region "$region" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
            timestamp: $timestamp,
            region: $region,
            quotas: $quotas,
            usage: $usage,
            warnings: $warnings
        }')
    
    echo "$report_data" > "$output_file"
    echo "Quota report saved to: $output_file"
}

# Check all quotas
check_all_quotas() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    local deployment_type="${2:-standard}"
    
    echo "===================================================="
    echo "AWS Service Quota Check"
    echo "Region: $region"
    echo "Deployment Type: $deployment_type"
    echo "===================================================="
    
    # Initialize
    init_quota_checker
    
    # Run all quota checks
    check_ec2_quotas "$region"
    check_vpc_quotas "$region"
    check_eip_quotas "$region"
    check_security_group_quotas "$region"
    check_efs_quotas "$region"
    check_alb_quotas "$region"
    check_cloudformation_quotas "$region"
    
    # Analyze results
    analyze_quota_availability "$deployment_type"
    
    # Generate report
    generate_quota_report "quota-report-$(date +%Y%m%d-%H%M%S).json" "$region"
}

# Quota monitoring function
monitor_quota_usage() {
    local region="${1:-${AWS_DEFAULT_REGION:-us-east-1}}"
    local threshold="${2:-80}"
    
    echo "Monitoring quota usage (threshold: ${threshold}%)..."
    
    init_quota_checker
    
    # Quick quota checks
    check_ec2_quotas "$region" &>/dev/null
    check_vpc_quotas "$region" &>/dev/null
    check_eip_quotas "$region" &>/dev/null
    
    # Check usage percentages
    for quota_type in "${!SERVICE_QUOTAS[@]}"; do
        local limit="${SERVICE_QUOTAS[$quota_type]}"
        local current="${CURRENT_USAGE[$quota_type]}"
        
        if [[ $limit -gt 0 ]]; then
            local usage_percent=$((current * 100 / limit))
            
            if [[ $usage_percent -ge $threshold ]]; then
                echo "⚠ High quota usage for $quota_type: ${usage_percent}% (${current}/${limit})"
            fi
        fi
    done
}

# Export functions
export -f init_quota_checker
export -f check_ec2_quotas
export -f check_spot_quotas
export -f check_vpc_quotas
export -f check_eip_quotas
export -f check_security_group_quotas
export -f check_efs_quotas
export -f check_alb_quotas
export -f check_cloudformation_quotas
export -f analyze_quota_availability
export -f request_quota_increase
export -f generate_quota_report
export -f check_all_quotas
export -f monitor_quota_usage