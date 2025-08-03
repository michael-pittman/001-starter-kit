#!/usr/bin/env bash
# =============================================================================
# Unity Environment Override Manager
# Advanced environment-specific configuration override system
# Supports development, staging, production with inheritance and validation
# Compatible with bash 3.x+ and enterprise deployment patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL CONSTANTS AND CONFIGURATION
# =============================================================================

readonly OVERRIDE_MANAGER_VERSION="1.0.0"
readonly CONFIG_ROOT="${CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../config" && pwd)}"
readonly PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$CONFIG_ROOT/.." && pwd)}"

# Environment configuration
readonly ENVIRONMENTS_DIR="$CONFIG_ROOT/environments"
readonly OVERRIDES_CACHE_DIR="$CONFIG_ROOT/.cache/overrides"
readonly OVERRIDE_HISTORY_DIR="$CONFIG_ROOT/.cache/override-history"

# Supported environments
readonly SUPPORTED_ENVIRONMENTS=("development" "staging" "production" "test" "demo")
readonly DEFAULT_ENVIRONMENT="development"

# Override precedence (highest to lowest)
readonly OVERRIDE_PRECEDENCE=(
    "cli_args"          # Command line arguments
    "env_vars"          # Environment variables
    "env_local"         # .env.local file
    "env_specific"      # .env.<environment> file
    "aws_parameter_store" # AWS Parameter Store
    "env_config"        # config/environments/<environment>.yml
    "base_config"       # config/defaults.yml
    "hardcoded"         # Hardcoded defaults
)

# =============================================================================
# BASH VERSION COMPATIBILITY
# =============================================================================

# Check bash version for associative arrays
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    BASH_4_PLUS=true
    declare -A ENVIRONMENT_CONFIGS
    declare -A OVERRIDE_STACK
    declare -A APPLIED_OVERRIDES
else
    BASH_4_PLUS=false
    # Use prefix-based variables for bash 3.x
    ENV_CONFIGS_PREFIX="ENV_CFG_"
    OVERRIDE_STACK_PREFIX="OVERRIDE_"
    APPLIED_OVERRIDES_PREFIX="APPLIED_"
fi

# =============================================================================
# LOGGING AND ERROR HANDLING
# =============================================================================

# Enhanced logging for override operations
log_override() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo "[$timestamp] [OVERRIDE-MANAGER] ERROR: $message" >&2
            ;;
        "WARN")
            echo "[$timestamp] [OVERRIDE-MANAGER] WARN: $message" >&2
            ;;
        "INFO")
            [[ "${OVERRIDE_DEBUG:-false}" != "false" ]] && \
                echo "[$timestamp] [OVERRIDE-MANAGER] INFO: $message" >&2
            ;;
        "DEBUG")
            [[ "${OVERRIDE_DEBUG:-false}" == "true" ]] && \
                echo "[$timestamp] [OVERRIDE-MANAGER] DEBUG: $message" >&2
            ;;
    esac
}

# Override error handler
override_error() {
    local error_code="$1"
    local error_message="$2"
    local suggestion="${3:-}"
    
    log_override "ERROR" "Override operation failed with code $error_code: $error_message"
    [[ -n "$suggestion" ]] && log_override "INFO" "Suggestion: $suggestion"
    return "$error_code"
}

# =============================================================================
# ENVIRONMENT VALIDATION AND DISCOVERY
# =============================================================================

