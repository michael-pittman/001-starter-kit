#!/usr/bin/env bash
# =============================================================================
# Deployment Rollback Module
# Handles rollback operations, triggers, and cleanup with comprehensive testing
# =============================================================================

# Prevent multiple sourcing
[ -n "${_DEPLOYMENT_ROLLBACK_SH_LOADED:-}" ] && return 0
_DEPLOYMENT_ROLLBACK_SH_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Ensure error handling is available
if ! declare -F log_error >/dev/null 2>&1; then
    echo "ERROR: Required logging functions not found. Source error-handling.sh first." >&2
    return 1
fi

# =============================================================================
# ROLLBACK CONFIGURATION
# =============================================================================

# Rollback configuration defaults
ROLLBACK_DEFAULT_TIMEOUT=900
ROLLBACK_DEFAULT_RETRY_ATTEMPTS=3
ROLLBACK_DEFAULT_RETRY_DELAY=30
ROLLBACK_MAX_BACKOFF=300
ROLLBACK_HEALTH_CHECK_INTERVAL=30
ROLLBACK_SNAPSHOT_RETENTION_DAYS=7

# Rollback states
ROLLBACK_STATE_INITIALIZING="initializing"
ROLLBACK_STATE_IN_PROGRESS="in_progress"
ROLLBACK_STATE_COMPLETED="completed"
ROLLBACK_STATE_FAILED="failed"
ROLLBACK_STATE_VERIFYING="verifying"
ROLLBACK_STATE_PARTIAL="partial"

# Rollback triggers
ROLLBACK_TRIGGER_MANUAL="manual"
ROLLBACK_TRIGGER_HEALTH_FAILURE="health_failure"
ROLLBACK_TRIGGER_DEPLOYMENT_FAILURE="deployment_failure"
ROLLBACK_TRIGGER_VALIDATION_FAILURE="validation_failure"
ROLLBACK_TRIGGER_TIMEOUT="timeout"
ROLLBACK_TRIGGER_USER_ABORT="user_abort"
ROLLBACK_TRIGGER_QUOTA_EXCEEDED="quota_exceeded"
ROLLBACK_TRIGGER_COST_LIMIT="cost_limit"

# Rollback modes
ROLLBACK_MODE_FULL="full"
ROLLBACK_MODE_PARTIAL="partial"
ROLLBACK_MODE_INCREMENTAL="incremental"
ROLLBACK_MODE_EMERGENCY="emergency"

# Global rollback state tracking
declare -A ROLLBACK_REGISTRY=()
declare -A ROLLBACK_TRIGGERS=()
declare -A ROLLBACK_SNAPSHOTS=()
declare -A ROLLBACK_METRICS=()

# =============================================================================
# ROLLBACK TRIGGER DETECTION
# =============================================================================

# Register rollback trigger
register_rollback_trigger() {
    local trigger_name="$1"
    local trigger_condition="$2"
    local trigger_action="$3"
    local priority="${4:-50}"
    
    ROLLBACK_TRIGGERS["${trigger_name}"]=$(cat <<EOF
{
    "condition": "${trigger_condition}",
    "action": "${trigger_action}",
    "priority": ${priority},
    "enabled": true
}
EOF
)
    
    log_info "Registered rollback trigger: ${trigger_name} (priority: ${priority})" "ROLLBACK"
}

# Check rollback triggers
check_rollback_triggers() {
    local stack_name="$1"
    local deployment_state="$2"
    
    log_debug "Checking rollback triggers for stack: ${stack_name}" "ROLLBACK"
    
    # Sort triggers by priority
    local sorted_triggers
    sorted_triggers=$(for trigger in "${!ROLLBACK_TRIGGERS[@]}"; do
        local priority
        priority=$(echo "${ROLLBACK_TRIGGERS[$trigger]}" | jq -r '.priority')
        echo "${priority}:${trigger}"
    done | sort -n | cut -d: -f2)
    
    # Check each trigger
    for trigger_name in $sorted_triggers; do
        local trigger_config="${ROLLBACK_TRIGGERS[$trigger_name]}"
        local enabled
        enabled=$(echo "${trigger_config}" | jq -r '.enabled')
        
        if [[ "${enabled}" != "true" ]]; then
            continue
        fi
        
        local condition
        condition=$(echo "${trigger_config}" | jq -r '.condition')
        
        # Evaluate trigger condition
        if evaluate_trigger_condition "${trigger_name}" "${condition}" "${stack_name}" "${deployment_state}"; then
            log_warn "Rollback trigger activated: ${trigger_name}" "ROLLBACK"
            
            # Execute trigger action
            local action
            action=$(echo "${trigger_config}" | jq -r '.action')
            
            if [[ -n "${action}" ]]; then
                log_info "Executing trigger action: ${action}" "ROLLBACK"
                if type "${action}" >/dev/null 2>&1; then
                    "${action}" "${stack_name}" "${trigger_name}"
                fi
            fi
            
            return 0
        fi
    done
    
    return 1
}

# Evaluate trigger condition
evaluate_trigger_condition() {
    local trigger_name="$1"
    local condition="$2"
    local stack_name="$3"
    local deployment_state="$4"
    
    case "${trigger_name}" in
        "health_check_failure")
            check_health_failure_trigger "${stack_name}"
            ;;
        "deployment_timeout")
            check_timeout_trigger "${stack_name}" "${deployment_state}"
            ;;
        "resource_quota")
            check_quota_trigger "${stack_name}"
            ;;
        "cost_threshold")
            check_cost_trigger "${stack_name}"
            ;;
        "validation_failure")
            check_validation_trigger "${stack_name}"
            ;;
        *)
            # Custom condition evaluation
            if [[ -n "${condition}" ]]; then
                eval "${condition}"
            else
                return 1
            fi
            ;;
    esac
}

# Health check failure trigger
check_health_failure_trigger() {
    local stack_name="$1"
    local health_status
    
    # Get health status from deployment state
    health_status=$(get_variable "HEALTH_STATUS" "$VARIABLE_SCOPE_STACK")
    
    if [[ "${health_status}" == "UNHEALTHY" ]] || [[ "${health_status}" == "CRITICAL" ]]; then
        log_error "Health check failure detected for stack: ${stack_name}" "ROLLBACK"
        return 0
    fi
    
    return 1
}

