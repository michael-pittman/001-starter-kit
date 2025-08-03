#!/bin/bash
# =============================================================================
# Unity Plugin Interface Specifications
# Defines plugin contracts, interface specifications, and versioning system
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# =============================================================================
# PLUGIN INTERFACE METADATA
# =============================================================================

readonly UNITY_PLUGIN_INTERFACE_VERSION="1.0.0"
readonly UNITY_PLUGIN_API_VERSION="2.0"
readonly UNITY_PLUGIN_MIN_BASH_VERSION="3.2"

# Supported plugin interface versions (for backward compatibility)
declare -a UNITY_PLUGIN_SUPPORTED_VERSIONS=("1.0" "2.0")

# =============================================================================
# PLUGIN INTERFACE CONSTANTS
# =============================================================================

# Plugin states
readonly PLUGIN_STATE_UNLOADED="unloaded"
readonly PLUGIN_STATE_LOADING="loading"
readonly PLUGIN_STATE_LOADED="loaded"
readonly PLUGIN_STATE_INITIALIZING="initializing"
readonly PLUGIN_STATE_INITIALIZED="initialized"
readonly PLUGIN_STATE_STARTING="starting"
readonly PLUGIN_STATE_ACTIVE="active"
readonly PLUGIN_STATE_STOPPING="stopping"
readonly PLUGIN_STATE_STOPPED="stopped"
readonly PLUGIN_STATE_ERROR="error"
readonly PLUGIN_STATE_DISABLED="disabled"

# Plugin priorities (for loading order)
readonly PLUGIN_PRIORITY_CRITICAL=100
readonly PLUGIN_PRIORITY_HIGH=80
readonly PLUGIN_PRIORITY_NORMAL=50
readonly PLUGIN_PRIORITY_LOW=20
readonly PLUGIN_PRIORITY_BACKGROUND=10

# Plugin types
readonly PLUGIN_TYPE_CORE="core"
readonly PLUGIN_TYPE_INFRASTRUCTURE="infrastructure"
readonly PLUGIN_TYPE_DEPLOYMENT="deployment"
readonly PLUGIN_TYPE_MONITORING="monitoring"
readonly PLUGIN_TYPE_OPTIMIZATION="optimization"
readonly PLUGIN_TYPE_INTEGRATION="integration"
readonly PLUGIN_TYPE_EXTENSION="extension"

# Plugin execution modes
readonly PLUGIN_EXEC_SYNC="sync"
readonly PLUGIN_EXEC_ASYNC="async"
readonly PLUGIN_EXEC_BACKGROUND="background"

# =============================================================================
# PLUGIN INTERFACE SPECIFICATION
# =============================================================================

# Plugin Interface Contract
# Every plugin MUST implement these functions to be considered valid
UNITY_PLUGIN_REQUIRED_FUNCTIONS=(
    "plugin_metadata"
    "plugin_validate"
    "plugin_init"
    "plugin_start"
    "plugin_stop"
    "plugin_cleanup"
)

# Plugin Interface Optional Functions
# Plugins MAY implement these functions for extended functionality
UNITY_PLUGIN_OPTIONAL_FUNCTIONS=(
    "plugin_configure"
    "plugin_health_check"
    "plugin_status"
    "plugin_metrics"
    "plugin_handle_event"
    "plugin_pre_hook"
    "plugin_post_hook"
    "plugin_on_config_change"
    "plugin_on_dependency_ready"
    "plugin_on_system_shutdown"
)

# Extension Point Hooks
# Available extension points throughout the system
UNITY_PLUGIN_EXTENSION_POINTS=(
    "pre_deployment"
    "post_deployment"
    "pre_config_load"
    "post_config_load"
    "pre_service_start"
    "post_service_start"
    "pre_health_check"
    "post_health_check"
    "on_error"
    "on_alert"
    "on_metric_threshold"
    "on_cost_threshold"
    "on_security_violation"
    "on_performance_degradation"
)

# =============================================================================
# PLUGIN METADATA SPECIFICATION
# =============================================================================

