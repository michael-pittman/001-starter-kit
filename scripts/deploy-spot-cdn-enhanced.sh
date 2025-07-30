#!/usr/bin/env bash
# =============================================================================
# Enhanced Spot + CDN Deployment Script
# Provides robust deployment with ALB/CloudFront integration and failure handling
# =============================================================================

set -euo pipefail

# Initialize library loader
SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

# Source the errors module
if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
    source "$LIB_DIR_TEMP/modules/core/errors.sh"
else
    # Fallback warning if errors module not found
    echo "WARNING: Could not load errors module" >&2
fi

# Source the library loader
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/utils/library-loader.sh"


# Initialize script with required modules
initialize_script "deploy-spot-cdn-enhanced.sh" \
    "core/variables" \
    "core/errors" \
    "core/registry" \
    "infrastructure/vpc" \
    "compute/core" \
    "infrastructure/alb" \
    "infrastructure/cloudfront"

# Initialize enhanced error handling
if declare -f init_enhanced_error_handling >/dev/null 2>&1; then
    init_enhanced_error_handling "auto" "true" "true"
else
    init_error_handling "strict"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default configuration
STACK_NAME=""
DEPLOYMENT_TYPE="spot"
ENABLE_ALB="true"
ENABLE_CLOUDFRONT="false"
FALLBACK_TO_BASIC="true"
VERBOSE="false"
DRY_RUN="false"
MAX_RETRIES=3
RETRY_DELAY=5

# Service dependencies
REQUIRED_SERVICES=(
    "ec2"
    "iam"
    "elbv2"
    "cloudformation"
)

OPTIONAL_SERVICES=(
    "cloudfront"
    "route53"
)

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] STACK_NAME

Enhanced deployment script for spot instances with ALB and optional CloudFront CDN.
Provides robust error handling and graceful fallback mechanisms.

Options:
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose output
    -d, --dry-run               Show what would be deployed without creating resources
    --no-alb                    Skip ALB creation (deployment will be basic)
    --enable-cloudfront         Enable CloudFront CDN distribution
    --no-fallback               Fail completely if ALB/CloudFront creation fails
    --max-retries NUM           Maximum retries for failed operations (default: 3)
    --region REGION             AWS region (default: us-east-1)
    --instance-type TYPE        Instance type (default: g4dn.xlarge)

Examples:
    # Basic spot deployment with ALB
    $0 my-stack

    # Spot deployment with ALB and CloudFront
    $0 --enable-cloudfront prod-stack

    # Dry run to see what would be created
    $0 --dry-run --enable-cloudfront test-stack

    # No fallback - fail if ALB can't be created
    $0 --no-fallback enterprise-stack

EOF
    exit "${1:-0}"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage 0
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            --no-alb)
                ENABLE_ALB="false"
                shift
                ;;
            --enable-cloudfront)
                ENABLE_CLOUDFRONT="true"
                shift
                ;;
            --no-fallback)
                FALLBACK_TO_BASIC="false"
                shift
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --region)
                export AWS_REGION="$2"
                export AWS_DEFAULT_REGION="$2"
                shift 2
                ;;
            --instance-type)
                export INSTANCE_TYPE="$2"
                shift 2
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                usage 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate stack name
    if [ ${#args[@]} -eq 0 ]; then
        echo "ERROR: Stack name is required" >&2
        usage 1
    fi
    
    STACK_NAME="${args[0]}"
}

# =============================================================================
# DEPENDENCY CHECKING
# =============================================================================

check_aws_permissions() {
    local service="$1"
    local test_action="$2"
    
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    log_info "Checking permissions for $service..."
    
    # Use more robust permission checks that don't rely on --dry-run
    local error_output
    case $service in
        iam)
            # For IAM: Use list-roles with max-items
            if error_output=$(aws iam list-roles --max-items 1 2>&1); then
                log_success "✓ Permissions verified for $service"
                return 0
            fi
            ;;
        elbv2)
            # For ELBV2: Use describe-load-balancers with max-items
            if error_output=$(aws elbv2 describe-load-balancers --max-items 1 2>&1); then
                log_success "✓ Permissions verified for $service"
                return 0
            fi
            ;;
        cloudformation)
            # For CloudFormation: Use list-stacks with max-items
            if error_output=$(aws cloudformation list-stacks --max-items 1 2>&1); then
                log_success "✓ Permissions verified for $service"
                return 0
            fi
            ;;
        ec2)
            # For EC2: Keep describe-instances approach
            if error_output=$(aws ec2 describe-instances --max-items 1 2>&1); then
                log_success "✓ Permissions verified for $service"
                return 0
            fi
            ;;
        cloudfront)
            # For CloudFront: Use list-distributions with max-items
            if error_output=$(aws cloudfront list-distributions --max-items 1 2>&1); then
                log_success "✓ Permissions verified for $service"
                return 0
            fi
            ;;
        *)
            # Default fallback for other services
            if aws $service $test_action >/dev/null 2>&1; then
                log_success "✓ Permissions verified for $service"
                return 0
            fi
            ;;
    esac
    
    # If we get here, the permission check failed
    log_error "✗ Insufficient permissions for $service"
    if [ -n "$error_output" ]; then
        log_error "Error: $error_output"
    fi
    return 1
}

