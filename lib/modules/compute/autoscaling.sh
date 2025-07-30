#!/usr/bin/env bash
# =============================================================================
# Compute Auto Scaling Module
# Auto Scaling Group and scaling policy management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_AUTOSCALING_SH_LOADED:-}" ] && return 0
_COMPUTE_AUTOSCALING_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/launch.sh"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# AUTO SCALING CONFIGURATION
# =============================================================================

# Auto Scaling defaults
readonly ASG_DEFAULT_MIN_SIZE=1
readonly ASG_DEFAULT_MAX_SIZE=3
readonly ASG_DEFAULT_DESIRED_CAPACITY=1
readonly ASG_DEFAULT_HEALTH_CHECK_TYPE="EC2"
readonly ASG_DEFAULT_HEALTH_CHECK_GRACE_PERIOD=300
readonly ASG_DEFAULT_DEFAULT_COOLDOWN=300
readonly ASG_DEFAULT_TERMINATION_POLICIES="OldestInstance"

# Scaling policy defaults
readonly SCALING_DEFAULT_METRIC_TYPE="ASGAverageCPUUtilization"
readonly SCALING_DEFAULT_TARGET_VALUE=70.0
readonly SCALING_DEFAULT_SCALE_IN_COOLDOWN=300
readonly SCALING_DEFAULT_SCALE_OUT_COOLDOWN=60

# =============================================================================
# AUTO SCALING GROUP CREATION
# =============================================================================

