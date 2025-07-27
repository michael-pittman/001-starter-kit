#!/bin/bash
# =============================================================================
# Spot Instance Optimization Module  
# Handles spot pricing analysis, instance selection, and cost optimization
# =============================================================================

# Prevent multiple sourcing
[ -n "${_SPOT_OPTIMIZER_SH_LOADED:-}" ] && return 0
_SPOT_OPTIMIZER_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# SPOT PRICING ANALYSIS (MIGRATED FROM MONOLITH)
# =============================================================================

# Analyze spot pricing across availability zones
analyze_spot_pricing() {
    local instance_type="$1"
    local region="${2:-${AWS_REGION:-us-east-1}}"
    local availability_zones=("${@:3}")
    
    if [ -z "$instance_type" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "analyze_spot_pricing requires instance_type parameter"
    fi

    echo "Analyzing spot pricing for $instance_type in $region..." >&2

    # Get all AZs if none specified
    if [ ${#availability_zones[@]} -eq 0 ]; then
        # Use compatible method instead of mapfile for bash 3.2
        local az_output
        az_output=$(aws ec2 describe-availability-zones \
            --region "$region" \
            --query 'AvailabilityZones[].ZoneName' \
            --output text | tr '\t' ' ')
        read -ra availability_zones <<< "$az_output"
    fi

    local best_az=""
    local best_price=""
    local current_prices=()

    # Check pricing in each AZ
    for az in "${availability_zones[@]+"${availability_zones[@]}"}"; do
        local price_info
        price_info=$(aws ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --availability-zone "$az" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "$region" \
            --query 'SpotPriceHistory[0].[AvailabilityZone,SpotPrice,Timestamp]' \
            --output text 2>/dev/null)

        if [ -n "$price_info" ]; then
            local current_price
            current_price=$(echo "$price_info" | cut -f2)
            current_prices+=("$az:$current_price")
            
            if [ -z "$best_price" ] || (( $(echo "$current_price < $best_price" | bc -l 2>/dev/null || echo 0) )); then
                best_az="$az"
                best_price="$current_price"
            fi
            
            echo "Spot price in $az: \$${current_price}/hour" >&2
        fi
    done

    if [ -n "$best_az" ]; then
        echo "Best spot price: \$${best_price}/hour in $best_az" >&2
        echo "$best_az:$best_price"
    else
        echo "Could not retrieve spot pricing information" >&2
        return 1
    fi

    return 0
}

# Get optimal spot configuration for deployment
get_optimal_spot_configuration() {
    local instance_type="$1"
    local max_price="$2"
    local region="${3:-${AWS_REGION:-us-east-1}}"
    
    if [ -z "$instance_type" ] || [ -z "$max_price" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "get_optimal_spot_configuration requires instance_type and max_price parameters"
    fi

    echo "Finding optimal spot configuration for $instance_type (max: \$${max_price}/hour)..." >&2
    
    # Get current spot pricing
    local pricing_result
    pricing_result=$(analyze_spot_pricing "$instance_type" "$region")
    
    if [ -z "$pricing_result" ]; then
        echo "Failed to get spot pricing information" >&2
        return 1
    fi
    
    local best_az
    local best_price
    best_az=$(echo "$pricing_result" | cut -d':' -f1)
    best_price=$(echo "$pricing_result" | cut -d':' -f2)
    
    # Check if price is within budget
    if (( $(echo "$best_price <= $max_price" | bc -l 2>/dev/null || echo 0) )); then
        echo "Optimal configuration found:" >&2
        echo "  Instance Type: $instance_type" >&2
        echo "  Availability Zone: $best_az" >&2
        echo "  Current Price: \$${best_price}/hour" >&2
        echo "  Max Price: \$${max_price}/hour" >&2
        echo "  Savings: $(echo "scale=2; (($max_price - $best_price) / $max_price) * 100" | bc -l 2>/dev/null || echo "Unknown")%" >&2
        
        # Return configuration
        cat <<EOF
{
    "instance_type": "$instance_type",
    "availability_zone": "$best_az",
    "current_price": "$best_price",
    "max_price": "$max_price",
    "recommended": true
}
EOF
    else
        echo "Current spot price (\$${best_price}/hour) exceeds maximum budget (\$${max_price}/hour)" >&2
        
        # Suggest alternative instance types
        suggest_alternative_instance_types "$instance_type" "$max_price" "$region"
        
        # Return configuration with warning
        cat <<EOF
{
    "instance_type": "$instance_type",
    "availability_zone": "$best_az",
    "current_price": "$best_price",
    "max_price": "$max_price",
    "recommended": false,
    "reason": "Price exceeds budget"
}
EOF
    fi
}

# Suggest alternative instance types within budget
suggest_alternative_instance_types() {
    local instance_type="$1"
    local max_price="$2"
    local region="${3:-${AWS_REGION:-us-east-1}}"
    
    echo "Suggesting alternative instance types within budget..." >&2
    
    # Define instance families based on input type
    local alternatives=()
    case "$instance_type" in
        g4dn.*)
            alternatives=("g4dn.large" "g4dn.xlarge" "g4dn.2xlarge" "g5.large" "g5.xlarge")
            ;;
        g5.*)
            alternatives=("g5.large" "g5.xlarge" "g5.2xlarge" "g4dn.xlarge" "g4dn.2xlarge")
            ;;
        t3.*)
            alternatives=("t3.medium" "t3.large" "t3.xlarge" "t3a.medium" "t3a.large")
            ;;
        *)
            alternatives=("t3.medium" "t3.large" "m5.large" "m5.xlarge")
            ;;
    esac
    
    local found_alternative=false
    for alt_type in "${alternatives[@]}"; do
        if [ "$alt_type" = "$instance_type" ]; then
            continue
        fi
        
        local alt_pricing
        alt_pricing=$(analyze_spot_pricing "$alt_type" "$region" 2>/dev/null)
        
        if [ -n "$alt_pricing" ]; then
            local alt_price
            alt_price=$(echo "$alt_pricing" | cut -d':' -f2)
            
            if (( $(echo "$alt_price <= $max_price" | bc -l 2>/dev/null || echo 0) )); then
                echo "  Alternative: $alt_type at \$${alt_price}/hour" >&2
                found_alternative=true
            fi
        fi
    done
    
    if [ "$found_alternative" = "false" ]; then
        echo "  No suitable alternatives found within budget" >&2
    fi
}

