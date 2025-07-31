#!/usr/bin/env bash
# =============================================================================
# Centralized Variable Management System
# Implementation with enhanced type safety and performance
# Provides consistent variable handling, validation, and defaults
# Compatible with bash 3.x+
# =============================================================================

# Compatible with bash 3.x+

# Prevent multiple sourcing
[ -n "${_VARIABLES_SH_LOADED:-}" ] && return 0
declare -gr _VARIABLES_SH_LOADED=1

# =============================================================================
# MODERN VARIABLE REGISTRY WITH ASSOCIATIVE ARRAYS
# =============================================================================

# Variable registry using associative arrays
declare -gA _VARIABLE_REGISTRY=()
declare -gA _VARIABLE_DEFAULTS=()
declare -gA _VARIABLE_VALIDATORS=()
declare -gA _VARIABLE_TYPES=()
declare -gA _VARIABLE_DESCRIPTIONS=()

# Performance enhancement: cache for frequently accessed variables
declare -gA _VARIABLE_CACHE=()
declare -gi _CACHE_TTL=300  # 5 minutes cache TTL
declare -gA _CACHE_TIMESTAMPS=()

# Register a variable with enhanced metadata and type safety
register_variable() {
    local -n var_name_ref="$1"  # Use name reference for efficiency
    local var_name="$1"
    local default_value="$2"
    local validator="${3:-}"
    local var_type="${4:-string}"  # string, integer, boolean, array
    local description="${5:-}"
    
    # Validate variable name format
    if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Invalid variable name format: $var_name (must start with letter/underscore, contain only alphanumeric and underscores)"
    fi
    
    # Register in associative arrays with enhanced metadata
    _VARIABLE_REGISTRY["$var_name"]=1
    _VARIABLE_DEFAULTS["$var_name"]="$default_value"
    _VARIABLE_TYPES["$var_name"]="$var_type"
    
    # Store validator and description if provided
    [[ -n "$validator" ]] && _VARIABLE_VALIDATORS["$var_name"]="$validator"
    [[ -n "$description" ]] && _VARIABLE_DESCRIPTIONS["$var_name"]="$description"
    
    # Initialize with default value using proper typing
    case "$var_type" in
        "integer")
            declare -gi "$var_name"="$default_value"
            ;;
        "array")
            declare -ga "$var_name"  # Global array
            ;;
        "boolean")
            declare -g "$var_name"="$default_value"
            ;;
        "string")
            declare -g "$var_name"="$default_value"
            ;;
        *)
            throw_error $ERROR_VALIDATION_FORMAT "Unknown variable type: $var_type for $var_name"
            ;;
    esac
}

# Get variable value with enhanced caching and type safety
get_variable() {
    local var_name="$1"
    local use_cache="${2:-true}"
    
    # Validate variable name
    if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Invalid variable name: $var_name (must start with letter/underscore, contain only alphanumeric and underscores)"
    fi
    
    # Check if variable is registered
    # Use portable test for array key existence
    if [[ ! ${_VARIABLE_REGISTRY["$var_name"]+isset} ]]; then
        throw_error $ERROR_VALIDATION_REQUIRED "Variable $var_name not registered"
    fi
    
    # Check cache first for performance
    # Use portable test for cache existence
    if [[ "$use_cache" == "true" && ${_VARIABLE_CACHE["$var_name"]+isset} ]]; then
        local cache_time="${_CACHE_TIMESTAMPS[$var_name]:-0}"
        local current_time="$(date +%s)"
        if (( current_time - cache_time < _CACHE_TTL )); then
            echo "${_VARIABLE_CACHE[$var_name]}"
            return 0
        fi
    fi
    
    # Use name reference for efficient variable access
    local -n var_ref="$var_name"
    local current_value="${var_ref:-}"
    
    # Fallback to default if empty
    if [[ -z "$current_value" && -v _VARIABLE_DEFAULTS["$var_name"] ]]; then
        current_value="${_VARIABLE_DEFAULTS[$var_name]}"
    fi
    
    # Update cache
    if [[ "$use_cache" == "true" ]]; then
        _VARIABLE_CACHE["$var_name"]="$current_value"
        _CACHE_TIMESTAMPS["$var_name"]="$(date +%s)"
    fi
    
    echo "$current_value"
}

# Sanitize variable name for bash compatibility
sanitize_var_name() {
    local name="$1"
    # Replace hyphens with underscores and remove invalid characters
    echo "$name" | sed 's/-/_/g; s/[^a-zA-Z0-9_]/_/g'
}

