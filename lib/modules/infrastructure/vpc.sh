#!/usr/bin/env bash
# =============================================================================
# VPC Infrastructure Module
# Uniform VPC creation and management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_INFRASTRUCTURE_VPC_SH_LOADED:-}" ] && return 0
declare -gr _INFRASTRUCTURE_VPC_SH_LOADED=1

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies using dependency groups
source "${SCRIPT_DIR}/../core/dependency-groups.sh"
load_dependency_group "INFRASTRUCTURE" "$SCRIPT_DIR/.."

# =============================================================================
# VPC CONFIGURATION
# =============================================================================

# VPC configuration defaults
VPC_DEFAULT_CIDR="10.0.0.0/16"
VPC_DEFAULT_ENABLE_DNS_HOSTNAMES=true
VPC_DEFAULT_ENABLE_DNS_SUPPORT=true
VPC_DEFAULT_INSTANCE_TENANCY="default"

# Subnet configuration defaults
SUBNET_DEFAULT_MAP_PUBLIC_IP_ON_LAUNCH=true
SUBNET_DEFAULT_AUTO_ASSIGN_IPV6=false

# =============================================================================
# VPC CREATION FUNCTIONS
# =============================================================================

# Create VPC with subnets
create_vpc_with_subnets() {
    local stack_name="$1"
    local vpc_cidr="${2:-$VPC_DEFAULT_CIDR}"
    local public_subnets="${3:-}"
    local private_subnets="${4:-}"
    local isolated_subnets="${5:-}"
    
    log_info "Creating VPC with subnets for stack: $stack_name" "VPC"
    
    # Check for existing VPC from environment or stack variables
    local existing_vpc_id="${EXISTING_VPC_ID:-}"
    if [[ -z "$existing_vpc_id" ]]; then
        existing_vpc_id=$(get_variable "VPC_ID" "$VARIABLE_SCOPE_STACK")
    fi
    
    if [[ -n "$existing_vpc_id" ]]; then
        log_info "Using existing VPC: $existing_vpc_id" "VPC"
        
        # Source existing resources module if not already loaded
        if [[ -z "${_EXISTING_RESOURCES_SH_LOADED:-}" ]]; then
            source "${SCRIPT_DIR}/existing-resources.sh"
        fi
        
        # Validate existing VPC
        if ! validate_existing_vpc "$existing_vpc_id" "$vpc_cidr"; then
            log_error "Existing VPC validation failed: $existing_vpc_id" "VPC"
            return 1
        fi
        
        # Register existing VPC
        register_resource "vpc" "$existing_vpc_id" "{\"type\": \"existing\", \"stack\": \"$stack_name\"}"
        
        # Check for existing subnets
        local existing_public_subnets
        existing_public_subnets=$(get_variable "PUBLIC_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
        local existing_private_subnets
        existing_private_subnets=$(get_variable "PRIVATE_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
        local existing_isolated_subnets
        existing_isolated_subnets=$(get_variable "ISOLATED_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$existing_public_subnets" || -n "$existing_private_subnets" || -n "$existing_isolated_subnets" ]]; then
            log_info "Using existing subnets" "VPC"
            
            # Validate existing subnets
            if [[ -n "$existing_public_subnets" ]]; then
                if ! validate_existing_subnets "$existing_public_subnets" "$existing_vpc_id" "public"; then
                    log_error "Existing public subnet validation failed" "VPC"
                    return 1
                fi
                # Register existing public subnets
                for subnet_id in $existing_public_subnets; do
                    register_resource "subnet" "$subnet_id" "{\"type\": \"existing\", \"vpc_id\": \"$existing_vpc_id\", \"subnet_type\": \"public\"}"
                done
            fi
            
            if [[ -n "$existing_private_subnets" ]]; then
                if ! validate_existing_subnets "$existing_private_subnets" "$existing_vpc_id" "private"; then
                    log_error "Existing private subnet validation failed" "VPC"
                    return 1
                fi
                # Register existing private subnets
                for subnet_id in $existing_private_subnets; do
                    register_resource "subnet" "$subnet_id" "{\"type\": \"existing\", \"vpc_id\": \"$existing_vpc_id\", \"subnet_type\": \"private\"}"
                done
            fi
            
            if [[ -n "$existing_isolated_subnets" ]]; then
                if ! validate_existing_subnets "$existing_isolated_subnets" "$existing_vpc_id" "isolated"; then
                    log_error "Existing isolated subnet validation failed" "VPC"
                    return 1
                fi
                # Register existing isolated subnets
                for subnet_id in $existing_isolated_subnets; do
                    register_resource "subnet" "$subnet_id" "{\"type\": \"existing\", \"vpc_id\": \"$existing_vpc_id\", \"subnet_type\": \"isolated\"}"
                done
            fi
            
            # Check for existing IGW/NAT/Routes
            local existing_igw_id
            existing_igw_id=$(get_variable "INTERNET_GATEWAY_ID" "$VARIABLE_SCOPE_STACK")
            if [[ -n "$existing_igw_id" ]]; then
                log_info "Using existing internet gateway: $existing_igw_id" "VPC"
                register_resource "internet-gateway" "$existing_igw_id" "{\"type\": \"existing\", \"vpc_id\": \"$existing_vpc_id\"}"
            fi
            
            local existing_nat_id
            existing_nat_id=$(get_variable "NAT_GATEWAY_ID" "$VARIABLE_SCOPE_STACK")
            if [[ -n "$existing_nat_id" ]]; then
                log_info "Using existing NAT gateway: $existing_nat_id" "VPC"
                register_resource "nat-gateway" "$existing_nat_id" "{\"type\": \"existing\", \"vpc_id\": \"$existing_vpc_id\"}"
            fi
            
            log_info "Using existing VPC and subnets successfully" "VPC"
            return 0
        else
            # Using existing VPC but need to create subnets
            log_info "Using existing VPC but creating new subnets" "VPC"
            local vpc_id="$existing_vpc_id"
        fi
    else
        # No existing VPC - create new one
        # Generate VPC name
        local vpc_name
        vpc_name=$(generate_resource_name "vpc" "$stack_name")
        
        # Create VPC
        local vpc_id
        vpc_id=$(create_vpc "$vpc_name" "$vpc_cidr")
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create VPC: $vpc_name" "VPC"
            return 1
        fi
        
        # Store VPC ID
        set_variable "VPC_ID" "$vpc_id" "$VARIABLE_SCOPE_STACK"
    fi
    
    # Create subnets if specified and not using existing
    if [[ -n "$public_subnets" || -n "$private_subnets" || -n "$isolated_subnets" ]]; then
        if ! create_subnets "$vpc_id" "$stack_name" "$public_subnets" "$private_subnets" "$isolated_subnets"; then
            log_error "Failed to create subnets for VPC: $vpc_id" "VPC"
            # Only rollback if we created the VPC
            if [[ -z "$existing_vpc_id" ]]; then
                delete_vpc "$vpc_id"
            fi
            return 1
        fi
    fi
    
    # Create internet gateway if public subnets exist and not using existing
    if [[ -n "$public_subnets" ]]; then
        local existing_igw_id
        existing_igw_id=$(get_variable "INTERNET_GATEWAY_ID" "$VARIABLE_SCOPE_STACK")
        
        if [[ -z "$existing_igw_id" ]]; then
            local igw_id
            igw_id=$(create_internet_gateway "$stack_name")
            if [[ $? -eq 0 ]]; then
                set_variable "INTERNET_GATEWAY_ID" "$igw_id" "$VARIABLE_SCOPE_STACK"
                
                # Attach internet gateway to VPC
                if ! attach_internet_gateway "$igw_id" "$vpc_id"; then
                    log_error "Failed to attach internet gateway to VPC" "VPC"
                    return 1
                fi
            else
                log_error "Failed to create internet gateway" "VPC"
                return 1
            fi
        fi
    fi
    
    # Create NAT gateway if private subnets exist and not using existing
    if [[ -n "$private_subnets" ]]; then
        local existing_nat_id
        existing_nat_id=$(get_variable "NAT_GATEWAY_ID" "$VARIABLE_SCOPE_STACK")
        
        if [[ -z "$existing_nat_id" ]]; then
            local nat_gateway_id
            nat_gateway_id=$(create_nat_gateway "$stack_name" "$vpc_id")
            if [[ $? -eq 0 ]]; then
                set_variable "NAT_GATEWAY_ID" "$nat_gateway_id" "$VARIABLE_SCOPE_STACK"
            else
                log_error "Failed to create NAT gateway" "VPC"
                return 1
            fi
        fi
    fi
    
    # Create route tables
    if ! create_route_tables "$vpc_id" "$stack_name" "$public_subnets" "$private_subnets"; then
        log_error "Failed to create route tables" "VPC"
        return 1
    fi
    
    log_info "VPC creation completed successfully: $vpc_id" "VPC"
    return 0
}

# Create VPC
create_vpc() {
    local vpc_name="$1"
    local vpc_cidr="$2"
    
    log_info "Creating VPC: $vpc_name with CIDR: $vpc_cidr" "VPC"
    
    # Validate VPC name
    if ! validate_resource_name "$vpc_name" "vpc"; then
        return 1
    fi
    
    # Validate CIDR
    if ! validate_cidr_block "$vpc_cidr"; then
        return 1
    fi
    
    # Generate tags
    local tags
    tags=$(generate_tags "$STACK_NAME")
    
    # Convert tags to JSON format for tag-specifications
    local tag_json="[{Key=Name,Value=$vpc_name}"
    if [[ -n "$tags" ]]; then
        # Parse each tag and add to JSON array
        while IFS=' ' read -r tag; do
            if [[ "$tag" =~ Key=([^,]+),Value=(.*) ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                # Skip Name tag as we already have it
                if [[ "$key" != "Name" ]]; then
                    tag_json="${tag_json},{Key=$key,Value=$value}"
                fi
            fi
        done <<< "$tags"
    fi
    tag_json="${tag_json}]"
    
    # Create VPC
    local vpc_output
    local exit_code
    vpc_output=$(aws ec2 create-vpc \
        --cidr-block "$vpc_cidr" \
        --instance-tenancy "$VPC_DEFAULT_INSTANCE_TENANCY" \
        --tag-specifications "ResourceType=vpc,Tags=${tag_json}" \
        --output json \
        --query 'Vpc.VpcId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "AWS CLI failed with exit code: $exit_code" "VPC"
        log_error "AWS CLI error output: $vpc_output" "VPC"
        
        # Try to parse specific error messages
        if [[ "$vpc_output" =~ "InvalidParameterValue" ]]; then
            log_error "Invalid parameter value detected. Check VPC name, CIDR, or tags." "VPC"
        elif [[ "$vpc_output" =~ "UnauthorizedOperation" ]]; then
            log_error "Unauthorized operation. Check AWS credentials and permissions." "VPC"
        elif [[ "$vpc_output" =~ "VpcLimitExceeded" ]]; then
            log_error "VPC limit exceeded in this region." "VPC"
        elif [[ "$vpc_output" =~ "InvalidVpcID.NotFound" ]]; then
            log_error "Invalid VPC ID reference." "VPC"
        fi
        
        return 1
    fi
    
    local vpc_id
    vpc_id=$(echo "$vpc_output" | tr -d '"')
    
    # Wait for VPC to be available
    log_info "Waiting for VPC to be available: $vpc_id" "VPC"
    aws ec2 wait vpc-available \
        --vpc-ids "$vpc_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    if [[ $? -ne 0 ]]; then
        log_error "VPC failed to become available: $vpc_id" "VPC"
        return 1
    fi
    
    # Enable DNS settings
    log_info "Enabling DNS hostnames and support for VPC: $vpc_id" "VPC"
    
    # Enable DNS hostnames
    if ! aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-hostnames \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1; then
        log_error "Failed to enable DNS hostnames for VPC: $vpc_id" "VPC"
    fi
    
    # Enable DNS support
    if ! aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-support \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1; then
        log_error "Failed to enable DNS support for VPC: $vpc_id" "VPC"
    fi
    
    log_info "VPC created successfully: $vpc_id" "VPC"
    echo "$vpc_id"
    return 0
}

# Create subnets
create_subnets() {
    local vpc_id="$1"
    local stack_name="$2"
    local public_subnets="$3"
    local private_subnets="$4"
    local isolated_subnets="$5"
    
    log_info "Creating subnets for VPC: $vpc_id" "VPC"
    
    # Get availability zones
    local availability_zones
    availability_zones=$(get_availability_zones)
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get availability zones" "VPC"
        return 1
    fi
    
    # Create public subnets
    if [[ -n "$public_subnets" ]]; then
        if ! create_subnet_group "$vpc_id" "$stack_name" "public" "$public_subnets" "$availability_zones"; then
            log_error "Failed to create public subnets" "VPC"
            return 1
        fi
    fi
    
    # Create private subnets
    if [[ -n "$private_subnets" ]]; then
        if ! create_subnet_group "$vpc_id" "$stack_name" "private" "$private_subnets" "$availability_zones"; then
            log_error "Failed to create private subnets" "VPC"
            return 1
        fi
    fi
    
    # Create isolated subnets
    if [[ -n "$isolated_subnets" ]]; then
        if ! create_subnet_group "$vpc_id" "$stack_name" "isolated" "$isolated_subnets" "$availability_zones"; then
            log_error "Failed to create isolated subnets" "VPC"
            return 1
        fi
    fi
    
    log_info "Subnet creation completed successfully" "VPC"
    return 0
}

# Create subnet group
create_subnet_group() {
    local vpc_id="$1"
    local stack_name="$2"
    local subnet_type="$3"
    local subnet_cidrs="$4"
    local availability_zones="$5"
    
    log_info "Creating $subnet_type subnets" "VPC"
    
    # Parse subnet CIDRs and AZs
    IFS=' ' read -ra CIDR_ARRAY <<< "$subnet_cidrs"
    IFS=' ' read -ra AZ_ARRAY <<< "$availability_zones"
    
    local subnet_ids=()
    local index=0
    
    for cidr in "${CIDR_ARRAY[@]}"; do
        if [[ $index -ge ${#AZ_ARRAY[@]} ]]; then
            log_error "Not enough availability zones for all subnets" "VPC"
            return 1
        fi
        
        local az="${AZ_ARRAY[$index]}"
        local subnet_name
        subnet_name=$(generate_resource_name "subnet" "$stack_name" "$subnet_type" "$az")
        
        local subnet_id
        subnet_id=$(create_subnet "$vpc_id" "$subnet_name" "$cidr" "$az" "$subnet_type")
        if [[ $? -eq 0 ]]; then
            subnet_ids+=("$subnet_id")
            
            # Store subnet ID in variable store
            local var_name="${subnet_type^^}_SUBNET_IDS"
            set_variable "$var_name" "${subnet_ids[*]}" "$VARIABLE_SCOPE_STACK"
        else
            log_error "Failed to create subnet: $subnet_name" "VPC"
            return 1
        fi
        
        ((index++))
    done
    
    log_info "$subnet_type subnets created: ${subnet_ids[*]}" "VPC"
    return 0
}

# Create individual subnet
create_subnet() {
    local vpc_id="$1"
    local subnet_name="$2"
    local cidr="$3"
    local az="$4"
    local subnet_type="$5"
    
    log_info "Creating subnet: $subnet_name in AZ: $az" "VPC"
    
    # Validate subnet name
    if ! validate_resource_name "$subnet_name" "subnet"; then
        return 1
    fi
    
    # Validate CIDR
    if ! validate_cidr_block "$cidr"; then
        return 1
    fi
    
    # Set public IP mapping based on subnet type
    local map_public_ip="false"
    if [[ "$subnet_type" == "public" ]]; then
        map_public_ip="true"
    fi
    
    # Create subnet
    local subnet_output
    subnet_output=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$cidr" \
        --availability-zone "$az" \
        --map-public-ip-on-launch "$map_public_ip" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$subnet_name}]" \
        --output json \
        --query 'Subnet.SubnetId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create subnet: $subnet_output" "VPC"
        return 1
    fi
    
    local subnet_id
    subnet_id=$(echo "$subnet_output" | tr -d '"')
    
    # Wait for subnet to be available
    log_info "Waiting for subnet to be available: $subnet_id" "VPC"
    aws ec2 wait subnet-available \
        --subnet-ids "$subnet_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    if [[ $? -ne 0 ]]; then
        log_error "Subnet failed to become available: $subnet_id" "VPC"
        return 1
    fi
    
    log_info "Subnet created successfully: $subnet_id" "VPC"
    echo "$subnet_id"
    return 0
}

# =============================================================================
# INTERNET GATEWAY FUNCTIONS
# =============================================================================

# Create internet gateway
create_internet_gateway() {
    local stack_name="$1"
    
    log_info "Creating internet gateway for stack: $stack_name" "VPC"
    
    # Generate internet gateway name
    local igw_name
    igw_name=$(generate_resource_name "internet-gateway" "$stack_name")
    
    # Create internet gateway
    local igw_output
    igw_output=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$igw_name}]" \
        --output json \
        --query 'InternetGateway.InternetGatewayId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create internet gateway: $igw_output" "VPC"
        return 1
    fi
    
    local igw_id
    igw_id=$(echo "$igw_output" | tr -d '"')
    
    log_info "Internet gateway created successfully: $igw_id" "VPC"
    echo "$igw_id"
    return 0
}

# Attach internet gateway to VPC
attach_internet_gateway() {
    local igw_id="$1"
    local vpc_id="$2"
    
    log_info "Attaching internet gateway $igw_id to VPC $vpc_id" "VPC"
    
    if ! aws ec2 attach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to attach internet gateway to VPC" "VPC"
        return 1
    fi
    
    log_info "Internet gateway attached successfully" "VPC"
    return 0
}

# =============================================================================
# NAT GATEWAY FUNCTIONS
# =============================================================================

# Create NAT gateway
create_nat_gateway() {
    local stack_name="$1"
    local vpc_id="$2"
    
    log_info "Creating NAT gateway for stack: $stack_name" "VPC"
    
    # Get first public subnet for NAT gateway
    local public_subnet_ids
    public_subnet_ids=$(get_variable "PUBLIC_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
    
    if [[ -z "$public_subnet_ids" ]]; then
        log_error "No public subnets available for NAT gateway" "VPC"
        return 1
    fi
    
    # Use first public subnet
    local first_public_subnet
    first_public_subnet=$(echo "$public_subnet_ids" | cut -d' ' -f1)
    
    # Allocate elastic IP for NAT gateway
    local eip_id
    eip_id=$(allocate_elastic_ip "$stack_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to allocate elastic IP for NAT gateway" "VPC"
        return 1
    fi
    
    # Generate NAT gateway name
    local nat_gateway_name
    nat_gateway_name=$(generate_resource_name "nat-gateway" "$stack_name")
    
    # Create NAT gateway
    local nat_output
    nat_output=$(aws ec2 create-nat-gateway \
        --subnet-id "$first_public_subnet" \
        --allocation-id "$eip_id" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$nat_gateway_name}]" \
        --output json \
        --query 'NatGateway.NatGatewayId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create NAT gateway: $nat_output" "VPC"
        # Release elastic IP
        release_elastic_ip "$eip_id"
        return 1
    fi
    
    local nat_gateway_id
    nat_gateway_id=$(echo "$nat_output" | tr -d '"')
    
    # Wait for NAT gateway to be available
    log_info "Waiting for NAT gateway to be available: $nat_gateway_id" "VPC"
    aws ec2 wait nat-gateway-available \
        --nat-gateway-ids "$nat_gateway_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    if [[ $? -ne 0 ]]; then
        log_error "NAT gateway failed to become available: $nat_gateway_id" "VPC"
        return 1
    fi
    
    # Store elastic IP ID
    set_variable "NAT_GATEWAY_EIP_ID" "$eip_id" "$VARIABLE_SCOPE_STACK"
    
    log_info "NAT gateway created successfully: $nat_gateway_id" "VPC"
    echo "$nat_gateway_id"
    return 0
}

# Allocate elastic IP
allocate_elastic_ip() {
    local stack_name="$1"
    
    log_info "Allocating elastic IP for stack: $stack_name" "VPC"
    
    # Generate elastic IP name
    local eip_name
    eip_name=$(generate_resource_name "eip" "$stack_name")
    
    # Allocate elastic IP
    local eip_output
    eip_output=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$eip_name}]" \
        --output json \
        --query 'AllocationId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to allocate elastic IP: $eip_output" "VPC"
        return 1
    fi
    
    local eip_id
    eip_id=$(echo "$eip_output" | tr -d '"')
    
    log_info "Elastic IP allocated successfully: $eip_id" "VPC"
    echo "$eip_id"
    return 0
}

# Release elastic IP
release_elastic_ip() {
    local eip_id="$1"
    
    log_info "Releasing elastic IP: $eip_id" "VPC"
    
    if ! aws ec2 release-address \
        --allocation-id "$eip_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to release elastic IP: $eip_id" "VPC"
        return 1
    fi
    
    log_info "Elastic IP released successfully: $eip_id" "VPC"
    return 0
}

# =============================================================================
# ROUTE TABLE FUNCTIONS
# =============================================================================

# Create route tables
create_route_tables() {
    local vpc_id="$1"
    local stack_name="$2"
    local public_subnets="$3"
    local private_subnets="$4"
    
    log_info "Creating route tables for VPC: $vpc_id" "VPC"
    
    # Create public route table if public subnets exist
    if [[ -n "$public_subnets" ]]; then
        local public_route_table_id
        public_route_table_id=$(create_public_route_table "$vpc_id" "$stack_name")
        if [[ $? -eq 0 ]]; then
            set_variable "PUBLIC_ROUTE_TABLE_ID" "$public_route_table_id" "$VARIABLE_SCOPE_STACK"
        else
            log_error "Failed to create public route table" "VPC"
            return 1
        fi
    fi
    
    # Create private route table if private subnets exist
    if [[ -n "$private_subnets" ]]; then
        local private_route_table_id
        private_route_table_id=$(create_private_route_table "$vpc_id" "$stack_name")
        if [[ $? -eq 0 ]]; then
            set_variable "PRIVATE_ROUTE_TABLE_ID" "$private_route_table_id" "$VARIABLE_SCOPE_STACK"
        else
            log_error "Failed to create private route table" "VPC"
            return 1
        fi
    fi
    
    # Associate route tables with subnets
    if ! associate_route_tables "$stack_name"; then
        log_error "Failed to associate route tables with subnets" "VPC"
        return 1
    fi
    
    log_info "Route tables created and associated successfully" "VPC"
    return 0
}

# Create public route table
create_public_route_table() {
    local vpc_id="$1"
    local stack_name="$2"
    
    log_info "Creating public route table for VPC: $vpc_id" "VPC"
    
    # Generate route table name
    local route_table_name
    route_table_name=$(generate_resource_name "route-table" "$stack_name" "public")
    
    # Create route table
    local route_table_output
    route_table_output=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$route_table_name}]" \
        --output json \
        --query 'RouteTable.RouteTableId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create public route table: $route_table_output" "VPC"
        return 1
    fi
    
    local route_table_id
    route_table_id=$(echo "$route_table_output" | tr -d '"')
    
    # Add route to internet gateway
    local igw_id
    igw_id=$(get_variable "INTERNET_GATEWAY_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$igw_id" ]]; then
        if ! aws ec2 create-route \
            --route-table-id "$route_table_id" \
            --destination-cidr-block "0.0.0.0/0" \
            --gateway-id "$igw_id" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            log_error "Failed to add internet gateway route to public route table" "VPC"
            return 1
        fi
    fi
    
    log_info "Public route table created successfully: $route_table_id" "VPC"
    echo "$route_table_id"
    return 0
}

# Create private route table
create_private_route_table() {
    local vpc_id="$1"
    local stack_name="$2"
    
    log_info "Creating private route table for VPC: $vpc_id" "VPC"
    
    # Generate route table name
    local route_table_name
    route_table_name=$(generate_resource_name "route-table" "$stack_name" "private")
    
    # Create route table
    local route_table_output
    route_table_output=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$route_table_name}]" \
        --output json \
        --query 'RouteTable.RouteTableId' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create private route table: $route_table_output" "VPC"
        return 1
    fi
    
    local route_table_id
    route_table_id=$(echo "$route_table_output" | tr -d '"')
    
    # Add route to NAT gateway
    local nat_gateway_id
    nat_gateway_id=$(get_variable "NAT_GATEWAY_ID" "$VARIABLE_SCOPE_STACK")
    
    if [[ -n "$nat_gateway_id" ]]; then
        if ! aws ec2 create-route \
            --route-table-id "$route_table_id" \
            --destination-cidr-block "0.0.0.0/0" \
            --nat-gateway-id "$nat_gateway_id" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            log_error "Failed to add NAT gateway route to private route table" "VPC"
            return 1
        fi
    fi
    
    log_info "Private route table created successfully: $route_table_id" "VPC"
    echo "$route_table_id"
    return 0
}

