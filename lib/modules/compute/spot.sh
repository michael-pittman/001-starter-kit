#!/usr/bin/env bash
# =============================================================================
# Compute Spot Module
# Spot instance pricing, optimization, and management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_SPOT_SH_LOADED:-}" ] && return 0
_COMPUTE_SPOT_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/ami.sh"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# SPOT PRICING CONFIGURATION
# =============================================================================

# Pricing cache configuration
readonly SPOT_PRICE_CACHE_TTL="${SPOT_PRICE_CACHE_TTL:-3600}"  # 1 hour
readonly SPOT_PRICE_CACHE_FILE="${SPOT_PRICE_CACHE_FILE:-/tmp/geusemaker-spot-cache.json}"

# Spot pricing fallbacks (rough estimates)
declare -A SPOT_PRICE_FALLBACKS=(
    ["g4dn.xlarge"]="0.21"
    ["g4dn.large"]="0.13"
    ["g4dn.2xlarge"]="0.42"
    ["g5.xlarge"]="0.18"
    ["g5.large"]="0.11"
    ["t3.micro"]="0.003"
    ["t3.small"]="0.006"
    ["t3.medium"]="0.012"
    ["t3.large"]="0.025"
    ["t3.xlarge"]="0.050"
    ["m5.large"]="0.030"
    ["m5.xlarge"]="0.060"
)

# On-demand pricing (for savings calculations)
declare -A ONDEMAND_PRICES=(
    ["g4dn.xlarge"]="0.834"
    ["g4dn.large"]="0.526"
    ["g4dn.2xlarge"]="1.668"
    ["g5.xlarge"]="2.012"
    ["g5.large"]="1.006"
    ["t3.micro"]="0.0116"
    ["t3.small"]="0.0232"
    ["t3.medium"]="0.0464"
    ["t3.large"]="0.0928"
    ["t3.xlarge"]="0.1856"
    ["m5.large"]="0.108"
    ["m5.xlarge"]="0.216"
)

# =============================================================================
# SPOT PRICE CACHE
# =============================================================================

# Initialize spot price cache
init_spot_cache() {
    if [ ! -f "$SPOT_PRICE_CACHE_FILE" ]; then
        echo '{}' > "$SPOT_PRICE_CACHE_FILE"
    fi
}

# Get cached spot price
get_cached_spot_price() {
    local cache_key="$1"
    
    init_spot_cache
    
    # Check if cache entry exists and is not expired
    local cache_entry
    cache_entry=$(jq -r --arg key "$cache_key" '.[$key] // empty' "$SPOT_PRICE_CACHE_FILE")
    
    if [ -n "$cache_entry" ]; then
        local cached_time=$(echo "$cache_entry" | jq -r '.timestamp')
        local cached_price=$(echo "$cache_entry" | jq -r '.price')
        local current_time=$(date +%s)
        
        if [ $((current_time - cached_time)) -lt "$SPOT_PRICE_CACHE_TTL" ]; then
            log_debug "Using cached spot price: \$$cached_price" "SPOT"
            echo "$cached_price"
            return 0
        fi
    fi
    
    return 1
}

# Cache spot price
cache_spot_price() {
    local cache_key="$1"
    local price="$2"
    
    init_spot_cache
    
    local temp_file=$(mktemp)
    jq --arg key "$cache_key" \
       --arg price "$price" \
       --arg ts "$(date +%s)" \
       '.[$key] = {price: $price, timestamp: ($ts | tonumber)}' \
       "$SPOT_PRICE_CACHE_FILE" > "$temp_file" && \
    mv "$temp_file" "$SPOT_PRICE_CACHE_FILE"
}

# =============================================================================
# SPOT PRICING ANALYSIS
# =============================================================================

