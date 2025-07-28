#!/bin/bash
# =============================================================================
# Instance Launch Module
# Common instance launch patterns and lifecycle management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_LAUNCH_SH_LOADED:-}" ] && return 0
_LAUNCH_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../config/variables.sh"
source "${SCRIPT_DIR}/ami.sh"

# Initialize AWS_REGION if not set
if [ -z "${AWS_REGION:-}" ]; then
    AWS_REGION="$(get_variable AWS_REGION)"
    export AWS_REGION
fi

# =============================================================================
# LAUNCH CONFIGURATION
# =============================================================================

# Build launch configuration
build_launch_config() {
    local config_json="$1"
    
    # Extract configuration
    local instance_type=$(echo "$config_json" | jq -r '.instance_type // "g4dn.xlarge"')
    local key_name=$(echo "$config_json" | jq -r '.key_name // ""')
    local security_group_id=$(echo "$config_json" | jq -r '.security_group_id // ""')
    local subnet_id=$(echo "$config_json" | jq -r '.subnet_id // ""')
    local iam_instance_profile=$(echo "$config_json" | jq -r '.iam_instance_profile // ""')
    local volume_size=$(echo "$config_json" | jq -r '.volume_size // "100"')
    local user_data=$(echo "$config_json" | jq -r '.user_data // ""')
    local stack_name=$(echo "$config_json" | jq -r '.stack_name // "'$STACK_NAME'"')
    
    # Get AMI
    local ami_id
    ami_id=$(get_ami_for_instance "$instance_type") || return 1
    
    # Build block device mapping
    local block_devices=$(cat <<EOF
[
    {
        "DeviceName": "/dev/sda1",
        "Ebs": {
            "VolumeSize": $volume_size,
            "VolumeType": "gp3",
            "DeleteOnTermination": true,
            "Encrypted": true
        }
    }
]
EOF
)
    
    # Generate tags for both instance and volume
    local tags_json=$(generate_tags "$stack_name")
    local instance_tag_spec=$(tags_to_tag_spec "$tags_json" "instance")
    local volume_tag_spec=$(tags_to_tag_spec "$tags_json" "volume")
    
    # Build complete configuration
    cat <<EOF
{
    "ImageId": "$ami_id",
    "InstanceType": "$instance_type",
    "KeyName": "$key_name",
    "SecurityGroupIds": ["$security_group_id"],
    "SubnetId": "$subnet_id",
    "IamInstanceProfile": {
        "Name": "$iam_instance_profile"
    },
    "BlockDeviceMappings": $block_devices,
    "UserData": "$user_data",
    "TagSpecifications": [
        $instance_tag_spec,
        $volume_tag_spec
    ],
    "MetadataOptions": {
        "HttpEndpoint": "enabled",
        "HttpTokens": "required",
        "HttpPutResponseHopLimit": 2
    },
    "Monitoring": {
        "Enabled": true
    }
}
EOF
}

# =============================================================================
# INSTANCE LAUNCH
# =============================================================================

# Launch instance with configuration
launch_instance() {
    local launch_config="$1"
    local instance_type="${2:-ondemand}"  # ondemand or spot
    
    case "$instance_type" in
        ondemand)
            launch_ondemand_instance "$launch_config"
            ;;
        spot)
            launch_spot_instance "$launch_config"
            ;;
        *)
            throw_error $ERROR_INVALID_ARGUMENT "Unknown instance type: $instance_type"
            ;;
    esac
}

# Launch on-demand instance
launch_ondemand_instance() {
    local launch_config="$1"
    
    echo "Launching on-demand instance..." >&2
    
    with_error_context "launch_ondemand_instance" \
        _launch_ondemand_instance_impl "$launch_config"
}

