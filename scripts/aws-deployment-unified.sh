#!/bin/bash
# =============================================================================
# Unified AWS Deployment Script
# Demonstrates consolidated deployment using shared libraries
# Supports: spot, ondemand, and simple deployment types
# =============================================================================

set -euo pipefail

# =============================================================================
# CLEANUP ON FAILURE HANDLER
# =============================================================================

# Global flag to track if cleanup should run
CLEANUP_ON_FAILURE="${CLEANUP_ON_FAILURE:-true}"
RESOURCES_CREATED=false

cleanup_on_failure() {
    local exit_code=$?
    if [ "$CLEANUP_ON_FAILURE" = "true" ] && [ "$RESOURCES_CREATED" = "true" ] && [ $exit_code -ne 0 ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error "🚨 Deployment failed! Running automatic cleanup for stack: ${STACK_NAME:-unknown}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Use cleanup script if available, otherwise use library functions
        if [ -f "$PROJECT_ROOT/cleanup-stack.sh" ]; then
            log "Using cleanup script to remove resources..."
            "$PROJECT_ROOT/cleanup-stack.sh" "${STACK_NAME:-unknown}" || true
        else
            log "Running manual cleanup using library functions..."
            cleanup_instances "${STACK_NAME:-unknown}" || true
            cleanup_security_groups "${STACK_NAME:-unknown}" || true
            cleanup_key_pairs "${STACK_NAME:-unknown}" || true
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warning "💡 To disable automatic cleanup, set CLEANUP_ON_FAILURE=false"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Register cleanup handler
trap cleanup_on_failure EXIT

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly LIB_DIR="$PROJECT_ROOT/lib"

# Default configuration
readonly DEFAULT_DEPLOYMENT_TYPE="spot"
readonly DEFAULT_ENVIRONMENT="development"
readonly DEFAULT_BUDGET_TIER="medium"

# =============================================================================
# LOAD SHARED LIBRARIES
# =============================================================================

# Load error handling first
if [ -f "$LIB_DIR/error-handling.sh" ]; then
    source "$LIB_DIR/error-handling.sh"
    init_error_handling "${ERROR_HANDLING_MODE:-resilient}"
fi

# Load core libraries
source "$LIB_DIR/aws-deployment-common.sh"
source "$LIB_DIR/aws-config.sh"

# Load security validation
if [ -f "$SCRIPT_DIR/security-validation.sh" ]; then
    source "$SCRIPT_DIR/security-validation.sh"
fi

# Register cleanup functions
register_cleanup_function "cleanup_on_error" "Emergency cleanup on script failure"

# =============================================================================
# PRE-DEPLOYMENT VALIDATION
# =============================================================================

perform_pre_deployment_validation() {
    local deployment_type="$1"
    local stack_name="$2"
    
    log "Starting pre-deployment validation..."
    
    # Run security validation
    if command -v run_security_validation &>/dev/null; then
        if ! run_security_validation "$AWS_REGION" "$INSTANCE_TYPE" "$stack_name" "$AWS_PROFILE"; then
            error "Security validation failed"
            return 1
        fi
    fi
    
    # Check for secrets
    if [ -d "$PROJECT_ROOT/secrets" ]; then
        log "Validating secrets..."
        if [ -f "$SCRIPT_DIR/setup-secrets.sh" ]; then
            "$SCRIPT_DIR/setup-secrets.sh" validate || {
                warning "Secrets validation failed. Run: ./scripts/setup-secrets.sh setup"
                return 1
            }
        fi
    else
        warning "Secrets directory not found. Creating..."
        if [ -f "$SCRIPT_DIR/setup-secrets.sh" ]; then
            "$SCRIPT_DIR/setup-secrets.sh" setup || {
                error "Failed to setup secrets"
                return 1
            }
        fi
    fi
    
    # Validate Docker compose file
    local compose_file="${COMPOSE_FILE:-docker-compose.gpu-optimized.yml}"
    if [ -f "$PROJECT_ROOT/$compose_file" ]; then
        log "Validating Docker Compose configuration..."
        docker-compose -f "$PROJECT_ROOT/$compose_file" config >/dev/null || {
            error "Invalid Docker Compose configuration"
            return 1
        }
    fi
    
    success "Pre-deployment validation completed"
    return 0
}

# =============================================================================
# ERROR HANDLING AND CLEANUP
# =============================================================================

cleanup_on_error() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code: $exit_code"
        
        # Clean up any partial deployments if requested
        if [ "${CLEANUP_ON_ERROR:-false}" = "true" ] && [ -n "${STACK_NAME:-}" ]; then
            warning "Cleaning up partial deployment: $STACK_NAME"
            cleanup_aws_resources "$STACK_NAME" 2>/dev/null || true
        fi
        
        # Generate error report
        local error_report
        error_report=$(generate_error_report)
        warning "Error report generated: $error_report"
    fi
    
    return 0  # Don't fail cleanup
}

# =============================================================================
# USAGE AND HELP
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] STACK_NAME