# Create Auto Scaling Group
create_auto_scaling_group() {
    local stack_name="$1"
    local launch_template_id="$2"
    local subnet_ids="$3"
    local config_overrides="${4:-}"
    
    log_info "Creating Auto Scaling Group for stack: $stack_name" "ASG"
    
    # Generate ASG name
    local asg_name=$(generate_compute_resource_name "asg" "$stack_name")
    
    # Base configuration
    local asg_config=$(cat <<EOF
{
    "AutoScalingGroupName": "$asg_name",
    "LaunchTemplate": {
        "LaunchTemplateId": "$launch_template_id",
        "Version": "\$Latest"
    },
    "MinSize": $ASG_DEFAULT_MIN_SIZE,
    "MaxSize": $ASG_DEFAULT_MAX_SIZE,
    "DesiredCapacity": $ASG_DEFAULT_DESIRED_CAPACITY,
    "HealthCheckType": "$ASG_DEFAULT_HEALTH_CHECK_TYPE",
    "HealthCheckGracePeriod": $ASG_DEFAULT_HEALTH_CHECK_GRACE_PERIOD,
    "DefaultCooldown": $ASG_DEFAULT_DEFAULT_COOLDOWN,
    "TerminationPolicies": ["$ASG_DEFAULT_TERMINATION_POLICIES"],
    "VPCZoneIdentifier": "$subnet_ids"
}
EOF
)
    
    # Apply overrides if provided
    if [ -n "$config_overrides" ]; then
        asg_config=$(echo "$asg_config" | jq -s '.[0] * .[1]' - <(echo "$config_overrides"))
    fi
    
    # Add tags
    local tags=$(generate_compute_tags "$stack_name" "auto-scaling-group")
    local asg_tags=()
    
    # Convert tags to ASG format
    echo "$tags" | jq -c '.[]' | while read -r tag; do
        local key=$(echo "$tag" | jq -r '.Key')
        local value=$(echo "$tag" | jq -r '.Value')
        asg_tags+=("{\"Key\": \"$key\", \"Value\": \"$value\", \"PropagateAtLaunch\": true}")
    done
    
    # Add tags to config
    if [ ${#asg_tags[@]} -gt 0 ]; then
        local tags_json="[$(IFS=,; echo "${asg_tags[*]}")]"
        asg_config=$(echo "$asg_config" | jq --argjson tags "$tags_json" '.Tags = $tags')
    fi
    
    # Create ASG
    local create_result
    create_result=$(aws autoscaling create-auto-scaling-group \
        --cli-input-json "$asg_config" 2>&1) || {
        
        log_error "Failed to create Auto Scaling Group: $create_result" "ASG"
        return 1
    }
    
    log_info "Auto Scaling Group created: $asg_name" "ASG"
    
    # Register ASG
    register_resource "auto_scaling_groups" "$asg_name" \
        "{\"launch_template\": \"$launch_template_id\", \"stack\": \"$stack_name\"}"
    
    # Store ASG name
    set_variable "AUTO_SCALING_GROUP_NAME" "$asg_name"
    
    echo "$asg_name"
}

# Create ASG with mixed instances policy
create_mixed_instances_asg() {
    local stack_name="$1"
    local launch_template_id="$2"
    local subnet_ids="$3"
    local instance_types="$4"  # Comma-separated list
    local spot_allocation_strategy="${5:-capacity-optimized}"
    local on_demand_percentage="${6:-20}"
    
    log_info "Creating mixed instances ASG with ${on_demand_percentage}% on-demand" "ASG"
    
    # Generate ASG name
    local asg_name=$(generate_compute_resource_name "asg-mixed" "$stack_name")
    
    # Build instance overrides
    local overrides=()
    IFS=',' read -ra types_array <<< "$instance_types"
    for instance_type in "${types_array[@]}"; do
        overrides+=("{\"InstanceType\": \"$instance_type\"}")
    done
    local overrides_json="[$(IFS=,; echo "${overrides[*]}")]"
    
    # Create mixed instances policy
    local mixed_policy=$(cat <<EOF
{
    "LaunchTemplate": {
        "LaunchTemplateSpecification": {
            "LaunchTemplateId": "$launch_template_id",
            "Version": "\$Latest"
        },
        "Overrides": $overrides_json
    },
    "InstancesDistribution": {
        "OnDemandAllocationStrategy": "prioritized",
        "OnDemandBaseCapacity": 0,
        "OnDemandPercentageAboveBaseCapacity": $on_demand_percentage,
        "SpotAllocationStrategy": "$spot_allocation_strategy"
    }
}
EOF
)
    
    # Create ASG with mixed instances
    local asg_config=$(cat <<EOF
{
    "AutoScalingGroupName": "$asg_name",
    "MixedInstancesPolicy": $mixed_policy,
    "MinSize": $ASG_DEFAULT_MIN_SIZE,
    "MaxSize": $ASG_DEFAULT_MAX_SIZE,
    "DesiredCapacity": $ASG_DEFAULT_DESIRED_CAPACITY,
    "HealthCheckType": "$ASG_DEFAULT_HEALTH_CHECK_TYPE",
    "HealthCheckGracePeriod": $ASG_DEFAULT_HEALTH_CHECK_GRACE_PERIOD,
    "VPCZoneIdentifier": "$subnet_ids"
}
EOF
)
    
    # Add tags
    local tags=$(generate_compute_tags "$stack_name" "auto-scaling-group")
    local asg_tags=()
    
    echo "$tags" | jq -c '.[]' | while read -r tag; do
        local key=$(echo "$tag" | jq -r '.Key')
        local value=$(echo "$tag" | jq -r '.Value')
        asg_tags+=("{\"Key\": \"$key\", \"Value\": \"$value\", \"PropagateAtLaunch\": true}")
    done
    
    if [ ${#asg_tags[@]} -gt 0 ]; then
        local tags_json="[$(IFS=,; echo "${asg_tags[*]}")]"
        asg_config=$(echo "$asg_config" | jq --argjson tags "$tags_json" '.Tags = $tags')
    fi
    
    # Create ASG
    local create_result
    create_result=$(aws autoscaling create-auto-scaling-group \
        --cli-input-json "$asg_config" 2>&1) || {
        
        log_error "Failed to create mixed instances ASG: $create_result" "ASG"
        return 1
    }
    
    log_info "Mixed instances ASG created: $asg_name" "ASG"
    
    # Register ASG
    register_resource "auto_scaling_groups" "$asg_name" \
        "{\"type\": \"mixed\", \"spot_percent\": $((100 - on_demand_percentage)), \"stack\": \"$stack_name\"}"
    
    echo "$asg_name"
}

# =============================================================================
# AUTO SCALING GROUP MANAGEMENT
# =============================================================================

# Update Auto Scaling Group
update_auto_scaling_group() {
    local asg_name="$1"
    local updates="$2"  # JSON object with updates
    
    log_info "Updating Auto Scaling Group: $asg_name" "ASG"
    
    # Build update command
    local update_cmd="aws autoscaling update-auto-scaling-group --auto-scaling-group-name $asg_name"
    
    # Parse updates
    local min_size=$(echo "$updates" | jq -r '.MinSize // empty')
    local max_size=$(echo "$updates" | jq -r '.MaxSize // empty')
    local desired_capacity=$(echo "$updates" | jq -r '.DesiredCapacity // empty')
    local health_check_type=$(echo "$updates" | jq -r '.HealthCheckType // empty')
    local health_check_grace=$(echo "$updates" | jq -r '.HealthCheckGracePeriod // empty')
    
    # Add parameters
    [ -n "$min_size" ] && update_cmd="$update_cmd --min-size $min_size"
    [ -n "$max_size" ] && update_cmd="$update_cmd --max-size $max_size"
    [ -n "$desired_capacity" ] && update_cmd="$update_cmd --desired-capacity $desired_capacity"
    [ -n "$health_check_type" ] && update_cmd="$update_cmd --health-check-type $health_check_type"
    [ -n "$health_check_grace" ] && update_cmd="$update_cmd --health-check-grace-period $health_check_grace"
    
    # Execute update
    eval "$update_cmd" 2>&1 || {
        log_error "Failed to update ASG" "ASG"
        return 1
    }
    
    log_info "ASG updated successfully" "ASG"
}

# Get ASG details
get_asg_details() {
    local asg_name="$1"
    
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0]' \
        --output json 2>/dev/null || echo "{}"
}

# Get ASG instances
get_asg_instances() {
    local asg_name="$1"
    
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0].Instances[].{
            InstanceId: InstanceId,
            LifecycleState: LifecycleState,
            HealthStatus: HealthStatus,
            AvailabilityZone: AvailabilityZone,
            InstanceType: InstanceType
        }' \
        --output json 2>/dev/null || echo "[]"
}

# Set ASG capacity
set_asg_capacity() {
    local asg_name="$1"
    local desired_capacity="$2"
    local honor_cooldown="${3:-true}"
    
    log_info "Setting ASG capacity to $desired_capacity" "ASG"
    
    local cmd="aws autoscaling set-desired-capacity"
    cmd="$cmd --auto-scaling-group-name $asg_name"
    cmd="$cmd --desired-capacity $desired_capacity"
    
    if [ "$honor_cooldown" = "true" ]; then
        cmd="$cmd --honor-cooldown"
    fi
    
    eval "$cmd" 2>&1 || {
        log_error "Failed to set ASG capacity" "ASG"
        return 1
    }
    
    log_info "ASG capacity set successfully" "ASG"
}

# =============================================================================
# SCALING POLICIES
# =============================================================================

# Create target tracking scaling policy
create_target_tracking_policy() {
    local asg_name="$1"
    local policy_name="${2:-cpu-target-tracking}"
    local target_value="${3:-$SCALING_DEFAULT_TARGET_VALUE}"
    local metric_type="${4:-$SCALING_DEFAULT_METRIC_TYPE}"
    
    log_info "Creating target tracking policy: $policy_name" "ASG"
    
    # Build policy configuration
    local policy_config=$(cat <<EOF
{
    "TargetValue": $target_value,
    "PredefinedMetricSpecification": {
        "PredefinedMetricType": "$metric_type"
    },
    "ScaleInCooldown": $SCALING_DEFAULT_SCALE_IN_COOLDOWN,
    "ScaleOutCooldown": $SCALING_DEFAULT_SCALE_OUT_COOLDOWN
}
EOF
)
    
    # Create policy
    local policy_arn
    policy_arn=$(aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "$asg_name" \
        --policy-name "$policy_name" \
        --policy-type "TargetTrackingScaling" \
        --target-tracking-configuration "$policy_config" \
        --query 'PolicyARN' \
        --output text 2>&1) || {
        
        log_error "Failed to create scaling policy" "ASG"
        return 1
    }
    
    log_info "Scaling policy created: $policy_arn" "ASG"
    echo "$policy_arn"
}

# Create step scaling policy
create_step_scaling_policy() {
    local asg_name="$1"
    local policy_name="$2"
    local metric_alarm_arn="$3"
    local adjustment_type="${4:-ChangeInCapacity}"
    local steps="$5"  # JSON array of step adjustments
    
    log_info "Creating step scaling policy: $policy_name" "ASG"
    
    # Build policy
    local policy_config=$(cat <<EOF
{
    "AdjustmentType": "$adjustment_type",
    "StepAdjustments": $steps,
    "MetricAggregationType": "Average"
}
EOF
)
    
    # Create policy
    local policy_arn
    policy_arn=$(aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "$asg_name" \
        --policy-name "$policy_name" \
        --policy-type "StepScaling" \
        --step-scaling-policy-configuration "$policy_config" \
        --query 'PolicyARN' \
        --output text 2>&1) || {
        
        log_error "Failed to create step scaling policy" "ASG"
        return 1
    }
    
    log_info "Step scaling policy created: $policy_arn" "ASG"
    echo "$policy_arn"
}

# Create predictive scaling policy
create_predictive_scaling_policy() {
    local asg_name="$1"
    local policy_name="${2:-predictive-scaling}"
    local mode="${3:-ForecastAndScale}"  # ForecastOnly or ForecastAndScale
    
    log_info "Creating predictive scaling policy: $policy_name" "ASG"
    
    # Build metric specifications
    local metric_specs=$(cat <<EOF
[
    {
        "TargetValue": $SCALING_DEFAULT_TARGET_VALUE,
        "PredefinedMetricPairSpecification": {
            "PredefinedMetricType": "ASGCPUUtilization"
        }
    }
]
EOF
)
    
    # Create policy
    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "$asg_name" \
        --policy-name "$policy_name" \
        --policy-type "PredictiveScaling" \
        --predictive-scaling-configuration "{
            \"MetricSpecifications\": $metric_specs,
            \"Mode\": \"$mode\"
        }" 2>&1 || {
        
        log_error "Failed to create predictive scaling policy" "ASG"
        return 1
    }
    
    log_info "Predictive scaling policy created" "ASG"
}

