#!/usr/bin/env bash
# =============================================================================
# Existing Resources Infrastructure Module
# Manages existing AWS resources for deployment reuse
# =============================================================================

# Prevent multiple sourcing
[ -n "${_EXISTING_RESOURCES_SH_LOADED:-}" ] && return 0
_EXISTING_RESOURCES_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/instance-utils.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# EXISTING RESOURCES CONFIGURATION
# =============================================================================

# Load existing resources configuration
load_existing_resources_config() {
    local environment="${1:-$ENVIRONMENT}"
    local config_file="${2:-config/environments/${environment}.yml}"
    
    log_info "Loading existing resources configuration from: $config_file" "EXISTING_RESOURCES"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "Configuration file not found: $config_file" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Load configuration using yq or similar tool
    local config
    if command -v yq >/dev/null 2>&1; then
        config=$(yq eval '.existing_resources' -o=json "$config_file" 2>/dev/null)
    else
        log_error "yq is required for configuration parsing" "EXISTING_RESOURCES"
        return 1
    fi
    
    if [[ -z "$config" ]]; then
        log_warn "No existing_resources configuration found in: $config_file" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Export configuration as environment variables
    export EXISTING_RESOURCES_ENABLED=$(echo "$config" | yq eval '.enabled // false')
    export EXISTING_RESOURCES_VALIDATION_MODE=$(echo "$config" | yq eval '.validation_mode // "strict"')
    export EXISTING_RESOURCES_AUTO_DISCOVERY=$(echo "$config" | yq eval '.auto_discovery // false')
    
    log_info "Existing resources enabled: $EXISTING_RESOURCES_ENABLED" "EXISTING_RESOURCES"
    return 0
}

# =============================================================================
# RESOURCE VALIDATION
# =============================================================================

