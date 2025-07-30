#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Unified State Management System
# Single source of truth for all deployment state
# =============================================================================

# Prevent multiple sourcing
if [[ "${UNIFIED_STATE_MANAGER_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly UNIFIED_STATE_MANAGER_LOADED=true

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Source unified error handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/unified-error-handling.sh" || {
    echo "ERROR: Failed to source unified error handling" >&2
    exit 1
}

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Version
readonly STATE_MANAGER_VERSION="3.0.0"

# State storage backends
readonly STATE_BACKEND_LOCAL="local"
readonly STATE_BACKEND_S3="s3"
readonly STATE_BACKEND_DYNAMODB="dynamodb"

# State scopes
readonly STATE_SCOPE_GLOBAL="global"
readonly STATE_SCOPE_STACK="stack"
readonly STATE_SCOPE_RESOURCE="resource"
readonly STATE_SCOPE_DEPLOYMENT="deployment"

# State file paths
readonly STATE_BASE_DIR="${STATE_BASE_DIR:-/tmp/geuse-state}"
readonly STATE_FILE_PREFIX="deployment-state"
readonly STATE_BACKUP_DIR="${STATE_BACKUP_DIR:-$STATE_BASE_DIR/backups}"
readonly STATE_LOCK_DIR="${STATE_LOCK_DIR:-$STATE_BASE_DIR/locks}"

# Configuration
STATE_BACKEND="${STATE_BACKEND:-$STATE_BACKEND_LOCAL}"
STATE_LOCK_TIMEOUT="${STATE_LOCK_TIMEOUT:-300}"  # 5 minutes
STATE_BACKUP_ENABLED="${STATE_BACKUP_ENABLED:-true}"
STATE_BACKUP_RETENTION="${STATE_BACKUP_RETENTION:-10}"
STATE_CHECKSUM_ENABLED="${STATE_CHECKSUM_ENABLED:-true}"

# Deployment phases
readonly PHASE_INITIALIZED="initialized"
readonly PHASE_VALIDATING="validating"
readonly PHASE_PREPARING="preparing"
readonly PHASE_PROVISIONING="provisioning"
readonly PHASE_CONFIGURING="configuring"
readonly PHASE_DEPLOYING="deploying"
readonly PHASE_VERIFYING="verifying"
readonly PHASE_READY="ready"
readonly PHASE_FAILED="failed"
readonly PHASE_ROLLING_BACK="rolling_back"
readonly PHASE_TERMINATED="terminated"

# Valid state transitions
declare -A VALID_TRANSITIONS
VALID_TRANSITIONS["$PHASE_INITIALIZED"]="$PHASE_VALIDATING"
VALID_TRANSITIONS["$PHASE_VALIDATING"]="$PHASE_PREPARING $PHASE_FAILED"
VALID_TRANSITIONS["$PHASE_PREPARING"]="$PHASE_PROVISIONING $PHASE_FAILED"
VALID_TRANSITIONS["$PHASE_PROVISIONING"]="$PHASE_CONFIGURING $PHASE_FAILED"
VALID_TRANSITIONS["$PHASE_CONFIGURING"]="$PHASE_DEPLOYING $PHASE_FAILED"
VALID_TRANSITIONS["$PHASE_DEPLOYING"]="$PHASE_VERIFYING $PHASE_FAILED"
VALID_TRANSITIONS["$PHASE_VERIFYING"]="$PHASE_READY $PHASE_FAILED"
VALID_TRANSITIONS["$PHASE_READY"]="$PHASE_CONFIGURING $PHASE_TERMINATED"
VALID_TRANSITIONS["$PHASE_FAILED"]="$PHASE_ROLLING_BACK $PHASE_TERMINATED"
VALID_TRANSITIONS["$PHASE_ROLLING_BACK"]="$PHASE_TERMINATED $PHASE_FAILED"

# Global state
CURRENT_STACK_NAME=""
CURRENT_DEPLOYMENT_ID=""
STATE_MODIFIED=false

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize state management
init_state_management() {
    local stack_name="${1:-}"
    local backend="${2:-$STATE_BACKEND}"
    
    # Set current stack
    if [[ -n "$stack_name" ]]; then
        CURRENT_STACK_NAME="$stack_name"
    fi
    
    # Set backend
    STATE_BACKEND="$backend"
    
    # Create directories
    mkdir -p "$STATE_BASE_DIR" "$STATE_BACKUP_DIR" "$STATE_LOCK_DIR"
    
    # Initialize backend
    case "$backend" in
        "$STATE_BACKEND_LOCAL")
            init_local_backend
            ;;
        "$STATE_BACKEND_S3")
            init_s3_backend
            ;;
        "$STATE_BACKEND_DYNAMODB")
            init_dynamodb_backend
            ;;
        *)
            throw_error $ERROR_INVALID_ARGUMENT "Unknown state backend: $backend"
            ;;
    esac
    
    # Generate deployment ID if not set
    if [[ -z "$CURRENT_DEPLOYMENT_ID" ]]; then
        CURRENT_DEPLOYMENT_ID="deploy-$(date +%s)-$$"
    fi
    
    log_error_internal "INFO" "State management initialized (backend: $backend, stack: ${CURRENT_STACK_NAME:-none})"
}

