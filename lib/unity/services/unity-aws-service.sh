#!/bin/bash
# Unity AWS Service - Unified interface for all AWS operations
# Consolidates EC2, VPC, ALB, CloudFront, EFS, cost optimization, and quota management

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source required dependencies
source "$PROJECT_ROOT/lib/utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Initialize with required core modules
initialize_script "unity-aws-service" \
    "config/variables" \
    "core/registry" \
    "core/errors" \
    "core/logging" \
    "performance/aws-api-cache"

# Service metadata
UNITY_AWS_SERVICE_VERSION="1.0.0"
UNITY_AWS_SERVICE_NAME="unity-aws-service"

# Service state tracking - bash 3 compatible
declare -A UNITY_AWS_RESOURCES 2>/dev/null || UNITY_AWS_RESOURCES=()
declare -A UNITY_AWS_COSTS 2>/dev/null || UNITY_AWS_COSTS=()
declare -A UNITY_AWS_QUOTAS 2>/dev/null || UNITY_AWS_QUOTAS=()
declare -A UNITY_AWS_CACHE 2>/dev/null || UNITY_AWS_CACHE=()

# Initialize service registries
init_unity_aws_service() {
    local service_name="${1:-unity-aws}"
    log_info "Initializing Unity AWS Service v$UNITY_AWS_SERVICE_VERSION"
    
    # Initialize enhanced event system integration
    _init_aws_service_events
    
    # Register service with Unity registry if available
    if command -v register_unity_service >/dev/null 2>&1; then
        register_unity_service "$service_name" "aws" "$UNITY_AWS_SERVICE_VERSION"
    fi
    
    # Initialize resource tracking
    UNITY_AWS_RESOURCES=()
    UNITY_AWS_COSTS=()
    UNITY_AWS_QUOTAS=()
    UNITY_AWS_CACHE=()
    
    # Initialize caching system
    init_aws_api_cache
    
    # Emit service startup event
    _emit_aws_event "system.startup" "unity-aws-service" "{\"component\":\"unity-aws-service\",\"version\":\"$UNITY_AWS_SERVICE_VERSION\",\"startup_time\":$(date +%s)}" "medium"
    
    return 0
}

#############################################
# EC2 Operations (Spot, On-Demand, ASG)
#############################################

# Unified EC2 instance launcher
launch_ec2_instance() {
    local instance_type="${1}"
    local deployment_type="${2:-spot}"  # spot, on-demand, or asg
    local stack_name="${3}"
    local options="${4:-}"
    
    log_info "Launching EC2 instance: type=$instance_type, deployment=$deployment_type"
    
    # Check quotas first
    check_ec2_quota "$instance_type" || return 1
    
    case "$deployment_type" in
        spot)
            launch_spot_instance "$instance_type" "$stack_name" "$options"
            ;;
        on-demand)
            launch_ondemand_instance "$instance_type" "$stack_name" "$options"
            ;;
        asg)
            launch_asg_instance "$instance_type" "$stack_name" "$options"
            ;;
        *)
            log_error "Unknown deployment type: $deployment_type"
            return 1
            ;;
    esac
}

# Spot instance launcher with cost optimization
launch_spot_instance() {
    local instance_type="${1}"
    local stack_name="${2}"
    local options="${3:-}"
    
    # Get optimal spot price and availability zone
    local optimal_config
    optimal_config=$(get_optimal_spot_config "$instance_type")
    
    if [[ -z "$optimal_config" ]]; then
        log_error "Failed to find optimal spot configuration"
        return 1
    fi
    
    local spot_price=$(echo "$optimal_config" | cut -d'|' -f1)
    local az=$(echo "$optimal_config" | cut -d'|' -f2)
    local savings=$(echo "$optimal_config" | cut -d'|' -f3)
    
    log_info "Optimal spot config: price=$spot_price, AZ=$az, savings=$savings%"
    
    # Launch spot instance with optimal configuration
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --instance-type "$instance_type" \
        --instance-market-options "MarketType=spot,SpotOptions={MaxPrice=$spot_price,SpotInstanceType=one-time}" \
        --placement "AvailabilityZone=$az" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$stack_name},{Key=Unity,Value=true}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        $options) || {
        log_error "Failed to launch spot instance"
        return 1
    }
    
    # Track resource and cost
    track_resource "ec2" "$instance_id" "$stack_name"
    track_cost "ec2-spot" "$instance_id" "$spot_price"
    
    echo "$instance_id"
}

