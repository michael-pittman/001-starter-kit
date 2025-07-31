#!/usr/bin/env bash
# =============================================================================
# Deployment Variable Management Functions
# Provides standardized init_variable_store and load_environment_config
# functions for GeuseMaker deployment scripts
# Compatible with bash 3.x+
# =============================================================================

# Global variables for compatibility
declare -g VARIABLE_STORE_INITIALIZED="false"
declare -g ENVIRONMENT_CONFIG_LOADED="false"

# =============================================================================
# init_variable_store - Initialize the variable store system
# 
# This function initializes the GeuseMaker variable management system by:
# 1. Loading the core variables module
# 2. Registering standard deployment variables
# 3. Setting up parameter store integration
# 
# Usage: init_variable_store [prefix]
# Arguments:
#   prefix - Parameter store prefix (default: /aibuildkit)
# Returns:
#   0 on success, 1 on failure
# =============================================================================
init_variable_store() {
    local prefix="${1:-/aibuildkit}"
    
    # Prevent double initialization
    if [[ "$VARIABLE_STORE_INITIALIZED" == "true" ]]; then
        [[ "${DEBUG:-false}" == "true" ]] && echo "DEBUG: Variable store already initialized" >&2
        return 0
    fi
    
    echo "Initializing variable store..." >&2
    
    # Determine script and library directories
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    local lib_dir="${LIB_DIR:-$(cd "$script_dir/.." && pwd)/lib}"
    
    # Load the core variables module if not already loaded
    if ! declare -f register_variable >/dev/null 2>&1; then
        local variables_module="$lib_dir/modules/config/variables.sh"
        if [[ -f "$variables_module" ]]; then
            source "$variables_module" || {
                echo "ERROR: Failed to load variables module from $variables_module" >&2
                return 1
            }
        else
            echo "ERROR: Variables module not found at $variables_module" >&2
            return 1
        fi
    fi
    
    # Load config defaults loader if available
    local defaults_loader="$lib_dir/config-defaults-loader.sh"
    if [[ -f "$defaults_loader" ]] && ! declare -f load_defaults_from_yaml >/dev/null 2>&1; then
        source "$defaults_loader" || {
            echo "WARNING: Failed to load config defaults loader" >&2
        }
    fi
    
    # Try to load and register variables from defaults.yml first
    if declare -f register_variables_with_defaults >/dev/null 2>&1; then
        register_variables_with_defaults || {
            echo "WARNING: Failed to register variables from defaults.yml" >&2
        }
    else
        # Fallback to hardcoded registration if defaults loader not available
        if ! is_variable_registered "STACK_NAME" 2>/dev/null; then
            register_variable "STACK_NAME" "string" "" "Unique stack identifier for AWS resources"
            register_variable "AWS_REGION" "string" "us-east-1" "AWS region for deployment"
            register_variable "AWS_DEFAULT_REGION" "string" "us-east-1" "Default AWS region fallback"
            register_variable "DEPLOYMENT_TYPE" "string" "spot" "Deployment strategy: spot, ondemand, simple, alb, cdn, full, or enterprise"
            register_variable "INSTANCE_TYPE" "string" "g4dn.xlarge" "EC2 instance type"
            register_variable "KEY_NAME" "string" "" "EC2 key pair name"
            register_variable "VOLUME_SIZE" "number" "30" "EBS volume size in GB"
            register_variable "ENVIRONMENT" "string" "development" "Deployment environment"
            register_variable "DEBUG" "boolean" "false" "Enable debug output"
            register_variable "DRY_RUN" "boolean" "false" "Perform dry run without creating resources"
            register_variable "CLEANUP_ON_FAILURE" "boolean" "true" "Cleanup resources on failure"
        fi
    fi
    
    # Initialize variables with parameter store disabled by default
    # (can be enabled via environment variable or explicit call)
    local load_parameter_store="${LOAD_PARAMETER_STORE:-false}"
    local load_env_files="${LOAD_ENV_FILES:-true}"
    local load_environment="${LOAD_ENVIRONMENT:-true}"
    
    if declare -f initialize_variables >/dev/null 2>&1; then
        initialize_variables "$load_parameter_store" "$load_env_files" "$load_environment" "$prefix" || {
            echo "WARNING: Variable initialization encountered errors" >&2
        }
    fi
    
    VARIABLE_STORE_INITIALIZED="true"
    echo "Variable store initialized successfully" >&2
    return 0
}

