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
    local vpc_id
    
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || true)
    
    # Return empty if no VPC found or if result is "None"
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        return 0
    fi
    
    echo "$vpc_id"
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
    
    # Validate required parameters
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "VPC ID is required for subnet creation"
    fi
    
    # Auto-select AZ if not provided
    if [ -z "$availability_zone" ]; then
        availability_zone=$(get_available_az)
    fi
    
    echo "Creating public subnet in AZ: $availability_zone" >&2
    
    # Check if subnet already exists by stack and AZ
    local existing_subnet
    existing_subnet=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
                  "Name=tag:Stack,Values=$stack_name" \
                  "Name=tag:Type,Values=public" \
                  "Name=availability-zone,Values=$availability_zone" \
        --query 'Subnets[0].SubnetId' \
        --output text 2>/dev/null ) || true
    
    if [ -n "$existing_subnet" ] && [ "$existing_subnet" != "None" ] && [ "$existing_subnet" != "null" ]; then
        echo "Public subnet already exists: $existing_subnet" >&2
        echo "$existing_subnet"
        return 0
    fi
    
    # Check for CIDR conflicts before creating
    local cidr_conflict
    cidr_conflict=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
                  "Name=cidr-block,Values=$cidr_block" \
        --query 'Subnets[0].SubnetId' \
        --output text 2>/dev/null ) || true
    
    if [ -n "$cidr_conflict" ] && [ "$cidr_conflict" != "None" ] && [ "$cidr_conflict" != "null" ]; then
        echo "WARNING: CIDR conflict detected for $cidr_block (existing subnet: $cidr_conflict)" >&2
        echo "Attempting conflict resolution..." >&2
        
        # Use conflict resolution function
        local resolved_subnet
        resolved_subnet=$(create_public_subnet_with_conflict_resolution "$vpc_id" "$availability_zone" "$cidr_block" "$stack_name")
        echo "$resolved_subnet"
        return $?
    fi
    
    # Create subnet with original CIDR
    local subnet_id
    subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$cidr_block" \
        --availability-zone "$availability_zone" \
        --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name" "Type=public")" "subnet")" \
        --query 'Subnet.SubnetId' \
        --output text) || {
        echo "ERROR: Failed to create public subnet with CIDR $cidr_block" >&2
        echo "Attempting conflict resolution..." >&2
        
        # Fallback to conflict resolution
        local fallback_subnet
        fallback_subnet=$(create_public_subnet_with_conflict_resolution "$vpc_id" "$availability_zone" "$cidr_block" "$stack_name")
        echo "$fallback_subnet"
        return $?
    }
    
    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute \
        --subnet-id "$subnet_id" \
        --map-public-ip-on-launch || {
        throw_error $ERROR_AWS_API "Failed to enable auto-assign public IP"
    }
    
    # Register subnet
    register_resource "subnet" "$subnet_id" "{\"type\": \"public\", \"vpc_id\": \"$vpc_id\", \"cidr\": \"$cidr_block\", \"az\": \"$availability_zone\"}"
    
    echo "$subnet_id"
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
    
    # Use the enhanced function with state checking
    local igw_id
    igw_id=$(create_internet_gateway_with_check "$vpc_id" "$stack_name")
    
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
# ENTERPRISE MULTI-AZ NETWORK SETUP
# =============================================================================

