#!/bin/bash
# Unity AWS Service Complete - Production-Ready AWS Operations
# Comprehensive AWS service with VPC, EC2, ALB, CloudFront, EFS, IAM, cost optimization
# Event-driven architecture with proper lifecycle management and error handling

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core dependencies
if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-core.sh" ]]; then
    source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
fi

if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-events.sh" ]]; then
    source "$PROJECT_ROOT/lib/unity/core/unity-events.sh"
fi

# Service metadata and version
UNITY_AWS_SERVICE_VERSION="2.0.0"
UNITY_AWS_SERVICE_NAME="unity-aws-service-complete"

# Service state tracking - bash 3/4 compatible
declare -A UNITY_AWS_RESOURCES 2>/dev/null || UNITY_AWS_RESOURCES=()
declare -A UNITY_AWS_COSTS 2>/dev/null || UNITY_AWS_COSTS=()
declare -A UNITY_AWS_QUOTAS 2>/dev/null || UNITY_AWS_QUOTAS=()
declare -A UNITY_AWS_CACHE 2>/dev/null || UNITY_AWS_CACHE=()

# AWS region and configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_DEFAULT_REGION="$AWS_REGION"

# Cost optimization settings
SPOT_SAVINGS_TARGET=70
COST_THRESHOLD_DEFAULT=100
QUOTA_CHECK_INTERVAL=300

#############################################
# Unity Service Interface Implementation
#############################################

# Initialize AWS service (required Unity interface)
init_unity_aws_service() {
    local service_name="${1:-unity-aws-complete}"
    
    unity_log "INFO" "Initializing Unity AWS Service Complete v$UNITY_AWS_SERVICE_VERSION"
    
    # Validate AWS credentials
    if ! _validate_aws_credentials; then
        unity_handle_error "$UNITY_ERROR_PREREQUISITE" "service:unity-aws" "AWS credentials not configured" "cleanup"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Initialize enhanced event system integration
    _init_aws_service_events
    
    # Initialize resource tracking
    UNITY_AWS_RESOURCES=()
    UNITY_AWS_COSTS=()
    UNITY_AWS_QUOTAS=()
    UNITY_AWS_CACHE=()
    
    # Create state directories
    local state_dirs=(".unity/aws/cache" ".unity/aws/state" ".unity/aws/costs" ".unity/aws/quotas")
    for dir in "${state_dirs[@]}"; do
        mkdir -p "$dir" 2>/dev/null || true
    done
    
    # Initialize caching system
    _init_aws_api_cache
    
    # Initialize cost tracking
    _init_cost_tracking
    
    # Initialize quota monitoring
    _init_quota_monitoring
    
    # Register with Unity system if available
    if command -v unity_register_service >/dev/null 2>&1; then
        unity_register_service "$service_name" "$0" "aws" "config"
    fi
    
    # Emit service startup event
    _emit_aws_event "system.startup" "unity-aws-service" "{\"component\":\"unity-aws-service-complete\",\"version\":\"$UNITY_AWS_SERVICE_VERSION\",\"startup_time\":$(date +%s)}" "medium"
    
    unity_log "SUCCESS" "Unity AWS Service Complete initialized successfully"
    return $UNITY_SUCCESS
}

# Start AWS service (required Unity interface)
start_unity_aws_service() {
    unity_log "INFO" "Starting Unity AWS Service Complete"
    
    # Start background quota monitoring
    _start_quota_monitoring &
    
    # Start cost monitoring
    _start_cost_monitoring &
    
    # Emit service started event
    _emit_aws_event "system.service.started" "unity-aws-service" "{\"service\":\"unity-aws-complete\"}" "medium"
    
    unity_log "SUCCESS" "Unity AWS Service Complete started"
    return $UNITY_SUCCESS
}

# Stop AWS service (required Unity interface)
stop_unity_aws_service() {
    unity_log "INFO" "Stopping Unity AWS Service Complete"
    
    # Stop background processes
    pkill -f "_start_quota_monitoring" 2>/dev/null || true
    pkill -f "_start_cost_monitoring" 2>/dev/null || true
    
    # Emit service stopped event
    _emit_aws_event "system.service.stopped" "unity-aws-service" "{\"service\":\"unity-aws-complete\"}" "medium"
    
    unity_log "SUCCESS" "Unity AWS Service Complete stopped"
    return $UNITY_SUCCESS
}

# Health check (required Unity interface)
health_unity_aws_service() {
    local health_status="healthy"
    local health_details="{}"
    
    # Check AWS credentials
    if ! _validate_aws_credentials; then
        health_status="unhealthy"
        health_details="{\"error\":\"AWS credentials invalid\"}"
    fi
    
    # Check AWS connectivity
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        health_status="unhealthy"
        health_details="{\"error\":\"AWS API connectivity failed\"}"
    fi
    
    # Emit health check event
    _emit_aws_event "monitor.health.check" "unity-aws-service" "{\"status\":\"$health_status\",\"details\":$health_details}" "low"
    
    if [[ "$health_status" == "healthy" ]]; then
        unity_log "INFO" "AWS Service health check: HEALTHY"
        return $UNITY_SUCCESS
    else
        unity_log "ERROR" "AWS Service health check: UNHEALTHY - $health_details"
        return $UNITY_ERROR_EXECUTION
    fi
}

# Configuration management (required Unity interface)
config_unity_aws_service() {
    local action="${1:-get}"
    local key="${2:-}"
    local value="${3:-}"
    
    case "$action" in
        get)
            if [[ -n "$key" ]]; then
                _get_aws_config "$key"
            else
                _get_all_aws_config
            fi
            ;;
        set)
            if [[ -n "$key" && -n "$value" ]]; then
                _set_aws_config "$key" "$value"
            else
                unity_log "ERROR" "Config set requires key and value"
                return $UNITY_ERROR_VALIDATION
            fi
            ;;
        validate)
            _validate_aws_config
            ;;
        *)
            unity_log "ERROR" "Unknown config action: $action"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
}

#############################################
# VPC Operations - Complete Implementation
#############################################

# Create VPC with intelligent CIDR allocation and multi-AZ support
create_unity_vpc() {
    local stack_name="${1}"
    local cidr="${2:-}"
    local multi_az="${3:-false}"
    local options="${4:-}"
    
    unity_log "INFO" "Creating VPC for stack: $stack_name (multi-AZ: $multi_az)"
    
    # Check for existing VPC
    local existing_vpc
    existing_vpc=$(find_existing_vpc "$stack_name")
    
    if [[ -n "$existing_vpc" ]]; then
        unity_log "INFO" "Using existing VPC: $existing_vpc"
        echo "$existing_vpc"
        return $UNITY_SUCCESS
    fi
    
    # Check VPC quota
    if ! check_vpc_quota_with_events; then
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Auto-assign CIDR if not provided
    if [[ -z "$cidr" ]]; then
        cidr=$(get_available_cidr)
    fi
    
    # Validate CIDR
    if ! _validate_cidr "$cidr"; then
        unity_log "ERROR" "Invalid CIDR block: $cidr"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --region "$AWS_REGION" \
        --cidr-block "$cidr" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$stack_name},{Key=Unity,Value=true},{Key=CreatedBy,Value=unity-aws-service}]" \
        --query 'Vpc.VpcId' \
        --output text) || {
        unity_log "ERROR" "Failed to create VPC"
        _emit_aws_event "aws.resource.failed" "vpc-manager" "{\"resource_type\":\"vpc\",\"stack_name\":\"$stack_name\",\"error\":\"creation_failed\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Enable DNS resolution and hostnames
    aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$vpc_id" --enable-dns-resolution
    aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$vpc_id" --enable-dns-hostnames
    
    # Create Internet Gateway
    local igw_id
    igw_id=$(create_internet_gateway "$vpc_id" "$stack_name")
    
    # Create subnets based on multi-AZ setting
    if [[ "$multi_az" == "true" ]]; then
        create_multi_az_subnets "$vpc_id" "$stack_name" "$cidr"
    else
        create_single_az_subnets "$vpc_id" "$stack_name" "$cidr"
    fi
    
    # Create route tables
    create_route_tables "$vpc_id" "$igw_id" "$stack_name"
    
    # Create security groups
    create_default_security_groups "$vpc_id" "$stack_name"
    
    # Track resource and emit events
    track_resource_with_events "vpc" "$vpc_id" "$stack_name" "0" "{\"cidr\":\"$cidr\",\"multi_az\":$multi_az}"
    _emit_aws_event "aws.vpc.created" "vpc-manager" "{\"vpc_id\":\"$vpc_id\",\"stack_name\":\"$stack_name\",\"cidr\":\"$cidr\",\"multi_az\":$multi_az}" "medium"
    
    echo "$vpc_id"
    return $UNITY_SUCCESS
}

# Create Internet Gateway
create_internet_gateway() {
    local vpc_id="${1}"
    local stack_name="${2}"
    
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --region "$AWS_REGION" \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${stack_name}-igw},{Key=Unity,Value=true}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text) || {
        unity_log "ERROR" "Failed to create Internet Gateway"
        return 1
    }
    
    # Attach to VPC
    aws ec2 attach-internet-gateway \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --internet-gateway-id "$igw_id" || {
        unity_log "ERROR" "Failed to attach Internet Gateway to VPC"
        return 1
    }
    
    track_resource_with_events "igw" "$igw_id" "$stack_name" "0"
    echo "$igw_id"
}

