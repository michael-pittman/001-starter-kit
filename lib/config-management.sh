#!/usr/bin/env bash
# =============================================================================
# Configuration Management Library 
# Centralized configuration system for GeuseMaker project
# Compatible with bash 3.x+
# =============================================================================


# Load associative array utilities
source "$SCRIPT_DIR/associative-arrays.sh"
# This library provides centralized configuration management for the GeuseMaker
# project, supporting multiple environments, deployment types, and integrating
# with the existing shared library system.
# =============================================================================

# Prevent multiple sourcing
if [[ "${CONFIG_MANAGEMENT_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly CONFIG_MANAGEMENT_LIB_LOADED=true

# =============================================================================
# CONFIGURATION CONSTANTS AND DEFAULTS
# =============================================================================

# Project structure
readonly CONFIG_MANAGEMENT_VERSION="1.0.0"
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    readonly PROJECT_ROOT
fi
if [[ -z "${CONFIG_DIR:-}" ]]; then
    readonly CONFIG_DIR="${PROJECT_ROOT}/config"
fi
if [[ -z "${ENVIRONMENTS_DIR:-}" ]]; then
    readonly ENVIRONMENTS_DIR="${CONFIG_DIR}/environments"
fi
if [[ -z "${LIB_DIR:-}" ]]; then
    readonly LIB_DIR="${PROJECT_ROOT}/lib"
fi

# Default values (bash 3.x compatible)
if [[ -z "${DEFAULT_ENVIRONMENT:-}" ]]; then
    readonly DEFAULT_ENVIRONMENT="development"
fi
if [[ -z "${DEFAULT_REGION:-}" ]]; then
    readonly DEFAULT_REGION="us-east-1"
fi
if [[ -z "${DEFAULT_DEPLOYMENT_TYPE:-}" ]]; then
    readonly DEFAULT_DEPLOYMENT_TYPE="simple"
fi

# =============================================================================
# GLOBAL ASSOCIATIVE ARRAYS FOR CONFIGURATION
# =============================================================================

# Global configuration storage using associative arrays
declare -gA CONFIG_CACHE
declare -gA ENVIRONMENT_CONFIGS
declare -gA DEPLOYMENT_OVERRIDES
declare -gA VALIDATION_RULES
declare -gA CONFIG_METADATA

# Valid options stored in associative arrays for enhanced validation
declare -gA VALID_OPTIONS
aa_set VALID_OPTIONS "environments" "development staging production"
aa_set VALID_OPTIONS "deployment_types" "simple spot ondemand"
aa_set VALID_OPTIONS "regions" "us-east-1 us-west-2 eu-west-1 ap-southeast-1"

# Configuration state management
declare -gA CONFIG_STATE
aa_set CONFIG_STATE "cache_loaded" "false"
aa_set CONFIG_STATE "current_environment" ""
aa_set CONFIG_STATE "current_deployment_type" ""
aa_set CONFIG_STATE "config_file_path" ""

# =============================================================================
# DEPENDENCY MANAGEMENT
# =============================================================================

# Check if required dependencies are available with improved detection
check_config_dependencies() {
    local missing_tools=()
    local optional_tools=()
    local available_alternatives=false
    local has_yaml_processor=false
    local has_json_processor=false
    
    # Check for YAML processing capabilities
    if command -v yq >/dev/null 2>&1; then
        has_yaml_processor=true
    elif command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; print('yaml available')" 2>/dev/null | grep -q "yaml available"; then
            has_yaml_processor=true
            available_alternatives=true
        fi
    fi
    
    if [ "$has_yaml_processor" = "false" ]; then
        # Check for basic YAML parsing alternatives
        if command -v python >/dev/null 2>&1; then
            if python -c "import yaml" 2>/dev/null; then
                has_yaml_processor=true
                available_alternatives=true
            fi
        fi
    fi
    
    if [ "$has_yaml_processor" = "false" ]; then
        missing_tools+=("yq (or python3-yaml)")
    fi
    
    # Check for JSON processing capabilities
    if command -v jq >/dev/null 2>&1; then
        has_json_processor=true
    elif command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json; print('json available')" 2>/dev/null | grep -q "json available"; then
            has_json_processor=true
            available_alternatives=true
        fi
    elif command -v python >/dev/null 2>&1; then
        if python -c "import json" 2>/dev/null; then
            has_json_processor=true
            available_alternatives=true
        fi
    fi
    
    if [ "$has_json_processor" = "false" ]; then
        missing_tools+=("jq (or python with json)")
    fi
    
    # Optional tools (graceful degradation)
    for tool in envsubst bc; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            optional_tools+=("$tool")
        fi
    done
    
    # Provide helpful information but don't fail
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        if command -v log_message >/dev/null 2>&1; then
            log_message "WARN" "Missing recommended dependencies: ${missing_tools[*]}" "CONFIG_MANAGEMENT"
            if [ "$available_alternatives" = "true" ]; then
                log_message "WARN" "Using fallback implementations" "CONFIG_MANAGEMENT"
            else
                log_message "WARN" "Some enhanced features may not be available" "CONFIG_MANAGEMENT"
            fi
        else
            if command -v log_message >/dev/null 2>&1; then
                log_message "WARN" "Missing recommended dependencies: ${missing_tools[*]}" "CONFIG_MANAGEMENT"
                if [ "$available_alternatives" = "true" ]; then
                    log_message "WARN" "Using fallback implementations" "CONFIG_MANAGEMENT"
                else
                    log_message "WARN" "Some enhanced features may not be available" "CONFIG_MANAGEMENT"
                fi
            else
                echo "WARNING: Missing recommended dependencies: ${missing_tools[*]}" >&2
                if [ "$available_alternatives" = "true" ]; then
                    echo "WARNING: Using fallback implementations" >&2
                else
                    echo "WARNING: Some enhanced features may not be available" >&2
                fi
            fi
        fi
        if command -v log_message >/dev/null 2>&1; then
            log_message "INFO" "Install with:" "CONFIG_MANAGEMENT"
            log_message "INFO" "  macOS: brew install yq jq" "CONFIG_MANAGEMENT"
            log_message "INFO" "  Ubuntu: apt-get install yq jq" "CONFIG_MANAGEMENT"
            log_message "INFO" "  Or: pip3 install PyYAML" "CONFIG_MANAGEMENT"
        else
            echo "Install with:" >&2
            echo "  macOS: brew install yq jq" >&2
            echo "  Ubuntu: apt-get install yq jq" >&2
            echo "  Or: pip3 install PyYAML" >&2
        fi
    fi
    
    if [[ ${#optional_tools[@]} -gt 0 ]]; then
        if command -v log_message >/dev/null 2>&1; then
            log_message "WARN" "Optional tools missing (some features may be limited): ${optional_tools[*]}" "CONFIG_MANAGEMENT"
        elif declare -f warning >/dev/null 2>&1; then
            warning "Optional tools missing (some features may be limited): ${optional_tools[*]}"
        else
            echo "WARNING: Optional tools missing: ${optional_tools[*]}" >&2
        fi
    fi
    
    # Always return success to allow graceful degradation
    return 0
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Enhanced validation using associative arrays
validate_environment() {
    local env="$1"
    
    if [[ -z "$env" ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "Environment name cannot be empty"
    fi
    
    # Use associative array for validation
    local valid_environments=$(aa_get VALID_OPTIONS "environments" "")
    local valid=false
    
    for valid_env in $valid_environments; do
        if [[ "$env" == "$valid_env" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "Invalid environment: $env. Valid options: $valid_environments"
    fi
    
    # Store validation result in cache
    aa_set CONFIG_METADATA "last_validated_environment" "$env"
    aa_set CONFIG_METADATA "last_validation_time" "$(date +%s)"
    
    return 0
}

# Enhanced deployment type validation using associative arrays
validate_deployment_type() {
    local type="$1"
    
    if [[ -z "$type" ]]; then
        type="$DEFAULT_DEPLOYMENT_TYPE"
    fi
    
    # Use associative array for validation
    local valid_deployment_types=$(aa_get VALID_OPTIONS "deployment_types" "")
    local valid=false
    
    for valid_type in $valid_deployment_types; do
        if [[ "$type" == "$valid_type" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "Invalid deployment type: $type. Valid options: $valid_deployment_types"
    fi
    
    # Store validation result and get deployment metadata
    aa_set CONFIG_METADATA "last_validated_deployment_type" "$type"
    
    # Load deployment type metadata if available
    declare -A deployment_metadata
    case "$type" in
        "spot")
            aa_set deployment_metadata "cost_optimization" "high"
            aa_set deployment_metadata "availability_guarantee" "low"
            aa_set deployment_metadata "recommended_for" "development,testing,batch_processing"
            ;;
        "ondemand")
            aa_set deployment_metadata "cost_optimization" "low"
            aa_set deployment_metadata "availability_guarantee" "high"
            aa_set deployment_metadata "recommended_for" "production,critical_workloads"
            ;;
        "simple")
            aa_set deployment_metadata "cost_optimization" "medium"
            aa_set deployment_metadata "availability_guarantee" "medium"
            aa_set deployment_metadata "recommended_for" "development,prototyping"
            ;;
    esac
    
    # Store deployment metadata in config cache
    local metadata_key
    for metadata_key in $(aa_keys deployment_metadata); do
        aa_set CONFIG_CACHE "deployment_metadata:${type}:${metadata_key}" "$(aa_get deployment_metadata "$metadata_key")"
    done
    
    return 0
}

# Validate AWS region (bash 3.x compatible)
validate_aws_region() {
    local region="$1"
    
    if [[ -z "$region" ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "AWS region cannot be empty"
    fi
    
    # Basic AWS region format validation
    if [[ ! "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "AWS region format may be invalid: $region"
    fi
    
    return 0
}

# Validate stack name
validate_stack_name() {
    local stack_name="$1"
    
    if [[ -z "$stack_name" ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "Stack name cannot be empty"
    fi
    
    # CloudFormation stack name validation
    if [[ ${#stack_name} -gt 128 ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "Stack name too long (max 128 characters): $stack_name"
    fi
    
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        throw_error $ERROR_CONFIG_VALIDATION "Invalid stack name format. Must start with letter, contain only alphanumeric and hyphens: $stack_name"
    fi
    
    return 0
}

# Validate configuration file structure with improved error handling
validate_configuration_file() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        throw_error $ERROR_CONFIG_MISSING "Configuration file not found: $config_file"
    fi
    
    # Check file is readable
    if [[ ! -r "$config_file" ]]; then
        throw_error $ERROR_CONFIG_INVALID "Configuration file not readable: $config_file"
    fi
    
    # Check file is not empty
    if [[ ! -s "$config_file" ]]; then
        throw_error $ERROR_CONFIG_INVALID "Configuration file is empty: $config_file"
    fi
    
    # Validate YAML syntax first
    local yaml_valid=false
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' "$config_file" >/dev/null 2>&1; then
            yaml_valid=true
        fi
    elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            yaml_valid=true
        fi
    elif command -v python >/dev/null 2>&1 && python -c "import yaml" 2>/dev/null; then
        if python -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            yaml_valid=true
        fi
    else
        # Basic YAML structure check with grep
        if grep -q ":" "$config_file" && ! grep -q "^[[:space:]]*[{}\[\]]" "$config_file"; then
            yaml_valid=true
        fi
    fi
    
    if [ "$yaml_valid" = "false" ]; then
        throw_error $ERROR_CONFIG_PARSE "Configuration file has invalid YAML syntax: $config_file"
    fi
    
    # Check for required sections (bash 3.x compatible)
    local required_sections="global infrastructure applications"
    local missing_sections=""
    
    for section in $required_sections; do
        if ! grep -q "^${section}:" "$config_file" && ! grep -q "^[[:space:]]*${section}:" "$config_file"; then
            if [ -z "$missing_sections" ]; then
                missing_sections="$section"
            else
                missing_sections="$missing_sections $section"
            fi
        fi
    done
    
    if [ -n "$missing_sections" ]; then
        throw_error $ERROR_CONFIG_MISSING "Configuration file missing recommended sections: $missing_sections"
    fi
    
    return 0
}

# =============================================================================
# CONFIGURATION LOADING AND CACHING
# =============================================================================

# Get configuration file path for environment
get_config_file_path() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    echo "${ENVIRONMENTS_DIR}/${env}.yml"
}

# Check if configuration file exists
config_file_exists() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local config_file
    config_file=$(get_config_file_path "$env")
    [[ -f "$config_file" ]]
}

# Enhanced configuration loading with associative array caching
load_config() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${2:-$DEFAULT_DEPLOYMENT_TYPE}"
    local force_reload="${3:-false}"
    
    # Validate inputs
    validate_environment "$env" || return 1
    validate_deployment_type "$deployment_type" || return 1
    
    # Create cache key for this configuration
    local cache_key="${env}:${deployment_type}"
    local cache_loaded=$(aa_get CONFIG_STATE "cache_loaded")
    local current_env=$(aa_get CONFIG_STATE "current_environment")
    local current_type=$(aa_get CONFIG_STATE "current_deployment_type")
    
    # Check cache
    if [[ "$cache_loaded" == "true" && "$current_env" == "$env" && "$current_type" == "$deployment_type" && "$force_reload" != "true" ]]; then
        if declare -f log >/dev/null 2>&1; then
            log "Using cached configuration for $env:$deployment_type"
        fi
        return 0
    fi
    
    local config_file
    config_file=$(get_config_file_path "$env")
    
    if [[ ! -f "$config_file" ]]; then
        throw_error $ERROR_CONFIG_MISSING "Configuration file not found: $config_file"
    fi
    
    # Load configuration using associative arrays
    if declare -f log >/dev/null 2>&1; then
        log "Loading configuration with associative arrays: environment=$env, type=$deployment_type"
    fi
    
    # Store configuration in associative arrays
    declare -A config_data
    aa_set config_data "environment" "$env"
    aa_set config_data "deployment_type" "$deployment_type"
    aa_set config_data "config_file" "$config_file"
    aa_set config_data "load_time" "$(date +%s)"
    aa_set config_data "aws_region" "${AWS_REGION:-us-east-1}"
    aa_set config_data "stack_name" "${STACK_NAME:-GeuseMaker-${env}}"
    
    # Cache configuration data with structured keys
    local config_key
    for config_key in $(aa_keys config_data); do
        aa_set CONFIG_CACHE "${cache_key}:${config_key}" "$(aa_get config_data "$config_key")"
    done
    
    # Load environment-specific configuration if available
    if [[ -f "$config_file" ]]; then
        load_yaml_config_to_array "$config_file" "$env" "$deployment_type"
    fi
    
    # Set global variables for backward compatibility
    export ENVIRONMENT="$env"
    export CONFIG_ENVIRONMENT="$env"
    export CONFIG_REGION="${AWS_REGION:-us-east-1}"
    export CONFIG_STACK_NAME="${STACK_NAME:-GeuseMaker-${env}}"
    export DEPLOYMENT_TYPE="$deployment_type"
    export CONFIG_FILE="$config_file"
    export CONFIG_FILE_PATH="$config_file"
    
    # Update state management
    aa_set CONFIG_STATE "cache_loaded" "true"
    aa_set CONFIG_STATE "current_environment" "$env"
    aa_set CONFIG_STATE "current_deployment_type" "$deployment_type"
    aa_set CONFIG_STATE "config_file_path" "$config_file"
    aa_set CONFIG_STATE "last_load_time" "$(date +%s)"
    
    return 0
}

# Load YAML configuration into associative arrays
load_yaml_config_to_array() {
    local config_file="$1"
    local env="$2"
    local deployment_type="$3"
    local cache_key="${env}:${deployment_type}"
    
    # Use yq to extract configuration sections if available
    if command -v yq >/dev/null 2>&1; then
        # Load global configuration
        local global_keys
        global_keys=$(yq eval '.global | keys | .[]' "$config_file" 2>/dev/null || echo "")
        
        for key in $global_keys; do
            local value
            value=$(yq eval ".global.$key" "$config_file" 2>/dev/null || echo "")
            if [[ "$value" != "null" && -n "$value" ]]; then
                aa_set CONFIG_CACHE "${cache_key}:global:${key}" "$value"
            fi
        done
        
        # Load infrastructure configuration
        local infra_keys
        infra_keys=$(yq eval '.infrastructure | keys | .[]' "$config_file" 2>/dev/null || echo "")
        
        for key in $infra_keys; do
            local value
            value=$(yq eval ".infrastructure.$key" "$config_file" 2>/dev/null || echo "")
            if [[ "$value" != "null" && -n "$value" ]]; then
                aa_set CONFIG_CACHE "${cache_key}:infrastructure:${key}" "$value"
            fi
        done
        
        # Load application configurations
        local app_names
        app_names=$(yq eval '.applications | keys | .[]' "$config_file" 2>/dev/null || echo "")
        
        for app in $app_names; do
            local app_keys
            app_keys=$(yq eval ".applications.$app | keys | .[]" "$config_file" 2>/dev/null || echo "")
            
            for key in $app_keys; do
                local value
                value=$(yq eval ".applications.$app.$key" "$config_file" 2>/dev/null || echo "")
                if [[ "$value" != "null" && -n "$value" ]]; then
                    aa_set CONFIG_CACHE "${cache_key}:applications:${app}:${key}" "$value"
                fi
            done
        done
        
        if declare -f log >/dev/null 2>&1; then
            log "Configuration loaded from YAML into associative arrays"
        fi
    else
        if declare -f warning >/dev/null 2>&1; then
            warning "yq not available, skipping YAML configuration loading"
        fi
    fi
}

# Clear configuration cache using associative arrays
clear_config_cache() {
    aa_clear CONFIG_CACHE
    aa_clear ENVIRONMENT_CONFIGS
    aa_clear DEPLOYMENT_OVERRIDES
    
    # Reset state
    aa_set CONFIG_STATE "cache_loaded" "false"
    aa_set CONFIG_STATE "current_environment" ""
    aa_set CONFIG_STATE "current_deployment_type" ""
    aa_set CONFIG_STATE "config_file_path" ""
}

# =============================================================================
# CONFIGURATION INHERITANCE AND OVERRIDES
# =============================================================================

# Apply environment-specific overrides using associative arrays
apply_environment_overrides() {
    local base_env="${1:-development}"
    local target_env="${2:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${3:-$DEFAULT_DEPLOYMENT_TYPE}"
    
    if [[ "$base_env" == "$target_env" ]]; then
        return 0  # No overrides needed
    fi
    
    declare -A base_config
    declare -A target_config
    declare -A merged_config
    
    # Extract base configuration
    local base_cache_key="${base_env}:${deployment_type}"
    local target_cache_key="${target_env}:${deployment_type}"
    
    # Copy base configuration
    local config_key value
    for config_key in $(aa_keys CONFIG_CACHE); do
        if [[ "$config_key" =~ ^${base_cache_key}: ]]; then
            value=$(aa_get CONFIG_CACHE "$config_key")
            local new_key="${config_key#${base_cache_key}:}"
            aa_set base_config "$new_key" "$value"
        fi
    done
    
    # Copy target configuration
    for config_key in $(aa_keys CONFIG_CACHE); do
        if [[ "$config_key" =~ ^${target_cache_key}: ]]; then
            value=$(aa_get CONFIG_CACHE "$config_key")
            local new_key="${config_key#${target_cache_key}:}"
            aa_set target_config "$new_key" "$value"
        fi
    done
    
    # Merge configurations (target overrides base)
    aa_copy base_config merged_config
    aa_merge merged_config target_config true
    
    # Store merged configuration back
    for config_key in $(aa_keys merged_config); do
        value=$(aa_get merged_config "$config_key")
        aa_set CONFIG_CACHE "${target_cache_key}:${config_key}" "$value"
    done
    
    if declare -f log >/dev/null 2>&1; then
        log "Applied environment overrides: $base_env -> $target_env"
    fi
}

# Apply deployment type specific overrides
apply_deployment_overrides() {
    local env="$1"
    local deployment_type="$2"
    
    declare -A overrides
    local cache_key="${env}:${deployment_type}"
    
    # Define deployment-specific overrides
    case "$deployment_type" in
        "spot")
            aa_set overrides "infrastructure:auto_scaling:min_capacity" "2"
            aa_set overrides "infrastructure:auto_scaling:max_capacity" "10"
            aa_set overrides "cost_optimization:spot_instances:enabled" "true"
            aa_set overrides "cost_optimization:spot_instances:max_price" "2.00"
            aa_set overrides "infrastructure:instance_type" "g4dn.xlarge"
            ;;
        "ondemand")
            aa_set overrides "infrastructure:auto_scaling:min_capacity" "2"
            aa_set overrides "infrastructure:auto_scaling:max_capacity" "8"
            aa_set overrides "cost_optimization:spot_instances:enabled" "false"
            aa_set overrides "infrastructure:availability_guarantee" "high"
            ;;
        "simple")
            aa_set overrides "infrastructure:auto_scaling:min_capacity" "1"
            aa_set overrides "infrastructure:auto_scaling:max_capacity" "1"
            aa_set overrides "cost_optimization:spot_instances:enabled" "false"
            aa_set overrides "infrastructure:auto_scaling:enabled" "false"
            ;;
    esac
    
    # Apply overrides to cache
    local override_key value
    for override_key in $(aa_keys overrides); do
        value=$(aa_get overrides "$override_key")
        aa_set CONFIG_CACHE "${cache_key}:${override_key}" "$value"
        
        # Also store in deployment overrides for reference
        aa_set DEPLOYMENT_OVERRIDES "${deployment_type}:${override_key}" "$value"
    done
    
    if declare -f log >/dev/null 2>&1; then
        log "Applied deployment overrides for type: $deployment_type"
    fi
}

# Create configuration profile for specific use case
create_configuration_profile() {
    local profile_name="$1"
    local base_env="${2:-development}"
    local deployment_type="${3:-simple}"
    
    declare -A profile_config
    
    # Load base configuration first
    load_config "$base_env" "$deployment_type"
    
    # Define profiles with specific configurations
    case "$profile_name" in
        "ml_development")
            aa_set profile_config "infrastructure:instance_type" "g4dn.xlarge"
            aa_set profile_config "applications:ollama:resources:gpu_memory_fraction" "0.9"
            aa_set profile_config "applications:ollama:config:max_loaded_models" "1"
            aa_set profile_config "cost_optimization:spot_instances:enabled" "true"
            aa_set profile_config "cost_optimization:spot_instances:max_price" "1.50"
            ;;
        "ml_production")
            aa_set profile_config "infrastructure:instance_type" "g5.xlarge"
            aa_set profile_config "applications:ollama:resources:gpu_memory_fraction" "0.85"
            aa_set profile_config "applications:ollama:config:max_loaded_models" "2"
            aa_set profile_config "cost_optimization:spot_instances:enabled" "false"
            aa_set profile_config "infrastructure:auto_scaling:enabled" "true"
            ;;
        "cost_optimized")
            aa_set profile_config "infrastructure:instance_type" "g4dn.large"
            aa_set profile_config "cost_optimization:spot_instances:enabled" "true"
            aa_set profile_config "cost_optimization:spot_instances:max_price" "0.50"
            aa_set profile_config "infrastructure:auto_scaling:target_utilization" "85"
            ;;
        "high_availability")
            aa_set profile_config "infrastructure:auto_scaling:min_capacity" "3"
            aa_set profile_config "infrastructure:auto_scaling:max_capacity" "12"
            aa_set profile_config "cost_optimization:spot_instances:enabled" "false"
            aa_set profile_config "infrastructure:availability_guarantee" "high"
            ;;
    esac
    
    # Apply profile overrides
    local cache_key="${base_env}:${deployment_type}"
    local profile_key value
    for profile_key in $(aa_keys profile_config); do
        value=$(aa_get profile_config "$profile_key")
        aa_set CONFIG_CACHE "${cache_key}:${profile_key}" "$value"
    done
    
    # Store profile metadata
    aa_set CONFIG_METADATA "active_profile" "$profile_name"
    aa_set CONFIG_METADATA "profile_created_time" "$(date +%s)"
    aa_set CONFIG_METADATA "profile_base_env" "$base_env"
    aa_set CONFIG_METADATA "profile_deployment_type" "$deployment_type"
    
    if declare -f success >/dev/null 2>&1; then
        success "Created configuration profile: $profile_name"
    fi
}

# =============================================================================
# CONFIGURATION VALUE RETRIEVAL
# =============================================================================

# Enhanced configuration value retrieval using associative arrays
get_config_value() {
    local path="$1"
    local fallback="${2:-}"
    local env="${3:-$(aa_get CONFIG_STATE "current_environment")}"
    local deployment_type="${4:-$(aa_get CONFIG_STATE "current_deployment_type")}"
    
    # Construct cache key
    local cache_key="${env}:${deployment_type}"
    local config_key="${cache_key}:${path}"
    
    # First, try to get from cache
    local cached_value=$(aa_get CONFIG_CACHE "$config_key" "")
    if [[ -n "$cached_value" ]]; then
        echo "$cached_value"
        return 0
    fi
    
    # Try alternative key formats (handle legacy path formats)
    if [[ "$path" =~ ^\. ]]; then
        # Remove leading dot for cache lookup
        local clean_path="${path#.}"
        config_key="${cache_key}:${clean_path}"
        cached_value=$(aa_get CONFIG_CACHE "$config_key" "")
        if [[ -n "$cached_value" ]]; then
            echo "$cached_value"
            return 0
        fi
    fi
    
    # If not in cache, try to load from file directly
    local config_file=$(aa_get CONFIG_STATE "config_file_path")
    if [[ -z "$config_file" ]]; then
        config_file=$(get_config_file_path "${env:-$DEFAULT_ENVIRONMENT}")
    fi
    
    if [[ -f "$config_file" ]]; then
        local value=""
        
        # Try yq first (preferred)
        if command -v yq >/dev/null 2>&1; then
            value=$(yq eval "$path" "$config_file" 2>/dev/null || echo "")
            if [[ "$value" != "null" && "$value" != "" && "$value" != "~" ]]; then
                # Cache the result for future use
                aa_set CONFIG_CACHE "$config_key" "$value"
                echo "$value"
                return 0
            fi
        fi
        
        # Fallback to Python YAML parsing
        if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
            local python_script="
import yaml
import sys

def get_nested_value(data, path_str):
    try:
        path_parts = path_str.lstrip('.').split('.')
        current = data
        for part in path_parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                return None
        return current
    except:
        return None

try:
    with open('$config_file', 'r') as f:
        data = yaml.safe_load(f)
    result = get_nested_value(data, '$path')
    if result is not None:
        print(result)
        sys.exit(0)
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
"
            if value=$(python3 -c "$python_script" 2>/dev/null); then
                # Cache the result
                aa_set CONFIG_CACHE "$config_key" "$value"
                echo "$value"
                return 0
            fi
        fi
    fi
    
    # If all else fails, return fallback
    echo "$fallback"
    return 1
}

# Enhanced configuration retrieval with path validation
get_config_value_safe() {
    local path="$1"
    local fallback="${2:-}"
    local validate_type="${3:-}"  # string, number, boolean, array
    
    local value
    value=$(get_config_value "$path" "$fallback")
    
    # Validate type if specified
    case "$validate_type" in
        "number")
            if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                if declare -f warning >/dev/null 2>&1; then
                    warning "Configuration value for '$path' is not a valid number, using fallback"
                fi
                echo "$fallback"
                return 1
            fi
            ;;
        "boolean")
            if ! [[ "$value" =~ ^(true|false|yes|no|1|0)$ ]]; then
                if declare -f warning >/dev/null 2>&1; then
                    warning "Configuration value for '$path' is not a valid boolean, using fallback"
                fi
                echo "$fallback"
                return 1
            fi
            # Normalize boolean values
            case "$value" in
                "yes"|"1") value="true" ;;
                "no"|"0") value="false" ;;
            esac
            ;;
        "string")
            if [[ -z "$value" ]]; then
                echo "$fallback"
                return 1
            fi
            ;;
    esac
    
    echo "$value"
    return 0
}

# Get global configuration values
get_global_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".global.$key" "$fallback"
}

# Get infrastructure configuration values
get_infrastructure_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".infrastructure.$key" "$fallback"
}

