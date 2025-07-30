#!/usr/bin/env bash
# =============================================================================
# GeuseMaker Deployment Orchestrator
# Main entry point for all deployment operations
# =============================================================================

set -euo pipefail

# Initialize library loader
SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TEMP="$SCRIPT_DIR_TEMP/lib"

# Source the errors module
if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
    source "$LIB_DIR_TEMP/modules/core/errors.sh"
else
    # Fallback warning if errors module not found
    echo "WARNING: Could not load errors module" >&2
fi

# Prevent multiple sourcing
[ -n "${_DEPLOY_SH_LOADED:-}" ] && return 0
_DEPLOY_SH_LOADED=1

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Script metadata
SCRIPT_NAME="deploy.sh"
SCRIPT_VERSION="2.1.0"  # Enhanced with comprehensive error handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"

# Configuration paths
CONFIG_DIR="${SCRIPT_DIR}/config"
ENV_DIR="${CONFIG_DIR}/environments"

# Logging configuration
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# COMPREHENSIVE ERROR HANDLING SETUP
# =============================================================================

# Enable strict error handling
set -euo pipefail

# Set up global error trap
trap 'error_trap $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "%s " "${FUNCNAME[@]}")' ERR

# Global error trap handler
error_trap() {
    local exit_code=$1
    local line_number=$2
    local bash_line_number=$3
    local last_command=$4
    local func_stack=($5)
    
    # Don't trigger on expected failures
    if [[ "${EXPECTED_FAILURE:-false}" == "true" ]]; then
        return 0
    fi
    
    echo "ERROR: Command failed with exit code $exit_code" >&2
    echo "  Command: $last_command" >&2
    echo "  Location: Line $line_number" >&2
    echo "  Function stack: ${func_stack[*]}" >&2
    
    # Log to error file if available
    if [[ -n "${ERROR_LOG_FILE:-}" ]]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: Exit $exit_code at line $line_number: $last_command" >> "$ERROR_LOG_FILE"
    fi
}

# =============================================================================
# EARLY ARGUMENT HANDLING
# =============================================================================

# Check for help or version before loading libraries
for arg in "$@"; do
    case $arg in
        --help|-h)
            # Define show_usage inline for help
            cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - GeuseMaker Deployment Orchestrator

USAGE:
    ${SCRIPT_NAME} [OPTIONS] <stack-name>
    ${SCRIPT_NAME} --type <deployment-type> <stack-name>

DEPLOYMENT TYPES:
    --type spot                 Cost-optimized deployment with spot instances (70% savings)
    --type alb                  High-availability deployment with Application Load Balancer
    --type cdn                  Global deployment with CloudFront CDN (includes ALB)
    --type full                 Full-featured enterprise deployment (all components)

EXAMPLES:
    # Interactive deployment type selection
    ${SCRIPT_NAME} my-stack

    # Spot deployment for cost optimization
    ${SCRIPT_NAME} --type spot my-stack

    # ALB deployment for high availability
    ${SCRIPT_NAME} --type alb my-stack

    # CDN deployment for global reach
    ${SCRIPT_NAME} --type cdn my-stack

    # Full enterprise deployment
    ${SCRIPT_NAME} --type full my-stack

    # Custom deployment with specific features
    ${SCRIPT_NAME} --spot --alb --monitoring my-stack

OPTIONS:
    --stack-name, -s <name>     Stack name (required)
    --type, -t <type>           Deployment type (spot|alb|cdn|full)
    --region, -r <region>       AWS region (default: us-east-1)
    --profile, -p <profile>     AWS profile (default: default)
    --env, -e <environment>     Environment (default: development)
    
    # Quick Deployment Presets
    --dev                       Development deployment (single AZ, on-demand)
    --prod                      Production deployment (multi-AZ, spot)
    --enterprise               Enterprise deployment (all features)
    
    # Infrastructure Components (for custom configurations)
    --alb                      Enable Application Load Balancer
    --cdn                      Enable CloudFront CDN
    --efs                      Enable EFS file system
    --multi-az                 Enable multi-AZ deployment
    --spot                     Use spot instances for cost optimization
    --monitoring               Enable enhanced monitoring
    --backup                   Enable automated backups
    
    # Advanced Options
    --dry-run                  Show what would be deployed without executing
    --validate                 Validate configuration only
    --rollback                 Rollback to previous deployment
    --destroy                  Destroy existing deployment
    --status                   Show deployment status
    --logs                     Show deployment logs
    
    # Infrastructure Configuration
    --vpc-cidr <cidr>         VPC CIDR block (default: 10.0.0.0/16)
    --public-subnets <list>   Comma-separated list of public subnet CIDRs
    --private-subnets <list>  Comma-separated list of private subnet CIDRs
    --instance-type <type>    EC2 instance type (default: t3.micro)
    --min-capacity <num>      Minimum capacity for auto scaling (default: 1)
    --max-capacity <num>      Maximum capacity for auto scaling (default: 3)
    --efs-encryption          Enable EFS encryption (default: true)
    --alb-internal            Create internal ALB (default: false)
    --cloudfront-price-class <class> CloudFront price class (default: PriceClass_100)
    
    --help, -h                 Show this help message
    --version, -v              Show version information

DEPLOYMENT TYPE DETAILS:
    spot:  • Spot instances (70% cost savings)
           • EFS file system for shared storage
           • Auto-scaling enabled
           • Single AZ deployment
           • Best for: Cost-sensitive workloads, batch processing
           
    alb:   • Application Load Balancer
           • Spot instances for cost optimization
           • CloudFront CDN for global delivery
           • EFS file system for shared storage
           • Single AZ deployment
           • Health checks and monitoring
           • Best for: High-availability production workloads
           
    cdn:   • CloudFront CDN (includes ALB)
           • EFS file system for shared storage
           • Global edge locations
           • Single AZ deployment
           • Caching and optimization
           • Best for: Global applications, static content
           
    full:  • All features enabled
           • Spot instances + ALB + CDN + EFS
           • Single AZ deployment
           • Enterprise monitoring and backup
           • Best for: Mission-critical enterprise applications

ENVIRONMENT VARIABLES:
    AWS_DEFAULT_REGION         Default AWS region
    AWS_PROFILE               Default AWS profile
    DEPLOYMENT_ENVIRONMENT    Default deployment environment
    LOG_LEVEL                Logging level (DEBUG, INFO, WARN, ERROR)

EXIT CODES:
    0  - Success
    1  - General error
    2  - Configuration error
    3  - AWS API error
    4  - Validation error
    5  - Rollback error

EOF
            exit 0
            ;;
        --version|-v)
            echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
            echo "GeuseMaker Deployment Orchestrator"
            echo "Built with modular architecture and uniform coding standards"
            exit 0
            ;;
    esac
done

# =============================================================================
# DEPENDENCY LOADING
# =============================================================================

# Load the library loader
source "${PROJECT_ROOT}/lib/utils/library-loader.sh"

# Define required modules for deployment orchestrator
REQUIRED_MODULES=(
    # Core modules
    "core/variables"
    "core/errors"
    "core/logging"
    "core/validation"
    
    # Deployment modules
    "deployment/orchestrator"
    "deployment/rollback"
    "deployment/state"
    
    # Infrastructure modules
    "infrastructure/vpc"
    "compute/core"
    "infrastructure/alb"
    "infrastructure/cloudfront"
    "infrastructure/efs"
    "infrastructure/security"
    
    # Monitoring modules
    "monitoring/health"
    "monitoring/metrics"
)

# Initialize script with all required modules
if ! initialize_script "deploy.sh" "${REQUIRED_MODULES[@]}"; then
    echo "Error: Failed to initialize deployment orchestrator" >&2
    exit 1
fi

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Deployment state
DEPLOYMENT_STATE=""
DEPLOYMENT_START_TIME=""
DEPLOYMENT_ERRORS=()
DEPLOYMENT_ROLLBACK_POINTS=()
CREATED_RESOURCES=()

# Configuration
STACK_NAME=""
DEPLOYMENT_TYPE=""
AWS_REGION=""
AWS_PROFILE=""

# Error handling configuration
ERROR_RECOVERY_MODE="automatic"  # automatic, manual, abort
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=30
ENABLE_PARTIAL_ROLLBACK=true

# Feature flags
ENABLE_ALB=false
ENABLE_CDN=false
ENABLE_EFS=false
ENABLE_MULTI_AZ=false
ENABLE_SPOT=false
ENABLE_MONITORING=false
ENABLE_BACKUP=false

# Infrastructure configuration
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNETS=""
PRIVATE_SUBNETS=""
INSTANCE_TYPE="t3.micro"
MIN_CAPACITY=1
MAX_CAPACITY=3
EFS_ENCRYPTION=true
ALB_INTERNAL=false
CLOUDFRONT_PRICE_CLASS="PriceClass_100"

# =============================================================================
# USAGE AND HELP
# =============================================================================

show_usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - GeuseMaker Deployment Orchestrator

USAGE:
    ${SCRIPT_NAME} [OPTIONS] <stack-name>
    ${SCRIPT_NAME} --type <deployment-type> <stack-name>

DEPLOYMENT TYPES:
    --type spot                 Cost-optimized deployment with spot instances (70% savings)
    --type alb                  High-availability deployment with Application Load Balancer
    --type cdn                  Global deployment with CloudFront CDN (includes ALB)
    --type full                 Full-featured enterprise deployment (all components)

EXAMPLES:
    # Interactive deployment type selection
    ${SCRIPT_NAME} my-stack

    # Spot deployment for cost optimization
    ${SCRIPT_NAME} --type spot my-stack

    # ALB deployment for high availability
    ${SCRIPT_NAME} --type alb my-stack

    # CDN deployment for global reach
    ${SCRIPT_NAME} --type cdn my-stack

    # Full enterprise deployment
    ${SCRIPT_NAME} --type full my-stack

    # Custom deployment with specific features
    ${SCRIPT_NAME} --spot --alb --monitoring my-stack

OPTIONS:
    --stack-name, -s <name>     Stack name (required)
    --type, -t <type>           Deployment type (spot|alb|cdn|full)
    --region, -r <region>       AWS region (default: us-east-1)
    --profile, -p <profile>     AWS profile (default: default)
    --env, -e <environment>     Environment (default: development)
    
    # Quick Deployment Presets
    --dev                       Development deployment (single AZ, on-demand)
    --prod                      Production deployment (multi-AZ, spot)
    --enterprise               Enterprise deployment (all features)
    
    # Infrastructure Components (for custom configurations)
    --alb                      Enable Application Load Balancer
    --cdn                      Enable CloudFront CDN
    --efs                      Enable EFS file system
    --multi-az                 Enable multi-AZ deployment
    --spot                     Use spot instances for cost optimization
    --monitoring               Enable enhanced monitoring
    --backup                   Enable automated backups
    
    # Advanced Options
    --dry-run                  Show what would be deployed without executing
    --validate                 Validate configuration only
    --rollback                 Rollback to previous deployment
    --destroy                  Destroy existing deployment
    --status                   Show deployment status
    --logs                     Show deployment logs
    
    # Infrastructure Configuration
    --vpc-cidr <cidr>         VPC CIDR block (default: 10.0.0.0/16)
    --public-subnets <list>   Comma-separated list of public subnet CIDRs
    --private-subnets <list>  Comma-separated list of private subnet CIDRs
    --instance-type <type>    EC2 instance type (default: t3.micro)
    --min-capacity <num>      Minimum capacity for auto scaling (default: 1)
    --max-capacity <num>      Maximum capacity for auto scaling (default: 3)
    --efs-encryption          Enable EFS encryption (default: true)
    --alb-internal            Create internal ALB (default: false)
    --cloudfront-price-class <class> CloudFront price class (default: PriceClass_100)
    
    --help, -h                 Show this help message
    --version, -v              Show version information

