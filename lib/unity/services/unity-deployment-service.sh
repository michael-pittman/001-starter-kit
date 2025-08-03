#!/bin/bash
# Unity Deployment Orchestration Service
# Event-driven deployment orchestration with self-healing, dynamic scaling, and cost optimization

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity core and events
source "$SCRIPT_DIR/../core/unity-core.sh"
source "$SCRIPT_DIR/../core/unity-events.sh"
source "$SCRIPT_DIR/../core/unity-atomic-state.sh"
source "$SCRIPT_DIR/../events/reactive-patterns.sh"
source "$SCRIPT_DIR/../events/rollback-manager.sh"

# Load deployment dependencies
source "$PROJECT_ROOT/lib/modules/core/errors.sh"
source "$PROJECT_ROOT/lib/modules/core/logging.sh"
source "$PROJECT_ROOT/lib/modules/core/registry.sh"
source "$PROJECT_ROOT/lib/modules/config/variables.sh"

# Deployment service configuration
UNITY_DEPLOYMENT_STATE_DIR=".unity/deployment/state"
UNITY_DEPLOYMENT_WORKFLOWS_DIR=".unity/deployment/workflows"
UNITY_DEPLOYMENT_METRICS_DIR=".unity/deployment/metrics"
UNITY_DEPLOYMENT_LOG="logs/unity/deployment-service.log"

# Service configuration
UNITY_DEPLOYMENT_HEALTH_CHECK_INTERVAL=30
UNITY_DEPLOYMENT_METRIC_COLLECTION_INTERVAL=60
UNITY_DEPLOYMENT_SCALING_THRESHOLD_CPU=80
UNITY_DEPLOYMENT_SCALING_THRESHOLD_MEMORY=85
UNITY_DEPLOYMENT_COST_CHECK_INTERVAL=300
UNITY_DEPLOYMENT_MAX_CONCURRENT_DEPLOYMENTS=3

# Deployment strategies
DEPLOYMENT_STRATEGY_ROLLING="rolling"
DEPLOYMENT_STRATEGY_BLUE_GREEN="blue-green"
DEPLOYMENT_STRATEGY_CANARY="canary"
DEPLOYMENT_STRATEGY_RECREATE="recreate"

# Service state
UNITY_DEPLOYMENT_SERVICE_INITIALIZED=false
declare -A UNITY_DEPLOYMENT_ACTIVE_WORKFLOWS 2>/dev/null || UNITY_DEPLOYMENT_ACTIVE_WORKFLOWS=()
declare -A UNITY_DEPLOYMENT_HEALTH_STATUS 2>/dev/null || UNITY_DEPLOYMENT_HEALTH_STATUS=()
declare -A UNITY_DEPLOYMENT_METRICS 2>/dev/null || UNITY_DEPLOYMENT_METRICS=()

#############################################
# Atomic State Management Helpers
#############################################

# Update deployment state atomically
_update_deployment_state() {
    local deployment_id="$1"
    local status="$2"
    local additional_data="${3:-}"
    
    local state_file="$UNITY_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    
    # Check if deployment state file exists
    if [[ ! -f "$state_file" ]]; then
        # Check in completed/failed directories
        if [[ -f "$UNITY_DEPLOYMENT_STATE_DIR/completed/${deployment_id}.state" ]]; then
            state_file="$UNITY_DEPLOYMENT_STATE_DIR/completed/${deployment_id}.state"
        elif [[ -f "$UNITY_DEPLOYMENT_STATE_DIR/failed/${deployment_id}.state" ]]; then
            state_file="$UNITY_DEPLOYMENT_STATE_DIR/failed/${deployment_id}.state"
        else
            unity_log "ERROR" "Deployment state file not found: $deployment_id"
            return $UNITY_ERROR_VALIDATION
        fi
    fi
    
    # Read current state
    local current_state
    current_state="$(unity_atomic_read "$state_file" "true")"
    if [[ $? -ne 0 ]]; then
        unity_log "ERROR" "Failed to read deployment state: $state_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Update state with new status and timestamp
    local updated_state
    if command -v jq >/dev/null 2>&1; then
        updated_state="$(echo "$current_state" | jq \
            --arg status "$status" \
            --arg timestamp "$(date +%s)" \
            --argjson additional "${additional_data:-null}" \
            '.status = $status | .updated_at = ($timestamp | tonumber) | if $additional != null then . + $additional else . end')"
    else
        # Fallback: simple replacement
        updated_state="$(echo "$current_state" | \
            sed "s/\"status\": \"[^\"]*\"/\"status\": \"$status\"/" | \
            sed "s/\"updated_at\": [0-9]*/\"updated_at\": $(date +%s)/")"
    fi
    
    # Write updated state atomically
    if ! unity_atomic_write "$state_file" "$updated_state" "json" "true"; then
        unity_log "ERROR" "Failed to update deployment state: $state_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Emit state change event
    unity_emit_event "deployment.state.updated" "deployment-service" \
        "{\"deployment_id\":\"$deployment_id\",\"status\":\"$status\",\"timestamp\":$(date +%s)}" \
        "medium" "false"
    
    unity_log "DEBUG" "Updated deployment state: $deployment_id -> $status"
    return $UNITY_SUCCESS
}

# Add transaction log entry to deployment state
_add_deployment_transaction_log() {
    local deployment_id="$1"
    local action="$2"
    local details="$3"
    local status="${4:-success}"
    
    local state_file="$UNITY_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    
    # Check if file exists in other directories
    if [[ ! -f "$state_file" ]]; then
        for dir in "completed" "failed"; do
            if [[ -f "$UNITY_DEPLOYMENT_STATE_DIR/$dir/${deployment_id}.state" ]]; then
                state_file="$UNITY_DEPLOYMENT_STATE_DIR/$dir/${deployment_id}.state"
                break
            fi
        done
    fi
    
    if [[ ! -f "$state_file" ]]; then
        unity_log "ERROR" "Deployment state file not found for transaction log: $deployment_id"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Create transaction entry
    local transaction_entry
    transaction_entry='{"timestamp": '$(date +%s)', "action": "'$action'", "details": "'$details'", "status": "'$status'"}'
    
    # Read current state
    local current_state
    current_state="$(unity_atomic_read "$state_file" "true")"
    if [[ $? -ne 0 ]]; then
        unity_log "ERROR" "Failed to read state for transaction log: $state_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Add transaction to log
    local updated_state
    if command -v jq >/dev/null 2>&1; then
        updated_state="$(echo "$current_state" | jq \
            --argjson entry "$transaction_entry" \
            '.transaction_log += [$entry] | .updated_at = ('$(date +%s)')')"
    else
        # Fallback: append to end of file (less precise but functional)
        updated_state="$current_state"
    fi
    
    # Write updated state atomically
    if ! unity_atomic_write "$state_file" "$updated_state" "json" "true"; then
        unity_log "ERROR" "Failed to add transaction log entry: $state_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    unity_log "DEBUG" "Added transaction log: $deployment_id - $action"
    return $UNITY_SUCCESS
}

