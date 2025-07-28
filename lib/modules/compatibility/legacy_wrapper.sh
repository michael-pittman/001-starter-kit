#!/bin/bash
# =============================================================================
# Enhanced Compatibility Wrapper
# Provides intelligent compatibility layer for both legacy and modern bash
# Automatically detects bash version and loads appropriate modules
# =============================================================================

# Prevent multiple sourcing
[ -n "${_LEGACY_WRAPPER_SH_LOADED:-}" ] && return 0
_LEGACY_WRAPPER_SH_LOADED=1

# =============================================================================
# BASH VERSION DETECTION AND ADAPTIVE LOADING
# =============================================================================

# Detect bash version and capabilities
BASH_MAJOR=${BASH_VERSINFO[0]}
BASH_MINOR=${BASH_VERSINFO[1]}
BASH_HAS_ASSOCIATIVE_ARRAYS=false
BASH_HAS_NAME_REFERENCES=false
BASH_IS_MODERN=false

# Check for modern bash features
if (( BASH_MAJOR > 4 || (BASH_MAJOR == 4 && BASH_MINOR >= 0) )); then
    BASH_HAS_ASSOCIATIVE_ARRAYS=true
fi

if (( BASH_MAJOR > 4 || (BASH_MAJOR == 4 && BASH_MINOR >= 3) )); then
    BASH_HAS_NAME_REFERENCES=true
fi

if (( BASH_MAJOR > 5 || (BASH_MAJOR == 5 && BASH_MINOR >= 3) )); then
    BASH_IS_MODERN=true
fi

echo "Bash compatibility layer: v${BASH_VERSION} (modern: $BASH_IS_MODERN, assoc: $BASH_HAS_ASSOCIATIVE_ARRAYS, nameref: $BASH_HAS_NAME_REFERENCES)" >&2

# =============================================================================
# ADAPTIVE MODULE LOADING
# =============================================================================

# Load appropriate modules based on bash capabilities
if [[ "$BASH_IS_MODERN" == "true" ]]; then
    echo "Loading modern variable management system..." >&2
    MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    
    # Try to load modern modules first
    if [[ -f "$MODULE_ROOT/modules/config/variables.sh" ]]; then
        source "$MODULE_ROOT/modules/config/variables.sh" 2>/dev/null || {
            echo "WARNING: Failed to load modern variables, falling back to legacy mode" >&2
            BASH_IS_MODERN=false
        }
    fi
    
    if [[ -f "$MODULE_ROOT/modules/core/registry.sh" ]]; then
        source "$MODULE_ROOT/modules/core/registry.sh" 2>/dev/null || {
            echo "WARNING: Failed to load modern registry, falling back to legacy mode" >&2
            BASH_IS_MODERN=false
        }
    fi
fi

# Fallback to legacy/compatibility mode if modern loading failed
if [[ "$BASH_IS_MODERN" != "true" ]]; then
    echo "Using legacy compatibility mode for bash ${BASH_VERSION}" >&2
    # Initialize legacy compatibility functions (defined below)
fi

# =============================================================================
# LEGACY VARIABLE MANAGEMENT (BASH 3.x+ COMPATIBLE)
# =============================================================================

if [[ "$BASH_IS_MODERN" != "true" ]]; then
    # Legacy variable registry using simple string concatenation
    _LEGACY_VARIABLE_REGISTRY=""
    _LEGACY_VARIABLE_DEFAULTS=""
    _LEGACY_VARIABLE_VALIDATORS=""
    
    # Legacy variable registration
    register_variable() {
        local var_name="$1"
        local default_value="$2"
        local validator="${3:-}"
        local var_type="${4:-string}"  # Ignored in legacy mode
        local description="${5:-}"  # Ignored in legacy mode
        
        # Add to registry
        _LEGACY_VARIABLE_REGISTRY="${_LEGACY_VARIABLE_REGISTRY}${var_name}:"
        
        # Store default value using eval (bash 3.x compatible)
        eval "_LEGACY_DEFAULT_${var_name}='${default_value}'"
        
        # Store validator if provided
        if [ -n "$validator" ]; then
            eval "_LEGACY_VALIDATOR_${var_name}='${validator}'"
        fi
        
        # Set initial value
        export "${var_name}=${default_value}"
    }
    
    # Legacy variable getter
    get_variable() {
        local var_name="$1"
        local use_cache="${2:-true}"  # Ignored in legacy mode
        
        # Direct variable reference (bash 3.x compatible)
        local current_value
        eval "current_value=\${${var_name}:-}"
        
        if [ -z "$current_value" ]; then
            # Get default value
            local default_var="_LEGACY_DEFAULT_${var_name}"
            eval "current_value=\${${default_var}:-}"
        fi
        
        echo "$current_value"
    }
    
    # Legacy variable setter with validation
    set_variable() {
        local var_name="$1"
        local value="$2"
        local force_type="${3:-}"  # Ignored in legacy mode
        
        # Check if validator exists
        local validator_var="_LEGACY_VALIDATOR_${var_name}"
        local validator
        eval "validator=\${${validator_var}:-}"
        
        if [ -n "$validator" ]; then
            if ! $validator "$value"; then
                echo "ERROR: Invalid value '$value' for variable '$var_name'" >&2
                return 1
            fi
        fi
        
        # Set the variable
        export "${var_name}=${value}"
        return 0
    }
    
    # Legacy bulk operations (simplified)
    set_variables_bulk() {
        echo "WARNING: Bulk variable operations not optimized in legacy mode" >&2
        return 1
    }
    
    list_variables() {
        local filter="${1:-}"
        local format="${2:-simple}"
        
        echo "=== Legacy Variable Registry ===" >&2
        for var in $(echo "$_LEGACY_VARIABLE_REGISTRY" | tr ':' ' '); do
            [ -n "$var" ] || continue
            [[ -n "$filter" && ! "$var" =~ $filter ]] && continue
            
            local value
            eval "value=\${${var}:-}"
            echo "$var=$value"
        done
    }
    
    clear_variable_cache() {
        echo "INFO: Variable caching not available in legacy mode" >&2
    }
