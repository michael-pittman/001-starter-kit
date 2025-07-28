#!/usr/bin/env bash
# =============================================================================
# AWS Resource Management Library
# Enhanced resource tracking, monitoring, and lifecycle management using bash 5.3.3+
# Requires: bash 5.3.3+
# =============================================================================

# Bash version validation
if [[ -z "${BASH_VERSION_VALIDATED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/modules/core/bash_version.sh"
    require_bash_533 "aws-resource-manager.sh"
    export BASH_VERSION_VALIDATED=true
fi

# Load associative array utilities
source "$SCRIPT_DIR/associative-arrays.sh"

# Prevent multiple sourcing
if [[ "${AWS_RESOURCE_MANAGER_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly AWS_RESOURCE_MANAGER_LIB_LOADED=true

# =============================================================================
# LIBRARY METADATA
# =============================================================================

readonly AWS_RESOURCE_MANAGER_VERSION="1.0.0"
readonly REQUIRED_BASH_VERSION="5.3.3"

# =============================================================================
# GLOBAL ASSOCIATIVE ARRAYS FOR RESOURCE MANAGEMENT
# =============================================================================

# Resource tracking and state management
declare -gA AWS_RESOURCES              # All tracked resources
declare -gA RESOURCE_DEPENDENCIES      # Resource dependency mapping
declare -gA RESOURCE_METADATA          # Resource metadata and tags
declare -gA RESOURCE_STATE_HISTORY     # Resource state change history
declare -gA RESOURCE_LIFECYCLE         # Resource lifecycle management
declare -gA RESOURCE_MONITORING        # Resource monitoring and health
declare -gA STACK_RESOURCES            # Resources grouped by stack

# Resource type definitions
declare -gA RESOURCE_TYPES
aa_set RESOURCE_TYPES "compute" "ec2:instances,ec2:spot-requests,autoscaling:groups"
aa_set RESOURCE_TYPES "network" "ec2:vpcs,ec2:subnets,ec2:security-groups,elbv2:load-balancers"
aa_set RESOURCE_TYPES "storage" "ec2:volumes,efs:file-systems,s3:buckets"
aa_set RESOURCE_TYPES "database" "rds:instances,dynamodb:tables"
aa_set RESOURCE_TYPES "monitoring" "cloudwatch:alarms,logs:log-groups"
aa_set RESOURCE_TYPES "security" "iam:roles,iam:policies,secretsmanager:secrets"

# Resource lifecycle states
declare -gA LIFECYCLE_STATES
aa_set LIFECYCLE_STATES "creating" "Resource is being created"
aa_set LIFECYCLE_STATES "active" "Resource is active and operational"
aa_set LIFECYCLE_STATES "updating" "Resource is being updated"
aa_set LIFECYCLE_STATES "stopping" "Resource is being stopped"
aa_set LIFECYCLE_STATES "stopped" "Resource is stopped"
aa_set LIFECYCLE_STATES "deleting" "Resource is being deleted"
aa_set LIFECYCLE_STATES "deleted" "Resource has been deleted"
aa_set LIFECYCLE_STATES "error" "Resource is in error state"

# =============================================================================
# RESOURCE REGISTRATION AND TRACKING
# =============================================================================

# Register a new AWS resource
# Usage: register_aws_resource resource_id resource_type resource_arn stack_name [metadata_json]
register_aws_resource() {
    local resource_id="$1"
    local resource_type="$2"
    local resource_arn="$3"
    local stack_name="$4"
    local metadata_json="${5:-{}}"
    
    if [[ -z "$resource_id" ]] || [[ -z "$resource_type" ]] || [[ -z "$resource_arn" ]]; then
        error "register_aws_resource requires resource_id, resource_type, and resource_arn"
        return 1
    fi
    
    local timestamp=$(date +%s)
    local resource_key="${stack_name}:${resource_type}:${resource_id}"
    
    # Register basic resource information
    aa_set AWS_RESOURCES "${resource_key}:id" "$resource_id"
    aa_set AWS_RESOURCES "${resource_key}:type" "$resource_type"
    aa_set AWS_RESOURCES "${resource_key}:arn" "$resource_arn"
    aa_set AWS_RESOURCES "${resource_key}:stack_name" "$stack_name"
    aa_set AWS_RESOURCES "${resource_key}:created_at" "$timestamp"
    aa_set AWS_RESOURCES "${resource_key}:last_updated" "$timestamp"
    aa_set AWS_RESOURCES "${resource_key}:state" "creating"
    aa_set AWS_RESOURCES "${resource_key}:region" "${AWS_REGION:-us-east-1}"
    
    # Parse and store metadata if provided
    if [[ "$metadata_json" != "{}" ]] && command -v jq >/dev/null 2>&1; then
        local metadata_keys
        metadata_keys=$(echo "$metadata_json" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        for key in $metadata_keys; do
            local value
            value=$(echo "$metadata_json" | jq -r ".$key" 2>/dev/null || echo "")
            if [[ -n "$value" && "$value" != "null" ]]; then
                aa_set RESOURCE_METADATA "${resource_key}:${key}" "$value"
            fi
        done
    fi
    
    # Add to stack resources index
    local stack_resources_key="${stack_name}:${resource_type}"
    local existing_resources=$(aa_get STACK_RESOURCES "$stack_resources_key" "")
    if [[ -n "$existing_resources" ]]; then
        aa_set STACK_RESOURCES "$stack_resources_key" "${existing_resources},${resource_id}"
    else
        aa_set STACK_RESOURCES "$stack_resources_key" "$resource_id"
    fi
    
    # Record state change
    record_resource_state_change "$resource_key" "created" "Resource registered in resource manager"
    
    if declare -f log >/dev/null 2>&1; then
        log "Registered AWS resource: $resource_type/$resource_id in stack $stack_name"
    fi
}

# Update resource state
# Usage: update_resource_state resource_key new_state [description]
update_resource_state() {
    local resource_key="$1"
    local new_state="$2"
    local description="${3:-State updated}"
    
    if ! aa_has_key AWS_RESOURCES "${resource_key}:id"; then
        error "Resource not found: $resource_key"
        return 1
    fi
    
    local old_state=$(aa_get AWS_RESOURCES "${resource_key}:state" "unknown")
    local timestamp=$(date +%s)
    
    # Update resource state
    aa_set AWS_RESOURCES "${resource_key}:state" "$new_state"
    aa_set AWS_RESOURCES "${resource_key}:last_updated" "$timestamp"
    
    # Record state change
    record_resource_state_change "$resource_key" "$new_state" "$description"
    
    if declare -f log >/dev/null 2>&1; then
        log "Resource state updated: $resource_key: $old_state -> $new_state"
    fi
}

# Record resource state change in history
record_resource_state_change() {
    local resource_key="$1"
    local new_state="$2"
    local description="$3"
    local timestamp=$(date +%s)
    
    local history_key="${resource_key}:history:${timestamp}"
    aa_set RESOURCE_STATE_HISTORY "$history_key" "$new_state:$description"
}

# =============================================================================
# RESOURCE DISCOVERY AND SYNCHRONIZATION
# =============================================================================

# Discover and register EC2 instances for a stack
discover_ec2_instances() {
    local stack_name="$1"
    local region="${2:-$AWS_REGION}"
    
    if [[ -z "$stack_name" ]]; then
        error "discover_ec2_instances requires stack_name"
        return 1
    fi
    
    log "Discovering EC2 instances for stack: $stack_name"
    
    # Query EC2 instances with stack tag
    local instances_json
    instances_json=$(aws ec2 describe-instances \
        --region "$region" \
        --filters "Name=tag:Stack,Values=$stack_name" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,LaunchTime,Tags]' \
        --output json 2>/dev/null)
    
    if [[ -z "$instances_json" ]] || [[ "$instances_json" == "[]" ]]; then
        log "No EC2 instances found for stack: $stack_name"
        return 0
    fi
    
    # Process each instance
    local instance_count=0
    if command -v jq >/dev/null 2>&1; then
        local instances_array
        instances_array=$(echo "$instances_json" | jq -c '.[]' 2>/dev/null)
        
        while IFS= read -r instance_data; do
            if [[ -n "$instance_data" ]]; then
                local instance_id instance_type state launch_time
                instance_id=$(echo "$instance_data" | jq -r '.[0]' 2>/dev/null)
                instance_type=$(echo "$instance_data" | jq -r '.[1]' 2>/dev/null)
                state=$(echo "$instance_data" | jq -r '.[2]' 2>/dev/null)
                launch_time=$(echo "$instance_data" | jq -r '.[3]' 2>/dev/null)
                
                if [[ -n "$instance_id" && "$instance_id" != "null" ]]; then
                    # Create resource ARN
                    local instance_arn="arn:aws:ec2:${region}:${AWS_ACCOUNT_ID:-*}:instance/${instance_id}"
                    
                    # Create metadata
                    local metadata="{\"instance_type\":\"$instance_type\",\"launch_time\":\"$launch_time\",\"discovered\":true}"
                    
                    # Register the instance
                    register_aws_resource "$instance_id" "ec2:instance" "$instance_arn" "$stack_name" "$metadata"
                    
                    # Update state based on AWS state
                    case "$state" in
                        "running") update_resource_state "${stack_name}:ec2:instance:${instance_id}" "active" "Instance is running" ;;
                        "pending") update_resource_state "${stack_name}:ec2:instance:${instance_id}" "creating" "Instance is starting" ;;
                        "stopping") update_resource_state "${stack_name}:ec2:instance:${instance_id}" "stopping" "Instance is stopping" ;;
                        "stopped") update_resource_state "${stack_name}:ec2:instance:${instance_id}" "stopped" "Instance is stopped" ;;
                        *) update_resource_state "${stack_name}:ec2:instance:${instance_id}" "unknown" "Unknown state: $state" ;;
                    esac
                    
                    instance_count=$((instance_count + 1))
                fi
            fi
        done <<< "$instances_array"
    fi
    
    success "Discovered and registered $instance_count EC2 instances for stack: $stack_name"
}