# =============================================================================
# LIFECYCLE HOOKS
# =============================================================================

# Create lifecycle hook
create_lifecycle_hook() {
    local asg_name="$1"
    local hook_name="$2"
    local lifecycle_transition="$3"  # autoscaling:EC2_INSTANCE_LAUNCHING or TERMINATING
    local notification_target_arn="${4:-}"
    local role_arn="${5:-}"
    local heartbeat_timeout="${6:-300}"
    
    log_info "Creating lifecycle hook: $hook_name" "ASG"
    
    local cmd="aws autoscaling put-lifecycle-hook"
    cmd="$cmd --auto-scaling-group-name $asg_name"
    cmd="$cmd --lifecycle-hook-name $hook_name"
    cmd="$cmd --lifecycle-transition $lifecycle_transition"
    cmd="$cmd --heartbeat-timeout $heartbeat_timeout"
    cmd="$cmd --default-result CONTINUE"
    
    if [ -n "$notification_target_arn" ] && [ -n "$role_arn" ]; then
        cmd="$cmd --notification-target-arn $notification_target_arn"
        cmd="$cmd --role-arn $role_arn"
    fi
    
    eval "$cmd" 2>&1 || {
        log_error "Failed to create lifecycle hook" "ASG"
        return 1
    }
    
    log_info "Lifecycle hook created" "ASG"
}

