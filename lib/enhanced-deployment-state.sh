#!/usr/bin/env bash
# =============================================================================
# Enhanced Deployment State Management Library
# Comprehensive state tracking with persistence, recovery, and monitoring
# Compatible with bash 3.x+
# =============================================================================

# Load dependencies
source "${LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}/associative-arrays.sh"
source "${LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}/error-handling.sh"

# Prevent multiple sourcing
if [[ "${ENHANCED_DEPLOYMENT_STATE_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly ENHANCED_DEPLOYMENT_STATE_LIB_LOADED=true

# =============================================================================
# LIBRARY METADATA
# =============================================================================

readonly ENHANCED_DEPLOYMENT_STATE_VERSION="2.0.0"

# =============================================================================
# STATE CONFIGURATION
# =============================================================================

# State storage configuration
readonly STATE_BASE_DIR="${STATE_BASE_DIR:-${CONFIG_DIR:-./config}/state}"
readonly STATE_FILE="${STATE_BASE_DIR}/deployment-state.json"
readonly STATE_BACKUP_DIR="${STATE_BASE_DIR}/backups"
readonly STATE_JOURNAL_DIR="${STATE_BASE_DIR}/journal"
readonly STATE_METRICS_DIR="${STATE_BASE_DIR}/metrics"
readonly STATE_LOCK_DIR="${STATE_BASE_DIR}/locks"

# State persistence configuration
readonly STATE_BACKUP_RETENTION_DAYS="${STATE_BACKUP_RETENTION_DAYS:-30}"
readonly STATE_JOURNAL_RETENTION_DAYS="${STATE_JOURNAL_RETENTION_DAYS:-7}"
readonly STATE_BACKUP_FREQUENCY="${STATE_BACKUP_FREQUENCY:-300}" # 5 minutes
readonly STATE_SYNC_INTERVAL="${STATE_SYNC_INTERVAL:-60}" # 1 minute

# State monitoring configuration
readonly STATE_ALERT_WEBHOOK_URL="${STATE_ALERT_WEBHOOK_URL:-}"
readonly STATE_HEALTH_CHECK_INTERVAL="${STATE_HEALTH_CHECK_INTERVAL:-300}"
readonly STATE_METRICS_RETENTION_HOURS="${STATE_METRICS_RETENTION_HOURS:-24}"

# =============================================================================
# GLOBAL ASSOCIATIVE ARRAYS FOR ENHANCED STATE MANAGEMENT
# =============================================================================

# Core state tracking
declare -gA DEPLOYMENT_STATES          # Current deployment states
declare -gA DEPLOYMENT_TRANSITIONS     # State transition tracking
declare -gA DEPLOYMENT_JOURNAL         # State change journal
declare -gA DEPLOYMENT_LOCKS           # Resource locks for synchronization
declare -gA DEPLOYMENT_METRICS         # Real-time metrics and monitoring
declare -gA DEPLOYMENT_ALERTS          # Alert configuration and history
declare -gA DEPLOYMENT_SUBSCRIPTIONS   # Event subscriptions
declare -gA DEPLOYMENT_SNAPSHOTS       # Point-in-time state snapshots

# State transition definitions with validation rules
declare -gA STATE_TRANSITIONS
aa_set STATE_TRANSITIONS "pending:running" "allowed"
aa_set STATE_TRANSITIONS "pending:cancelled" "allowed"
aa_set STATE_TRANSITIONS "running:paused" "allowed"
aa_set STATE_TRANSITIONS "running:completed" "allowed"
aa_set STATE_TRANSITIONS "running:failed" "allowed"
aa_set STATE_TRANSITIONS "paused:running" "allowed"
aa_set STATE_TRANSITIONS "paused:cancelled" "allowed"
aa_set STATE_TRANSITIONS "failed:running" "allowed"  # retry
aa_set STATE_TRANSITIONS "failed:rolled_back" "allowed"
aa_set STATE_TRANSITIONS "completed:rolled_back" "allowed"
aa_set STATE_TRANSITIONS "rolled_back:running" "allowed"  # redeploy

# State monitoring thresholds
declare -gA STATE_MONITORING_THRESHOLDS
aa_set STATE_MONITORING_THRESHOLDS "max_duration_pending" "300"  # 5 minutes
aa_set STATE_MONITORING_THRESHOLDS "max_duration_running" "3600" # 1 hour
aa_set STATE_MONITORING_THRESHOLDS "max_duration_paused" "1800"  # 30 minutes
aa_set STATE_MONITORING_THRESHOLDS "max_retry_attempts" "3"
aa_set STATE_MONITORING_THRESHOLDS "min_success_rate" "80"  # percentage

# =============================================================================
# STATE INITIALIZATION AND SETUP
# =============================================================================

# Initialize enhanced state management system
init_enhanced_state_management() {
    local force_reset="${1:-false}"
    
    log "Initializing enhanced deployment state management (v${ENHANCED_DEPLOYMENT_STATE_VERSION})"
    
    # Create directory structure
    mkdir -p "$STATE_BASE_DIR" "$STATE_BACKUP_DIR" "$STATE_JOURNAL_DIR" "$STATE_METRICS_DIR" "$STATE_LOCK_DIR"
    
    # Initialize or load existing state
    if [[ -f "$STATE_FILE" ]] && [[ "$force_reset" != "true" ]]; then
        if ! load_state_from_file; then
            error "Failed to load existing state file"
            return 1
        fi
    else
        if ! initialize_empty_state; then
            error "Failed to initialize state"
            return 1
        fi
    fi
    
    # Start background processes
    start_state_background_processes
    
    # Initialize monitoring
    init_state_monitoring
    
    log "Enhanced state management initialized successfully"
    return 0
}

# Initialize empty state structure
initialize_empty_state() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create initial state structure
    cat > "$STATE_FILE" <<EOF
{
    "metadata": {
        "version": "$ENHANCED_DEPLOYMENT_STATE_VERSION",
        "created": "$timestamp",
        "last_modified": "$timestamp",
        "checksum": ""
    },
    "deployments": {},
    "stacks": {},
    "resources": {},
    "transitions": [],
    "journal": [],
    "metrics": {
        "total_deployments": 0,
        "successful_deployments": 0,
        "failed_deployments": 0,
        "average_deployment_time": 0
    }
}
EOF
    
    # Calculate and update checksum
    update_state_checksum
    
    # Create initial backup
    create_state_backup "initial"
    
    return 0
}

# Load state from file into memory
load_state_from_file() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "State file not found: $STATE_FILE"
        return 1
    fi
    
    # Validate state file
    if ! validate_state_file; then
        error "State file validation failed"
        return 1
    fi
    
    # Load deployments into memory
    if command -v jq >/dev/null 2>&1; then
        local deployments
        deployments=$(jq -r '.deployments | to_entries[] | "\(.key)=\(.value | tostring)"' "$STATE_FILE" 2>/dev/null || echo "")
        
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                # Parse and load deployment data
                load_deployment_to_memory "$key" "$value"
            fi
        done <<< "$deployments"
    fi
    
    log "State loaded from file successfully"
    return 0
}