Unified AWS deployment script supporting multiple deployment types.

ARGUMENTS:
  STACK_NAME              Name for the deployment stack (required)

OPTIONS:
  -t, --type TYPE         Deployment type: spot|ondemand|simple (default: $DEFAULT_DEPLOYMENT_TYPE)
  -r, --region REGION     AWS region (default: us-east-1)
  -i, --instance-type TYPE Instance type (auto-selected based on deployment type)
  -e, --environment ENV   Environment: development|staging|production (default: $DEFAULT_ENVIRONMENT)
  -p, --spot-price PRICE  Maximum spot price (for spot deployments)
  -b, --budget-tier TIER  Budget tier: low|medium|high (default: $DEFAULT_BUDGET_TIER)
  -c, --compose-file FILE Docker compose file to use
  -v, --vpc-id VPC_ID     Existing VPC ID (will create new if not provided)
  -s, --subnet-id SUBNET  Existing subnet ID (will create new if not provided)
  -k, --key-file FILE     SSH key file path (will create new if not provided)
  --no-monitoring         Skip CloudWatch monitoring setup
  --no-load-balancer      Skip load balancer setup (for applicable deployments)
  --no-cloudfront         Skip CloudFront setup (for applicable deployments)
  --validate-only         Validate configuration without deploying
  --cleanup               Clean up existing resources for the stack
  -h, --help              Show this help message

EXAMPLES:
  # Spot deployment with default settings
  $0 my-ai-stack

  # On-demand deployment in production
  $0 -t ondemand -e production -b high prod-ai-stack

  # Simple development deployment
  $0 -t simple -e development -i t3.medium dev-ai-stack

  # Spot deployment with custom pricing
  $0 -t spot -p 0.30 -i g4dn.xlarge cost-optimized-stack

  # Validate configuration only
  $0 --validate-only test-stack

  # Clean up existing deployment
  $0 --cleanup old-stack

DEPLOYMENT TYPES:
  spot      - Cost-optimized spot instances with auto-failover
  ondemand  - Reliable on-demand instances with load balancing
  simple    - Basic deployment for development and learning

For more information, see the documentation in the project README.
EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    
    # Initialize variables
    DEPLOYMENT_TYPE="$DEFAULT_DEPLOYMENT_TYPE"
    ENVIRONMENT="$DEFAULT_ENVIRONMENT"
    BUDGET_TIER="$DEFAULT_BUDGET_TIER"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -i|--instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--spot-price)
                SPOT_PRICE="$2"
                shift 2
                ;;
            -b|--budget-tier)
                BUDGET_TIER="$2"
                shift 2
                ;;
            -c|--compose-file)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            -v|--vpc-id)
                VPC_ID="$2"
                shift 2
                ;;
            -s|--subnet-id)
                SUBNET_ID="$2"
                shift 2
                ;;
            -k|--key-file)
                KEY_FILE="$2"
                shift 2
                ;;
            --no-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            --no-load-balancer)
                SKIP_LOAD_BALANCER=true
                shift
                ;;
            --no-cloudfront)
                SKIP_CLOUDFRONT=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --cleanup)
                CLEANUP_MODE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                # If STACK_NAME is already set via environment variable, ignore positional arguments
                if [ -z "${STACK_NAME:-}" ]; then
                    STACK_NAME="$1"
                else
                    # STACK_NAME already set by environment variable, skip this argument
                    echo "DEBUG: STACK_NAME already set by environment variable: $STACK_NAME, ignoring argument: $1"
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "${STACK_NAME:-}" ]; then
        error "Stack name is required"
        show_usage
        exit 1
    fi
}