# Get application configuration values
get_application_config() {
    local app="$1"
    local key="$2"
    local fallback="${3:-}"
    get_config_value ".applications.$app.$key" "$fallback"
}

# Get security configuration values
get_security_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".security.$key" "$fallback"
}

# Get monitoring configuration values
get_monitoring_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".monitoring.$key" "$fallback"
}

# Get cost optimization configuration values
get_cost_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".cost_optimization.$key" "$fallback"
}

# =============================================================================
# ENVIRONMENT VARIABLE GENERATION
# =============================================================================

# Generate base environment variables (common to all deployment types)
generate_base_env_vars() {
    cat << EOF
# =============================================================================
# Base Configuration Variables
# Generated by lib/config-management.sh v${CONFIG_MANAGEMENT_VERSION}
# Environment: ${ENVIRONMENT}
# Deployment Type: ${DEPLOYMENT_TYPE}
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# =============================================================================

# Global Configuration
ENVIRONMENT=${ENVIRONMENT}
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}
AWS_REGION=$(get_global_config "region" "$DEFAULT_REGION")
STACK_NAME=$(get_global_config "stack_name" "GeuseMaker-${ENVIRONMENT}")
PROJECT_NAME=$(get_global_config "project_name" "GeuseMaker")

# Infrastructure Configuration
VPC_CIDR=$(get_infrastructure_config "networking.vpc_cidr" "10.0.0.0/16")
EFS_PERFORMANCE_MODE=$(get_infrastructure_config "storage.efs_performance_mode" "generalPurpose")
EFS_ENCRYPTION=$(get_infrastructure_config "storage.efs_encryption" "true")
BACKUP_RETENTION_DAYS=$(get_infrastructure_config "storage.backup_retention_days" "30")