# Generate plugin metadata template
# Usage: generate_plugin_metadata_template
generate_plugin_metadata_template() {
    cat <<'METADATA_TEMPLATE'
#!/bin/bash
# Plugin metadata function - REQUIRED
# Must return valid JSON with plugin information
plugin_metadata() {
    cat <<'PLUGIN_METADATA'
{
  "name": "example-plugin",
  "version": "1.0.0",
  "api_version": "2.0",
  "description": "Example plugin demonstrating Unity plugin interface",
  "author": "Plugin Developer",
  "license": "MIT",
  "homepage": "https://github.com/example/plugin",
  "type": "extension",
  "category": "optimization",
  "priority": 50,
  "execution_mode": "sync",
  "bash_compatibility": {
    "min_version": "3.2",
    "tested_versions": ["3.2", "4.0", "4.4", "5.0", "5.1"]
  },
  "dependencies": {
    "required": [],
    "optional": ["aws-cli", "docker"],
    "unity_services": ["config", "events"],
    "system_commands": ["curl", "jq"]
  },
  "capabilities": {
    "extension_points": ["pre_deployment", "post_deployment"],
    "event_handlers": ["deployment.started", "deployment.completed"],
    "configuration_schema": true,
    "metrics_collection": true,
    "health_monitoring": true
  },
  "configuration": {
    "config_file": "config.yml",
    "environment_prefix": "PLUGIN_EXAMPLE",
    "required_config": ["api_key", "endpoint"],
    "optional_config": ["timeout", "retry_count"]
  },
  "resources": {
    "max_memory_mb": 50,
    "max_cpu_percent": 10,
    "max_disk_mb": 100,
    "network_access": true,
    "file_permissions": ["read", "write:tmp"]
  },
  "security": {
    "sandbox_mode": true,
    "allowed_commands": ["curl", "echo", "date"],
    "restricted_paths": ["/etc", "/root"],
    "environment_isolation": true
  }
}
PLUGIN_METADATA
}
METADATA_TEMPLATE
}

# =============================================================================
# PLUGIN VALIDATION INTERFACE
# =============================================================================

# Plugin validation function template
generate_plugin_validation_template() {
    cat <<'VALIDATION_TEMPLATE'
# Plugin validation function - REQUIRED
# Validates plugin environment, dependencies, and prerequisites
# Returns: 0 for success, non-zero for failure
plugin_validate() {
    local errors=0
    local warnings=0
    
    # Validate bash version compatibility
    if ! _validate_bash_version; then
        _plugin_log "ERROR" "Bash version not supported"
        errors=$((errors + 1))
    fi
    
    # Validate required dependencies
    if ! _validate_dependencies; then
        _plugin_log "ERROR" "Required dependencies not available"
        errors=$((errors + 1))
    fi
    
    # Validate configuration
    if ! _validate_configuration; then
        _plugin_log "WARNING" "Configuration validation failed"
        warnings=$((warnings + 1))
    fi
    
    # Validate system resources
    if ! _validate_resources; then
        _plugin_log "WARNING" "Resource constraints may be exceeded"
        warnings=$((warnings + 1))
    fi
    
    # Validate permissions
    if ! _validate_permissions; then
        _plugin_log "ERROR" "Insufficient permissions"
        errors=$((errors + 1))
    fi
    
    # Log validation summary
    _plugin_log "INFO" "Validation completed: $errors errors, $warnings warnings"
    
    return $errors
}

# Helper validation functions
_validate_bash_version() {
    local required_version="3.2"
    local current_version="${BASH_VERSION%%.*}.${BASH_VERSION#*.}"
    current_version="${current_version%%.*}"
    
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" == "$required_version" ]]; then
        return 0
    else
        return 1
    fi
}

_validate_dependencies() {
    local metadata_json
    metadata_json=$(plugin_metadata)
    
    # Extract required dependencies (simplified - would use JSON parser in real implementation)
    local required_deps=()
    # This would be implemented with proper JSON parsing
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            _plugin_log "ERROR" "Required dependency not found: $dep"
            return 1
        fi
    done
    
    return 0
}

_validate_configuration() {
    # Check if required configuration values are present
    local required_config=("API_KEY" "ENDPOINT")
    
    for config in "${required_config[@]}"; do
        local env_var="PLUGIN_EXAMPLE_${config}"
        if [[ -z "${!env_var:-}" ]]; then
            _plugin_log "WARNING" "Required configuration missing: $config"
            return 1
        fi
    done
    
    return 0
}

_validate_resources() {
    # Check available system resources
    local available_memory
    available_memory=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "1000")
    
    if [[ $available_memory -lt 50 ]]; then
        _plugin_log "WARNING" "Low memory available: ${available_memory}MB"
        return 1
    fi
    
    return 0
}

