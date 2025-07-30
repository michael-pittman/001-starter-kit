#!/usr/bin/env bash
# =============================================================================
# Modular AWS Deployment Orchestrator
# Minimal orchestrator that leverages modular components
# Compatible with bash 3.x+
# =============================================================================

set -euo pipefail

# Initialize library loader for version checking
SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

# Source the errors module
if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
    source "$LIB_DIR_TEMP/modules/core/errors.sh"
else
    # Fallback warning if errors module not found
    echo "WARNING: Could not load errors module" >&2
fi

# Initialize library loader
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Initialize script with required modules
initialize_script "aws-deployment-modular.sh" \
    "config/variables" \
    "core/registry" \
    "core/errors" || {
    echo "Error: Failed to initialize script" >&2
    exit 1
}

# Load additional libraries
safe_source "aws-cli-v2.sh" true "AWS CLI v2 enhancements"
safe_source "deployment-validation.sh" false "Deployment validation"
safe_source "error-recovery.sh" false "Error recovery"
safe_source "aws-quota-checker.sh" false "AWS quota checker"
safe_source "deployment-health.sh" false "Deployment health"

# Load monitoring integration
if safe_source "modules/monitoring/integration.sh" false "Monitoring integration"; then
    echo "📊 Monitoring integration loaded"
    MONITORING_AVAILABLE=true
else
    echo "⚠️  Monitoring integration not available"
    MONITORING_AVAILABLE=false
fi

# Initialize enhanced error handling with modern features
if declare -f init_enhanced_error_handling >/dev/null 2>&1; then
    init_enhanced_error_handling "auto" "true" "true"
    echo "🚀 Enhanced error handling initialized with modern features"
else
    # Fallback to basic error trap
    trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
    echo "⚙️  Basic error handling initialized"
fi

# Use standardized logging if available, otherwise fallback to custom functions
if command -v log_message >/dev/null 2>&1; then
    log_error() { log_message "ERROR" "$1" "DEPLOYMENT"; }
    log_warning() { log_message "WARN" "$1" "DEPLOYMENT"; }
    log_info() { log_message "INFO" "$1" "DEPLOYMENT"; }
    log_debug() { log_message "DEBUG" "$1" "DEPLOYMENT"; }
    log_success() { log_message "INFO" "$1" "DEPLOYMENT"; }  # Use INFO level for success
else
    # Fallback to custom logging functions
    log_error() { echo "ERROR: $*" >&2; }
    log_warning() { echo "WARNING: $*" >&2; }
    log_info() { echo "INFO: $*"; }
    log_debug() { [[ "${DEBUG:-}" == "true" ]] && echo "DEBUG: $*" >&2 || true; }
    log_success() { echo "SUCCESS: $*"; }
fi

# COMPATIBILITY: Define fallback error handling if not available
if ! declare -f handle_error >/dev/null 2>&1; then
    handle_error() {
        local exit_code="${1:-1}"
        local error_msg="${2:-Unknown error}"
        echo "ERROR: $error_msg (exit code: $exit_code)" >&2
        return "$exit_code"
    }
fi

# COMPATIBILITY: Define fallback retry function if not available
if ! declare -f retry_with_backoff >/dev/null 2>&1; then
    retry_with_backoff() {
        local cmd="$1"
        local description="${2:-Command}"
        local max_attempts="${3:-3}"
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            echo "Attempt $attempt/$max_attempts: $description"
            if $cmd; then
                return 0
            fi
            if [ $attempt -lt $max_attempts ]; then
                echo "Failed, retrying in $((attempt * 2)) seconds..."
                sleep $((attempt * 2))
            fi
            ((attempt++))
        done
        
        echo "ERROR: $description failed after $max_attempts attempts" >&2
        return 1
    }
fi

# COMPATIBILITY: Define fallback cleanup script generator if not available
if ! declare -f generate_cleanup_script >/dev/null 2>&1; then
    generate_cleanup_script() {
        local script_path="${1:-/tmp/cleanup-script.sh}"
        local stack_name="$(get_variable STACK_NAME)"
        
        cat > "$script_path" <<'EOF'
#!/usr/bin/env bash
echo "NOTICE: Cleanup script generation not available (error handling disabled)"
echo "To manually clean up resources, use: make destroy STACK_NAME=${STACK_NAME}"
EOF
        chmod +x "$script_path"
    }
fi

# Load AWS error handling for intelligent retries
safe_source "aws-api-error-handling.sh" false "AWS API error handling"

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] STACK_NAME

Modular AWS deployment orchestrator for AI Starter Kit with comprehensive infrastructure

