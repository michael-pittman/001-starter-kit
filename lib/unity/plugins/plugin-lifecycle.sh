#!/bin/bash
# =============================================================================
# Unity Plugin Lifecycle Management
# Manages plugin initialization, startup, shutdown, and state transitions
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

if [[ -f "$SCRIPT_DIR/plugin-loader.sh" ]]; then
    source "$SCRIPT_DIR/plugin-loader.sh"
fi

# =============================================================================
# LIFECYCLE MANAGEMENT CONSTANTS
# =============================================================================

readonly UNITY_PLUGIN_LIFECYCLE_VERSION="1.0.0"
readonly PLUGIN_LIFECYCLE_TIMEOUT=30
readonly PLUGIN_STATE_TRANSITION_TIMEOUT=10
readonly PLUGIN_HEALTH_CHECK_INTERVAL=60

# Plugin lifecycle state machine transitions
declare -A VALID_STATE_TRANSITIONS=(
    ["$PLUGIN_STATE_UNLOADED"]="$PLUGIN_STATE_LOADING"
    ["$PLUGIN_STATE_LOADING"]="$PLUGIN_STATE_LOADED,$PLUGIN_STATE_ERROR"
    ["$PLUGIN_STATE_LOADED"]="$PLUGIN_STATE_INITIALIZING,$PLUGIN_STATE_UNLOADED"
    ["$PLUGIN_STATE_INITIALIZING"]="$PLUGIN_STATE_INITIALIZED,$PLUGIN_STATE_ERROR"
    ["$PLUGIN_STATE_INITIALIZED"]="$PLUGIN_STATE_STARTING,$PLUGIN_STATE_STOPPED"
    ["$PLUGIN_STATE_STARTING"]="$PLUGIN_STATE_ACTIVE,$PLUGIN_STATE_ERROR"
    ["$PLUGIN_STATE_ACTIVE"]="$PLUGIN_STATE_STOPPING,$PLUGIN_STATE_ERROR"
    ["$PLUGIN_STATE_STOPPING"]="$PLUGIN_STATE_STOPPED,$PLUGIN_STATE_ERROR"
    ["$PLUGIN_STATE_STOPPED"]="$PLUGIN_STATE_STARTING,$PLUGIN_STATE_UNLOADED"
    ["$PLUGIN_STATE_ERROR"]="$PLUGIN_STATE_UNLOADED,$PLUGIN_STATE_LOADING"
    ["$PLUGIN_STATE_DISABLED"]="$PLUGIN_STATE_UNLOADED"
)

# Lifecycle directories and files
readonly PLUGIN_LIFECYCLE_STATE_DIR=".unity/state/plugins"
readonly PLUGIN_LIFECYCLE_LOG=".unity/logs/plugin-lifecycle.log"
readonly PLUGIN_PID_DIR=".unity/pids/plugins"

# =============================================================================
# PLUGIN LIFECYCLE STATE MANAGEMENT
# =============================================================================

# Initialize plugin lifecycle management
init_plugin_lifecycle() {
    local verbose="${1:-false}"
    
    # Create required directories
    mkdir -p "$PLUGIN_LIFECYCLE_STATE_DIR" "$PLUGIN_PID_DIR" "$(dirname "$PLUGIN_LIFECYCLE_LOG")"
    
    # Initialize lifecycle state tracking
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        kv_clear "plugin_lifecycle_state"
        kv_clear "plugin_start_time"
        kv_clear "plugin_last_health_check"
        kv_clear "plugin_error_count"
    else
        declare -gA plugin_lifecycle_state=()
        declare -gA plugin_start_time=()
        declare -gA plugin_last_health_check=()
        declare -gA plugin_error_count=()
    fi
    
    if [[ "$verbose" == "true" ]]; then
        _lifecycle_log "SUCCESS" "Plugin lifecycle management initialized"
    fi
    
    return 0
}

# Validate state transition
# Usage: validate_state_transition plugin_name from_state to_state
validate_state_transition() {
    local plugin_name="$1"
    local from_state="$2"
    local to_state="$3"
    
    if [[ -z "${VALID_STATE_TRANSITIONS[$from_state]:-}" ]]; then
        _lifecycle_log "ERROR" "Invalid from state: $from_state for plugin: $plugin_name"
        return 1
    fi
    
    if [[ ! "${VALID_STATE_TRANSITIONS[$from_state]}" =~ $to_state ]]; then
        _lifecycle_log "ERROR" "Invalid state transition: $from_state -> $to_state for plugin: $plugin_name"
        return 1
    fi
    
    return 0
}

