#!/usr/bin/env bash
# =============================================================================
# Deployment State Management Module
# Manages deployment state and persistence
# =============================================================================

# Prevent multiple sourcing
[ -n "${_DEPLOYMENT_STATE_SH_LOADED:-}" ] && return 0
_DEPLOYMENT_STATE_SH_LOADED=1

# =============================================================================
# STATE CONFIGURATION
# =============================================================================

# State file configuration
STATE_FILE_DIR="${CONFIG_DIR:-./config}/state"
STATE_FILE="${STATE_FILE_DIR}/deployment-state.json"
STATE_BACKUP_DIR="${STATE_FILE_DIR}/backups"

# State file structure
STATE_FILE_TEMPLATE='{
    "metadata": {
        "version": "1.0.0",
        "created": "",
        "last_modified": ""
    },
    "deployments": {},
    "stacks": {},
    "resources": {},
    "history": []
}'

# =============================================================================
# STATE MANAGEMENT FUNCTIONS
# =============================================================================

# Initialize state management
init_state_management() {
    local stack_name="${1:-}"
    
    log_info "Initializing state management" "STATE"
    
    # Create state directory
    mkdir -p "$STATE_FILE_DIR"
    mkdir -p "$STATE_BACKUP_DIR"
    
    # Initialize state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "$STATE_FILE_TEMPLATE" | jq --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg modified "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.metadata.created = $created | .metadata.last_modified = $modified' > "$STATE_FILE"
        log_info "State file initialized: $STATE_FILE" "STATE"
    fi
    
    # Initialize stack state if provided
    if [[ -n "$stack_name" ]]; then
        init_stack_state "$stack_name"
    fi
    
    log_info "State management initialized" "STATE"
}

# Initialize stack state
init_stack_state() {
    local stack_name="$1"
    
    log_info "Initializing stack state: $stack_name" "STATE"
    
    # Check if stack state already exists
    if stack_state_exists "$stack_name"; then
        log_warn "Stack state already exists: $stack_name" "STATE"
        return 0
    fi
    
    # Create stack state entry
    local stack_state='{
        "name": "'$stack_name'",
        "status": "initializing",
        "created": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "last_modified": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "resources": {},
        "deployments": [],
        "variables": {}
    }'
    
    # Add stack state to state file
    jq --arg stack "$stack_name" --argjson state "$stack_state" '.stacks[$stack] = $state' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log_info "Stack state initialized: $stack_name" "STATE"
}

# Set deployment state
set_deployment_state() {
    local stack_name="$1"
    local state="$2"
    local details="${3:-}"
    
    log_info "Setting deployment state: $stack_name -> $state" "STATE"
    
    # Update stack state
    local update_query='.stacks[$stack].status = $state | .stacks[$stack].last_modified = $timestamp'
    
    if [[ -n "$details" ]]; then
        update_query='.stacks[$stack].status = $state | .stacks[$stack].last_modified = $timestamp | .stacks[$stack].details = $details'
    fi
    
    jq --arg stack "$stack_name" \
       --arg state "$state" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg details "$details" \
       "$update_query" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    # Add to deployment history
    add_deployment_history "$stack_name" "$state" "$details"
    
    log_info "Deployment state updated: $stack_name -> $state" "STATE"
}

# Get deployment state
get_deployment_state() {
    local stack_name="$1"
    
    if stack_state_exists "$stack_name"; then
        jq -r --arg stack "$stack_name" '.stacks[$stack].status' "$STATE_FILE" 2>/dev/null
    else
        echo "not_found"
    fi
}

# Check if stack state exists
stack_state_exists() {
    local stack_name="$1"
    
    jq -e --arg stack "$stack_name" '.stacks[$stack]' "$STATE_FILE" >/dev/null 2>&1
}

# Add deployment history
add_deployment_history() {
    local stack_name="$1"
    local state="$2"
    local details="${3:-}"
    
    local history_entry='{
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "state": "'$state'",
        "details": "'$details'"
    }'
    
    # Add to stack history
    jq --arg stack "$stack_name" \
       --argjson entry "$history_entry" \
       '.stacks[$stack].deployments += [$entry]' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    # Add to global history
    jq --argjson entry "$history_entry" \
       --arg stack "$stack_name" \
       '.history += [$entry + {"stack": $stack}]' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Add resource to stack state