# Launch on-demand instance
launch_ondemand_instance() {
    local instance_type="${1}"
    local stack_name="${2}"
    local options="${3:-}"
    
    log_info "Launching on-demand instance: $instance_type"
    
    # Launch instance
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --instance-type "$instance_type" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$stack_name},{Key=Unity,Value=true}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        $options) || {
        log_error "Failed to launch on-demand instance"
        return 1
    }
    
    # Track resource and cost
    track_resource "ec2" "$instance_id" "$stack_name"
    local price=$(get_ondemand_price "$instance_type")
    track_cost "ec2-ondemand" "$instance_id" "$price"
    
    echo "$instance_id"
}

# Launch ASG instance
launch_asg_instance() {
    local instance_type="${1}"
    local stack_name="${2}"
    local options="${3:-}"
    
    log_info "Creating Auto Scaling Group: $instance_type"
    
    # Create launch template
    local template_name="${stack_name}-lt"
    aws ec2 create-launch-template \
        --launch-template-name "$template_name" \
        --launch-template-data "{\"InstanceType\":\"$instance_type\",\"TagSpecifications\":[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"$stack_name\"},{\"Key\":\"Unity\",\"Value\":\"true\"}]}]}" \
        >/dev/null || {
        log_error "Failed to create launch template"
        return 1
    }
    
    # Create ASG
    local asg_name="${stack_name}-asg"
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "$asg_name" \
        --launch-template "LaunchTemplateName=$template_name" \
        --min-size 1 \
        --max-size 3 \
        --desired-capacity 1 \
        $options || {
        log_error "Failed to create Auto Scaling Group"
        return 1
    }
    
    # Track resource
    track_resource "asg" "$asg_name" "$stack_name"
    
    echo "$asg_name"
}

# Get optimal spot configuration with caching
get_optimal_spot_config() {
    local instance_type="${1}"
    local cache_key="spot_optimal_${instance_type}"
    
    # Check cache first
    local cached_config
    cached_config=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_config" ]]; then
        echo "$cached_config"
        return 0
    fi
    
    # Query spot prices across all AZs
    local best_price=999999
    local best_az=""
    local on_demand_price
    
    # Get on-demand price for savings calculation
    on_demand_price=$(get_ondemand_price "$instance_type")
    
    # Get spot prices for all AZs
    local spot_data
    spot_data=$(aws ec2 describe-spot-price-history \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-results 20 \
        --query 'SpotPriceHistory[*].[SpotPrice,AvailabilityZone]' \
        --output text 2>/dev/null) || {
        log_warn "Failed to get spot prices, using fallback"
        echo "0.10|${AWS_REGION}a|70"
        return 0
    }
    
    # Find best price
    while IFS=$'\t' read -r price az; do
        if (( $(echo "$price < $best_price" | bc -l) )); then
            best_price="$price"
            best_az="$az"
        fi
    done <<< "$spot_data"
    
    # Calculate savings
    local savings
    savings=$(echo "scale=0; (1 - $best_price / $on_demand_price) * 100" | bc -l)
    
    local config="${best_price}|${best_az}|${savings}"
    
    # Cache the result
    set_aws_cache "$cache_key" "$config" 3600
    
    echo "$config"
}

#############################################
# VPC and Networking Operations
#############################################

# Create or get VPC with intelligent CIDR allocation
create_or_get_vpc() {
    local stack_name="${1}"
    local cidr="${2:-}"
    
    log_info "Creating or getting VPC for stack: $stack_name"
    
    # Check for existing VPC
    local existing_vpc
    existing_vpc=$(find_existing_vpc "$stack_name")
    
    if [[ -n "$existing_vpc" ]]; then
        log_info "Using existing VPC: $existing_vpc"
        echo "$existing_vpc"
        return 0
    fi
    
    # Check VPC quota
    check_vpc_quota || return 1
    
    # Auto-assign CIDR if not provided
    if [[ -z "$cidr" ]]; then
        cidr=$(get_available_cidr)
    fi
    
    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$stack_name},{Key=Unity,Value=true}]" \
        --query 'Vpc.VpcId' \
        --output text) || {
        log_error "Failed to create VPC"
        return 1
    }
    
    # Enable DNS resolution and hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-resolution
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
    
    # Track resource
    track_resource "vpc" "$vpc_id" "$stack_name"
    
    echo "$vpc_id"
}