# =============================================================================
# load_environment_config - Load environment-specific configuration
# 
# This function loads configuration based on the current environment:
# 1. Loads environment-specific .env files
# 2. Applies environment variable overrides
# 3. Validates configuration
# 
# Usage: load_environment_config [environment]
# Arguments:
#   environment - Target environment (default: from ENVIRONMENT variable)
# Returns:
#   0 on success, 1 on failure
# =============================================================================
load_environment_config() {
    local environment="${1:-${ENVIRONMENT:-development}}"
    
    # Ensure variable store is initialized
    if [[ "$VARIABLE_STORE_INITIALIZED" != "true" ]]; then
        init_variable_store || return 1
    fi
    
    echo "Loading environment configuration for: $environment" >&2
    
    # Set the environment variable
    if declare -f set_variable >/dev/null 2>&1; then
        set_variable "ENVIRONMENT" "$environment" || {
            echo "WARNING: Failed to set ENVIRONMENT variable" >&2
        }
    else
        export ENVIRONMENT="$environment"
    fi
    
    # Load environment-specific files
    local env_files=(
        ".env.$environment"
        ".env.local"
        ".env"
    )
    
    local loaded_file=""
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            echo "Loading configuration from $env_file..." >&2
            if declare -f load_env_file >/dev/null 2>&1; then
                load_env_file "$env_file" || {
                    echo "WARNING: Failed to load $env_file" >&2
                    continue
                }
            else
                # Fallback to simple source
                set -a
                source "$env_file" || {
                    echo "WARNING: Failed to source $env_file" >&2
                    set +a
                    continue
                }
                set +a
            fi
            loaded_file="$env_file"
            break
        fi
    done
    
    if [[ -z "$loaded_file" ]]; then
        echo "No environment configuration files found, using defaults" >&2
    fi
    
    # Apply environment variable overrides
    echo "Applying environment variable overrides..." >&2
    
    # Common deployment variables to check
    local deployment_vars=(
        "STACK_NAME"
        "AWS_REGION"
        "AWS_DEFAULT_REGION"
        "INSTANCE_TYPE"
        "DEPLOYMENT_TYPE"
        "KEY_NAME"
        "VOLUME_SIZE"
        "DEBUG"
        "DRY_RUN"
    )
    
    for var_name in "${deployment_vars[@]}"; do
        if [[ -n "${!var_name:-}" ]]; then
            if declare -f set_variable >/dev/null 2>&1; then
                set_variable "$var_name" "${!var_name}" || {
                    echo "WARNING: Failed to set $var_name from environment" >&2
                }
            fi
        fi
    done
    
    # Validate critical variables
    if declare -f get_variable >/dev/null 2>&1; then
        local stack_name="$(get_variable STACK_NAME 2>/dev/null || true)"
        if [[ -z "$stack_name" ]]; then
            echo "WARNING: STACK_NAME not set" >&2
        fi
    fi
    
    ENVIRONMENT_CONFIG_LOADED="true"
    echo "Environment configuration loaded successfully" >&2
    return 0
}

# =============================================================================
# Helper function to check if a variable is registered
# =============================================================================
is_variable_registered() {
    local var_name="$1"
    
    if declare -f get_variable >/dev/null 2>&1; then
        get_variable "$var_name" >/dev/null 2>&1
        return $?
    else
        # Fallback check
        [[ -n "${!var_name:-}" ]]
        return $?
    fi
}

# =============================================================================
# Convenience function to initialize both variable store and environment
# =============================================================================
init_deployment_variables() {
    local environment="${1:-${ENVIRONMENT:-development}}"
    local prefix="${2:-/aibuildkit}"
    
    echo "Initializing deployment variables for environment: $environment" >&2
    
    # Initialize variable store
    init_variable_store "$prefix" || return 1
    
    # Load environment configuration
    load_environment_config "$environment" || return 1
    
    echo "Deployment variables initialized successfully" >&2
    return 0
}

# =============================================================================
# DYNAMIC VARIABLE DETECTION AND LOADING
# =============================================================================

