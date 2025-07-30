#!/usr/bin/env bash
# =============================================================================
# Spot Instance Deployment Library
# Specialized functions for AWS Spot Instance deployments
# Compatible with bash 3.x+
# =============================================================================


# Load associative array utilities
source "$SCRIPT_DIR/associative-arrays.sh"

# =============================================================================
# VARIABLE INITIALIZATION AND DEFAULTS
# =============================================================================

# Initialize variables with defaults to prevent unbound variable errors
ALB_SCHEME="${ALB_SCHEME:-internet-facing}"
ALB_TYPE="${ALB_TYPE:-application}"
SPOT_TYPE="${SPOT_TYPE:-one-time}"
CLOUDWATCH_LOG_GROUP="${CLOUDWATCH_LOG_GROUP:-/aws/ec2/GeuseMaker}"
CLOUDWATCH_LOG_RETENTION="${CLOUDWATCH_LOG_RETENTION:-7}"
CLOUDFRONT_PRICE_CLASS="${CLOUDFRONT_PRICE_CLASS:-PriceClass_100}"
CLOUDFRONT_MIN_TTL="${CLOUDFRONT_MIN_TTL:-0}"
CLOUDFRONT_DEFAULT_TTL="${CLOUDFRONT_DEFAULT_TTL:-86400}"
CLOUDFRONT_MAX_TTL="${CLOUDFRONT_MAX_TTL:-31536000}"

# =============================================================================
# GLOBAL ASSOCIATIVE ARRAYS
# =============================================================================

# Global pricing cache with associative arrays
declare -gA SPOT_PRICING_CACHE
declare -gA INSTANCE_CAPABILITIES
declare -gA PRICING_HISTORY
declare -gA DEPLOYMENT_STATE

# Initialize pricing data and capabilities
aa_create_pricing_data SPOT_PRICING_CACHE
aa_create_capability_matrix INSTANCE_CAPABILITIES

# =============================================================================
# SPOT PRICING ANALYSIS
# =============================================================================