# =============================================================================
# CONFIGURATION SETUP
# =============================================================================

setup_configuration() {
    log "Setting up deployment configuration..."

    # Set default configuration based on deployment type
    set_default_configuration "$DEPLOYMENT_TYPE"
    
    # Apply environment-specific overrides
    apply_environment_overrides "$ENVIRONMENT"
    
    # Apply region-specific configuration
    apply_region_specific_configuration "${AWS_REGION:-us-east-1}"
    
    # Apply cost optimization based on budget tier
    get_cost_optimized_configuration "$DEPLOYMENT_TYPE" "$BUDGET_TIER"
    
    # Set derived configuration
    export STACK_NAME
    export KEY_FILE="${KEY_FILE:-${STACK_NAME}-key.pem}"
    
    # Load deployment-specific libraries
    case "$DEPLOYMENT_TYPE" in
        "spot")
            source "$LIB_DIR/spot-instance.sh"
            ;;
        "ondemand")
            source "$LIB_DIR/ondemand-instance.sh"
            ;;
        "simple")
            source "$LIB_DIR/simple-instance.sh"
            ;;
    esac
    
    success "Configuration setup completed"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_deployment() {
    log "Validating deployment configuration..."
    
    # Validate configuration
    if ! validate_deployment_configuration "$STACK_NAME" "$DEPLOYMENT_TYPE"; then
        error "Configuration validation failed"
        return 1
    fi
    
    # Validate deployment-specific configuration
    if ! validate_deployment_config "$DEPLOYMENT_TYPE" "$STACK_NAME"; then
        error "Deployment-specific validation failed"
        return 1
    fi
    
    # Check prerequisites
    if ! check_common_prerequisites; then
        error "Prerequisites check failed"
        return 1
    fi
    
    # Display configuration summary
    display_configuration_summary "$DEPLOYMENT_TYPE" "$STACK_NAME"
    
    success "Validation completed successfully"
    return 0
}

# =============================================================================
# INFRASTRUCTURE SETUP
# =============================================================================

setup_infrastructure() {
    log "Setting up AWS infrastructure..."
    
    # Mark that we're starting to create resources
    RESOURCES_CREATED=true
    
    # Get or create VPC with retry
    if [ -z "${VPC_ID:-}" ]; then
        log_debug "Fetching default VPC information"
        
        if ! retry_command 3 5 "Get default VPC" \
           aws ec2 describe-vpcs \
               --filters "Name=is-default,Values=true" \
               --query 'Vpcs[0].VpcId' \
               --output text \
               --region "$AWS_REGION"; then
            log_error "Failed to retrieve VPC information after retries"
            suggest_error_recovery "aws"
            return 1
        fi
        
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=is-default,Values=true" \
            --query 'Vpcs[0].VpcId' \
            --output text \
            --region "$AWS_REGION")
        
        if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
            log_error "No default VPC found. Please specify --vpc-id" "AWS region: $AWS_REGION"
            return 1
        fi
        
        info "Using default VPC: $VPC_ID"
        log_debug "VPC validation successful"
    fi
    
    # Get or create subnet
    if [ -z "${SUBNET_ID:-}" ]; then
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
            --query 'Subnets[0].SubnetId' \
            --output text \
            --region "$AWS_REGION")
        
        if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
            error "No suitable subnet found. Please specify --subnet-id"
            return 1
        fi
        
        info "Using subnet: $SUBNET_ID"
        
        # Get the availability zone of the subnet
        SUBNET_AZ=$(aws ec2 describe-subnets \
            --subnet-ids "$SUBNET_ID" \
            --query 'Subnets[0].AvailabilityZone' \
            --output text \
            --region "$AWS_REGION")
        
        if [ "$SUBNET_AZ" = "None" ] || [ -z "$SUBNET_AZ" ]; then
            error "Failed to get availability zone for subnet: $SUBNET_ID"
            return 1
        fi
        
        info "Subnet availability zone: $SUBNET_AZ"
    fi
    
    # Create key pair
    if ! create_standard_key_pair "$STACK_NAME" "$KEY_FILE"; then
        error "Failed to create key pair"
        return 1
    fi
    
    # Create security group
    local additional_ports=()
    if [ "$DEPLOYMENT_TYPE" != "simple" ]; then
        additional_ports=(80 443 8080)  # Additional ports for load balancer deployments
    fi
    
    SECURITY_GROUP_ID=$(create_standard_security_group "$STACK_NAME" "$VPC_ID" "${additional_ports[@]+"${additional_ports[@]}"}")
    if [ -z "$SECURITY_GROUP_ID" ]; then
        error "Failed to create security group"
        return 1
    fi
    
    # Create IAM resources (for non-simple deployments)
    if [ "$DEPLOYMENT_TYPE" != "simple" ]; then
        local additional_policies=()
        if [ "$DEPLOYMENT_TYPE" = "ondemand" ]; then
            additional_policies=("arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess")
        fi
        
        IAM_INSTANCE_PROFILE=$(create_standard_iam_role "$STACK_NAME" "${additional_policies[@]+"${additional_policies[@]}"}")
        if [ -z "$IAM_INSTANCE_PROFILE" ]; then
            error "Failed to create IAM resources"
            return 1
        fi
    fi
    
    success "Infrastructure setup completed"
    return 0
}