# Timeout trigger
check_timeout_trigger() {
    local stack_name="$1"
    local deployment_state="$2"
    local start_time
    local current_time
    local elapsed
    local timeout
    
    start_time=$(get_variable "DEPLOYMENT_START_TIME" "$VARIABLE_SCOPE_STACK")
    timeout=$(get_variable "DEPLOYMENT_TIMEOUT" "$VARIABLE_SCOPE_STACK")
    timeout="${timeout:-${ROLLBACK_DEFAULT_TIMEOUT}}"
    
    if [[ -n "${start_time}" ]]; then
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [[ ${elapsed} -gt ${timeout} ]]; then
            log_error "Deployment timeout exceeded: ${elapsed}s > ${timeout}s" "ROLLBACK"
            return 0
        fi
    fi
    
    return 1
}

# Resource quota trigger
check_quota_trigger() {
    local stack_name="$1"
    local quota_status
    
    quota_status=$(get_variable "QUOTA_STATUS" "$VARIABLE_SCOPE_STACK")
    
    if [[ "${quota_status}" == "EXCEEDED" ]]; then
        log_error "Resource quota exceeded for stack: ${stack_name}" "ROLLBACK"
        return 0
    fi
    
    return 1
}

# Cost threshold trigger
check_cost_trigger() {
    local stack_name="$1"
    local current_cost
    local cost_limit
    
    current_cost=$(get_variable "DEPLOYMENT_COST" "$VARIABLE_SCOPE_STACK")
    cost_limit=$(get_variable "COST_LIMIT" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "${current_cost}" ]] && [[ -n "${cost_limit}" ]]; then
        if (( $(echo "${current_cost} > ${cost_limit}" | bc -l) )); then
            log_error "Cost limit exceeded: \$${current_cost} > \$${cost_limit}" "ROLLBACK"
            return 0
        fi
    fi
    
    return 1
}

# Validation failure trigger
check_validation_trigger() {
    local stack_name="$1"
    local validation_status
    
    validation_status=$(get_variable "VALIDATION_STATUS" "$VARIABLE_SCOPE_STACK")
    
    if [[ "${validation_status}" == "FAILED" ]]; then
        log_error "Validation failure detected for stack: ${stack_name}" "ROLLBACK"
        return 0
    fi
    
    return 1
}

# =============================================================================
# ROLLBACK INITIALIZATION AND HELPERS
# =============================================================================

# Initialize rollback
initialize_rollback() {
    local stack_name="$1"
    local deployment_type="$2"
    local rollback_mode="${3:-${ROLLBACK_MODE_FULL}}"
    
    log_info "Initializing rollback for stack: ${stack_name} (mode: ${rollback_mode})" "ROLLBACK"
    
    # Set rollback state
    set_rollback_state "${stack_name}" "$ROLLBACK_STATE_INITIALIZING"
    
    # Validate stack exists
    if ! validate_stack_exists "$stack_name"; then
        log_error "Stack does not exist: $stack_name" "ROLLBACK"
        return 1
    fi
    
    # Load stack state
    if ! load_stack_state "$stack_name"; then
        log_error "Failed to load stack state: $stack_name" "ROLLBACK"
        return 1
    fi
    
    # Create rollback backup
    if ! create_rollback_backup "$stack_name"; then
        log_warn "Failed to create rollback backup" "ROLLBACK"
    fi
    
    # Initialize rollback registry for this stack
    ROLLBACK_REGISTRY["${stack_name}_type"]="${deployment_type}"
    ROLLBACK_REGISTRY["${stack_name}_mode"]="${rollback_mode}"
    ROLLBACK_REGISTRY["${stack_name}_start_time"]=$(date +%s)
    
    log_info "Rollback initialization completed" "ROLLBACK"
    return 0
}

# Create rollback backup (legacy compatibility)
create_rollback_backup() {
    local stack_name="$1"
    create_rollback_snapshot "${stack_name}" "backup"
}

# =============================================================================
# ENHANCED ROLLBACK FUNCTIONS
# =============================================================================

# Main rollback orchestrator with enhanced logic
rollback_deployment() {
    local stack_name="$1"
    local deployment_type="$2"
    local rollback_config="${3:-}"
    local rollback_mode="${4:-${ROLLBACK_MODE_FULL}}"
    local trigger="${5:-${ROLLBACK_TRIGGER_MANUAL}}"
    
    log_info "Starting rollback for stack: ${stack_name} (type: ${deployment_type}, mode: ${rollback_mode}, trigger: ${trigger})" "ROLLBACK"
    
    # Record rollback metrics
    ROLLBACK_METRICS["${stack_name}_start_time"]=$(date +%s)
    ROLLBACK_METRICS["${stack_name}_trigger"]="${trigger}"
    ROLLBACK_METRICS["${stack_name}_mode"]="${rollback_mode}"
    
    # Create pre-rollback snapshot
    if ! create_rollback_snapshot "${stack_name}" "pre_rollback"; then
        log_warn "Failed to create pre-rollback snapshot" "ROLLBACK"
    fi
    
    # Initialize rollback
    if ! initialize_rollback "${stack_name}" "${deployment_type}" "${rollback_mode}"; then
        log_error "Failed to initialize rollback" "ROLLBACK"
        record_rollback_failure "${stack_name}" "initialization_failed"
        return 1
    fi
    
    # Set rollback state
    set_rollback_state "${stack_name}" "$ROLLBACK_STATE_IN_PROGRESS"
    
    # Execute rollback based on mode
    local rollback_result=0
    case "${rollback_mode}" in
        "${ROLLBACK_MODE_FULL}")
            execute_full_rollback "${stack_name}" "${deployment_type}" "${rollback_config}"
            rollback_result=$?
            ;;
        "${ROLLBACK_MODE_PARTIAL}")
            execute_partial_rollback "${stack_name}" "${deployment_type}" "${rollback_config}"
            rollback_result=$?
            ;;
        "${ROLLBACK_MODE_INCREMENTAL}")
            execute_incremental_rollback "${stack_name}" "${deployment_type}" "${rollback_config}"
            rollback_result=$?
            ;;
        "${ROLLBACK_MODE_EMERGENCY}")
            execute_emergency_rollback "${stack_name}" "${deployment_type}" "${rollback_config}"
            rollback_result=$?
            ;;
        *)
            log_error "Unknown rollback mode: ${rollback_mode}" "ROLLBACK"
            record_rollback_failure "${stack_name}" "invalid_mode"
            return 1
            ;;
    esac
    
    # Verify rollback
    set_rollback_state "${stack_name}" "$ROLLBACK_STATE_VERIFYING"
    if verify_rollback "${stack_name}" "${deployment_type}"; then
        log_info "Rollback completed and verified successfully" "ROLLBACK"
        set_rollback_state "${stack_name}" "$ROLLBACK_STATE_COMPLETED"
        
        # Create post-rollback snapshot
        create_rollback_snapshot "${stack_name}" "post_rollback"
        
        # Record success metrics
        record_rollback_success "${stack_name}"
        return 0
    else
        log_error "Rollback verification failed" "ROLLBACK"
        set_rollback_state "${stack_name}" "$ROLLBACK_STATE_FAILED"
        record_rollback_failure "${stack_name}" "verification_failed"
        return 1
    fi
}