# Initialize local backend
init_local_backend() {
    # Ensure state file exists
    local state_file=$(get_state_file_path)
    
    if [[ ! -f "$state_file" ]]; then
        create_empty_state_file "$state_file"
    fi
    
    # Validate state file
    if ! validate_state_file "$state_file"; then
        log_error_internal "WARNING" "State file validation failed, creating new state"
        create_empty_state_file "$state_file"
    fi
}

# =============================================================================
# CORE STATE OPERATIONS
# =============================================================================

# Get state value
get_state() {
    local key="$1"
    local scope="${2:-$STATE_SCOPE_STACK}"
    local default="${3:-}"
    
    acquire_state_lock
    
    local value
    case "$scope" in
        "$STATE_SCOPE_GLOBAL")
            value=$(read_global_state "$key")
            ;;
        "$STATE_SCOPE_STACK")
            value=$(read_stack_state "$CURRENT_STACK_NAME" "$key")
            ;;
        "$STATE_SCOPE_RESOURCE")
            local resource="${4:-}"
            value=$(read_resource_state "$CURRENT_STACK_NAME" "$resource" "$key")
            ;;
        "$STATE_SCOPE_DEPLOYMENT")
            value=$(read_deployment_state "$CURRENT_DEPLOYMENT_ID" "$key")
            ;;
        *)
            release_state_lock
            throw_error $ERROR_INVALID_ARGUMENT "Invalid state scope: $scope"
            ;;
    esac
    
    release_state_lock
    
    echo "${value:-$default}"
}

# Set state value
set_state() {
    local key="$1"
    local value="$2"
    local scope="${3:-$STATE_SCOPE_STACK}"
    
    acquire_state_lock
    
    case "$scope" in
        "$STATE_SCOPE_GLOBAL")
            write_global_state "$key" "$value"
            ;;
        "$STATE_SCOPE_STACK")
            write_stack_state "$CURRENT_STACK_NAME" "$key" "$value"
            ;;
        "$STATE_SCOPE_RESOURCE")
            local resource="${4:-}"
            write_resource_state "$CURRENT_STACK_NAME" "$resource" "$key" "$value"
            ;;
        "$STATE_SCOPE_DEPLOYMENT")
            write_deployment_state "$CURRENT_DEPLOYMENT_ID" "$key" "$value"
            ;;
        *)
            release_state_lock
            throw_error $ERROR_INVALID_ARGUMENT "Invalid state scope: $scope"
            ;;
    esac
    
    STATE_MODIFIED=true
    
    # Save state if using local backend
    if [[ "$STATE_BACKEND" == "$STATE_BACKEND_LOCAL" ]]; then
        save_state_file
    fi
    
    release_state_lock
}

