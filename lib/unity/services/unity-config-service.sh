#!/usr/bin/env bash
# =============================================================================
# Unity Configuration Service - Production-Ready Configuration Management
# Unified configuration system with type safety, validation, and dynamic reloading
# Compatible with bash 3.x+
# =============================================================================

set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_UNITY_CONFIG_SERVICE_LOADED:-}" ]] && return 0
declare -gr _UNITY_CONFIG_SERVICE_LOADED=1

# =============================================================================
# INITIALIZATION AND GLOBALS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# Load Unity core if available, otherwise provide minimal compatibility
if [[ -f "$SCRIPT_DIR/../core/unity-core.sh" ]]; then
    source "$SCRIPT_DIR/../core/unity-core.sh"
else
    # Minimal compatibility layer
    UNITY_SUCCESS=0
    UNITY_ERROR_VALIDATION=1
    unity_log() { echo "[$1] $2" >&2; }
    unity_emit_event() { return 0; }
    unity_handle_error() { echo "ERROR: $3" >&2; return $2; }
    unity_register_service() { return 0; }
fi

# Configuration paths
UNITY_CONFIG_FILE="${UNITY_CONFIG_FILE:-$PROJECT_ROOT/config/unity.yml}"
UNITY_CONFIG_CACHE_DIR="${UNITY_CONFIG_CACHE_DIR:-$PROJECT_ROOT/.unity/state}"
UNITY_CONFIG_CACHE="$UNITY_CONFIG_CACHE_DIR/config-cache.json"
UNITY_CONFIG_SCHEMA_CACHE="$UNITY_CONFIG_CACHE_DIR/schema-cache.json"

# Configuration state
declare -g UNITY_CONFIG_LOADED="false"
declare -g UNITY_CONFIG_CACHE_TTL=300  # 5 minutes
declare -g UNITY_CONFIG_VALIDATION_MODE="${UNITY_CONFIG_VALIDATION_MODE:-strict}"  # strict, lenient, skip
declare -g UNITY_CONFIG_LOG_LEVEL="${UNITY_CONFIG_LOG_LEVEL:-info}"  # none, error, warn, info, debug

# Type definitions and validation
declare -gA UNITY_CONFIG_TYPES=()
declare -gA UNITY_CONFIG_VALIDATORS=()
declare -gA UNITY_CONFIG_DESCRIPTIONS=()
declare -gA UNITY_CONFIG_CACHE_MAP=()
declare -gA UNITY_CONFIG_CACHE_TIMESTAMPS=()

# File watchers for dynamic reloading
declare -ga UNITY_CONFIG_WATCHED_FILES=()
declare -gA UNITY_CONFIG_FILE_MTIMES=()

# Configuration sources in priority order (highest to lowest)
declare -ga UNITY_CONFIG_SOURCES=(
    "COMMAND_LINE_ARGS"      # Priority 1: Command line arguments
    "ENVIRONMENT_VARIABLES"  # Priority 2: Shell environment variables
    "ENV_FILES"             # Priority 3: .env.local, .env.production etc
    "AWS_PARAMETER_STORE"   # Priority 4: AWS Parameter Store
    "UNITY_CONFIG_FILE"     # Priority 5: config/unity.yml
    "DEFAULTS_CONFIG"       # Priority 6: config/defaults.yml
    "HARDCODED_DEFAULTS"    # Priority 7: Hardcoded fallbacks
)

unity_config_init() {
    unity_emit_event "CONFIG_SERVICE_INIT_STARTED" "config"
    
    # Create necessary directories
    mkdir -p "$UNITY_CONFIG_CACHE_DIR"
    mkdir -p "$(dirname "$UNITY_CONFIG_FILE")"
    
    # Initialize configuration schema
    _unity_config_init_schema
    
    # Load configuration from all sources
    _unity_config_load_all_sources || {
        unity_handle_error $UNITY_ERROR_VALIDATION "config_init" "Failed to load configuration sources"
        return $UNITY_ERROR_VALIDATION
    }
    
    # Validate configuration
    if [[ "$UNITY_CONFIG_VALIDATION_MODE" != "skip" ]]; then
        unity_config_validate || {
            if [[ "$UNITY_CONFIG_VALIDATION_MODE" == "strict" ]]; then
                return $UNITY_ERROR_VALIDATION
            else
                unity_log "WARN" "⚠️  Configuration validation failed but continuing in lenient mode"
            fi
        }
    fi
    
    # Initialize file watchers for dynamic reloading
    _unity_config_init_watchers
    
    UNITY_CONFIG_LOADED="true"
    unity_emit_event "CONFIG_SERVICE_INIT_COMPLETED" "config"
    unity_log "SUCCESS" "✅ Unity Config Service initialized successfully"
    return $UNITY_SUCCESS
}

# =============================================================================
# SCHEMA INITIALIZATION AND TYPE DEFINITIONS
# =============================================================================

