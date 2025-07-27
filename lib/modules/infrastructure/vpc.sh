#!/bin/bash
# =============================================================================
# VPC Management Module
# Handles VPC, subnet, and network infrastructure
# =============================================================================

# Prevent multiple sourcing
[ -n "${_VPC_SH_LOADED:-}" ] && return 0
_VPC_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# VPC CREATION
# =============================================================================

# Create VPC with standard configuration
create_vpc() {
    local stack_name="${1:-$STACK_NAME}"
    local cidr_block="${2:-10.0.0.0/16}"
    
    with_error_context "create_vpc" \
        _create_vpc_impl "$stack_name" "$cidr_block"
}

_create_vpc_impl() {
    local stack_name="$1"
    local cidr_block="$2"
    
    echo "Creating VPC for stack: $stack_name" >&2
    
    # Check if VPC already exists
    local existing_vpc
    existing_vpc=$(get_vpc_by_stack "$stack_name") || true
    
    if [ -n "$existing_vpc" ]; then
        echo "VPC already exists: $existing_vpc" >&2
        echo "$existing_vpc"
        return 0
    fi
    
    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr_block" \
        --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name")" "vpc")" \
        --query 'Vpc.VpcId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create VPC"
    }
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-hostnames || {
        throw_error $ERROR_AWS_API "Failed to enable DNS hostnames"
    }
    
    # Register VPC
    register_resource "vpc" "$vpc_id" "{\"cidr\": \"$cidr_block\"}"
    
    echo "$vpc_id"
}

# Get VPC by stack name
get_vpc_by_stack() {
    local stack_name="$1"
    
    aws ec2 describe-vpcs \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null | grep -v "None" || true
}

# =============================================================================
# SUBNET MANAGEMENT
# =============================================================================

# Create public subnet
create_public_subnet() {
    local vpc_id="$1"
    local availability_zone="${2:-}"
    local cidr_block="${3:-10.0.1.0/24}"
    local stack_name="${4:-$STACK_NAME}"
    
    with_error_context "create_public_subnet" \
        _create_public_subnet_impl "$vpc_id" "$availability_zone" "$cidr_block" "$stack_name"
}

_create_public_subnet_impl() {
    local vpc_id="$1"
    local availability_zone="$2"
    local cidr_block="$3"
    local stack_name="$4"
    
    # Auto-select AZ if not provided
    if [ -z "$availability_zone" ]; then
        availability_zone=$(get_available_az)
    fi
    
    echo "Creating public subnet in AZ: $availability_zone" >&2
    
    # Use the new create_subnet function
    create_subnet "$vpc_id" "$availability_zone" "$cidr_block" "$stack_name" "public"
}

# Get available AZ
get_available_az() {
    aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query 'AvailabilityZones[0].ZoneName' \
        --output text
}

# =============================================================================
# INTERNET GATEWAY
# =============================================================================

# Create and attach internet gateway
create_internet_gateway() {
    local vpc_id="$1"
    local stack_name="${2:-$STACK_NAME}"
    
    with_error_context "create_internet_gateway" \
        _create_internet_gateway_impl "$vpc_id" "$stack_name"
}

_create_internet_gateway_impl() {
    local vpc_id="$1"
    local stack_name="$2"
    
    echo "Creating Internet Gateway" >&2
    
    # Create IGW
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name")" "internet-gateway")" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create Internet Gateway"
    }
    
    # Attach to VPC
    aws ec2 attach-internet-gateway \
        --vpc-id "$vpc_id" \
        --internet-gateway-id "$igw_id" || {
        throw_error $ERROR_AWS_API "Failed to attach Internet Gateway"
    }
    
    # Register IGW
    register_resource "internet_gateways" "$igw_id" "{\"vpc\": \"$vpc_id\"}"
    
    echo "$igw_id"
}

# =============================================================================
# ROUTE TABLE MANAGEMENT
# =============================================================================

# Configure route table for public access
configure_public_routes() {
    local vpc_id="$1"
    local subnet_id="$2"
    local igw_id="$3"
    
    with_error_context "configure_public_routes" \
        _configure_public_routes_impl "$vpc_id" "$subnet_id" "$igw_id"
}

_configure_public_routes_impl() {
    local vpc_id="$1"
    local subnet_id="$2"
    local igw_id="$3"
    
    echo "Configuring public routes" >&2
    
    # Get main route table
    local route_table_id
    route_table_id=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=true" \
        --query 'RouteTables[0].RouteTableId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to get route table"
    }
    
    # Add route to IGW
    aws ec2 create-route \
        --route-table-id "$route_table_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id" 2>/dev/null || {
        # Route might already exist
        echo "Route to IGW may already exist, continuing..." >&2
    }
    
    # Associate subnet with route table
    aws ec2 associate-route-table \
        --subnet-id "$subnet_id" \
        --route-table-id "$route_table_id" >/dev/null 2>&1 || {
        echo "Subnet already associated with route table" >&2
    }
    
    # Register route table
    register_resource "route_tables" "$route_table_id" "{\"vpc\": \"$vpc_id\"}"
}

# =============================================================================
# NETWORK SETUP ORCHESTRATION
# =============================================================================

# Complete network setup
setup_network_infrastructure() {
    local stack_name="${1:-$STACK_NAME}"
    local vpc_cidr="${2:-10.0.0.0/16}"
    local subnet_cidr="${3:-10.0.1.0/24}"
    
    echo "Setting up network infrastructure for: $stack_name" >&2
    
    # Create VPC
    local vpc_id
    vpc_id=$(create_vpc "$stack_name" "$vpc_cidr") || return 1
    echo "VPC created: $vpc_id" >&2
    
    # Create subnet
    local subnet_id
    subnet_id=$(create_public_subnet "$vpc_id" "" "$subnet_cidr" "$stack_name") || return 1
    echo "Subnet created: $subnet_id" >&2
    
    # Create Internet Gateway
    local igw_id
    igw_id=$(create_internet_gateway "$vpc_id" "$stack_name") || return 1
    echo "Internet Gateway created: $igw_id" >&2
    
    # Configure routes
    configure_public_routes "$vpc_id" "$subnet_id" "$igw_id" || return 1
    echo "Routes configured" >&2
    
    # Return network info
    cat <<EOF
{
    "vpc_id": "$vpc_id",
    "subnet_id": "$subnet_id",
    "igw_id": "$igw_id"
}
EOF
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup VPC and dependencies
cleanup_vpc() {
    local vpc_id="$1"
    
    echo "Cleaning up VPC: $vpc_id" >&2
    
    # Delete subnets
    local subnets
    subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].SubnetId' \
        --output text)
    
    for subnet in $subnets; do
        echo "Deleting subnet: $subnet" >&2
        aws ec2 delete-subnet --subnet-id "$subnet" || true
    done
    
    # Detach and delete IGWs
    local igws
    igws=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[*].InternetGatewayId' \
        --output text)
    
    for igw in $igws; do
        echo "Detaching and deleting IGW: $igw" >&2
        aws ec2 detach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw" || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" || true
    done
    
    # Delete VPC
    echo "Deleting VPC: $vpc_id" >&2
    aws ec2 delete-vpc --vpc-id "$vpc_id" || true
}