# Validate environment name
validate_environment() {
    local environment="$1"
    
    if [[ -z "$environment" ]]; then
        override_error 400 "Environment name cannot be empty"
        return 1
    fi
    
    # Check if environment is supported
    local supported=false
    for env in "${SUPPORTED_ENVIRONMENTS[@]}"; do
        if [[ "$environment" == "$env" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" != "true" ]]; then
        log_override "WARN" "Environment '$environment' is not in supported list: ${SUPPORTED_ENVIRONMENTS[*]}"
        log_override "INFO" "Proceeding anyway - custom environments are allowed"
    fi
    
    return 0
}

# Discover available environment configurations
discover_environment_configs() {
    local discovery_report="$OVERRIDES_CACHE_DIR/environment-discovery.json"
    
    log_override "INFO" "Discovering environment configurations..."
    
    mkdir -p "$OVERRIDES_CACHE_DIR"
    
    # Initialize discovery report
    cat > "$discovery_report" << 'EOF'
{
  "discovery_timestamp": "",
  "manager_version": "",
  "environments": {},
  "files": {
    "yaml_configs": [],
    "env_files": [],
    "parameter_store_prefixes": []
  },
  "statistics": {
    "total_environments": 0,
    "total_override_files": 0,
    "total_variables": 0
  }
}
EOF
    
    # Update metadata
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    update_json_field "$discovery_report" ".discovery_timestamp" "\"$timestamp\""
    update_json_field "$discovery_report" ".manager_version" "\"$OVERRIDE_MANAGER_VERSION\""
    
    # Discover YAML environment configs
    discover_yaml_environment_configs "$discovery_report"
    
    # Discover .env files
    discover_env_files "$discovery_report"
    
    # Discover Parameter Store configurations
    discover_parameter_store_prefixes "$discovery_report"
    
    # Calculate statistics
    calculate_discovery_statistics "$discovery_report"
    
    log_override "INFO" "Environment discovery completed. Report: $discovery_report"
    echo "$discovery_report"
}

# Discover YAML environment configurations
discover_yaml_environment_configs() {
    local discovery_report="$1"
    local env_count=0
    
    if [[ -d "$ENVIRONMENTS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            local env_name=$(basename "$file" .yml)
            local relative_path="${file#$PROJECT_ROOT/}"
            local variable_count=$(analyze_yaml_variables "$file")
            
            # Add environment info
            local env_entry=$(cat << EOF
{
  "name": "$env_name",
  "config_file": "$relative_path",
  "absolute_path": "$file",
  "variable_count": $variable_count,
  "last_modified": "$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$file" 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "size_bytes": $(wc -c < "$file"),
  "supported": $(is_environment_supported "$env_name" && echo "true" || echo "false")
}
EOF
            )
            
            update_json_field "$discovery_report" ".environments[\"$env_name\"]" "$env_entry"
            
            # Add to files list
            local file_entry=$(cat << EOF
{
  "path": "$relative_path",
  "environment": "$env_name",
  "type": "yaml_config",
  "variable_count": $variable_count
}
EOF
            )
            
            add_to_json_array "$discovery_report" ".files.yaml_configs" "$file_entry"
            ((env_count++))
        done < <(find "$ENVIRONMENTS_DIR" -name "*.yml" -type f -print0 2>/dev/null || true)
    fi
    
    log_override "DEBUG" "Discovered $env_count YAML environment configurations"
}

# Discover environment files
discover_env_files() {
    local discovery_report="$1"
    
    # Find all .env files
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local relative_path="${file#$PROJECT_ROOT/}"
        local variable_count=$(grep -c '^[A-Z_][A-Z0-9_]*=' "$file" 2>/dev/null || echo "0")
        
        # Determine environment from filename
        local environment="unknown"
        case "$filename" in
            ".env.local") environment="local" ;;
            ".env.development") environment="development" ;;
            ".env.staging") environment="staging" ;;
            ".env.production") environment="production" ;;
            ".env.test") environment="test" ;;
            ".env") environment="default" ;;
        esac
        
        # Add to files list
        local file_entry=$(cat << EOF
{
  "path": "$relative_path",
  "environment": "$environment",
  "type": "env_file",
  "variable_count": $variable_count,
  "last_modified": "$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$file" 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
        )
        
        add_to_json_array "$discovery_report" ".files.env_files" "$file_entry"
    done < <(find "$PROJECT_ROOT" -maxdepth 1 -name ".env*" -type f -print0 2>/dev/null || true)
}