_unity_config_init_schema() {
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "🔧 Initializing configuration schema"
    
    # Core deployment variables with enhanced type safety
    _unity_config_register "AWS_REGION" "string" "^(us|eu|ap|ca|sa|af|me|il|cn|us-gov)-(east|west|north|south|central|northeast|northwest|southeast|southwest)-[0-9]$" "AWS deployment region"
    _unity_config_register "AWS_DEFAULT_REGION" "string" "^(us|eu|ap|ca|sa|af|me|il|cn|us-gov)-(east|west|north|south|central|northeast|northwest|southeast|southwest)-[0-9]$" "Default AWS region fallback"
    _unity_config_register "AWS_PROFILE" "string" "^[a-zA-Z0-9][a-zA-Z0-9_-]*$" "AWS CLI profile name"
    _unity_config_register "STACK_NAME" "string" "^[a-zA-Z][a-zA-Z0-9-]{0,127}$" "Unique CloudFormation stack identifier"
    _unity_config_register "DEPLOYMENT_TYPE" "enum" "^(spot|ondemand|simple|enterprise|alb|cdn|full)$" "Deployment strategy type"
    _unity_config_register "INSTANCE_TYPE" "string" "^[a-z][0-9]+[a-z]*\\.[a-z0-9]+$" "EC2 instance type"
    _unity_config_register "KEY_NAME" "string" "^[a-zA-Z0-9][a-zA-Z0-9_-]*$" "EC2 SSH key pair name"
    _unity_config_register "VOLUME_SIZE" "integer" "^[1-9][0-9]*$" "EBS volume size in GB (minimum 1)"
    _unity_config_register "ENVIRONMENT" "enum" "^(development|staging|production)$" "Deployment environment"
    
    # Feature flags with boolean validation
    _unity_config_register "DEBUG" "boolean" "^(true|false)$" "Enable debug output"
    _unity_config_register "DRY_RUN" "boolean" "^(true|false)$" "Perform dry run without creating resources"
    _unity_config_register "CLEANUP_ON_FAILURE" "boolean" "^(true|false)$" "Clean up resources on deployment failure"
    _unity_config_register "VALIDATE_ONLY" "boolean" "^(true|false)$" "Validate configuration without deploying"
    _unity_config_register "VERBOSE" "boolean" "^(true|false)$" "Enable verbose logging"
    
    # Application service toggles
    _unity_config_register "N8N_ENABLE" "boolean" "^(true|false)$" "Enable n8n workflow automation service"
    _unity_config_register "QDRANT_ENABLE" "boolean" "^(true|false)$" "Enable Qdrant vector database service"
    _unity_config_register "OLLAMA_ENABLE" "boolean" "^(true|false)$" "Enable Ollama LLM inference service"
    _unity_config_register "CRAWL4AI_ENABLE" "boolean" "^(true|false)$" "Enable Crawl4AI web scraping service"
    
    # Infrastructure features
    _unity_config_register "ENABLE_MULTI_AZ" "boolean" "^(true|false)$" "Deploy across multiple availability zones"
    _unity_config_register "ENABLE_ALB" "boolean" "^(true|false)$" "Enable Application Load Balancer"
    _unity_config_register "ENABLE_CLOUDFRONT" "boolean" "^(true|false)$" "Enable CloudFront CDN"
    _unity_config_register "ENABLE_EFS" "boolean" "^(true|false)$" "Enable EFS for persistent storage"
    _unity_config_register "ENABLE_MONITORING" "boolean" "^(true|false)$" "Enable CloudWatch monitoring"
    _unity_config_register "ENABLE_BACKUP" "boolean" "^(true|false)$" "Enable automated backups"
    
    # Spot instance configuration
    _unity_config_register "SPOT_PRICE" "decimal" "^[0-9]+(\\.[0-9]+)?$" "Maximum spot price (empty for on-demand)"
    _unity_config_register "SPOT_INTERRUPTION_BEHAVIOR" "enum" "^(terminate|stop|hibernate)$" "Spot instance interruption behavior"
    _unity_config_register "ENABLE_SPOT_FALLBACK" "boolean" "^(true|false)$" "Fallback to on-demand if spot fails"
    
    # Networking
    _unity_config_register "VPC_CIDR" "cidr" "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$" "VPC CIDR block"
    _unity_config_register "PUBLIC_SUBNET_COUNT" "integer" "^[1-9][0-9]*$" "Number of public subnets"
    _unity_config_register "PRIVATE_SUBNET_COUNT" "integer" "^[1-9][0-9]*$" "Number of private subnets"
    
    # Backup and retention
    _unity_config_register "BACKUP_RETENTION_DAYS" "integer" "^[1-9][0-9]*$" "Backup retention period in days"
    
    # Parameter Store integration
    _unity_config_register "LOAD_PARAMETER_STORE" "boolean" "^(true|false)$" "Load values from AWS Parameter Store"
    _unity_config_register "PARAM_STORE_PREFIX" "string" "^/[a-zA-Z0-9/_-]+$" "Parameter Store path prefix"
    
    # Unity system configuration
    _unity_config_register "UNITY_LOG_LEVEL" "enum" "^(debug|info|warn|error|none)$" "Unity system log level"
    _unity_config_register "UNITY_CONFIG_VALIDATION_MODE" "enum" "^(strict|lenient|skip)$" "Configuration validation strictness"
    _unity_config_register "UNITY_CONFIG_CACHE_TTL" "integer" "^[1-9][0-9]*$" "Configuration cache TTL in seconds"
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "✅ Configuration schema initialized with ${#UNITY_CONFIG_TYPES[@]} variables"
}

# Register a configuration variable with type and validation
# Args: variable_name, type, validator_regex, description
_unity_config_register() {
    local var_name="$1"
    local var_type="$2"
    local validator="$3"
    local description="$4"
    
    UNITY_CONFIG_TYPES["$var_name"]="$var_type"
    UNITY_CONFIG_VALIDATORS["$var_name"]="$validator"
    UNITY_CONFIG_DESCRIPTIONS["$var_name"]="$description"
}

# =============================================================================
# CONFIGURATION LOADING FROM MULTIPLE SOURCES
# =============================================================================

_unity_config_load_all_sources() {
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "🔄 Loading configuration from all sources"
    
    local source_errors=0
    
    # Load from each source in priority order
    for source in "${UNITY_CONFIG_SOURCES[@]}"; do
        case "$source" in
            "COMMAND_LINE_ARGS")
                _unity_config_load_command_line_args || ((source_errors++))
                ;;
            "ENVIRONMENT_VARIABLES")
                _unity_config_load_environment_variables || ((source_errors++))
                ;;
            "ENV_FILES")
                _unity_config_load_env_files || ((source_errors++))
                ;;
            "AWS_PARAMETER_STORE")
                _unity_config_load_parameter_store || ((source_errors++))
                ;;
            "UNITY_CONFIG_FILE")
                _unity_config_load_unity_config || ((source_errors++))
                ;;
            "DEFAULTS_CONFIG")
                _unity_config_load_defaults_config || ((source_errors++))
                ;;
            "HARDCODED_DEFAULTS")
                _unity_config_load_hardcoded_defaults || ((source_errors++))
                ;;
        esac
    done
    
    # Cache the final configuration state
    _unity_config_save_cache
    
    if [[ $source_errors -gt 0 ]]; then
        unity_log "WARN" "⚠️  $source_errors configuration sources had errors but continuing"
    fi
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "✅ Configuration loading completed"
    return 0
}

_unity_config_load_command_line_args() {
    # Command line arguments take highest priority
    # Args are parsed and stored in environment variables by the calling script
    # This function validates they match registered variables
    
    local processed=0
    for var_name in "${!UNITY_CONFIG_TYPES[@]}"; do
        if [[ -n "${!var_name:-}" ]]; then
            _unity_config_set_with_validation "$var_name" "${!var_name}" "COMMAND_LINE"
            ((processed++))
        fi
    done
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "📝 Processed $processed command line arguments"
    return 0
}

