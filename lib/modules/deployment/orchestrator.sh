#!/usr/bin/env bash
# =============================================================================
# Deployment Orchestrator Module
# Manages deployment flow, rollback, and resource coordination
# =============================================================================

# Prevent multiple sourcing
[ -n "${_DEPLOYMENT_ORCHESTRATOR_SH_LOADED:-}" ] && return 0
_DEPLOYMENT_ORCHESTRATOR_SH_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Source rollback module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/rollback.sh" ]]; then
    source "$SCRIPT_DIR/rollback.sh"
    ROLLBACK_ENABLED=true
else
    ROLLBACK_ENABLED=false
fi

# =============================================================================
# DEPLOYMENT CONFIGURATION
# =============================================================================

# Deployment configuration defaults
DEPLOYMENT_DEFAULT_TIMEOUT=1800
DEPLOYMENT_DEFAULT_RETRY_ATTEMPTS=3
DEPLOYMENT_DEFAULT_RETRY_DELAY=30

# Deployment states
DEPLOYMENT_STATE_INITIALIZING="initializing"
DEPLOYMENT_STATE_IN_PROGRESS="in_progress"
DEPLOYMENT_STATE_COMPLETED="completed"
DEPLOYMENT_STATE_FAILED="failed"
DEPLOYMENT_STATE_ROLLING_BACK="rolling_back"
DEPLOYMENT_STATE_ROLLED_BACK="rolled_back"

# =============================================================================
# ROLLBACK MONITORING FUNCTIONS
# =============================================================================

# Start rollback monitoring
start_rollback_monitoring() {
    local stack_name="$1"
    local check_interval="${2:-30}"
    
    log_info "Starting rollback monitoring for stack: $stack_name" "ORCHESTRATOR"
    
    while true; do
        # Check deployment state
        local deployment_state=$(get_deployment_state)
        
        # Stop monitoring if deployment completed or already rolling back
        if [[ "$deployment_state" == "$DEPLOYMENT_STATE_COMPLETED" ]] || \
           [[ "$deployment_state" == "$DEPLOYMENT_STATE_ROLLING_BACK" ]] || \
           [[ "$deployment_state" == "$DEPLOYMENT_STATE_ROLLED_BACK" ]]; then
            break
        fi
        
        # Check rollback triggers
        if check_rollback_triggers "$stack_name" "$deployment_state"; then
            log_warn "Rollback trigger activated during deployment" "ORCHESTRATOR"
            
            # Update deployment state
            set_deployment_state "$DEPLOYMENT_STATE_ROLLING_BACK"
            
            # Exit monitoring
            break
        fi
        
        sleep "$check_interval"
    done
}

# Stop rollback monitoring
stop_rollback_monitoring() {
    if [[ -n "$ROLLBACK_MONITOR_PID" ]]; then
        kill "$ROLLBACK_MONITOR_PID" 2>/dev/null || true
        unset ROLLBACK_MONITOR_PID
    fi
}

# =============================================================================
# DEPLOYMENT ORCHESTRATION FUNCTIONS
# =============================================================================