DEPLOYMENT TYPE DETAILS:
    spot:  • Spot instances (70% cost savings)
           • EFS file system for shared storage
           • Auto-scaling enabled
           • Single AZ deployment
           • Best for: Cost-sensitive workloads, batch processing
           
    alb:   • Application Load Balancer
           • Spot instances for cost optimization
           • CloudFront CDN for global delivery
           • EFS file system for shared storage
           • Single AZ deployment
           • Health checks and monitoring
           • Best for: High-availability production workloads
           
    cdn:   • CloudFront CDN (includes ALB)
           • EFS file system for shared storage
           • Global edge locations
           • Single AZ deployment
           • Caching and optimization
           • Best for: Global applications, static content
           
    full:  • All features enabled
           • Spot instances + ALB + CDN + EFS
           • Single AZ deployment
           • Enterprise monitoring and backup
           • Best for: Mission-critical enterprise applications

ENVIRONMENT VARIABLES:
    AWS_DEFAULT_REGION         Default AWS region
    AWS_PROFILE               Default AWS profile
    DEPLOYMENT_ENVIRONMENT    Default deployment environment
    LOG_LEVEL                Logging level (DEBUG, INFO, WARN, ERROR)

EXIT CODES:
    0  - Success
    1  - General error
    2  - Configuration error
    3  - AWS API error
    4  - Validation error
    5  - Rollback error

EOF
}

show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "GeuseMaker Deployment Orchestrator"
    echo "Built with modular architecture and uniform coding standards"
}

# =============================================================================
# DEPLOYMENT TYPE SELECTION
# =============================================================================

select_deployment_type() {
    echo ""
    echo "=========================================="
    echo "GeuseMaker Deployment Type Selection"
    echo "=========================================="
    echo ""
    echo "Available deployment types:"
    echo ""
    echo "  1) spot  - Cost-optimized (70% savings)"
    echo "             • Spot instances with auto-scaling"
    echo "             • EFS file system for shared storage"
    echo "             • Single AZ deployment"
    echo "             • Best for: Cost-sensitive workloads"
    echo ""
    echo "  2) alb   - High availability with CDN"
    echo "             • Application Load Balancer"
    echo "             • Spot instances for cost optimization"
    echo "             • CloudFront CDN for global delivery"
    echo "             • EFS file system for shared storage"
    echo "             • Single AZ deployment"
    echo "             • Best for: Production workloads"
    echo ""
    echo "  3) cdn   - Global distribution"
    echo "             • CloudFront CDN + ALB"
    echo "             • EFS file system for shared storage"
    echo "             • Single AZ deployment"
    echo "             • Edge caching"
    echo "             • Best for: Global applications"
    echo ""
    echo "  4) full  - Enterprise features"
    echo "             • All components enabled"
    echo "             • Spot + ALB + CDN + EFS"
    echo "             • Single AZ deployment"
    echo "             • Best for: Mission-critical apps"
    echo ""
    echo "=========================================="
    echo ""
    
    local selection
    while true; do
        read -p "Select deployment type (1-4): " selection
        case $selection in
            1|spot)
                DEPLOYMENT_TYPE="spot"
                configure_spot_deployment
                break
                ;;
            2|alb)
                DEPLOYMENT_TYPE="alb"
                configure_alb_deployment
                break
                ;;
            3|cdn)
                DEPLOYMENT_TYPE="cdn"
                configure_cdn_deployment
                break
                ;;
            4|full)
                DEPLOYMENT_TYPE="full"
                configure_full_deployment
                break
                ;;
            *)
                echo "Invalid selection. Please choose 1-4."
                ;;
        esac
    done
    
    echo ""
    echo "Selected deployment type: $DEPLOYMENT_TYPE"
    echo ""
}

configure_spot_deployment() {
    ENABLE_SPOT=true
    ENABLE_MULTI_AZ=false
    ENABLE_EFS=true
    MIN_CAPACITY=2
    MAX_CAPACITY=10
    INSTANCE_TYPE="g4dn.xlarge"
}

configure_alb_deployment() {
    ENABLE_ALB=true
    ENABLE_SPOT=true
    ENABLE_CDN=true
    ENABLE_MULTI_AZ=false
    ENABLE_EFS=true
    ENABLE_MONITORING=true
    MIN_CAPACITY=2
    MAX_CAPACITY=8
    INSTANCE_TYPE="g4dn.xlarge"
}

configure_cdn_deployment() {
    ENABLE_ALB=true
    ENABLE_CDN=true
    ENABLE_MULTI_AZ=false
    ENABLE_EFS=true
    ENABLE_MONITORING=true
    MIN_CAPACITY=2
    MAX_CAPACITY=8
    INSTANCE_TYPE="g4dn.xlarge"
}

configure_full_deployment() {
    ENABLE_SPOT=true
    ENABLE_ALB=true
    ENABLE_CDN=true
    ENABLE_EFS=true
    ENABLE_MULTI_AZ=false
    ENABLE_MONITORING=true
    ENABLE_BACKUP=true
    MIN_CAPACITY=2
    MAX_CAPACITY=10
    INSTANCE_TYPE="g4dn.xlarge"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    local args=("$@")
    local stack_name_provided=false
    local deployment_type_provided=false
    
    # Default values
    AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    AWS_PROFILE="${AWS_PROFILE:-default}"
    DEPLOYMENT_TYPE=""
    ENVIRONMENT="${DEPLOYMENT_ENVIRONMENT:-development}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            # Stack name
            --stack-name|-s)
                STACK_NAME="$2"
                stack_name_provided=true
                shift 2
                ;;
            
            # Deployment type
            --type|-t)
                DEPLOYMENT_TYPE="$2"
                deployment_type_provided=true
                # Validate deployment type
                case $DEPLOYMENT_TYPE in
                    spot|alb|cdn|full)
                        # Valid type, will configure after libraries are loaded
                        ;;
                    *)
                        echo "Error: Invalid deployment type: $DEPLOYMENT_TYPE" >&2
                        echo "Valid types: spot, alb, cdn, full" >&2
                        exit 2
                        ;;
                esac
                shift 2
                ;;
            
            # AWS configuration
            --region|-r)
                AWS_REGION="$2"
                shift 2
                ;;
            --profile|-p)
                AWS_PROFILE="$2"
                shift 2
                ;;
            
            # Environment
            --env|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            
            # Quick deployment presets
            --dev)
                DEPLOYMENT_TYPE="development"
                deployment_type_provided=true
                ENABLE_SPOT=false
                ENABLE_MULTI_AZ=false
                ENABLE_EFS=true
                shift
                ;;
            --prod)
                DEPLOYMENT_TYPE="production"
                deployment_type_provided=true
                ENABLE_SPOT=true
                ENABLE_MULTI_AZ=false
                ENABLE_EFS=true
                ENABLE_MONITORING=true
                shift
                ;;
            --enterprise)
                DEPLOYMENT_TYPE="enterprise"
                deployment_type_provided=true
                ENABLE_SPOT=true
                ENABLE_MULTI_AZ=false
                ENABLE_ALB=true
                ENABLE_CDN=true
                ENABLE_EFS=true
                ENABLE_MONITORING=true
                ENABLE_BACKUP=true
                shift
                ;;
            
            # Infrastructure components
            --alb)
                ENABLE_ALB=true
                shift
                ;;
            --cdn)
                ENABLE_CDN=true
                shift
                ;;
            --efs)
                ENABLE_EFS=true
                shift
                ;;
            --multi-az)
                ENABLE_MULTI_AZ=true
                shift
                ;;
            --spot)
                ENABLE_SPOT=true
                shift
                ;;
            --monitoring)
                ENABLE_MONITORING=true
                shift
                ;;
            --backup)
                ENABLE_BACKUP=true
                shift
                ;;
            
            # Advanced Options
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --validate)
                VALIDATE_ONLY=true
                shift
                ;;
            --rollback)
                ROLLBACK_MODE=true
                shift
                ;;
            --destroy)
                DESTROY_MODE=true
                shift
                ;;
            --status)
                STATUS_MODE=true
                shift
                ;;
            --logs)
                LOGS_MODE=true
                shift
                ;;
            
            # Infrastructure Configuration
            --vpc-cidr)
                VPC_CIDR="$2"
                shift 2
                ;;
            --public-subnets)
                PUBLIC_SUBNETS="$2"
                shift 2
                ;;
            --private-subnets)
                PRIVATE_SUBNETS="$2"
                shift 2
                ;;
            --instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --min-capacity)
                MIN_CAPACITY="$2"
                shift 2
                ;;
            --max-capacity)
                MAX_CAPACITY="$2"
                shift 2
                ;;
            --efs-encryption)
                EFS_ENCRYPTION="$2"
                shift 2
                ;;
            --alb-internal)
                ALB_INTERNAL="$2"
                shift 2
                ;;
            --cloudfront-price-class)
                CLOUDFRONT_PRICE_CLASS="$2"
                shift 2
                ;;
            
            # Help and version
            --help|-h)
                show_usage
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            
            # Unknown option
            -*)
                echo "Error: Unknown option: $1" >&2
                show_usage
                exit 2
                ;;
            
            # Positional argument (stack name)
            *)
                if [[ "$stack_name_provided" == false ]]; then
                    STACK_NAME="$1"
                    stack_name_provided=true
                else
                    echo "Error: Multiple stack names provided: $STACK_NAME and $1" >&2
                    exit 2
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$STACK_NAME" ]]; then
        echo "Error: Stack name is required" >&2
        show_usage
        exit 2
    fi
    
    # Validate stack name format
    if [[ ! "$STACK_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{2,30}$ ]]; then
        echo "Error: Invalid stack name: $STACK_NAME (must be 3-30 chars, start with letter, contain only letters, numbers, and hyphens)" >&2
        exit 2
    fi
    
    # If no deployment type provided and not in special modes, show interactive selection
    if [[ -z "$DEPLOYMENT_TYPE" && "$deployment_type_provided" == false ]]; then
        if [[ "${DESTROY_MODE:-false}" != true && "${ROLLBACK_MODE:-false}" != true && \
              "${STATUS_MODE:-false}" != true && "${LOGS_MODE:-false}" != true && \
              "${VALIDATE_ONLY:-false}" != true ]]; then
            select_deployment_type
        fi
    fi
    
    # Configure deployment type if provided
    if [[ -n "$DEPLOYMENT_TYPE" ]]; then
        case $DEPLOYMENT_TYPE in
            spot)
                configure_spot_deployment
                ;;
            alb)
                configure_alb_deployment
                ;;
            cdn)
                configure_cdn_deployment
                ;;
            full)
                configure_full_deployment
                ;;
        esac
    fi
}

# =============================================================================
# ERROR HANDLING HELPERS
# =============================================================================

# Register created resource for cleanup
register_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_region="${3:-$AWS_REGION}"
    
    CREATED_RESOURCES+=("${resource_type}:${resource_id}:${resource_region}")
    log_debug "Registered resource for cleanup: $resource_type ($resource_id)"
}

# Add rollback point
add_rollback_point() {
    local rollback_point="$1"
    local rollback_data="${2:-}"
    
    DEPLOYMENT_ROLLBACK_POINTS+=("${rollback_point}:${rollback_data}")
    log_debug "Added rollback point: $rollback_point"
}

# Handle deployment error with recovery
handle_deployment_error() {
    local error_code="$1"
    local error_message="$2"
    local error_context="${3:-}"
    local recovery_action="${4:-abort}"
    
    # Log structured error
    log_structured_error "$error_code" "$error_message" \
        "$ERROR_CAT_INFRASTRUCTURE" "$ERROR_SEVERITY_ERROR" \
        "$error_context" "$recovery_action"
    
    # Add to deployment errors
    DEPLOYMENT_ERRORS+=("$error_code:$error_message")
    
    # Execute recovery action
    case "$recovery_action" in
        retry)
            return 1  # Signal retry
            ;;
        rollback)
            log_error "Initiating rollback due to error: $error_message"
            execute_deployment_rollback
            exit 5
            ;;
        skip)
            log_warning "Skipping error and continuing: $error_message"
            return 0
            ;;
        abort|*)
            log_error "Aborting deployment due to error: $error_message"
            execute_emergency_cleanup
            exit 1
            ;;
    esac
}

