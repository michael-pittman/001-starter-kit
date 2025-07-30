#!/usr/bin/env bash
# =============================================================================
# Compute Launch Module
# Unified instance launch logic with spot/on-demand support
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_LAUNCH_SH_LOADED:-}" ] && return 0
_COMPUTE_LAUNCH_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/ami.sh"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# LAUNCH CONFIGURATION
# =============================================================================

# Build comprehensive launch configuration
build_launch_configuration() {
    local stack_name="$1"
    local instance_type="$2"
    local config_overrides="${3:-}"
    
    log_info "Building launch configuration for $instance_type" "LAUNCH"
    
    # Base configuration
    local config=$(cat <<EOF
{
    "stack_name": "$stack_name",
    "instance_type": "$instance_type",
    "key_name": "",
    "security_group_id": "",
    "subnet_id": "",
    "iam_instance_profile": "",
    "volume_size": $COMPUTE_DEFAULT_VOLUME_SIZE,
    "volume_type": "$COMPUTE_DEFAULT_VOLUME_TYPE",
    "encrypted": $COMPUTE_DEFAULT_ENCRYPTED,
    "delete_on_termination": $COMPUTE_DEFAULT_DELETE_ON_TERMINATION,
    "monitoring_enabled": true,
    "user_data": "",
    "tags": {}
}
EOF
)
    
    # Apply overrides if provided
    if [ -n "$config_overrides" ]; then
        config=$(echo "$config" | jq -s '.[0] * .[1]' - <(echo "$config_overrides"))
    fi
    
    # Get AMI for instance type
    local ami_id
    ami_id=$(get_ami_for_instance "$instance_type") || {
        log_error "Failed to get AMI for instance type: $instance_type" "LAUNCH"
        return 1
    }
    
    # Add AMI to config
    config=$(echo "$config" | jq --arg ami "$ami_id" '.ami_id = $ami')
    
    # Validate required fields
    local required_fields=("security_group_id" "subnet_id")
    for field in "${required_fields[@]}"; do
        local value
        value=$(echo "$config" | jq -r ".$field")
        if [ -z "$value" ] || [ "$value" = "null" ]; then
            # Try to get from variables
            local var_name=$(echo "$field" | tr '[:lower:]' '[:upper:]')
            value=$(get_variable "$var_name" || echo "")
            if [ -n "$value" ]; then
                config=$(echo "$config" | jq --arg field "$field" --arg value "$value" '.[$field] = $value')
            else
                log_error "Required field missing: $field" "LAUNCH"
                return 1
            fi
        fi
    done
    
    echo "$config"
}

# Build AWS CLI launch specification
build_launch_specification() {
    local config="$1"
    
    # Extract values from config
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local ami_id=$(echo "$config" | jq -r '.ami_id')
    local key_name=$(echo "$config" | jq -r '.key_name // empty')
    local security_group_id=$(echo "$config" | jq -r '.security_group_id')
    local subnet_id=$(echo "$config" | jq -r '.subnet_id')
    local iam_instance_profile=$(echo "$config" | jq -r '.iam_instance_profile // empty')
    local volume_size=$(echo "$config" | jq -r '.volume_size')
    local volume_type=$(echo "$config" | jq -r '.volume_type')
    local encrypted=$(echo "$config" | jq -r '.encrypted')
    local delete_on_termination=$(echo "$config" | jq -r '.delete_on_termination')
    local user_data=$(echo "$config" | jq -r '.user_data // empty')
    local stack_name=$(echo "$config" | jq -r '.stack_name')
    
    # Generate block device mapping
    local block_devices=$(generate_block_device_mapping "$volume_size" "$volume_type" "$encrypted" "$delete_on_termination")
    
    # Generate tags
    local tags=$(generate_compute_tags "$stack_name" "instance")
    local tag_spec_instance=$(tags_to_tag_spec "$tags" "instance")
    local tag_spec_volume=$(tags_to_tag_spec "$tags" "volume")
    
    # Generate metadata options
    local metadata_options=$(generate_metadata_options)
    
    # Build launch specification
    local launch_spec=$(cat <<EOF
{
    "ImageId": "$ami_id",
    "InstanceType": "$instance_type",
    "SubnetId": "$subnet_id",
    "SecurityGroupIds": ["$security_group_id"],
    "BlockDeviceMappings": $block_devices,
    "TagSpecifications": [$tag_spec_instance, $tag_spec_volume],
    "MetadataOptions": $metadata_options,
    "Monitoring": {"Enabled": true}
}
EOF
)
    
    # Add optional fields
    if [ -n "$key_name" ]; then
        launch_spec=$(echo "$launch_spec" | jq --arg key "$key_name" '.KeyName = $key')
    fi
    
    if [ -n "$iam_instance_profile" ]; then
        launch_spec=$(echo "$launch_spec" | jq --arg profile "$iam_instance_profile" '.IamInstanceProfile = {Name: $profile}')
    fi
    
    if [ -n "$user_data" ]; then
        # Base64 encode user data
        local encoded_user_data=$(echo "$user_data" | base64)
        launch_spec=$(echo "$launch_spec" | jq --arg data "$encoded_user_data" '.UserData = $data')
    fi
    
    echo "$launch_spec"
}

