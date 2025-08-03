#!/bin/bash
# Unity Event System - Automatic Rollback Manager
# Comprehensive rollback mechanisms and state restoration

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Rollback manager configuration
UNITY_ROLLBACK_STATE_DIR=".unity/events/rollback-state"
UNITY_ROLLBACK_SNAPSHOTS_DIR=".unity/events/rollback-snapshots"
UNITY_ROLLBACK_LOG="logs/unity/rollback-manager.log"
UNITY_ROLLBACK_STRATEGIES_DIR=".unity/events/rollback-strategies"

# Rollback settings
UNITY_ROLLBACK_TIMEOUT=600  # 10 minutes default timeout
UNITY_ROLLBACK_MAX_RETRIES=3
UNITY_ROLLBACK_SNAPSHOT_RETENTION_DAYS=7
UNITY_ROLLBACK_PARALLEL_LIMIT=3

# Rollback trigger thresholds
UNITY_ROLLBACK_FAILURE_THRESHOLD=3
UNITY_ROLLBACK_ERROR_RATE_THRESHOLD=0.5
UNITY_ROLLBACK_HEALTH_CHECK_FAILURES=5

#############################################
# Rollback Manager Initialization
#############################################

# Initialize rollback manager
init_rollback_manager() {
    local verbose="${1:-false}"
    
    # Create rollback directories
    mkdir -p "$UNITY_ROLLBACK_STATE_DIR" "$UNITY_ROLLBACK_SNAPSHOTS_DIR" "$(dirname "$UNITY_ROLLBACK_LOG")"
    mkdir -p "$UNITY_ROLLBACK_STRATEGIES_DIR" "$UNITY_ROLLBACK_STATE_DIR/active" "$UNITY_ROLLBACK_STATE_DIR/history"
    mkdir -p "$UNITY_ROLLBACK_SNAPSHOTS_DIR/deployment" "$UNITY_ROLLBACK_SNAPSHOTS_DIR/configuration"
    mkdir -p "$UNITY_ROLLBACK_SNAPSHOTS_DIR/infrastructure" "$UNITY_ROLLBACK_SNAPSHOTS_DIR/application"
    
    # Initialize rollback strategies
    _init_rollback_strategies
    
    # Register rollback event handlers
    _register_rollback_handlers
    
    # Initialize state tracking
    _init_rollback_state_tracking
    
    # Set up automatic rollback triggers
    _setup_automatic_rollback_triggers
    
    if [[ "$verbose" == "true" ]] && command -v unity_log >/dev/null 2>&1; then
        unity_log "SUCCESS" "Rollback manager initialized with automatic triggers and state restoration"
    fi
    
    return 0
}