# Retry operation with exponential backoff
retry_with_backoff() {
    local operation="$1"
    local max_attempts="${2:-$MAX_RETRY_ATTEMPTS}"
    local base_delay="${3:-$RETRY_DELAY}"
    
    local attempt=1
    local delay=$base_delay
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempting operation: $operation (attempt $attempt/$max_attempts)"
        
        if eval "$operation"; then
            log_info "Operation succeeded: $operation"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Operation failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Operation failed after $max_attempts attempts: $operation"
    return 1
}

# =============================================================================
# INITIALIZATION
# =============================================================================

initialize_deployment() {
    log_info "Initializing deployment orchestrator"
    
    # Create required directories
    mkdir -p "${LOG_DIR}" || {
        echo "ERROR: Failed to create log directory: ${LOG_DIR}" >&2
        exit 1
    }
    mkdir -p "${CONFIG_DIR}/temp" || {
        echo "ERROR: Failed to create temp directory: ${CONFIG_DIR}/temp" >&2
        exit 1
    }
    
    # Initialize logging with error handling
    if ! init_logging "${LOG_FILE}"; then
        echo "ERROR: Failed to initialize logging" >&2
        exit 1
    fi
    
    # Initialize error tracking
    initialize_error_tracking
    
    # Set deployment start time
    DEPLOYMENT_START_TIME=$(date +%s)
    
    # Initialize deployment state with error handling
    if ! init_deployment_state "${STACK_NAME}" "${AWS_REGION}"; then
        handle_deployment_error "INIT_STATE_FAILED" \
            "Failed to initialize deployment state" \
            "stack=$STACK_NAME,region=$AWS_REGION" \
            "abort"
    fi
    
    # Initialize state management
    if ! init_state_management "${STACK_NAME}"; then
        handle_deployment_error "INIT_STATE_MGMT_FAILED" \
            "Failed to initialize state management" \
            "stack=$STACK_NAME" \
            "abort"
    fi
    
    # Load environment configuration
    if ! load_environment_config "${ENVIRONMENT}"; then
        handle_deployment_error "LOAD_CONFIG_FAILED" \
            "Failed to load environment configuration" \
            "environment=$ENVIRONMENT" \
            "abort"
    fi
    
    # Validate AWS credentials with retry
    if ! retry_with_backoff "validate_aws_credentials '${AWS_PROFILE}' '${AWS_REGION}'" 3 10; then
        handle_deployment_error "AWS_CREDS_INVALID" \
            "Failed to validate AWS credentials" \
            "profile=$AWS_PROFILE,region=$AWS_REGION" \
            "abort"
    fi
    
    # Add initialization rollback point
    add_rollback_point "initialization_complete" "timestamp=$(date +%s)"
    
    log_info "Deployment orchestrator initialized successfully"
}

# =============================================================================
# DEPLOYMENT STATE MANAGEMENT
# =============================================================================