_validate_permissions() {
    # Check required file permissions
    if [[ ! -w "/tmp" ]]; then
        _plugin_log "ERROR" "No write permission to /tmp"
        return 1
    fi
    
    return 0
}
VALIDATION_TEMPLATE
}

# =============================================================================
# PLUGIN LIFECYCLE INTERFACE
# =============================================================================

# Plugin initialization function template
generate_plugin_init_template() {
    cat <<'INIT_TEMPLATE'
# Plugin initialization function - REQUIRED
# Called once when plugin is first loaded
# Should setup plugin state, configuration, and resources
# Returns: 0 for success, non-zero for failure
plugin_init() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    _plugin_log "INFO" "Initializing plugin: $plugin_name"
    
    # Initialize plugin state directory
    local plugin_dir=".unity/plugins/$plugin_name"
    mkdir -p "$plugin_dir/state" "$plugin_dir/logs" "$plugin_dir/cache"
    
    # Load plugin configuration
    if ! _load_plugin_config; then
        _plugin_log "ERROR" "Failed to load plugin configuration"
        return 1
    fi
    
    # Initialize plugin resources
    if ! _init_plugin_resources; then
        _plugin_log "ERROR" "Failed to initialize plugin resources"
        return 1
    fi
    
    # Register with Unity event system
    if ! _register_event_handlers; then
        _plugin_log "WARNING" "Failed to register event handlers"
    fi
    
    # Register extension point hooks
    if ! _register_extension_hooks; then
        _plugin_log "WARNING" "Failed to register extension hooks"
    fi
    
    _plugin_log "SUCCESS" "Plugin initialized successfully"
    return 0
}

# Helper initialization functions
_load_plugin_config() {
    # Load configuration from Unity config system
    local config_key="plugins.example-plugin"
    
    # This would integrate with Unity configuration service
    # For now, just check environment variables
    return 0
}

_init_plugin_resources() {
    # Initialize any required resources (files, connections, etc.)
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    # Create plugin-specific resource files
    touch ".unity/plugins/$plugin_name/state/status.txt"
    echo "initialized" > ".unity/plugins/$plugin_name/state/status.txt"
    
    return 0
}

_register_event_handlers() {
    # Register to handle specific Unity events
    # This would integrate with Unity event bus
    return 0
}

_register_extension_hooks() {
    # Register hooks for extension points
    # This would integrate with Unity extension point system
    return 0
}
INIT_TEMPLATE
}

# Plugin start function template
generate_plugin_start_template() {
    cat <<'START_TEMPLATE'
# Plugin start function - REQUIRED
# Called when plugin should begin active operation
# Returns: 0 for success, non-zero for failure
plugin_start() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    _plugin_log "INFO" "Starting plugin: $plugin_name"
    
    # Check if plugin is initialized
    if ! _is_plugin_initialized; then
        _plugin_log "ERROR" "Plugin not initialized - cannot start"
        return 1
    fi
    
    # Start plugin services/processes
    if ! _start_plugin_services; then
        _plugin_log "ERROR" "Failed to start plugin services"
        return 1
    fi
    
    # Update plugin state
    echo "active" > ".unity/plugins/$plugin_name/state/status.txt"
    echo "$(date '+%s')" > ".unity/plugins/$plugin_name/state/start_time.txt"
    
    _plugin_log "SUCCESS" "Plugin started successfully"
    return 0
}