# Setup enterprise multi-AZ network infrastructure with comprehensive subnet allocation
setup_enterprise_network_infrastructure() {
    local stack_name="${1:-$STACK_NAME}"
    local vpc_cidr="${2:-10.0.0.0/16}"
    local enable_private_subnets="${3:-false}"
    local enable_nat_gateway="${4:-false}"
    
    echo "Setting up enterprise multi-AZ network infrastructure for: $stack_name" >&2
    
    # Create VPC
    local vpc_id
    vpc_id=$(create_vpc "$stack_name" "$vpc_cidr") || return 1
    echo "VPC created: $vpc_id" >&2
    
    # Get available AZs (limit to first 3 for cost control)
    local availability_zones
    availability_zones=($(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query 'AvailabilityZones[0:3].ZoneName' \
        --output text))
    
    if [ ${#availability_zones[@]} -eq 0 ]; then
        echo "ERROR: No availability zones available" >&2
        return 1
    fi
    
    echo "Using availability zones: ${availability_zones[*]}" >&2
    
    # Create public subnets with automatic CIDR allocation
    local public_subnets_json="["
    local subnet_counter=1
    
    for az in "${availability_zones[@]}"; do
        local public_cidr="10.0.${subnet_counter}.0/24"
        local subnet_id
        
        subnet_id=$(create_public_subnet_with_conflict_resolution "$vpc_id" "$az" "$public_cidr" "$stack_name") || {
            echo "WARNING: Failed to create public subnet in $az, skipping" >&2
            continue
        }
        
        if [ "$public_subnets_json" != "[" ]; then
            public_subnets_json="${public_subnets_json},"
        fi
        
        public_subnets_json="${public_subnets_json}{\"id\": \"$subnet_id\", \"az\": \"$az\", \"cidr\": \"$public_cidr\"}"
        
        subnet_counter=$((subnet_counter + 1))
        echo "Public subnet created: $subnet_id in $az" >&2
    done
    
    public_subnets_json="${public_subnets_json}]"
    
    # Create private subnets if enabled
    local private_subnets_json="[]"
    if [ "$enable_private_subnets" = "true" ]; then
        private_subnets_json="["
        local private_subnet_counter=10  # Start private subnets at 10.0.10.0/24
        
        for az in "${availability_zones[@]}"; do
            local private_cidr="10.0.${private_subnet_counter}.0/24"
            local private_subnet_id
            
            private_subnet_id=$(create_private_subnet_with_conflict_resolution "$vpc_id" "$az" "$private_cidr" "$stack_name") || {
                echo "WARNING: Failed to create private subnet in $az, skipping" >&2
                continue
            }
            
            if [ "$private_subnets_json" != "[" ]; then
                private_subnets_json="${private_subnets_json},"
            fi
            
            private_subnets_json="${private_subnets_json}{\"id\": \"$private_subnet_id\", \"az\": \"$az\", \"cidr\": \"$private_cidr\"}"
            
            private_subnet_counter=$((private_subnet_counter + 1))
            echo "Private subnet created: $private_subnet_id in $az" >&2
        done
        
        private_subnets_json="${private_subnets_json}]"
    fi
    
    # Create Internet Gateway with existing check
    local igw_id
    igw_id=$(create_internet_gateway_with_check "$vpc_id" "$stack_name") || return 1
    echo "Internet Gateway: $igw_id" >&2
    
    # Configure routes for all public subnets
    local first_public_subnet
    first_public_subnet=$(echo "$public_subnets_json" | jq -r '.[0].id' 2>/dev/null)
    
    if [ -n "$first_public_subnet" ] && [ "$first_public_subnet" != "null" ]; then
        configure_public_routes "$vpc_id" "$first_public_subnet" "$igw_id" || return 1
        echo "Routes configured for public subnets" >&2
    fi
    
    # Return comprehensive network info
    cat <<EOF
{
    "vpc_id": "$vpc_id",
    "public_subnets": $public_subnets_json,
    "private_subnets": $private_subnets_json,
    "igw_id": "$igw_id"
}
EOF
}

# Create public subnet with CIDR conflict resolution
create_public_subnet_with_conflict_resolution() {
    local vpc_id="$1"
    local availability_zone="$2"
    local initial_cidr="$3"
    local stack_name="$4"
    local max_attempts=10
    local attempt=1
    
    # Extract base network for conflict resolution
    local base_network=$(echo "$initial_cidr" | cut -d'.' -f1-2)  # e.g., "10.0"
    
    while [ $attempt -le $max_attempts ]; do
        local test_cidr="${base_network}.${attempt}.0/24"
        
        # Check if CIDR already exists in this VPC
        local existing_subnet
        existing_subnet=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
                      "Name=cidr-block,Values=$test_cidr" \
            --query 'Subnets[0].SubnetId' \
            --output text 2>/dev/null ) || true
        
        if [ -z "$existing_subnet" ] || [ "$existing_subnet" = "None" ] || [ "$existing_subnet" = "null" ]; then
            # CIDR is available, create subnet
            echo "Attempting to create subnet with CIDR: $test_cidr in AZ: $availability_zone" >&2
            
            local subnet_id
            subnet_id=$(aws ec2 create-subnet \
                --vpc-id "$vpc_id" \
                --cidr-block "$test_cidr" \
                --availability-zone "$availability_zone" \
                --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name" "Type=public")" "subnet")" \
                --query 'Subnet.SubnetId' \
                --output text 2>/dev/null) || {
                echo "Failed to create subnet with CIDR $test_cidr, trying next..." >&2
                attempt=$((attempt + 1))
                continue
            }
            
            # Enable auto-assign public IP
            aws ec2 modify-subnet-attribute \
                --subnet-id "$subnet_id" \
                --map-public-ip-on-launch || {
                echo "WARNING: Failed to enable auto-assign public IP for $subnet_id" >&2
            }
            
            # Register subnet
            register_resource "subnets" "$subnet_id" "{\"type\": \"public\", \"vpc_id\": \"$vpc_id\", \"cidr\": \"$test_cidr\", \"az\": \"$availability_zone\"}"
            
            echo "$subnet_id"
            return 0
        else
            echo "CIDR $test_cidr already exists (subnet: $existing_subnet), trying next..." >&2
            attempt=$((attempt + 1))
        fi
    done
    
    echo "ERROR: Failed to find available CIDR after $max_attempts attempts" >&2
    return 1
}