# Auto Scaling Configuration
ASG_MIN_CAPACITY=$(get_infrastructure_config "auto_scaling.min_capacity" "1")
ASG_MAX_CAPACITY=$(get_infrastructure_config "auto_scaling.max_capacity" "3")
ASG_TARGET_UTILIZATION=$(get_infrastructure_config "auto_scaling.target_utilization" "70")

# Security Configuration
CONTAINER_SECURITY_ENABLED=$(get_security_config "container_security.run_as_non_root" "true")
NETWORK_SECURITY_STRICT=$(get_security_config "network_security.cors_strict_mode" "true")
SECRETS_MANAGER_ENABLED=$(get_security_config "secrets_management.use_aws_secrets_manager" "true")

# Monitoring Configuration
MONITORING_ENABLED=$(get_monitoring_config "metrics.enabled" "true")
LOG_LEVEL=$(get_monitoring_config "logging.level" "info")
LOG_FORMAT=$(get_monitoring_config "logging.format" "json")
METRICS_RETENTION_DAYS=$(get_monitoring_config "metrics.retention_days" "30")

# Cost Optimization Configuration
SPOT_INSTANCES_ENABLED=$(get_cost_config "spot_instances.enabled" "false")
SPOT_MAX_PRICE=$(get_cost_config "spot_instances.max_price" "1.00")
AUTO_SCALING_ENABLED=$(get_cost_config "auto_scaling.scale_down_enabled" "true")
IDLE_TIMEOUT_MINUTES=$(get_cost_config "auto_scaling.idle_timeout_minutes" "30")
EOF
}

