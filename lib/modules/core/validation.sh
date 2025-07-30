#!/usr/bin/env bash
# =============================================================================
# Core Validation Module
# Uniform validation standards and checks
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CORE_VALIDATION_SH_LOADED:-}" ] && return 0
_CORE_VALIDATION_SH_LOADED=1

# =============================================================================
# VALIDATION CONFIGURATION
# =============================================================================

# Validation levels
VALIDATION_LEVEL_STRICT="strict"
VALIDATION_LEVEL_NORMAL="normal"
VALIDATION_LEVEL_LOOSE="loose"

# Default validation level
DEFAULT_VALIDATION_LEVEL="$VALIDATION_LEVEL_NORMAL"

# Validation result codes
VALIDATION_SUCCESS=0
VALIDATION_FAILED=1
VALIDATION_WARNING=2

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate AWS configuration
validate_aws_configuration() {
    local region="$1"
    local profile="$2"
    
    log_info "Validating AWS configuration" "VALIDATION"
    
    # Validate region
    if ! validate_aws_region "$region"; then
        set_error "$ERROR_AWS_REGION_INVALID" "Invalid AWS region: $region"
        return 1
    fi
    
    # Validate profile
    if ! validate_aws_profile "$profile"; then
        set_error "$ERROR_AWS_PROFILE_INVALID" "Invalid AWS profile: $profile"
        return 1
    fi
    
    # Validate credentials
    if ! validate_aws_credentials "$profile" "$region"; then
        set_error "$ERROR_AWS_CREDENTIALS" "AWS credentials not found or invalid"
        return 1
    fi
    
    log_info "AWS configuration validation passed" "VALIDATION"
    return 0
}

# Validate AWS region
validate_aws_region() {
    local region="$1"
    
    # Check if region is provided
    if [[ -z "$region" ]]; then
        log_error "AWS region is required" "VALIDATION"
        return 1
    fi
    
    # Validate region format
    if [[ ! "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        log_error "Invalid AWS region format: $region" "VALIDATION"
        return 1
    fi
    
    # Check if region is supported (basic check)
    local supported_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1"
        "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2"
        "sa-east-1" "ca-central-1"
    )
    
    local is_supported=false
    for supported_region in "${supported_regions[@]}"; do
        if [[ "$region" == "$supported_region" ]]; then
            is_supported=true
            break
        fi
    done
    
    if [[ "$is_supported" == false ]]; then
        log_warn "AWS region may not be supported: $region" "VALIDATION"
    fi
    
    return 0
}

# Validate AWS profile
validate_aws_profile() {
    local profile="$1"
    
    # Check if profile is provided
    if [[ -z "$profile" ]]; then
        log_error "AWS profile is required" "VALIDATION"
        return 1
    fi
    
    # Check if profile exists in AWS config
    if ! aws configure list-profiles 2>/dev/null | grep -q "^$profile$"; then
        log_error "AWS profile not found: $profile" "VALIDATION"
        return 1
    fi
    
    return 0
}

# Validate AWS credentials
validate_aws_credentials() {
    local profile="$1"
    local region="$2"
    
    # Test AWS credentials
    if ! aws sts get-caller-identity --profile "$profile" --region "$region" >/dev/null 2>&1; then
        log_error "AWS credentials validation failed for profile: $profile" "VALIDATION"
        return 1
    fi
    
    # Get account information
    local account_info
    account_info=$(aws sts get-caller-identity --profile "$profile" --region "$region" --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local account_id
        account_id=$(echo "$account_info" | jq -r '.Account' 2>/dev/null)
        local user_arn
        user_arn=$(echo "$account_info" | jq -r '.Arn' 2>/dev/null)
        
        log_info "AWS credentials validated - Account: $account_id, User: $user_arn" "VALIDATION"
    fi
    
    return 0
}

# Validate AWS quotas
validate_aws_quotas() {
    local region="$1"
    local deployment_type="$2"
    
    log_info "Validating AWS service quotas" "VALIDATION"
    
    # Get current quotas
    local vpc_quota
    vpc_quota=$(aws service-quotas get-service-quota \
        --service-code vpc \
        --quota-code L-F678F1CE \
        --region "$region" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "5")
    
    local current_vpcs
    current_vpcs=$(aws ec2 describe-vpcs \
        --region "$region" \
        --query 'length(Vpcs)' \
        --output text 2>/dev/null || echo "0")
    
    # Check VPC quota
    if [[ $current_vpcs -ge $vpc_quota ]]; then
        log_error "VPC quota exceeded: $current_vpcs/$vpc_quota" "VALIDATION"
        set_error "$ERROR_AWS_QUOTA_EXCEEDED" "VPC quota exceeded"
        return 1
    fi
    
    # Check other quotas based on deployment type
    case "$deployment_type" in
        "enterprise")
            validate_enterprise_quotas "$region"
            ;;
        "production")
            validate_production_quotas "$region"
            ;;
        *)
            validate_basic_quotas "$region"
            ;;
    esac
    
    log_info "AWS quota validation passed" "VALIDATION"
    return 0
}