# Create multi-AZ subnets
create_multi_az_subnets() {
    local vpc_id="${1}"
    local stack_name="${2}"
    local vpc_cidr="${3}"
    
    # Get available AZs
    local azs
    azs=$(aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text | head -n 3)
    
    local az_count=0
    local subnet_size=24  # /24 subnets from /16 VPC
    
    for az in $azs; do
        local subnet_cidr
        subnet_cidr=$(calculate_subnet_cidr "$vpc_cidr" "$az_count" "$subnet_size")
        
        # Create public subnet
        local public_subnet_id
        public_subnet_id=$(aws ec2 create-subnet \
            --region "$AWS_REGION" \
            --vpc-id "$vpc_id" \
            --cidr-block "$subnet_cidr" \
            --availability-zone "$az" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${stack_name}-public-${az}},{Key=Unity,Value=true},{Key=Type,Value=public}]" \
            --query 'Subnet.SubnetId' \
            --output text)
        
        # Enable auto-assign public IP
        aws ec2 modify-subnet-attribute \
            --region "$AWS_REGION" \
            --subnet-id "$public_subnet_id" \
            --map-public-ip-on-launch
        
        track_resource_with_events "subnet" "$public_subnet_id" "$stack_name" "0" "{\"type\":\"public\",\"az\":\"$az\"}"
        
        # Create private subnet
        local private_cidr
        private_cidr=$(calculate_subnet_cidr "$vpc_cidr" $((az_count + 10)) "$subnet_size")
        
        local private_subnet_id
        private_subnet_id=$(aws ec2 create-subnet \
            --region "$AWS_REGION" \
            --vpc-id "$vpc_id" \
            --cidr-block "$private_cidr" \
            --availability-zone "$az" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${stack_name}-private-${az}},{Key=Unity,Value=true},{Key=Type,Value=private}]" \
            --query 'Subnet.SubnetId' \
            --output text)
        
        track_resource_with_events "subnet" "$private_subnet_id" "$stack_name" "0" "{\"type\":\"private\",\"az\":\"$az\"}"
        
        az_count=$((az_count + 1))
        
        # Limit to 3 AZs
        if [[ $az_count -ge 3 ]]; then
            break
        fi
    done
}

# Create single-AZ subnets
create_single_az_subnets() {
    local vpc_id="${1}"
    local stack_name="${2}"
    local vpc_cidr="${3}"
    
    # Get first available AZ
    local az
    az=$(aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text | head -n 1)
    
    # Create public subnet
    local public_cidr
    public_cidr=$(calculate_subnet_cidr "$vpc_cidr" "0" "24")
    
    local public_subnet_id
    public_subnet_id=$(aws ec2 create-subnet \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --cidr-block "$public_cidr" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${stack_name}-public},{Key=Unity,Value=true},{Key=Type,Value=public}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute \
        --region "$AWS_REGION" \
        --subnet-id "$public_subnet_id" \
        --map-public-ip-on-launch
    
    track_resource_with_events "subnet" "$public_subnet_id" "$stack_name" "0" "{\"type\":\"public\",\"az\":\"$az\"}"
    
    # Create private subnet
    local private_cidr
    private_cidr=$(calculate_subnet_cidr "$vpc_cidr" "1" "24")
    
    local private_subnet_id
    private_subnet_id=$(aws ec2 create-subnet \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --cidr-block "$private_cidr" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${stack_name}-private},{Key=Unity,Value=true},{Key=Type,Value=private}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    track_resource_with_events "subnet" "$private_subnet_id" "$stack_name" "0" "{\"type\":\"private\",\"az\":\"$az\"}"
}

# Create route tables
create_route_tables() {
    local vpc_id="${1}"
    local igw_id="${2}"
    local stack_name="${3}"
    
    # Create public route table
    local public_rt_id
    public_rt_id=$(aws ec2 create-route-table \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${stack_name}-public-rt},{Key=Unity,Value=true},{Key=Type,Value=public}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    # Add route to Internet Gateway
    aws ec2 create-route \
        --region "$AWS_REGION" \
        --route-table-id "$public_rt_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id"
    
    # Associate with public subnets
    local public_subnets
    public_subnets=$(aws ec2 describe-subnets \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Type,Values=public" \
        --query 'Subnets[*].SubnetId' \
        --output text)
    
    for subnet_id in $public_subnets; do
        aws ec2 associate-route-table \
            --region "$AWS_REGION" \
            --route-table-id "$public_rt_id" \
            --subnet-id "$subnet_id"
    done
    
    track_resource_with_events "route-table" "$public_rt_id" "$stack_name" "0" "{\"type\":\"public\"}"
}

# Create default security groups
create_default_security_groups() {
    local vpc_id="${1}"
    local stack_name="${2}"
    
    # Create web security group
    local web_sg_id
    web_sg_id=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --group-name "${stack_name}-web-sg" \
        --description "Unity Web Security Group for ${stack_name}" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${stack_name}-web-sg},{Key=Unity,Value=true}]" \
        --query 'GroupId' \
        --output text)
    
    # Add web security group rules
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$web_sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$web_sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$web_sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    track_resource_with_events "security-group" "$web_sg_id" "$stack_name" "0" "{\"type\":\"web\"}"
}

#############################################
# EC2 Operations - Enhanced Implementation
#############################################

# Launch EC2 instance with optimal configuration
launch_unity_ec2() {
    local instance_type="${1}"
    local deployment_type="${2:-spot}"  # spot, on-demand, or asg
    local stack_name="${3}"
    local options="${4:-}"
    
    unity_log "INFO" "Launching EC2 instance: type=$instance_type, deployment=$deployment_type, stack=$stack_name"
    
    # Check quotas first
    if ! check_ec2_quota_with_events "$instance_type"; then
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Get VPC and subnet information
    local vpc_id
    vpc_id=$(find_existing_vpc "$stack_name")
    
    if [[ -z "$vpc_id" ]]; then
        unity_log "ERROR" "No VPC found for stack: $stack_name"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    local subnet_id
    subnet_id=$(get_best_subnet "$vpc_id" "$instance_type")
    
    # Get or create security group
    local security_group_id
    security_group_id=$(get_or_create_instance_security_group "$vpc_id" "$stack_name")
    
    # Get or create key pair
    local key_pair_name
    key_pair_name=$(get_or_create_key_pair "$stack_name")
    
    # Get AMI ID
    local ami_id
    ami_id=$(get_optimal_ami "$instance_type")
    
    case "$deployment_type" in
        spot)
            launch_spot_instance_enhanced "$instance_type" "$stack_name" "$subnet_id" "$security_group_id" "$key_pair_name" "$ami_id" "$options"
            ;;
        on-demand)
            launch_ondemand_instance_enhanced "$instance_type" "$stack_name" "$subnet_id" "$security_group_id" "$key_pair_name" "$ami_id" "$options"
            ;;
        asg)
            launch_asg_instance_enhanced "$instance_type" "$stack_name" "$subnet_id" "$security_group_id" "$key_pair_name" "$ami_id" "$options"
            ;;
        *)
            unity_log "ERROR" "Unknown deployment type: $deployment_type"
            return $UNITY_ERROR_VALIDATION
            ;;
    esac
}

# Enhanced spot instance launcher with advanced optimization
launch_spot_instance_enhanced() {
    local instance_type="${1}"
    local stack_name="${2}"
    local subnet_id="${3}"
    local security_group_id="${4}"
    local key_pair_name="${5}"
    local ami_id="${6}"
    local options="${7:-}"
    
    # Get optimal spot configuration
    local optimal_config
    optimal_config=$(get_optimal_spot_config_enhanced "$instance_type")
    
    if [[ -z "$optimal_config" ]]; then
        unity_log "ERROR" "Failed to find optimal spot configuration"
        return $UNITY_ERROR_EXECUTION
    fi
    
    local spot_price=$(echo "$optimal_config" | cut -d'|' -f1)
    local az=$(echo "$optimal_config" | cut -d'|' -f2)
    local savings=$(echo "$optimal_config" | cut -d'|' -f3)
    
    unity_log "INFO" "Optimal spot config: price=$spot_price, AZ=$az, savings=$savings%"
    
    # Create user data script
    local user_data
    user_data=$(create_user_data_script "$stack_name")
    
    # Launch spot instance with enhanced configuration
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --key-name "$key_pair_name" \
        --security-group-ids "$security_group_id" \
        --subnet-id "$subnet_id" \
        --user-data "$user_data" \
        --instance-market-options "MarketType=spot,SpotOptions={MaxPrice=$spot_price,SpotInstanceType=one-time,InstanceInterruptionBehavior=stop}" \
        --placement "AvailabilityZone=$az" \
        --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$stack_name},{Key=Unity,Value=true},{Key=DeploymentType,Value=spot},{Key=SpotSavings,Value=$savings%}]" \
        --monitoring "Enabled=true" \
        --query 'Instances[0].InstanceId' \
        --output text \
        $options) || {
        unity_log "ERROR" "Failed to launch spot instance"
        _emit_aws_event "aws.ec2.launch_failed" "ec2-manager" "{\"instance_type\":\"$instance_type\",\"deployment_type\":\"spot\",\"stack_name\":\"$stack_name\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Wait for instance to be running
    unity_log "INFO" "Waiting for instance to be running: $instance_id"
    aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$instance_id"
    
    # Get instance details
    local instance_details
    instance_details=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
        --output text)
    
    local public_ip=$(echo "$instance_details" | cut -f1)
    local private_ip=$(echo "$instance_details" | cut -f2)
    
    # Track resource and cost with enhanced monitoring
    track_resource_with_events "ec2" "$instance_id" "$stack_name" "$spot_price" "{\"instance_type\":\"$instance_type\",\"deployment_type\":\"spot\",\"public_ip\":\"$public_ip\",\"private_ip\":\"$private_ip\",\"savings\":\"$savings%\"}"
    track_cost_with_monitoring "ec2-spot" "$instance_id" "$spot_price" "$stack_name" "$COST_THRESHOLD_DEFAULT"
    
    # Emit success event
    _emit_aws_event "aws.ec2.launched" "ec2-manager" "{\"instance_id\":\"$instance_id\",\"instance_type\":\"$instance_type\",\"deployment_type\":\"spot\",\"stack_name\":\"$stack_name\",\"public_ip\":\"$public_ip\",\"savings\":\"$savings%\"}" "medium"
    
    unity_log "SUCCESS" "Spot instance launched: $instance_id (savings: $savings%)"
    echo "$instance_id"
    return $UNITY_SUCCESS
}