# Discover Parameter Store prefixes
discover_parameter_store_prefixes() {
    local discovery_report="$1"
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        log_override "WARN" "AWS CLI not available, skipping Parameter Store discovery"
        return 0
    fi
    
    # Common Parameter Store prefixes
    local prefixes=("/aibuildkit" "/geousemaker" "/unity" "/config")
    
    for prefix in "${prefixes[@]}"; do
        # Try to list parameters with the prefix
        local param_count=0
        if aws ssm get-parameters-by-path \
            --path "$prefix" \
            --recursive \
            --query 'Parameters[].Name' \
            --output text >/dev/null 2>&1; then
            
            param_count=$(aws ssm get-parameters-by-path \
                --path "$prefix" \
                --recursive \
                --query 'length(Parameters)' \
                --output text 2>/dev/null || echo "0")
        fi
        
        if [[ "$param_count" -gt "0" ]]; then
            # Add to parameter store prefixes
            local prefix_entry=$(cat << EOF
{
  "prefix": "$prefix",
  "parameter_count": $param_count,
  "type": "parameter_store",
  "discovery_time": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
            )
            
            add_to_json_array "$discovery_report" ".files.parameter_store_prefixes" "$prefix_entry"
            log_override "DEBUG" "Found $param_count parameters with prefix $prefix"
        fi
    done
}

# =============================================================================
# OVERRIDE RESOLUTION AND MERGING
# =============================================================================

# Load base configuration
load_base_configuration() {
    local base_config_file="$CONFIG_ROOT/defaults.yml"
    local cache_key="base_config_$(stat -f '%m' "$base_config_file" 2>/dev/null || echo "0")"
    
    log_override "DEBUG" "Loading base configuration from: $base_config_file"
    
    # Check cache first
    if command -v cache_get >/dev/null 2>&1; then
        if cache_get "$cache_key" 2>/dev/null; then
            log_override "DEBUG" "Using cached base configuration"
            return 0
        fi
    fi
    
    # Load and cache base configuration
    if [[ -f "$base_config_file" ]]; then
        local base_config=$(cat "$base_config_file")
        
        # Cache for future use
        if command -v cache_set >/dev/null 2>&1; then
            cache_set "$cache_key" "$base_config" 3600 "base_config"
        fi
        
        echo "$base_config"
        log_override "DEBUG" "Base configuration loaded successfully"
    else
        override_error 404 "Base configuration file not found: $base_config_file"
        return 1
    fi
}

# Load environment-specific configuration
load_environment_configuration() {
    local environment="$1"
    local env_config_file="$ENVIRONMENTS_DIR/${environment}.yml"
    local cache_key="env_config_${environment}_$(stat -f '%m' "$env_config_file" 2>/dev/null || echo "0")"
    
    log_override "DEBUG" "Loading environment configuration for: $environment"
    
    # Validate environment
    validate_environment "$environment" || return 1
    
    # Check cache first
    if command -v cache_get >/dev/null 2>&1; then
        if cache_get "$cache_key" 2>/dev/null; then
            log_override "DEBUG" "Using cached environment configuration"
            return 0
        fi
    fi
    
    # Load environment configuration
    if [[ -f "$env_config_file" ]]; then
        local env_config=$(cat "$env_config_file")
        
        # Cache for future use
        if command -v cache_set >/dev/null 2>&1; then
            cache_set "$cache_key" "$env_config" 1800 "env_config,$environment"
        fi
        
        echo "$env_config"
        log_override "DEBUG" "Environment configuration loaded for: $environment"
    else
        log_override "WARN" "Environment configuration file not found: $env_config_file"
        echo "{}"  # Return empty config
    fi
}

# Merge configurations with precedence
merge_configurations() {
    local base_config="$1"
    local environment_config="$2"
    local environment="$3"
    local output_file="${4:-}"
    
    log_override "INFO" "Merging configurations for environment: $environment"
    
    # Create temporary files for processing
    local temp_base=$(mktemp)
    local temp_env=$(mktemp)
    local temp_merged=$(mktemp)
    
    # Clean up on exit
    trap 'rm -f "$temp_base" "$temp_env" "$temp_merged"' EXIT
    
    # Write configurations to temp files
    echo "$base_config" > "$temp_base"
    echo "$environment_config" > "$temp_env"
    
    # Merge using yq if available
    if command -v yq >/dev/null 2>&1; then
        # Deep merge environment config over base config
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$temp_base" "$temp_env" > "$temp_merged" 2>/dev/null || {
            log_override "WARN" "yq merge failed, using base configuration only"
            cp "$temp_base" "$temp_merged"
        }
    else
        log_override "WARN" "yq not available, using base configuration only"
        cp "$temp_base" "$temp_merged"
    fi
    
    # Apply runtime overrides
    apply_runtime_overrides "$temp_merged" "$environment"
    
    # Output result
    if [[ -n "$output_file" ]]; then
        cp "$temp_merged" "$output_file"
        log_override "INFO" "Merged configuration saved to: $output_file"
    else
        cat "$temp_merged"
    fi
    
    log_override "INFO" "Configuration merge completed for environment: $environment"
}