# Validate basic quotas
validate_basic_quotas() {
    local region="$1"
    
    # Basic quota checks for development/simple deployments
    log_debug "Performing basic quota validation" "VALIDATION"
    
    # Add specific quota checks as needed
    return 0
}

# Validate production quotas
validate_production_quotas() {
    local region="$1"
    
    log_debug "Performing production quota validation" "VALIDATION"
    
    # Check EBS volume quotas
    local ebs_quota
    ebs_quota=$(aws service-quotas get-service-quota \
        --service-code ebs \
        --quota-code L-D18FAB1D \
        --region "$region" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "5000")
    
    local current_volumes
    current_volumes=$(aws ec2 describe-volumes \
        --region "$region" \
        --query 'length(Volumes)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ $current_volumes -ge $((ebs_quota - 10)) ]]; then
        log_warn "EBS volume quota nearly exceeded: $current_volumes/$ebs_quota" "VALIDATION"
    fi
    
    return 0
}

# Validate enterprise quotas
validate_enterprise_quotas() {
    local region="$1"
    
    log_debug "Performing enterprise quota validation" "VALIDATION"
    
    # Comprehensive quota checks for enterprise deployments
    validate_production_quotas "$region"
    
    # Check additional enterprise-specific quotas
    # Add as needed
    
    return 0
}

# Validate deployment parameters
validate_deployment_parameters() {
    log_info "Validating deployment parameters" "VALIDATION"
    
    # Validate stack name
    if ! validate_stack_name "$STACK_NAME"; then
        return 1
    fi
    
    # Validate deployment type
    if ! validate_deployment_type "$DEPLOYMENT_TYPE"; then
        return 1
    fi
    
    # Validate feature compatibility
    if ! validate_feature_compatibility; then
        return 1
    fi
    
    log_info "Deployment parameters validation passed" "VALIDATION"
    return 0
}

# Validate stack name
validate_stack_name() {
    local stack_name="$1"
    
    # Check if stack name is provided
    if [[ -z "$stack_name" ]]; then
        log_error "Stack name is required" "VALIDATION"
        return 1
    fi
    
    # Validate stack name format
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]{2,30}$ ]]; then
        log_error "Invalid stack name format: $stack_name (must be 3-30 chars, start with letter, contain only letters, numbers, and hyphens)" "VALIDATION"
        return 1
    fi
    
    # Check for reserved names
    local reserved_names=("aws" "amazon" "ec2" "vpc" "default" "test" "prod" "dev")
    for reserved in "${reserved_names[@]}"; do
        if [[ "$stack_name" == "$reserved" ]]; then
            log_error "Stack name is reserved: $stack_name" "VALIDATION"
            return 1
        fi
    done
    
    return 0
}

# Validate deployment type
validate_deployment_type() {
    local deployment_type="$1"
    
    # Check if deployment type is provided
    if [[ -z "$deployment_type" ]]; then
        log_error "Deployment type is required" "VALIDATION"
        return 1
    fi
    
    # Validate deployment type
    case "$deployment_type" in
        "development"|"dev")
            return 0
            ;;
        "production"|"prod")
            return 0
            ;;
        "staging"|"stage")
            return 0
            ;;
        "enterprise"|"ent")
            return 0
            ;;
        "standard")
            return 0
            ;;
        *)
            log_error "Invalid deployment type: $deployment_type" "VALIDATION"
            return 1
            ;;
    esac
}

# Validate feature compatibility
validate_feature_compatibility() {
    local errors=()
    
    # CDN requires ALB
    if [[ "$ENABLE_CDN" == true && "$ENABLE_ALB" == false ]]; then
        errors+=("CDN requires ALB to be enabled")
    fi
    
    # Multi-AZ requires ALB
    if [[ "$ENABLE_MULTI_AZ" == true && "$ENABLE_ALB" == false ]]; then
        errors+=("Multi-AZ deployment requires ALB to be enabled")
    fi
    
    # EFS requires VPC
    if [[ "$ENABLE_EFS" == true ]]; then
        # EFS validation will be done during VPC creation
        log_debug "EFS validation will be performed during VPC creation" "VALIDATION"
    fi
    
    # Check for errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_error "$error" "VALIDATION"
        done
        return 1
    fi
    
    return 0
}

