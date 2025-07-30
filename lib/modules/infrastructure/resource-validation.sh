#!/usr/bin/env bash
# =============================================================================
# Resource Validation Module
# Simple validation functions for existing AWS resources
# =============================================================================

# Prevent multiple sourcing
[ -n "${_RESOURCE_VALIDATION_SH_LOADED:-}" ] && return 0
_RESOURCE_VALIDATION_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source core modules
source "$PROJECT_ROOT/lib/modules/core/logging.sh" || true
source "$PROJECT_ROOT/lib/modules/core/errors.sh" || true

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate existing VPC
validate_existing_vpc() {
    local vpc_id="$1"
    
    # Empty VPC ID is valid (no existing VPC)
    [[ -z "$vpc_id" ]] && return 0
    
    log_info "Validating existing VPC: $vpc_id" "RESOURCE_VALIDATION"
    
    # Check if VPC exists and is available
    if aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].State' --output text 2>/dev/null | grep -q "available"; then
        log_info "VPC $vpc_id is valid and available" "RESOURCE_VALIDATION"
        return 0
    else
        if declare -f error_resource_not_found >/dev/null 2>&1; then
            error_resource_not_found "VPC" "$vpc_id"
        else
            log_error "VPC not found or not available: $vpc_id" "RESOURCE_VALIDATION"
        fi
        return 1
    fi
}

# Validate existing subnets
validate_existing_subnets() {
    local subnet_ids="$1"
    local vpc_id="$2"
    
    [[ -z "$subnet_ids" ]] && return 0
    
    log_info "Validating existing subnets: $subnet_ids" "RESOURCE_VALIDATION"
    
    # Convert comma-separated list to array
    IFS=',' read -ra SUBNET_ARRAY <<< "$subnet_ids"
    
    for subnet_id in "${SUBNET_ARRAY[@]}"; do
        # Check if subnet exists
        local subnet_vpc
        subnet_vpc=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" \
            --query 'Subnets[0].VpcId' --output text 2>/dev/null)
        
        if [[ $? -ne 0 ]]; then
            log_error "Subnet not found: $subnet_id" "RESOURCE_VALIDATION"
            return 1
        fi
        
        # Verify subnet belongs to the correct VPC if VPC is specified
        if [[ -n "$vpc_id" ]] && [[ "$subnet_vpc" != "$vpc_id" ]]; then
            log_error "Subnet $subnet_id belongs to VPC $subnet_vpc, not $vpc_id" "RESOURCE_VALIDATION"
            return 1
        fi
    done
    
    log_info "All subnets validated successfully" "RESOURCE_VALIDATION"
    return 0
}

# Validate existing security groups
validate_existing_security_groups() {
    local sg_ids="$1"
    local vpc_id="$2"
    
    [[ -z "$sg_ids" ]] && return 0
    
    log_info "Validating existing security groups: $sg_ids" "RESOURCE_VALIDATION"
    
    # Convert comma-separated list to array
    IFS=',' read -ra SG_ARRAY <<< "$sg_ids"
    
    for sg_id in "${SG_ARRAY[@]}"; do
        # Check if security group exists
        local sg_vpc
        sg_vpc=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query 'SecurityGroups[0].VpcId' --output text 2>/dev/null)
        
        if [[ $? -ne 0 ]]; then
            log_error "Security group not found: $sg_id" "RESOURCE_VALIDATION"
            return 1
        fi
        
        # Verify security group belongs to the correct VPC if VPC is specified
        if [[ -n "$vpc_id" ]] && [[ "$sg_vpc" != "$vpc_id" ]]; then
            log_error "Security group $sg_id belongs to VPC $sg_vpc, not $vpc_id" "RESOURCE_VALIDATION"
            return 1
        fi
    done
    
    log_info "All security groups validated successfully" "RESOURCE_VALIDATION"
    return 0
}