# Find available CIDR block
get_available_cidr() {
    local used_cidrs
    used_cidrs=$(aws ec2 describe-vpcs \
        --query 'Vpcs[*].CidrBlock' \
        --output text 2>/dev/null | tr '\t' '\n' | sort)
    
    # Try common private CIDR blocks
    local candidates=("10.0.0.0/16" "10.1.0.0/16" "10.2.0.0/16" "172.16.0.0/16" "172.17.0.0/16")
    
    for cidr in "${candidates[@]}"; do
        if ! echo "$used_cidrs" | grep -q "^$cidr$"; then
            echo "$cidr"
            return 0
        fi
    done
    
    # Generate random 10.x.0.0/16
    local random_second=$((RANDOM % 256))
    echo "10.${random_second}.0.0/16"
}

#############################################
# ALB Operations
#############################################

# Create Application Load Balancer
create_alb() {
    local stack_name="${1}"
    local vpc_id="${2}"
    local subnet_ids="${3}"  # comma-separated
    
    log_info "Creating ALB for stack: $stack_name"
    
    # Check ALB quota
    check_alb_quota || return 1
    
    # Create ALB
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "${stack_name}-alb" \
        --subnets $(echo "$subnet_ids" | tr ',' ' ') \
        --security-groups "$(get_or_create_alb_security_group "$vpc_id")" \
        --tags "Key=Name,Value=$stack_name" "Key=Unity,Value=true" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) || {
        log_error "Failed to create ALB"
        return 1
    }
    
    # Track resource
    track_resource "alb" "$alb_arn" "$stack_name"
    track_cost "alb" "$alb_arn" "0.0225"  # $0.0225 per hour
    
    echo "$alb_arn"
}

#############################################
# CloudFront CDN Operations
#############################################

# Create CloudFront distribution
create_cloudfront() {
    local stack_name="${1}"
    local origin_domain="${2}"
    
    log_info "Creating CloudFront distribution for stack: $stack_name"
    
    # Create distribution config
    local dist_config="/tmp/cf-config-${stack_name}.json"
    cat > "$dist_config" <<EOF
{
    "CallerReference": "${stack_name}-$(date +%s)",
    "Comment": "Unity CloudFront for ${stack_name}",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "${stack_name}-origin",
                "DomainName": "${origin_domain}",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only"
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "${stack_name}-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {
                "Forward": "all"
            }
        },
        "MinTTL": 0,
        "Compress": true
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}
EOF
    
    # Create distribution
    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "file://$dist_config" \
        --query 'Distribution.Id' \
        --output text) || {
        log_error "Failed to create CloudFront distribution"
        rm -f "$dist_config"
        return 1
    }
    
    rm -f "$dist_config"
    
    # Track resource
    track_resource "cloudfront" "$dist_id" "$stack_name"
    
    echo "$dist_id"
}

#############################################
# EFS Operations
#############################################

# Create or get EFS file system
create_or_get_efs() {
    local stack_name="${1}"
    local vpc_id="${2}"
    
    log_info "Creating or getting EFS for stack: $stack_name"
    
    # Check for existing EFS
    local existing_efs
    existing_efs=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='$stack_name']].FileSystemId" \
        --output text 2>/dev/null)
    
    if [[ -n "$existing_efs" ]]; then
        log_info "Using existing EFS: $existing_efs"
        echo "$existing_efs"
        return 0
    fi
    
    # Create EFS
    local efs_id
    efs_id=$(aws efs create-file-system \
        --creation-token "${stack_name}-efs" \
        --tags "Key=Name,Value=$stack_name" "Key=Unity,Value=true" \
        --query 'FileSystemId' \
        --output text) || {
        log_error "Failed to create EFS"
        return 1
    }
    
    # Wait for EFS to be available
    aws efs wait file-system-available --file-system-id "$efs_id"
    
    # Track resource
    track_resource "efs" "$efs_id" "$stack_name"
    track_cost "efs" "$efs_id" "0.30"  # $0.30 per GB-month
    
    echo "$efs_id"
}

#############################################
# Cost Optimization Engine
#############################################