# Main deployment orchestrator
deploy_stack() {
    local stack_name="$1"
    local deployment_type="$2"
    local deployment_config="$3"
    
    log_info "Starting deployment for stack: $stack_name (type: $deployment_type)" "ORCHESTRATOR"
    
    # Initialize deployment
    if ! initialize_deployment "$stack_name" "$deployment_type"; then
        log_error "Failed to initialize deployment" "ORCHESTRATOR"
        
        # Trigger rollback if enabled
        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            rollback_deployment "$stack_name" "$deployment_type" "" "$ROLLBACK_MODE_FULL" "$ROLLBACK_TRIGGER_DEPLOYMENT_FAILURE"
        fi
        return 1
    fi
    
    # Set deployment state
    set_deployment_state "$DEPLOYMENT_STATE_IN_PROGRESS"
    
    # Start rollback trigger monitoring if enabled
    if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
        start_rollback_monitoring "$stack_name" &
        ROLLBACK_MONITOR_PID=$!
    fi
    
    # Execute deployment based on type
    local deployment_result
    case "$deployment_type" in
        "spot")
            deployment_result=$(deploy_spot_stack "$stack_name" "$deployment_config")
            ;;
        "alb")
            deployment_result=$(deploy_alb_stack "$stack_name" "$deployment_config")
            ;;
        "cdn")
            deployment_result=$(deploy_cdn_stack "$stack_name" "$deployment_config")
            ;;
        "full")
            deployment_result=$(deploy_full_stack "$stack_name" "$deployment_config")
            ;;
        *)
            log_error "Unknown deployment type: $deployment_type" "ORCHESTRATOR"
            set_deployment_state "$DEPLOYMENT_STATE_FAILED"
            return 1
            ;;
    esac
    
    # Check deployment result
    if [[ $? -eq 0 ]]; then
        log_info "Deployment completed successfully" "ORCHESTRATOR"
        set_deployment_state "$DEPLOYMENT_STATE_COMPLETED"
        
        # Stop rollback monitoring
        stop_rollback_monitoring
        
        return 0
    else
        log_error "Deployment failed, initiating rollback" "ORCHESTRATOR"
        set_deployment_state "$DEPLOYMENT_STATE_ROLLING_BACK"
        
        # Stop rollback monitoring
        stop_rollback_monitoring
        
        # Perform rollback based on configuration
        local rollback_mode="${ROLLBACK_MODE:-$ROLLBACK_MODE_FULL}"
        local rollback_trigger="$ROLLBACK_TRIGGER_DEPLOYMENT_FAILURE"
        
        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            if rollback_deployment "$stack_name" "$deployment_type" "$deployment_config" "$rollback_mode" "$rollback_trigger"; then
                log_info "Rollback completed successfully" "ORCHESTRATOR"
                set_deployment_state "$DEPLOYMENT_STATE_ROLLED_BACK"
            else
                log_error "Rollback failed" "ORCHESTRATOR"
                set_deployment_state "$DEPLOYMENT_STATE_FAILED"
            fi
        else
            log_warn "Rollback module not available, performing basic cleanup" "ORCHESTRATOR"
            # Fallback to basic cleanup
            cleanup_failed_deployment "$stack_name" "$deployment_type"
            set_deployment_state "$DEPLOYMENT_STATE_FAILED"
        fi
        
        return 1
    fi
}

# =============================================================================
# DEPLOYMENT CLEANUP FUNCTIONS
# =============================================================================

# Cleanup failed deployment (fallback when rollback module not available)
cleanup_failed_deployment() {
    local stack_name="$1"
    local deployment_type="$2"
    
    log_info "Performing basic cleanup for failed deployment: $stack_name" "ORCHESTRATOR"
    
    # Basic cleanup based on deployment type
    case "$deployment_type" in
        "spot")
            # Terminate instances and delete security groups
            local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
            local security_group_id=$(get_variable "SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
            local vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
            
            [[ -n "$instance_id" ]] && terminate_ec2_instance "$instance_id"
            [[ -n "$security_group_id" ]] && delete_security_group "$security_group_id"
            [[ -n "$vpc_id" ]] && delete_vpc_infrastructure "$vpc_id"
            ;;
        "alb"|"full")
            # More complex cleanup for ALB deployments
            delete_alb_resources "$stack_name"
            ;;
    esac
    
    # Clear variables
    clear_stack_variables "$stack_name"
}