# Complete lifecycle action
complete_lifecycle_action() {
    local asg_name="$1"
    local hook_name="$2"
    local lifecycle_token="$3"
    local result="${4:-CONTINUE}"  # CONTINUE or ABANDON
    
    log_info "Completing lifecycle action: $hook_name" "ASG"
    
    aws autoscaling complete-lifecycle-action \
        --auto-scaling-group-name "$asg_name" \
        --lifecycle-hook-name "$hook_name" \
        --lifecycle-action-token "$lifecycle_token" \
        --lifecycle-action-result "$result" 2>&1 || {
        
        log_error "Failed to complete lifecycle action" "ASG"
        return 1
    }
    
    log_info "Lifecycle action completed with result: $result" "ASG"
}

# =============================================================================
# SCHEDULED ACTIONS
# =============================================================================

# Create scheduled action
create_scheduled_action() {
    local asg_name="$1"
    local action_name="$2"
    local recurrence="$3"  # Cron expression
    local min_size="${4:-}"
    local max_size="${5:-}"
    local desired_capacity="${6:-}"
    
    log_info "Creating scheduled action: $action_name" "ASG"
    
    local cmd="aws autoscaling put-scheduled-update-group-action"
    cmd="$cmd --auto-scaling-group-name $asg_name"
    cmd="$cmd --scheduled-action-name $action_name"
    cmd="$cmd --recurrence '$recurrence'"
    
    [ -n "$min_size" ] && cmd="$cmd --min-size $min_size"
    [ -n "$max_size" ] && cmd="$cmd --max-size $max_size"
    [ -n "$desired_capacity" ] && cmd="$cmd --desired-capacity $desired_capacity"
    
    eval "$cmd" 2>&1 || {
        log_error "Failed to create scheduled action" "ASG"
        return 1
    }
    
    log_info "Scheduled action created" "ASG"
}

# =============================================================================
# WARM POOLS
# =============================================================================

# Create warm pool
create_warm_pool() {
    local asg_name="$1"
    local min_size="${2:-0}"
    local max_capacity="${3:-}"
    local instance_reuse_policy="${4:-}"
    
    log_info "Creating warm pool for ASG: $asg_name" "ASG"
    
    local warm_pool_config="{\"MinSize\": $min_size}"
    
    if [ -n "$max_capacity" ]; then
        warm_pool_config=$(echo "$warm_pool_config" | jq --arg max "$max_capacity" '. + {MaxGroupPreparedCapacity: ($max | tonumber)}')
    fi
    
    if [ -n "$instance_reuse_policy" ]; then
        warm_pool_config=$(echo "$warm_pool_config" | jq --argjson policy "$instance_reuse_policy" '. + {InstanceReusePolicy: $policy}')
    fi
    
    aws autoscaling put-warm-pool \
        --auto-scaling-group-name "$asg_name" \
        --cli-input-json "$warm_pool_config" 2>&1 || {
        
        log_error "Failed to create warm pool" "ASG"
        return 1
    }
    
    log_info "Warm pool created" "ASG"
}