_is_plugin_initialized() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    local status_file=".unity/plugins/$plugin_name/state/status.txt"
    
    [[ -f "$status_file" ]] && [[ "$(cat "$status_file")" == "initialized" ]]
}

_start_plugin_services() {
    # Start any background services or processes
    # This is plugin-specific implementation
    return 0
}
START_TEMPLATE
}

# Plugin stop function template
generate_plugin_stop_template() {
    cat <<'STOP_TEMPLATE'
# Plugin stop function - REQUIRED
# Called when plugin should stop active operation
# Returns: 0 for success, non-zero for failure
plugin_stop() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    _plugin_log "INFO" "Stopping plugin: $plugin_name"
    
    # Stop plugin services gracefully
    if ! _stop_plugin_services; then
        _plugin_log "WARNING" "Failed to stop plugin services gracefully"
    fi
    
    # Save plugin state
    if ! _save_plugin_state; then
        _plugin_log "WARNING" "Failed to save plugin state"
    fi
    
    # Update plugin status
    echo "stopped" > ".unity/plugins/$plugin_name/state/status.txt"
    echo "$(date '+%s')" > ".unity/plugins/$plugin_name/state/stop_time.txt"
    
    _plugin_log "SUCCESS" "Plugin stopped successfully"
    return 0
}

_stop_plugin_services() {
    # Stop any running services or processes
    # This is plugin-specific implementation
    return 0
}

_save_plugin_state() {
    # Save any important state information
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    # Save configuration, metrics, or other state data
    return 0
}
START_TEMPLATE
}

# Plugin cleanup function template
generate_plugin_cleanup_template() {
    cat <<'CLEANUP_TEMPLATE'
# Plugin cleanup function - REQUIRED
# Called when plugin is being completely removed/unloaded
# Should cleanup all resources, files, and registrations
# Returns: 0 for success, non-zero for failure
plugin_cleanup() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    _plugin_log "INFO" "Cleaning up plugin: $plugin_name"
    
    # Ensure plugin is stopped first
    if _is_plugin_active; then
        plugin_stop
    fi
    
    # Cleanup temporary resources
    if ! _cleanup_temp_resources; then
        _plugin_log "WARNING" "Failed to cleanup temporary resources"
    fi
    
    # Unregister from Unity systems
    if ! _unregister_from_unity; then
        _plugin_log "WARNING" "Failed to unregister from Unity systems"
    fi
    
    # Remove plugin state (optional - may want to preserve for debugging)
    local cleanup_state="${PLUGIN_CLEANUP_STATE:-false}"
    if [[ "$cleanup_state" == "true" ]]; then
        rm -rf ".unity/plugins/$plugin_name"
    fi
    
    _plugin_log "SUCCESS" "Plugin cleanup completed"
    return 0
}

_is_plugin_active() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    local status_file=".unity/plugins/$plugin_name/state/status.txt"
    
    [[ -f "$status_file" ]] && [[ "$(cat "$status_file")" == "active" ]]
}

_cleanup_temp_resources() {
    # Cleanup temporary files, connections, processes
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    # Remove temporary files
    rm -f "/tmp/${plugin_name}_"*
    
    return 0
}

_unregister_from_unity() {
    # Unregister event handlers and extension hooks
    # This would integrate with Unity systems
    return 0
}
CLEANUP_TEMPLATE
}

# =============================================================================
# PLUGIN OPTIONAL INTERFACE FUNCTIONS
# =============================================================================