# Enhanced spot pricing analysis using associative arrays
analyze_spot_pricing() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    shift 2
    local availability_zones=("$@")
    
    if [[ -z "$instance_type" ]]; then
        error "analyze_spot_pricing requires instance_type parameter"
        return 1
    fi

    log "Analyzing spot pricing for $instance_type in $region using associative arrays..."

    # Create pricing analysis result array
    declare -A pricing_analysis
    declare -A az_prices
    
    # Get all AZs if none specified using AWS CLI v2 with caching
    if [[ ${#availability_zones[@]} -eq 0 ]]; then
        local az_output
        az_output=$(aws_cli_cached 1800 ec2 describe-availability-zones \
            --region "$region" \
            --query 'AvailabilityZones[].ZoneName' \
            --output text | tr '\t' ' ')
        read -ra availability_zones <<< "$az_output"
    fi

    local best_az=""
    local best_price=""
    local cache_key="${instance_type}:${region}"
    local current_time=$(date +%s)
    
    # Check cache first
    local cache_timestamp=$(aa_get SPOT_PRICING_CACHE "${cache_key}:timestamp" "0")
    local cache_ttl=$(aa_get SPOT_PRICING_CACHE "_cache_ttl" "3600")
    
    if [[ $((current_time - cache_timestamp)) -lt $cache_ttl ]]; then
        local cached_result=$(aa_get SPOT_PRICING_CACHE "${cache_key}:result" "")
        if [[ -n "$cached_result" ]]; then
            log "Using cached pricing data for $instance_type in $region"
            echo "$cached_result"
            return 0
        fi
    fi

    # Analyze pricing in each AZ using AWS CLI v2 with retry logic
    for az in "${availability_zones[@]}"; do
        local price_info
        price_info=$(aws_cli_with_retry ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --availability-zone "$az" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "$region" \
            --query 'SpotPriceHistory[0].[AvailabilityZone,SpotPrice,Timestamp]' \
            --output text 2>/dev/null)

        if [[ -n "$price_info" ]]; then
            local current_price timestamp
            current_price=$(echo "$price_info" | cut -f2)
            timestamp=$(echo "$price_info" | cut -f3)
            
            # Store in pricing analysis
            aa_set az_prices "$az" "$current_price"
            aa_set pricing_analysis "${az}:price" "$current_price"
            aa_set pricing_analysis "${az}:timestamp" "$timestamp"
            
            # Update pricing history
            aa_set PRICING_HISTORY "${instance_type}:${region}:${az}:$(date +%Y%m%d%H)" "$current_price"
            
            # Track best price
            if [[ -z "$best_price" ]] || (( $(echo "$current_price < $best_price" | bc -l) )); then
                best_az="$az"
                best_price="$current_price"
            fi
            
            info "Spot price in $az: \$${current_price}/hour"
        fi
    done

    # Store analysis results
    if [[ -n "$best_az" ]]; then
        local result="${best_az}:${best_price}"
        aa_set pricing_analysis "best_az" "$best_az"
        aa_set pricing_analysis "best_price" "$best_price"
        aa_set pricing_analysis "analysis_time" "$current_time"
        aa_set pricing_analysis "total_azs_checked" "${#availability_zones[@]}"
        aa_set pricing_analysis "successful_checks" "$(aa_size az_prices)"
        
        # Cache the result
        aa_set SPOT_PRICING_CACHE "${cache_key}:result" "$result"
        aa_set SPOT_PRICING_CACHE "${cache_key}:timestamp" "$current_time"
        aa_set SPOT_PRICING_CACHE "${cache_key}:analysis" "$(aa_to_json pricing_analysis)"
        
        success "Best spot price: \$${best_price}/hour in $best_az"
        echo "$result"
        return 0
    else
        error "Could not retrieve spot pricing information"
        return 1
    fi
}

get_optimal_spot_configuration() {
    local instance_type="$1"
    local max_price="$2"
    local region="${3:-$AWS_REGION}"
    
    if [ -z "$instance_type" ] || [ -z "$max_price" ]; then
        error "get_optimal_spot_configuration requires instance_type and max_price parameters"
        return 1
    fi

    log "Finding optimal spot configuration for $instance_type (max: \$${max_price}/hour)..."

    # Analyze current pricing
    local pricing_result
    pricing_result=$(analyze_spot_pricing "$instance_type" "$region")
    
    if [ $? -ne 0 ]; then
        error "Failed to analyze spot pricing"
        return 1
    fi

    local best_az="${pricing_result%:*}"
    local best_price="${pricing_result#*:}"

    # Check if best price is within budget
    if (( $(echo "$best_price > $max_price" | bc -l) )); then
        warning "Best available spot price (\$${best_price}) exceeds maximum (\$${max_price})"
        
        # Suggest alternative instance types
        suggest_alternative_instance_types "$instance_type" "$max_price" "$region"
        return 1
    fi

    # Calculate recommended bid price (10% above current price)
    local recommended_bid
    recommended_bid=$(echo "$best_price * 1.1" | bc -l)
    
    # Cap at max price
    if (( $(echo "$recommended_bid > $max_price" | bc -l) )); then
        recommended_bid="$max_price"
    fi

    success "Optimal configuration found:"
    info "  Availability Zone: $best_az"
    info "  Current Price: \$${best_price}/hour"
    info "  Recommended Bid: \$${recommended_bid}/hour"

    echo "${best_az}:${recommended_bid}"
    return 0
}

# Enhanced alternative instance type suggestions using associative arrays
suggest_alternative_instance_types() {
    local target_instance_type="$1"
    local max_price="$2"
    local region="$3"
    
    log "Suggesting alternative instance types within budget using capability matrix..."

    # Create alternatives mapping using associative arrays
    declare -A alternatives_map
    declare -A pricing_results
    declare -A recommendations
    
    # Define alternative instance types with scoring
    case "$target_instance_type" in
        "g4dn.xlarge")
            aa_set alternatives_map "g4dn.large" "0.8"  # 80% capability score
            aa_set alternatives_map "g5.large" "0.9"   # 90% capability score
            aa_set alternatives_map "c5.xlarge" "0.6"  # 60% capability score (no GPU)
            aa_set alternatives_map "m5.xlarge" "0.5"  # 50% capability score (no GPU)
            ;;
        "g4dn.2xlarge")
            aa_set alternatives_map "g4dn.xlarge" "0.8"
            aa_set alternatives_map "g5.xlarge" "0.9"
            aa_set alternatives_map "c5.2xlarge" "0.6"
            aa_set alternatives_map "m5.2xlarge" "0.5"
            ;;
        "g5.xlarge")
            aa_set alternatives_map "g4dn.xlarge" "0.8"
            aa_set alternatives_map "g5.large" "0.7"
            aa_set alternatives_map "c5.xlarge" "0.5"
            ;;
        *)
            warning "No alternatives defined for instance type: $target_instance_type"
            return 1
            ;;
    esac

    info "Checking alternative instance types with capability scoring:"
    
    # Analyze each alternative
    local alt_type capability_score
    for alt_type in $(aa_keys alternatives_map); do
        capability_score=$(aa_get alternatives_map "$alt_type")
        
        local pricing_result
        pricing_result=$(analyze_spot_pricing "$alt_type" "$region" 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            local best_price="${pricing_result#*:}"
            local best_az="${pricing_result%:*}"
            
            # Store pricing result
            aa_set pricing_results "${alt_type}:price" "$best_price"
            aa_set pricing_results "${alt_type}:az" "$best_az"
            aa_set pricing_results "${alt_type}:capability_score" "$capability_score"
            
            # Check if within budget
            if (( $(echo "$best_price <= $max_price" | bc -l) )); then
                local savings_percent
                savings_percent=$(echo "scale=1; (($max_price - $best_price) / $max_price) * 100" | bc -l)
                
                # Create recommendation score (capability + cost efficiency)
                local cost_efficiency
                cost_efficiency=$(echo "scale=2; ($max_price - $best_price) / $max_price" | bc -l)
                local recommendation_score
                recommendation_score=$(echo "scale=2; ($capability_score * 0.7) + ($cost_efficiency * 0.3)" | bc -l)
                
                aa_set recommendations "$alt_type" "$recommendation_score"
                
                success "  $alt_type: \$${best_price}/hour (${savings_percent}% savings, capability: ${capability_score}, score: ${recommendation_score}) ✓"
            else
                info "  $alt_type: \$${best_price}/hour (over budget, capability: ${capability_score})"
            fi
        else
            warning "  $alt_type: pricing data unavailable"
        fi
    done
    
    # Show best recommendation if any
    if ! aa_is_empty recommendations; then
        local best_alternative=""
        local best_score="0"
        
        for alt_type in $(aa_keys recommendations); do
            local score=$(aa_get recommendations "$alt_type")
            if (( $(echo "$score > $best_score" | bc -l) )); then
                best_alternative="$alt_type"
                best_score="$score"
            fi
        done
        
        if [[ -n "$best_alternative" ]]; then
            local alt_price=$(aa_get pricing_results "${best_alternative}:price")
            local alt_az=$(aa_get pricing_results "${best_alternative}:az")
            local alt_capability=$(aa_get pricing_results "${best_alternative}:capability_score")
            
            success "RECOMMENDATION: $best_alternative in $alt_az"
            success "  Price: \$${alt_price}/hour, Capability: ${alt_capability}, Score: ${best_score}"
        fi
    else
        warning "No suitable alternatives found within budget of \$${max_price}/hour"
    fi
}

