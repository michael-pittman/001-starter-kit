#!/bin/bash
# Unity Event System - Enhanced Event Bus Implementation
# Phase 2: Comprehensive event-driven architecture with advanced features

# Don't use strict mode here as it can cause issues with function exports

# Version detection for compatibility
BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"

# Event system state and configuration
UNITY_EVENTS_DIR=".unity/events"
UNITY_EVENT_LOG="logs/unity/events.log"
UNITY_EVENT_AUDIT_LOG="logs/unity/events-audit.log"
UNITY_EVENT_DEAD_LETTER_DIR=".unity/events/dead-letter"
UNITY_EVENT_REPLAY_DIR=".unity/events/replay"
UNITY_EVENT_CONFIG_FILE=".unity/events/config.conf"
UNITY_EVENT_LOCK_DIR=".unity/events/locks"

# Event system configuration
UNITY_EVENT_MAX_RETRIES=3
UNITY_EVENT_RETRY_DELAY=2
UNITY_EVENT_HANDLER_TIMEOUT=30
UNITY_EVENT_BATCH_SIZE=10
UNITY_EVENT_AUDIT_RETENTION_DAYS=30

# Event handlers registry (bash 3/4 compatible)
declare -A UNITY_EVENT_HANDLERS 2>/dev/null || UNITY_EVENT_HANDLERS=()
declare -A UNITY_EVENT_PRIORITIES 2>/dev/null || UNITY_EVENT_PRIORITIES=()
declare -A UNITY_EVENT_FILTERS 2>/dev/null || UNITY_EVENT_FILTERS=()
declare -A UNITY_EVENT_ROUTES 2>/dev/null || UNITY_EVENT_ROUTES=()

# Event processing state
UNITY_EVENT_PROCESSING_ACTIVE=false
UNITY_EVENT_ASYNC_QUEUE_SIZE=0

# Initialize enhanced event system
unity_init_events() {
    local verbose="${1:-false}"
    
    # Create all required directories with error handling
    local dirs=(
        "$UNITY_EVENTS_DIR"
        "$(dirname "$UNITY_EVENT_LOG")"
        "$(dirname "$UNITY_EVENT_AUDIT_LOG")"
        "$UNITY_EVENT_DEAD_LETTER_DIR"
        "$UNITY_EVENT_REPLAY_DIR"
        "$UNITY_EVENT_LOCK_DIR"
        "$UNITY_EVENTS_DIR/queue"
        "$UNITY_EVENTS_DIR/processed"
        "$UNITY_EVENTS_DIR/failed"
        "$UNITY_EVENTS_DIR/priorities/high"
        "$UNITY_EVENTS_DIR/priorities/medium"
        "$UNITY_EVENTS_DIR/priorities/low"
    )
    
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            # Try relative path if absolute fails
            local rel_dir="./${dir#/}"
            mkdir -p "$rel_dir" 2>/dev/null || {
                if [[ "$verbose" == "true" ]] && command -v unity_log >/dev/null 2>&1; then
                    unity_log "WARN" "Failed to create directory: $dir"
                fi
            }
        fi
    done
    
    # Initialize configuration
    _init_event_config
    
    # Initialize event types registry with enhanced schema
    _init_event_types_registry
    
    # Initialize handler registry persistence
    _init_handler_registry
    
    # Initialize routing and filtering
    _init_event_routing
    
    # Initialize enhanced lock management system
    _init_lock_management
    
    # Set up periodic cleanup
    _setup_event_cleanup
    
    # Mark system as initialized
    if [[ -w "$(dirname "$UNITY_EVENT_AUDIT_LOG")" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S')|SYSTEM|EVENT_BUS_INITIALIZED|{}" >> "$UNITY_EVENT_AUDIT_LOG" 2>/dev/null || true
    fi
    
    if [[ "$verbose" == "true" ]] && command -v unity_log >/dev/null 2>&1; then
        unity_log "SUCCESS" "Enhanced Event Bus initialized with persistence, routing, and audit trails"
    fi
    
    return 0
}

# Enhanced event emission with validation, routing, and persistence
unity_emit_event() {
    local event_type="$1"
    local event_source="${2:-system}"
    local event_data="${3:-{}}"
    local priority="${4:-medium}"
    local sync_mode="${5:-false}"
    
    # Validate inputs
    if [[ -z "$event_type" ]]; then
        _log_event_error "Event type is required"
        return 1
    fi
    
    # Generate event ID and metadata
    local timestamp=$(date '+%s')
    local event_id="event_$(date +%s%N)_${RANDOM}"
    local correlation_id="${UNITY_CORRELATION_ID:-}"
    
    # Create standardized event structure
    local event_payload
    event_payload=$(cat <<EOF
{
  "id": "$event_id",
  "timestamp": $timestamp,
  "type": "$event_type",
  "source": "$event_source",
  "data": $event_data,
  "metadata": {
    "priority": "$priority",
    "correlation_id": "$correlation_id",
    "version": "2.0",
    "sync_mode": $sync_mode
  }
}
EOF
    )
    
    # Validate event structure
    if ! _validate_event_payload "$event_payload"; then
        _log_event_error "Invalid event payload for $event_type"
        return 1
    fi
    
    # Apply filters and routing
    if ! _should_process_event "$event_type" "$event_source" "$event_data"; then
        return 0  # Event filtered out
    fi
    
    # Persist event for audit trail
    _persist_event "$event_id" "$event_payload" "$priority"
    
    # Route event to appropriate queue
    _route_event "$event_id" "$event_payload" "$priority"
    
    # Process event (sync or async)
    if [[ "$sync_mode" == "true" ]]; then
        _process_event_sync "$event_id" "$event_payload"
    else
        _queue_event_async "$event_id" "$event_payload" "$priority"
    fi
    
    return 0
}

# Enhanced event handler registration with priorities, filters, and routing
unity_on_event() {
    local event_pattern="$1"
    local handler_function="$2"
    local options="${3:-}"
    
    if [[ -z "$event_pattern" || -z "$handler_function" ]]; then
        _log_event_error "Event handler registration requires event pattern and handler function"
        return 1
    fi
    
    # Parse options
    local priority="medium"
    local filter_condition=""
    local route_condition=""
    local handler_id="handler_$(date +%s%N)_${RANDOM}"
    local timeout="$UNITY_EVENT_HANDLER_TIMEOUT"
    local retry_count="$UNITY_EVENT_MAX_RETRIES"
    
    if [[ -n "$options" ]]; then
        eval "$options"  # Parse options like priority=high filter="source==aws"
    fi
    
    # Validate handler function exists
    if ! command -v "$handler_function" >/dev/null 2>&1; then
        _log_event_error "Handler function '$handler_function' not found"
        return 1
    fi
    
    # Register handler with metadata
    _register_event_handler "$handler_id" "$event_pattern" "$handler_function" "$priority" "$filter_condition" "$route_condition" "$timeout" "$retry_count"
    
    # Persist registration
    _persist_handler_registration "$handler_id" "$event_pattern" "$handler_function" "$priority" "$filter_condition" "$route_condition" "$timeout" "$retry_count"
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "DEBUG" "Registered handler '$handler_id' for pattern '$event_pattern' with priority '$priority'"
    fi
    
    return 0
}

# Subscribe to events (enhanced compatibility wrapper)
unity_subscribe_event() {
    local event_type="$1"
    local handler_script="$2"
    local priority="${3:-medium}"
    local filter="${4:-}"
    
    local options=""
    [[ -n "$priority" ]] && options="${options}priority=$priority "
    [[ -n "$filter" ]] && options="${options}filter='$filter' "
    
    unity_on_event "$event_type" "$handler_script" "$options"
}

# Enhanced event processing with priority queues and error handling
unity_process_events() {
    local batch_size="${1:-$UNITY_EVENT_BATCH_SIZE}"
    local max_processing_time="${2:-300}"  # 5 minutes max
    
    if [[ "$UNITY_EVENT_PROCESSING_ACTIVE" == "true" ]]; then
        return 0  # Already processing
    fi
    
    UNITY_EVENT_PROCESSING_ACTIVE=true
    local start_time=$(date +%s)
    local processed_count=0
    
    # Create processing lock
    local lock_file="$UNITY_EVENT_LOCK_DIR/processing.lock"
    if ! _acquire_lock "$lock_file"; then
        UNITY_EVENT_PROCESSING_ACTIVE=false
        return 1
    fi
    
    # Process events by priority: high -> medium -> low
    for priority in "high" "medium" "low"; do
        _process_priority_queue "$priority" "$batch_size" "$max_processing_time" "$start_time" processed_count
        
        # Check if we've exceeded max processing time
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -gt $max_processing_time ]]; then
            break
        fi
    done
    
    # Process async queue
    _process_async_queue "$batch_size"
    
    # Release lock
    _release_lock "$lock_file"
    UNITY_EVENT_PROCESSING_ACTIVE=false
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "DEBUG" "Processed $processed_count events in $(($(date +%s) - start_time)) seconds"
    fi
    
    return 0
}