# Set plugin state
# Usage: set_plugin_state plugin_name new_state
set_plugin_state() {
    local plugin_name="$1"
    local new_state="$2"
    local timestamp=$(date '+%s')
    
    # Get current state
    local current_state
    current_state=$(aa_get "plugin_status" "$plugin_name" "$PLUGIN_STATE_UNLOADED")
    
    # Validate state transition
    if ! validate_state_transition "$plugin_name" "$current_state" "$new_state"; then
        return 1
    fi
    
    # Update state
    aa_set "plugin_status" "$plugin_name" "$new_state"
    aa_set "plugin_lifecycle_state" "$plugin_name" "$timestamp:$current_state:$new_state"
    
    # Create state file
    local state_file="$PLUGIN_LIFECYCLE_STATE_DIR/${plugin_name}.state"
    cat > "$state_file" <<EOF
{
  "plugin_name": "$plugin_name",
  "current_state": "$new_state",
  "previous_state": "$current_state",
  "transition_timestamp": $timestamp,
  "transition_time": "$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')"
}
EOF
    
    _lifecycle_log "INFO" "State transition: $plugin_name: $current_state -> $new_state"
    
    # Emit state change event
    _emit_lifecycle_event "plugin.state_changed" "$plugin_name" "{\"from\": \"$current_state\", \"to\": \"$new_state\"}"
    
    return 0
}

# Get plugin lifecycle history
# Usage: get_plugin_lifecycle_history plugin_name
get_plugin_lifecycle_history() {
    local plugin_name="$1"
    local state_file="$PLUGIN_LIFECYCLE_STATE_DIR/${plugin_name}.state"
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo '{"error": "No lifecycle history found"}'
        return 1
    fi
}

# =============================================================================
# PLUGIN INITIALIZATION MANAGEMENT
# =============================================================================