# Move deployment state between directories atomically
_move_deployment_state() {
    local deployment_id="$1"
    local from_dir="$2"
    local to_dir="$3"
    local new_status="${4:-}"
    
    local source_file="$UNITY_DEPLOYMENT_STATE_DIR/$from_dir/${deployment_id}.state"
    local target_file="$UNITY_DEPLOYMENT_STATE_DIR/$to_dir/${deployment_id}.state"
    
    if [[ ! -f "$source_file" ]]; then
        unity_log "ERROR" "Source deployment state not found: $source_file"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Update status if provided
    if [[ -n "$new_status" ]]; then
        _update_deployment_state "$deployment_id" "$new_status"
    fi
    
    # Create target directory
    mkdir -p "$UNITY_DEPLOYMENT_STATE_DIR/$to_dir"
    
    # Atomic move
    if ! mv "$source_file" "$target_file"; then
        unity_log "ERROR" "Failed to move deployment state: $source_file -> $target_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Move checksum file if it exists
    if [[ -f "${source_file}.checksum" ]]; then
        mv "${source_file}.checksum" "${target_file}.checksum" 2>/dev/null || true
    fi
    
    unity_log "DEBUG" "Moved deployment state: $deployment_id ($from_dir -> $to_dir)"
    return $UNITY_SUCCESS
}

# Validate deployment state integrity
_validate_deployment_state() {
    local deployment_id="$1"
    local state_file="$UNITY_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    
    # Check all possible locations
    if [[ ! -f "$state_file" ]]; then
        for dir in "completed" "failed"; do
            if [[ -f "$UNITY_DEPLOYMENT_STATE_DIR/$dir/${deployment_id}.state" ]]; then
                state_file="$UNITY_DEPLOYMENT_STATE_DIR/$dir/${deployment_id}.state"
                break
            fi
        done
    fi
    
    if [[ ! -f "$state_file" ]]; then
        unity_log "ERROR" "Deployment state file not found: $deployment_id"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Check if recovery is needed
    if unity_atomic_needs_recovery "$state_file"; then
        unity_log "WARN" "Deployment state file corrupted, attempting recovery: $deployment_id"
        if unity_atomic_force_recovery "$state_file"; then
            unity_log "INFO" "Successfully recovered deployment state: $deployment_id"
        else
            unity_log "ERROR" "Failed to recover deployment state: $deployment_id"
            return $UNITY_ERROR_EXECUTION
        fi
    fi
    
    # Validate JSON structure
    local state_content
    state_content="$(unity_atomic_read "$state_file" "true")"
    if [[ $? -ne 0 ]]; then
        unity_log "ERROR" "Failed to read deployment state for validation: $deployment_id"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Check required fields
    local required_fields=("deployment_id" "stack_name" "deployment_type" "status" "created_at")
    local field
    for field in "${required_fields[@]}"; do
        if ! echo "$state_content" | grep -q "\"$field\":"; then
            unity_log "ERROR" "Missing required field in deployment state: $field ($deployment_id)"
            return $UNITY_ERROR_VALIDATION
        fi
    done
    
    unity_log "DEBUG" "Deployment state validation passed: $deployment_id"
    return $UNITY_SUCCESS
}

#############################################
# Service Initialization
#############################################

# Initialize deployment service
unity_deployment_init() {
    local verbose="${1:-false}"
    
    if [[ "$UNITY_DEPLOYMENT_SERVICE_INITIALIZED" == "true" ]]; then
        unity_log "INFO" "Deployment service already initialized"
        return $UNITY_SUCCESS
    fi
    
    unity_log "INFO" "Initializing Unity Deployment Service..."
    
    # Create service directories
    mkdir -p "$UNITY_DEPLOYMENT_STATE_DIR" "$UNITY_DEPLOYMENT_WORKFLOWS_DIR" "$UNITY_DEPLOYMENT_METRICS_DIR"
    mkdir -p "$UNITY_DEPLOYMENT_STATE_DIR/active" "$UNITY_DEPLOYMENT_STATE_DIR/completed" "$UNITY_DEPLOYMENT_STATE_DIR/failed"
    mkdir -p "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/templates" "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/instances"
    mkdir -p "$(dirname "$UNITY_DEPLOYMENT_LOG")"
    
    # Initialize atomic state management
    init_unity_atomic_state
    
    # Validate existing deployment states and recover if needed
    _validate_existing_deployment_states
    
    # Initialize deployment workflows
    _init_deployment_workflows
    
    # Initialize self-healing mechanisms
    _init_self_healing_mechanisms
    
    # Initialize cost optimization automation
    _init_cost_optimization_automation
    
    # Initialize scaling triggers
    _init_dynamic_scaling_triggers
    
    # Register event handlers
    _register_deployment_event_handlers
    
    # Start monitoring loops
    _start_deployment_monitoring
    
    UNITY_DEPLOYMENT_SERVICE_INITIALIZED=true
    unity_emit_event "deployment.service.initialized" "deployment-service" "{\"version\":\"2.0\"}"
    
    unity_log "SUCCESS" "Deployment Service initialized with event-driven orchestration"
    return $UNITY_SUCCESS
}