# Event replay functionality
unity_replay_events() {
    local start_time="${1:-0}"
    local end_time="${2:-$(date +%s)}"
    local event_pattern="${3:-.*}"
    local dry_run="${4:-true}"
    
    local replay_id="replay_$(date +%s%N)"
    local replay_dir="$UNITY_EVENT_REPLAY_DIR/$replay_id"
    
    mkdir -p "$replay_dir"
    
    # Extract events from audit log matching criteria
    local events_to_replay
    events_to_replay=$(awk -F'|' -v start="$start_time" -v end="$end_time" -v pattern="$event_pattern" '
        {
            timestamp = gensub(/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}).*/, "\\1", "g", $1)
            if (timestamp >= start && timestamp <= end && $3 ~ pattern) {
                print $0
            }
        }' "$UNITY_EVENT_AUDIT_LOG" > "$replay_dir/events.log")
    
    local event_count
    event_count=$(wc -l < "$replay_dir/events.log")
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "INFO" "Found $event_count events to replay (dry_run=$dry_run)"
    fi
    
    if [[ "$dry_run" != "true" ]]; then
        # Actually replay events
        while IFS='|' read -r timestamp source event_type event_data; do
            if [[ -n "$event_type" ]]; then
                unity_emit_event "$event_type" "$source" "$event_data" "medium" "false"
            fi
        done < "$replay_dir/events.log"
    fi
    
    echo "$replay_id"
    return 0
}

# Dead letter queue management
unity_process_dead_letter_queue() {
    local action="${1:-list}"  # list, retry, delete
    local pattern="${2:-.*}"
    
    case "$action" in
        list)
            find "$UNITY_EVENT_DEAD_LETTER_DIR" -name '*.event' -type f | while read -r dead_event; do
                local event_id
                event_id=$(basename "$dead_event" .event)
                local failure_reason
                failure_reason=$(cat "${dead_event}.reason" 2>/dev/null || echo "Unknown")
                echo "$event_id: $failure_reason"
            done
            ;;
        retry)
            find "$UNITY_EVENT_DEAD_LETTER_DIR" -name '*.event' -type f | while read -r dead_event; do
                if [[ "$(basename "$dead_event")" =~ $pattern ]]; then
                    local event_payload
                    event_payload=$(cat "$dead_event")
                    local event_id
                    event_id=$(basename "$dead_event" .event)
                    
                    # Move back to processing queue
                    mv "$dead_event" "$UNITY_EVENTS_DIR/queue/${event_id}.event"
                    rm -f "${dead_event}.reason"
                    
                    if command -v unity_log >/dev/null 2>&1; then
                        unity_log "INFO" "Retrying dead letter event: $event_id"
                    fi
                fi
            done
            ;;
        delete)
            find "$UNITY_EVENT_DEAD_LETTER_DIR" -name '*.event' -type f | while read -r dead_event; do
                if [[ "$(basename "$dead_event")" =~ $pattern ]]; then
                    rm -f "$dead_event" "${dead_event}.reason"
                fi
            done
            ;;
    esac
}

#############################################
# Internal Supporting Functions
#############################################

# Initialize event configuration
_init_event_config() {
    cat > "$UNITY_EVENT_CONFIG_FILE" <<EOF
# Unity Event System Configuration
MAX_RETRIES=$UNITY_EVENT_MAX_RETRIES
RETRY_DELAY=$UNITY_EVENT_RETRY_DELAY
HANDLER_TIMEOUT=$UNITY_EVENT_HANDLER_TIMEOUT
BATCH_SIZE=$UNITY_EVENT_BATCH_SIZE
AUDIT_RETENTION_DAYS=$UNITY_EVENT_AUDIT_RETENTION_DAYS
EOF
}