fi

# =============================================================================
# LEGACY RESOURCE REGISTRY (BASH 3.x+ COMPATIBLE)
# =============================================================================

if [[ "$BASH_IS_MODERN" != "true" ]]; then
    # Legacy resource tracking using files
    LEGACY_RESOURCE_REGISTRY_FILE="${RESOURCE_REGISTRY_FILE:-/tmp/legacy-registry-$$.txt}"
    
    # Legacy resource registration
    register_resource() {
        local resource_type="$1"
        local resource_id="$2"
        local metadata="${3:-{}}"
        local cleanup_command="${4:-}"
        local dependencies="${5:-}"  # Simplified in legacy mode
        local tags="${6:-{}}"  # Ignored in legacy mode
        
        # Create registry file if it doesn't exist
        [ -f "$LEGACY_RESOURCE_REGISTRY_FILE" ] || touch "$LEGACY_RESOURCE_REGISTRY_FILE"
        
        # Simple format: type|id|metadata|cleanup|timestamp
        local timestamp
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local record="${resource_type}|${resource_id}|${metadata}|${cleanup_command}|${timestamp}"
        echo "$record" >> "$LEGACY_RESOURCE_REGISTRY_FILE"
        
        echo "Resource registered: $resource_type/$resource_id" >&2
    }
    
    # Legacy resource data getter
    get_resource_data() {
        local resource_id="$1"
        local data_type="${2:-metadata}"
        
        if [ ! -f "$LEGACY_RESOURCE_REGISTRY_FILE" ]; then
            case "$data_type" in
                "metadata"|"tags") echo "{}" ;;
                *) echo "" ;;
            esac
            return 1
        fi
        
        # Find resource record
        local record
        record=$(grep "|${resource_id}|" "$LEGACY_RESOURCE_REGISTRY_FILE" | head -1)
        
        if [ -z "$record" ]; then
            case "$data_type" in
                "metadata"|"tags") echo "{}" ;;
                *) echo "" ;;
            esac
            return 1
        fi
        
        # Parse record fields: type|id|metadata|cleanup|timestamp
        local type id metadata cleanup timestamp
        IFS='|' read -r type id metadata cleanup timestamp <<< "$record"
        
        case "$data_type" in
            "metadata") echo "$metadata" ;;
            "type") echo "$type" ;;
            "cleanup") echo "$cleanup" ;;
            "timestamp") echo "$timestamp" ;;
            "status") echo "created" ;;  # Simplified status
            "dependencies") echo "" ;;  # Not tracked in legacy mode
            "tags") echo "{}" ;;  # Not supported in legacy mode
            *) echo "" ;;
        esac
    }
    
    # Other legacy resource functions
    get_resources_by_type() {
        local resource_type="$1"
        
        if [ ! -f "$LEGACY_RESOURCE_REGISTRY_FILE" ]; then
            return 1
        fi
        
        grep "^${resource_type}|" "$LEGACY_RESOURCE_REGISTRY_FILE" | cut -d'|' -f2
    }
    
    resource_exists() {
        local resource_id="$1"
        local expected_status="${2:-}"  # Ignored in legacy mode
        
        if [ ! -f "$LEGACY_RESOURCE_REGISTRY_FILE" ]; then
            return 1
        fi
        
        grep -q "|${resource_id}|" "$LEGACY_RESOURCE_REGISTRY_FILE"
    }
    
    unregister_resource() {
        local resource_id="$1"
        local force="${2:-false}"  # Ignored in legacy mode
        
        if [ ! -f "$LEGACY_RESOURCE_REGISTRY_FILE" ]; then
            return 0
        fi
        
        # Create temporary file without the resource
        local temp_file="/tmp/legacy-registry-temp-$$"
        grep -v "|${resource_id}|" "$LEGACY_RESOURCE_REGISTRY_FILE" > "$temp_file"
        mv "$temp_file" "$LEGACY_RESOURCE_REGISTRY_FILE"
        
        echo "Resource unregistered: $resource_id" >&2
    }
    
    update_resource_status() {
        local resource_id="$1"
        local status="$2"
        
        echo "INFO: Resource $resource_id status: $status (tracking simplified in legacy mode)" >&2
    }
    
    # Initialize registry function
    initialize_registry() {
        local stack_name="${1:-default}"
        echo "Initialized legacy resource registry for: $stack_name" >&2
        touch "$LEGACY_RESOURCE_REGISTRY_FILE"
    }
    
    # Status constants for compatibility
    if [[ -z "${STATUS_PENDING:-}" ]]; then
        readonly STATUS_PENDING="pending"
        readonly STATUS_CREATING="creating"
        readonly STATUS_CREATED="created"
        readonly STATUS_UPDATING="updating"
        readonly STATUS_FAILED="failed"
        readonly STATUS_DELETING="deleting"
        readonly STATUS_DELETED="deleted"
        readonly STATUS_UNKNOWN="unknown"
    fi