# Associate route tables with subnets
associate_route_tables() {
    local stack_name="$1"
    
    log_info "Associating route tables with subnets" "VPC"
    
    # Get route table IDs
    local public_route_table_id
    public_route_table_id=$(get_variable "PUBLIC_ROUTE_TABLE_ID" "$VARIABLE_SCOPE_STACK")
    
    local private_route_table_id
    private_route_table_id=$(get_variable "PRIVATE_ROUTE_TABLE_ID" "$VARIABLE_SCOPE_STACK")
    
    # Associate public subnets with public route table
    if [[ -n "$public_route_table_id" ]]; then
        local public_subnet_ids
        public_subnet_ids=$(get_variable "PUBLIC_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$public_subnet_ids" ]]; then
            for subnet_id in $public_subnet_ids; do
                if ! associate_route_table "$public_route_table_id" "$subnet_id"; then
                    log_error "Failed to associate public subnet $subnet_id with route table" "VPC"
                    return 1
                fi
            done
        fi
    fi
    
    # Associate private subnets with private route table
    if [[ -n "$private_route_table_id" ]]; then
        local private_subnet_ids
        private_subnet_ids=$(get_variable "PRIVATE_SUBNET_IDS" "$VARIABLE_SCOPE_STACK")
        
        if [[ -n "$private_subnet_ids" ]]; then
            for subnet_id in $private_subnet_ids; do
                if ! associate_route_table "$private_route_table_id" "$subnet_id"; then
                    log_error "Failed to associate private subnet $subnet_id with route table" "VPC"
                    return 1
                fi
            done
        fi
    fi
    
    log_info "Route table associations completed successfully" "VPC"
    return 0
}

