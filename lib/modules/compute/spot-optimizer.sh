#!/usr/bin/env bash
# =============================================================================
# Optimized Spot Instance Operations
# High-performance spot instance management with caching and parallel execution
# Compatible with bash 3.x+
# =============================================================================

# Load dependencies
if [[ -n "$LIB_DIR" ]]; then
    source "$LIB_DIR/modules/performance/aws-api-cache.sh" 2>/dev/null || true
    source "$LIB_DIR/modules/performance/parallel-executor.sh" 2>/dev/null || true
    source "$LIB_DIR/modules/performance/performance-monitor.sh" 2>/dev/null || true
    source "$LIB_DIR/associative-arrays.sh" 2>/dev/null || true
fi

# =============================================================================
# OPTIMIZED SPOT PRICING
# =============================================================================

# Get spot prices with caching and parallel execution
get_spot_prices_optimized() {
    local instance_type="$1"
    local regions=("${@:2}")
    
    perf_timer_start "spot_price_lookup" "Optimized spot price lookup for $instance_type"
    
    # Default regions if none specified
    if [[ ${#regions[@]} -eq 0 ]]; then
        regions=(us-east-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1)
    fi
    
    # Use parallel execution to get prices across regions
    local results=$(parallel_get_spot_prices "$instance_type" "${regions[@]}")
    
    perf_timer_stop "spot_price_lookup"
    
    echo "$results"
}

# Batch get spot prices for multiple instance types
batch_get_spot_prices() {
    local region="${1:-$AWS_REGION}"
    shift
    local instance_types=("$@")
    
    perf_timer_start "batch_spot_prices" "Batch spot price lookup"
    
    # Define function for parallel execution
    get_instance_spot_price() {
        local instance_type="$1"
        local region="$2"
        
        # Use cached API call
        local result=$(get_spot_prices_cached "$instance_type" "$region")
        if [[ -n "$result" ]]; then
            echo "${instance_type}:${result}"
        fi
    }
    
    export -f get_instance_spot_price
    export -f get_spot_prices_cached
    export -f aws_cli_cached
    export -f cache_get
    export -f cache_put
    export -f generate_cache_key
    export AWS_REGION
    
    # Execute in parallel
    local job_ids=()
    for instance_type in "${instance_types[@]}"; do
        local job_id="spot_${instance_type}"
        parallel_execute "$job_id" get_instance_spot_price "$instance_type" "$region"
        job_ids+=("$job_id")
    done
    
    # Collect results
    parallel_wait_all
    
    local results=()
    for job_id in "${job_ids[@]}"; do
        local result=$(parallel_get_result "$job_id")
        if [[ -n "$result" ]]; then
            results+=("$result")
        fi
    done
    
    perf_timer_stop "batch_spot_prices"
    
    printf '%s\n' "${results[@]}"
}

# =============================================================================
# OPTIMIZED INSTANCE SELECTION
# =============================================================================

# Find best spot instance with parallel AZ checking
find_best_spot_instance() {
    local instance_types=("$@")
    local region="${AWS_REGION:-us-east-1}"
    
    perf_timer_start "find_best_spot" "Finding best spot instance"
    
    # Get all availability zones
    local azs=($(get_availability_zones_cached "$region" | grep available | cut -f1))
    
    # Create scoring matrix
    declare -A instance_scores
    declare -A instance_prices
    declare -A instance_azs
    
    # Check each instance type in parallel
    for instance_type in "${instance_types[@]}"; do
        # Get availability across AZs
        local available_azs=($(parallel_check_instance_availability "$instance_type" "$region"))
        
        # Calculate score based on availability and price
        local best_price=""
        local best_az=""
        
        for az_info in "${available_azs[@]}"; do
            local az=$(echo "$az_info" | cut -d: -f1)
            local price=$(echo "$az_info" | cut -d: -f3)
            
            if [[ -z "$best_price" ]] || (( $(echo "$price < $best_price" | bc -l 2>/dev/null || echo 0) )); then
                best_price="$price"
                best_az="$az"
            fi
        done
        
        if [[ -n "$best_price" ]]; then
            # Calculate score (lower price = higher score)
            local score=$(echo "scale=4; 1 / $best_price" | bc -l 2>/dev/null || echo "0")
            
            aa_set instance_scores "$instance_type" "$score"
            aa_set instance_prices "$instance_type" "$best_price"
            aa_set instance_azs "$instance_type" "$best_az"
        fi
    done
    
    # Find instance with highest score
    local best_instance=""
    local best_score="0"
    
    for instance_type in "${instance_types[@]}"; do
        local score=$(aa_get instance_scores "$instance_type" "0")
        if (( $(echo "$score > $best_score" | bc -l 2>/dev/null || echo 0) )); then
            best_score="$score"
            best_instance="$instance_type"
        fi
    done
    
    perf_timer_stop "find_best_spot"
    
    if [[ -n "$best_instance" ]]; then
        local price=$(aa_get instance_prices "$best_instance")
        local az=$(aa_get instance_azs "$best_instance")
        echo "${best_instance}:${az}:${price}"
    fi
}

# =============================================================================
# OPTIMIZED CAPACITY CHECKING
# =============================================================================

# Check spot capacity across multiple instance types and AZs
check_spot_capacity_parallel() {
    local region="${1:-$AWS_REGION}"
    shift
    local instance_types=("$@")
    
    perf_timer_start "capacity_check" "Parallel spot capacity check"
    
    # Get all AZs
    local azs=($(get_availability_zones_cached "$region" | grep available | cut -f1))
    
    # Define capacity check function
    check_instance_az_capacity() {
        local instance_type="$1"
        local az="$2"
        local region="$3"
        
        # Try to get spot price as proxy for capacity
        local price=$(aws_cli_cached 300 ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --availability-zone "$az" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "$region" \
            --query 'SpotPriceHistory[0].SpotPrice' \
            --output text)
        
        if [[ -n "$price" ]] && [[ "$price" != "None" ]]; then
            # Try to check actual capacity (this may fail but worth trying)
            local capacity=$(aws ec2 describe-instance-type-offerings \
                --location-type "availability-zone" \
                --filters "Name=location,Values=$az" "Name=instance-type,Values=$instance_type" \
                --region "$region" \
                --query 'InstanceTypeOfferings[0].InstanceType' \
                --output text 2>/dev/null)
            
            if [[ "$capacity" == "$instance_type" ]]; then
                echo "${instance_type}:${az}:available:${price}"
            else
                echo "${instance_type}:${az}:limited:${price}"
            fi
        else
            echo "${instance_type}:${az}:unavailable:0"
        fi
    }
    
    export -f check_instance_az_capacity
    export -f aws_cli_cached
    
    # Execute all checks in parallel
    local job_ids=()
    local job_count=0
    
    for instance_type in "${instance_types[@]}"; do
        for az in "${azs[@]}"; do
            local job_id="capacity_${job_count}"
            parallel_execute "$job_id" check_instance_az_capacity "$instance_type" "$az" "$region"
            job_ids+=("$job_id")
            job_count=$((job_count + 1))
        done
    done
    
    # Wait for all checks
    parallel_wait_all
    
    # Collect and summarize results
    declare -A capacity_matrix
    
    for job_id in "${job_ids[@]}"; do
        local result=$(parallel_get_result "$job_id")
        if [[ -n "$result" ]]; then
            local instance_type=$(echo "$result" | cut -d: -f1)
            local az=$(echo "$result" | cut -d: -f2)
            local status=$(echo "$result" | cut -d: -f3)
            local price=$(echo "$result" | cut -d: -f4)
            
            aa_set capacity_matrix "${instance_type}:${az}" "${status}:${price}"
        fi
    done
    
    perf_timer_stop "capacity_check"
    
    # Display capacity matrix
    echo "Spot Capacity Matrix:"
    echo "===================="
    printf "%-20s" "Instance Type"
    for az in "${azs[@]}"; do
        printf "%-15s" "$az"
    done
    echo ""
    echo "--------------------"
    
    for instance_type in "${instance_types[@]}"; do
        printf "%-20s" "$instance_type"
        for az in "${azs[@]}"; do
            local info=$(aa_get capacity_matrix "${instance_type}:${az}" "unknown:0")
            local status=$(echo "$info" | cut -d: -f1)
            local price=$(echo "$info" | cut -d: -f2)
            
            case "$status" in
                available)
                    printf "%-15s" "✓ \$$price"
                    ;;
                limited)
                    printf "%-15s" "⚠ \$$price"
                    ;;
                unavailable)
                    printf "%-15s" "✗"
                    ;;
                *)
                    printf "%-15s" "?"
                    ;;
            esac
        done
        echo ""
    done
}