# Calculate total deployment cost
calculate_deployment_cost() {
    local stack_name="${1}"
    local duration_hours="${2:-720}"  # Default 30 days
    
    log_info "Calculating deployment cost for: $stack_name"
    
    local total_cost=0
    local cost_breakdown=""
    
    # Iterate through tracked costs
    for resource_key in "${!UNITY_AWS_COSTS[@]}"; do
        if [[ "$resource_key" == *"${stack_name}"* ]]; then
            local hourly_cost="${UNITY_AWS_COSTS[$resource_key]}"
            local resource_cost=$(echo "$hourly_cost * $duration_hours" | bc -l)
            total_cost=$(echo "$total_cost + $resource_cost" | bc -l)
            
            local resource_type=$(echo "$resource_key" | cut -d'|' -f1)
            cost_breakdown+="\n  - $resource_type: \$$(printf "%.2f" "$resource_cost")"
        fi
    done
    
    log_info "Total estimated cost: \$$(printf "%.2f" "$total_cost")$cost_breakdown"
    echo "$total_cost"
}

# Optimize deployment costs
optimize_deployment_costs() {
    local stack_name="${1}"
    
    log_info "Optimizing deployment costs for: $stack_name"
    
    local recommendations=()
    
    # Check for spot instance opportunities
    local ec2_instances
    ec2_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Reservations[*].Instances[?InstanceLifecycle!=`spot`].[InstanceId,InstanceType]' \
        --output text 2>/dev/null)
    
    if [[ -n "$ec2_instances" ]]; then
        while IFS=$'\t' read -r instance_id instance_type; do
            local spot_config
            spot_config=$(get_optimal_spot_config "$instance_type")
            local savings=$(echo "$spot_config" | cut -d'|' -f3)
            
            if [[ "$savings" -gt 50 ]]; then
                recommendations+=("Convert $instance_id to spot instance (save $savings%)")
            fi
        done <<< "$ec2_instances"
    fi
    
    # Check for unused resources
    # check_unused_resources "$stack_name" recommendations
    
    # Print recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        log_info "Cost optimization recommendations:"
        for rec in "${recommendations[@]}"; do
            log_info "  - $rec"
        done
    else
        log_info "No cost optimization opportunities found"
    fi
}

#############################################
# Quota Management
#############################################

# Check EC2 quota
check_ec2_quota() {
    local instance_type="${1}"
    local cache_key="quota_ec2_${instance_type}"
    
    # Check cache
    local cached_quota
    cached_quota=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_quota" ]]; then
        return 0
    fi
    
    # Get current usage and limit
    local service_code="ec2"
    local quota_code="L-1216C47A"  # Running On-Demand instances
    
    local current_usage
    current_usage=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query 'length(Reservations[*].Instances[*])' \
        --output text 2>/dev/null || echo "0")
    
    local quota_limit
    quota_limit=$(aws service-quotas get-service-quota \
        --service-code "$service_code" \
        --quota-code "$quota_code" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "20")
    
    if [[ "$current_usage" -ge "$quota_limit" ]]; then
        log_error "EC2 quota exceeded: $current_usage/$quota_limit instances"
        return 1
    fi
    
    # Cache success
    set_aws_cache "$cache_key" "ok" 300
    return 0
}

# Check VPC quota
check_vpc_quota() {
    local cache_key="quota_vpc"
    
    # Check cache
    local cached_quota
    cached_quota=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_quota" ]]; then
        return 0
    fi
    
    # Get current VPC count
    local vpc_count
    vpc_count=$(aws ec2 describe-vpcs \
        --query 'length(Vpcs[*])' \
        --output text 2>/dev/null || echo "0")
    
    local vpc_limit=5  # Default VPC limit
    
    if [[ "$vpc_count" -ge "$vpc_limit" ]]; then
        log_error "VPC quota exceeded: $vpc_count/$vpc_limit VPCs"
        
        # Suggest cleanup
        log_info "Run 'unity_aws cleanup-vpcs' to remove unused VPCs"
        return 1
    fi
    
    # Cache success
    set_aws_cache "$cache_key" "ok" 300
    return 0
}