# Plugin configuration function template
generate_plugin_configure_template() {
    cat <<'CONFIGURE_TEMPLATE'
# Plugin configuration function - OPTIONAL
# Called when plugin configuration needs to be updated
# Parameters: config updates as key=value pairs
# Returns: 0 for success, non-zero for failure
plugin_configure() {
    local config_updates=("$@")
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    _plugin_log "INFO" "Configuring plugin: $plugin_name"
    
    # Process configuration updates
    for update in "${config_updates[@]}"; do
        if [[ "$update" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            if ! _update_config_value "$key" "$value"; then
                _plugin_log "ERROR" "Failed to update configuration: $key=$value"
                return 1
            fi
        fi
    done
    
    # Validate new configuration
    if ! _validate_configuration; then
        _plugin_log "ERROR" "Configuration validation failed"
        return 1
    fi
    
    # Apply configuration changes
    if ! _apply_config_changes; then
        _plugin_log "ERROR" "Failed to apply configuration changes"
        return 1
    fi
    
    _plugin_log "SUCCESS" "Plugin configuration updated"
    return 0
}

_update_config_value() {
    local key="$1"
    local value="$2"
    
    # Update configuration value in plugin state
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    local config_file=".unity/plugins/$plugin_name/state/config.txt"
    
    # Simple key=value storage (would be more sophisticated in real implementation)
    echo "$key=$value" >> "$config_file"
    
    return 0
}

_apply_config_changes() {
    # Apply configuration changes to running plugin
    # May require restart of certain components
    return 0
}
CONFIGURE_TEMPLATE
}

# Plugin health check function template
generate_plugin_health_check_template() {
    cat <<'HEALTH_CHECK_TEMPLATE'
# Plugin health check function - OPTIONAL
# Returns plugin health status and metrics
# Returns: 0 for healthy, 1 for degraded, 2 for unhealthy
plugin_health_check() {
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    local health_status=0
    local health_details=()
    
    # Check if plugin is running
    if ! _is_plugin_active; then
        health_details+=("Plugin is not active")
        health_status=2
    fi
    
    # Check resource usage
    if ! _check_resource_usage; then
        health_details+=("High resource usage detected")
        health_status=1
    fi
    
    # Check dependencies
    if ! _check_dependencies_health; then
        health_details+=("Dependency health issues")
        health_status=1
    fi
    
    # Check plugin-specific health indicators
    if ! _check_plugin_specific_health; then
        health_details+=("Plugin-specific health check failed")
        health_status=1
    fi
    
    # Output health status
    local status_text
    case $health_status in
        0) status_text="healthy" ;;
        1) status_text="degraded" ;;
        2) status_text="unhealthy" ;;
    esac
    
    # Generate health report (would be JSON in real implementation)
    cat <<EOF
{
  "plugin": "$plugin_name",
  "status": "$status_text",
  "timestamp": $(date '+%s'),
  "details": [$(IFS=,; echo "${health_details[*]/#/\"}" | sed 's/,/", "/g')]
}
EOF
    
    return $health_status
}

_check_resource_usage() {
    # Check memory, CPU, disk usage
    return 0
}

_check_dependencies_health() {
    # Check if dependencies are available and healthy
    return 0
}

_check_plugin_specific_health() {
    # Plugin-specific health checks
    return 0
}
HEALTH_CHECK_TEMPLATE
}

# =============================================================================
# PLUGIN EVENT HANDLING INTERFACE
# =============================================================================

# Plugin event handler function template
generate_plugin_event_handler_template() {
    cat <<'EVENT_HANDLER_TEMPLATE'
# Plugin event handler function - OPTIONAL
# Called when Unity events that plugin is registered for occur
# Parameters: event_type event_data
# Returns: 0 for success, non-zero for failure
plugin_handle_event() {
    local event_type="$1"
    local event_data="$2"
    local plugin_name
    plugin_name=$(plugin_metadata | grep '"name"' | cut -d'"' -f4)
    
    _plugin_log "INFO" "Handling event: $event_type"
    
    # Route event to appropriate handler
    case "$event_type" in
        "deployment.started")
            _handle_deployment_started "$event_data"
            ;;
        "deployment.completed")
            _handle_deployment_completed "$event_data"
            ;;
        "deployment.failed")
            _handle_deployment_failed "$event_data"
            ;;
        "aws.resource.created")
            _handle_aws_resource_created "$event_data"
            ;;
        "config.updated")
            _handle_config_updated "$event_data"
            ;;
        "monitor.alert.triggered")
            _handle_alert_triggered "$event_data"
            ;;
        *)
            _plugin_log "WARNING" "Unhandled event type: $event_type"
            return 1
            ;;
    esac
    
    return 0
}