# =============================================================================
# SPOT INSTANCE LAUNCH FUNCTIONS (MIGRATED FROM MONOLITH)
# =============================================================================

# Launch spot instance with failover capability
launch_spot_instance_with_failover() {
    local stack_name="$1"
    local instance_type="$2"
    local spot_price="$3"
    local user_data="$4"
    local security_group_id="$5"
    local subnet_id="$6"
    local key_name="$7"
    local iam_instance_profile="$8"
    local availability_zone="${9:-}"
    
    if [ -z "$stack_name" ] || [ -z "$instance_type" ] || [ -z "$spot_price" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "launch_spot_instance_with_failover requires stack_name, instance_type, and spot_price parameters"
    fi
    
    echo "Launching spot instance with failover capability..." >&2
    echo "  Stack: $stack_name" >&2
    echo "  Instance Type: $instance_type" >&2
    echo "  Max Spot Price: \$${spot_price}/hour" >&2
    
    # Get optimal configuration
    local config
    config=$(get_optimal_spot_configuration "$instance_type" "$spot_price" "${AWS_REGION:-us-east-1}")
    
    if [ -z "$config" ]; then
        throw_error $ERROR_AWS_API "Failed to get optimal spot configuration"
    fi
    
    # Parse configuration
    local recommended
    recommended=$(echo "$config" | grep '"recommended"' | cut -d':' -f2 | tr -d ' ,"')
    
    if [ "$recommended" != "true" ]; then
        echo "Warning: Current configuration not optimal, proceeding anyway..." >&2
    fi
    
    # Use provided AZ or get from config
    if [ -z "$availability_zone" ]; then
        availability_zone=$(echo "$config" | grep '"availability_zone"' | cut -d'"' -f4)
    fi
    
    # Get AMI for the region and instance type
    local ami_id
    ami_id=$(get_nvidia_optimized_ami "$instance_type" "${AWS_REGION:-us-east-1}")
    
    if [ -z "$ami_id" ]; then
        echo "Failed to get optimal AMI, using fallback..." >&2
        ami_id=$(get_fallback_ami "${AWS_REGION:-us-east-1}")
    fi
    
    # Launch spot instance
    local instance_id
    instance_id=$(launch_spot_instance_primary "$stack_name" "$instance_type" "$spot_price" "$ami_id" \
                  "$user_data" "$security_group_id" "$subnet_id" "$key_name" "$iam_instance_profile" "$availability_zone")
    
    if [ -n "$instance_id" ]; then
        echo "Successfully launched spot instance: $instance_id" >&2
        echo "$instance_id"
        return 0
    else
        echo "Primary spot launch failed, attempting fallback..." >&2
        instance_id=$(launch_spot_instance_fallback "$stack_name" "$instance_type" "$spot_price" "$ami_id" \
                      "$user_data" "$security_group_id" "$subnet_id" "$key_name" "$iam_instance_profile")
        
        if [ -n "$instance_id" ]; then
            echo "Fallback spot instance launched: $instance_id" >&2
            echo "$instance_id"
            return 0
        else
            throw_error $ERROR_AWS_API "Failed to launch spot instance with both primary and fallback methods"
        fi
    fi
}

# Primary spot instance launch method
launch_spot_instance_primary() {
    local stack_name="$1"
    local instance_type="$2"
    local spot_price="$3"
    local ami_id="$4"
    local user_data="$5"
    local security_group_id="$6"
    local subnet_id="$7"
    local key_name="$8"
    local iam_instance_profile="$9"
    local availability_zone="${10:-}"
    
    echo "Attempting primary spot instance launch..." >&2
    
    # Create launch specification
    local launch_spec
    if [ -n "$iam_instance_profile" ]; then
        launch_spec=$(cat <<EOF
{
    "ImageId": "$ami_id",
    "InstanceType": "$instance_type",
    "KeyName": "$key_name",
    "SecurityGroupIds": ["$security_group_id"],
    "SubnetId": "$subnet_id",
    "UserData": "$user_data",
    "IamInstanceProfile": {
        "Name": "$iam_instance_profile"
    }
}
EOF
)
    else
        launch_spec=$(cat <<EOF
{
    "ImageId": "$ami_id",
    "InstanceType": "$instance_type",
    "KeyName": "$key_name",
    "SecurityGroupIds": ["$security_group_id"],
    "SubnetId": "$subnet_id",
    "UserData": "$user_data"
}
EOF
)
    fi
    
    # Request spot instance
    local spot_request_id
    spot_request_id=$(aws ec2 request-spot-instances \
        --spot-price "$spot_price" \
        --type "one-time" \
        --launch-specification "$launch_spec" \
        --region "${AWS_REGION:-us-east-1}" \
        --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
        --output text 2>/dev/null)
    
    if [ -z "$spot_request_id" ] || [ "$spot_request_id" = "None" ]; then
        echo "Failed to create spot instance request" >&2
        return 1
    fi
    
    echo "Spot instance request created: $spot_request_id" >&2
    
    # Wait for fulfillment
    local instance_id
    instance_id=$(wait_for_spot_fulfillment "$spot_request_id" "${AWS_REGION:-us-east-1}")
    
    if [ -n "$instance_id" ]; then
        # Tag the instance
        aws ec2 create-tags \
            --resources "$instance_id" \
            --tags "Key=Name,Value=${stack_name}-spot" \
                   "Key=Stack,Value=$stack_name" \
                   "Key=Type,Value=spot" \
                   "Key=SpotRequestId,Value=$spot_request_id" \
            --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1
        
        # Register resources
        register_resource "spot_requests" "$spot_request_id" "{\"instance_id\": \"$instance_id\", \"stack\": \"$stack_name\"}"
        register_resource "instances" "$instance_id" "{\"type\": \"spot\", \"stack\": \"$stack_name\"}"
        
        echo "$instance_id"
        return 0
    else
        echo "Spot request fulfillment failed" >&2
        return 1
    fi
}

# Wait for spot instance fulfillment
wait_for_spot_fulfillment() {
    local spot_request_id="$1"
    local region="${2:-${AWS_REGION:-us-east-1}}"
    local max_attempts="${3:-30}"
    local attempt=1
    
    echo "Waiting for spot instance fulfillment..." >&2
    
    while [ $attempt -le $max_attempts ]; do
        local status
        status=$(aws ec2 describe-spot-instance-requests \
            --spot-instance-request-ids "$spot_request_id" \
            --region "$region" \
            --query 'SpotInstanceRequests[0].State' \
            --output text 2>/dev/null)
        
        case "$status" in
            "active")
                # Get instance ID
                local instance_id
                instance_id=$(aws ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --region "$region" \
                    --query 'SpotInstanceRequests[0].InstanceId' \
                    --output text 2>/dev/null)
                
                if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                    echo "Spot instance fulfilled: $instance_id" >&2
                    echo "$instance_id"
                    return 0
                fi
                ;;
            "failed"|"cancelled"|"closed")
                echo "Spot request failed with status: $status" >&2
                return 1
                ;;
            *)
                echo "Spot request status: ${status:-pending} (attempt $attempt/$max_attempts)" >&2
                ;;
        esac
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "Timeout waiting for spot instance fulfillment" >&2
    return 1
}