# Check ALB quota
check_alb_quota() {
    local cache_key="quota_alb"
    
    # Check cache
    local cached_quota
    cached_quota=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_quota" ]]; then
        return 0
    fi
    
    # Get current ALB count
    local alb_count
    alb_count=$(aws elbv2 describe-load-balancers \
        --query 'length(LoadBalancers[*])' \
        --output text 2>/dev/null || echo "0")
    
    local alb_limit=50  # Default ALB limit
    
    if [[ "$alb_count" -ge "$alb_limit" ]]; then
        log_error "ALB quota exceeded: $alb_count/$alb_limit ALBs"
        return 1
    fi
    
    # Cache success
    set_aws_cache "$cache_key" "ok" 300
    return 0
}

#############################################
# Resource Lifecycle Management
#############################################

# Track resource
track_resource() {
    local resource_type="${1}"
    local resource_id="${2}"
    local stack_name="${3}"
    
    local key="${resource_type}|${resource_id}|${stack_name}"
    UNITY_AWS_RESOURCES["$key"]="$(date +%s)"
    
    # Emit enhanced resource creation event
    _emit_aws_event "aws.resource.created" "unity-aws-service" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"stack_name\":\"$stack_name\",\"region\":\"${AWS_REGION:-us-west-2}\",\"created_at\":$(date +%s)}" "medium"
}

# Track cost
track_cost() {
    local resource_type="${1}"
    local resource_id="${2}"
    local hourly_cost="${3}"
    
    local key="${resource_type}|${resource_id}"
    UNITY_AWS_COSTS["$key"]="$hourly_cost"
}

# List stack resources
list_stack_resources() {
    local stack_name="${1}"
    
    log_info "Resources for stack: $stack_name"
    
    for resource_key in "${!UNITY_AWS_RESOURCES[@]}"; do
        if [[ "$resource_key" == *"${stack_name}"* ]]; then
            local resource_type=$(echo "$resource_key" | cut -d'|' -f1)
            local resource_id=$(echo "$resource_key" | cut -d'|' -f2)
            log_info "  - $resource_type: $resource_id"
        fi
    done
}

# Delete stack resources
delete_stack_resources() {
    local stack_name="${1}"
    local force="${2:-false}"
    
    log_info "Deleting resources for stack: $stack_name"
    
    # Collect resources to delete
    local resources_to_delete=()
    
    for resource_key in "${!UNITY_AWS_RESOURCES[@]}"; do
        if [[ "$resource_key" == *"${stack_name}"* ]]; then
            resources_to_delete+=("$resource_key")
        fi
    done
    
    # Delete in reverse dependency order
    local delete_order=("cloudfront" "alb" "ec2" "efs" "vpc")
    
    for resource_type in "${delete_order[@]}"; do
        for resource_key in "${resources_to_delete[@]}"; do
            if [[ "$resource_key" == "${resource_type}|"* ]]; then
                local resource_id=$(echo "$resource_key" | cut -d'|' -f2)
                delete_resource "$resource_type" "$resource_id" "$force"
            fi
        done
    done
}

# Delete individual resource
delete_resource() {
    local resource_type="${1}"
    local resource_id="${2}"
    local force="${3:-false}"
    
    log_info "Deleting $resource_type: $resource_id"
    
    case "$resource_type" in
        ec2)
            aws ec2 terminate-instances --instance-ids "$resource_id" >/dev/null
            ;;
        vpc)
            if [[ "$force" == "true" ]]; then
                delete_vpc_with_dependencies "$resource_id"
            else
                aws ec2 delete-vpc --vpc-id "$resource_id" >/dev/null
            fi
            ;;
        alb)
            aws elbv2 delete-load-balancer --load-balancer-arn "$resource_id" >/dev/null
            ;;
        cloudfront)
            # CloudFront deletion requires disabling first
            log_warn "CloudFront deletion requires manual intervention"
            ;;
        efs)
            # Delete mount targets first
            aws efs describe-mount-targets --file-system-id "$resource_id" \
                --query 'MountTargets[*].MountTargetId' --output text | \
                xargs -r -n1 aws efs delete-mount-target --mount-target-id
            sleep 5
            aws efs delete-file-system --file-system-id "$resource_id" >/dev/null
            ;;
    esac
    
    # Remove from tracking
    unset "UNITY_AWS_RESOURCES[${resource_type}|${resource_id}|*]"
    unset "UNITY_AWS_COSTS[${resource_type}|${resource_id}]"
}

#############################################
# Utility Functions
#############################################

# Find existing VPC by stack name
find_existing_vpc() {
    local stack_name="${1}"
    
    aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null | grep -v "None" || true
}