_launch_ondemand_instance_impl() {
    local launch_config="$1"
    
    # Launch instance
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --cli-input-json "$launch_config" \
        --query 'Instances[0].InstanceId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to launch instance"
    }
    
    echo "Instance launched: $instance_id" >&2
    
    # Register instance
    register_resource "instances" "$instance_id" \
        "$(echo "$launch_config" | jq '{instance_type: .InstanceType, ami_id: .ImageId}')"
    
    # Wait for instance to be running
    wait_for_instance_state "$instance_id" "running"
    
    echo "$instance_id"
}

# Launch spot instance
launch_spot_instance() {
    local launch_config="$1"
    
    echo "Launching spot instance..." >&2
    
    with_error_context "launch_spot_instance" \
        _launch_spot_instance_impl "$launch_config"
}

_launch_spot_instance_impl() {
    local launch_config="$1"
    
    # Extract instance type for spot price check
    local instance_type=$(echo "$launch_config" | jq -r '.InstanceType')
    
    # Get current spot price
    local spot_price
    spot_price=$(get_spot_price "$instance_type") || {
        echo "Failed to get spot price, falling back to on-demand" >&2
        launch_ondemand_instance "$launch_config"
        return
    }
    
    # Create spot request specification
    local spot_spec=$(echo "$launch_config" | jq --arg price "$spot_price" '. + {
        SpotPrice: $price,
        Type: "one-time",
        InstanceInterruptionBehavior: "terminate"
    }')
    
    # Request spot instance
    local request_id
    request_id=$(aws ec2 request-spot-instances \
        --spot-price "$spot_price" \
        --launch-specification "$spot_spec" \
        --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
        --output text) || {
        echo "Spot request failed, falling back to on-demand" >&2
        launch_ondemand_instance "$launch_config"
        return
    }
    
    echo "Spot request created: $request_id" >&2
    
    # Register spot request
    register_resource "spot_requests" "$request_id"
    
    # Wait for spot instance
    local instance_id
    instance_id=$(wait_for_spot_instance "$request_id") || {
        echo "Spot instance failed, falling back to on-demand" >&2
        cancel_spot_request "$request_id"
        launch_ondemand_instance "$launch_config"
        return
    }
    
    # Register instance
    register_resource "instances" "$instance_id" \
        "$(echo "$launch_config" | jq '{instance_type: .InstanceType, ami_id: .ImageId, spot: true}')"
    
    echo "$instance_id"
}

# =============================================================================
# INSTANCE STATE MANAGEMENT
# =============================================================================

# Wait for instance state
wait_for_instance_state() {
    local instance_id="$1"
    local desired_state="$2"
    local timeout="${3:-300}"  # 5 minutes default
    
    echo "Waiting for instance $instance_id to reach $desired_state state..." >&2
    
    local start_time=$(date +%s)
    
    while true; do
        local current_state
        current_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null) || {
            throw_error $ERROR_AWS_API "Failed to describe instance"
        }
        
        if [ "$current_state" = "$desired_state" ]; then
            echo "Instance reached $desired_state state" >&2
            return 0
        fi
        
        if [[ "$current_state" =~ ^(terminated|terminating)$ ]]; then
            throw_error $ERROR_RESOURCE_NOT_FOUND "Instance terminated unexpectedly"
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            throw_error $ERROR_TIMEOUT "Timeout waiting for instance state"
        fi
        
        echo "Current state: $current_state, waiting..." >&2
        sleep 5
    done
}

# Get instance details
get_instance_details() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].{
            InstanceId: InstanceId,
            State: State.Name,
            PublicIpAddress: PublicIpAddress,
            PrivateIpAddress: PrivateIpAddress,
            InstanceType: InstanceType,
            ImageId: ImageId,
            LaunchTime: LaunchTime,
            SubnetId: SubnetId,
            VpcId: VpcId,
            SecurityGroups: SecurityGroups
        }' \
        --output json
}