# Execute full rollback
execute_full_rollback() {
    local stack_name="$1"
    local deployment_type="$2"
    local rollback_config="${3:-}"
    
    log_info "Executing full rollback for stack: ${stack_name}" "ROLLBACK"
    
    # Execute rollback based on deployment type
    case "${deployment_type}" in
        "spot")
            rollback_spot_stack "${stack_name}" "${rollback_config}"
            ;;
        "alb")
            rollback_alb_stack "${stack_name}" "${rollback_config}"
            ;;
        "cdn")
            rollback_cdn_stack "${stack_name}" "${rollback_config}"
            ;;
        "full")
            rollback_full_stack "${stack_name}" "${rollback_config}"
            ;;
        *)
            log_error "Unknown deployment type for rollback: ${deployment_type}" "ROLLBACK"
            return 1
            ;;
    esac
}

# Execute partial rollback
execute_partial_rollback() {
    local stack_name="$1"
    local deployment_type="$2"
    local rollback_config="${3:-}"
    
    log_info "Executing partial rollback for stack: ${stack_name}" "ROLLBACK"
    
    # Get failed components
    local failed_components
    failed_components=$(get_variable "FAILED_COMPONENTS" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "${failed_components}" ]]; then
        log_warn "No failed components identified, falling back to full rollback" "ROLLBACK"
        execute_full_rollback "${stack_name}" "${deployment_type}" "${rollback_config}"
        return $?
    fi
    
    # Rollback only failed components
    local rollback_success=true
    for component in ${failed_components}; do
        log_info "Rolling back component: ${component}" "ROLLBACK"
        
        if ! rollback_component "${stack_name}" "${component}" "${rollback_config}"; then
            log_error "Failed to rollback component: ${component}" "ROLLBACK"
            rollback_success=false
        fi
    done
    
    [[ "${rollback_success}" == "true" ]] && return 0 || return 1
}

# Execute incremental rollback
execute_incremental_rollback() {
    local stack_name="$1"
    local deployment_type="$2"
    local rollback_config="${3:-}"
    
    log_info "Executing incremental rollback for stack: ${stack_name}" "ROLLBACK"
    
    # Get deployment phases
    local deployment_phases
    deployment_phases=$(get_variable "DEPLOYMENT_PHASES" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "${deployment_phases}" ]]; then
        log_warn "No deployment phases found, falling back to full rollback" "ROLLBACK"
        execute_full_rollback "${stack_name}" "${deployment_type}" "${rollback_config}"
        return $?
    fi
    
    # Rollback phases in reverse order
    local phases_array
    IFS=',' read -ra phases_array <<< "${deployment_phases}"
    
    for ((i=${#phases_array[@]}-1; i>=0; i--)); do
        local phase="${phases_array[i]}"
        local phase_status
        phase_status=$(get_variable "PHASE_${phase}_STATUS" "$VARIABLE_SCOPE_STACK")
        
        if [[ "${phase_status}" == "COMPLETED" ]] || [[ "${phase_status}" == "FAILED" ]]; then
            log_info "Rolling back phase: ${phase}" "ROLLBACK"
            
            if ! rollback_phase "${stack_name}" "${phase}" "${rollback_config}"; then
                log_error "Failed to rollback phase: ${phase}" "ROLLBACK"
                return 1
            fi
        fi
    done
    
    return 0
}

# Execute emergency rollback
execute_emergency_rollback() {
    local stack_name="$1"
    local deployment_type="$2"
    local rollback_config="${3:-}"
    
    log_warn "Executing EMERGENCY rollback for stack: ${stack_name}" "ROLLBACK"
    
    # Force terminate all resources without waiting
    local resources
    resources=$(list_stack_resources "${stack_name}")
    
    if [[ -n "${resources}" ]]; then
        log_info "Force terminating all resources" "ROLLBACK"
        
        # Parallel resource deletion
        echo "${resources}" | while read -r resource_type resource_id; do
            (
                log_info "Force deleting ${resource_type}: ${resource_id}" "ROLLBACK"
                force_delete_resource "${resource_type}" "${resource_id}"
            ) &
        done
        
        # Wait for parallel deletions with timeout
        local timeout=300
        local elapsed=0
        while [[ $(jobs -r | wc -l) -gt 0 ]] && [[ ${elapsed} -lt ${timeout} ]]; do
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        if [[ ${elapsed} -ge ${timeout} ]]; then
            log_error "Emergency rollback timeout reached" "ROLLBACK"
            return 1
        fi
    fi
    
    # Clear all stack data
    clear_stack_variables "${stack_name}"
    
    return 0
}

# =============================================================================
# ROLLBACK COMPONENT FUNCTIONS
# =============================================================================

# Rollback specific component
rollback_component() {
    local stack_name="$1"
    local component="$2"
    local rollback_config="${3:-}"
    
    case "${component}" in
        "vpc")
            rollback_vpc_component "${stack_name}" "${rollback_config}"
            ;;
        "security_groups")
            rollback_security_groups "${stack_name}" "${rollback_config}"
            ;;
        "instances")
            rollback_instances "${stack_name}" "${rollback_config}"
            ;;
        "alb")
            rollback_alb_component "${stack_name}" "${rollback_config}"
            ;;
        "cloudfront")
            rollback_cloudfront_component "${stack_name}" "${rollback_config}"
            ;;
        "efs")
            rollback_efs_component "${stack_name}" "${rollback_config}"
            ;;
        "iam")
            rollback_iam_component "${stack_name}" "${rollback_config}"
            ;;
        *)
            log_error "Unknown component: ${component}" "ROLLBACK"
            return 1
            ;;
    esac
}