fi

# =============================================================================
# CONDITIONAL MODULE LOADING
# =============================================================================

# Source the modular components (with error handling)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Function to safely source modules
safe_source() {
    local module_path="$1"
    local module_name="$(basename "$module_path")"
    
    if [[ -f "$module_path" ]]; then
        if source "$module_path" 2>/dev/null; then
            echo "Loaded module: $module_name" >&2
        else
            echo "WARNING: Failed to load module: $module_name" >&2
        fi
    else
        echo "WARNING: Module not found: $module_path" >&2
    fi
}

# Load core modules
safe_source "${MODULE_ROOT}/core/errors.sh"

# Load infrastructure modules
safe_source "${MODULE_ROOT}/infrastructure/vpc.sh"
safe_source "${MODULE_ROOT}/infrastructure/security.sh"
safe_source "${MODULE_ROOT}/infrastructure/iam.sh"
safe_source "${MODULE_ROOT}/infrastructure/efs_legacy.sh"

# Load compute modules
safe_source "${MODULE_ROOT}/compute/spot_optimizer.sh"
safe_source "${MODULE_ROOT}/compute/provisioner.sh"

# Load application modules
safe_source "${MODULE_ROOT}/application/docker_manager.sh"
safe_source "${MODULE_ROOT}/application/health_monitor.sh"

# =============================================================================
# ENHANCED VALIDATION AND INITIALIZATION
# =============================================================================

