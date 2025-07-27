#!/bin/bash
# =============================================================================
# Modular AWS Deployment Orchestrator
# Minimal orchestrator that leverages modular components
# =============================================================================

set -euo pipefail

# =============================================================================
# SCRIPT SETUP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core modules
source "$PROJECT_ROOT/lib/modules/config/variables.sh"
source "$PROJECT_ROOT/lib/modules/core/registry.sh"
source "$PROJECT_ROOT/lib/modules/core/errors.sh"

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
    
    Deployment Options:
    --validate-only           Validate configuration without deploying
    --cleanup                 Clean up existing resources before deploying
    --no-cleanup-on-failure   Don't clean up resources if deployment fails
    --dry-run                 Show what would be deployed without creating resources
    
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
    
    # Stage 1: Infrastructure
    echo -e "\n🔧 Stage 1: Infrastructure Setup"
    setup_infrastructure || return 1
    
    # Stage 2: Instance Launch
    echo -e "\n🚀 Stage 2: Instance Launch"
    launch_deployment_instance || return 1
    
    # Stage 3: Application Deployment
    echo -e "\n📦 Stage 3: Application Deployment"
    deploy_application || return 1
    
    # Stage 4: Validation
    echo -e "\n✅ Stage 4: Validation"
    validate_deployment || return 1
    
    # Success
    echo -e "\n🎉 Deployment completed successfully!"
    print_deployment_summary
}

# =============================================================================
# STAGE 1: INFRASTRUCTURE
# =============================================================================

setup_infrastructure() {
    echo "Setting up comprehensive infrastructure..."
    
    # Source all infrastructure modules
    source "$PROJECT_ROOT/lib/modules/infrastructure/vpc.sh"
    source "$PROJECT_ROOT/lib/modules/infrastructure/security.sh"
    source "$PROJECT_ROOT/lib/modules/infrastructure/iam.sh"
    source "$PROJECT_ROOT/lib/modules/infrastructure/efs.sh"
    source "$PROJECT_ROOT/lib/modules/infrastructure/alb.sh"
    
    # Get configuration variables
    local stack_name="$(get_variable STACK_NAME)"
    local deployment_type="$(get_variable DEPLOYMENT_TYPE)"
    # Initialize variables to prevent set -u errors (bash 3.x compatibility)
    local enable_multi_az="false"
    local enable_efs="true"
    local enable_private_subnets="false"
    local enable_nat_gateway="false"
    local enable_alb="false"
    
    # Set from environment if available
    [ "${ENABLE_MULTI_AZ:-}" = "true" ] && enable_multi_az="true"
    [ "${ENABLE_EFS:-}" = "false" ] && enable_efs="false"
    [ "${ENABLE_PRIVATE_SUBNETS:-}" = "true" ] && enable_private_subnets="true"
    [ "${ENABLE_NAT_GATEWAY:-}" = "true" ] && enable_nat_gateway="true"
    [ "${ENABLE_ALB:-}" = "true" ] && enable_alb="true"
    
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
    if [ "$enable_alb" = "true" ]; then
        echo "Setting up Application Load Balancer..." >&2
        local alb_info
        alb_info=$(setup_alb_infrastructure "$stack_name" "$PUBLIC_SUBNETS_JSON" "$ALB_SECURITY_GROUP_ID" "$VPC_ID") || {
            echo "WARNING: Failed to setup ALB, continuing without load balancer" >&2
            ALB_DNS_NAME=""
            ALB_TARGET_GROUP_ARN=""
        }
        
        if [ -n "$alb_info" ]; then
            ALB_DNS_NAME=$(echo "$alb_info" | jq -r '.alb_dns')
            # Get the first target group ARN (for n8n by default)
            ALB_TARGET_GROUP_ARN=$(echo "$alb_info" | jq -r '.target_groups[0].target_group_arn')
            # Store all target groups for instance registration
            ALB_TARGET_GROUPS_JSON=$(echo "$alb_info" | jq -c '.target_groups')
            echo "ALB: $ALB_DNS_NAME (Primary Target Group: $ALB_TARGET_GROUP_ARN)" >&2
        fi
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
    
    echo "Comprehensive infrastructure setup complete" >&2
    return 0
}

# =============================================================================
# STAGE 2: INSTANCE LAUNCH
# =============================================================================

launch_deployment_instance() {
    echo "Launching instance..."
    
    # Source instance modules
    source "$PROJECT_ROOT/lib/modules/instances/launch.sh"
    source "$PROJECT_ROOT/lib/modules/deployment/userdata.sh"
    
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
    
    # Source monitoring module
    source "$PROJECT_ROOT/lib/modules/monitoring/health.sh"
    
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

Service URLs:
- n8n Workflow UI:    http://${ALB_DNS_NAME:-$public_ip}:5678
- Qdrant Vector DB:   http://${ALB_DNS_NAME:-$public_ip}:6333
- Ollama LLM API:     http://${ALB_DNS_NAME:-$public_ip}:11434
- Crawl4AI Scraper:   http://${ALB_DNS_NAME:-$public_ip}:11235
- Health Check:       http://${ALB_DNS_NAME:-$public_ip}:8080/health

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
        
        # Generate and run cleanup script
        generate_cleanup_script "/tmp/cleanup-${STACK_NAME}.sh"
        bash "/tmp/cleanup-${STACK_NAME}.sh"
    fi
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
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Run deployment
    run_deployment
}

# Run main function
main "$@"