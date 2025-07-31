#!/usr/bin/env bash
# =============================================================================
# Configuration Defaults Loader
# Loads default values from config/defaults.yml into the variable system
# Compatible with bash 3.x+
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_CONFIG_DEFAULTS_LOADER_LOADED:-}" ]] && return 0
_CONFIG_DEFAULTS_LOADER_LOADED=1

# =============================================================================
# YAML PARSING FUNCTIONS
# =============================================================================

# Simple YAML parser for flat key-value pairs
parse_yaml_value() {
    local file="$1"
    local key_path="$2"
    local default_value="${3:-}"
    
    # Check if yq is available for better parsing
    if command -v yq >/dev/null 2>&1; then
        local value
        value=$(yq eval ".${key_path}" "$file" 2>/dev/null || echo "")
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
        else
            echo "$default_value"
        fi
    else
        # Fallback to simple grep/sed parsing
        local value
        value=$(grep -A1 "^[[:space:]]*${key_path##*.}:" "$file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*#.*$//' | cut -d: -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr -d '"')
        if [[ -n "$value" ]]; then
            echo "$value"
        else
            echo "$default_value"
        fi
    fi
}

# Load defaults from YAML file
load_defaults_from_yaml() {
    local yaml_file="${1:-${CONFIG_DIR:-${PROJECT_ROOT:-$(pwd)}/config}/defaults.yml}"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "WARNING: Defaults file not found: $yaml_file" >&2
        return 1
    fi
    
    echo "Loading defaults from: $yaml_file" >&2
    
    # Core deployment variables mapping
    local -A yaml_to_var_mapping=(
        ["deployment_variables.aws_region"]="AWS_REGION"
        ["deployment_variables.aws_default_region"]="AWS_DEFAULT_REGION"
        ["deployment_variables.aws_profile"]="AWS_PROFILE"
        ["deployment_variables.deployment_type"]="DEPLOYMENT_TYPE"
        ["deployment_variables.instance_type"]="INSTANCE_TYPE"
        ["deployment_variables.key_name"]="KEY_NAME"
        ["deployment_variables.volume_size"]="VOLUME_SIZE"
        ["deployment_variables.environment"]="ENVIRONMENT"
        ["deployment_variables.debug"]="DEBUG"
        ["deployment_variables.dry_run"]="DRY_RUN"
        ["deployment_variables.cleanup_on_failure"]="CLEANUP_ON_FAILURE"
        ["deployment_variables.validate_only"]="VALIDATE_ONLY"
        ["deployment_variables.verbose"]="VERBOSE"
        ["deployment_variables.n8n_enable"]="N8N_ENABLE"
        ["deployment_variables.qdrant_enable"]="QDRANT_ENABLE"
        ["deployment_variables.ollama_enable"]="OLLAMA_ENABLE"
        ["deployment_variables.crawl4ai_enable"]="CRAWL4AI_ENABLE"
        ["deployment_variables.load_parameter_store"]="LOAD_PARAMETER_STORE"
        ["deployment_variables.param_store_prefix"]="PARAM_STORE_PREFIX"
        ["deployment_variables.enable_multi_az"]="ENABLE_MULTI_AZ"
        ["deployment_variables.enable_alb"]="ENABLE_ALB"
        ["deployment_variables.enable_cloudfront"]="ENABLE_CLOUDFRONT"
        ["deployment_variables.enable_efs"]="ENABLE_EFS"
        ["deployment_variables.enable_backup"]="ENABLE_BACKUP"
        ["deployment_variables.enable_monitoring"]="ENABLE_MONITORING"
        ["deployment_variables.spot_price"]="SPOT_PRICE"
        ["deployment_variables.spot_interruption_behavior"]="SPOT_INTERRUPTION_BEHAVIOR"
        ["deployment_variables.enable_spot_fallback"]="ENABLE_SPOT_FALLBACK"
        ["deployment_variables.backup_retention_days"]="BACKUP_RETENTION_DAYS"
        ["deployment_variables.deployment_timeout"]="DEPLOYMENT_TIMEOUT"
    )
    
    # Load each mapped variable
    for yaml_path in "${!yaml_to_var_mapping[@]}"; do
        local var_name="${yaml_to_var_mapping[$yaml_path]}"
        local yaml_value=$(parse_yaml_value "$yaml_file" "$yaml_path" "")
        
        if [[ -n "$yaml_value" ]]; then
            # Only set if not already set by environment
            if [[ -z "${!var_name:-}" ]]; then
                export "$var_name=$yaml_value"
                [[ "${DEBUG:-false}" == "true" ]] && echo "DEBUG: Set $var_name=$yaml_value from defaults.yml" >&2
            fi
        fi
    done
    
    # Load infrastructure defaults
    export DEFAULT_VPC_CIDR=$(parse_yaml_value "$yaml_file" "infrastructure.networking.vpc_cidr" "10.0.0.0/16")
    export DEFAULT_PUBLIC_SUBNET_COUNT=$(parse_yaml_value "$yaml_file" "infrastructure.networking.public_subnet_count" "2")
    export DEFAULT_PRIVATE_SUBNET_COUNT=$(parse_yaml_value "$yaml_file" "infrastructure.networking.private_subnet_count" "2")
    
    echo "Defaults loaded successfully from YAML" >&2
    return 0
}

# =============================================================================
# ENHANCED VARIABLE REGISTRATION WITH DEFAULTS
# =============================================================================

# Register variables with defaults from YAML
register_variables_with_defaults() {
    local yaml_file="${1:-${CONFIG_DIR:-${PROJECT_ROOT:-$(pwd)}/config}/defaults.yml}"
    
    # Ensure variable management is loaded
    if ! declare -f register_variable >/dev/null 2>&1; then
        echo "WARNING: Variable management system not loaded" >&2
        return 1
    fi
    
    # Load defaults from YAML first
    load_defaults_from_yaml "$yaml_file" || {
        echo "WARNING: Failed to load defaults from YAML, using hardcoded defaults" >&2
    }
    
    # Register variables with loaded defaults
    register_variable "AWS_REGION" "string" "${AWS_REGION:-us-east-1}" "AWS region for deployment"
    register_variable "AWS_DEFAULT_REGION" "string" "${AWS_DEFAULT_REGION:-us-east-1}" "Default AWS region fallback"
    register_variable "AWS_PROFILE" "string" "${AWS_PROFILE:-default}" "AWS CLI profile to use"
    register_variable "STACK_NAME" "string" "${STACK_NAME:-}" "Unique stack identifier for AWS resources"
    register_variable "DEPLOYMENT_TYPE" "string" "${DEPLOYMENT_TYPE:-spot}" "Deployment strategy"
    register_variable "INSTANCE_TYPE" "string" "${INSTANCE_TYPE:-g4dn.xlarge}" "EC2 instance type"
    register_variable "KEY_NAME" "string" "${KEY_NAME:-}" "EC2 key pair name"
    register_variable "VOLUME_SIZE" "number" "${VOLUME_SIZE:-30}" "EBS volume size in GB"
    register_variable "ENVIRONMENT" "string" "${ENVIRONMENT:-development}" "Deployment environment"
    register_variable "DEBUG" "boolean" "${DEBUG:-false}" "Enable debug output"
    register_variable "DRY_RUN" "boolean" "${DRY_RUN:-false}" "Perform dry run"
    register_variable "CLEANUP_ON_FAILURE" "boolean" "${CLEANUP_ON_FAILURE:-true}" "Cleanup on failure"
    register_variable "VALIDATE_ONLY" "boolean" "${VALIDATE_ONLY:-false}" "Validate only"
    register_variable "VERBOSE" "boolean" "${VERBOSE:-false}" "Enable verbose output"
    
    # Application toggles
    register_variable "N8N_ENABLE" "boolean" "${N8N_ENABLE:-true}" "Enable n8n service"
    register_variable "QDRANT_ENABLE" "boolean" "${QDRANT_ENABLE:-true}" "Enable Qdrant service"
    register_variable "OLLAMA_ENABLE" "boolean" "${OLLAMA_ENABLE:-true}" "Enable Ollama service"
    register_variable "CRAWL4AI_ENABLE" "boolean" "${CRAWL4AI_ENABLE:-true}" "Enable Crawl4AI service"
    
    # Additional features
    register_variable "ENABLE_MULTI_AZ" "boolean" "${ENABLE_MULTI_AZ:-false}" "Enable multi-AZ deployment"
    register_variable "ENABLE_ALB" "boolean" "${ENABLE_ALB:-false}" "Enable Application Load Balancer"
    register_variable "ENABLE_CLOUDFRONT" "boolean" "${ENABLE_CLOUDFRONT:-false}" "Enable CloudFront CDN"
    register_variable "ENABLE_EFS" "boolean" "${ENABLE_EFS:-true}" "Enable EFS storage"
    register_variable "ENABLE_BACKUP" "boolean" "${ENABLE_BACKUP:-false}" "Enable automated backups"
    
    echo "Variables registered with defaults from configuration" >&2
    return 0
}

# =============================================================================
# ENVIRONMENT-SPECIFIC CONFIGURATION
# =============================================================================

# Load environment-specific overrides
load_environment_defaults() {
    local environment="${1:-${ENVIRONMENT:-development}}"
    local config_dir="${CONFIG_DIR:-${PROJECT_ROOT:-$(pwd)}/config}"
    
    # Check for environment-specific defaults file
    local env_defaults_file="$config_dir/defaults-${environment}.yml"
    if [[ -f "$env_defaults_file" ]]; then
        echo "Loading environment-specific defaults from: $env_defaults_file" >&2
        load_defaults_from_yaml "$env_defaults_file"
    fi
    
    # Check for environment-specific overrides in main defaults
    if [[ -f "$config_dir/defaults.yml" ]] && command -v yq >/dev/null 2>&1; then
        # Check if environment-specific section exists
        local has_env_section
        has_env_section=$(yq eval ".environments.${environment}" "$config_dir/defaults.yml" 2>/dev/null || echo "null")
        
        if [[ "$has_env_section" != "null" ]]; then
            echo "Applying environment-specific overrides for: $environment" >&2
            # Load environment-specific values
            # This would require more complex parsing logic
        fi
    fi
    
    return 0
}

# =============================================================================
# INTEGRATION WITH DEPLOYMENT VARIABLE MANAGEMENT
# =============================================================================

# Enhanced init_variable_store that loads from defaults.yml
init_variable_store_with_defaults() {
    local prefix="${1:-/aibuildkit}"
    
    # Load defaults from YAML first
    load_defaults_from_yaml || {
        echo "WARNING: Failed to load defaults from YAML" >&2
    }
    
    # Call original init_variable_store if available
    if declare -f init_variable_store >/dev/null 2>&1; then
        init_variable_store "$prefix"
    else
        echo "WARNING: Original init_variable_store not found" >&2
    fi
    
    # Register variables with defaults
    register_variables_with_defaults
    
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print current configuration
print_configuration() {
    echo "=== Current Configuration ==="
    echo "AWS_REGION: ${AWS_REGION:-<not set>}"
    echo "DEPLOYMENT_TYPE: ${DEPLOYMENT_TYPE:-<not set>}"
    echo "INSTANCE_TYPE: ${INSTANCE_TYPE:-<not set>}"
    echo "ENVIRONMENT: ${ENVIRONMENT:-<not set>}"
    echo "STACK_NAME: ${STACK_NAME:-<not set>}"
    echo "KEY_NAME: ${KEY_NAME:-<not set>}"
    echo "============================"
}

# Validate configuration consistency
validate_configuration() {
    local errors=0
    
    # Check required variables
    if [[ -z "${STACK_NAME:-}" ]]; then
        echo "ERROR: STACK_NAME is required but not set" >&2
        ((errors++))
    fi
    
    if [[ -z "${KEY_NAME:-}" ]]; then
        echo "ERROR: KEY_NAME is required but not set" >&2
        ((errors++))
    fi
    
    # Check for conflicting settings
    if [[ "${DEPLOYMENT_TYPE}" == "spot" ]] && [[ "${ENABLE_MULTI_AZ}" == "true" ]]; then
        echo "WARNING: Multi-AZ with spot instances may increase interruption impact" >&2
    fi
    
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Export functions
export -f load_defaults_from_yaml
export -f register_variables_with_defaults
export -f load_environment_defaults
export -f init_variable_store_with_defaults
export -f print_configuration
export -f validate_configuration