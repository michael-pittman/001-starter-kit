#!/usr/bin/env bash
# =============================================================================
# Deployment State Synchronization
# Manages state synchronization across distributed components
# =============================================================================

# Prevent multiple sourcing
if [[ "${DEPLOYMENT_STATE_SYNC_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly DEPLOYMENT_STATE_SYNC_LIB_LOADED=true

# =============================================================================
# SYNCHRONIZATION CONFIGURATION
# =============================================================================

# Sync configuration
readonly SYNC_INTERVAL="${SYNC_INTERVAL:-60}"                    # Default sync interval
readonly SYNC_RETRY_ATTEMPTS="${SYNC_RETRY_ATTEMPTS:-3}"         # Retry attempts on failure
readonly SYNC_RETRY_DELAY="${SYNC_RETRY_DELAY:-5}"              # Delay between retries
readonly SYNC_CONFLICT_RESOLUTION="${SYNC_CONFLICT_RESOLUTION:-timestamp}" # timestamp, merge, manual
readonly SYNC_BATCH_SIZE="${SYNC_BATCH_SIZE:-100}"              # Max items per sync batch

# Remote sync endpoints (can be S3, DynamoDB, custom API)
readonly SYNC_REMOTE_TYPE="${SYNC_REMOTE_TYPE:-s3}"             # s3, dynamodb, api
readonly SYNC_S3_BUCKET="${SYNC_S3_BUCKET:-}"
readonly SYNC_S3_PREFIX="${SYNC_S3_PREFIX:-deployment-state}"
readonly SYNC_DYNAMODB_TABLE="${SYNC_DYNAMODB_TABLE:-}"
readonly SYNC_API_ENDPOINT="${SYNC_API_ENDPOINT:-}"

# Sync state tracking
declare -gA SYNC_STATE
declare -gA SYNC_CONFLICTS
declare -gA SYNC_QUEUE
declare -gA SYNC_HISTORY

# =============================================================================
# SYNC INITIALIZATION
# =============================================================================

# Initialize state synchronization
init_state_sync() {
    local sync_mode="${1:-auto}"  # auto, manual, disabled
    
    log "Initializing state synchronization (mode: $sync_mode)"
    
    # Validate configuration
    if ! validate_sync_configuration; then
        error "Invalid sync configuration"
        return 1
    fi
    
    # Initialize sync state
    aa_set SYNC_STATE "mode" "$sync_mode"
    aa_set SYNC_STATE "initialized_at" "$(date +%s)"
    aa_set SYNC_STATE "last_sync" "0"
    aa_set SYNC_STATE "sync_count" "0"
    aa_set SYNC_STATE "conflict_count" "0"
    aa_set SYNC_STATE "error_count" "0"
    
    # Start sync scheduler if auto mode
    if [[ "$sync_mode" == "auto" ]]; then
        start_sync_scheduler
    fi
    
    log "State synchronization initialized"
    return 0
}

# Validate sync configuration
validate_sync_configuration() {
    case "$SYNC_REMOTE_TYPE" in
        "s3")
            if [[ -z "$SYNC_S3_BUCKET" ]]; then
                error "S3 bucket not configured for sync"
                return 1
            fi
            # Check AWS CLI availability
            if ! command -v aws >/dev/null 2>&1; then
                error "AWS CLI not available for S3 sync"
                return 1
            fi
            ;;
        "dynamodb")
            if [[ -z "$SYNC_DYNAMODB_TABLE" ]]; then
                error "DynamoDB table not configured for sync"
                return 1
            fi
            ;;
        "api")
            if [[ -z "$SYNC_API_ENDPOINT" ]]; then
                error "API endpoint not configured for sync"
                return 1
            fi
            ;;
        *)
            error "Unknown sync remote type: $SYNC_REMOTE_TYPE"
            return 1
            ;;
    esac
    
    return 0
}

# =============================================================================
# STATE SYNCHRONIZATION
# =============================================================================