# Initialize deployment state
init_deployment_state() {
    local stack_name="$1"
    local region="$2"
    
    log_info "Initializing deployment state for stack: $stack_name"
    
    # Initialize variable store
    init_variable_store "$stack_name" "${ENVIRONMENT:-dev}"
    
    # Set basic deployment variables
    set_variable "STACK_NAME" "$stack_name" "$VARIABLE_SCOPE_STACK"
    set_variable "AWS_REGION" "$region" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_TYPE" "$DEPLOYMENT_TYPE" "$VARIABLE_SCOPE_STACK"
    set_variable "ENVIRONMENT" "${ENVIRONMENT:-dev}" "$VARIABLE_SCOPE_STACK"
    
    # Set feature flags
    set_variable "ENABLE_ALB" "$ENABLE_ALB" "$VARIABLE_SCOPE_STACK"
    set_variable "ENABLE_CDN" "$ENABLE_CDN" "$VARIABLE_SCOPE_STACK"
    set_variable "ENABLE_EFS" "$ENABLE_EFS" "$VARIABLE_SCOPE_STACK"
    set_variable "ENABLE_MULTI_AZ" "$ENABLE_MULTI_AZ" "$VARIABLE_SCOPE_STACK"
    set_variable "ENABLE_SPOT" "$ENABLE_SPOT" "$VARIABLE_SCOPE_STACK"
    set_variable "ENABLE_MONITORING" "$ENABLE_MONITORING" "$VARIABLE_SCOPE_STACK"
    
    # Set infrastructure configuration
    set_variable "VPC_CIDR" "$VPC_CIDR" "$VARIABLE_SCOPE_STACK"
    set_variable "PUBLIC_SUBNETS" "$PUBLIC_SUBNETS" "$VARIABLE_SCOPE_STACK"
    set_variable "PRIVATE_SUBNETS" "$PRIVATE_SUBNETS" "$VARIABLE_SCOPE_STACK"
    set_variable "INSTANCE_TYPE" "$INSTANCE_TYPE" "$VARIABLE_SCOPE_STACK"
    set_variable "MIN_CAPACITY" "$MIN_CAPACITY" "$VARIABLE_SCOPE_STACK"
    set_variable "MAX_CAPACITY" "$MAX_CAPACITY" "$VARIABLE_SCOPE_STACK"
    set_variable "EFS_ENCRYPTION" "$EFS_ENCRYPTION" "$VARIABLE_SCOPE_STACK"
    set_variable "ALB_INTERNAL" "$ALB_INTERNAL" "$VARIABLE_SCOPE_STACK"
    set_variable "CLOUDFRONT_PRICE_CLASS" "$CLOUDFRONT_PRICE_CLASS" "$VARIABLE_SCOPE_STACK"
    
    log_info "Deployment state initialized successfully"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_deployment_configuration() {
    log_info "Validating deployment configuration"
    
    local validation_errors=()
    
    # Validate AWS configuration with error handling
    if ! validate_aws_configuration "${AWS_REGION}" "${AWS_PROFILE}"; then
        validation_errors+=("AWS configuration validation failed")
    fi
    
    # Validate deployment parameters
    if ! validate_deployment_parameters; then
        validation_errors+=("Deployment parameter validation failed")
    fi
    
    # Validate feature compatibility
    if ! validate_feature_compatibility; then
        validation_errors+=("Feature compatibility validation failed")
    fi
    
    # Validate quotas with retry for transient API errors
    if ! retry_with_backoff "validate_aws_quotas '${AWS_REGION}' '${DEPLOYMENT_TYPE}'" 2 15; then
        validation_errors+=("AWS quota validation failed")
    fi
    
    # Check if any validation errors occurred
    if [ ${#validation_errors[@]} -gt 0 ]; then
        log_error "Validation failed with ${#validation_errors[@]} errors:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        
        handle_deployment_error "VALIDATION_FAILED" \
            "Deployment validation failed with ${#validation_errors[@]} errors" \
            "errors=${#validation_errors[@]}" \
            "abort"
    fi
    
    # Add validation rollback point
    add_rollback_point "validation_complete" "timestamp=$(date +%s)"
    
    log_info "Configuration validation completed successfully"
}

validate_deployment_parameters() {
    local errors=()
    
    # Check required parameters
    [[ -z "$STACK_NAME" ]] && errors+=("Stack name is required")
    [[ -z "$AWS_REGION" ]] && errors+=("AWS region is required")
    [[ -z "$AWS_PROFILE" ]] && errors+=("AWS profile is required")
    
    # Check parameter formats
    [[ ! "$STACK_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{2,30}$ ]] && \
        errors+=("Invalid stack name format: $STACK_NAME")
    
    # Check for errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_error "$error"
        done
        exit 2
    fi
}

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
    
    # Check for errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_error "$error"
        done
        exit 2
    fi
}

# =============================================================================
# EXISTING RESOURCES SETUP
# =============================================================================

# Setup existing resources if configured
setup_existing_resources_for_deployment() {
    log_info "Setting up existing resources for deployment"
    
    # Load existing resources module
    source "${LIB_DIR}/modules/infrastructure/existing-resources.sh"
    
    # Setup existing resources
    if ! setup_existing_resources "${STACK_NAME}" "${ENVIRONMENT}"; then
        log_error "Failed to setup existing resources"
        return 1
    fi
    
    return 0
}

# =============================================================================
# DEPLOYMENT OPERATIONS
# =============================================================================

execute_deployment() {
    log_info "Starting deployment execution"
    
    # Set deployment state
    set_deployment_state "${STACK_NAME}" "IN_PROGRESS"
    
    # Execute deployment based on mode
    if [[ "${DESTROY_MODE:-false}" == true ]]; then
        execute_destroy
    elif [[ "${ROLLBACK_MODE:-false}" == true ]]; then
        execute_rollback
    elif [[ "${STATUS_MODE:-false}" == true ]]; then
        execute_status_check
    elif [[ "${LOGS_MODE:-false}" == true ]]; then
        execute_logs_view
    elif [[ "${VALIDATE_ONLY:-false}" == true ]]; then
        log_info "Validation only mode - no deployment executed"
    else
        execute_create_deployment
    fi
}

execute_create_deployment() {
    log_info "Creating deployment: $STACK_NAME"
    
    # Track deployment progress
    local deployment_phase="pre_checks"
    
    # Pre-deployment checks with error handling
    log_info "Performing pre-deployment checks"
    if ! check_existing_deployment "${STACK_NAME}" "${AWS_REGION}"; then
        local existing_stack
        existing_stack=$(get_existing_stack_status "${STACK_NAME}" "${AWS_REGION}")
        if [[ -n "$existing_stack" ]]; then
            # Check if we're in dev/staging environment and auto-cleanup is enabled
            if [[ "${ENVIRONMENT,,}" == "development" ]] || [[ "${ENVIRONMENT,,}" == "dev" ]] || [[ "${ENVIRONMENT,,}" == "staging" ]]; then
                log_warn "Stack already exists in ${ENVIRONMENT} environment: $STACK_NAME"
                log_info "Automatically cleaning up existing stack for redeployment"
                
                # Auto cleanup the existing stack
                auto_cleanup_existing_stack "${STACK_NAME}" "${AWS_REGION}" "${ENVIRONMENT}"
                
                # Check if stack still exists in deployment state
                if stack_state_exists "${STACK_NAME}"; then
                    log_info "Removing stack from deployment state: ${STACK_NAME}"
                    delete_stack_state "${STACK_NAME}"
                fi
                
                # Small delay to ensure cleanup completes
                sleep 5
                
                # Verify cleanup was successful
                existing_stack=$(get_existing_stack_status "${STACK_NAME}" "${AWS_REGION}")
                if [[ -n "$existing_stack" ]]; then
                    handle_deployment_error "CLEANUP_FAILED" \
                        "Failed to auto-cleanup existing stack: $STACK_NAME" \
                        "existing_status=$existing_stack" \
                        "abort"
                fi
                log_info "Auto-cleanup completed successfully, proceeding with deployment"
            else
                # In production, abort deployment
                handle_deployment_error "STACK_EXISTS" \
                    "Stack already exists in ${ENVIRONMENT} environment: $STACK_NAME" \
                    "existing_status=$existing_stack,environment=${ENVIRONMENT}" \
                    "abort"
            fi
        fi
    fi
    
    # Setup existing resources before infrastructure creation
    deployment_phase="existing_resources_setup"
    log_info "Setting up existing resources"
    if ! setup_existing_resources_for_deployment; then
        handle_deployment_error "EXISTING_RESOURCES_SETUP_FAILED" \
            "Failed to setup existing resources" \
            "phase=$deployment_phase,stack=$STACK_NAME" \
            "rollback"
    fi
    add_rollback_point "existing_resources_setup" "timestamp=$(date +%s)"
    
    # Create infrastructure components with error handling and rollback points
    deployment_phase="vpc_creation"
    log_info "Creating VPC infrastructure"
    if ! create_vpc_infrastructure; then
        handle_deployment_error "VPC_CREATION_FAILED" \
            "Failed to create VPC infrastructure" \
            "phase=$deployment_phase,stack=$STACK_NAME" \
            "rollback"
    fi
    add_rollback_point "vpc_created" "vpc_id=$(get_variable 'VPC_ID' '$VARIABLE_SCOPE_STACK')"
    
    deployment_phase="security_creation"
    log_info "Creating security infrastructure"
    if ! create_security_infrastructure; then
        handle_deployment_error "SECURITY_CREATION_FAILED" \
            "Failed to create security infrastructure" \
            "phase=$deployment_phase,stack=$STACK_NAME" \
            "rollback"
    fi
    add_rollback_point "security_created" "timestamp=$(date +%s)"
    
    deployment_phase="compute_creation"
    log_info "Creating compute infrastructure"
    if ! retry_with_backoff "create_compute_infrastructure" 3 60; then
        handle_deployment_error "COMPUTE_CREATION_FAILED" \
            "Failed to create compute infrastructure after retries" \
            "phase=$deployment_phase,stack=$STACK_NAME" \
            "rollback"
    fi
    add_rollback_point "compute_created" "timestamp=$(date +%s)"
    
    # Create optional components with error handling
    if [[ "$ENABLE_EFS" == true ]]; then
        deployment_phase="efs_creation"
        log_info "Creating EFS infrastructure"
        if ! create_efs_infrastructure; then
            if [[ "$ENABLE_PARTIAL_ROLLBACK" == true ]]; then
                log_warning "EFS creation failed, continuing without EFS"
                set_variable "ENABLE_EFS" "false" "$VARIABLE_SCOPE_STACK"
            else
                handle_deployment_error "EFS_CREATION_FAILED" \
                    "Failed to create EFS infrastructure" \
                    "phase=$deployment_phase,stack=$STACK_NAME" \
                    "rollback"
            fi
        else
            add_rollback_point "efs_created" "efs_id=$(get_variable 'EFS_FILE_SYSTEM_ID' '$VARIABLE_SCOPE_STACK')"
        fi
    fi
    
    if [[ "$ENABLE_ALB" == true ]]; then
        deployment_phase="alb_creation"
        log_info "Creating ALB infrastructure"
        if ! create_alb_infrastructure; then
            handle_deployment_error "ALB_CREATION_FAILED" \
                "Failed to create ALB infrastructure" \
                "phase=$deployment_phase,stack=$STACK_NAME" \
                "rollback"
        fi
        add_rollback_point "alb_created" "alb_arn=$(get_variable 'ALB_ARN' '$VARIABLE_SCOPE_STACK')"
    fi
    
    if [[ "$ENABLE_CDN" == true ]]; then
        deployment_phase="cdn_creation"
        log_info "Creating CloudFront infrastructure"
        if ! retry_with_backoff "create_cloudfront_infrastructure" 2 120; then
            if [[ "$ENABLE_PARTIAL_ROLLBACK" == true ]]; then
                log_warning "CloudFront creation failed, continuing without CDN"
                set_variable "ENABLE_CDN" "false" "$VARIABLE_SCOPE_STACK"
            else
                handle_deployment_error "CDN_CREATION_FAILED" \
                    "Failed to create CloudFront infrastructure" \
                    "phase=$deployment_phase,stack=$STACK_NAME" \
                    "rollback"
            fi
        else
            add_rollback_point "cdn_created" "distribution_id=$(get_variable 'CLOUDFRONT_DISTRIBUTION_ID' '$VARIABLE_SCOPE_STACK')"
        fi
    fi
    
    # Create monitoring if enabled
    if [[ "$ENABLE_MONITORING" == true ]]; then
        deployment_phase="monitoring_creation"
        log_info "Creating monitoring infrastructure"
        if ! create_monitoring_infrastructure; then
            log_warning "Monitoring creation failed, deployment will continue without monitoring"
            set_variable "ENABLE_MONITORING" "false" "$VARIABLE_SCOPE_STACK"
        fi
    fi
    
    # Finalize deployment with error handling
    deployment_phase="finalization"
    if ! finalize_deployment; then
        handle_deployment_error "FINALIZATION_FAILED" \
            "Failed to finalize deployment" \
            "phase=$deployment_phase,stack=$STACK_NAME" \
            "rollback"
    fi
    
    log_info "Deployment completed successfully"
}

execute_destroy() {
    log_info "Destroying deployment: $STACK_NAME"
    
    # Set deployment state
    set_deployment_state "${STACK_NAME}" "DESTROYING"
    
    local destroy_errors=0
    
    # Load deployment state if available
    local state_file="${CONFIG_DIR}/deployments/${STACK_NAME}.state"
    if [[ -f "$state_file" ]]; then
        log_info "Loading deployment state from: $state_file"
        # Could parse state file to determine what resources exist
    fi
    
    # Destroy infrastructure in reverse order with error handling
    if [[ "$ENABLE_CDN" == true ]]; then
        log_info "Destroying CloudFront infrastructure"
        if ! destroy_cloudfront_infrastructure; then
            log_warning "Failed to destroy CloudFront infrastructure"
            destroy_errors=$((destroy_errors + 1))
        fi
    fi
    
    if [[ "$ENABLE_ALB" == true ]]; then
        log_info "Destroying ALB infrastructure"
        if ! destroy_alb_infrastructure; then
            log_warning "Failed to destroy ALB infrastructure"
            destroy_errors=$((destroy_errors + 1))
        fi
    fi
    
    if [[ "$ENABLE_EFS" == true ]]; then
        log_info "Destroying EFS infrastructure"
        if ! destroy_efs_infrastructure; then
            log_warning "Failed to destroy EFS infrastructure"
            destroy_errors=$((destroy_errors + 1))
        fi
    fi
    
    log_info "Destroying compute infrastructure"
    if ! destroy_compute_infrastructure; then
        log_warning "Failed to destroy compute infrastructure"
        destroy_errors=$((destroy_errors + 1))
    fi
    
    log_info "Destroying security infrastructure"
    if ! destroy_security_infrastructure; then
        log_warning "Failed to destroy security infrastructure"
        destroy_errors=$((destroy_errors + 1))
    fi
    
    log_info "Destroying VPC infrastructure"
    if ! destroy_vpc_infrastructure; then
        log_warning "Failed to destroy VPC infrastructure"
        destroy_errors=$((destroy_errors + 1))
    fi
    
    # Clean up deployment state
    if ! cleanup_deployment_state "${STACK_NAME}" "${AWS_REGION}"; then
        log_warning "Failed to clean up deployment state"
    fi
    
    # Remove state file
    if [[ -f "$state_file" ]]; then
        rm -f "$state_file" || log_warning "Failed to remove state file"
    fi
    
    if [ $destroy_errors -gt 0 ]; then
        log_error "Deployment destruction completed with $destroy_errors errors"
        log_error "Some resources may need manual cleanup"
        return 1
    else
        log_info "Deployment destroyed successfully"
        return 0
    fi
}

execute_rollback() {
    log_info "Rolling back deployment: $STACK_NAME"
    
    # Set deployment state
    set_deployment_state "${STACK_NAME}" "ROLLING_BACK"
    
    # Execute rollback
    perform_rollback "${STACK_NAME}" "${AWS_REGION}"
    
    log_info "Rollback completed"
}

execute_status_check() {
    log_info "Checking deployment status: $STACK_NAME"
    
    # Get deployment status
    local status
    status=$(get_deployment_status "${STACK_NAME}" "${AWS_REGION}")
    
    # Display status
    echo "Deployment Status: $status"
    
    # Show detailed information
    show_deployment_details "${STACK_NAME}" "${AWS_REGION}"
}

execute_logs_view() {
    log_info "Viewing deployment logs: $STACK_NAME"
    
    # Show deployment logs
    show_deployment_logs "${STACK_NAME}" "${AWS_REGION}"
}

# =============================================================================
# INFRASTRUCTURE CREATION
# =============================================================================

create_vpc_infrastructure() {
    log_info "Creating VPC infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create VPC infrastructure"
        return 0
    fi
    
    # Get VPC configuration from variable store
    local vpc_cidr
    vpc_cidr=$(get_variable "VPC_CIDR" "$VARIABLE_SCOPE_STACK")
    local public_subnets
    public_subnets=$(get_variable "PUBLIC_SUBNETS" "$VARIABLE_SCOPE_STACK")
    local private_subnets
    private_subnets=$(get_variable "PRIVATE_SUBNETS" "$VARIABLE_SCOPE_STACK")
    
    # Validate configuration
    if [[ -z "$vpc_cidr" ]]; then
        log_error "VPC CIDR is not configured"
        return 1
    fi
    
    # Create VPC with subnets using the integrated VPC module
    local vpc_result
    if vpc_result=$(create_vpc_with_subnets "${STACK_NAME}" "$vpc_cidr" "$public_subnets" "$private_subnets" 2>&1); then
        # Extract and register VPC ID
        local vpc_id
        vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
        if [[ -n "$vpc_id" ]]; then
            register_resource "vpc" "$vpc_id"
        fi
        
        # Register subnets
        local subnet_ids
        subnet_ids=$(get_variable "PUBLIC_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
        if [[ -n "$subnet_ids" ]]; then
            IFS=',' read -ra SUBNET_ARRAY <<< "$subnet_ids"
            for subnet_id in "${SUBNET_ARRAY[@]}"; do
                register_resource "subnet" "$subnet_id"
            done
        fi
        
        log_info "VPC infrastructure created successfully"
        return 0
    else
        # Check for specific error conditions
        if [[ "$vpc_result" =~ "InvalidParameterValue" ]]; then
            log_error "Invalid VPC configuration: $vpc_result"
            error_config_invalid_variable "VPC_CIDR" "$vpc_cidr"
        elif [[ "$vpc_result" =~ "VpcLimitExceeded" ]]; then
            log_error "VPC limit exceeded in region $AWS_REGION"
            error_vpc_limit_exceeded "$AWS_REGION"
        else
            log_error "Failed to create VPC infrastructure: $vpc_result"
        fi
        return 1
    fi
}

create_security_infrastructure() {
    log_info "Creating security infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create security infrastructure"
        return 0
    fi
    
    # Get VPC ID from variable store
    local vpc_id
    vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$vpc_id" ]]; then
        log_error "VPC ID not found - VPC must be created first"
        error_dependency_not_ready "VPC" "Security Groups"
        return 1
    fi
    
    # Create comprehensive security groups with error handling
    local sg_result
    if sg_result=$(create_comprehensive_security_groups "${STACK_NAME}" "$vpc_id" "${ENABLE_ALB}" 2>&1); then
        # Register created security groups
        local web_sg_id alb_sg_id efs_sg_id
        web_sg_id=$(get_variable "WEB_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
        alb_sg_id=$(get_variable "ALB_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
        efs_sg_id=$(get_variable "EFS_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
        
        [[ -n "$web_sg_id" ]] && register_resource "security-group" "$web_sg_id"
        [[ -n "$alb_sg_id" ]] && register_resource "security-group" "$alb_sg_id"
        [[ -n "$efs_sg_id" ]] && register_resource "security-group" "$efs_sg_id"
        
        log_info "Security groups created successfully"
    else
        # Handle specific error conditions
        if [[ "$sg_result" =~ "InvalidGroup.Duplicate" ]]; then
            log_error "Security groups already exist for stack: ${STACK_NAME}"
            error_network_security_group_invalid "duplicate-${STACK_NAME}"
        elif [[ "$sg_result" =~ "InvalidVpcID.NotFound" ]]; then
            log_error "VPC not found: $vpc_id"
            error_network_vpc_not_found "$vpc_id"
        else
            log_error "Failed to create security groups: $sg_result"
        fi
        return 1
    fi
    
    # Create IAM roles if needed with error handling
    if [[ "${ENABLE_MONITORING:-false}" == true ]]; then
        local iam_result
        if iam_result=$(create_iam_role "${STACK_NAME}" 2>&1); then
            # Register IAM role
            local iam_role_arn
            iam_role_arn=$(get_variable "IAM_ROLE_ARN" "$VARIABLE_SCOPE_STACK")
            [[ -n "$iam_role_arn" ]] && register_resource "iam-role" "${STACK_NAME}-role"
            
            log_info "IAM role created successfully"
        else
            # Handle IAM errors
            if [[ "$iam_result" =~ "AccessDenied" ]]; then
                error_auth_insufficient_permissions "iam:CreateRole" "IAM"
                log_error "Insufficient permissions to create IAM role"
                return 1
            elif [[ "$iam_result" =~ "EntityAlreadyExists" ]]; then
                log_warning "IAM role already exists, continuing"
            else
                log_error "Failed to create IAM role: $iam_result"
                return 1
            fi
        fi
    fi
    
    log_info "Security infrastructure created successfully"
}

create_compute_infrastructure() {
    log_info "Creating compute infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create compute infrastructure"
        return 0
    fi
    
    # Get VPC ID from variable store
    local vpc_id
    vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$vpc_id" ]]; then
        log_error "VPC ID not found - VPC must be created first"
        error_dependency_not_ready "VPC" "Compute"
        return 1
    fi
    
    # Get compute configuration from variable store
    local instance_type
    instance_type=$(get_variable "INSTANCE_TYPE" "$VARIABLE_SCOPE_STACK")
    local min_capacity
    min_capacity=$(get_variable "MIN_CAPACITY" "$VARIABLE_SCOPE_STACK")
    local max_capacity
    max_capacity=$(get_variable "MAX_CAPACITY" "$VARIABLE_SCOPE_STACK")
    local enable_spot
    enable_spot=$(get_variable "ENABLE_SPOT" "$VARIABLE_SCOPE_STACK")
    local enable_multi_az
    enable_multi_az=$(get_variable "ENABLE_MULTI_AZ" "$VARIABLE_SCOPE_STACK")
    
    # Validate compute configuration
    if [[ -z "$instance_type" ]] || [[ -z "$min_capacity" ]] || [[ -z "$max_capacity" ]]; then
        log_error "Invalid compute configuration"
        error_config_missing_parameter "instance_type or capacity settings"
        return 1
    fi
    
    # Create JSON configuration object for compute module
    local compute_config
    compute_config=$(cat << EOF
{
    "instance_type": "$instance_type",
    "use_spot": $enable_spot,
    "min_capacity": $min_capacity,
    "max_capacity": $max_capacity,
    "desired_capacity": $min_capacity,
    "multi_az": $enable_multi_az
}
EOF
)
    
    # Create compute infrastructure with error handling
    local compute_result
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        if compute_result=$(create_compute_infrastructure "${STACK_NAME}" "$compute_config" 2>&1); then
            # Register created instances
            local instance_ids
            instance_ids=$(get_variable "INSTANCE_IDS" "$VARIABLE_SCOPE_STACK")
            if [[ -n "$instance_ids" ]]; then
                IFS=',' read -ra INSTANCE_ARRAY <<< "$instance_ids"
                for instance_id in "${INSTANCE_ARRAY[@]}"; do
                    register_resource "instance" "$instance_id"
                done
            fi
            
            # Register auto-scaling group if created
            local asg_name
            asg_name=$(get_variable "ASG_NAME" "$VARIABLE_SCOPE_STACK")
            if [[ -n "$asg_name" ]]; then
                register_resource "auto-scaling-group" "$asg_name"
            fi
            
            log_info "Compute infrastructure created successfully"
            return 0
        else
            # Handle specific error conditions
            if [[ "$compute_result" =~ "InsufficientInstanceCapacity" ]]; then
                error_ec2_insufficient_capacity "$instance_type" "$AWS_REGION"
                
                if [[ "$enable_spot" == true ]]; then
                    log_warning "Spot capacity unavailable, trying different instance type or region"
                    # Could implement fallback logic here
                fi
                
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log_info "Retrying compute creation (attempt $((retry_count + 1))/$max_retries)"
                    sleep $((RETRY_DELAY * retry_count))
                fi
            elif [[ "$compute_result" =~ "InstanceLimitExceeded" ]]; then
                error_ec2_instance_limit_exceeded "$instance_type"
                log_error "Instance limit exceeded - manual intervention required"
                return 1
            elif [[ "$compute_result" =~ "RequestLimitExceeded" ]]; then
                log_warning "AWS API rate limit hit, backing off"
                sleep $((30 * (retry_count + 1)))
                retry_count=$((retry_count + 1))
            else
                log_error "Failed to create compute infrastructure: $compute_result"
                return 1
            fi
        fi
    done
    
    log_error "Failed to create compute infrastructure after $max_retries attempts"
    return 1
}

create_efs_infrastructure() {
    log_info "Creating EFS infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create EFS infrastructure"
        return 0
    fi
    
    # Get VPC ID from variable store
    local vpc_id
    vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$vpc_id" ]]; then
        log_error "VPC ID not found - VPC must be created first"
        error_dependency_not_ready "VPC" "EFS"
        return 1
    fi
    
    # Get subnet information
    local private_subnet_ids
    private_subnet_ids=$(get_variable "PRIVATE_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$private_subnet_ids" ]]; then
        log_error "Private subnet IDs not found - VPC must be created first"
        error_dependency_not_ready "Private Subnets" "EFS"
        return 1
    fi
    
    # Get security group ID
    local efs_security_group_id
    efs_security_group_id=$(get_variable "EFS_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$efs_security_group_id" ]]; then
        log_error "EFS security group ID not found - Security must be created first"
        error_dependency_not_ready "Security Groups" "EFS"
        return 1
    fi
    
    # Get EFS configuration from variable store
    local efs_encryption
    efs_encryption=$(get_variable "EFS_ENCRYPTION" "$VARIABLE_SCOPE_STACK")
    
    # Create subnets JSON for EFS module with error handling
    local subnets_json
    if ! subnets_json=$(echo "$private_subnet_ids" | tr ',' '\n' | jq -R . | jq -s . 2>&1); then
        log_error "Failed to parse subnet IDs: $subnets_json"
        return 1
    fi
    
    # Create EFS infrastructure with retry logic
    local efs_result
    local retry_count=0
    local max_retries=2
    
    while [ $retry_count -le $max_retries ]; do
        if efs_result=$(setup_efs_infrastructure "${STACK_NAME}" "$subnets_json" "$efs_security_group_id" 2>&1); then
            # Extract and validate EFS ID
            local efs_id
            efs_id=$(echo "$efs_result" | jq -r '.efs_id' 2>/dev/null || echo "")
            
            if [[ -n "$efs_id" ]] && [[ "$efs_id" != "null" ]]; then
                set_variable "EFS_FILE_SYSTEM_ID" "$efs_id" "$VARIABLE_SCOPE_STACK"
                register_resource "efs" "$efs_id"
                
                # Register mount targets if available
                local mount_target_ids
                mount_target_ids=$(echo "$efs_result" | jq -r '.mount_target_ids[]?' 2>/dev/null || true)
                if [[ -n "$mount_target_ids" ]]; then
                    while IFS= read -r mt_id; do
                        [[ -n "$mt_id" ]] && register_resource "efs-mount-target" "$mt_id"
                    done <<< "$mount_target_ids"
                fi
                
                log_info "EFS infrastructure created successfully"
                return 0
            else
                log_error "Failed to extract EFS ID from result"
                return 1
            fi
        else
            # Handle specific error conditions
            if [[ "$efs_result" =~ "FileSystemLimitExceeded" ]]; then
                log_error "EFS file system limit exceeded in region $AWS_REGION"
                error_ec2_instance_limit_exceeded "EFS"
                return 1
            elif [[ "$efs_result" =~ "SubnetNotFound" ]]; then
                log_error "One or more subnets not found for EFS"
                return 1
            elif [[ "$efs_result" =~ "MountTargetConflict" ]]; then
                log_warning "Mount target conflict detected, retrying..."
                retry_count=$((retry_count + 1))
                if [ $retry_count -le $max_retries ]; then
                    sleep $((RETRY_DELAY * retry_count))
                    continue
                fi
            else
                log_error "Failed to create EFS infrastructure: $efs_result"
                return 1
            fi
        fi
    done
    
    log_error "Failed to create EFS infrastructure after $max_retries retries"
    return 1
}

create_alb_infrastructure() {
    log_info "Creating ALB infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create ALB infrastructure"
        return 0
    fi
    
    # Get VPC ID from variable store
    local vpc_id
    vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$vpc_id" ]]; then
        log_error "VPC ID not found - VPC must be created first"
        error_dependency_not_ready "VPC" "ALB"
        return 1
    fi
    
    # Get subnet information
    local public_subnet_ids
    public_subnet_ids=$(get_variable "PUBLIC_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$public_subnet_ids" ]]; then
        log_error "Public subnet IDs not found - VPC must be created first"
        error_dependency_not_ready "Public Subnets" "ALB"
        return 1
    fi
    
    # Validate we have at least 2 subnets for ALB
    local subnet_count
    subnet_count=$(echo "$public_subnet_ids" | tr ',' '\n' | wc -l)
    if [ "$subnet_count" -lt 2 ]; then
        log_error "ALB requires at least 2 subnets, found: $subnet_count"
        error_config_invalid_variable "PUBLIC_SUBNET_IDS" "insufficient subnets"
        return 1
    fi
    
    # Get ALB configuration from variable store
    local alb_internal
    alb_internal=$(get_variable "ALB_INTERNAL" "$VARIABLE_SCOPE_STACK")
    
    # Create ALB with error handling
    local alb_result
    if alb_result=$(create_alb_with_target_group "${STACK_NAME}" "$vpc_id" "$public_subnet_ids" "$alb_internal" 2>&1); then
        # Register ALB resources
        local alb_arn alb_dns target_group_arn
        alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
        alb_dns=$(get_variable "ALB_DNS_NAME" "$VARIABLE_SCOPE_STACK")
        target_group_arn=$(get_variable "TARGET_GROUP_ARN" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$alb_arn" ]]; then
            register_resource "alb" "$alb_arn"
            log_info "ALB created: $alb_dns"
        fi
        
        if [[ -n "$target_group_arn" ]]; then
            register_resource "target-group" "$target_group_arn"
        fi
        
        log_info "ALB infrastructure created successfully"
        return 0
    else
        # Handle specific ALB errors
        if [[ "$alb_result" =~ "DuplicateLoadBalancerName" ]]; then
            log_error "Load balancer with name ${STACK_NAME}-alb already exists"
            return 1
        elif [[ "$alb_result" =~ "InvalidSubnet" ]]; then
            log_error "Invalid subnet configuration for ALB"
            return 1
        elif [[ "$alb_result" =~ "TooManyLoadBalancers" ]]; then
            log_error "Load balancer limit exceeded in region $AWS_REGION"
            error_ec2_instance_limit_exceeded "ALB"
            return 1
        else
            log_error "Failed to create ALB infrastructure: $alb_result"
            return 1
        fi
    fi
}

create_cloudfront_infrastructure() {
    log_info "Creating CloudFront infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create CloudFront infrastructure"
        return 0
    fi
    
    # Get ALB DNS name from variable store
    local alb_dns_name
    alb_dns_name=$(get_variable "ALB_DNS_NAME" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$alb_dns_name" ]]; then
        log_error "ALB DNS name not found - ALB must be created first"
        error_dependency_not_ready "ALB" "CloudFront"
        return 1
    fi
    
    # Get CloudFront configuration from variable store
    local cloudfront_price_class
    cloudfront_price_class=$(get_variable "CLOUDFRONT_PRICE_CLASS" "$VARIABLE_SCOPE_STACK")
    
    # Create CloudFront distribution with error handling and timeout
    local cf_result
    local cf_timeout=600  # CloudFront can take up to 10 minutes
    
    log_info "Creating CloudFront distribution (this may take up to 10 minutes)..."
    
    if timeout "$cf_timeout" bash -c "cf_result=\$(create_cloudfront_distribution '${STACK_NAME}' '$alb_dns_name' '$cloudfront_price_class' 2>&1) && echo \"\$cf_result\""; then
        # Extract CloudFront details
        local distribution_id distribution_domain
        distribution_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
        distribution_domain=$(get_variable "CLOUDFRONT_DOMAIN_NAME" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$distribution_id" ]]; then
            register_resource "cloudfront-distribution" "$distribution_id"
            log_info "CloudFront distribution created: $distribution_domain"
            
            # Wait for distribution to be deployed
            log_info "Waiting for CloudFront distribution to deploy..."
            local wait_result
            if ! wait_result=$(aws cloudfront wait distribution-deployed \
                --id "$distribution_id" \
                --region "$AWS_REGION" 2>&1); then
                log_warning "CloudFront distribution deployment wait timed out: $wait_result"
                log_warning "Distribution will continue deploying in the background"
            fi
        else
            log_error "Failed to extract CloudFront distribution ID"
            return 1
        fi
        
        log_info "CloudFront infrastructure created successfully"
        return 0
    else
        # Handle timeout or error
        if [ $? -eq 124 ]; then
            error_timeout_operation "CloudFront creation" "$cf_timeout"
            log_error "CloudFront creation timed out after ${cf_timeout} seconds"
        else
            # Parse specific CloudFront errors
            if [[ "${cf_result:-}" =~ "TooManyDistributions" ]]; then
                log_error "CloudFront distribution limit exceeded"
                error_ec2_instance_limit_exceeded "CloudFront distributions"
            elif [[ "${cf_result:-}" =~ "InvalidOrigin" ]]; then
                log_error "Invalid origin configuration for CloudFront"
                error_config_invalid_variable "ALB_DNS_NAME" "$alb_dns_name"
            else
                log_error "Failed to create CloudFront infrastructure: ${cf_result:-unknown error}"
            fi
        fi
        return 1
    fi
}

create_monitoring_infrastructure() {
    log_info "Creating monitoring infrastructure"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "DRY RUN: Would create monitoring infrastructure"
        return 0
    fi
    
    local monitoring_errors=0
    
    # Create CloudWatch alarms with error handling
    log_info "Creating CloudWatch alarms"
    local alarm_result
    if alarm_result=$(create_cloudwatch_alarms "${STACK_NAME}" "${AWS_REGION}" 2>&1); then
        log_info "CloudWatch alarms created successfully"
    else
        log_warning "Failed to create some CloudWatch alarms: $alarm_result"
        monitoring_errors=$((monitoring_errors + 1))
        
        # Check if it's a permissions issue
        if [[ "$alarm_result" =~ "AccessDenied" ]]; then
            error_auth_insufficient_permissions "cloudwatch:PutMetricAlarm" "CloudWatch"
        fi
    fi
    
    # Create CloudWatch dashboards with error handling
    log_info "Creating CloudWatch dashboards"
    local dashboard_result
    if dashboard_result=$(create_cloudwatch_dashboards "${STACK_NAME}" "${AWS_REGION}" 2>&1); then
        log_info "CloudWatch dashboards created successfully"
        
        # Register dashboard
        register_resource "cloudwatch-dashboard" "${STACK_NAME}-dashboard"
    else
        log_warning "Failed to create CloudWatch dashboards: $dashboard_result"
        monitoring_errors=$((monitoring_errors + 1))
    fi
    
    # Create SNS topic for alerts if configured
    local sns_topic_arn
    sns_topic_arn=$(get_variable "SNS_ALERT_TOPIC" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$sns_topic_arn" ]]; then
        log_info "Creating SNS topic for alerts"
        local sns_result
        if sns_result=$(aws sns create-topic \
            --name "${STACK_NAME}-alerts" \
            --region "$AWS_REGION" \
            --output text --query 'TopicArn' 2>&1); then
            set_variable "SNS_ALERT_TOPIC" "$sns_result" "$VARIABLE_SCOPE_STACK"
            register_resource "sns-topic" "$sns_result"
            log_info "SNS topic created: $sns_result"
        else
            log_warning "Failed to create SNS topic: $sns_result"
            monitoring_errors=$((monitoring_errors + 1))
        fi
    fi
    
    # Determine success based on error count
    if [ $monitoring_errors -eq 0 ]; then
        log_info "Monitoring infrastructure created successfully"
        return 0
    else
        log_warning "Monitoring infrastructure created with $monitoring_errors errors"
        # Return success as monitoring is optional
        return 0
    fi
}

# =============================================================================
# INFRASTRUCTURE DESTRUCTION
# =============================================================================

destroy_cloudfront_infrastructure() {
    log_info "Destroying CloudFront infrastructure"
    
    # Get CloudFront distribution ID from variable store
    local distribution_id
    distribution_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "$distribution_id" ]]; then
        log_debug "No CloudFront distribution ID found, skipping"
        return 0
    fi
    
    # Disable distribution first
    log_info "Disabling CloudFront distribution: $distribution_id"
    local config_result etag
    if config_result=$(aws cloudfront get-distribution-config \
        --id "$distribution_id" \
        --region "$AWS_REGION" 2>&1); then
        
        etag=$(echo "$config_result" | jq -r '.ETag')
        local config
        config=$(echo "$config_result" | jq '.DistributionConfig | .Enabled = false')
        
        if aws cloudfront update-distribution \
            --id "$distribution_id" \
            --if-match "$etag" \
            --distribution-config "$config" \
            --region "$AWS_REGION" >/dev/null 2>&1; then
            log_info "CloudFront distribution disabled"
        else
            log_warning "Failed to disable CloudFront distribution"
        fi
    fi
    
    # Delete distribution
    if delete_cloudfront_distribution "$distribution_id"; then
        log_info "CloudFront distribution deleted successfully"
        return 0
    else
        log_error "Failed to delete CloudFront distribution"
        return 1
    fi
}

destroy_alb_infrastructure() {
    log_info "Destroying ALB infrastructure"
    
    # Get ALB and target group ARNs from variable store
    local alb_arn target_group_arn
    alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    target_group_arn=$(get_variable "TARGET_GROUP_ARN" "$VARIABLE_SCOPE_STACK")
    
    local destroy_failed=false
    
    # Delete ALB first
    if [[ -n "$alb_arn" ]]; then
        log_info "Deleting ALB: $alb_arn"
        if ! aws elbv2 delete-load-balancer \
            --load-balancer-arn "$alb_arn" \
            --region "$AWS_REGION" 2>&1; then
            log_error "Failed to delete ALB"
            destroy_failed=true
        else
            # Wait for ALB deletion
            log_info "Waiting for ALB deletion..."
            local wait_count=0
            while [ $wait_count -lt 30 ]; do
                if ! aws elbv2 describe-load-balancers \
                    --load-balancer-arns "$alb_arn" \
                    --region "$AWS_REGION" >/dev/null 2>&1; then
                    break
                fi
                sleep 10
                wait_count=$((wait_count + 1))
            done
        fi
    fi
    
    # Delete target group
    if [[ -n "$target_group_arn" ]]; then
        log_info "Deleting target group: $target_group_arn"
        if ! aws elbv2 delete-target-group \
            --target-group-arn "$target_group_arn" \
            --region "$AWS_REGION" 2>&1; then
            log_warning "Failed to delete target group (may already be deleted)"
        fi
    fi
    
    if [[ "$destroy_failed" == true ]]; then
        return 1
    else
        log_info "ALB infrastructure destroyed successfully"
        return 0
    fi
}

destroy_efs_infrastructure() {
    log_info "Destroying EFS infrastructure"
    
    # Get EFS file system ID from variable store
    local efs_id
    efs_id=$(get_variable "EFS_FILE_SYSTEM_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "$efs_id" ]]; then
        log_debug "No EFS file system ID found, skipping"
        return 0
    fi
    
    # Delete mount targets first
    log_info "Deleting EFS mount targets for: $efs_id"
    local mount_targets
    if mount_targets=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --region "$AWS_REGION" \
        --query 'MountTargets[].MountTargetId' \
        --output text 2>&1); then
        
        for mt_id in $mount_targets; do
            if [[ -n "$mt_id" ]] && [[ "$mt_id" != "None" ]]; then
                log_debug "Deleting mount target: $mt_id"
                aws efs delete-mount-target \
                    --mount-target-id "$mt_id" \
                    --region "$AWS_REGION" 2>&1 || true
            fi
        done
        
        # Wait for mount targets to be deleted
        log_info "Waiting for mount targets to be deleted..."
        sleep 30
    fi
    
    # Delete EFS file system
    log_info "Deleting EFS file system: $efs_id"
    if aws efs delete-file-system \
        --file-system-id "$efs_id" \
        --region "$AWS_REGION" 2>&1; then
        log_info "EFS file system deleted successfully"
        return 0
    else
        log_error "Failed to delete EFS file system"
        return 1
    fi
}

destroy_compute_infrastructure() {
    log_info "Destroying compute infrastructure"
    
    # Get ASG name from variable store
    local asg_name
    asg_name=$(get_variable "ASG_NAME" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$asg_name" ]]; then
        log_info "Deleting Auto Scaling Group: $asg_name"
        
        # Update ASG to terminate all instances
        aws autoscaling update-auto-scaling-group \
            --auto-scaling-group-name "$asg_name" \
            --min-size 0 \
            --desired-capacity 0 \
            --region "$AWS_REGION" 2>&1 || true
        
        # Force delete ASG
        if aws autoscaling delete-auto-scaling-group \
            --auto-scaling-group-name "$asg_name" \
            --force-delete \
            --region "$AWS_REGION" 2>&1; then
            log_info "Auto Scaling Group deleted"
        else
            log_warning "Failed to delete Auto Scaling Group"
        fi
    fi
    
    # Get individual instance IDs if any
    local instance_ids
    instance_ids=$(get_variable "INSTANCE_IDS" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$instance_ids" ]]; then
        log_info "Terminating instances: $instance_ids"
        IFS=',' read -ra INSTANCE_ARRAY <<< "$instance_ids"
        for instance_id in "${INSTANCE_ARRAY[@]}"; do
            aws ec2 terminate-instances \
                --instance-ids "$instance_id" \
                --region "$AWS_REGION" 2>&1 || true
        done
    fi
    
    # Delete launch template if exists
    local launch_template_id
    launch_template_id=$(get_variable "LAUNCH_TEMPLATE_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -n "$launch_template_id" ]]; then
        log_info "Deleting launch template: $launch_template_id"
        aws ec2 delete-launch-template \
            --launch-template-id "$launch_template_id" \
            --region "$AWS_REGION" 2>&1 || true
    fi
    
    log_info "Compute infrastructure destroyed"
    return 0
}

destroy_security_infrastructure() {
    log_info "Destroying security infrastructure"
    
    # Get security group IDs from variable store
    local web_sg_id alb_sg_id efs_sg_id
    web_sg_id=$(get_variable "WEB_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    alb_sg_id=$(get_variable "ALB_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    efs_sg_id=$(get_variable "EFS_SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    
    # Delete security groups (may fail if still in use)
    for sg_id in "$web_sg_id" "$alb_sg_id" "$efs_sg_id"; do
        if [[ -n "$sg_id" ]] && [[ "$sg_id" != "null" ]]; then
            log_debug "Attempting to delete security group: $sg_id"
            aws ec2 delete-security-group \
                --group-id "$sg_id" \
                --region "$AWS_REGION" 2>&1 || true
        fi
    done
    
    # Delete IAM role if exists
    local iam_role_name="${STACK_NAME}-role"
    log_info "Deleting IAM role: $iam_role_name"
    
    # Detach policies first
    local attached_policies
    if attached_policies=$(aws iam list-attached-role-policies \
        --role-name "$iam_role_name" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>&1); then
        
        for policy_arn in $attached_policies; do
            if [[ -n "$policy_arn" ]] && [[ "$policy_arn" != "None" ]]; then
                aws iam detach-role-policy \
                    --role-name "$iam_role_name" \
                    --policy-arn "$policy_arn" 2>&1 || true
            fi
        done
    fi
    
    # Delete the role
    aws iam delete-role \
        --role-name "$iam_role_name" 2>&1 || true
    
    log_info "Security infrastructure destroyed"
    return 0
}

destroy_vpc_infrastructure() {
    log_info "Destroying VPC infrastructure"
    
    # Get VPC ID from variable store
    local vpc_id
    vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "$vpc_id" ]]; then
        log_debug "No VPC ID found, skipping"
        return 0
    fi
    
    log_info "Preparing to delete VPC: $vpc_id"
    
    # Delete NAT Gateways first
    local nat_gateways
    if nat_gateways=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
        --region "$AWS_REGION" \
        --query 'NatGateways[].NatGatewayId' \
        --output text 2>&1); then
        
        for nat_id in $nat_gateways; do
            if [[ -n "$nat_id" ]] && [[ "$nat_id" != "None" ]]; then
                log_info "Deleting NAT Gateway: $nat_id"
                aws ec2 delete-nat-gateway \
                    --nat-gateway-id "$nat_id" \
                    --region "$AWS_REGION" 2>&1 || true
            fi
        done
        
        # Wait for NAT gateways to be deleted
        if [[ -n "$nat_gateways" ]] && [[ "$nat_gateways" != "None" ]]; then
            log_info "Waiting for NAT gateways to be deleted..."
            sleep 60
        fi
    fi
    
    # Release Elastic IPs
    local eips
    if eips=$(aws ec2 describe-addresses \
        --filters "Name=tag:Stack,Values=${STACK_NAME}" \
        --region "$AWS_REGION" \
        --query 'Addresses[].AllocationId' \
        --output text 2>&1); then
        
        for eip_id in $eips; do
            if [[ -n "$eip_id" ]] && [[ "$eip_id" != "None" ]]; then
                log_info "Releasing Elastic IP: $eip_id"
                aws ec2 release-address \
                    --allocation-id "$eip_id" \
                    --region "$AWS_REGION" 2>&1 || true
            fi
        done
    fi
    
    # Delete Internet Gateway
    local igw_id
    if igw_id=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --region "$AWS_REGION" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>&1); then
        
        if [[ -n "$igw_id" ]] && [[ "$igw_id" != "None" ]]; then
            log_info "Detaching and deleting Internet Gateway: $igw_id"
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$igw_id" \
                --vpc-id "$vpc_id" \
                --region "$AWS_REGION" 2>&1 || true
            
            aws ec2 delete-internet-gateway \
                --internet-gateway-id "$igw_id" \
                --region "$AWS_REGION" 2>&1 || true
        fi
    fi
    
    # Delete subnets
    local subnet_ids
    subnet_ids=$(get_variable "PUBLIC_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
    subnet_ids="${subnet_ids},$(get_variable 'PRIVATE_SUBNET_IDS' '$VARIABLE_SCOPE_STACK')"
    
    IFS=',' read -ra SUBNET_ARRAY <<< "$subnet_ids"
    for subnet_id in "${SUBNET_ARRAY[@]}"; do
        if [[ -n "$subnet_id" ]] && [[ "$subnet_id" != "null" ]]; then
            log_debug "Deleting subnet: $subnet_id"
            aws ec2 delete-subnet \
                --subnet-id "$subnet_id" \
                --region "$AWS_REGION" 2>&1 || true
        fi
    done
    
    # Delete route tables
    local route_tables
    if route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$AWS_REGION" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
        --output text 2>&1); then
        
        for rt_id in $route_tables; do
            if [[ -n "$rt_id" ]] && [[ "$rt_id" != "None" ]]; then
                log_debug "Deleting route table: $rt_id"
                aws ec2 delete-route-table \
                    --route-table-id "$rt_id" \
                    --region "$AWS_REGION" 2>&1 || true
            fi
        done
    fi
    
    # Finally delete the VPC
    log_info "Deleting VPC: $vpc_id"
    if aws ec2 delete-vpc \
        --vpc-id "$vpc_id" \
        --region "$AWS_REGION" 2>&1; then
        log_info "VPC deleted successfully"
        return 0
    else
        log_error "Failed to delete VPC - may require manual cleanup"
        return 1
    fi
}

# =============================================================================
# FINALIZATION
# =============================================================================

finalize_deployment() {
    log_info "Finalizing deployment"
    
    # Perform final validation
    log_info "Performing final deployment validation"
    local validation_errors=0
    
    # Verify all critical resources are created
    local vpc_id
    vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$vpc_id" ]]; then
        log_error "Critical resource missing: VPC"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check compute resources
    local instance_ids asg_name
    instance_ids=$(get_variable "INSTANCE_IDS" "$VARIABLE_SCOPE_STACK")
    asg_name=$(get_variable "ASG_NAME" "$VARIABLE_SCOPE_STACK")
    if [[ -z "$instance_ids" ]] && [[ -z "$asg_name" ]]; then
        log_error "Critical resource missing: Compute instances"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check ALB if enabled
    if [[ "$ENABLE_ALB" == true ]]; then
        local alb_arn
        alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
        if [[ -z "$alb_arn" ]]; then
            log_error "Critical resource missing: ALB"
            validation_errors=$((validation_errors + 1))
        fi
    fi
    
    if [ $validation_errors -gt 0 ]; then
        log_error "Deployment validation failed with $validation_errors errors"
        set_deployment_state "${STACK_NAME}" "FAILED"
        return 1
    fi
    
    # Update deployment state
    set_deployment_state "${STACK_NAME}" "COMPLETED"
    
    # Generate deployment summary
    if ! generate_deployment_summary; then
        log_warning "Failed to generate deployment summary"
    fi
    
    # Perform health check if monitoring is enabled
    if [[ "$ENABLE_MONITORING" == true ]]; then
        log_info "Performing deployment health check"
        local health_result
        if health_result=$(perform_health_check "${STACK_NAME}" "${AWS_REGION}" 2>&1); then
            log_info "Health check passed"
        else
            log_warning "Health check reported issues: $health_result"
            # Don't fail deployment for health check issues
        fi
    fi
    
    # Tag all resources with deployment metadata
    log_info "Tagging resources with deployment metadata"
    tag_deployment_resources
    
    # Save deployment state for future operations
    save_deployment_state
    
    # Show deployment information
    show_deployment_information
    
    log_info "Deployment finalized successfully"
    return 0
}

# Tag all created resources
tag_deployment_resources() {
    local deployment_date
    deployment_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    local tags="Key=Stack,Value=${STACK_NAME} Key=DeploymentType,Value=${DEPLOYMENT_TYPE} Key=DeploymentDate,Value=${deployment_date} Key=ManagedBy,Value=GeuseMaker"
    
    # Tag each resource type
    for resource in "${CREATED_RESOURCES[@]}"; do
        local resource_type="${resource%%:*}"
        local remaining="${resource#*:}"
        local resource_id="${remaining%%:*}"
        local resource_region="${remaining#*:}"
        
        case "$resource_type" in
            "vpc"|"subnet"|"security-group"|"instance")
                aws ec2 create-tags \
                    --resources "$resource_id" \
                    --tags $tags \
                    --region "$resource_region" 2>/dev/null || true
                ;;
            "efs")
                aws efs tag-resource \
                    --resource-id "$resource_id" \
                    --tags $tags \
                    --region "$resource_region" 2>/dev/null || true
                ;;
        esac
    done
}

# Save deployment state for future operations
save_deployment_state() {
    local state_file="${CONFIG_DIR}/deployments/${STACK_NAME}.state"
    mkdir -p "$(dirname "$state_file")"
    
    cat > "$state_file" << EOF
{
    "stack_name": "${STACK_NAME}",
    "deployment_type": "${DEPLOYMENT_TYPE}",
    "aws_region": "${AWS_REGION}",
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment_duration": $(($(date +%s) - DEPLOYMENT_START_TIME)),
    "features": {
        "alb": ${ENABLE_ALB},
        "cdn": ${ENABLE_CDN},
        "efs": ${ENABLE_EFS},
        "multi_az": ${ENABLE_MULTI_AZ},
        "spot": ${ENABLE_SPOT},
        "monitoring": ${ENABLE_MONITORING}
    },
    "resources": {
        "vpc_id": "$(get_variable 'VPC_ID' '$VARIABLE_SCOPE_STACK')",
        "instance_type": "$(get_variable 'INSTANCE_TYPE' '$VARIABLE_SCOPE_STACK')",
        "resource_count": ${#CREATED_RESOURCES[@]}
    },
    "rollback_points": ${#DEPLOYMENT_ROLLBACK_POINTS[@]}
}
EOF
    
    log_debug "Deployment state saved to: $state_file"
}

generate_deployment_summary() {
    local summary_file="${CONFIG_DIR}/temp/${STACK_NAME}-summary.json"
    
    cat > "$summary_file" << EOF
{
    "stack_name": "${STACK_NAME}",
    "deployment_type": "${DEPLOYMENT_TYPE}",
    "aws_region": "${AWS_REGION}",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "features": {
        "alb": ${ENABLE_ALB},
        "cdn": ${ENABLE_CDN},
        "efs": ${ENABLE_EFS},
        "multi_az": ${ENABLE_MULTI_AZ},
        "spot": ${ENABLE_SPOT},
        "monitoring": ${ENABLE_MONITORING},
        "backup": ${ENABLE_BACKUP}
    },
    "status": "completed"
}
EOF
    
    log_info "Deployment summary generated: $summary_file"
}

show_deployment_information() {
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo "Stack Name:      $STACK_NAME"
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "AWS Region:      $AWS_REGION"
    echo "Deployment Time: $(date)"
    echo ""
    echo "Features Enabled:"
    echo "  • ALB:        $ENABLE_ALB"
    echo "  • CDN:        $ENABLE_CDN"
    echo "  • EFS:        $ENABLE_EFS"
    echo "  • Multi-AZ:   $ENABLE_MULTI_AZ"
    echo "  • Spot:       $ENABLE_SPOT"
    echo "  • Monitoring: $ENABLE_MONITORING"
    echo "  • Backup:     $ENABLE_BACKUP"
    echo ""
    
    # Show deployment type specific information
    case $DEPLOYMENT_TYPE in
        spot)
            echo "Cost Optimization:"
            echo "  • Estimated savings: 70%"
            echo "  • Instance type: $INSTANCE_TYPE"
            echo "  • Auto-scaling: $MIN_CAPACITY-$MAX_CAPACITY instances"
            ;;
        alb)
            echo "High Availability:"
            echo "  • Load balancer: Enabled"
            echo "  • Multi-AZ: $ENABLE_MULTI_AZ"
            echo "  • Auto-scaling: $MIN_CAPACITY-$MAX_CAPACITY instances"
            ;;
        cdn)
            echo "Global Distribution:"
            echo "  • CloudFront: Enabled"
            echo "  • Price class: $CLOUDFRONT_PRICE_CLASS"
            echo "  • Origin: Application Load Balancer"
            ;;
        full)
            echo "Enterprise Features:"
            echo "  • All components enabled"
            echo "  • Cost optimization: Spot instances"
            echo "  • Global reach: CloudFront CDN"
            echo "  • High availability: ALB + Multi-AZ"
            ;;
    esac
    
    echo ""
    echo "Next Steps:"
    echo "  • Check status:  $0 --status $STACK_NAME"
    echo "  • View logs:     $0 --logs $STACK_NAME"
    echo "  • Destroy:       $0 --destroy $STACK_NAME"
    echo "=========================================="
    echo ""
}

# =============================================================================
# ROLLBACK AND CLEANUP
# =============================================================================

# Execute deployment rollback
execute_deployment_rollback() {
    log_error "Executing deployment rollback"
    
    # Set deployment state
    set_deployment_state "${STACK_NAME}" "ROLLING_BACK"
    
    # Process rollback points in reverse order
    local rollback_count=${#DEPLOYMENT_ROLLBACK_POINTS[@]}
    for ((i=$rollback_count-1; i>=0; i--)); do
        local rollback_point="${DEPLOYMENT_ROLLBACK_POINTS[$i]}"
        local point_name="${rollback_point%%:*}"
        local point_data="${rollback_point#*:}"
        
        log_info "Rolling back: $point_name"
        
        case "$point_name" in
            "cdn_created")
                if [[ "$ENABLE_CDN" == true ]]; then
                    destroy_cloudfront_infrastructure || true
                fi
                ;;
            "alb_created")
                if [[ "$ENABLE_ALB" == true ]]; then
                    destroy_alb_infrastructure || true
                fi
                ;;
            "efs_created")
                if [[ "$ENABLE_EFS" == true ]]; then
                    destroy_efs_infrastructure || true
                fi
                ;;
            "compute_created")
                destroy_compute_infrastructure || true
                ;;
            "security_created")
                destroy_security_infrastructure || true
                ;;
            "vpc_created")
                destroy_vpc_infrastructure || true
                ;;
        esac
    done
    
    # Clean up deployment state
    cleanup_deployment_state "${STACK_NAME}" "${AWS_REGION}"
    
    log_info "Rollback completed"
}