# Discover and register ELB load balancers
discover_load_balancers() {
    local stack_name="$1"
    local region="${2:-$AWS_REGION}"
    
    log "Discovering load balancers for stack: $stack_name"
    
    # Discover Application Load Balancers
    local albs_json
    albs_json=$(aws elbv2 describe-load-balancers \
        --region "$region" \
        --query "LoadBalancers[?contains(LoadBalancerName, '$stack_name')].[LoadBalancerArn,LoadBalancerName,State.Code,Type,CreatedTime]" \
        --output json 2>/dev/null)
    
    local alb_count=0
    if [[ -n "$albs_json" ]] && [[ "$albs_json" != "[]" ]] && command -v jq >/dev/null 2>&1; then
        local albs_array
        albs_array=$(echo "$albs_json" | jq -c '.[]' 2>/dev/null)
        
        while IFS= read -r alb_data; do
            if [[ -n "$alb_data" ]]; then
                local alb_arn alb_name state alb_type created_time
                alb_arn=$(echo "$alb_data" | jq -r '.[0]' 2>/dev/null)
                alb_name=$(echo "$alb_data" | jq -r '.[1]' 2>/dev/null)
                state=$(echo "$alb_data" | jq -r '.[2]' 2>/dev/null)
                alb_type=$(echo "$alb_data" | jq -r '.[3]' 2>/dev/null)
                created_time=$(echo "$alb_data" | jq -r '.[4]' 2>/dev/null)
                
                if [[ -n "$alb_arn" && "$alb_arn" != "null" ]]; then
                    local metadata="{\"type\":\"$alb_type\",\"created_time\":\"$created_time\",\"discovered\":true}"
                    
                    register_aws_resource "$alb_name" "elbv2:load-balancer" "$alb_arn" "$stack_name" "$metadata"
                    
                    case "$state" in
                        "active") update_resource_state "${stack_name}:elbv2:load-balancer:${alb_name}" "active" "Load balancer is active" ;;
                        "provisioning") update_resource_state "${stack_name}:elbv2:load-balancer:${alb_name}" "creating" "Load balancer is provisioning" ;;
                        *) update_resource_state "${stack_name}:elbv2:load-balancer:${alb_name}" "unknown" "Unknown state: $state" ;;
                    esac
                    
                    alb_count=$((alb_count + 1))
                fi
            fi
        done <<< "$albs_array"
    fi
    
    success "Discovered and registered $alb_count load balancers for stack: $stack_name"
}