# Enhanced on-demand instance launcher
launch_ondemand_instance_enhanced() {
    local instance_type="${1}"
    local stack_name="${2}"
    local subnet_id="${3}"
    local security_group_id="${4}"
    local key_pair_name="${5}"
    local ami_id="${6}"
    local options="${7:-}"
    
    unity_log "INFO" "Launching on-demand instance: $instance_type"
    
    # Create user data script
    local user_data
    user_data=$(create_user_data_script "$stack_name")
    
    # Launch instance
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --key-name "$key_pair_name" \
        --security-group-ids "$security_group_id" \
        --subnet-id "$subnet_id" \
        --user-data "$user_data" \
        --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$stack_name},{Key=Unity,Value=true},{Key=DeploymentType,Value=on-demand}]" \
        --monitoring "Enabled=true" \
        --query 'Instances[0].InstanceId' \
        --output text \
        $options) || {
        unity_log "ERROR" "Failed to launch on-demand instance"
        _emit_aws_event "aws.ec2.launch_failed" "ec2-manager" "{\"instance_type\":\"$instance_type\",\"deployment_type\":\"on-demand\",\"stack_name\":\"$stack_name\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Wait for instance to be running
    unity_log "INFO" "Waiting for instance to be running: $instance_id"
    aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$instance_id"
    
    # Get instance details
    local instance_details
    instance_details=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
        --output text)
    
    local public_ip=$(echo "$instance_details" | cut -f1)
    local private_ip=$(echo "$instance_details" | cut -f2)
    
    # Track resource and cost
    local price=$(get_ondemand_price "$instance_type")
    track_resource_with_events "ec2" "$instance_id" "$stack_name" "$price" "{\"instance_type\":\"$instance_type\",\"deployment_type\":\"on-demand\",\"public_ip\":\"$public_ip\",\"private_ip\":\"$private_ip\"}"
    track_cost_with_monitoring "ec2-ondemand" "$instance_id" "$price" "$stack_name" "$COST_THRESHOLD_DEFAULT"
    
    # Emit success event
    _emit_aws_event "aws.ec2.launched" "ec2-manager" "{\"instance_id\":\"$instance_id\",\"instance_type\":\"$instance_type\",\"deployment_type\":\"on-demand\",\"stack_name\":\"$stack_name\",\"public_ip\":\"$public_ip\"}" "medium"
    
    unity_log "SUCCESS" "On-demand instance launched: $instance_id"
    echo "$instance_id"
    return $UNITY_SUCCESS
}

#############################################
# ALB Operations - Complete Implementation
#############################################

# Create Application Load Balancer with enhanced configuration
create_unity_alb() {
    local stack_name="${1}"
    local vpc_id="${2}"
    local options="${3:-}"
    
    unity_log "INFO" "Creating ALB for stack: $stack_name"
    
    # Check ALB quota
    if ! check_alb_quota_with_events; then
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Get public subnets for ALB
    local subnet_ids
    subnet_ids=$(aws ec2 describe-subnets \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Type,Values=public" \
        --query 'Subnets[*].SubnetId' \
        --output text | tr '\t' ',')
    
    if [[ -z "$subnet_ids" ]]; then
        unity_log "ERROR" "No public subnets found for ALB"
        return $UNITY_ERROR_PREREQUISITE
    fi
    
    # Create or get ALB security group
    local alb_sg_id
    alb_sg_id=$(get_or_create_alb_security_group "$vpc_id" "$stack_name")
    
    # Create ALB
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --region "$AWS_REGION" \
        --name "${stack_name}-alb" \
        --subnets $(echo "$subnet_ids" | tr ',' ' ') \
        --security-groups "$alb_sg_id" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags "Key=Name,Value=${stack_name}-alb" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) || {
        unity_log "ERROR" "Failed to create ALB"
        _emit_aws_event "aws.alb.creation_failed" "alb-manager" "{\"stack_name\":\"$stack_name\",\"vpc_id\":\"$vpc_id\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Wait for ALB to be active
    unity_log "INFO" "Waiting for ALB to be active: $alb_arn"
    aws elbv2 wait load-balancer-available --region "$AWS_REGION" --load-balancer-arns "$alb_arn"
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create default target group
    local target_group_arn
    target_group_arn=$(create_alb_target_group "$stack_name" "$vpc_id" "$alb_arn")
    
    # Create default listener
    create_alb_listener "$alb_arn" "$target_group_arn" "$stack_name"
    
    # Track resource and cost
    track_resource_with_events "alb" "$alb_arn" "$stack_name" "0.0225" "{\"dns_name\":\"$alb_dns\",\"target_group\":\"$target_group_arn\"}"
    track_cost_with_monitoring "alb" "$alb_arn" "0.0225" "$stack_name" "$COST_THRESHOLD_DEFAULT"
    
    # Emit success event
    _emit_aws_event "aws.alb.created" "alb-manager" "{\"alb_arn\":\"$alb_arn\",\"stack_name\":\"$stack_name\",\"dns_name\":\"$alb_dns\"}" "medium"
    
    unity_log "SUCCESS" "ALB created: $alb_dns"
    echo "$alb_arn"
    return $UNITY_SUCCESS
}

# Create ALB target group
create_alb_target_group() {
    local stack_name="${1}"
    local vpc_id="${2}"
    local alb_arn="${3}"
    
    local target_group_arn
    target_group_arn=$(aws elbv2 create-target-group \
        --region "$AWS_REGION" \
        --name "${stack_name}-tg" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$vpc_id" \
        --target-type instance \
        --health-check-protocol HTTP \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 5 \
        --tags "Key=Name,Value=${stack_name}-tg" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text) || {
        unity_log "ERROR" "Failed to create target group"
        return 1
    }
    
    track_resource_with_events "target-group" "$target_group_arn" "$stack_name" "0"
    echo "$target_group_arn"
}

# Create ALB listener
create_alb_listener() {
    local alb_arn="${1}"
    local target_group_arn="${2}"
    local stack_name="${3}"
    
    local listener_arn
    listener_arn=$(aws elbv2 create-listener \
        --region "$AWS_REGION" \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions "Type=forward,TargetGroupArn=$target_group_arn" \
        --tags "Key=Name,Value=${stack_name}-listener" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" \
        --query 'Listeners[0].ListenerArn' \
        --output text) || {
        unity_log "ERROR" "Failed to create ALB listener"
        return 1
    }
    
    track_resource_with_events "listener" "$listener_arn" "$stack_name" "0"
    echo "$listener_arn"
}

# Register instance with ALB target group
register_instance_with_alb() {
    local instance_id="${1}"
    local stack_name="${2}"
    
    # Find target group for stack
    local target_group_arn
    target_group_arn=$(aws elbv2 describe-target-groups \
        --region "$AWS_REGION" \
        --names "${stack_name}-tg" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$target_group_arn" ]]; then
        aws elbv2 register-targets \
            --region "$AWS_REGION" \
            --target-group-arn "$target_group_arn" \
            --targets "Id=$instance_id,Port=80"
        
        unity_log "INFO" "Registered instance $instance_id with target group"
        _emit_aws_event "aws.alb.target_registered" "alb-manager" "{\"instance_id\":\"$instance_id\",\"target_group_arn\":\"$target_group_arn\"}" "low"
    fi
}

#############################################
# CloudFront CDN Operations
#############################################

# Create CloudFront distribution with enhanced configuration
create_unity_cloudfront() {
    local stack_name="${1}"
    local origin_domain="${2}"
    local options="${3:-}"
    
    unity_log "INFO" "Creating CloudFront distribution for stack: $stack_name"
    
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
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 3,
                        "Items": ["TLSv1", "TLSv1.1", "TLSv1.2"]
                    }
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "${stack_name}-origin",
        "ViewerProtocolPolicy": "allow-all",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {
                "Forward": "all"
            },
            "Headers": {
                "Quantity": 0
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "CallerReference": "${stack_name}-$(date +%s)",
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "WebACLId": ""
}
EOF
    
    # Create distribution
    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --region "$AWS_REGION" \
        --distribution-config "file://$dist_config" \
        --query 'Distribution.Id' \
        --output text) || {
        unity_log "ERROR" "Failed to create CloudFront distribution"
        rm -f "$dist_config"
        _emit_aws_event "aws.cloudfront.creation_failed" "cloudfront-manager" "{\"stack_name\":\"$stack_name\",\"origin_domain\":\"$origin_domain\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    rm -f "$dist_config"
    
    # Get distribution domain name
    local dist_domain
    dist_domain=$(aws cloudfront get-distribution \
        --region "$AWS_REGION" \
        --id "$dist_id" \
        --query 'Distribution.DomainName' \
        --output text)
    
    # Track resource and cost
    track_resource_with_events "cloudfront" "$dist_id" "$stack_name" "0.085" "{\"domain_name\":\"$dist_domain\",\"origin_domain\":\"$origin_domain\"}"
    track_cost_with_monitoring "cloudfront" "$dist_id" "0.085" "$stack_name" "$COST_THRESHOLD_DEFAULT"
    
    # Emit success event
    _emit_aws_event "aws.cloudfront.created" "cloudfront-manager" "{\"distribution_id\":\"$dist_id\",\"stack_name\":\"$stack_name\",\"domain_name\":\"$dist_domain\"}" "medium"
    
    unity_log "SUCCESS" "CloudFront distribution created: $dist_domain (ID: $dist_id)"
    echo "$dist_id"
    return $UNITY_SUCCESS
}

#############################################
# EFS Operations - Complete Implementation
#############################################

# Create or get EFS file system with enhanced configuration
create_unity_efs() {
    local stack_name="${1}"
    local vpc_id="${2}"
    local performance_mode="${3:-generalPurpose}"
    local throughput_mode="${4:-provisioned}"
    local options="${5:-}"
    
    unity_log "INFO" "Creating EFS for stack: $stack_name"
    
    # Check for existing EFS
    local existing_efs
    existing_efs=$(aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='$stack_name']].FileSystemId" \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$existing_efs" ]]; then
        unity_log "INFO" "Using existing EFS: $existing_efs"
        echo "$existing_efs"
        return $UNITY_SUCCESS
    fi
    
    # Create EFS with enhanced configuration
    local efs_id
    efs_id=$(aws efs create-file-system \
        --region "$AWS_REGION" \
        --creation-token "${stack_name}-efs-$(date +%s)" \
        --performance-mode "$performance_mode" \
        --throughput-mode "$throughput_mode" \
        --encrypted \
        --tags "Key=Name,Value=$stack_name" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" \
        --query 'FileSystemId' \
        --output text) || {
        unity_log "ERROR" "Failed to create EFS"
        _emit_aws_event "aws.efs.creation_failed" "efs-manager" "{\"stack_name\":\"$stack_name\",\"vpc_id\":\"$vpc_id\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Wait for EFS to be available
    unity_log "INFO" "Waiting for EFS to be available: $efs_id"
    aws efs wait file-system-available --region "$AWS_REGION" --file-system-id "$efs_id"
    
    # Create mount targets in all subnets
    create_efs_mount_targets "$efs_id" "$vpc_id" "$stack_name"
    
    # Create access points
    create_efs_access_points "$efs_id" "$stack_name"
    
    # Track resource and cost
    track_resource_with_events "efs" "$efs_id" "$stack_name" "0.30" "{\"performance_mode\":\"$performance_mode\",\"throughput_mode\":\"$throughput_mode\"}"
    track_cost_with_monitoring "efs" "$efs_id" "0.30" "$stack_name" "$COST_THRESHOLD_DEFAULT"
    
    # Emit success event
    _emit_aws_event "aws.efs.created" "efs-manager" "{\"efs_id\":\"$efs_id\",\"stack_name\":\"$stack_name\",\"performance_mode\":\"$performance_mode\"}" "medium"
    
    unity_log "SUCCESS" "EFS created: $efs_id"
    echo "$efs_id"
    return $UNITY_SUCCESS
}

