#!/bin/bash
# =============================================================================
# Unity Plugin Framework
# Main plugin framework that orchestrates all plugin system components
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# =============================================================================
# UNITY PLUGIN FRAMEWORK METADATA
# =============================================================================

readonly UNITY_PLUGIN_FRAMEWORK_VERSION="1.0.0"
readonly PLUGIN_FRAMEWORK_API_VERSION="2.0"
readonly PLUGIN_FRAMEWORK_INITIALIZED_FLAG=".unity/state/plugin-framework-initialized"

# =============================================================================
# LOAD PLUGIN FRAMEWORK COMPONENTS
# =============================================================================

# Load required libraries in dependency order
_load_plugin_dependencies() {
    local verbose="${1:-false}"
    
    # Load core Unity libraries first
    local core_libs=(
        "$PROJECT_ROOT/lib/associative-arrays.sh"
        "$PROJECT_ROOT/lib/utils/library-loader.sh"
    )
    
    for lib in "${core_libs[@]}"; do
        if [[ -f "$lib" ]]; then
            if [[ "$verbose" == "true" ]]; then
                echo "Loading core library: $(basename "$lib")"
            fi
            source "$lib"
        else
            echo "ERROR: Required library not found: $lib" >&2
            return 1
        fi
    done
    
    # Load plugin framework components
    local plugin_components=(
        "$SCRIPT_DIR/plugin-interface.sh"
        "$SCRIPT_DIR/plugin-loader.sh"
        "$SCRIPT_DIR/plugin-lifecycle.sh"
        "$SCRIPT_DIR/plugin-validator.sh"
    )
    
    for component in "${plugin_components[@]}"; do
        if [[ -f "$component" ]]; then
            if [[ "$verbose" == "true" ]]; then
                echo "Loading plugin component: $(basename "$component")"
            fi
            source "$component"
        else
            echo "ERROR: Plugin framework component not found: $component" >&2
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# PLUGIN FRAMEWORK INITIALIZATION
# =============================================================================

# Initialize the complete plugin framework
# Usage: init_unity_plugin_framework [verbose] [validation_level]
init_unity_plugin_framework() {
    local verbose="${1:-false}"
    local validation_level="${2:-standard}"
    
    if [[ "$verbose" == "true" ]]; then
        echo "Initializing Unity Plugin Framework v$UNITY_PLUGIN_FRAMEWORK_VERSION"
    fi
    
    # Check if already initialized
    if [[ -f "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG" ]]; then
        if [[ "$verbose" == "true" ]]; then
            echo "Plugin framework already initialized"
        fi
        return 0
    fi
    
    # Create required directories
    mkdir -p "$(dirname "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG")"
    mkdir -p ".unity/plugins" ".unity/state/plugins" ".unity/logs" ".unity/events"
    
    # Load plugin framework dependencies
    if ! _load_plugin_dependencies "$verbose"; then
        echo "ERROR: Failed to load plugin framework dependencies" >&2
        return 1
    fi
    
    # Initialize plugin framework components
    local init_functions=(
        "init_plugin_registry"
        "init_plugin_lifecycle"
        "init_plugin_validator"
    )
    
    for init_func in "${init_functions[@]}"; do
        if declare -f "$init_func" >/dev/null 2>&1; then
            if [[ "$verbose" == "true" ]]; then
                echo "Initializing: $init_func"
            fi
            
            if ! "$init_func" "$verbose"; then
                echo "ERROR: Failed to initialize $init_func" >&2
                return 1
            fi
        else
            echo "WARNING: Initialization function not found: $init_func" >&2
        fi
    done
    
    # Create framework initialization marker
    cat > "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG" <<EOF
{
  "framework_version": "$UNITY_PLUGIN_FRAMEWORK_VERSION",
  "api_version": "$PLUGIN_FRAMEWORK_API_VERSION",
  "initialized_timestamp": $(date '+%s'),
  "validation_level": "$validation_level",
  "components": [
    "plugin-interface",
    "plugin-loader", 
    "plugin-lifecycle",
    "plugin-validator"
  ]
}
EOF
    
    # Initialize extension point system
    _init_extension_points "$verbose"
    
    if [[ "$verbose" == "true" ]]; then
        echo "Unity Plugin Framework initialized successfully"
    fi
    
    # Emit framework initialized event
    _emit_framework_event "framework.initialized" "{\"version\": \"$UNITY_PLUGIN_FRAMEWORK_VERSION\"}"
    
    return 0
}

# =============================================================================
# EXTENSION POINT SYSTEM
# =============================================================================

# Initialize extension point system
# Usage: _init_extension_points [verbose]
_init_extension_points() {
    local verbose="${1:-false}"
    
    # Initialize extension point registry
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        kv_clear "extension_points"
        kv_clear "extension_handlers"
    else
        declare -gA extension_points=()
        declare -gA extension_handlers=()
    fi
    
    # Register core extension points
    local core_extension_points=(
        "pre_deployment:Before deployment operations start"
        "post_deployment:After deployment operations complete"
        "pre_config_load:Before configuration is loaded"
        "post_config_load:After configuration is loaded"
        "pre_service_start:Before a service starts"
        "post_service_start:After a service starts"
        "pre_health_check:Before health check is performed"
        "post_health_check:After health check is performed"
        "on_error:When an error occurs"
        "on_alert:When an alert is triggered"
        "on_metric_threshold:When a metric threshold is exceeded"
        "on_cost_threshold:When a cost threshold is exceeded"
        "on_security_violation:When a security violation is detected"
        "on_performance_degradation:When performance degradation is detected"
    )
    
    for point_info in "${core_extension_points[@]}"; do
        local point_name="${point_info%:*}"
        local point_description="${point_info#*:}"
        
        aa_set "extension_points" "$point_name" "$point_description"
        aa_set "extension_handlers" "$point_name" ""
        
        if [[ "$verbose" == "true" ]]; then
            echo "Registered extension point: $point_name"
        fi
    done
}

# Register plugin for extension point
# Usage: register_extension_handler plugin_name extension_point handler_function
register_extension_handler() {
    local plugin_name="$1"
    local extension_point="$2"
    local handler_function="$3"
    
    if ! aa_has_key "extension_points" "$extension_point"; then
        echo "ERROR: Unknown extension point: $extension_point" >&2
        return 1
    fi
    
    # Get current handlers for this extension point
    local current_handlers
    current_handlers=$(aa_get "extension_handlers" "$extension_point")
    
    # Add new handler
    local new_handlers
    if [[ -z "$current_handlers" ]]; then
        new_handlers="$plugin_name:$handler_function"
    else
        new_handlers="$current_handlers,$plugin_name:$handler_function"
    fi
    
    aa_set "extension_handlers" "$extension_point" "$new_handlers"
    
    _framework_log "INFO" "Registered extension handler: $plugin_name -> $extension_point -> $handler_function"
    
    return 0
}

# Trigger extension point
# Usage: trigger_extension_point extension_point context_data [sync_mode]
trigger_extension_point() {
    local extension_point="$1"
    local context_data="$2"
    local sync_mode="${3:-true}"
    
    if ! aa_has_key "extension_points" "$extension_point"; then
        _framework_log "WARNING" "Unknown extension point triggered: $extension_point"
        return 1
    fi
    
    local handlers
    handlers=$(aa_get "extension_handlers" "$extension_point")
    
    if [[ -z "$handlers" ]]; then
        _framework_log "DEBUG" "No handlers registered for extension point: $extension_point"
        return 0
    fi
    
    _framework_log "INFO" "Triggering extension point: $extension_point"
    
    # Process each handler
    local handler_results=()
    local handler_count=0
    local success_count=0
    local failure_count=0
    
    IFS=',' read -ra handler_list <<< "$handlers"
    for handler_info in "${handler_list[@]}"; do
        if [[ -n "$handler_info" ]]; then
            local plugin_name="${handler_info%:*}"
            local handler_function="${handler_info#*:}"
            
            handler_count=$((handler_count + 1))
            
            if [[ "$sync_mode" == "true" ]]; then
                # Synchronous execution
                if _execute_extension_handler "$plugin_name" "$extension_point" "$handler_function" "$context_data"; then
                    success_count=$((success_count + 1))
                    handler_results+=("$plugin_name:success")
                else
                    failure_count=$((failure_count + 1))
                    handler_results+=("$plugin_name:failed")
                fi
            else
                # Asynchronous execution
                _execute_extension_handler "$plugin_name" "$extension_point" "$handler_function" "$context_data" &
                handler_results+=("$plugin_name:async")
            fi
        fi
    done
    
    _framework_log "INFO" "Extension point execution completed: $extension_point ($success_count success, $failure_count failed)"
    
    # Emit extension point event
    local result_data
    result_data=$(cat <<EOF
{
  "extension_point": "$extension_point",
  "handler_count": $handler_count,
  "success_count": $success_count,
  "failure_count": $failure_count,
  "sync_mode": $sync_mode
}
EOF
)
    
    _emit_framework_event "extension_point.triggered" "$result_data"
    
    return $failure_count
}

# Execute extension handler
# Usage: _execute_extension_handler plugin_name extension_point handler_function context_data
_execute_extension_handler() {
    local plugin_name="$1"
    local extension_point="$2"
    local handler_function="$3"
    local context_data="$4"
    local timeout="${PLUGIN_EXTENSION_TIMEOUT:-10}"
    
    _framework_log "DEBUG" "Executing extension handler: $plugin_name::$handler_function for $extension_point"
    
    # Get plugin path
    if ! aa_has_key "plugin_registry" "$plugin_name"; then
        _framework_log "ERROR" "Plugin not registered: $plugin_name"
        return 1
    fi
    
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Check if plugin is active
    local plugin_status
    plugin_status=$(aa_get "plugin_status" "$plugin_name" "unknown")
    
    if [[ "$plugin_status" != "$PLUGIN_STATE_ACTIVE" ]]; then
        _framework_log "WARNING" "Plugin not active for extension handler: $plugin_name (status: $plugin_status)"
        return 1
    fi
    
    # Execute handler with timeout
    local handler_result
    if handler_result=$(timeout "$timeout" bash -c "
        source '$plugin_path'
        if declare -f '$handler_function' >/dev/null 2>&1; then
            '$handler_function' '$extension_point' '$context_data'
        else
            echo 'Handler function not found: $handler_function'
            exit 1
        fi
    " 2>&1); then
        _framework_log "DEBUG" "Extension handler executed successfully: $plugin_name::$handler_function"
        return 0
    else
        _framework_log "ERROR" "Extension handler failed: $plugin_name::$handler_function - $handler_result"
        return 1
    fi
}

# List available extension points
# Usage: list_extension_points
list_extension_points() {
    echo "Available Extension Points:"
    
    if aa_is_empty "extension_points"; then
        echo "  No extension points registered"
        return 0
    fi
    
    while IFS= read -r point_name; do
        if [[ -n "$point_name" ]]; then
            local description
            description=$(aa_get "extension_points" "$point_name")
            local handlers
            handlers=$(aa_get "extension_handlers" "$point_name")
            local handler_count=0
            
            if [[ -n "$handlers" ]]; then
                IFS=',' read -ra handler_list <<< "$handlers"
                handler_count=${#handler_list[@]}
            fi
            
            echo "  - $point_name: $description ($handler_count handlers)"
        fi
    done < <(aa_keys "extension_points")
}

# =============================================================================
# HIGH-LEVEL PLUGIN OPERATIONS
# =============================================================================

# Discover, validate, and load plugins automatically
# Usage: discover_and_load_plugins [search_pattern] [validation_level]
discover_and_load_plugins() {
    local search_pattern="${1:-*}"
    local validation_level="${2:-standard}"
    
    _framework_log "INFO" "Starting automatic plugin discovery and loading"
    
    # Discover plugins
    local discovered_count
    if ! discover_plugins "$search_pattern"; then
        _framework_log "ERROR" "Plugin discovery failed"
        return 1
    fi
    
    discovered_count=$(aa_size "plugin_registry")
    _framework_log "INFO" "Discovered $discovered_count plugins"
    
    if [[ $discovered_count -eq 0 ]]; then
        _framework_log "INFO" "No plugins found to load"
        return 0
    fi
    
    # Validate all discovered plugins
    _framework_log "INFO" "Validating discovered plugins with level: $validation_level"
    
    local validation_failures
    validation_failures=$(validate_all_plugins "$validation_level")
    
    if [[ $validation_failures -gt 0 ]]; then
        _framework_log "WARNING" "$validation_failures plugins failed validation"
    fi
    
    # Load validated plugins
    _framework_log "INFO" "Loading validated plugins"
    
    local load_failures
    load_failures=$(load_all_plugins)
    
    if [[ $load_failures -gt 0 ]]; then
        _framework_log "WARNING" "$load_failures plugins failed to load"
    fi
    
    # Start loaded plugins
    _framework_log "INFO" "Starting loaded plugins"
    
    local start_failures
    start_failures=$(start_all_plugins)
    
    if [[ $start_failures -gt 0 ]]; then
        _framework_log "WARNING" "$start_failures plugins failed to start"
    fi
    
    # Generate summary
    local final_active_count=0
    
    while IFS= read -r plugin_name; do
        if [[ -n "$plugin_name" ]]; then
            local status
            status=$(aa_get "plugin_status" "$plugin_name")
            if [[ "$status" == "$PLUGIN_STATE_ACTIVE" ]]; then
                final_active_count=$((final_active_count + 1))
            fi
        fi
    done < <(aa_keys "plugin_registry")
    
    _framework_log "SUCCESS" "Plugin loading completed: $final_active_count active plugins out of $discovered_count discovered"
    
    # Emit discovery and loading completed event
    local summary_data
    summary_data=$(cat <<EOF
{
  "discovered_count": $discovered_count,
  "validation_failures": $validation_failures,
  "load_failures": $load_failures,
  "start_failures": $start_failures,
  "final_active_count": $final_active_count
}
EOF
)
    
    _emit_framework_event "plugins.discovery_load_completed" "$summary_data"
    
    return 0
}

# Install plugin from file or URL
# Usage: install_plugin plugin_source [plugin_name] [validation_level]
install_plugin() {
    local plugin_source="$1"
    local plugin_name="${2:-}"
    local validation_level="${3:-standard}"
    
    _framework_log "INFO" "Installing plugin from: $plugin_source"
    
    local temp_plugin_file=""
    local install_plugin_dir=""
    
    # Handle different source types
    if [[ "$plugin_source" =~ ^https?:// ]]; then
        # Download from URL
        temp_plugin_file="/tmp/plugin_$(date '+%s').sh"
        
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL "$plugin_source" -o "$temp_plugin_file"; then
                _framework_log "ERROR" "Failed to download plugin from: $plugin_source"
                return 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -q "$plugin_source" -O "$temp_plugin_file"; then
                _framework_log "ERROR" "Failed to download plugin from: $plugin_source"
                return 1
            fi
        else
            _framework_log "ERROR" "Neither curl nor wget available for download"
            return 1
        fi
        
        plugin_source="$temp_plugin_file"
    fi
    
    # Validate source file exists
    if [[ ! -f "$plugin_source" ]]; then
        _framework_log "ERROR" "Plugin source file not found: $plugin_source"
        [[ -n "$temp_plugin_file" ]] && rm -f "$temp_plugin_file"
        return 1
    fi
    
    # Extract plugin name if not provided
    if [[ -z "$plugin_name" ]]; then
        # Try to extract from metadata
        if plugin_name=$(bash -c "source '$plugin_source'; plugin_metadata 2>/dev/null | grep -o '\"name\": \"[^\"]*\"' | cut -d'\"' -f4"); then
            if [[ -z "$plugin_name" ]]; then
                plugin_name="plugin_$(date '+%s')"
            fi
        else
            plugin_name="plugin_$(date '+%s')"
        fi
    fi
    
    _framework_log "INFO" "Installing plugin: $plugin_name"
    
    # Create plugin directory
    install_plugin_dir="lib/unity/plugins/$plugin_name"
    mkdir -p "$install_plugin_dir"
    
    # Copy plugin file
    local plugin_file="$install_plugin_dir/plugin.sh"
    cp "$plugin_source" "$plugin_file"
    chmod +x "$plugin_file"
    
    # Clean up temp file
    [[ -n "$temp_plugin_file" ]] && rm -f "$temp_plugin_file"
    
    # Validate installed plugin
    if ! validate_plugin "$plugin_name" "$plugin_file" "$validation_level"; then
        _framework_log "ERROR" "Plugin validation failed during installation: $plugin_name"
        rm -rf "$install_plugin_dir"
        return 1
    fi
    
    # Register plugin
    local metadata
    metadata=$(bash -c "source '$plugin_file'; plugin_metadata 2>/dev/null" || echo '{}')
    
    if ! register_plugin "$plugin_name" "$plugin_file" "$metadata"; then
        _framework_log "ERROR" "Plugin registration failed: $plugin_name"
        rm -rf "$install_plugin_dir"
        return 1
    fi
    
    _framework_log "SUCCESS" "Plugin installed successfully: $plugin_name at $install_plugin_dir"
    
    # Emit plugin installed event
    _emit_framework_event "plugin.installed" "{\"plugin_name\": \"$plugin_name\", \"install_path\": \"$install_plugin_dir\"}"
    
    return 0
}

# Uninstall plugin
# Usage: uninstall_plugin plugin_name [remove_files]
uninstall_plugin() {
    local plugin_name="$1"
    local remove_files="${2:-true}"
    
    _framework_log "INFO" "Uninstalling plugin: $plugin_name"
    
    # Check if plugin exists
    if ! aa_has_key "plugin_registry" "$plugin_name"; then
        _framework_log "ERROR" "Plugin not found: $plugin_name"
        return 1
    fi
    
    # Stop and unload plugin
    local current_status
    current_status=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_status" == "$PLUGIN_STATE_ACTIVE" ]]; then
        stop_plugin "$plugin_name" 10 "true"  # Force stop
    fi
    
    if [[ "$current_status" != "$PLUGIN_STATE_UNLOADED" ]]; then
        unload_plugin "$plugin_name"
    fi
    
    # Remove plugin files if requested
    if [[ "$remove_files" == "true" ]]; then
        local plugin_path
        plugin_path=$(aa_get "plugin_registry" "$plugin_name")
        local plugin_dir
        plugin_dir=$(dirname "$plugin_path")
        
        if [[ -d "$plugin_dir" ]] && [[ "$plugin_dir" =~ /plugins/ ]]; then
            rm -rf "$plugin_dir"
            _framework_log "INFO" "Removed plugin files: $plugin_dir"
        fi
    fi
    
    # Remove from registry
    aa_delete "plugin_registry" "$plugin_name"
    aa_delete "plugin_status" "$plugin_name"
    aa_delete "plugin_metadata" "$plugin_name"
    aa_delete "plugin_dependencies" "$plugin_name"
    
    # Remove from other tracking
    aa_delete "plugin_validation_results" "$plugin_name" 2>/dev/null || true
    aa_delete "plugin_security_scores" "$plugin_name" 2>/dev/null || true
    aa_delete "plugin_compliance_status" "$plugin_name" 2>/dev/null || true
    
    _framework_log "SUCCESS" "Plugin uninstalled: $plugin_name"
    
    # Emit plugin uninstalled event
    _emit_framework_event "plugin.uninstalled" "{\"plugin_name\": \"$plugin_name\", \"files_removed\": $remove_files}"
    
    return 0
}

# =============================================================================
# FRAMEWORK STATUS AND MONITORING
# =============================================================================

# Get comprehensive plugin framework status
# Usage: get_plugin_framework_status
get_plugin_framework_status() {
    local framework_initialized="false"
    local initialization_time=""
    
    if [[ -f "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG" ]]; then
        framework_initialized="true"
        local init_timestamp
        init_timestamp=$(grep '"initialized_timestamp"' "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG" | cut -d':' -f2 | tr -d ' ,' || echo "0")
        initialization_time=$(date -d "@$init_timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    fi
    
    # Get component statuses
    local registry_status
    registry_status=$(get_plugin_loader_status 2>/dev/null || echo '{"error": "loader not available"}')
    
    local lifecycle_status
    lifecycle_status=$(get_plugin_lifecycle_status 2>/dev/null || echo '{"error": "lifecycle not available"}')
    
    local validator_status
    validator_status=$(get_plugin_validator_status 2>/dev/null || echo '{"error": "validator not available"}')
    
    # Get extension point summary
    local extension_point_count
    extension_point_count=$(aa_size "extension_points" 2>/dev/null || echo "0")
    
    local total_handlers=0
    if [[ $extension_point_count -gt 0 ]]; then
        while IFS= read -r point_name; do
            if [[ -n "$point_name" ]]; then
                local handlers
                handlers=$(aa_get "extension_handlers" "$point_name")
                if [[ -n "$handlers" ]]; then
                    IFS=',' read -ra handler_list <<< "$handlers"
                    total_handlers=$((total_handlers + ${#handler_list[@]}))
                fi
            fi
        done < <(aa_keys "extension_points" 2>/dev/null || echo "")
    fi
    
    cat <<EOF
{
  "framework": {
    "version": "$UNITY_PLUGIN_FRAMEWORK_VERSION",
    "api_version": "$PLUGIN_FRAMEWORK_API_VERSION",
    "initialized": $framework_initialized,
    "initialization_time": "$initialization_time"
  },
  "extension_points": {
    "total_points": $extension_point_count,
    "total_handlers": $total_handlers
  },
  "components": {
    "loader": $registry_status,
    "lifecycle": $lifecycle_status,
    "validator": $validator_status
  }
}
EOF
}

# Run plugin framework health check
# Usage: run_plugin_framework_health_check
run_plugin_framework_health_check() {
    local health_status="healthy"
    local issues=()
    
    _framework_log "INFO" "Running plugin framework health check"
    
    # Check if framework is initialized
    if [[ ! -f "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG" ]]; then
        health_status="unhealthy"
        issues+=("Framework not initialized")
    fi
    
    # Check core directories
    local required_dirs=(".unity/plugins" ".unity/state" ".unity/logs")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            health_status="degraded"
            issues+=("Required directory missing: $dir")
        fi
    done
    
    # Check component availability
    local components=("init_plugin_registry" "init_plugin_lifecycle" "init_plugin_validator")
    for component in "${components[@]}"; do
        if ! declare -f "$component" >/dev/null 2>&1; then
            health_status="unhealthy"
            issues+=("Component function not available: $component")
        fi
    done
    
    # Run plugin health checks
    local unhealthy_plugins=0
    if ! aa_is_empty "plugin_registry"; then
        while IFS= read -r plugin_name; do
            if [[ -n "$plugin_name" ]]; then
                local plugin_status
                plugin_status=$(aa_get "plugin_status" "$plugin_name")
                
                if [[ "$plugin_status" == "$PLUGIN_STATE_ACTIVE" ]]; then
                    local plugin_health
                    if ! plugin_health=$(run_plugin_health_check "$plugin_name" 2>/dev/null); then
                        unhealthy_plugins=$((unhealthy_plugins + 1))
                    fi
                fi
            fi
        done < <(aa_keys "plugin_registry")
    fi
    
    if [[ $unhealthy_plugins -gt 0 ]]; then
        health_status="degraded"
        issues+=("$unhealthy_plugins plugins unhealthy")
    fi
    
    # Generate health report
    local issues_json="[]"
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json="["
        local first=true
        for issue in "${issues[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                issues_json="$issues_json,"
            fi
            issues_json="$issues_json\"$issue\""
        done
        issues_json="$issues_json]"
    fi
    
    cat <<EOF
{
  "framework_health": "$health_status",
  "timestamp": $(date '+%s'),
  "issues": $issues_json,
  "unhealthy_plugins": $unhealthy_plugins
}
EOF
    
    case "$health_status" in
        "healthy") return 0 ;;
        "degraded") return 1 ;;
        "unhealthy") return 2 ;;
    esac
}

# =============================================================================
# FRAMEWORK EVENT SYSTEM
# =============================================================================

# Emit framework event
# Usage: _emit_framework_event event_type data
_emit_framework_event() {
    local event_type="$1"
    local data="$2"
    
    # Create event payload
    local event_payload
    event_payload=$(cat <<EOF
{
  "id": "event_$(date '+%s')_$$",
  "timestamp": $(date '+%s'),
  "type": "$event_type",
  "source": "plugin-framework",
  "data": $data,
  "metadata": {
    "priority": "medium",
    "version": "2.0"
  }
}
EOF
)
    
    # Emit to Unity event system if available
    if command -v unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "$event_payload"
    else
        # Log event
        _framework_log "EVENT" "$event_type"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Framework logging
# Usage: _framework_log level message [extra_data]
_framework_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format log message
    local log_entry="$timestamp [$level] [PluginFramework] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to framework log
    local framework_log=".unity/logs/plugin-framework.log"
    mkdir -p "$(dirname "$framework_log")"
    echo "$log_entry" >> "$framework_log"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "PluginFramework: $message"
    else
        # Fallback to stderr/stdout
        case "$level" in
            "ERROR"|"CRITICAL")
                echo "$log_entry" >&2
                ;;
            "SUCCESS"|"EVENT")
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

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all framework functions
export -f init_unity_plugin_framework
export -f register_extension_handler
export -f trigger_extension_point
export -f list_extension_points
export -f discover_and_load_plugins
export -f install_plugin
export -f uninstall_plugin
export -f get_plugin_framework_status
export -f run_plugin_framework_health_check

# =============================================================================
# AUTO-INITIALIZATION
# =============================================================================

# Auto-initialize framework when sourced
if [[ -z "${UNITY_PLUGIN_FRAMEWORK_LOADED:-}" ]]; then
    # Load dependencies
    _load_plugin_dependencies "false"
    
    export UNITY_PLUGIN_FRAMEWORK_LOADED=true
    
    # Initialize if not already done
    if [[ ! -f "$PLUGIN_FRAMEWORK_INITIALIZED_FLAG" ]]; then
        init_unity_plugin_framework "false"
    fi
fi

# =============================================================================
# MAIN SCRIPT EXECUTION
# =============================================================================

# If sourced directly, show framework information and optionally run operations
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Plugin Framework v$UNITY_PLUGIN_FRAMEWORK_VERSION"
    echo "API Version: $PLUGIN_FRAMEWORK_API_VERSION"
    echo ""
    
    # Parse command line arguments
    case "${1:-help}" in
        "init"|"initialize")
            init_unity_plugin_framework "true" "${2:-standard}"
            ;;
        "discover")
            discover_and_load_plugins "${2:-*}" "${3:-standard}"
            ;;
        "install")
            if [[ -n "${2:-}" ]]; then
                install_plugin "$2" "${3:-}" "${4:-standard}"
            else
                echo "Usage: $0 install <source> [name] [validation_level]"
                exit 1
            fi
            ;;
        "uninstall")
            if [[ -n "${2:-}" ]]; then
                uninstall_plugin "$2" "${3:-true}"
            else
                echo "Usage: $0 uninstall <plugin_name> [remove_files]"
                exit 1
            fi
            ;;
        "status")
            get_plugin_framework_status | jq '.' 2>/dev/null || cat
            ;;
        "health")
            run_plugin_framework_health_check | jq '.' 2>/dev/null || cat
            ;;
        "extensions")
            list_extension_points
            ;;
        "help"|*)
            echo "Available commands:"
            echo "  init [validation_level]     - Initialize plugin framework"
            echo "  discover [pattern] [level]  - Discover and load plugins"
            echo "  install <source> [name]     - Install plugin from file/URL"
            echo "  uninstall <name> [remove]   - Uninstall plugin"
            echo "  status                      - Show framework status"
            echo "  health                      - Run health check"
            echo "  extensions                  - List extension points"
            echo "  help                        - Show this help"
            ;;
    esac
fi