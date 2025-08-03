#!/bin/bash
# =============================================================================
# Unity Plugin Loader
# Plugin discovery, loading, and validation mechanisms
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load required libraries
if [[ -f "$PROJECT_ROOT/lib/associative-arrays.sh" ]]; then
    source "$PROJECT_ROOT/lib/associative-arrays.sh"
fi

if [[ -f "$SCRIPT_DIR/plugin-interface.sh" ]]; then
    source "$SCRIPT_DIR/plugin-interface.sh"
fi

# =============================================================================
# PLUGIN LOADER CONSTANTS
# =============================================================================

readonly UNITY_PLUGIN_LOADER_VERSION="1.0.0"
readonly UNITY_PLUGIN_DISCOVERY_TIMEOUT=30
readonly UNITY_PLUGIN_LOAD_TIMEOUT=10
readonly UNITY_PLUGIN_MAX_RETRIES=3

# Plugin directories (in search order)
UNITY_PLUGIN_SEARCH_PATHS=(
    "lib/unity/plugins"
    ".unity/plugins"
    "plugins"
    "${HOME}/.unity/plugins"
    "/usr/local/share/unity/plugins"
)

# Plugin file patterns
UNITY_PLUGIN_FILE_PATTERNS=(
    "plugin.sh"
    "*.plugin.sh"
    "main.sh"
)

# Plugin states
readonly PLUGIN_REGISTRY_FILE=".unity/state/plugin-registry.json"
readonly PLUGIN_LOAD_LOG=".unity/logs/plugin-loader.log"

# =============================================================================
# PLUGIN REGISTRY MANAGEMENT
# =============================================================================

# Initialize plugin registry using associative arrays
init_plugin_registry() {
    local verbose="${1:-false}"
    
    # Create required directories
    mkdir -p "$(dirname "$PLUGIN_REGISTRY_FILE")" "$(dirname "$PLUGIN_LOAD_LOG")"
    
    # Initialize plugin registry associative array
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        # Use compatibility mode for bash 3.x
        kv_clear "plugin_registry"
        kv_clear "plugin_metadata"
        kv_clear "plugin_status"
        kv_clear "plugin_dependencies"
    else
        # Use native associative arrays for bash 4+
        declare -gA plugin_registry=()
        declare -gA plugin_metadata=()
        declare -gA plugin_status=()
        declare -gA plugin_dependencies=()
    fi
    
    # Initialize plugin state files
    echo "[]" > "$PLUGIN_REGISTRY_FILE"
    
    if [[ "$verbose" == "true" ]]; then
        _plugin_loader_log "SUCCESS" "Plugin registry initialized"
    fi
    
    return 0
}

# Register plugin in registry
# Usage: register_plugin plugin_name plugin_path metadata
register_plugin() {
    local plugin_name="$1"
    local plugin_path="$2"
    local metadata="$3"
    local priority="${4:-50}"
    
    if [[ -z "$plugin_name" ]] || [[ -z "$plugin_path" ]]; then
        _plugin_loader_log "ERROR" "Invalid plugin registration parameters"
        return 1
    fi
    
    # Store plugin information
    aa_set "plugin_registry" "$plugin_name" "$plugin_path"
    aa_set "plugin_metadata" "$plugin_name" "$metadata"
    aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_UNLOADED"
    
    # Extract and store dependencies from metadata
    local dependencies
    dependencies=$(echo "$metadata" | grep -o '"required": \[[^]]*\]' | sed 's/"required": \[\([^]]*\)\]/\1/' | tr -d '"' | tr ',' ' ')
    aa_set "plugin_dependencies" "$plugin_name" "$dependencies"
    
    _plugin_loader_log "INFO" "Plugin registered: $plugin_name at $plugin_path"
    
    return 0
}

# Get plugin from registry
# Usage: get_plugin_info plugin_name
get_plugin_info() {
    local plugin_name="$1"
    
    if ! aa_has_key "plugin_registry" "$plugin_name"; then
        return 1
    fi
    
    local plugin_path
    local metadata
    local status
    local dependencies
    
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    metadata=$(aa_get "plugin_metadata" "$plugin_name")
    status=$(aa_get "plugin_status" "$plugin_name")
    dependencies=$(aa_get "plugin_dependencies" "$plugin_name")
    
    cat <<EOF
{
  "name": "$plugin_name",
  "path": "$plugin_path",
  "status": "$status",
  "dependencies": "$dependencies",
  "metadata": $metadata
}
EOF
}