_unity_config_load_environment_variables() {
    local processed=0
    for var_name in "${!UNITY_CONFIG_TYPES[@]}"; do
        if [[ -n "${!var_name:-}" ]]; then
            _unity_config_set_with_validation "$var_name" "${!var_name}" "ENVIRONMENT"
            ((processed++))
        fi
    done
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "🌍 Processed $processed environment variables"
    return 0
}

_unity_config_load_env_files() {
    # Load environment files in priority order
    local env_files=(
        ".env.local"
        ".env.${ENVIRONMENT:-development}"
        ".env"
    )
    
    local loaded_file=""
    for env_file in "${env_files[@]}"; do
        local full_path="$PROJECT_ROOT/$env_file"
        if [[ -f "$full_path" ]]; then
            _unity_config_load_env_file "$full_path" || return 1
            loaded_file="$env_file"
            break
        fi
    done
    
    if [[ -n "$loaded_file" ]]; then
        [[ "$UNITY_CONFIG_LOG_LEVEL" != "none" ]] && unity_log "INFO" "📄 Loaded configuration from $loaded_file"
        UNITY_CONFIG_WATCHED_FILES+=("$PROJECT_ROOT/$loaded_file")
    fi
    
    return 0
}

_unity_config_load_env_file() {
    local env_file="$1"
    local processed=0
    local line_number=0
    
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        ((line_number++))
        
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Handle export prefix
        if [[ "$key" =~ ^[[:space:]]*export[[:space:]]+ ]]; then
            key="${key#*export}"
            key="${key#"${key%%[![:space:]]*}"}"  # Remove leading whitespace
        fi
        
        # Clean up key and value
        key="${key%"${key##*[![:space:]]}"}"  # Remove trailing whitespace
        [[ -z "$key" ]] && continue
        
        # Remove quotes from value
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        
        # Only process registered variables
        if [[ ${UNITY_CONFIG_TYPES["$key"]+isset} ]]; then
            _unity_config_set_with_validation "$key" "$value" "ENV_FILE:$(basename "$env_file"):$line_number"
            ((processed++))
        elif [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]]; then
            unity_log "DEBUG" "⚠️  Skipped unregistered variable: $key (line $line_number)"
        fi
    done < "$env_file"
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "📄 Processed $processed variables from $(basename "$env_file")"
    return 0
}

_unity_config_load_parameter_store() {
    # Only load if enabled and AWS CLI is available
    [[ "${LOAD_PARAMETER_STORE:-false}" == "true" ]] || return 0
    command -v aws >/dev/null 2>&1 || return 0
    
    local prefix="${PARAM_STORE_PREFIX:-/aibuildkit}"
    local processed=0
    
    # Get parameters with retry logic
    local params
    local attempt=1
    local max_attempts=3
    
    while [[ $attempt -le $max_attempts ]]; do
        if params=$(aws ssm get-parameters-by-path \
            --path "$prefix" \
            --recursive \
            --with-decryption \
            --max-items 50 \
            --query 'Parameters[*].[Name,Value]' \
            --output text 2>/dev/null); then
            break
        else
            [[ "$UNITY_CONFIG_LOG_LEVEL" != "none" ]] && unity_log "WARN" "⚠️  Parameter Store access failed (attempt $attempt/$max_attempts)"
            if [[ $attempt -lt $max_attempts ]]; then
                sleep $((attempt * 2))
            fi
            ((attempt++))
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        unity_log "ERROR" "❌ Failed to load from Parameter Store after $max_attempts attempts"
        return 1
    fi
    
    # Process parameters
    while IFS=$'\t' read -r name value; do
        [[ -z "$name" ]] && continue
        
        # Convert parameter name to environment variable
        local var_name="${name#${prefix}/}"
        var_name="${var_name//\//_}"
        var_name="${var_name^^}"  # Convert to uppercase
        
        # Only process registered variables
        if [[ ${UNITY_CONFIG_TYPES["$var_name"]+isset} ]]; then
            _unity_config_set_with_validation "$var_name" "$value" "PARAMETER_STORE:$name"
            ((processed++))
        fi
    done <<< "$params"
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" != "none" ]] && unity_log "INFO" "☁️  Processed $processed parameters from Parameter Store"
    return 0
}

_unity_config_load_unity_config() {
    [[ -f "$UNITY_CONFIG_FILE" ]] || return 0
    
    # Add to watched files for dynamic reloading
    UNITY_CONFIG_WATCHED_FILES+=("$UNITY_CONFIG_FILE")
    
    # Simple YAML parsing for Unity config values
    local processed=0
    
    # Load values from unity.yml if they exist
    for var_name in "${!UNITY_CONFIG_TYPES[@]}"; do
        local yaml_value
        yaml_value=$(_unity_config_parse_yaml "$UNITY_CONFIG_FILE" "$var_name") || continue
        
        if [[ -n "$yaml_value" && "$yaml_value" != "null" ]]; then
            _unity_config_set_with_validation "$var_name" "$yaml_value" "UNITY_CONFIG"
            ((processed++))
        fi
    done
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "🔧 Processed $processed variables from unity.yml"
    return 0
}

_unity_config_load_defaults_config() {
    local defaults_file="$PROJECT_ROOT/config/defaults.yml"
    [[ -f "$defaults_file" ]] || return 0
    
    # Add to watched files
    UNITY_CONFIG_WATCHED_FILES+=("$defaults_file")
    
    local processed=0
    
    # Load values from defaults.yml using the existing mapping
    for var_name in "${!UNITY_CONFIG_TYPES[@]}"; do
        local default_value
        default_value=$(_unity_config_parse_yaml "$defaults_file" "$var_name") || continue
        
        if [[ -n "$default_value" && "$default_value" != "null" ]]; then
            # Only set if not already set by higher priority source
            if [[ -z "${UNITY_CONFIG_CACHE_MAP["$var_name"]:-}" ]]; then
                _unity_config_set_with_validation "$var_name" "$default_value" "DEFAULTS_CONFIG"
                ((processed++))
            fi
        fi
    done
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "📋 Processed $processed variables from defaults.yml"
    return 0
}

