#!/bin/bash
# Unity Deployment Wrapper - Main entry point for GeuseMaker deployments
# This is the sole deployment interface - all legacy systems have been migrated to Unity

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Unity system initialization
source "$SCRIPT_DIR/lib/unity/core/unity-core.sh" || {
    echo "Error: Failed to load Unity core system" >&2
    echo "Please ensure Unity is properly installed" >&2
    exit 1
}

# Initialize Unity
unity_init || {
    echo "Error: Failed to initialize Unity system" >&2
    exit 1
}

# Default values
DEPLOYMENT_TYPE="${1:-}"
STACK_NAME="${2:-geusemaker-dev}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Show usage
show_usage() {
    cat << EOF
GeuseMaker Unity Deployment System

Usage: $0 [deployment-type] [stack-name] [options]

Deployment Types:
  spot         Deploy spot instance with 70% cost savings (default)
  alb          Deploy with Application Load Balancer
  cdn          Deploy with CloudFront CDN
  full         Deploy complete stack (VPC + EC2 + ALB + CDN)
  destroy      Destroy all resources for the stack

Stack Name:
  Name for your deployment stack (default: geusemaker-dev)

Options:
  --environment, -e    Environment (dev/staging/prod) [default: dev]
  --region, -r         AWS region [default: us-east-1]
  --strategy, -s       Deployment strategy (rolling/blue-green/canary) [default: rolling]
  --dry-run           Perform validation without deploying
  --help, -h          Show this help message

Examples:
  $0 spot my-ai-stack                    # Deploy spot instance
  $0 alb prod-stack -e production        # Deploy ALB in production
  $0 full test-stack --strategy canary   # Full stack with canary deployment
  $0 destroy my-stack                    # Destroy stack

For more operations, use the Unity CLI:
  ./scripts/unity-cli.sh --help
EOF
}

# Parse command line arguments
parse_arguments() {
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --region|-r)
                AWS_REGION="$2"
                shift 2
                ;;
            --strategy|-s)
                DEPLOYMENT_STRATEGY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Restore positional parameters
    set -- "${args[@]}"
    
    # Set deployment type and stack name from remaining args
    DEPLOYMENT_TYPE="${1:-spot}"
    STACK_NAME="${2:-geusemaker-$ENVIRONMENT}"
    
    # Default strategy
    DEPLOYMENT_STRATEGY="${DEPLOYMENT_STRATEGY:-rolling}"
}

# Validate deployment type
validate_deployment_type() {
    local valid_types=("spot" "alb" "cdn" "full" "destroy")
    
    if [[ ! " ${valid_types[@]} " =~ " ${DEPLOYMENT_TYPE} " ]]; then
        echo "Error: Invalid deployment type: $DEPLOYMENT_TYPE" >&2
        echo "Valid types: ${valid_types[*]}" >&2
        show_usage
        exit 1
    fi
}

# Pre-flight checks
run_preflight_checks() {
    unity_log "INFO" "Running pre-flight checks..."
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        unity_log "ERROR" "AWS credentials not configured"
        echo "Please run: aws configure" >&2
        exit 1
    fi
    
    # Check required services
    local required_services=("aws" "docker" "config" "monitor")
    for service in "${required_services[@]}"; do
        if ! unity_discover_service "$service" >/dev/null 2>&1; then
            unity_log "ERROR" "Required Unity service not found: $service"
            exit 1
        fi
    done
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod|production)$ ]]; then
        unity_log "ERROR" "Invalid environment: $ENVIRONMENT"
        exit 1
    fi
    
    # Check for configuration
    if [[ ! -f "config/unity.yml" ]]; then
        unity_log "ERROR" "Unity configuration not found: config/unity.yml"
        exit 1
    fi
    
    unity_log "INFO" "Pre-flight checks passed"
}