# Rollback deployment phase
rollback_phase() {
    local stack_name="$1"
    local phase="$2"
    local rollback_config="${3:-}"
    
    # Get phase components
    local phase_components
    phase_components=$(get_variable "PHASE_${phase}_COMPONENTS" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "${phase_components}" ]]; then
        log_warn "No components found for phase: ${phase}" "ROLLBACK"
        return 0
    fi
    
    # Rollback phase components
    local rollback_success=true
    IFS=',' read -ra components_array <<< "${phase_components}"
    
    for component in "${components_array[@]}"; do
        if ! rollback_component "${stack_name}" "${component}" "${rollback_config}"; then
            rollback_success=false
        fi
    done
    
    [[ "${rollback_success}" == "true" ]] && return 0 || return 1
}

# =============================================================================
# ENHANCED RESOURCE DELETION WITH RETRY
# =============================================================================

# Delete resource with retry logic
delete_resource_with_retry() {
    local resource_type="$1"
    local resource_id="$2"
    local max_attempts="${3:-${ROLLBACK_DEFAULT_RETRY_ATTEMPTS}}"
    local retry_delay="${4:-${ROLLBACK_DEFAULT_RETRY_DELAY}}"
    
    local attempt=1
    local backoff=${retry_delay}
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_info "Deleting ${resource_type}: ${resource_id} (attempt ${attempt}/${max_attempts})" "ROLLBACK"
        
        if delete_resource "${resource_type}" "${resource_id}"; then
            log_info "Successfully deleted ${resource_type}: ${resource_id}" "ROLLBACK"
            return 0
        fi
        
        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_warn "Failed to delete ${resource_type}, retrying in ${backoff}s..." "ROLLBACK"
            sleep "${backoff}"
            
            # Exponential backoff
            backoff=$((backoff * 2))
            [[ ${backoff} -gt ${ROLLBACK_MAX_BACKOFF} ]] && backoff=${ROLLBACK_MAX_BACKOFF}
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Failed to delete ${resource_type} after ${max_attempts} attempts: ${resource_id}" "ROLLBACK"
    return 1
}

# Generic resource deletion
delete_resource() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "${resource_type}" in
        "ec2_instance")
            terminate_ec2_instance "${resource_id}"
            ;;
        "security_group")
            delete_security_group "${resource_id}"
            ;;
        "alb")
            delete_alb "${resource_id}"
            ;;
        "target_group")
            delete_target_group "${resource_id}"
            ;;
        "cloudfront")
            delete_cloudfront_distribution "${resource_id}"
            ;;
        "efs")
            delete_efs_filesystem "${resource_id}"
            ;;
        "vpc")
            delete_vpc_infrastructure "${resource_id}"
            ;;
        "iam_role")
            delete_iam_role "${resource_id}"
            ;;
        "nat_gateway")
            delete_nat_gateway "${resource_id}"
            ;;
        "internet_gateway")
            delete_internet_gateway "${resource_id}"
            ;;
        "subnet")
            delete_subnet "${resource_id}"
            ;;
        *)
            log_error "Unknown resource type: ${resource_type}" "ROLLBACK"
            return 1
            ;;
    esac
}

# Force delete resource (for emergency rollback)
force_delete_resource() {
    local resource_type="$1"
    local resource_id="$2"
    
    # Skip dependency checks and force deletion
    case "${resource_type}" in
        "ec2_instance")
            aws ec2 terminate-instances --instance-ids "${resource_id}" --force 2>/dev/null || true
            ;;
        "security_group")
            # Remove all rules first
            local group_id="${resource_id}"
            aws ec2 revoke-security-group-ingress --group-id "${group_id}" --source-group "${group_id}" 2>/dev/null || true
            aws ec2 revoke-security-group-egress --group-id "${group_id}" --source-group "${group_id}" 2>/dev/null || true
            aws ec2 delete-security-group --group-id "${group_id}" 2>/dev/null || true
            ;;
        *)
            # Fallback to regular deletion
            delete_resource "${resource_type}" "${resource_id}" || true
            ;;
    esac
}

# =============================================================================
# ROLLBACK STATE MANAGEMENT
# =============================================================================

# Set rollback state with persistence
set_rollback_state() {
    local stack_name="$1"
    local state="$2"
    local timestamp=$(date +%s)
    
    # Update in-memory state
    ROLLBACK_REGISTRY["${stack_name}_state"]="${state}"
    ROLLBACK_REGISTRY["${stack_name}_state_timestamp"]="${timestamp}"
    
    # Persist to variable store
    set_variable "ROLLBACK_STATE" "${state}" "$VARIABLE_SCOPE_STACK"
    set_variable "ROLLBACK_STATE_TIMESTAMP" "${timestamp}" "$VARIABLE_SCOPE_STACK"
    
    # Emit state change event
    emit_rollback_event "${stack_name}" "state_changed" "${state}"
    
    log_info "Rollback state set to: ${state} for stack: ${stack_name}" "ROLLBACK"
}

# Get rollback state
get_rollback_state() {
    local stack_name="$1"
    echo "${ROLLBACK_REGISTRY["${stack_name}_state"]:-unknown}"
}