# Event-specific handlers
_handle_deployment_started() {
    local event_data="$1"
    # Handle deployment started event
    _plugin_log "INFO" "Deployment started event received"
    return 0
}

_handle_deployment_completed() {
    local event_data="$1"
    # Handle deployment completed event
    _plugin_log "INFO" "Deployment completed event received"
    return 0
}

_handle_deployment_failed() {
    local event_data="$1"
    # Handle deployment failed event
    _plugin_log "INFO" "Deployment failed event received"
    return 0
}

_handle_aws_resource_created() {
    local event_data="$1"
    # Handle AWS resource created event
    _plugin_log "INFO" "AWS resource created event received"
    return 0
}

_handle_config_updated() {
    local event_data="$1"
    # Handle configuration updated event
    _plugin_log "INFO" "Configuration updated event received"
    return 0
}

_handle_alert_triggered() {
    local event_data="$1"
    # Handle alert triggered event
    _plugin_log "INFO" "Alert triggered event received"
    return 0
}
EVENT_HANDLER_TEMPLATE
}

# =============================================================================
# PLUGIN EXTENSION POINT HOOKS
# =============================================================================

# Plugin extension hook templates
generate_plugin_hook_templates() {
    cat <<'HOOK_TEMPLATES'
# Plugin pre-hook function - OPTIONAL
# Called before specified operations at extension points
# Parameters: hook_point context_data
# Returns: 0 to continue, non-zero to abort operation
plugin_pre_hook() {
    local hook_point="$1"
    local context_data="$2"
    
    case "$hook_point" in
        "pre_deployment")
            _pre_deployment_hook "$context_data"
            ;;
        "pre_config_load")
            _pre_config_load_hook "$context_data"
            ;;
        "pre_service_start")
            _pre_service_start_hook "$context_data"
            ;;
        "pre_health_check")
            _pre_health_check_hook "$context_data"
            ;;
        *)
            return 0  # Unknown hook point - continue
            ;;
    esac
}

# Plugin post-hook function - OPTIONAL
# Called after specified operations at extension points
# Parameters: hook_point context_data result
# Returns: 0 for success, non-zero for failure
plugin_post_hook() {
    local hook_point="$1"
    local context_data="$2"
    local result="$3"
    
    case "$hook_point" in
        "post_deployment")
            _post_deployment_hook "$context_data" "$result"
            ;;
        "post_config_load")
            _post_config_load_hook "$context_data" "$result"
            ;;
        "post_service_start")
            _post_service_start_hook "$context_data" "$result"
            ;;
        "post_health_check")
            _post_health_check_hook "$context_data" "$result"
            ;;
        *)
            return 0  # Unknown hook point - continue
            ;;
    esac
}

# Hook implementations
_pre_deployment_hook() {
    local context_data="$1"
    _plugin_log "INFO" "Pre-deployment hook called"
    # Implement pre-deployment logic
    return 0
}

_post_deployment_hook() {
    local context_data="$1"
    local result="$2"
    _plugin_log "INFO" "Post-deployment hook called with result: $result"
    # Implement post-deployment logic
    return 0
}

_pre_config_load_hook() {
    local context_data="$1"
    _plugin_log "INFO" "Pre-config-load hook called"
    # Implement pre-config-load logic
    return 0
}

_post_config_load_hook() {
    local context_data="$1"
    local result="$2"
    _plugin_log "INFO" "Post-config-load hook called"
    # Implement post-config-load logic
    return 0
}

_pre_service_start_hook() {
    local context_data="$1"
    _plugin_log "INFO" "Pre-service-start hook called"
    # Implement pre-service-start logic
    return 0
}

_post_service_start_hook() {
    local context_data="$1"
    local result="$2"
    _plugin_log "INFO" "Post-service-start hook called"
    # Implement post-service-start logic
    return 0
}