# Apply runtime environment variable overrides
apply_runtime_overrides() {
    local config_file="$1"
    local environment="$2"
    
    log_override "DEBUG" "Applying runtime overrides for environment: $environment"
    
    # Define environment variable to config path mappings
    local override_mappings=(
        "AWS_REGION:.global.region"
        "AWS_DEFAULT_REGION:.global.default_region"
        "STACK_NAME:.metadata.stack_name"
        "DEPLOYMENT_TYPE:.deployment_variables.deployment_type"
        "INSTANCE_TYPE:.deployment_variables.instance_type"
        "KEY_NAME:.deployment_variables.key_name"
        "VOLUME_SIZE:.deployment_variables.volume_size"
        "ENVIRONMENT:.global.environment"
        "DEBUG:.deployment_variables.debug"
        "DRY_RUN:.deployment_variables.dry_run"
        "ENABLE_MULTI_AZ:.deployment_variables.enable_multi_az"
        "ENABLE_ALB:.deployment_variables.enable_alb"
        "ENABLE_CLOUDFRONT:.deployment_variables.enable_cloudfront"
        "ENABLE_EFS:.deployment_variables.enable_efs"
        "SPOT_PRICE:.deployment_variables.spot_price"
        "SPOT_INTERRUPTION_BEHAVIOR:.deployment_variables.spot_interruption_behavior"
        "ENABLE_SPOT_FALLBACK:.deployment_variables.enable_spot_fallback"
        "BACKUP_RETENTION_DAYS:.deployment_variables.backup_retention_days"
        "N8N_ENABLE:.deployment_variables.n8n_enable"
        "QDRANT_ENABLE:.deployment_variables.qdrant_enable"
        "OLLAMA_ENABLE:.deployment_variables.ollama_enable"
        "CRAWL4AI_ENABLE:.deployment_variables.crawl4ai_enable"
        "LOAD_PARAMETER_STORE:.deployment_variables.load_parameter_store"
        "PARAM_STORE_PREFIX:.deployment_variables.param_store_prefix"
    )
    
    local applied_count=0
    
    # Process each override mapping
    for mapping in "${override_mappings[@]}"; do
        local env_var="${mapping%%:*}"
        local config_path="${mapping#*:}"
        
        # Check if environment variable is set
        if [[ -n "${!env_var:-}" ]]; then
            log_override "DEBUG" "Applying override: $env_var=${!env_var} -> $config_path"
            
            # Apply override using yq if available
            if command -v yq >/dev/null 2>&1; then
                # Determine value type for proper YAML formatting
                local yaml_value
                case "${!env_var}" in
                    "true"|"false")
                        yaml_value="${!env_var}"
                        ;;
                    *[0-9]*)
                        if [[ "${!env_var}" =~ ^[0-9]+$ ]]; then
                            yaml_value="${!env_var}"  # Integer
                        else
                            yaml_value="\"${!env_var}\""  # String with numbers
                        fi
                        ;;
                    *)
                        yaml_value="\"${!env_var}\""  # String
                        ;;
                esac
                
                yq eval "$config_path = $yaml_value" -i "$config_file" 2>/dev/null || {
                    log_override "WARN" "Failed to apply override: $env_var"
                    continue
                }
                
                ((applied_count++))
                
                # Record applied override
                record_applied_override "$environment" "$env_var" "${!env_var}" "$config_path"
            fi
        fi
    done
    
    log_override "DEBUG" "Applied $applied_count runtime overrides"
}