# Create rollback snapshot
create_rollback_snapshot() {
    local stack_name="$1"
    local snapshot_type="$2"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_id="${stack_name}_${snapshot_type}_${timestamp}"
    
    log_info "Creating rollback snapshot: ${snapshot_id}" "ROLLBACK"
    
    # Collect snapshot data
    local snapshot_data=$(cat <<EOF
{
    "id": "${snapshot_id}",
    "stack_name": "${stack_name}",
    "type": "${snapshot_type}",
    "timestamp": "${timestamp}",
    "resources": $(list_stack_resources "${stack_name}" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
    "variables": $(get_stack_variables "${stack_name}"),
    "state": "$(get_rollback_state "${stack_name}")"
}
EOF
)
    
    # Store snapshot
    ROLLBACK_SNAPSHOTS["${snapshot_id}"]="${snapshot_data}"
    
    # Persist to file
    local snapshot_dir="${CONFIG_DIR:-./config}/rollback_snapshots"
    mkdir -p "${snapshot_dir}"
    echo "${snapshot_data}" > "${snapshot_dir}/${snapshot_id}.json"
    
    # Clean old snapshots
    clean_old_snapshots "${snapshot_dir}" "${ROLLBACK_SNAPSHOT_RETENTION_DAYS}"
    
    return 0
}

# Clean old snapshots
clean_old_snapshots() {
    local snapshot_dir="$1"
    local retention_days="$2"
    
    log_debug "Cleaning snapshots older than ${retention_days} days" "ROLLBACK"
    
    find "${snapshot_dir}" -name "*.json" -type f -mtime +${retention_days} -delete 2>/dev/null || true
}

# =============================================================================
# ROLLBACK VERIFICATION
# =============================================================================

# Verify rollback completion
verify_rollback() {
    local stack_name="$1"
    local deployment_type="$2"
    
    log_info "Verifying rollback for stack: ${stack_name}" "ROLLBACK"
    
    # Check no resources remain
    local remaining_resources
    remaining_resources=$(list_stack_resources "${stack_name}" | wc -l)
    
    if [[ ${remaining_resources} -gt 0 ]]; then
        log_error "Found ${remaining_resources} remaining resources after rollback" "ROLLBACK"
        return 1
    fi
    
    # Verify stack variables cleared
    local stack_vars
    stack_vars=$(get_stack_variables "${stack_name}" | jq -r 'keys | length')
    
    if [[ ${stack_vars} -gt 0 ]]; then
        log_warn "Found ${stack_vars} remaining variables after rollback" "ROLLBACK"
    fi
    
    # Additional verification based on deployment type
    case "${deployment_type}" in
        "spot"|"alb"|"cdn"|"full")
            verify_aws_resources_cleaned "${stack_name}"
            ;;
    esac
    
    log_info "Rollback verification completed" "ROLLBACK"
    return 0
}