# Get current spot price
get_spot_price() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    local availability_zone="${3:-}"
    
    # Check cache first
    local cache_key="${region}:${instance_type}:${availability_zone:-all}"
    local cached_price
    cached_price=$(get_cached_spot_price "$cache_key") && {
        echo "$cached_price"
        return 0
    }
    
    log_info "Fetching spot price for $instance_type in $region" "SPOT"
    
    # Build AWS CLI query
    local filters="--instance-types $instance_type --product-descriptions Linux/UNIX"
    [ -n "$availability_zone" ] && filters="$filters --availability-zone $availability_zone"
    
    local spot_price
    spot_price=$(aws ec2 describe-spot-price-history \
        --region "$region" \
        $filters \
        --max-results 1 \
        --query 'SpotPriceHistory[0].SpotPrice' \
        --output text 2>/dev/null)
    
    if [ -n "$spot_price" ] && [ "$spot_price" != "None" ]; then
        # Cache the price
        cache_spot_price "$cache_key" "$spot_price"
        echo "$spot_price"
        return 0
    else
        # Use fallback price
        local fallback_price="${SPOT_PRICE_FALLBACKS[$instance_type]:-0.10}"
        log_warn "No spot price available, using fallback: \$$fallback_price" "SPOT"
        echo "$fallback_price"
        return 1
    fi
}

# Analyze spot pricing across availability zones
analyze_spot_pricing_zones() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    log_info "Analyzing spot pricing across AZs for $instance_type" "SPOT"
    
    # Get all AZs in region
    local azs
    azs=$(aws ec2 describe-availability-zones \
        --region "$region" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text 2>/dev/null)
    
    if [ -z "$azs" ]; then
        log_error "Failed to get availability zones" "SPOT"
        return 1
    fi
    
    local best_az=""
    local best_price=""
    local pricing_data=()
    
    # Check each AZ
    for az in $azs; do
        local price
        price=$(get_spot_price "$instance_type" "$region" "$az" 2>/dev/null || echo "")
        
        if [ -n "$price" ]; then
            pricing_data+=("{\"zone\": \"$az\", \"price\": \"$price\"}")
            
            if [ -z "$best_price" ] || (( $(echo "$price < $best_price" | bc -l 2>/dev/null || echo 0) )); then
                best_az="$az"
                best_price="$price"
            fi
            
            log_info "Spot price in $az: \$$price/hour" "SPOT"
        fi
    done
    
    # Return results as JSON
    cat <<EOF
{
    "instance_type": "$instance_type",
    "region": "$region",
    "best_zone": "$best_az",
    "best_price": "$best_price",
    "zones": [$(IFS=,; echo "${pricing_data[*]}")]
}
EOF
}

# Get spot price history
get_spot_price_history() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    local hours="${3:-24}"
    
    log_info "Getting $hours hours spot price history for $instance_type" "SPOT"
    
    local start_time=$(date -u -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S)
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    
    aws ec2 describe-spot-price-history \
        --region "$region" \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --query 'SpotPriceHistory[].{
            Timestamp: Timestamp,
            Price: SpotPrice,
            AvailabilityZone: AvailabilityZone
        }' \
        --output json 2>/dev/null || echo "[]"
}

# =============================================================================
# SPOT INSTANCE RECOMMENDATIONS
# =============================================================================

# Get optimal spot configuration
get_optimal_spot_config() {
    local instance_type="$1"
    local max_price="${2:-}"
    local region="${3:-$AWS_REGION}"
    
    log_info "Finding optimal spot configuration for $instance_type" "SPOT"
    
    # Analyze pricing across zones
    local pricing_analysis
    pricing_analysis=$(analyze_spot_pricing_zones "$instance_type" "$region")
    
    local best_zone=$(echo "$pricing_analysis" | jq -r '.best_zone')
    local best_price=$(echo "$pricing_analysis" | jq -r '.best_price')
    
    # Get on-demand price for comparison
    local ondemand_price="${ONDEMAND_PRICES[$instance_type]:-1.00}"
    
    # Calculate recommended max price (current + 20% buffer)
    if [ -z "$max_price" ]; then
        max_price=$(echo "scale=4; $best_price * 1.2" | bc -l 2>/dev/null || echo "$best_price")
    fi
    
    # Check if price is acceptable
    local recommended=true
    local reason=""
    
    if (( $(echo "$best_price > $ondemand_price" | bc -l 2>/dev/null || echo 0) )); then
        recommended=false
        reason="Spot price exceeds on-demand price"
    elif [ -n "$max_price" ] && (( $(echo "$best_price > $max_price" | bc -l 2>/dev/null || echo 0) )); then
        recommended=false
        reason="Spot price exceeds maximum budget"
    fi
    
    # Calculate savings
    local savings_percent=$(echo "scale=2; (($ondemand_price - $best_price) / $ondemand_price) * 100" | bc -l 2>/dev/null || echo "0")
    
    # Build recommendation
    cat <<EOF
{
    "instance_type": "$instance_type",
    "availability_zone": "$best_zone",
    "current_price": "$best_price",
    "recommended_max_price": "$max_price",
    "ondemand_price": "$ondemand_price",
    "savings_percent": "$savings_percent",
    "recommended": $recommended,
    "reason": "$reason",
    "pricing_analysis": $pricing_analysis
}
EOF
}