# Initialize Unity services
initialize_services() {
    unity_log "INFO" "Initializing Unity services..."
    
    # Register core services
    unity_register_service "aws" "$SCRIPT_DIR/lib/unity/services/aws-service.sh" "core" "config"
    unity_register_service "docker" "$SCRIPT_DIR/lib/unity/services/docker-service.sh" "core" "config"
    unity_register_service "config" "$SCRIPT_DIR/lib/unity/services/config-service.sh" "core" ""
    unity_register_service "monitor" "$SCRIPT_DIR/lib/unity/services/monitor-service.sh" "core" "config,aws"
    unity_register_service "deployment" "$SCRIPT_DIR/lib/unity/services/unity-deployment-service.sh" "orchestration" "aws,docker,config,monitor"
    
    # Initialize services in dependency order
    unity_initialize_service "config" || {
        unity_log "ERROR" "Failed to initialize config service"
        exit 1
    }
    
    unity_initialize_service "aws" || {
        unity_log "ERROR" "Failed to initialize AWS service"
        exit 1
    }
    
    unity_initialize_service "docker" || {
        unity_log "ERROR" "Failed to initialize Docker service"
        exit 1
    }
    
    unity_initialize_service "monitor" || {
        unity_log "ERROR" "Failed to initialize monitor service"
        exit 1
    }
    
    unity_initialize_service "deployment" || {
        unity_log "ERROR" "Failed to initialize deployment service"
        exit 1
    }
    
    unity_log "INFO" "All services initialized successfully"
}

# Execute deployment
execute_deployment() {
    unity_log "INFO" "Starting deployment: type=$DEPLOYMENT_TYPE, stack=$STACK_NAME, env=$ENVIRONMENT"
    
    # Set deployment context
    export STACK_NAME
    export ENVIRONMENT
    export AWS_REGION
    export DEPLOYMENT_STRATEGY
    
    # Handle destroy separately
    if [[ "$DEPLOYMENT_TYPE" == "destroy" ]]; then
        unity_log "WARN" "Destroying stack: $STACK_NAME"
        
        # Confirm destruction
        if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
            read -p "Are you sure you want to destroy all resources for $STACK_NAME? (yes/no): " confirm
            if [[ "$confirm" != "yes" ]]; then
                unity_log "INFO" "Destruction cancelled"
                exit 0
            fi
        fi
        
        # Emit destroy event
        unity_emit_event "DEPLOYMENT_DESTROY_REQUESTED" "deploy.sh" "$STACK_NAME"
        
        # Wait for completion
        unity_log "INFO" "Destruction initiated. Monitor progress with: ./scripts/unity-cli.sh status"
        exit 0
    fi
    
    # Dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        unity_log "INFO" "DRY RUN MODE - Validating deployment configuration"
        unity_emit_event "DEPLOYMENT_VALIDATION_REQUESTED" "deploy.sh" "$DEPLOYMENT_TYPE:$STACK_NAME"
        exit 0
    fi
    
    # Execute deployment via deployment service
    unity_log "INFO" "Executing deployment via Unity deployment service"
    
    # Create deployment options
    local options="{\"environment\":\"$ENVIRONMENT\",\"region\":\"$AWS_REGION\",\"strategy\":\"$DEPLOYMENT_STRATEGY\"}"
    
    # Execute deployment
    if deployment_id=$(unity_deployment_execute "deploy" "$STACK_NAME" "$DEPLOYMENT_TYPE" "$DEPLOYMENT_STRATEGY" "$options"); then
        unity_log "INFO" "Deployment initiated with ID: $deployment_id"
        
        # Emit deployment requested event
        unity_emit_event "DEPLOYMENT_REQUESTED" "deploy.sh" "$DEPLOYMENT_TYPE:$STACK_NAME:$deployment_id"
        
        echo ""
        echo "Deployment started successfully!"
        echo "Deployment ID: $deployment_id"
        echo ""
        echo "Monitor progress with:"
        echo "  ./scripts/unity-cli.sh status $deployment_id"
        echo ""
        echo "View logs with:"
        echo "  ./scripts/unity-cli.sh logs $deployment_id"
        echo ""
        
        # Wait for initial status if not in background mode
        if [[ "${BACKGROUND:-false}" != "true" ]]; then
            sleep 3
            unity_deployment_execute "status" "$deployment_id"
        fi
    else
        unity_log "ERROR" "Failed to initiate deployment"
        exit 1
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Show banner
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               GeuseMaker Unity Deployment System              ║"
    echo "║                    Unified • Event-Driven • Smart             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Validate deployment type
    validate_deployment_type
    
    # Run pre-flight checks
    run_preflight_checks
    
    # Initialize services
    initialize_services
    
    # Execute deployment
    execute_deployment
}

# Run main function
main "$@"