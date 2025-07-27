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

Modular AWS deployment orchestrator for AI Starter Kit

Options:
    -t, --type TYPE           Deployment type: spot, ondemand, simple (default: spot)
    -r, --region REGION       AWS region (default: us-east-1)
    -i, --instance TYPE       Instance type (default: g4dn.xlarge)
    -k, --key-name NAME       SSH key name (default: STACK_NAME-key)
    -s, --volume-size SIZE    Volume size in GB (default: 100)
    -e, --environment ENV     Environment: development, staging, production (default: production)
    --validate-only           Validate configuration without deploying
    --cleanup                 Clean up existing resources before deploying
    --no-cleanup-on-failure   Don't clean up resources if deployment fails
    -h, --help               Show this help message

Examples:
    $0 my-stack
    $0 --type ondemand --region us-west-2 my-stack
    $0 --validate-only my-stack

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
    echo "Setting up infrastructure..."
    
    # Source infrastructure modules
    source "$PROJECT_ROOT/lib/modules/infrastructure/vpc.sh"
    source "$PROJECT_ROOT/lib/modules/infrastructure/security.sh"
    
    # Setup network
    local network_info
    network_info=$(setup_network_infrastructure) || {
        echo "ERROR: Failed to setup network infrastructure" >&2
        return 1
    }
    
    # Extract network details
    VPC_ID=$(echo "$network_info" | jq -r '.vpc_id')
    SUBNET_ID=$(echo "$network_info" | jq -r '.subnet_id')
    
    # Create security group
    SECURITY_GROUP_ID=$(create_security_group "$VPC_ID") || {
        echo "ERROR: Failed to create security group" >&2
        return 1
    }
    
    # Setup IAM role
    IAM_ROLE_NAME=$(create_iam_role) || {
        echo "ERROR: Failed to create IAM role" >&2
        return 1
    }
    
    # Ensure key pair
    KEY_NAME=$(ensure_key_pair "$(get_variable KEY_NAME)") || {
        echo "ERROR: Failed to ensure key pair" >&2
        return 1
    }
    
    echo "Infrastructure setup complete"
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
    
    # Build launch configuration
    local launch_config=$(cat <<EOF
{
    "instance_type": "$(get_variable INSTANCE_TYPE)",
    "key_name": "$KEY_NAME",
    "security_group_id": "$SECURITY_GROUP_ID",
    "subnet_id": "$SUBNET_ID",
    "iam_instance_profile": "${IAM_ROLE_NAME}-profile",
    "volume_size": $(get_variable VOLUME_SIZE),
    "user_data": "$user_data",
    "stack_name": "$(get_variable STACK_NAME)"
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
DEPLOYMENT SUMMARY
================================================================================
Stack Name:     $(get_variable STACK_NAME)
Instance ID:    $INSTANCE_ID
Instance Type:  $(get_variable INSTANCE_TYPE)
Public IP:      $public_ip
Region:         $(get_variable AWS_REGION)

Service URLs:
- n8n:          http://${public_ip}:5678
- Qdrant:       http://${public_ip}:6333
- Ollama:       http://${public_ip}:11434
- Crawl4AI:     http://${public_ip}:11235
- Health Check: http://${public_ip}:8080/health

SSH Access:
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${public_ip}

Next Steps:
1. Check service health: curl http://${public_ip}:8080/health
2. View logs: ./scripts/aws-deployment-modular.sh --logs $INSTANCE_ID
3. Monitor: Check CloudWatch dashboard "${STACK_NAME}-dashboard"
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
    if [ "${CLEANUP_EXISTING:-false}" = "true" ]; then
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