# Sanitize AWS CLI output to remove control characters and newlines
sanitize_aws_value() {
    local value="$1"
    
    # Remove common problematic patterns from AWS CLI output
    value=$(echo "$value" | tr -d '\n\r\t' | tr -d '\000-\037')
    
    # Remove 'null' prefix if present (common AWS CLI issue)
    value=$(echo "$value" | sed 's/^null//g')
    
    # Remove 'None' if that's the only content
    if [ "$value" = "None" ]; then
        value=""
    fi
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    
    echo "$value"
}

# Set variable with enhanced validation and type checking
set_variable() {
    local var_name="$1"
    local value="$2"
    local force_type="${3:-}"  # Optional type override
    
    # Sanitize variable name first
    var_name=$(sanitize_var_name "$var_name")
    
    # Validate variable name after sanitization
    if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Invalid variable name format even after sanitization: $var_name (must start with letter/underscore, contain only alphanumeric and underscores)"
    fi
    
    # Check if variable is registered
    if [[ ! -v _VARIABLE_REGISTRY["$var_name"] ]]; then
        throw_error $ERROR_VALIDATION_REQUIRED "Setting unregistered variable: $var_name"
    fi
    
    # Get variable type for validation
    local var_type="${force_type:-${_VARIABLE_TYPES[$var_name]:-string}}"
    
    # Sanitize AWS-related values to prevent corruption
    if [[ "$var_name" =~ (VPC|SUBNET|.*_ID|.*_ARN) ]]; then
        value=$(sanitize_aws_value "$value")
        if [[ "${DEBUG:-false}" == "true" ]]; then
            echo "DEBUG: AWS value sanitization for $var_name = '$value'" >&2
        fi
    fi
    
    # Type-specific validation and conversion
    case "$var_type" in
        "integer")
            if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
                throw_error $ERROR_VALIDATION_FORMAT "Invalid integer value '$value' for variable '$var_name'"
            fi
            ;;
        "boolean")
            case "${value,,}" in  # Convert to lowercase
                true|yes|1|on|enabled) value="true" ;;
                false|no|0|off|disabled) value="false" ;;
                *) 
                    throw_error $ERROR_VALIDATION_FORMAT "Invalid boolean value '$value' for variable '$var_name'"
                    ;;
            esac
            ;;
        "array")
            # For arrays, value should be space-separated or JSON
            if [[ "$value" =~ ^\[.*\]$ ]]; then
                # JSON array format - would need jq for proper parsing
                echo "WARNING: JSON array format detected, ensure proper handling" >&2
            fi
            ;;
    esac
    
    # Run custom validator if present
    if [[ -v _VARIABLE_VALIDATORS["$var_name"] ]]; then
        local validator="${_VARIABLE_VALIDATORS[$var_name]}"
        # Guard against executing non-function values
        if declare -F "$validator" >/dev/null 2>&1; then
            if ! "$validator" "$value"; then
                throw_error $ERROR_VALIDATION_FAILED "Validation failed for variable '$var_name' with value '$value'"
            fi
        else
            echo "WARNING: Validator '$validator' for variable '$var_name' is not a declared function, skipping validation" >&2
        fi
    fi
    
    # Set the variable using name reference for efficiency
    local -n var_ref="$var_name"
    var_ref="$value"
    
    # Clear cache for this variable
    unset _VARIABLE_CACHE["$var_name"]
    unset _CACHE_TIMESTAMPS["$var_name"]
    
    # Export if it's a global variable
    export "$var_name"
    
    return 0
}

# =============================================================================
# ENHANCED VARIABLE VALIDATORS WITH ASSOCIATIVE ARRAYS
# =============================================================================

# Cache valid AWS regions for performance
declare -gA _VALID_AWS_REGIONS=(
    ["us-east-1"]=1 ["us-east-2"]=1 ["us-west-1"]=1 ["us-west-2"]=1
    ["eu-west-1"]=1 ["eu-west-2"]=1 ["eu-west-3"]=1 ["eu-central-1"]=1 ["eu-north-1"]=1
    ["ap-south-1"]=1 ["ap-northeast-1"]=1 ["ap-northeast-2"]=1 ["ap-northeast-3"]=1
    ["ap-southeast-1"]=1 ["ap-southeast-2"]=1 ["ap-southeast-3"]=1 ["ap-east-1"]=1
    ["ca-central-1"]=1 ["sa-east-1"]=1 ["af-south-1"]=1 ["me-south-1"]=1
)

# Optimized AWS region validator using associative array lookup
validate_aws_region() {
    local region="$1"
    
    # O(1) lookup instead of O(n) iteration
    [[ -v _VALID_AWS_REGIONS["$region"] ]]
}