# =============================================================================
# SPOT INSTANCE LAUNCH
# =============================================================================

launch_spot_instance_with_failover() {
    local stack_name="$1"
    local instance_type="$2"
    local spot_price="$3"
    local user_data="$4"
    local security_group_id="$5"
    local subnet_id="$6"
    local key_name="$7"
    local iam_instance_profile="$8"
    local target_az="${9:-}"
    
    if [ -z "$stack_name" ] || [ -z "$instance_type" ] || [ -z "$spot_price" ]; then
        error "launch_spot_instance_with_failover requires stack_name, instance_type, and spot_price parameters"
        return 1
    fi

    log "Launching spot instance with failover strategy..."

    local bid_price="$spot_price"
    
    # Use provided AZ or find optimal configuration
    if [ -n "$target_az" ]; then
        log "Using specified availability zone: $target_az"
        
        # Get current spot price for the specified AZ using AWS CLI v2
        local current_price
        current_price=$(aws_cli_with_retry ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --availability-zone "$target_az" \
            --max-items 1 \
            --query 'SpotPriceHistory[0].SpotPrice' \
            --output text \
            --region "$AWS_REGION" | head -1 | tr -d '[:space:]')
            
        if [ "$current_price" != "None" ] && [ -n "$current_price" ]; then
            info "Current spot price in $target_az: \$${current_price}/hour"
            # Use current price if it's lower than our max
            if command -v bc >/dev/null 2>&1; then
                if (( $(echo "$current_price < $spot_price" | bc -l) )); then
                    bid_price="$current_price"
                    info "Using current market price: \$${bid_price}/hour"
                fi
            fi
        else
            warning "No current spot price available for $target_az"
        fi
    else
        # Get optimal spot configuration
        local optimal_config
        optimal_config=$(get_optimal_spot_configuration "$instance_type" "$spot_price")
        
        if [ $? -ne 0 ]; then
            error "Failed to get optimal spot configuration"
            return 1
        fi

        target_az="${optimal_config%:*}"
        bid_price="${optimal_config#*:}"
    fi

    # Get AMI for the instance type
    local ami_id
    ami_id=$(get_nvidia_optimized_ami "$AWS_REGION")
    
    if [ -z "$ami_id" ]; then
        error "Failed to get optimized AMI"
        return 1
    fi

    # Create spot instance request
    log "Creating spot instance request..."
    log "  Instance Type: $instance_type"
    log "  Bid Price: \$${bid_price}/hour"
    log "  Availability Zone: $target_az"

    # Debug logging
    log "DEBUG: IAM Instance Profile: $iam_instance_profile"
    
    # Create spot launch specification file to avoid JSON parsing issues
    local launch_spec_file="/tmp/launch-spec-${stack_name}.json"
    cat > "$launch_spec_file" << EOF
{
    "ImageId": "$ami_id",
    "InstanceType": "$instance_type",
    "KeyName": "$key_name",
    "SecurityGroupIds": ["$security_group_id"],
    "SubnetId": "$subnet_id",
    "UserData": "$(echo -n "$user_data" | base64 -w 0)",
    "IamInstanceProfile": {"Name": "$iam_instance_profile"},
    "Placement": {"AvailabilityZone": "$target_az"}
}
EOF
    
    # Debug: log the launch spec
    log "DEBUG: Launch spec file: $launch_spec_file"

    # Submit spot instance request using AWS CLI v2 with retry logic
    local spot_request_id
    spot_request_id=$(aws_cli_with_retry ec2 request-spot-instances \
        --spot-price "$bid_price" \
        --instance-count 1 \
        --type "$SPOT_TYPE" \
        --launch-specification "file://$launch_spec_file" \
        --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
        --output text \
        --region "$AWS_REGION")

    # Clean up temporary file
    rm -f "$launch_spec_file"
    
    if [ -z "$spot_request_id" ] || [ "$spot_request_id" = "None" ]; then
        error "Failed to create spot instance request"
        return 1
    fi

    success "Spot instance request created: $spot_request_id"

    # Wait for spot request to be fulfilled
    local instance_id
    instance_id=$(wait_for_spot_fulfillment "$spot_request_id" "$stack_name")
    
    if [ $? -ne 0 ]; then
        warning "Spot request failed or timed out. Attempting failover..."
        
        # Cancel the failed request using AWS CLI v2
        aws_cli_with_retry ec2 cancel-spot-instance-requests \
            --spot-instance-request-ids "$spot_request_id" \
            --region "$AWS_REGION" > /dev/null
        
        # Try fallback strategy
        instance_id=$(launch_spot_instance_fallback "$stack_name" "$instance_type" "$spot_price" "$user_data" "$security_group_id" "$subnet_id" "$key_name" "$iam_instance_profile")
        
        if [ $? -ne 0 ]; then
            error "All spot launch strategies failed"
            return 1
        fi
    fi

    echo "$instance_id"
    return 0
}

wait_for_spot_fulfillment() {
    local spot_request_id="$1"
    local stack_name="$2"
    local max_wait="${3:-300}"  # 5 minutes default
    local check_interval="${4:-10}"
    
    log "Waiting for spot request fulfillment: $spot_request_id"
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local request_state
        request_state=$(aws_cli_with_retry ec2 describe-spot-instance-requests \
            --spot-instance-request-ids "$spot_request_id" \
            --query 'SpotInstanceRequests[0].State' \
            --output text \
            --region "$AWS_REGION")

        case "$request_state" in
            "active")
                local instance_id
                instance_id=$(aws_cli_with_retry ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --query 'SpotInstanceRequests[0].InstanceId' \
                    --output text \
                    --region "$AWS_REGION")
                
                success "Spot instance launched: $instance_id"
                
                # Tag the instance
                tag_instance_with_metadata "$instance_id" "$stack_name" "spot" \
                    "Key=SpotRequestId,Value=$spot_request_id"
                
                echo "$instance_id"
                return 0
                ;;
            "failed"|"cancelled"|"closed")
                local status_code
                status_code=$(aws_cli_with_retry ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --query 'SpotInstanceRequests[0].Status.Code' \
                    --output text \
                    --region "$AWS_REGION")
                
                error "Spot request failed with status: $status_code"
                return 1
                ;;
            "open")
                info "Spot request pending... (${elapsed}s elapsed)"
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    error "Spot request timed out after ${max_wait}s"
    return 1
}