# Comprehensive resource discovery for a stack
discover_all_resources() {
    local stack_name="$1"
    local region="${2:-$AWS_REGION}"
    
    if [[ -z "$stack_name" ]]; then
        error "discover_all_resources requires stack_name"
        return 1
    fi
    
    log "Starting comprehensive resource discovery for stack: $stack_name"
    
    # Discover different resource types
    discover_ec2_instances "$stack_name" "$region"
    discover_load_balancers "$stack_name" "$region"
    
    # Add more discovery functions as needed
    # discover_efs_file_systems "$stack_name" "$region"
    # discover_rds_instances "$stack_name" "$region"
    # discover_security_groups "$stack_name" "$region"
    
    success "Completed resource discovery for stack: $stack_name"
}

# =============================================================================
# RESOURCE MONITORING AND HEALTH CHECKS
# =============================================================================

# Monitor resource health
monitor_resource_health() {
    local resource_key="$1"
    local check_type="${2:-basic}"  # basic, detailed, full
    
    if ! aa_has_key AWS_RESOURCES "${resource_key}:id"; then
        error "Resource not found: $resource_key"
        return 1
    fi
    
    local resource_type=$(aa_get AWS_RESOURCES "${resource_key}:type")
    local resource_id=$(aa_get AWS_RESOURCES "${resource_key}:id")
    local region=$(aa_get AWS_RESOURCES "${resource_key}:region")
    
    declare -A health_status
    aa_set health_status "resource_key" "$resource_key"
    aa_set health_status "check_time" "$(date +%s)"
    aa_set health_status "check_type" "$check_type"
    
    case "$resource_type" in
        "ec2:instance")
            check_ec2_instance_health "$resource_id" "$region" health_status "$check_type"
            ;;
        "elbv2:load-balancer")
            check_alb_health "$resource_id" "$region" health_status "$check_type"
            ;;
        *)
            aa_set health_status "status" "unknown"
            aa_set health_status "message" "Health check not implemented for resource type: $resource_type"
            ;;
    esac
    
    # Store health check results
    local timestamp=$(date +%s)
    local health_key="${resource_key}:health:${timestamp}"
    aa_set RESOURCE_MONITORING "$health_key" "$(aa_to_json health_status)"
    
    # Update resource monitoring summary
    local status=$(aa_get health_status "status")
    aa_set RESOURCE_MONITORING "${resource_key}:last_health_check" "$timestamp"
    aa_set RESOURCE_MONITORING "${resource_key}:last_health_status" "$status"
    
    echo "$status"
}