# Get on-demand price for instance type
get_ondemand_price() {
    local instance_type="${1}"
    local cache_key="price_ondemand_${instance_type}"
    
    # Check cache
    local cached_price
    cached_price=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_price" ]]; then
        echo "$cached_price"
        return 0
    fi
    
    # Fallback prices for common instances
    case "$instance_type" in
        "g4dn.xlarge") echo "0.526" ;;
        "g5.xlarge") echo "1.006" ;;
        "t3.medium") echo "0.0416" ;;
        "t3.large") echo "0.0832" ;;
        *) echo "1.00" ;;  # Default fallback
    esac
}

# Delete VPC with all dependencies
delete_vpc_with_dependencies() {
    local vpc_id="${1}"
    
    # Delete all dependent resources in order
    # 1. Delete NAT gateways
    aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NatGateways[*].NatGatewayId' --output text | \
        xargs -r -n1 aws ec2 delete-nat-gateway --nat-gateway-id
    
    # 2. Delete internet gateways
    local igw_id
    igw_id=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$igw_id" ]]; then
        aws ec2 detach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id"
    fi
    
    # 3. Delete subnets
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].SubnetId' --output text | \
        xargs -r -n1 aws ec2 delete-subnet --subnet-id
    
    # 4. Delete route tables
    aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text | \
        xargs -r -n1 aws ec2 delete-route-table --route-table-id
    
    # 5. Delete security groups
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text | \
        xargs -r -n1 aws ec2 delete-security-group --group-id
    
    # 6. Finally delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc_id"
}

# Get or create ALB security group
get_or_create_alb_security_group() {
    local vpc_id="${1}"
    
    # Check for existing security group
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=unity-alb-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$sg_id" ]]; then
        echo "$sg_id"
        return 0
    fi
    
    # Create security group
    sg_id=$(aws ec2 create-security-group \
        --vpc-id "$vpc_id" \
        --group-name "unity-alb-sg" \
        --description "Unity ALB Security Group" \
        --query 'GroupId' \
        --output text) || {
        log_error "Failed to create ALB security group"
        return 1
    }
    
    # Add ingress rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 >/dev/null
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 >/dev/null
    
    echo "$sg_id"
}

# Cleanup unused VPCs
cleanup_unused_vpcs() {
    local dry_run="${1:-true}"
    
    log_info "Cleaning up unused VPCs (dry_run=$dry_run)"
    
    # Get all VPCs
    local vpcs
    vpcs=$(aws ec2 describe-vpcs \
        --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' \
        --output text)
    
    while IFS=$'\t' read -r vpc_id vpc_name; do
        # Skip default VPC
        if aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query 'Vpcs[0].IsDefault' --output text | grep -q "true"; then
            continue
        fi
        
        # Check if VPC has any instances
        local instance_count
        instance_count=$(aws ec2 describe-instances \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,stopped" \
            --query 'length(Reservations[*].Instances[*])' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$instance_count" -eq 0 ]]; then
            log_info "Found unused VPC: $vpc_id ($vpc_name)"
            
            if [[ "$dry_run" != "true" ]]; then
                delete_vpc_with_dependencies "$vpc_id" && \
                    log_info "Deleted VPC: $vpc_id" || \
                    log_error "Failed to delete VPC: $vpc_id"
            fi
        fi
    done <<< "$vpcs"
}

#############################################
# Main CLI Interface
#############################################

# Unity AWS CLI
unity_aws() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        init)
            init_unity_aws_service "$@"
            ;;
        launch)
            launch_ec2_instance "$@"
            ;;
        create-vpc)
            create_or_get_vpc "$@"
            ;;
        create-alb)
            create_alb "$@"
            ;;
        create-cloudfront)
            create_cloudfront "$@"
            ;;
        create-efs)
            create_or_get_efs "$@"
            ;;
        cost)
            calculate_deployment_cost "$@"
            ;;
        optimize)
            optimize_deployment_costs "$@"
            ;;
        list)
            list_stack_resources "$@"
            ;;
        delete)
            delete_stack_resources "$@"
            ;;
        cleanup-vpcs)
            cleanup_unused_vpcs "$@"
            ;;
        check-quota)
            check_ec2_quota "$@" && check_vpc_quota && check_alb_quota
            ;;
        help|*)
            cat <<EOF
Unity AWS Service v$UNITY_AWS_SERVICE_VERSION