# Delete state value
delete_state() {
    local key="$1"
    local scope="${2:-$STATE_SCOPE_STACK}"
    
    acquire_state_lock
    
    local state_file=$(get_state_file_path)
    local temp_file="${state_file}.tmp"
    
    case "$scope" in
        "$STATE_SCOPE_GLOBAL")
            jq "del(.global.$key)" "$state_file" > "$temp_file"
            ;;
        "$STATE_SCOPE_STACK")
            jq "del(.stacks.\"$CURRENT_STACK_NAME\".$key)" "$state_file" > "$temp_file"
            ;;
        "$STATE_SCOPE_RESOURCE")
            local resource="${3:-}"
            jq "del(.stacks.\"$CURRENT_STACK_NAME\".resources.\"$resource\".$key)" "$state_file" > "$temp_file"
            ;;
        "$STATE_SCOPE_DEPLOYMENT")
            jq "del(.deployments.\"$CURRENT_DEPLOYMENT_ID\".$key)" "$state_file" > "$temp_file"
            ;;
    esac
    
    mv "$temp_file" "$state_file"
    STATE_MODIFIED=true
    
    release_state_lock
}

# =============================================================================
# PHASE MANAGEMENT
# =============================================================================

# Get current phase
get_current_phase() {
    local stack_name="${1:-$CURRENT_STACK_NAME}"
    
    if [[ -z "$stack_name" ]]; then
        echo "$PHASE_INITIALIZED"
        return
    fi
    
    get_state "phase" "$STATE_SCOPE_STACK" "$PHASE_INITIALIZED"
}

# Transition to new phase
transition_phase() {
    local new_phase="$1"
    local stack_name="${2:-$CURRENT_STACK_NAME}"
    
    if [[ -z "$stack_name" ]]; then
        throw_error $ERROR_INVALID_ARGUMENT "Stack name required for phase transition"
    fi
    
    # Get current phase
    local current_phase=$(get_current_phase "$stack_name")
    
    # Validate transition
    if ! validate_phase_transition "$current_phase" "$new_phase"; then
        throw_error $ERROR_VALIDATION_FAILED \
            "Invalid phase transition: $current_phase -> $new_phase"
    fi
    
    # Record transition
    local transition_record=$(cat <<EOF
{
    "from": "$current_phase",
    "to": "$new_phase",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment_id": "$CURRENT_DEPLOYMENT_ID"
}
EOF
)
    
    # Update phase
    set_state "phase" "$new_phase" "$STATE_SCOPE_STACK"
    
    # Add to transition history
    add_to_state_array "phase_transitions" "$transition_record" "$STATE_SCOPE_STACK"
    
    # Fire phase change event
    fire_state_event "phase_changed" "$transition_record"
    
    log_error_internal "INFO" "Phase transition: $current_phase -> $new_phase (stack: $stack_name)"
}

# Validate phase transition
validate_phase_transition() {
    local from_phase="$1"
    local to_phase="$2"
    
    # Always allow transition to failed or terminated
    if [[ "$to_phase" == "$PHASE_FAILED" ]] || [[ "$to_phase" == "$PHASE_TERMINATED" ]]; then
        return 0
    fi
    
    # Check valid transitions
    local valid_transitions="${VALID_TRANSITIONS[$from_phase]:-}"
    
    if [[ -z "$valid_transitions" ]]; then
        return 1
    fi
    
    # Check if to_phase is in valid transitions
    for valid in $valid_transitions; do
        if [[ "$valid" == "$to_phase" ]]; then
            return 0
        fi
    done
    
    return 1
}

# =============================================================================
# STATE FILE OPERATIONS
# =============================================================================

# Get state file path
get_state_file_path() {
    local stack_name="${1:-$CURRENT_STACK_NAME}"
    
    if [[ -z "$stack_name" ]]; then
        echo "$STATE_BASE_DIR/${STATE_FILE_PREFIX}-global.json"
    else
        echo "$STATE_BASE_DIR/${STATE_FILE_PREFIX}-${stack_name}.json"
    fi
}