# Get instance public IP
get_instance_public_ip() {
    local instance_id="$1"
    local public_ip
    
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || true)
    
    # Return empty if no IP found or if result is "None"
    if [ -z "$public_ip" ] || [ "$public_ip" = "None" ] || [ "$public_ip" = "null" ]; then
        return 0
    fi
    
    echo "$public_ip"
}

# =============================================================================
# SSH CONNECTION
# =============================================================================

# Wait for SSH to be ready
wait_for_ssh() {
    local instance_id="$1"
    local timeout="${2:-300}"  # 5 minutes default
    
    echo "Waiting for SSH to be ready on instance $instance_id..." >&2
    
    # Get instance IP
    local public_ip
    public_ip=$(get_instance_public_ip "$instance_id") || {
        throw_error $ERROR_RESOURCE_NOT_FOUND "No public IP for instance"
    }
    
    # Get key file
    local key_name=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].KeyName' \
        --output text)
    
    local key_file="$HOME/.ssh/${key_name}.pem"
    
    if [ ! -f "$key_file" ]; then
        echo "WARNING: SSH key not found: $key_file" >&2
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
               ubuntu@"$public_ip" \
               "echo 'SSH ready'" 2>/dev/null; then
            echo "SSH is ready on $public_ip" >&2
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            throw_error $ERROR_TIMEOUT "Timeout waiting for SSH"
        fi
        
        echo "SSH not ready yet, waiting..." >&2
        sleep 10
    done
}

# =============================================================================
# SPOT INSTANCE HELPERS
# =============================================================================

# Get spot price
get_spot_price() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    # Get current spot price
    local spot_price
    spot_price=$(aws ec2 describe-spot-price-history \
        --region "$region" \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-results 1 \
        --query 'SpotPriceHistory[0].SpotPrice' \
        --output text 2>/dev/null)
    
    if [ -z "$spot_price" ] || [ "$spot_price" = "None" ]; then
        echo "No spot price available for $instance_type" >&2
        return 1
    fi
    
    echo "$spot_price"
}

# Wait for spot instance
wait_for_spot_instance() {
    local request_id="$1"
    local timeout="${2:-300}"  # 5 minutes default
    
    echo "Waiting for spot instance from request $request_id..." >&2
    
    local start_time=$(date +%s)
    
    while true; do
        local status
        status=$(aws ec2 describe-spot-instance-requests \
            --spot-instance-request-ids "$request_id" \
            --query 'SpotInstanceRequests[0].Status.Code' \
            --output text 2>/dev/null)
        
        case "$status" in
            fulfilled)
                # Get instance ID
                local instance_id
                instance_id=$(aws ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$request_id" \
                    --query 'SpotInstanceRequests[0].InstanceId' \
                    --output text)
                
                echo "Spot instance fulfilled: $instance_id" >&2
                echo "$instance_id"
                return 0
                ;;
            failed|cancelled|closed)
                echo "Spot request failed with status: $status" >&2
                return 1
                ;;
        esac
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            echo "Timeout waiting for spot instance" >&2
            return 1
        fi
        
        echo "Current status: $status, waiting..." >&2
        sleep 10
    done
}

# Cancel spot request
cancel_spot_request() {
    local request_id="$1"
    
    echo "Cancelling spot request: $request_id" >&2
    
    aws ec2 cancel-spot-instance-requests \
        --spot-instance-request-ids "$request_id" || true
    
    # Unregister request
    unregister_resource "spot_requests" "$request_id"
}

# =============================================================================
# INSTANCE TERMINATION
# =============================================================================

# Terminate instance
terminate_instance() {
    local instance_id="$1"
    
    echo "Terminating instance: $instance_id" >&2
    
    aws ec2 terminate-instances \
        --instance-ids "$instance_id" || {
        echo "Failed to terminate instance: $instance_id" >&2
        return 1
    }
    
    # Unregister instance
    unregister_resource "instances" "$instance_id"
    
    # Wait for termination
    wait_for_instance_state "$instance_id" "terminated" || true
}