# =============================================================================
# ENHANCED STATE TRACKING WITH TRANSITIONS
# =============================================================================

# Initialize deployment with enhanced tracking
init_deployment_with_tracking() {
    local deployment_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local options_json="${4:-{}}"
    
    # Initialize basic deployment
    init_deployment "$deployment_id" "$stack_name" "$deployment_type" "$options_json"
    
    # Add enhanced tracking
    local timestamp=$(date +%s)
    local session_id="${deployment_id}-${timestamp}"
    
    # Initialize transition tracking
    aa_set DEPLOYMENT_TRANSITIONS "${deployment_id}:initialized_at" "$timestamp"
    aa_set DEPLOYMENT_TRANSITIONS "${deployment_id}:transition_count" "0"
    aa_set DEPLOYMENT_TRANSITIONS "${deployment_id}:last_transition" "initialized"
    
    # Initialize metrics
    aa_set DEPLOYMENT_METRICS "${deployment_id}:start_time" "$timestamp"
    aa_set DEPLOYMENT_METRICS "${deployment_id}:phase_times" "{}"
    aa_set DEPLOYMENT_METRICS "${deployment_id}:resource_usage" "{}"
    
    # Record in journal
    add_to_journal "$deployment_id" "initialized" "Deployment initialized with tracking"
    
    # Persist to disk
    persist_deployment_state "$deployment_id"
    
    return 0
}

