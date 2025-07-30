#!/usr/bin/env bash
# =============================================================================
# ALB Infrastructure Module
# Uniform Application Load Balancer creation and management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_INFRASTRUCTURE_ALB_SH_LOADED:-}" ] && return 0
_INFRASTRUCTURE_ALB_SH_LOADED=1

# =============================================================================
# ALB CONFIGURATION
# =============================================================================

# ALB configuration defaults
ALB_DEFAULT_SCHEME="internet-facing"
ALB_DEFAULT_TYPE="application"
ALB_DEFAULT_IP_ADDRESS_TYPE="ipv4"
ALB_DEFAULT_DELETION_PROTECTION=false

# Target group configuration defaults
TARGET_GROUP_DEFAULT_PROTOCOL="HTTP"
TARGET_GROUP_DEFAULT_PORT=80
TARGET_GROUP_DEFAULT_TARGET_TYPE="instance"
TARGET_GROUP_DEFAULT_HEALTH_CHECK_PROTOCOL="HTTP"
TARGET_GROUP_DEFAULT_HEALTH_CHECK_PORT="traffic-port"
TARGET_GROUP_DEFAULT_HEALTH_CHECK_PATH="/health"
TARGET_GROUP_DEFAULT_HEALTH_CHECK_INTERVAL=30
TARGET_GROUP_DEFAULT_HEALTH_CHECK_TIMEOUT=5
TARGET_GROUP_DEFAULT_HEALTHY_THRESHOLD=2
TARGET_GROUP_DEFAULT_UNHEALTHY_THRESHOLD=2

# Listener configuration defaults
LISTENER_DEFAULT_PROTOCOL="HTTP"
LISTENER_DEFAULT_PORT=80
LISTENER_DEFAULT_ACTION_TYPE="forward"

# =============================================================================
# ALB CREATION FUNCTIONS
# =============================================================================