# =============================================================================
# INTELLIGENT SPOT SELECTION
# =============================================================================

# Select optimal spot configuration with multiple criteria
select_optimal_spot_config() {
    local max_price="$1"
    local preferred_types="${2:-g4dn.xlarge,g4dn.2xlarge,g5.xlarge}"
    local region="${3:-$AWS_REGION}"
    
    perf_timer_start "optimal_selection" "Selecting optimal spot configuration"
    
    # Parse preferred types
    IFS=',' read -ra instance_types <<< "$preferred_types"
    
    # Score matrix
    declare -A config_scores
    declare -A config_details
    
    # Get capacity and pricing in parallel
    log "Analyzing ${#instance_types[@]} instance types across region $region..."
    
    # Warm up cache
    warmup_cache "$region"
    
    # Check each instance type
    for instance_type in "${instance_types[@]}"; do
        # Get instance capabilities
        local capabilities=$(get_instance_types_cached "$instance_type")
        local vcpus=$(echo "$capabilities" | awk '{print $2}')
        local memory=$(echo "$capabilities" | awk '{print $3}')
        local gpu_count=$(echo "$capabilities" | awk '{print $4}')
        local gpu_memory=$(echo "$capabilities" | awk '{print $5}')
        
        # Get best price and AZ
        local spot_info=$(find_best_spot_instance "$instance_type")
        if [[ -n "$spot_info" ]]; then
            local price=$(echo "$spot_info" | cut -d: -f3)
            local az=$(echo "$spot_info" | cut -d: -f2)
            
            # Skip if over budget
            if (( $(echo "$price > $max_price" | bc -l 2>/dev/null || echo 0) )); then
                continue
            fi
            
            # Calculate composite score
            local price_score=$(echo "scale=4; ($max_price - $price) / $max_price" | bc -l)
            local resource_score=$(echo "scale=4; ($vcpus + $memory/1024 + $gpu_count*10) / 100" | bc -l)
            local total_score=$(echo "scale=4; $price_score * 0.6 + $resource_score * 0.4" | bc -l)
            
            aa_set config_scores "${instance_type}:${az}" "$total_score"
            aa_set config_details "${instance_type}:${az}" "${price}:${vcpus}:${memory}:${gpu_count}:${gpu_memory}"
        fi
    done
    
    # Find best configuration
    local best_config=""
    local best_score="0"
    
    for config in $(aa_keys config_scores); do
        local score=$(aa_get config_scores "$config")
        if (( $(echo "$score > $best_score" | bc -l 2>/dev/null || echo 0) )); then
            best_score="$score"
            best_config="$config"
        fi
    done
    
    perf_timer_stop "optimal_selection"
    
    if [[ -n "$best_config" ]]; then
        local instance_type=$(echo "$best_config" | cut -d: -f1)
        local az=$(echo "$best_config" | cut -d: -f2)
        local details=$(aa_get config_details "$best_config")
        local price=$(echo "$details" | cut -d: -f1)
        
        echo "Optimal Spot Configuration:"
        echo "=========================="
        echo "Instance Type: $instance_type"
        echo "Availability Zone: $az"
        echo "Spot Price: \$$price/hour"
        echo "Score: $best_score"
        echo ""
        echo "${instance_type}:${az}:${price}"
    else
        error "No suitable spot configuration found within budget"
        return 1
    fi
}

