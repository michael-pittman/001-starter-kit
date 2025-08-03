#!/bin/bash
# Unity Config Service - Unified configuration management

# Service metadata
SERVICE_NAME="config"
SERVICE_VERSION="1.0.0"
SERVICE_DESCRIPTION="Unified configuration management and validation"

# Config service state
CONFIG_SERVICE_INITIALIZED=false
CONFIG_SOURCES=()
CONFIG_CACHE_DIR=".unity/cache/config"
declare -A CONFIG_VALUES 2>/dev/null || CONFIG_VALUES=()

# Initialize Config service
init_config_service() {
    unity_log "INFO" "Initializing Config service..."
    
    # Create cache directory
    mkdir -p "$CONFIG_CACHE_DIR"
    
    # Set default configuration sources
    CONFIG_SOURCES=(
        "config/defaults.yml"
        "config/unity.yml"
        ".env.local"
        "AWS_PARAMETER_STORE"
    )
    
    # Load configurations
    load_all_configurations || {
        unity_log "ERROR" "Failed to load configurations"
        return $UNITY_ERROR_EXECUTION
    }
    
    CONFIG_SERVICE_INITIALIZED=true
    unity_log "INFO" "Config service initialized successfully"
    return $UNITY_SUCCESS
}

# Start Config service
start_config_service() {
    if [[ "$CONFIG_SERVICE_INITIALIZED" != "true" ]]; then
        unity_log "ERROR" "Config service not initialized"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    unity_log "INFO" "Starting Config service..."
    
    # Start configuration file monitoring
    monitor_config_changes &
    
    unity_emit_event "SERVICE_STARTED" "config" ""
    return $UNITY_SUCCESS
}

# Stop Config service
stop_config_service() {
    unity_log "INFO" "Stopping Config service..."
    
    # Stop background processes
    pkill -f "monitor_config_changes" 2>/dev/null || true
    
    unity_emit_event "SERVICE_STOPPED" "config" ""
    return $UNITY_SUCCESS
}

# Check Config service health
health_config_service() {
    local health_status="healthy"
    local health_details=""
    
    # Check configuration sources
    for source in "${CONFIG_SOURCES[@]}"; do
        if [[ "$source" != "AWS_PARAMETER_STORE" && ! -f "$source" ]]; then
            if [[ "$source" == "config/defaults.yml" || "$source" == "config/unity.yml" ]]; then
                health_status="unhealthy"
                health_details="${health_details}; Missing required config: $source"
            fi
        fi
    done
    
    # Check if we have any configuration loaded
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        if [[ ${#CONFIG_VALUES[@]} -eq 0 ]]; then
            health_status="unhealthy"
            health_details="${health_details}; No configuration loaded"
        fi
    fi
    
    echo "$health_status|$health_details"
    
    if [[ "$health_status" == "unhealthy" ]]; then
        unity_emit_event "SERVICE_UNHEALTHY" "config" "$health_details"
        return $UNITY_ERROR_EXECUTION
    fi
    
    return $UNITY_SUCCESS
}

# Configure Config service
config_config_service() {
    local action="${1:-get}"
    local key="$2"
    local value="$3"
    
    case "$action" in
        get)
            if [[ -z "$key" ]]; then
                # Return all configuration sources
                echo "sources=${CONFIG_SOURCES[*]}"
                echo "cache_dir=$CONFIG_CACHE_DIR"
            else
                # Get specific configuration value
                get_config_value "$key"
            fi
            ;;
            
        set)
            if [[ -z "$key" || -z "$value" ]]; then
                unity_log "ERROR" "Configuration key and value required"
                return $UNITY_ERROR_VALIDATION
            fi
            
            # Set configuration value
            set_config_value "$key" "$value"
            
            unity_emit_event "CONFIG_UPDATED" "config" "$key=$value"
            ;;
            
        reload)
            # Reload all configurations
            unity_log "INFO" "Reloading configurations..."
            load_all_configurations
            unity_emit_event "CONFIG_RELOADED" "config" ""
            ;;
            
        *)
            unity_log "ERROR" "Unknown action: $action"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# Config-specific functions

# Load all configurations
load_all_configurations() {
    unity_log "INFO" "Loading configurations from all sources..."
    
    # Clear existing values
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        CONFIG_VALUES=()
    else
        # Bash 3.x: Clear all CONFIG_ variables
        for var in $(compgen -v | grep "^CONFIG_VALUE_"); do
            unset "$var"
        done
    fi
    
    # Load from each source in order
    for source in "${CONFIG_SOURCES[@]}"; do
        case "$source" in
            *.yml|*.yaml)
                load_yaml_config "$source"
                ;;
            .env*)
                load_env_config "$source"
                ;;
            AWS_PARAMETER_STORE)
                load_parameter_store_config
                ;;
            *)
                unity_log "WARN" "Unknown config source type: $source"
                ;;
        esac
    done
    
    unity_log "INFO" "Configuration loading complete"
    return $UNITY_SUCCESS
}