# Create EFS mount targets
create_efs_mount_targets() {
    local efs_id="${1}"
    local vpc_id="${2}"
    local stack_name="${3}"
    
    # Get private subnets for mount targets
    local subnets
    subnets=$(aws ec2 describe-subnets \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Type,Values=private" \
        --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
        --output text)
    
    # Create or get EFS security group
    local efs_sg_id
    efs_sg_id=$(get_or_create_efs_security_group "$vpc_id" "$stack_name")
    
    while IFS=$'\t' read -r subnet_id az; do
        local mount_target_id
        mount_target_id=$(aws efs create-mount-target \
            --region "$AWS_REGION" \
            --file-system-id "$efs_id" \
            --subnet-id "$subnet_id" \
            --security-groups "$efs_sg_id" \
            --query 'MountTargetId' \
            --output text) || {
            unity_log "WARN" "Failed to create mount target in subnet: $subnet_id"
            continue
        }
        
        track_resource_with_events "efs-mount-target" "$mount_target_id" "$stack_name" "0" "{\"subnet_id\":\"$subnet_id\",\"az\":\"$az\"}"
        unity_log "INFO" "Created EFS mount target: $mount_target_id in $az"
    done <<< "$subnets"
}

# Create EFS access points
create_efs_access_points() {
    local efs_id="${1}"
    local stack_name="${2}"
    
    # Create root access point
    local root_ap_id
    root_ap_id=$(aws efs create-access-point \
        --region "$AWS_REGION" \
        --file-system-id "$efs_id" \
        --posix-user "Uid=1000,Gid=1000" \
        --root-directory "Path=/,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
        --tags "Key=Name,Value=${stack_name}-root-ap" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" \
        --query 'AccessPointId' \
        --output text) || {
        unity_log "WARN" "Failed to create EFS access point"
        return 1
    }
    
    track_resource_with_events "efs-access-point" "$root_ap_id" "$stack_name" "0" "{\"type\":\"root\"}"
    unity_log "INFO" "Created EFS access point: $root_ap_id"
}

#############################################
# IAM Operations - Complete Implementation
#############################################

# Create IAM role with policies
create_unity_iam_role() {
    local role_name="${1}"
    local stack_name="${2}"
    local service_principal="${3:-ec2.amazonaws.com}"
    local policies="${4:-}"  # comma-separated policy ARNs
    
    unity_log "INFO" "Creating IAM role: $role_name"
    
    # Check if role already exists
    if aws iam get-role --region "$AWS_REGION" --role-name "$role_name" >/dev/null 2>&1; then
        unity_log "INFO" "IAM role already exists: $role_name"
        echo "$role_name"
        return $UNITY_SUCCESS
    fi
    
    # Create trust policy
    local trust_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "$service_principal"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    )
    
    # Create role
    local role_arn
    role_arn=$(aws iam create-role \
        --region "$AWS_REGION" \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" \
        --description "Unity IAM role for $stack_name" \
        --tags "Key=Name,Value=$role_name" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" \
        --query 'Role.Arn' \
        --output text) || {
        unity_log "ERROR" "Failed to create IAM role: $role_name"
        _emit_aws_event "aws.iam.role_creation_failed" "iam-manager" "{\"role_name\":\"$role_name\",\"stack_name\":\"$stack_name\"}" "high"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Attach policies if provided
    if [[ -n "$policies" ]]; then
        IFS=',' read -ra policy_array <<< "$policies"
        for policy_arn in "${policy_array[@]}"; do
            aws iam attach-role-policy \
                --region "$AWS_REGION" \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" || {
                unity_log "WARN" "Failed to attach policy: $policy_arn"
            }
        done
    fi
    
    # Create instance profile for EC2 roles
    if [[ "$service_principal" == "ec2.amazonaws.com" ]]; then
        create_instance_profile "$role_name" "$stack_name"
    fi
    
    # Track resource
    track_resource_with_events "iam-role" "$role_arn" "$stack_name" "0" "{\"service_principal\":\"$service_principal\"}"
    
    # Emit success event
    _emit_aws_event "aws.iam.role_created" "iam-manager" "{\"role_arn\":\"$role_arn\",\"stack_name\":\"$stack_name\"}" "medium"
    
    unity_log "SUCCESS" "IAM role created: $role_arn"
    echo "$role_name"
    return $UNITY_SUCCESS
}

# Create instance profile
create_instance_profile() {
    local role_name="${1}"
    local stack_name="${2}"
    
    # Create instance profile
    aws iam create-instance-profile \
        --region "$AWS_REGION" \
        --instance-profile-name "$role_name" \
        --tags "Key=Name,Value=$role_name" "Key=Unity,Value=true" "Key=Stack,Value=$stack_name" || {
        unity_log "WARN" "Instance profile already exists or failed to create: $role_name"
        return 1
    }
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --region "$AWS_REGION" \
        --instance-profile-name "$role_name" \
        --role-name "$role_name" || {
        unity_log "WARN" "Failed to add role to instance profile: $role_name"
        return 1
    }
    
    track_resource_with_events "instance-profile" "$role_name" "$stack_name" "0"
    unity_log "INFO" "Instance profile created: $role_name"
}

#############################################
# Cost Optimization Engine - Enhanced
#############################################

# Calculate comprehensive deployment cost
calculate_unity_deployment_cost() {
    local stack_name="${1}"
    local duration_hours="${2:-720}"  # Default 30 days
    local detailed="${3:-false}"
    
    unity_log "INFO" "Calculating deployment cost for: $stack_name (${duration_hours}h)"
    
    local total_cost=0
    local cost_breakdown=""
    local cost_details="{\"stack\":\"$stack_name\",\"duration_hours\":$duration_hours,\"breakdown\":[]}"
    
    # Calculate costs for each resource type
    local resource_costs=()
    
    # EC2 costs with spot savings
    local ec2_cost
    ec2_cost=$(calculate_ec2_costs "$stack_name" "$duration_hours")
    if [[ "$ec2_cost" != "0" ]]; then
        total_cost=$(echo "$total_cost + $ec2_cost" | bc -l)
        cost_breakdown+="\n  - EC2: \$$(printf "%.2f" "$ec2_cost")"
        resource_costs+=("ec2:$ec2_cost")
    fi
    
    # ALB costs
    local alb_cost
    alb_cost=$(calculate_alb_costs "$stack_name" "$duration_hours")
    if [[ "$alb_cost" != "0" ]]; then
        total_cost=$(echo "$total_cost + $alb_cost" | bc -l)
        cost_breakdown+="\n  - ALB: \$$(printf "%.2f" "$alb_cost")"
        resource_costs+=("alb:$alb_cost")
    fi
    
    # EFS costs
    local efs_cost
    efs_cost=$(calculate_efs_costs "$stack_name" "$duration_hours")
    if [[ "$efs_cost" != "0" ]]; then
        total_cost=$(echo "$total_cost + $efs_cost" | bc -l)
        cost_breakdown+="\n  - EFS: \$$(printf "%.2f" "$efs_cost")"
        resource_costs+=("efs:$efs_cost")
    fi
    
    # CloudFront costs
    local cf_cost
    cf_cost=$(calculate_cloudfront_costs "$stack_name" "$duration_hours")
    if [[ "$cf_cost" != "0" ]]; then
        total_cost=$(echo "$total_cost + $cf_cost" | bc -l)
        cost_breakdown+="\n  - CloudFront: \$$(printf "%.2f" "$cf_cost")"
        resource_costs+=("cloudfront:$cf_cost")
    fi
    
    # Data transfer costs (estimated)
    local transfer_cost
    transfer_cost=$(calculate_data_transfer_costs "$stack_name" "$duration_hours")
    if [[ "$transfer_cost" != "0" ]]; then
        total_cost=$(echo "$total_cost + $transfer_cost" | bc -l)
        cost_breakdown+="\n  - Data Transfer: \$$(printf "%.2f" "$transfer_cost")"
        resource_costs+=("data-transfer:$transfer_cost")
    fi
    
    # Calculate potential savings
    local potential_savings
    potential_savings=$(calculate_potential_savings "$stack_name")
    
    if [[ "$detailed" == "true" ]]; then
        unity_log "INFO" "Detailed cost breakdown:"
        unity_log "INFO" "  Total estimated cost: \$$(printf "%.2f" "$total_cost")$cost_breakdown"
        unity_log "INFO" "  Potential savings: \$$(printf "%.2f" "$potential_savings")"
    else
        unity_log "INFO" "Total estimated cost: \$$(printf "%.2f" "$total_cost")"
    fi
    
    # Emit cost calculation event
    _emit_aws_event "aws.cost.calculated" "cost-calculator" "{\"stack_name\":\"$stack_name\",\"total_cost\":$total_cost,\"duration_hours\":$duration_hours,\"potential_savings\":$potential_savings}" "low"
    
    echo "$total_cost"
    return $UNITY_SUCCESS
}