launch_spot_instance_fallback() {
    local stack_name="$1"
    local instance_type="$2"
    local max_price="$3"
    local user_data="$4"
    local security_group_id="$5"
    local subnet_id="$6"
    local key_name="$7"
    local iam_instance_profile="$8"

    # Parameter validation
    if [ -z "$stack_name" ] || [ -z "$instance_type" ] || [ -z "$max_price" ] || [ -z "$user_data" ] || [ -z "$security_group_id" ] || [ -z "$key_name" ] || [ -z "$iam_instance_profile" ]; then
        error "launch_spot_instance_fallback requires stack_name, instance_type, max_price, user_data, security_group_id, key_name, and iam_instance_profile parameters"
        return 1
    fi

    log "Attempting spot instance fallback strategies..."

    # Strategy 1: Try alternative availability zones
    local azs=()
    while IFS= read -r az; do
        [ -n "$az" ] && azs+=("$az")
    done < <(aws_cli_cached 1800 ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[].ZoneName' \
        --output text | tr '\t' '\n')

    for az in "${azs[@]+${azs[@]}}"; do
        log "Trying availability zone: $az"
        
        # Get subnet for this AZ
        local az_subnet_id
        az_subnet_id=$(aws ec2 describe-subnets \
            --filters "Name=availability-zone,Values=$az" "Name=state,Values=available" \
            --query 'Subnets[0].SubnetId' \
            --output text \
            --region "$AWS_REGION")

        if [ "$az_subnet_id" != "None" ] && [ -n "$az_subnet_id" ]; then
            # Try spot launch in this AZ
            local launch_spec='{
                "ImageId": "'$(get_nvidia_optimized_ami "$AWS_REGION")'",
                "InstanceType": "'$instance_type'",
                "KeyName": "'$key_name'",
                "SecurityGroupIds": ["'$security_group_id'"],
                "SubnetId": "'$az_subnet_id'",
                "UserData": "'$(echo -n "$user_data" | base64 -w 0)'",
                "IamInstanceProfile": {"Name": "'$iam_instance_profile'"},
                "Placement": {"AvailabilityZone": "'$az'"}
            }'

            local spot_request_id
            spot_request_id=$(aws ec2 request-spot-instances \
                --spot-price "$max_price" \
                --instance-count 1 \
                --type "one-time" \
                --launch-specification "$launch_spec" \
                --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null)

            if [ -n "$spot_request_id" ] && [ "$spot_request_id" != "None" ]; then
                local instance_id
                instance_id=$(wait_for_spot_fulfillment "$spot_request_id" "$stack_name" 120)
                
                if [ $? -eq 0 ]; then
                    success "Fallback spot launch successful in $az"
                    echo "$instance_id"
                    return 0
                fi
                
                # Cancel failed request
                aws ec2 cancel-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --region "$AWS_REGION" > /dev/null
            fi
        fi
    done

    # Strategy 2: Try lower instance types
    warning "Trying alternative instance types for spot launch..."
    
    local alternative_types=()
    case "$instance_type" in
        "g4dn.2xlarge")
            alternative_types=("g4dn.xlarge" "g4dn.large")
            ;;
        "g4dn.xlarge")
            alternative_types=("g4dn.large")
            ;;
        "g5.xlarge")
            alternative_types=("g4dn.xlarge" "g4dn.large")
            ;;
    esac

    for alt_type in "${alternative_types[@]+"${alternative_types[@]}"}"; do
        log "Trying alternative instance type: $alt_type"
        
        local optimal_config
        optimal_config=$(get_optimal_spot_configuration "$alt_type" "$max_price" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local target_az="${optimal_config%:*}"
            local bid_price="${optimal_config#*:}"
            
            # Get subnet for target AZ
            local target_subnet_id
            target_subnet_id=$(aws ec2 describe-subnets \
                --filters "Name=availability-zone,Values=$target_az" "Name=state,Values=available" \
                --query 'Subnets[0].SubnetId' \
                --output text \
                --region "$AWS_REGION")

            if [ "$target_subnet_id" != "None" ] && [ -n "$target_subnet_id" ]; then
                local instance_id
                instance_id=$(launch_spot_instance_with_failover "$stack_name" "$alt_type" "$bid_price" "$user_data" "$security_group_id" "$target_subnet_id" "$key_name" "$iam_instance_profile")
                
                if [ $? -eq 0 ]; then
                    warning "Successfully launched alternative instance type: $alt_type"
                    echo "$instance_id"
                    return 0
                fi
            fi
        fi
    done

    error "All fallback strategies failed"
    return 1
}

# =============================================================================
# SPOT INSTANCE MONITORING
# =============================================================================