# Generate application-specific environment variables
generate_app_env_vars() {
    cat << EOF

# =============================================================================
# Application Configuration Variables
# =============================================================================

# PostgreSQL Configuration
POSTGRES_DB=$(get_application_config "postgres" "config.database_name" "n8n")
POSTGRES_MAX_CONNECTIONS=$(get_application_config "postgres" "config.max_connections" "100")
POSTGRES_SHARED_BUFFERS=$(get_application_config "postgres" "config.shared_buffers" "256MB")
POSTGRES_EFFECTIVE_CACHE_SIZE=$(get_application_config "postgres" "config.effective_cache_size" "1GB")

# n8n Configuration
N8N_CORS_ENABLED=$(get_application_config "n8n" "config.cors_enable" "true")
N8N_CORS_ALLOWED_ORIGINS=$(get_application_config "n8n" "config.cors_allowed_origins" "*")
N8N_PAYLOAD_SIZE_MAX=$(get_application_config "n8n" "config.payload_size_max" "16")
N8N_METRICS=$(get_application_config "n8n" "config.metrics" "true")
N8N_LOG_LEVEL=$(get_application_config "n8n" "config.log_level" "info")

# Ollama Configuration
OLLAMA_HOST=0.0.0.0
OLLAMA_GPU_MEMORY_FRACTION=$(get_application_config "ollama" "resources.gpu_memory_fraction" "0.80")
OLLAMA_MAX_LOADED_MODELS=$(get_application_config "ollama" "config.max_loaded_models" "2")
OLLAMA_CONCURRENT_REQUESTS=$(get_application_config "ollama" "config.concurrent_requests" "4")

# Qdrant Configuration
QDRANT__SERVICE__HTTP_PORT=6333
QDRANT__SERVICE__GRPC_PORT=6334
QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=$(get_application_config "qdrant" "config.max_search_threads" "4")
QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS=$(get_application_config "qdrant" "config.max_optimization_threads" "2")
QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=$(get_application_config "qdrant" "config.wal_capacity_mb" "128")

# Crawl4AI Configuration
CRAWL4AI_RATE_LIMITING_ENABLED=$(get_application_config "crawl4ai" "config.rate_limiting_enabled" "true")
CRAWL4AI_DEFAULT_LIMIT=$(get_application_config "crawl4ai" "config.default_limit" "1000/minute")
CRAWL4AI_MAX_CONCURRENT_SESSIONS=$(get_application_config "crawl4ai" "config.max_concurrent_sessions" "2")
CRAWL4AI_BROWSER_POOL_SIZE=$(get_application_config "crawl4ai" "config.browser_pool_size" "1")
EOF
}