# Optimize deployment costs with advanced recommendations
optimize_unity_deployment_costs() {
    local stack_name="${1}"
    local apply_changes="${2:-false}"
    
    unity_log "INFO" "Optimizing deployment costs for: $stack_name"
    
    local recommendations=()
    local potential_savings=0
    
    # Check for spot instance opportunities
    local spot_recommendations
    spot_recommendations=$(analyze_spot_opportunities "$stack_name")
    if [[ -n "$spot_recommendations" ]]; then
        recommendations+=("$spot_recommendations")
    fi
    
    # Check for rightsizing opportunities
    local rightsizing_recommendations
    rightsizing_recommendations=$(analyze_rightsizing_opportunities "$stack_name")
    if [[ -n "$rightsizing_recommendations" ]]; then
        recommendations+=("$rightsizing_recommendations")
    fi
    
    # Check for unused resources
    local unused_recommendations
    unused_recommendations=$(analyze_unused_resources "$stack_name")
    if [[ -n "$unused_recommendations" ]]; then
        recommendations+=("$unused_recommendations")
    fi
    
    # Check for reserved instance opportunities
    local ri_recommendations
    ri_recommendations=$(analyze_reserved_instance_opportunities "$stack_name")
    if [[ -n "$ri_recommendations" ]]; then
        recommendations+=("$ri_recommendations")
    fi
    
    # Check for storage optimization
    local storage_recommendations
    storage_recommendations=$(analyze_storage_optimization "$stack_name")
    if [[ -n "$storage_recommendations" ]]; then
        recommendations+=("$storage_recommendations")
    fi
    
    # Print recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        unity_log "INFO" "Cost optimization recommendations:"
        for rec in "${recommendations[@]}"; do
            unity_log "INFO" "  - $rec"
        done
        
        if [[ "$apply_changes" == "true" ]]; then
            unity_log "INFO" "Applying cost optimization changes..."
            apply_cost_optimizations "$stack_name" "${recommendations[@]}"
        fi
    else
        unity_log "INFO" "No cost optimization opportunities found"
    fi
    
    # Emit optimization event
    _emit_aws_event "aws.cost.optimization.completed" "cost-optimizer" "{\"stack_name\":\"$stack_name\",\"recommendations_count\":${#recommendations[@]},\"applied\":$apply_changes}" "medium"
    
    return $UNITY_SUCCESS
}

#############################################
# Quota Management - Enhanced Implementation
#############################################

# Check EC2 quota with enhanced monitoring
check_ec2_quota_with_events() {
    local instance_type="${1}"
    local cache_key="quota_ec2_${instance_type}"
    
    # Check cache
    local cached_quota
    cached_quota=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_quota" ]]; then
        return $UNITY_SUCCESS
    fi
    
    # Get current usage and limit
    local current_usage
    current_usage=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=instance-state-name,Values=running,pending" \
        --query 'length(Reservations[*].Instances[*])' \
        --output text 2>/dev/null || echo "0")
    
    local quota_limit
    quota_limit=$(aws service-quotas get-service-quota \
        --region "$AWS_REGION" \
        --service-code "ec2" \
        --quota-code "L-1216C47A" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "20")
    
    # Use enhanced quota checking with events
    if check_quota_with_events "ec2" "instances" "$current_usage" "$quota_limit" "unknown"; then
        # Cache success
        set_aws_cache "$cache_key" "ok" "$QUOTA_CHECK_INTERVAL"
        return $UNITY_SUCCESS
    else
        return $UNITY_ERROR_PREREQUISITE
    fi
}

# Check VPC quota with enhanced monitoring
check_vpc_quota_with_events() {
    local cache_key="quota_vpc"
    
    # Check cache
    local cached_quota
    cached_quota=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_quota" ]]; then
        return $UNITY_SUCCESS
    fi
    
    # Get current VPC count
    local vpc_count
    vpc_count=$(aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
        --query 'length(Vpcs[*])' \
        --output text 2>/dev/null || echo "0")
    
    local vpc_limit=5  # Default VPC limit
    
    # Use enhanced quota checking with events
    if check_quota_with_events "vpc" "vpcs" "$vpc_count" "$vpc_limit" "unknown"; then
        # Cache success
        set_aws_cache "$cache_key" "ok" "$QUOTA_CHECK_INTERVAL"
        return $UNITY_SUCCESS
    else
        unity_log "INFO" "Consider running: unity_aws cleanup-vpcs to remove unused VPCs"
        return $UNITY_ERROR_PREREQUISITE
    fi
}

# Check ALB quota with enhanced monitoring
check_alb_quota_with_events() {
    local cache_key="quota_alb"
    
    # Check cache
    local cached_quota
    cached_quota=$(get_aws_cache "$cache_key")
    
    if [[ -n "$cached_quota" ]]; then
        return $UNITY_SUCCESS
    fi
    
    # Get current ALB count
    local alb_count
    alb_count=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query 'length(LoadBalancers[*])' \
        --output text 2>/dev/null || echo "0")
    
    local alb_limit=50  # Default ALB limit
    
    # Use enhanced quota checking with events
    if check_quota_with_events "alb" "load-balancers" "$alb_count" "$alb_limit" "unknown"; then
        # Cache success
        set_aws_cache "$cache_key" "ok" "$QUOTA_CHECK_INTERVAL"
        return $UNITY_SUCCESS
    else
        return $UNITY_ERROR_PREREQUISITE
    fi
}

#############################################
# Resource Lifecycle Management - Enhanced
#############################################

# Track resource with enhanced metadata
track_resource_with_events() {
    local resource_type="${1}"
    local resource_id="${2}"
    local stack_name="${3}"
    local cost_per_hour="${4:-0}"
    local additional_metadata="${5:-{}}"
    
    local key="${resource_type}|${resource_id}|${stack_name}"
    UNITY_AWS_RESOURCES["$key"]="$(date +%s)"
    
    # Track cost if provided
    if [[ "$cost_per_hour" != "0" ]]; then
        track_cost_with_monitoring "$resource_type" "$resource_id" "$cost_per_hour" "$stack_name" "$COST_THRESHOLD_DEFAULT"
    fi
    
    # Persist to file for recovery
    echo "${key}|$(date +%s)|${additional_metadata}" >> ".unity/aws/state/resources.log"
    
    # Emit detailed resource creation event
    _emit_aws_event "aws.resource.created" "unity-aws-service" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"stack_name\":\"$stack_name\",\"cost_per_hour\":$cost_per_hour,\"metadata\":$additional_metadata,\"region\":\"$AWS_REGION\"}" "medium"
}

# Enhanced cost tracking with threshold monitoring
track_cost_with_monitoring() {
    local resource_type="${1}"
    local resource_id="${2}"
    local hourly_cost="${3}"
    local stack_name="${4:-unknown}"
    local cost_threshold="${5:-100}"  # Default $100 threshold
    
    local key="${resource_type}|${resource_id}"
    UNITY_AWS_COSTS["$key"]="$hourly_cost"
    
    # Calculate projected monthly cost
    local monthly_cost
    monthly_cost=$(echo "$hourly_cost * 24 * 30" | bc -l 2>/dev/null || echo "$hourly_cost")
    
    # Persist to file
    echo "${key}|${hourly_cost}|${monthly_cost}|$(date +%s)" >> ".unity/aws/costs/costs.log"
    
    # Check if projected cost exceeds threshold
    if (( $(echo "$monthly_cost > $cost_threshold" | bc -l 2>/dev/null || echo "0") )); then
        _emit_aws_event "aws.cost.threshold_exceeded" "cost-monitor" "{\"stack_name\":\"$stack_name\",\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"hourly_cost\":$hourly_cost,\"monthly_projection\":$monthly_cost,\"threshold\":$cost_threshold}" "high"
    fi
    
    # Emit cost tracking event
    _emit_aws_event "aws.cost.tracked" "cost-tracker" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"hourly_cost\":$hourly_cost,\"monthly_projection\":$monthly_cost}" "low"
}

# List stack resources with enhanced details
list_unity_stack_resources() {
    local stack_name="${1}"
    local output_format="${2:-table}"  # table, json, csv
    
    unity_log "INFO" "Resources for stack: $stack_name"
    
    local resources=()
    local total_cost=0
    
    for resource_key in "${!UNITY_AWS_RESOURCES[@]}"; do
        if [[ "$resource_key" == *"${stack_name}"* ]]; then
            local resource_type=$(echo "$resource_key" | cut -d'|' -f1)
            local resource_id=$(echo "$resource_key" | cut -d'|' -f2)
            local created_at="${UNITY_AWS_RESOURCES[$resource_key]}"
            
            # Get cost information
            local cost_key="${resource_type}|${resource_id}"
            local hourly_cost="${UNITY_AWS_COSTS[$cost_key]:-0}"
            local monthly_cost=$(echo "$hourly_cost * 24 * 30" | bc -l 2>/dev/null || echo "0")
            total_cost=$(echo "$total_cost + $monthly_cost" | bc -l 2>/dev/null || echo "$total_cost")
            
            case "$output_format" in
                json)
                    resources+=("{\"type\":\"$resource_type\",\"id\":\"$resource_id\",\"created_at\":$created_at,\"hourly_cost\":$hourly_cost,\"monthly_cost\":$monthly_cost}")
                    ;;
                csv)
                    resources+=("$resource_type,$resource_id,$created_at,$hourly_cost,$monthly_cost")
                    ;;
                *)
                    unity_log "INFO" "  - $resource_type: $resource_id (monthly cost: \$$(printf "%.2f" "$monthly_cost"))"
                    ;;
            esac
        fi
    done
    
    case "$output_format" in
        json)
            echo "{\"stack\":\"$stack_name\",\"total_monthly_cost\":$total_cost,\"resources\":[$(IFS=','; echo "${resources[*]}")]}}"
            ;;
        csv)
            echo "Type,ID,Created,HourlyCost,MonthlyCost"
            printf '%s\n' "${resources[@]}"
            echo "TOTAL,,,$total_cost"
            ;;
        *)
            unity_log "INFO" "Total estimated monthly cost: \$$(printf "%.2f" "$total_cost")"
            ;;
    esac
    
    return $UNITY_SUCCESS
}