monitor_spot_instance_interruption() {
    local instance_id="$1"
    local notification_topic="$2"
    
    if [ -z "$instance_id" ]; then
        error "monitor_spot_instance_interruption requires instance_id parameter"
        return 1
    fi

    log "Setting up spot instance interruption monitoring for: $instance_id"

    # Create CloudWatch alarm for spot interruption
    local alarm_name="spot-interruption-${instance_id}"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "Monitor spot instance interruption for $instance_id" \
        --metric-name "StatusCheckFailed_Instance" \
        --namespace "AWS/EC2" \
        --statistic "Maximum" \
        --period 60 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION"

    if [ -n "$notification_topic" ]; then
        aws cloudwatch put-metric-alarm \
            --alarm-name "$alarm_name" \
            --alarm-actions "$notification_topic" \
            --region "$AWS_REGION"
    fi

    success "Spot instance monitoring configured"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

get_nvidia_optimized_ami() {
    local region="$1"
    
    # Get the latest NVIDIA-optimized AMI
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=Deep Learning AMI GPU TensorFlow*Ubuntu*" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$region" 2>/dev/null)

    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        # Fallback to Ubuntu 22.04 LTS
        ami_id=$(aws ec2 describe-images \
            --owners 099720109477 \
            --filters \
                "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
                "Name=state,Values=available" \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text \
            --region "$region")
    fi

    echo "$ami_id"
    return 0
}

# Enhanced cost savings calculation using associative arrays
calculate_spot_savings() {
    local spot_price="$1"
    local instance_type="$2"
    local hours="${3:-24}"
    local detailed="${4:-false}"
    
    if [[ -z "$spot_price" ]] || [[ -z "$instance_type" ]]; then
        error "calculate_spot_savings requires spot_price and instance_type parameters"
        return 1
    fi

    # Create cost analysis using associative arrays
    declare -A cost_analysis
    declare -A pricing_data
    
    # Enhanced on-demand pricing lookup from capability matrix
    local ondemand_price=$(aa_get SPOT_PRICING_CACHE "${instance_type}:${AWS_REGION:-us-east-1}:ondemand" "")
    
    # Fallback to static pricing if not cached
    if [[ -z "$ondemand_price" ]]; then
        case "$instance_type" in
            "g4dn.xlarge")
                ondemand_price="0.526"
                ;;
            "g4dn.2xlarge")
                ondemand_price="0.752"
                ;;
            "g5.xlarge")
                ondemand_price="1.006"
                ;;
            "g5.2xlarge")
                ondemand_price="2.012"
                ;;
            "g4dn.large")
                ondemand_price="0.263"
                ;;
            *)
                warning "On-demand price not available for $instance_type"
                return 1
                ;;
        esac
    fi

    # Calculate costs and savings
    local spot_cost ondemand_cost savings savings_percentage
    spot_cost=$(echo "scale=4; $spot_price * $hours" | bc -l)
    ondemand_cost=$(echo "scale=4; $ondemand_price * $hours" | bc -l)
    savings=$(echo "scale=4; $ondemand_cost - $spot_cost" | bc -l)
    savings_percentage=$(echo "scale=1; ($savings / $ondemand_cost) * 100" | bc -l)

    # Store in associative array
    aa_set cost_analysis "instance_type" "$instance_type"
    aa_set cost_analysis "duration_hours" "$hours"
    aa_set cost_analysis "spot_price_per_hour" "$spot_price"
    aa_set cost_analysis "ondemand_price_per_hour" "$ondemand_price"
    aa_set cost_analysis "spot_total_cost" "$spot_cost"
    aa_set cost_analysis "ondemand_total_cost" "$ondemand_cost"
    aa_set cost_analysis "total_savings" "$savings"
    aa_set cost_analysis "savings_percentage" "$savings_percentage"
    aa_set cost_analysis "analysis_timestamp" "$(date +%s)"
    
    # Add instance capabilities if available
    local gpu_memory=$(aa_get INSTANCE_CAPABILITIES "${instance_type}:gpu_memory" "")
    local gpu_type=$(aa_get INSTANCE_CAPABILITIES "${instance_type}:gpu_type" "")
    local vcpus=$(aa_get INSTANCE_CAPABILITIES "${instance_type}:vcpus" "")
    local memory=$(aa_get INSTANCE_CAPABILITIES "${instance_type}:memory" "")
    
    if [[ -n "$gpu_memory" ]]; then
        aa_set cost_analysis "gpu_memory_gb" "$gpu_memory"
        aa_set cost_analysis "gpu_type" "$gpu_type"
        aa_set cost_analysis "vcpus" "$vcpus"
        aa_set cost_analysis "memory_gb" "$memory"
        
        # Calculate cost per GPU GB
        local cost_per_gpu_gb_spot cost_per_gpu_gb_ondemand
        cost_per_gpu_gb_spot=$(echo "scale=6; $spot_price / $gpu_memory" | bc -l)
        cost_per_gpu_gb_ondemand=$(echo "scale=6; $ondemand_price / $gpu_memory" | bc -l)
        
        aa_set cost_analysis "cost_per_gpu_gb_spot" "$cost_per_gpu_gb_spot"
        aa_set cost_analysis "cost_per_gpu_gb_ondemand" "$cost_per_gpu_gb_ondemand"
    fi

    # Display results
    info "=== Enhanced Spot Instance Cost Analysis ==="
    aa_print cost_analysis "Cost Analysis for $instance_type" true
    
    if [[ "$detailed" == "true" ]]; then
        info ""
        info "=== Cost Breakdown ==="
        printf "%-25s: %s\n" "Instance Type" "$instance_type"
        printf "%-25s: %s hours\n" "Duration" "$hours"
        printf "%-25s: \$%s/hour\n" "Spot Price" "$spot_price"
        printf "%-25s: \$%s/hour\n" "On-Demand Price" "$ondemand_price"
        printf "%-25s: \$%s\n" "Spot Total Cost" "$spot_cost"
        printf "%-25s: \$%s\n" "On-Demand Total Cost" "$ondemand_cost"
        printf "%-25s: \$%s (%s%%)\n" "Total Savings" "$savings" "$savings_percentage"
        
        if [[ -n "$gpu_memory" ]]; then
            printf "%-25s: %s GB %s GPU\n" "GPU Specification" "$gpu_memory" "$gpu_type"
            printf "%-25s: \$%s/GB/hour\n" "Spot Cost per GPU GB" "$cost_per_gpu_gb_spot"
            printf "%-25s: \$%s/GB/hour\n" "OnDemand Cost per GPU GB" "$cost_per_gpu_gb_ondemand"
        fi
    fi
    
    # Store in pricing history for future analysis
    local timestamp=$(date +%Y%m%d%H%M)
    aa_set PRICING_HISTORY "cost_analysis:${instance_type}:${timestamp}" "$(aa_to_json cost_analysis)"
    
    return 0
}