# Verify AWS resources cleaned
verify_aws_resources_cleaned() {
    local stack_name="$1"
    
    # Check for tagged resources
    local tagged_resources
    tagged_resources=$(aws resourcegroupstaggingapi get-resources \
        --tag-filters "Key=Stack,Values=${stack_name}" \
        --query 'ResourceTagMappingList[].ResourceARN' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${tagged_resources}" ]]; then
        log_warn "Found tagged resources still existing:" "ROLLBACK"
        echo "${tagged_resources}" | while read -r arn; do
            log_warn "  - ${arn}" "ROLLBACK"
        done
        return 1
    fi
    
    return 0
}

# =============================================================================
# ROLLBACK METRICS AND REPORTING
# =============================================================================

# Record rollback success
record_rollback_success() {
    local stack_name="$1"
    local end_time=$(date +%s)
    local start_time="${ROLLBACK_METRICS["${stack_name}_start_time"]}"
    local duration=$((end_time - start_time))
    
    ROLLBACK_METRICS["${stack_name}_end_time"]="${end_time}"
    ROLLBACK_METRICS["${stack_name}_duration"]="${duration}"
    ROLLBACK_METRICS["${stack_name}_status"]="success"
    
    # Generate rollback report
    generate_rollback_report "${stack_name}" "success"
}

# Record rollback failure
record_rollback_failure() {
    local stack_name="$1"
    local failure_reason="$2"
    local end_time=$(date +%s)
    local start_time="${ROLLBACK_METRICS["${stack_name}_start_time"]:-0}"
    local duration=$((end_time - start_time))
    
    ROLLBACK_METRICS["${stack_name}_end_time"]="${end_time}"
    ROLLBACK_METRICS["${stack_name}_duration"]="${duration}"
    ROLLBACK_METRICS["${stack_name}_status"]="failed"
    ROLLBACK_METRICS["${stack_name}_failure_reason"]="${failure_reason}"
    
    # Generate rollback report
    generate_rollback_report "${stack_name}" "failed"
}

# Generate rollback report
generate_rollback_report() {
    local stack_name="$1"
    local status="$2"
    local report_file="${CONFIG_DIR:-./config}/rollback_reports/rollback_${stack_name}_$(date +%Y%m%d-%H%M%S).json"
    
    mkdir -p "$(dirname "${report_file}")"
    
    # Collect metrics
    local metrics="{}"
    for key in "${!ROLLBACK_METRICS[@]}"; do
        if [[ "${key}" == "${stack_name}_"* ]]; then
            local metric_name="${key#${stack_name}_}"
            metrics=$(echo "${metrics}" | jq --arg k "${metric_name}" --arg v "${ROLLBACK_METRICS[$key]}" '. + {($k): $v}')
        fi
    done
    
    # Generate report
    cat <<EOF > "${report_file}"
{
    "stack_name": "${stack_name}",
    "status": "${status}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "metrics": ${metrics},
    "snapshots": $(list_rollback_snapshots "${stack_name}")
}
EOF
    
    log_info "Rollback report generated: ${report_file}" "ROLLBACK"
}

# List rollback snapshots
list_rollback_snapshots() {
    local stack_name="$1"
    local snapshots="[]"
    
    for snapshot_id in "${!ROLLBACK_SNAPSHOTS[@]}"; do
        if [[ "${snapshot_id}" == "${stack_name}_"* ]]; then
            local snapshot_data="${ROLLBACK_SNAPSHOTS[$snapshot_id]}"
            snapshots=$(echo "${snapshots}" | jq --argjson s "${snapshot_data}" '. + [$s]')
        fi
    done
    
    echo "${snapshots}"
}

# =============================================================================
# ROLLBACK EVENT HANDLING
# =============================================================================

# Emit rollback event
emit_rollback_event() {
    local stack_name="$1"
    local event_type="$2"
    local event_data="$3"
    local timestamp=$(date +%s)
    
    # Log event
    log_info "Rollback event: ${event_type} - ${event_data}" "ROLLBACK"
    
    # Execute event handlers
    local handler="handle_rollback_${event_type}"
    if type "${handler}" >/dev/null 2>&1; then
        "${handler}" "${stack_name}" "${event_data}"
    fi
}

# =============================================================================
# ROLLBACK TESTING CAPABILITIES
# =============================================================================

# Test rollback mechanism
test_rollback_mechanism() {
    local test_stack="test-rollback-$(date +%s)"
    local test_type="${1:-spot}"
    
    log_info "Testing rollback mechanism for type: ${test_type}" "ROLLBACK_TEST"
    
    # Create test deployment state
    set_variable "STACK_NAME" "${test_stack}" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_TYPE" "${test_type}" "$VARIABLE_SCOPE_STACK"
    set_variable "VPC_ID" "vpc-test123" "$VARIABLE_SCOPE_STACK"
    set_variable "INSTANCE_ID" "i-test123" "$VARIABLE_SCOPE_STACK"
    set_variable "SECURITY_GROUP_ID" "sg-test123" "$VARIABLE_SCOPE_STACK"
    
    # Test rollback triggers
    log_info "Testing rollback triggers..." "ROLLBACK_TEST"
    
    # Test health failure trigger
    set_variable "HEALTH_STATUS" "CRITICAL" "$VARIABLE_SCOPE_STACK"
    if check_rollback_triggers "${test_stack}" "deploying"; then
        log_info "✓ Health failure trigger working" "ROLLBACK_TEST"
    else
        log_error "✗ Health failure trigger not working" "ROLLBACK_TEST"
    fi
    
    # Test timeout trigger
    set_variable "DEPLOYMENT_START_TIME" "$(($(date +%s) - 1000))" "$VARIABLE_SCOPE_STACK"
    set_variable "DEPLOYMENT_TIMEOUT" "300" "$VARIABLE_SCOPE_STACK"
    if check_rollback_triggers "${test_stack}" "deploying"; then
        log_info "✓ Timeout trigger working" "ROLLBACK_TEST"
    else
        log_error "✗ Timeout trigger not working" "ROLLBACK_TEST"
    fi
    
    # Test rollback execution (dry run)
    log_info "Testing rollback execution (dry run)..." "ROLLBACK_TEST"
    
    # Override deletion functions for testing
    terminate_ec2_instance() { log_info "TEST: Would terminate instance: $1" "ROLLBACK_TEST"; return 0; }
    delete_security_group() { log_info "TEST: Would delete security group: $1" "ROLLBACK_TEST"; return 0; }
    delete_vpc_infrastructure() { log_info "TEST: Would delete VPC: $1" "ROLLBACK_TEST"; return 0; }
    
    # Execute test rollback
    if rollback_deployment "${test_stack}" "${test_type}" "" "${ROLLBACK_MODE_FULL}" "test"; then
        log_info "✓ Rollback execution completed" "ROLLBACK_TEST"
    else
        log_error "✗ Rollback execution failed" "ROLLBACK_TEST"
    fi
    
    # Clean test data
    clear_stack_variables "${test_stack}"
    
    log_info "Rollback mechanism testing completed" "ROLLBACK_TEST"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# List stack resources
list_stack_resources() {
    local stack_name="$1"
    
    # Get all resource variables for the stack
    local resources=""
    
    # Check VPC resources
    local vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    [[ -n "${vpc_id}" ]] && resources="${resources}vpc ${vpc_id}\n"
    
    # Check EC2 resources
    local instance_id=$(get_variable "INSTANCE_ID" "$VARIABLE_SCOPE_STACK")
    [[ -n "${instance_id}" ]] && resources="${resources}ec2_instance ${instance_id}\n"
    
    # Check security groups
    local sg_id=$(get_variable "SECURITY_GROUP_ID" "$VARIABLE_SCOPE_STACK")
    [[ -n "${sg_id}" ]] && resources="${resources}security_group ${sg_id}\n"
    
    # Check ALB resources
    local alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    [[ -n "${alb_arn}" ]] && resources="${resources}alb ${alb_arn}\n"
    
    # Check CloudFront
    local cf_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
    [[ -n "${cf_id}" ]] && resources="${resources}cloudfront ${cf_id}\n"
    
    echo -e "${resources}" | grep -v '^$'
}

# Get stack variables
get_stack_variables() {
    local stack_name="$1"
    
    if [[ -f "${VARIABLE_STORE_FILE}" ]]; then
        jq -r --arg stack "${stack_name}" '.stacks[$stack] // {}' "${VARIABLE_STORE_FILE}" 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize default rollback triggers
initialize_default_triggers() {
    # Health check failure trigger
    register_rollback_trigger "health_check_failure" \
        "check_health_failure_trigger" \
        "rollback_deployment" \
        10
    
    # Deployment timeout trigger
    register_rollback_trigger "deployment_timeout" \
        "check_timeout_trigger" \
        "rollback_deployment" \
        20
    
    # Resource quota trigger
    register_rollback_trigger "resource_quota" \
        "check_quota_trigger" \
        "rollback_deployment" \
        30
    
    # Cost threshold trigger
    register_rollback_trigger "cost_threshold" \
        "check_cost_trigger" \
        "rollback_deployment" \
        40
    
    # Validation failure trigger
    register_rollback_trigger "validation_failure" \
        "check_validation_trigger" \
        "rollback_deployment" \
        50
}

# Initialize on load
initialize_default_triggers

# =============================================================================
# DEPLOYMENT TYPE ROLLBACK IMPLEMENTATIONS
# =============================================================================

# Rollback spot stack
rollback_spot_stack() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back spot stack: ${stack_name}" "ROLLBACK"
    
    # Rollback components in reverse order
    local rollback_success=true
    
    # 1. Rollback instances
    if ! rollback_instances "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # 2. Rollback security groups
    if ! rollback_security_groups "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # 3. Rollback VPC
    if ! rollback_vpc_component "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # Clear stack variables
    clear_stack_variables "${stack_name}"
    
    [[ "${rollback_success}" == "true" ]] && return 0 || return 1
}

# Rollback ALB stack
rollback_alb_stack() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back ALB stack: ${stack_name}" "ROLLBACK"
    
    # Rollback components in reverse order
    local rollback_success=true
    
    # 1. Rollback ALB component
    if ! rollback_alb_component "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # 2. Rollback instances
    if ! rollback_instances "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # 3. Rollback security groups
    if ! rollback_security_groups "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # 4. Rollback VPC
    if ! rollback_vpc_component "${stack_name}" "${rollback_config}"; then
        rollback_success=false
    fi
    
    # Clear stack variables
    clear_stack_variables "${stack_name}"
    
    [[ "${rollback_success}" == "true" ]] && return 0 || return 1
}

# Rollback CDN stack
rollback_cdn_stack() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back CDN stack: ${stack_name}" "ROLLBACK"
    
    # Rollback CloudFront component
    if rollback_cloudfront_component "${stack_name}" "${rollback_config}"; then
        log_info "CDN stack rollback completed" "ROLLBACK"
        clear_stack_variables "${stack_name}"
        return 0
    else
        log_error "CDN stack rollback failed" "ROLLBACK"
        return 1
    fi
}