# Associate route table with subnet
associate_route_table() {
    local route_table_id="$1"
    local subnet_id="$2"
    
    log_info "Associating route table $route_table_id with subnet $subnet_id" "VPC"
    
    if ! aws ec2 associate-route-table \
        --route-table-id "$route_table_id" \
        --subnet-id "$subnet_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to associate route table with subnet" "VPC"
        return 1
    fi
    
    log_info "Route table associated successfully" "VPC"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get availability zones
get_availability_zones() {
    log_info "Getting availability zones for region: $AWS_REGION" "VPC"
    
    local az_output
    az_output=$(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query 'AvailabilityZones[].ZoneName' \
        --output text \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get availability zones: $az_output" "VPC"
        return 1
    fi
    
    # Limit to first 3 AZs
    local azs=()
    local count=0
    for az in $az_output; do
        if [[ $count -lt 3 ]]; then
            azs+=("$az")
            ((count++))
        else
            break
        fi
    done
    
    log_info "Using availability zones: ${azs[*]}" "VPC"
    echo "${azs[*]}"
    return 0
}

# Delete VPC
delete_vpc() {
    local vpc_id="$1"
    
    log_info "Deleting VPC: $vpc_id" "VPC"
    
    # Delete VPC (this will fail if resources still exist)
    if ! aws ec2 delete-vpc \
        --vpc-id "$vpc_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Failed to delete VPC: $vpc_id" "VPC"
        return 1
    fi
    
    log_info "VPC deleted successfully: $vpc_id" "VPC"
    return 0
}

# Get VPC information
get_vpc_info() {
    local vpc_id="$1"
    
    log_info "Getting VPC information: $vpc_id" "VPC"
    
    local vpc_info
    vpc_info=$(aws ec2 describe-vpcs \
        --vpc-ids "$vpc_id" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get VPC information: $vpc_info" "VPC"
        return 1
    fi
    
    echo "$vpc_info"
    return 0
}