# Create ALB with target group and listener
create_alb_with_target_group() {
    local stack_name="$1"
    local vpc_id="$2"
    local subnets="$3"
    local security_groups="${4:-}"
    
    # Check for existing ALB from environment or variable store
    local existing_alb_arn="${EXISTING_ALB_ARN:-}"
    if [[ -z "$existing_alb_arn" ]]; then
        existing_alb_arn=$(get_variable "ALB_LOAD_BALANCER_ARN" "$VARIABLE_SCOPE_STACK")
    fi
    
    if [[ -n "$existing_alb_arn" ]]; then
        log_info "Using existing ALB: $existing_alb_arn" "ALB"
        
        # Validate existing ALB
        if ! validate_existing_alb "$existing_alb_arn"; then
            log_error "Existing ALB validation failed: $existing_alb_arn" "ALB"
            return 1
        fi
        
        # Register existing ALB in resource registry
        register_resource "load_balancers" "$existing_alb_arn" "existing"
        
        # Extract ALB details
        local alb_info
        alb_info=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$existing_alb_arn" \
            --query 'LoadBalancers[0]' \
            --output json \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE")
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to get existing ALB information" "ALB"
            return 1
        fi
        
        local alb_dns_name
        alb_dns_name=$(echo "$alb_info" | jq -r '.DNSName')
        local alb_zone_id
        alb_zone_id=$(echo "$alb_info" | jq -r '.CanonicalHostedZoneId')
        
        # Set variables for downstream use
        set_variable "ALB_ARN" "$existing_alb_arn" "$VARIABLE_SCOPE_STACK"
        set_variable "ALB_DNS_NAME" "$alb_dns_name" "$VARIABLE_SCOPE_STACK"
        set_variable "ALB_ZONE_ID" "$alb_zone_id" "$VARIABLE_SCOPE_STACK"
        
        log_info "Existing ALB configured successfully: $existing_alb_arn" "ALB"
        
        # Check for existing target group from environment or variable store
        local existing_target_group_arn="${EXISTING_TARGET_GROUP_ARN:-}"
        if [[ -z "$existing_target_group_arn" ]]; then
            existing_target_group_arn=$(get_variable "TARGET_GROUP_ARN" "$VARIABLE_SCOPE_STACK")
        fi
        
        if [[ -n "$existing_target_group_arn" ]]; then
            log_info "Using existing target group: $existing_target_group_arn" "ALB"
            register_resource "target_groups" "$existing_target_group_arn" "existing"
        else
            # Create new target group for existing ALB
            local target_group_arn
            target_group_arn=$(create_target_group "$stack_name" "$vpc_id")
            if [[ $? -ne 0 ]]; then
                log_error "Failed to create target group" "ALB"
                return 1
            fi
            
            # Store target group ARN
            set_variable "TARGET_GROUP_ARN" "$target_group_arn" "$VARIABLE_SCOPE_STACK"
            register_resource "target_groups" "$target_group_arn" "created"
        fi
        
        # Check for existing listener
        local existing_listener_arn
        existing_listener_arn=$(get_variable "LISTENER_ARN" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$existing_listener_arn" ]]; then
            log_info "Using existing listener: $existing_listener_arn" "ALB"
            register_resource "listeners" "$existing_listener_arn" "existing"
        else
            # Get target group ARN for listener creation
            local target_group_arn_for_listener
            target_group_arn_for_listener=$(get_variable "TARGET_GROUP_ARN" "$VARIABLE_SCOPE_STACK")
            
            # Create new listener for existing ALB
            local listener_arn
            listener_arn=$(create_listener "$existing_alb_arn" "$target_group_arn_for_listener")
            if [[ $? -ne 0 ]]; then
                log_error "Failed to create listener" "ALB"
                return 1
            fi
            
            # Store listener ARN
            set_variable "LISTENER_ARN" "$listener_arn" "$VARIABLE_SCOPE_STACK"
            register_resource "listeners" "$listener_arn" "created"
        fi
        
        return 0
    fi
    
    # Continue with normal ALB creation if no existing ALB
    log_info "Creating ALB with target group for stack: $stack_name" "ALB"
    
    # Generate ALB name
    local alb_name
    alb_name=$(generate_resource_name "alb" "$stack_name")
    
    # Create ALB
    local alb_arn
    alb_arn=$(create_alb "$alb_name" "$vpc_id" "$subnets" "$security_groups")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create ALB: $alb_name" "ALB"
        return 1
    fi
    
    # Store ALB ARN
    set_variable "ALB_ARN" "$alb_arn" "$VARIABLE_SCOPE_STACK"
    register_resource "load_balancers" "$alb_arn" "created"
    
    # Get ALB DNS name
    local alb_dns_name
    alb_dns_name=$(get_alb_dns_name "$alb_arn")
    if [[ $? -eq 0 ]]; then
        set_variable "ALB_DNS_NAME" "$alb_dns_name" "$VARIABLE_SCOPE_STACK"
    fi
    
    # Create target group
    local target_group_arn
    target_group_arn=$(create_target_group "$stack_name" "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create target group" "ALB"
        # Rollback ALB creation
        delete_alb "$alb_arn"
        return 1
    fi
    
    # Store target group ARN
    set_variable "TARGET_GROUP_ARN" "$target_group_arn" "$VARIABLE_SCOPE_STACK"
    register_resource "target_groups" "$target_group_arn" "created"
    
    # Create listener
    local listener_arn
    listener_arn=$(create_listener "$alb_arn" "$target_group_arn")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create listener" "ALB"
        # Rollback target group creation
        delete_target_group "$target_group_arn"
        delete_alb "$alb_arn"
        return 1
    fi
    
    # Store listener ARN
    set_variable "LISTENER_ARN" "$listener_arn" "$VARIABLE_SCOPE_STACK"
    register_resource "listeners" "$listener_arn" "created"
    
    log_info "ALB creation completed successfully: $alb_arn" "ALB"
    return 0
}

# Create ALB
create_alb() {
    local alb_name="$1"
    local vpc_id="$2"
    local subnets="$3"
    local security_groups="$4"
    
    log_info "Creating ALB: $alb_name" "ALB"
    
    # Validate ALB name
    if ! validate_resource_name "$alb_name" "alb"; then
        return 1
    fi
    
    # Validate VPC ID
    if [[ -z "$vpc_id" ]]; then
        log_error "VPC ID is required for ALB creation" "ALB"
        return 1
    fi
    
    # Validate subnets
    if [[ -z "$subnets" ]]; then
        log_error "Subnets are required for ALB creation" "ALB"
        return 1
    fi
    
    # Parse subnets
    local subnet_array=()
    IFS=' ' read -ra SUBNET_ARRAY <<< "$subnets"
    subnet_array=("${SUBNET_ARRAY[@]}")
    
    # Build ALB creation command
    local alb_cmd="aws elbv2 create-load-balancer"
    alb_cmd="$alb_cmd --name $alb_name"
    alb_cmd="$alb_cmd --subnets ${subnet_array[*]}"
    alb_cmd="$alb_cmd --scheme $ALB_DEFAULT_SCHEME"
    alb_cmd="$alb_cmd --type $ALB_DEFAULT_TYPE"
    alb_cmd="$alb_cmd --ip-address-type $ALB_DEFAULT_IP_ADDRESS_TYPE"
    
    # Add security groups if provided
    if [[ -n "$security_groups" ]]; then
        alb_cmd="$alb_cmd --security-groups $security_groups"
    fi
    
    # Add tags
    alb_cmd="$alb_cmd --tags Key=Name,Value=$alb_name"
    alb_cmd="$alb_cmd --tags Key=Stack,Value=$STACK_NAME"
    alb_cmd="$alb_cmd --tags Key=Environment,Value=$ENVIRONMENT"
    
    # Add output format
    alb_cmd="$alb_cmd --output json"
    alb_cmd="$alb_cmd --query 'LoadBalancers[0].LoadBalancerArn'"
    alb_cmd="$alb_cmd --region $AWS_REGION"
    alb_cmd="$alb_cmd --profile $AWS_PROFILE"
    
    # Create ALB
    local alb_output
    alb_output=$(eval "$alb_cmd" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create ALB: $alb_output" "ALB"
        return 1
    fi
    
    local alb_arn
    alb_arn=$(echo "$alb_output" | tr -d '"')
    
    # Wait for ALB to be available
    log_info "Waiting for ALB to be available: $alb_arn" "ALB"
    aws elbv2 wait load-balancer-available \
        --load-balancer-arns "$alb_arn" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    if [[ $? -ne 0 ]]; then
        log_error "ALB failed to become available: $alb_arn" "ALB"
        return 1
    fi
    
    log_info "ALB created successfully: $alb_arn" "ALB"
    echo "$alb_arn"
    return 0
}

# Get ALB DNS name
get_alb_dns_name() {
    local alb_arn="$1"
    
    log_info "Getting ALB DNS name: $alb_arn" "ALB"
    
    local dns_name
    dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get ALB DNS name: $dns_name" "ALB"
        return 1
    fi
    
    log_info "ALB DNS name: $dns_name" "ALB"
    echo "$dns_name"
    return 0
}

# =============================================================================
# TARGET GROUP FUNCTIONS
# =============================================================================

# Create target group
create_target_group() {
    local stack_name="$1"
    local vpc_id="$2"
    
    log_info "Creating target group for stack: $stack_name" "ALB"
    
    # Generate target group name
    local target_group_name
    target_group_name=$(generate_resource_name "target-group" "$stack_name")
    
    # Validate target group name
    if ! validate_resource_name "$target_group_name" "target-group"; then
        return 1
    fi
    
    # Create target group
    local target_group_output
    target_group_output=$(aws elbv2 create-target-group \
        --name "$target_group_name" \
        --protocol "$TARGET_GROUP_DEFAULT_PROTOCOL" \
        --port "$TARGET_GROUP_DEFAULT_PORT" \
        --vpc-id "$vpc_id" \
        --target-type "$TARGET_GROUP_DEFAULT_TARGET_TYPE" \
        --health-check-protocol "$TARGET_GROUP_DEFAULT_HEALTH_CHECK_PROTOCOL" \
        --health-check-port "$TARGET_GROUP_DEFAULT_HEALTH_CHECK_PORT" \
        --health-check-path "$TARGET_GROUP_DEFAULT_HEALTH_CHECK_PATH" \
        --health-check-interval-seconds "$TARGET_GROUP_DEFAULT_HEALTH_CHECK_INTERVAL" \
        --health-check-timeout-seconds "$TARGET_GROUP_DEFAULT_HEALTH_CHECK_TIMEOUT" \
        --healthy-threshold-count "$TARGET_GROUP_DEFAULT_HEALTHY_THRESHOLD" \
        --unhealthy-threshold-count "$TARGET_GROUP_DEFAULT_UNHEALTHY_THRESHOLD" \
        --tags "Key=Name,Value=$target_group_name" \
        --tags "Key=Stack,Value=$stack_name" \
        --tags "Key=Environment,Value=$ENVIRONMENT" \
        --output json \
        --query 'TargetGroups[0].TargetGroupArn' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create target group: $target_group_output" "ALB"
        return 1
    fi
    
    local target_group_arn
    target_group_arn=$(echo "$target_group_output" | tr -d '"')
    
    log_info "Target group created successfully: $target_group_arn" "ALB"
    echo "$target_group_arn"
    return 0
}

# Register targets with target group
register_targets() {
    local target_group_arn="$1"
    local instance_ids="$2"
    
    log_info "Registering targets with target group: $target_group_arn" "ALB"
    
    # Validate target group ARN
    if [[ -z "$target_group_arn" ]]; then
        log_error "Target group ARN is required" "ALB"
        return 1
    fi
    
    # Validate instance IDs
    if [[ -z "$instance_ids" ]]; then
        log_error "Instance IDs are required" "ALB"
        return 1
    fi
    
    # Parse instance IDs
    local instance_array=()
    IFS=' ' read -ra INSTANCE_ARRAY <<< "$instance_ids"
    instance_array=("${INSTANCE_ARRAY[@]}")
    
    # Build targets parameter
    local targets_param=""
    for instance_id in "${instance_array[@]}"; do
        if [[ -n "$targets_param" ]]; then
            targets_param="$targets_param Id=$instance_id"
        else
            targets_param="Id=$instance_id"
        fi
    done
    
    # Register targets
    local register_output
    register_output=$(aws elbv2 register-targets \
        --target-group-arn "$target_group_arn" \
        --targets $targets_param \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to register targets: $register_output" "ALB"
        return 1
    fi
    
    log_info "Targets registered successfully: ${instance_array[*]}" "ALB"
    return 0
}

# Deregister targets from target group
deregister_targets() {
    local target_group_arn="$1"
    local instance_ids="$2"
    
    log_info "Deregistering targets from target group: $target_group_arn" "ALB"
    
    # Validate target group ARN
    if [[ -z "$target_group_arn" ]]; then
        log_error "Target group ARN is required" "ALB"
        return 1
    fi
    
    # Validate instance IDs
    if [[ -z "$instance_ids" ]]; then
        log_error "Instance IDs are required" "ALB"
        return 1
    fi
    
    # Parse instance IDs
    local instance_array=()
    IFS=' ' read -ra INSTANCE_ARRAY <<< "$instance_ids"
    instance_array=("${INSTANCE_ARRAY[@]}")
    
    # Build targets parameter
    local targets_param=""
    for instance_id in "${instance_array[@]}"; do
        if [[ -n "$targets_param" ]]; then
            targets_param="$targets_param Id=$instance_id"
        else
            targets_param="Id=$instance_id"
        fi
    done
    
    # Deregister targets
    local deregister_output
    deregister_output=$(aws elbv2 deregister-targets \
        --target-group-arn "$target_group_arn" \
        --targets $targets_param \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to deregister targets: $deregister_output" "ALB"
        return 1
    fi
    
    log_info "Targets deregistered successfully: ${instance_array[*]}" "ALB"
    return 0
}

# =============================================================================
# LISTENER FUNCTIONS
# =============================================================================

# Create listener
create_listener() {
    local alb_arn="$1"
    local target_group_arn="$2"
    
    log_info "Creating listener for ALB: $alb_arn" "ALB"
    
    # Validate ALB ARN
    if [[ -z "$alb_arn" ]]; then
        log_error "ALB ARN is required" "ALB"
        return 1
    fi
    
    # Validate target group ARN
    if [[ -z "$target_group_arn" ]]; then
        log_error "Target group ARN is required" "ALB"
        return 1
    fi
    
    # Create listener
    local listener_output
    listener_output=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol "$LISTENER_DEFAULT_PROTOCOL" \
        --port "$LISTENER_DEFAULT_PORT" \
        --default-actions "Type=$LISTENER_DEFAULT_ACTION_TYPE,TargetGroupArn=$target_group_arn" \
        --output json \
        --query 'Listeners[0].ListenerArn' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create listener: $listener_output" "ALB"
        return 1
    fi
    
    local listener_arn
    listener_arn=$(echo "$listener_output" | tr -d '"')
    
    log_info "Listener created successfully: $listener_arn" "ALB"
    echo "$listener_arn"
    return 0
}

# Create HTTPS listener with certificate
create_https_listener() {
    local alb_arn="$1"
    local target_group_arn="$2"
    local certificate_arn="$3"
    
    log_info "Creating HTTPS listener for ALB: $alb_arn" "ALB"
    
    # Validate ALB ARN
    if [[ -z "$alb_arn" ]]; then
        log_error "ALB ARN is required" "ALB"
        return 1
    fi
    
    # Validate target group ARN
    if [[ -z "$target_group_arn" ]]; then
        log_error "Target group ARN is required" "ALB"
        return 1
    fi
    
    # Validate certificate ARN
    if [[ -z "$certificate_arn" ]]; then
        log_error "Certificate ARN is required for HTTPS listener" "ALB"
        return 1
    fi
    
    # Create HTTPS listener
    local listener_output
    listener_output=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol "HTTPS" \
        --port 443 \
        --certificates "CertificateArn=$certificate_arn" \
        --default-actions "Type=forward,TargetGroupArn=$target_group_arn" \
        --output json \
        --query 'Listeners[0].ListenerArn' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create HTTPS listener: $listener_output" "ALB"
        return 1
    fi
    
    local listener_arn
    listener_arn=$(echo "$listener_output" | tr -d '"')
    
    log_info "HTTPS listener created successfully: $listener_arn" "ALB"
    echo "$listener_arn"
    return 0
}

# =============================================================================
# SECURITY GROUP FUNCTIONS
# =============================================================================

# Create ALB security group
create_alb_security_group() {
    local stack_name="$1"
    local vpc_id="$2"
    
    log_info "Creating ALB security group for stack: $stack_name" "ALB"
    
    # Generate security group name
    local security_group_name
    security_group_name=$(generate_resource_name "security-group" "$stack_name" "alb")
    
    # Validate security group name
    if ! validate_resource_name "$security_group_name" "security-group"; then
        return 1
    fi
    
    # Create security group
    local security_group_output
    security_group_output=$(aws ec2 create-security-group \
        --group-name "$security_group_name" \
        --description "Security group for ALB $stack_name" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$security_group_name}]" \
        --output json \
        --query 'GroupId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create ALB security group: $security_group_output" "ALB"
        return 1
    fi
    
    local security_group_id
    security_group_id=$(echo "$security_group_output" | tr -d '"')
    
    # Add inbound rules
    if ! add_alb_inbound_rules "$security_group_id"; then
        log_error "Failed to add ALB inbound rules" "ALB"
        # Cleanup security group
        delete_security_group "$security_group_id"
        return 1
    fi
    
    log_info "ALB security group created successfully: $security_group_id" "ALB"
    echo "$security_group_id"
    return 0
}

# Add ALB inbound rules
add_alb_inbound_rules() {
    local security_group_id="$1"
    
    log_info "Adding ALB inbound rules to security group: $security_group_id" "ALB"
    
    # Add HTTP rule
    local http_rule_output
    http_rule_output=$(aws ec2 authorize-security-group-ingress \
        --group-id "$security_group_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to add HTTP rule: $http_rule_output" "ALB"
        return 1
    fi
    
    # Add HTTPS rule
    local https_rule_output
    https_rule_output=$(aws ec2 authorize-security-group-ingress \
        --group-id "$security_group_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to add HTTPS rule: $https_rule_output" "ALB"
        return 1
    fi
    
    log_info "ALB inbound rules added successfully" "ALB"
    return 0
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Delete ALB
delete_alb() {
    local alb_arn="$1"
    
    log_info "Deleting ALB: $alb_arn" "ALB"
    
    if ! aws elbv2 delete-load-balancer \
        --load-balancer-arn "$alb_arn" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to delete ALB: $alb_arn" "ALB"
        return 1
    fi
    
    log_info "ALB deleted successfully: $alb_arn" "ALB"
    return 0
}

# Delete target group
delete_target_group() {
    local target_group_arn="$1"
    
    log_info "Deleting target group: $target_group_arn" "ALB"
    
    if ! aws elbv2 delete-target-group \
        --target-group-arn "$target_group_arn" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to delete target group: $target_group_arn" "ALB"
        return 1
    fi
    
    log_info "Target group deleted successfully: $target_group_arn" "ALB"
    return 0
}

# Delete listener
delete_listener() {
    local listener_arn="$1"
    
    log_info "Deleting listener: $listener_arn" "ALB"
    
    if ! aws elbv2 delete-listener \
        --listener-arn "$listener_arn" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to delete listener: $listener_arn" "ALB"
        return 1
    fi
    
    log_info "Listener deleted successfully: $listener_arn" "ALB"
    return 0
}

# Delete security group
delete_security_group() {
    local security_group_id="$1"
    
    log_info "Deleting security group: $security_group_id" "ALB"
    
    if ! aws ec2 delete-security-group \
        --group-id "$security_group_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to delete security group: $security_group_id" "ALB"
        return 1
    fi
    
    log_info "Security group deleted successfully: $security_group_id" "ALB"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get ALB information
get_alb_info() {
    local alb_arn="$1"
    
    log_info "Getting ALB information: $alb_arn" "ALB"
    
    local alb_info
    alb_info=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get ALB information: $alb_info" "ALB"
        return 1
    fi
    
    echo "$alb_info"
    return 0
}

# Get target group information
get_target_group_info() {
    local target_group_arn="$1"
    
    log_info "Getting target group information: $target_group_arn" "ALB"
    
    local target_group_info
    target_group_info=$(aws elbv2 describe-target-groups \
        --target-group-arns "$target_group_arn" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get target group information: $target_group_info" "ALB"
        return 1
    fi
    
    echo "$target_group_info"
    return 0
}

# Get target health
get_target_health() {
    local target_group_arn="$1"
    
    log_info "Getting target health for target group: $target_group_arn" "ALB"
    
    local target_health
    target_health=$(aws elbv2 describe-target-health \
        --target-group-arn "$target_group_arn" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get target health: $target_health" "ALB"
        return 1
    fi
    
    echo "$target_health"
    return 0
}

# Wait for targets to be healthy
wait_for_targets_healthy() {
    local target_group_arn="$1"
    local timeout="${2:-300}"
    
    log_info "Waiting for targets to be healthy: $target_group_arn" "ALB"
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for targets to be healthy" "ALB"
            return 1
        fi
        
        local target_health
        target_health=$(get_target_health "$target_group_arn")
        if [[ $? -ne 0 ]]; then
            log_error "Failed to get target health" "ALB"
            return 1
        fi
        
        # Check if all targets are healthy
        local unhealthy_count
        unhealthy_count=$(echo "$target_health" | jq -r '.TargetHealthDescriptions[] | select(.TargetHealth.State != "healthy") | .Target.Id' | wc -l)
        
        if [[ $unhealthy_count -eq 0 ]]; then
            log_info "All targets are healthy" "ALB"
            return 0
        fi
        
        log_info "Waiting for targets to be healthy... ($unhealthy_count unhealthy)" "ALB"
        sleep 10
    done
}

# =============================================================================
# EXISTING RESOURCE VALIDATION
# =============================================================================

# Validate existing ALB
validate_existing_alb() {
    local alb_arn="$1"
    
    log_info "Validating existing ALB: $alb_arn" "ALB"
    
    if [[ -z "$alb_arn" ]]; then
        log_error "ALB ARN is required for validation" "ALB"
        return 1
    fi
    
    # Check if ALB exists and get its information
    local alb_info
    alb_info=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0]' \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ "$alb_info" == "null" ]] || [[ -z "$alb_info" ]]; then
        log_error "ALB not found or inaccessible: $alb_arn" "ALB"
        return 1
    fi
    
    # Validate ALB state
    local alb_state
    alb_state=$(echo "$alb_info" | jq -r '.State.Code')
    if [[ "$alb_state" != "active" ]]; then
        log_error "ALB is not in active state: $alb_state" "ALB"
        return 1
    fi
    
    # Validate ALB scheme (optional, could be made configurable)
    local alb_scheme
    alb_scheme=$(echo "$alb_info" | jq -r '.Scheme')
    log_info "ALB scheme: $alb_scheme" "ALB"
    
    # Validate ALB type
    local alb_type
    alb_type=$(echo "$alb_info" | jq -r '.Type')
    if [[ "$alb_type" != "application" ]]; then
        log_error "ALB is not an application load balancer: $alb_type" "ALB"
        return 1
    fi
    
    # Validate VPC association (if VPC ID is available)
    local expected_vpc_id
    expected_vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$expected_vpc_id" ]]; then
        local alb_vpc_id
        alb_vpc_id=$(echo "$alb_info" | jq -r '.VpcId')
        if [[ "$alb_vpc_id" != "$expected_vpc_id" ]]; then
            log_error "ALB is not in the expected VPC. Expected: $expected_vpc_id, Actual: $alb_vpc_id" "ALB"
            return 1
        fi
    fi
    
    # Check if ALB has listeners
    local listener_count
    listener_count=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --query 'length(Listeners)' \
        --output text \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ "$listener_count" -gt 0 ]]; then
        log_info "ALB has $listener_count existing listener(s)" "ALB"
    else
        log_info "ALB has no existing listeners" "ALB"
    fi
    
    log_info "ALB validation successful: $alb_arn" "ALB"
    return 0
}