# Transition deployment state with validation
transition_deployment_state() {
    local deployment_id="$1"
    local new_state="$2"
    local reason="${3:-State transition}"
    local metadata="${4:-{}}"
    
    if ! deployment_exists "$deployment_id"; then
        error "Deployment not found: $deployment_id"
        return 1
    fi
    
    local current_state=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status")
    
    # Validate transition
    if ! validate_state_transition "$current_state" "$new_state"; then
        error "Invalid state transition: $current_state -> $new_state"
        return 1
    fi
    
    # Acquire lock for state change
    if ! acquire_deployment_lock "$deployment_id" "state_transition"; then
        error "Failed to acquire lock for state transition"
        return 1
    fi
    
    local timestamp=$(date +%s)
    
    # Record transition
    local transition_id="${deployment_id}-transition-${timestamp}"
    aa_set DEPLOYMENT_TRANSITIONS "${transition_id}:from_state" "$current_state"
    aa_set DEPLOYMENT_TRANSITIONS "${transition_id}:to_state" "$new_state"
    aa_set DEPLOYMENT_TRANSITIONS "${transition_id}:timestamp" "$timestamp"
    aa_set DEPLOYMENT_TRANSITIONS "${transition_id}:reason" "$reason"
    aa_set DEPLOYMENT_TRANSITIONS "${transition_id}:metadata" "$metadata"
    
    # Update deployment state
    aa_set DEPLOYMENT_STATES "${deployment_id}:status" "$new_state"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$timestamp"
    
    # Update transition count
    local transition_count=$(aa_get DEPLOYMENT_TRANSITIONS "${deployment_id}:transition_count" "0")
    transition_count=$((transition_count + 1))
    aa_set DEPLOYMENT_TRANSITIONS "${deployment_id}:transition_count" "$transition_count"
    aa_set DEPLOYMENT_TRANSITIONS "${deployment_id}:last_transition" "$new_state"
    
    # Add to journal
    add_to_journal "$deployment_id" "state_transition" "$current_state -> $new_state: $reason"
    
    # Trigger event subscriptions
    trigger_state_event "$deployment_id" "state_changed" "{\"from\":\"$current_state\",\"to\":\"$new_state\"}"
    
    # Check monitoring thresholds
    check_state_monitoring_thresholds "$deployment_id" "$new_state"
    
    # Persist changes
    persist_deployment_state "$deployment_id"
    
    # Release lock
    release_deployment_lock "$deployment_id" "state_transition"
    
    log "State transitioned: $deployment_id: $current_state -> $new_state"
    return 0
}

# Validate state transition
validate_state_transition() {
    local from_state="$1"
    local to_state="$2"
    
    local transition_key="${from_state}:${to_state}"
    local allowed=$(aa_get STATE_TRANSITIONS "$transition_key" "not_allowed")
    
    [[ "$allowed" == "allowed" ]]
}

# =============================================================================
# ROBUST STATE PERSISTENCE AND RECOVERY
# =============================================================================