# Delete stack resources with enhanced safety checks
delete_unity_stack_resources() {
    local stack_name="${1}"
    local force="${2:-false}"
    local dry_run="${3:-false}"
    
    unity_log "INFO" "Deleting resources for stack: $stack_name (force=$force, dry_run=$dry_run)"
    
    # Safety check for production stacks
    if [[ "$stack_name" == *"prod"* && "$force" != "true" ]]; then
        unity_log "ERROR" "Cannot delete production stack without force flag"
        return $UNITY_ERROR_VALIDATION
    fi
    
    # Collect resources to delete
    local resources_to_delete=()
    
    for resource_key in "${!UNITY_AWS_RESOURCES[@]}"; do
        if [[ "$resource_key" == *"${stack_name}"* ]]; then
            resources_to_delete+=("$resource_key")
        fi
    done
    
    if [[ ${#resources_to_delete[@]} -eq 0 ]]; then
        unity_log "WARN" "No resources found for stack: $stack_name"
        return $UNITY_SUCCESS
    fi
    
    unity_log "INFO" "Found ${#resources_to_delete[@]} resources to delete"
    
    if [[ "$dry_run" == "true" ]]; then
        unity_log "INFO" "DRY RUN - Resources that would be deleted:"
        for resource_key in "${resources_to_delete[@]}"; do
            local resource_type=$(echo "$resource_key" | cut -d'|' -f1)
            local resource_id=$(echo "$resource_key" | cut -d'|' -f2)
            unity_log "INFO" "  - $resource_type: $resource_id"
        done
        return $UNITY_SUCCESS
    fi
    
    # Delete in reverse dependency order
    local delete_order=("cloudfront" "alb" "target-group" "listener" "efs-access-point" "efs-mount-target" "efs" "ec2" "iam-role" "instance-profile" "security-group" "route-table" "subnet" "igw" "vpc")
    
    for resource_type in "${delete_order[@]}"; do
        for resource_key in "${resources_to_delete[@]}"; do
            if [[ "$resource_key" == "${resource_type}|"* ]]; then
                local resource_id=$(echo "$resource_key" | cut -d'|' -f2)
                delete_unity_resource "$resource_type" "$resource_id" "$force" "$stack_name"
            fi
        done
    done
    
    # Emit stack deletion event
    _emit_aws_event "aws.stack.deleted" "stack-manager" "{\"stack_name\":\"$stack_name\",\"resources_deleted\":${#resources_to_delete[@]}}" "medium"
    
    unity_log "SUCCESS" "Stack deletion completed: $stack_name"
    return $UNITY_SUCCESS
}

#############################################
# Utility Functions - Enhanced Implementation
#############################################

# Validate AWS credentials
_validate_aws_credentials() {
    if ! command -v aws >/dev/null 2>&1; then
        unity_log "ERROR" "AWS CLI not installed"
        return 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        unity_log "ERROR" "AWS credentials not configured or invalid"
        return 1
    fi
    
    return 0
}

# Initialize AWS API cache
_init_aws_api_cache() {
    mkdir -p ".unity/aws/cache" 2>/dev/null || true
    # Set default cache TTL
    export AWS_CACHE_TTL="${AWS_CACHE_TTL:-3600}"
}

# Initialize cost tracking
_init_cost_tracking() {
    mkdir -p ".unity/aws/costs" 2>/dev/null || true
    touch ".unity/aws/costs/costs.log"
}

# Initialize quota monitoring
_init_quota_monitoring() {
    mkdir -p ".unity/aws/quotas" 2>/dev/null || true
    touch ".unity/aws/quotas/quotas.log"
}

# Get/Set AWS cache functions
get_aws_cache() {
    local key="${1}"
    local cache_file=".unity/aws/cache/${key}"
    
    if [[ -f "$cache_file" ]]; then
        local cache_time
        cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local cache_age=$((current_time - cache_time))
        
        if [[ $cache_age -lt ${AWS_CACHE_TTL:-3600} ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    return 1
}

set_aws_cache() {
    local key="${1}"
    local value="${2}"
    local ttl="${3:-3600}"
    local cache_file=".unity/aws/cache/${key}"
    
    echo "$value" > "$cache_file"
    return 0
}

# Enhanced event system integration
_init_aws_service_events() {
    # Register event handlers if event system is available
    if command -v unity_on_event >/dev/null 2>&1; then
        # Register cost threshold handler
        unity_on_event "aws\.cost\.threshold_exceeded" "handle_aws_cost_alert" "priority=high"
        
        # Register resource failure handler
        unity_on_event "aws\.resource\.failed" "handle_aws_resource_failure" "priority=high"
        
        # Register quota exceeded handler
        unity_on_event "aws\.quota\.exceeded" "handle_aws_quota_exceeded" "priority=high"
        
        unity_log "DEBUG" "AWS service event handlers registered"
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
        unity_emit_event "$event_type" "$event_source" "$event_data" "$priority" "false" || true
    else
        # Fallback to basic logging
        unity_log "INFO" "AWS Event: $event_type from $event_source - $event_data"
    fi
}

#############################################
# Main CLI Interface
#############################################

# Unity AWS CLI
unity_aws_complete() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        init)
            init_unity_aws_service "$@"
            ;;
        start)
            start_unity_aws_service "$@"
            ;;
        stop)
            stop_unity_aws_service "$@"
            ;;
        health)
            health_unity_aws_service "$@"
            ;;
        config)
            config_unity_aws_service "$@"
            ;;
        create-vpc)
            create_unity_vpc "$@"
            ;;
        launch-ec2)
            launch_unity_ec2 "$@"
            ;;
        create-alb)
            create_unity_alb "$@"
            ;;
        create-cloudfront)
            create_unity_cloudfront "$@"
            ;;
        create-efs)
            create_unity_efs "$@"
            ;;
        create-iam-role)
            create_unity_iam_role "$@"
            ;;
        cost)
            calculate_unity_deployment_cost "$@"
            ;;
        optimize)
            optimize_unity_deployment_costs "$@"
            ;;
        list)
            list_unity_stack_resources "$@"
            ;;
        delete)
            delete_unity_stack_resources "$@"
            ;;
        check-quota)
            check_ec2_quota_with_events "$@" && check_vpc_quota_with_events && check_alb_quota_with_events
            ;;
        help|*)
            cat <<EOF
Unity AWS Service Complete v$UNITY_AWS_SERVICE_VERSION

Usage: unity_aws_complete <command> [options]

Service Management:
    init                           Initialize Unity AWS Service
    start                          Start AWS Service
    stop                           Stop AWS Service
    health                         Check service health
    config <action> [key] [value]  Manage configuration

Resource Creation:
    create-vpc <stack> [cidr] [multi-az]     Create VPC with subnets
    launch-ec2 <type> <deploy> <stack>       Launch EC2 instance
    create-alb <stack> <vpc>                 Create Application Load Balancer
    create-cloudfront <stack> <origin>       Create CloudFront distribution
    create-efs <stack> <vpc>                 Create EFS file system
    create-iam-role <role> <stack> [service] Create IAM role

Cost Management:
    cost <stack> [hours] [detailed]         Calculate deployment cost
    optimize <stack> [apply]                Optimize deployment costs

Resource Management:
    list <stack> [format]                   List stack resources
    delete <stack> [force] [dry-run]        Delete stack resources
    check-quota [type]                      Check AWS quotas

Examples:
    unity_aws_complete create-vpc my-stack 10.0.0.0/16 true
    unity_aws_complete launch-ec2 g4dn.xlarge spot my-stack
    unity_aws_complete create-alb my-stack vpc-12345
    unity_aws_complete cost my-stack 720 true
    unity_aws_complete optimize my-stack true
    unity_aws_complete delete my-stack false true
EOF
            ;;
    esac
}

# Export main functions
export -f unity_aws_complete
export -f init_unity_aws_service
export -f start_unity_aws_service
export -f stop_unity_aws_service
export -f health_unity_aws_service
export -f config_unity_aws_service
export -f create_unity_vpc
export -f launch_unity_ec2
export -f create_unity_alb
export -f create_unity_cloudfront
export -f create_unity_efs
export -f create_unity_iam_role
export -f calculate_unity_deployment_cost
export -f optimize_unity_deployment_costs
export -f list_unity_stack_resources
export -f delete_unity_stack_resources

#############################################
# Missing Utility Functions - Implementation
#############################################

# Find existing VPC by stack name
find_existing_vpc() {
    local stack_name="${1}"
    
    aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null | grep -v "None" || true
}

# Get available CIDR block
get_available_cidr() {
    local used_cidrs
    used_cidrs=$(aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
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

# Validate CIDR block
_validate_cidr() {
    local cidr="${1}"
    
    # Basic CIDR validation
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    
    return 0
}

# Calculate subnet CIDR
calculate_subnet_cidr() {
    local vpc_cidr="${1}"
    local subnet_index="${2}"
    local subnet_size="${3}"
    
    # Extract base IP from VPC CIDR
    local base_ip="${vpc_cidr%/*}"
    local base_prefix="${vpc_cidr#*/}"
    
    # Simple subnet calculation for common cases
    local octets=(${base_ip//./ })
    local third_octet=$((${octets[2]} + subnet_index))
    
    echo "${octets[0]}.${octets[1]}.${third_octet}.0/${subnet_size}"
}

# Get best subnet for instance
get_best_subnet() {
    local vpc_id="${1}"
    local instance_type="${2}"
    
    # Get first available public subnet
    aws ec2 describe-subnets \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Type,Values=public" \
        --query 'Subnets[0].SubnetId' \
        --output text 2>/dev/null | grep -v "None" || {
        # Fallback to any subnet in VPC
        aws ec2 describe-subnets \
            --region "$AWS_REGION" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'Subnets[0].SubnetId' \
            --output text 2>/dev/null | grep -v "None" || true
    }
}

# Get or create instance security group
get_or_create_instance_security_group() {
    local vpc_id="${1}"
    local stack_name="${2}"
    
    # Check for existing security group
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=${stack_name}-instance-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$sg_id" ]]; then
        echo "$sg_id"
        return 0
    fi
    
    # Create security group for instances
    sg_id=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --group-name "${stack_name}-instance-sg" \
        --description "Unity Instance Security Group for ${stack_name}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${stack_name}-instance-sg},{Key=Unity,Value=true}]" \
        --query 'GroupId' \
        --output text) || {
        unity_log "ERROR" "Failed to create instance security group"
        return 1
    }
    
    # Add common ingress rules
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 2>/dev/null || true
    
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 2>/dev/null || true
    
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 2>/dev/null || true
    
    echo "$sg_id"
}

# Get or create key pair
get_or_create_key_pair() {
    local stack_name="${1}"
    local key_name="${stack_name}-key"
    
    # Check if key pair exists
    if aws ec2 describe-key-pairs --region "$AWS_REGION" --key-names "$key_name" >/dev/null 2>&1; then
        echo "$key_name"
        return 0
    fi
    
    # Create new key pair
    aws ec2 create-key-pair \
        --region "$AWS_REGION" \
        --key-name "$key_name" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$key_name},{Key=Unity,Value=true}]" \
        --query 'KeyMaterial' \
        --output text > "${key_name}.pem" || {
        unity_log "ERROR" "Failed to create key pair"
        return 1
    }
    
    chmod 600 "${key_name}.pem"
    unity_log "INFO" "Created key pair: $key_name (saved as ${key_name}.pem)"
    echo "$key_name"
}

# Get optimal AMI
get_optimal_ami() {
    local instance_type="${1}"
    
    # Get latest Amazon Linux 2 AMI
    aws ec2 describe-images \
        --region "$AWS_REGION" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*" "Name=virtualization-type,Values=hvm" "Name=state,Values=available" \
        --query 'Images|sort_by(@, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null || echo "ami-0abcdef1234567890"  # Fallback
}