# Suggest alternative spot instance types
suggest_spot_alternatives() {
    local instance_type="$1"
    local max_price="$2"
    local region="${3:-$AWS_REGION}"
    
    log_info "Finding alternative instance types within budget: \$$max_price" "SPOT"
    
    # Get fallback types
    local alternatives=$(get_instance_type_fallbacks "$instance_type")
    
    # Add similar instance types
    local family=$(get_instance_family "$instance_type")
    case "$family" in
        g4dn|g5)
            alternatives="$alternatives g4dn.xlarge g4dn.2xlarge g5.xlarge g5.2xlarge"
            ;;
        t3)
            alternatives="$alternatives t3.medium t3.large t3.xlarge t3a.medium t3a.large"
            ;;
        m5)
            alternatives="$alternatives m5.large m5.xlarge m5.2xlarge m5a.large m5a.xlarge"
            ;;
    esac
    
    # Remove duplicates and original type
    alternatives=$(echo "$alternatives" | tr ' ' '\n' | sort -u | grep -v "^$instance_type$" | tr '\n' ' ')
    
    local suggestions=()
    
    for alt_type in $alternatives; do
        # Check if instance type is available
        if check_instance_type_availability "$alt_type" "$region" 2>/dev/null; then
            local price
            price=$(get_spot_price "$alt_type" "$region" 2>/dev/null || echo "")
            
            if [ -n "$price" ] && (( $(echo "$price <= $max_price" | bc -l 2>/dev/null || echo 0) )); then
                local ondemand="${ONDEMAND_PRICES[$alt_type]:-1.00}"
                local savings=$(echo "scale=2; (($ondemand - $price) / $ondemand) * 100" | bc -l 2>/dev/null || echo "0")
                
                suggestions+=("{
                    \"instance_type\": \"$alt_type\",
                    \"spot_price\": \"$price\",
                    \"ondemand_price\": \"$ondemand\",
                    \"savings_percent\": \"$savings\"
                }")
            fi
        fi
    done
    
    # Sort by price and return
    if [ ${#suggestions[@]} -gt 0 ]; then
        echo "[$(IFS=,; echo "${suggestions[*]}")] | sort_by(.spot_price | tonumber)" | jq '.'
    else
        echo "[]"
    fi
}

# =============================================================================
# SPOT REQUEST MANAGEMENT
# =============================================================================

# Create spot instance request
create_spot_request() {
    local config="$1"
    local max_price="$2"
    local request_type="${3:-one-time}"  # one-time or persistent
    
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local stack_name=$(echo "$config" | jq -r '.stack_name')
    
    log_info "Creating $request_type spot request for $instance_type at max \$$max_price/hour" "SPOT"
    
    # Build launch specification from config
    local launch_spec
    launch_spec=$(build_launch_specification "$config") || return 1
    
    # Create spot request
    local request_result
    request_result=$(aws ec2 request-spot-instances \
        --spot-price "$max_price" \
        --type "$request_type" \
        --instance-interruption-behavior "terminate" \
        --launch-specification "$launch_spec" \
        --query 'SpotInstanceRequests[0].{
            RequestId: SpotInstanceRequestId,
            State: State,
            Status: Status.Code
        }' \
        --output json 2>&1) || {
        
        log_error "Failed to create spot request: $request_result" "SPOT"
        return 1
    }
    
    local request_id=$(echo "$request_result" | jq -r '.RequestId')
    
    if [ -z "$request_id" ] || [ "$request_id" = "null" ]; then
        log_error "Failed to extract spot request ID" "SPOT"
        return 1
    fi
    
    log_info "Spot request created: $request_id" "SPOT"
    
    # Register spot request
    register_resource "spot_requests" "$request_id" \
        "{\"type\": \"$request_type\", \"max_price\": \"$max_price\", \"stack\": \"$stack_name\"}"
    
    echo "$request_id"
}

