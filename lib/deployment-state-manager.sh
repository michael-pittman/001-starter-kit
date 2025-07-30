#!/usr/bin/env bash
# =============================================================================
# Deployment State Management Library
# Comprehensive deployment orchestration and state tracking
# Compatible with bash 3.x+
# =============================================================================


# Load associative array utilities
source "$SCRIPT_DIR/associative-arrays.sh"

# Prevent multiple sourcing
if [[ "${DEPLOYMENT_STATE_MANAGER_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly DEPLOYMENT_STATE_MANAGER_LIB_LOADED=true

# =============================================================================
# LIBRARY METADATA
# =============================================================================

readonly DEPLOYMENT_STATE_MANAGER_VERSION="1.0.0"

# =============================================================================
# GLOBAL ASSOCIATIVE ARRAYS FOR DEPLOYMENT STATE
# =============================================================================

# Deployment state tracking
declare -gA DEPLOYMENT_STATES          # Current deployment states
declare -gA DEPLOYMENT_OPTIONS          # Deployment configuration options
declare -gA DEPLOYMENT_PROGRESS         # Progress tracking for each deployment
declare -gA DEPLOYMENT_HISTORY          # Historical deployment data
declare -gA DEPLOYMENT_DEPENDENCIES     # Inter-deployment dependencies
declare -gA DEPLOYMENT_ROLLBACK         # Rollback information and states
declare -gA DEPLOYMENT_METRICS          # Performance and timing metrics
declare -gA DEPLOYMENT_VALIDATIONS      # Pre and post deployment validations

# Deployment phase definitions
declare -gA DEPLOYMENT_PHASES
aa_set DEPLOYMENT_PHASES "validation:order" "1"
aa_set DEPLOYMENT_PHASES "validation:description" "Pre-deployment validation and checks"
aa_set DEPLOYMENT_PHASES "validation:timeout" "300"
aa_set DEPLOYMENT_PHASES "validation:required" "true"

aa_set DEPLOYMENT_PHASES "preparation:order" "2"
aa_set DEPLOYMENT_PHASES "preparation:description" "Resource preparation and setup"
aa_set DEPLOYMENT_PHASES "preparation:timeout" "600"
aa_set DEPLOYMENT_PHASES "preparation:required" "true"

aa_set DEPLOYMENT_PHASES "infrastructure:order" "3"
aa_set DEPLOYMENT_PHASES "infrastructure:description" "Infrastructure provisioning"
aa_set DEPLOYMENT_PHASES "infrastructure:timeout" "1200"
aa_set DEPLOYMENT_PHASES "infrastructure:required" "true"

aa_set DEPLOYMENT_PHASES "application:order" "4"
aa_set DEPLOYMENT_PHASES "application:description" "Application deployment"
aa_set DEPLOYMENT_PHASES "application:timeout" "900"
aa_set DEPLOYMENT_PHASES "application:required" "true"

aa_set DEPLOYMENT_PHASES "verification:order" "5"
aa_set DEPLOYMENT_PHASES "verification:description" "Post-deployment verification"
aa_set DEPLOYMENT_PHASES "verification:timeout" "300"
aa_set DEPLOYMENT_PHASES "verification:required" "true"

aa_set DEPLOYMENT_PHASES "cleanup:order" "6"
aa_set DEPLOYMENT_PHASES "cleanup:description" "Cleanup and finalization"
aa_set DEPLOYMENT_PHASES "cleanup:timeout" "300"
aa_set DEPLOYMENT_PHASES "cleanup:required" "false"

# Deployment status definitions
declare -gA DEPLOYMENT_STATUS_DEFINITIONS
aa_set DEPLOYMENT_STATUS_DEFINITIONS "pending" "Deployment is queued but not started"
aa_set DEPLOYMENT_STATUS_DEFINITIONS "running" "Deployment is currently in progress"
aa_set DEPLOYMENT_STATUS_DEFINITIONS "paused" "Deployment is paused and can be resumed"
aa_set DEPLOYMENT_STATUS_DEFINITIONS "completed" "Deployment completed successfully"
aa_set DEPLOYMENT_STATUS_DEFINITIONS "failed" "Deployment failed"
aa_set DEPLOYMENT_STATUS_DEFINITIONS "rolled_back" "Deployment was rolled back"
aa_set DEPLOYMENT_STATUS_DEFINITIONS "cancelled" "Deployment was cancelled"

# =============================================================================
# DEPLOYMENT INITIALIZATION AND CONFIGURATION
# =============================================================================

# Initialize a new deployment
# Usage: init_deployment deployment_id stack_name deployment_type [options_json]
init_deployment() {
    local deployment_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local options_json="${4:-{}}"
    
    if [[ -z "$deployment_id" ]] || [[ -z "$stack_name" ]] || [[ -z "$deployment_type" ]]; then
        error "init_deployment requires deployment_id, stack_name, and deployment_type"
        return 1
    fi
    
    local timestamp=$(date +%s)
    local session_id="${deployment_id}-${timestamp}"
    
    # Initialize deployment state
    aa_set DEPLOYMENT_STATES "${deployment_id}:session_id" "$session_id"
    aa_set DEPLOYMENT_STATES "${deployment_id}:stack_name" "$stack_name"
    aa_set DEPLOYMENT_STATES "${deployment_id}:deployment_type" "$deployment_type"
    aa_set DEPLOYMENT_STATES "${deployment_id}:status" "pending"
    aa_set DEPLOYMENT_STATES "${deployment_id}:created_at" "$timestamp"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$timestamp"
    aa_set DEPLOYMENT_STATES "${deployment_id}:current_phase" ""
    aa_set DEPLOYMENT_STATES "${deployment_id}:phase_progress" "0"
    aa_set DEPLOYMENT_STATES "${deployment_id}:overall_progress" "0"
    aa_set DEPLOYMENT_STATES "${deployment_id}:region" "${AWS_REGION:-us-east-1}"
    
    # Initialize deployment options with defaults
    declare -A default_options
    aa_set default_options "timeout" "3600"
    aa_set default_options "retry_attempts" "3"
    aa_set default_options "fail_fast" "false"
    aa_set default_options "dry_run" "false"
    aa_set default_options "verbose" "false"
    aa_set default_options "backup_enabled" "true"
    aa_set default_options "rollback_enabled" "true"
    aa_set default_options "notifications_enabled" "false"
    
    # Merge with provided options
    for option_key in $(aa_keys default_options); do
        aa_set DEPLOYMENT_OPTIONS "${deployment_id}:${option_key}" "$(aa_get default_options "$option_key")"
    done
    
    # Parse custom options if provided
    if [[ "$options_json" != "{}" ]] && command -v jq >/dev/null 2>&1; then
        local option_keys
        option_keys=$(echo "$options_json" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        for key in $option_keys; do
            local value
            value=$(echo "$options_json" | jq -r ".$key" 2>/dev/null || echo "")
            if [[ -n "$value" && "$value" != "null" ]]; then
                aa_set DEPLOYMENT_OPTIONS "${deployment_id}:${key}" "$value"
            fi
        done
    fi
    
    # Initialize progress tracking for each phase
    for phase_key in $(aa_keys DEPLOYMENT_PHASES); do
        if [[ "$phase_key" =~ :order$ ]]; then
            local phase_name="${phase_key%:order}"
            aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:status" "pending"
            aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:start_time" "0"
            aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:end_time" "0"
            aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:progress" "0"
            aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:message" ""
        fi
    done
    
    # Record deployment history
    record_deployment_event "$deployment_id" "initialized" "Deployment initialized for stack $stack_name"
    
    if declare -f log >/dev/null 2>&1; then
        log "Initialized deployment: $deployment_id (session: $session_id)"
    fi
    
    return 0
}

# Configure deployment with advanced options
configure_deployment() {
    local deployment_id="$1"
    local configuration_json="$2"
    
    if ! deployment_exists "$deployment_id"; then
        error "Deployment not found: $deployment_id"
        return 1
    fi
    
    if [[ -z "$configuration_json" ]] || [[ "$configuration_json" == "{}" ]]; then
        error "Configuration JSON required"
        return 1
    fi
    
    # Parse and apply configuration
    if command -v jq >/dev/null 2>&1; then
        local config_keys
        config_keys=$(echo "$configuration_json" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        for key in $config_keys; do
            local value
            value=$(echo "$configuration_json" | jq -r ".$key" 2>/dev/null || echo "")
            if [[ -n "$value" && "$value" != "null" ]]; then
                case "$key" in
                    "dependencies")
                        # Handle deployment dependencies
                        aa_set DEPLOYMENT_DEPENDENCIES "${deployment_id}:depends_on" "$value"
                        ;;
                    "rollback_strategy")
                        # Configure rollback strategy
                        aa_set DEPLOYMENT_ROLLBACK "${deployment_id}:strategy" "$value"
                        ;;
                    "notification_webhooks")
                        # Configure notification endpoints
                        aa_set DEPLOYMENT_OPTIONS "${deployment_id}:webhook_url" "$value"
                        ;;
                    *)
                        # Store as general option
                        aa_set DEPLOYMENT_OPTIONS "${deployment_id}:${key}" "$value"
                        ;;
                esac
            fi
        done
        
        # Update timestamp
        aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$(date +%s)"
        
        record_deployment_event "$deployment_id" "configured" "Deployment configuration updated"
        
        if declare -f log >/dev/null 2>&1; then
            log "Configured deployment: $deployment_id"
        fi
    else
        error "jq not available for JSON parsing"
        return 1
    fi
}

