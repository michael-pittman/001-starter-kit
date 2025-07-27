#!/bin/bash
# =============================================================================
# Legacy Compatibility Wrapper
# Provides backward compatibility for existing deployment scripts
# =============================================================================

# Prevent multiple sourcing
[ -n "${_LEGACY_WRAPPER_SH_LOADED:-}" ] && return 0
_LEGACY_WRAPPER_SH_LOADED=1

# =============================================================================
# MODULE LOADING
# =============================================================================

# Source the modular components
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Core modules
source "${MODULE_ROOT}/core/registry.sh"
source "${MODULE_ROOT}/core/errors.sh"

# Infrastructure modules
source "${MODULE_ROOT}/infrastructure/vpc.sh"
source "${MODULE_ROOT}/infrastructure/security.sh"
source "${MODULE_ROOT}/infrastructure/iam.sh"
source "${MODULE_ROOT}/infrastructure/efs_legacy.sh"

# Compute modules
source "${MODULE_ROOT}/compute/spot_optimizer.sh"
source "${MODULE_ROOT}/compute/provisioner.sh"

# Application modules
source "${MODULE_ROOT}/application/docker_manager.sh"
source "${MODULE_ROOT}/application/health_monitor.sh"

# =============================================================================
# LEGACY FUNCTION COMPATIBILITY WRAPPERS
# =============================================================================

# Legacy AWS deployment common functions that now use modular architecture

# Infrastructure compatibility functions
create_standard_key_pair() {
    # Delegate to IAM module
    create_standard_key_pair "$@"
}

create_standard_security_group() {
    # Delegate to security module
    create_standard_security_group "$@"
}

create_standard_iam_role() {
    # Delegate to IAM module
    create_standard_iam_role "$@"
}

create_shared_efs() {
    # Delegate to EFS module
    create_shared_efs "$@"
}

create_efs_mount_target_for_az() {
    # Delegate to EFS module
    create_efs_mount_target_for_az "$@"
}

# Compute compatibility functions
launch_spot_instance_with_failover() {
    # Delegate to spot optimizer module
    launch_spot_instance_with_failover "$@"
}

analyze_spot_pricing() {
    # Delegate to spot optimizer module
    analyze_spot_pricing "$@"
}

get_optimal_spot_configuration() {
    # Delegate to spot optimizer module
    get_optimal_spot_configuration "$@"
}

calculate_spot_savings() {
    # Delegate to spot optimizer module
    calculate_spot_savings "$@"
}

# Application compatibility functions
deploy_application_stack() {
    # Delegate to docker manager module
    deploy_application_stack "$@"
}

wait_for_apt_lock() {
    # Delegate to docker manager module
    wait_for_apt_lock "$@"
}

# =============================================================================
# ENHANCED ORCHESTRATION FUNCTIONS
# =============================================================================

# Enhanced infrastructure setup using modular components
setup_infrastructure_enhanced() {
    local stack_name="${1:-$STACK_NAME}"
    local vpc_cidr="${2:-10.0.0.0/16}"
    local subnet_cidr="${3:-10.0.1.0/24}"
    local deployment_type="${4:-simple}"
    
    echo "Setting up enhanced infrastructure for: $stack_name" >&2
    
    # Initialize registry for this deployment
    init_registry "$stack_name"
    
    # Setup network infrastructure
    local network_result
    network_result=$(setup_network_infrastructure "$stack_name" "$vpc_cidr" "$subnet_cidr")
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_INFRASTRUCTURE "Failed to setup network infrastructure"
    fi
    
    # Parse network result
    local vpc_id subnet_id igw_id
    vpc_id=$(echo "$network_result" | grep '"vpc_id"' | cut -d'"' -f4)
    subnet_id=$(echo "$network_result" | grep '"subnet_id"' | cut -d'"' -f4)
    igw_id=$(echo "$network_result" | grep '"igw_id"' | cut -d'"' -f4)
    
    # Setup comprehensive security groups
    local security_result
    security_result=$(create_comprehensive_security_groups "$vpc_id" "$stack_name" "0.0.0.0/0")
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_INFRASTRUCTURE "Failed to setup security groups"
    fi
    
    # Parse security result
    local app_sg_id alb_sg_id efs_sg_id
    app_sg_id=$(echo "$security_result" | grep '"application_sg_id"' | cut -d'"' -f4)
    alb_sg_id=$(echo "$security_result" | grep '"alb_sg_id"' | cut -d'"' -f4)
    efs_sg_id=$(echo "$security_result" | grep '"efs_sg_id"' | cut -d'"' -f4)
    
    # Setup IAM resources
    local iam_result
    iam_result=$(setup_comprehensive_iam "$stack_name" "true" "true" "false")
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_INFRASTRUCTURE "Failed to setup IAM resources"
    fi
    
    # Parse IAM result
    local role_name instance_profile
    role_name=$(echo "$iam_result" | grep '"role_name"' | cut -d'"' -f4)
    instance_profile=$(echo "$iam_result" | grep '"instance_profile"' | cut -d'"' -f4)
    
    # Setup EFS if needed for non-simple deployments
    local efs_id=""
    if [ "$deployment_type" != "simple" ]; then
        efs_id=$(create_comprehensive_efs "$stack_name" "$subnet_id" "$efs_sg_id")
        
        if [ $? -ne 0 ]; then
            echo "Warning: EFS setup failed, continuing without shared storage" >&2
        fi
    fi
    
    # Return comprehensive infrastructure information
    cat <<EOF
{
    "vpc_id": "$vpc_id",
    "subnet_id": "$subnet_id",
    "igw_id": "$igw_id",
    "application_sg_id": "$app_sg_id",
    "alb_sg_id": "$alb_sg_id",
    "efs_sg_id": "$efs_sg_id",
    "role_name": "$role_name",
    "instance_profile": "$instance_profile",
    "efs_id": "$efs_id"
}
EOF
}