# Load environment variables from .env files
load_env_file_overrides() {
    local environment="$1"
    local env_files_loaded=0
    
    log_override "DEBUG" "Loading .env file overrides for environment: $environment"
    
    # Define .env files in order of precedence (lowest to highest)
    local env_files=(
        ".env"
        ".env.$environment"
        ".env.local"
    )
    
    # Load each .env file
    for env_file in "${env_files[@]}"; do
        local env_file_path="$PROJECT_ROOT/$env_file"
        
        if [[ -f "$env_file_path" ]]; then
            log_override "DEBUG" "Loading environment file: $env_file"
            
            # Source the file in a subshell to avoid polluting current environment
            (
                set -a  # Export all variables
                source "$env_file_path"
                set +a
                
                # Export variables to parent shell by echoing them
                while IFS='=' read -r var_name var_value; do
                    if [[ -n "$var_name" ]] && [[ "$var_name" != "#"* ]]; then
                        echo "export $var_name='$var_value'"
                    fi
                done < "$env_file_path"
            ) | while read -r export_cmd; do
                eval "$export_cmd" 2>/dev/null || true
            done
            
            ((env_files_loaded++))
        fi
    done
    
    log_override "DEBUG" "Loaded $env_files_loaded .env files"
}

# Load Parameter Store overrides
load_parameter_store_overrides() {
    local environment="$1"
    local param_store_prefix="${2:-/aibuildkit}"
    
    log_override "DEBUG" "Loading Parameter Store overrides for environment: $environment"
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        log_override "WARN" "AWS CLI not available, skipping Parameter Store overrides"
        return 0
    fi
    
    # Check if Parameter Store loading is enabled
    if [[ "${LOAD_PARAMETER_STORE:-false}" != "true" ]]; then
        log_override "DEBUG" "Parameter Store loading disabled"
        return 0
    fi
    
    local params_loaded=0
    
    # Try to load parameters from Parameter Store
    local parameters
    if parameters=$(aws ssm get-parameters-by-path \
        --path "$param_store_prefix" \
        --recursive \
        --with-decryption \
        --query 'Parameters[].{Name:Name,Value:Value}' \
        --output json 2>/dev/null); then
        
        # Process each parameter
        echo "$parameters" | jq -c '.[]?' 2>/dev/null | while read -r param; do
            local param_name=$(echo "$param" | jq -r '.Name')
            local param_value=$(echo "$param" | jq -r '.Value')
            
            # Convert Parameter Store path to environment variable name
            local env_var_name=$(basename "$param_name" | tr '[:lower:]' '[:upper:]')
            
            # Export the parameter as an environment variable
            export "$env_var_name=$param_value"
            
            log_override "DEBUG" "Loaded parameter: $param_name -> $env_var_name"
            ((params_loaded++))
        done
        
        log_override "DEBUG" "Loaded $params_loaded parameters from Parameter Store"
    else
        log_override "WARN" "Failed to load parameters from Parameter Store prefix: $param_store_prefix"
    fi
}

# =============================================================================
# OVERRIDE TRACKING AND HISTORY
# =============================================================================

# Record applied override
record_applied_override() {
    local environment="$1"
    local variable_name="$2"
    local variable_value="$3"
    local config_path="$4"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    mkdir -p "$OVERRIDE_HISTORY_DIR"
    
    local history_file="$OVERRIDE_HISTORY_DIR/override-history-${environment}.json"
    
    # Initialize history file if it doesn't exist
    if [[ ! -f "$history_file" ]]; then
        cat > "$history_file" << 'EOF'
{
  "environment": "",
  "history": []
}
EOF
        update_json_field "$history_file" ".environment" "\"$environment\""
    fi
    
    # Add override record
    local override_record=$(cat << EOF
{
  "timestamp": "$timestamp",
  "variable_name": "$variable_name",
  "variable_value": "$variable_value",
  "config_path": "$config_path",
  "source": "runtime_override"
}
EOF
    )
    
    add_to_json_array "$history_file" ".history" "$override_record"
    
    # Store in memory for quick access
    if [[ "$BASH_4_PLUS" == "true" ]]; then
        APPLIED_OVERRIDES["${environment}_${variable_name}"]="$variable_value"
    else
        local override_var="${APPLIED_OVERRIDES_PREFIX}${environment}_${variable_name}"
        eval "${override_var}='$variable_value'"
    fi
}