# Initialize deployment
initialize_deployment() {
    local stack_name="$1"
    local deployment_type="$2"
    
    log_info "Initializing deployment for stack: $stack_name" "ORCHESTRATOR"
    
    # Set deployment metadata for rollback tracking
    set_variable "DEPLOYMENT_START_TIME" "$(date +%s)" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_TYPE" "$deployment_type" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_TIMEOUT" "${DEPLOYMENT_TIMEOUT:-$DEPLOYMENT_DEFAULT_TIMEOUT}" "$VARIABLE_SCOPE_STACK"
    
    # Initialize deployment phases based on type
    case "$deployment_type" in
        "spot")
            set_variable "DEPLOYMENT_PHASES" "infrastructure,compute" "$VARIABLE_SCOPE_STACK"
            ;;
        "alb")
            set_variable "DEPLOYMENT_PHASES" "infrastructure,alb,compute" "$VARIABLE_SCOPE_STACK"
            ;;
        "cdn")
            set_variable "DEPLOYMENT_PHASES" "cdn" "$VARIABLE_SCOPE_STACK"
            ;;
        "full")
            set_variable "DEPLOYMENT_PHASES" "infrastructure,alb,compute,cdn" "$VARIABLE_SCOPE_STACK"
            ;;
    esac
    
    # Set deployment state
    set_deployment_state "$DEPLOYMENT_STATE_INITIALIZING"
    
    # Create deployment directory
    local deployment_dir
    deployment_dir=$(create_deployment_directory "$stack_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create deployment directory" "ORCHESTRATOR"
        return 1
    fi
    
    # Initialize variable store
    if ! initialize_variable_store "$stack_name"; then
        log_error "Failed to initialize variable store" "ORCHESTRATOR"
        return 1
    fi
    
    # Store deployment metadata
    set_variable "DEPLOYMENT_START_TIME" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_TYPE" "$deployment_type" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_STATUS" "$DEPLOYMENT_STATE_INITIALIZING" "$VARIABLE_SCOPE_STACK"
    
    # Validate AWS configuration
    if ! validate_aws_configuration; then
        log_error "AWS configuration validation failed" "ORCHESTRATOR"
        return 1
    fi
    
    log_info "Deployment initialization completed" "ORCHESTRATOR"
    return 0
}