Usage: unity_aws <command> [options]

Commands:
    init                    Initialize Unity AWS Service
    launch <type> <deployment> <stack>  Launch EC2 instance
    create-vpc <stack> [cidr]          Create or get VPC
    create-alb <stack> <vpc> <subnets> Create Application Load Balancer
    create-cloudfront <stack> <origin> Create CloudFront distribution
    create-efs <stack> <vpc>           Create or get EFS file system
    cost <stack> [hours]               Calculate deployment cost
    optimize <stack>                   Optimize deployment costs
    list <stack>                       List stack resources
    delete <stack> [force]             Delete stack resources
    cleanup-vpcs [dry-run]             Cleanup unused VPCs
    check-quota <type>                 Check AWS quotas
    help                               Show this help

Examples:
    unity_aws launch g4dn.xlarge spot my-stack
    unity_aws create-vpc my-stack 10.0.0.0/16
    unity_aws cost my-stack 720
    unity_aws optimize my-stack
    unity_aws cleanup-vpcs false
EOF
            ;;
    esac
}

# Export functions and variables
export -f unity_aws
export -f init_unity_aws_service
export -f launch_ec2_instance
export -f create_or_get_vpc
export -f create_alb
export -f create_cloudfront
export -f create_or_get_efs
export -f calculate_deployment_cost
export -f optimize_deployment_costs
export -f list_stack_resources
export -f delete_stack_resources

#############################################
# Enhanced Event System Integration
#############################################

# Initialize AWS service event integration
_init_aws_service_events() {
    # Source enhanced event system if available
    local events_file="$PROJECT_ROOT/lib/unity/core/unity-events.sh"
    if [[ -f "$events_file" ]]; then
        source "$events_file" 2>/dev/null || true
        
        # Initialize event system if not already done
        if command -v unity_init_events >/dev/null 2>&1; then
            unity_init_events "false" 2>/dev/null || true
        fi
    fi
    
    # Register AWS service event handlers if handler system is available
    if command -v unity_on_event >/dev/null 2>&1; then
        # Register cost threshold handler
        unity_on_event "aws\.cost\.threshold_exceeded" "handle_aws_cost_alert" "priority=high"
        
        # Register resource failure handler
        unity_on_event "aws\.resource\.failed" "handle_aws_resource_failure" "priority=high"
        
        # Register quota exceeded handler
        unity_on_event "aws\.quota\.exceeded" "handle_aws_quota_exceeded" "priority=high"
    fi
}

# Emit AWS service events
_emit_aws_event() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local priority="${4:-medium}"
    
    # Use enhanced event system if available
    if command -v unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "$event_type" "$event_source" "$event_data" "$priority" "false"
    else
        # Fallback to basic logging
        log_info "AWS Event: $event_type from $event_source - $event_data"
    fi
}

# Handle AWS cost alert events
handle_aws_cost_alert() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    log_warn "AWS Cost Alert: $event_data"
    
    # Extract cost information
    local stack_name
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Trigger cost optimization
    optimize_deployment_costs "$stack_name"
    
    # Emit follow-up event for potential rollback consideration
    _emit_aws_event "aws.cost.optimization.required" "cost-handler" "{\"stack_name\":\"$stack_name\",\"trigger\":\"threshold_exceeded\"}" "high"
}

# Handle AWS resource failure events
handle_aws_resource_failure() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    log_error "AWS Resource Failure: $event_data"
    
    # Extract resource information
    local resource_type resource_id stack_name
    resource_type=$(echo "$event_data" | grep -o '"resource_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    resource_id=$(echo "$event_data" | grep -o '"resource_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Attempt automatic remediation based on resource type
    case "$resource_type" in
        "ec2")
            log_info "Attempting EC2 instance recovery for $resource_id"
            # Could trigger instance replacement logic
            ;;
        "vpc")
            log_info "VPC failure detected for $resource_id - may require manual intervention"
            ;;
        *)
            log_info "Generic resource failure handling for $resource_type: $resource_id"
            ;;
    esac
    
    # Emit remediation event
    _emit_aws_event "aws.resource.remediation.attempted" "failure-handler" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"stack_name\":\"$stack_name\"}" "high"
}