# Persist deployment state to disk
persist_deployment_state() {
    local deployment_id="$1"
    local backup="${2:-true}"
    
    # Create atomic write using temp file
    local temp_file="${STATE_FILE}.tmp.$$"
    
    # Export current state to JSON
    if ! export_state_to_json > "$temp_file"; then
        error "Failed to export state to JSON"
        rm -f "$temp_file"
        return 1
    fi
    
    # Update checksum
    local checksum=$(calculate_file_checksum "$temp_file")
    jq --arg checksum "$checksum" '.metadata.checksum = $checksum' "$temp_file" > "${temp_file}.2" && mv "${temp_file}.2" "$temp_file"
    
    # Atomic move
    if ! mv -f "$temp_file" "$STATE_FILE"; then
        error "Failed to persist state file"
        rm -f "$temp_file"
        return 1
    fi
    
    # Create backup if requested
    if [[ "$backup" == "true" ]]; then
        create_state_backup "auto_${deployment_id}"
    fi
    
    # Update last persist timestamp
    aa_set DEPLOYMENT_METRICS "last_persist_timestamp" "$(date +%s)"
    
    return 0
}

# Export state to JSON format
export_state_to_json() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Build JSON structure
    cat <<EOF
{
    "metadata": {
        "version": "$ENHANCED_DEPLOYMENT_STATE_VERSION",
        "created": "$(jq -r '.metadata.created' "$STATE_FILE" 2>/dev/null || echo "$timestamp")",
        "last_modified": "$timestamp",
        "checksum": ""
    },
    "deployments": $(export_deployments_json),
    "stacks": $(export_stacks_json),
    "resources": $(export_resources_json),
    "transitions": $(export_transitions_json),
    "journal": $(export_journal_json),
    "metrics": $(export_metrics_json)
}
EOF
}

# Create state backup with rotation
create_state_backup() {
    local backup_type="${1:-manual}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${STATE_BACKUP_DIR}/state-${backup_type}-${timestamp}.json"
    
    # Copy current state
    if [[ -f "$STATE_FILE" ]]; then
        cp "$STATE_FILE" "$backup_file"
        
        # Compress if larger than 1MB
        if [[ $(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null) -gt 1048576 ]]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
        fi
        
        log "State backup created: $backup_file"
        
        # Rotate old backups
        rotate_state_backups
    fi
    
    return 0
}

# Rotate old state backups
rotate_state_backups() {
    local max_age_days="${STATE_BACKUP_RETENTION_DAYS}"
    
    # Remove old backups
    find "$STATE_BACKUP_DIR" -name "state-*.json*" -type f -mtime +$max_age_days -delete
    
    # Keep minimum number of recent backups
    local backup_count=$(find "$STATE_BACKUP_DIR" -name "state-*.json*" -type f | wc -l)
    if [[ $backup_count -lt 10 ]]; then
        return 0  # Keep at least 10 backups regardless of age
    fi
    
    # Remove oldest backups if too many
    if [[ $backup_count -gt 50 ]]; then
        find "$STATE_BACKUP_DIR" -name "state-*.json*" -type f -printf '%T@ %p\n' | \
            sort -n | head -n $((backup_count - 50)) | cut -d' ' -f2- | \
            xargs rm -f
    fi
}

# Recover state from backup
recover_state_from_backup() {
    local backup_identifier="${1:-latest}"
    local backup_file=""
    
    # Find backup file
    if [[ "$backup_identifier" == "latest" ]]; then
        backup_file=$(find "$STATE_BACKUP_DIR" -name "state-*.json*" -type f -printf '%T@ %p\n' | \
            sort -rn | head -1 | cut -d' ' -f2-)
    elif [[ -f "$backup_identifier" ]]; then
        backup_file="$backup_identifier"
    elif [[ -f "${STATE_BACKUP_DIR}/${backup_identifier}" ]]; then
        backup_file="${STATE_BACKUP_DIR}/${backup_identifier}"
    fi
    
    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_identifier"
        return 1
    fi
    
    log "Recovering state from backup: $backup_file"
    
    # Create recovery backup of current state
    create_state_backup "pre_recovery"
    
    # Decompress if needed
    local temp_file="${STATE_FILE}.recovery.$$"
    if [[ "$backup_file" =~ \.gz$ ]]; then
        gunzip -c "$backup_file" > "$temp_file"
    else
        cp "$backup_file" "$temp_file"
    fi
    
    # Validate backup file
    if ! jq empty "$temp_file" 2>/dev/null; then
        error "Invalid JSON in backup file"
        rm -f "$temp_file"
        return 1
    fi
    
    # Restore state
    mv -f "$temp_file" "$STATE_FILE"
    
    # Reload state into memory
    load_state_from_file
    
    # Add recovery journal entry
    add_to_journal "system" "recovery" "State recovered from backup: $backup_file"
    
    log "State recovery completed successfully"
    return 0
}