# Sync deployment state
sync_deployment_state_distributed() {
    local deployment_id="${1:-all}"
    local sync_direction="${2:-bidirectional}"  # push, pull, bidirectional
    local force="${3:-false}"
    
    log "Starting state sync: $deployment_id (direction: $sync_direction)"
    
    # Check if sync is needed
    if [[ "$force" != "true" ]] && ! is_sync_needed "$deployment_id"; then
        log "Sync not needed for: $deployment_id"
        return 0
    fi
    
    # Acquire sync lock
    if ! acquire_deployment_lock "sync" "global" 60; then
        error "Failed to acquire sync lock"
        return 1
    fi
    
    local sync_result=0
    
    # Perform sync based on direction
    case "$sync_direction" in
        "push")
            sync_result=$(push_state_to_remote "$deployment_id")
            ;;
        "pull")
            sync_result=$(pull_state_from_remote "$deployment_id")
            ;;
        "bidirectional")
            # Pull first to get latest changes
            pull_state_from_remote "$deployment_id"
            # Then push local changes
            push_state_to_remote "$deployment_id"
            sync_result=$?
            ;;
    esac
    
    # Update sync state
    aa_set SYNC_STATE "last_sync" "$(date +%s)"
    local sync_count=$(aa_get SYNC_STATE "sync_count" "0")
    aa_set SYNC_STATE "sync_count" "$((sync_count + 1))"
    
    # Release sync lock
    release_deployment_lock "sync" "global"
    
    if [[ $sync_result -eq 0 ]]; then
        log "State sync completed successfully"
    else
        error "State sync failed"
        local error_count=$(aa_get SYNC_STATE "error_count" "0")
        aa_set SYNC_STATE "error_count" "$((error_count + 1))"
    fi
    
    return $sync_result
}

# Check if sync is needed
is_sync_needed() {
    local deployment_id="$1"
    
    # Check last modification time
    local last_modified=$(aa_get DEPLOYMENT_STATES "${deployment_id}:updated_at" "0")
    local last_sync=$(aa_get SYNC_STATE "last_sync" "0")
    
    if [[ $last_modified -gt $last_sync ]]; then
        return 0  # Sync needed
    fi
    
    # Check if there are queued changes
    local queue_size=$(aa_size SYNC_QUEUE)
    if [[ $queue_size -gt 0 ]]; then
        return 0  # Sync needed
    fi
    
    return 1  # No sync needed
}

# =============================================================================
# PUSH SYNCHRONIZATION
# =============================================================================

# Push state to remote
push_state_to_remote() {
    local deployment_id="$1"
    local attempt=1
    
    while [[ $attempt -le $SYNC_RETRY_ATTEMPTS ]]; do
        log "Pushing state to remote (attempt $attempt/$SYNC_RETRY_ATTEMPTS)"
        
        case "$SYNC_REMOTE_TYPE" in
            "s3")
                if push_state_to_s3 "$deployment_id"; then
                    return 0
                fi
                ;;
            "dynamodb")
                if push_state_to_dynamodb "$deployment_id"; then
                    return 0
                fi
                ;;
            "api")
                if push_state_to_api "$deployment_id"; then
                    return 0
                fi
                ;;
        esac
        
        # Retry with delay
        attempt=$((attempt + 1))
        if [[ $attempt -le $SYNC_RETRY_ATTEMPTS ]]; then
            sleep "$SYNC_RETRY_DELAY"
        fi
    done
    
    error "Failed to push state after $SYNC_RETRY_ATTEMPTS attempts"
    return 1
}

# Push state to S3
push_state_to_s3() {
    local deployment_id="$1"
    local temp_file="/tmp/deployment-state-${deployment_id}-$$.json"
    
    # Export state to file
    if [[ "$deployment_id" == "all" ]]; then
        cp "$STATE_FILE" "$temp_file"
    else
        # Export specific deployment
        export_deployment_to_json "$deployment_id" > "$temp_file"
    fi
    
    # Add sync metadata
    local sync_metadata=$(cat <<EOF
{
    "sync_timestamp": $(date +%s),
    "sync_source": "$(hostname)",
    "sync_version": "$ENHANCED_DEPLOYMENT_STATE_VERSION"
}
EOF
)
    
    # Merge metadata with state
    jq --argjson metadata "$sync_metadata" '. + {sync_metadata: $metadata}' "$temp_file" > "${temp_file}.tmp" && \
        mv "${temp_file}.tmp" "$temp_file"
    
    # Upload to S3
    local s3_key="${SYNC_S3_PREFIX}/${deployment_id}/state.json"
    if [[ "$deployment_id" == "all" ]]; then
        s3_key="${SYNC_S3_PREFIX}/global/state.json"
    fi
    
    if aws s3 cp "$temp_file" "s3://${SYNC_S3_BUCKET}/${s3_key}" \
        --metadata "sync-timestamp=$(date +%s),sync-source=$(hostname)" 2>/dev/null; then
        log "Successfully pushed state to S3: $s3_key"
        rm -f "$temp_file"
        return 0
    else
        error "Failed to push state to S3"
        rm -f "$temp_file"
        return 1
    fi
}