# Enhanced compute deployment with multiple fallback strategies
deploy_compute_enhanced() {
    local stack_name="$1"
    local deployment_type="$2"
    local instance_type="$3"
    local infrastructure_config="$4"
    local user_data_script="$5"
    
    echo "Deploying enhanced compute for: $stack_name" >&2
    
    # Parse infrastructure configuration
    local subnet_id app_sg_id instance_profile
    subnet_id=$(echo "$infrastructure_config" | grep '"subnet_id"' | cut -d'"' -f4)
    app_sg_id=$(echo "$infrastructure_config" | grep '"application_sg_id"' | cut -d'"' -f4)
    instance_profile=$(echo "$infrastructure_config" | grep '"instance_profile"' | cut -d'"' -f4)
    
    local instance_id=""
    
    case "$deployment_type" in
        "spot")
            # Use spot optimizer for spot deployments
            local spot_price="${SPOT_PRICE:-0.50}"
            
            echo "Analyzing spot pricing for optimal deployment..." >&2
            local config
            config=$(get_optimal_spot_configuration "$instance_type" "$spot_price" "${AWS_REGION:-us-east-1}")
            
            if [ $? -eq 0 ]; then
                local recommended
                recommended=$(echo "$config" | grep '"recommended"' | cut -d':' -f2 | tr -d ' ,"')
                
                if [ "$recommended" = "true" ]; then
                    echo "Launching spot instance with optimal configuration..." >&2
                    instance_id=$(launch_spot_instance_with_failover "$stack_name" "$instance_type" "$spot_price" \
                                  "$user_data_script" "$app_sg_id" "$subnet_id" "${stack_name}-key" "$instance_profile")
                else
                    echo "Spot pricing not optimal, considering alternatives..." >&2
                    # Could implement alternative strategies here
                fi
            fi
            ;;
        "ondemand"|"simple")
            # Use standard instance provisioning
            echo "Launching on-demand instance..." >&2
            instance_id=$(launch_instance_standard "$stack_name" "$instance_type" "$user_data_script" \
                          "$app_sg_id" "$subnet_id" "${stack_name}-key" "$instance_profile")
            ;;
    esac
    
    if [ -z "$instance_id" ]; then
        throw_error $ERROR_DEPLOYMENT "Failed to launch instance for $deployment_type deployment"
    fi
    
    # Wait for instance to be ready
    echo "Waiting for instance to be ready..." >&2
    local instance_ip
    instance_ip=$(wait_for_instance_ready "$instance_id" "${AWS_REGION:-us-east-1}")
    
    if [ -z "$instance_ip" ]; then
        throw_error $ERROR_DEPLOYMENT "Failed to get instance IP address"
    fi
    
    # Return instance information
    cat <<EOF
{
    "instance_id": "$instance_id",
    "instance_ip": "$instance_ip",
    "deployment_type": "$deployment_type"
}
EOF
}

# Enhanced application deployment with comprehensive monitoring
deploy_application_enhanced() {
    local instance_ip="$1"
    local key_file="$2"
    local stack_name="$3"
    local compose_file="${4:-docker-compose.gpu-optimized.yml}"
    local environment="${5:-development}"
    
    echo "Deploying enhanced application stack..." >&2
    
    # Deploy using the modular docker manager
    deploy_application_stack "$instance_ip" "$key_file" "$stack_name" "$compose_file" "$environment" "true"
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_DEPLOYMENT "Enhanced application deployment failed"
    fi
    
    # Setup comprehensive health monitoring
    echo "Setting up enhanced health monitoring..." >&2
    setup_comprehensive_health_monitoring "$stack_name" "$instance_ip"
    
    echo "Enhanced application deployment completed successfully" >&2
    return 0
}

# =============================================================================
# ORCHESTRATION WRAPPER FOR COMPLETE DEPLOYMENT
# =============================================================================