# Execute emergency cleanup
execute_emergency_cleanup() {
    log_error "Executing emergency cleanup"
    
    # Set deployment state
    set_deployment_state "${STACK_NAME}" "CLEANING_UP"
    
    # Clean up all registered resources
    for resource in "${CREATED_RESOURCES[@]}"; do
        local resource_type="${resource%%:*}"
        local remaining="${resource#*:}"
        local resource_id="${remaining%%:*}"
        local resource_region="${remaining#*:}"
        
        log_info "Cleaning up $resource_type: $resource_id in $resource_region"
        
        case "$resource_type" in
            "instance")
                aws ec2 terminate-instances \
                    --instance-ids "$resource_id" \
                    --region "$resource_region" 2>/dev/null || true
                ;;
            "auto-scaling-group")
                aws autoscaling delete-auto-scaling-group \
                    --auto-scaling-group-name "$resource_id" \
                    --force-delete \
                    --region "$resource_region" 2>/dev/null || true
                ;;
            "vpc")
                # VPC cleanup is complex, defer to module function
                delete_vpc "$resource_id" || true
                ;;
            "subnet")
                aws ec2 delete-subnet \
                    --subnet-id "$resource_id" \
                    --region "$resource_region" 2>/dev/null || true
                ;;
        esac
    done
    
    log_info "Emergency cleanup completed"
}