# =============================================================================
# MONITORING AND HEALTH
# =============================================================================

# Get ASG metrics
get_asg_metrics() {
    local asg_name="$1"
    local metric_name="$2"
    local start_time="${3:-$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)}"
    local end_time="${4:-$(date -u +%Y-%m-%dT%H:%M:%S)}"
    
    aws cloudwatch get-metric-statistics \
        --namespace "AWS/AutoScaling" \
        --metric-name "$metric_name" \
        --dimensions Name=AutoScalingGroupName,Value="$asg_name" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average,Maximum,Minimum \
        --output json 2>/dev/null || echo "{}"
}

# Check ASG health
check_asg_health() {
    local asg_name="$1"
    
    log_info "Checking health of ASG: $asg_name" "ASG"
    
    local asg_details=$(get_asg_details "$asg_name")
    
    if [ -z "$asg_details" ] || [ "$asg_details" = "{}" ]; then
        log_error "ASG not found: $asg_name" "ASG"
        return 1
    fi
    
    # Check instance health
    local instances=$(echo "$asg_details" | jq -r '.Instances[]')
    local unhealthy_count=0
    
    echo "$instances" | jq -c '.' | while read -r instance; do
        local health_status=$(echo "$instance" | jq -r '.HealthStatus')
        local lifecycle_state=$(echo "$instance" | jq -r '.LifecycleState')
        
        if [ "$health_status" != "Healthy" ] || [ "$lifecycle_state" != "InService" ]; then
            ((unhealthy_count++))
            local instance_id=$(echo "$instance" | jq -r '.InstanceId')
            log_warn "Unhealthy instance: $instance_id (health: $health_status, state: $lifecycle_state)" "ASG"
        fi
    done
    
    # Check capacity
    local min_size=$(echo "$asg_details" | jq -r '.MinSize')
    local max_size=$(echo "$asg_details" | jq -r '.MaxSize')
    local desired_capacity=$(echo "$asg_details" | jq -r '.DesiredCapacity')
    local current_size=$(echo "$asg_details" | jq -r '.Instances | length')
    
    log_info "ASG capacity - Min: $min_size, Max: $max_size, Desired: $desired_capacity, Current: $current_size" "ASG"
    
    if [ $current_size -lt $min_size ]; then
        log_error "ASG below minimum capacity" "ASG"
        return 1
    fi
    
    if [ $unhealthy_count -gt 0 ]; then
        log_warn "ASG has $unhealthy_count unhealthy instances" "ASG"
        return 1
    fi
    
    log_info "ASG health check passed" "ASG"
    return 0
}

# =============================================================================
# CLEANUP
# =============================================================================

# Delete Auto Scaling Group
delete_auto_scaling_group() {
    local asg_name="$1"
    local force_delete="${2:-true}"
    
    log_info "Deleting Auto Scaling Group: $asg_name" "ASG"
    
    local cmd="aws autoscaling delete-auto-scaling-group"
    cmd="$cmd --auto-scaling-group-name $asg_name"
    
    if [ "$force_delete" = "true" ]; then
        cmd="$cmd --force-delete"
    fi
    
    eval "$cmd" 2>&1 || {
        log_error "Failed to delete ASG" "ASG"
        return 1
    }
    
    # Unregister ASG
    unregister_resource "auto_scaling_groups" "$asg_name"
    
    log_info "ASG deleted successfully" "ASG"
}

# Delete all ASGs for stack
delete_stack_asgs() {
    local stack_name="$1"
    
    log_info "Deleting all ASGs for stack: $stack_name" "ASG"
    
    # Find ASGs with stack tag
    local asgs
    asgs=$(aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[?Tags[?Key=='Stack' && Value=='$stack_name']].AutoScalingGroupName" \
        --output text 2>/dev/null)
    
    if [ -z "$asgs" ]; then
        log_info "No ASGs found for stack" "ASG"
        return 0
    fi
    
    # Delete each ASG
    for asg in $asgs; do
        delete_auto_scaling_group "$asg" true || {
            log_error "Failed to delete ASG: $asg" "ASG"
        }
    done
    
    log_info "Stack ASGs deleted" "ASG"
}