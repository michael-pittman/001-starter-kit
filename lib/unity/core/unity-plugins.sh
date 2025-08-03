#!/bin/bash
# Unity Plugin System - Plugin Loader and Management

set -euo pipefail

UNITY_PLUGINS_DIR="${UNITY_PLUGINS_DIR:-./lib/unity/plugins}"
UNITY_PLUGIN_STATE=".unity/state/plugins.txt"

# Initialize plugin system
unity_init_plugins() {
    mkdir -p "$UNITY_PLUGINS_DIR" "$(dirname "$UNITY_PLUGIN_STATE")"
    
    echo "# Unity Plugin Registry" > "$UNITY_PLUGIN_STATE"
    echo "# Format: PLUGIN_NAME:STATUS:PATH:VERSION" >> "$UNITY_PLUGIN_STATE"
    
    unity_log "SUCCESS" "✅ Plugin system initialized"
}

# Load a plugin
unity_load_plugin() {
    local plugin_name=$1
    local plugin_dir="$UNITY_PLUGINS_DIR/$plugin_name"
    
    if [[ ! -d "$plugin_dir" ]]; then
        unity_log "ERROR" "❌ Plugin not found: $plugin_name"
        return $UNITY_ERROR_VALIDATION
    fi
    
    local plugin_main="$plugin_dir/plugin.sh"
    if [[ -f "$plugin_main" ]]; then
        source "$plugin_main"
        echo "$plugin_name:loaded:$plugin_dir:1.0" >> "$UNITY_PLUGIN_STATE"
        unity_log "SUCCESS" "🔌 Plugin loaded: $plugin_name"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "❌ Plugin main file not found: $plugin_main"
        return $UNITY_ERROR_VALIDATION
    fi
}

# List available plugins
unity_list_plugins() {
    unity_log "INFO" "🔌 Available Plugins:"
    if [[ -d "$UNITY_PLUGINS_DIR" ]]; then
        for plugin_dir in "$UNITY_PLUGINS_DIR"/*; do
            if [[ -d "$plugin_dir" ]]; then
                local plugin_name=$(basename "$plugin_dir")
                unity_log "INFO" "  - $plugin_name"
            fi
        done
    else
        unity_log "INFO" "  No plugins directory found"
    fi
}

# Enable plugin
unity_enable_plugin() {
    local plugin_name=$1
    unity_load_plugin "$plugin_name"
}

# Export plugin functions
export -f unity_init_plugins
export -f unity_load_plugin
export -f unity_list_plugins
export -f unity_enable_plugin