# Check EC2 instance health
check_ec2_instance_health() {
    local instance_id="$1"
    local region="$2"
    local -n health_ref="$3"
    local check_type="$4"
    
    # Get instance status
    local instance_status
    instance_status=$(aws ec2 describe-instance-status \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'InstanceStatuses[0].[InstanceStatus.Status,SystemStatus.Status,InstanceState.Name]' \
        --output text 2>/dev/null)
    
    if [[ -n "$instance_status" ]]; then
        local instance_check system_check instance_state
        instance_check=$(echo "$instance_status" | cut -f1)
        system_check=$(echo "$instance_status" | cut -f2)
        instance_state=$(echo "$instance_status" | cut -f3)
        
        aa_set health_ref "instance_check" "$instance_check"
        aa_set health_ref "system_check" "$system_check"
        aa_set health_ref "instance_state" "$instance_state"
        
        # Determine overall health status
        if [[ "$instance_check" == "ok" && "$system_check" == "ok" && "$instance_state" == "running" ]]; then
            aa_set health_ref "status" "healthy"
            aa_set health_ref "message" "Instance is healthy and running"
        elif [[ "$instance_state" == "running" ]]; then
            aa_set health_ref "status" "degraded"
            aa_set health_ref "message" "Instance is running but has health check issues"
        else
            aa_set health_ref "status" "unhealthy"
            aa_set health_ref "message" "Instance is not running: $instance_state"
        fi
    else
        aa_set health_ref "status" "unknown"
        aa_set health_ref "message" "Unable to retrieve instance status"
    fi
    
    # Additional checks for detailed monitoring
    if [[ "$check_type" == "detailed" || "$check_type" == "full" ]]; then
        # Check CPU utilization
        local cpu_utilization
        cpu_utilization=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/EC2 \
            --metric-name CPUUtilization \
            --dimensions Name=InstanceId,Value="$instance_id" \
            --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 300 \
            --statistics Average \
            --region "$region" \
            --query 'Datapoints[0].Average' \
            --output text 2>/dev/null)
        
        if [[ -n "$cpu_utilization" && "$cpu_utilization" != "None" ]]; then
            aa_set health_ref "cpu_utilization" "$cpu_utilization"
        fi
    fi
}