# Fallback spot instance launch (try different AZs and instance types)
launch_spot_instance_fallback() {
    local stack_name="$1"
    local instance_type="$2"
    local spot_price="$3"
    local ami_id="$4"
    local user_data="$5"
    local security_group_id="$6"
    local subnet_id="$7"
    local key_name="$8"
    local iam_instance_profile="$9"
    
    echo "Attempting fallback spot instance launch..." >&2
    
    # Try alternative instance types
    local alternative_types=()
    case "$instance_type" in
        g4dn.xlarge)
            alternative_types=("g4dn.large" "g5.xlarge" "g4dn.2xlarge")
            ;;
        g5.xlarge)
            alternative_types=("g4dn.xlarge" "g5.large" "g5.2xlarge")
            ;;
        *)
            alternative_types=("t3.large" "m5.large" "t3.xlarge")
            ;;
    esac
    
    for alt_type in "${alternative_types[@]}"; do
        echo "Trying alternative instance type: $alt_type" >&2
        
        # Get alternative AMI if needed
        local alt_ami_id="$ami_id"
        if [[ "$alt_type" =~ ^t3\. ]] || [[ "$alt_type" =~ ^m5\. ]]; then
            alt_ami_id=$(get_fallback_ami "${AWS_REGION:-us-east-1}")
        fi
        
        local instance_id
        instance_id=$(launch_spot_instance_primary "$stack_name" "$alt_type" "$spot_price" "$alt_ami_id" \
                      "$user_data" "$security_group_id" "$subnet_id" "$key_name" "$iam_instance_profile")
        
        if [ -n "$instance_id" ]; then
            echo "Successfully launched fallback spot instance: $instance_id (type: $alt_type)" >&2
            echo "$instance_id"
            return 0
        fi
        
        echo "Failed to launch $alt_type, trying next alternative..." >&2
    done
    
    echo "All fallback attempts failed" >&2
    return 1
}