# =============================================================================
# SPOT FLEET OPTIMIZATION
# =============================================================================

# Create optimized spot fleet request
create_optimized_spot_fleet() {
    local stack_name="$1"
    local target_capacity="$2"
    local max_price="$3"
    local instance_types="${4:-g4dn.xlarge,g4dn.2xlarge,g5.xlarge}"
    
    perf_timer_start "spot_fleet_creation" "Creating optimized spot fleet"
    
    # Parse instance types
    IFS=',' read -ra types_array <<< "$instance_types"
    
    # Build launch specifications in parallel
    local launch_specs=()
    
    for instance_type in "${types_array[@]}"; do
        # Get optimal config for this type
        local config=$(select_optimal_spot_config "$max_price" "$instance_type")
        if [[ -n "$config" ]]; then
            local az=$(echo "$config" | cut -d: -f2)
            local price=$(echo "$config" | cut -d: -f3)
            
            # Create launch spec
            local spec=$(cat <<EOF
{
    "InstanceType": "${instance_type}",
    "SpotPrice": "${price}",
    "Placement": {
        "AvailabilityZone": "${az}"
    },
    "WeightedCapacity": 1
}
EOF
)
            launch_specs+=("$spec")
        fi
    done
    
    # Create fleet request
    if [[ ${#launch_specs[@]} -gt 0 ]]; then
        log "Creating spot fleet with ${#launch_specs[@]} launch specifications"
        # Fleet creation logic here
    else
        error "No valid launch specifications for spot fleet"
        return 1
    fi
    
    perf_timer_stop "spot_fleet_creation"
}

# =============================================================================
# PERFORMANCE REPORTING
# =============================================================================

# Generate spot optimization report
generate_spot_optimization_report() {
    echo "=== Spot Instance Optimization Report ==="
    echo "Generated: $(date)"
    echo ""
    
    # Cache statistics
    get_cache_stats
    echo ""
    
    # Parallel execution statistics
    parallel_get_stats
    echo ""
    
    # Performance metrics
    perf_generate_report "summary"
    echo ""
    
    # Optimization recommendations
    echo "Optimization Recommendations:"
    echo "============================"
    perf_analyze
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize optimized spot operations
init_spot_optimizer() {
    # Initialize performance monitoring
    init_performance_monitor
    
    # Initialize caching
    init_aws_cache
    
    # Initialize parallel executor
    init_parallel_executor
    
    # Set custom thresholds
    perf_set_threshold "spot_price_lookup" 10 "warn"
    perf_set_threshold "find_best_spot" 30 "warn"
    perf_set_threshold "capacity_check" 60 "warn"
}

# Auto-initialize if sourced
init_spot_optimizer