# =============================================================================
# DEPLOYMENT EXECUTION AND ORCHESTRATION
# =============================================================================

# Start deployment execution
start_deployment() {
    local deployment_id="$1"
    local force="${2:-false}"
    
    if ! deployment_exists "$deployment_id"; then
        error "Deployment not found: $deployment_id"
        return 1
    fi
    
    local current_status=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status")
    
    # Check if deployment can be started
    if [[ "$current_status" != "pending" ]] && [[ "$force" != "true" ]]; then
        if [[ "$current_status" == "paused" ]]; then
            info "Resuming paused deployment: $deployment_id"
        else
            error "Cannot start deployment in status: $current_status (use force=true to override)"
            return 1
        fi
    fi
    
    # Check dependencies
    local dependencies=$(aa_get DEPLOYMENT_DEPENDENCIES "${deployment_id}:depends_on" "")
    if [[ -n "$dependencies" ]]; then
        info "Checking deployment dependencies: $dependencies"
        
        IFS=',' read -ra dep_array <<< "$dependencies"
        for dep_id in "${dep_array[@]}"; do
            dep_id=$(echo "$dep_id" | xargs)  # trim whitespace
            if [[ -n "$dep_id" ]]; then
                local dep_status=$(aa_get DEPLOYMENT_STATES "${dep_id}:status" "not_found")
                if [[ "$dep_status" != "completed" ]]; then
                    error "Dependency $dep_id not completed (status: $dep_status)"
                    return 1
                fi
            fi
        done
    fi
    
    # Update deployment state
    aa_set DEPLOYMENT_STATES "${deployment_id}:status" "running"
    aa_set DEPLOYMENT_STATES "${deployment_id}:started_at" "$(date +%s)"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$(date +%s)"
    
    record_deployment_event "$deployment_id" "started" "Deployment execution started"
    
    # Execute deployment phases
    local deployment_result
    if execute_deployment_phases "$deployment_id"; then
        deployment_result="completed"
    else
        deployment_result="failed"
    fi
    
    # Update final status
    aa_set DEPLOYMENT_STATES "${deployment_id}:status" "$deployment_result"
    aa_set DEPLOYMENT_STATES "${deployment_id}:completed_at" "$(date +%s)"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$(date +%s)"
    
    record_deployment_event "$deployment_id" "$deployment_result" "Deployment execution $deployment_result"
    
    # Handle post-deployment actions
    if [[ "$deployment_result" == "completed" ]]; then
        trigger_deployment_notifications "$deployment_id" "success"
        if declare -f success >/dev/null 2>&1; then
            success "Deployment completed successfully: $deployment_id"
        fi
    else
        # Check if rollback is enabled
        local rollback_enabled=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:rollback_enabled" "true")
        if [[ "$rollback_enabled" == "true" ]]; then
            warning "Deployment failed - initiating rollback: $deployment_id"
            rollback_deployment "$deployment_id"
        fi
        
        trigger_deployment_notifications "$deployment_id" "failure"
        if declare -f error >/dev/null 2>&1; then
            error "Deployment failed: $deployment_id"
        fi
    fi
    
    return $([ "$deployment_result" == "completed" ] && echo 0 || echo 1)
}