_unity_config_load_hardcoded_defaults() {
    # Set hardcoded defaults for critical variables if not already set
    declare -A hardcoded_defaults=(
        ["AWS_REGION"]="us-east-1"
        ["AWS_DEFAULT_REGION"]="us-east-1"
        ["AWS_PROFILE"]="default"
        ["DEPLOYMENT_TYPE"]="spot"
        ["INSTANCE_TYPE"]="g4dn.xlarge"
        ["VOLUME_SIZE"]="30"
        ["ENVIRONMENT"]="development"
        ["DEBUG"]="false"
        ["DRY_RUN"]="false"
        ["CLEANUP_ON_FAILURE"]="true"
        ["VALIDATE_ONLY"]="false"
        ["VERBOSE"]="false"
        ["N8N_ENABLE"]="true"
        ["QDRANT_ENABLE"]="true"
        ["OLLAMA_ENABLE"]="true"
        ["CRAWL4AI_ENABLE"]="true"
        ["ENABLE_EFS"]="true"
        ["ENABLE_MONITORING"]="true"
        ["SPOT_INTERRUPTION_BEHAVIOR"]="terminate"
        ["ENABLE_SPOT_FALLBACK"]="true"
        ["VPC_CIDR"]="10.0.0.0/16"
        ["PUBLIC_SUBNET_COUNT"]="2"
        ["PRIVATE_SUBNET_COUNT"]="2"
        ["BACKUP_RETENTION_DAYS"]="7"
        ["LOAD_PARAMETER_STORE"]="false"
        ["PARAM_STORE_PREFIX"]="/aibuildkit"
        ["UNITY_LOG_LEVEL"]="info"
        ["UNITY_CONFIG_VALIDATION_MODE"]="strict"
        ["UNITY_CONFIG_CACHE_TTL"]="300"
    )
    
    local processed=0
    for var_name in "${!hardcoded_defaults[@]}"; do
        # Only set if not already set by any higher priority source
        if [[ -z "${UNITY_CONFIG_CACHE_MAP["$var_name"]:-}" ]]; then
            _unity_config_set_with_validation "$var_name" "${hardcoded_defaults[$var_name]}" "HARDCODED_DEFAULT"
            ((processed++))
        fi
    done
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "🔧 Applied $processed hardcoded defaults"
    return 0
}

# =============================================================================
# TYPE-SAFE CONFIGURATION ACCESS AND VALIDATION
# =============================================================================

unity_config_get() {
    local key="$1"
    local default_value="${2:-}"
    local use_cache="${3:-true}"
    
    # Validate key is registered
    if [[ ! ${UNITY_CONFIG_TYPES["$key"]+isset} ]]; then
        if [[ "$UNITY_CONFIG_VALIDATION_MODE" == "strict" ]]; then
            unity_handle_error $UNITY_ERROR_VALIDATION "config_get" "Unregistered variable: $key"
            return $UNITY_ERROR_VALIDATION
        else
            unity_log "WARN" "⚠️  Accessing unregistered variable: $key"
            echo "$default_value"
            return 0
        fi
    fi
    
    # Check cache first
    if [[ "$use_cache" == "true" && ${UNITY_CONFIG_CACHE_MAP["$key"]+isset} ]]; then
        local cache_time="${UNITY_CONFIG_CACHE_TIMESTAMPS[$key]:-0}"
        local current_time="$(date +%s)"
        if (( current_time - cache_time < UNITY_CONFIG_CACHE_TTL )); then
            echo "${UNITY_CONFIG_CACHE_MAP[$key]}"
            return 0
        fi
    fi
    
    # Get value from environment or cache
    local value="${UNITY_CONFIG_CACHE_MAP[$key]:-${!key:-$default_value}}"
    
    # Update cache
    if [[ "$use_cache" == "true" ]]; then
        UNITY_CONFIG_CACHE_MAP["$key"]="$value"
        UNITY_CONFIG_CACHE_TIMESTAMPS["$key"]="$(date +%s)"
    fi
    
    echo "$value"
}

unity_config_set() {
    local key="$1"
    local value="$2"
    local source="${3:-USER}"
    
    _unity_config_set_with_validation "$key" "$value" "$source"
}

_unity_config_set_with_validation() {
    local key="$1"
    local value="$2"
    local source="${3:-UNKNOWN}"
    
    # Validate key is registered
    if [[ ! ${UNITY_CONFIG_TYPES["$key"]+isset} ]]; then
        if [[ "$UNITY_CONFIG_VALIDATION_MODE" == "strict" ]]; then
            unity_handle_error $UNITY_ERROR_VALIDATION "config_set" "Cannot set unregistered variable: $key"
            return $UNITY_ERROR_VALIDATION
        else
            unity_log "WARN" "⚠️  Setting unregistered variable: $key"
        fi
    fi
    
    # Type validation and normalization
    local normalized_value
    normalized_value=$(_unity_config_validate_and_normalize "$key" "$value") || {
        unity_handle_error $UNITY_ERROR_VALIDATION "config_set" "Invalid value '$value' for variable '$key'"
        return $UNITY_ERROR_VALIDATION
    }
    
    # Update cache and environment
    UNITY_CONFIG_CACHE_MAP["$key"]="$normalized_value"
    UNITY_CONFIG_CACHE_TIMESTAMPS["$key"]="$(date +%s)"
    export "$key=$normalized_value"
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "🔧 Set $key='$normalized_value' (source: $source)"
    
    # Emit configuration change event
    unity_emit_event "CONFIG_VARIABLE_CHANGED" "config" "key=$key,value=$normalized_value,source=$source"
    
    return 0
}

_unity_config_validate_and_normalize() {
    local key="$1"
    local value="$2"
    
    # Get type and validator
    local var_type="${UNITY_CONFIG_TYPES[$key]:-string}"
    local validator="${UNITY_CONFIG_VALIDATORS[$key]:-}"
    
    # Handle empty values based on type
    if [[ -z "$value" ]]; then
        case "$var_type" in
            "boolean") echo "false"; return 0 ;;
            "integer") echo "0"; return 0 ;;
            "decimal") echo "0.0"; return 0 ;;
            *) echo ""; return 0 ;;
        esac
    fi
    
    # Type-specific validation and normalization
    case "$var_type" in
        "boolean")
            case "${value,,}" in
                true|yes|1|on|enabled) echo "true"; return 0 ;;
                false|no|0|off|disabled) echo "false"; return 0 ;;
                *) return 1 ;;
            esac
            ;;
        "integer")
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                echo "$value"
                return 0
            else
                return 1
            fi
            ;;
        "decimal")
            if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                echo "$value"
                return 0
            else
                return 1
            fi
            ;;
        "enum"|"string"|"cidr")
            # Apply regex validator if provided
            if [[ -n "$validator" ]]; then
                if [[ "$value" =~ $validator ]]; then
                    echo "$value"
                    return 0
                else
                    return 1
                fi
            else
                echo "$value"
                return 0
            fi
            ;;
        *)
            echo "$value"
            return 0
            ;;
    esac
}