# Create empty state file
create_empty_state_file() {
    local state_file="$1"
    
    local empty_state=$(cat <<EOF
{
    "version": "$STATE_MANAGER_VERSION",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "backend": "$STATE_BACKEND",
    "global": {},
    "stacks": {},
    "deployments": {},
    "events": []
}
EOF
)
    
    echo "$empty_state" | jq '.' > "$state_file"
    
    # Generate checksum if enabled
    if [[ "$STATE_CHECKSUM_ENABLED" == "true" ]]; then
        generate_state_checksum "$state_file"
    fi
}

# Validate state file
validate_state_file() {
    local state_file="$1"
    
    # Check file exists
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$state_file" 2>/dev/null; then
        return 1
    fi
    
    # Check checksum if enabled
    if [[ "$STATE_CHECKSUM_ENABLED" == "true" ]]; then
        if ! verify_state_checksum "$state_file"; then
            log_error_internal "WARNING" "State file checksum validation failed"
            return 1
        fi
    fi
    
    # Check required fields
    local version=$(jq -r '.version // ""' "$state_file")
    if [[ -z "$version" ]]; then
        return 1
    fi
    
    return 0
}

# Save state file
save_state_file() {
    if [[ "$STATE_MODIFIED" != "true" ]]; then
        return 0
    fi
    
    local state_file=$(get_state_file_path)
    
    # Update metadata
    local temp_file="${state_file}.tmp"
    jq ".last_modified = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$state_file" > "$temp_file"
    mv "$temp_file" "$state_file"
    
    # Create backup if enabled
    if [[ "$STATE_BACKUP_ENABLED" == "true" ]]; then
        create_state_backup "$state_file"
    fi
    
    # Generate checksum
    if [[ "$STATE_CHECKSUM_ENABLED" == "true" ]]; then
        generate_state_checksum "$state_file"
    fi
    
    STATE_MODIFIED=false
}

# =============================================================================
# LOCKING MECHANISM
# =============================================================================

# Acquire state lock
acquire_state_lock() {
    local lock_file="${STATE_LOCK_DIR}/${CURRENT_STACK_NAME:-global}.lock"
    local timeout="${STATE_LOCK_TIMEOUT}"
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Write lock info
            cat > "$lock_file/info" <<EOF
{
    "pid": $$,
    "deployment_id": "$CURRENT_DEPLOYMENT_ID",
    "acquired": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "host": "$(hostname)"
}
EOF
            return 0
        fi
        
        # Check if lock is stale
        if [[ -f "$lock_file/info" ]]; then
            local lock_pid=$(jq -r '.pid // ""' "$lock_file/info" 2>/dev/null)
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                log_error_internal "WARNING" "Removing stale lock from PID $lock_pid"
                rm -rf "$lock_file"
                continue
            fi
        fi
        
        sleep 1
        ((elapsed++))
    done
    
    throw_error $ERROR_TIMEOUT "Failed to acquire state lock after ${timeout}s"
}

# Release state lock
release_state_lock() {
    local lock_file="${STATE_LOCK_DIR}/${CURRENT_STACK_NAME:-global}.lock"
    
    if [[ -d "$lock_file" ]]; then
        rm -rf "$lock_file"
    fi
}

# =============================================================================
# READ OPERATIONS
# =============================================================================

# Read global state
read_global_state() {
    local key="$1"
    local state_file=$(get_state_file_path)
    
    jq -r ".global.$key // empty" "$state_file" 2>/dev/null
}

# Read stack state
read_stack_state() {
    local stack_name="$1"
    local key="$2"
    local state_file=$(get_state_file_path)
    
    jq -r ".stacks.\"$stack_name\".$key // empty" "$state_file" 2>/dev/null
}

# Read resource state
read_resource_state() {
    local stack_name="$1"
    local resource="$2"
    local key="$3"
    local state_file=$(get_state_file_path)
    
    jq -r ".stacks.\"$stack_name\".resources.\"$resource\".$key // empty" "$state_file" 2>/dev/null
}