# =============================================================================
# STATE MONITORING AND ALERTING
# =============================================================================

# Initialize state monitoring
init_state_monitoring() {
    # Initialize monitoring metrics
    aa_set DEPLOYMENT_METRICS "monitoring:initialized_at" "$(date +%s)"
    aa_set DEPLOYMENT_METRICS "monitoring:health_check_count" "0"
    aa_set DEPLOYMENT_METRICS "monitoring:alert_count" "0"
    
    # Schedule health checks
    schedule_state_health_checks
    
    log "State monitoring initialized"
}

# Check state monitoring thresholds
check_state_monitoring_thresholds() {
    local deployment_id="$1"
    local current_state="$2"
    local timestamp=$(date +%s)
    
    # Get state entry time
    local state_entry_time=$(aa_get DEPLOYMENT_TRANSITIONS "${deployment_id}:${current_state}_entered_at" "$timestamp")
    aa_set DEPLOYMENT_TRANSITIONS "${deployment_id}:${current_state}_entered_at" "$timestamp"
    
    local duration=$((timestamp - state_entry_time))
    
    # Check duration thresholds
    local max_duration_key="max_duration_${current_state}"
    local max_duration=$(aa_get STATE_MONITORING_THRESHOLDS "$max_duration_key" "0")
    
    if [[ $max_duration -gt 0 ]] && [[ $duration -gt $max_duration ]]; then
        trigger_state_alert "$deployment_id" "duration_exceeded" \
            "Deployment $deployment_id exceeded maximum duration for state $current_state: ${duration}s > ${max_duration}s"
    fi
    
    # Check retry attempts for failed state
    if [[ "$current_state" == "failed" ]]; then
        local retry_count=$(aa_get DEPLOYMENT_METRICS "${deployment_id}:retry_count" "0")
        local max_retries=$(aa_get STATE_MONITORING_THRESHOLDS "max_retry_attempts" "3")
        
        if [[ $retry_count -ge $max_retries ]]; then
            trigger_state_alert "$deployment_id" "max_retries_exceeded" \
                "Deployment $deployment_id exceeded maximum retry attempts: $retry_count"
        fi
    fi
}

# Trigger state alert
trigger_state_alert() {
    local deployment_id="$1"
    local alert_type="$2"
    local alert_message="$3"
    local timestamp=$(date +%s)
    
    # Record alert
    local alert_id="${deployment_id}-alert-${timestamp}"
    aa_set DEPLOYMENT_ALERTS "${alert_id}:type" "$alert_type"
    aa_set DEPLOYMENT_ALERTS "${alert_id}:message" "$alert_message"
    aa_set DEPLOYMENT_ALERTS "${alert_id}:timestamp" "$timestamp"
    aa_set DEPLOYMENT_ALERTS "${alert_id}:deployment_id" "$deployment_id"
    
    # Update alert count
    local alert_count=$(aa_get DEPLOYMENT_METRICS "monitoring:alert_count" "0")
    alert_count=$((alert_count + 1))
    aa_set DEPLOYMENT_METRICS "monitoring:alert_count" "$alert_count"
    
    # Send webhook notification if configured
    if [[ -n "$STATE_ALERT_WEBHOOK_URL" ]]; then
        send_alert_webhook "$deployment_id" "$alert_type" "$alert_message"
    fi
    
    # Log alert
    error "ALERT [$alert_type]: $alert_message"
    
    # Add to journal
    add_to_journal "$deployment_id" "alert" "$alert_type: $alert_message"
}