# Deploy spot instance stack
deploy_spot_stack() {
    local stack_name="$1"
    local deployment_config="$2"
    
    log_info "Deploying spot instance stack: $stack_name" "ORCHESTRATOR"
    
    # Phase 1: Infrastructure
    set_variable "PHASE_infrastructure_STATUS" "IN_PROGRESS" "$VARIABLE_SCOPE_STACK"
    set_variable "PHASE_infrastructure_COMPONENTS" "vpc,security_groups" "$VARIABLE_SCOPE_STACK"
    
    # Create VPC infrastructure
    local vpc_id
    vpc_id=$(create_vpc_infrastructure "$stack_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create VPC infrastructure" "ORCHESTRATOR"
        set_variable "PHASE_infrastructure_STATUS" "FAILED" "$VARIABLE_SCOPE_STACK"
        set_variable "FAILED_COMPONENTS" "vpc" "$VARIABLE_SCOPE_STACK"
        return 1
    fi
    set_variable "VPC_ID" "$vpc_id" "$VARIABLE_SCOPE_STACK"
    
    # Create EC2 security group
    local security_group_id
    security_group_id=$(create_ec2_security_group "$stack_name" "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create EC2 security group" "ORCHESTRATOR"
        set_variable "PHASE_infrastructure_STATUS" "FAILED" "$VARIABLE_SCOPE_STACK"
        set_variable "FAILED_COMPONENTS" "security_groups" "$VARIABLE_SCOPE_STACK"
        # Basic rollback if rollback module not available
        if [[ "$ROLLBACK_ENABLED" != "true" ]]; then
            delete_vpc_infrastructure "$stack_name"
        fi
        return 1
    fi
    set_variable "SECURITY_GROUP_ID" "$security_group_id" "$VARIABLE_SCOPE_STACK"
    
    # Infrastructure phase completed
    set_variable "PHASE_infrastructure_STATUS" "COMPLETED" "$VARIABLE_SCOPE_STACK"
    
    # Phase 2: Compute
    set_variable "PHASE_compute_STATUS" "IN_PROGRESS" "$VARIABLE_SCOPE_STACK"
    set_variable "PHASE_compute_COMPONENTS" "instances" "$VARIABLE_SCOPE_STACK"
    
    # Get subnet ID for EC2 instance
    local subnet_id
    subnet_id=$(get_public_subnet_id "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get public subnet ID" "ORCHESTRATOR"
        set_variable "PHASE_compute_STATUS" "FAILED" "$VARIABLE_SCOPE_STACK"
        set_variable "FAILED_COMPONENTS" "instances" "$VARIABLE_SCOPE_STACK"
        # Basic rollback if rollback module not available
        if [[ "$ROLLBACK_ENABLED" != "true" ]]; then
            delete_security_group "$security_group_id"
            delete_vpc_infrastructure "$stack_name"
        fi
        return 1
    fi
    set_variable "SUBNET_IDS" "$subnet_id" "$VARIABLE_SCOPE_STACK"
    
    # Create EC2 instance
    local instance_id
    instance_id=$(create_ec2_instance "$stack_name" "$subnet_id" "$security_group_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create EC2 instance" "ORCHESTRATOR"
        set_variable "PHASE_compute_STATUS" "FAILED" "$VARIABLE_SCOPE_STACK"
        set_variable "FAILED_COMPONENTS" "instances" "$VARIABLE_SCOPE_STACK"
        # Basic rollback if rollback module not available
        if [[ "$ROLLBACK_ENABLED" != "true" ]]; then
            delete_security_group "$security_group_id"
            delete_vpc_infrastructure "$stack_name"
        fi
        return 1
    fi
    set_variable "INSTANCE_ID" "$instance_id" "$VARIABLE_SCOPE_STACK"
    
    # Compute phase completed
    set_variable "PHASE_compute_STATUS" "COMPLETED" "$VARIABLE_SCOPE_STACK"
    
    # Wait for instance to be ready
    if ! wait_for_ec2_instance_ready "$instance_id"; then
        log_error "EC2 instance failed to become ready" "ORCHESTRATOR"
        # Rollback instance, security group, and VPC
        terminate_ec2_instance "$instance_id"
        delete_security_group "$security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Get instance public IP
    local public_ip
    public_ip=$(get_ec2_public_ip "$instance_id")
    if [[ $? -eq 0 ]]; then
        set_variable "EC2_PUBLIC_IP" "$public_ip" "$VARIABLE_SCOPE_STACK"
    fi
    
    log_info "Spot instance stack deployment completed successfully" "ORCHESTRATOR"
    return 0
}

# Deploy ALB stack
deploy_alb_stack() {
    local stack_name="$1"
    local deployment_config="$2"
    
    log_info "Deploying ALB stack: $stack_name" "ORCHESTRATOR"
    
    # Create VPC infrastructure
    local vpc_id
    vpc_id=$(create_vpc_infrastructure "$stack_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create VPC infrastructure" "ORCHESTRATOR"
        return 1
    fi
    
    # Create ALB security group
    local alb_security_group_id
    alb_security_group_id=$(create_alb_security_group "$stack_name" "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create ALB security group" "ORCHESTRATOR"
        # Rollback VPC
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Get public subnet IDs for ALB
    local public_subnet_ids
    public_subnet_ids=$(get_public_subnet_ids "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get public subnet IDs" "ORCHESTRATOR"
        # Rollback ALB security group and VPC
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Create ALB with target group
    if ! create_alb_with_target_group "$stack_name" "$vpc_id" "$public_subnet_ids" "$alb_security_group_id"; then
        log_error "Failed to create ALB with target group" "ORCHESTRATOR"
        # Rollback ALB security group and VPC
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    log_info "ALB stack deployment completed successfully" "ORCHESTRATOR"
    return 0
}

# Deploy CDN stack
deploy_cdn_stack() {
    local stack_name="$1"
    local deployment_config="$2"
    
    log_info "Deploying CDN stack: $stack_name" "ORCHESTRATOR"
    
    # Get ALB DNS name from variable store
    local alb_dns_name
    alb_dns_name=$(get_variable "ALB_DNS_NAME" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "$alb_dns_name" ]]; then
        log_error "ALB DNS name not found in variable store" "ORCHESTRATOR"
        return 1
    fi
    
    # Create CloudFront distribution
    local distribution_id
    distribution_id=$(create_cloudfront_distribution "$stack_name" "$alb_dns_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create CloudFront distribution" "ORCHESTRATOR"
        return 1
    fi
    
    log_info "CDN stack deployment completed successfully" "ORCHESTRATOR"
    return 0
}

# Deploy full stack (VPC + EC2 + ALB + CDN)
deploy_full_stack() {
    local stack_name="$1"
    local deployment_config="$2"
    
    log_info "Deploying full stack: $stack_name" "ORCHESTRATOR"
    
    # Deploy VPC infrastructure
    local vpc_id
    vpc_id=$(create_vpc_infrastructure "$stack_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create VPC infrastructure" "ORCHESTRATOR"
        return 1
    fi
    
    # Create security groups
    local alb_security_group_id
    alb_security_group_id=$(create_alb_security_group "$stack_name" "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create ALB security group" "ORCHESTRATOR"
        # Rollback VPC
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    local ec2_security_group_id
    ec2_security_group_id=$(create_ec2_security_group "$stack_name" "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create EC2 security group" "ORCHESTRATOR"
        # Rollback ALB security group and VPC
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Get subnet IDs
    local public_subnet_ids
    public_subnet_ids=$(get_public_subnet_ids "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get public subnet IDs" "ORCHESTRATOR"
        # Rollback security groups and VPC
        delete_security_group "$ec2_security_group_id"
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    local private_subnet_id
    private_subnet_id=$(get_private_subnet_id "$vpc_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get private subnet ID" "ORCHESTRATOR"
        # Rollback security groups and VPC
        delete_security_group "$ec2_security_group_id"
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Create ALB with target group
    if ! create_alb_with_target_group "$stack_name" "$vpc_id" "$public_subnet_ids" "$alb_security_group_id"; then
        log_error "Failed to create ALB with target group" "ORCHESTRATOR"
        # Rollback security groups and VPC
        delete_security_group "$ec2_security_group_id"
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Get target group ARN
    local target_group_arn
    target_group_arn=$(get_variable "TARGET_GROUP_ARN" "$VARIABLE_SCOPE_STACK")
    
    # Create EC2 instance
    local instance_id
    instance_id=$(create_ec2_instance "$stack_name" "$private_subnet_id" "$ec2_security_group_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create EC2 instance" "ORCHESTRATOR"
        # Rollback ALB, security groups, and VPC
        delete_alb_resources "$stack_name"
        delete_security_group "$ec2_security_group_id"
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Register instance with target group
    if [[ -n "$target_group_arn" ]]; then
        if ! register_targets "$target_group_arn" "$instance_id"; then
            log_error "Failed to register instance with target group" "ORCHESTRATOR"
            # Rollback instance, ALB, security groups, and VPC
            terminate_ec2_instance "$instance_id"
            delete_alb_resources "$stack_name"
            delete_security_group "$ec2_security_group_id"
            delete_security_group "$alb_security_group_id"
            delete_vpc_infrastructure "$stack_name"
            return 1
        fi
    fi
    
    # Wait for instance to be ready
    if ! wait_for_ec2_instance_ready "$instance_id"; then
        log_error "EC2 instance failed to become ready" "ORCHESTRATOR"
        # Rollback instance, ALB, security groups, and VPC
        terminate_ec2_instance "$instance_id"
        delete_alb_resources "$stack_name"
        delete_security_group "$ec2_security_group_id"
        delete_security_group "$alb_security_group_id"
        delete_vpc_infrastructure "$stack_name"
        return 1
    fi
    
    # Get ALB DNS name
    local alb_dns_name
    alb_dns_name=$(get_variable "ALB_DNS_NAME" "$VARIABLE_SCOPE_STACK")
    
    # Create CloudFront distribution
    if [[ -n "$alb_dns_name" ]]; then
        local distribution_id
        distribution_id=$(create_cloudfront_distribution "$stack_name" "$alb_dns_name")
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create CloudFront distribution" "ORCHESTRATOR"
            # Note: Don't rollback here as the core infrastructure is working
            log_warn "CloudFront deployment failed, but core infrastructure is operational" "ORCHESTRATOR"
        fi
    fi
    
    log_info "Full stack deployment completed successfully" "ORCHESTRATOR"
    return 0
}

# =============================================================================
# ROLLBACK FUNCTIONS
# =============================================================================

# Rollback deployment
rollback_deployment() {
    local stack_name="$1"
    local deployment_type="$2"
    
    log_info "Starting rollback for stack: $stack_name (type: $deployment_type)" "ORCHESTRATOR"
    
    # Set deployment state
    set_deployment_state "$DEPLOYMENT_STATE_ROLLING_BACK"
    
    # Perform rollback based on deployment type
    case "$deployment_type" in
        "spot")
            rollback_spot_stack "$stack_name"
            ;;
        "alb")
            rollback_alb_stack "$stack_name"
            ;;
        "cdn")
            rollback_cdn_stack "$stack_name"
            ;;
        "full")
            rollback_full_stack "$stack_name"
            ;;
        *)
            log_error "Unknown deployment type for rollback: $deployment_type" "ORCHESTRATOR"
            return 1
            ;;
    esac
    
    local rollback_result=$?
    
    # Update deployment status
    if [[ $rollback_result -eq 0 ]]; then
        set_deployment_state "$DEPLOYMENT_STATE_ROLLED_BACK"
        log_info "Rollback completed successfully" "ORCHESTRATOR"
    else
        set_deployment_state "$DEPLOYMENT_STATE_FAILED"
        log_error "Rollback failed" "ORCHESTRATOR"
    fi
    
    return $rollback_result
}

# Rollback spot stack
rollback_spot_stack() {
    local stack_name="$1"
    
    log_info "Rolling back spot stack: $stack_name" "ORCHESTRATOR"
    
    # Get resources from variable store
    local instance_id
    instance_id=$(get_variable "EC2_INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    
    local security_group_id
    security_group_id=$(get_variable "EC2_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    
    # Terminate EC2 instance
    if [[ -n "$instance_id" ]]; then
        terminate_ec2_instance "$instance_id"
    fi
    
    # Delete security group
    if [[ -n "$security_group_id" ]]; then
        delete_security_group "$security_group_id"
    fi
    
    # Delete VPC infrastructure
    delete_vpc_infrastructure "$stack_name"
    
    log_info "Spot stack rollback completed" "ORCHESTRATOR"
    return 0
}

# Rollback ALB stack
rollback_alb_stack() {
    local stack_name="$1"
    
    log_info "Rolling back ALB stack: $stack_name" "ORCHESTRATOR"
    
    # Delete ALB resources
    delete_alb_resources "$stack_name"
    
    # Delete VPC infrastructure
    delete_vpc_infrastructure "$stack_name"
    
    log_info "ALB stack rollback completed" "ORCHESTRATOR"
    return 0
}

# Rollback CDN stack
rollback_cdn_stack() {
    local stack_name="$1"
    
    log_info "Rolling back CDN stack: $stack_name" "ORCHESTRATOR"
    
    # Get CloudFront distribution ID
    local distribution_id
    distribution_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
    
    # Delete CloudFront distribution
    if [[ -n "$distribution_id" ]]; then
        delete_cloudfront_distribution "$distribution_id"
    fi
    
    log_info "CDN stack rollback completed" "ORCHESTRATOR"
    return 0
}

# Rollback full stack
rollback_full_stack() {
    local stack_name="$1"
    
    log_info "Rolling back full stack: $stack_name" "ORCHESTRATOR"
    
    # Get resources from variable store
    local instance_id
    instance_id=$(get_variable "EC2_INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    
    local distribution_id
    distribution_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
    
    local alb_security_group_id
    alb_security_group_id=$(get_variable "ALB_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    
    local ec2_security_group_id
    ec2_security_group_id=$(get_variable "EC2_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    
    # Delete CloudFront distribution
    if [[ -n "$distribution_id" ]]; then
        delete_cloudfront_distribution "$distribution_id"
    fi
    
    # Terminate EC2 instance
    if [[ -n "$instance_id" ]]; then
        terminate_ec2_instance "$instance_id"
    fi
    
    # Delete ALB resources
    delete_alb_resources "$stack_name"
    
    # Delete security groups
    if [[ -n "$ec2_security_group_id" ]]; then
        delete_security_group "$ec2_security_group_id"
    fi
    
    if [[ -n "$alb_security_group_id" ]]; then
        delete_security_group "$alb_security_group_id"
    fi
    
    # Delete VPC infrastructure
    delete_vpc_infrastructure "$stack_name"
    
    log_info "Full stack rollback completed" "ORCHESTRATOR"
    return 0
}

# =============================================================================
# DEPLOYMENT UTILITY FUNCTIONS
# =============================================================================

# Create deployment directory
create_deployment_directory() {
    local stack_name="$1"
    
    log_info "Creating deployment directory for stack: $stack_name" "ORCHESTRATOR"
    
    local deployment_dir="${DEPLOYMENT_DIR:-./deployments}/${stack_name}"
    
    if ! mkdir -p "$deployment_dir"; then
        log_error "Failed to create deployment directory: $deployment_dir" "ORCHESTRATOR"
        return 1
    fi
    
    log_info "Deployment directory created: $deployment_dir" "ORCHESTRATOR"
    echo "$deployment_dir"
    return 0
}

# Set deployment state
set_deployment_state() {
    local state="$1"
    
    log_info "Setting deployment state: $state" "ORCHESTRATOR"
    
    set_variable "DEPLOYMENT_STATE" "$state" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_LAST_UPDATE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VARIABLE_SCOPE_STACK"
}

# Validate AWS configuration
validate_aws_configuration() {
    log_info "Validating AWS configuration" "ORCHESTRATOR"
    
    # Check AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed" "ORCHESTRATOR"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "AWS credentials are not valid" "ORCHESTRATOR"
        return 1
    fi
    
    # Check AWS region
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not set" "ORCHESTRATOR"
        return 1
    fi
    
    log_info "AWS configuration validation passed" "ORCHESTRATOR"
    return 0
}

# Delete ALB resources
delete_alb_resources() {
    local stack_name="$1"
    
    log_info "Deleting ALB resources for stack: $stack_name" "ORCHESTRATOR"
    
    # Get ALB resources from variable store
    local alb_arn
    alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    
    local target_group_arn
    target_group_arn=$(get_variable "TARGET_GROUP_ARN" "$VARIABLE_SCOPE_STACK")
    
    local listener_arn
    listener_arn=$(get_variable "LISTENER_ARN" "$VARIABLE_SCOPE_STACK")
    
    local alb_security_group_id
    alb_security_group_id=$(get_variable "ALB_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    
    # Delete listener
    if [[ -n "$listener_arn" ]]; then
        delete_listener "$listener_arn"
    fi
    
    # Delete target group
    if [[ -n "$target_group_arn" ]]; then
        delete_target_group "$target_group_arn"
    fi
    
    # Delete ALB
    if [[ -n "$alb_arn" ]]; then
        delete_alb "$alb_arn"
    fi
    
    # Delete ALB security group
    if [[ -n "$alb_security_group_id" ]]; then
        delete_security_group "$alb_security_group_id"
    fi
    
    log_info "ALB resources deletion completed" "ORCHESTRATOR"
    return 0
}

# Get deployment status
get_deployment_status() {
    local stack_name="$1"
    
    log_info "Getting deployment status for stack: $stack_name" "ORCHESTRATOR"
    
    local deployment_state
    deployment_state=$(get_variable "DEPLOYMENT_STATE" "$VARIABLE_SCOPE_STACK")
    
    local deployment_start_time
    deployment_start_time=$(get_variable "DEPLOYMENT_START_TIME" "$VARIABLE_SCOPE_STACK")
    
    local deployment_last_update
    deployment_last_update=$(get_variable "DEPLOYMENT_LAST_UPDATE" "$VARIABLE_SCOPE_STACK")
    
    local deployment_type
    deployment_type=$(get_variable "DEPLOYMENT_TYPE" "$VARIABLE_SCOPE_STACK")
    
    # Build status JSON
    local status_json
    status_json=$(cat <<EOF
{
    "stack_name": "$stack_name",
    "deployment_type": "$deployment_type",
    "state": "$deployment_state",
    "start_time": "$deployment_start_time",
    "last_update": "$deployment_last_update"
}
EOF
)
    
    echo "$status_json"
    return 0
} 