# Check Application Load Balancer health
check_alb_health() {
    local alb_name="$1"
    local region="$2"
    local -n health_ref="$3"
    local check_type="$4"
    
    # Get ALB status
    local alb_status
    alb_status=$(aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --region "$region" \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null)
    
    if [[ -n "$alb_status" ]]; then
        aa_set health_ref "alb_state" "$alb_status"
        
        case "$alb_status" in
            "active")
                aa_set health_ref "status" "healthy"
                aa_set health_ref "message" "Load balancer is active"
                ;;
            "provisioning")
                aa_set health_ref "status" "creating"
                aa_set health_ref "message" "Load balancer is provisioning"
                ;;
            *)
                aa_set health_ref "status" "unhealthy"
                aa_set health_ref "message" "Load balancer state: $alb_status"
                ;;
        esac
    else
        aa_set health_ref "status" "unknown"
        aa_set health_ref "message" "Unable to retrieve load balancer status"
    fi
}

# =============================================================================
# RESOURCE LIFECYCLE MANAGEMENT
# =============================================================================

# Set resource lifecycle policy
set_resource_lifecycle_policy() {
    local resource_key="$1"
    local policy_name="$2"
    local policy_config="$3"  # JSON string
    
    if ! aa_has_key AWS_RESOURCES "${resource_key}:id"; then
        error "Resource not found: $resource_key"
        return 1
    fi
    
    aa_set RESOURCE_LIFECYCLE "${resource_key}:policy" "$policy_name"
    aa_set RESOURCE_LIFECYCLE "${resource_key}:config" "$policy_config"
    aa_set RESOURCE_LIFECYCLE "${resource_key}:set_at" "$(date +%s)"
    
    log "Set lifecycle policy '$policy_name' for resource: $resource_key"
}

