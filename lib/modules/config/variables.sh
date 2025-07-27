#!/bin/bash
# =============================================================================
# Centralized Variable Management System
# Provides consistent variable handling, validation, and defaults
# =============================================================================

# Prevent multiple sourcing
[ -n "${_VARIABLES_SH_LOADED:-}" ] && return 0
_VARIABLES_SH_LOADED=1

# =============================================================================
# VARIABLE REGISTRY
# =============================================================================

# Initialize variable registry (bash 3.x compatible)
_VARIABLE_REGISTRY=""
_VARIABLE_DEFAULTS=""
_VARIABLE_VALIDATORS=""

# Register a variable with default value and optional validator
register_variable() {
    local var_name="$1"
    local default_value="$2"
    local validator="${3:-}"
    
    # Add to registry
    _VARIABLE_REGISTRY="${_VARIABLE_REGISTRY}${var_name}:"
    
    # Store default value
    eval "_VARIABLE_DEFAULT_${var_name}='${default_value}'"
    
    # Store validator if provided
    if [ -n "$validator" ]; then
        eval "_VARIABLE_VALIDATOR_${var_name}='${validator}'"
    fi
}

# Get variable value with fallback to default
get_variable() {
    local var_name="$1"
    local current_value="${!var_name:-}"
    
    if [ -z "$current_value" ]; then
        # Get default value
        local default_var="_VARIABLE_DEFAULT_${var_name}"
        current_value="${!default_var:-}"
    fi
    
    echo "$current_value"
}

# Sanitize variable name for bash compatibility
sanitize_var_name() {
    local name="$1"
    # Replace hyphens with underscores and remove invalid characters
    echo "$name" | sed 's/-/_/g; s/[^a-zA-Z0-9_]/_/g'
}

# Set variable with validation
set_variable() {
    local var_name="$1"
    local value="$2"
    
    # Sanitize variable name for bash export
    local safe_var_name=$(sanitize_var_name "$var_name")
    
    # Check if validator exists
    local validator_var="_VARIABLE_VALIDATOR_${safe_var_name}"
    local validator="${!validator_var:-}"
    
    if [ -n "$validator" ]; then
        if ! $validator "$value"; then
            echo "ERROR: Invalid value '$value' for variable '$var_name'" >&2
            return 1
        fi
    fi
    
    # Set the variable using sanitized name
    eval "export ${safe_var_name}='${value}'"
    return 0
}

# =============================================================================
# VARIABLE VALIDATORS
# =============================================================================

validate_aws_region() {
    local region="$1"
    local valid_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1"
        "ap-south-1" "ap-northeast-1" "ap-northeast-2" "ap-southeast-1" "ap-southeast-2"
        "ca-central-1" "sa-east-1"
    )
    
    for valid in "${valid_regions[@]}"; do
        [ "$region" = "$valid" ] && return 0
    done
    return 1
}

validate_instance_type() {
    local instance_type="$1"
    # Basic validation - ensure it matches AWS naming pattern
    if [[ "$instance_type" =~ ^[a-z][0-9]+[a-z]*\.[a-z0-9]+$ ]]; then
        return 0
    fi
    return 1
}

validate_boolean() {
    local value="$1"
    case "$value" in
        true|false|yes|no|1|0) return 0 ;;
        *) return 1 ;;
    esac
}