validate_dependencies() {
    log_section "Validating AWS Service Dependencies"
    
    local failed_services=()
    
    # Check required services
    for service in "${REQUIRED_SERVICES[@]}"; do
        case $service in
            ec2)
                check_aws_permissions "ec2" "describe-instances" || failed_services+=("$service")
                ;;
            iam)
                check_aws_permissions "iam" "list-roles" || failed_services+=("$service")
                ;;
            elbv2)
                if [ "$ENABLE_ALB" = "true" ]; then
                    check_aws_permissions "elbv2" "describe-load-balancers" || failed_services+=("$service")
                fi
                ;;
            cloudformation)
                check_aws_permissions "cloudformation" "list-stacks" || failed_services+=("$service")
                ;;
        esac
    done
    
    # Check optional services
    if [ "$ENABLE_CLOUDFRONT" = "true" ]; then
        if ! check_aws_permissions "cloudfront" "list-distributions"; then
            log_warning "CloudFront permissions not available - disabling CloudFront integration"
            ENABLE_CLOUDFRONT="false"
        fi
    fi
    
    # Report results
    if [ ${#failed_services[@]} -gt 0 ]; then
        log_error "Missing permissions for required services: ${failed_services[*]}"
        log_error "Please ensure your IAM user/role has the necessary permissions"
        return 1
    fi
    
    log_success "All required dependencies validated"
    return 0
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

build_deployment_command() {
    local cmd="$PROJECT_ROOT/scripts/aws-deployment-modular.sh"
    local args=("--type" "$DEPLOYMENT_TYPE")
    
    # Add ALB flag if enabled
    if [ "$ENABLE_ALB" = "true" ]; then
        args+=("--alb")
    fi
    
    # Add multi-AZ for better ALB support
    if [ "$ENABLE_ALB" = "true" ]; then
        args+=("--multi-az")
    fi
    
    # Add region if specified
    if [ -n "${AWS_REGION:-}" ]; then
        args+=("--region" "$AWS_REGION")
    fi
    
    # Add instance type if specified
    if [ -n "${INSTANCE_TYPE:-}" ]; then
        args+=("--instance" "$INSTANCE_TYPE")
    fi
    
    # Add stack name
    args+=("$STACK_NAME")
    
    echo "$cmd ${args[*]}"
}

deploy_with_retries() {
    local cmd="$1"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Deployment attempt $attempt of $MAX_RETRIES..."
        
        if [ "$DRY_RUN" = "true" ]; then
            log_info "DRY RUN: Would execute: $cmd"
            return 0
        fi
        
        if eval "$cmd"; then
            log_success "Deployment succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            log_warning "Deployment attempt $attempt failed with exit code $exit_code"
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                log_info "Waiting ${RETRY_DELAY}s before retry..."
                sleep $RETRY_DELAY
                ((attempt++))
            else
                log_error "All deployment attempts failed"
                return $exit_code
            fi
        fi
    done
}

handle_alb_failure() {
    log_section "Handling ALB Creation Failure"
    
    if [ "$FALLBACK_TO_BASIC" = "true" ]; then
        log_warning "ALB creation failed - falling back to basic deployment"
        log_info "The stack will be deployed without load balancing"
        log_info "You can manually add an ALB later if needed"
        
        # Rebuild command without ALB
        ENABLE_ALB="false"
        local fallback_cmd=$(build_deployment_command)
        
        log_info "Attempting fallback deployment..."
        if deploy_with_retries "$fallback_cmd"; then
            log_success "Fallback deployment succeeded"
            log_warning "Note: Stack deployed without ALB - direct instance access only"
            return 0
        else
            log_error "Fallback deployment also failed"
            return 1
        fi
    else
        log_error "ALB creation failed and fallback is disabled"
        log_error "Use --no-fallback to allow deployment without ALB"
        return 1
    fi
}

setup_cloudfront() {
    if [ "$ENABLE_CLOUDFRONT" != "true" ]; then
        return 0
    fi
    
    log_section "Setting up CloudFront Distribution"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would create CloudFront distribution for ALB"
        return 0
    fi
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --names "${STACK_NAME}-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$alb_dns" ] || [ "$alb_dns" = "None" ]; then
        log_warning "No ALB found - skipping CloudFront setup"
        return 0
    fi
    
    log_info "Creating CloudFront distribution for ALB: $alb_dns"
    
    # Create CloudFront distribution configuration
    local dist_config=$(cat <<EOF
{
    "CallerReference": "${STACK_NAME}-$(date +%s)",
    "Comment": "CloudFront distribution for ${STACK_NAME}",
    "Enabled": true,
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "${STACK_NAME}-alb",
            "DomainName": "${alb_dns}",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only",
                "OriginSslProtocols": {
                    "Quantity": 3,
                    "Items": ["TLSv1", "TLSv1.1", "TLSv1.2"]
                }
            }
        }]
    },
    "DefaultRootObject": "",
    "DefaultCacheBehavior": {
        "TargetOriginId": "${STACK_NAME}-alb",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": { "Forward": "all" },
            "Headers": {
                "Quantity": 1,
                "Items": ["*"]
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0
    },
    "PriceClass": "PriceClass_100"
}
EOF
)
    
    # Create distribution
    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --query 'Distribution.Id' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$dist_id" ] && [ "$dist_id" != "None" ]; then
        log_success "CloudFront distribution created: $dist_id"
        
        # Get distribution domain
        local cf_domain
        cf_domain=$(aws cloudfront get-distribution \
            --id "$dist_id" \
            --query 'Distribution.DomainName' \
            --output text)
        
        log_success "CloudFront domain: https://$cf_domain"
        
        # Tag the distribution
        aws cloudfront tag-resource \
            --resource "arn:aws:cloudfront::$(aws sts get-caller-identity --query Account --output text):distribution/$dist_id" \
            --tags "Items=[{Key=Stack,Value=$STACK_NAME},{Key=Purpose,Value=CDN}]" || true
    else
        log_warning "Failed to create CloudFront distribution"
        log_info "You can manually create a CloudFront distribution later if needed"
    fi
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