# Apply automatic cleanup based on lifecycle policies
apply_lifecycle_policies() {
    local stack_name="${1:-}"
    local dry_run="${2:-true}"
    
    declare -A cleanup_actions
    local resource_key
    
    # Check all resources for lifecycle policies
    for resource_key in $(aa_keys AWS_RESOURCES); do
        if [[ "$resource_key" =~ :id$ ]]; then
            local base_key="${resource_key%:id}"
            
            # Skip if stack filter is set and doesn't match
            if [[ -n "$stack_name" ]]; then
                local resource_stack=$(aa_get AWS_RESOURCES "${base_key}:stack_name" "")
                if [[ "$resource_stack" != "$stack_name" ]]; then
                    continue
                fi
            fi
            
            # Check if resource has lifecycle policy
            local policy=$(aa_get RESOURCE_LIFECYCLE "${base_key}:policy" "")
            if [[ -n "$policy" ]]; then
                evaluate_lifecycle_policy "$base_key" "$policy" cleanup_actions "$dry_run"
            fi
        fi
    done
    
    # Report cleanup actions
    if ! aa_is_empty cleanup_actions; then
        info "Lifecycle policy evaluation results:"
        aa_print_table cleanup_actions "Resource" "Action"
    else
        info "No lifecycle actions required"
    fi
}

# Evaluate specific lifecycle policy for a resource
evaluate_lifecycle_policy() {
    local resource_key="$1"
    local policy_name="$2"
    local -n actions_ref="$3"
    local dry_run="$4"
    
    local resource_id=$(aa_get AWS_RESOURCES "${resource_key}:id")
    local created_at=$(aa_get AWS_RESOURCES "${resource_key}:created_at")
    local current_time=$(date +%s)
    local age_hours=$(( (current_time - created_at) / 3600 ))
    
    case "$policy_name" in
        "development_cleanup")
            # Clean up development resources after 24 hours
            if [[ $age_hours -gt 24 ]]; then
                aa_set actions_ref "$resource_key" "DELETE (dev cleanup after 24h)"
                if [[ "$dry_run" != "true" ]]; then
                    schedule_resource_deletion "$resource_key" "development_cleanup"
                fi
            fi
            ;;
        "cost_optimization")
            # Stop instances after 8 hours of inactivity
            local last_activity=$(aa_get RESOURCE_MONITORING "${resource_key}:last_activity" "$created_at")
            local inactive_hours=$(( (current_time - last_activity) / 3600 ))
            
            if [[ $inactive_hours -gt 8 ]]; then
                aa_set actions_ref "$resource_key" "STOP (inactive for ${inactive_hours}h)"
                if [[ "$dry_run" != "true" ]]; then
                    schedule_resource_action "$resource_key" "stop" "cost_optimization"
                fi
            fi
            ;;
        "spot_instance_management")
            # Special handling for spot instances
            local resource_type=$(aa_get AWS_RESOURCES "${resource_key}:type")
            if [[ "$resource_type" == "ec2:spot-request" ]]; then
                local state=$(aa_get AWS_RESOURCES "${resource_key}:state")
                if [[ "$state" == "error" ]]; then
                    aa_set actions_ref "$resource_key" "RECREATE (spot instance failed)"
                fi
            fi
            ;;
    esac
}

# =============================================================================
# RESOURCE REPORTING AND ANALYTICS
# =============================================================================