# =============================================================================
# INSTANCE DEPLOYMENT
# =============================================================================

deploy_instance() {
    log "Deploying instance..."
    
    # Generate user data script
    local user_data
    case "$DEPLOYMENT_TYPE" in
        "simple")
            user_data=$(create_simple_user_data "$STACK_NAME" "$COMPOSE_FILE")
            ;;
        *)
            user_data=$(generate_user_data_script "$STACK_NAME" "")
            ;;
    esac
    
    # Launch instance based on deployment type
    case "$DEPLOYMENT_TYPE" in
        "spot")
            INSTANCE_ID=$(launch_spot_instance_with_failover \
                "$STACK_NAME" "$INSTANCE_TYPE" "$SPOT_PRICE" "$user_data" \
                "$SECURITY_GROUP_ID" "$SUBNET_ID" "${STACK_NAME}-key" "$IAM_INSTANCE_PROFILE" "$SUBNET_AZ")
            ;;
        "ondemand")
            INSTANCE_ID=$(launch_ondemand_instance \
                "$STACK_NAME" "$INSTANCE_TYPE" "$user_data" \
                "$SECURITY_GROUP_ID" "$SUBNET_ID" "${STACK_NAME}-key" "$IAM_INSTANCE_PROFILE")
            ;;
        "simple")
            INSTANCE_ID=$(launch_simple_instance \
                "$STACK_NAME" "$INSTANCE_TYPE" "$user_data" \
                "$SECURITY_GROUP_ID" "$SUBNET_ID" "${STACK_NAME}-key")
            ;;
    esac
    
    if [ -z "$INSTANCE_ID" ]; then
        error "Failed to launch instance"
        return 1
    fi
    
    # Get instance public IP
    INSTANCE_IP=$(get_instance_public_ip "$INSTANCE_ID")
    if [ -z "$INSTANCE_IP" ]; then
        error "Failed to get instance public IP"
        return 1
    fi
    
    success "Instance deployed: $INSTANCE_ID ($INSTANCE_IP)"
    return 0
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

deploy_application() {
    log "Deploying application..."
    
    # Wait for SSH to be ready
    if ! wait_for_ssh_ready "$INSTANCE_IP" "$KEY_FILE"; then
        error "SSH connectivity failed"
        return 1
    fi
    
    # Deploy application stack
    local follow_logs="${FOLLOW_LOGS:-false}"
    if ! deploy_application_stack "$INSTANCE_IP" "$KEY_FILE" "$STACK_NAME" "$COMPOSE_FILE" "$ENVIRONMENT" "$follow_logs"; then
        error "Application deployment failed"
        return 1
    fi
    
    success "Application deployed successfully"
    return 0
}

# =============================================================================
# LOAD BALANCER SETUP (ON-DEMAND ONLY)
# =============================================================================

