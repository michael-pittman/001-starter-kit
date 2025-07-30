#!/usr/bin/env bash
# =============================================================================
# Compute Lifecycle Module
# Instance state management, monitoring, and lifecycle operations
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_LIFECYCLE_SH_LOADED:-}" ] && return 0
_COMPUTE_LIFECYCLE_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# INSTANCE STATE CONSTANTS
# =============================================================================

# Instance states
readonly INSTANCE_STATE_PENDING="pending"
readonly INSTANCE_STATE_RUNNING="running"
readonly INSTANCE_STATE_SHUTTING_DOWN="shutting-down"
readonly INSTANCE_STATE_TERMINATED="terminated"
readonly INSTANCE_STATE_STOPPING="stopping"
readonly INSTANCE_STATE_STOPPED="stopped"

# Instance status checks
readonly INSTANCE_STATUS_OK="ok"
readonly INSTANCE_STATUS_IMPAIRED="impaired"
readonly INSTANCE_STATUS_INSUFFICIENT_DATA="insufficient-data"
readonly INSTANCE_STATUS_NOT_APPLICABLE="not-applicable"

# =============================================================================
# INSTANCE STATE MANAGEMENT
# =============================================================================

# Get instance state
get_instance_state() {
    local instance_id="$1"
    local region="${2:-$AWS_REGION}"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown"
}

# Wait for instance state
wait_for_instance_state() {
    local instance_id="$1"
    local desired_state="$2"
    local timeout="${3:-300}"  # 5 minutes default
    
    log_info "Waiting for instance $instance_id to reach $desired_state state" "LIFECYCLE"
    
    local start_time=$(date +%s)
    
    while true; do
        local current_state=$(get_instance_state "$instance_id")
        
        if [ "$current_state" = "$desired_state" ]; then
            log_info "Instance reached $desired_state state" "LIFECYCLE"
            return 0
        fi
        
        # Check for terminal states
        case "$current_state" in
            "terminated")
                if [ "$desired_state" != "terminated" ]; then
                    log_error "Instance terminated unexpectedly" "LIFECYCLE"
                    return 1
                fi
                ;;
            "failed")
                log_error "Instance in failed state" "LIFECYCLE"
                return 1
                ;;
        esac
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for state: $desired_state (current: $current_state)" "LIFECYCLE"
            return 1
        fi
        
        log_debug "Current state: $current_state, waiting..." "LIFECYCLE"
        sleep 5
    done
}

# Wait for multiple instance states
wait_for_instances_state() {
    local desired_state="$1"
    local timeout="${2:-300}"
    shift 2
    local instance_ids=("$@")
    
    log_info "Waiting for ${#instance_ids[@]} instances to reach $desired_state state" "LIFECYCLE"
    
    local all_ready=false
    local start_time=$(date +%s)
    
    while [ "$all_ready" = "false" ]; do
        all_ready=true
        
        for instance_id in "${instance_ids[@]}"; do
            local state=$(get_instance_state "$instance_id")
            
            if [ "$state" != "$desired_state" ]; then
                all_ready=false
                log_debug "Instance $instance_id state: $state" "LIFECYCLE"
            fi
        done
        
        if [ "$all_ready" = "true" ]; then
            log_info "All instances reached $desired_state state" "LIFECYCLE"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for instances" "LIFECYCLE"
            return 1
        fi
        
        sleep 5
    done
}

# =============================================================================
# INSTANCE STATUS CHECKS
# =============================================================================

# Get instance status
get_instance_status() {
    local instance_id="$1"
    local region="${2:-$AWS_REGION}"
    
    aws ec2 describe-instance-status \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'InstanceStatuses[0].{
            InstanceStatus: InstanceStatus.Status,
            SystemStatus: SystemStatus.Status,
            InstanceState: InstanceState.Name
        }' \
        --output json 2>/dev/null || echo "{}"
}

# Wait for instance status checks
wait_for_instance_status_ok() {
    local instance_id="$1"
    local timeout="${2:-600}"  # 10 minutes default
    
    log_info "Waiting for instance $instance_id status checks" "LIFECYCLE"
    
    # First wait for running state
    wait_for_instance_state "$instance_id" "$INSTANCE_STATE_RUNNING" "$timeout" || return 1
    
    local start_time=$(date +%s)
    
    while true; do
        local status_json=$(get_instance_status "$instance_id")
        local instance_status=$(echo "$status_json" | jq -r '.InstanceStatus // "unknown"')
        local system_status=$(echo "$status_json" | jq -r '.SystemStatus // "unknown"')
        
        if [ "$instance_status" = "$INSTANCE_STATUS_OK" ] && [ "$system_status" = "$INSTANCE_STATUS_OK" ]; then
            log_info "Instance status checks passed" "LIFECYCLE"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for status checks (instance: $instance_status, system: $system_status)" "LIFECYCLE"
            return 1
        fi
        
        log_debug "Status checks - Instance: $instance_status, System: $system_status" "LIFECYCLE"
        sleep 15
    done
}