add_resource_to_state() {
    local stack_name="$1"
    local resource_type="$2"
    local resource_id="$3"
    local resource_data="${4:-}"
    
    log_info "Adding resource to state: $stack_name -> $resource_type:$resource_id" "STATE"
    
    local resource_entry='{
        "id": "'$resource_id'",
        "type": "'$resource_type'",
        "created": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "data": '$resource_data'
    }'
    
    jq --arg stack "$stack_name" \
       --arg type "$resource_type" \
       --argjson entry "$resource_entry" \
       '.stacks[$stack].resources[$type] = $entry' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log_info "Resource added to state: $resource_type:$resource_id" "STATE"
}

# Remove resource from state
remove_resource_from_state() {
    local stack_name="$1"
    local resource_type="$2"
    
    log_info "Removing resource from state: $stack_name -> $resource_type" "STATE"
    
    jq --arg stack "$stack_name" \
       --arg type "$resource_type" \
       'del(.stacks[$stack].resources[$type])' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log_info "Resource removed from state: $resource_type" "STATE"
}

# Get resource from state
get_resource_from_state() {
    local stack_name="$1"
    local resource_type="$2"
    
    if stack_state_exists "$stack_name"; then
        jq -r --arg stack "$stack_name" --arg type "$resource_type" '.stacks[$stack].resources[$type].id // empty' "$STATE_FILE" 2>/dev/null
    fi
}

# List stack resources
list_stack_resources() {
    local stack_name="$1"
    
    if stack_state_exists "$stack_name"; then
        jq -r --arg stack "$stack_name" '.stacks[$stack].resources | to_entries[] | "\(.key): \(.value.id)"' "$STATE_FILE" 2>/dev/null
    fi
}

# Set stack variable
set_stack_variable() {
    local stack_name="$1"
    local variable_name="$2"
    local variable_value="$3"
    
    log_info "Setting stack variable: $stack_name -> $variable_name" "STATE"
    
    jq --arg stack "$stack_name" \
       --arg name "$variable_name" \
       --arg value "$variable_value" \
       '.stacks[$stack].variables[$name] = $value' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Get stack variable
get_stack_variable() {
    local stack_name="$1"
    local variable_name="$2"
    
    if stack_state_exists "$stack_name"; then
        jq -r --arg stack "$stack_name" --arg name "$variable_name" '.stacks[$stack].variables[$name] // empty' "$STATE_FILE" 2>/dev/null
    fi
}

# List stack variables
list_stack_variables() {
    local stack_name="$1"
    
    if stack_state_exists "$stack_name"; then
        jq -r --arg stack "$stack_name" '.stacks[$stack].variables | to_entries[] | "\(.key)=\(.value)"' "$STATE_FILE" 2>/dev/null
    fi
}

# Delete stack state
delete_stack_state() {
    local stack_name="$1"
    
    log_info "Deleting stack state: $stack_name" "STATE"
    
    # Create backup before deletion
    create_state_backup "$stack_name"
    
    # Remove stack from state file
    jq --arg stack "$stack_name" 'del(.stacks[$stack])' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log_info "Stack state deleted: $stack_name" "STATE"
}

# Create state backup
create_state_backup() {
    local stack_name="${1:-}"
    local backup_file
    
    if [[ -n "$stack_name" ]]; then
        backup_file="${STATE_BACKUP_DIR}/state-${stack_name}-$(date +%Y%m%d-%H%M%S).json"
    else
        backup_file="${STATE_BACKUP_DIR}/state-full-$(date +%Y%m%d-%H%M%S).json"
    fi
    
    log_info "Creating state backup: $backup_file" "STATE"
    
    if [[ -n "$stack_name" ]]; then
        # Backup specific stack
        jq --arg stack "$stack_name" '.stacks[$stack]' "$STATE_FILE" > "$backup_file"
    else
        # Backup entire state file
        cp "$STATE_FILE" "$backup_file"
    fi
    
    log_info "State backup created: $backup_file" "STATE"
}

# Restore state from backup
restore_state_from_backup() {
    local backup_file="$1"
    local stack_name="${2:-}"
    
    log_info "Restoring state from backup: $backup_file" "STATE"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file" "STATE"
        return 1
    fi
    
    if [[ -n "$stack_name" ]]; then
        # Restore specific stack
        local stack_data
        stack_data=$(jq --arg stack "$stack_name" '.stacks[$stack]' "$backup_file" 2>/dev/null)
        
        if [[ -n "$stack_data" ]]; then
            jq --arg stack "$stack_name" --argjson data "$stack_data" '.stacks[$stack] = $data' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            log_info "Stack state restored: $stack_name" "STATE"
            return 0
        else
            log_error "Stack not found in backup: $stack_name" "STATE"
            return 1
        fi
    else
        # Restore entire state file
        cp "$backup_file" "$STATE_FILE"
        log_info "Full state restored from backup" "STATE"
        return 0
    fi
}

# List all stacks
list_all_stacks() {
    jq -r '.stacks | keys[]' "$STATE_FILE" 2>/dev/null
}

# Get stack summary
get_stack_summary() {
    local stack_name="$1"
    
    if stack_state_exists "$stack_name"; then
        jq --arg stack "$stack_name" '.stacks[$stack] | {
            name: .name,
            status: .status,
            created: .created,
            last_modified: .last_modified,
            resource_count: (.resources | length),
            deployment_count: (.deployments | length)
        }' "$STATE_FILE" 2>/dev/null
    fi
}