# Push state to DynamoDB
push_state_to_dynamodb() {
    local deployment_id="$1"
    
    # Prepare DynamoDB item
    local state_json=$(export_deployment_to_json "$deployment_id")
    local item=$(cat <<EOF
{
    "deployment_id": {"S": "$deployment_id"},
    "state_data": {"S": $(echo "$state_json" | jq -c . | jq -Rs .)},
    "sync_timestamp": {"N": "$(date +%s)"},
    "sync_source": {"S": "$(hostname)"},
    "ttl": {"N": "$(($(date +%s) + 86400))"}
}
EOF
)
    
    # Put item to DynamoDB
    if aws dynamodb put-item \
        --table-name "$SYNC_DYNAMODB_TABLE" \
        --item "$item" \
        --condition-expression "attribute_not_exists(deployment_id) OR sync_timestamp < :timestamp" \
        --expression-attribute-values '{":timestamp": {"N": "'$(date +%s)'"}}' \
        2>/dev/null; then
        log "Successfully pushed state to DynamoDB"
        return 0
    else
        error "Failed to push state to DynamoDB"
        return 1
    fi
}

# Push state to API
push_state_to_api() {
    local deployment_id="$1"
    
    # Prepare API payload
    local state_json=$(export_deployment_to_json "$deployment_id")
    local payload=$(cat <<EOF
{
    "deployment_id": "$deployment_id",
    "state": $state_json,
    "sync_metadata": {
        "timestamp": $(date +%s),
        "source": "$(hostname)",
        "version": "$ENHANCED_DEPLOYMENT_STATE_VERSION"
    }
}
EOF
)
    
    # Send to API
    if curl -s -X POST "$SYNC_API_ENDPOINT/deployments/${deployment_id}/state" \
        -H "Content-Type: application/json" \
        -H "X-Sync-Token: ${SYNC_API_TOKEN:-}" \
        -d "$payload" \
        -w "%{http_code}" \
        -o /tmp/api-response-$$.json | grep -q "^2"; then
        log "Successfully pushed state to API"
        rm -f /tmp/api-response-$$.json
        return 0
    else
        error "Failed to push state to API"
        rm -f /tmp/api-response-$$.json
        return 1
    fi
}

# =============================================================================
# PULL SYNCHRONIZATION
# =============================================================================

# Pull state from remote
pull_state_from_remote() {
    local deployment_id="$1"
    local attempt=1
    
    while [[ $attempt -le $SYNC_RETRY_ATTEMPTS ]]; do
        log "Pulling state from remote (attempt $attempt/$SYNC_RETRY_ATTEMPTS)"
        
        case "$SYNC_REMOTE_TYPE" in
            "s3")
                if pull_state_from_s3 "$deployment_id"; then
                    return 0
                fi
                ;;
            "dynamodb")
                if pull_state_from_dynamodb "$deployment_id"; then
                    return 0
                fi
                ;;
            "api")
                if pull_state_from_api "$deployment_id"; then
                    return 0
                fi
                ;;
        esac
        
        # Retry with delay
        attempt=$((attempt + 1))
        if [[ $attempt -le $SYNC_RETRY_ATTEMPTS ]]; then
            sleep "$SYNC_RETRY_DELAY"
        fi
    done
    
    error "Failed to pull state after $SYNC_RETRY_ATTEMPTS attempts"
    return 1
}

# Pull state from S3
pull_state_from_s3() {
    local deployment_id="$1"
    local temp_file="/tmp/deployment-state-pull-${deployment_id}-$$.json"
    
    # Determine S3 key
    local s3_key="${SYNC_S3_PREFIX}/${deployment_id}/state.json"
    if [[ "$deployment_id" == "all" ]]; then
        s3_key="${SYNC_S3_PREFIX}/global/state.json"
    fi
    
    # Download from S3
    if aws s3 cp "s3://${SYNC_S3_BUCKET}/${s3_key}" "$temp_file" 2>/dev/null; then
        log "Successfully pulled state from S3: $s3_key"
        
        # Merge with local state
        if merge_remote_state "$deployment_id" "$temp_file"; then
            rm -f "$temp_file"
            return 0
        else
            rm -f "$temp_file"
            return 1
        fi
    else
        error "Failed to pull state from S3"
        return 1
    fi
}