# =============================================================================
# INSTANCE INFORMATION
# =============================================================================

# Get instance details
get_instance_details() {
    local instance_id="$1"
    local region="${2:-$AWS_REGION}"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].{
            InstanceId: InstanceId,
            InstanceType: InstanceType,
            State: State.Name,
            StateReason: StateReason.Message,
            PublicIpAddress: PublicIpAddress,
            PrivateIpAddress: PrivateIpAddress,
            PublicDnsName: PublicDnsName,
            PrivateDnsName: PrivateDnsName,
            SubnetId: SubnetId,
            VpcId: VpcId,
            SecurityGroups: SecurityGroups,
            KeyName: KeyName,
            LaunchTime: LaunchTime,
            Platform: Platform,
            Architecture: Architecture,
            RootDeviceType: RootDeviceType,
            Tags: Tags
        }' \
        --output json 2>/dev/null || echo "{}"
}

# Get instance metadata
get_instance_metadata() {
    local instance_id="$1"
    local metadata_path="${2:-}"
    
    # This function should be called from within the instance
    # For external use, use get_instance_details instead
    
    local base_url="http://169.254.169.254/latest/meta-data"
    
    if [ -n "$metadata_path" ]; then
        curl -s --fail "$base_url/$metadata_path" 2>/dev/null || echo ""
    else
        # Get common metadata
        cat <<EOF
{
    "instance-id": "$(curl -s "$base_url/instance-id" 2>/dev/null || echo "")",
    "instance-type": "$(curl -s "$base_url/instance-type" 2>/dev/null || echo "")",
    "ami-id": "$(curl -s "$base_url/ami-id" 2>/dev/null || echo "")",
    "hostname": "$(curl -s "$base_url/hostname" 2>/dev/null || echo "")",
    "local-ipv4": "$(curl -s "$base_url/local-ipv4" 2>/dev/null || echo "")",
    "public-ipv4": "$(curl -s "$base_url/public-ipv4" 2>/dev/null || echo "")",
    "availability-zone": "$(curl -s "$base_url/placement/availability-zone" 2>/dev/null || echo "")"
}
EOF
    fi
}

# Get instance public IP
get_instance_public_ip() {
    local instance_id="$1"
    local region="${2:-$AWS_REGION}"
    
    local public_ip
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null)
    
    if [ -n "$public_ip" ] && [ "$public_ip" != "None" ] && [ "$public_ip" != "null" ]; then
        echo "$public_ip"
    fi
}

# Get instance private IP
get_instance_private_ip() {
    local instance_id="$1"
    local region="${2:-$AWS_REGION}"
    
    local private_ip
    private_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text 2>/dev/null)
    
    if [ -n "$private_ip" ] && [ "$private_ip" != "None" ] && [ "$private_ip" != "null" ]; then
        echo "$private_ip"
    fi
}

# =============================================================================
# INSTANCE LIFECYCLE OPERATIONS
# =============================================================================

# Start instance
start_instance() {
    local instance_id="$1"
    local wait="${2:-true}"
    
    log_info "Starting instance: $instance_id" "LIFECYCLE"
    
    aws ec2 start-instances \
        --instance-ids "$instance_id" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to start instance" "LIFECYCLE"
        return 1
    }
    
    if [ "$wait" = "true" ]; then
        wait_for_instance_state "$instance_id" "$INSTANCE_STATE_RUNNING"
    fi
}

# Stop instance
stop_instance() {
    local instance_id="$1"
    local force="${2:-false}"
    local wait="${3:-true}"
    
    log_info "Stopping instance: $instance_id (force=$force)" "LIFECYCLE"
    
    if [ "$force" = "true" ]; then
        aws ec2 stop-instances \
            --instance-ids "$instance_id" \
            --force \
            --output json >/dev/null 2>&1 || {
            log_error "Failed to force stop instance" "LIFECYCLE"
            return 1
        }
    else
        aws ec2 stop-instances \
            --instance-ids "$instance_id" \
            --output json >/dev/null 2>&1 || {
            log_error "Failed to stop instance" "LIFECYCLE"
            return 1
        }
    fi
    
    if [ "$wait" = "true" ]; then
        wait_for_instance_state "$instance_id" "$INSTANCE_STATE_STOPPED"
    fi
}