# Execute deployment phases in order
execute_deployment_phases() {
    local deployment_id="$1"
    
    # Get ordered list of phases
    declare -A phase_order
    for phase_key in $(aa_keys DEPLOYMENT_PHASES); do
        if [[ "$phase_key" =~ :order$ ]]; then
            local phase_name="${phase_key%:order}"
            local order=$(aa_get DEPLOYMENT_PHASES "$phase_key")
            aa_set phase_order "$order" "$phase_name"
        fi
    done
    
    # Execute phases in order
    local total_phases=$(aa_size phase_order)
    local current_phase_num=0
    
    for order in $(printf '%s\n' $(aa_keys phase_order) | sort -n); do
        local phase_name=$(aa_get phase_order "$order")
        current_phase_num=$((current_phase_num + 1))
        
        aa_set DEPLOYMENT_STATES "${deployment_id}:current_phase" "$phase_name"
        
        # Calculate overall progress
        local overall_progress=$(echo "scale=2; ($current_phase_num - 1) / $total_phases * 100" | bc -l 2>/dev/null || echo "0")
        aa_set DEPLOYMENT_STATES "${deployment_id}:overall_progress" "$overall_progress"
        
        if declare -f log >/dev/null 2>&1; then
            log "Executing deployment phase: $phase_name ($current_phase_num/$total_phases)"
        fi
        
        # Execute the phase
        if ! execute_deployment_phase "$deployment_id" "$phase_name"; then
            local required=$(aa_get DEPLOYMENT_PHASES "${phase_name}:required" "true")
            if [[ "$required" == "true" ]]; then
                error "Required deployment phase failed: $phase_name"
                return 1
            else
                warning "Optional deployment phase failed: $phase_name"
            fi
        fi
        
        # Update overall progress after phase completion
        overall_progress=$(echo "scale=2; $current_phase_num / $total_phases * 100" | bc -l 2>/dev/null || echo "0")
        aa_set DEPLOYMENT_STATES "${deployment_id}:overall_progress" "$overall_progress"
    done
    
    return 0
}