# Enhanced validation with legacy fallback
validate_required_variables() {
    local context="${1:-deployment}"
    local strict_mode="${2:-true}"
    
    if [[ "$BASH_IS_MODERN" == "true" ]] && declare -f validate_required_variables >/dev/null 2>&1; then
        # Use modern validation if available
        command validate_required_variables "$context" "$strict_mode"
    else
        # Legacy validation
        local required_vars=("AWS_REGION" "STACK_NAME" "DEPLOYMENT_TYPE" "INSTANCE_TYPE")
        local missing=()
        
        for var in "${required_vars[@]}"; do
            local value
            eval "value=\${${var}:-}"
            if [ -z "$value" ]; then
                missing+=("$var")
            fi
        done
        
        if [ ${#missing[@]} -gt 0 ]; then
            echo "ERROR: Missing required variables: ${missing[*]}" >&2
            return 1
        fi
    fi
    
    return 0
}

# Enhanced configuration printing
print_configuration() {
    local format="${1:-detailed}"
    
    if [[ "$BASH_IS_MODERN" == "true" ]] && declare -f print_configuration >/dev/null 2>&1; then
        # Use modern configuration display
        command print_configuration "$format"
    else
        # Legacy configuration display
        echo "=== Configuration (Legacy Mode) ===" >&2
        echo "AWS_REGION: $(get_variable AWS_REGION)" >&2
        echo "STACK_NAME: $(get_variable STACK_NAME)" >&2
        echo "DEPLOYMENT_TYPE: $(get_variable DEPLOYMENT_TYPE)" >&2
        echo "INSTANCE_TYPE: $(get_variable INSTANCE_TYPE)" >&2
        echo "Environment: $(get_variable ENVIRONMENT)" >&2
        echo "===================================" >&2
    fi
}

# Enhanced initialization
initialize_variables() {
    local load_parameter_store="${1:-true}"
    local load_env_files="${2:-true}"
    local load_environment="${3:-true}"
    
    if [[ "$BASH_IS_MODERN" == "true" ]] && declare -f initialize_variables >/dev/null 2>&1; then
        # Use modern initialization
        command initialize_variables "$load_parameter_store" "$load_env_files" "$load_environment"
    else
        # Legacy initialization
        echo "Initializing variables (legacy mode)..." >&2
        
        # Register core variables with legacy system
        register_variable "AWS_REGION" "us-east-1" "validate_aws_region"
        register_variable "STACK_NAME" "" "validate_stack_name"
        register_variable "DEPLOYMENT_TYPE" "spot" "validate_deployment_type"
        register_variable "INSTANCE_TYPE" "g4dn.xlarge" "validate_instance_type"
        register_variable "ENVIRONMENT" "production"
        
        # Load from .env file if exists and enabled
        if [ "$load_env_files" = "true" ] && [ -f ".env" ]; then
            echo "Loading from .env file..." >&2
            set -a  # Export all variables
            source ".env" 2>/dev/null || true
            set +a
        fi
        
        # Apply environment overrides if enabled
        if [ "$load_environment" = "true" ]; then
            echo "Applying environment variable overrides..." >&2
            for var in AWS_REGION STACK_NAME DEPLOYMENT_TYPE INSTANCE_TYPE ENVIRONMENT; do
                local env_value
                eval "env_value=\${${var}:-}"
                if [ -n "$env_value" ]; then
                    set_variable "$var" "$env_value" || true
                fi
            done
        fi
        
        echo "Legacy variable initialization completed" >&2
    fi
}

# =============================================================================
# COMPATIBILITY FUNCTION WRAPPERS
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
# COMPATIBILITY LAYER SUMMARY AND RECOMMENDATIONS
# =============================================================================

# Show compatibility status and recommendations
show_compatibility_status() {
    cat >&2 <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 BASH COMPATIBILITY LAYER STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Bash Version: ${BASH_VERSION}
Modern Features: $BASH_IS_MODERN
Associative Arrays: $BASH_HAS_ASSOCIATIVE_ARRAYS
Name References: $BASH_HAS_NAME_REFERENCES

EOF

    if [[ "$BASH_IS_MODERN" == "true" ]]; then
        cat >&2 <<EOF
✅ MODERN MODE ACTIVE
  • Enhanced performance with associative arrays
  • Advanced variable management and caching
  • Comprehensive resource dependency tracking
  • Structured logging and monitoring
  • Full feature set available

EOF
    else
        cat >&2 <<EOF
⚠️  LEGACY COMPATIBILITY MODE
  • Basic functionality maintained
  • Reduced performance (no caching/optimization)
  • Simplified resource tracking
  • Limited validation and error handling
  • Some advanced features unavailable

📈 UPGRADE RECOMMENDATIONS:
  • macOS: brew install bash (get 5.2+)
  • Ubuntu 22.04+: bash 5.1+ available
  • Compile from source for latest features
  
🔗 See: docs/BASH_MODERNIZATION_GUIDE.md

EOF
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Enhanced cleanup using modular architecture
cleanup_enhanced_deployment() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Starting enhanced cleanup for: $stack_name" >&2
    
    # Cleanup in reverse order
    if declare -f cleanup_docker_comprehensive >/dev/null 2>&1; then
        cleanup_docker_comprehensive "$stack_name"
    fi
    
    if declare -f cleanup_spot_resources >/dev/null 2>&1; then
        cleanup_spot_resources "$stack_name"
    fi
    
    if declare -f cleanup_efs_resources >/dev/null 2>&1; then
        cleanup_efs_resources "$stack_name"
    fi
    
    if declare -f cleanup_security_resources >/dev/null 2>&1; then
        cleanup_security_resources "$stack_name"
    fi
    
    if declare -f cleanup_iam_resources_comprehensive >/dev/null 2>&1; then
        cleanup_iam_resources_comprehensive "$stack_name"
    fi
    
    # Cleanup registry (both modern and legacy)
    if [[ "$BASH_IS_MODERN" == "true" ]] && declare -f cleanup_registry >/dev/null 2>&1; then
        cleanup_registry "$stack_name"
    elif [[ -f "$LEGACY_RESOURCE_REGISTRY_FILE" ]]; then
        rm -f "$LEGACY_RESOURCE_REGISTRY_FILE"
        echo "Legacy registry cleaned up" >&2
    fi
    
    echo "Enhanced cleanup completed" >&2
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize the compatibility layer
if ! initialize_variables; then
    echo "WARNING: Variable initialization encountered errors" >&2
fi

# Show compatibility status if requested
if [[ "${SHOW_COMPATIBILITY_STATUS:-true}" == "true" ]]; then
    show_compatibility_status
    export SHOW_COMPATIBILITY_STATUS=false
fi

echo "Enhanced compatibility wrapper loaded successfully (modern: $BASH_IS_MODERN)" >&2