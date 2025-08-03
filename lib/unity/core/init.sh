#!/bin/bash
# Unity Core Initialization
# Central initialization point for the Unity system

# Get the directory where this script is located
UNITY_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITY_LIB_DIR="$(cd "$UNITY_CORE_DIR/.." && pwd)"

# Ensure log directory exists
export UNITY_LOG_DIR="${UNITY_LOG_DIR:-$UNITY_LIB_DIR/../../logs/unity}"
mkdir -p "$UNITY_LOG_DIR" 2>/dev/null || {
    # Fallback to relative path
    export UNITY_LOG_DIR="./logs/unity"
    mkdir -p "$UNITY_LOG_DIR" 2>/dev/null
}

# Load core components in order
source "$UNITY_CORE_DIR/unity-core.sh" || {
    echo "Error: Failed to load unity-core.sh" >&2
    return 1
}

source "$UNITY_CORE_DIR/unity-events.sh" || {
    echo "Error: Failed to load unity-events.sh" >&2
    return 1
}

source "$UNITY_CORE_DIR/unity-plugins.sh" || {
    echo "Error: Failed to load unity-plugins.sh" >&2
    return 1
}

source "$UNITY_CORE_DIR/registry.sh" || {
    echo "Error: Failed to load registry.sh" >&2
    return 1
}

# Initialize the event system
unity_init_events || {
    echo "Warning: Event system initialization failed" >&2
}

# Create compatibility function
unity_register_handler() {
    unity_on_event "$@"
}

# Export core functions
export -f unity_emit_event 2>/dev/null
export -f unity_on_event 2>/dev/null
export -f unity_register_handler 2>/dev/null
export -f unity_register_service 2>/dev/null
export -f unity_load_plugin 2>/dev/null

# Set initialization flag
export UNITY_INITIALIZED=true

return 0