# Generate secrets placeholders (to be filled by deployment scripts)
generate_secrets_env_vars() {
    cat << EOF

# =============================================================================
# Secrets and Dynamic Variables
# These will be populated by deployment scripts from AWS Parameter Store/Secrets Manager
# =============================================================================

# Database Secrets
# POSTGRES_PASSWORD must be set by deployment script or Parameter Store
# No fallback provided for security reasons
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD:-}

# n8n Secrets  
# N8N_ENCRYPTION_KEY must be set by deployment script or Parameter Store
# No fallback provided for security reasons
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY:-}
# N8N_USER_MANAGEMENT_JWT_SECRET must be set by deployment script or Parameter Store
N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET:-}

# n8n Configuration
N8N_BASIC_AUTH_ACTIVE=\${N8N_BASIC_AUTH_ACTIVE:-true}
N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER:-admin}
# N8N_BASIC_AUTH_PASSWORD must be set by deployment script or Parameter Store
# No fallback provided for security reasons
N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD:-}

# API Keys
OPENAI_API_KEY=\${OPENAI_API_KEY:-}

# AWS Infrastructure (populated by deployment scripts)
EFS_DNS=\${EFS_DNS:-}
INSTANCE_ID=\${INSTANCE_ID:-}
INSTANCE_TYPE=\${INSTANCE_TYPE:-}