# Validate existing VPC
validate_existing_vpc() {
    local vpc_id="$1"
    local expected_cidr="${2:-}"
    
    log_info "Validating existing VPC: $vpc_id" "EXISTING_RESOURCES"
    
    # If VPC ID is empty, no validation needed
    if [[ -z "$vpc_id" ]]; then
        log_info "No VPC ID provided, skipping validation" "EXISTING_RESOURCES"
        return 0
    fi
    
    # Check if VPC exists
    local vpc_info
    vpc_info=$(aws ec2 describe-vpcs \
        --vpc-ids "$vpc_id" \
        --query 'Vpcs[0]' \
        --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "VPC not found or inaccessible: $vpc_id" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Validate VPC state
    local vpc_state
    vpc_state=$(echo "$vpc_info" | jq -r '.State')
    if [[ "$vpc_state" != "available" ]]; then
        log_error "VPC is not in available state: $vpc_state" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Validate CIDR if provided
    if [[ -n "$expected_cidr" ]]; then
        local actual_cidr
        actual_cidr=$(echo "$vpc_info" | jq -r '.CidrBlock')
        if [[ "$actual_cidr" != "$expected_cidr" ]]; then
            log_warn "VPC CIDR mismatch. Expected: $expected_cidr, Actual: $actual_cidr" "EXISTING_RESOURCES"
            if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" == "strict" ]]; then
                return 1
            fi
        fi
    fi
    
    log_info "VPC validation successful: $vpc_id" "EXISTING_RESOURCES"
    return 0
}

# Validate existing subnets
validate_existing_subnets() {
    local subnet_ids="$1"
    local vpc_id="$2"
    local subnet_type="${3:-public}"
    
    log_info "Validating existing $subnet_type subnets: $subnet_ids" "EXISTING_RESOURCES"
    
    if [[ -z "$subnet_ids" ]]; then
        log_error "Subnet IDs are required for validation" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Convert comma-separated list to array
    IFS=',' read -ra SUBNET_ARRAY <<< "$subnet_ids"
    
    for subnet_id in "${SUBNET_ARRAY[@]}"; do
        # Check if subnet exists
        local subnet_info
        subnet_info=$(aws ec2 describe-subnets \
            --subnet-ids "$subnet_id" \
            --query 'Subnets[0]' \
            --output json 2>/dev/null)
        
        if [[ $? -ne 0 ]]; then
            log_error "Subnet not found or inaccessible: $subnet_id" "EXISTING_RESOURCES"
            return 1
        fi
        
        # Validate subnet state
        local subnet_state
        subnet_state=$(echo "$subnet_info" | jq -r '.State')
        if [[ "$subnet_state" != "available" ]]; then
            log_error "Subnet is not in available state: $subnet_state" "EXISTING_RESOURCES"
            return 1
        fi
        
        # Validate VPC association
        local subnet_vpc_id
        subnet_vpc_id=$(echo "$subnet_info" | jq -r '.VpcId')
        if [[ "$subnet_vpc_id" != "$vpc_id" ]]; then
            log_error "Subnet $subnet_id is not associated with VPC $vpc_id" "EXISTING_RESOURCES"
            return 1
        fi
        
        # Validate subnet type
        local map_public_ip_on_launch
        map_public_ip_on_launch=$(echo "$subnet_info" | jq -r '.MapPublicIpOnLaunch')
        if [[ "$subnet_type" == "public" && "$map_public_ip_on_launch" != "true" ]]; then
            log_warn "Subnet $subnet_id may not be properly configured as public" "EXISTING_RESOURCES"
        fi
    done
    
    log_info "$subnet_type subnet validation successful: $subnet_ids" "EXISTING_RESOURCES"
    return 0
}

# Validate existing security groups
validate_existing_security_groups() {
    local security_group_ids="$1"
    local vpc_id="$2"
    
    log_info "Validating existing security groups: $security_group_ids" "EXISTING_RESOURCES"
    
    if [[ -z "$security_group_ids" ]]; then
        log_error "Security group IDs are required for validation" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Convert comma-separated list to array
    IFS=',' read -ra SG_ARRAY <<< "$security_group_ids"
    
    for sg_id in "${SG_ARRAY[@]}"; do
        # Check if security group exists
        local sg_info
        sg_info=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0]' \
            --output json 2>/dev/null)
        
        if [[ $? -ne 0 ]]; then
            log_error "Security group not found or inaccessible: $sg_id" "EXISTING_RESOURCES"
            return 1
        fi
        
        # Validate VPC association
        local sg_vpc_id
        sg_vpc_id=$(echo "$sg_info" | jq -r '.VpcId')
        if [[ "$sg_vpc_id" != "$vpc_id" ]]; then
            log_error "Security group $sg_id is not associated with VPC $vpc_id" "EXISTING_RESOURCES"
            return 1
        fi
    done
    
    log_info "Security group validation successful: $security_group_ids" "EXISTING_RESOURCES"
    return 0
}

# Validate existing ALB
validate_existing_alb() {
    local alb_arn="$1"
    
    log_info "Validating existing ALB: $alb_arn" "EXISTING_RESOURCES"
    
    if [[ -z "$alb_arn" ]]; then
        log_error "ALB ARN is required for validation" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Check if ALB exists
    local alb_info
    alb_info=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0]' \
        --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ "$alb_info" == "null" ]] || [[ -z "$alb_info" ]]; then
        log_error "ALB not found or inaccessible: $alb_arn" "EXISTING_RESOURCES"
        return 1
    fi
    
    # Validate ALB state
    local alb_state
    alb_state=$(echo "$alb_info" | jq -r '.State.Code')
    if [[ "$alb_state" != "active" ]]; then
        log_error "ALB is not in active state: $alb_state" "EXISTING_RESOURCES"
        return 1
    fi
    
    log_info "ALB validation successful: $alb_arn" "EXISTING_RESOURCES"
    return 0
}

# =============================================================================
# RESOURCE DISCOVERY
# =============================================================================