# =============================================================================
# AMI SELECTION FOR SPOT INSTANCES
# =============================================================================

# Get NVIDIA optimized AMI for GPU instances
get_nvidia_optimized_ami() {
    local instance_type="$1"
    local region="${2:-${AWS_REGION:-us-east-1}}"
    
    # Check if this is a GPU instance type
    if [[ "$instance_type" =~ ^g[0-9] ]]; then
        echo "Getting NVIDIA optimized AMI for GPU instance..." >&2
        
        # Look for Deep Learning AMI with NVIDIA drivers
        local ami_id
        ami_id=$(aws ec2 describe-images \
            --region "$region" \
            --owners "amazon" \
            --filters "Name=name,Values=Deep Learning AMI GPU*" \
                      "Name=state,Values=available" \
                      "Name=architecture,Values=x86_64" \
            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
            --output text 2>/dev/null)
        
        if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
            echo "Found NVIDIA optimized AMI: $ami_id" >&2
            echo "$ami_id"
            return 0
        fi
    fi
    
    # Fallback to standard Ubuntu AMI
    get_fallback_ami "$region"
}

# Get fallback AMI (standard Ubuntu)
get_fallback_ami() {
    local region="${1:-${AWS_REGION:-us-east-1}}"
    
    echo "Getting fallback Ubuntu AMI..." >&2
    
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --region "$region" \
        --owners "099720109477" \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
                  "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null)
    
    if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
        echo "Found fallback AMI: $ami_id" >&2
        echo "$ami_id"
        return 0
    else
        throw_error $ERROR_AWS_API "Failed to find suitable AMI in region: $region"
    fi
}