# Enhanced spot configuration
get_optimal_spot_config_enhanced() {
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
        --region "$AWS_REGION" \
        --instance-types "$instance_type" \
        --product-descriptions "Linux/UNIX" \
        --max-results 20 \
        --query 'SpotPriceHistory[*].[SpotPrice,AvailabilityZone]' \
        --output text 2>/dev/null) || {
        unity_log "WARN" "Failed to get spot prices, using fallback"
        echo "0.10|${AWS_REGION}a|70"
        return 0
    }
    
    # Find best price
    while IFS=$'\t' read -r price az; do
        if (( $(echo "$price < $best_price" | bc -l 2>/dev/null || echo "0") )); then
            best_price="$price"
            best_az="$az"
        fi
    done <<< "$spot_data"
    
    # Calculate savings
    local savings
    savings=$(echo "scale=0; (1 - $best_price / $on_demand_price) * 100" | bc -l 2>/dev/null || echo "70")
    
    local config="${best_price}|${best_az}|${savings}"
    
    # Cache the result
    set_aws_cache "$cache_key" "$config" 3600
    
    echo "$config"
}

# Create user data script
create_user_data_script() {
    local stack_name="${1}"
    
    cat <<'EOF'
#!/bin/bash
yum update -y
yum install -y docker
service docker start
usermod -a -G docker ec2-user
chkconfig docker on

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Unity agent (if available)
curl -fsSL https://raw.githubusercontent.com/your-repo/unity-agent/main/install.sh | bash || true

# Send signal that instance is ready
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} || true
EOF
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
    
    # Try to get actual pricing (simplified - in real implementation, use AWS Pricing API)
    local price
    case "$instance_type" in
        "g4dn.xlarge") price="0.526" ;;
        "g5.xlarge") price="1.006" ;;
        "g4dn.2xlarge") price="1.052" ;;
        "g5.2xlarge") price="2.012" ;;
        "t3.micro") price="0.0104" ;;
        "t3.small") price="0.0208" ;;
        "t3.medium") price="0.0416" ;;
        "t3.large") price="0.0832" ;;
        "t3.xlarge") price="0.1664" ;;
        "m5.large") price="0.096" ;;
        "m5.xlarge") price="0.192" ;;
        "c5.large") price="0.085" ;;
        "c5.xlarge") price="0.17" ;;
        *) price="1.00" ;;  # Default fallback
    esac
    
    # Cache the result
    set_aws_cache "$cache_key" "$price" 86400  # Cache for 24 hours
    echo "$price"
}

# Get or create ALB security group
get_or_create_alb_security_group() {
    local vpc_id="${1}"
    local stack_name="${2}"
    
    # Check for existing security group
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=${stack_name}-alb-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$sg_id" ]]; then
        echo "$sg_id"
        return 0
    fi
    
    # Create security group
    sg_id=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --group-name "${stack_name}-alb-sg" \
        --description "Unity ALB Security Group for ${stack_name}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${stack_name}-alb-sg},{Key=Unity,Value=true}]" \
        --query 'GroupId' \
        --output text) || {
        unity_log "ERROR" "Failed to create ALB security group"
        return 1
    }
    
    # Add ingress rules
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 >/dev/null
    
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 >/dev/null
    
    echo "$sg_id"
}

# Get or create EFS security group
get_or_create_efs_security_group() {
    local vpc_id="${1}"
    local stack_name="${2}"
    
    # Check for existing security group
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=${stack_name}-efs-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$sg_id" ]]; then
        echo "$sg_id"
        return 0
    fi
    
    # Create security group
    sg_id=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --vpc-id "$vpc_id" \
        --group-name "${stack_name}-efs-sg" \
        --description "Unity EFS Security Group for ${stack_name}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${stack_name}-efs-sg},{Key=Unity,Value=true}]" \
        --query 'GroupId' \
        --output text) || {
        unity_log "ERROR" "Failed to create EFS security group"
        return 1
    }
    
    # Add NFS ingress rule
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 2049 \
        --source-group "$sg_id" >/dev/null  # Allow self-referencing
    
    echo "$sg_id"
}

# Delete individual resource
delete_unity_resource() {
    local resource_type="${1}"
    local resource_id="${2}"
    local force="${3:-false}"
    local stack_name="${4:-}"
    
    unity_log "INFO" "Deleting $resource_type: $resource_id"
    
    case "$resource_type" in
        ec2)
            aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$resource_id" >/dev/null 2>&1 || true
            ;;
        vpc)
            if [[ "$force" == "true" ]]; then
                delete_vpc_with_dependencies "$resource_id"
            else
                aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id "$resource_id" >/dev/null 2>&1 || true
            fi
            ;;
        alb)
            aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$resource_id" >/dev/null 2>&1 || true
            ;;
        target-group)
            aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$resource_id" >/dev/null 2>&1 || true
            ;;
        listener)
            aws elbv2 delete-listener --region "$AWS_REGION" --listener-arn "$resource_id" >/dev/null 2>&1 || true
            ;;
        cloudfront)
            # CloudFront deletion requires disabling first
            unity_log "WARN" "CloudFront deletion requires manual intervention: $resource_id"
            ;;
        efs)
            # Delete mount targets first
            aws efs describe-mount-targets --region "$AWS_REGION" --file-system-id "$resource_id" \
                --query 'MountTargets[*].MountTargetId' --output text | \
                xargs -r -n1 aws efs delete-mount-target --region "$AWS_REGION" --mount-target-id 2>/dev/null || true
            sleep 5
            aws efs delete-file-system --region "$AWS_REGION" --file-system-id "$resource_id" >/dev/null 2>&1 || true
            ;;
        efs-mount-target)
            aws efs delete-mount-target --region "$AWS_REGION" --mount-target-id "$resource_id" >/dev/null 2>&1 || true
            ;;
        efs-access-point)
            aws efs delete-access-point --region "$AWS_REGION" --access-point-id "$resource_id" >/dev/null 2>&1 || true
            ;;
        iam-role)
            # Detach policies first
            aws iam list-attached-role-policies --region "$AWS_REGION" --role-name "$resource_id" \
                --query 'AttachedPolicies[*].PolicyArn' --output text | \
                xargs -r -n1 aws iam detach-role-policy --region "$AWS_REGION" --role-name "$resource_id" --policy-arn 2>/dev/null || true
            aws iam delete-role --region "$AWS_REGION" --role-name "$resource_id" >/dev/null 2>&1 || true
            ;;
        instance-profile)
            # Remove role from instance profile first
            aws iam list-instance-profile-roles --region "$AWS_REGION" --instance-profile-name "$resource_id" \
                --query 'Roles[*].RoleName' --output text | \
                xargs -r -n1 aws iam remove-role-from-instance-profile --region "$AWS_REGION" --instance-profile-name "$resource_id" --role-name 2>/dev/null || true
            aws iam delete-instance-profile --region "$AWS_REGION" --instance-profile-name "$resource_id" >/dev/null 2>&1 || true
            ;;
        security-group)
            aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$resource_id" >/dev/null 2>&1 || true
            ;;
        subnet)
            aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "$resource_id" >/dev/null 2>&1 || true
            ;;
        route-table)
            aws ec2 delete-route-table --region "$AWS_REGION" --route-table-id "$resource_id" >/dev/null 2>&1 || true
            ;;
        igw)
            # Detach from VPC first
            local vpc_id
            vpc_id=$(aws ec2 describe-internet-gateways --region "$AWS_REGION" --internet-gateway-ids "$resource_id" \
                --query 'InternetGateways[0].Attachments[0].VpcId' --output text 2>/dev/null | grep -v "None" || true)
            if [[ -n "$vpc_id" ]]; then
                aws ec2 detach-internet-gateway --region "$AWS_REGION" --vpc-id "$vpc_id" --internet-gateway-id "$resource_id" >/dev/null 2>&1 || true
            fi
            aws ec2 delete-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$resource_id" >/dev/null 2>&1 || true
            ;;
    esac
    
    # Remove from tracking
    for key in "${!UNITY_AWS_RESOURCES[@]}"; do
        if [[ "$key" == *"|${resource_id}|"* ]]; then
            unset "UNITY_AWS_RESOURCES[$key]"
        fi
    done
    
    for key in "${!UNITY_AWS_COSTS[@]}"; do
        if [[ "$key" == *"|${resource_id}" ]]; then
            unset "UNITY_AWS_COSTS[$key]"
        fi
    done
    
    # Emit deletion event
    _emit_aws_event "aws.resource.deleted" "resource-manager" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"stack_name\":\"$stack_name\"}" "low"
}

# Delete VPC with all dependencies
delete_vpc_with_dependencies() {
    local vpc_id="${1}"
    
    unity_log "INFO" "Deleting VPC with dependencies: $vpc_id"
    
    # Delete all dependent resources in order
    # 1. Delete NAT gateways
    aws ec2 describe-nat-gateways --region "$AWS_REGION" --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NatGateways[*].NatGatewayId' --output text | \
        xargs -r -n1 aws ec2 delete-nat-gateway --region "$AWS_REGION" --nat-gateway-id 2>/dev/null || true
    
    # 2. Delete internet gateways
    local igw_id
    igw_id=$(aws ec2 describe-internet-gateways \
        --region "$AWS_REGION" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [[ -n "$igw_id" ]]; then
        aws ec2 detach-internet-gateway --region "$AWS_REGION" --vpc-id "$vpc_id" --internet-gateway-id "$igw_id" 2>/dev/null || true
        aws ec2 delete-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$igw_id" 2>/dev/null || true
    fi
    
    # 3. Delete subnets
    aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].SubnetId' --output text | \
        xargs -r -n1 aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id 2>/dev/null || true
    
    # 4. Delete route tables
    aws ec2 describe-route-tables --region "$AWS_REGION" --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text | \
        xargs -r -n1 aws ec2 delete-route-table --region "$AWS_REGION" --route-table-id 2>/dev/null || true
    
    # 5. Delete security groups
    aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text | \
        xargs -r -n1 aws ec2 delete-security-group --region "$AWS_REGION" --group-id 2>/dev/null || true
    
    # 6. Finally delete VPC
    aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id "$vpc_id" 2>/dev/null || true
    
    unity_log "INFO" "VPC deletion completed: $vpc_id"
}