# Load YAML configuration
load_yaml_config() {
    local yaml_file="$1"
    
    if [[ ! -f "$yaml_file" ]]; then
        unity_log "DEBUG" "YAML file not found: $yaml_file"
        return 0
    fi
    
    unity_log "INFO" "Loading YAML configuration: $yaml_file"
    
    # Check for yq command
    if command -v yq >/dev/null 2>&1; then
        # Use yq to parse YAML
        while IFS='=' read -r key value; do
            set_config_value "$key" "$value"
        done < <(yq eval '.. | select(. == "*") | {(path | join(".")): .} | to_entries | .[] | .key + "=" + .value' "$yaml_file" 2>/dev/null || true)
    else
        # Fallback: basic parsing for simple key-value pairs
        unity_log "WARN" "yq not found, using basic YAML parsing"
        while IFS=': ' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Trim whitespace
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [[ -n "$key" && -n "$value" ]]; then
                set_config_value "$key" "$value"
            fi
        done < "$yaml_file"
    fi
    
    return $UNITY_SUCCESS
}

# Load environment file configuration
load_env_config() {
    local env_file="$1"
    
    if [[ ! -f "$env_file" ]]; then
        unity_log "DEBUG" "Environment file not found: $env_file"
        return 0
    fi
    
    unity_log "INFO" "Loading environment configuration: $env_file"
    
    # Parse environment file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove quotes from value
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        
        # Export to environment and store
        export "$key=$value"
        set_config_value "$key" "$value"
    done < "$env_file"
    
    return $UNITY_SUCCESS
}

# Load AWS Parameter Store configuration
load_parameter_store_config() {
    if ! command -v aws >/dev/null 2>&1; then
        unity_log "DEBUG" "AWS CLI not available, skipping Parameter Store"
        return 0
    fi
    
    unity_log "INFO" "Loading configuration from AWS Parameter Store..."
    
    local prefix="/aibuildkit/"
    
    # Get parameters by path
    local parameters
    parameters=$(aws ssm get-parameters-by-path \
        --path "$prefix" \
        --recursive \
        --with-decryption \
        --query 'Parameters[*].[Name,Value]' \
        --output text 2>/dev/null) || {
        unity_log "WARN" "Failed to load from Parameter Store"
        return 0
    }
    
    # Parse and store parameters
    while IFS=$'\t' read -r name value; do
        # Remove prefix from name
        local key="${name#$prefix}"
        key="${key//\//_}"  # Replace / with _
        
        set_config_value "$key" "$value"
    done <<< "$parameters"
    
    return $UNITY_SUCCESS
}

# Get configuration value
get_config_value() {
    local key="$1"
    local default="${2:-}"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        echo "${CONFIG_VALUES[$key]:-$default}"
    else
        local var_name="CONFIG_VALUE_${key//[^a-zA-Z0-9_]/_}"
        echo "${!var_name:-$default}"
    fi
}

# Set configuration value
set_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        CONFIG_VALUES["$key"]="$value"
    else
        local var_name="CONFIG_VALUE_${key//[^a-zA-Z0-9_]/_}"
        eval "$var_name='$value'"
    fi
    
    unity_log "DEBUG" "Set config: $key = $value"
}

# Validate configuration
validate_config() {
    local validation_errors=0
    
    unity_log "INFO" "Validating configuration..."
    
    # Check required configurations
    local required_keys=(
        "unity.version"
        "unity.deployment.default_environment"
        "AWS_REGION"
        "STACK_NAME"
    )
    
    for key in "${required_keys[@]}"; do
        local value=$(get_config_value "$key")
        if [[ -z "$value" ]]; then
            unity_log "ERROR" "Missing required configuration: $key"
            ((validation_errors++))
        fi
    done
    
    if [[ $validation_errors -gt 0 ]]; then
        unity_log "ERROR" "Configuration validation failed with $validation_errors errors"
        return $UNITY_ERROR_VALIDATION
    fi
    
    unity_log "INFO" "Configuration validation successful"
    return $UNITY_SUCCESS
}

# Monitor configuration changes
monitor_config_changes() {
    local check_interval=60
    
    while true; do
        unity_log "DEBUG" "Checking for configuration changes..."
        
        # Check file modification times
        for source in "${CONFIG_SOURCES[@]}"; do
            if [[ -f "$source" ]]; then
                local cache_file="$CONFIG_CACHE_DIR/$(basename "$source").mtime"
                local current_mtime=$(stat -f %m "$source" 2>/dev/null || stat -c %Y "$source" 2>/dev/null || echo 0)
                
                if [[ -f "$cache_file" ]]; then
                    local cached_mtime=$(cat "$cache_file")
                    if [[ "$current_mtime" != "$cached_mtime" ]]; then
                        unity_log "INFO" "Configuration changed: $source"
                        unity_emit_event "CONFIG_CHANGED" "config" "$source"
                        
                        # Reload configuration
                        load_all_configurations
                    fi
                fi
                
                echo "$current_mtime" > "$cache_file"
            fi
        done
        
        sleep "$check_interval"
    done
}

# Export service functions
export -f init_config_service
export -f start_config_service
export -f stop_config_service
export -f health_config_service
export -f config_config_service
export -f load_all_configurations
export -f load_yaml_config
export -f load_env_config
export -f load_parameter_store_config
export -f get_config_value
export -f set_config_value
export -f validate_config
export -f monitor_config_changes