# Read deployment state
read_deployment_state() {
    local deployment_id="$1"
    local key="$2"
    local state_file=$(get_state_file_path)
    
    jq -r ".deployments.\"$deployment_id\".$key // empty" "$state_file" 2>/dev/null
}

# =============================================================================
# WRITE OPERATIONS
# =============================================================================

# Write global state
write_global_state() {
    local key="$1"
    local value="$2"
    local state_file=$(get_state_file_path)
    local temp_file="${state_file}.tmp"
    
    jq ".global.$key = \"$value\"" "$state_file" > "$temp_file"
    mv "$temp_file" "$state_file"
}

# Write stack state
write_stack_state() {
    local stack_name="$1"
    local key="$2"
    local value="$3"
    local state_file=$(get_state_file_path)
    local temp_file="${state_file}.tmp"
    
    # Ensure stack exists
    jq ".stacks.\"$stack_name\" //= {}" "$state_file" | \
    jq ".stacks.\"$stack_name\".$key = \"$value\"" > "$temp_file"
    
    mv "$temp_file" "$state_file"
}

# Write resource state
write_resource_state() {
    local stack_name="$1"
    local resource="$2"
    local key="$3"
    local value="$4"
    local state_file=$(get_state_file_path)
    local temp_file="${state_file}.tmp"
    
    # Ensure paths exist
    jq ".stacks.\"$stack_name\" //= {}" "$state_file" | \
    jq ".stacks.\"$stack_name\".resources //= {}" | \
    jq ".stacks.\"$stack_name\".resources.\"$resource\" //= {}" | \
    jq ".stacks.\"$stack_name\".resources.\"$resource\".$key = \"$value\"" > "$temp_file"
    
    mv "$temp_file" "$state_file"
}

# Write deployment state
write_deployment_state() {
    local deployment_id="$1"
    local key="$2"
    local value="$3"
    local state_file=$(get_state_file_path)
    local temp_file="${state_file}.tmp"
    
    jq ".deployments.\"$deployment_id\" //= {}" "$state_file" | \
    jq ".deployments.\"$deployment_id\".$key = \"$value\"" > "$temp_file"
    
    mv "$temp_file" "$state_file"
}

# =============================================================================
# ARRAY OPERATIONS
# =============================================================================

# Add to state array
add_to_state_array() {
    local array_key="$1"
    local value="$2"
    local scope="${3:-$STATE_SCOPE_STACK}"
    
    acquire_state_lock
    
    local state_file=$(get_state_file_path)
    local temp_file="${state_file}.tmp"
    local path=""
    
    # Determine path based on scope
    case "$scope" in
        "$STATE_SCOPE_GLOBAL")
            path=".global.$array_key"
            ;;
        "$STATE_SCOPE_STACK")
            path=".stacks.\"$CURRENT_STACK_NAME\".$array_key"
            ;;
        "$STATE_SCOPE_DEPLOYMENT")
            path=".deployments.\"$CURRENT_DEPLOYMENT_ID\".$array_key"
            ;;
    esac
    
    # Add to array
    jq "$path //= []" "$state_file" | \
    jq "$path += [$value]" > "$temp_file"
    
    mv "$temp_file" "$state_file"
    STATE_MODIFIED=true
    
    release_state_lock
}

# =============================================================================
# BACKUP AND RECOVERY
# =============================================================================

# Create state backup
create_state_backup() {
    local state_file="$1"
    local backup_name="$(basename "$state_file" .json)-$(date +%Y%m%d-%H%M%S).json"
    local backup_path="$STATE_BACKUP_DIR/$backup_name"
    
    cp "$state_file" "$backup_path"
    
    # Compress if large
    if [[ $(stat -f%z "$backup_path" 2>/dev/null || stat -c%s "$backup_path") -gt 1048576 ]]; then
        gzip "$backup_path"
        backup_path="${backup_path}.gz"
    fi
    
    # Rotate old backups
    rotate_state_backups
    
    log_error_internal "INFO" "Created state backup: $backup_path"
}