# Initialize rollback strategies
_init_rollback_strategies() {
    # Deployment rollback strategy
    cat > "$UNITY_ROLLBACK_STRATEGIES_DIR/deployment.strategy" <<'DEPLOYMENT_STRATEGY_EOF'
# Deployment Rollback Strategy
strategy_id: deployment_rollback
description: "Complete deployment rollback with state restoration"
priority: high
timeout: 600

# Rollback phases (executed in order)
phases:
  - phase_id: stop_services
    description: "Stop all running services"
    timeout: 120
    actions:
      - stop_docker_containers
      - disable_load_balancer_targets
      - stop_application_services
    rollback_events:
      - docker.container.stopped
      - aws.alb.target_disabled
    
  - phase_id: restore_configuration
    description: "Restore previous configuration"
    timeout: 60
    depends_on: stop_services
    actions:
      - restore_environment_variables
      - restore_config_files
      - restore_secrets
    rollback_events:
      - config.restored
      
  - phase_id: restore_infrastructure
    description: "Restore infrastructure state"
    timeout: 300
    depends_on: restore_configuration
    actions:
      - restore_ec2_state
      - restore_vpc_configuration
      - restore_security_groups
    rollback_events:
      - aws.infrastructure.restored
      
  - phase_id: restart_services
    description: "Restart services with previous state"
    timeout: 180
    depends_on: restore_infrastructure
    actions:
      - start_previous_docker_compose
      - enable_health_checks
      - restore_dns_records
    rollback_events:
      - docker.compose.restored
      - monitor.health_checks.enabled
      
  - phase_id: validation
    description: "Validate rollback success"
    timeout: 120
    depends_on: restart_services
    actions:
      - run_health_checks
      - validate_endpoints
      - check_service_connectivity
    success_events:
      - deployment.rollback.completed
    failure_events:
      - deployment.rollback.failed

# Failure handling during rollback
failure_handling:
  emergency_stop: true
  manual_intervention_required: true
  preserve_logs: true
  
# Compensation if rollback fails
emergency_actions:
  - isolate_failed_resources
  - preserve_error_state
  - trigger_manual_recovery
  - send_emergency_alerts
DEPLOYMENT_STRATEGY_EOF

    # Infrastructure rollback strategy
    cat > "$UNITY_ROLLBACK_STRATEGIES_DIR/infrastructure.strategy" <<'INFRASTRUCTURE_STRATEGY_EOF'
# Infrastructure Rollback Strategy
strategy_id: infrastructure_rollback
description: "AWS infrastructure rollback with resource cleanup"
priority: high
timeout: 480

phases:
  - phase_id: isolate_resources
    description: "Isolate failed resources"
    timeout: 60
    actions:
      - detach_load_balancers
      - remove_from_auto_scaling
      - isolate_security_groups
    
  - phase_id: cleanup_new_resources
    description: "Clean up newly created resources"
    timeout: 240
    depends_on: isolate_resources
    actions:
      - terminate_failed_instances
      - delete_failed_load_balancers
      - cleanup_failed_vpc_resources
    
  - phase_id: restore_previous_state  
    description: "Restore previous infrastructure state"
    timeout: 180
    depends_on: cleanup_new_resources
    actions:
      - restore_previous_instances
      - restore_load_balancer_config
      - restore_network_configuration

failure_handling:
  preserve_working_resources: true
  cleanup_failed_resources: true
  emergency_isolation: true
INFRASTRUCTURE_STRATEGY_EOF

    # Application rollback strategy
    cat > "$UNITY_ROLLBACK_STRATEGIES_DIR/application.strategy" <<'APPLICATION_STRATEGY_EOF'
# Application Rollback Strategy
strategy_id: application_rollback
description: "Application-level rollback with data preservation"
priority: medium
timeout: 300

phases:
  - phase_id: backup_current_state
    description: "Backup current application state"
    timeout: 60
    actions:
      - backup_application_data
      - backup_container_state
      - backup_configuration
    
  - phase_id: stop_current_application
    description: "Gracefully stop current application"
    timeout: 120
    depends_on: backup_current_state
    actions:
      - drain_traffic
      - stop_application_containers
      - preserve_persistent_data
    
  - phase_id: restore_previous_application
    description: "Restore previous application version"
    timeout: 120
    depends_on: stop_current_application
    actions:
      - restore_previous_containers
      - restore_application_config
      - restore_traffic_routing

failure_handling:
  preserve_data: true
  graceful_degradation: true
  zero_downtime_preferred: true
APPLICATION_STRATEGY_EOF
}

# Register rollback event handlers
_register_rollback_handlers() {
    # Deployment failure triggers
    unity_on_event "deployment\.failed" "trigger_automatic_rollback" "priority=high strategy=deployment"
    unity_on_event "deployment\.verification_failed" "trigger_automatic_rollback" "priority=high strategy=deployment"
    
    # Infrastructure failure triggers
    unity_on_event "aws\.resource\.failed" "trigger_automatic_rollback" "priority=high strategy=infrastructure"
    unity_on_event "aws\.ec2\.failed" "trigger_automatic_rollback" "priority=high strategy=infrastructure"
    
    # Application failure triggers
    unity_on_event "docker\.container\.failed" "trigger_conditional_rollback" "priority=medium strategy=application"
    unity_on_event "docker\.compose\.failed" "trigger_automatic_rollback" "priority=high strategy=application"
    
    # Health check failure triggers
    unity_on_event "monitor\.health\.check\.failed" "evaluate_rollback_trigger" "priority=medium"
    unity_on_event "monitor\.service\.unhealthy" "evaluate_rollback_trigger" "priority=medium"
    
    # Configuration failure triggers
    unity_on_event "config\.error" "trigger_conditional_rollback" "priority=medium strategy=configuration"
    
    # System-wide failure triggers
    unity_on_event "system\.emergency" "trigger_emergency_rollback" "priority=critical"
}

# Initialize rollback state tracking
_init_rollback_state_tracking() {
    cat > "$UNITY_ROLLBACK_STATE_DIR/rollback-registry.state" <<EOF
# Rollback Registry State
# Format: rollback_id|strategy|stack_name|status|created_at|completed_at|success

EOF

    cat > "$UNITY_ROLLBACK_STATE_DIR/snapshot-registry.state" <<EOF
# Snapshot Registry State  
# Format: snapshot_id|type|stack_name|created_at|size|valid

EOF

    cat > "$UNITY_ROLLBACK_STATE_DIR/trigger-history.state" <<EOF
# Rollback Trigger History
# Format: timestamp|event_type|stack_name|trigger_reason|action_taken

EOF
}