# Pull state from DynamoDB
pull_state_from_dynamodb() {
    local deployment_id="$1"
    
    # Get item from DynamoDB
    local response=$(aws dynamodb get-item \
        --table-name "$SYNC_DYNAMODB_TABLE" \
        --key '{"deployment_id": {"S": "'$deployment_id'"}}' \
        2>/dev/null)
    
    if [[ -n "$response" ]]; then
        # Extract state data
        local state_data=$(echo "$response" | jq -r '.Item.state_data.S' | jq .)
        local sync_timestamp=$(echo "$response" | jq -r '.Item.sync_timestamp.N')
        
        if [[ -n "$state_data" ]]; then
            log "Successfully pulled state from DynamoDB"
            
            # Save to temp file for merging
            local temp_file="/tmp/deployment-state-dynamo-$$.json"
            echo "$state_data" > "$temp_file"
            
            # Merge with local state
            if merge_remote_state "$deployment_id" "$temp_file"; then
                rm -f "$temp_file"
                return 0
            else
                rm -f "$temp_file"
                return 1
            fi
        fi
    fi
    
    error "Failed to pull state from DynamoDB"
    return 1
}

# Pull state from API
pull_state_from_api() {
    local deployment_id="$1"
    local temp_file="/tmp/deployment-state-api-$$.json"
    
    # Get from API
    local http_code=$(curl -s -X GET "$SYNC_API_ENDPOINT/deployments/${deployment_id}/state" \
        -H "X-Sync-Token: ${SYNC_API_TOKEN:-}" \
        -w "%{http_code}" \
        -o "$temp_file")
    
    if [[ "$http_code" =~ ^2 ]]; then
        log "Successfully pulled state from API"
        
        # Extract state from response
        local state_data=$(jq '.state' "$temp_file")
        echo "$state_data" > "${temp_file}.state"
        
        # Merge with local state
        if merge_remote_state "$deployment_id" "${temp_file}.state"; then
            rm -f "$temp_file" "${temp_file}.state"
            return 0
        else
            rm -f "$temp_file" "${temp_file}.state"
            return 1
        fi
    else
        error "Failed to pull state from API (HTTP $http_code)"
        rm -f "$temp_file"
        return 1
    fi
}

# =============================================================================
# CONFLICT RESOLUTION
# =============================================================================

# Merge remote state with local
merge_remote_state() {
    local deployment_id="$1"
    local remote_file="$2"
    
    log "Merging remote state for: $deployment_id"
    
    # Check for conflicts
    local conflicts=$(detect_state_conflicts "$deployment_id" "$remote_file")
    
    if [[ -n "$conflicts" ]]; then
        log "State conflicts detected: $conflicts"
        
        # Resolve conflicts based on strategy
        if ! resolve_state_conflicts "$deployment_id" "$remote_file" "$conflicts"; then
            error "Failed to resolve state conflicts"
            return 1
        fi
    fi
    
    # Apply merged state
    if [[ "$deployment_id" == "all" ]]; then
        # Full state replacement (with conflict resolution)
        apply_merged_global_state "$remote_file"
    else
        # Merge specific deployment
        apply_merged_deployment_state "$deployment_id" "$remote_file"
    fi
    
    log "State merge completed"
    return 0
}