# Monitor spot request status
monitor_spot_request() {
    local request_id="$1"
    local timeout="${2:-300}"  # 5 minutes default
    
    log_info "Monitoring spot request: $request_id" "SPOT"
    
    local start_time=$(date +%s)
    local last_status=""
    
    while true; do
        local request_info
        request_info=$(aws ec2 describe-spot-instance-requests \
            --spot-instance-request-ids "$request_id" \
            --query 'SpotInstanceRequests[0].{
                State: State,
                Status: Status.Code,
                Message: Status.Message,
                InstanceId: InstanceId
            }' \
            --output json 2>/dev/null || echo "{}")
        
        local state=$(echo "$request_info" | jq -r '.State // "unknown"')
        local status=$(echo "$request_info" | jq -r '.Status // "unknown"')
        local message=$(echo "$request_info" | jq -r '.Message // ""')
        
        # Log status changes
        if [ "$status" != "$last_status" ]; then
            log_info "Spot request status: $state/$status - $message" "SPOT"
            last_status="$status"
        fi
        
        case "$state" in
            "active")
                local instance_id=$(echo "$request_info" | jq -r '.InstanceId // empty')
                if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
                    log_info "Spot instance fulfilled: $instance_id" "SPOT"
                    echo "$instance_id"
                    return 0
                fi
                ;;
            "failed"|"cancelled"|"closed")
                log_error "Spot request failed: $state - $message" "SPOT"
                return 1
                ;;
        esac
        
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for spot fulfillment" "SPOT"
            return 1
        fi
        
        sleep 10
    done
}

# Cancel spot request
cancel_spot_request() {
    local request_id="$1"
    
    log_info "Cancelling spot request: $request_id" "SPOT"
    
    aws ec2 cancel-spot-instance-requests \
        --spot-instance-request-ids "$request_id" \
        --output json >/dev/null 2>&1 || {
        log_error "Failed to cancel spot request" "SPOT"
        return 1
    }
    
    # Unregister request
    unregister_resource "spot_requests" "$request_id"
    
    log_info "Spot request cancelled" "SPOT"
}

# =============================================================================
# SPOT INSTANCE INTERRUPTION HANDLING
# =============================================================================

# Setup spot instance interruption handler
setup_spot_interruption_handler() {
    local instance_id="$1"
    local handler_script="${2:-/usr/local/bin/spot-interrupt-handler.sh}"
    
    log_info "Setting up spot interruption handler for $instance_id" "SPOT"
    
    # Create handler script
    cat > "$handler_script" <<'EOF'
#!/usr/bin/env bash
# Spot instance interruption handler

# Check for interruption notice
check_interruption() {
    local notice=$(curl -s -m 5 http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null)
    
    if [ -n "$notice" ] && [ "$notice" != "404 - Not Found" ]; then
        echo "SPOT INTERRUPTION NOTICE: $notice"
        
        # Extract termination time
        local termination_time=$(echo "$notice" | jq -r '.time // empty' 2>/dev/null)
        
        if [ -n "$termination_time" ]; then
            echo "Instance will be terminated at: $termination_time"
            
            # Trigger graceful shutdown actions
            handle_interruption
        fi
        
        return 0
    fi
    
    return 1
}

# Handle interruption
handle_interruption() {
    echo "Handling spot instance interruption..."
    
    # Stop services gracefully
    systemctl stop docker || true
    
    # Sync data to persistent storage
    sync
    
    # Send notification (customize as needed)
    # aws sns publish --topic-arn $SNS_TOPIC --message "Spot instance terminating: $(hostname)"
    
    echo "Interruption handling complete"
}

# Monitor loop
while true; do
    if check_interruption; then
        exit 0
    fi
    sleep 5
done
EOF
    
    chmod +x "$handler_script"
    
    # Create systemd service
    cat > /etc/systemd/system/spot-interrupt-handler.service <<EOF
[Unit]
Description=Spot Instance Interruption Handler
After=network.target

[Service]
Type=simple
ExecStart=$handler_script
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable spot-interrupt-handler
    systemctl start spot-interrupt-handler
    
    log_info "Spot interruption handler installed" "SPOT"
}