validate_stack_name() {
    local name="$1"
    # AWS CloudFormation stack name rules
    if [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]] && [ ${#name} -le 128 ]; then
        return 0
    fi
    return 1
}

validate_deployment_type() {
    local type="$1"
    case "$type" in
        spot|ondemand|simple) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# CORE DEPLOYMENT VARIABLES
# =============================================================================

# Register AWS variables
register_variable "AWS_REGION" "us-east-1" "validate_aws_region"
register_variable "AWS_DEFAULT_REGION" "us-east-1" "validate_aws_region"
register_variable "AWS_PROFILE" "default"

# Register deployment variables
register_variable "STACK_NAME" "" "validate_stack_name"
register_variable "DEPLOYMENT_TYPE" "spot" "validate_deployment_type"
register_variable "INSTANCE_TYPE" "g4dn.xlarge" "validate_instance_type"
register_variable "KEY_NAME" ""
register_variable "VOLUME_SIZE" "100"
register_variable "ENVIRONMENT" "production"

# Register feature flags
register_variable "CLEANUP_ON_FAILURE" "true" "validate_boolean"
register_variable "VALIDATE_ONLY" "false" "validate_boolean"
register_variable "DRY_RUN" "false" "validate_boolean"
register_variable "DEBUG" "false" "validate_boolean"
register_variable "VERBOSE" "false" "validate_boolean"

# Register application variables
register_variable "N8N_ENABLE" "true" "validate_boolean"
register_variable "QDRANT_ENABLE" "true" "validate_boolean"
register_variable "OLLAMA_ENABLE" "true" "validate_boolean"
register_variable "CRAWL4AI_ENABLE" "true" "validate_boolean"

# =============================================================================
# PARAMETER STORE INTEGRATION
# =============================================================================

# Load variables from Parameter Store
load_from_parameter_store() {
    local prefix="${1:-/aibuildkit}"
    
    if ! command -v aws &> /dev/null; then
        echo "WARNING: AWS CLI not available, skipping Parameter Store loading" >&2
        return 1
    fi
    
    echo "Loading configuration from Parameter Store (prefix: $prefix)..." >&2
    
    # Get all parameters with prefix
    local params
    params=$(aws ssm get-parameters-by-path \
        --path "$prefix" \
        --recursive \
        --with-decryption \
        --query 'Parameters[*].[Name,Value]' \
        --output text 2>/dev/null) || {
        echo "WARNING: Failed to load from Parameter Store" >&2
        return 1
    }
    
    # Process each parameter
    while IFS=$'\t' read -r name value; do
        # Convert parameter name to environment variable
        # /aibuildkit/OPENAI_API_KEY -> OPENAI_API_KEY
        local var_name="${name#${prefix}/}"
        var_name="${var_name//\//_}"  # Replace / with _
        
        # Set the variable
        set_variable "$var_name" "$value" || {
            echo "WARNING: Failed to set $var_name from Parameter Store" >&2
        }
    done <<< "$params"
    
    return 0
}

# =============================================================================
# ENVIRONMENT FILE SUPPORT
# =============================================================================

# Load variables from environment file
load_env_file() {
    local env_file="$1"
    
    [ -f "$env_file" ] || {
        echo "ERROR: Environment file not found: $env_file" >&2
        return 1
    }
    
    echo "Loading environment from: $env_file" >&2
    
    # Read file line by line
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [ -z "$key" ] && continue
        
        # Remove quotes from value
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        
        # Set the variable
        set_variable "$key" "$value" || {
            echo "WARNING: Failed to set $key from env file" >&2
        }
    done < "$env_file"
    
    return 0
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate all required variables
validate_required_variables() {
    local required_vars=(
        "AWS_REGION"
        "STACK_NAME"
        "DEPLOYMENT_TYPE"
        "INSTANCE_TYPE"
    )
    
    local missing=()
    for var in "${required_vars[@]}"; do
        local value=$(get_variable "$var")
        if [ -z "$value" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Missing required variables: ${missing[*]}" >&2
        return 1
    fi
    
    return 0
}

# Print current configuration
print_configuration() {
    echo "=== Current Configuration ==="
    echo "AWS_REGION: $(get_variable AWS_REGION)"
    echo "STACK_NAME: $(get_variable STACK_NAME)"
    echo "DEPLOYMENT_TYPE: $(get_variable DEPLOYMENT_TYPE)"
    echo "INSTANCE_TYPE: $(get_variable INSTANCE_TYPE)"
    echo "KEY_NAME: $(get_variable KEY_NAME)"
    echo "ENVIRONMENT: $(get_variable ENVIRONMENT)"
    echo "CLEANUP_ON_FAILURE: $(get_variable CLEANUP_ON_FAILURE)"
    echo "============================"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize variables from environment
initialize_variables() {
    # Load from Parameter Store if available
    load_from_parameter_store "/aibuildkit" || true
    
    # Load from .env file if exists
    [ -f ".env" ] && load_env_file ".env" || true
    
    # Apply any environment overrides
    for var in $(echo "$_VARIABLE_REGISTRY" | tr ':' ' '); do
        [ -n "$var" ] || continue
        local env_value="${!var:-}"
        if [ -n "$env_value" ]; then
            set_variable "$var" "$env_value" || true
        fi
    done
}

# Auto-initialize on source
initialize_variables