# Get override history
get_override_history() {
    local environment="$1"
    local history_file="$OVERRIDE_HISTORY_DIR/override-history-${environment}.json"
    
    if [[ -f "$history_file" ]]; then
        cat "$history_file"
    else
        echo '{"environment": "'$environment'", "history": []}'
    fi
}

# Clear override history
clear_override_history() {
    local environment="$1"
    local history_file="$OVERRIDE_HISTORY_DIR/override-history-${environment}.json"
    
    if [[ -f "$history_file" ]]; then
        rm -f "$history_file"
        log_override "INFO" "Cleared override history for environment: $environment"
    fi
}

# =============================================================================
# OVERRIDE VALIDATION AND CONFLICT DETECTION
# =============================================================================

# Validate environment overrides
validate_environment_overrides() {
    local environment="$1"
    local merged_config="$2"
    local validation_report="$OVERRIDES_CACHE_DIR/override-validation-${environment}.json"
    
    log_override "INFO" "Validating environment overrides for: $environment"
    
    mkdir -p "$OVERRIDES_CACHE_DIR"
    
    # Initialize validation report
    cat > "$validation_report" << EOF
{
  "environment": "$environment",
  "validation_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "override_conflicts": [],
  "invalid_overrides": [],
  "warnings": [],
  "statistics": {
    "total_overrides": 0,
    "conflicts": 0,
    "invalid": 0,
    "warnings": 0
  }
}
EOF
    
    # Check for override conflicts
    detect_override_conflicts "$environment" "$validation_report"
    
    # Validate override values
    validate_override_values "$environment" "$merged_config" "$validation_report"
    
    # Update statistics
    update_validation_statistics "$validation_report"
    
    log_override "INFO" "Override validation completed. Report: $validation_report"
    echo "$validation_report"
}