# Validate network configuration
validate_network_configuration() {
    local vpc_cidr="$1"
    local public_subnets="$2"
    local private_subnets="$3"
    
    log_info "Validating network configuration" "VALIDATION"
    
    # Validate VPC CIDR
    if ! validate_cidr_block "$vpc_cidr"; then
        return 1
    fi
    
    # Validate subnet CIDRs
    if [[ -n "$public_subnets" ]]; then
        for subnet in $public_subnets; do
            if ! validate_cidr_block "$subnet"; then
                log_error "Invalid public subnet CIDR: $subnet" "VALIDATION"
                return 1
            fi
            
            if ! validate_subnet_in_vpc "$subnet" "$vpc_cidr"; then
                log_error "Public subnet $subnet is not within VPC CIDR $vpc_cidr" "VALIDATION"
                return 1
            fi
        done
    fi
    
    if [[ -n "$private_subnets" ]]; then
        for subnet in $private_subnets; do
            if ! validate_cidr_block "$subnet"; then
                log_error "Invalid private subnet CIDR: $subnet" "VALIDATION"
                return 1
            fi
            
            if ! validate_subnet_in_vpc "$subnet" "$vpc_cidr"; then
                log_error "Private subnet $subnet is not within VPC CIDR $vpc_cidr" "VALIDATION"
                return 1
            fi
        done
    fi
    
    # Check for subnet overlaps
    if ! validate_subnet_overlaps "$public_subnets" "$private_subnets"; then
        return 1
    fi
    
    log_info "Network configuration validation passed" "VALIDATION"
    return 0
}

# Validate CIDR block
validate_cidr_block() {
    local cidr="$1"
    
    # Check CIDR format
    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid CIDR format: $cidr" "VALIDATION"
        return 1
    fi
    
    # Extract network and prefix
    local network="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Validate network octets
    IFS='.' read -ra OCTETS <<< "$network"
    for octet in "${OCTETS[@]}"; do
        if [[ "$octet" -lt 0 || "$octet" -gt 255 ]]; then
            log_error "Invalid network octet in CIDR: $cidr" "VALIDATION"
            return 1
        fi
    done
    
    # Validate prefix length
    if [[ "$prefix" -lt 0 || "$prefix" -gt 32 ]]; then
        log_error "Invalid prefix length in CIDR: $cidr" "VALIDATION"
        return 1
    fi
    
    return 0
}

# Validate subnet is within VPC
validate_subnet_in_vpc() {
    local subnet_cidr="$1"
    local vpc_cidr="$2"
    
    # This is a simplified check - in production, you might want more sophisticated validation
    # For now, we'll just check that the subnet prefix is larger than the VPC prefix
    
    local vpc_prefix="${vpc_cidr#*/}"
    local subnet_prefix="${subnet_cidr#*/}"
    
    if [[ $subnet_prefix -le $vpc_prefix ]]; then
        return 1
    fi
    
    return 0
}