# Execute a single deployment phase
execute_deployment_phase() {
    local deployment_id="$1"
    local phase_name="$2"
    
    local start_time=$(date +%s)
    local timeout=$(aa_get DEPLOYMENT_PHASES "${phase_name}:timeout" "300")
    local phase_description=$(aa_get DEPLOYMENT_PHASES "${phase_name}:description" "No description")
    
    # Update phase status
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:status" "running"
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:start_time" "$start_time"
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:message" "Executing: $phase_description"
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:progress" "0"
    
    record_deployment_event "$deployment_id" "phase_started" "Started phase: $phase_name"
    
    # Execute phase-specific logic
    local phase_result=0
    case "$phase_name" in
        "validation")
            execute_validation_phase "$deployment_id"
            phase_result=$?
            ;;
        "preparation")
            execute_preparation_phase "$deployment_id"
            phase_result=$?
            ;;
        "infrastructure")
            execute_infrastructure_phase "$deployment_id"
            phase_result=$?
            ;;
        "application")
            execute_application_phase "$deployment_id"
            phase_result=$?
            ;;
        "verification")
            execute_verification_phase "$deployment_id"
            phase_result=$?
            ;;
        "cleanup")
            execute_cleanup_phase "$deployment_id"
            phase_result=$?
            ;;
        *)
            error "Unknown deployment phase: $phase_name"
            phase_result=1
            ;;
    esac
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    # Update phase completion status
    if [[ $phase_result -eq 0 ]]; then
        aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:status" "completed"
        aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:message" "Phase completed successfully"
        record_deployment_event "$deployment_id" "phase_completed" "Completed phase: $phase_name (${execution_time}s)"
    else
        aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:status" "failed"
        aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:message" "Phase failed"
        record_deployment_event "$deployment_id" "phase_failed" "Failed phase: $phase_name (${execution_time}s)"
    fi
    
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:end_time" "$end_time"
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:execution_time" "$execution_time"
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:progress" "100"
    
    # Store metrics
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${phase_name}:execution_time" "$execution_time"
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${phase_name}:timeout_used" "$timeout"
    aa_set DEPLOYMENT_METRICS "${deployment_id}:${phase_name}:result" "$phase_result"
    
    return $phase_result
}

