#!/usr/bin/env bash
# State Management Compatibility Wrapper
# Provides backward compatibility for old state management functions

# Source unified state manager
source "$(dirname "${BASH_SOURCE[0]}")/unified-state-manager.sh"

# =============================================================================
# COMPATIBILITY ALIASES AND FUNCTIONS
# =============================================================================

# deployment-state-manager.sh compatibility
init_deployment_state() {
    init_state_management "$@"
}

start_deployment() {
    local deployment_id="$1"
    CURRENT_DEPLOYMENT_ID="$deployment_id"
    transition_phase "$PHASE_PREPARING"
}

update_deployment_phase() {
    local phase="$1"
    transition_phase "$phase"
}

get_deployment_status() {
    get_current_phase
}

# enhanced-deployment-state.sh compatibility
load_deployment_state() {
    # No-op - state is loaded automatically
    return 0
}

save_deployment_state() {
    # No-op - state is saved automatically
    return 0
}

backup_deployment_state() {
    create_state_backup "$(get_state_file_path)"
}

# State getters/setters compatibility
get_stack_state() {
    local stack="$1"
    local key="$2"
    CURRENT_STACK_NAME="$stack" get_state "$key" "$STATE_SCOPE_STACK"
}

set_stack_state() {
    local stack="$1"
    local key="$2"
    local value="$3"
    CURRENT_STACK_NAME="$stack" set_state "$key" "$value" "$STATE_SCOPE_STACK"
}

update_resource_state() {
    local resource="$1"
    local key="$2"
    local value="$3"
    set_state "$key" "$value" "$STATE_SCOPE_RESOURCE" "$resource"
}

# deployment-state-json-helpers.sh compatibility
export_deployment_to_json() {
    get_state_summary "$@"
}

import_deployment_from_json() {
    log_warning "import_deployment_from_json is deprecated - use restore functionality"
    return 0
}

# Export compatibility functions
export -f init_deployment_state
export -f start_deployment
export -f update_deployment_phase
export -f get_deployment_status
export -f load_deployment_state
export -f save_deployment_state
export -f backup_deployment_state
export -f get_stack_state
export -f set_stack_state
export -f update_resource_state
export -f export_deployment_to_json
export -f import_deployment_from_json