# Get pricing statistics and trends using associative arrays
get_pricing_statistics() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    local hours_back="${3:-24}"
    
    declare -A pricing_stats
    declare -A historical_prices
    
    # Filter pricing history for this instance type and region
    local history_key price_data timestamp price
    local prices=()
    local min_price="" max_price="" total_price=0 count=0
    
    # Collect historical prices
    for history_key in $(aa_keys PRICING_HISTORY); do
        if [[ "$history_key" =~ ^${instance_type}:${region}: ]]; then
            price_data=$(aa_get PRICING_HISTORY "$history_key")
            if [[ -n "$price_data" ]]; then
                prices+=("$price_data")
                
                # Update min/max
                if [[ -z "$min_price" ]] || (( $(echo "$price_data < $min_price" | bc -l) )); then
                    min_price="$price_data"
                fi
                if [[ -z "$max_price" ]] || (( $(echo "$price_data > $max_price" | bc -l) )); then
                    max_price="$price_data"
                fi
                
                total_price=$(echo "scale=6; $total_price + $price_data" | bc -l)
                count=$((count + 1))
            fi
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        local avg_price volatility
        avg_price=$(echo "scale=6; $total_price / $count" | bc -l)
        volatility=$(echo "scale=2; (($max_price - $min_price) / $avg_price) * 100" | bc -l)
        
        aa_set pricing_stats "instance_type" "$instance_type"
        aa_set pricing_stats "region" "$region"
        aa_set pricing_stats "sample_count" "$count"
        aa_set pricing_stats "min_price" "$min_price"
        aa_set pricing_stats "max_price" "$max_price"
        aa_set pricing_stats "avg_price" "$avg_price"
        aa_set pricing_stats "volatility_percent" "$volatility"
        aa_set pricing_stats "analysis_time" "$(date)"
        
        info "=== Pricing Statistics for $instance_type in $region ==="
        aa_print_table pricing_stats "Metric" "Value"
    else
        warning "No historical pricing data available for $instance_type in $region"
        return 1
    fi
}

# =============================================================================
# LOAD BALANCER SETUP (SPOT INSTANCE COMPATIBLE)
# =============================================================================

create_application_load_balancer() {
    local stack_name="$1"
    local security_group_id="$2"
    local subnet_ids=("${@:3}")
    
    if [ -z "$stack_name" ] || [ -z "$security_group_id" ] || [ ${#subnet_ids[@]} -eq 0 ]; then
        error "create_application_load_balancer requires stack_name, security_group_id, and subnet_ids parameters"
        return 1
    fi

    local alb_name="${stack_name}-alb"
    log "Creating Application Load Balancer: $alb_name"

    # Check if ALB already exists
    local alb_arn
    alb_arn=$(aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ "$alb_arn" != "None" ] && [ -n "$alb_arn" ]; then
        warning "Load balancer $alb_name already exists: $alb_arn"
        echo "$alb_arn"
        return 0
    fi

    # Create the load balancer
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "$alb_name" \
        --subnets "${subnet_ids[@]}" \
        --security-groups "$security_group_id" \
        --scheme "$ALB_SCHEME" \
        --type "$ALB_TYPE" \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="$alb_name" Key=Stack,Value="$stack_name" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$alb_arn" ] || [ "$alb_arn" = "None" ]; then
        error "Failed to create Application Load Balancer"
        return 1
    fi

    success "Application Load Balancer created: $alb_name"
    
    # Wait for ALB to be active
    log "Waiting for load balancer to be active..."
    aws elbv2 wait load-balancer-available \
        --load-balancer-arns "$alb_arn" \
        --region "$AWS_REGION"

    echo "$alb_arn"
    return 0
}

create_target_group() {
    local stack_name="$1"
    local service_name="$2"
    local port="$3"
    local vpc_id="$4"
    local health_check_path="${5:-/}"
    local health_check_port="${6:-traffic-port}"
    
    if [ -z "$stack_name" ] || [ -z "$service_name" ] || [ -z "$port" ] || [ -z "$vpc_id" ]; then
        error "create_target_group requires stack_name, service_name, port, and vpc_id parameters"
        return 1
    fi

    local tg_name="${stack_name}-${service_name}-tg"
    log "Creating target group: $tg_name"

    # Check if target group already exists
    local tg_arn
    tg_arn=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ "$tg_arn" != "None" ] && [ -n "$tg_arn" ]; then
        warning "Target group $tg_name already exists: $tg_arn"
        echo "$tg_arn"
        return 0
    fi

    # Create target group
    log "Creating target group with improved health check settings for containerized applications..."
    tg_arn=$(aws elbv2 create-target-group \
        --name "$tg_name" \
        --protocol HTTP \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --health-check-protocol HTTP \
        --health-check-path "$health_check_path" \
        --health-check-port "$health_check_port" \
        --health-check-interval-seconds 60 \
        --health-check-timeout-seconds 15 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 5 \
        --target-type instance \
        --tags Key=Name,Value="$tg_name" Key=Stack,Value="$stack_name" Key=Service,Value="$service_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$tg_arn" ] || [ "$tg_arn" = "None" ]; then
        error "Failed to create target group: $tg_name"
        return 1
    fi

    success "Target group created: $tg_name"
    echo "$tg_arn"
    return 0
}

register_instance_with_target_group() {
    local target_group_arn="$1"
    local instance_id="$2"
    local port="$3"
    
    if [ -z "$target_group_arn" ] || [ -z "$instance_id" ] || [ -z "$port" ]; then
        error "register_instance_with_target_group requires target_group_arn, instance_id, and port parameters"
        return 1
    fi

    log "Registering instance $instance_id with target group on port $port..."

    aws elbv2 register-targets \
        --target-group-arn "$target_group_arn" \
        --targets Id="$instance_id",Port="$port" \
        --region "$AWS_REGION"

    if [ $? -eq 0 ]; then
        success "Instance registered with target group"
        
        # Wait for target to be healthy
        log "Waiting for target to be healthy..."
        local max_wait=300
        local elapsed=0
        local check_interval=15
        
        while [ $elapsed -lt $max_wait ]; do
            local target_health
            target_health=$(aws elbv2 describe-target-health \
                --target-group-arn "$target_group_arn" \
                --targets Id="$instance_id",Port="$port" \
                --query 'TargetHealthDescriptions[0].TargetHealth.State' \
                --output text \
                --region "$AWS_REGION")

            case "$target_health" in
                "healthy")
                    success "Target is healthy"
                    return 0
                    ;;
                "unhealthy")
                    warning "Target is unhealthy (${elapsed}s elapsed)"
                    ;;
                "initial"|"draining"|"unused")
                    info "Target health check in progress: $target_health (${elapsed}s elapsed)"
                    ;;
            esac
            
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done
        
        warning "Target health check timed out after ${max_wait}s"
        return 1
    else
        error "Failed to register instance with target group"
        return 1
    fi
}