# Complete enhanced deployment orchestrator
deploy_stack_enhanced() {
    local stack_name="$1"
    local deployment_type="${2:-spot}"
    local instance_type="${3:-g4dn.xlarge}"
    local environment="${4:-development}"
    local compose_file="${5:-docker-compose.gpu-optimized.yml}"
    
    if [ -z "$stack_name" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "deploy_stack_enhanced requires stack_name parameter"
    fi
    
    echo "Starting enhanced deployment for stack: $stack_name" >&2
    echo "  Deployment Type: $deployment_type" >&2
    echo "  Instance Type: $instance_type" >&2
    echo "  Environment: $environment" >&2
    
    # Step 1: Setup infrastructure
    echo "=== Step 1: Infrastructure Setup ===" >&2
    local infrastructure_config
    infrastructure_config=$(setup_infrastructure_enhanced "$stack_name" "10.0.0.0/16" "10.0.1.0/24" "$deployment_type")
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_DEPLOYMENT "Infrastructure setup failed"
    fi
    
    # Step 2: Generate user data
    echo "=== Step 2: User Data Generation ===" >&2
    local user_data
    user_data=$(generate_comprehensive_user_data "$stack_name" "$deployment_type" "$environment")
    
    # Step 3: Deploy compute
    echo "=== Step 3: Compute Deployment ===" >&2
    local compute_config
    compute_config=$(deploy_compute_enhanced "$stack_name" "$deployment_type" "$instance_type" \
                     "$infrastructure_config" "$user_data")
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_DEPLOYMENT "Compute deployment failed"
    fi
    
    # Parse compute configuration
    local instance_ip
    instance_ip=$(echo "$compute_config" | grep '"instance_ip"' | cut -d'"' -f4)
    
    # Step 4: Deploy application
    echo "=== Step 4: Application Deployment ===" >&2
    deploy_application_enhanced "$instance_ip" "${stack_name}-key.pem" "$stack_name" "$compose_file" "$environment"
    
    if [ $? -ne 0 ]; then
        throw_error $ERROR_DEPLOYMENT "Application deployment failed"
    fi
    
    # Step 5: Final validation and summary
    echo "=== Step 5: Deployment Validation ===" >&2
    validate_enhanced_deployment "$stack_name" "$instance_ip" "$deployment_type"
    
    # Display deployment summary
    display_enhanced_deployment_summary "$stack_name" "$deployment_type" "$instance_ip" \
                                        "$infrastructure_config" "$compute_config"
    
    echo "Enhanced deployment completed successfully!" >&2
    return 0
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Generate comprehensive user data (placeholder)
generate_comprehensive_user_data() {
    local stack_name="$1"
    local deployment_type="$2"
    local environment="$3"
    
    # This would integrate with the userdata module
    echo "Generating user data for $stack_name ($deployment_type, $environment)..." >&2
    echo "#!/bin/bash\n# Enhanced user data for $stack_name\necho 'User data executed'"
}

# Wait for instance to be ready (placeholder)
wait_for_instance_ready() {
    local instance_id="$1"
    local region="$2"
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for instance to be ready: $instance_id" >&2
    
    while [ $attempt -le $max_attempts ]; do
        local state
        state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$region" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        if [ "$state" = "running" ]; then
            local ip
            ip=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --region "$region" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text 2>/dev/null)
            
            if [ -n "$ip" ] && [ "$ip" != "None" ]; then
                echo "Instance ready with IP: $ip" >&2
                echo "$ip"
                return 0
            fi
        fi
        
        echo "Instance state: ${state:-pending}, waiting..." >&2
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo "Timeout waiting for instance to be ready" >&2
    return 1
}

# Launch standard instance (placeholder)
launch_instance_standard() {
    local stack_name="$1"
    local instance_type="$2"
    local user_data="$3"
    local security_group_id="$4"
    local subnet_id="$5"
    local key_name="$6"
    local iam_instance_profile="$7"
    
    echo "Launching standard instance: $instance_type" >&2
    # Implementation would go here - delegate to compute/provisioner.sh
    echo "i-1234567890abcdef0"  # Mock instance ID
}

# Validate enhanced deployment (placeholder)
validate_enhanced_deployment() {
    local stack_name="$1"
    local instance_ip="$2"
    local deployment_type="$3"
    
    echo "Validating enhanced deployment..." >&2
    # Implementation would go here
    return 0
}

# Display enhanced deployment summary (placeholder)
display_enhanced_deployment_summary() {
    local stack_name="$1"
    local deployment_type="$2"
    local instance_ip="$3"
    local infrastructure_config="$4"
    local compute_config="$5"
    
    echo "" >&2
    echo "=== Enhanced Deployment Summary ===" >&2
    echo "Stack Name: $stack_name" >&2
    echo "Deployment Type: $deployment_type" >&2
    echo "Instance IP: $instance_ip" >&2
    echo "Status: Deployment completed successfully" >&2
    echo "" >&2
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Enhanced cleanup using modular architecture
cleanup_enhanced_deployment() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Starting enhanced cleanup for: $stack_name" >&2
    
    # Cleanup in reverse order
    cleanup_docker_comprehensive "$stack_name"
    cleanup_spot_resources "$stack_name"
    cleanup_efs_resources "$stack_name"
    cleanup_security_resources "$stack_name"
    cleanup_iam_resources_comprehensive "$stack_name"
    
    # Cleanup registry
    cleanup_registry "$stack_name"
    
    echo "Enhanced cleanup completed" >&2
}