# Detect state conflicts
detect_state_conflicts() {
    local deployment_id="$1"
    local remote_file="$2"
    local conflicts=""
    
    if [[ "$deployment_id" == "all" ]]; then
        # Compare timestamps for all deployments
        local remote_deployments=$(jq -r '.deployments | keys[]' "$remote_file" 2>/dev/null)
        
        for dep_id in $remote_deployments; do
            local local_updated=$(jq -r --arg id "$dep_id" '.deployments[$id].updated_at // 0' "$STATE_FILE" 2>/dev/null)
            local remote_updated=$(jq -r --arg id "$dep_id" '.deployments[$id].updated_at // 0' "$remote_file" 2>/dev/null)
            
            if [[ "$local_updated" != "0" ]] && [[ "$remote_updated" != "0" ]] && \
               [[ "$local_updated" != "$remote_updated" ]]; then
                conflicts="${conflicts}${dep_id},"
            fi
        done
    else
        # Check specific deployment
        local local_updated=$(aa_get DEPLOYMENT_STATES "${deployment_id}:updated_at" "0")
        local remote_updated=$(jq -r '.updated_at // 0' "$remote_file" 2>/dev/null)
        
        if [[ "$local_updated" != "0" ]] && [[ "$remote_updated" != "0" ]] && \
           [[ "$local_updated" != "$remote_updated" ]]; then
            conflicts="$deployment_id"
        fi
    fi
    
    echo "${conflicts%,}"  # Remove trailing comma
}

# Resolve state conflicts
resolve_state_conflicts() {
    local deployment_id="$1"
    local remote_file="$2"
    local conflicts="$3"
    
    case "$SYNC_CONFLICT_RESOLUTION" in
        "timestamp")
            # Use most recent version
            resolve_conflicts_by_timestamp "$deployment_id" "$remote_file" "$conflicts"
            ;;
        "merge")
            # Merge changes from both versions
            resolve_conflicts_by_merge "$deployment_id" "$remote_file" "$conflicts"
            ;;
        "manual")
            # Queue for manual resolution
            queue_conflicts_for_manual_resolution "$deployment_id" "$remote_file" "$conflicts"
            ;;
        *)
            error "Unknown conflict resolution strategy: $SYNC_CONFLICT_RESOLUTION"
            return 1
            ;;
    esac
    
    # Update conflict count
    local conflict_count=$(aa_get SYNC_STATE "conflict_count" "0")
    aa_set SYNC_STATE "conflict_count" "$((conflict_count + 1))"
    
    return 0
}

# Resolve conflicts by timestamp
resolve_conflicts_by_timestamp() {
    local deployment_id="$1"
    local remote_file="$2"
    local conflicts="$3"
    
    IFS=',' read -ra conflict_ids <<< "$conflicts"
    
    for conf_id in "${conflict_ids[@]}"; do
        local local_updated=$(aa_get DEPLOYMENT_STATES "${conf_id}:updated_at" "0")
        local remote_updated=$(jq -r --arg id "$conf_id" '.deployments[$id].updated_at // 0' "$remote_file" 2>/dev/null)
        
        if [[ $remote_updated -gt $local_updated ]]; then
            log "Conflict resolution: Using remote version for $conf_id (newer)"
            # Remote is newer, will be applied during merge
        else
            log "Conflict resolution: Keeping local version for $conf_id (newer)"
            # Local is newer, exclude from merge
            jq --arg id "$conf_id" 'del(.deployments[$id])' "$remote_file" > "${remote_file}.tmp" && \
                mv "${remote_file}.tmp" "$remote_file"
        fi
    done
}

# Resolve conflicts by merging
resolve_conflicts_by_merge() {
    local deployment_id="$1"
    local remote_file="$2"
    local conflicts="$3"
    
    # This would implement a more sophisticated merge strategy
    # For now, fall back to timestamp resolution
    resolve_conflicts_by_timestamp "$deployment_id" "$remote_file" "$conflicts"
}

# Queue conflicts for manual resolution
queue_conflicts_for_manual_resolution() {
    local deployment_id="$1"
    local remote_file="$2"
    local conflicts="$3"
    
    local conflict_id="conflict-$(date +%s)-$$"
    
    aa_set SYNC_CONFLICTS "${conflict_id}:deployment_id" "$deployment_id"
    aa_set SYNC_CONFLICTS "${conflict_id}:conflicts" "$conflicts"
    aa_set SYNC_CONFLICTS "${conflict_id}:remote_file" "$remote_file"
    aa_set SYNC_CONFLICTS "${conflict_id}:timestamp" "$(date +%s)"
    aa_set SYNC_CONFLICTS "${conflict_id}:status" "pending"
    
    log "Queued conflicts for manual resolution: $conflict_id"
}

# =============================================================================
# STATE APPLICATION
# =============================================================================