# Handle AWS quota exceeded events
handle_aws_quota_exceeded() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    log_error "AWS Quota Exceeded: $event_data"
    
    # Extract quota information
    local quota_type
    quota_type=$(echo "$event_data" | grep -o '"quota_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Emit alert for manual intervention
    _emit_aws_event "monitor.alert.triggered" "quota-monitor" "{\"alert_type\":\"quota_exceeded\",\"severity\":\"critical\",\"message\":\"AWS quota exceeded: $quota_type\"}" "critical"
}

# Enhanced resource tracking with events
track_resource_with_events() {
    local resource_type="${1}"
    local resource_id="${2}"
    local stack_name="${3}"
    local cost_per_hour="${4:-0}"
    local additional_metadata="${5:-{}}"
    
    # Call original tracking
    track_resource "$resource_type" "$resource_id" "$stack_name"
    
    # Track cost if provided
    if [[ "$cost_per_hour" != "0" ]]; then
        track_cost "$resource_type" "$resource_id" "$cost_per_hour"
    fi
    
    # Emit detailed resource creation event
    _emit_aws_event "aws.resource.created" "unity-aws-service" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"stack_name\":\"$stack_name\",\"cost_per_hour\":$cost_per_hour,\"metadata\":$additional_metadata}" "medium"
}

# Enhanced cost tracking with threshold monitoring
track_cost_with_monitoring() {
    local resource_type="${1}"
    local resource_id="${2}"
    local hourly_cost="${3}"
    local stack_name="${4:-unknown}"
    local cost_threshold="${5:-100}"  # Default $100 threshold
    
    # Call original cost tracking
    track_cost "$resource_type" "$resource_id" "$hourly_cost"
    
    # Calculate projected monthly cost
    local monthly_cost
    monthly_cost=$(echo "$hourly_cost * 24 * 30" | bc -l 2>/dev/null || echo "$hourly_cost")
    
    # Check if projected cost exceeds threshold
    if (( $(echo "$monthly_cost > $cost_threshold" | bc -l 2>/dev/null || echo "0") )); then
        _emit_aws_event "aws.cost.threshold_exceeded" "cost-monitor" "{\"stack_name\":\"$stack_name\",\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"hourly_cost\":$hourly_cost,\"monthly_projection\":$monthly_cost,\"threshold\":$cost_threshold}" "high"
    fi
    
    # Emit cost tracking event
    _emit_aws_event "aws.cost.tracked" "cost-tracker" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"hourly_cost\":$hourly_cost,\"monthly_projection\":$monthly_cost}" "low"
}

# Enhanced quota checking with events
check_quota_with_events() {
    local quota_type="${1}"
    local resource_type="${2}"
    local current_usage="${3}"
    local quota_limit="${4}"
    local stack_name="${5:-unknown}"
    
    # Calculate usage percentage
    local usage_percentage
    usage_percentage=$(echo "scale=2; $current_usage * 100 / $quota_limit" | bc -l 2>/dev/null || echo "0")
    
    # Emit quota check event
    _emit_aws_event "aws.quota.checked" "quota-monitor" "{\"quota_type\":\"$quota_type\",\"resource_type\":\"$resource_type\",\"current_usage\":$current_usage,\"quota_limit\":$quota_limit,\"usage_percentage\":$usage_percentage,\"stack_name\":\"$stack_name\"}" "low"
    
    # Check if approaching limit (80% threshold)
    if (( $(echo "$usage_percentage > 80" | bc -l 2>/dev/null || echo "0") )); then
        _emit_aws_event "aws.quota.warning" "quota-monitor" "{\"quota_type\":\"$quota_type\",\"usage_percentage\":$usage_percentage,\"message\":\"Approaching quota limit\"}" "medium"
    fi
    
    # Check if quota exceeded
    if [[ "$current_usage" -ge "$quota_limit" ]]; then
        _emit_aws_event "aws.quota.exceeded" "quota-monitor" "{\"quota_type\":\"$quota_type\",\"current_usage\":$current_usage,\"quota_limit\":$quota_limit,\"stack_name\":\"$stack_name\"}" "critical"
        return 1
    fi
    
    return 0
}

# Export enhanced functions
export -f _init_aws_service_events
export -f _emit_aws_event
export -f handle_aws_cost_alert
export -f handle_aws_resource_failure
export -f handle_aws_quota_exceeded
export -f track_resource_with_events
export -f track_cost_with_monitoring
export -f check_quota_with_events

# Initialize if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    unity_aws "$@"
fi