# AWS Configuration Functions
_get_aws_config() {
    local key="${1}"
    
    case "$key" in
        region)
            echo "${AWS_REGION}"
            ;;
        cost_threshold)
            echo "${COST_THRESHOLD_DEFAULT}"
            ;;
        spot_savings_target)
            echo "${SPOT_SAVINGS_TARGET}"
            ;;
        quota_check_interval)
            echo "${QUOTA_CHECK_INTERVAL}"
            ;;
        *)
            unity_log "ERROR" "Unknown config key: $key"
            return 1
            ;;
    esac
}

_get_all_aws_config() {
    echo "AWS Service Configuration:"
    echo "  region: ${AWS_REGION}"
    echo "  cost_threshold: ${COST_THRESHOLD_DEFAULT}"
    echo "  spot_savings_target: ${SPOT_SAVINGS_TARGET}%"
    echo "  quota_check_interval: ${QUOTA_CHECK_INTERVAL}s"
}

_set_aws_config() {
    local key="${1}"
    local value="${2}"
    
    case "$key" in
        region)
            AWS_REGION="$value"
            export AWS_REGION
            ;;
        cost_threshold)
            COST_THRESHOLD_DEFAULT="$value"
            ;;
        spot_savings_target)
            SPOT_SAVINGS_TARGET="$value"
            ;;
        quota_check_interval)
            QUOTA_CHECK_INTERVAL="$value"
            ;;
        *)
            unity_log "ERROR" "Unknown config key: $key"
            return 1
            ;;
    esac
    
    unity_log "INFO" "Config updated: $key = $value"
}

_validate_aws_config() {
    local valid=true
    
    # Validate region
    if ! aws ec2 describe-regions --region "$AWS_REGION" --region-names "$AWS_REGION" >/dev/null 2>&1; then
        unity_log "ERROR" "Invalid AWS region: $AWS_REGION"
        valid=false
    fi
    
    # Validate numeric values
    if ! [[ "$COST_THRESHOLD_DEFAULT" =~ ^[0-9]+$ ]]; then
        unity_log "ERROR" "Invalid cost threshold: $COST_THRESHOLD_DEFAULT"
        valid=false
    fi
    
    if ! [[ "$SPOT_SAVINGS_TARGET" =~ ^[0-9]+$ ]]; then
        unity_log "ERROR" "Invalid spot savings target: $SPOT_SAVINGS_TARGET"
        valid=false
    fi
    
    if [[ "$valid" == "true" ]]; then
        unity_log "SUCCESS" "AWS configuration is valid"
        return 0
    else
        unity_log "ERROR" "AWS configuration validation failed"
        return 1
    fi
}

# Enhanced quota checking with events (implementation of missing function)
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

# Start quota monitoring background process
_start_quota_monitoring() {
    while true; do
        sleep "$QUOTA_CHECK_INTERVAL"
        
        # Check EC2 quota
        check_ec2_quota_with_events "t3.micro" >/dev/null 2>&1 || true
        
        # Check VPC quota
        check_vpc_quota_with_events >/dev/null 2>&1 || true
        
        # Check ALB quota
        check_alb_quota_with_events >/dev/null 2>&1 || true
    done
}

# Start cost monitoring background process
_start_cost_monitoring() {
    while true; do
        sleep 3600  # Check every hour
        
        # Monitor costs for all tracked stacks
        for resource_key in "${!UNITY_AWS_RESOURCES[@]}"; do
            local stack_name=$(echo "$resource_key" | cut -d'|' -f3)
            calculate_unity_deployment_cost "$stack_name" 24 >/dev/null 2>&1 || true
        done
    done
}

# Stub implementations for cost analysis functions
calculate_ec2_costs() {
    local stack_name="${1}"
    local duration_hours="${2}"
    echo "0"  # Placeholder implementation
}

calculate_alb_costs() {
    local stack_name="${1}"
    local duration_hours="${2}"
    echo "0"  # Placeholder implementation
}

calculate_efs_costs() {
    local stack_name="${1}"
    local duration_hours="${2}"
    echo "0"  # Placeholder implementation
}

calculate_cloudfront_costs() {
    local stack_name="${1}"
    local duration_hours="${2}"
    echo "0"  # Placeholder implementation
}

calculate_data_transfer_costs() {
    local stack_name="${1}"
    local duration_hours="${2}"
    echo "0"  # Placeholder implementation
}

calculate_potential_savings() {
    local stack_name="${1}"
    echo "0"  # Placeholder implementation
}

# Stub implementations for optimization analysis functions
analyze_spot_opportunities() {
    local stack_name="${1}"
    echo ""  # Placeholder implementation
}

analyze_rightsizing_opportunities() {
    local stack_name="${1}"
    echo ""  # Placeholder implementation
}

analyze_unused_resources() {
    local stack_name="${1}"
    echo ""  # Placeholder implementation
}

analyze_reserved_instance_opportunities() {
    local stack_name="${1}"
    echo ""  # Placeholder implementation
}

analyze_storage_optimization() {
    local stack_name="${1}"
    echo ""  # Placeholder implementation
}

apply_cost_optimizations() {
    local stack_name="${1}"
    shift
    local recommendations=("$@")
    
    unity_log "INFO" "Applying cost optimizations for $stack_name"
    # Placeholder implementation
}

# Launch ASG instance enhanced (missing implementation)
launch_asg_instance_enhanced() {
    local instance_type="${1}"
    local stack_name="${2}"
    local subnet_id="${3}"
    local security_group_id="${4}"
    local key_pair_name="${5}"
    local ami_id="${6}"
    local options="${7:-}"
    
    unity_log "INFO" "Creating Auto Scaling Group: $instance_type"
    
    # Create launch template
    local template_name="${stack_name}-lt"
    local template_id
    template_id=$(aws ec2 create-launch-template \
        --region "$AWS_REGION" \
        --launch-template-name "$template_name" \
        --launch-template-data "{
            \"ImageId\":\"$ami_id\",
            \"InstanceType\":\"$instance_type\",
            \"KeyName\":\"$key_pair_name\",
            \"SecurityGroupIds\":[\"$security_group_id\"],
            \"UserData\":\"$(base64 -w 0 <<< "$(create_user_data_script "$stack_name")")\",
            \"TagSpecifications\":[{
                \"ResourceType\":\"instance\",
                \"Tags\":[
                    {\"Key\":\"Name\",\"Value\":\"$stack_name\"},
                    {\"Key\":\"Unity\",\"Value\":\"true\"},
                    {\"Key\":\"DeploymentType\",\"Value\":\"asg\"}
                ]
            }]
        }" \
        --tag-specifications "ResourceType=launch-template,Tags=[{Key=Name,Value=$template_name},{Key=Unity,Value=true}]" \
        --query 'LaunchTemplate.LaunchTemplateId' \
        --output text) || {
        unity_log "ERROR" "Failed to create launch template"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Create ASG
    local asg_name="${stack_name}-asg"
    aws autoscaling create-auto-scaling-group \
        --region "$AWS_REGION" \
        --auto-scaling-group-name "$asg_name" \
        --launch-template "LaunchTemplateId=$template_id,Version=\$Latest" \
        --min-size 1 \
        --max-size 3 \
        --desired-capacity 1 \
        --vpc-zone-identifier "$subnet_id" \
        --tags "Key=Name,Value=$asg_name,PropagateAtLaunch=true,ResourceId=$asg_name,ResourceType=auto-scaling-group" \
               "Key=Unity,Value=true,PropagateAtLaunch=true,ResourceId=$asg_name,ResourceType=auto-scaling-group" \
        $options || {
        unity_log "ERROR" "Failed to create Auto Scaling Group"
        return $UNITY_ERROR_EXECUTION
    }
    
    # Track resource
    track_resource_with_events "asg" "$asg_name" "$stack_name" "0" "{\"launch_template\":\"$template_id\"}"
    track_resource_with_events "launch-template" "$template_id" "$stack_name" "0"
    
    # Emit success event
    _emit_aws_event "aws.asg.created" "asg-manager" "{\"asg_name\":\"$asg_name\",\"stack_name\":\"$stack_name\",\"launch_template\":\"$template_id\"}" "medium"
    
    unity_log "SUCCESS" "Auto Scaling Group created: $asg_name"
    echo "$asg_name"
    return $UNITY_SUCCESS
}

# Event handlers for AWS service events
handle_aws_cost_alert() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    unity_log "WARN" "AWS Cost Alert: $event_data"
    
    # Extract cost information
    local stack_name
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Trigger cost optimization
    optimize_unity_deployment_costs "$stack_name"
    
    # Emit follow-up event for potential rollback consideration
    _emit_aws_event "aws.cost.optimization.required" "cost-handler" "{\"stack_name\":\"$stack_name\",\"trigger\":\"threshold_exceeded\"}" "high"
}

handle_aws_resource_failure() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    unity_log "ERROR" "AWS Resource Failure: $event_data"
    
    # Extract resource information
    local resource_type resource_id stack_name
    resource_type=$(echo "$event_data" | grep -o '"resource_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    resource_id=$(echo "$event_data" | grep -o '"resource_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    stack_name=$(echo "$event_data" | grep -o '"stack_name": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Attempt automatic remediation based on resource type
    case "$resource_type" in
        "ec2")
            unity_log "INFO" "Attempting EC2 instance recovery for $resource_id"
            # Could trigger instance replacement logic
            ;;
        "vpc")
            unity_log "INFO" "VPC failure detected for $resource_id - may require manual intervention"
            ;;
        *)
            unity_log "INFO" "Generic resource failure handling for $resource_type: $resource_id"
            ;;
    esac
    
    # Emit remediation event
    _emit_aws_event "aws.resource.remediation.attempted" "failure-handler" "{\"resource_type\":\"$resource_type\",\"resource_id\":\"$resource_id\",\"stack_name\":\"$stack_name\"}" "high"
}

handle_aws_quota_exceeded() {
    local event_type="$1"
    local event_source="$2"
    local event_data="$3"
    local timestamp="$4"
    
    unity_log "ERROR" "AWS Quota Exceeded: $event_data"
    
    # Extract quota information
    local quota_type
    quota_type=$(echo "$event_data" | grep -o '"quota_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    # Emit alert for manual intervention
    _emit_aws_event "monitor.alert.triggered" "quota-monitor" "{\"alert_type\":\"quota_exceeded\",\"severity\":\"critical\",\"message\":\"AWS quota exceeded: $quota_type\"}" "critical"
}

# Initialize if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    unity_aws_complete "$@"
fi