# Send alert webhook
send_alert_webhook() {
    local deployment_id="$1"
    local alert_type="$2"
    local alert_message="$3"
    
    if command -v curl >/dev/null 2>&1; then
        local payload=$(cat <<EOF
{
    "deployment_id": "$deployment_id",
    "alert_type": "$alert_type",
    "message": "$alert_message",
    "timestamp": $(date +%s),
    "severity": "$(get_alert_severity "$alert_type")"
}
EOF
)
        
        curl -s -X POST "$STATE_ALERT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1 || true
    fi
}

# Get alert severity
get_alert_severity() {
    local alert_type="$1"
    
    case "$alert_type" in
        "duration_exceeded")
            echo "warning"
            ;;
        "max_retries_exceeded"|"state_corruption"|"sync_failure")
            echo "critical"
            ;;
        *)
            echo "info"
            ;;
    esac
}

# =============================================================================
# STATE SYNCHRONIZATION
# =============================================================================

# Acquire deployment lock
acquire_deployment_lock() {
    local deployment_id="$1"
    local lock_type="$2"
    local timeout="${3:-30}"
    
    local lock_file="${STATE_LOCK_DIR}/${deployment_id}.${lock_type}.lock"
    local lock_acquired=false
    local start_time=$(date +%s)
    
    while [[ "$lock_acquired" == "false" ]]; do
        if mkdir "$lock_file" 2>/dev/null; then
            echo "$$:$(date +%s)" > "${lock_file}/owner"
            lock_acquired=true
            aa_set DEPLOYMENT_LOCKS "${deployment_id}:${lock_type}" "$lock_file"
            return 0
        fi
        
        # Check timeout
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -gt $timeout ]]; then
            error "Failed to acquire lock: $deployment_id:$lock_type (timeout)"
            return 1
        fi
        
        # Check for stale locks
        if [[ -f "${lock_file}/owner" ]]; then
            local lock_info=$(cat "${lock_file}/owner" 2>/dev/null)
            local lock_pid="${lock_info%%:*}"
            local lock_time="${lock_info##*:}"
            
            # Remove stale lock if process doesn't exist or lock is too old
            if ! kill -0 "$lock_pid" 2>/dev/null || [[ $((current_time - lock_time)) -gt 300 ]]; then
                rm -rf "$lock_file"
                continue
            fi
        fi
        
        sleep 0.1
    done
}

# Release deployment lock
release_deployment_lock() {
    local deployment_id="$1"
    local lock_type="$2"
    
    local lock_file=$(aa_get DEPLOYMENT_LOCKS "${deployment_id}:${lock_type}" "")
    
    if [[ -n "$lock_file" ]] && [[ -d "$lock_file" ]]; then
        rm -rf "$lock_file"
        aa_delete DEPLOYMENT_LOCKS "${deployment_id}:${lock_type}"
    fi
}

# Synchronize state across components
sync_deployment_state() {
    local deployment_id="${1:-all}"
    local sync_type="${2:-full}"  # full, partial, metadata
    
    log "Synchronizing deployment state: $deployment_id ($sync_type)"
    
    # Acquire sync lock
    if ! acquire_deployment_lock "system" "state_sync" 60; then
        error "Failed to acquire sync lock"
        return 1
    fi
    
    # Perform synchronization
    case "$sync_type" in
        "full")
            sync_full_state
            ;;
        "partial")
            sync_partial_state "$deployment_id"
            ;;
        "metadata")
            sync_metadata_only
            ;;
    esac
    
    # Update sync timestamp
    aa_set DEPLOYMENT_METRICS "last_sync_timestamp" "$(date +%s)"
    
    # Release sync lock
    release_deployment_lock "system" "state_sync"
    
    log "State synchronization completed"
    return 0
}

# =============================================================================
# JOURNAL AND AUDIT TRAIL
# =============================================================================