# Detect required variables based on deployment type
detect_deployment_variables() {
    local deployment_type="${1:-spot}"
    local stack_name="${2:-}"
    
    echo "Detecting variables for deployment type: $deployment_type" >&2
    
    # Base variables required for all deployments
    local base_vars=(
        "STACK_NAME|string||Stack identifier (required)"
        "AWS_REGION|string|us-east-1|AWS deployment region"
        "ENVIRONMENT|string|development|Deployment environment"
        "KEY_NAME|string||EC2 SSH key pair name"
    )
    
    # Type-specific variables
    local type_vars=()
    case "$deployment_type" in
        "spot")
            type_vars+=(
                "INSTANCE_TYPE|string|g4dn.xlarge|EC2 instance type for spot"
                "SPOT_PRICE|string||Maximum spot price (auto if empty)"
                "SPOT_INTERRUPTION_BEHAVIOR|string|terminate|Spot interruption behavior"
                "ENABLE_SPOT_FALLBACK|boolean|true|Fallback to on-demand if spot fails"
            )
            ;;
        "ondemand")
            type_vars+=(
                "INSTANCE_TYPE|string|g4dn.xlarge|EC2 instance type"
                "ENABLE_RESERVED_INSTANCES|boolean|false|Use reserved instances if available"
            )
            ;;
        "enterprise")
            type_vars+=(
                "INSTANCE_TYPE|string|g5.xlarge|EC2 instance type for enterprise"
                "ENABLE_MULTI_AZ|boolean|true|Deploy across multiple AZs"
                "ENABLE_ALB|boolean|true|Enable Application Load Balancer"
                "ENABLE_CLOUDFRONT|boolean|true|Enable CloudFront CDN"
                "ENABLE_EFS|boolean|true|Enable EFS for persistent storage"
                "ENABLE_BACKUP|boolean|true|Enable automated backups"
                "BACKUP_RETENTION_DAYS|number|7|Backup retention period"
            )
            ;;
    esac
    
    # Register detected variables
    for var_spec in "${base_vars[@]}" "${type_vars[@]}"; do
        IFS='|' read -r name type default desc <<< "$var_spec"
        if ! is_variable_registered "$name" 2>/dev/null; then
            register_variable "$name" "$type" "$default" "$desc"
        fi
    done
    
    echo "Detected and registered ${#base_vars[@]} base and ${#type_vars[@]} type-specific variables" >&2
}

# Load variables from existing deployment state
load_deployment_state_variables() {
    local stack_name="$1"
    
    echo "Loading variables from deployment state for: $stack_name" >&2
    
    # Check if state file exists
    local state_file="${CONFIG_DIR:-${PROJECT_ROOT:-$(pwd)}/config}/state/deployment-state.json"
    if [[ ! -f "$state_file" ]]; then
        echo "No deployment state found, using defaults" >&2
        return 0
    fi
    
    # Extract stack variables from state
    if command -v jq >/dev/null 2>&1; then
        local stack_vars=$(jq -r ".stacks[\"$stack_name\"].variables // {}" "$state_file" 2>/dev/null || echo "{}")
        
        if [[ "$stack_vars" != "{}" && "$stack_vars" != "null" ]]; then
            echo "Found existing stack variables in state" >&2
            
            # Load each variable from state
            while IFS= read -r var_name; do
                local var_value=$(echo "$stack_vars" | jq -r ".[\"$var_name\"]")
                if [[ -n "$var_value" && "$var_value" != "null" ]]; then
                    if declare -f set_variable >/dev/null 2>&1; then
                        set_variable "$var_name" "$var_value" || {
                            echo "WARNING: Failed to set $var_name from state" >&2
                        }
                    else
                        export "$var_name=$var_value"
                    fi
                fi
            done < <(echo "$stack_vars" | jq -r 'keys[]' 2>/dev/null || true)
        fi
    fi
}

# Discover AWS resources for existing stack
discover_aws_resources() {
    local stack_name="$1"
    local region="${2:-${AWS_REGION:-us-east-1}}"
    
    echo "Discovering AWS resources for stack: $stack_name in region: $region" >&2
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        echo "WARNING: AWS CLI not available, skipping resource discovery" >&2
        return 0
    fi
    
    # Try to discover CloudFormation stack resources
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" >/dev/null 2>&1; then
        echo "Found CloudFormation stack: $stack_name" >&2
        
        # Extract key resources
        local vpc_id=$(aws cloudformation describe-stack-resources \
            --stack-name "$stack_name" \
            --region "$region" \
            --query "StackResources[?ResourceType=='AWS::EC2::VPC'].PhysicalResourceId" \
            --output text 2>/dev/null || true)
        
        if [[ -n "$vpc_id" ]]; then
            export EXISTING_VPC_ID="$vpc_id"
            echo "Discovered VPC: $vpc_id" >&2
        fi
        
        # Discover other resources as needed
        local instance_id=$(aws cloudformation describe-stack-resources \
            --stack-name "$stack_name" \
            --region "$region" \
            --query "StackResources[?ResourceType=='AWS::EC2::Instance'].PhysicalResourceId" \
            --output text 2>/dev/null | head -1 || true)
        
        if [[ -n "$instance_id" ]]; then
            export EXISTING_INSTANCE_ID="$instance_id"
            echo "Discovered EC2 instance: $instance_id" >&2
            
            # Get instance details
            local instance_type=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --region "$region" \
                --query "Reservations[0].Instances[0].InstanceType" \
                --output text 2>/dev/null || true)
            
            if [[ -n "$instance_type" ]] && declare -f set_variable >/dev/null 2>&1; then
                set_variable "INSTANCE_TYPE" "$instance_type"
                echo "Discovered instance type: $instance_type" >&2
            fi
        fi
    else
        echo "No CloudFormation stack found, checking for tagged resources" >&2
        
        # Try to find resources by tags
        local instances=$(aws ec2 describe-instances \
            --filters "Name=tag:Stack,Values=$stack_name" \
            --region "$region" \
            --query "Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]" \
            --output text 2>/dev/null || true)
        
        if [[ -n "$instances" ]]; then
            echo "Found tagged EC2 instances for stack" >&2
        fi
    fi
}