# Monitoring and Health Check URLs
WEBHOOK_URL=\${WEBHOOK_URL:-http://localhost:5678}
NOTIFICATION_WEBHOOK=\${NOTIFICATION_WEBHOOK:-}

# Default region for AWS services
AWS_DEFAULT_REGION=\${AWS_REGION:-us-east-1}

# Variable Management Integration
# Source variable management library if available
if [ -f "\${PROJECT_ROOT:-/home/ubuntu/GeuseMaker}/lib/variable-management.sh" ]; then
    source "\${PROJECT_ROOT:-/home/ubuntu/GeuseMaker}/lib/variable-management.sh"
    
    # Initialize variables with Parameter Store integration
    if command -v init_all_variables >/dev/null 2>&1; then
        init_all_variables || true
    fi
fi
EOF
}

# Generate complete environment file
generate_env_file() {
    local output_file="${1:-}"
    local env="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    
    if [[ -z "$output_file" ]]; then
        output_file="${PROJECT_ROOT}/.env.${env}"
    fi
    
    # Ensure configuration is loaded
    if [[ "$CONFIG_CACHE_LOADED" != "true" ]]; then
        load_config "$env" || return 1
    fi
    
    # Generate complete environment file
    {
        generate_base_env_vars
        generate_app_env_vars  
        generate_secrets_env_vars
    } > "$output_file"
    
    if declare -f success >/dev/null 2>&1; then
        success "Environment file generated: $output_file"
    else
        echo "Environment file generated: $output_file"
    fi
    
    return 0
}

# =============================================================================
# IMAGE VERSION MANAGEMENT
# =============================================================================

# Get image version based on environment strategy
get_image_version() {
    local service="$1"
    local environment="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    local image_config_file="${CONFIG_DIR}/image-versions.yml"
    
    if [[ ! -f "$image_config_file" ]]; then
        if declare -f warning >/dev/null 2>&1; then
            warning "Image versions config not found: $image_config_file"
        fi
        return 1
    fi
    
    # Get version strategy for environment
    local version_strategy
    version_strategy=$(yq eval ".environments.${environment}.version_strategy // .settings.version_strategy // \"stable\"" "$image_config_file" 2>/dev/null)
    
    # Get image name and version based on strategy
    local image_base
    local image_tag
    image_base=$(yq eval ".services.${service}.image" "$image_config_file" 2>/dev/null)
    
    case "$version_strategy" in
        "latest")
            image_tag=$(yq eval ".services.${service}.versions.latest" "$image_config_file" 2>/dev/null)
            ;;
        "stable")
            image_tag=$(yq eval ".services.${service}.versions.stable" "$image_config_file" 2>/dev/null)
            ;;
        "locked")
            # Return full locked image with digest
            echo "$(yq eval ".services.${service}.versions.locked" "$image_config_file" 2>/dev/null)"
            return 0
            ;;
        *)
            image_tag=$(yq eval ".services.${service}.versions.stable" "$image_config_file" 2>/dev/null)
            ;;
    esac
    
    if [[ "$image_base" == "null" || "$image_tag" == "null" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Image configuration not found for service: $service"
        fi
        return 1
    fi
    
    echo "${image_base}:${image_tag}"
    return 0
}

# Validate image version configuration
validate_image_versions() {
    local image_config_file="${CONFIG_DIR}/image-versions.yml"
    
    if [[ ! -f "$image_config_file" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Image versions config not found: $image_config_file"
        fi
        return 1
    fi
    
    # Validate YAML syntax
    if ! yq eval '.' "$image_config_file" >/dev/null 2>&1; then
        if declare -f error >/dev/null 2>&1; then
            error "Invalid YAML syntax in image versions config"
        fi
        return 1
    fi
    
    # Validate required services are defined (bash 3.x compatible)
    local required_services="postgres n8n ollama qdrant crawl4ai"
    for service in $required_services; do
        if ! yq eval ".services.${service}" "$image_config_file" >/dev/null 2>&1; then
            if declare -f warning >/dev/null 2>&1; then
                warning "Missing image configuration for service: $service"
            fi
        fi
    done
    
    return 0
}

# Validate configuration file structure and syntax
validate_configuration() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Configuration file not found: $config_file"
        fi
        return 1
    fi
    
    # Validate YAML syntax using yq if available, otherwise try python
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
            if declare -f error >/dev/null 2>&1; then
                error "Invalid YAML syntax in configuration file: $config_file"
            fi
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            if declare -f error >/dev/null 2>&1; then
                error "Invalid YAML syntax in configuration file: $config_file"
            fi
            return 1
        fi
    fi
    
    # Check for required sections
    if command -v yq >/dev/null 2>&1; then
        local required_sections=("global" "infrastructure" "application")
        for section in "${required_sections[@]}"; do
            if ! yq eval ".${section}" "$config_file" >/dev/null 2>&1; then
                if declare -f error >/dev/null 2>&1; then
                    error "Missing required section '$section' in configuration file"
                fi
                return 1
            fi
        done
    fi
    
    return 0
}

# Generate Docker Compose image overrides
generate_docker_image_overrides() {
    local output_file="${1:-${PROJECT_ROOT}/docker-compose.images.yml}"
    local environment="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    
    if ! validate_image_versions; then
        return 1
    fi
    
    cat > "$output_file" << EOF
# Generated Docker Compose Image Overrides
# Environment: $environment
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

version: '3.8'

services:
EOF

    # Generate image overrides for each service (bash 3.x compatible)
    local services="postgres n8n ollama qdrant crawl4ai"
    for service in $services; do
        local image_version
        if image_version=$(get_image_version "$service"); then
            cat >> "$output_file" << EOF
  ${service}:
    image: ${image_version}
EOF
        fi
    done
    
    if declare -f success >/dev/null 2>&1; then
        success "Docker image overrides generated: $output_file"
    fi
    
    return 0
}

# =============================================================================
# DOCKER COMPOSE INTEGRATION
# =============================================================================

# Generate Docker Compose environment section for a service
generate_docker_env_section() {
    local service="$1"
    
    case "$service" in
        postgres)
            cat << EOF
    environment:
      - POSTGRES_DB=\${POSTGRES_DB:-n8n}
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_MAX_CONNECTIONS=\${POSTGRES_MAX_CONNECTIONS:-100}
      - POSTGRES_SHARED_BUFFERS=\${POSTGRES_SHARED_BUFFERS:-256MB}
      - POSTGRES_EFFECTIVE_CACHE_SIZE=\${POSTGRES_EFFECTIVE_CACHE_SIZE:-1GB}
EOF
            ;;
        n8n)
            cat << EOF
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB:-n8n}
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET}
      - N8N_CORS_ENABLED=\${N8N_CORS_ENABLED:-true}
      - N8N_CORS_ALLOWED_ORIGINS=\${N8N_CORS_ALLOWED_ORIGINS:-*}
      - N8N_PAYLOAD_SIZE_MAX=\${N8N_PAYLOAD_SIZE_MAX:-16}
      - N8N_METRICS=\${N8N_METRICS:-true}
      - N8N_LOG_LEVEL=\${N8N_LOG_LEVEL:-info}