# Add entry to journal
add_to_journal() {
    local deployment_id="$1"
    local event_type="$2"
    local event_details="$3"
    local timestamp=$(date +%s)
    
    local journal_entry="${deployment_id}:${timestamp}:${event_type}"
    aa_set DEPLOYMENT_JOURNAL "$journal_entry" "$event_details"
    
    # Write to journal file
    local journal_file="${STATE_JOURNAL_DIR}/journal-$(date +%Y%m%d).log"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$deployment_id] [$event_type] $event_details" >> "$journal_file"
    
    # Rotate journal files
    rotate_journal_files
}

# Rotate journal files
rotate_journal_files() {
    find "$STATE_JOURNAL_DIR" -name "journal-*.log" -type f -mtime +$STATE_JOURNAL_RETENTION_DAYS -delete
}

# =============================================================================
# METRICS AND REPORTING
# =============================================================================

# Update deployment metrics
update_deployment_metrics() {
    local deployment_id="$1"
    local metric_name="$2"
    local metric_value="$3"
    local timestamp=$(date +%s)
    
    # Update metric
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${metric_name}" "$metric_value"
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${metric_name}_updated_at" "$timestamp"
    
    # Write to metrics file
    local metrics_file="${STATE_METRICS_DIR}/metrics-$(date +%Y%m%d-%H).json"
    local metrics_entry=$(cat <<EOF
{
    "timestamp": $timestamp,
    "deployment_id": "$deployment_id",
    "metric": "$metric_name",
    "value": "$metric_value"
}
EOF
)
    
    echo "$metrics_entry" >> "$metrics_file"
}

# Generate state report
generate_state_report() {
    local report_type="${1:-summary}"  # summary, detailed, metrics
    local output_format="${2:-text}"   # text, json, html
    local deployment_filter="${3:-}"   # specific deployment or empty for all
    
    case "$report_type" in
        "summary")
            generate_summary_report "$output_format" "$deployment_filter"
            ;;
        "detailed")
            generate_detailed_report "$output_format" "$deployment_filter"
            ;;
        "metrics")
            generate_metrics_report "$output_format" "$deployment_filter"
            ;;
    esac
}

# =============================================================================
# BACKGROUND PROCESSES
# =============================================================================

# Start background processes for state management
start_state_background_processes() {
    # Start auto-backup process
    if [[ -z "${STATE_BACKUP_PID:-}" ]]; then
        (
            while true; do
                sleep "$STATE_BACKUP_FREQUENCY"
                create_state_backup "auto" 2>/dev/null || true
            done
        ) &
        STATE_BACKUP_PID=$!
        export STATE_BACKUP_PID
    fi
    
    # Start state sync process
    if [[ -z "${STATE_SYNC_PID:-}" ]]; then
        (
            while true; do
                sleep "$STATE_SYNC_INTERVAL"
                sync_deployment_state "all" "metadata" 2>/dev/null || true
            done
        ) &
        STATE_SYNC_PID=$!
        export STATE_SYNC_PID
    fi
}