# List all registered plugins
list_registered_plugins() {
    local format="${1:-simple}"
    
    if aa_is_empty "plugin_registry"; then
        echo "No plugins registered"
        return 0
    fi
    
    case "$format" in
        "simple")
            echo "Registered Plugins:"
            while IFS= read -r plugin_name; do
                if [[ -n "$plugin_name" ]]; then
                    local status
                    status=$(aa_get "plugin_status" "$plugin_name" "unknown")
                    echo "  - $plugin_name [$status]"
                fi
            done < <(aa_keys "plugin_registry")
            ;;
        "detailed")
            echo "Plugin Registry Details:"
            while IFS= read -r plugin_name; do
                if [[ -n "$plugin_name" ]]; then
                    echo "=== $plugin_name ==="
                    get_plugin_info "$plugin_name" | sed 's/^/  /'
                    echo ""
                fi
            done < <(aa_keys "plugin_registry")
            ;;
        "json")
            echo "["
            local first=true
            while IFS= read -r plugin_name; do
                if [[ -n "$plugin_name" ]]; then
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        echo ","
                    fi
                    get_plugin_info "$plugin_name" | sed 's/^/  /'
                fi
            done < <(aa_keys "plugin_registry")
            echo "]"
            ;;
        *)
            echo "Invalid format: $format. Use: simple, detailed, json"
            return 1
            ;;
    esac
}

# =============================================================================
# PLUGIN DISCOVERY
# =============================================================================

# Discover plugins in all search paths
# Usage: discover_plugins [search_pattern]
discover_plugins() {
    local search_pattern="${1:-*}"
    local discovered_count=0
    
    _plugin_loader_log "INFO" "Starting plugin discovery with pattern: $search_pattern"
    
    # Search in all configured paths
    for search_path in "${UNITY_PLUGIN_SEARCH_PATHS[@]}"; do
        if [[ -d "$search_path" ]]; then
            _plugin_loader_log "DEBUG" "Searching in: $search_path"
            
            # Search for plugin files using different patterns
            for pattern in "${UNITY_PLUGIN_FILE_PATTERNS[@]}"; do
                while IFS= read -r -d '' plugin_file; do
                    if [[ -f "$plugin_file" ]]; then
                        local plugin_dir
                        plugin_dir=$(dirname "$plugin_file")
                        local plugin_name
                        plugin_name=$(basename "$plugin_dir")
                        
                        # Skip if plugin name doesn't match search pattern
                        if [[ "$search_pattern" != "*" ]] && [[ ! "$plugin_name" =~ $search_pattern ]]; then
                            continue
                        fi
                        
                        if _validate_plugin_file "$plugin_file"; then
                            if _discover_single_plugin "$plugin_name" "$plugin_file"; then
                                discovered_count=$((discovered_count + 1))
                                _plugin_loader_log "SUCCESS" "Discovered plugin: $plugin_name"
                            fi
                        fi
                    fi
                done < <(find "$search_path" -name "$pattern" -type f -print0 2>/dev/null || true)
            done
        fi
    done
    
    _plugin_loader_log "INFO" "Plugin discovery completed. Found $discovered_count plugins"
    return 0
}

# Discover single plugin
# Usage: _discover_single_plugin plugin_name plugin_file
_discover_single_plugin() {
    local plugin_name="$1"
    local plugin_file="$2"
    
    # Check if plugin is already registered
    if aa_has_key "plugin_registry" "$plugin_name"; then
        _plugin_loader_log "DEBUG" "Plugin already registered: $plugin_name"
        return 0
    fi
    
    # Load plugin metadata
    local metadata
    if ! metadata=$(_extract_plugin_metadata "$plugin_file"); then
        _plugin_loader_log "ERROR" "Failed to extract metadata from: $plugin_file"
        return 1
    fi
    
    # Validate plugin metadata
    if ! _validate_plugin_metadata "$metadata"; then
        _plugin_loader_log "ERROR" "Invalid plugin metadata: $plugin_name"
        return 1
    fi
    
    # Register the plugin
    register_plugin "$plugin_name" "$plugin_file" "$metadata"
    
    return 0
}