Options:
    -t, --type TYPE           Deployment type: spot, ondemand, simple (default: spot)
    -r, --region REGION       AWS region (default: us-east-1)
    -i, --instance TYPE       Instance type (default: g4dn.xlarge)
    -k, --key-name NAME       SSH key name (default: STACK_NAME-key)
    -s, --volume-size SIZE    Volume size in GB (default: 100)
    -e, --environment ENV     Environment: development, staging, production (default: production)
    
    Infrastructure Options:
    --multi-az                Enable multi-AZ deployment with redundant subnets
    --private-subnets         Create private subnets (requires --nat-gateway for outbound)
    --nat-gateway             Create NAT Gateway for private subnet internet access
    --no-efs                  Disable EFS persistent storage (enabled by default)
    --alb                     Create Application Load Balancer for high availability
    --cloudfront, --cdn       Create CloudFront CDN distribution (requires --alb)
    
    Deployment Options:
    --validate-only           Validate configuration without deploying
    --cleanup                 Clean up existing resources before deploying
    --no-cleanup-on-failure   Don't clean up resources if deployment fails
    --dry-run                 Show what would be deployed without creating resources
    
    Monitoring Options:
    --monitoring PROFILE      Enable monitoring with profile: minimal, standard, comprehensive, debug
    --no-monitoring           Disable monitoring (monitoring is enabled by default)
    --monitoring-dir DIR      Directory for monitoring output (default: /tmp/monitoring_$$)
    
    Help:
    -h, --help               Show this help message

Examples:
    # Basic deployment
    $0 my-stack
    
    # Production deployment with multi-AZ and private subnets
    $0 --type ondemand --multi-az --private-subnets --nat-gateway prod-stack
    
    # Development deployment without EFS
    $0 --type simple --no-efs --environment development dev-stack
    
    # Validation only
    $0 --validate-only --multi-az test-stack

EOF
    exit "${1:-0}"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    # Register core deployment variables to prevent warnings
    register_variable "DEPLOYMENT_TYPE" "string" "deployment" "Type of deployment (simple, spot, enterprise)"
    register_variable "STACK_NAME" "string" "" "Name of the CloudFormation stack"
    register_variable "AWS_REGION" "string" "us-east-1" "AWS region for deployment"
    register_variable "INSTANCE_TYPE" "string" "g4dn.xlarge" "EC2 instance type"
    register_variable "KEY_NAME" "string" "" "EC2 key pair name"
    register_variable "VOLUME_SIZE" "number" "30" "EBS volume size in GB"
    register_variable "ENVIRONMENT" "string" "development" "Deployment environment"
    register_variable "VALIDATE_ONLY" "boolean" "false" "Run validation only"
    register_variable "CLEANUP_ON_FAILURE" "boolean" "true" "Cleanup resources on failure"
    register_variable "DRY_RUN" "boolean" "false" "Perform dry run without creating resources"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                set_variable "DEPLOYMENT_TYPE" "$2"
                shift 2
                ;;
            -r|--region)
                set_variable "AWS_REGION" "$2"
                set_variable "AWS_DEFAULT_REGION" "$2"
                shift 2
                ;;
            -i|--instance)
                set_variable "INSTANCE_TYPE" "$2"
                shift 2
                ;;
            -k|--key-name)
                set_variable "KEY_NAME" "$2"
                shift 2
                ;;
            -s|--volume-size)
                set_variable "VOLUME_SIZE" "$2"
                shift 2
                ;;
            -e|--environment)
                set_variable "ENVIRONMENT" "$2"
                shift 2
                ;;
            --multi-az)
                ENABLE_MULTI_AZ="true"
                shift
                ;;
            --private-subnets)
                ENABLE_PRIVATE_SUBNETS="true"
                shift
                ;;
            --nat-gateway)
                ENABLE_NAT_GATEWAY="true"
                shift
                ;;
            --no-efs)
                ENABLE_EFS="false"
                shift
                ;;
            --alb)
                ENABLE_ALB="true"
                shift
                ;;
            --validate-only)
                set_variable "VALIDATE_ONLY" "true"
                shift
                ;;
            --cleanup)
                CLEANUP_EXISTING="true"
                shift
                ;;
            --no-cleanup-on-failure)
                set_variable "CLEANUP_ON_FAILURE" "false"
                shift
                ;;
            --dry-run)
                set_variable "DRY_RUN" "true"
                shift
                ;;
            --monitoring)
                if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                    MONITORING_PROFILE="$2"
                    shift 2
                else
                    MONITORING_PROFILE="standard"
                    shift
                fi
                MONITORING_ENABLED="true"
                ;;
            --no-monitoring)
                MONITORING_ENABLED="false"
                shift
                ;;
            --monitoring-dir)
                MONITORING_OUTPUT_DIR="$2"
                shift 2
                ;;
            --cloudfront|--cdn)
                ENABLE_CLOUDFRONT="true"
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                usage 1
                ;;
            *)
                set_variable "STACK_NAME" "$1"
                shift
                ;;
        esac
    done
}

