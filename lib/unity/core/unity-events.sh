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

# Lock management functions
_acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-30}"
    local wait_time=0
    
    while [[ $wait_time -lt $timeout ]]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            return 0
        fi
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    return 1
}

_release_lock() {
    local lock_file="$1"
    rm -f "$lock_file"
}

# Export all event functions
export -f unity_init_events
export -f unity_emit_event
export -f unity_on_event
export -f unity_subscribe_event
export -f unity_process_events
export -f unity_replay_events
export -f unity_process_dead_letter_queue