create_alb_listener() {
    local alb_arn="$1"
    local target_group_arn="$2"
    local port="${3:-80}"
    local protocol="${4:-HTTP}"
    
    if [ -z "$alb_arn" ] || [ -z "$target_group_arn" ]; then
        error "create_alb_listener requires alb_arn and target_group_arn parameters"
        return 1
    fi

    log "Creating ALB listener on port $port..."

    local listener_arn
    listener_arn=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol "$protocol" \
        --port "$port" \
        --default-actions Type=forward,TargetGroupArn="$target_group_arn" \
        --query 'Listeners[0].ListenerArn' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$listener_arn" ] || [ "$listener_arn" = "None" ]; then
        error "Failed to create ALB listener"
        return 1
    fi

    success "ALB listener created on port $port"
    echo "$listener_arn"
    return 0
}

# =============================================================================
# CLOUDFRONT SETUP (SPOT INSTANCE COMPATIBLE)
# =============================================================================

setup_cloudfront_distribution() {
    local stack_name="$1"
    local alb_dns_name="$2"
    local origin_path="${3:-}"
    
    if [ -z "$stack_name" ] || [ -z "$alb_dns_name" ]; then
        error "setup_cloudfront_distribution requires stack_name and alb_dns_name parameters"
        return 1
    fi

    log "Setting up CloudFront distribution for ALB: $alb_dns_name"

    # Validate required parameters
    if [[ -z "$stack_name" ]]; then
        error "Stack name is required for CloudFront setup"
        return 1
    fi
    
    if [[ -z "$alb_dns_name" ]]; then
        error "ALB DNS name is required for CloudFront setup"
        return 1
    fi

    # Set default CloudFront TTL values with proper validation
    local min_ttl="${CLOUDFRONT_MIN_TTL:-0}"
    local default_ttl="${CLOUDFRONT_DEFAULT_TTL:-86400}"
    local max_ttl="${CLOUDFRONT_MAX_TTL:-31536000}"
    local price_class="${CLOUDFRONT_PRICE_CLASS:-PriceClass_100}"
    
    # Validate TTL values are numeric
    if ! [[ "$min_ttl" =~ ^[0-9]+$ ]] || ! [[ "$default_ttl" =~ ^[0-9]+$ ]] || ! [[ "$max_ttl" =~ ^[0-9]+$ ]]; then
        error "CloudFront TTL values must be numeric"
        return 1
    fi
    
    # Sanitize input values to prevent JSON injection
    local sanitized_stack_name
    sanitized_stack_name=$(echo "$stack_name" | tr -cd '[:alnum:]-' | head -c 64)
    local sanitized_alb_dns
    sanitized_alb_dns=$(echo "$alb_dns_name" | tr -cd '[:alnum:].-' | head -c 253)
    
    local caller_ref="${sanitized_stack_name}-$(date +%s)"
    local origin_id="${sanitized_stack_name}-alb-origin"
    
    # Create distribution configuration with validated JSON structure
    local temp_config_file="/tmp/cloudfront-config-${sanitized_stack_name}-$(date +%s).json"
    
    # Generate CloudFront configuration with proper escaping and validation
    cat > "$temp_config_file" << EOF
{
    "CallerReference": "${caller_ref}",
    "Comment": "CloudFront distribution for ${sanitized_stack_name} GeuseMaker",
    "DefaultCacheBehavior": {
        "TargetOriginId": "${origin_id}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {"Forward": "all"},
            "Headers": {
                "Quantity": 1,
                "Items": ["*"]
            }
        },
        "MinTTL": ${min_ttl},
        "DefaultTTL": ${default_ttl},
        "MaxTTL": ${max_ttl},
        "Compress": true,
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        }
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "${origin_id}",
            "DomainName": "${sanitized_alb_dns}",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only",
                "OriginSslProtocols": {
                    "Quantity": 1,
                    "Items": ["TLSv1.2"]
                },
                "OriginReadTimeout": 30,
                "OriginKeepaliveTimeout": 5
            }
        }]
    },
    "Enabled": true,
    "PriceClass": "${price_class}"
}
EOF

    # Validate JSON syntax before using
    if ! python3 -c "import json; json.load(open('$temp_config_file'))" 2>/dev/null; then
        if command -v jq >/dev/null 2>&1; then
            if ! jq . "$temp_config_file" >/dev/null 2>&1; then
                error "Generated CloudFront configuration has invalid JSON syntax"
                rm -f "$temp_config_file"
                return 1
            fi
        else
            warning "Cannot validate JSON syntax (jq not available)"
        fi
    fi

    # Create the distribution using the validated configuration file
    local distribution_id
    distribution_id=$(aws cloudfront create-distribution \
        --distribution-config "file://$temp_config_file" \
        --query 'Distribution.Id' \
        --output text 2>/dev/null)
    
    # Clean up temporary file
    rm -f "$temp_config_file"

    if [ -z "$distribution_id" ] || [ "$distribution_id" = "None" ] || [ "$distribution_id" = "null" ]; then
        error "Failed to create CloudFront distribution"
        # Try to get more detailed error information
        log "Attempting to get detailed error information..."
        aws cloudfront create-distribution \
            --distribution-config "file://$temp_config_file" \
            --region "$AWS_REGION" 2>&1 | head -10 || true
        return 1
    fi

    success "CloudFront distribution created: $distribution_id"
    
    # Get distribution domain name
    local domain_name
    domain_name=$(aws cloudfront get-distribution \
        --id "$distribution_id" \
        --query 'Distribution.DomainName' \
        --output text \
        --region "$AWS_REGION")

    log "CloudFront distribution domain: $domain_name"
    log "Note: Distribution deployment may take 15-20 minutes"

    echo "${distribution_id}:${domain_name}"
    return 0
}