# Generate comprehensive resource report
generate_resource_report() {
    local stack_name="${1:-}"
    local output_format="${2:-table}"  # table, json, yaml
    local include_history="${3:-false}"
    
    declare -A report_summary
    declare -A resource_counts
    declare -A state_counts
    
    # Initialize counters
    aa_set resource_counts "total" "0"
    aa_set state_counts "active" "0"
    aa_set state_counts "stopped" "0"
    aa_set state_counts "error" "0"
    aa_set state_counts "unknown" "0"
    
    local resource_key
    for resource_key in $(aa_keys AWS_RESOURCES); do
        if [[ "$resource_key" =~ :id$ ]]; then
            local base_key="${resource_key%:id}"
            
            # Filter by stack if specified
            if [[ -n "$stack_name" ]]; then
                local resource_stack=$(aa_get AWS_RESOURCES "${base_key}:stack_name" "")
                if [[ "$resource_stack" != "$stack_name" ]]; then
                    continue
                fi
            fi
            
            local resource_type=$(aa_get AWS_RESOURCES "${base_key}:type")
            local resource_state=$(aa_get AWS_RESOURCES "${base_key}:state")
            local resource_id=$(aa_get AWS_RESOURCES "${base_key}:id")
            
            # Update counters
            local total_count=$(aa_get resource_counts "total")
            aa_set resource_counts "total" "$((total_count + 1))"
            
            local type_count=$(aa_get resource_counts "$resource_type" "0")
            aa_set resource_counts "$resource_type" "$((type_count + 1))"
            
            local state_count=$(aa_get state_counts "$resource_state" "0")
            aa_set state_counts "$resource_state" "$((state_count + 1))"
        fi
    done
    
    # Generate report based on format
    case "$output_format" in
        "table")
            echo "=== AWS Resource Report ==="
            if [[ -n "$stack_name" ]]; then
                echo "Stack: $stack_name"
            else
                echo "All Stacks"
            fi
            echo "Generated: $(date)"
            echo ""
            
            echo "Resource Summary:"
            aa_print_table resource_counts "Resource Type" "Count"
            echo ""
            
            echo "State Summary:"
            aa_print_table state_counts "State" "Count"
            ;;
        "json")
            local report_json="{"
            report_json+="\"summary\":{\"generated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
            if [[ -n "$stack_name" ]]; then
                report_json+=",\"stack\":\"$stack_name\""
            fi
            report_json+="},"
            report_json+="\"resource_counts\":$(aa_to_json resource_counts),"
            report_json+="\"state_counts\":$(aa_to_json state_counts)"
            report_json+="}"
            echo "$report_json"
            ;;
        "yaml")
            echo "summary:"
            echo "  generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            if [[ -n "$stack_name" ]]; then
                echo "  stack: $stack_name"
            fi
            echo "resource_counts:"
            for type in $(aa_keys resource_counts); do
                local count=$(aa_get resource_counts "$type")
                echo "  $type: $count"
            done
            echo "state_counts:"
            for state in $(aa_keys state_counts); do
                local count=$(aa_get state_counts "$state")
                echo "  $state: $count"
            done
            ;;
    esac
}

# Get resource dependencies
get_resource_dependencies() {
    local resource_key="$1"
    local direction="${2:-both}"  # dependencies, dependents, both
    
    declare -A dependencies_result
    
    case "$direction" in
        "dependencies"|"both")
            # Resources this resource depends on
            local deps=$(aa_get RESOURCE_DEPENDENCIES "${resource_key}:depends_on" "")
            if [[ -n "$deps" ]]; then
                aa_set dependencies_result "depends_on" "$deps"
            fi
            ;;
    esac
    
    case "$direction" in
        "dependents"|"both")
            # Resources that depend on this resource
            local dependents=""
            local dep_key
            for dep_key in $(aa_keys RESOURCE_DEPENDENCIES); do
                if [[ "$dep_key" =~ :depends_on$ ]]; then
                    local dep_list=$(aa_get RESOURCE_DEPENDENCIES "$dep_key")
                    if [[ "$dep_list" =~ $resource_key ]]; then
                        local dependent_resource="${dep_key%:depends_on}"
                        if [[ -n "$dependents" ]]; then
                            dependents+=","
                        fi
                        dependents+="$dependent_resource"
                    fi
                fi
            done
            
            if [[ -n "$dependents" ]]; then
                aa_set dependencies_result "dependents" "$dependents"
            fi
            ;;
    esac
    
    if ! aa_is_empty dependencies_result; then
        aa_print dependencies_result "Dependencies for $resource_key"
    else
        echo "No dependencies found for $resource_key"
    fi
}

# =============================================================================
# CLEANUP AND MAINTENANCE
# =============================================================================

