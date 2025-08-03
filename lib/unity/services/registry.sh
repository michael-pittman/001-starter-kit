#!/bin/bash
# Unity Service Registry
# Manages service registration and dependencies

# Get the core registry functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/registry.sh" || {
    echo "Error: Failed to load core registry.sh" >&2
    return 1
}

# Additional service-specific registry functions can be added here

# Service states
UNITY_SERVICE_STATE_STOPPED="stopped"
UNITY_SERVICE_STATE_STARTING="starting"
UNITY_SERVICE_STATE_ACTIVE="active"
UNITY_SERVICE_STATE_STOPPING="stopping"
UNITY_SERVICE_STATE_FAILED="failed"

# Get service dependencies
unity_get_service_dependencies() {
    local service_name="$1"
    
    # This would query the registry for dependencies
    # For now, return empty
    echo ""
}

# Get service state
unity_get_service_state() {
    local service_name="$1"
    
    # Check if service is registered
    if unity_service_exists "$service_name"; then
        # For now, assume all registered services are active
        echo "$UNITY_SERVICE_STATE_ACTIVE"
    else
        echo "$UNITY_SERVICE_STATE_STOPPED"
    fi
}

return 0