# Enhanced instance type validation with family-specific rules
validate_instance_type() {
    local instance_type="$1"
    
    # Enhanced pattern validation with detailed feedback
    if [[ ! "$instance_type" =~ ^[a-z][0-9]+[a-z]*\.[a-z0-9]+$ ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Instance type '$instance_type' doesn't match AWS naming pattern. Expected format: family[generation][attributes].size (e.g., m5.large, g4dn.xlarge)"
    fi
    
    # Extract family for additional validation
    local family="${instance_type%%.*}"
    
    # Validate known GPU families for GeuseMaker
    case "$family" in
        g4dn|g5|g5g|p3|p4d|inf1|inf2)
            # GPU/ML optimized instances - good for GeuseMaker
            return 0
            ;;
        m5|m5a|m5n|c5|c5n|r5|r5a|t3|t3a)
            # General purpose instances - acceptable but warn
            echo "WARNING: Instance type '$instance_type' is not GPU-optimized. Consider g4dn.xlarge for AI workloads" >&2
            return 0
            ;;
        *)
            # Unknown or deprecated families
            echo "WARNING: Instance family '$family' may not be optimal for AI workloads" >&2
            return 0
            ;;
    esac
}

# Enhanced boolean validation with case-insensitive matching
validate_boolean() {
    local value="${1,,}"  # Convert to lowercase
    
    case "$value" in
        true|yes|1|on|enabled|active) return 0 ;;
        false|no|0|off|disabled|inactive) return 0 ;;
        *) 
            throw_error $ERROR_VALIDATION_FORMAT "Invalid boolean value: '$1'. Valid: true/false, yes/no, 1/0, on/off, enabled/disabled"
            return 1 
            ;;
    esac
}

# Enhanced stack name validation with detailed feedback
validate_stack_name() {
    local name="$1"
    
    # Check length first
    if (( ${#name} > 128 )); then
        throw_error $ERROR_VALIDATION_FORMAT "Stack name too long (${#name} chars). Maximum 128 characters"
    fi
    
    if (( ${#name} < 1 )); then
        throw_error $ERROR_VALIDATION_FORMAT "Stack name cannot be empty"
    fi
    
    # Check format with detailed error messages
    if [[ ! "$name" =~ ^[a-zA-Z] ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Stack name must start with a letter: '$name'"
    fi
    
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Stack name contains invalid characters. Only letters, numbers, and hyphens allowed: '$name'"
    fi
    
    # Check for consecutive hyphens or trailing hyphens
    if [[ "$name" =~ -- ]] || [[ "$name" =~ -$ ]]; then
        throw_error $ERROR_VALIDATION_FORMAT "Stack name cannot have consecutive hyphens or end with hyphen: '$name'"
    fi
    
    return 0
}

# Enhanced deployment type validation with recommendations
validate_deployment_type() {
    local deployment_type="$1"
    
    case "$deployment_type" in
        spot)
            echo "INFO: Spot deployment selected - up to 70% cost savings but may experience interruptions" >&2
            return 0
            ;;
        ondemand|on-demand)
            echo "INFO: On-demand deployment selected - guaranteed availability at standard pricing" >&2
            return 0
            ;;
        simple)
            echo "INFO: Simple deployment selected - basic configuration without advanced features" >&2
            return 0
            ;;
        enterprise|alb|cdn|full)
            echo "INFO: Enterprise deployment selected - full production features enabled" >&2
            return 0
            ;;
        *) 
            throw_error $ERROR_VALIDATION_FORMAT "Invalid deployment type: '$deployment_type'. Valid options: spot, ondemand, simple, enterprise, alb, cdn, full"
            return 1
            ;;
    esac
}

# =============================================================================
# MODERN VARIABLE UTILITIES
# =============================================================================

# Get all registered variables with their metadata
list_variables() {
    local filter="${1:-}"  # Optional filter pattern
    local format="${2:-table}"  # table, json, or simple
    
    case "$format" in
        "json")
            echo "{"
            local first=true
            for var_name in "${!_VARIABLE_REGISTRY[@]}"; do
                [[ -n "$filter" && ! "$var_name" =~ $filter ]] && continue
                
                [[ "$first" == "false" ]] && echo ","
                first=false
                
                echo -n "  \"$var_name\": {"
                echo -n "\"value\": \"$(get_variable "$var_name")\","
                echo -n "\"default\": \"${_VARIABLE_DEFAULTS[$var_name]:-}\","
                echo -n "\"type\": \"${_VARIABLE_TYPES[$var_name]:-string}\","
                echo -n "\"description\": \"${_VARIABLE_DESCRIPTIONS[$var_name]:-}\""
                echo -n "}"
            done
            echo
            echo "}"
            ;;
        "table")
            printf "%-20s %-15s %-15s %-10s %s\n" "VARIABLE" "VALUE" "DEFAULT" "TYPE" "DESCRIPTION"
            printf "%-20s %-15s %-15s %-10s %s\n" "--------" "-----" "-------" "----" "-----------"
            for var_name in "${!_VARIABLE_REGISTRY[@]}"; do
                [[ -n "$filter" && ! "$var_name" =~ $filter ]] && continue
                
                local value="$(get_variable "$var_name")"
                local default="${_VARIABLE_DEFAULTS[$var_name]:-}"
                local var_type="${_VARIABLE_TYPES[$var_name]:-string}"
                local desc="${_VARIABLE_DESCRIPTIONS[$var_name]:-}"
                
                printf "%-20s %-15s %-15s %-10s %s\n" \
                    "${var_name:0:19}" "${value:0:14}" "${default:0:14}" "$var_type" "${desc:0:40}"
            done
            ;;
        "simple")
            for var_name in "${!_VARIABLE_REGISTRY[@]}"; do
                [[ -n "$filter" && ! "$var_name" =~ $filter ]] && continue
                echo "$var_name=$(get_variable "$var_name")"
            done
            ;;
    esac
}