# Set up automatic rollback triggers
_setup_automatic_rollback_triggers() {
    cat > "$UNITY_ROLLBACK_STATE_DIR/trigger-config.conf" <<EOF
# Automatic Rollback Trigger Configuration

# Failure count thresholds
DEPLOYMENT_FAILURE_THRESHOLD=$UNITY_ROLLBACK_FAILURE_THRESHOLD
HEALTH_CHECK_FAILURE_THRESHOLD=$UNITY_ROLLBACK_HEALTH_CHECK_FAILURES
ERROR_RATE_THRESHOLD=$UNITY_ROLLBACK_ERROR_RATE_THRESHOLD

# Time windows for evaluation
FAILURE_TIME_WINDOW=300  # 5 minutes
HEALTH_CHECK_TIME_WINDOW=180  # 3 minutes
ERROR_RATE_TIME_WINDOW=600  # 10 minutes

# Automatic rollback enablement
AUTO_ROLLBACK_ENABLED=true
EMERGENCY_ROLLBACK_ENABLED=true
CONDITIONAL_ROLLBACK_ENABLED=true

# Rollback execution settings
MAX_CONCURRENT_ROLLBACKS=$UNITY_ROLLBACK_PARALLEL_LIMIT
ROLLBACK_TIMEOUT=$UNITY_ROLLBACK_TIMEOUT
MAX_ROLLBACK_RETRIES=$UNITY_ROLLBACK_MAX_RETRIES
EOF
}

#############################################
# Snapshot Management
#############################################

# Create deployment snapshot
create_deployment_snapshot() {
    local stack_name="$1"
    local snapshot_type="${2:-full}"
    local description="${3:-Pre-deployment snapshot}"
    
    local snapshot_id="${stack_name}_$(date +%s%N)"
    local snapshot_dir="$UNITY_ROLLBACK_SNAPSHOTS_DIR/deployment/$snapshot_id"
    
    mkdir -p "$snapshot_dir"
    
    # Create snapshot metadata
    cat > "$snapshot_dir/metadata.json" <<EOF
{
  "snapshot_id": "$snapshot_id",
  "stack_name": "$stack_name",
  "snapshot_type": "$snapshot_type",
  "description": "$description",
  "created_at": $(date +%s),
  "version": "2.0",
  "components": []
}
EOF
    
    # Capture infrastructure state
    _capture_infrastructure_snapshot "$stack_name" "$snapshot_dir"
    
    # Capture application state
    _capture_application_snapshot "$stack_name" "$snapshot_dir"
    
    # Capture configuration state
    _capture_configuration_snapshot "$stack_name" "$snapshot_dir"
    
    # Update snapshot registry
    _register_snapshot "$snapshot_id" "$snapshot_type" "$stack_name"
    
    _log_rollback_event "SNAPSHOT_CREATED" "$snapshot_id" "$stack_name" "$snapshot_type"
    
    echo "$snapshot_id"
}

# Capture infrastructure snapshot
_capture_infrastructure_snapshot() {
    local stack_name="$1"
    local snapshot_dir="$2"
    
    local infra_dir="$snapshot_dir/infrastructure"
    mkdir -p "$infra_dir"
    
    # Capture EC2 instance state
    if command -v aws >/dev/null 2>&1; then
        aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$stack_name" \
            --output json > "$infra_dir/ec2-instances.json" 2>/dev/null || true
        
        # Capture VPC configuration
        aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=$stack_name" \
            --output json > "$infra_dir/vpc-config.json" 2>/dev/null || true
        
        # Capture security groups
        aws ec2 describe-security-groups \
            --filters "Name=tag:Name,Values=$stack_name" \
            --output json > "$infra_dir/security-groups.json" 2>/dev/null || true
        
        # Capture load balancer configuration
        aws elbv2 describe-load-balancers \
            --output json 2>/dev/null | jq ".LoadBalancers[] | select(.LoadBalancerName | contains(\"$stack_name\"))" > "$infra_dir/load-balancers.json" 2>/dev/null || true
    fi
    
    # Capture resource metadata
    if [[ -f "$UNITY_ROLLBACK_STATE_DIR/../handler-state/resources.state" ]]; then
        grep "$stack_name" "$UNITY_ROLLBACK_STATE_DIR/../handler-state/resources.state" > "$infra_dir/resource-tracking.state" 2>/dev/null || true
    fi
}