EOF
            ;;
        ollama)
            cat << EOF
    environment:
      - OLLAMA_HOST=\${OLLAMA_HOST:-0.0.0.0}
      - OLLAMA_GPU_MEMORY_FRACTION=\${OLLAMA_GPU_MEMORY_FRACTION:-0.80}
      - OLLAMA_MAX_LOADED_MODELS=\${OLLAMA_MAX_LOADED_MODELS:-2}
      - OLLAMA_CONCURRENT_REQUESTS=\${OLLAMA_CONCURRENT_REQUESTS:-4}
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
EOF
            ;;
        qdrant)
            cat << EOF
    environment:
      - QDRANT__SERVICE__HTTP_PORT=\${QDRANT__SERVICE__HTTP_PORT:-6333}
      - QDRANT__SERVICE__GRPC_PORT=\${QDRANT__SERVICE__GRPC_PORT:-6334}
      - QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=\${QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS:-4}
      - QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS=\${QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS:-2}
      - QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=\${QDRANT__STORAGE__WAL__WAL_CAPACITY_MB:-128}
EOF
            ;;
        crawl4ai)
            cat << EOF
    environment:
      - CRAWL4AI_RATE_LIMITING_ENABLED=\${CRAWL4AI_RATE_LIMITING_ENABLED:-true}
      - CRAWL4AI_DEFAULT_LIMIT=\${CRAWL4AI_DEFAULT_LIMIT:-1000/minute}
      - CRAWL4AI_MAX_CONCURRENT_SESSIONS=\${CRAWL4AI_MAX_CONCURRENT_SESSIONS:-2}
      - CRAWL4AI_BROWSER_POOL_SIZE=\${CRAWL4AI_BROWSER_POOL_SIZE:-1}
      - OPENAI_API_KEY=\${OPENAI_API_KEY}
EOF
            ;;
        *)
            if declare -f warning >/dev/null 2>&1; then
                warning "Unknown service for Docker environment generation: $service"
            fi
            return 1
            ;;
    esac
}

# =============================================================================
# DEPLOYMENT TYPE SPECIFIC CONFIGURATION
# =============================================================================

# Apply deployment type specific overrides
apply_deployment_type_overrides() {
    local deployment_type="${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}"
    local deployment_config_file="${CONFIG_DIR}/deployment-types.yml"
    
    # Load deployment type specific configuration if available
    if [[ -f "$deployment_config_file" ]]; then
        # Extract deployment type specific values using yq
        if command -v yq >/dev/null 2>&1; then
            # Infrastructure overrides
            local min_capacity=$(yq eval ".${deployment_type}.infrastructure.auto_scaling.min_capacity // 1" "$deployment_config_file" 2>/dev/null)
            local max_capacity=$(yq eval ".${deployment_type}.infrastructure.auto_scaling.max_capacity // 3" "$deployment_config_file" 2>/dev/null)
            local target_util=$(yq eval ".${deployment_type}.infrastructure.auto_scaling.target_utilization // 70" "$deployment_config_file" 2>/dev/null)
            
            # Cost optimization overrides
            local spot_enabled=$(yq eval ".${deployment_type}.cost_optimization.spot_instances.enabled // false" "$deployment_config_file" 2>/dev/null)
            local spot_price=$(yq eval ".${deployment_type}.cost_optimization.spot_instances.max_price // 2.00" "$deployment_config_file" 2>/dev/null)
            local auto_scaling=$(yq eval ".${deployment_type}.cost_optimization.auto_scaling.scale_down_enabled // true" "$deployment_config_file" 2>/dev/null)
            
            # Apply the extracted values
            export ASG_MIN_CAPACITY="$min_capacity"
            export ASG_MAX_CAPACITY="$max_capacity"
            export ASG_TARGET_UTILIZATION="$target_util"
            export SPOT_INSTANCES_ENABLED="$spot_enabled"
            export SPOT_MAX_PRICE="$spot_price"
            export AUTO_SCALING_ENABLED="$auto_scaling"
            
            if declare -f log >/dev/null 2>&1; then
                log "Applied deployment type overrides from config: $deployment_type"
            fi
            return 0
        fi
    fi
    
    # Fallback to hardcoded values if config file not available
    case "$deployment_type" in
        spot)
            export SPOT_INSTANCES_ENABLED=true
            export SPOT_MAX_PRICE=$(get_cost_config "spot_instances.max_price" "2.00")
            export AUTO_SCALING_ENABLED=true
            export ASG_MIN_CAPACITY=2
            export ASG_MAX_CAPACITY=10
            ;;
        ondemand)
            export SPOT_INSTANCES_ENABLED=false
            export AUTO_SCALING_ENABLED=true
            export ASG_MIN_CAPACITY=2
            export ASG_MAX_CAPACITY=8
            ;;
        simple)  
            export SPOT_INSTANCES_ENABLED=false
            export AUTO_SCALING_ENABLED=false
            export ASG_MIN_CAPACITY=1
            export ASG_MAX_CAPACITY=1
            ;;
        *)
            if declare -f warning >/dev/null 2>&1; then
                warning "Unknown deployment type: $deployment_type"
            fi
            ;;
    esac
}

# =============================================================================
# HIGH-LEVEL CONFIGURATION FUNCTIONS
# =============================================================================