setup_load_balancer() {
    if [ "$DEPLOYMENT_TYPE" != "ondemand" ] || [ "${SKIP_LOAD_BALANCER:-false}" = "true" ]; then
        info "Skipping load balancer setup"
        return 0
    fi
    
    log "Setting up load balancer..."
    
    # Get additional subnets for ALB
    local subnet_ids
    mapfile -t subnet_ids < <(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'Subnets[].SubnetId' \
        --output text | tr '\t' '\n' | head -2)
    
    if [ ${#subnet_ids[@]} -lt 2 ]; then
        warning "Need at least 2 subnets for ALB. Skipping load balancer setup."
        return 0
    fi
    
    # Create ALB
    ALB_ARN=$(create_application_load_balancer "$STACK_NAME" "$SECURITY_GROUP_ID" "${subnet_ids[@]}")
    if [ -z "$ALB_ARN" ]; then
        error "Failed to create load balancer"
        return 1
    fi
    
    # Create target groups and register instance
    local services
    IFS=' ' read -ra services <<< "$(get_standard_service_list "$DEPLOYMENT_TYPE")"
    
    for service_info in "${services[@]}"; do
        local service_name="${service_info%:*}"
        local service_port="${service_info#*:}"
        
        local tg_arn
        tg_arn=$(create_target_group "$STACK_NAME" "$service_name" "$service_port" "$VPC_ID")
        
        if [ -n "$tg_arn" ]; then
            register_instance_with_target_group "$tg_arn" "$INSTANCE_ID" "$service_port"
            create_alb_listener "$ALB_ARN" "$tg_arn" "$service_port"
        fi
    done
    
    # Get ALB DNS name
    ALB_DNS_NAME=$(get_alb_dns_name "$ALB_ARN")
    
    success "Load balancer setup completed: $ALB_DNS_NAME"
    return 0
}

# =============================================================================
# CLOUDFRONT SETUP (ON-DEMAND ONLY)
# =============================================================================

setup_cloudfront() {
    if [ "$DEPLOYMENT_TYPE" != "ondemand" ] || [ "${SKIP_CLOUDFRONT:-false}" = "true" ] || [ -z "${ALB_DNS_NAME:-}" ]; then
        info "Skipping CloudFront setup"
        return 0
    fi
    
    log "Setting up CloudFront distribution..."
    
    local cloudfront_result
    cloudfront_result=$(setup_cloudfront_distribution "$STACK_NAME" "$ALB_DNS_NAME")
    
    if [ -n "$cloudfront_result" ]; then
        CLOUDFRONT_ID="${cloudfront_result%:*}"
        CLOUDFRONT_DOMAIN="${cloudfront_result#*:}"
        success "CloudFront setup completed: $CLOUDFRONT_DOMAIN"
    fi
    
    return 0
}

# =============================================================================
# MONITORING SETUP
# =============================================================================

setup_monitoring() {
    if [ "${SKIP_MONITORING:-false}" = "true" ]; then
        info "Skipping monitoring setup"
        return 0
    fi
    
    log "Setting up monitoring..."
    
    case "$DEPLOYMENT_TYPE" in
        "simple")
            setup_simple_monitoring "$STACK_NAME" "$INSTANCE_ID"
            ;;
        *)
            setup_cloudwatch_monitoring "$STACK_NAME" "$INSTANCE_ID" "${ALB_ARN:-}"
            ;;
    esac
    
    success "Monitoring setup completed"
    return 0
}

# =============================================================================
# VALIDATION AND HEALTH CHECKS
# =============================================================================

validate_deployment_health() {
    log "Validating deployment health..."
    
    case "$DEPLOYMENT_TYPE" in
        "simple")
            validate_simple_deployment "$INSTANCE_IP"
            ;;
        *)
            local services
            IFS=' ' read -ra services <<< "$(get_standard_service_list "$DEPLOYMENT_TYPE")"
            validate_service_endpoints "$INSTANCE_IP" "${services[@]}"
            ;;
    esac
    
    return $?
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup_deployment() {
    if [ "${CLEANUP_MODE:-false}" != "true" ]; then
        return 0
    fi
    
    warning "Cleaning up deployment: $STACK_NAME"
    
    # Confirm cleanup
    read -p "Are you sure you want to clean up all resources for $STACK_NAME? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled"
        return 0
    fi
    
    # Perform cleanup
    cleanup_aws_resources "$STACK_NAME"
    
    success "Cleanup completed"
    return 0
}