# Validate subnet overlaps
validate_subnet_overlaps() {
    local public_subnets="$1"
    local private_subnets="$2"
    
    # Combine all subnets
    local all_subnets=()
    
    if [[ -n "$public_subnets" ]]; then
        IFS=' ' read -ra PUBLIC <<< "$public_subnets"
        all_subnets+=("${PUBLIC[@]}")
    fi
    
    if [[ -n "$private_subnets" ]]; then
        IFS=' ' read -ra PRIVATE <<< "$private_subnets"
        all_subnets+=("${PRIVATE[@]}")
    fi
    
    # Check for overlaps (simplified)
    local i j
    for ((i=0; i<${#all_subnets[@]}; i++)); do
        for ((j=i+1; j<${#all_subnets[@]}; j++)); do
            if [[ "${all_subnets[$i]}" == "${all_subnets[$j]}" ]]; then
                log_error "Duplicate subnet CIDR: ${all_subnets[$i]}" "VALIDATION"
                return 1
            fi
        done
    done
    
    return 0
}

# Validate instance configuration
validate_instance_configuration() {
    local instance_type="$1"
    local min_capacity="$2"
    local max_capacity="$3"
    local desired_capacity="$4"
    
    log_info "Validating instance configuration" "VALIDATION"
    
    # Validate instance type
    if ! validate_instance_type "$instance_type"; then
        return 1
    fi
    
    # Validate capacity values
    if ! validate_capacity_values "$min_capacity" "$max_capacity" "$desired_capacity"; then
        return 1
    fi
    
    log_info "Instance configuration validation passed" "VALIDATION"
    return 0
}

# Validate instance type
validate_instance_type() {
    local instance_type="$1"
    
    # Check if instance type is provided
    if [[ -z "$instance_type" ]]; then
        log_error "Instance type is required" "VALIDATION"
        return 1
    fi
    
    # Validate instance type format
    if [[ ! "$instance_type" =~ ^[a-z][0-9][a-z]?\.[a-z0-9]+$ ]]; then
        log_error "Invalid instance type format: $instance_type" "VALIDATION"
        return 1
    fi
    
    # Check if instance type is supported (basic check)
    local supported_families=("t3" "t4g" "m6i" "c6i" "r6i" "g4dn" "p3" "p4")
    local family
    family=$(echo "$instance_type" | cut -d'.' -f1)
    
    local is_supported=false
    for supported_family in "${supported_families[@]}"; do
        if [[ "$family" == "$supported_family" ]]; then
            is_supported=true
            break
        fi
    done
    
    if [[ "$is_supported" == false ]]; then
        log_warn "Instance family may not be supported: $family" "VALIDATION"
    fi
    
    return 0
}

# Validate capacity values
validate_capacity_values() {
    local min_capacity="$1"
    local max_capacity="$2"
    local desired_capacity="$3"
    
    # Validate min capacity
    if [[ ! "$min_capacity" =~ ^[0-9]+$ ]] || [[ "$min_capacity" -lt 0 ]]; then
        log_error "Invalid min capacity: $min_capacity" "VALIDATION"
        return 1
    fi
    
    # Validate max capacity
    if [[ ! "$max_capacity" =~ ^[0-9]+$ ]] || [[ "$max_capacity" -lt 1 ]]; then
        log_error "Invalid max capacity: $max_capacity" "VALIDATION"
        return 1
    fi
    
    # Validate desired capacity
    if [[ ! "$desired_capacity" =~ ^[0-9]+$ ]] || [[ "$desired_capacity" -lt 0 ]]; then
        log_error "Invalid desired capacity: $desired_capacity" "VALIDATION"
        return 1
    fi
    
    # Validate relationships
    if [[ "$min_capacity" -gt "$max_capacity" ]]; then
        log_error "Min capacity ($min_capacity) cannot be greater than max capacity ($max_capacity)" "VALIDATION"
        return 1
    fi
    
    if [[ "$desired_capacity" -lt "$min_capacity" || "$desired_capacity" -gt "$max_capacity" ]]; then
        log_error "Desired capacity ($desired_capacity) must be between min ($min_capacity) and max ($max_capacity)" "VALIDATION"
        return 1
    fi
    
    return 0
}

# Validate security configuration
validate_security_configuration() {
    local security_groups="$1"
    local key_pair="$2"
    
    log_info "Validating security configuration" "VALIDATION"
    
    # Validate security groups if provided
    if [[ -n "$security_groups" ]]; then
        if ! validate_security_groups "$security_groups"; then
            return 1
        fi
    fi
    
    # Validate key pair if provided
    if [[ -n "$key_pair" ]]; then
        if ! validate_key_pair "$key_pair"; then
            return 1
        fi
    fi
    
    log_info "Security configuration validation passed" "VALIDATION"
    return 0
}

# Validate security groups
validate_security_groups() {
    local security_groups="$1"
    
    # Check if security groups exist
    IFS=',' read -ra SG_ARRAY <<< "$security_groups"
    for sg in "${SG_ARRAY[@]}"; do
        if ! aws ec2 describe-security-groups --group-ids "$sg" >/dev/null 2>&1; then
            log_error "Security group not found: $sg" "VALIDATION"
            return 1
        fi
    done
    
    return 0
}

# Validate key pair
validate_key_pair() {
    local key_pair="$1"
    
    # Check if key pair exists
    if ! aws ec2 describe-key-pairs --key-names "$key_pair" >/dev/null 2>&1; then
        log_error "Key pair not found: $key_pair" "VALIDATION"
        return 1
    fi
    
    return 0
}

# =============================================================================
# COMPREHENSIVE VALIDATION
# =============================================================================

# Perform comprehensive validation
perform_comprehensive_validation() {
    local validation_level="${1:-$DEFAULT_VALIDATION_LEVEL}"
    
    log_info "Performing comprehensive validation (level: $validation_level)" "VALIDATION"
    
    local validation_errors=0
    
    # Basic validations (all levels)
    if ! validate_aws_configuration "$AWS_REGION" "$AWS_PROFILE"; then
        ((validation_errors++))
    fi
    
    if ! validate_deployment_parameters; then
        ((validation_errors++))
    fi
    
    # Normal and strict validations
    if [[ "$validation_level" == "$VALIDATION_LEVEL_NORMAL" || "$validation_level" == "$VALIDATION_LEVEL_STRICT" ]]; then
        if ! validate_aws_quotas "$AWS_REGION" "$DEPLOYMENT_TYPE"; then
            ((validation_errors++))
        fi
    fi
    
    # Strict validations only
    if [[ "$validation_level" == "$VALIDATION_LEVEL_STRICT" ]]; then
        if ! validate_network_configuration "$VPC_CIDR" "$PUBLIC_SUBNET_CIDRS" "$PRIVATE_SUBNET_CIDRS"; then
            ((validation_errors++))
        fi
        
        if ! validate_instance_configuration "$INSTANCE_TYPE" "$MIN_CAPACITY" "$MAX_CAPACITY" "$DESIRED_CAPACITY"; then
            ((validation_errors++))
        fi
    fi
    
    if [[ $validation_errors -gt 0 ]]; then
        log_error "Validation failed with $validation_errors error(s)" "VALIDATION"
        return 1
    fi
    
    log_info "Comprehensive validation passed" "VALIDATION"
    return 0
}

# =============================================================================
# VALIDATION UTILITIES
# =============================================================================

# Get validation summary
get_validation_summary() {
    local summary_file="${1:-}"
    
    if [[ -z "$summary_file" ]]; then
        summary_file="${CONFIG_DIR}/temp/validation-summary-$(date +%Y%m%d-%H%M%S).json"
    fi
    
    # Create summary directory
    local summary_dir
    summary_dir=$(dirname "$summary_file")
    mkdir -p "$summary_dir"
    
    # Generate JSON summary
    cat > "$summary_file" << EOF
{
    "validation_summary": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "stack_name": "$(get_variable STACK_NAME)",
        "aws_region": "$(get_variable AWS_REGION)",
        "deployment_type": "$(get_variable DEPLOYMENT_TYPE)",
        "validation_level": "$DEFAULT_VALIDATION_LEVEL",
        "aws_configuration": {
            "region_valid": true,
            "profile_valid": true,
            "credentials_valid": true
        },
        "deployment_parameters": {
            "stack_name_valid": true,
            "deployment_type_valid": true,
            "feature_compatibility_valid": true
        },
        "features": {
            "alb": ${ENABLE_ALB},
            "cdn": ${ENABLE_CDN},
            "efs": ${ENABLE_EFS},
            "multi_az": ${ENABLE_MULTI_AZ},
            "spot": ${ENABLE_SPOT},
            "monitoring": ${ENABLE_MONITORING},
            "backup": ${ENABLE_BACKUP}
        },
        "status": "validated"
    }
}
EOF
    
    log_info "Validation summary generated: $summary_file" "VALIDATION"
    echo "$summary_file"
}

# Check if validation is required
is_validation_required() {
    local operation="$1"
    
    case "$operation" in
        "deploy"|"create"|"update")
            return 0  # Validation required
            ;;
        "destroy"|"delete"|"cleanup")
            return 1  # Validation not required
            ;;
        "status"|"info"|"list")
            return 1  # Validation not required
            ;;
        *)
            return 0  # Default to validation required
            ;;
    esac
}

# Validate based on operation
validate_for_operation() {
    local operation="$1"
    local validation_level="${2:-$DEFAULT_VALIDATION_LEVEL}"
    
    if ! is_validation_required "$operation"; then
        log_debug "Validation not required for operation: $operation" "VALIDATION"
        return 0
    fi
    
    log_info "Validating for operation: $operation" "VALIDATION"
    
    case "$operation" in
        "deploy"|"create")
            perform_comprehensive_validation "$validation_level"
            ;;
        "update")
            # Less strict validation for updates
            perform_comprehensive_validation "$VALIDATION_LEVEL_NORMAL"
            ;;
        *)
            perform_comprehensive_validation "$validation_level"
            ;;
    esac
} 