# Reboot instance
reboot_instance() {
    local instance_id="$1"
    
    log_info "Rebooting instance: $instance_id" "LIFECYCLE"
    
    aws ec2 reboot-instances \
        --instance-ids "$instance_id" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to reboot instance" "LIFECYCLE"
        return 1
    }
    
    # Wait a bit for reboot to initiate
    sleep 10
    
    # Wait for instance to be running again
    wait_for_instance_state "$instance_id" "$INSTANCE_STATE_RUNNING"
}

# Terminate instance
terminate_instance() {
    local instance_id="$1"
    local wait="${2:-true}"
    
    log_info "Terminating instance: $instance_id" "LIFECYCLE"
    
    aws ec2 terminate-instances \
        --instance-ids "$instance_id" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to terminate instance" "LIFECYCLE"
        return 1
    }
    
    # Unregister instance from resource registry
    unregister_resource "instances" "$instance_id"
    
    if [ "$wait" = "true" ]; then
        wait_for_instance_state "$instance_id" "$INSTANCE_STATE_TERMINATED"
    fi
}

# Terminate multiple instances
terminate_instances_batch() {
    local instance_ids=("$@")
    
    if [ ${#instance_ids[@]} -eq 0 ]; then
        log_warn "No instances to terminate" "LIFECYCLE"
        return 0
    fi
    
    log_info "Terminating ${#instance_ids[@]} instances" "LIFECYCLE"
    
    aws ec2 terminate-instances \
        --instance-ids "${instance_ids[@]}" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to terminate instances" "LIFECYCLE"
        return 1
    }
    
    # Unregister all instances
    for instance_id in "${instance_ids[@]}"; do
        unregister_resource "instances" "$instance_id"
    done
    
    # Wait for all to terminate
    wait_for_instances_state "$INSTANCE_STATE_TERMINATED" 600 "${instance_ids[@]}"
}

# =============================================================================
# SSH CONNECTION MANAGEMENT
# =============================================================================

# Wait for SSH to be ready
wait_for_ssh_ready() {
    local instance_id="$1"
    local timeout="${2:-300}"  # 5 minutes default
    local ssh_user="${3:-ubuntu}"
    local ssh_port="${4:-22}"
    
    log_info "Waiting for SSH to be ready on instance $instance_id" "LIFECYCLE"
    
    # Get instance IP
    local public_ip
    public_ip=$(get_instance_public_ip "$instance_id")
    
    if [ -z "$public_ip" ]; then
        log_error "Instance has no public IP address" "LIFECYCLE"
        return 1
    fi
    
    # Get SSH key
    local instance_details=$(get_instance_details "$instance_id")
    local key_name=$(echo "$instance_details" | jq -r '.KeyName // empty')
    
    if [ -z "$key_name" ]; then
        log_warn "No SSH key associated with instance" "LIFECYCLE"
        return 1
    fi
    
    local key_file="$HOME/.ssh/${key_name}.pem"
    if [ ! -f "$key_file" ]; then
        log_error "SSH key not found: $key_file" "LIFECYCLE"
        return 1
    fi
    
    # Wait for SSH
    local start_time=$(date +%s)
    
    while true; do
        if ssh -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o LogLevel=ERROR \
               -i "$key_file" \
               -p "$ssh_port" \
               "${ssh_user}@${public_ip}" \
               "echo 'SSH ready'" 2>/dev/null; then
            log_info "SSH is ready on $public_ip" "LIFECYCLE"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for SSH" "LIFECYCLE"
            return 1
        fi
        
        log_debug "SSH not ready yet, waiting..." "LIFECYCLE"
        sleep 10
    done
}

# Get SSH connection command
get_ssh_command() {
    local instance_id="$1"
    local ssh_user="${2:-ubuntu}"
    local ssh_port="${3:-22}"
    
    # Get instance details
    local instance_details=$(get_instance_details "$instance_id")
    local public_ip=$(echo "$instance_details" | jq -r '.PublicIpAddress // empty')
    local key_name=$(echo "$instance_details" | jq -r '.KeyName // empty')
    
    if [ -z "$public_ip" ]; then
        log_error "Instance has no public IP" "LIFECYCLE"
        return 1
    fi
    
    if [ -z "$key_name" ]; then
        log_error "Instance has no SSH key" "LIFECYCLE"
        return 1
    fi
    
    local key_file="$HOME/.ssh/${key_name}.pem"
    
    echo "ssh -i \"$key_file\" -p $ssh_port ${ssh_user}@${public_ip}"
}

# =============================================================================
# INSTANCE MONITORING
# =============================================================================

# Monitor instance metrics
get_instance_metrics() {
    local instance_id="$1"
    local metric_name="$2"
    local start_time="${3:-$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)}"
    local end_time="${4:-$(date -u +%Y-%m-%dT%H:%M:%S)}"
    local period="${5:-300}"  # 5 minutes
    
    aws cloudwatch get-metric-statistics \
        --namespace "AWS/EC2" \
        --metric-name "$metric_name" \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period "$period" \
        --statistics Average,Maximum \
        --output json 2>/dev/null || echo "{}"
}

# Get instance CPU utilization
get_instance_cpu_utilization() {
    local instance_id="$1"
    
    local metrics=$(get_instance_metrics "$instance_id" "CPUUtilization")
    
    # Extract latest average
    echo "$metrics" | jq -r '
        .Datapoints 
        | sort_by(.Timestamp) 
        | reverse 
        | .[0].Average // 0'
}

# Check instance health
check_instance_health() {
    local instance_id="$1"
    
    log_info "Checking health of instance: $instance_id" "LIFECYCLE"
    
    # Get instance state
    local state=$(get_instance_state "$instance_id")
    if [ "$state" != "$INSTANCE_STATE_RUNNING" ]; then
        log_warn "Instance not in running state: $state" "LIFECYCLE"
        return 1
    fi
    
    # Get status checks
    local status_json=$(get_instance_status "$instance_id")
    local instance_status=$(echo "$status_json" | jq -r '.InstanceStatus // "unknown"')
    local system_status=$(echo "$status_json" | jq -r '.SystemStatus // "unknown"')
    
    if [ "$instance_status" != "$INSTANCE_STATUS_OK" ] || [ "$system_status" != "$INSTANCE_STATUS_OK" ]; then
        log_warn "Instance status checks failing - Instance: $instance_status, System: $system_status" "LIFECYCLE"
        return 1
    fi
    
    # Check CPU utilization
    local cpu_util=$(get_instance_cpu_utilization "$instance_id")
    if (( $(echo "$cpu_util > 90" | bc -l 2>/dev/null || echo 0) )); then
        log_warn "High CPU utilization: ${cpu_util}%" "LIFECYCLE"
    fi
    
    log_info "Instance health check passed" "LIFECYCLE"
    return 0
}

# =============================================================================
# INSTANCE TAGS
# =============================================================================

# Add tags to instance
add_instance_tags() {
    local instance_id="$1"
    shift
    local tags=("$@")
    
    if [ ${#tags[@]} -eq 0 ]; then
        log_warn "No tags provided" "LIFECYCLE"
        return 0
    fi
    
    log_info "Adding ${#tags[@]} tags to instance $instance_id" "LIFECYCLE"
    
    # Format tags for AWS CLI
    local tag_specs=()
    for tag in "${tags[@]}"; do
        if [[ "$tag" =~ ^([^=]+)=(.+)$ ]]; then
            tag_specs+=("Key=${BASH_REMATCH[1]},Value=${BASH_REMATCH[2]}")
        fi
    done
    
    aws ec2 create-tags \
        --resources "$instance_id" \
        --tags "${tag_specs[@]}" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to add tags" "LIFECYCLE"
        return 1
    }
    
    log_info "Tags added successfully" "LIFECYCLE"
}

# Get instance tags
get_instance_tags() {
    local instance_id="$1"
    
    aws ec2 describe-tags \
        --filters "Name=resource-id,Values=$instance_id" \
        --query 'Tags[].{Key: Key, Value: Value}' \
        --output json 2>/dev/null || echo "[]"
}

# Remove instance tags
remove_instance_tags() {
    local instance_id="$1"
    shift
    local tag_keys=("$@")
    
    if [ ${#tag_keys[@]} -eq 0 ]; then
        log_warn "No tag keys provided" "LIFECYCLE"
        return 0
    fi
    
    log_info "Removing ${#tag_keys[@]} tags from instance $instance_id" "LIFECYCLE"
    
    # Format tags for AWS CLI
    local tag_specs=()
    for key in "${tag_keys[@]}"; do
        tag_specs+=("Key=$key")
    done
    
    aws ec2 delete-tags \
        --resources "$instance_id" \
        --tags "${tag_specs[@]}" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to remove tags" "LIFECYCLE"
        return 1
    }
    
    log_info "Tags removed successfully" "LIFECYCLE"
}