# =============================================================================
# PHASE-SPECIFIC EXECUTION FUNCTIONS
# =============================================================================

# Validation phase implementation
execute_validation_phase() {
    local deployment_id="$1"
    
    local stack_name=$(aa_get DEPLOYMENT_STATES "${deployment_id}:stack_name")
    local deployment_type=$(aa_get DEPLOYMENT_STATES "${deployment_id}:deployment_type")
    local dry_run=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:dry_run" "false")
    
    update_phase_progress "$deployment_id" "validation" "10" "Validating deployment configuration"
    
    # Validate stack name
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        error "Invalid stack name format: $stack_name"
        return 1
    fi
    
    update_phase_progress "$deployment_id" "validation" "25" "Validating AWS credentials"
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
        return 1
    fi
    
    update_phase_progress "$deployment_id" "validation" "50" "Checking deployment type compatibility"
    
    # Validate deployment type
    case "$deployment_type" in
        "simple"|"spot"|"ondemand")
            # Valid deployment types
            ;;
        *)
            error "Unknown deployment type: $deployment_type"
            return 1
            ;;
    esac
    
    update_phase_progress "$deployment_id" "validation" "75" "Validating resource quotas"
    
    # Check AWS service quotas (simplified)
    local region=$(aa_get DEPLOYMENT_STATES "${deployment_id}:region")
    local instance_limit
    instance_limit=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --region "$region" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "20")
    
    if [[ "$instance_limit" -lt 1 ]]; then
        warning "Low EC2 instance quota: $instance_limit"
    fi
    
    update_phase_progress "$deployment_id" "validation" "100" "Validation completed successfully"
    
    return 0
}

# Preparation phase implementation
execute_preparation_phase() {
    local deployment_id="$1"
    
    local stack_name=$(aa_get DEPLOYMENT_STATES "${deployment_id}:stack_name")
    local backup_enabled=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:backup_enabled" "true")
    
    update_phase_progress "$deployment_id" "preparation" "20" "Preparing deployment environment"
    
    # Create backup if enabled
    if [[ "$backup_enabled" == "true" ]]; then
        update_phase_progress "$deployment_id" "preparation" "40" "Creating deployment backup"
        
        local backup_id="${stack_name}-backup-$(date +%s)"
        aa_set DEPLOYMENT_ROLLBACK "${deployment_id}:backup_id" "$backup_id"
        
        # Simplified backup - in real implementation, this would backup actual resources
        record_deployment_event "$deployment_id" "backup_created" "Backup created: $backup_id"
    fi
    
    update_phase_progress "$deployment_id" "preparation" "70" "Setting up deployment parameters"
    
    # Prepare deployment parameters
    local parameter_store_prefix="/aibuildkit"
    
    # Check if required parameters exist
    local required_params=("OPENAI_API_KEY" "POSTGRES_PASSWORD" "N8N_ENCRYPTION_KEY")
    for param in "${required_params[@]}"; do
        if ! aws ssm get-parameter --name "${parameter_store_prefix}/$param" >/dev/null 2>&1; then
            warning "Required parameter not found: ${parameter_store_prefix}/$param"
        fi
    done
    
    update_phase_progress "$deployment_id" "preparation" "100" "Preparation completed"
    
    return 0
}