# Rollback full stack
rollback_full_stack() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back full stack: ${stack_name}" "ROLLBACK"
    
    # Rollback in reverse order: CDN -> ALB -> Instances -> VPC
    local rollback_success=true
    
    # 1. Rollback CDN
    if ! rollback_cloudfront_component "${stack_name}" "${rollback_config}"; then
        log_warn "CloudFront rollback failed, continuing..." "ROLLBACK"
        rollback_success=false
    fi
    
    # 2. Rollback ALB
    if ! rollback_alb_component "${stack_name}" "${rollback_config}"; then
        log_warn "ALB rollback failed, continuing..." "ROLLBACK"
        rollback_success=false
    fi
    
    # 3. Rollback EFS
    if ! rollback_efs_component "${stack_name}" "${rollback_config}"; then
        log_warn "EFS rollback failed, continuing..." "ROLLBACK"
        rollback_success=false
    fi
    
    # 4. Rollback instances
    if ! rollback_instances "${stack_name}" "${rollback_config}"; then
        log_warn "Instance rollback failed, continuing..." "ROLLBACK"
        rollback_success=false
    fi
    
    # 5. Rollback IAM
    if ! rollback_iam_component "${stack_name}" "${rollback_config}"; then
        log_warn "IAM rollback failed, continuing..." "ROLLBACK"
        rollback_success=false
    fi
    
    # 6. Rollback security groups
    if ! rollback_security_groups "${stack_name}" "${rollback_config}"; then
        log_warn "Security group rollback failed, continuing..." "ROLLBACK"
        rollback_success=false
    fi
    
    # 7. Rollback VPC
    if ! rollback_vpc_component "${stack_name}" "${rollback_config}"; then
        log_warn "VPC rollback failed" "ROLLBACK"
        rollback_success=false
    fi
    
    # Clear stack variables
    clear_stack_variables "${stack_name}"
    
    [[ "${rollback_success}" == "true" ]] && return 0 || return 1
}

# =============================================================================
# COMPONENT ROLLBACK IMPLEMENTATIONS
# =============================================================================

# Rollback VPC component
rollback_vpc_component() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back VPC component for stack: ${stack_name}" "ROLLBACK"
    
    local vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    local subnet_ids=$(get_variable "SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
    local igw_id=$(get_variable "IGW_ID" "$VARIABLE_SCOPE_STACK")
    local nat_gateway_ids=$(get_variable "NAT_GATEWAY_IDS" "$VARIABLE_SCOPE_STACK")
    
    # Delete NAT gateways first
    if [[ -n "${nat_gateway_ids}" ]]; then
        IFS=',' read -ra nat_array <<< "${nat_gateway_ids}"
        for nat_id in "${nat_array[@]}"; do
            delete_resource_with_retry "nat_gateway" "${nat_id}"
        done
    fi
    
    # Detach and delete internet gateway
    if [[ -n "${igw_id}" ]] && [[ -n "${vpc_id}" ]]; then
        aws ec2 detach-internet-gateway --internet-gateway-id "${igw_id}" --vpc-id "${vpc_id}" 2>/dev/null || true
        delete_resource_with_retry "internet_gateway" "${igw_id}"
    fi
    
    # Delete subnets
    if [[ -n "${subnet_ids}" ]]; then
        IFS=',' read -ra subnet_array <<< "${subnet_ids}"
        for subnet_id in "${subnet_array[@]}"; do
            delete_resource_with_retry "subnet" "${subnet_id}"
        done
    fi
    
    # Delete VPC
    if [[ -n "${vpc_id}" ]]; then
        delete_resource_with_retry "vpc" "${vpc_id}"
    fi
    
    return 0
}

# Rollback security groups
rollback_security_groups() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back security groups for stack: ${stack_name}" "ROLLBACK"
    
    local sg_ids=$(get_variable "SECURITY_GROUP_IDS" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "${sg_ids}" ]]; then
        IFS=',' read -ra sg_array <<< "${sg_ids}"
        for sg_id in "${sg_array[@]}"; do
            delete_resource_with_retry "security_group" "${sg_id}"
        done
    fi
    
    return 0
}

# Rollback instances
rollback_instances() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back instances for stack: ${stack_name}" "ROLLBACK"
    
    local instance_ids=$(get_variable "INSTANCE_IDS" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "${instance_ids}" ]]; then
        IFS=',' read -ra instance_array <<< "${instance_ids}"
        for instance_id in "${instance_array[@]}"; do
            delete_resource_with_retry "ec2_instance" "${instance_id}"
        done
    fi
    
    return 0
}

# Rollback ALB component
rollback_alb_component() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back ALB component for stack: ${stack_name}" "ROLLBACK"
    
    local alb_arn=$(get_variable "ALB_ARN" "$VARIABLE_SCOPE_STACK")
    local target_group_arns=$(get_variable "TARGET_GROUP_ARNS" "$VARIABLE_SCOPE_STACK")
    
    # Delete ALB first
    if [[ -n "${alb_arn}" ]]; then
        delete_resource_with_retry "alb" "${alb_arn}"
    fi
    
    # Delete target groups
    if [[ -n "${target_group_arns}" ]]; then
        IFS=',' read -ra tg_array <<< "${target_group_arns}"
        for tg_arn in "${tg_array[@]}"; do
            delete_resource_with_retry "target_group" "${tg_arn}"
        done
    fi
    
    return 0
}

# Rollback CloudFront component
rollback_cloudfront_component() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back CloudFront component for stack: ${stack_name}" "ROLLBACK"
    
    local distribution_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "${distribution_id}" ]]; then
        # Disable distribution first
        local etag
        etag=$(aws cloudfront get-distribution-config --id "${distribution_id}" --query 'ETag' --output text 2>/dev/null || echo "")
        
        if [[ -n "${etag}" ]]; then
            aws cloudfront update-distribution --id "${distribution_id}" \
                --if-match "${etag}" \
                --distribution-config "$(aws cloudfront get-distribution-config --id "${distribution_id}" --query 'DistributionConfig' | jq '.Enabled = false')" \
                2>/dev/null || true
        fi
        
        # Delete distribution
        delete_resource_with_retry "cloudfront" "${distribution_id}"
    fi
    
    return 0
}