print_deployment_plan() {
    log_section "Deployment Plan"
    
    echo "Stack Name:        $STACK_NAME"
    echo "Deployment Type:   $DEPLOYMENT_TYPE"
    echo "ALB Enabled:       $ENABLE_ALB"
    echo "CloudFront:        $ENABLE_CLOUDFRONT"
    echo "Fallback Mode:     $FALLBACK_TO_BASIC"
    echo "Region:            ${AWS_REGION:-us-east-1}"
    echo "Instance Type:     ${INSTANCE_TYPE:-g4dn.xlarge}"
    echo ""
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
}

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Print header
    clear_line
    log_header "Enhanced Spot + CDN Deployment"
    
    # Print deployment plan
    print_deployment_plan
    
    # Validate dependencies
    if ! validate_dependencies; then
        log_error "Dependency validation failed"
        exit 1
    fi
    
    # Build deployment command
    local deployment_cmd=$(build_deployment_command)
    
    log_section "Starting Deployment"
    log_info "Executing: $deployment_cmd"
    
    # Execute deployment with retries
    if deploy_with_retries "$deployment_cmd"; then
        log_success "Primary deployment completed successfully"
        
        # Setup CloudFront if enabled
        if [ "$ENABLE_CLOUDFRONT" = "true" ]; then
            setup_cloudfront
        fi
        
        # Print summary
        log_section "Deployment Summary"
        log_success "Stack '$STACK_NAME' deployed successfully"
        
        if [ "$ENABLE_ALB" = "true" ]; then
            local alb_dns
            alb_dns=$(aws elbv2 describe-load-balancers \
                --names "${STACK_NAME}-alb" \
                --query 'LoadBalancers[0].DNSName' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$alb_dns" ] && [ "$alb_dns" != "None" ]; then
                log_info "ALB Endpoint: http://$alb_dns"
            fi
        fi
        
        log_info ""
        log_info "Next steps:"
        log_info "1. Check deployment status: make status STACK_NAME=$STACK_NAME"
        log_info "2. View health check: make health-check STACK_NAME=$STACK_NAME"
        log_info "3. Access services via ALB endpoints"
        
    else
        # Handle deployment failure
        if [ "$ENABLE_ALB" = "true" ]; then
            # Check if failure was ALB-related
            if grep -q "ALB\|load.balancer\|target.group" "$PROJECT_ROOT/logs/deployment-${STACK_NAME}.log" 2>/dev/null; then
                handle_alb_failure
            else
                log_error "Deployment failed (non-ALB related issue)"
                exit 1
            fi
        else
            log_error "Deployment failed"
            exit 1
        fi
    fi
}

# =============================================================================
# LOGGING HELPERS
# =============================================================================

# Use standardized logging if available, otherwise fallback to custom functions
if command -v log_message >/dev/null 2>&1; then
    # Use standardized logging functions
    log_header() {
        echo ""
        echo "=============================================================="
        echo "$1"
        echo "=============================================================="
        echo ""
    }
    
    log_section() {
        echo ""
        echo ">>> $1"
        echo "--------------------------------------------------------------"
    }
    
    log_info() { log_message "INFO" "$1" "DEPLOYMENT"; }
    log_success() { log_message "INFO" "$1" "DEPLOYMENT"; }  # Use INFO level for success
    log_warning() { log_message "WARN" "$1" "DEPLOYMENT"; }
    log_error() { log_message "ERROR" "$1" "DEPLOYMENT"; }
else
    # Fallback to custom logging functions
    log_header() {
        echo ""
        echo "=============================================================="
        echo "$1"
        echo "=============================================================="
        echo ""
    }
    
    log_section() {
        echo ""
        echo ">>> $1"
        echo "--------------------------------------------------------------"
    }
    
    log_info() {
        echo "ℹ️  $1"
    }
    
    log_success() {
        echo "✅ $1"
    }
    
    log_warning() {
        echo "⚠️  $1"
    }
    
    log_error() {
        echo "❌ $1" >&2
    }
fi

clear_line() {
    printf "\033[2K\r"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Execute main function
main "$@"