# Rotate state backups
rotate_state_backups() {
    local max_backups="${STATE_BACKUP_RETENTION}"
    
    # Find and sort backups
    local backups=($(ls -t "$STATE_BACKUP_DIR"/*.json* 2>/dev/null))
    
    # Remove old backups
    if [[ ${#backups[@]} -gt $max_backups ]]; then
        for ((i=$max_backups; i<${#backups[@]}; i++)); do
            rm -f "${backups[$i]}"
            log_error_internal "INFO" "Removed old backup: ${backups[$i]}"
        done
    fi
}

# =============================================================================
# CHECKSUM OPERATIONS
# =============================================================================

# Generate state checksum
generate_state_checksum() {
    local state_file="$1"
    local checksum_file="${state_file}.sha256"
    
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$state_file" | cut -d' ' -f1 > "$checksum_file"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$state_file" | cut -d' ' -f1 > "$checksum_file"
    fi
}

# Verify state checksum
verify_state_checksum() {
    local state_file="$1"
    local checksum_file="${state_file}.sha256"
    
    if [[ ! -f "$checksum_file" ]]; then
        return 0  # No checksum to verify
    fi
    
    local expected=$(cat "$checksum_file")
    local actual=""
    
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$state_file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$state_file" | cut -d' ' -f1)
    fi
    
    [[ "$expected" == "$actual" ]]
}

# =============================================================================
# EVENT SYSTEM
# =============================================================================

# Fire state event
fire_state_event() {
    local event_type="$1"
    local event_data="${2:-{}}"
    
    local event=$(cat <<EOF
{
    "type": "$event_type",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment_id": "$CURRENT_DEPLOYMENT_ID",
    "stack": "$CURRENT_STACK_NAME",
    "data": $event_data
}
EOF
)
    
    # Add to events array
    add_to_state_array "events" "$event" "$STATE_SCOPE_GLOBAL"
    
    # Call event handlers if registered
    local handler="handle_${event_type}_event"
    if declare -f "$handler" >/dev/null; then
        "$handler" "$event"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get state summary
get_state_summary() {
    local stack_name="${1:-$CURRENT_STACK_NAME}"
    local state_file=$(get_state_file_path "$stack_name")
    
    if [[ ! -f "$state_file" ]]; then
        echo "{}"
        return
    fi
    
    jq "{
        version: .version,
        created: .created,
        last_modified: .last_modified,
        current_phase: .stacks.\"$stack_name\".phase,
        resource_count: (.stacks.\"$stack_name\".resources | length),
        event_count: (.events | length)
    }" "$state_file"
}

# Clear state
clear_state() {
    local scope="${1:-$STATE_SCOPE_STACK}"
    
    acquire_state_lock
    
    case "$scope" in
        "$STATE_SCOPE_GLOBAL")
            create_empty_state_file "$(get_state_file_path)"
            ;;
        "$STATE_SCOPE_STACK")
            local state_file=$(get_state_file_path)
            local temp_file="${state_file}.tmp"
            jq "del(.stacks.\"$CURRENT_STACK_NAME\")" "$state_file" > "$temp_file"
            mv "$temp_file" "$state_file"
            ;;
        "$STATE_SCOPE_DEPLOYMENT")
            local state_file=$(get_state_file_path)
            local temp_file="${state_file}.tmp"
            jq "del(.deployments.\"$CURRENT_DEPLOYMENT_ID\")" "$state_file" > "$temp_file"
            mv "$temp_file" "$state_file"
            ;;
    esac
    
    STATE_MODIFIED=true
    save_state_file
    
    release_state_lock
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all public functions
export -f init_state_management
export -f get_state
export -f set_state
export -f delete_state
export -f get_current_phase
export -f transition_phase
export -f get_state_summary
export -f clear_state
export -f fire_state_event
export -f add_to_state_array

# Export for backward compatibility
export -f acquire_state_lock
export -f release_state_lock

log_error_internal "INFO" "Unified state manager loaded (v$STATE_MANAGER_VERSION)"