# Generate error report
generate_deployment_error_report() {
    local report_file="${LOG_DIR}/deployment-error-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
    "deployment": {
        "stack_name": "${STACK_NAME}",
        "deployment_type": "${DEPLOYMENT_TYPE}",
        "region": "${AWS_REGION}",
        "start_time": "${DEPLOYMENT_START_TIME}",
        "end_time": "$(date +%s)",
        "duration_seconds": $(($(date +%s) - DEPLOYMENT_START_TIME)),
        "state": "${DEPLOYMENT_STATE}",
        "error_count": ${#DEPLOYMENT_ERRORS[@]}
    },
    "errors": [
EOF
    
    local first=true
    for error in "${DEPLOYMENT_ERRORS[@]}"; do
        local error_code="${error%%:*}"
        local error_message="${error#*:}"
        
        if [[ "$first" != true ]]; then
            echo "," >> "$report_file"
        fi
        first=false
        
        cat >> "$report_file" << EOF
        {
            "code": "$error_code",
            "message": "$error_message",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        }
EOF
    done
    
    cat >> "$report_file" << EOF
    ],
    "rollback_points": ${#DEPLOYMENT_ROLLBACK_POINTS[@]},
    "created_resources": ${#CREATED_RESOURCES[@]}
}
EOF
    
    log_info "Error report generated: $report_file"
    
    # Also generate the standard error report
    generate_error_report "${LOG_DIR}/deployment-errors-$(date +%Y%m%d-%H%M%S).json"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Set up error handling
    trap 'handle_script_error $? $LINENO' ERR
    trap 'handle_script_exit' EXIT
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize deployment
    initialize_deployment
    
    # Validate configuration
    validate_deployment_configuration
    
    # Execute deployment
    execute_deployment
    
    # Check for errors
    if [ ${#DEPLOYMENT_ERRORS[@]} -gt 0 ]; then
        log_warning "Deployment completed with ${#DEPLOYMENT_ERRORS[@]} errors"
        generate_deployment_error_report
        exit 1
    fi
    
    # Exit successfully
    exit 0
}

# Cleanup deployment state
cleanup_deployment_state() {
    local stack_name="$1"
    local region="$2"
    
    log_info "Cleaning up deployment state for stack: $stack_name"
    
    # Clear variables from variable store
    if command -v clear_stack_variables &>/dev/null; then
        clear_stack_variables "$stack_name"
    fi
    
    # Remove any temporary files
    rm -f "${CONFIG_DIR}/temp/${stack_name}-"* 2>/dev/null || true
    
    # Clear deployment rollback points and errors
    DEPLOYMENT_ROLLBACK_POINTS=()
    DEPLOYMENT_ERRORS=()
    CREATED_RESOURCES=()
    
    return 0
}

# Get existing stack status
get_existing_stack_status() {
    local stack_name="$1"
    local region="$2"
    
    # Check for existing VPC with stack tag
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --region "$region" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_id" ]] && [[ "$vpc_id" != "None" ]]; then
        echo "EXISTS"
        return 0
    fi
    
    # Check deployment state file
    local state_file="${CONFIG_DIR}/deployments/${stack_name}.state"
    if [[ -f "$state_file" ]]; then
        echo "STATE_FILE_EXISTS"
        return 0
    fi
    
    echo ""
    return 1
}

# Auto cleanup existing stack in dev environments
auto_cleanup_existing_stack() {
    local stack_name="$1"
    local region="$2"
    local environment="${3:-}"
    
    # Safety check: Only allow auto-cleanup in non-production environments
    if [[ "${environment,,}" != "development" ]] && [[ "${environment,,}" != "dev" ]] && [[ "${environment,,}" != "staging" ]]; then
        log_error "Auto-cleanup is not allowed in production environments"
        log_error "Environment: $environment"
        log_error "To clean up production stacks, use manual cleanup commands"
        return 1
    fi
    
    log_info "Auto-cleaning existing stack: $stack_name in $environment environment"
    
    # Clean up deployment state
    if stack_state_exists "$stack_name"; then
        log_info "Removing stack from deployment state: $stack_name"
        delete_stack_state "$stack_name"
    fi
    
    # Clean up AWS resources
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --region "$region" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_id" ]] && [[ "$vpc_id" != "None" ]]; then
        log_info "Found existing VPC for stack: $vpc_id"
        
        # Get EC2 instances
        local instance_ids
        instance_ids=$(aws ec2 describe-instances \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
            --region "$region" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text 2>/dev/null || echo "")
        
        # Terminate instances
        if [[ -n "$instance_ids" ]]; then
            log_info "Terminating instances: $instance_ids"
            aws ec2 terminate-instances --instance-ids $instance_ids --region "$region" 2>/dev/null || true
            
            # Wait for instances to terminate
            log_info "Waiting for instances to terminate..."
            aws ec2 wait instance-terminated --instance-ids $instance_ids --region "$region" 2>/dev/null || true
        fi
        
        # Delete ALB resources if they exist
        local alb_arns
        alb_arns=$(aws elbv2 describe-load-balancers \
            --region "$region" \
            --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$alb_arns" ]] && [[ "$alb_arns" != "None" ]]; then
            for alb_arn in $alb_arns; do
                log_info "Deleting ALB: $alb_arn"
                
                # Delete listeners first
                local listener_arns
                listener_arns=$(aws elbv2 describe-listeners \
                    --load-balancer-arn "$alb_arn" \
                    --region "$region" \
                    --query 'Listeners[].ListenerArn' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$listener_arns" ]]; then
                    for listener_arn in $listener_arns; do
                        aws elbv2 delete-listener --listener-arn "$listener_arn" --region "$region" 2>/dev/null || true
                    done
                fi
                
                # Delete ALB
                aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$region" 2>/dev/null || true
            done
            
            # Wait for ALBs to be deleted
            sleep 10
        fi
        
        # Delete target groups
        local target_group_arns
        target_group_arns=$(aws elbv2 describe-target-groups \
            --region "$region" \
            --query "TargetGroups[?VpcId=='$vpc_id'].TargetGroupArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$target_group_arns" ]] && [[ "$target_group_arns" != "None" ]]; then
            for tg_arn in $target_group_arns; do
                log_info "Deleting target group: $tg_arn"
                aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$region" 2>/dev/null || true
            done
        fi
        
        # Delete security groups (except default)
        local sg_ids
        sg_ids=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --region "$region" \
            --query "SecurityGroups[?GroupName!='default'].GroupId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$sg_ids" ]]; then
            for sg_id in $sg_ids; do
                log_info "Deleting security group: $sg_id"
                aws ec2 delete-security-group --group-id "$sg_id" --region "$region" 2>/dev/null || true
            done
        fi
        
        # Delete subnets
        local subnet_ids
        subnet_ids=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --region "$region" \
            --query 'Subnets[].SubnetId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$subnet_ids" ]]; then
            for subnet_id in $subnet_ids; do
                log_info "Deleting subnet: $subnet_id"
                aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" 2>/dev/null || true
            done
        fi
        
        # Delete route tables (except main)
        local rt_ids
        rt_ids=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --region "$region" \
            --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$rt_ids" ]]; then
            for rt_id in $rt_ids; do
                log_info "Deleting route table: $rt_id"
                aws ec2 delete-route-table --route-table-id "$rt_id" --region "$region" 2>/dev/null || true
            done
        fi
        
        # Detach and delete internet gateway
        local igw_id
        igw_id=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$vpc_id" \
            --region "$region" \
            --query 'InternetGateways[0].InternetGatewayId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$igw_id" ]] && [[ "$igw_id" != "None" ]]; then
            log_info "Detaching and deleting internet gateway: $igw_id"
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$region" 2>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$region" 2>/dev/null || true
        fi
        
        # Delete VPC
        log_info "Deleting VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$region" 2>/dev/null || true
    fi
    
    log_info "Auto cleanup completed for stack: $stack_name"
}

# Check if deployment already exists
check_existing_deployment() {
    local stack_name="$1"
    local region="$2"
    
    # Use get_existing_stack_status to check if stack exists
    local stack_status
    stack_status=$(get_existing_stack_status "$stack_name" "$region")
    
    # Return 0 if stack doesn't exist (safe to proceed)
    # Return 1 if stack exists (should not proceed)
    if [[ -z "$stack_status" ]]; then
        return 0  # Stack doesn't exist, safe to proceed
    else
        return 1  # Stack exists, should not proceed
    fi
}

# Error handler for script errors
handle_script_error() {
    local exit_code=$1
    local line_number=$2
    
    log_error "Script error at line $line_number (exit code: $exit_code)"
    
    # Add to deployment errors
    DEPLOYMENT_ERRORS+=("SCRIPT_ERROR:Script failed at line $line_number")
    
    # Generate error report
    generate_deployment_error_report
    
    # Attempt cleanup based on error recovery mode
    case "$ERROR_RECOVERY_MODE" in
        automatic)
            log_info "Attempting automatic recovery"
            execute_deployment_rollback
            ;;
        manual)
            log_error "Manual intervention required"
            print_manual_recovery_instructions
            ;;
        abort|*)
            log_error "Aborting deployment"
            execute_emergency_cleanup
            ;;
    esac
}