# Initialize event types registry
_init_event_types_registry() {
    cat > "$UNITY_EVENTS_DIR/event-types.txt" <<'EVENTS_EOF'
# Unity Event Types - Enhanced Schema v2.0
# Format: EVENT_TYPE|CATEGORY|DESCRIPTION

# Deployment Events
deployment.started|deployment|Deployment process initiated
deployment.completed|deployment|Deployment successfully completed
deployment.failed|deployment|Deployment failed with error
deployment.rollback_started|deployment|Rollback process initiated
deployment.rollback_completed|deployment|Rollback successfully completed
deployment.rollback_failed|deployment|Rollback failed

# AWS Service Events
aws.resource.created|aws|AWS resource created
aws.resource.deleted|aws|AWS resource deleted
aws.resource.modified|aws|AWS resource modified
aws.ec2.launched|aws|EC2 instance launched
aws.ec2.terminated|aws|EC2 instance terminated
aws.vpc.created|aws|VPC created
aws.alb.created|aws|Application Load Balancer created
aws.cost.threshold_exceeded|aws|Cost threshold exceeded

# Docker Service Events
docker.container.started|docker|Container started
docker.container.stopped|docker|Container stopped
docker.container.failed|docker|Container failed to start
docker.image.pulled|docker|Docker image pulled
docker.image.built|docker|Docker image built
docker.compose.up|docker|Docker Compose services started
docker.compose.down|docker|Docker Compose services stopped

# Configuration Events
config.loaded|config|Configuration loaded
config.updated|config|Configuration updated
config.validated|config|Configuration validated
config.error|config|Configuration error occurred

# Monitoring Events
monitor.health.check|monitor|Health check performed
monitor.alert.triggered|monitor|Alert triggered
monitor.metric.collected|monitor|Metric collected
monitor.threshold.exceeded|monitor|Threshold exceeded
monitor.service.healthy|monitor|Service is healthy
monitor.service.unhealthy|monitor|Service is unhealthy

# System Events
system.startup|system|System startup
system.shutdown|system|System shutdown
system.error|system|System error occurred
system.warning|system|System warning

# Lock Management Events
lock.LOCK_ACQUIRED|lock|Lock successfully acquired
lock.LOCK_RELEASED|lock|Lock successfully released
lock.LOCK_CONTENTION|lock|Lock contention detected
lock.LOCK_TIMEOUT|lock|Lock acquisition timeout
lock.DEADLOCK_DETECTED|lock|Deadlock detected in lock acquisition
lock.DEADLOCK_RESOLVED|lock|Deadlock resolved by victim selection
lock.STALE_LOCK_CLEANED|lock|Stale lock cleaned up
lock.LOCK_ORDERING_VIOLATION|lock|Lock ordering violation detected
EVENTS_EOF
}

# Initialize handler registry
_init_handler_registry() {
    touch "$UNITY_EVENTS_DIR/handlers.registry"
    touch "$UNITY_EVENTS_DIR/filters.registry"
    touch "$UNITY_EVENTS_DIR/routes.registry"
}

# Initialize event routing
_init_event_routing() {
    mkdir -p "$UNITY_EVENTS_DIR/routes"
    cat > "$UNITY_EVENTS_DIR/routes/default.route" <<'ROUTE_EOF'
# Default routing rules
deployment.*|sync=true
aws.cost.*|priority=high
monitor.alert.*|priority=high
.*\.failed|priority=high,dead_letter_on_fail=true
ROUTE_EOF
}

# Set up periodic cleanup
_setup_event_cleanup() {
    # Create cleanup script that can be called periodically
    cat > "$UNITY_EVENTS_DIR/cleanup.sh" <<'CLEANUP_EOF'
#!/bin/bash
# Automatic event cleanup script

EVENTS_DIR=".unity/events"
AUDIT_LOG="logs/unity/events-audit.log"
RETENTION_DAYS=30

# Clean up old processed events
find "$EVENTS_DIR/processed" -name "*.event" -mtime +7 -delete 2>/dev/null

# Clean up old audit logs
if [[ -f "$AUDIT_LOG" ]]; then
    # Keep only last RETENTION_DAYS days
    tail -n 1000 "$AUDIT_LOG" > "${AUDIT_LOG}.tmp" && mv "${AUDIT_LOG}.tmp" "$AUDIT_LOG"
fi

# Clean up old replay directories
find "$EVENTS_DIR/replay" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
CLEANUP_EOF
    chmod +x "$UNITY_EVENTS_DIR/cleanup.sh"
}

# Log event errors with better error handling
_log_event_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Try to write to audit log if possible
    if [[ -w "$(dirname "$UNITY_EVENT_AUDIT_LOG")" ]]; then
        echo "$timestamp|ERROR|EVENT_BUS|$message" >> "$UNITY_EVENT_AUDIT_LOG" 2>/dev/null || true
    fi
    
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "ERROR" "Event Bus: $message"
    else
        echo "ERROR: Event Bus: $message" >&2
    fi
}

# Validate event payload structure
_validate_event_payload() {
    local payload="$1"
    
    # Basic JSON-like structure validation
    if [[ ! "$payload" =~ ^\{.*\}$ ]]; then
        return 1
    fi
    
    # Check required fields
    for field in "id" "timestamp" "type" "source" "data" "metadata"; do
        if [[ ! "$payload" =~ \"$field\": ]]; then
            return 1
        fi
    done
    
    return 0
}

# Check if event should be processed based on filters
_should_process_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    
    # Apply global filters
    if [[ -f "$UNITY_EVENTS_DIR/filters.registry" ]]; then
        while IFS='|' read -r pattern condition; do
            if [[ "$event_type" =~ $pattern ]]; then
                # Simple condition evaluation (extend as needed)
                case "$condition" in
                    "source=="*) 
                        local expected_source="${condition#source==}"
                        [[ "$event_source" == "$expected_source" ]] || return 1
                        ;;
                    "data.contains=="*)
                        local search_term="${condition#data.contains==}"
                        [[ "$event_data" == *"$search_term"* ]] || return 1
                        ;;
                esac
            fi
        done < "$UNITY_EVENTS_DIR/filters.registry"
    fi
    
    return 0
}