# =============================================================================
# COST CALCULATION AND SAVINGS
# =============================================================================

# Calculate spot instance savings compared to on-demand
calculate_spot_savings() {
    local spot_price="$1"
    local instance_type="$2"
    local hours="${3:-24}"
    
    if [ -z "$spot_price" ] || [ -z "$instance_type" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "calculate_spot_savings requires spot_price and instance_type parameters"
    fi
    
    echo "Calculating spot instance savings..." >&2
    
    # Get on-demand pricing (simplified fallback values)
    local ondemand_price
    case "$instance_type" in
        g4dn.large)    ondemand_price="0.526" ;;
        g4dn.xlarge)   ondemand_price="0.834" ;;
        g4dn.2xlarge)  ondemand_price="1.668" ;;
        g5.large)      ondemand_price="1.006" ;;
        g5.xlarge)     ondemand_price="2.012" ;;
        t3.medium)     ondemand_price="0.0464" ;;
        t3.large)      ondemand_price="0.0928" ;;
        *)             ondemand_price="1.000" ;;
    esac
    
    # Calculate savings
    local spot_cost
    local ondemand_cost
    local savings_percent
    local savings_amount
    
    spot_cost=$(echo "scale=4; $spot_price * $hours" | bc -l 2>/dev/null || echo "0")
    ondemand_cost=$(echo "scale=4; $ondemand_price * $hours" | bc -l 2>/dev/null || echo "0")
    savings_amount=$(echo "scale=4; $ondemand_cost - $spot_cost" | bc -l 2>/dev/null || echo "0")
    savings_percent=$(echo "scale=2; ($savings_amount / $ondemand_cost) * 100" | bc -l 2>/dev/null || echo "0")
    
    # Display results
    cat <<EOF
Cost Analysis for $instance_type over $hours hours:
  On-Demand Cost: \$${ondemand_cost}
  Spot Cost:      \$${spot_cost}
  Savings:        \$${savings_amount} (${savings_percent}%)
  
Recommendation: Use spot instances for cost-effective GPU workloads
EOF
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup spot instance resources
cleanup_spot_resources() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up spot instance resources for: $stack_name" >&2
    
    # Cancel active spot requests
    local spot_requests
    spot_requests=$(aws ec2 describe-spot-instance-requests \
        --filters "Name=tag:Stack,Values=$stack_name" "Name=state,Values=open,active" \
        --query 'SpotInstanceRequests[*].SpotInstanceRequestId' \
        --output text 2>/dev/null || echo "")
    
    for spot_id in $spot_requests; do
        if [ -n "$spot_id" ] && [ "$spot_id" != "None" ]; then
            aws ec2 cancel-spot-instance-requests \
                --spot-instance-request-ids "$spot_id" \
                --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1 || true
            echo "Cancelled spot instance request: $spot_id" >&2
        fi
    done
    
    # Terminate spot instances
    local spot_instances
    spot_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Stack,Values=$stack_name" "Name=tag:Type,Values=spot" \
                  "Name=instance-state-name,Values=running,pending,stopped,stopping" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    for instance_id in $spot_instances; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            aws ec2 terminate-instances \
                --instance-ids "$instance_id" \
                --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1 || true
            echo "Terminated spot instance: $instance_id" >&2
        fi
    done
}