# Apply merged global state
apply_merged_global_state() {
    local remote_file="$1"
    
    # Backup current state
    create_state_backup "pre_merge"
    
    # Merge remote state into local
    local temp_merged="/tmp/merged-state-$$.json"
    
    # Start with current local state
    cp "$STATE_FILE" "$temp_merged"
    
    # Merge deployments
    jq -s '.[0] * .[1]' "$temp_merged" "$remote_file" > "${temp_merged}.new" && \
        mv "${temp_merged}.new" "$temp_merged"
    
    # Update metadata
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.metadata.last_modified = $timestamp | .metadata.last_sync = $timestamp' \
       "$temp_merged" > "${temp_merged}.new" && \
        mv "${temp_merged}.new" "$temp_merged"
    
    # Apply merged state
    mv "$temp_merged" "$STATE_FILE"
    
    # Reload into memory
    load_state_from_file
    
    log "Applied merged global state"
}

# Apply merged deployment state
apply_merged_deployment_state() {
    local deployment_id="$1"
    local remote_file="$2"
    
    # Load remote deployment data
    local remote_data=$(jq '.' "$remote_file" 2>/dev/null)
    
    if [[ -n "$remote_data" ]] && [[ "$remote_data" != "null" ]]; then
        # Update in-memory state
        load_deployment_to_memory "$deployment_id" "$remote_data"
        
        # Persist to disk
        persist_deployment_state "$deployment_id" "false"
        
        log "Applied merged state for deployment: $deployment_id"
    fi
}

# =============================================================================
# SYNC SCHEDULING
# =============================================================================

# Start sync scheduler
start_sync_scheduler() {
    log "Starting sync scheduler (interval: ${SYNC_INTERVAL}s)"
    
    (
        while true; do
            sleep "$SYNC_INTERVAL"
            
            # Check if sync is still enabled
            local sync_mode=$(aa_get SYNC_STATE "mode" "disabled")
            if [[ "$sync_mode" != "auto" ]]; then
                break
            fi
            
            # Perform sync
            sync_deployment_state_distributed "all" "bidirectional" "false" 2>&1 | \
                while read -r line; do
                    log "[SYNC] $line"
                done
        done
    ) &
    
    local scheduler_pid=$!
    aa_set SYNC_STATE "scheduler_pid" "$scheduler_pid"
    
    log "Sync scheduler started (PID: $scheduler_pid)"
}

# Stop sync scheduler
stop_sync_scheduler() {
    local scheduler_pid=$(aa_get SYNC_STATE "scheduler_pid" "")
    
    if [[ -n "$scheduler_pid" ]] && kill -0 "$scheduler_pid" 2>/dev/null; then
        kill "$scheduler_pid"
        log "Sync scheduler stopped"
    fi
    
    aa_set SYNC_STATE "mode" "manual"
}

# =============================================================================
# SYNC MONITORING
# =============================================================================

# Get sync status
get_sync_status() {
    local format="${1:-summary}"  # summary, detailed, json
    
    case "$format" in
        "summary")
            echo "=== Sync Status ==="
            echo "Mode: $(aa_get SYNC_STATE "mode" "disabled")"
            echo "Last Sync: $(date -d @$(aa_get SYNC_STATE "last_sync" "0") 2>/dev/null || echo "Never")"
            echo "Sync Count: $(aa_get SYNC_STATE "sync_count" "0")"
            echo "Conflicts: $(aa_get SYNC_STATE "conflict_count" "0")"
            echo "Errors: $(aa_get SYNC_STATE "error_count" "0")"
            ;;
        "detailed")
            get_sync_status "summary"
            echo ""
            echo "=== Pending Conflicts ==="
            list_pending_conflicts
            echo ""
            echo "=== Sync Queue ==="
            list_sync_queue
            ;;
        "json")
            generate_sync_status_json
            ;;
    esac
}

# List pending conflicts
list_pending_conflicts() {
    local conflict_count=0
    
    for conflict_key in $(aa_keys SYNC_CONFLICTS); do
        if [[ "$conflict_key" =~ :status$ ]]; then
            local status=$(aa_get SYNC_CONFLICTS "$conflict_key")
            if [[ "$status" == "pending" ]]; then
                local conflict_id="${conflict_key%:status}"
                local deployment_id=$(aa_get SYNC_CONFLICTS "${conflict_id}:deployment_id")
                local timestamp=$(aa_get SYNC_CONFLICTS "${conflict_id}:timestamp")
                
                echo "- $conflict_id: $deployment_id ($(date -d @$timestamp 2>/dev/null))"
                conflict_count=$((conflict_count + 1))
            fi
        fi
    done
    
    if [[ $conflict_count -eq 0 ]]; then
        echo "No pending conflicts"
    fi
}