# Detect override conflicts
detect_override_conflicts() {
    local environment="$1"
    local validation_report="$2"
    
    log_override "DEBUG" "Detecting override conflicts for environment: $environment"
    
    # Check for conflicts between different override sources
    local env_vars_file="$PROJECT_ROOT/.env.$environment"
    local local_env_file="$PROJECT_ROOT/.env.local"
    
    if [[ -f "$env_vars_file" ]] && [[ -f "$local_env_file" ]]; then
        # Find common variables
        local env_vars=$(grep '^[A-Z_][A-Z0-9_]*=' "$env_vars_file" 2>/dev/null | cut -d'=' -f1 || true)
        local local_vars=$(grep '^[A-Z_][A-Z0-9_]*=' "$local_env_file" 2>/dev/null | cut -d'=' -f1 || true)
        
        for var in $env_vars; do
            if echo "$local_vars" | grep -q "^$var$"; then
                local env_value=$(grep "^$var=" "$env_vars_file" | cut -d'=' -f2- | tr -d '"' || echo "")
                local local_value=$(grep "^$var=" "$local_env_file" | cut -d'=' -f2- | tr -d '"' || echo "")
                
                if [[ "$env_value" != "$local_value" ]]; then
                    local conflict_entry=$(cat << EOF
{
  "variable": "$var",
  "environment_value": "$env_value",
  "local_value": "$local_value",
  "resolution": "local_value_takes_precedence",
  "detected_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
                    )
                    
                    add_to_json_array "$validation_report" ".override_conflicts" "$conflict_entry"
                fi
            fi
        done
    fi
}

# Validate override values
validate_override_values() {
    local environment="$1"
    local merged_config="$2"
    local validation_report="$3"
    
    log_override "DEBUG" "Validating override values for environment: $environment"
    
    # Get applied overrides for this environment
    local history_file="$OVERRIDE_HISTORY_DIR/override-history-${environment}.json"
    
    if [[ -f "$history_file" ]]; then
        # Validate each applied override
        jq -c '.history[]?' "$history_file" 2>/dev/null | while read -r override; do
            local var_name=$(echo "$override" | jq -r '.variable_name')
            local var_value=$(echo "$override" | jq -r '.variable_value')
            local config_path=$(echo "$override" | jq -r '.config_path')
            
            # Validate based on variable type and constraints
            validate_single_override "$var_name" "$var_value" "$config_path" "$validation_report"
        done
    fi
}

# Validate single override value
validate_single_override() {
    local var_name="$1"
    local var_value="$2"
    local config_path="$3"
    local validation_report="$4"
    
    # Define validation rules for common variables
    case "$var_name" in
        "AWS_REGION")
            # Validate AWS region format
            if ! [[ "$var_value" =~ ^[a-z]+-[a-z]+-[0-9]+$ ]]; then
                add_invalid_override "$validation_report" "$var_name" "$var_value" \
                    "Invalid AWS region format"
            fi
            ;;
        "INSTANCE_TYPE")
            # Validate instance type format
            if ! [[ "$var_value" =~ ^[a-z][0-9]+[a-z]*\.[a-z0-9]+$ ]]; then
                add_invalid_override "$validation_report" "$var_name" "$var_value" \
                    "Invalid EC2 instance type format"
            fi
            ;;
        "VOLUME_SIZE")
            # Validate volume size is numeric and within range
            if ! [[ "$var_value" =~ ^[0-9]+$ ]] || [[ "$var_value" -lt "20" ]] || [[ "$var_value" -gt "1000" ]]; then
                add_invalid_override "$validation_report" "$var_name" "$var_value" \
                    "Volume size must be numeric between 20-1000 GB"
            fi
            ;;
        "SPOT_PRICE")
            # Validate spot price format and range
            if [[ -n "$var_value" ]] && ! [[ "$var_value" =~ ^[0-9]+\.[0-9]+$ ]]; then
                add_invalid_override "$validation_report" "$var_name" "$var_value" \
                    "Spot price must be in decimal format (e.g., 1.50)"
            fi
            ;;
        "DEBUG"|"DRY_RUN"|"ENABLE_"*)
            # Validate boolean values
            if [[ "$var_value" != "true" ]] && [[ "$var_value" != "false" ]]; then
                add_invalid_override "$validation_report" "$var_name" "$var_value" \
                    "Boolean value must be 'true' or 'false'"
            fi
            ;;
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if environment is supported
is_environment_supported() {
    local environment="$1"
    
    for env in "${SUPPORTED_ENVIRONMENTS[@]}"; do
        if [[ "$environment" == "$env" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Analyze YAML variables count
analyze_yaml_variables() {
    local file="$1"
    
    if command -v yq >/dev/null 2>&1; then
        yq eval 'paths(scalars) as $p | $p | join(".")' "$file" 2>/dev/null | wc -l | tr -d ' '
    else
        grep -c '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:' "$file" 2>/dev/null || echo "0"
    fi
}

# Update JSON field
update_json_field() {
    local file="$1"
    local path="$2"
    local value="$3"
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file="${file}.tmp"
        jq "$path = $value" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Add to JSON array
add_to_json_array() {
    local file="$1"
    local path="$2"
    local element="$3"
    
    if command -v jq >/dev/null 2>&1; then
        local temp_file="${file}.tmp"
        jq "$path += [$element]" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Add invalid override to validation report
add_invalid_override() {
    local validation_report="$1"
    local var_name="$2"
    local var_value="$3"
    local reason="$4"
    
    local invalid_entry=$(cat << EOF
{
  "variable": "$var_name",
  "value": "$var_value",
  "reason": "$reason",
  "detected_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
    )
    
    add_to_json_array "$validation_report" ".invalid_overrides" "$invalid_entry"
}

# Calculate discovery statistics
calculate_discovery_statistics() {
    local discovery_report="$1"
    
    if command -v jq >/dev/null 2>&1; then
        local total_environments=$(jq '.environments | length' "$discovery_report" 2>/dev/null || echo "0")
        local total_yaml_files=$(jq '.files.yaml_configs | length' "$discovery_report" 2>/dev/null || echo "0")
        local total_env_files=$(jq '.files.env_files | length' "$discovery_report" 2>/dev/null || echo "0")
        local total_override_files=$((total_yaml_files + total_env_files))
        local total_variables=$(jq '[.files.yaml_configs[].variable_count, .files.env_files[].variable_count] | add' "$discovery_report" 2>/dev/null || echo "0")
        
        update_json_field "$discovery_report" ".statistics.total_environments" "$total_environments"
        update_json_field "$discovery_report" ".statistics.total_override_files" "$total_override_files"
        update_json_field "$discovery_report" ".statistics.total_variables" "$total_variables"
    fi
}

# Update validation statistics
update_validation_statistics() {
    local validation_report="$1"
    
    if command -v jq >/dev/null 2>&1; then
        local conflicts=$(jq '.override_conflicts | length' "$validation_report" 2>/dev/null || echo "0")
        local invalid=$(jq '.invalid_overrides | length' "$validation_report" 2>/dev/null || echo "0")
        local warnings=$(jq '.warnings | length' "$validation_report" 2>/dev/null || echo "0")
        
        update_json_field "$validation_report" ".statistics.conflicts" "$conflicts"
        update_json_field "$validation_report" ".statistics.invalid" "$invalid"
        update_json_field "$validation_report" ".statistics.warnings" "$warnings"
    fi
}

# =============================================================================
# PUBLIC API FUNCTIONS
# =============================================================================

# Initialize override manager
initialize_override_manager() {
    log_override "INFO" "Initializing Unity Environment Override Manager v$OVERRIDE_MANAGER_VERSION"
    
    # Create necessary directories
    mkdir -p "$ENVIRONMENTS_DIR" "$OVERRIDES_CACHE_DIR" "$OVERRIDE_HISTORY_DIR"
    
    log_override "INFO" "Override manager initialized successfully"
}

# Resolve configuration for environment
resolve_environment_configuration() {
    local environment="${1:-$DEFAULT_ENVIRONMENT}"
    local output_file="${2:-}"
    local enable_caching="${3:-true}"
    
    log_override "INFO" "Resolving configuration for environment: $environment"
    
    # Validate environment
    validate_environment "$environment" || return 1
    
    # Load .env file overrides first
    load_env_file_overrides "$environment"
    
    # Load Parameter Store overrides
    load_parameter_store_overrides "$environment"
    
    # Load base configuration
    local base_config
    base_config=$(load_base_configuration) || return 1
    
    # Load environment-specific configuration
    local env_config
    env_config=$(load_environment_configuration "$environment") || return 1
    
    # Merge configurations
    local merged_config
    merged_config=$(merge_configurations "$base_config" "$env_config" "$environment" "$output_file")
    
    # Validate overrides
    validate_environment_overrides "$environment" "$merged_config"
    
    # Output result if no output file specified
    if [[ -z "$output_file" ]]; then
        echo "$merged_config"
    fi
    
    log_override "INFO" "Configuration resolved successfully for environment: $environment"
}

# Get environment discovery report
get_environment_discovery() {
    discover_environment_configs
}

# Get override validation report
get_override_validation() {
    local environment="$1"
    local validation_file="$OVERRIDES_CACHE_DIR/override-validation-${environment}.json"
    
    if [[ -f "$validation_file" ]]; then
        cat "$validation_file"
    else
        echo '{"environment": "'$environment'", "message": "No validation report available"}'
    fi
}

# Export functions for use in other scripts
export -f initialize_override_manager
export -f resolve_environment_configuration
export -f get_environment_discovery
export -f get_override_validation
export -f validate_environment_overrides
export -f get_override_history
export -f clear_override_history

log_override "DEBUG" "Unity Environment Override Manager loaded successfully"