# =============================================================================
# SPOT INSTANCE ALB/CDN INTEGRATION
# =============================================================================

setup_spot_instance_load_balancing() {
    local stack_name="$1"
    local instance_id="$2"
    local vpc_id="$3"
    local subnet_ids=("${@:4}")
    
    if [ -z "$stack_name" ] || [ -z "$instance_id" ] || [ -z "$vpc_id" ] || [ ${#subnet_ids[@]} -eq 0 ]; then
        error "setup_spot_instance_load_balancing requires stack_name, instance_id, vpc_id, and subnet_ids parameters"
        return 1
    fi

    log "Setting up load balancing for spot instance: $instance_id"

    # Create ALB security group
    local alb_sg_name="${stack_name}-alb-sg"
    local alb_sg_id
    alb_sg_id=$(aws ec2 create-security-group \
        --group-name "$alb_sg_name" \
        --description "Security group for ALB" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$alb_sg_id" ] || [ "$alb_sg_id" = "None" ]; then
        error "Failed to create ALB security group"
        return 1
    fi

    # Configure ALB security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$alb_sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"

    aws ec2 authorize-security-group-ingress \
        --group-id "$alb_sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"

    # Tag ALB security group
    aws ec2 create-tags \
        --resources "$alb_sg_id" \
        --tags Key=Name,Value="$alb_sg_name" Key=Stack,Value="$stack_name" \
        --region "$AWS_REGION"

    # Create Application Load Balancer
    local alb_arn
    alb_arn=$(create_application_load_balancer "$stack_name" "$alb_sg_id" "${subnet_ids[@]}")
    
    if [ $? -ne 0 ]; then
        error "Failed to create Application Load Balancer"
        return 1
    fi

    # Get ALB DNS name
    local alb_dns_name
    alb_dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION")

    # Create target groups for each service
    local services=("n8n" "ollama" "qdrant" "crawl4ai")
    local ports=(80 8080 8081 8082)
    local target_groups=()

    for i in "${!services[@]}"; do
        local service="${services[$i]}"
        local port="${ports[$i]}"
        
        local tg_arn
        tg_arn=$(create_target_group "$stack_name" "$service" "$port" "$vpc_id")
        
        if [ $? -eq 0 ]; then
            target_groups+=("$tg_arn")
            
            # Register instance with target group
            register_instance_with_target_group "$tg_arn" "$instance_id" "$port"
            
            # Create ALB listener
            create_alb_listener "$alb_arn" "$tg_arn" "$port"
        else
            warning "Failed to setup target group for $service"
        fi
    done

    success "Load balancing setup complete for spot instance"
    echo "$alb_arn:$alb_dns_name"
    return 0
}

setup_spot_instance_cdn() {
    local stack_name="$1"
    local alb_dns_name="$2"
    
    if [ -z "$stack_name" ] || [ -z "$alb_dns_name" ]; then
        error "setup_spot_instance_cdn requires stack_name and alb_dns_name parameters"
        return 1
    fi

    log "Setting up CloudFront CDN for spot instance ALB: $alb_dns_name"

    # Setup CloudFront distribution
    local cdn_result
    cdn_result=$(setup_cloudfront_distribution "$stack_name" "$alb_dns_name")
    
    if [ $? -ne 0 ]; then
        error "Failed to setup CloudFront distribution"
        return 1
    fi

    local distribution_id="${cdn_result%:*}"
    local domain_name="${cdn_result#*:}"

    success "CloudFront CDN setup complete for spot instance"
    echo "$distribution_id:$domain_name"
    return 0
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_alb_dns_name() {
    local alb_arn="$1"
    
    if [ -z "$alb_arn" ]; then
        error "get_alb_dns_name requires alb_arn parameter"
        return 1
    fi

    local dns_name
    dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$dns_name" ] || [ "$dns_name" = "None" ]; then
        error "Failed to get ALB DNS name"
        return 1
    fi

    echo "$dns_name"
    return 0
}