# =============================================================================
# YAML PARSING AND FILE OPERATIONS
# =============================================================================

_unity_config_parse_yaml() {
    local yaml_file="$1"
    local key="$2"
    
    # Check if yq is available for better parsing
    if command -v yq >/dev/null 2>&1; then
        yq eval ".$key // empty" "$yaml_file" 2>/dev/null
    else
        # Fallback to simple grep/sed parsing
        # This handles basic YAML structures but not complex nested objects
        local value
        value=$(grep -E "^[[:space:]]*${key}:" "$yaml_file" 2>/dev/null | head -1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr -d '"')
        echo "$value"
    fi
}

# =============================================================================
# DYNAMIC RELOADING AND FILE WATCHING
# =============================================================================

_unity_config_init_watchers() {
    # Initialize file modification time tracking
    for file in "${UNITY_CONFIG_WATCHED_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            if command -v stat >/dev/null 2>&1; then
                # Use stat for better cross-platform compatibility
                local mtime
                if [[ "$(uname)" == "Darwin" ]]; then
                    mtime=$(stat -f "%m" "$file" 2>/dev/null || echo "0")
                else
                    mtime=$(stat -c "%Y" "$file" 2>/dev/null || echo "0")
                fi
                UNITY_CONFIG_FILE_MTIMES["$file"]="$mtime"
            else
                # Fallback to ls -l parsing
                UNITY_CONFIG_FILE_MTIMES["$file"]="$(ls -l "$file" 2>/dev/null | awk '{print $6" "$7" "$8}')"
            fi
        fi
    done
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "👀 Watching ${#UNITY_CONFIG_WATCHED_FILES[@]} configuration files for changes"
}

unity_config_check_for_changes() {
    local changes_detected=false
    local changed_files=()
    
    for file in "${UNITY_CONFIG_WATCHED_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            continue
        fi
        
        local current_mtime
        if command -v stat >/dev/null 2>&1; then
            if [[ "$(uname)" == "Darwin" ]]; then
                current_mtime=$(stat -f "%m" "$file" 2>/dev/null || echo "0")
            else
                current_mtime=$(stat -c "%Y" "$file" 2>/dev/null || echo "0")
            fi
        else
            current_mtime="$(ls -l "$file" 2>/dev/null | awk '{print $6" "$7" "$8}')"
        fi
        
        local cached_mtime="${UNITY_CONFIG_FILE_MTIMES[$file]:-}"
        
        if [[ "$current_mtime" != "$cached_mtime" ]]; then
            changes_detected=true
            changed_files+=("$file")
            UNITY_CONFIG_FILE_MTIMES["$file"]="$current_mtime"
        fi
    done
    
    if [[ "$changes_detected" == "true" ]]; then
        unity_log "INFO" "🔄 Configuration changes detected in: ${changed_files[*]}"
        unity_config_reload
        return 0
    fi
    
    return 1
}

unity_config_reload() {
    unity_emit_event "CONFIG_RELOAD_STARTED" "config"
    unity_log "INFO" "🔄 Reloading configuration..."
    
    # Clear cache
    UNITY_CONFIG_CACHE_MAP=()
    UNITY_CONFIG_CACHE_TIMESTAMPS=()
    
    # Reload from all sources
    _unity_config_load_all_sources || {
        unity_handle_error $UNITY_ERROR_VALIDATION "config_reload" "Failed to reload configuration"
        return $UNITY_ERROR_VALIDATION
    }
    
    # Re-validate
    if [[ "$UNITY_CONFIG_VALIDATION_MODE" != "skip" ]]; then
        unity_config_validate || {
            if [[ "$UNITY_CONFIG_VALIDATION_MODE" == "strict" ]]; then
                unity_handle_error $UNITY_ERROR_VALIDATION "config_reload" "Configuration validation failed after reload"
                return $UNITY_ERROR_VALIDATION
            fi
        }
    fi
    
    unity_emit_event "CONFIG_RELOAD_COMPLETED" "config"
    unity_log "SUCCESS" "✅ Configuration reloaded successfully"
    return 0
}

# =============================================================================
# CACHING AND PERFORMANCE
# =============================================================================