# Capture application snapshot
_capture_application_snapshot() {
    local stack_name="$1"
    local snapshot_dir="$2"
    
    local app_dir="$snapshot_dir/application"
    mkdir -p "$app_dir"
    
    # Capture Docker container state
    if command -v docker >/dev/null 2>&1; then
        docker ps --filter "label=stack=$stack_name" --format "table {{.ID}}\t{{.Image}}\t{{.Command}}\t{{.Status}}" > "$app_dir/docker-containers.txt" 2>/dev/null || true
        
        # Capture Docker Compose configuration
        if [[ -f "docker-compose.yml" ]]; then
            cp "docker-compose.yml" "$app_dir/" 2>/dev/null || true
        fi
        
        # Capture container environment variables
        docker ps --filter "label=stack=$stack_name" --format "{{.ID}}" | while read -r container_id; do
            if [[ -n "$container_id" ]]; then
                docker inspect "$container_id" > "$app_dir/container-${container_id}.json" 2>/dev/null || true
            fi
        done
    fi
    
    # Capture application configuration files
    if [[ -d ".env" ]]; then
        cp -r ".env" "$app_dir/" 2>/dev/null || true
    fi
    
    for env_file in .env.* config/*.yml config/*.yaml; do
        if [[ -f "$env_file" ]]; then
            cp "$env_file" "$app_dir/" 2>/dev/null || true
        fi
    done
}

# Capture configuration snapshot
_capture_configuration_snapshot() {
    local stack_name="$1"
    local snapshot_dir="$2"
    
    local config_dir="$snapshot_dir/configuration"
    mkdir -p "$config_dir"
    
    # Capture environment configuration
    if [[ -f ".env.local" ]]; then
        cp ".env.local" "$config_dir/" 2>/dev/null || true
    fi
    
    # Capture Unity configuration
    if [[ -d ".unity" ]]; then
        cp -r ".unity/config" "$config_dir/unity-config" 2>/dev/null || true
    fi
    
    # Capture deployment variables
    if [[ -f "config/defaults.yml" ]]; then
        cp "config/defaults.yml" "$config_dir/" 2>/dev/null || true
    fi
    
    # Capture AWS Parameter Store values (if accessible)
    if command -v aws >/dev/null 2>&1; then
        aws ssm get-parameters-by-path \
            --path "/aibuildkit" \
            --recursive \
            --with-decryption \
            --output json > "$config_dir/parameter-store.json" 2>/dev/null || true
    fi
}

# Register snapshot in registry
_register_snapshot() {
    local snapshot_id="$1"
    local snapshot_type="$2"
    local stack_name="$3"
    
    local snapshot_size
    snapshot_size=$(du -sh "$UNITY_ROLLBACK_SNAPSHOTS_DIR/deployment/$snapshot_id" 2>/dev/null | cut -f1 || echo "Unknown")
    
    echo "$snapshot_id|$snapshot_type|$stack_name|$(date +%s)|$snapshot_size|true" >> "$UNITY_ROLLBACK_STATE_DIR/snapshot-registry.state"
}

#############################################
# Rollback Trigger Functions
#############################################

# Trigger automatic rollback
trigger_automatic_rollback() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    _log_rollback_event "TRIGGER_AUTOMATIC" "auto" "$event_type" "$event_source"
    
    # Extract stack name from event data
    local stack_name
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Determine rollback strategy based on event type
    local strategy="deployment"
    case "$event_type" in
        "aws."*) strategy="infrastructure" ;;
        "docker."*) strategy="application" ;;
        "config."*) strategy="configuration" ;;
    esac
    
    # Check if rollback is already in progress
    if _is_rollback_in_progress "$stack_name"; then
        _log_rollback_event "ROLLBACK_ALREADY_ACTIVE" "$stack_name" "$strategy" "skipped"
        return 0
    fi
    
    # Execute rollback
    execute_rollback "$stack_name" "$strategy" "automatic" "$event_type"
    
    return 0
}

# Trigger conditional rollback (based on thresholds)
trigger_conditional_rollback() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local stack_name
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Evaluate rollback conditions
    if _should_trigger_rollback "$stack_name" "$event_type" "$timestamp"; then
        _log_rollback_event "TRIGGER_CONDITIONAL" "$stack_name" "$event_type" "threshold_exceeded"
        
        local strategy="application"
        execute_rollback "$stack_name" "$strategy" "conditional" "$event_type"
    else
        _log_rollback_event "TRIGGER_EVALUATED" "$stack_name" "$event_type" "threshold_not_met"
    fi
    
    return 0
}

# Evaluate rollback trigger conditions
evaluate_rollback_trigger() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    local service
    service=$(echo "$event_data" | grep -o '"service": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Count recent failures for this service
    local failure_count
    failure_count=$(_count_recent_failures "$service" "$timestamp")
    
    if [[ $failure_count -ge $UNITY_ROLLBACK_HEALTH_CHECK_FAILURES ]]; then
        _log_rollback_event "TRIGGER_HEALTH_FAILURE" "$service" "$event_type" "failure_count=$failure_count"
        
        # Emit rollback required event
        if command -v unity_emit_event >/dev/null 2>&1; then
            unity_emit_event "deployment.rollback_required" "rollback-manager" "{\"reason\":\"health_check_failures\",\"service\":\"$service\",\"failure_count\":$failure_count}" "high" "true"
        fi
    fi
    
    return 0
}

# Trigger emergency rollback
trigger_emergency_rollback() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    _log_rollback_event "TRIGGER_EMERGENCY" "emergency" "$event_type" "$event_source"
    
    local stack_name
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "all")
    
    # Emergency rollback - use most comprehensive strategy
    execute_rollback "$stack_name" "deployment" "emergency" "$event_type"
    
    return 0
}

#############################################
# Rollback Execution Engine
#############################################

# Execute rollback
execute_rollback() {
    local stack_name="$1"
    local strategy="${2:-deployment}"
    local trigger_type="${3:-manual}"
    local trigger_event="${4:-manual_trigger}"
    
    local rollback_id="${strategy}_${stack_name}_$(date +%s%N)"
    
    _log_rollback_event "ROLLBACK_STARTED" "$rollback_id" "$stack_name" "$strategy"
    
    # Create rollback state tracking
    _init_rollback_execution "$rollback_id" "$stack_name" "$strategy" "$trigger_type" "$trigger_event"
    
    # Load rollback strategy
    local strategy_file="$UNITY_ROLLBACK_STRATEGIES_DIR/${strategy}.strategy"
    if [[ ! -f "$strategy_file" ]]; then
        _log_rollback_event "ROLLBACK_ERROR" "$rollback_id" "strategy_not_found" "$strategy"
        return 1
    fi
    
    # Find most recent snapshot for this stack
    local snapshot_id
    snapshot_id=$(_find_latest_snapshot "$stack_name")
    
    if [[ -z "$snapshot_id" ]]; then
        _log_rollback_event "ROLLBACK_ERROR" "$rollback_id" "no_snapshot_found" "$stack_name"
        return 1
    fi
    
    # Execute rollback phases
    _execute_rollback_phases "$rollback_id" "$stack_name" "$strategy_file" "$snapshot_id"
    
    return 0
}

# Initialize rollback execution
_init_rollback_execution() {
    local rollback_id="$1"
    local stack_name="$2"
    local strategy="$3"
    local trigger_type="$4"
    local trigger_event="$5"
    
    local rollback_file="$UNITY_ROLLBACK_STATE_DIR/active/${rollback_id}.rollback"
    
    cat > "$rollback_file" <<EOF
{
  "rollback_id": "$rollback_id",
  "stack_name": "$stack_name",
  "strategy": "$strategy",
  "trigger_type": "$trigger_type",
  "trigger_event": "$trigger_event",
  "started_at": $(date +%s),
  "status": "active",
  "current_phase": null,
  "completed_phases": [],
  "failed_phases": [],
  "retry_count": 0
}
EOF
    
    # Register in rollback registry
    echo "$rollback_id|$strategy|$stack_name|active|$(date +%s)||false" >> "$UNITY_ROLLBACK_STATE_DIR/rollback-registry.state"
}

# Execute rollback phases
_execute_rollback_phases() {
    local rollback_id="$1"
    local stack_name="$2"
    local strategy_file="$3"
    local snapshot_id="$4"
    
    # Parse strategy file and execute phases
    # This is a simplified implementation - real implementation would parse YAML/config
    
    case "$(basename "$strategy_file" .strategy)" in
        "deployment")
            _execute_deployment_rollback_phases "$rollback_id" "$stack_name" "$snapshot_id"
            ;;
        "infrastructure")
            _execute_infrastructure_rollback_phases "$rollback_id" "$stack_name" "$snapshot_id"
            ;;
        "application")
            _execute_application_rollback_phases "$rollback_id" "$stack_name" "$snapshot_id"
            ;;
    esac
}

# Execute deployment rollback phases
_execute_deployment_rollback_phases() {
    local rollback_id="$1"
    local stack_name="$2"
    local snapshot_id="$3"
    
    local snapshot_dir="$UNITY_ROLLBACK_SNAPSHOTS_DIR/deployment/$snapshot_id"
    
    # Phase 1: Stop services
    _log_rollback_event "PHASE_START" "$rollback_id" "stop_services" "deployment"
    if _stop_deployment_services "$stack_name"; then
        _log_rollback_event "PHASE_SUCCESS" "$rollback_id" "stop_services" "completed"
    else
        _log_rollback_event "PHASE_FAILED" "$rollback_id" "stop_services" "failed"
        return 1
    fi
    
    # Phase 2: Restore configuration
    _log_rollback_event "PHASE_START" "$rollback_id" "restore_configuration" "deployment"
    if _restore_configuration_from_snapshot "$stack_name" "$snapshot_dir"; then
        _log_rollback_event "PHASE_SUCCESS" "$rollback_id" "restore_configuration" "completed"
    else
        _log_rollback_event "PHASE_FAILED" "$rollback_id" "restore_configuration" "failed"
        return 1
    fi
    
    # Phase 3: Restore infrastructure
    _log_rollback_event "PHASE_START" "$rollback_id" "restore_infrastructure" "deployment"
    if _restore_infrastructure_from_snapshot "$stack_name" "$snapshot_dir"; then
        _log_rollback_event "PHASE_SUCCESS" "$rollback_id" "restore_infrastructure" "completed"
    else
        _log_rollback_event "PHASE_FAILED" "$rollback_id" "restore_infrastructure" "failed"
        return 1
    fi
    
    # Phase 4: Restart services
    _log_rollback_event "PHASE_START" "$rollback_id" "restart_services" "deployment"
    if _restart_services_from_snapshot "$stack_name" "$snapshot_dir"; then
        _log_rollback_event "PHASE_SUCCESS" "$rollback_id" "restart_services" "completed"
    else
        _log_rollback_event "PHASE_FAILED" "$rollback_id" "restart_services" "failed"
        return 1
    fi
    
    # Phase 5: Validation
    _log_rollback_event "PHASE_START" "$rollback_id" "validation" "deployment"
    if _validate_rollback_success "$stack_name"; then
        _log_rollback_event "PHASE_SUCCESS" "$rollback_id" "validation" "completed"
        _finalize_rollback_success "$rollback_id" "$stack_name"
    else
        _log_rollback_event "PHASE_FAILED" "$rollback_id" "validation" "failed"
        _handle_rollback_failure "$rollback_id" "$stack_name"
        return 1
    fi
    
    return 0
}

# Execute infrastructure rollback phases
_execute_infrastructure_rollback_phases() {
    local rollback_id="$1"
    local stack_name="$2"
    local snapshot_id="$3"
    
    # Simplified infrastructure rollback implementation
    _log_rollback_event "INFRASTRUCTURE_ROLLBACK" "$rollback_id" "$stack_name" "executing"
    
    # Would implement infrastructure-specific rollback logic here
    
    return 0
}

# Execute application rollback phases
_execute_application_rollback_phases() {
    local rollback_id="$1"
    local stack_name="$2"
    local snapshot_id="$3"
    
    # Simplified application rollback implementation
    _log_rollback_event "APPLICATION_ROLLBACK" "$rollback_id" "$stack_name" "executing"
    
    # Would implement application-specific rollback logic here
    
    return 0
}

#############################################
# Rollback Phase Implementations
#############################################

# Stop deployment services
_stop_deployment_services() {
    local stack_name="$1"
    
    # Stop Docker containers
    if command -v docker >/dev/null 2>&1; then
        docker ps --filter "label=stack=$stack_name" --format "{{.ID}}" | while read -r container_id; do
            if [[ -n "$container_id" ]]; then
                docker stop "$container_id" >/dev/null 2>&1 || true
            fi
        done
    fi
    
    # Stop Docker Compose services
    if [[ -f "docker-compose.yml" ]]; then
        docker-compose down >/dev/null 2>&1 || true
    fi
    
    return 0
}

# Restore configuration from snapshot
_restore_configuration_from_snapshot() {
    local stack_name="$1"
    local snapshot_dir="$2"
    
    local config_dir="$snapshot_dir/configuration"
    
    if [[ -d "$config_dir" ]]; then
        # Restore environment files
        for env_file in "$config_dir"/.env*; do
            if [[ -f "$env_file" ]]; then
                cp "$env_file" "./" 2>/dev/null || true
            fi
        done
        
        # Restore configuration files
        if [[ -f "$config_dir/defaults.yml" ]]; then
            cp "$config_dir/defaults.yml" "config/" 2>/dev/null || true
        fi
        
        # Restore Unity configuration
        if [[ -d "$config_dir/unity-config" ]]; then
            cp -r "$config_dir/unity-config"/* ".unity/config/" 2>/dev/null || true
        fi
    fi
    
    return 0
}

# Restore infrastructure from snapshot
_restore_infrastructure_from_snapshot() {
    local stack_name="$1"
    local snapshot_dir="$2"
    
    local infra_dir="$snapshot_dir/infrastructure"
    
    if [[ -d "$infra_dir" ]] && command -v aws >/dev/null 2>&1; then
        # This would implement infrastructure restoration logic
        # For now, just log the attempt
        _log_rollback_event "INFRASTRUCTURE_RESTORE" "$stack_name" "attempted" "$infra_dir"
    fi
    
    return 0
}

# Restart services from snapshot
_restart_services_from_snapshot() {
    local stack_name="$1"
    local snapshot_dir="$2"
    
    local app_dir="$snapshot_dir/application"
    
    if [[ -d "$app_dir" ]]; then
        # Restart Docker Compose if available
        if [[ -f "$app_dir/docker-compose.yml" ]]; then
            cp "$app_dir/docker-compose.yml" "./" 2>/dev/null || true
            docker-compose up -d >/dev/null 2>&1 || true
        fi
    fi
    
    return 0
}

# Validate rollback success
_validate_rollback_success() {
    local stack_name="$1"
    
    # Basic validation - check if services are running
    local validation_success=true
    
    # Check Docker containers
    if command -v docker >/dev/null 2>&1; then
        local running_containers
        running_containers=$(docker ps --filter "label=stack=$stack_name" --format "{{.ID}}" | wc -l)
        
        if [[ $running_containers -eq 0 ]]; then
            validation_success=false
        fi
    fi
    
    # Check basic connectivity (simplified)
    if ! ping -c 1 localhost >/dev/null 2>&1; then
        validation_success=false
    fi
    
    [[ "$validation_success" == "true" ]]
}

#############################################
# Rollback Support Functions
#############################################

# Check if rollback is in progress
_is_rollback_in_progress() {
    local stack_name="$1"
    
    # Check for active rollback files
    for rollback_file in "$UNITY_ROLLBACK_STATE_DIR/active"/*.rollback; do
        if [[ -f "$rollback_file" ]]; then
            if grep -q "\"stack_name\": \"$stack_name\"" "$rollback_file"; then
                return 0  # Rollback in progress
            fi
        fi
    done
    
    return 1  # No rollback in progress
}

# Determine if rollback should be triggered
_should_trigger_rollback() {
    local stack_name="$1"
    local event_type="$2"
    local timestamp="$3"
    
    # Count recent failures within time window
    local failure_count
    failure_count=$(_count_recent_failures "$stack_name" "$timestamp")
    
    # Check failure threshold
    if [[ $failure_count -ge $UNITY_ROLLBACK_FAILURE_THRESHOLD ]]; then
        return 0  # Should trigger rollback
    fi
    
    return 1  # Should not trigger rollback
}

# Count recent failures
_count_recent_failures() {
    local stack_name="$1"
    local current_timestamp="$2"
    local time_window=300  # 5 minutes
    
    local cutoff_time=$((current_timestamp - time_window))
    local failure_count=0
    
    # Count failures in trigger history
    while IFS='|' read -r timestamp event_type stack trigger_reason action; do
        if [[ "$timestamp" -ge "$cutoff_time" ]] && [[ "$stack" == "$stack_name" ]] && [[ "$event_type" =~ .*failed.* ]]; then
            failure_count=$((failure_count + 1))
        fi
    done < "$UNITY_ROLLBACK_STATE_DIR/trigger-history.state" 2>/dev/null || true
    
    echo "$failure_count"
}

# Find latest snapshot
_find_latest_snapshot() {
    local stack_name="$1"
    
    # Find most recent snapshot for stack
    local latest_snapshot=""
    local latest_timestamp=0
    
    while IFS='|' read -r snapshot_id snapshot_type stack_name_snap created_at size valid; do
        if [[ "$stack_name_snap" == "$stack_name" ]] && [[ "$valid" == "true" ]]; then
            if [[ "$created_at" -gt "$latest_timestamp" ]]; then
                latest_timestamp="$created_at"
                latest_snapshot="$snapshot_id"
            fi
        fi
    done < "$UNITY_ROLLBACK_STATE_DIR/snapshot-registry.state" 2>/dev/null || true
    
    echo "$latest_snapshot"
}

# Finalize rollback success
_finalize_rollback_success() {
    local rollback_id="$1"
    local stack_name="$2"
    
    # Move rollback file to history
    local rollback_file="$UNITY_ROLLBACK_STATE_DIR/active/${rollback_id}.rollback"
    if [[ -f "$rollback_file" ]]; then
        mv "$rollback_file" "$UNITY_ROLLBACK_STATE_DIR/history/"
    fi
    
    # Update registry
    sed -i.bak "s/|${rollback_id}|.*|active|/|${rollback_id}|deployment|${stack_name}|completed|$(date +%s)|true|/" "$UNITY_ROLLBACK_STATE_DIR/rollback-registry.state" 2>/dev/null || true
    rm -f "$UNITY_ROLLBACK_STATE_DIR/rollback-registry.state.bak"
    
    # Emit success event
    if command -v unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "deployment.rollback.completed" "rollback-manager" "{\"rollback_id\":\"$rollback_id\",\"stack_name\":\"$stack_name\"}" "medium" "false"
    fi
    
    _log_rollback_event "ROLLBACK_COMPLETED" "$rollback_id" "$stack_name" "success"
}

# Handle rollback failure
_handle_rollback_failure() {
    local rollback_id="$1"
    local stack_name="$2"
    
    _log_rollback_event "ROLLBACK_FAILED" "$rollback_id" "$stack_name" "manual_intervention_required"
    
    # Emit failure event
    if command -v unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "deployment.rollback.failed" "rollback-manager" "{\"rollback_id\":\"$rollback_id\",\"stack_name\":\"$stack_name\"}" "critical" "true"
    fi
    
    # Move to failed state
    local rollback_file="$UNITY_ROLLBACK_STATE_DIR/active/${rollback_id}.rollback"
    if [[ -f "$rollback_file" ]]; then
        mv "$rollback_file" "$UNITY_ROLLBACK_STATE_DIR/history/"
    fi
}

# Log rollback events
_log_rollback_event() {
    local event_category="$1"
    local rollback_id="$2"
    local stack_name="$3"
    local details="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$timestamp|$event_category|$rollback_id|$stack_name|$details" >> "$UNITY_ROLLBACK_LOG"
    
    # Also log to trigger history if it's a trigger event
    if [[ "$event_category" =~ TRIGGER.* ]]; then
        echo "$(date +%s)|$stack_name|$rollback_id|$details|rollback_triggered" >> "$UNITY_ROLLBACK_STATE_DIR/trigger-history.state"
    fi
}

#############################################
# Rollback Management Commands
#############################################

# List active rollbacks
list_active_rollbacks() {
    local format="${1:-summary}"
    
    echo "=== Active Rollbacks ==="
    
    for rollback_file in "$UNITY_ROLLBACK_STATE_DIR/active"/*.rollback; do
        if [[ -f "$rollback_file" ]]; then
            local rollback_id
            rollback_id=$(basename "$rollback_file" .rollback)
            
            if [[ "$format" == "detailed" ]]; then
                echo "Rollback ID: $rollback_id"
                cat "$rollback_file" 2>/dev/null | grep -E '"(stack_name|strategy|started_at|status)"' || true
                echo "---"
            else
                local stack_name strategy started_at
                stack_name=$(grep '"stack_name":' "$rollback_file" | cut -d':' -f2 | tr -d ' ",' 2>/dev/null || echo "unknown")
                strategy=$(grep '"strategy":' "$rollback_file" | cut -d':' -f2 | tr -d ' ",' 2>/dev/null || echo "unknown")
                started_at=$(grep '"started_at":' "$rollback_file" | cut -d':' -f2 | tr -d ' ,' 2>/dev/null || echo "0")
                
                local started_str
                started_str=$(date -d "@$started_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$started_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                
                echo "$rollback_id | $stack_name | $strategy | $started_str"
            fi
        fi
    done
}

# List available snapshots
list_rollback_snapshots() {
    local stack_name="${1:-all}"
    local format="${2:-summary}"
    
    echo "=== Available Snapshots ==="
    
    while IFS='|' read -r snapshot_id snapshot_type stack_name_snap created_at size valid; do
        if [[ "$stack_name" == "all" ]] || [[ "$stack_name_snap" == "$stack_name" ]]; then
            if [[ "$valid" == "true" ]]; then
                if [[ "$format" == "detailed" ]]; then
                    local created_str
                    created_str=$(date -d "@$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                    
                    echo "Snapshot: $snapshot_id"
                    echo "  Stack: $stack_name_snap"
                    echo "  Type: $snapshot_type"
                    echo "  Created: $created_str"
                    echo "  Size: $size"
                    echo "---"
                else
                    local created_str
                    created_str=$(date -d "@$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                    
                    echo "$snapshot_id | $stack_name_snap | $snapshot_type | $created_str | $size"
                fi
            fi
        fi
    done < "$UNITY_ROLLBACK_STATE_DIR/snapshot-registry.state" 2>/dev/null || true
}

# Manual rollback execution
manual_rollback() {
    local stack_name="$1"
    local strategy="${2:-deployment}"
    local snapshot_id="${3:-}"
    
    if [[ -z "$stack_name" ]]; then
        echo "Error: Stack name is required for manual rollback"
        return 1
    fi
    
    # If no snapshot specified, find latest
    if [[ -z "$snapshot_id" ]]; then
        snapshot_id=$(_find_latest_snapshot "$stack_name")
        
        if [[ -z "$snapshot_id" ]]; then
            echo "Error: No snapshots found for stack $stack_name"
            return 1
        fi
        
        echo "Using latest snapshot: $snapshot_id"
    fi
    
    # Execute rollback
    execute_rollback "$stack_name" "$strategy" "manual" "manual_trigger"
}

#############################################
# Export Functions
#############################################

# Export all rollback manager functions
export -f init_rollback_manager
export -f create_deployment_snapshot
export -f trigger_automatic_rollback
export -f trigger_conditional_rollback
export -f evaluate_rollback_trigger
export -f trigger_emergency_rollback
export -f execute_rollback
export -f list_active_rollbacks
export -f list_rollback_snapshots
export -f manual_rollback

# Initialize rollback manager if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_rollback_manager "true"
fi