# Rollback EFS component
rollback_efs_component() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back EFS component for stack: ${stack_name}" "ROLLBACK"
    
    local efs_id=$(get_variable "EFS_ID" "$VARIABLE_SCOPE_STACK")
    local mount_target_ids=$(get_variable "MOUNT_TARGET_IDS" "$VARIABLE_SCOPE_STACK")
    
    # Delete mount targets first
    if [[ -n "${mount_target_ids}" ]]; then
        IFS=',' read -ra mt_array <<< "${mount_target_ids}"
        for mt_id in "${mt_array[@]}"; do
            aws efs delete-mount-target --mount-target-id "${mt_id}" 2>/dev/null || true
        done
        
        # Wait for mount targets to be deleted
        sleep 30
    fi
    
    # Delete EFS filesystem
    if [[ -n "${efs_id}" ]]; then
        delete_resource_with_retry "efs" "${efs_id}"
    fi
    
    return 0
}

# Rollback IAM component
rollback_iam_component() {
    local stack_name="$1"
    local rollback_config="${2:-}"
    
    log_info "Rolling back IAM component for stack: ${stack_name}" "ROLLBACK"
    
    local role_names=$(get_variable "IAM_ROLE_NAMES" "$VARIABLE_SCOPE_STACK")
    local instance_profile_names=$(get_variable "INSTANCE_PROFILE_NAMES" "$VARIABLE_SCOPE_STACK")
    
    # Delete instance profiles first
    if [[ -n "${instance_profile_names}" ]]; then
        IFS=',' read -ra profile_array <<< "${instance_profile_names}"
        for profile_name in "${profile_array[@]}"; do
            # Remove roles from instance profile
            local roles
            roles=$(aws iam get-instance-profile --instance-profile-name "${profile_name}" --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null || echo "")
            
            if [[ -n "${roles}" ]]; then
                for role in ${roles}; do
                    aws iam remove-role-from-instance-profile --instance-profile-name "${profile_name}" --role-name "${role}" 2>/dev/null || true
                done
            fi
            
            # Delete instance profile
            aws iam delete-instance-profile --instance-profile-name "${profile_name}" 2>/dev/null || true
        done
    fi
    
    # Delete IAM roles
    if [[ -n "${role_names}" ]]; then
        IFS=',' read -ra role_array <<< "${role_names}"
        for role_name in "${role_array[@]}"; do
            # Detach policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            if [[ -n "${attached_policies}" ]]; then
                for policy_arn in ${attached_policies}; do
                    aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}" 2>/dev/null || true
                done
            fi
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "${role_name}" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            if [[ -n "${inline_policies}" ]]; then
                for policy_name in ${inline_policies}; do
                    aws iam delete-role-policy --role-name "${role_name}" --policy-name "${policy_name}" 2>/dev/null || true
                done
            fi
            
            # Delete role
            delete_resource_with_retry "iam_role" "${role_name}"
        done
    fi
    
    return 0
}

# =============================================================================
# ENHANCED RESOURCE DELETION FUNCTIONS
# =============================================================================

# Delete EFS filesystem
delete_efs_filesystem() {
    local efs_id="$1"
    
    log_info "Deleting EFS filesystem: ${efs_id}" "ROLLBACK"
    
    if aws efs delete-file-system --file-system-id "${efs_id}" 2>/dev/null; then
        log_info "EFS filesystem deletion initiated: ${efs_id}" "ROLLBACK"
        return 0
    else
        log_error "Failed to delete EFS filesystem: ${efs_id}" "ROLLBACK"
        return 1
    fi
}

# Delete IAM role
delete_iam_role() {
    local role_name="$1"
    
    log_info "Deleting IAM role: ${role_name}" "ROLLBACK"
    
    if aws iam delete-role --role-name "${role_name}" 2>/dev/null; then
        log_info "IAM role deleted: ${role_name}" "ROLLBACK"
        return 0
    else
        log_error "Failed to delete IAM role: ${role_name}" "ROLLBACK"
        return 1
    fi
}

# Delete NAT gateway
delete_nat_gateway() {
    local nat_gateway_id="$1"
    
    log_info "Deleting NAT gateway: ${nat_gateway_id}" "ROLLBACK"
    
    if aws ec2 delete-nat-gateway --nat-gateway-id "${nat_gateway_id}" 2>/dev/null; then
        log_info "NAT gateway deletion initiated: ${nat_gateway_id}" "ROLLBACK"
        return 0
    else
        log_error "Failed to delete NAT gateway: ${nat_gateway_id}" "ROLLBACK"
        return 1
    fi
}

# Delete internet gateway
delete_internet_gateway() {
    local igw_id="$1"
    
    log_info "Deleting internet gateway: ${igw_id}" "ROLLBACK"
    
    if aws ec2 delete-internet-gateway --internet-gateway-id "${igw_id}" 2>/dev/null; then
        log_info "Internet gateway deleted: ${igw_id}" "ROLLBACK"
        return 0
    else
        log_error "Failed to delete internet gateway: ${igw_id}" "ROLLBACK"
        return 1
    fi
}

# Delete subnet
delete_subnet() {
    local subnet_id="$1"
    
    log_info "Deleting subnet: ${subnet_id}" "ROLLBACK"
    
    if aws ec2 delete-subnet --subnet-id "${subnet_id}" 2>/dev/null; then
        log_info "Subnet deleted: ${subnet_id}" "ROLLBACK"
        return 0
    else
        log_error "Failed to delete subnet: ${subnet_id}" "ROLLBACK"
        return 1
    fi
}

# Initialize rollback module
initialize_rollback_module() {
    # Initialize rollback triggers
    initialize_default_triggers
    
    # Create rollback directories
    mkdir -p "${CONFIG_DIR:-./config}/rollback_snapshots"
    mkdir -p "${CONFIG_DIR:-./config}/rollback_reports"
    
    log_info "Rollback module initialized" "ROLLBACK"
    return 0
}

# Initialize module
initialize_rollback_module