# Create private subnet with conflict resolution
create_private_subnet_with_conflict_resolution() {
    local vpc_id="$1"
    local availability_zone="$2"
    local initial_cidr="$3"
    local stack_name="$4"
    local max_attempts=10
    local attempt=10  # Start at 10 for private subnets
    
    # Extract base network for conflict resolution
    local base_network=$(echo "$initial_cidr" | cut -d'.' -f1-2)  # e.g., "10.0"
    
    while [ $attempt -le $((10 + max_attempts)) ]; do
        local test_cidr="${base_network}.${attempt}.0/24"
        
        # Check if CIDR already exists in this VPC
        local existing_subnet
        existing_subnet=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
                      "Name=cidr-block,Values=$test_cidr" \
            --query 'Subnets[0].SubnetId' \
            --output text 2>/dev/null ) || true
        
        if [ -z "$existing_subnet" ] || [ "$existing_subnet" = "None" ] || [ "$existing_subnet" = "null" ]; then
            # CIDR is available, create subnet
            echo "Attempting to create private subnet with CIDR: $test_cidr in AZ: $availability_zone" >&2
            
            local subnet_id
            subnet_id=$(aws ec2 create-subnet \
                --vpc-id "$vpc_id" \
                --cidr-block "$test_cidr" \
                --availability-zone "$availability_zone" \
                --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name" "Type=private")" "subnet")" \
                --query 'Subnet.SubnetId' \
                --output text 2>/dev/null) || {
                echo "Failed to create private subnet with CIDR $test_cidr, trying next..." >&2
                attempt=$((attempt + 1))
                continue
            }
            
            # Register subnet
            register_resource "subnets" "$subnet_id" "{\"type\": \"private\", \"vpc_id\": \"$vpc_id\", \"cidr\": \"$test_cidr\", \"az\": \"$availability_zone\"}"
            
            echo "$subnet_id"
            return 0
        else
            echo "CIDR $test_cidr already exists (subnet: $existing_subnet), trying next..." >&2
            attempt=$((attempt + 1))
        fi
    done
    
    echo "ERROR: Failed to find available private subnet CIDR after $max_attempts attempts" >&2
    return 1
}

# Create Internet Gateway with existing resource check
create_internet_gateway_with_check() {
    local vpc_id="$1"
    local stack_name="$2"
    
    echo "Creating/checking Internet Gateway for VPC: $vpc_id" >&2
    
    # Check if VPC already has an IGW attached
    local existing_igw
    existing_igw=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>/dev/null ) || true
    
    if [ -n "$existing_igw" ] && [ "$existing_igw" != "None" ] && [ "$existing_igw" != "null" ]; then
        echo "Internet Gateway already exists and attached: $existing_igw" >&2
        
        # Register existing IGW
        register_resource "internet_gateways" "$existing_igw" "{\"vpc\": \"$vpc_id\", \"existing\": true}"
        
        echo "$existing_igw"
        return 0
    fi
    
    # Check if there's an unattached IGW for this stack
    local unattached_igw
    unattached_igw=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --query 'InternetGateways[?length(Attachments) == `0`][0].InternetGatewayId' \
        --output text 2>/dev/null ) || true
    
    if [ -n "$unattached_igw" ] && [ "$unattached_igw" != "None" ] && [ "$unattached_igw" != "null" ]; then
        echo "Found unattached IGW for stack, attempting to attach: $unattached_igw" >&2
        
        # Attempt to attach existing IGW
        aws ec2 attach-internet-gateway \
            --vpc-id "$vpc_id" \
            --internet-gateway-id "$unattached_igw" || {
            echo "ERROR: Failed to attach existing Internet Gateway $unattached_igw" >&2
            return 1
        }
        
        register_resource "internet_gateways" "$unattached_igw" "{\"vpc\": \"$vpc_id\", \"reattached\": true}"
        echo "$unattached_igw"
        return 0
    fi
    
    # Create new IGW
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name")" "internet-gateway")" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text) || {
        echo "ERROR: Failed to create Internet Gateway" >&2
        return 1
    }
    
    echo "Created new Internet Gateway: $igw_id" >&2
    
    # Attach to VPC
    aws ec2 attach-internet-gateway \
        --vpc-id "$vpc_id" \
        --internet-gateway-id "$igw_id" || {
        echo "ERROR: Failed to attach Internet Gateway $igw_id to VPC $vpc_id" >&2
        
        # Cleanup IGW if attachment fails
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" 2>/dev/null || true
        return 1
    }
    
    # Register IGW
    register_resource "internet_gateways" "$igw_id" "{\"vpc\": \"$vpc_id\", \"created\": true}"
    
    echo "$igw_id"
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