# Clean up stale resource entries
cleanup_stale_resources() {
    local max_age_hours="${1:-72}"  # 3 days default
    local dry_run="${2:-true}"
    
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - (max_age_hours * 3600)))
    local cleanup_count=0
    
    declare -A stale_resources
    
    # Find stale resources
    local resource_key
    for resource_key in $(aa_keys AWS_RESOURCES); do
        if [[ "$resource_key" =~ :id$ ]]; then
            local base_key="${resource_key%:id}"
            local last_updated=$(aa_get AWS_RESOURCES "${base_key}:last_updated" "0")
            local state=$(aa_get AWS_RESOURCES "${base_key}:state")
            
            # Consider resources stale if they haven't been updated recently and are in terminal states
            if [[ $last_updated -lt $cutoff_time ]] && [[ "$state" =~ ^(deleted|error)$ ]]; then
                local resource_id=$(aa_get AWS_RESOURCES "${resource_key}")
                aa_set stale_resources "$base_key" "Last updated: $(date -d "@$last_updated"), State: $state"
                cleanup_count=$((cleanup_count + 1))
            fi
        fi
    done
    
    if [[ $cleanup_count -gt 0 ]]; then
        info "Found $cleanup_count stale resources"
        aa_print_table stale_resources "Resource" "Details"
        
        if [[ "$dry_run" != "true" ]]; then
            # Actually remove stale resources
            for resource_key in $(aa_keys stale_resources); do
                remove_resource_from_tracking "$resource_key"
            done
            success "Cleaned up $cleanup_count stale resources"
        else
            info "Dry run mode - no resources were removed"
        fi
    else
        info "No stale resources found"
    fi
}

# Remove resource from all tracking
remove_resource_from_tracking() {
    local resource_key="$1"
    
    # Remove from main resource tracking
    local key
    for key in $(aa_keys AWS_RESOURCES); do
        if [[ "$key" =~ ^${resource_key}: ]]; then
            aa_delete AWS_RESOURCES "$key"
        fi
    done
    
    # Remove from other tracking arrays
    for key in $(aa_keys RESOURCE_METADATA); do
        if [[ "$key" =~ ^${resource_key}: ]]; then
            aa_delete RESOURCE_METADATA "$key"
        fi
    done
    
    for key in $(aa_keys RESOURCE_MONITORING); do
        if [[ "$key" =~ ^${resource_key}: ]]; then
            aa_delete RESOURCE_MONITORING "$key"
        fi
    done
    
    for key in $(aa_keys RESOURCE_LIFECYCLE); do
        if [[ "$key" =~ ^${resource_key}: ]]; then
            aa_delete RESOURCE_LIFECYCLE "$key"
        fi
    done
    
    log "Removed resource from tracking: $resource_key"
}

# =============================================================================
# LIBRARY INITIALIZATION
# =============================================================================

# Initialize resource manager
init_resource_manager() {
    local stack_name="${1:-}"
    local auto_discover="${2:-false}"
    
    log "Initializing AWS Resource Manager (v${AWS_RESOURCE_MANAGER_VERSION})"
    
    # Set default lifecycle policies
    aa_set VALIDATION_RULES "max_resource_age_hours" "168"  # 1 week
    aa_set VALIDATION_RULES "max_inactive_hours" "24"      # 1 day
    aa_set VALIDATION_RULES "enable_auto_cleanup" "false"   # Disabled by default
    
    if [[ "$auto_discover" == "true" && -n "$stack_name" ]]; then
        log "Auto-discovering resources for stack: $stack_name"
        discover_all_resources "$stack_name"
    fi
    
    success "AWS Resource Manager initialized"
}

# Export all functions
export -f register_aws_resource update_resource_state record_resource_state_change
export -f discover_ec2_instances discover_load_balancers discover_all_resources
export -f monitor_resource_health check_ec2_instance_health check_alb_health
export -f set_resource_lifecycle_policy apply_lifecycle_policies evaluate_lifecycle_policy
export -f generate_resource_report get_resource_dependencies
export -f cleanup_stale_resources remove_resource_from_tracking init_resource_manager

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "AWS Resource Manager library loaded (v${AWS_RESOURCE_MANAGER_VERSION})"
fi