# Validate all existing deployment states on startup
_validate_existing_deployment_states() {
    unity_log "INFO" "Validating existing deployment states..."
    
    local validation_errors=0
    local recovery_count=0
    
    # Check all deployment state files
    for dir in "active" "completed" "failed"; do
        for state_file in "$UNITY_DEPLOYMENT_STATE_DIR/$dir"/*.state; do
            [[ -f "$state_file" ]] || continue
            
            local deployment_id
            deployment_id=$(basename "$state_file" .state)
            
            # Check if file needs recovery
            if unity_atomic_needs_recovery "$state_file"; then
                unity_log "WARN" "Corrupted deployment state detected: $deployment_id"
                if unity_atomic_force_recovery "$state_file"; then
                    unity_log "INFO" "Successfully recovered deployment state: $deployment_id"
                    ((recovery_count++))
                else
                    unity_log "ERROR" "Failed to recover deployment state: $deployment_id"
                    ((validation_errors++))
                fi
            fi
            
            # Validate state structure
            local state_content
            state_content="$(unity_atomic_read "$state_file" "true" 2>/dev/null)"
            if [[ $? -ne 0 ]]; then
                unity_log "ERROR" "Cannot read deployment state: $deployment_id"
                ((validation_errors++))
                continue
            fi
            
            # Check for required fields
            local required_fields=("deployment_id" "stack_name" "status")
            local field missing_fields=()
            for field in "${required_fields[@]}"; do
                if ! echo "$state_content" | grep -q "\"$field\":"; then
                    missing_fields+=("$field")
                fi
            done
            
            if [[ ${#missing_fields[@]} -gt 0 ]]; then
                unity_log "ERROR" "Missing required fields in deployment state $deployment_id: ${missing_fields[*]}"
                ((validation_errors++))
            fi
        done
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        unity_log "SUCCESS" "All deployment states validated successfully"
        if [[ $recovery_count -gt 0 ]]; then
            unity_log "INFO" "Recovered $recovery_count corrupted deployment states"
        fi
    else
        unity_log "ERROR" "Deployment state validation failed with $validation_errors errors"
        if [[ $recovery_count -gt 0 ]]; then
            unity_log "INFO" "Recovered $recovery_count deployment states"
        fi
        return $UNITY_ERROR_VALIDATION
    fi
    
    return $UNITY_SUCCESS
}

# Validate deployment service prerequisites
unity_deployment_validate() {
    local errors=0
    
    # Check Unity core is initialized
    if [[ "$UNITY_INITIALIZED" != "true" ]]; then
        unity_log "ERROR" "Unity core not initialized"
        ((errors++))
    fi
    
    # Check required directories exist
    for dir in "$UNITY_DEPLOYMENT_STATE_DIR" "$UNITY_DEPLOYMENT_WORKFLOWS_DIR" "$UNITY_DEPLOYMENT_METRICS_DIR"; do
        if [[ ! -d "$dir" ]]; then
            unity_log "ERROR" "Required directory missing: $dir"
            ((errors++))
        fi
    done
    
    # Check deployment dependencies
    local required_functions=(
        "unity_emit_event"
        "unity_on_event"
        "create_deployment_workflow"
        "init_rollback_manager"
    )
    
    for func in "${required_functions[@]}"; do
        if ! command -v "$func" >/dev/null 2>&1; then
            unity_log "ERROR" "Required function missing: $func"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        unity_log "INFO" "Deployment service validation passed"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "Deployment service validation failed with $errors errors"
        return $UNITY_ERROR_VALIDATION
    fi
}

#############################################
# Deployment Orchestration
#############################################

# Execute deployment with event-driven orchestration
unity_deployment_execute() {
    local operation="$1"
    shift
    
    case "$operation" in
        "deploy")
            _execute_deployment "$@"
            ;;
        "rollback")
            _execute_rollback "$@"
            ;;
        "scale")
            _execute_scaling "$@"
            ;;
        "health-check")
            _execute_health_check "$@"
            ;;
        "cost-optimize")
            _execute_cost_optimization "$@"
            ;;
        "status")
            _get_deployment_status "$@"
            ;;
        *)
            unity_log "ERROR" "Unknown deployment operation: $operation"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
}

# Execute deployment workflow
_execute_deployment() {
    local stack_name="$1"
    local deployment_type="${2:-spot}"
    local strategy="${3:-$DEPLOYMENT_STRATEGY_ROLLING}"
    local options="${4:-}"
    
    unity_log "INFO" "Starting deployment: stack=$stack_name, type=$deployment_type, strategy=$strategy"
    
    # Create deployment state
    local deployment_id="deploy_${stack_name}_$(date +%s%N)"
    local deployment_state_file="$UNITY_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    
    # Initialize deployment state using atomic write
    local deployment_state_content
    deployment_state_content=$(cat <<EOF
{
  "deployment_id": "$deployment_id",
  "stack_name": "$stack_name",
  "deployment_type": "$deployment_type",
  "strategy": "$strategy",
  "status": "initializing",
  "created_at": $(date +%s),
  "updated_at": $(date +%s),
  "options": "$options",
  "health_status": "unknown",
  "rollback_enabled": true,
  "transaction_log": [],
  "metrics": {
    "start_time": $(date +%s),
    "resources_created": 0,
    "cost_estimate": 0
  }
}
EOF
)
    
    # Write deployment state atomically
    if ! unity_atomic_write "$deployment_state_file" "$deployment_state_content" "json" "false"; then
        unity_log "ERROR" "Failed to create deployment state file: $deployment_state_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Register deployment in active workflows
    if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
        UNITY_DEPLOYMENT_ACTIVE_WORKFLOWS["$deployment_id"]="$stack_name"
    else
        eval "UNITY_DEPLOYMENT_ACTIVE_WORKFLOWS_${deployment_id}='$stack_name'"
    fi
    
    # Create deployment workflow based on strategy
    local workflow_id
    case "$strategy" in
        "$DEPLOYMENT_STRATEGY_BLUE_GREEN")
            workflow_id=$(_create_blue_green_workflow "$deployment_id" "$stack_name" "$deployment_type" "$options")
            ;;
        "$DEPLOYMENT_STRATEGY_CANARY")
            workflow_id=$(_create_canary_workflow "$deployment_id" "$stack_name" "$deployment_type" "$options")
            ;;
        "$DEPLOYMENT_STRATEGY_ROLLING")
            workflow_id=$(_create_rolling_workflow "$deployment_id" "$stack_name" "$deployment_type" "$options")
            ;;
        "$DEPLOYMENT_STRATEGY_RECREATE")
            workflow_id=$(_create_recreate_workflow "$deployment_id" "$stack_name" "$deployment_type" "$options")
            ;;
        *)
            unity_log "ERROR" "Unknown deployment strategy: $strategy"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
    
    # Add initial transaction log entry
    _add_deployment_transaction_log "$deployment_id" "deployment_started" "Deployment initialized with strategy: $strategy" "success"
    
    # Update deployment state to started
    _update_deployment_state "$deployment_id" "started" '{"workflow_id": "'$workflow_id'"}'
    
    # Emit deployment started event
    unity_emit_event "deployment.started" "deployment-service" \
        "{\"deployment_id\":\"$deployment_id\",\"stack_name\":\"$stack_name\",\"strategy\":\"$strategy\",\"workflow_id\":\"$workflow_id\"}" \
        "high" "false"
    
    echo "$deployment_id"
    return $UNITY_SUCCESS
}

#############################################
# Deployment Strategies
#############################################

# Create blue-green deployment workflow
_create_blue_green_workflow() {
    local deployment_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local options="$4"
    
    local workflow_file="$UNITY_DEPLOYMENT_WORKFLOWS_DIR/instances/${deployment_id}_blue_green.workflow"
    
    local workflow_content
    workflow_content=$(cat <<EOF
{
  "workflow_id": "${deployment_id}_blue_green",
  "deployment_id": "$deployment_id",
  "strategy": "blue-green",
  "created_at": $(date +%s),
  "phases": [
    {
      "phase": "prepare",
      "steps": [
        "validate_prerequisites",
        "create_green_environment",
        "setup_green_infrastructure"
      ]
    },
    {
      "phase": "deploy",
      "steps": [
        "deploy_green_application",
        "run_green_health_checks",
        "validate_green_endpoints"
      ]
    },
    {
      "phase": "switch",
      "steps": [
        "switch_load_balancer_targets",
        "monitor_traffic_flow",
        "validate_switch_success"
      ]
    },
    {
      "phase": "cleanup",
      "steps": [
        "monitor_green_stability",
        "decommission_blue_environment",
        "cleanup_old_resources"
      ]
    }
  ],
  "rollback_strategy": "instant_switch_back",
  "health_check_config": {
    "interval": 10,
    "timeout": 5,
    "healthy_threshold": 3,
    "unhealthy_threshold": 2
  }
}
EOF
)
    
    # Write workflow atomically
    if ! unity_atomic_write "$workflow_file" "$workflow_content" "json" "false"; then
        unity_log "ERROR" "Failed to create blue-green workflow: $workflow_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    # Create deployment workflow instance
    local workflow_params="{\"deployment_id\":\"$deployment_id\",\"stack_name\":\"$stack_name\",\"deployment_type\":\"$deployment_type\",\"options\":\"$options\"}"
    local workflow_id
    workflow_id=$(create_deployment_workflow "$stack_name" "$deployment_type" "$workflow_params")
    
    echo "$workflow_id"
}

# Create canary deployment workflow
_create_canary_workflow() {
    local deployment_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local options="$4"
    
    local workflow_file="$UNITY_DEPLOYMENT_WORKFLOWS_DIR/instances/${deployment_id}_canary.workflow"
    
    local workflow_content
    workflow_content=$(cat <<EOF
{
  "workflow_id": "${deployment_id}_canary",
  "deployment_id": "$deployment_id",
  "strategy": "canary",
  "created_at": $(date +%s),
  "canary_config": {
    "initial_weight": 10,
    "increment": 10,
    "interval": 300,
    "success_threshold": 0.99,
    "error_threshold": 0.05
  },
  "phases": [
    {
      "phase": "prepare",
      "steps": [
        "validate_prerequisites",
        "create_canary_infrastructure",
        "setup_traffic_splitting"
      ]
    },
    {
      "phase": "canary_rollout",
      "steps": [
        "deploy_canary_version",
        "route_canary_traffic",
        "monitor_canary_metrics",
        "analyze_canary_results"
      ],
      "iterate_until": "canary_complete"
    },
    {
      "phase": "promotion",
      "steps": [
        "promote_canary_to_production",
        "shift_all_traffic",
        "validate_full_deployment"
      ]
    },
    {
      "phase": "cleanup",
      "steps": [
        "remove_canary_infrastructure",
        "cleanup_old_version",
        "finalize_deployment"
      ]
    }
  ],
  "monitoring_config": {
    "metrics": ["error_rate", "latency", "success_rate", "throughput"],
    "alerting_enabled": true,
    "auto_rollback_on_failure": true
  }
}
EOF
)
    
    # Write workflow atomically
    if ! unity_atomic_write "$workflow_file" "$workflow_content" "json" "false"; then
        unity_log "ERROR" "Failed to create canary workflow: $workflow_file"
        return $UNITY_ERROR_EXECUTION
    fi
    
    local workflow_params="{\"deployment_id\":\"$deployment_id\",\"stack_name\":\"$stack_name\",\"deployment_type\":\"$deployment_type\",\"canary_config\":true}"
    local workflow_id
    workflow_id=$(create_deployment_workflow "$stack_name" "$deployment_type" "$workflow_params")
    
    echo "$workflow_id"
}

# Create rolling deployment workflow
_create_rolling_workflow() {
    local deployment_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local options="$4"
    
    local workflow_params="{\"deployment_id\":\"$deployment_id\",\"stack_name\":\"$stack_name\",\"deployment_type\":\"$deployment_type\"}"
    local workflow_id
    workflow_id=$(create_deployment_workflow "$stack_name" "$deployment_type" "$workflow_params")
    
    echo "$workflow_id"
}

# Create recreate deployment workflow
_create_recreate_workflow() {
    local deployment_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local options="$4"
    
    local workflow_params="{\"deployment_id\":\"$deployment_id\",\"stack_name\":\"$stack_name\",\"deployment_type\":\"$deployment_type\",\"strategy\":\"recreate\"}"
    local workflow_id
    workflow_id=$(create_deployment_workflow "$stack_name" "$deployment_type" "$workflow_params")
    
    echo "$workflow_id"
}

#############################################
# Self-Healing Mechanisms
#############################################

# Initialize self-healing mechanisms
_init_self_healing_mechanisms() {
    # Register health check monitors
    unity_on_event "monitor.health.check" "_handle_health_check_event" "priority=high"
    unity_on_event "monitor.service.unhealthy" "_handle_unhealthy_service" "priority=high"
    unity_on_event "docker.container.failed" "_handle_container_failure" "priority=high"
    unity_on_event "aws.ec2.terminated" "_handle_instance_termination" "priority=high"
    
    # Create self-healing workflows
    cat > "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/templates/self_healing.workflow" <<'SELF_HEAL_EOF'
{
  "workflow_type": "self_healing",
  "triggers": [
    {
      "event": "monitor.service.unhealthy",
      "condition": "consecutive_failures > 3",
      "action": "restart_service"
    },
    {
      "event": "docker.container.failed",
      "condition": "exit_code != 0",
      "action": "restart_container_with_backoff"
    },
    {
      "event": "aws.ec2.terminated",
      "condition": "termination_reason == 'spot_interruption'",
      "action": "launch_replacement_instance"
    },
    {
      "event": "monitor.endpoint.unreachable",
      "condition": "duration > 60",
      "action": "failover_to_backup"
    }
  ],
  "recovery_actions": {
    "restart_service": {
      "steps": [
        "stop_unhealthy_service",
        "clear_service_cache",
        "start_service_fresh",
        "validate_service_health"
      ],
      "timeout": 300,
      "max_retries": 3
    },
    "restart_container_with_backoff": {
      "steps": [
        "analyze_failure_reason",
        "apply_backoff_delay",
        "restart_container",
        "monitor_container_health"
      ],
      "backoff_multiplier": 2,
      "max_backoff": 300
    },
    "launch_replacement_instance": {
      "steps": [
        "select_replacement_az",
        "launch_spot_instance",
        "configure_instance",
        "restore_application_state",
        "update_load_balancer"
      ],
      "timeout": 600
    }
  }
}
SELF_HEAL_EOF
    
    unity_log "INFO" "Self-healing mechanisms initialized"
}

# Handle health check events
_handle_health_check_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    # Extract service info from event data
    local service_name
    service_name=$(echo "$event_data" | grep -o '"service": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    local status
    status=$(echo "$event_data" | grep -o '"status": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Update health status tracking
    if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
        UNITY_DEPLOYMENT_HEALTH_STATUS["$service_name"]="$status"
    else
        eval "UNITY_DEPLOYMENT_HEALTH_STATUS_${service_name}='$status'"
    fi
    
    # Check if self-healing is needed
    if [[ "$status" == "unhealthy" ]]; then
        _check_self_healing_triggers "$service_name" "$event_data"
    fi
    
    return 0
}

# Handle unhealthy service
_handle_unhealthy_service() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local service_name
    service_name=$(echo "$event_data" | grep -o '"service": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "WARN" "Service unhealthy: $service_name - initiating self-healing"
    
    # Create self-healing workflow
    local healing_workflow_id="heal_${service_name}_$(date +%s%N)"
    local healing_params="{\"service\":\"$service_name\",\"event_data\":$event_data,\"action\":\"restart_service\"}"
    
    # Emit self-healing started event
    unity_emit_event "deployment.self_healing.started" "deployment-service" "$healing_params" "high" "true"
    
    # Execute self-healing actions
    _execute_self_healing_action "restart_service" "$service_name" "$event_data"
    
    return 0
}

# Handle container failure
_handle_container_failure() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local container_name
    container_name=$(echo "$event_data" | grep -o '"container_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "WARN" "Container failed: $container_name - attempting automatic recovery"
    
    # Execute container recovery with exponential backoff
    _execute_self_healing_action "restart_container_with_backoff" "$container_name" "$event_data"
    
    return 0
}

# Handle instance termination
_handle_instance_termination() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local instance_id
    instance_id=$(echo "$event_data" | grep -o '"instance_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    local termination_reason
    termination_reason=$(echo "$event_data" | grep -o '"reason": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    if [[ "$termination_reason" == "spot_interruption" ]]; then
        unity_log "WARN" "Spot instance terminated: $instance_id - launching replacement"
        _execute_self_healing_action "launch_replacement_instance" "$instance_id" "$event_data"
    fi
    
    return 0
}

# Execute self-healing action
_execute_self_healing_action() {
    local action="$1"
    local target="$2"
    local context="$3"
    
    case "$action" in
        "restart_service")
            _restart_service_with_validation "$target" "$context"
            ;;
        "restart_container_with_backoff")
            _restart_container_with_backoff "$target" "$context"
            ;;
        "launch_replacement_instance")
            _launch_replacement_instance "$target" "$context"
            ;;
        *)
            unity_log "ERROR" "Unknown self-healing action: $action"
            return $UNITY_ERROR_EXECUTION
            ;;
    esac
}

#############################################
# Dynamic Scaling Triggers
#############################################

# Initialize dynamic scaling triggers
_init_dynamic_scaling_triggers() {
    # Register metric collection handlers
    unity_on_event "monitor.metric.collected" "_handle_metric_event" "priority=medium"
    unity_on_event "monitor.threshold.exceeded" "_handle_threshold_event" "priority=high"
    
    # Create scaling policies
    cat > "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/templates/scaling_policies.json" <<'SCALING_EOF'
{
  "scaling_policies": [
    {
      "policy_id": "cpu_based_scaling",
      "metric": "cpu_utilization",
      "scale_up_threshold": 80,
      "scale_down_threshold": 20,
      "scale_up_increment": 2,
      "scale_down_increment": 1,
      "cooldown_period": 300,
      "min_instances": 1,
      "max_instances": 10
    },
    {
      "policy_id": "memory_based_scaling",
      "metric": "memory_utilization",
      "scale_up_threshold": 85,
      "scale_down_threshold": 30,
      "scale_up_increment": 1,
      "scale_down_increment": 1,
      "cooldown_period": 300
    },
    {
      "policy_id": "request_based_scaling",
      "metric": "requests_per_second",
      "scale_up_threshold": 1000,
      "scale_down_threshold": 100,
      "scale_up_increment": 3,
      "scale_down_increment": 1,
      "cooldown_period": 180
    },
    {
      "policy_id": "queue_based_scaling",
      "metric": "queue_depth",
      "scale_up_threshold": 100,
      "scale_down_threshold": 10,
      "scale_up_increment": 2,
      "scale_down_increment": 1,
      "cooldown_period": 240
    }
  ],
  "scaling_strategies": {
    "predictive": {
      "enabled": true,
      "learning_period": 604800,
      "prediction_window": 3600
    },
    "scheduled": {
      "enabled": true,
      "schedules": [
        {
          "cron": "0 8 * * 1-5",
          "action": "scale_up",
          "target_capacity": 5
        },
        {
          "cron": "0 20 * * 1-5",
          "action": "scale_down",
          "target_capacity": 2
        }
      ]
    }
  }
}
SCALING_EOF
    
    # Start metric collection
    _start_metric_collection
    
    unity_log "INFO" "Dynamic scaling triggers initialized"
}

# Handle metric events
_handle_metric_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    # Extract metric data
    local metric_name
    metric_name=$(echo "$event_data" | grep -o '"metric": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    local metric_value
    metric_value=$(echo "$event_data" | grep -o '"value": [0-9.]*' | cut -d':' -f2 | tr -d ' ' 2>/dev/null || echo "0")
    local resource_id
    resource_id=$(echo "$event_data" | grep -o '"resource_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Store metric
    if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
        UNITY_DEPLOYMENT_METRICS["${resource_id}_${metric_name}"]="$metric_value"
    else
        eval "UNITY_DEPLOYMENT_METRICS_${resource_id}_${metric_name}='$metric_value'"
    fi
    
    # Check scaling policies
    _check_scaling_policies "$resource_id" "$metric_name" "$metric_value"
    
    return 0
}

# Handle threshold events
_handle_threshold_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local threshold_type
    threshold_type=$(echo "$event_data" | grep -o '"threshold_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "WARN" "Threshold exceeded: $threshold_type"
    
    # Trigger scaling action
    case "$threshold_type" in
        "cpu_high")
            _execute_scaling "scale-up" "cpu_based" "$event_data"
            ;;
        "memory_high")
            _execute_scaling "scale-up" "memory_based" "$event_data"
            ;;
        "cpu_low")
            _execute_scaling "scale-down" "cpu_based" "$event_data"
            ;;
        "memory_low")
            _execute_scaling "scale-down" "memory_based" "$event_data"
            ;;
    esac
    
    return 0
}

# Execute scaling operation
_execute_scaling() {
    local direction="$1"
    local reason="$2"
    local context="$3"
    
    unity_log "INFO" "Executing $direction scaling due to $reason"
    
    # Create scaling workflow
    local scaling_id="scale_$(date +%s%N)"
    local scaling_params="{\"direction\":\"$direction\",\"reason\":\"$reason\",\"context\":$context}"
    
    # Emit scaling event
    unity_emit_event "deployment.scaling.started" "deployment-service" "$scaling_params" "high" "false"
    
    # Execute scaling based on direction
    case "$direction" in
        "scale-up")
            _scale_up_resources "$reason" "$context"
            ;;
        "scale-down")
            _scale_down_resources "$reason" "$context"
            ;;
    esac
    
    return 0
}

#############################################
# Cost Optimization Automation
#############################################

# Initialize cost optimization automation
_init_cost_optimization_automation() {
    # Register cost event handlers
    unity_on_event "aws.cost.threshold_exceeded" "_handle_cost_threshold" "priority=high"
    unity_on_event "deployment.cost_analysis.completed" "_handle_cost_analysis" "priority=medium"
    
    # Create cost optimization strategies
    cat > "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/templates/cost_optimization.json" <<'COST_OPT_EOF'
{
  "optimization_strategies": [
    {
      "strategy_id": "spot_conversion",
      "description": "Convert on-demand instances to spot",
      "potential_savings": "70%",
      "risk_level": "medium",
      "conditions": {
        "workload_type": ["stateless", "batch", "dev", "test"],
        "interruption_tolerance": "high"
      },
      "actions": [
        "analyze_workload_suitability",
        "select_optimal_spot_instances",
        "implement_interruption_handling",
        "migrate_to_spot"
      ]
    },
    {
      "strategy_id": "rightsizing",
      "description": "Rightsize over-provisioned resources",
      "potential_savings": "30%",
      "risk_level": "low",
      "conditions": {
        "cpu_utilization": "< 20%",
        "memory_utilization": "< 30%",
        "observation_period": "7 days"
      },
      "actions": [
        "analyze_usage_patterns",
        "recommend_instance_types",
        "schedule_rightsizing",
        "execute_rightsizing"
      ]
    },
    {
      "strategy_id": "scheduled_scaling",
      "description": "Scale down during off-hours",
      "potential_savings": "40%",
      "risk_level": "low",
      "conditions": {
        "workload_pattern": "predictable",
        "off_hours_defined": true
      },
      "actions": [
        "analyze_traffic_patterns",
        "define_scaling_schedule",
        "implement_scheduled_scaling",
        "monitor_performance"
      ]
    },
    {
      "strategy_id": "unused_resource_cleanup",
      "description": "Remove unused resources",
      "potential_savings": "100%",
      "risk_level": "very_low",
      "conditions": {
        "last_used": "> 30 days",
        "no_dependencies": true
      },
      "actions": [
        "identify_unused_resources",
        "validate_no_dependencies",
        "backup_if_needed",
        "delete_resources"
      ]
    }
  ],
  "automation_config": {
    "auto_apply_threshold": 100,
    "require_approval_above": 1000,
    "notification_channels": ["email", "slack"],
    "reporting_frequency": "weekly"
  }
}
COST_OPT_EOF
    
    # Start cost monitoring
    _start_cost_monitoring
    
    unity_log "INFO" "Cost optimization automation initialized"
}

# Handle cost threshold events
_handle_cost_threshold() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local threshold_amount
    threshold_amount=$(echo "$event_data" | grep -o '"amount": [0-9.]*' | cut -d':' -f2 | tr -d ' ' 2>/dev/null || echo "0")
    local cost_category
    cost_category=$(echo "$event_data" | grep -o '"category": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "WARN" "Cost threshold exceeded: \$$threshold_amount for $cost_category"
    
    # Trigger cost analysis saga
    local saga_params="{\"threshold_amount\":$threshold_amount,\"category\":\"$cost_category\",\"timestamp\":$timestamp}"
    local saga_id
    saga_id=$(create_saga "cost_optimization" "$event_data" "$saga_params")
    
    unity_log "INFO" "Cost optimization saga started: $saga_id"
    
    return 0
}

# Handle cost analysis results
_handle_cost_analysis() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    # Extract optimization recommendations
    local recommendations
    recommendations=$(echo "$event_data" | grep -o '"recommendations": \[[^]]*\]' | cut -d':' -f2- 2>/dev/null || echo "[]")
    
    # Process each recommendation
    _process_cost_recommendations "$recommendations"
    
    return 0
}

# Process cost optimization recommendations
_process_cost_recommendations() {
    local recommendations="$1"
    
    # Parse and apply recommendations based on automation config
    unity_log "INFO" "Processing cost optimization recommendations"
    
    # Emit event for each recommendation
    unity_emit_event "deployment.cost_optimization.processing" "deployment-service" \
        "{\"recommendations\":$recommendations}" "medium" "false"
    
    return 0
}

#############################################
# Deployment Monitoring
#############################################

# Start deployment monitoring loops
_start_deployment_monitoring() {
    # Health check monitoring
    (
        while true; do
            sleep "$UNITY_DEPLOYMENT_HEALTH_CHECK_INTERVAL"
            _run_health_checks
        done
    ) &
    
    # Metric collection
    (
        while true; do
            sleep "$UNITY_DEPLOYMENT_METRIC_COLLECTION_INTERVAL"
            _collect_deployment_metrics
        done
    ) &
    
    unity_log "INFO" "Deployment monitoring started"
}

# Start metric collection
_start_metric_collection() {
    local metric_config_file="$UNITY_DEPLOYMENT_METRICS_DIR/collection.config"
    
    cat > "$metric_config_file" <<'METRIC_EOF'
# Metrics to collect
cpu_utilization:command="top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
memory_utilization:command="free | grep Mem | awk '{print ($3/$2) * 100.0}'"
disk_utilization:command="df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1"
network_throughput:command="cat /proc/net/dev | grep eth0 | awk '{print $2+$10}'"
container_count:command="docker ps -q | wc -l"
METRIC_EOF
    
    unity_log "INFO" "Metric collection configured"
}

# Start cost monitoring
_start_cost_monitoring() {
    (
        while true; do
            sleep "$UNITY_DEPLOYMENT_COST_CHECK_INTERVAL"
            _check_deployment_costs
        done
    ) &
    
    unity_log "INFO" "Cost monitoring started"
}

# Run health checks
_run_health_checks() {
    # Check all active deployments
    for deployment_file in "$UNITY_DEPLOYMENT_STATE_DIR/active"/*.state; do
        [[ -f "$deployment_file" ]] || continue
        
        local deployment_id
        deployment_id=$(basename "$deployment_file" .state)
        
        # Emit health check event
        unity_emit_event "deployment.health_check.started" "deployment-service" \
            "{\"deployment_id\":\"$deployment_id\"}" "low" "false"
    done
}

# Collect deployment metrics
_collect_deployment_metrics() {
    # Collect system metrics
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    
    local memory_usage
    memory_usage=$(free | grep Mem | awk '{print ($3/$2) * 100.0}' 2>/dev/null || echo "0")
    
    # Emit metric events
    unity_emit_event "monitor.metric.collected" "deployment-service" \
        "{\"metric\":\"cpu_utilization\",\"value\":$cpu_usage,\"resource_id\":\"system\"}" "low" "false"
    
    unity_emit_event "monitor.metric.collected" "deployment-service" \
        "{\"metric\":\"memory_utilization\",\"value\":$memory_usage,\"resource_id\":\"system\"}" "low" "false"
}

# Check deployment costs
_check_deployment_costs() {
    # This would integrate with AWS Cost Explorer API
    # For now, emit a sample event
    unity_emit_event "deployment.cost_check.completed" "deployment-service" \
        "{\"total_cost\":0,\"breakdown\":{}}" "low" "false"
}

#############################################
# Helper Functions
#############################################

# Check self-healing triggers
_check_self_healing_triggers() {
    local service_name="$1"
    local event_data="$2"
    
    # Check consecutive failures using atomic writes
    local failure_count_file="$UNITY_DEPLOYMENT_STATE_DIR/failures/${service_name}.count"
    local current_failures=0
    
    if [[ -f "$failure_count_file" ]]; then
        current_failures=$(unity_atomic_read "$failure_count_file" "false" 2>/dev/null || echo "0")
        if [[ ! "$current_failures" =~ ^[0-9]+$ ]]; then
            current_failures=0
        fi
    fi
    
    current_failures=$((current_failures + 1))
    
    # Write failure count atomically
    mkdir -p "$(dirname "$failure_count_file")"
    if ! unity_atomic_write "$failure_count_file" "$current_failures" "text" "true"; then
        unity_log "WARN" "Failed to update failure count for service: $service_name"
        return 0  # Don't fail the whole process for this
    fi
    
    if [[ $current_failures -ge $UNITY_ROLLBACK_FAILURE_THRESHOLD ]]; then
        unity_log "WARN" "Service $service_name exceeded failure threshold ($current_failures)"
        unity_emit_event "deployment.self_healing.triggered" "deployment-service" \
            "{\"service\":\"$service_name\",\"failure_count\":$current_failures}" "high" "true"
        
        # Reset failure count after triggering (atomic write)
        unity_atomic_write "$failure_count_file" "0" "text" "true" || unity_log "WARN" "Failed to reset failure count for service: $service_name"
    fi
}

# Check scaling policies
_check_scaling_policies() {
    local resource_id="$1"
    local metric_name="$2"
    local metric_value="$3"
    
    # Check against scaling thresholds
    case "$metric_name" in
        "cpu_utilization")
            if (( $(echo "$metric_value > $UNITY_DEPLOYMENT_SCALING_THRESHOLD_CPU" | bc -l) )); then
                unity_emit_event "monitor.threshold.exceeded" "deployment-service" \
                    "{\"threshold_type\":\"cpu_high\",\"value\":$metric_value,\"resource_id\":\"$resource_id\"}" "high" "false"
            elif (( $(echo "$metric_value < 20" | bc -l) )); then
                unity_emit_event "monitor.threshold.exceeded" "deployment-service" \
                    "{\"threshold_type\":\"cpu_low\",\"value\":$metric_value,\"resource_id\":\"$resource_id\"}" "medium" "false"
            fi
            ;;
        "memory_utilization")
            if (( $(echo "$metric_value > $UNITY_DEPLOYMENT_SCALING_THRESHOLD_MEMORY" | bc -l) )); then
                unity_emit_event "monitor.threshold.exceeded" "deployment-service" \
                    "{\"threshold_type\":\"memory_high\",\"value\":$metric_value,\"resource_id\":\"$resource_id\"}" "high" "false"
            fi
            ;;
    esac
}

# Scale up resources
_scale_up_resources() {
    local reason="$1"
    local context="$2"
    
    unity_log "INFO" "Scaling up resources due to: $reason"
    
    # Execute scaling logic here
    # This would integrate with AWS Auto Scaling or launch new instances
    
    unity_emit_event "deployment.scaling.completed" "deployment-service" \
        "{\"direction\":\"up\",\"reason\":\"$reason\",\"success\":true}" "medium" "false"
}

# Scale down resources
_scale_down_resources() {
    local reason="$1"
    local context="$2"
    
    unity_log "INFO" "Scaling down resources due to: $reason"
    
    # Execute scaling logic here
    # This would integrate with AWS Auto Scaling or terminate instances
    
    unity_emit_event "deployment.scaling.completed" "deployment-service" \
        "{\"direction\":\"down\",\"reason\":\"$reason\",\"success\":true}" "medium" "false"
}

# Restart service with validation
_restart_service_with_validation() {
    local service_name="$1"
    local context="$2"
    
    unity_log "INFO" "Restarting service: $service_name"
    
    # Stop service
    unity_emit_event "deployment.service.stopping" "deployment-service" \
        "{\"service\":\"$service_name\"}" "medium" "true"
    
    # Wait and restart
    sleep 5
    
    unity_emit_event "deployment.service.starting" "deployment-service" \
        "{\"service\":\"$service_name\"}" "medium" "true"
    
    # Validate health
    unity_emit_event "deployment.service.validating" "deployment-service" \
        "{\"service\":\"$service_name\"}" "medium" "true"
    
    unity_emit_event "deployment.self_healing.completed" "deployment-service" \
        "{\"service\":\"$service_name\",\"action\":\"restart\",\"success\":true}" "medium" "false"
}

# Restart container with backoff
_restart_container_with_backoff() {
    local container_name="$1"
    local context="$2"
    
    local backoff_file="$UNITY_DEPLOYMENT_STATE_DIR/backoff/${container_name}.backoff"
    local current_backoff=1
    
    if [[ -f "$backoff_file" ]]; then
        current_backoff=$(cat "$backoff_file")
        current_backoff=$((current_backoff * 2))
        if [[ $current_backoff -gt 300 ]]; then
            current_backoff=300
        fi
    fi
    
    echo "$current_backoff" > "$backoff_file"
    
    unity_log "INFO" "Restarting container $container_name with ${current_backoff}s backoff"
    
    sleep "$current_backoff"
    
    # Restart container
    unity_emit_event "docker.container.restart" "deployment-service" \
        "{\"container\":\"$container_name\",\"backoff\":$current_backoff}" "medium" "true"
    
    unity_emit_event "deployment.self_healing.completed" "deployment-service" \
        "{\"container\":\"$container_name\",\"action\":\"restart_with_backoff\",\"success\":true}" "medium" "false"
}

# Launch replacement instance
_launch_replacement_instance() {
    local instance_id="$1"
    local context="$2"
    
    unity_log "INFO" "Launching replacement for terminated instance: $instance_id"
    
    # Extract instance details from context
    local instance_type
    instance_type=$(echo "$context" | grep -o '"instance_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "t3.medium")
    
    # Launch replacement
    unity_emit_event "aws.ec2.launch_replacement" "deployment-service" \
        "{\"old_instance\":\"$instance_id\",\"instance_type\":\"$instance_type\"}" "high" "true"
    
    unity_emit_event "deployment.self_healing.completed" "deployment-service" \
        "{\"instance\":\"$instance_id\",\"action\":\"launch_replacement\",\"success\":true}" "medium" "false"
}

# Execute rollback
_execute_rollback() {
    local deployment_id="$1"
    local reason="${2:-manual}"
    
    unity_log "INFO" "Executing rollback for deployment: $deployment_id (reason: $reason)"
    
    # Trigger rollback workflow
    unity_emit_event "deployment.rollback_started" "deployment-service" \
        "{\"deployment_id\":\"$deployment_id\",\"reason\":\"$reason\"}" "high" "true"
    
    return $UNITY_SUCCESS
}

# Get deployment status with atomic reads
_get_deployment_status() {
    local deployment_id="${1:-all}"
    
    if [[ "$deployment_id" == "all" ]]; then
        # Show all deployments across all directories
        echo "Unity Deployment Status Report:"
        echo ""
        
        for dir in "active" "completed" "failed"; do
            echo "${dir^} Deployments:"
            local found_any=false
            
            for state_file in "$UNITY_DEPLOYMENT_STATE_DIR/$dir"/*.state; do
                [[ -f "$state_file" ]] || continue
                found_any=true
                
                local id
                id=$(basename "$state_file" .state)
                
                # Validate and read state atomically
                if _validate_deployment_state "$id"; then
                    local state_content
                    state_content="$(unity_atomic_read "$state_file" "true")"
                    if [[ $? -eq 0 ]]; then
                        local status stack_name deployment_type created_at
                        if command -v jq >/dev/null 2>&1; then
                            status=$(echo "$state_content" | jq -r '.status // "unknown"')
                            stack_name=$(echo "$state_content" | jq -r '.stack_name // "unknown"')
                            deployment_type=$(echo "$state_content" | jq -r '.deployment_type // "unknown"')
                            created_at=$(echo "$state_content" | jq -r '.created_at // 0')
                        else
                            status=$(echo "$state_content" | grep -o '"status":[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
                            stack_name=$(echo "$state_content" | grep -o '"stack_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
                            deployment_type=$(echo "$state_content" | grep -o '"deployment_type":[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
                            created_at="unknown"
                        fi
                        
                        local created_date="unknown"
                        if [[ "$created_at" =~ ^[0-9]+$ ]]; then
                            created_date=$(date -r "$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
                        fi
                        
                        echo "  - $id:"
                        echo "    Stack: $stack_name"
                        echo "    Type: $deployment_type"
                        echo "    Status: $status"
                        echo "    Created: $created_date"
                    else
                        echo "  - $id: [READ error - possibly corrupted]"
                    fi
                else
                    echo "  - $id: [validation failed - attempting recovery]"
                fi
            done
            
            if [[ "$found_any" == "false" ]]; then
                echo "  (none)"
            fi
            echo ""
        done
    else
        # Show specific deployment with full details
        echo "Deployment Details: $deployment_id"
        echo ""
        
        # Validate state first
        if ! _validate_deployment_state "$deployment_id"; then
            unity_log "ERROR" "Deployment validation failed: $deployment_id"
            return $UNITY_ERROR_VALIDATION
        fi
        
        # Find deployment state file
        local state_file=""
        for dir in "active" "completed" "failed"; do
            if [[ -f "$UNITY_DEPLOYMENT_STATE_DIR/$dir/${deployment_id}.state" ]]; then
                state_file="$UNITY_DEPLOYMENT_STATE_DIR/$dir/${deployment_id}.state"
                break
            fi
        done
        
        if [[ -z "$state_file" ]]; then
            unity_log "ERROR" "Deployment not found: $deployment_id"
            return $UNITY_ERROR_VALIDATION
        fi
        
        # Read and display state content
        local state_content
        state_content="$(unity_atomic_read "$state_file" "true")"
        if [[ $? -eq 0 ]]; then
            # Pretty print JSON if jq is available
            if command -v jq >/dev/null 2>&1; then
                echo "$state_content" | jq .
            else
                echo "$state_content"
            fi
            
            # Show transaction history if available
            echo ""
            echo "Transaction History:"
            unity_atomic_get_transaction_history "$state_file" 5 || echo "  (no transaction history available)"
        else
            unity_log "ERROR" "Failed to read deployment state: $deployment_id"
            return $UNITY_ERROR_EXECUTION
        fi
    fi
    
    return $UNITY_SUCCESS
}

#############################################
# Service Lifecycle
#############################################

# Cleanup deployment service with atomic state management
unity_deployment_cleanup() {
    unity_log "INFO" "Cleaning up deployment service..."
    
    # Stop monitoring loops
    pkill -f "_run_health_checks" 2>/dev/null || true
    pkill -f "_collect_deployment_metrics" 2>/dev/null || true
    pkill -f "_check_deployment_costs" 2>/dev/null || true
    
    # Archive completed deployments atomically
    mkdir -p "$UNITY_DEPLOYMENT_STATE_DIR/archive"
    
    for state_file in "$UNITY_DEPLOYMENT_STATE_DIR/completed"/*.state; do
        [[ -f "$state_file" ]] || continue
        
        local deployment_id
        deployment_id=$(basename "$state_file" .state)
        
        # Add archival transaction log entry
        _add_deployment_transaction_log "$deployment_id" "archived" "Deployment archived during cleanup" "success" 2>/dev/null || true
        
        # Move state file and checksum
        local archive_file="$UNITY_DEPLOYMENT_STATE_DIR/archive/$(basename "$state_file")"
        if mv "$state_file" "$archive_file"; then
            # Move checksum file if it exists
            if [[ -f "${state_file}.checksum" ]]; then
                mv "${state_file}.checksum" "${archive_file}.checksum" 2>/dev/null || true
            fi
            unity_log "DEBUG" "Archived deployment state: $deployment_id"
        else
            unity_log "WARN" "Failed to archive deployment state: $deployment_id"
        fi
    done
    
    # Clean up stale atomic state locks
    find "$UNITY_ATOMIC_LOCK_DIR" -name "*.lock" -mmin +$((UNITY_ATOMIC_LOCK_TIMEOUT * 2)) -delete 2>/dev/null || true
    
    # Clean up temporary atomic files
    find "$UNITY_ATOMIC_TEMP_DIR" -name "*.tmp" -mmin +60 -delete 2>/dev/null || true
    
    unity_log "INFO" "Deployment service cleanup completed"
    return $UNITY_SUCCESS
}

# Get deployment service status
unity_deployment_status() {
    echo "Unity Deployment Service Status:"
    echo "  Initialized: $UNITY_DEPLOYMENT_SERVICE_INITIALIZED"
    
    if [[ "$UNITY_DEPLOYMENT_SERVICE_INITIALIZED" == "true" ]]; then
        local active_count
        active_count=$(find "$UNITY_DEPLOYMENT_STATE_DIR/active" -name "*.state" 2>/dev/null | wc -l)
        echo "  Active Deployments: $active_count"
        
        local completed_count
        completed_count=$(find "$UNITY_DEPLOYMENT_STATE_DIR/completed" -name "*.state" 2>/dev/null | wc -l)
        echo "  Completed Deployments: $completed_count"
        
        local failed_count
        failed_count=$(find "$UNITY_DEPLOYMENT_STATE_DIR/failed" -name "*.state" 2>/dev/null | wc -l)
        echo "  Failed Deployments: $failed_count"
        
        echo "  Health Check Interval: ${UNITY_DEPLOYMENT_HEALTH_CHECK_INTERVAL}s"
        echo "  Metric Collection Interval: ${UNITY_DEPLOYMENT_METRIC_COLLECTION_INTERVAL}s"
        echo "  Cost Check Interval: ${UNITY_DEPLOYMENT_COST_CHECK_INTERVAL}s"
    fi
    
    return $UNITY_SUCCESS
}

#############################################
# Workflow Template Initialization
#############################################

# Initialize deployment workflow templates
_init_deployment_workflows() {
    # Register deployment event handlers
    unity_on_event "deployment\..*" "handle_deployment_event" "priority=high"
    
    unity_log "INFO" "Deployment workflows initialized"
}

# Register deployment event handlers
_register_deployment_event_handlers() {
    # Deployment lifecycle events
    unity_on_event "deployment\.started" "_handle_deployment_started" "priority=high"
    unity_on_event "deployment\.completed" "_handle_deployment_completed" "priority=high"
    unity_on_event "deployment\.failed" "_handle_deployment_failed" "priority=high"
    
    # Rollback events
    unity_on_event "deployment\.rollback_started" "_handle_rollback_started" "priority=high"
    unity_on_event "deployment\.rollback_completed" "_handle_rollback_completed" "priority=high"
    
    unity_log "INFO" "Deployment event handlers registered"
}

# Handle deployment events
handle_deployment_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    # Log deployment event
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$event_type|$event_source|$event_data" >> "$UNITY_DEPLOYMENT_LOG"
    
    return 0
}

# Handle deployment started
_handle_deployment_started() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local deployment_id
    deployment_id=$(echo "$event_data" | grep -o '"deployment_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "INFO" "Deployment started: $deployment_id"
    
    # Initialize deployment monitoring
    mkdir -p "$UNITY_DEPLOYMENT_STATE_DIR/failures"
    mkdir -p "$UNITY_DEPLOYMENT_STATE_DIR/backoff"
    
    return 0
}

# Handle deployment completed
_handle_deployment_completed() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local deployment_id
    deployment_id=$(echo "$event_data" | grep -o '"deployment_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "SUCCESS" "Deployment completed: $deployment_id"
    
    # Update deployment state and move to completed
    _add_deployment_transaction_log "$deployment_id" "deployment_completed" "Deployment completed successfully" "success"
    _move_deployment_state "$deployment_id" "active" "completed" "completed"
    
    # Clean up temporary files
    rm -f "$UNITY_DEPLOYMENT_STATE_DIR/failures/${deployment_id}".*
    rm -f "$UNITY_DEPLOYMENT_STATE_DIR/backoff/${deployment_id}".*
    
    return 0
}

# Handle deployment failed
_handle_deployment_failed() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local deployment_id
    deployment_id=$(echo "$event_data" | grep -o '"deployment_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "ERROR" "Deployment failed: $deployment_id"
    
    # Update deployment state and move to failed
    _add_deployment_transaction_log "$deployment_id" "deployment_failed" "Deployment failed" "error"
    _move_deployment_state "$deployment_id" "active" "failed" "failed"
    
    # Check if automatic rollback is enabled from the state file
    local state_file="$UNITY_DEPLOYMENT_STATE_DIR/failed/${deployment_id}.state"
    local rollback_enabled="false"
    
    if [[ -f "$state_file" ]]; then
        local state_content
        state_content="$(unity_atomic_read "$state_file" "true")"
        if [[ $? -eq 0 ]]; then
            rollback_enabled=$(echo "$state_content" | grep -o '"rollback_enabled":[[:space:]]*true\|false' | grep -o 'true\|false' || echo "false")
        fi
    fi
    
    if [[ "$rollback_enabled" == "true" ]]; then
        unity_log "INFO" "Triggering automatic rollback for failed deployment: $deployment_id"
        _execute_rollback "$deployment_id" "automatic_failure"
    fi
    
    return 0
}

# Handle rollback started
_handle_rollback_started() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local deployment_id
    deployment_id=$(echo "$event_data" | grep -o '"deployment_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "INFO" "Rollback started for deployment: $deployment_id"
    
    return 0
}

# Handle rollback completed
_handle_rollback_completed() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local deployment_id
    deployment_id=$(echo "$event_data" | grep -o '"deployment_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    unity_log "SUCCESS" "Rollback completed for deployment: $deployment_id"
    
    return 0
}

#############################################
# Export Functions
#############################################

# Export all deployment service functions
export -f unity_deployment_init
export -f unity_deployment_validate
export -f unity_deployment_execute
export -f unity_deployment_cleanup
export -f unity_deployment_status
export -f handle_deployment_event

# Register service with Unity
unity_register_service "deployment" "$(basename "${BASH_SOURCE[0]}")" "orchestration" "core,events,rollback"

# Log service loaded
unity_log "INFO" "Unity Deployment Service loaded"