# Validate existing EFS
validate_existing_efs() {
    local efs_id="$1"
    
    [[ -z "$efs_id" ]] && return 0
    
    log_info "Validating existing EFS: $efs_id" "RESOURCE_VALIDATION"
    
    # Check if EFS exists and is available
    local efs_state
    efs_state=$(aws efs describe-file-systems --file-system-id "$efs_id" \
        --query 'FileSystems[0].LifeCycleState' --output text 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        if declare -f error_resource_not_found >/dev/null 2>&1; then
            error_resource_not_found "EFS" "$efs_id"
        else
            log_error "EFS not found: $efs_id" "RESOURCE_VALIDATION"
        fi
        return 1
    fi
    
    if [[ "$efs_state" != "available" ]]; then
        log_error "EFS is not in available state: $efs_state" "RESOURCE_VALIDATION"
        return 1
    fi
    
    log_info "EFS $efs_id is valid and available" "RESOURCE_VALIDATION"
    return 0
}

# Validate existing ALB
validate_existing_alb() {
    local alb_arn="$1"
    
    [[ -z "$alb_arn" ]] && return 0
    
    log_info "Validating existing ALB: $alb_arn" "RESOURCE_VALIDATION"
    
    # Check if ALB exists and is active
    local alb_state
    alb_state=$(aws elbv2 describe-load-balancers --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        if declare -f error_resource_not_found >/dev/null 2>&1; then
            error_resource_not_found "ALB" "$alb_arn"
        else
            log_error "ALB not found: $alb_arn" "RESOURCE_VALIDATION"
        fi
        return 1
    fi
    
    if [[ "$alb_state" != "active" ]]; then
        log_error "ALB is not in active state: $alb_state" "RESOURCE_VALIDATION"
        return 1
    fi
    
    log_info "ALB $alb_arn is valid and active" "RESOURCE_VALIDATION"
    return 0
}

# Validate existing target group
validate_existing_target_group() {
    local tg_arn="$1"
    
    [[ -z "$tg_arn" ]] && return 0
    
    log_info "Validating existing target group: $tg_arn" "RESOURCE_VALIDATION"
    
    # Check if target group exists
    if aws elbv2 describe-target-groups --target-group-arns "$tg_arn" \
        --query 'TargetGroups[0].TargetGroupArn' --output text >/dev/null 2>&1; then
        log_info "Target group $tg_arn is valid" "RESOURCE_VALIDATION"
        return 0
    else
        log_error "Target group not found: $tg_arn" "RESOURCE_VALIDATION"
        return 1
    fi
}

# Validate existing CloudFront distribution
validate_existing_cloudfront() {
    local distribution_id="$1"
    
    [[ -z "$distribution_id" ]] && return 0
    
    log_info "Validating existing CloudFront distribution: $distribution_id" "RESOURCE_VALIDATION"
    
    # Check if distribution exists and is deployed
    local cf_status
    cf_status=$(aws cloudfront get-distribution --id "$distribution_id" \
        --query 'Distribution.Status' --output text 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        if declare -f error_resource_not_found >/dev/null 2>&1; then
            error_resource_not_found "CloudFront" "$distribution_id"
        else
            log_error "CloudFront distribution not found: $distribution_id" "RESOURCE_VALIDATION"
        fi
        return 1
    fi
    
    if [[ "$cf_status" != "Deployed" ]]; then
        log_warning "CloudFront distribution is not deployed: $cf_status" "RESOURCE_VALIDATION"
    fi
    
    log_info "CloudFront distribution $distribution_id is valid" "RESOURCE_VALIDATION"
    return 0
}

# Validate all existing resources
validate_all_existing_resources() {
    local errors=0
    
    log_info "Validating all existing resources..." "RESOURCE_VALIDATION"
    
    # Validate VPC
    if [[ -n "${EXISTING_VPC_ID:-}" ]]; then
        validate_existing_vpc "$EXISTING_VPC_ID" || ((errors++))
    fi
    
    # Validate subnets
    if [[ -n "${EXISTING_SUBNET_IDS:-}" ]]; then
        validate_existing_subnets "$EXISTING_SUBNET_IDS" "${EXISTING_VPC_ID:-}" || ((errors++))
    fi
    
    # Validate security groups
    if [[ -n "${EXISTING_SECURITY_GROUP_IDS:-}" ]]; then
        validate_existing_security_groups "$EXISTING_SECURITY_GROUP_IDS" "${EXISTING_VPC_ID:-}" || ((errors++))
    fi
    
    # Validate EFS
    if [[ -n "${EXISTING_EFS_ID:-}" ]]; then
        validate_existing_efs "$EXISTING_EFS_ID" || ((errors++))
    fi
    
    # Validate ALB
    if [[ -n "${EXISTING_ALB_ARN:-}" ]]; then
        validate_existing_alb "$EXISTING_ALB_ARN" || ((errors++))
    fi
    
    # Validate target group
    if [[ -n "${EXISTING_TARGET_GROUP_ARN:-}" ]]; then
        validate_existing_target_group "$EXISTING_TARGET_GROUP_ARN" || ((errors++))
    fi
    
    # Validate CloudFront
    if [[ -n "${EXISTING_CLOUDFRONT_ID:-}" ]]; then
        validate_existing_cloudfront "$EXISTING_CLOUDFRONT_ID" || ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Resource validation failed with $errors errors" "RESOURCE_VALIDATION"
        return 1
    fi
    
    log_info "All existing resources validated successfully" "RESOURCE_VALIDATION"
    return 0
}

# Export validation functions
export -f validate_existing_vpc
export -f validate_existing_subnets
export -f validate_existing_security_groups
export -f validate_existing_efs
export -f validate_existing_alb
export -f validate_existing_target_group
export -f validate_existing_cloudfront
export -f validate_all_existing_resources