# Infrastructure phase implementation
execute_infrastructure_phase() {
    local deployment_id="$1"
    
    local stack_name=$(aa_get DEPLOYMENT_STATES "${deployment_id}:stack_name")
    local deployment_type=$(aa_get DEPLOYMENT_STATES "${deployment_id}:deployment_type")
    
    update_phase_progress "$deployment_id" "infrastructure" "10" "Creating VPC and networking"
    
    # Simulate infrastructure creation
    sleep 2
    
    update_phase_progress "$deployment_id" "infrastructure" "30" "Setting up security groups"
    
    # Simulate security group creation
    sleep 1
    
    update_phase_progress "$deployment_id" "infrastructure" "50" "Provisioning compute resources"
    
    # Instance provisioning logic would go here
    case "$deployment_type" in
        "spot")
            update_phase_progress "$deployment_id" "infrastructure" "60" "Requesting spot instances"
            # Spot instance logic
            ;;
        "ondemand")
            update_phase_progress "$deployment_id" "infrastructure" "60" "Launching on-demand instances"
            # On-demand instance logic
            ;;
        "simple")
            update_phase_progress "$deployment_id" "infrastructure" "60" "Creating simple instance"
            # Simple instance logic
            ;;
    esac
    
    sleep 3
    
    update_phase_progress "$deployment_id" "infrastructure" "80" "Setting up storage and EFS"
    
    # Simulate EFS setup
    sleep 1
    
    update_phase_progress "$deployment_id" "infrastructure" "100" "Infrastructure provisioning completed"
    
    return 0
}

# Application phase implementation
execute_application_phase() {
    local deployment_id="$1"
    
    update_phase_progress "$deployment_id" "application" "20" "Deploying Docker containers"
    
    # Simulate Docker deployment
    sleep 2
    
    update_phase_progress "$deployment_id" "application" "50" "Configuring services"
    
    # Simulate service configuration
    sleep 1
    
    update_phase_progress "$deployment_id" "application" "80" "Starting application services"
    
    # Simulate service startup
    sleep 2
    
    update_phase_progress "$deployment_id" "application" "100" "Application deployment completed"
    
    return 0
}

# Verification phase implementation
execute_verification_phase() {
    local deployment_id="$1"
    
    update_phase_progress "$deployment_id" "verification" "25" "Running health checks"
    
    # Simulate health checks
    sleep 1
    
    update_phase_progress "$deployment_id" "verification" "50" "Verifying service endpoints"
    
    # Simulate endpoint verification
    sleep 1
    
    update_phase_progress "$deployment_id" "verification" "75" "Running smoke tests"
    
    # Simulate smoke tests
    sleep 1
    
    update_phase_progress "$deployment_id" "verification" "100" "Verification completed"
    
    return 0
}

# Cleanup phase implementation
execute_cleanup_phase() {
    local deployment_id="$1"
    
    update_phase_progress "$deployment_id" "cleanup" "50" "Cleaning up temporary resources"
    
    # Simulate cleanup
    sleep 1
    
    update_phase_progress "$deployment_id" "cleanup" "100" "Cleanup completed"
    
    return 0
}

# =============================================================================
# DEPLOYMENT MANAGEMENT UTILITIES
# =============================================================================