# =============================================================================
# INSTANCE LAUNCH FUNCTIONS
# =============================================================================

# Launch instance (spot or on-demand)
launch_instance() {
    local config="$1"
    local launch_type="${2:-auto}"  # auto, spot, ondemand
    
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local stack_name=$(echo "$config" | jq -r '.stack_name')
    
    log_info "Launching $launch_type instance: $instance_type for stack $stack_name" "LAUNCH"
    
    # Determine launch type
    if [ "$launch_type" = "auto" ]; then
        if is_gpu_instance "$instance_type"; then
            launch_type="spot"
            log_info "Auto-selected spot instance for GPU workload" "LAUNCH"
        else
            launch_type="ondemand"
            log_info "Auto-selected on-demand instance" "LAUNCH"
        fi
    fi
    
    # Launch based on type
    case "$launch_type" in
        spot)
            launch_spot_instance "$config"
            ;;
        ondemand)
            launch_ondemand_instance "$config"
            ;;
        *)
            log_error "Unknown launch type: $launch_type" "LAUNCH"
            return 1
            ;;
    esac
}

# Launch on-demand instance
launch_ondemand_instance() {
    local config="$1"
    
    local stack_name=$(echo "$config" | jq -r '.stack_name')
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    
    log_info "Launching on-demand instance" "LAUNCH"
    
    # Build launch specification
    local launch_spec
    launch_spec=$(build_launch_specification "$config") || return 1
    
    # Launch instance
    local result
    result=$(aws ec2 run-instances \
        --cli-input-json "$launch_spec" \
        --query '{InstanceId: Instances[0].InstanceId, State: Instances[0].State.Name}' \
        --output json 2>&1) || {
        
        local error_info=$(parse_aws_error "$result")
        local error_code=$(echo "$error_info" | cut -d':' -f1)
        
        case "$error_code" in
            "InsufficientInstanceCapacity")
                log_error "Insufficient capacity for $instance_type" "LAUNCH"
                error_ec2_insufficient_capacity "$instance_type" "$AWS_REGION"
                ;;
            "InstanceLimitExceeded")
                log_error "Instance limit exceeded" "LAUNCH"
                error_ec2_instance_limit_exceeded "$instance_type"
                ;;
            *)
                log_error "Failed to launch instance: $result" "LAUNCH"
                ;;
        esac
        return 1
    }
    
    local instance_id=$(echo "$result" | jq -r '.InstanceId')
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
        log_error "Failed to extract instance ID from result" "LAUNCH"
        return 1
    fi
    
    log_info "Instance launched: $instance_id" "LAUNCH"
    
    # Register instance
    register_resource "instances" "$instance_id" \
        "{\"type\": \"ondemand\", \"instance_type\": \"$instance_type\", \"stack\": \"$stack_name\"}"
    
    # Store instance ID
    set_variable "INSTANCE_ID" "$instance_id"
    
    echo "$instance_id"
}

# Launch spot instance
launch_spot_instance() {
    local config="$1"
    
    local stack_name=$(echo "$config" | jq -r '.stack_name')
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local max_price="${2:-}"
    
    log_info "Launching spot instance" "LAUNCH"
    
    # Get spot price if not provided
    if [ -z "$max_price" ]; then
        max_price=$(get_spot_price_recommendation "$instance_type") || {
            log_warn "Failed to get spot price, falling back to on-demand" "LAUNCH"
            launch_ondemand_instance "$config"
            return
        }
    fi
    
    log_info "Using max spot price: \$$max_price/hour" "LAUNCH"
    
    # Build launch specification
    local launch_spec
    launch_spec=$(build_launch_specification "$config") || return 1
    
    # Request spot instance
    local spot_result
    spot_result=$(aws ec2 request-spot-instances \
        --spot-price "$max_price" \
        --type "one-time" \
        --instance-interruption-behavior "terminate" \
        --launch-specification "$launch_spec" \
        --query 'SpotInstanceRequests[0].{RequestId: SpotInstanceRequestId, State: State}' \
        --output json 2>&1) || {
        
        log_error "Spot request failed: $spot_result" "LAUNCH"
        log_info "Falling back to on-demand instance" "LAUNCH"
        launch_ondemand_instance "$config"
        return
    }
    
    local request_id=$(echo "$spot_result" | jq -r '.RequestId')
    
    if [ -z "$request_id" ] || [ "$request_id" = "null" ]; then
        log_error "Failed to create spot request" "LAUNCH"
        launch_ondemand_instance "$config"
        return
    fi
    
    log_info "Spot request created: $request_id" "LAUNCH"
    
    # Register spot request
    register_resource "spot_requests" "$request_id" \
        "{\"stack\": \"$stack_name\", \"max_price\": \"$max_price\"}"
    
    # Wait for spot instance
    local instance_id
    instance_id=$(wait_for_spot_fulfillment "$request_id") || {
        log_error "Spot request not fulfilled" "LAUNCH"
        cancel_spot_request "$request_id"
        launch_ondemand_instance "$config"
        return
    }
    
    log_info "Spot instance launched: $instance_id" "LAUNCH"
    
    # Register instance
    register_resource "instances" "$instance_id" \
        "{\"type\": \"spot\", \"instance_type\": \"$instance_type\", \"stack\": \"$stack_name\", \"spot_request\": \"$request_id\"}"
    
    # Store instance ID
    set_variable "INSTANCE_ID" "$instance_id"
    
    echo "$instance_id"
}