# Bulk set variables from key=value pairs
set_variables_bulk() {
    local -n kvp_array="$1"  # Name reference to associative array
    local validate="${2:-true}"
    
    local failed_vars=()
    
    for var_name in "${!kvp_array[@]}"; do
        local value="${kvp_array[$var_name]}"
        
        # Sanitize variable name to ensure it's valid
        local sanitized_name=$(sanitize_var_name "$var_name")
        
        if [[ "$validate" == "true" ]]; then
            if ! set_variable "$sanitized_name" "$value"; then
                failed_vars+=("$var_name")
                continue
            fi
        else
            # Skip validation for bulk operations
            # Still need to ensure valid variable name
            if [[ ! "$sanitized_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                throw_error $ERROR_VALIDATION_FORMAT "Invalid variable name after sanitization: $var_name -> $sanitized_name"
            fi
            local -n var_ref="$sanitized_name"
            var_ref="$value"
            export "$sanitized_name"
        fi
    done
    
    if (( ${#failed_vars[@]} > 0 )); then
        echo "WARNING: Failed to set variables: ${failed_vars[*]}" >&2
        return 1
    fi
    
    return 0
}

# Clear variable cache for performance testing or updates
clear_variable_cache() {
    local var_pattern="${1:-}"  # Optional pattern to clear specific variables
    
    if [[ -n "$var_pattern" ]]; then
        for var_name in "${!_VARIABLE_CACHE[@]}"; do
            [[ "$var_name" =~ $var_pattern ]] && unset _VARIABLE_CACHE["$var_name"]
        done
        for var_name in "${!_CACHE_TIMESTAMPS[@]}"; do
            [[ "$var_name" =~ $var_pattern ]] && unset _CACHE_TIMESTAMPS["$var_name"]
        done
    else
        _VARIABLE_CACHE=()
        _CACHE_TIMESTAMPS=()
    fi
}

# =============================================================================
# CORE DEPLOYMENT VARIABLES WITH ENHANCED METADATA
# =============================================================================

# Register AWS variables with enhanced metadata
register_variable "AWS_REGION" "us-east-1" "validate_aws_region" "string" "AWS region for deployment"
register_variable "AWS_DEFAULT_REGION" "us-east-1" "validate_aws_region" "string" "Default AWS region fallback"
register_variable "AWS_PROFILE" "default" "" "string" "AWS CLI profile to use"

# Register deployment variables
register_variable "STACK_NAME" "" "validate_stack_name" "string" "Unique stack identifier for AWS resources"
register_variable "DEPLOYMENT_TYPE" "spot" "validate_deployment_type" "string" "Deployment strategy: spot, ondemand, simple, enterprise, alb, cdn, or full"
register_variable "INSTANCE_TYPE" "g4dn.xlarge" "validate_instance_type" "string" "EC2 instance type for compute resources"
register_variable "KEY_NAME" "" "" "string" "SSH key pair name for instance access"
register_variable "VOLUME_SIZE" "100" "" "integer" "EBS volume size in GB"
register_variable "ENVIRONMENT" "production" "" "string" "Deployment environment context"

# Register feature flags with enhanced descriptions
register_variable "CLEANUP_ON_FAILURE" "true" "validate_boolean" "boolean" "Clean up resources automatically on deployment failure"
register_variable "VALIDATE_ONLY" "false" "validate_boolean" "boolean" "Validate configuration without deploying resources"
register_variable "DRY_RUN" "false" "validate_boolean" "boolean" "Show deployment plan without creating resources"
register_variable "DEBUG" "false" "validate_boolean" "boolean" "Enable verbose debug logging"
register_variable "VERBOSE" "false" "validate_boolean" "boolean" "Enable detailed operational output"

# Register application service toggles
register_variable "N8N_ENABLE" "true" "validate_boolean" "boolean" "Enable n8n workflow automation service"
register_variable "QDRANT_ENABLE" "true" "validate_boolean" "boolean" "Enable Qdrant vector database service"
register_variable "OLLAMA_ENABLE" "true" "validate_boolean" "boolean" "Enable Ollama LLM inference service"
register_variable "CRAWL4AI_ENABLE" "true" "validate_boolean" "boolean" "Enable Crawl4AI web scraping service"

# Register database and security variables
register_variable "POSTGRES_PASSWORD" "" "" "string" "PostgreSQL database password"
register_variable "POSTGRES_DB" "n8n" "" "string" "PostgreSQL database name"
register_variable "POSTGRES_USER" "n8n" "" "string" "PostgreSQL database user"
register_variable "N8N_ENCRYPTION_KEY" "" "" "string" "n8n encryption key"
register_variable "N8N_USER_MANAGEMENT_JWT_SECRET" "" "" "string" "n8n JWT secret for user management"
register_variable "n8n_ENCRYPTION_KEY" "" "" "string" "n8n encryption key (lowercase)"

# Register n8n configuration variables
register_variable "N8N_CORS_ENABLE" "true" "validate_boolean" "boolean" "Enable CORS for n8n"
register_variable "n8n_CORS_ENABLE" "true" "validate_boolean" "boolean" "Enable CORS for n8n (lowercase)"
register_variable "N8N_CORS_ALLOWED_ORIGINS" "*" "" "string" "Allowed CORS origins for n8n"
register_variable "n8n_CORS_ALLOWED_ORIGINS" "*" "" "string" "Allowed CORS origins for n8n (lowercase)"
register_variable "N8N_BASIC_AUTH_ACTIVE" "true" "validate_boolean" "boolean" "Enable basic auth for n8n"
register_variable "n8n_BASIC_AUTH_ACTIVE" "true" "validate_boolean" "boolean" "Enable basic auth for n8n (lowercase)"
register_variable "N8N_BASIC_AUTH_USER" "admin" "" "string" "n8n basic auth username"
register_variable "n8n_BASIC_AUTH_USER" "admin" "" "string" "n8n basic auth username (lowercase)"
register_variable "N8N_BASIC_AUTH_PASSWORD" "" "" "string" "n8n basic auth password"
register_variable "n8n_BASIC_AUTH_PASSWORD" "" "" "string" "n8n basic auth password (lowercase)"
register_variable "N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE" "true" "validate_boolean" "boolean" "Allow community packages tool usage in n8n"
register_variable "n8n_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE" "true" "validate_boolean" "boolean" "Allow community packages tool usage in n8n (lowercase)"
register_variable "n8n_USER_MANAGEMENT_JWT_SECRET" "" "" "string" "n8n JWT secret for user management (lowercase)"
register_variable "OPENAI_API_KEY" "" "" "string" "OpenAI API key"
register_variable "WEBHOOK_URL" "http://localhost:5678" "" "string" "Webhook URL for n8n"

# Register infrastructure variables
register_variable "efs_id" "" "" "string" "EFS filesystem ID"
register_variable "vpc_id" "" "" "string" "VPC ID"
register_variable "subnet_id" "" "" "string" "Subnet ID"
register_variable "security_group_id" "" "" "string" "Security group ID"
register_variable "instance_id" "" "" "string" "EC2 instance ID"
register_variable "alb_arn" "" "" "string" "Application Load Balancer ARN"
register_variable "cloudfront_id" "" "" "string" "CloudFront distribution ID"

# Register infrastructure feature flags
register_variable "ENABLE_ALB" "false" "validate_boolean" "boolean" "Enable Application Load Balancer"
register_variable "ENABLE_CDN" "false" "validate_boolean" "boolean" "Enable CloudFront CDN"
register_variable "ENABLE_EFS" "true" "validate_boolean" "boolean" "Enable EFS filesystem"
register_variable "ENABLE_MONITORING" "true" "validate_boolean" "boolean" "Enable CloudWatch monitoring"
register_variable "ENABLE_BACKUP" "true" "validate_boolean" "boolean" "Enable automated backups"

# Register deployment configuration variables
register_variable "ENABLE_MULTI_AZ" "false" "validate_boolean" "boolean" "Enable multi-AZ deployment"
register_variable "ENABLE_AUTO_SCALING" "false" "validate_boolean" "boolean" "Enable auto scaling"
register_variable "ENABLE_SSL" "true" "validate_boolean" "boolean" "Enable SSL/TLS encryption"
register_variable "ENABLE_LOGGING" "true" "validate_boolean" "boolean" "Enable detailed logging"
register_variable "ENABLE_METRICS" "true" "validate_boolean" "boolean" "Enable CloudWatch metrics"

# Register spot instance configuration variables
register_variable "ENABLE_SPOT" "true" "validate_boolean" "boolean" "Enable spot instances for cost savings"
register_variable "SPOT_MAX_PRICE" "0.5" "" "string" "Maximum spot instance price"
register_variable "SPOT_INTERRUPTION_BEHAVIOR" "terminate" "" "string" "Spot instance interruption behavior"
register_variable "SPOT_ALLOCATION_STRATEGY" "lowest-price" "" "string" "Spot instance allocation strategy"
register_variable "VPC_CIDR" "10.0.0.0/16" "" "string" "VPC CIDR block"
register_variable "PUBLIC_SUBNET_CIDR" "10.0.1.0/24" "" "string" "Public subnet CIDR block"
register_variable "PRIVATE_SUBNET_CIDR" "10.0.2.0/24" "" "string" "Private subnet CIDR block"
register_variable "AVAILABILITY_ZONES" "us-east-1a,us-east-1b,us-east-1c" "" "string" "Availability zones for deployment"

# =============================================================================
# PARAMETER STORE INTEGRATION
# =============================================================================

# Enhanced Parameter Store integration with batch processing
load_from_parameter_store() {
    local prefix="${1:-/aibuildkit}"
    local batch_size="${2:-10}"  # Process in batches for large parameter sets
    local max_retries="${3:-3}"
    
    if ! command -v aws &> /dev/null; then
        echo "WARNING: AWS CLI not available, skipping Parameter Store loading" >&2
        return 1
    fi
    
    echo "Loading configuration from Parameter Store (prefix: $prefix)..." >&2
    
    local attempt=1
    local params
    
    # Retry logic for Parameter Store access
    while (( attempt <= max_retries )); do
        if params=$(aws ssm get-parameters-by-path \
            --path "$prefix" \
            --recursive \
            --with-decryption \
            --max-items 50 \
            --query 'Parameters[*].[Name,Value,ParameterType]' \
            --output text 2>/dev/null); then
            break
        else
            echo "WARNING: Parameter Store access failed (attempt $attempt/$max_retries)" >&2
            if (( attempt < max_retries )); then
                sleep $((attempt * 2))  # Exponential backoff
            fi
            ((attempt++))
        fi
    done
    
    if (( attempt > max_retries )); then
        echo "ERROR: Failed to load from Parameter Store after $max_retries attempts" >&2
        return 1
    fi
    
    # Process parameters in batches for better performance
    local -A param_batch=()
    local batch_count=0
    local total_loaded=0
    local failed_count=0
    
    while IFS=$'\t' read -r name value param_type; do
        [[ -z "$name" ]] && continue
        
        # Convert parameter name to environment variable
        # /aibuildkit/OPENAI_API_KEY -> OPENAI_API_KEY
        local var_name="${name#${prefix}/}"
        var_name="${var_name//\//_}"  # Replace / with _
        
        # Sanitize variable name to ensure it's valid bash identifier
        var_name=$(sanitize_var_name "$var_name")
        
        # Add to batch
        param_batch["$var_name"]="$value"
        ((batch_count++))
        
        # Process batch when it reaches batch_size
        if (( batch_count >= batch_size )); then
            if set_variables_bulk param_batch true; then
                ((total_loaded += batch_count))
            else
                ((failed_count += batch_count))
            fi
            
            # Clear batch
            param_batch=()
            batch_count=0
        fi
    done <<< "$params"
    
    # Process remaining parameters in final batch
    if (( batch_count > 0 )); then
        if set_variables_bulk param_batch true; then
            ((total_loaded += batch_count))
        else
            ((failed_count += batch_count))
        fi
    fi
    
    echo "Parameter Store loading complete: $total_loaded loaded, $failed_count failed" >&2
    return 0
}

# =============================================================================
# ENVIRONMENT FILE SUPPORT
# =============================================================================

# Load variables from environment file
load_env_file() {
    local env_file="$1"
    
    [ -f "$env_file" ] || {
        throw_error $ERROR_FILE_NOT_FOUND "Environment file not found: $env_file"
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
            throw_error $ERROR_VALIDATION_FAILED "Failed to set $key from env file"
        }
    done < "$env_file"
    
    return 0
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Enhanced validation with dependency checking and context awareness
validate_required_variables() {
    local context="${1:-deployment}"  # deployment, testing, development
    local strict_mode="${2:-true}"
    
    # Define context-specific required variables
    local -A required_by_context=(
        ["deployment"]="AWS_REGION STACK_NAME DEPLOYMENT_TYPE INSTANCE_TYPE"
        ["testing"]="AWS_REGION STACK_NAME"
        ["development"]="AWS_REGION STACK_NAME DEPLOYMENT_TYPE"
    )
    
    local required_vars_str="${required_by_context[$context]:-${required_by_context[deployment]}}"
    read -ra required_vars <<< "$required_vars_str"
    
    local missing=()
    local invalid=()
    
    # Check each required variable
    for var in "${required_vars[@]}"; do
        local value
        value=$(get_variable "$var" false)  # Don't use cache for validation
        
        if [[ -z "$value" ]]; then
            missing+=("$var")
            continue
        fi
        
        # Run validator if exists
        if [[ -v _VARIABLE_VALIDATORS["$var"] ]]; then
            local validator="${_VARIABLE_VALIDATORS[$var]}"
            # Guard against executing non-function values
            if declare -F "$validator" >/dev/null 2>&1; then
                if ! "$validator" "$value" >/dev/null 2>&1; then
                    invalid+=("$var")
                fi
            else
                echo "WARNING: Validator '$validator' for variable '$var' is not a declared function, skipping validation" >&2
            fi
        fi
    done
    
    local has_errors=false
    
    # Report missing variables
    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: Missing required variables for context '$context': ${missing[*]}" >&2
        for var in "${missing[@]}"; do
            local default="${_VARIABLE_DEFAULTS[$var]:-N/A}"
            local desc="${_VARIABLE_DESCRIPTIONS[$var]:-No description}"
            echo "  $var: $desc (default: $default)" >&2
        done
        has_errors=true
    fi
    
    # Report invalid variables
    if (( ${#invalid[@]} > 0 )); then
        echo "ERROR: Invalid values for variables: ${invalid[*]}" >&2
        for var in "${invalid[@]}"; do
            local value
            value=$(get_variable "$var" false)
            echo "  $var='$value' failed validation" >&2
        done
        has_errors=true
    fi
    
    # Check cross-variable dependencies
    if [[ "$context" == "deployment" ]]; then
        validate_variable_dependencies || has_errors=true
    fi
    
    if [[ "$has_errors" == "true" ]]; then
        if [[ "$strict_mode" == "true" ]]; then
            throw_error $ERROR_VALIDATION_FAILED "Missing required variables for context '$context': ${missing[*]}"
        else
            throw_error $ERROR_VALIDATION_FAILED "Validation errors found but strict mode disabled"
        fi
    fi
    
    return 0
}

# Validate cross-variable dependencies
validate_variable_dependencies() {
    local errors=()
    
    # Check deployment type vs instance type compatibility
    local deployment_type
    deployment_type=$(get_variable "DEPLOYMENT_TYPE")
    local instance_type
    instance_type=$(get_variable "INSTANCE_TYPE")
    
    if [[ "$deployment_type" == "simple" && "$instance_type" =~ ^(g4dn|g5|p3|p4d) ]]; then
        errors+=("Simple deployment with GPU instance '$instance_type' may be over-provisioned")
    fi
    
    # Check environment vs deployment type
    local environment
    environment=$(get_variable "ENVIRONMENT")
    
    if [[ "$environment" == "production" && "$deployment_type" == "spot" ]]; then
        throw_error $ERROR_VALIDATION_FAILED "Production environment with spot instances may experience interruptions"
    fi
    
    # Check volume size vs instance type
    local volume_size
    volume_size=$(get_variable "VOLUME_SIZE")
    
    if [[ "$instance_type" =~ ^(g4dn|g5) ]] && (( volume_size < 50 )); then
        errors+=("GPU instances typically need more storage. Consider increasing VOLUME_SIZE to 100GB+")
    fi
    
    # Report dependency errors
    if (( ${#errors[@]} > 0 )); then
        throw_error $ERROR_VALIDATION_FAILED "Variable dependency issues: ${errors[*]}"
    fi
    
    return 0
}

# Enhanced configuration display with categorization and metadata
print_configuration() {
    local format="${1:-detailed}"  # detailed, compact, json
    local filter="${2:-}"  # Optional variable name pattern filter
    
    case "$format" in
        "json")
            list_variables "$filter" "json"
            ;;
        "compact")
            echo "=== Configuration Summary ==="
            echo "Stack: $(get_variable STACK_NAME) | Type: $(get_variable DEPLOYMENT_TYPE) | Region: $(get_variable AWS_REGION)"
            echo "Instance: $(get_variable INSTANCE_TYPE) | Environment: $(get_variable ENVIRONMENT)"
            echo "Debug: $(get_variable DEBUG) | Dry Run: $(get_variable DRY_RUN)"
            echo "============================"
            ;;
        "detailed"|*)
            echo "=== GeuseMaker Deployment Configuration ==="
            echo
            echo "📍 AWS Configuration:"
            echo "   Region: $(get_variable AWS_REGION)"
            echo "   Profile: $(get_variable AWS_PROFILE)"
            echo
            echo "🏗️  Deployment Configuration:"
            echo "   Stack Name: $(get_variable STACK_NAME)"
            echo "   Type: $(get_variable DEPLOYMENT_TYPE)"
            echo "   Environment: $(get_variable ENVIRONMENT)"
            echo
            echo "💻 Compute Configuration:"
            echo "   Instance Type: $(get_variable INSTANCE_TYPE)"
            echo "   Volume Size: $(get_variable VOLUME_SIZE) GB"
            echo "   Key Name: $(get_variable KEY_NAME)"
            echo
            echo "🔧 Service Configuration:"
            echo "   n8n: $(get_variable N8N_ENABLE)"
            echo "   Ollama: $(get_variable OLLAMA_ENABLE)"
            echo "   Qdrant: $(get_variable QDRANT_ENABLE)"
            echo "   Crawl4AI: $(get_variable CRAWL4AI_ENABLE)"
            echo
            echo "⚙️  Operational Flags:"
            echo "   Debug Mode: $(get_variable DEBUG)"
            echo "   Dry Run: $(get_variable DRY_RUN)"
            echo "   Cleanup on Failure: $(get_variable CLEANUP_ON_FAILURE)"
            echo "   Validate Only: $(get_variable VALIDATE_ONLY)"
            echo "=========================================="
            ;;
    esac
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Enhanced initialization with priority-based loading and performance optimization
initialize_variables() {
    local load_parameter_store="${1:-true}"
    local load_env_files="${2:-true}"
    local load_environment="${3:-true}"
    local prefix="${4:-/aibuildkit}"
    
    echo "Initializing GeuseMaker variable system..." >&2
    
    local start_time
    start_time=$(date +%s)
    
    # Priority 1: Load from Parameter Store (if enabled)
    if [[ "$load_parameter_store" == "true" ]]; then
        echo "Loading from AWS Parameter Store..." >&2
        load_from_parameter_store "$prefix" || {
            echo "WARNING: Parameter Store loading failed, continuing with other sources" >&2
        }
    fi
    
    # Priority 2: Load from environment-specific files (if enabled)
    if [[ "$load_env_files" == "true" ]]; then
        local env_files=(
            ".env.$(get_variable ENVIRONMENT)"
            ".env.local"
            ".env"
        )
        
        for env_file in "${env_files[@]}"; do
            if [[ -f "$env_file" ]]; then
                echo "Loading from $env_file..." >&2
                load_env_file "$env_file" || {
                    echo "WARNING: Failed to load $env_file" >&2
                }
                break  # Only load the first available env file
            fi
        done
    fi
    
    # Priority 3: Apply environment variable overrides (if enabled)
    if [[ "$load_environment" == "true" ]]; then
        echo "Applying environment variable overrides..." >&2
        
        # Use modern associative array iteration
        for var_name in "${!_VARIABLE_REGISTRY[@]}"; do
            # Use name reference for efficient access
            local -n env_value_ref="$var_name"
            local env_value="${env_value_ref:-}"
            
            if [[ -n "$env_value" ]]; then
                # Override with environment value, but skip validation for performance
                set_variable "$var_name" "$env_value" || {
                    echo "WARNING: Failed to set $var_name from environment" >&2
                }
            fi
        done
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Variable initialization completed in ${duration}s" >&2
    
    # Show initialization summary if debug enabled
    if [[ "$(get_variable DEBUG)" == "true" ]]; then
        echo "Variable initialization summary:" >&2
        echo "  Registered variables: ${#_VARIABLE_REGISTRY[@]}" >&2
        echo "  Cached values: ${#_VARIABLE_CACHE[@]}" >&2
        echo "  Total duration: ${duration}s" >&2
    fi
}

# Auto-initialize on source with error handling
if ! initialize_variables; then
    echo "WARNING: Variable initialization encountered errors" >&2
fi