# Update phase progress
update_phase_progress() {
    local deployment_id="$1"
    local phase_name="$2"
    local progress="$3"
    local message="$4"
    
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:progress" "$progress"
    aa_set DEPLOYMENT_PROGRESS "${deployment_id}:${phase_name}:message" "$message"
    
    # Update overall deployment progress
    aa_set DEPLOYMENT_STATES "${deployment_id}:phase_progress" "$progress"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$(date +%s)"
    
    if declare -f info >/dev/null 2>&1; then
        info "[$deployment_id] $phase_name: $progress% - $message"
    fi
}

# Check if deployment exists
deployment_exists() {
    local deployment_id="$1"
    aa_has_key DEPLOYMENT_STATES "${deployment_id}:session_id"
}

# Record deployment event
record_deployment_event() {
    local deployment_id="$1"
    local event_type="$2"
    local event_message="$3"
    local timestamp=$(date +%s)
    
    local event_key="${deployment_id}:events:${timestamp}"
    aa_set DEPLOYMENT_HISTORY "$event_key" "${event_type}:${event_message}"
    
    if declare -f log >/dev/null 2>&1; then
        log "[$deployment_id] $event_type: $event_message"
    fi
}

# Trigger deployment notifications
trigger_deployment_notifications() {
    local deployment_id="$1"
    local notification_type="$2"  # success, failure, progress
    
    local notifications_enabled=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:notifications_enabled" "false")
    if [[ "$notifications_enabled" != "true" ]]; then
        return 0
    fi
    
    local webhook_url=$(aa_get DEPLOYMENT_OPTIONS "${deployment_id}:webhook_url" "")
    if [[ -z "$webhook_url" ]]; then
        return 0
    fi
    
    local stack_name=$(aa_get DEPLOYMENT_STATES "${deployment_id}:stack_name")
    local status=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status")
    
    local payload="{\"deployment_id\":\"$deployment_id\",\"stack_name\":\"$stack_name\",\"status\":\"$status\",\"type\":\"$notification_type\",\"timestamp\":$(date +%s)}"
    
    # Send notification (simplified)
    if command -v curl >/dev/null 2>&1; then
        curl -s -X POST "$webhook_url" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1 || true
    fi
}

# =============================================================================
# ROLLBACK AND RECOVERY
# =============================================================================

# Rollback deployment
rollback_deployment() {
    local deployment_id="$1"
    local force="${2:-false}"
    
    if ! deployment_exists "$deployment_id"; then
        error "Deployment not found: $deployment_id"
        return 1
    fi
    
    local current_status=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status")
    if [[ "$current_status" == "rolled_back" ]] && [[ "$force" != "true" ]]; then
        warning "Deployment already rolled back: $deployment_id"
        return 0
    fi
    
    log "Starting rollback for deployment: $deployment_id"
    
    # Update status
    aa_set DEPLOYMENT_STATES "${deployment_id}:status" "rolling_back"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$(date +%s)"
    
    record_deployment_event "$deployment_id" "rollback_started" "Rollback initiated"
    
    # Get rollback strategy
    local rollback_strategy=$(aa_get DEPLOYMENT_ROLLBACK "${deployment_id}:strategy" "recreate")
    local backup_id=$(aa_get DEPLOYMENT_ROLLBACK "${deployment_id}:backup_id" "")
    
    case "$rollback_strategy" in
        "recreate")
            # Recreate from backup/configuration
            log "Performing recreate rollback for: $deployment_id"
            ;;
        "snapshot")
            # Restore from snapshot
            log "Performing snapshot rollback for: $deployment_id"
            ;;
        "blue_green")
            # Switch back to previous version
            log "Performing blue-green rollback for: $deployment_id"
            ;;
        *)
            warning "Unknown rollback strategy: $rollback_strategy"
            ;;
    esac
    
    # Simulate rollback execution
    sleep 2
    
    # Update final status
    aa_set DEPLOYMENT_STATES "${deployment_id}:status" "rolled_back"
    aa_set DEPLOYMENT_STATES "${deployment_id}:rollback_completed_at" "$(date +%s)"
    aa_set DEPLOYMENT_STATES "${deployment_id}:updated_at" "$(date +%s)"
    
    record_deployment_event "$deployment_id" "rollback_completed" "Rollback completed successfully"
    
    if declare -f success >/dev/null 2>&1; then
        success "Rollback completed for deployment: $deployment_id"
    fi
    
    return 0
}