# =============================================================================
# LAUNCH WITH RETRY AND FALLBACK
# =============================================================================

# Launch instance with retry logic
launch_instance_with_retry() {
    local config="$1"
    local launch_type="${2:-auto}"
    local max_retries="${3:-$COMPUTE_DEFAULT_MAX_RETRIES}"
    
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        log_info "Launch attempt $attempt/$max_retries" "LAUNCH"
        
        local instance_id
        instance_id=$(launch_instance "$config" "$launch_type" 2>&1) && {
            echo "$instance_id"
            return 0
        }
        
        # Check if we should retry
        if should_retry_error "EC2_INSUFFICIENT_CAPACITY" "$max_retries"; then
            local delay=$(calculate_backoff_delay "$attempt")
            log_info "Retrying in ${delay}s..." "LAUNCH"
            sleep "$delay"
        else
            break
        fi
        
        ((attempt++))
    done
    
    log_error "All launch attempts failed" "LAUNCH"
    return 1
}

# Launch instance with fallback options
launch_instance_with_fallback() {
    local config="$1"
    local launch_type="${2:-auto}"
    
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local stack_name=$(echo "$config" | jq -r '.stack_name')
    
    log_info "Launching instance with fallback options" "LAUNCH"
    
    # Try primary instance type
    local instance_id
    instance_id=$(launch_instance_with_retry "$config" "$launch_type") && {
        echo "$instance_id"
        return 0
    }
    
    # Try fallback instance types
    local fallback_types=$(get_instance_type_fallbacks "$instance_type")
    
    for fallback_type in $fallback_types; do
        log_info "Trying fallback instance type: $fallback_type" "LAUNCH"
        
        # Update config with fallback type
        local fallback_config
        fallback_config=$(echo "$config" | jq --arg type "$fallback_type" '.instance_type = $type')
        
        # Check availability
        if check_instance_type_availability "$fallback_type"; then
            instance_id=$(launch_instance_with_retry "$fallback_config" "$launch_type") && {
                log_info "Successfully launched with fallback type: $fallback_type" "LAUNCH"
                echo "$instance_id"
                return 0
            }
        fi
    done
    
    log_error "All fallback attempts failed" "LAUNCH"
    return 1
}

# =============================================================================
# SPOT INSTANCE HELPERS
# =============================================================================

# Get spot price recommendation
get_spot_price_recommendation() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    # Get current spot price
    local current_price
    current_price=$(aws ec2 describe-spot-price-history \
        --region "$region" \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-results 1 \
        --query 'SpotPriceHistory[0].SpotPrice' \
        --output text 2>/dev/null)
    
    if [ -z "$current_price" ] || [ "$current_price" = "None" ]; then
        log_error "No spot price available for $instance_type" "LAUNCH"
        return 1
    fi
    
    # Add 10% buffer to current price
    local recommended_price=$(echo "scale=4; $current_price * 1.1" | bc -l 2>/dev/null || echo "$current_price")
    
    log_info "Current spot price: \$$current_price, Recommended: \$$recommended_price" "LAUNCH"
    echo "$recommended_price"
}

# Wait for spot instance fulfillment
wait_for_spot_fulfillment() {
    local request_id="$1"
    local timeout="${2:-300}"  # 5 minutes default
    
    log_info "Waiting for spot instance fulfillment: $request_id" "LAUNCH"
    
    local start_time=$(date +%s)
    
    while true; do
        local state
        state=$(aws ec2 describe-spot-instance-requests \
            --spot-instance-request-ids "$request_id" \
            --query 'SpotInstanceRequests[0].State' \
            --output text 2>/dev/null)
        
        case "$state" in
            "active")
                # Get instance ID
                local instance_id
                instance_id=$(aws ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$request_id" \
                    --query 'SpotInstanceRequests[0].InstanceId' \
                    --output text)
                
                if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                    log_info "Spot instance fulfilled: $instance_id" "LAUNCH"
                    echo "$instance_id"
                    return 0
                fi
                ;;
            "failed"|"cancelled"|"closed")
                log_error "Spot request failed with state: $state" "LAUNCH"
                return 1
                ;;
        esac
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for spot fulfillment" "LAUNCH"
            return 1
        fi
        
        sleep 10
    done
}