# Persist event for audit trail with error handling
_persist_event() {
    local event_id="$1"
    local event_payload="$2"
    local priority="$3"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local event_type=$(echo "$event_payload" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    local event_source=$(echo "$event_payload" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
    
    # Store in audit log if writable
    if [[ -w "$(dirname "$UNITY_EVENT_AUDIT_LOG")" ]]; then
        echo "$timestamp|$event_source|$event_type|$event_payload" >> "$UNITY_EVENT_AUDIT_LOG" 2>/dev/null || true
    fi
    
    # Store full event data if directories exist
    if [[ -d "$UNITY_EVENTS_DIR/queue" ]]; then
        echo "$event_payload" > "$UNITY_EVENTS_DIR/queue/${event_id}.event" 2>/dev/null || return 1
        echo "$priority" > "$UNITY_EVENTS_DIR/queue/${event_id}.priority" 2>/dev/null || true
        echo "$timestamp" > "$UNITY_EVENTS_DIR/queue/${event_id}.timestamp" 2>/dev/null || true
    else
        return 1
    fi
    
    return 0
}

# Route event to appropriate queue
_route_event() {
    local event_id="$1"
    local event_payload="$2"
    local priority="$3"
    
    local event_type=$(echo "$event_payload" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    
    # Apply routing rules
    if [[ -f "$UNITY_EVENTS_DIR/routes/default.route" ]]; then
        while IFS='|' read -r pattern rules; do
            if [[ "$event_type" =~ $pattern ]]; then
                # Parse routing rules
                if [[ "$rules" == *"priority=high"* ]]; then
                    priority="high"
                elif [[ "$rules" == *"priority=low"* ]]; then
                    priority="low"
                fi
                
                # Update priority file
                echo "$priority" > "$UNITY_EVENTS_DIR/queue/${event_id}.priority"
                break
            fi
        done < "$UNITY_EVENTS_DIR/routes/default.route"
    fi
    
    # Move to priority queue
    mv "$UNITY_EVENTS_DIR/queue/${event_id}.event" "$UNITY_EVENTS_DIR/priorities/$priority/${event_id}.event"
    mv "$UNITY_EVENTS_DIR/queue/${event_id}.priority" "$UNITY_EVENTS_DIR/priorities/$priority/${event_id}.priority" 2>/dev/null
    mv "$UNITY_EVENTS_DIR/queue/${event_id}.timestamp" "$UNITY_EVENTS_DIR/priorities/$priority/${event_id}.timestamp" 2>/dev/null
}

# Process event synchronously
_process_event_sync() {
    local event_id="$1"
    local event_payload="$2"
    
    _execute_event_handlers "$event_id" "$event_payload" "true"
}

# Queue event for asynchronous processing
_queue_event_async() {
    local event_id="$1" 
    local event_payload="$2"
    local priority="$3"
    
    # Event is already queued by _route_event
    UNITY_EVENT_ASYNC_QUEUE_SIZE=$((UNITY_EVENT_ASYNC_QUEUE_SIZE + 1))
}

# Register event handler with metadata
_register_event_handler() {
    local handler_id="$1"
    local event_pattern="$2"
    local handler_function="$3"
    local priority="$4"
    local filter_condition="$5"
    local route_condition="$6"
    local timeout="$7"
    local retry_count="$8"
    
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        UNITY_EVENT_HANDLERS["${event_pattern}::${handler_id}"]="$handler_function"
        UNITY_EVENT_PRIORITIES["${event_pattern}::${handler_id}"]="$priority"
        if [[ -n "$filter_condition" ]]; then
            UNITY_EVENT_FILTERS["${event_pattern}::${handler_id}"]="$filter_condition"
        fi
    else
        # Bash 3.x compatibility
        eval "UNITY_EVENT_${event_pattern//[^a-zA-Z0-9]/_}_HANDLER_${handler_id}='$handler_function'"
        eval "UNITY_EVENT_${event_pattern//[^a-zA-Z0-9]/_}_PRIORITY_${handler_id}='$priority'"
        if [[ -n "$filter_condition" ]]; then
            eval "UNITY_EVENT_${event_pattern//[^a-zA-Z0-9]/_}_FILTER_${handler_id}='$filter_condition'"
        fi
    fi
}

# Persist handler registration
_persist_handler_registration() {
    local handler_id="$1"
    local event_pattern="$2" 
    local handler_function="$3"
    local priority="$4"
    local filter_condition="$5"
    local route_condition="$6"
    local timeout="$7"
    local retry_count="$8"
    
    local registration_line="$handler_id|$event_pattern|$handler_function|$priority|$filter_condition|$route_condition|$timeout|$retry_count"
    echo "$registration_line" >> "$UNITY_EVENTS_DIR/handlers.registry"
}

# Process priority queue
_process_priority_queue() {
    local priority="$1"
    local batch_size="$2"
    local max_processing_time="$3"
    local start_time="$4"
    local -n processed_count_ref="$5"
    
    local queue_dir="$UNITY_EVENTS_DIR/priorities/$priority"
    local count=0
    
    for event_file in "$queue_dir"/*.event; do
        [[ -f "$event_file" ]] || continue
        
        local event_id
        event_id=$(basename "$event_file" .event)
        local event_payload
        event_payload=$(cat "$event_file")
        
        # Process the event
        if _execute_event_handlers "$event_id" "$event_payload" "false"; then
            # Move to processed
            mv "$event_file" "$UNITY_EVENTS_DIR/processed/"
            mv "$queue_dir/${event_id}.priority" "$UNITY_EVENTS_DIR/processed/" 2>/dev/null
            mv "$queue_dir/${event_id}.timestamp" "$UNITY_EVENTS_DIR/processed/" 2>/dev/null
        else
            # Move to failed
            mv "$event_file" "$UNITY_EVENTS_DIR/failed/"
            mv "$queue_dir/${event_id}.priority" "$UNITY_EVENTS_DIR/failed/" 2>/dev/null
            mv "$queue_dir/${event_id}.timestamp" "$UNITY_EVENTS_DIR/failed/" 2>/dev/null
        fi
        
        count=$((count + 1))
        processed_count_ref=$((processed_count_ref + 1))
        
        # Check batch size and time limits
        if [[ $count -ge $batch_size ]] || [[ $(($(date +%s) - start_time)) -gt $max_processing_time ]]; then
            break
        fi
    done
}

# Process async queue
_process_async_queue() {
    local batch_size="$1"
    
    # This is handled by _process_priority_queue for each priority level
    # Reset queue size counter
    UNITY_EVENT_ASYNC_QUEUE_SIZE=0
}

# Execute event handlers for an event
_execute_event_handlers() {
    local event_id="$1"
    local event_payload="$2"
    local is_sync="$3"
    
    local event_type=$(echo "$event_payload" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
    local event_source=$(echo "$event_payload" | grep -o '"source": "[^"]*"' | cut -d'"' -f4)
    local event_data=$(echo "$event_payload" | grep -o '"data": {[^}]*}' | cut -d':' -f2-)
    local timestamp=$(echo "$event_payload" | grep -o '"timestamp": [0-9]*' | cut -d':' -f2 | tr -d ' ')
    
    local success=true
    local handlers_executed=0
    
    # Find matching handlers
    if [[ "$BASH_VERSION_MAJOR" -ge 4 ]]; then
        for handler_key in "${!UNITY_EVENT_HANDLERS[@]}"; do
            local pattern="${handler_key%%::*}"
            if [[ "$event_type" =~ $pattern ]]; then
                local handler="${UNITY_EVENT_HANDLERS[$handler_key]}"
                local handler_id="${handler_key##*::}"
                
                if _execute_single_handler "$handler" "$event_type" "$event_source" "$event_data" "$timestamp" "$handler_id"; then
                    handlers_executed=$((handlers_executed + 1))
                else
                    success=false
                fi
            fi
        done
    else
        # Bash 3.x: Use pattern matching on variable names
        for var in $(compgen -v | grep "^UNITY_EVENT_.*_HANDLER_"); do
            local pattern="${var#UNITY_EVENT_}"
            pattern="${pattern%_HANDLER_*}"
            pattern="${pattern//_/.}"
            
            if [[ "$event_type" =~ $pattern ]]; then
                local handler="${!var}"
                local handler_id="${var##*_}"
                
                if _execute_single_handler "$handler" "$event_type" "$event_source" "$event_data" "$timestamp" "$handler_id"; then
                    handlers_executed=$((handlers_executed + 1))
                else
                    success=false
                fi
            fi
        done
    fi
    
    # Log execution results
    local timestamp_str=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp_str|HANDLER_EXECUTION|$event_type|{\"event_id\":\"$event_id\",\"handlers_executed\":$handlers_executed,\"success\":$success}" >> "$UNITY_EVENT_AUDIT_LOG"
    
    return $([ "$success" = true ] && echo 0 || echo 1)
}

# Execute a single handler with timeout and retry logic
_execute_single_handler() {
    local handler="$1"
    local event_type="$2"
    local event_source="$3"
    local event_data="$4"
    local timestamp="$5"
    local handler_id="$6"
    
    local max_retries="$UNITY_EVENT_MAX_RETRIES"
    local retry_delay="$UNITY_EVENT_RETRY_DELAY"
    local timeout="$UNITY_EVENT_HANDLER_TIMEOUT"
    
    for ((attempt=1; attempt<=max_retries; attempt++)); do
        if timeout "$timeout" bash -c "$handler '$event_type' '$event_source' '$event_data' '$timestamp'" 2>/dev/null; then
            return 0
        else
            local exit_code=$?
            if [[ $attempt -lt $max_retries ]]; then
                sleep "$retry_delay"
            else
                # Final failure - send to dead letter queue
                _send_to_dead_letter_queue "$event_type" "$event_source" "$event_data" "$timestamp" "$handler" "Handler failed after $max_retries attempts (exit code: $exit_code)"
                return 1
            fi
        fi
    done
    
    return 1
}

# Send failed event to dead letter queue
_send_to_dead_letter_queue() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    local handler="$5"
    local failure_reason="$6"
    
    local dead_event_id="dead_$(date +%s%N)_${RANDOM}"
    local dead_event_payload=$(cat <<EOF
{
  "id": "$dead_event_id",
  "timestamp": $timestamp,
  "type": "$event_type",
  "source": "$event_source",
  "data": $event_data,
  "metadata": {
    "failed_handler": "$handler",
    "failure_reason": "$failure_reason",
    "dead_letter_timestamp": $(date +%s)
  }
}
EOF
    )
    
    echo "$dead_event_payload" > "$UNITY_EVENT_DEAD_LETTER_DIR/${dead_event_id}.event"
    echo "$failure_reason" > "$UNITY_EVENT_DEAD_LETTER_DIR/${dead_event_id}.reason"
    
    # Log to audit trail
    local timestamp_str=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp_str|DEAD_LETTER|$event_type|{\"event_id\":\"$dead_event_id\",\"reason\":\"$failure_reason\"}" >> "$UNITY_EVENT_AUDIT_LOG"
}

#############################################
# Enhanced Lock Management with Deadlock Detection
#############################################

# Lock management state
UNITY_LOCK_STATE_DIR=".unity/locks/state"
UNITY_LOCK_DEPENDENCY_GRAPH=".unity/locks/dependency-graph"
UNITY_LOCK_OWNERS_REGISTRY=".unity/locks/owners"
UNITY_LOCK_ACQUISITION_LOG="logs/unity/lock-acquisition.log"
UNITY_LOCK_MAX_TIMEOUT=300  # 5 minutes max
UNITY_LOCK_STALE_TIMEOUT=3600  # 1 hour for stale detection
UNITY_LOCK_BACKOFF_BASE=1
UNITY_LOCK_BACKOFF_MAX=8

# Lock ordering hierarchy to prevent circular dependencies
declare -A UNITY_LOCK_ORDER 2>/dev/null || UNITY_LOCK_ORDER=()
UNITY_LOCK_ORDER["processing.lock"]=100
UNITY_LOCK_ORDER["deployment.lock"]=200
UNITY_LOCK_ORDER["config.lock"]=300
UNITY_LOCK_ORDER["monitor.lock"]=400
UNITY_LOCK_ORDER["cleanup.lock"]=500

# Initialize lock management system
_init_lock_management() {
    mkdir -p "$(dirname "$UNITY_LOCK_STATE_DIR")"
    mkdir -p "$UNITY_LOCK_STATE_DIR"
    mkdir -p "$(dirname "$UNITY_LOCK_DEPENDENCY_GRAPH")"
    mkdir -p "$(dirname "$UNITY_LOCK_OWNERS_REGISTRY")"
    mkdir -p "$(dirname "$UNITY_LOCK_ACQUISITION_LOG")"
    
    # Clean up stale locks on initialization
    _cleanup_stale_locks
    
    # Initialize dependency graph
    echo "# Lock Dependency Graph - PID:LOCK_NAME:DEPENDS_ON" > "$UNITY_LOCK_DEPENDENCY_GRAPH"
    
    # Initialize owners registry
    echo "# Lock Owners Registry - PID:LOCK_NAME:TIMESTAMP:COMMAND" > "$UNITY_LOCK_OWNERS_REGISTRY"
}

# Enhanced lock acquisition with deadlock detection
_acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-30}"
    local requester_info="${3:-unknown}"
    
    # Initialize if not done
    [[ -d "$UNITY_LOCK_STATE_DIR" ]] || _init_lock_management
    
    local lock_name
    lock_name=$(basename "$lock_file")
    local current_pid=$$
    local start_time=$(date +%s)
    local attempt=0
    local backoff_time=$UNITY_LOCK_BACKOFF_BASE
    
    # Validate lock ordering to prevent circular dependencies
    if ! _validate_lock_ordering "$lock_name" "$current_pid"; then
        _log_lock_operation "ERROR" "Lock ordering violation detected for $lock_name by PID $current_pid"
        _emit_lock_event "LOCK_ORDERING_VIOLATION" "$lock_name" "$current_pid" "$requester_info"
        return 1
    fi
    
    _log_lock_operation "INFO" "Attempting to acquire lock $lock_name (PID: $current_pid, timeout: ${timeout}s)"
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        attempt=$((attempt + 1))
        
        # Check for deadlock before each attempt
        if _detect_deadlock "$lock_name" "$current_pid"; then
            _log_lock_operation "ERROR" "Deadlock detected for lock $lock_name by PID $current_pid"
            _emit_lock_event "DEADLOCK_DETECTED" "$lock_name" "$current_pid" "$requester_info"
            _resolve_deadlock "$lock_name" "$current_pid"
            return 1
        fi
        
        # Try to acquire lock atomically
        if (set -C; echo "$current_pid|$(date +%s)|$requester_info" > "$lock_file") 2>/dev/null; then
            # Successfully acquired lock
            _register_lock_owner "$lock_name" "$current_pid" "$requester_info"
            _update_dependency_graph "$lock_name" "$current_pid" "acquired"
            _log_lock_operation "INFO" "Successfully acquired lock $lock_name (PID: $current_pid, attempt: $attempt)"
            _emit_lock_event "LOCK_ACQUIRED" "$lock_name" "$current_pid" "$requester_info"
            return 0
        fi
        
        # Lock acquisition failed - analyze why
        local current_owner
        current_owner=$(_get_lock_owner "$lock_file")
        
        if [[ -n "$current_owner" ]]; then
            local owner_pid
            owner_pid=$(echo "$current_owner" | cut -d'|' -f1)
            
            # Check if owner process is still alive
            if ! _is_process_alive "$owner_pid"; then
                _log_lock_operation "WARN" "Detected stale lock $lock_name owned by dead PID $owner_pid"
                _cleanup_stale_lock "$lock_file" "$owner_pid"
                continue  # Retry immediately after cleanup
            fi
            
            # Update dependency graph for waiting
            _update_dependency_graph "$lock_name" "$current_pid" "waiting:$owner_pid"
            
            # Log contention
            if [[ $attempt -eq 1 ]]; then
                _log_lock_operation "WARN" "Lock contention detected for $lock_name (current owner: PID $owner_pid)"
                _emit_lock_event "LOCK_CONTENTION" "$lock_name" "$current_pid" "waiting_for:$owner_pid"
            fi
        fi
        
        # Exponential backoff with jitter (bash-compatible without bc)
        local jitter_ms=$((RANDOM % 1000))  # 0-999ms jitter
        local base_sleep_ms=$((backoff_time * 1000))  # Convert to milliseconds
        local total_sleep_ms=$((base_sleep_ms + jitter_ms))
        
        # Convert milliseconds to seconds for sleep (bash integer arithmetic)
        local sleep_seconds=$((total_sleep_ms / 1000))
        local sleep_fraction=$((total_sleep_ms % 1000))
        
        if [[ $sleep_seconds -gt 0 ]]; then
            sleep "$sleep_seconds"
        fi
        
        # Add fractional sleep for jitter (using millisecond precision)
        if [[ $sleep_fraction -gt 0 ]]; then
            sleep "0.$sleep_fraction" 2>/dev/null || sleep 1
        fi
        
        # Increase backoff time
        if [[ $backoff_time -lt $UNITY_LOCK_BACKOFF_MAX ]]; then
            backoff_time=$((backoff_time * 2))
        fi
    done
    
    # Timeout reached
    _log_lock_operation "ERROR" "Failed to acquire lock $lock_name within ${timeout}s (PID: $current_pid, attempts: $attempt)"
    _emit_lock_event "LOCK_TIMEOUT" "$lock_name" "$current_pid" "timeout:${timeout}s"
    _update_dependency_graph "$lock_name" "$current_pid" "timeout"
    
    return 1
}

# Enhanced lock release with proper cleanup
_release_lock() {
    local lock_file="$1"
    local force="${2:-false}"
    
    local lock_name
    lock_name=$(basename "$lock_file")
    local current_pid=$$
    
    # Verify we own this lock (unless forced)
    if [[ "$force" != "true" ]]; then
        local current_owner
        current_owner=$(_get_lock_owner "$lock_file")
        
        if [[ -n "$current_owner" ]]; then
            local owner_pid
            owner_pid=$(echo "$current_owner" | cut -d'|' -f1)
            
            if [[ "$owner_pid" != "$current_pid" ]]; then
                _log_lock_operation "ERROR" "Attempted to release lock $lock_name not owned by PID $current_pid (owned by PID $owner_pid)"
                return 1
            fi
        fi
    fi
    
    # Remove lock file
    if rm -f "$lock_file" 2>/dev/null; then
        # Clean up registry entries
        _unregister_lock_owner "$lock_name" "$current_pid"
        _update_dependency_graph "$lock_name" "$current_pid" "released"
        
        _log_lock_operation "INFO" "Successfully released lock $lock_name (PID: $current_pid)"
        _emit_lock_event "LOCK_RELEASED" "$lock_name" "$current_pid" "normal"
        
        return 0
    else
        _log_lock_operation "WARN" "Failed to remove lock file $lock_file"
        return 1
    fi
}

# Deadlock detection using cycle detection in dependency graph
_detect_deadlock() {
    local requesting_lock="$1"
    local requesting_pid="$2"
    
    # Get current lock holder of requested lock
    local current_owner
    current_owner=$(_get_lock_owner "$UNITY_EVENT_LOCK_DIR/$requesting_lock")
    
    [[ -n "$current_owner" ]] || return 1
    
    local owner_pid
    owner_pid=$(echo "$current_owner" | cut -d'|' -f1)
    
    # Perform cycle detection using DFS
    _detect_cycle_dfs "$requesting_pid" "$owner_pid" "$requesting_lock" ""
}

# Depth-first search for cycle detection
_detect_cycle_dfs() {
    local start_pid="$1"
    local current_pid="$2"
    local target_lock="$3"
    local visited="$4"
    
    # Check if we've come full circle
    if [[ "$current_pid" == "$start_pid" ]]; then
        return 0  # Cycle detected
    fi
    
    # Check if already visited (avoid infinite loops)
    if [[ "$visited" == *"$current_pid"* ]]; then
        return 1  # No cycle in this path
    fi
    
    # Add current PID to visited
    visited="$visited $current_pid"
    
    # Find what locks this PID is waiting for
    while IFS=':' read -r pid lock depends_on; do
        if [[ "$pid" == "$current_pid" && "$depends_on" =~ ^waiting: ]]; then
            local waiting_for_pid
            waiting_for_pid=$(echo "$depends_on" | cut -d':' -f2)
            
            # Recursively check
            if _detect_cycle_dfs "$start_pid" "$waiting_for_pid" "$target_lock" "$visited"; then
                return 0
            fi
        fi
    done < "$UNITY_LOCK_DEPENDENCY_GRAPH" 2>/dev/null || return 1
    
    return 1
}

# Resolve deadlocks by selecting a victim based on lock ordering
_resolve_deadlock() {
    local lock_name="$1"
    local current_pid="$2"
    
    _log_lock_operation "WARN" "Attempting to resolve deadlock for lock $lock_name"
    
    # Select victim process (process with highest lock order number)
    local victim_pid
    victim_pid=$(_select_deadlock_victim "$lock_name" "$current_pid")
    
    if [[ -n "$victim_pid" ]]; then
        _log_lock_operation "INFO" "Selected PID $victim_pid as deadlock victim"
        
        # Force release locks held by victim
        _force_release_locks_by_pid "$victim_pid"
        
        # Send termination signal to victim process
        if kill -TERM "$victim_pid" 2>/dev/null; then
            _log_lock_operation "INFO" "Sent TERM signal to victim PID $victim_pid"
            sleep 2
            
            # Force kill if still alive
            if _is_process_alive "$victim_pid"; then
                kill -KILL "$victim_pid" 2>/dev/null
                _log_lock_operation "WARN" "Force killed victim PID $victim_pid"
            fi
        fi
        
        _emit_lock_event "DEADLOCK_RESOLVED" "$lock_name" "$current_pid" "victim:$victim_pid"
    fi
}

# Select deadlock victim based on lock ordering and process priority
_select_deadlock_victim() {
    local lock_name="$1"
    local current_pid="$2"
    
    # Simple strategy: select the current requesting process as victim
    # In a more sophisticated implementation, we could consider:
    # - Process priority
    # - Number of locks held
    # - Lock hierarchy position
    # - Process start time
    
    echo "$current_pid"
}

# Validate lock ordering to prevent circular dependencies
_validate_lock_ordering() {
    local new_lock="$1"
    local pid="$2"
    
    # Get current locks held by this PID
    local held_locks
    held_locks=$(_get_locks_held_by_pid "$pid")
    
    # Check if new lock violates ordering
    local new_lock_order
    new_lock_order=${UNITY_LOCK_ORDER[$new_lock]:-999}
    
    while read -r held_lock; do
        [[ -n "$held_lock" ]] || continue
        
        local held_lock_order
        held_lock_order=${UNITY_LOCK_ORDER[$held_lock]:-999}
        
        # New lock must have higher order number than held locks
        if [[ $new_lock_order -le $held_lock_order ]]; then
            _log_lock_operation "ERROR" "Lock ordering violation: trying to acquire $new_lock (order $new_lock_order) while holding $held_lock (order $held_lock_order)"
            return 1
        fi
    done <<< "$held_locks"
    
    return 0
}

# Get locks currently held by a PID
_get_locks_held_by_pid() {
    local pid="$1"
    
    while IFS=':' read -r owner_pid lock_name timestamp command; do
        if [[ "$owner_pid" == "$pid" ]]; then
            echo "$lock_name"
        fi
    done < "$UNITY_LOCK_OWNERS_REGISTRY" 2>/dev/null
}

# Get current owner of a lock file
_get_lock_owner() {
    local lock_file="$1"
    
    if [[ -f "$lock_file" ]]; then
        cat "$lock_file" 2>/dev/null || echo ""
    fi
}

# Check if a process is still alive
_is_process_alive() {
    local pid="$1"
    
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Clean up stale locks (from dead processes)
_cleanup_stale_locks() {
    local current_time=$(date +%s)
    
    # Clean up stale lock files
    find "$UNITY_EVENT_LOCK_DIR" -name "*.lock" -type f 2>/dev/null | while read -r lock_file; do
        local owner_info
        owner_info=$(_get_lock_owner "$lock_file")
        
        if [[ -n "$owner_info" ]]; then
            local owner_pid
            local lock_timestamp
            owner_pid=$(echo "$owner_info" | cut -d'|' -f1)
            lock_timestamp=$(echo "$owner_info" | cut -d'|' -f2)
            
            # Check if process is dead or lock is too old
            if ! _is_process_alive "$owner_pid" || [[ $((current_time - lock_timestamp)) -gt $UNITY_LOCK_STALE_TIMEOUT ]]; then
                _cleanup_stale_lock "$lock_file" "$owner_pid"
            fi
        fi
    done
    
    # Clean up stale registry entries
    _cleanup_stale_registry_entries
}

# Clean up a specific stale lock
_cleanup_stale_lock() {
    local lock_file="$1"
    local stale_pid="$2"
    
    local lock_name
    lock_name=$(basename "$lock_file")
    
    if rm -f "$lock_file" 2>/dev/null; then
        _unregister_lock_owner "$lock_name" "$stale_pid"
        _update_dependency_graph "$lock_name" "$stale_pid" "stale_cleanup"
        
        _log_lock_operation "INFO" "Cleaned up stale lock $lock_name from dead PID $stale_pid"
        _emit_lock_event "STALE_LOCK_CLEANED" "$lock_name" "$stale_pid" "automatic"
    fi
}

# Clean up stale entries from registry files
_cleanup_stale_registry_entries() {
    local temp_file
    temp_file=$(mktemp)
    
    # Clean owners registry
    if [[ -f "$UNITY_LOCK_OWNERS_REGISTRY" ]]; then
        while IFS=':' read -r pid lock_name timestamp command; do
            if [[ "$pid" =~ ^[0-9]+$ ]] && _is_process_alive "$pid"; then
                echo "$pid:$lock_name:$timestamp:$command"
            fi
        done < "$UNITY_LOCK_OWNERS_REGISTRY" > "$temp_file"
        
        mv "$temp_file" "$UNITY_LOCK_OWNERS_REGISTRY"
    fi
    
    # Clean dependency graph
    if [[ -f "$UNITY_LOCK_DEPENDENCY_GRAPH" ]]; then
        grep -E '^#|^[0-9]+:' "$UNITY_LOCK_DEPENDENCY_GRAPH" | while IFS=':' read -r pid lock_name status; do
            if [[ "$pid" =~ ^# ]] || ([[ "$pid" =~ ^[0-9]+$ ]] && _is_process_alive "$pid"); then
                echo "$pid:$lock_name:$status"
            fi
        done > "$temp_file"
        
        mv "$temp_file" "$UNITY_LOCK_DEPENDENCY_GRAPH"
    fi
    
    rm -f "$temp_file"
}

# Register lock owner in registry
_register_lock_owner() {
    local lock_name="$1"
    local pid="$2"
    local requester_info="$3"
    
    local timestamp=$(date +%s)
    local command
    command=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
    
    echo "$pid:$lock_name:$timestamp:$command:$requester_info" >> "$UNITY_LOCK_OWNERS_REGISTRY"
}

# Unregister lock owner from registry
_unregister_lock_owner() {
    local lock_name="$1"
    local pid="$2"
    
    local temp_file
    temp_file=$(mktemp)
    
    if [[ -f "$UNITY_LOCK_OWNERS_REGISTRY" ]]; then
        grep -v "^$pid:$lock_name:" "$UNITY_LOCK_OWNERS_REGISTRY" > "$temp_file" || true
        mv "$temp_file" "$UNITY_LOCK_OWNERS_REGISTRY"
    fi
}

# Update lock dependency graph
_update_dependency_graph() {
    local lock_name="$1"
    local pid="$2"
    local status="$3"  # acquired, waiting:PID, released, timeout, stale_cleanup
    
    local temp_file
    temp_file=$(mktemp)
    
    # Remove existing entries for this PID and lock
    if [[ -f "$UNITY_LOCK_DEPENDENCY_GRAPH" ]]; then
        grep -v "^$pid:$lock_name:" "$UNITY_LOCK_DEPENDENCY_GRAPH" > "$temp_file" || true
    fi
    
    # Add new entry (except for released/cleanup statuses)
    if [[ "$status" != "released" && "$status" != "stale_cleanup" ]]; then
        echo "$pid:$lock_name:$status" >> "$temp_file"
    fi
    
    mv "$temp_file" "$UNITY_LOCK_DEPENDENCY_GRAPH"
}

# Force release all locks held by a PID
_force_release_locks_by_pid() {
    local pid="$1"
    
    _log_lock_operation "WARN" "Force releasing all locks held by PID $pid"
    
    # Find all locks held by this PID
    local locks_to_release
    locks_to_release=$(_get_locks_held_by_pid "$pid")
    
    while read -r lock_name; do
        [[ -n "$lock_name" ]] || continue
        
        local lock_file="$UNITY_EVENT_LOCK_DIR/$lock_name"
        if [[ -f "$lock_file" ]]; then
            _release_lock "$lock_file" "true"  # Force release
            _log_lock_operation "INFO" "Force released lock $lock_name from PID $pid"
        fi
    done <<< "$locks_to_release"
}

# Log lock operations
_log_lock_operation() {
    local level="$1"
    local message="$2"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="$timestamp|$level|LOCK_MANAGER|$message"
    
    # Write to lock acquisition log
    if [[ -w "$(dirname "$UNITY_LOCK_ACQUISITION_LOG")" ]]; then
        echo "$log_entry" >> "$UNITY_LOCK_ACQUISITION_LOG" 2>/dev/null || true
    fi
    
    # Also write to main audit log if available
    if [[ -w "$(dirname "$UNITY_EVENT_AUDIT_LOG")" ]]; then
        echo "$log_entry" >> "$UNITY_EVENT_AUDIT_LOG" 2>/dev/null || true
    fi
    
    # Log to Unity logger if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "Lock Manager: $message"
    fi
}

# Emit lock-related events
_emit_lock_event() {
    local event_type="$1"
    local lock_name="$2"
    local pid="$3"
    local details="$4"
    
    local event_data
    event_data=$(cat <<EOF
{
  "lock_name": "$lock_name",
  "pid": $pid,
  "details": "$details",
  "timestamp": $(date +%s)
}
EOF
    )
    
    # Only emit events if unity_emit_event is available and we're not in a recursive call
    if command -v unity_emit_event >/dev/null 2>&1 && [[ "${UNITY_LOCK_EVENT_RECURSION:-false}" != "true" ]]; then
        UNITY_LOCK_EVENT_RECURSION=true
        unity_emit_event "lock.$event_type" "lock_manager" "$event_data" "high" "false" 2>/dev/null || true
        UNITY_LOCK_EVENT_RECURSION=false
    fi
}

# Get comprehensive lock status report
_get_lock_status_report() {
    echo "=== Unity Lock Management Status Report ==="
    echo "Generated: $(date)"
    echo ""
    
    echo "Active Locks:"
    if [[ -f "$UNITY_LOCK_OWNERS_REGISTRY" ]]; then
        while IFS=':' read -r pid lock_name timestamp command requester; do
            if [[ "$pid" =~ ^[0-9]+$ ]] && _is_process_alive "$pid"; then
                local age=$(($(date +%s) - timestamp))
                echo "  $lock_name: PID $pid ($command) - ${age}s old - $requester"
            fi
        done < "$UNITY_LOCK_OWNERS_REGISTRY"
    fi
    
    echo ""
    echo "Lock Dependencies:"
    if [[ -f "$UNITY_LOCK_DEPENDENCY_GRAPH" ]]; then
        grep -v '^#' "$UNITY_LOCK_DEPENDENCY_GRAPH" | while IFS=':' read -r pid lock_name status; do
            if [[ "$pid" =~ ^[0-9]+$ ]] && _is_process_alive "$pid"; then
                echo "  PID $pid: $lock_name -> $status"
            fi
        done
    fi
    
    echo ""
    echo "Recent Lock Operations (last 20):"
    if [[ -f "$UNITY_LOCK_ACQUISITION_LOG" ]]; then
        tail -n 20 "$UNITY_LOCK_ACQUISITION_LOG"
    fi
}

# Export all event functions
export -f unity_init_events
export -f unity_emit_event
export -f unity_on_event
export -f unity_subscribe_event
export -f unity_process_events
export -f unity_replay_events
export -f unity_process_dead_letter_queue

# Export enhanced lock management functions
export -f _init_lock_management
export -f _acquire_lock
export -f _release_lock
export -f _detect_deadlock
export -f _resolve_deadlock
export -f _validate_lock_ordering
export -f _cleanup_stale_locks
export -f _get_lock_status_report