# List sync queue
list_sync_queue() {
    local queue_size=$(aa_size SYNC_QUEUE)
    
    if [[ $queue_size -eq 0 ]]; then
        echo "Queue is empty"
    else
        for queue_key in $(aa_keys SYNC_QUEUE); do
            local queue_item=$(aa_get SYNC_QUEUE "$queue_key")
            echo "- $queue_key: $queue_item"
        done
    fi
}

# Generate sync status JSON
generate_sync_status_json() {
    cat <<EOF
{
    "mode": "$(aa_get SYNC_STATE "mode" "disabled")",
    "initialized_at": $(aa_get SYNC_STATE "initialized_at" "0"),
    "last_sync": $(aa_get SYNC_STATE "last_sync" "0"),
    "sync_count": $(aa_get SYNC_STATE "sync_count" "0"),
    "conflict_count": $(aa_get SYNC_STATE "conflict_count" "0"),
    "error_count": $(aa_get SYNC_STATE "error_count" "0"),
    "remote_type": "$SYNC_REMOTE_TYPE",
    "sync_interval": $SYNC_INTERVAL,
    "pending_conflicts": $(count_pending_conflicts),
    "queue_size": $(aa_size SYNC_QUEUE)
}
EOF
}

# Count pending conflicts
count_pending_conflicts() {
    local count=0
    
    for conflict_key in $(aa_keys SYNC_CONFLICTS); do
        if [[ "$conflict_key" =~ :status$ ]]; then
            local status=$(aa_get SYNC_CONFLICTS "$conflict_key")
            if [[ "$status" == "pending" ]]; then
                count=$((count + 1))
            fi
        fi
    done
    
    echo "$count"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Export deployment to JSON
export_deployment_to_json() {
    local deployment_id="$1"
    
    if [[ "$deployment_id" == "all" ]]; then
        # Export entire state
        cat "$STATE_FILE"
    else
        # Export specific deployment
        local deployment_data="{"
        
        # Add all deployment fields
        for key in $(aa_keys DEPLOYMENT_STATES); do
            if [[ "$key" =~ ^${deployment_id}: ]]; then
                local field="${key#${deployment_id}:}"
                local value=$(aa_get DEPLOYMENT_STATES "$key")
                deployment_data="${deployment_data}\"${field}\":\"${value}\","
            fi
        done
        
        # Remove trailing comma and close
        deployment_data="${deployment_data%,}}"
        
        echo "$deployment_data"
    fi
}

# Queue state change for sync
queue_state_change() {
    local deployment_id="$1"
    local change_type="$2"  # create, update, delete
    local timestamp=$(date +%s)
    
    local queue_id="${deployment_id}-${change_type}-${timestamp}"
    aa_set SYNC_QUEUE "$queue_id" "{\"deployment_id\":\"$deployment_id\",\"type\":\"$change_type\",\"timestamp\":$timestamp}"
    
    # Trigger sync if auto mode
    local sync_mode=$(aa_get SYNC_STATE "mode" "manual")
    if [[ "$sync_mode" == "auto" ]]; then
        # Sync will happen on next scheduled interval
        log "Queued state change for sync: $queue_id"
    fi
}

# =============================================================================
# LIBRARY EXPORTS
# =============================================================================

# Export all functions
export -f init_state_sync validate_sync_configuration
export -f sync_deployment_state_distributed is_sync_needed
export -f push_state_to_remote push_state_to_s3 push_state_to_dynamodb push_state_to_api
export -f pull_state_from_remote pull_state_from_s3 pull_state_from_dynamodb pull_state_from_api
export -f merge_remote_state detect_state_conflicts resolve_state_conflicts
export -f resolve_conflicts_by_timestamp resolve_conflicts_by_merge queue_conflicts_for_manual_resolution
export -f apply_merged_global_state apply_merged_deployment_state
export -f start_sync_scheduler stop_sync_scheduler
export -f get_sync_status list_pending_conflicts list_sync_queue generate_sync_status_json
export -f export_deployment_to_json queue_state_change count_pending_conflicts

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "Deployment State Sync library loaded"
fi