# Cancel spot request
cancel_spot_request() {
    local request_id="$1"
    
    log_info "Cancelling spot request: $request_id" "LAUNCH"
    
    aws ec2 cancel-spot-instance-requests \
        --spot-instance-request-ids "$request_id" 2>/dev/null || true
    
    # Unregister request
    unregister_resource "spot_requests" "$request_id"
}

# =============================================================================
# LAUNCH TEMPLATES
# =============================================================================

# Create launch template
create_launch_template() {
    local stack_name="$1"
    local config="$2"
    local template_name="${3:-}"
    
    if [ -z "$template_name" ]; then
        template_name=$(generate_compute_resource_name "lt" "$stack_name")
    fi
    
    log_info "Creating launch template: $template_name" "LAUNCH"
    
    # Build launch specification
    local launch_spec
    launch_spec=$(build_launch_specification "$config") || return 1
    
    # Create launch template
    local template_result
    template_result=$(aws ec2 create-launch-template \
        --launch-template-name "$template_name" \
        --version-description "Created by GeuseMaker" \
        --launch-template-data "$launch_spec" \
        --query '{TemplateId: LaunchTemplate.LaunchTemplateId, Version: LaunchTemplate.LatestVersionNumber}' \
        --output json 2>&1) || {
        
        log_error "Failed to create launch template: $template_result" "LAUNCH"
        return 1
    }
    
    local template_id=$(echo "$template_result" | jq -r '.TemplateId')
    
    log_info "Launch template created: $template_id" "LAUNCH"
    
    # Register template
    register_resource "launch_templates" "$template_id" \
        "{\"name\": \"$template_name\", \"stack\": \"$stack_name\"}"
    
    # Store template ID
    set_variable "LAUNCH_TEMPLATE_ID" "$template_id"
    
    echo "$template_id"
}

# Launch instance from template
launch_from_template() {
    local template_id="$1"
    local overrides="${2:-}"
    
    log_info "Launching instance from template: $template_id" "LAUNCH"
    
    # Build run-instances command
    local launch_cmd="aws ec2 run-instances"
    launch_cmd="$launch_cmd --launch-template LaunchTemplateId=$template_id"
    
    # Add overrides if provided
    if [ -n "$overrides" ]; then
        # Parse overrides (e.g., instance type, subnet)
        local instance_type=$(echo "$overrides" | jq -r '.instance_type // empty')
        local subnet_id=$(echo "$overrides" | jq -r '.subnet_id // empty')
        
        [ -n "$instance_type" ] && launch_cmd="$launch_cmd --instance-type $instance_type"
        [ -n "$subnet_id" ] && launch_cmd="$launch_cmd --subnet-id $subnet_id"
    fi
    
    launch_cmd="$launch_cmd --query 'Instances[0].InstanceId' --output text"
    
    # Launch instance
    local instance_id
    instance_id=$(eval "$launch_cmd" 2>&1) || {
        log_error "Failed to launch from template: $instance_id" "LAUNCH"
        return 1
    }
    
    log_info "Instance launched from template: $instance_id" "LAUNCH"
    echo "$instance_id"
}

# =============================================================================
# BATCH LAUNCH OPERATIONS
# =============================================================================

# Launch multiple instances
launch_instances_batch() {
    local count="$1"
    local config="$2"
    local launch_type="${3:-auto}"
    
    log_info "Launching $count instances in batch" "LAUNCH"
    
    local instance_ids=()
    local success_count=0
    local failed_count=0
    
    for i in $(seq 1 "$count"); do
        log_info "Launching instance $i/$count" "LAUNCH"
        
        local instance_id
        instance_id=$(launch_instance "$config" "$launch_type" 2>&1) && {
            instance_ids+=("$instance_id")
            ((success_count++))
        } || {
            log_error "Failed to launch instance $i" "LAUNCH"
            ((failed_count++))
        }
        
        # Add small delay between launches
        [ $i -lt $count ] && sleep 2
    done
    
    log_info "Batch launch complete: $success_count succeeded, $failed_count failed" "LAUNCH"
    
    # Return instance IDs as JSON array
    printf '%s\n' "${instance_ids[@]}" | jq -R . | jq -s .
    
    [ $failed_count -eq 0 ]
}