_unity_config_save_cache() {
    # Save configuration state to JSON cache for persistence
    local cache_data="{"
    local first=true
    
    for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
        [[ "$first" == "false" ]] && cache_data+=","
        first=false
        
        local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
        local timestamp="${UNITY_CONFIG_CACHE_TIMESTAMPS[$key]:-0}"
        local var_type="${UNITY_CONFIG_TYPES[$key]:-string}"
        local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
        
        # JSON escape the value and description
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        description="${description//\\/\\\\}"
        description="${description//\"/\\\"}"
        
        cache_data+="\"$key\":{\"value\":\"$value\",\"type\":\"$var_type\",\"timestamp\":$timestamp,\"description\":\"$description\"}"
    done
    
    cache_data+="}"
    
    # Write to cache file
    echo "$cache_data" > "$UNITY_CONFIG_CACHE"
    
    [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "💾 Configuration cache saved with ${#UNITY_CONFIG_CACHE_MAP[@]} variables"
}

_unity_config_load_cache() {
    [[ -f "$UNITY_CONFIG_CACHE" ]] || return 1
    
    # Check cache age
    local cache_age
    if command -v stat >/dev/null 2>&1; then
        if [[ "$(uname)" == "Darwin" ]]; then
            cache_age=$(( $(date +%s) - $(stat -f "%m" "$UNITY_CONFIG_CACHE") ))
        else
            cache_age=$(( $(date +%s) - $(stat -c "%Y" "$UNITY_CONFIG_CACHE") ))
        fi
    else
        cache_age=$UNITY_CONFIG_CACHE_TTL  # Force reload if stat unavailable
    fi
    
    if (( cache_age > UNITY_CONFIG_CACHE_TTL )); then
        [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "💾 Configuration cache expired (age: ${cache_age}s)"
        return 1
    fi
    
    # Load cache if available and jq is installed
    if command -v jq >/dev/null 2>&1; then
        local loaded=0
        while IFS= read -r key; do
            local value timestamp
            value=$(jq -r ".\"$key\".value" "$UNITY_CONFIG_CACHE" 2>/dev/null)
            timestamp=$(jq -r ".\"$key\".timestamp" "$UNITY_CONFIG_CACHE" 2>/dev/null)
            
            if [[ -n "$value" && "$value" != "null" ]]; then
                UNITY_CONFIG_CACHE_MAP["$key"]="$value"
                UNITY_CONFIG_CACHE_TIMESTAMPS["$key"]="$timestamp"
                export "$key=$value"
                ((loaded++))
            fi
        done < <(jq -r 'keys[]' "$UNITY_CONFIG_CACHE" 2>/dev/null)
        
        [[ "$UNITY_CONFIG_LOG_LEVEL" == "debug" ]] && unity_log "DEBUG" "💾 Loaded $loaded variables from cache"
        return 0
    fi
    
    return 1
}

unity_config_clear_cache() {
    UNITY_CONFIG_CACHE_MAP=()
    UNITY_CONFIG_CACHE_TIMESTAMPS=()
    rm -f "$UNITY_CONFIG_CACHE"
    unity_log "INFO" "🗑️  Configuration cache cleared"
}

# =============================================================================
# COMPREHENSIVE VALIDATION PIPELINE
# =============================================================================

unity_config_validate() {
    unity_emit_event "CONFIG_VALIDATION_STARTED" "config"
    unity_log "INFO" "🔍 Validating configuration..."
    
    local validation_errors=()
    local validation_warnings=()
    
    # Stage 1: YAML Syntax Validation
    if [[ -f "$UNITY_CONFIG_FILE" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            if ! python3 -c "import yaml; yaml.safe_load(open('$UNITY_CONFIG_FILE'))" 2>/dev/null; then
                validation_errors+=("Invalid YAML syntax in $UNITY_CONFIG_FILE")
            fi
        elif command -v yq >/dev/null 2>&1; then
            if ! yq eval '.' "$UNITY_CONFIG_FILE" >/dev/null 2>&1; then
                validation_errors+=("Invalid YAML syntax in $UNITY_CONFIG_FILE")
            fi
        else
            validation_warnings+=("YAML syntax validation skipped (no python3 or yq available)")
        fi
    fi
    
    # Stage 2: Schema Validation
    local schema_errors=0
    for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
        local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
        
        if ! _unity_config_validate_and_normalize "$key" "$value" >/dev/null 2>&1; then
            validation_errors+=("Invalid value '$value' for variable '$key' (type: ${UNITY_CONFIG_TYPES[$key]:-unknown})")
            ((schema_errors++))
        fi
    done
    
    # Stage 3: Business Logic Validation
    _unity_config_validate_business_rules validation_errors validation_warnings
    
    # Stage 4: Dependency Validation
    _unity_config_validate_dependencies validation_errors validation_warnings
    
    # Stage 5: Security Validation
    _unity_config_validate_security validation_errors validation_warnings
    
    # Report results
    local total_errors=${#validation_errors[@]}
    local total_warnings=${#validation_warnings[@]}
    
    if [[ $total_warnings -gt 0 ]]; then
        unity_log "WARN" "⚠️  Configuration validation warnings ($total_warnings):"
        for warning in "${validation_warnings[@]}"; do
            unity_log "WARN" "  - $warning"
        done
    fi
    
    if [[ $total_errors -gt 0 ]]; then
        unity_log "ERROR" "❌ Configuration validation failed ($total_errors errors):"
        for error in "${validation_errors[@]}"; do
            unity_log "ERROR" "  - $error"
        done
        
        unity_emit_event "CONFIG_VALIDATION_FAILED" "config" "errors=$total_errors,warnings=$total_warnings"
        
        if [[ "$UNITY_CONFIG_VALIDATION_MODE" == "strict" ]]; then
            return $UNITY_ERROR_VALIDATION
        fi
    else
        unity_log "SUCCESS" "✅ Configuration validation passed ($total_warnings warnings)"
        unity_emit_event "CONFIG_VALIDATION_PASSED" "config" "warnings=$total_warnings"
    fi
    
    return 0
}

_unity_config_validate_business_rules() {
    local -n errors_ref=$1
    local -n warnings_ref=$2
    
    # Check deployment type vs instance type compatibility
    local deployment_type="${UNITY_CONFIG_CACHE_MAP[DEPLOYMENT_TYPE]:-}"
    local instance_type="${UNITY_CONFIG_CACHE_MAP[INSTANCE_TYPE]:-}"
    local environment="${UNITY_CONFIG_CACHE_MAP[ENVIRONMENT]:-}"
    
    if [[ "$deployment_type" == "simple" && "$instance_type" =~ ^(g4dn|g5|p3|p4d) ]]; then
        warnings_ref+=("Simple deployment with GPU instance '$instance_type' may be over-provisioned")
    fi
    
    if [[ "$environment" == "production" && "$deployment_type" == "spot" ]]; then
        warnings_ref+=("Production environment with spot instances may experience interruptions")
    fi
    
    # Check volume size vs instance type
    local volume_size="${UNITY_CONFIG_CACHE_MAP[VOLUME_SIZE]:-30}"
    if [[ "$instance_type" =~ ^(g4dn|g5) ]] && (( volume_size < 50 )); then
        warnings_ref+=("GPU instances typically need more storage. Consider increasing VOLUME_SIZE to 100GB+")
    fi
    
    # Check required variables are set
    local required_vars=("STACK_NAME" "KEY_NAME")
    for var in "${required_vars[@]}"; do
        local value="${UNITY_CONFIG_CACHE_MAP[$var]:-}"
        if [[ -z "$value" ]]; then
            errors_ref+=("Required variable '$var' is not set")
        fi
    done
    
    # Check CIDR block validity
    local vpc_cidr="${UNITY_CONFIG_CACHE_MAP[VPC_CIDR]:-}"
    if [[ -n "$vpc_cidr" ]]; then
        if ! _unity_config_validate_cidr "$vpc_cidr"; then
            errors_ref+=("Invalid VPC CIDR block: $vpc_cidr")
        fi
    fi
}

_unity_config_validate_dependencies() {
    local -n errors_ref=$1
    local -n warnings_ref=$2
    
    # Check if ALB is enabled but multi-AZ is not
    local enable_alb="${UNITY_CONFIG_CACHE_MAP[ENABLE_ALB]:-false}"
    local enable_multi_az="${UNITY_CONFIG_CACHE_MAP[ENABLE_MULTI_AZ]:-false}"
    
    if [[ "$enable_alb" == "true" && "$enable_multi_az" == "false" ]]; then
        warnings_ref+=("ALB enabled but multi-AZ disabled. Consider enabling ENABLE_MULTI_AZ for better availability")
    fi
    
    # Check if CloudFront is enabled but ALB is not
    local enable_cloudfront="${UNITY_CONFIG_CACHE_MAP[ENABLE_CLOUDFRONT]:-false}"
    if [[ "$enable_cloudfront" == "true" && "$enable_alb" == "false" ]]; then
        warnings_ref+=("CloudFront enabled but ALB disabled. CloudFront typically requires a load balancer origin")
    fi
    
    # Check Parameter Store configuration
    local load_param_store="${UNITY_CONFIG_CACHE_MAP[LOAD_PARAMETER_STORE]:-false}"
    local param_store_prefix="${UNITY_CONFIG_CACHE_MAP[PARAM_STORE_PREFIX]:-}"
    
    if [[ "$load_param_store" == "true" && -z "$param_store_prefix" ]]; then
        errors_ref+=("Parameter Store loading enabled but PARAM_STORE_PREFIX not set")
    fi
}

_unity_config_validate_security() {
    local -n errors_ref=$1
    local -n warnings_ref=$2
    
    # Check for sensitive data in environment variables
    for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
        local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
        
        # Check for potential passwords or secrets in plain text
        if [[ "$key" =~ (PASSWORD|SECRET|KEY|TOKEN) && -n "$value" ]]; then
            if [[ ${#value} -lt 8 ]]; then
                warnings_ref+=("$key appears to be a weak credential (less than 8 characters)")
            fi
            
            # Check if it looks like a placeholder
            if [[ "$value" =~ ^(changeme|password|secret|key|token|your-.*|.*-here)$ ]]; then
                errors_ref+=("$key contains placeholder value '$value' - must be set to actual value")
            fi
        fi
    done
    
    # Check for production-specific security requirements
    local environment="${UNITY_CONFIG_CACHE_MAP[ENVIRONMENT]:-}"
    if [[ "$environment" == "production" ]]; then
        local enable_monitoring="${UNITY_CONFIG_CACHE_MAP[ENABLE_MONITORING]:-false}"
        if [[ "$enable_monitoring" != "true" ]]; then
            warnings_ref+=("Production environment should have monitoring enabled")
        fi
        
        local enable_backup="${UNITY_CONFIG_CACHE_MAP[ENABLE_BACKUP]:-false}"
        if [[ "$enable_backup" != "true" ]]; then
            warnings_ref+=("Production environment should have backups enabled")
        fi
    fi
}

_unity_config_validate_cidr() {
    local cidr="$1"
    
    # Basic CIDR validation
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    
    # Extract IP and prefix
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Validate prefix length
    if (( prefix < 8 || prefix > 32 )); then
        return 1
    fi
    
    # Validate IP octets
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if (( octet < 0 || octet > 255 )); then
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# CONFIGURATION REPORTING AND UTILITIES
# =============================================================================

unity_config_execute() {
    local operation="$1"
    shift
    
    case "$operation" in
        "get")
            unity_config_get "$@"
            ;;
        "set")
            unity_config_set "$@"
            ;;
        "validate")
            unity_config_validate
            ;;
        "reload")
            unity_config_reload
            ;;
        "show"|"list"|"dump")
            unity_config_show "$@"
            ;;
        "check-changes")
            unity_config_check_for_changes && echo "Changes detected" || echo "No changes"
            ;;
        "clear-cache")
            unity_config_clear_cache
            ;;
        "export")
            unity_config_export "$@"
            ;;
        "import")
            unity_config_import "$@"
            ;;
        "schema")
            unity_config_show_schema "$@"
            ;;
        *)
            unity_handle_error $UNITY_ERROR_VALIDATION "config_execute" "Unknown operation: $operation"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
}