# Validate plugin file
# Usage: _validate_plugin_file plugin_file
_validate_plugin_file() {
    local plugin_file="$1"
    
    # Check if file exists and is readable
    if [[ ! -r "$plugin_file" ]]; then
        _plugin_loader_log "ERROR" "Plugin file not readable: $plugin_file"
        return 1
    fi
    
    # Check if file has bash shebang
    local first_line
    first_line=$(head -n1 "$plugin_file")
    if [[ ! "$first_line" =~ ^#!/.*/bash ]]; then
        _plugin_loader_log "WARNING" "Plugin file missing bash shebang: $plugin_file"
    fi
    
    # Check basic syntax by attempting to source it in a subshell
    if ! (
        set -euo pipefail
        source "$plugin_file" >/dev/null 2>&1
    ); then
        _plugin_loader_log "ERROR" "Plugin file has syntax errors: $plugin_file"
        return 1
    fi
    
    return 0
}

# Extract plugin metadata
# Usage: _extract_plugin_metadata plugin_file
_extract_plugin_metadata() {
    local plugin_file="$1"
    
    # Source the plugin file in a subshell and call plugin_metadata function
    local metadata
    if ! metadata=$(
        set -euo pipefail
        source "$plugin_file"
        if declare -f plugin_metadata >/dev/null 2>&1; then
            plugin_metadata
        else
            echo '{"error": "plugin_metadata function not found"}'
        fi
    ); then
        _plugin_loader_log "ERROR" "Failed to extract metadata from: $plugin_file"
        return 1
    fi
    
    echo "$metadata"
}

# Validate plugin metadata
# Usage: _validate_plugin_metadata metadata
_validate_plugin_metadata() {
    local metadata="$1"
    
    # Check if metadata is valid JSON-like structure
    if [[ ! "$metadata" =~ ^\{.*\}$ ]]; then
        _plugin_loader_log "ERROR" "Metadata is not valid JSON format"
        return 1
    fi
    
    # Check required fields
    local required_fields=("name" "version" "api_version" "type")
    for field in "${required_fields[@]}"; do
        if [[ ! "$metadata" =~ \"$field\": ]]; then
            _plugin_loader_log "ERROR" "Required metadata field missing: $field"
            return 1
        fi
    done
    
    # Validate API version compatibility
    local api_version
    api_version=$(echo "$metadata" | grep -o '"api_version": "[^"]*"' | cut -d'"' -f4)
    if ! is_plugin_api_version_supported "$api_version"; then
        _plugin_loader_log "ERROR" "Unsupported API version: $api_version"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN LOADING
# =============================================================================

# Load plugin by name
# Usage: load_plugin plugin_name [force]
load_plugin() {
    local plugin_name="$1"
    local force="${2:-false}"
    
    _plugin_loader_log "INFO" "Loading plugin: $plugin_name"
    
    # Check if plugin is registered
    if ! aa_has_key "plugin_registry" "$plugin_name"; then
        _plugin_loader_log "ERROR" "Plugin not registered: $plugin_name"
        return 1
    fi
    
    # Check current status
    local current_status
    current_status=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_status" == "$PLUGIN_STATE_LOADED" ]] && [[ "$force" != "true" ]]; then
        _plugin_loader_log "INFO" "Plugin already loaded: $plugin_name"
        return 0
    fi
    
    # Update status
    aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_LOADING"
    
    # Load plugin dependencies first
    if ! _load_plugin_dependencies "$plugin_name"; then
        aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_ERROR"
        _plugin_loader_log "ERROR" "Failed to load dependencies for: $plugin_name"
        return 1
    fi
    
    # Load the plugin file
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    if ! _load_plugin_file "$plugin_path"; then
        aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_ERROR"
        _plugin_loader_log "ERROR" "Failed to load plugin file: $plugin_path"
        return 1
    fi
    
    # Validate plugin interface
    if ! validate_plugin_interface "$plugin_path"; then
        aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_ERROR"
        _plugin_loader_log "ERROR" "Plugin interface validation failed: $plugin_name"
        return 1
    fi
    
    # Run plugin validation
    if ! _run_plugin_validation "$plugin_path"; then
        aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_ERROR"
        _plugin_loader_log "ERROR" "Plugin validation failed: $plugin_name"
        return 1
    fi
    
    # Update status to loaded
    aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_LOADED"
    
    _plugin_loader_log "SUCCESS" "Plugin loaded successfully: $plugin_name"
    
    # Emit plugin loaded event
    _emit_plugin_event "plugin.loaded" "$plugin_name" '{"status": "loaded"}'
    
    return 0
}

# Load plugin dependencies
# Usage: _load_plugin_dependencies plugin_name
_load_plugin_dependencies() {
    local plugin_name="$1"
    local dependencies
    dependencies=$(aa_get "plugin_dependencies" "$plugin_name")
    
    if [[ -z "$dependencies" ]]; then
        return 0
    fi
    
    _plugin_loader_log "DEBUG" "Loading dependencies for $plugin_name: $dependencies"
    
    # Load each dependency
    for dep in $dependencies; do
        if aa_has_key "plugin_registry" "$dep"; then
            local dep_status
            dep_status=$(aa_get "plugin_status" "$dep")
            
            if [[ "$dep_status" != "$PLUGIN_STATE_LOADED" ]]; then
                if ! load_plugin "$dep"; then
                    _plugin_loader_log "ERROR" "Failed to load dependency: $dep"
                    return 1
                fi
            fi
        else
            _plugin_loader_log "ERROR" "Dependency not found: $dep"
            return 1
        fi
    done
    
    return 0
}

# Load plugin file
# Usage: _load_plugin_file plugin_file
_load_plugin_file() {
    local plugin_file="$1"
    
    # Source the plugin file
    if ! source "$plugin_file"; then
        _plugin_loader_log "ERROR" "Failed to source plugin file: $plugin_file"
        return 1
    fi
    
    return 0
}

# Run plugin validation
# Usage: _run_plugin_validation plugin_file
_run_plugin_validation() {
    local plugin_file="$1"
    
    # Source the plugin and run its validation
    if ! (
        source "$plugin_file"
        if declare -f plugin_validate >/dev/null 2>&1; then
            plugin_validate
        else
            return 0  # No validation function is OK
        fi
    ); then
        _plugin_loader_log "ERROR" "Plugin validation failed"
        return 1
    fi
    
    return 0
}

# Load multiple plugins
# Usage: load_plugins plugin_name1 plugin_name2 ...
load_plugins() {
    local plugins=("$@")
    local success_count=0
    local failure_count=0
    
    _plugin_loader_log "INFO" "Loading ${#plugins[@]} plugins"
    
    for plugin_name in "${plugins[@]}"; do
        if load_plugin "$plugin_name"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    _plugin_loader_log "INFO" "Plugin loading completed: $success_count successful, $failure_count failed"
    
    if [[ $failure_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Load all discovered plugins
# Usage: load_all_plugins [priority_filter]
load_all_plugins() {
    local priority_filter="${1:-}"
    local loaded_count=0
    local failed_count=0
    
    _plugin_loader_log "INFO" "Loading all discovered plugins"
    
    # Get plugins sorted by priority
    local plugins_by_priority
    plugins_by_priority=()
    
    while IFS= read -r plugin_name; do
        if [[ -n "$plugin_name" ]]; then
            local metadata
            metadata=$(aa_get "plugin_metadata" "$plugin_name")
            local priority
            priority=$(echo "$metadata" | grep -o '"priority": [0-9]*' | cut -d':' -f2 | tr -d ' ' || echo "50")
            
            # Apply priority filter if specified
            if [[ -n "$priority_filter" ]] && [[ "$priority" -lt "$priority_filter" ]]; then
                continue
            fi
            
            plugins_by_priority+=("$priority:$plugin_name")
        fi
    done < <(aa_keys "plugin_registry")
    
    # Sort by priority (descending)
    IFS=$'\n' plugins_by_priority=($(sort -t: -k1 -nr <<< "${plugins_by_priority[*]}"))
    
    # Load plugins in priority order
    for plugin_entry in "${plugins_by_priority[@]}"; do
        local plugin_name="${plugin_entry#*:}"
        
        if load_plugin "$plugin_name"; then
            loaded_count=$((loaded_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done
    
    _plugin_loader_log "INFO" "Loaded $loaded_count plugins, $failed_count failed"
    
    return $failed_count
}

# =============================================================================
# PLUGIN UNLOADING
# =============================================================================

# Unload plugin by name
# Usage: unload_plugin plugin_name
unload_plugin() {
    local plugin_name="$1"
    
    _plugin_loader_log "INFO" "Unloading plugin: $plugin_name"
    
    # Check if plugin is registered
    if ! aa_has_key "plugin_registry" "$plugin_name"; then
        _plugin_loader_log "ERROR" "Plugin not registered: $plugin_name"
        return 1
    fi
    
    # Check current status
    local current_status
    current_status=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_status" == "$PLUGIN_STATE_UNLOADED" ]]; then
        _plugin_loader_log "INFO" "Plugin already unloaded: $plugin_name"
        return 0
    fi
    
    # Stop plugin if it's active
    if [[ "$current_status" == "$PLUGIN_STATE_ACTIVE" ]]; then
        if ! _stop_plugin "$plugin_name"; then
            _plugin_loader_log "WARNING" "Failed to stop plugin cleanly: $plugin_name"
        fi
    fi
    
    # Run plugin cleanup
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    if ! _run_plugin_cleanup "$plugin_path"; then
        _plugin_loader_log "WARNING" "Plugin cleanup failed: $plugin_name"
    fi
    
    # Update status
    aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_UNLOADED"
    
    _plugin_loader_log "SUCCESS" "Plugin unloaded: $plugin_name"
    
    # Emit plugin unloaded event
    _emit_plugin_event "plugin.unloaded" "$plugin_name" '{"status": "unloaded"}'
    
    return 0
}

# Stop plugin
# Usage: _stop_plugin plugin_name
_stop_plugin() {
    local plugin_name="$1"
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Source plugin and call stop function
    if ! (
        source "$plugin_path"
        if declare -f plugin_stop >/dev/null 2>&1; then
            plugin_stop
        else
            return 0  # No stop function is OK
        fi
    ); then
        return 1
    fi
    
    return 0
}

# Run plugin cleanup
# Usage: _run_plugin_cleanup plugin_file
_run_plugin_cleanup() {
    local plugin_file="$1"
    
    # Source plugin and call cleanup function
    if ! (
        source "$plugin_file"
        if declare -f plugin_cleanup >/dev/null 2>&1; then
            plugin_cleanup
        else
            return 0  # No cleanup function is OK
        fi
    ); then
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN STATUS AND MONITORING
# =============================================================================

# Get plugin status
# Usage: get_plugin_status plugin_name
get_plugin_status() {
    local plugin_name="$1"
    
    if ! aa_has_key "plugin_status" "$plugin_name"; then
        echo "unknown"
        return 1
    fi
    
    aa_get "plugin_status" "$plugin_name"
}

# Check if plugin is loaded
# Usage: is_plugin_loaded plugin_name
is_plugin_loaded() {
    local plugin_name="$1"
    local status
    status=$(get_plugin_status "$plugin_name")
    
    [[ "$status" == "$PLUGIN_STATE_LOADED" ]] || [[ "$status" == "$PLUGIN_STATE_ACTIVE" ]]
}

# Get plugin health status
# Usage: get_plugin_health plugin_name
get_plugin_health() {
    local plugin_name="$1"
    
    if ! is_plugin_loaded "$plugin_name"; then
        echo '{"status": "unloaded", "healthy": false}'
        return 1
    fi
    
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Run plugin health check if available
    local health_result
    if health_result=$(
        source "$plugin_path"
        if declare -f plugin_health_check >/dev/null 2>&1; then
            plugin_health_check
        else
            echo '{"status": "healthy", "message": "No health check available"}'
        fi
    ); then
        echo "$health_result"
    else
        echo '{"status": "unhealthy", "message": "Health check failed"}'
        return 2
    fi
}

# =============================================================================
# PLUGIN EVENTS
# =============================================================================

# Emit plugin event
# Usage: _emit_plugin_event event_type plugin_name data
_emit_plugin_event() {
    local event_type="$1"
    local plugin_name="$2"
    local data="$3"
    
    # Create event payload
    local event_payload
    event_payload=$(cat <<EOF
{
  "id": "event_$(date '+%s')_$$",
  "timestamp": $(date '+%s'),
  "type": "$event_type",
  "source": "plugin-loader",
  "data": {
    "plugin_name": "$plugin_name",
    "details": $data
  },
  "metadata": {
    "priority": "medium",
    "version": "2.0"
  }
}
EOF
)
    
    # Emit event to Unity event system if available
    if command -v unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "$event_payload"
    else
        # Log event to file
        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: $event_type for $plugin_name" >> "$PLUGIN_LOAD_LOG"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Plugin loader logging
# Usage: _plugin_loader_log level message [extra_data]
_plugin_loader_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format log message
    local log_entry="$timestamp [$level] [PluginLoader] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to plugin loader log
    echo "$log_entry" >> "$PLUGIN_LOAD_LOG"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "PluginLoader: $message"
    else
        # Fallback to stderr/stdout
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

# Reload plugin
# Usage: reload_plugin plugin_name
reload_plugin() {
    local plugin_name="$1"
    
    _plugin_loader_log "INFO" "Reloading plugin: $plugin_name"
    
    # Unload and reload
    if unload_plugin "$plugin_name" && load_plugin "$plugin_name"; then
        _plugin_loader_log "SUCCESS" "Plugin reloaded successfully: $plugin_name"
        return 0
    else
        _plugin_loader_log "ERROR" "Failed to reload plugin: $plugin_name"
        return 1
    fi
}

# Get plugin loader status
get_plugin_loader_status() {
    local total_plugins
    total_plugins=$(aa_size "plugin_registry")
    
    local loaded_count=0
    local active_count=0
    local error_count=0
    
    if [[ $total_plugins -gt 0 ]]; then
        while IFS= read -r plugin_name; do
            if [[ -n "$plugin_name" ]]; then
                local status
                status=$(aa_get "plugin_status" "$plugin_name")
                case "$status" in
                    "$PLUGIN_STATE_LOADED"|"$PLUGIN_STATE_ACTIVE")
                        loaded_count=$((loaded_count + 1))
                        ;;
                    "$PLUGIN_STATE_ACTIVE")
                        active_count=$((active_count + 1))
                        ;;
                    "$PLUGIN_STATE_ERROR")
                        error_count=$((error_count + 1))
                        ;;
                esac
            fi
        done < <(aa_keys "plugin_registry")
    fi
    
    cat <<EOF
{
  "loader_version": "$UNITY_PLUGIN_LOADER_VERSION",
  "total_plugins": $total_plugins,
  "loaded_plugins": $loaded_count,
  "active_plugins": $active_count,
  "error_plugins": $error_count,
  "registry_file": "$PLUGIN_REGISTRY_FILE",
  "log_file": "$PLUGIN_LOAD_LOG"
}
EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all plugin loader functions
export -f init_plugin_registry
export -f register_plugin
export -f get_plugin_info
export -f list_registered_plugins
export -f discover_plugins
export -f load_plugin
export -f load_plugins
export -f load_all_plugins
export -f unload_plugin
export -f get_plugin_status
export -f is_plugin_loaded
export -f get_plugin_health
export -f reload_plugin
export -f get_plugin_loader_status

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize plugin registry when sourced
if [[ -z "${UNITY_PLUGIN_REGISTRY_INITIALIZED:-}" ]]; then
    init_plugin_registry
    export UNITY_PLUGIN_REGISTRY_INITIALIZED=true
fi

# If sourced directly, show loader information
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Plugin Loader v$UNITY_PLUGIN_LOADER_VERSION"
    echo "Search paths: ${#UNITY_PLUGIN_SEARCH_PATHS[@]}"
    echo "File patterns: ${#UNITY_PLUGIN_FILE_PATTERNS[@]}"
    echo ""
    echo "Use discover_plugins to find plugins"
    echo "Use load_plugin <name> to load a specific plugin"
    echo "Use load_all_plugins to load all discovered plugins"
fi