# =============================================================================
# SPOT FLEET MANAGEMENT
# =============================================================================

# Create spot fleet request
create_spot_fleet() {
    local fleet_config="$1"
    
    log_info "Creating spot fleet request" "SPOT"
    
    # Create fleet request
    local fleet_id
    fleet_id=$(aws ec2 create-fleet \
        --cli-input-json "$fleet_config" \
        --query 'FleetId' \
        --output text 2>&1) || {
        
        log_error "Failed to create spot fleet: $fleet_id" "SPOT"
        return 1
    }
    
    log_info "Spot fleet created: $fleet_id" "SPOT"
    
    # Register fleet
    register_resource "spot_fleets" "$fleet_id"
    
    echo "$fleet_id"
}

# =============================================================================
# COST ANALYSIS
# =============================================================================

# Calculate spot instance savings
calculate_spot_savings() {
    local instance_type="$1"
    local hours="${2:-24}"
    local spot_price="${3:-}"
    
    # Get spot price if not provided
    if [ -z "$spot_price" ]; then
        spot_price=$(get_spot_price "$instance_type") || return 1
    fi
    
    # Get on-demand price
    local ondemand_price="${ONDEMAND_PRICES[$instance_type]:-1.00}"
    
    # Calculate costs
    local spot_cost=$(echo "scale=2; $spot_price * $hours" | bc -l 2>/dev/null || echo "0")
    local ondemand_cost=$(echo "scale=2; $ondemand_price * $hours" | bc -l 2>/dev/null || echo "0")
    local savings=$(echo "scale=2; $ondemand_cost - $spot_cost" | bc -l 2>/dev/null || echo "0")
    local savings_percent=$(echo "scale=2; ($savings / $ondemand_cost) * 100" | bc -l 2>/dev/null || echo "0")
    
    cat <<EOF
{
    "instance_type": "$instance_type",
    "hours": $hours,
    "spot_price_per_hour": "$spot_price",
    "ondemand_price_per_hour": "$ondemand_price",
    "spot_total_cost": "$spot_cost",
    "ondemand_total_cost": "$ondemand_cost",
    "total_savings": "$savings",
    "savings_percentage": "$savings_percent"
}
EOF
}

# Get spot usage report
get_spot_usage_report() {
    local stack_name="${1:-}"
    local days="${2:-7}"
    
    log_info "Generating spot usage report for last $days days" "SPOT"
    
    local start_date=$(date -u -d "$days days ago" +%Y-%m-%d)
    local end_date=$(date -u +%Y-%m-%d)
    
    # Get spot instance usage
    local filters="Name=instance-lifecycle,Values=spot"
    [ -n "$stack_name" ] && filters="$filters Name=tag:Stack,Values=$stack_name"
    
    aws ce get-cost-and-usage \
        --time-period "Start=$start_date,End=$end_date" \
        --granularity DAILY \
        --metrics UnblendedCost UsageQuantity \
        --filter "{
            \"And\": [
                {\"Dimensions\": {\"Key\": \"SERVICE\", \"Values\": [\"Amazon Elastic Compute Cloud - Compute\"]}},
                {\"Dimensions\": {\"Key\": \"USAGE_TYPE_GROUP\", \"Values\": [\"EC2: Running Hours\"]}}
            ]
        }" \
        --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
        --output json 2>/dev/null || echo "{}"
}