# Initialize plugin
# Usage: initialize_plugin plugin_name [timeout]
initialize_plugin() {
    local plugin_name="$1"
    local timeout="${2:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    
    _lifecycle_log "INFO" "Initializing plugin: $plugin_name"
    
    # Check if plugin is loaded
    if ! is_plugin_loaded "$plugin_name"; then
        _lifecycle_log "ERROR" "Plugin not loaded: $plugin_name"
        return 1
    fi
    
    # Set initializing state
    if ! set_plugin_state "$plugin_name" "$PLUGIN_STATE_INITIALIZING"; then
        return 1
    fi
    
    # Get plugin path
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Run plugin initialization with timeout
    local init_result
    if init_result=$(timeout "$timeout" bash -c "
        source '$plugin_path'
        if declare -f plugin_init >/dev/null 2>&1; then
            plugin_init
        else
            echo 'No plugin_init function found'
            exit 0
        fi
    " 2>&1); then
        # Set initialized state
        set_plugin_state "$plugin_name" "$PLUGIN_STATE_INITIALIZED"
        aa_set "plugin_start_time" "$plugin_name" "$(date '+%s')"
        
        _lifecycle_log "SUCCESS" "Plugin initialized: $plugin_name"
        _emit_lifecycle_event "plugin.initialized" "$plugin_name" "{\"result\": \"success\"}"
        
        return 0
    else
        # Set error state
        set_plugin_state "$plugin_name" "$PLUGIN_STATE_ERROR"
        _increment_error_count "$plugin_name"
        
        _lifecycle_log "ERROR" "Plugin initialization failed: $plugin_name - $init_result"
        _emit_lifecycle_event "plugin.init_failed" "$plugin_name" "{\"error\": \"$init_result\"}"
        
        return 1
    fi
}

# =============================================================================
# PLUGIN STARTUP MANAGEMENT
# =============================================================================

# Start plugin
# Usage: start_plugin plugin_name [timeout]
start_plugin() {
    local plugin_name="$1"
    local timeout="${2:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    
    _lifecycle_log "INFO" "Starting plugin: $plugin_name"
    
    # Check if plugin is initialized
    local current_state
    current_state=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_state" != "$PLUGIN_STATE_INITIALIZED" ]] && [[ "$current_state" != "$PLUGIN_STATE_STOPPED" ]]; then
        if [[ "$current_state" == "$PLUGIN_STATE_LOADED" ]]; then
            # Try to initialize first
            if ! initialize_plugin "$plugin_name"; then
                return 1
            fi
        else
            _lifecycle_log "ERROR" "Plugin not in startable state: $plugin_name (current: $current_state)"
            return 1
        fi
    fi
    
    # Set starting state
    if ! set_plugin_state "$plugin_name" "$PLUGIN_STATE_STARTING"; then
        return 1
    fi
    
    # Get plugin path
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Run plugin start with timeout
    local start_result
    if start_result=$(timeout "$timeout" bash -c "
        source '$plugin_path'
        if declare -f plugin_start >/dev/null 2>&1; then
            plugin_start
        else
            echo 'No plugin_start function found'
            exit 0
        fi
    " 2>&1); then
        # Set active state
        set_plugin_state "$plugin_name" "$PLUGIN_STATE_ACTIVE"
        aa_set "plugin_start_time" "$plugin_name" "$(date '+%s')"
        
        # Create PID file if plugin runs background processes
        _create_plugin_pid_file "$plugin_name"
        
        _lifecycle_log "SUCCESS" "Plugin started: $plugin_name"
        _emit_lifecycle_event "plugin.started" "$plugin_name" "{\"result\": \"success\"}"
        
        # Schedule health checks
        _schedule_health_check "$plugin_name"
        
        return 0
    else
        # Set error state
        set_plugin_state "$plugin_name" "$PLUGIN_STATE_ERROR"
        _increment_error_count "$plugin_name"
        
        _lifecycle_log "ERROR" "Plugin start failed: $plugin_name - $start_result"
        _emit_lifecycle_event "plugin.start_failed" "$plugin_name" "{\"error\": \"$start_result\"}"
        
        return 1
    fi
}

# =============================================================================
# PLUGIN SHUTDOWN MANAGEMENT
# =============================================================================

# Stop plugin
# Usage: stop_plugin plugin_name [timeout] [force]
stop_plugin() {
    local plugin_name="$1"
    local timeout="${2:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    local force="${3:-false}"
    
    _lifecycle_log "INFO" "Stopping plugin: $plugin_name (force: $force)"
    
    # Check if plugin is active
    local current_state
    current_state=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_state" != "$PLUGIN_STATE_ACTIVE" ]]; then
        _lifecycle_log "WARNING" "Plugin not active: $plugin_name (current: $current_state)"
        if [[ "$current_state" == "$PLUGIN_STATE_STOPPED" ]]; then
            return 0  # Already stopped
        fi
    fi
    
    # Set stopping state
    if ! set_plugin_state "$plugin_name" "$PLUGIN_STATE_STOPPING"; then
        if [[ "$force" == "true" ]]; then
            _lifecycle_log "WARNING" "Forcing state change for plugin: $plugin_name"
            aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_STOPPING"
        else
            return 1
        fi
    fi
    
    # Get plugin path
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Run plugin stop with timeout
    local stop_result
    if stop_result=$(timeout "$timeout" bash -c "
        source '$plugin_path'
        if declare -f plugin_stop >/dev/null 2>&1; then
            plugin_stop
        else
            echo 'No plugin_stop function found'
            exit 0
        fi
    " 2>&1); then
        # Set stopped state
        set_plugin_state "$plugin_name" "$PLUGIN_STATE_STOPPED"
        
        # Remove PID file
        _remove_plugin_pid_file "$plugin_name"
        
        # Cancel health checks
        _cancel_health_check "$plugin_name"
        
        _lifecycle_log "SUCCESS" "Plugin stopped: $plugin_name"
        _emit_lifecycle_event "plugin.stopped" "$plugin_name" "{\"result\": \"success\"}"
        
        return 0
    else
        if [[ "$force" == "true" ]]; then
            # Force stop by killing processes
            _force_stop_plugin "$plugin_name"
            set_plugin_state "$plugin_name" "$PLUGIN_STATE_STOPPED"
            
            _lifecycle_log "WARNING" "Plugin force stopped: $plugin_name"
            _emit_lifecycle_event "plugin.force_stopped" "$plugin_name" "{\"result\": \"forced\"}"
            
            return 0
        else
            # Set error state
            set_plugin_state "$plugin_name" "$PLUGIN_STATE_ERROR"
            _increment_error_count "$plugin_name"
            
            _lifecycle_log "ERROR" "Plugin stop failed: $plugin_name - $stop_result"
            _emit_lifecycle_event "plugin.stop_failed" "$plugin_name" "{\"error\": \"$stop_result\"}"
            
            return 1
        fi
    fi
}

# Force stop plugin by killing associated processes
# Usage: _force_stop_plugin plugin_name
_force_stop_plugin() {
    local plugin_name="$1"
    local pid_file="$PLUGIN_PID_DIR/${plugin_name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        
        if kill -0 "$pid" 2>/dev/null; then
            _lifecycle_log "INFO" "Killing plugin process: $plugin_name (PID: $pid)"
            
            # Try TERM first, then KILL
            kill -TERM "$pid" 2>/dev/null
            sleep 2
            
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null
            fi
        fi
        
        rm -f "$pid_file"
    fi
    
    # Kill any processes matching plugin name pattern
    pkill -f "$plugin_name" 2>/dev/null || true
}

# =============================================================================
# PLUGIN RESTART MANAGEMENT
# =============================================================================

# Restart plugin
# Usage: restart_plugin plugin_name [stop_timeout] [start_timeout]
restart_plugin() {
    local plugin_name="$1"
    local stop_timeout="${2:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    local start_timeout="${3:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    
    _lifecycle_log "INFO" "Restarting plugin: $plugin_name"
    
    # Stop plugin first
    if ! stop_plugin "$plugin_name" "$stop_timeout"; then
        _lifecycle_log "WARNING" "Plugin stop failed during restart, attempting force stop"
        stop_plugin "$plugin_name" "$stop_timeout" "true"
    fi
    
    # Wait a moment for cleanup
    sleep 1
    
    # Start plugin
    if start_plugin "$plugin_name" "$start_timeout"; then
        _lifecycle_log "SUCCESS" "Plugin restarted successfully: $plugin_name"
        _emit_lifecycle_event "plugin.restarted" "$plugin_name" "{\"result\": \"success\"}"
        return 0
    else
        _lifecycle_log "ERROR" "Plugin restart failed: $plugin_name"
        _emit_lifecycle_event "plugin.restart_failed" "$plugin_name" "{\"result\": \"failed\"}"
        return 1
    fi
}

# =============================================================================
# PLUGIN HEALTH MONITORING
# =============================================================================

# Schedule health check for plugin
# Usage: _schedule_health_check plugin_name
_schedule_health_check() {
    local plugin_name="$1"
    
    # This would integrate with a proper job scheduler in production
    # For now, just mark that health checks should be performed
    aa_set "plugin_last_health_check" "$plugin_name" "$(date '+%s')"
    
    _lifecycle_log "DEBUG" "Health check scheduled for plugin: $plugin_name"
}

# Cancel health check for plugin
# Usage: _cancel_health_check plugin_name
_cancel_health_check() {
    local plugin_name="$1"
    
    aa_delete "plugin_last_health_check" "$plugin_name" 2>/dev/null || true
    
    _lifecycle_log "DEBUG" "Health check cancelled for plugin: $plugin_name"
}

# Run health check for plugin
# Usage: run_plugin_health_check plugin_name
run_plugin_health_check() {
    local plugin_name="$1"
    
    # Check if plugin is in a healthy state
    local current_state
    current_state=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_state" != "$PLUGIN_STATE_ACTIVE" ]]; then
        echo '{"status": "inactive", "healthy": false, "message": "Plugin not active"}'
        return 1
    fi
    
    # Get plugin path
    local plugin_path
    plugin_path=$(aa_get "plugin_registry" "$plugin_name")
    
    # Run plugin health check
    local health_result
    if health_result=$(
        source "$plugin_path"
        if declare -f plugin_health_check >/dev/null 2>&1; then
            plugin_health_check
        else
            echo '{"status": "healthy", "message": "No health check function available"}'
        fi
    ); then
        # Update last health check time
        aa_set "plugin_last_health_check" "$plugin_name" "$(date '+%s')"
        
        # Parse health status
        local health_status
        health_status=$(echo "$health_result" | grep -o '"status": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
        
        if [[ "$health_status" == "unhealthy" ]]; then
            _increment_error_count "$plugin_name"
            _lifecycle_log "WARNING" "Plugin health check failed: $plugin_name"
            _emit_lifecycle_event "plugin.health_check_failed" "$plugin_name" "$health_result"
            return 2
        fi
        
        echo "$health_result"
        return 0
    else
        _increment_error_count "$plugin_name"
        _lifecycle_log "ERROR" "Plugin health check error: $plugin_name"
        echo '{"status": "error", "healthy": false, "message": "Health check execution failed"}'
        return 1
    fi
}

# Run health checks for all active plugins
# Usage: run_all_plugin_health_checks
run_all_plugin_health_checks() {
    local healthy_count=0
    local unhealthy_count=0
    local error_count=0
    
    _lifecycle_log "INFO" "Running health checks for all active plugins"
    
    # Check all plugins
    while IFS= read -r plugin_name; do
        if [[ -n "$plugin_name" ]]; then
            local current_state
            current_state=$(aa_get "plugin_status" "$plugin_name")
            
            if [[ "$current_state" == "$PLUGIN_STATE_ACTIVE" ]]; then
                local health_check_result
                health_check_result=$(run_plugin_health_check "$plugin_name")
                local health_check_status=$?
                
                case $health_check_status in
                    0) healthy_count=$((healthy_count + 1)) ;;
                    2) unhealthy_count=$((unhealthy_count + 1)) ;;
                    *) error_count=$((error_count + 1)) ;;
                esac
            fi
        fi
    done < <(aa_keys "plugin_registry")
    
    _lifecycle_log "INFO" "Health check summary: $healthy_count healthy, $unhealthy_count unhealthy, $error_count errors"
    
    # Return non-zero if any plugins are unhealthy or have errors
    if [[ $unhealthy_count -gt 0 ]] || [[ $error_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN ERROR HANDLING
# =============================================================================

# Increment error count for plugin
# Usage: _increment_error_count plugin_name
_increment_error_count() {
    local plugin_name="$1"
    local current_count
    current_count=$(aa_get "plugin_error_count" "$plugin_name" "0")
    local new_count=$((current_count + 1))
    
    aa_set "plugin_error_count" "$plugin_name" "$new_count"
    
    _lifecycle_log "WARNING" "Error count incremented for plugin $plugin_name: $new_count"
    
    # Check if error threshold exceeded
    local error_threshold="${UNITY_PLUGIN_ERROR_THRESHOLD:-5}"
    if [[ $new_count -ge $error_threshold ]]; then
        _lifecycle_log "ERROR" "Error threshold exceeded for plugin: $plugin_name ($new_count >= $error_threshold)"
        _emit_lifecycle_event "plugin.error_threshold_exceeded" "$plugin_name" "{\"error_count\": $new_count, \"threshold\": $error_threshold}"
        
        # Disable plugin if too many errors
        disable_plugin "$plugin_name"
    fi
}

# Reset error count for plugin
# Usage: reset_plugin_error_count plugin_name
reset_plugin_error_count() {
    local plugin_name="$1"
    
    aa_set "plugin_error_count" "$plugin_name" "0"
    _lifecycle_log "INFO" "Error count reset for plugin: $plugin_name"
}

# Disable plugin due to errors
# Usage: disable_plugin plugin_name
disable_plugin() {
    local plugin_name="$1"
    
    _lifecycle_log "WARNING" "Disabling plugin due to errors: $plugin_name"
    
    # Stop plugin if active
    local current_state
    current_state=$(aa_get "plugin_status" "$plugin_name")
    
    if [[ "$current_state" == "$PLUGIN_STATE_ACTIVE" ]]; then
        stop_plugin "$plugin_name" 10 "true"  # Force stop with short timeout
    fi
    
    # Set disabled state
    aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_DISABLED"
    
    _emit_lifecycle_event "plugin.disabled" "$plugin_name" "{\"reason\": \"error_threshold_exceeded\"}"
}

# Enable previously disabled plugin
# Usage: enable_plugin plugin_name
enable_plugin() {
    local plugin_name="$1"
    
    _lifecycle_log "INFO" "Enabling plugin: $plugin_name"
    
    # Reset error count
    reset_plugin_error_count "$plugin_name"
    
    # Set to unloaded state so it can be loaded again
    aa_set "plugin_status" "$plugin_name" "$PLUGIN_STATE_UNLOADED"
    
    _emit_lifecycle_event "plugin.enabled" "$plugin_name" "{\"result\": \"enabled\"}"
}

# =============================================================================
# PLUGIN PID MANAGEMENT
# =============================================================================

# Create PID file for plugin
# Usage: _create_plugin_pid_file plugin_name
_create_plugin_pid_file() {
    local plugin_name="$1"
    local pid_file="$PLUGIN_PID_DIR/${plugin_name}.pid"
    
    # Store the current shell PID (plugins run in subshells)
    echo "$$" > "$pid_file"
    
    _lifecycle_log "DEBUG" "Created PID file for plugin: $plugin_name (PID: $$)"
}

# Remove PID file for plugin
# Usage: _remove_plugin_pid_file plugin_name
_remove_plugin_pid_file() {
    local plugin_name="$1"
    local pid_file="$PLUGIN_PID_DIR/${plugin_name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        rm -f "$pid_file"
        _lifecycle_log "DEBUG" "Removed PID file for plugin: $plugin_name"
    fi
}

# =============================================================================
# BATCH OPERATIONS
# =============================================================================

# Start all loaded plugins
# Usage: start_all_plugins [timeout]
start_all_plugins() {
    local timeout="${1:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    local started_count=0
    local failed_count=0
    
    _lifecycle_log "INFO" "Starting all loaded plugins"
    
    # Get plugins sorted by priority
    local plugins_by_priority=()
    
    while IFS= read -r plugin_name; do
        if [[ -n "$plugin_name" ]]; then
            local current_state
            current_state=$(aa_get "plugin_status" "$plugin_name")
            
            if [[ "$current_state" == "$PLUGIN_STATE_LOADED" ]] || [[ "$current_state" == "$PLUGIN_STATE_INITIALIZED" ]] || [[ "$current_state" == "$PLUGIN_STATE_STOPPED" ]]; then
                local metadata
                metadata=$(aa_get "plugin_metadata" "$plugin_name")
                local priority
                priority=$(echo "$metadata" | grep -o '"priority": [0-9]*' | cut -d':' -f2 | tr -d ' ' || echo "50")
                
                plugins_by_priority+=("$priority:$plugin_name")
            fi
        fi
    done < <(aa_keys "plugin_registry")
    
    # Sort by priority (descending)
    IFS=$'\n' plugins_by_priority=($(sort -t: -k1 -nr <<< "${plugins_by_priority[*]}"))
    
    # Start plugins in priority order
    for plugin_entry in "${plugins_by_priority[@]}"; do
        local plugin_name="${plugin_entry#*:}"
        
        if start_plugin "$plugin_name" "$timeout"; then
            started_count=$((started_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done
    
    _lifecycle_log "INFO" "Started $started_count plugins, $failed_count failed"
    
    return $failed_count
}

# Stop all active plugins
# Usage: stop_all_plugins [timeout] [force]
stop_all_plugins() {
    local timeout="${1:-$PLUGIN_LIFECYCLE_TIMEOUT}"
    local force="${2:-false}"
    local stopped_count=0
    local failed_count=0
    
    _lifecycle_log "INFO" "Stopping all active plugins (force: $force)"
    
    # Get active plugins (reverse priority order for shutdown)
    local plugins_by_priority=()
    
    while IFS= read -r plugin_name; do
        if [[ -n "$plugin_name" ]]; then
            local current_state
            current_state=$(aa_get "plugin_status" "$plugin_name")
            
            if [[ "$current_state" == "$PLUGIN_STATE_ACTIVE" ]] || [[ "$current_state" == "$PLUGIN_STATE_STARTING" ]]; then
                local metadata
                metadata=$(aa_get "plugin_metadata" "$plugin_name")
                local priority
                priority=$(echo "$metadata" | grep -o '"priority": [0-9]*' | cut -d':' -f2 | tr -d ' ' || echo "50")
                
                plugins_by_priority+=("$priority:$plugin_name")
            fi
        fi
    done < <(aa_keys "plugin_registry")
    
    # Sort by priority (ascending for shutdown)
    IFS=$'\n' plugins_by_priority=($(sort -t: -k1 -n <<< "${plugins_by_priority[*]}"))
    
    # Stop plugins in reverse priority order
    for plugin_entry in "${plugins_by_priority[@]}"; do
        local plugin_name="${plugin_entry#*:}"
        
        if stop_plugin "$plugin_name" "$timeout" "$force"; then
            stopped_count=$((stopped_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done
    
    _lifecycle_log "INFO" "Stopped $stopped_count plugins, $failed_count failed"
    
    return $failed_count
}

# =============================================================================
# LIFECYCLE EVENT HANDLING
# =============================================================================

# Emit lifecycle event
# Usage: _emit_lifecycle_event event_type plugin_name data
_emit_lifecycle_event() {
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
  "source": "plugin-lifecycle",
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: $event_type for $plugin_name" >> "$PLUGIN_LIFECYCLE_LOG"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Lifecycle logging
# Usage: _lifecycle_log level message [extra_data]
_lifecycle_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format log message
    local log_entry="$timestamp [$level] [PluginLifecycle] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to lifecycle log
    echo "$log_entry" >> "$PLUGIN_LIFECYCLE_LOG"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "PluginLifecycle: $message"
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

# Get lifecycle status summary
get_plugin_lifecycle_status() {
    local total_plugins
    total_plugins=$(aa_size "plugin_registry")
    
    local state_counts
    declare -A state_counts=(
        ["unloaded"]=0
        ["loaded"]=0
        ["initialized"]=0
        ["active"]=0
        ["stopped"]=0
        ["error"]=0
        ["disabled"]=0
    )
    
    if [[ $total_plugins -gt 0 ]]; then
        while IFS= read -r plugin_name; do
            if [[ -n "$plugin_name" ]]; then
                local state
                state=$(aa_get "plugin_status" "$plugin_name")
                case "$state" in
                    "$PLUGIN_STATE_UNLOADED") state_counts["unloaded"]=$((${state_counts["unloaded"]} + 1)) ;;
                    "$PLUGIN_STATE_LOADED") state_counts["loaded"]=$((${state_counts["loaded"]} + 1)) ;;
                    "$PLUGIN_STATE_INITIALIZED") state_counts["initialized"]=$((${state_counts["initialized"]} + 1)) ;;
                    "$PLUGIN_STATE_ACTIVE") state_counts["active"]=$((${state_counts["active"]} + 1)) ;;
                    "$PLUGIN_STATE_STOPPED") state_counts["stopped"]=$((${state_counts["stopped"]} + 1)) ;;
                    "$PLUGIN_STATE_ERROR") state_counts["error"]=$((${state_counts["error"]} + 1)) ;;
                    "$PLUGIN_STATE_DISABLED") state_counts["disabled"]=$((${state_counts["disabled"]} + 1)) ;;
                esac
            fi
        done < <(aa_keys "plugin_registry")
    fi
    
    cat <<EOF
{
  "lifecycle_version": "$UNITY_PLUGIN_LIFECYCLE_VERSION",
  "total_plugins": $total_plugins,
  "state_counts": {
    "unloaded": ${state_counts["unloaded"]},
    "loaded": ${state_counts["loaded"]},
    "initialized": ${state_counts["initialized"]},
    "active": ${state_counts["active"]},
    "stopped": ${state_counts["stopped"]},
    "error": ${state_counts["error"]},
    "disabled": ${state_counts["disabled"]}
  },
  "state_dir": "$PLUGIN_LIFECYCLE_STATE_DIR",
  "log_file": "$PLUGIN_LIFECYCLE_LOG"
}
EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all lifecycle management functions
export -f init_plugin_lifecycle
export -f validate_state_transition
export -f set_plugin_state
export -f get_plugin_lifecycle_history
export -f initialize_plugin
export -f start_plugin
export -f stop_plugin
export -f restart_plugin
export -f run_plugin_health_check
export -f run_all_plugin_health_checks
export -f reset_plugin_error_count
export -f disable_plugin
export -f enable_plugin
export -f start_all_plugins
export -f stop_all_plugins
export -f get_plugin_lifecycle_status

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize lifecycle management when sourced
if [[ -z "${UNITY_PLUGIN_LIFECYCLE_INITIALIZED:-}" ]]; then
    init_plugin_lifecycle
    export UNITY_PLUGIN_LIFECYCLE_INITIALIZED=true
fi

# If sourced directly, show lifecycle information
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Plugin Lifecycle Management v$UNITY_PLUGIN_LIFECYCLE_VERSION"
    echo "Lifecycle timeout: $PLUGIN_LIFECYCLE_TIMEOUT seconds"
    echo "Health check interval: $PLUGIN_HEALTH_CHECK_INTERVAL seconds"
    echo ""
    echo "Use start_plugin <name> to start a plugin"
    echo "Use stop_plugin <name> to stop a plugin"
    echo "Use restart_plugin <name> to restart a plugin"
    echo "Use run_plugin_health_check <name> to check plugin health"
fi