# =============================================================================
# DEPLOYMENT PIPELINE
# =============================================================================

# Main deployment pipeline
run_deployment() {
    local stack_name="$(get_variable STACK_NAME)"
    local deployment_type="$(get_variable DEPLOYMENT_TYPE)"
    
    echo "=== Starting Modular Deployment ==="
    echo "Stack: $stack_name"
    echo "Type: $deployment_type"
    echo "Region: $(get_variable AWS_REGION)"
    echo "================================"
    
    # Initialize registry
    initialize_registry "$stack_name"
    
    # Initialize monitoring if available
    if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f init_deployment_monitoring >/dev/null 2>&1; then
        echo -e "\n📊 Initializing deployment monitoring..."
        init_deployment_monitoring "$stack_name" "${MONITORING_PROFILE:-standard}" || {
            echo "WARNING: Monitoring initialization failed, continuing without monitoring" >&2
            MONITORING_AVAILABLE=false
        }
        
        # Pre-deployment monitoring
        if declare -f monitor_pre_deployment >/dev/null 2>&1; then
            monitor_pre_deployment "$stack_name"
        fi
    fi
    
    # Stage 1: Infrastructure with retry
    echo -e "\n🔧 Stage 1: Infrastructure Setup"
    
    # Start monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "infrastructure" "start"
    
    if declare -f retry_with_backoff >/dev/null 2>&1; then
        retry_with_backoff "setup_infrastructure" "Infrastructure setup" 2 || {
            echo "ERROR: Infrastructure setup failed after retries" >&2
            [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                monitor_deployment_phase "infrastructure" "error"
            return 1
        }
    else
        setup_infrastructure || {
            [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                monitor_deployment_phase "infrastructure" "error"
            return 1
        }
    fi
    
    # End monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "infrastructure" "end"
    
    # Stage 2: Instance Launch with intelligent recovery
    echo -e "\n🚀 Stage 2: Instance Launch"
    
    # Start monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "compute" "start"
    
    if ! launch_deployment_instance; then
        echo "Instance launch failed, attempting recovery..." >&2
        
        # Try recovery if available
        if declare -f orchestrate_recovery >/dev/null 2>&1; then
            if orchestrate_recovery "EC2_INSUFFICIENT_CAPACITY" "$stack_name"; then
                echo "Recovery successful, retrying instance launch..."
                launch_deployment_instance || {
                    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                        monitor_deployment_phase "compute" "error"
                    return 1
                }
            else
                echo "ERROR: Recovery failed" >&2
                [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                    monitor_deployment_phase "compute" "error"
                return 1
            fi
        else
            [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                monitor_deployment_phase "compute" "error"
            return 1
        fi
    fi
    
    # End monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "compute" "end"
    
    # Stage 3: Application Deployment
    echo -e "\n📦 Stage 3: Application Deployment"
    
    # Start monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "application" "start"
    
    if declare -f retry_with_backoff >/dev/null 2>&1; then
        retry_with_backoff "deploy_application" "Application deployment" 2 || {
            [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                monitor_deployment_phase "application" "error"
            return 1
        }
    else
        deploy_application || {
            [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
                monitor_deployment_phase "application" "error"
            return 1
        }
    fi
    
    # End monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "application" "end"
    
    # Stage 4: Validation
    echo -e "\n✅ Stage 4: Validation"
    
    # Start monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "validation" "start"
    
    validate_deployment || {
        [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
            monitor_deployment_phase "validation" "error"
        return 1
    }
    
    # End monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "validation" "end"
    
    # Stage 5: Health Check
    echo -e "\n🏥 Stage 5: Post-Deployment Health Check"
    
    # Start monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "health_check" "start"
    
    if declare -f perform_health_check >/dev/null 2>&1; then
        if ! perform_health_check "$stack_name" "$(get_variable AWS_REGION)"; then
            echo "WARNING: Health check detected issues" >&2
            echo "Please run 'make health-check STACK_NAME=$stack_name' for details" >&2
            
            # Monitor service health
            if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_service_health >/dev/null 2>&1; then
                for service in n8n qdrant ollama crawl4ai; do
                    monitor_service_health "$service" "healthy" || true
                done
            fi
        fi
    fi
    
    # End monitoring phase
    [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_deployment_phase >/dev/null 2>&1 && \
        monitor_deployment_phase "health_check" "end"
    
    # Post-deployment monitoring
    if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_post_deployment >/dev/null 2>&1; then
        monitor_post_deployment "success"
    fi
    
    # Success
    echo -e "\n🎉 Deployment completed successfully!"
    print_deployment_summary
    
    # Provide next steps
    echo -e "\n💡 Next Steps:"
    echo "  1. Run health check: make health-check STACK_NAME=$stack_name"
    echo "  2. Monitor deployment: make health-monitor STACK_NAME=$stack_name"
    echo "  3. View logs: make logs STACK_NAME=$stack_name"
    echo "  4. Check quotas: make check-quotas REGION=$(get_variable AWS_REGION)"
}

# =============================================================================
# STAGE 1: INFRASTRUCTURE
# =============================================================================

setup_infrastructure() {
    echo "Setting up comprehensive infrastructure..."
    
    # Load all infrastructure modules
    load_modules \
        "infrastructure/vpc" \
        "infrastructure/security" \
        "infrastructure/iam" \
        "infrastructure/efs" \
        "infrastructure/alb" \
        "infrastructure/cloudfront" || {
        echo "ERROR: Failed to load infrastructure modules" >&2
        return 1
    }
    
    # Get configuration variables
    local stack_name="$(get_variable STACK_NAME)"
    local deployment_type="$(get_variable DEPLOYMENT_TYPE)"
    # Initialize variables to prevent set -u errors (bash 3.x compatibility)
    local enable_multi_az="false"
    local enable_efs="true"
    local enable_private_subnets="false"
    local enable_nat_gateway="false"
    local enable_alb="false"
    local enable_cloudfront="false"
    
    # Set from environment if available
    [ "${ENABLE_MULTI_AZ:-}" = "true" ] && enable_multi_az="true"
    [ "${ENABLE_EFS:-}" = "false" ] && enable_efs="false"
    [ "${ENABLE_PRIVATE_SUBNETS:-}" = "true" ] && enable_private_subnets="true"
    [ "${ENABLE_NAT_GATEWAY:-}" = "true" ] && enable_nat_gateway="true"
    [ "${ENABLE_ALB:-}" = "true" ] && enable_alb="true"
    [ "${ENABLE_CLOUDFRONT:-}" = "true" ] && enable_cloudfront="true"
    
    echo "Configuration: Multi-AZ=$enable_multi_az, EFS=$enable_efs, Private Subnets=$enable_private_subnets, ALB=$enable_alb" >&2
    
    # Setup network infrastructure based on deployment type
    local network_info
    if [ "$enable_multi_az" = "true" ] || [ "$deployment_type" = "production" ]; then
        echo "Setting up enterprise multi-AZ network..." >&2
        network_info=$(setup_enterprise_network_infrastructure "$stack_name" "10.0.0.0/16" "$enable_private_subnets" "$enable_nat_gateway") || {
            echo "ERROR: Failed to setup enterprise network infrastructure" >&2
            return 1
        }
    else
        echo "Setting up basic network..." >&2
        network_info=$(setup_network_infrastructure "$stack_name") || {
            echo "ERROR: Failed to setup basic network infrastructure" >&2
            return 1
        }
    fi
    
    # Extract network details
    VPC_ID=$(echo "$network_info" | jq -r '.vpc_id')
    if [ "$enable_multi_az" = "true" ]; then
        # Get all public subnets for multi-AZ
        PUBLIC_SUBNETS_JSON=$(echo "$network_info" | jq -r '.public_subnets')
        SUBNET_ID=$(echo "$PUBLIC_SUBNETS_JSON" | jq -r '.[0].id')  # First subnet for backward compatibility
        PRIVATE_SUBNETS_JSON=$(echo "$network_info" | jq -r '.private_subnets // []')
    else
        SUBNET_ID=$(echo "$network_info" | jq -r '.subnet_id')
        PUBLIC_SUBNETS_JSON="[{\"id\": \"$SUBNET_ID\", \"az\": \"$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --query 'Subnets[0].AvailabilityZone' --output text)\", \"cidr\": \"$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --query 'Subnets[0].CidrBlock' --output text)\"}]"
        PRIVATE_SUBNETS_JSON="[]"
    fi
    
    echo "VPC: $VPC_ID, Primary Subnet: $SUBNET_ID" >&2
    
    # Create comprehensive security groups
    local security_groups_info
    security_groups_info=$(create_comprehensive_security_groups "$VPC_ID" "$stack_name") || {
        echo "ERROR: Failed to create security groups" >&2
        return 1
    }
    
    # Extract security group IDs
    SECURITY_GROUP_ID=$(echo "$security_groups_info" | jq -r '.application_sg_id')
    ALB_SECURITY_GROUP_ID=$(echo "$security_groups_info" | jq -r '.alb_sg_id')
    EFS_SECURITY_GROUP_ID=$(echo "$security_groups_info" | jq -r '.efs_sg_id')
    
    echo "Security Groups - App: $SECURITY_GROUP_ID, ALB: $ALB_SECURITY_GROUP_ID, EFS: $EFS_SECURITY_GROUP_ID" >&2
    
    # Setup comprehensive IAM
    local iam_info
    iam_info=$(setup_comprehensive_iam "$stack_name" "$enable_efs" "true" "false") || {
        echo "ERROR: Failed to setup IAM" >&2
        return 1
    }
    
    IAM_ROLE_NAME=$(echo "$iam_info" | jq -r '.role_name')
    IAM_INSTANCE_PROFILE=$(echo "$iam_info" | jq -r '.instance_profile')
    
    echo "IAM Role: $IAM_ROLE_NAME, Instance Profile: $IAM_INSTANCE_PROFILE" >&2
    
    # Setup EFS if enabled
    EFS_ID=""
    EFS_DNS=""
    if [ "$enable_efs" = "true" ]; then
        echo "Setting up EFS infrastructure..." >&2
        local efs_info
        efs_info=$(setup_efs_infrastructure "$stack_name" "$PUBLIC_SUBNETS_JSON" "$EFS_SECURITY_GROUP_ID") || {
            echo "WARNING: Failed to setup EFS, continuing without persistent storage" >&2
            EFS_ID=""
            EFS_DNS=""
        }
        
        if [ -n "$efs_info" ]; then
            EFS_ID=$(echo "$efs_info" | jq -r '.efs_id')
            EFS_DNS=$(echo "$efs_info" | jq -r '.efs_dns')
            echo "EFS: $EFS_ID ($EFS_DNS)" >&2
        fi
    fi
    
    # Setup ALB if enabled
    ALB_DNS_NAME=""
    ALB_TARGET_GROUP_ARN=""
    ALB_SETUP_FAILED="false"
    if [ "$enable_alb" = "true" ]; then
        echo "Setting up Application Load Balancer..." >&2
        local alb_info
        
        # Check if we have enough subnets for ALB
        local subnet_count
        subnet_count=$(echo "$PUBLIC_SUBNETS_JSON" | jq 'length')
        if [ "$subnet_count" -lt 2 ]; then
            echo "WARNING: ALB requires at least 2 subnets in different AZs (found: $subnet_count)" >&2
            echo "WARNING: Continuing without ALB - use multi-AZ deployment for ALB support" >&2
            ALB_SETUP_FAILED="true"
            enable_alb="false"
        else
            # Try to setup ALB with retries
            alb_info=$(setup_alb_infrastructure_with_retries "$stack_name" "$PUBLIC_SUBNETS_JSON" "$ALB_SECURITY_GROUP_ID" "$VPC_ID" 3 10) || {
                echo "WARNING: Failed to setup ALB after retries, continuing without load balancer" >&2
                ALB_SETUP_FAILED="true"
                enable_alb="false"
                ALB_DNS_NAME=""
                ALB_TARGET_GROUP_ARN=""
            }
            
            if [ -n "$alb_info" ] && [ "$alb_info" != "{}" ]; then
                ALB_DNS_NAME=$(echo "$alb_info" | jq -r '.alb_dns // empty')
                if [ -n "$ALB_DNS_NAME" ]; then
                    # Get the first target group ARN (for n8n by default)
                    ALB_TARGET_GROUP_ARN=$(echo "$alb_info" | jq -r '.target_groups[0].target_group_arn // empty')
                    # Store all target groups for instance registration
                    ALB_TARGET_GROUPS_JSON=$(echo "$alb_info" | jq -c '.target_groups // []')
                    echo "ALB: $ALB_DNS_NAME (Primary Target Group: $ALB_TARGET_GROUP_ARN)" >&2
                else
                    echo "WARNING: ALB created but DNS name not available" >&2
                    ALB_SETUP_FAILED="true"
                    enable_alb="false"
                fi
            else
                ALB_SETUP_FAILED="true"
                enable_alb="false"
            fi
        fi
    fi
    
    # Setup CloudFront if enabled and ALB was successful
    CLOUDFRONT_DOMAIN=""
    CLOUDFRONT_DIST_ID=""
    if [ "$enable_cloudfront" = "true" ] && [ "$enable_alb" = "true" ] && [ -n "$ALB_DNS_NAME" ]; then
        echo "Setting up CloudFront CDN distribution..." >&2
        local cf_info
        cf_info=$(setup_cloudfront_for_alb "$stack_name" "$ALB_DNS_NAME") || {
            echo "WARNING: Failed to setup CloudFront, continuing without CDN" >&2
            CLOUDFRONT_DOMAIN=""
            CLOUDFRONT_DIST_ID=""
        }
        
        if [ -n "$cf_info" ]; then
            CLOUDFRONT_DIST_ID=$(echo "$cf_info" | jq -r '.distribution_id // empty')
            CLOUDFRONT_DOMAIN=$(echo "$cf_info" | jq -r '.domain_name // empty')
            if [ -n "$CLOUDFRONT_DOMAIN" ]; then
                echo "CloudFront: https://$CLOUDFRONT_DOMAIN (Distribution: $CLOUDFRONT_DIST_ID)" >&2
            fi
        fi
    elif [ "$enable_cloudfront" = "true" ] && [ "$ALB_SETUP_FAILED" = "true" ]; then
        echo "WARNING: CloudFront requires ALB, but ALB setup failed. Skipping CloudFront." >&2
        echo "TIP: Use --multi-az flag to ensure ALB can be created (requires 2+ AZs)" >&2
    fi
    
    # Ensure key pair
    local key_name="$(get_variable KEY_NAME)"
    if [ -z "$key_name" ]; then
        key_name="${stack_name}-key"
        set_variable "KEY_NAME" "$key_name"
    fi
    
    KEY_NAME=$(ensure_key_pair "$key_name") || {
        echo "ERROR: Failed to ensure key pair" >&2
        return 1
    }
    
    echo "Key Pair: $KEY_NAME" >&2
    
    # Export variables for use in other stages
    export VPC_ID SUBNET_ID PUBLIC_SUBNETS_JSON PRIVATE_SUBNETS_JSON
    export SECURITY_GROUP_ID ALB_SECURITY_GROUP_ID EFS_SECURITY_GROUP_ID
    export IAM_ROLE_NAME IAM_INSTANCE_PROFILE KEY_NAME
    export EFS_ID EFS_DNS ALB_DNS_NAME ALB_TARGET_GROUP_ARN ALB_TARGET_GROUPS_JSON
    export CLOUDFRONT_DOMAIN CLOUDFRONT_DIST_ID ALB_SETUP_FAILED
    
    echo "Comprehensive infrastructure setup complete" >&2
    return 0
}

# =============================================================================
# STAGE 2: INSTANCE LAUNCH
# =============================================================================

launch_deployment_instance() {
    echo "Launching instance..."
    
    # Load instance modules
    load_modules \
        "instances/launch" \
        "deployment/userdata" || {
        echo "ERROR: Failed to load instance modules" >&2
        return 1
    }
    
    # Generate user data
    local user_data
    user_data=$(generate_user_data) || {
        echo "ERROR: Failed to generate user data" >&2
        return 1
    }
    
    # Build enhanced launch configuration
    local launch_config=$(cat <<EOF
{
    "instance_type": "$(get_variable INSTANCE_TYPE)",
    "key_name": "$KEY_NAME",
    "security_group_id": "$SECURITY_GROUP_ID",
    "subnet_id": "$SUBNET_ID",
    "iam_instance_profile": "$IAM_INSTANCE_PROFILE",
    "volume_size": $(get_variable VOLUME_SIZE),
    "user_data": "$user_data",
    "stack_name": "$(get_variable STACK_NAME)",
    "efs_id": "$EFS_ID",
    "efs_dns": "$EFS_DNS",
    "vpc_id": "$VPC_ID",
    "alb_target_group_arn": "$ALB_TARGET_GROUP_ARN"
}
EOF
)
    
    # Launch instance based on deployment type
    local deployment_type="$(get_variable DEPLOYMENT_TYPE)"
    INSTANCE_ID=$(launch_instance "$(build_launch_config "$launch_config")" "$deployment_type") || {
        echo "ERROR: Failed to launch instance" >&2
        return 1
    }
    
    echo "Instance launched: $INSTANCE_ID"
    
    # Register instance with ALB target groups if enabled
    if [ -n "$ALB_TARGET_GROUP_ARN" ]; then
        echo "Registering instance with ALB target groups..." >&2
        # Register with all target groups created for this deployment
        if [ -n "${ALB_TARGET_GROUPS_JSON:-}" ]; then
            echo "$ALB_TARGET_GROUPS_JSON" | jq -c '.[]' | while read -r service_obj; do
                local tg_arn port
                tg_arn=$(echo "$service_obj" | jq -r '.target_group_arn')
                port=$(echo "$service_obj" | jq -r '.port')
                
                register_target "$tg_arn" "$INSTANCE_ID" "$port" || {
                    echo "WARNING: Failed to register instance with target group $tg_arn" >&2
                }
            done
        else
            # Fallback: register with primary target group only
            register_target "$ALB_TARGET_GROUP_ARN" "$INSTANCE_ID" "80" || {
                echo "WARNING: Failed to register instance with primary ALB target group" >&2
            }
        fi
    fi
    
    # Wait for SSH
    wait_for_ssh "$INSTANCE_ID" || {
        echo "WARNING: SSH not ready, continuing anyway" >&2
    }
    
    return 0
}

# =============================================================================
# STAGE 3: APPLICATION DEPLOYMENT
# =============================================================================

deploy_application() {
    echo "Deploying application..."
    
    # Application deployment is handled by user data script
    # Here we just wait and monitor
    
    echo "Waiting for application deployment to complete..."
    sleep 60  # Give services time to start
    
    return 0
}

# =============================================================================
# STAGE 4: VALIDATION
# =============================================================================

validate_deployment() {
    echo "Validating deployment..."
    
    # Load monitoring module
    load_module "monitoring/health" || {
        echo "ERROR: Failed to load monitoring module" >&2
        return 1
    }
    
    # Run health checks
    check_instance_health "$INSTANCE_ID" "all" || {
        echo "WARNING: Some health checks failed" >&2
        # Don't fail deployment for health check warnings
    }
    
    # Setup monitoring
    setup_cloudwatch_monitoring "$(get_variable STACK_NAME)" "$INSTANCE_ID"
    
    return 0
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

print_deployment_summary() {
    local public_ip
    public_ip=$(get_instance_public_ip "$INSTANCE_ID") || public_ip="N/A"
    
    cat <<EOF

================================================================================
COMPREHENSIVE DEPLOYMENT SUMMARY
================================================================================
Stack Name:     $(get_variable STACK_NAME)
Deployment Type: $(get_variable DEPLOYMENT_TYPE)
Region:         $(get_variable AWS_REGION)

Infrastructure:
- VPC ID:       ${VPC_ID:-N/A}
- Subnet ID:    ${SUBNET_ID:-N/A}
- Security Groups:
  * Application: ${SECURITY_GROUP_ID:-N/A}
  * ALB:         ${ALB_SECURITY_GROUP_ID:-N/A}
  * EFS:         ${EFS_SECURITY_GROUP_ID:-N/A}
- IAM Role:     ${IAM_ROLE_NAME:-N/A}
- Key Pair:     ${KEY_NAME:-N/A}

Compute:
- Instance ID:  $INSTANCE_ID
- Instance Type: $(get_variable INSTANCE_TYPE)
- Public IP:    $public_ip

Storage:
- EFS ID:       ${EFS_ID:-Not configured}
- EFS DNS:      ${EFS_DNS:-Not configured}

Load Balancing:
- ALB DNS:      ${ALB_DNS_NAME:-Not configured}
- Target Group: ${ALB_TARGET_GROUP_ARN:-Not configured}

CDN (CloudFront):
- Domain:       ${CLOUDFRONT_DOMAIN:-Not configured}
- Distribution: ${CLOUDFRONT_DIST_ID:-Not configured}

Service URLs:
EOF
    
    # Display appropriate URLs based on what's configured
    if [ -n "$CLOUDFRONT_DOMAIN" ]; then
        cat <<EOF
- n8n Workflow UI:    https://${CLOUDFRONT_DOMAIN}/n8n/
- Qdrant Vector DB:   https://${CLOUDFRONT_DOMAIN}/api/qdrant/
- Ollama LLM API:     https://${CLOUDFRONT_DOMAIN}/api/ollama/
- Crawl4AI Scraper:   https://${CLOUDFRONT_DOMAIN}/api/crawl4ai/
- Health Check:       https://${CLOUDFRONT_DOMAIN}/health
EOF
    elif [ -n "$ALB_DNS_NAME" ]; then
        cat <<EOF
- n8n Workflow UI:    http://${ALB_DNS_NAME}:5678
- Qdrant Vector DB:   http://${ALB_DNS_NAME}:6333
- Ollama LLM API:     http://${ALB_DNS_NAME}:11434
- Crawl4AI Scraper:   http://${ALB_DNS_NAME}:11235
- Health Check:       http://${ALB_DNS_NAME}:8080/health
EOF
    else
        cat <<EOF
- n8n Workflow UI:    http://${public_ip}:5678
- Qdrant Vector DB:   http://${public_ip}:6333
- Ollama LLM API:     http://${public_ip}:11434
- Crawl4AI Scraper:   http://${public_ip}:11235
- Health Check:       http://${public_ip}:8080/health
EOF
    fi
    
    cat <<EOF

SSH Access:
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${public_ip}

Next Steps:
1. Check service health: curl http://${ALB_DNS_NAME:-$public_ip}:8080/health
2. View logs: ./scripts/aws-deployment-modular.sh --logs $INSTANCE_ID
3. Monitor: Check CloudWatch dashboard "$(get_variable STACK_NAME)-dashboard"
================================================================================

EOF
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup_on_failure() {
    if [ "$(get_variable CLEANUP_ON_FAILURE)" = "true" ]; then
        echo "Deployment failed, running cleanup..." >&2
        
        # Post-deployment monitoring for failure
        if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f monitor_post_deployment >/dev/null 2>&1; then
            monitor_post_deployment "failed" "Deployment failed, cleanup initiated"
        fi
        
        # Generate and run cleanup script
        generate_cleanup_script "/tmp/cleanup-${STACK_NAME}.sh"
        bash "/tmp/cleanup-${STACK_NAME}.sh"
        
        # Cleanup monitoring
        if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f cleanup_deployment_monitoring >/dev/null 2>&1; then
            cleanup_deployment_monitoring
        fi
    fi
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_required_variables() {
    local missing_vars=()
    
    # Check required variables
    local required_vars=("STACK_NAME" "DEPLOYMENT_TYPE" "AWS_REGION")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "$(get_variable "$var")" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "ERROR: Missing required variables: ${missing_vars[*]}" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Validate required variables
    validate_required_variables || {
        echo "ERROR: Missing required variables" >&2
        usage 1
    }
    
    # Run comprehensive deployment validation
    echo -e "\n🔍 Running comprehensive deployment validation..."
    if declare -f validate_deployment_prerequisites >/dev/null 2>&1; then
        if ! validate_deployment_prerequisites "$(get_variable STACK_NAME)" "$(get_variable AWS_REGION)"; then
            echo "ERROR: Deployment validation failed" >&2
            echo "Please resolve the issues above before proceeding" >&2
            exit 1
        fi
    fi
    
    # Check AWS quotas for the deployment type
    echo -e "\n📋 Checking AWS service quotas..."
    if declare -f check_all_quotas >/dev/null 2>&1; then
        local deployment_type="standard"
        [ "$(get_variable MULTI_AZ)" = "true" ] && deployment_type="multi-az"
        [ "$(get_variable ALB_ENABLED)" = "true" ] && deployment_type="enterprise"
        
        if ! check_all_quotas "$(get_variable AWS_REGION)" "$deployment_type"; then
            echo "WARNING: AWS quota issues detected" >&2
            echo "Deployment may fail due to insufficient quotas" >&2
            # Continue with warning rather than failing
        fi
    fi
    
    # Print configuration
    print_configuration
    
    # Validation only mode
    if [ "$(get_variable VALIDATE_ONLY)" = "true" ]; then
        echo "Validation complete. Exiting without deployment."
        exit 0
    fi
    
    # Cleanup existing resources if requested
    # Initialize cleanup variable to prevent set -u errors
    local cleanup_existing="false"
    [ "${CLEANUP_EXISTING:-}" = "true" ] && cleanup_existing="true"
    
    if [ "$cleanup_existing" = "true" ]; then
        echo "Cleaning up existing resources..."
        cleanup_on_failure
    fi
    
    # Set up error handling with monitoring cleanup
    cleanup_and_exit() {
        local exit_code=$?
        echo "Error occurred during deployment. Exit code: $exit_code" >&2
        
        # Cleanup monitoring if enabled
        if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f cleanup_deployment_monitoring >/dev/null 2>&1; then
            cleanup_deployment_monitoring
        fi
        
        exit $exit_code
    }
    
    # Set trap for errors and script exit
    trap cleanup_and_exit ERR EXIT
    
    # Run deployment
    run_deployment
    
    # Success - clear trap
    trap - ERR EXIT
    
    # Final monitoring cleanup
    if [[ "$MONITORING_AVAILABLE" == "true" ]] && declare -f cleanup_deployment_monitoring >/dev/null 2>&1; then
        cleanup_deployment_monitoring
    fi
}

# Run main function
main "$@"