# Initialize configuration system
init_config() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${2:-$DEFAULT_DEPLOYMENT_TYPE}"
    
    # Check dependencies
    check_config_dependencies || return 1
    
    # Load configuration
    load_config "$env" "$deployment_type" || return 1
    
    # Apply deployment type overrides
    apply_deployment_type_overrides
    
    if declare -f success >/dev/null 2>&1; then
        success "Configuration system initialized: environment=$env, type=$deployment_type"
    fi
    
    return 0
}

# Generate all configuration files for an environment
generate_all_config_files() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${2:-$DEFAULT_DEPLOYMENT_TYPE}"
    
    # Initialize configuration
    init_config "$env" "$deployment_type" || return 1
    
    # Generate environment file
    generate_env_file "${PROJECT_ROOT}/.env.${env}" || return 1
    
    if declare -f success >/dev/null 2>&1; then
        success "All configuration files generated for environment: $env"
    fi
    
    return 0
}

# Get configuration summary for display
get_config_summary() {
    local env="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    
    cat << EOF
Configuration Summary:
  Environment: $env
  Deployment Type: ${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}
  AWS Region: $(get_global_config "region" "$DEFAULT_REGION")
  Stack Name: $(get_global_config "stack_name" "GeuseMaker-${env}")
  Project: $(get_global_config "project_name" "GeuseMaker")
  
Instance Configuration:
  Spot Instances: ${SPOT_INSTANCES_ENABLED:-false}
  Auto Scaling: ${AUTO_SCALING_ENABLED:-true}
  Min Capacity: ${ASG_MIN_CAPACITY:-1}
  Max Capacity: ${ASG_MAX_CAPACITY:-3}
  
Security Settings:
  Container Security: ${CONTAINER_SECURITY_ENABLED:-true}
  Secrets Manager: ${SECRETS_MANAGER_ENABLED:-true}
  Network Security: ${NETWORK_SECURITY_STRICT:-true}
EOF
}

# =============================================================================
# ADDITIONAL HELPER FUNCTIONS FOR TESTING
# =============================================================================

# Generate environment file from configuration
generate_environment_file() {
    local config_file="$1"
    local environment="${2:-development}"
    local output_file="$3"
    
    if [[ ! -f "$config_file" ]]; then
        log "Error: Configuration file not found: $config_file"
        return 1
    fi
    
    if [[ -z "$output_file" ]]; then
        log "Error: Output file path required"
        return 1
    fi
    
    # Load configuration first
    load_config "$environment" "${DEPLOYMENT_TYPE:-simple}"
    
    # Generate environment file using existing function
    generate_env_file "$output_file"
}

# Generate Docker Compose file from configuration  
generate_docker_compose() {
    local config_file="$1"
    local environment="${2:-development}"
    local output_file="$3"
    
    if [[ ! -f "$config_file" ]]; then
        log "Error: Configuration file not found: $config_file"
        return 1
    fi
    
    if [[ -z "$output_file" ]]; then
        log "Error: Output file path required"
        return 1
    fi
    
    # Load configuration first
    load_config "$environment" "${DEPLOYMENT_TYPE:-simple}"
    
    # Generate basic Docker Compose structure
    cat > "$output_file" << EOF
version: '3.8'

services:
  postgres:
    image: $(get_image_version "postgres" "16.1-alpine3.19")
    deploy:
      resources:
        limits:
          cpus: '$(get_application_config "postgres.resources.cpu_limit" "0.5")'
          memory: $(get_application_config "postgres.resources.memory_limit" "1G")
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-network

  n8n:
    image: $(get_image_version "n8n" "1.19.4")
    deploy:
      resources:
        limits:
          cpus: '$(get_application_config "n8n.resources.cpu_limit" "0.5")'
          memory: $(get_application_config "n8n.resources.memory_limit" "1G")
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: n8n
      DB_POSTGRESDB_PASSWORD: \${POSTGRES_PASSWORD}
      N8N_HOST: 0.0.0.0
      N8N_PORT: 5678
    ports:
      - "5678:5678"
    depends_on:
      - postgres
    networks:
      - n8n-network

volumes:
  postgres_data:

networks:
  n8n-network:
    driver: bridge
EOF
    
    return 0
}

# Validate security configuration
validate_security_configuration() {
    local config_file="${1:-}"
    
    if [[ ! -f "$config_file" ]]; then
        log "Error: Configuration file not found: $config_file"
        return 1
    fi
    
    # Load configuration
    load_config "${ENVIRONMENT:-development}" "${DEPLOYMENT_TYPE:-simple}"
    
    # Basic security validation - always pass for development environment
    local environment=$(get_global_config "environment" "development")
    
    if [[ "$environment" == "development" ]]; then
        # Development environment allows more relaxed security
        return 0
    elif [[ "$environment" == "production" ]]; then
        # Production requires stricter security
        local encryption_at_rest=$(get_security_config "secrets_management.encryption_at_rest" "false")
        local use_secrets_manager=$(get_security_config "secrets_management.use_aws_secrets_manager" "false")
        
        if [[ "$encryption_at_rest" != "true" ]] || [[ "$use_secrets_manager" != "true" ]]; then
            log "Error: Production environment requires encryption at rest and AWS Secrets Manager"
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# LIBRARY INITIALIZATION
# =============================================================================

# Auto-initialize if environment variables are set (with error handling)
if [[ -n "${AUTO_INIT_CONFIG:-}" && "${AUTO_INIT_CONFIG}" == "true" ]]; then
    if declare -f init_config >/dev/null 2>&1; then
        if ! init_config "${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}" "${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}" 2>/dev/null; then
            if declare -f warning >/dev/null 2>&1; then
                warning "Auto-initialization of configuration failed, manual initialization may be required"
            else
                echo "WARNING: Auto-initialization of configuration failed" >&2
            fi
        fi
    else
        if declare -f warning >/dev/null 2>&1; then
            warning "Auto-initialization requested but init_config function not available"
        else
            echo "WARNING: Auto-initialization requested but init_config function not available" >&2
        fi
    fi
fi

# Export main functions for external use (with error handling for export failures)
if command -v export >/dev/null 2>&1; then
    # Core validation functions
    export -f validate_environment validate_deployment_type validate_aws_region validate_stack_name 2>/dev/null || true
    
    # Configuration access functions
    export -f load_config get_config_value get_global_config get_infrastructure_config 2>/dev/null || true
    export -f get_application_config get_security_config get_monitoring_config get_cost_config 2>/dev/null || true
    
    # Generation functions
    export -f generate_env_file generate_docker_env_section init_config generate_all_config_files 2>/dev/null || true
    export -f get_config_summary apply_deployment_type_overrides check_config_dependencies 2>/dev/null || true
    
    # Image and validation functions
    export -f get_image_version validate_image_versions validate_configuration_file generate_docker_image_overrides 2>/dev/null || true
    export -f generate_environment_file generate_docker_compose validate_security_configuration 2>/dev/null || true
fi

if declare -f log >/dev/null 2>&1; then
    log "Configuration management library loaded (v${CONFIG_MANAGEMENT_VERSION})"
fi