# Exit handler
handle_script_exit() {
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Success - print summary if not already done
        if [ ${#DEPLOYMENT_ERRORS[@]} -eq 0 ] && [[ "$DEPLOYMENT_STATE" == "COMPLETED" ]]; then
            print_error_summary
        fi
    else
        # Failure - ensure error report is generated
        if [ ${#DEPLOYMENT_ERRORS[@]} -gt 0 ]; then
            generate_deployment_error_report
        fi
    fi
}

# Print manual recovery instructions
print_manual_recovery_instructions() {
    cat << EOF

========================================
MANUAL RECOVERY REQUIRED
========================================

The deployment has encountered an error that requires manual intervention.

Current State:
  - Stack: ${STACK_NAME}
  - Region: ${AWS_REGION}
  - Phase: ${DEPLOYMENT_STATE}
  - Errors: ${#DEPLOYMENT_ERRORS[@]}

Recovery Options:

1. ROLLBACK - Remove all created resources:
   $0 --rollback ${STACK_NAME}

2. RESUME - Attempt to continue deployment:
   $0 --resume ${STACK_NAME}

3. DESTROY - Force removal of all resources:
   $0 --destroy ${STACK_NAME}

4. STATUS - Check current deployment status:
   $0 --status ${STACK_NAME}

For detailed error information, check:
  - Log file: ${LOG_FILE}
  - Error report: ${LOG_DIR}/deployment-error-report-*.json

========================================

EOF
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 