# Get deployment history
get_deployment_history() {
    local stack_name="${1:-}"
    
    if [[ -n "$stack_name" ]]; then
        # Get history for specific stack
        if stack_state_exists "$stack_name"; then
            jq --arg stack "$stack_name" '.stacks[$stack].deployments' "$STATE_FILE" 2>/dev/null
        fi
    else
        # Get global history
        jq '.history' "$STATE_FILE" 2>/dev/null
    fi
}

# Clean up old backups
cleanup_old_backups() {
    local max_age_days="${1:-30}"
    
    log_info "Cleaning up backups older than $max_age_days days" "STATE"
    
    find "$STATE_BACKUP_DIR" -name "*.json" -type f -mtime +$max_age_days -delete
    
    log_info "Backup cleanup completed" "STATE"
}

# Validate state file
validate_state_file() {
    log_info "Validating state file: $STATE_FILE" "STATE"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "State file not found: $STATE_FILE" "STATE"
        return 1
    fi
    
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        log_error "Invalid JSON in state file: $STATE_FILE" "STATE"
        return 1
    fi
    
    log_info "State file validation passed" "STATE"
    return 0
}

# Export state to file
export_state() {
    local output_file="$1"
    local stack_name="${2:-}"
    
    log_info "Exporting state to: $output_file" "STATE"
    
    if [[ -n "$stack_name" ]]; then
        # Export specific stack
        if stack_state_exists "$stack_name"; then
            jq --arg stack "$stack_name" '.stacks[$stack]' "$STATE_FILE" > "$output_file"
        else
            log_error "Stack not found: $stack_name" "STATE"
            return 1
        fi
    else
        # Export entire state
        cp "$STATE_FILE" "$output_file"
    fi
    
    log_info "State exported to: $output_file" "STATE"
}

# Import state from file
import_state() {
    local input_file="$1"
    local stack_name="${2:-}"
    
    log_info "Importing state from: $input_file" "STATE"
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Input file not found: $input_file" "STATE"
        return 1
    fi
    
    if ! jq empty "$input_file" 2>/dev/null; then
        log_error "Invalid JSON in input file: $input_file" "STATE"
        return 1
    fi
    
    if [[ -n "$stack_name" ]]; then
        # Import specific stack
        local stack_data
        stack_data=$(jq '.' "$input_file" 2>/dev/null)
        
        if [[ -n "$stack_data" ]]; then
            jq --arg stack "$stack_name" --argjson data "$stack_data" '.stacks[$stack] = $data' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            log_info "Stack state imported: $stack_name" "STATE"
            return 0
        else
            log_error "Invalid stack data in input file" "STATE"
            return 1
        fi
    else
        # Import entire state
        cp "$input_file" "$STATE_FILE"
        log_info "Full state imported from: $input_file" "STATE"
        return 0
    fi
} 