_pre_health_check_hook() {
    local context_data="$1"
    _plugin_log "INFO" "Pre-health-check hook called"
    # Implement pre-health-check logic
    return 0
}

_post_health_check_hook() {
    local context_data="$1"
    local result="$2"
    _plugin_log "INFO" "Post-health-check hook called"
    # Implement post-health-check logic
    return 0
}
HOOK_TEMPLATES
}

# =============================================================================
# PLUGIN UTILITY FUNCTIONS
# =============================================================================

# Plugin logging function
generate_plugin_logging_template() {
    cat <<'LOGGING_TEMPLATE'
# Plugin logging utility function
# Usage: _plugin_log LEVEL MESSAGE [extra_data]
_plugin_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local plugin_name
    plugin_name=$(plugin_metadata 2>/dev/null | grep '"name"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Format log message
    local log_entry="$timestamp [$level] [$plugin_name] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to plugin log file
    local log_dir=".unity/plugins/$plugin_name/logs"
    mkdir -p "$log_dir"
    echo "$log_entry" >> "$log_dir/plugin.log"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "Plugin[$plugin_name]: $message"
    else
        # Fallback to stderr
        case "$level" in
            "ERROR"|"CRITICAL")
                echo "$log_entry" >&2
                ;;
            "SUCCESS")
                echo "$log_entry"
                ;;
            "INFO"|"WARNING"|"DEBUG")
                if [[ "${UNITY_PLUGIN_VERBOSE:-false}" == "true" ]]; then
                    echo "$log_entry"
                fi
                ;;
        esac
    fi
}
LOGGING_TEMPLATE
}

# =============================================================================
# PLUGIN INTERFACE VALIDATION
# =============================================================================