# =============================================================================
# RESULTS DISPLAY
# =============================================================================

display_deployment_results() {
    echo
    success "=== Deployment Complete ==="
    echo "Stack Name: $STACK_NAME"
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "Environment: $ENVIRONMENT"
    echo "Instance ID: $INSTANCE_ID"
    echo "Public IP: $INSTANCE_IP"
    echo
    echo "🌐 Access URLs:"
    echo "   SSH: ssh -i $KEY_FILE ubuntu@$INSTANCE_IP"
    
    # Display service URLs
    local services
    IFS=' ' read -ra services <<< "$(get_standard_service_list "$DEPLOYMENT_TYPE")"
    
    for service_info in "${services[@]}"; do
        local service_name="${service_info%:*}"
        local service_port="${service_info#*:}"
        echo "   $service_name: http://$INSTANCE_IP:$service_port"
    done
    
    # Display load balancer URLs if available
    if [ -n "${ALB_DNS_NAME:-}" ]; then
        echo
        echo "🔗 Load Balancer:"
        echo "   ALB: http://$ALB_DNS_NAME"
    fi
    
    # Display CloudFront URLs if available
    if [ -n "${CLOUDFRONT_DOMAIN:-}" ]; then
        echo
        echo "🌍 CloudFront:"
        echo "   Distribution: https://$CLOUDFRONT_DOMAIN"
    fi
    
    echo
    echo "📊 Monitoring:"
    echo "   CloudWatch: AWS Console > CloudWatch > Instances > $INSTANCE_ID"
    
    echo
    echo "💰 Cost Information:"
    case "$DEPLOYMENT_TYPE" in
        "spot")
            calculate_spot_savings "${SPOT_PRICE:-0.50}" "$INSTANCE_TYPE" 24
            ;;
        "ondemand")
            analyze_ondemand_costs "$INSTANCE_TYPE" 24
            ;;
        "simple")
            analyze_simple_deployment_costs "$INSTANCE_TYPE" 8 30
            ;;
    esac
    
    echo
    info "Next Steps:"
    info "1. Wait for all services to be fully initialized (~5-10 minutes)"
    info "2. Access the n8n interface to start building workflows"
    info "3. Check the monitoring dashboard for system health"
    info "4. Review the cost optimization recommendations"
    echo
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Handle cleanup mode
    if [ "${CLEANUP_MODE:-false}" = "true" ]; then
        cleanup_deployment
        exit 0
    fi
    
    # Setup configuration
    setup_configuration
    
    # Validate deployment
    if ! validate_deployment; then
        exit 1
    fi
    
    # Exit if validation only
    if [ "${VALIDATE_ONLY:-false}" = "true" ]; then
        success "Configuration validation passed. Use without --validate-only to deploy."
        exit 0
    fi
    
    # Confirm deployment (skip confirmation if non-interactive)
    echo
    warning "Ready to deploy $DEPLOYMENT_TYPE instance"
    display_configuration_summary "$DEPLOYMENT_TYPE" "$STACK_NAME"
    echo
    
    # Check if running in interactive mode
    if [ -t 0 ] && [ "${FORCE_YES:-false}" != "true" ]; then
        read -p "Proceed with deployment? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled"
            exit 0
        fi
    else
        info "Non-interactive mode or FORCE_YES=true - proceeding with deployment"
    fi
    
    # Execute deployment steps
    log "Starting deployment process..."
    
    if ! setup_infrastructure; then
        error "Infrastructure setup failed"
        exit 1
    fi
    
    if ! deploy_instance; then
        error "Instance deployment failed"
        exit 1
    fi
    
    if ! deploy_application; then
        error "Application deployment failed"
        exit 1
    fi
    
    if ! setup_load_balancer; then
        warning "Load balancer setup had issues (continuing)"
    fi
    
    if ! setup_cloudfront; then
        warning "CloudFront setup had issues (continuing)"
    fi
    
    if ! setup_monitoring; then
        warning "Monitoring setup had issues (continuing)"
    fi
    
    # Validate deployment health
    log "Validating deployment health..."
    if validate_deployment_health; then
        success "All health checks passed"
    else
        warning "Some health checks failed. Check the logs and service status."
    fi
    
    # Display final results
    display_deployment_results
    
    success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"