# Dynamic variable initialization with state awareness
init_dynamic_variables() {
    local stack_name="${1:-}"
    local deployment_type="${2:-spot}"
    local discover_resources="${3:-true}"
    
    echo "Initializing dynamic variables for deployment" >&2
    
    # Initialize base variable store
    init_variable_store || return 1
    
    # Detect required variables based on deployment type
    detect_deployment_variables "$deployment_type" "$stack_name"
    
    # Load environment configuration
    load_environment_config || return 1
    
    # If stack name provided, load state and discover resources
    if [[ -n "$stack_name" ]]; then
        # Load variables from deployment state
        load_deployment_state_variables "$stack_name"
        
        # Discover existing AWS resources if enabled
        if [[ "$discover_resources" == "true" ]]; then
            discover_aws_resources "$stack_name"
        fi
    fi
    
    # Validate required variables
    validate_required_variables "$deployment_type"
    
    echo "Dynamic variable initialization complete" >&2
    return 0
}

# Validate required variables for deployment type
validate_required_variables() {
    local deployment_type="${1:-spot}"
    local missing_vars=()
    
    echo "Validating required variables for $deployment_type deployment" >&2
    
    # Check base required variables
    local required_vars=("STACK_NAME" "AWS_REGION" "KEY_NAME")
    
    # Add type-specific required variables
    case "$deployment_type" in
        "enterprise")
            required_vars+=("INSTANCE_TYPE")
            ;;
    esac
    
    # Check each required variable
    for var_name in "${required_vars[@]}"; do
        local var_value
        if declare -f get_variable >/dev/null 2>&1; then
            var_value="$(get_variable "$var_name" 2>/dev/null || true)"
        else
            var_value="${!var_name:-}"
        fi
        
        if [[ -z "$var_value" ]]; then
            missing_vars+=("$var_name")
        fi
    done
    
    # Report missing variables
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "WARNING: Missing required variables: ${missing_vars[*]}" >&2
        echo "Please set these variables before deployment" >&2
        return 1
    fi
    
    echo "All required variables validated successfully" >&2
    return 0
}

# Save current variables to deployment state
save_variables_to_state() {
    local stack_name="$1"
    
    echo "Saving variables to deployment state for: $stack_name" >&2
    
    # Ensure state directory exists
    local state_dir="${CONFIG_DIR:-${PROJECT_ROOT:-$(pwd)}/config}/state"
    mkdir -p "$state_dir"
    
    local state_file="$state_dir/deployment-state.json"
    
    # Initialize state file if needed
    if [[ ! -f "$state_file" ]]; then
        echo '{}' > "$state_file"
    fi
    
    # Build variables object
    local vars_json="{}"
    local deployment_vars=(
        "STACK_NAME" "AWS_REGION" "DEPLOYMENT_TYPE" "INSTANCE_TYPE"
        "KEY_NAME" "VOLUME_SIZE" "ENVIRONMENT" "SPOT_PRICE"
        "ENABLE_MULTI_AZ" "ENABLE_ALB" "ENABLE_CLOUDFRONT" "ENABLE_EFS"
    )
    
    for var_name in "${deployment_vars[@]}"; do
        local var_value
        if declare -f get_variable >/dev/null 2>&1; then
            var_value="$(get_variable "$var_name" 2>/dev/null || true)"
        else
            var_value="${!var_name:-}"
        fi
        
        if [[ -n "$var_value" ]]; then
            vars_json=$(echo "$vars_json" | jq --arg key "$var_name" --arg val "$var_value" '.[$key] = $val')
        fi
    done
    
    # Update state file
    if command -v jq >/dev/null 2>&1; then
        jq --arg stack "$stack_name" --argjson vars "$vars_json" \
            '.stacks[$stack].variables = $vars' "$state_file" > "${state_file}.tmp" && \
            mv "${state_file}.tmp" "$state_file"
        echo "Variables saved to deployment state" >&2
    fi
}

# Export functions for use in other scripts
export -f init_variable_store
export -f load_environment_config
export -f init_deployment_variables
export -f is_variable_registered
export -f detect_deployment_variables
export -f load_deployment_state_variables
export -f discover_aws_resources
export -f init_dynamic_variables
export -f validate_required_variables
export -f save_variables_to_state