# Validate plugin interface compliance
# Usage: validate_plugin_interface plugin_file
validate_plugin_interface() {
    local plugin_file="$1"
    local errors=0
    local warnings=0
    
    if [[ ! -f "$plugin_file" ]]; then
        echo "ERROR: Plugin file not found: $plugin_file"
        return 1
    fi
    
    echo "Validating plugin interface: $plugin_file"
    
    # Check if plugin is executable
    if [[ ! -x "$plugin_file" ]]; then
        echo "WARNING: Plugin file is not executable"
        warnings=$((warnings + 1))
    fi
    
    # Source the plugin file to check functions
    if ! source "$plugin_file" 2>/dev/null; then
        echo "ERROR: Plugin file has syntax errors"
        return 1
    fi
    
    # Check required functions
    for func in "${UNITY_PLUGIN_REQUIRED_FUNCTIONS[@]}"; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            echo "ERROR: Required function missing: $func"
            errors=$((errors + 1))
        fi
    done
    
    # Test plugin metadata function
    if declare -f plugin_metadata >/dev/null 2>&1; then
        local metadata
        if ! metadata=$(plugin_metadata 2>/dev/null); then
            echo "ERROR: plugin_metadata function failed"
            errors=$((errors + 1))
        else
            # Basic JSON validation (simplified)
            if [[ ! "$metadata" =~ ^\{.*\}$ ]]; then
                echo "ERROR: plugin_metadata must return valid JSON"
                errors=$((errors + 1))
            fi
            
            # Check required metadata fields
            local required_fields=("name" "version" "api_version" "type")
            for field in "${required_fields[@]}"; do
                if [[ ! "$metadata" =~ \"$field\": ]]; then
                    echo "ERROR: Required metadata field missing: $field"
                    errors=$((errors + 1))
                fi
            done
        fi
    fi
    
    # Test plugin validation function
    if declare -f plugin_validate >/dev/null 2>&1; then
        if ! plugin_validate >/dev/null 2>&1; then
            echo "WARNING: Plugin validation failed"
            warnings=$((warnings + 1))
        fi
    fi
    
    # Check optional functions
    local optional_count=0
    for func in "${UNITY_PLUGIN_OPTIONAL_FUNCTIONS[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            optional_count=$((optional_count + 1))
        fi
    done
    
    echo "Interface validation completed:"
    echo "  Required functions: $((${#UNITY_PLUGIN_REQUIRED_FUNCTIONS[@]} - errors)) / ${#UNITY_PLUGIN_REQUIRED_FUNCTIONS[@]}"
    echo "  Optional functions: $optional_count / ${#UNITY_PLUGIN_OPTIONAL_FUNCTIONS[@]}"
    echo "  Errors: $errors"
    echo "  Warnings: $warnings"
    
    return $errors
}

# =============================================================================
# PLUGIN INTERFACE UTILITIES
# =============================================================================

# Get plugin interface version
get_plugin_interface_version() {
    echo "$UNITY_PLUGIN_INTERFACE_VERSION"
}

# Check if plugin API version is supported
is_plugin_api_version_supported() {
    local api_version="$1"
    
    for supported_version in "${UNITY_PLUGIN_SUPPORTED_VERSIONS[@]}"; do
        if [[ "$api_version" == "$supported_version" ]]; then
            return 0
        fi
    done
    
    return 1
}

# List available extension points
list_extension_points() {
    echo "Available extension points:"
    for point in "${UNITY_PLUGIN_EXTENSION_POINTS[@]}"; do
        echo "  - $point"
    done
}

# Generate complete plugin template
generate_complete_plugin_template() {
    local plugin_name="${1:-example-plugin}"
    
    cat <<EOF
#!/bin/bash
# Unity Plugin: $plugin_name
# Generated by Unity Plugin Framework v$UNITY_PLUGIN_INTERFACE_VERSION

set -euo pipefail

# =============================================================================
# PLUGIN METADATA
# =============================================================================

$(generate_plugin_metadata_template)

# =============================================================================
# PLUGIN VALIDATION
# =============================================================================

$(generate_plugin_validation_template)

# =============================================================================
# PLUGIN LIFECYCLE FUNCTIONS
# =============================================================================

$(generate_plugin_init_template)

$(generate_plugin_start_template)

$(generate_plugin_stop_template)

$(generate_plugin_cleanup_template)

# =============================================================================
# PLUGIN OPTIONAL FUNCTIONS
# =============================================================================

$(generate_plugin_configure_template)

$(generate_plugin_health_check_template)

# =============================================================================
# PLUGIN EVENT HANDLING
# =============================================================================

$(generate_plugin_event_handler_template)

# =============================================================================
# PLUGIN EXTENSION HOOKS
# =============================================================================

$(generate_plugin_hook_templates)

# =============================================================================
# PLUGIN UTILITIES
# =============================================================================

$(generate_plugin_logging_template)

# =============================================================================
# PLUGIN IMPLEMENTATION
# =============================================================================

# Add your plugin-specific implementation here

EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all interface functions
export -f generate_plugin_metadata_template
export -f generate_plugin_validation_template
export -f generate_plugin_init_template
export -f generate_plugin_start_template
export -f generate_plugin_stop_template
export -f generate_plugin_cleanup_template
export -f generate_plugin_configure_template
export -f generate_plugin_health_check_template
export -f generate_plugin_event_handler_template
export -f generate_plugin_hook_templates
export -f generate_plugin_logging_template
export -f validate_plugin_interface
export -f get_plugin_interface_version
export -f is_plugin_api_version_supported
export -f list_extension_points
export -f generate_complete_plugin_template

# =============================================================================
# INITIALIZATION
# =============================================================================

# If sourced directly, show interface information
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Plugin Interface Specification v$UNITY_PLUGIN_INTERFACE_VERSION"
    echo "API Version: $UNITY_PLUGIN_API_VERSION"
    echo "Minimum Bash Version: $UNITY_PLUGIN_MIN_BASH_VERSION"
    echo ""
    echo "Required Functions: ${#UNITY_PLUGIN_REQUIRED_FUNCTIONS[@]}"
    echo "Optional Functions: ${#UNITY_PLUGIN_OPTIONAL_FUNCTIONS[@]}"
    echo "Extension Points: ${#UNITY_PLUGIN_EXTENSION_POINTS[@]}"
    echo ""
    echo "Use generate_complete_plugin_template to create a new plugin"
fi