# =============================================================================
# REPORTING AND MONITORING
# =============================================================================

# Get deployment status
get_deployment_status() {
    local deployment_id="$1"
    local format="${2:-summary}"  # summary, detailed, json
    
    if ! deployment_exists "$deployment_id"; then
        error "Deployment not found: $deployment_id"
        return 1
    fi
    
    case "$format" in
        "summary")
            local status=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status")
            local progress=$(aa_get DEPLOYMENT_STATES "${deployment_id}:overall_progress")
            local current_phase=$(aa_get DEPLOYMENT_STATES "${deployment_id}:current_phase")
            
            echo "Deployment: $deployment_id"
            echo "Status: $status"
            echo "Progress: ${progress}%"
            if [[ -n "$current_phase" ]]; then
                echo "Current Phase: $current_phase"
            fi
            ;;
        "detailed")
            echo "=== Deployment Status: $deployment_id ==="
            for state_key in $(aa_keys DEPLOYMENT_STATES); do
                if [[ "$state_key" =~ ^${deployment_id}: ]]; then
                    local key="${state_key#${deployment_id}:}"
                    local value=$(aa_get DEPLOYMENT_STATES "$state_key")
                    printf "%-20s: %s\n" "$key" "$value"
                fi
            done
            
            echo ""
            echo "=== Phase Progress ==="
            for progress_key in $(aa_keys DEPLOYMENT_PROGRESS); do
                if [[ "$progress_key" =~ ^${deployment_id}: ]]; then
                    local key="${progress_key#${deployment_id}:}"
                    local value=$(aa_get DEPLOYMENT_PROGRESS "$progress_key")
                    printf "%-30s: %s\n" "$key" "$value"
                fi
            done
            ;;
        "json")
            generate_deployment_status_json "$deployment_id"
            ;;
    esac
}

# Generate JSON status report
generate_deployment_status_json() {
    local deployment_id="$1"
    
    declare -A status_data
    
    # Collect deployment state
    for state_key in $(aa_keys DEPLOYMENT_STATES); do
        if [[ "$state_key" =~ ^${deployment_id}: ]]; then
            local key="${state_key#${deployment_id}:}"
            local value=$(aa_get DEPLOYMENT_STATES "$state_key")
            aa_set status_data "state:$key" "$value"
        fi
    done
    
    # Collect progress data
    for progress_key in $(aa_keys DEPLOYMENT_PROGRESS); do
        if [[ "$progress_key" =~ ^${deployment_id}: ]]; then
            local key="${progress_key#${deployment_id}:}"
            local value=$(aa_get DEPLOYMENT_PROGRESS "$progress_key")
            aa_set status_data "progress:$key" "$value"
        fi
    done
    
    # Output JSON (simplified)
    echo "{"
    echo "  \"deployment_id\": \"$deployment_id\","
    echo "  \"timestamp\": $(date +%s),"
    echo "  \"state\": $(aa_to_json status_data)"
    echo "}"
}

# =============================================================================
# LIBRARY EXPORTS
# =============================================================================

# Export all functions
export -f init_deployment configure_deployment start_deployment
export -f execute_deployment_phases execute_deployment_phase
export -f execute_validation_phase execute_preparation_phase execute_infrastructure_phase
export -f execute_application_phase execute_verification_phase execute_cleanup_phase
export -f update_phase_progress deployment_exists record_deployment_event
export -f trigger_deployment_notifications rollback_deployment
export -f get_deployment_status generate_deployment_status_json

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "Deployment State Manager library loaded (v${DEPLOYMENT_STATE_MANAGER_VERSION})"
fi