# Stop background processes
stop_state_background_processes() {
    if [[ -n "${STATE_BACKUP_PID:-}" ]]; then
        kill "$STATE_BACKUP_PID" 2>/dev/null || true
        unset STATE_BACKUP_PID
    fi
    
    if [[ -n "${STATE_SYNC_PID:-}" ]]; then
        kill "$STATE_SYNC_PID" 2>/dev/null || true
        unset STATE_SYNC_PID
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Calculate file checksum
calculate_file_checksum() {
    local file="$1"
    
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        echo "no_checksum_available"
    fi
}

# Update state checksum
update_state_checksum() {
    local checksum=$(calculate_file_checksum "$STATE_FILE")
    
    # Update checksum in file
    local temp_file="${STATE_FILE}.checksum.$$"
    jq --arg checksum "$checksum" '.metadata.checksum = $checksum' "$STATE_FILE" > "$temp_file" && \
        mv -f "$temp_file" "$STATE_FILE"
}

# Validate state file integrity
validate_state_file() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "State file not found: $STATE_FILE"
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        error "Invalid JSON in state file"
        return 1
    fi
    
    # Check version compatibility
    local file_version=$(jq -r '.metadata.version' "$STATE_FILE" 2>/dev/null)
    if [[ -z "$file_version" ]]; then
        error "State file missing version information"
        return 1
    fi
    
    # Check checksum if available
    local stored_checksum=$(jq -r '.metadata.checksum' "$STATE_FILE" 2>/dev/null)
    if [[ -n "$stored_checksum" ]] && [[ "$stored_checksum" != "no_checksum_available" ]]; then
        # Create temp copy without checksum field for validation
        local temp_file="${STATE_FILE}.validate.$$"
        jq '.metadata.checksum = ""' "$STATE_FILE" > "$temp_file"
        local calculated_checksum=$(calculate_file_checksum "$temp_file")
        rm -f "$temp_file"
        
        if [[ "$stored_checksum" != "$calculated_checksum" ]]; then
            error "State file checksum mismatch"
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# EVENT SUBSCRIPTIONS
# =============================================================================

# Subscribe to state events
subscribe_to_state_event() {
    local deployment_id="$1"
    local event_type="$2"
    local callback="$3"
    
    local subscription_id="${deployment_id}-${event_type}-$(date +%s)"
    aa_set DEPLOYMENT_SUBSCRIPTIONS "${subscription_id}:deployment_id" "$deployment_id"
    aa_set DEPLOYMENT_SUBSCRIPTIONS "${subscription_id}:event_type" "$event_type"
    aa_set DEPLOYMENT_SUBSCRIPTIONS "${subscription_id}:callback" "$callback"
    
    echo "$subscription_id"
}

# Trigger state event
trigger_state_event() {
    local deployment_id="$1"
    local event_type="$2"
    local event_data="${3:-{}}"
    
    # Find matching subscriptions
    for sub_key in $(aa_keys DEPLOYMENT_SUBSCRIPTIONS); do
        if [[ "$sub_key" =~ :deployment_id$ ]]; then
            local sub_id="${sub_key%:deployment_id}"
            local sub_deployment=$(aa_get DEPLOYMENT_SUBSCRIPTIONS "${sub_id}:deployment_id")
            local sub_event=$(aa_get DEPLOYMENT_SUBSCRIPTIONS "${sub_id}:event_type")
            
            if [[ "$sub_deployment" == "$deployment_id" || "$sub_deployment" == "*" ]] && \
               [[ "$sub_event" == "$event_type" || "$sub_event" == "*" ]]; then
                local callback=$(aa_get DEPLOYMENT_SUBSCRIPTIONS "${sub_id}:callback")
                
                # Execute callback
                if declare -f "$callback" >/dev/null 2>&1; then
                    "$callback" "$deployment_id" "$event_type" "$event_data"
                fi
            fi
        fi
    done
}

# =============================================================================
# LIBRARY EXPORTS
# =============================================================================

# Export all functions
export -f init_enhanced_state_management initialize_empty_state load_state_from_file
export -f init_deployment_with_tracking transition_deployment_state validate_state_transition
export -f persist_deployment_state export_state_to_json create_state_backup
export -f rotate_state_backups recover_state_from_backup
export -f init_state_monitoring check_state_monitoring_thresholds trigger_state_alert
export -f send_alert_webhook get_alert_severity
export -f acquire_deployment_lock release_deployment_lock sync_deployment_state
export -f add_to_journal rotate_journal_files
export -f update_deployment_metrics generate_state_report
export -f start_state_background_processes stop_state_background_processes
export -f calculate_file_checksum update_state_checksum validate_state_file
export -f subscribe_to_state_event trigger_state_event

# Clean up on exit
trap 'stop_state_background_processes' EXIT

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "Enhanced Deployment State Management library loaded (v${ENHANCED_DEPLOYMENT_STATE_VERSION})"
fi