# Auto-discover existing resources
discover_existing_resources() {
    local stack_name="$1"
    local environment="$2"
    
    log_info "Auto-discovering existing resources for stack: $stack_name" "EXISTING_RESOURCES"
    
    local discovered_resources="{}"
    
    # Discover VPC
    local vpc_id
    vpc_id=$(discover_vpc "$stack_name" "$environment")
    if [[ -n "$vpc_id" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg vpc_id "$vpc_id" '.vpc.id = $vpc_id')
    fi
    
    # Discover subnets
    local public_subnets
    public_subnets=$(discover_subnets "$stack_name" "$environment" "public")
    if [[ -n "$public_subnets" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg subnets "$public_subnets" '.subnets.public.ids = ($subnets | split(","))')
    fi
    
    local private_subnets
    private_subnets=$(discover_subnets "$stack_name" "$environment" "private")
    if [[ -n "$private_subnets" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg subnets "$private_subnets" '.subnets.private.ids = ($subnets | split(","))')
    fi
    
    # Discover security groups
    local alb_sg
    alb_sg=$(discover_security_group "$stack_name" "$environment" "alb")
    if [[ -n "$alb_sg" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg sg_id "$alb_sg" '.security_groups.alb.id = $sg_id')
    fi
    
    local ec2_sg
    ec2_sg=$(discover_security_group "$stack_name" "$environment" "ec2")
    if [[ -n "$ec2_sg" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg sg_id "$ec2_sg" '.security_groups.ec2.id = $sg_id')
    fi
    
    # Discover ALB
    local alb_arn
    alb_arn=$(discover_alb "$stack_name" "$environment")
    if [[ -n "$alb_arn" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg alb_arn "$alb_arn" '.alb.load_balancer_arn = $alb_arn')
    fi
    
    # Discover EFS
    local efs_id
    efs_id=$(discover_efs "$stack_name" "$environment")
    if [[ -n "$efs_id" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg efs_id "$efs_id" '.efs.file_system_id = $efs_id')
    fi
    
    # Discover CloudFront
    local cf_id
    cf_id=$(discover_cloudfront "$stack_name" "$environment")
    if [[ -n "$cf_id" ]]; then
        discovered_resources=$(echo "$discovered_resources" | jq --arg cf_id "$cf_id" '.cloudfront.distribution_id = $cf_id')
    fi
    
    echo "$discovered_resources"
}

# Discover VPC by name pattern
discover_vpc() {
    local stack_name="$1"
    local environment="$2"
    
    local vpc_pattern="${stack_name}-${environment}-vpc"
    
    aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$vpc_pattern" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null
}

# Discover subnets by name pattern
discover_subnets() {
    local stack_name="$1"
    local environment="$2"
    local subnet_type="$3"
    
    local subnet_pattern="${stack_name}-${environment}-${subnet_type}-subnet-*"
    
    aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=$subnet_pattern" \
        --query 'Subnets[].SubnetId' \
        --output text 2>/dev/null | tr '\t' ','
}

# Discover security group by name pattern
discover_security_group() {
    local stack_name="$1"
    local environment="$2"
    local sg_type="$3"
    
    local sg_pattern="${stack_name}-${environment}-${sg_type}-sg"
    
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_pattern" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null
}

# Discover ALB by name pattern
discover_alb() {
    local stack_name="$1"
    local environment="$2"
    
    local alb_pattern="${stack_name}-${environment}-alb"
    
    aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, '$alb_pattern')].LoadBalancerArn" \
        --output text 2>/dev/null
}

# Discover EFS by name pattern
discover_efs() {
    local stack_name="$1"
    local environment="$2"
    
    local efs_pattern="${stack_name}-${environment}-efs"
    
    aws efs describe-file-systems \
        --query "FileSystems[?contains(Name, '$efs_pattern')].FileSystemId" \
        --output text 2>/dev/null
}

# Discover CloudFront by name pattern
discover_cloudfront() {
    local stack_name="$1"
    local environment="$2"
    
    local cf_pattern="${stack_name}-${environment}-cdn"
    
    aws cloudfront list-distributions \
        --query "DistributionList.Items[?contains(Comment, '$cf_pattern')].Id" \
        --output text 2>/dev/null
}

# =============================================================================
# RESOURCE MAPPING
# =============================================================================

# Map existing resources to deployment variables
map_existing_resources() {
    local resources_config="$1"
    local stack_name="$2"
    
    log_info "Mapping existing resources to deployment variables" "EXISTING_RESOURCES"
    
    # Map VPC
    local vpc_id
    vpc_id=$(echo "$resources_config" | jq -r '.vpc.id // empty')
    if [[ -n "$vpc_id" ]]; then
        set_variable "VPC_ID" "$vpc_id" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped VPC ID: $vpc_id" "EXISTING_RESOURCES"
    fi
    
    # Map subnets
    local public_subnet_ids
    public_subnet_ids=$(echo "$resources_config" | jq -r '.subnets.public.ids // [] | join(",")')
    if [[ -n "$public_subnet_ids" ]]; then
        set_variable "PUBLIC_SUBNET_IDS" "$public_subnet_ids" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped public subnet IDs: $public_subnet_ids" "EXISTING_RESOURCES"
    fi
    
    local private_subnet_ids
    private_subnet_ids=$(echo "$resources_config" | jq -r '.subnets.private.ids // [] | join(",")')
    if [[ -n "$private_subnet_ids" ]]; then
        set_variable "PRIVATE_SUBNET_IDS" "$private_subnet_ids" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped private subnet IDs: $private_subnet_ids" "EXISTING_RESOURCES"
    fi
    
    # Map security groups
    local alb_sg_id
    alb_sg_id=$(echo "$resources_config" | jq -r '.security_groups.alb.id // empty')
    if [[ -n "$alb_sg_id" ]]; then
        set_variable "ALB_SECURITY_GROUP_ID" "$alb_sg_id" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped ALB security group ID: $alb_sg_id" "EXISTING_RESOURCES"
    fi
    
    local ec2_sg_id
    ec2_sg_id=$(echo "$resources_config" | jq -r '.security_groups.ec2.id // empty')
    if [[ -n "$ec2_sg_id" ]]; then
        set_variable "EC2_SECURITY_GROUP_ID" "$ec2_sg_id" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped EC2 security group ID: $ec2_sg_id" "EXISTING_RESOURCES"
    fi
    
    local efs_sg_id
    efs_sg_id=$(echo "$resources_config" | jq -r '.security_groups.efs.id // empty')
    if [[ -n "$efs_sg_id" ]]; then
        set_variable "EFS_SECURITY_GROUP_ID" "$efs_sg_id" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped EFS security group ID: $efs_sg_id" "EXISTING_RESOURCES"
    fi
    
    # Map ALB
    local alb_arn
    alb_arn=$(echo "$resources_config" | jq -r '.alb.load_balancer_arn // empty')
    if [[ -n "$alb_arn" ]]; then
        set_variable "ALB_LOAD_BALANCER_ARN" "$alb_arn" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped ALB ARN: $alb_arn" "EXISTING_RESOURCES"
    fi
    
    # Map EFS
    local efs_id
    efs_id=$(echo "$resources_config" | jq -r '.efs.file_system_id // empty')
    if [[ -n "$efs_id" ]]; then
        set_variable "EFS_FILE_SYSTEM_ID" "$efs_id" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped EFS file system ID: $efs_id" "EXISTING_RESOURCES"
    fi
    
    # Map CloudFront
    local cf_id
    cf_id=$(echo "$resources_config" | jq -r '.cloudfront.distribution_id // empty')
    if [[ -n "$cf_id" ]]; then
        set_variable "CLOUDFRONT_DISTRIBUTION_ID" "$cf_id" "$VARIABLE_SCOPE_STACK"
        log_info "Mapped CloudFront distribution ID: $cf_id" "EXISTING_RESOURCES"
    fi
}

# =============================================================================
# MAIN EXISTING RESOURCES SETUP
# =============================================================================

# Setup existing resources for deployment
setup_existing_resources() {
    local stack_name="$1"
    local environment="$2"
    
    log_info "Setting up existing resources for deployment" "EXISTING_RESOURCES"
    
    # Load configuration
    if ! load_existing_resources_config "$environment"; then
        log_warn "Failed to load existing resources configuration" "EXISTING_RESOURCES"
        return 0
    fi
    
    # Check if existing resources are enabled
    if [[ "$EXISTING_RESOURCES_ENABLED" != "true" ]]; then
        log_info "Existing resources not enabled, proceeding with normal deployment" "EXISTING_RESOURCES"
        return 0
    fi
    
    # Get resources configuration
    local resources_config
    if [[ "$EXISTING_RESOURCES_AUTO_DISCOVERY" == "true" ]]; then
        log_info "Auto-discovering existing resources" "EXISTING_RESOURCES"
        resources_config=$(discover_existing_resources "$stack_name" "$environment")
    else
        # Load from configuration file
        local config_file="config/environments/${environment}.yml"
        resources_config=$(yq eval '.existing_resources.resources' "$config_file" 2>/dev/null)
    fi
    
    if [[ -z "$resources_config" || "$resources_config" == "null" ]]; then
        log_warn "No existing resources configuration found" "EXISTING_RESOURCES"
        return 0
    fi
    
    # Validate resources if validation is enabled
    if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" != "skip" ]]; then
        log_info "Validating existing resources" "EXISTING_RESOURCES"
        
        # Validate VPC
        local vpc_id
        vpc_id=$(echo "$resources_config" | jq -r '.vpc.id // empty')
        if [[ -n "$vpc_id" ]]; then
            if ! validate_existing_vpc "$vpc_id"; then
                if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" == "strict" ]]; then
                    log_error "VPC validation failed" "EXISTING_RESOURCES"
                    return 1
                fi
            fi
        fi
        
        # Validate subnets
        local public_subnet_ids
        public_subnet_ids=$(echo "$resources_config" | jq -r '.subnets.public.ids // [] | join(",")')
        if [[ -n "$public_subnet_ids" && -n "$vpc_id" ]]; then
            if ! validate_existing_subnets "$public_subnet_ids" "$vpc_id" "public"; then
                if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" == "strict" ]]; then
                    log_error "Public subnet validation failed" "EXISTING_RESOURCES"
                    return 1
                fi
            fi
        fi
        
        local private_subnet_ids
        private_subnet_ids=$(echo "$resources_config" | jq -r '.subnets.private.ids // [] | join(",")')
        if [[ -n "$private_subnet_ids" && -n "$vpc_id" ]]; then
            if ! validate_existing_subnets "$private_subnet_ids" "$vpc_id" "private"; then
                if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" == "strict" ]]; then
                    log_error "Private subnet validation failed" "EXISTING_RESOURCES"
                    return 1
                fi
            fi
        fi
        
        # Validate security groups
        local security_group_ids
        security_group_ids=$(echo "$resources_config" | jq -r '.security_groups | to_entries[] | .value.id // empty' | grep -v '^$' | tr '\n' ',')
        if [[ -n "$security_group_ids" && -n "$vpc_id" ]]; then
            if ! validate_existing_security_groups "$security_group_ids" "$vpc_id"; then
                if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" == "strict" ]]; then
                    log_error "Security group validation failed" "EXISTING_RESOURCES"
                    return 1
                fi
            fi
        fi
        
        # Validate ALB
        local alb_arn
        alb_arn=$(echo "$resources_config" | jq -r '.alb.load_balancer_arn // empty')
        if [[ -n "$alb_arn" ]]; then
            if ! validate_existing_alb "$alb_arn"; then
                if [[ "$EXISTING_RESOURCES_VALIDATION_MODE" == "strict" ]]; then
                    log_error "ALB validation failed" "EXISTING_RESOURCES"
                    return 1
                fi
            fi
        fi
    fi
    
    # Map resources to deployment variables
    map_existing_resources "$resources_config" "$stack_name"
    
    log_info "Existing resources setup completed successfully" "EXISTING_RESOURCES"
    return 0
}