unity_config_show() {
    local format="${1:-table}"  # table, json, yaml, env
    local filter="${2:-}"       # Optional variable name pattern
    
    case "$format" in
        "json")
            echo "{"
            local first=true
            for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
                [[ -n "$filter" && ! "$key" =~ $filter ]] && continue
                
                [[ "$first" == "false" ]] && echo ","
                first=false
                
                local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
                local var_type="${UNITY_CONFIG_TYPES[$key]:-string}"
                local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
                
                # JSON escape
                value="${value//\\/\\\\}"
                value="${value//\"/\\\"}"
                description="${description//\\/\\\\}"
                description="${description//\"/\\\"}"
                
                echo -n "  \"$key\": {\"value\": \"$value\", \"type\": \"$var_type\", \"description\": \"$description\"}"
            done
            echo
            echo "}"
            ;;
        "yaml")
            echo "# Unity Configuration Export"
            echo "# Generated: $(date)"
            echo "configuration:"
            for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
                [[ -n "$filter" && ! "$key" =~ $filter ]] && continue
                
                local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
                local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
                
                [[ -n "$description" ]] && echo "  # $description"
                echo "  $key: \"$value\""
            done
            ;;
        "env")
            echo "# Unity Configuration Export - Environment Variables"
            echo "# Generated: $(date)"
            for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
                [[ -n "$filter" && ! "$key" =~ $filter ]] && continue
                
                local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
                local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
                
                [[ -n "$description" ]] && echo "# $description"
                echo "export $key=\"$value\""
            done
            ;;
        "table"|*)
            printf "%-25s %-15s %-10s %-50s\n" "VARIABLE" "VALUE" "TYPE" "DESCRIPTION"
            printf "%-25s %-15s %-10s %-50s\n" "--------" "-----" "----" "-----------"
            for key in "${!UNITY_CONFIG_CACHE_MAP[@]}"; do
                [[ -n "$filter" && ! "$key" =~ $filter ]] && continue
                
                local value="${UNITY_CONFIG_CACHE_MAP[$key]}"
                local var_type="${UNITY_CONFIG_TYPES[$key]:-string}"
                local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
                
                printf "%-25s %-15s %-10s %-50s\n" \
                    "${key:0:24}" "${value:0:14}" "$var_type" "${description:0:49}"
            done
            ;;
    esac
}

unity_config_show_schema() {
    local format="${1:-table}"
    
    case "$format" in
        "json")
            echo "{"
            local first=true
            for key in "${!UNITY_CONFIG_TYPES[@]}"; do
                [[ "$first" == "false" ]] && echo ","
                first=false
                
                local var_type="${UNITY_CONFIG_TYPES[$key]}"
                local validator="${UNITY_CONFIG_VALIDATORS[$key]:-}"
                local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
                
                # JSON escape
                validator="${validator//\\/\\\\}"
                validator="${validator//\"/\\\"}"
                description="${description//\\/\\\\}"
                description="${description//\"/\\\"}"
                
                echo -n "  \"$key\": {\"type\": \"$var_type\", \"validator\": \"$validator\", \"description\": \"$description\"}"
            done
            echo
            echo "}"
            ;;
        "table"|*)
            printf "%-25s %-10s %-30s %-40s\n" "VARIABLE" "TYPE" "VALIDATOR" "DESCRIPTION"
            printf "%-25s %-10s %-30s %-40s\n" "--------" "----" "---------" "-----------"
            for key in "${!UNITY_CONFIG_TYPES[@]}"; do
                local var_type="${UNITY_CONFIG_TYPES[$key]}"
                local validator="${UNITY_CONFIG_VALIDATORS[$key]:-}"
                local description="${UNITY_CONFIG_DESCRIPTIONS[$key]:-}"
                
                printf "%-25s %-10s %-30s %-40s\n" \
                    "${key:0:24}" "$var_type" "${validator:0:29}" "${description:0:39}"
            done
            ;;
    esac
}

unity_config_export() {
    local output_file="${1:-config-export.yml}"
    local format="${2:-yaml}"
    
    unity_config_show "$format" > "$output_file"
    unity_log "SUCCESS" "✅ Configuration exported to $output_file"
}

unity_config_import() {
    local input_file="$1"
    local format="${2:-auto}"
    
    [[ -f "$input_file" ]] || {
        unity_handle_error $UNITY_ERROR_VALIDATION "config_import" "Import file not found: $input_file"
        return $UNITY_ERROR_VALIDATION
    }
    
    # Auto-detect format if not specified
    if [[ "$format" == "auto" ]]; then
        case "${input_file##*.}" in
            yml|yaml) format="yaml" ;;
            json) format="json" ;;
            env) format="env" ;;
            *) format="env" ;;  # Default fallback
        esac
    fi
    
    case "$format" in
        "env")
            _unity_config_load_env_file "$input_file"
            ;;
        "yaml")
            # TODO: Implement YAML import
            unity_log "WARN" "⚠️  YAML import not yet implemented"
            return 1
            ;;
        "json")
            # TODO: Implement JSON import
            unity_log "WARN" "⚠️  JSON import not yet implemented"
            return 1
            ;;
        *)
            unity_handle_error $UNITY_ERROR_VALIDATION "config_import" "Unsupported import format: $format"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
    
    unity_log "SUCCESS" "✅ Configuration imported from $input_file"
}

# =============================================================================
# SERVICE LIFECYCLE MANAGEMENT
# =============================================================================

unity_config_cleanup() {
    # Clear in-memory state
    UNITY_CONFIG_CACHE_MAP=()
    UNITY_CONFIG_CACHE_TIMESTAMPS=()
    UNITY_CONFIG_WATCHED_FILES=()
    UNITY_CONFIG_FILE_MTIMES=()
    
    # Remove cache files
    rm -f "$UNITY_CONFIG_CACHE" "$UNITY_CONFIG_SCHEMA_CACHE"
    
    unity_log "INFO" "🧹 Configuration service cleaned up"
    return $UNITY_SUCCESS
}

unity_config_status() {
    unity_log "INFO" "📊 Unity Config Service Status:"
    unity_log "INFO" "  - Service: ${UNITY_CONFIG_LOADED:-false}"
    unity_log "INFO" "  - Validation mode: ${UNITY_CONFIG_VALIDATION_MODE:-strict}"
    unity_log "INFO" "  - Log level: ${UNITY_CONFIG_LOG_LEVEL:-info}"
    unity_log "INFO" "  - Cache TTL: ${UNITY_CONFIG_CACHE_TTL:-300}s"
    
    if [[ -f "$UNITY_CONFIG_FILE" ]]; then
        unity_log "INFO" "  - Unity config: $UNITY_CONFIG_FILE"
        local line_count=$(wc -l < "$UNITY_CONFIG_FILE" 2>/dev/null || echo "0")
        unity_log "INFO" "  - Lines: $line_count"
    else
        unity_log "INFO" "  - Unity config: not found"
    fi
    
    unity_log "INFO" "  - Registered variables: ${#UNITY_CONFIG_TYPES[@]}"
    unity_log "INFO" "  - Cached variables: ${#UNITY_CONFIG_CACHE_MAP[@]}"
    unity_log "INFO" "  - Watched files: ${#UNITY_CONFIG_WATCHED_FILES[@]}"
    
    return $UNITY_SUCCESS
}

# =============================================================================
# MIGRATION UTILITIES
# =============================================================================

unity_config_migrate_from_legacy() {
    unity_log "INFO" "🔄 Migrating from legacy configuration system..."
    
    # Migrate from existing variable management system
    if command -v get_variable >/dev/null 2>&1; then
        local migrated=0
        for key in "${!UNITY_CONFIG_TYPES[@]}"; do
            local legacy_value
            legacy_value=$(get_variable "$key" 2>/dev/null) && {
                unity_config_set "$key" "$legacy_value" "LEGACY_MIGRATION"
                ((migrated++))
            }
        done
        unity_log "INFO" "📦 Migrated $migrated variables from legacy system"
    fi
    
    # Migrate from config/defaults.yml if exists
    local defaults_file="$PROJECT_ROOT/config/defaults.yml"
    if [[ -f "$defaults_file" ]]; then
        _unity_config_load_defaults_config
        unity_log "INFO" "📋 Migrated defaults from $defaults_file"
    fi
    
    unity_log "SUCCESS" "✅ Legacy configuration migration completed"
}

# Register the service
unity_register_service "config" "$(basename "${BASH_SOURCE[0]}")"

# Export main functions for external use
export -f unity_config_init
export -f unity_config_get
export -f unity_config_set
export -f unity_config_validate
export -f unity_config_reload
export -f unity_config_show
export -f unity_config_execute
export -f unity_config_status
export -f unity_config_cleanup

# Service is already registered above
