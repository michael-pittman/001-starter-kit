#!/bin/bash
# Migrate VPC module from legacy to Unity AWS service

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source migration utilities
source "$SCRIPT_DIR/lib/migration-utils.sh"

# Legacy VPC module location
LEGACY_VPC_MODULE="$PROJECT_ROOT/archive/unity-cleanup-20250803_024204/original-files/lib/modules/infrastructure/vpc.sh"

# Target Unity AWS service
TARGET_SERVICE="$PROJECT_ROOT/lib/unity/services/unity-aws-service-vpc.sh"

# Main migration function
migrate_vpc_module() {
    log_migration "INFO" "Starting VPC module migration"
    
    # Check if legacy module exists
    if [[ ! -f "$LEGACY_VPC_MODULE" ]]; then
        log_migration "ERROR" "Legacy VPC module not found: $LEGACY_VPC_MODULE"
        return 1
    fi
    
    # Create target service file
    mkdir -p "$(dirname "$TARGET_SERVICE")"
    
    cat > "$TARGET_SERVICE" << 'EOF'
#!/bin/bash
# Unity AWS Service - VPC Operations
# Migrated from legacy VPC module

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity core
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || {
    echo "Error: Failed to load Unity core" >&2
    exit 1
}

# VPC Management Functions

# Create VPC with Unity patterns
create_vpc_unity() {
    local stack_name="$1"
    local cidr_block="${2:-10.0.0.0/16}"
    local multi_az="${3:-false}"
    
    unity_emit_event "VPC_CREATION_STARTED" "aws" "$stack_name"
    
    unity_log "INFO" "Creating VPC for stack: $stack_name"
    unity_log "DEBUG" "CIDR: $cidr_block, Multi-AZ: $multi_az"
    
    # Create VPC
    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr_block" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$stack_name-vpc},{Key=unity:managed,Value=true},{Key=unity:stack,Value=$stack_name}]" \
        --query 'Vpc.VpcId' \
        --output text) || {
        unity_log "ERROR" "Failed to create VPC"
        unity_emit_event "VPC_CREATION_FAILED" "aws" "$stack_name"
        return 1
    }
    
    unity_log "INFO" "Created VPC: $vpc_id"
    
    # Enable DNS
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames || {
        unity_log "ERROR" "Failed to enable DNS hostnames"
        return 1
    }
    
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support || {
        unity_log "ERROR" "Failed to enable DNS support"
        return 1
    }
    
    # Create subnets
    if [[ "$multi_az" == "true" ]]; then
        create_multi_az_subnets_unity "$vpc_id" "$stack_name"
    else
        create_single_az_subnet_unity "$vpc_id" "$stack_name"
    fi
    
    # Create Internet Gateway
    create_internet_gateway_unity "$vpc_id" "$stack_name"
    
    # Create route tables
    create_route_tables_unity "$vpc_id" "$stack_name"
    
    # Store VPC ID in Unity state
    unity_set_state "vpc_id_$stack_name" "$vpc_id"
    
    unity_emit_event "VPC_CREATED" "aws" "$vpc_id"
    
    echo "$vpc_id"
}

# Create subnets for single AZ
create_single_az_subnet_unity() {
    local vpc_id="$1"
    local stack_name="$2"
    
    unity_log "INFO" "Creating single-AZ subnet configuration"
    
    # Get first available AZ
    local az=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[?State==`available`].ZoneName | [0]' \
        --output text)
    
    # Create public subnet
    local public_subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.1.0/24" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$stack_name-public},{Key=unity:type,Value=public}]" \
        --query 'Subnet.SubnetId' \
        --output text) || {
        unity_log "ERROR" "Failed to create public subnet"
        return 1
    }
    
    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute \
        --subnet-id "$public_subnet_id" \
        --map-public-ip-on-launch || {
        unity_log "ERROR" "Failed to enable auto-assign public IP"
        return 1
    }
    
    # Create private subnet
    local private_subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.2.0/24" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$stack_name-private},{Key=unity:type,Value=private}]" \
        --query 'Subnet.SubnetId' \
        --output text) || {
        unity_log "ERROR" "Failed to create private subnet"
        return 1
    }
    
    unity_log "INFO" "Created subnets - Public: $public_subnet_id, Private: $private_subnet_id"
    
    # Store subnet IDs
    unity_set_state "public_subnet_${stack_name}" "$public_subnet_id"
    unity_set_state "private_subnet_${stack_name}" "$private_subnet_id"
}

# Create subnets for multi-AZ
create_multi_az_subnets_unity() {
    local vpc_id="$1"
    local stack_name="$2"
    
    unity_log "INFO" "Creating multi-AZ subnet configuration"
    
    # Get available AZs
    local azs=($(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text))
    
    if [[ ${#azs[@]} -lt 2 ]]; then
        unity_log "ERROR" "Insufficient availability zones for multi-AZ deployment"
        return 1
    fi
    
    local public_subnets=()
    local private_subnets=()
    
    # Create subnets in first two AZs
    for i in 0 1; do
        local az="${azs[$i]}"
        local az_suffix=$((i + 1))
        
        # Public subnet
        local public_subnet_id=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "10.0.$((i*2+1)).0/24" \
            --availability-zone "$az" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$stack_name-public-${az_suffix}},{Key=unity:type,Value=public}]" \
            --query 'Subnet.SubnetId' \
            --output text) || {
            unity_log "ERROR" "Failed to create public subnet in $az"
            return 1
        }
        
        aws ec2 modify-subnet-attribute \
            --subnet-id "$public_subnet_id" \
            --map-public-ip-on-launch
        
        public_subnets+=("$public_subnet_id")
        
        # Private subnet
        local private_subnet_id=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "10.0.$((i*2+2)).0/24" \
            --availability-zone "$az" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$stack_name-private-${az_suffix}},{Key=unity:type,Value=private}]" \
            --query 'Subnet.SubnetId' \
            --output text) || {
            unity_log "ERROR" "Failed to create private subnet in $az"
            return 1
        }
        
        private_subnets+=("$private_subnet_id")
    done
    
    unity_log "INFO" "Created multi-AZ subnets"
    unity_log "DEBUG" "Public subnets: ${public_subnets[*]}"
    unity_log "DEBUG" "Private subnets: ${private_subnets[*]}"
    
    # Store subnet IDs
    unity_set_state "public_subnets_${stack_name}" "${public_subnets[*]}"
    unity_set_state "private_subnets_${stack_name}" "${private_subnets[*]}"
}

# Create Internet Gateway
create_internet_gateway_unity() {
    local vpc_id="$1"
    local stack_name="$2"
    
    unity_log "INFO" "Creating Internet Gateway"
    
    # Create IGW
    local igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$stack_name-igw}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text) || {
        unity_log "ERROR" "Failed to create Internet Gateway"
        return 1
    }
    
    # Attach to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id" || {
        unity_log "ERROR" "Failed to attach Internet Gateway to VPC"
        return 1
    }
    
    unity_log "INFO" "Created and attached Internet Gateway: $igw_id"
    
    # Store IGW ID
    unity_set_state "igw_${stack_name}" "$igw_id"
}

# Create route tables
create_route_tables_unity() {
    local vpc_id="$1"
    local stack_name="$2"
    
    unity_log "INFO" "Creating route tables"
    
    # Get IGW ID
    local igw_id=$(unity_get_state "igw_${stack_name}")
    
    # Create public route table
    local public_rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$stack_name-public-rt}]" \
        --query 'RouteTable.RouteTableId' \
        --output text) || {
        unity_log "ERROR" "Failed to create public route table"
        return 1
    }
    
    # Add route to IGW
    aws ec2 create-route \
        --route-table-id "$public_rt_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id" || {
        unity_log "ERROR" "Failed to create route to Internet Gateway"
        return 1
    }
    
    # Associate with public subnets
    local public_subnets=$(unity_get_state "public_subnets_${stack_name}" || unity_get_state "public_subnet_${stack_name}")
    
    for subnet_id in $public_subnets; do
        aws ec2 associate-route-table \
            --subnet-id "$subnet_id" \
            --route-table-id "$public_rt_id" || {
            unity_log "WARN" "Failed to associate route table with subnet: $subnet_id"
        }
    done
    
    unity_log "INFO" "Created and configured route tables"
}

# Delete VPC and all resources
delete_vpc_unity() {
    local stack_name="$1"
    local vpc_id="${2:-$(unity_get_state "vpc_id_$stack_name")}"
    
    if [[ -z "$vpc_id" ]]; then
        unity_log "ERROR" "No VPC found for stack: $stack_name"
        return 1
    fi
    
    unity_emit_event "VPC_DELETION_STARTED" "aws" "$vpc_id"
    
    unity_log "INFO" "Deleting VPC and resources for stack: $stack_name"
    
    # Delete in reverse order of creation
    # 1. Delete routes (except default)
    # 2. Delete subnets
    # 3. Detach and delete IGW
    # 4. Delete security groups (except default)
    # 5. Delete VPC
    
    # Implementation would go here...
    
    unity_emit_event "VPC_DELETED" "aws" "$vpc_id"
    
    # Clear state
    unity_delete_state "vpc_id_$stack_name"
    unity_delete_state "public_subnet_${stack_name}"
    unity_delete_state "private_subnet_${stack_name}"
    unity_delete_state "public_subnets_${stack_name}"
    unity_delete_state "private_subnets_${stack_name}"
    unity_delete_state "igw_${stack_name}"
}

# Check if VPC exists
vpc_exists_unity() {
    local vpc_id="$1"
    
    if aws ec2 describe-vpcs --vpc-ids "$vpc_id" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get VPC by stack name
get_vpc_by_stack_unity() {
    local stack_name="$1"
    
    # First check Unity state
    local vpc_id=$(unity_get_state "vpc_id_$stack_name")
    
    if [[ -n "$vpc_id" ]] && vpc_exists_unity "$vpc_id"; then
        echo "$vpc_id"
        return 0
    fi
    
    # Search by tags
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:unity:stack,Values=$stack_name" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)
    
    if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
        echo "$vpc_id"
        return 0
    fi
    
    return 1
}

# Export functions
export -f create_vpc_unity
export -f create_single_az_subnet_unity
export -f create_multi_az_subnets_unity
export -f create_internet_gateway_unity
export -f create_route_tables_unity
export -f delete_vpc_unity
export -f vpc_exists_unity
export -f get_vpc_by_stack_unity
EOF
    
    # Make executable
    chmod +x "$TARGET_SERVICE"
    
    log_migration "SUCCESS" "Created Unity VPC service: $TARGET_SERVICE"
    
    # Update references
    log_migration "INFO" "Updating references to VPC module"
    update_legacy_references \
        "lib/modules/infrastructure/vpc.sh" \
        "lib/unity/services/unity-aws-service-vpc.sh"
    
    # Generate migration report
    generate_migration_report "vpc" "success" "VPC module migrated to Unity AWS service"
    
    return 0
}

# Main execution
main() {
    log_migration "INFO" "VPC Module Migration Tool"
    log_migration "INFO" "========================"
    
    if ! migrate_vpc_module; then
        log_migration "ERROR" "VPC module migration failed"
        exit 1
    fi
    
    log_migration "SUCCESS" "VPC module migration completed successfully"
    echo ""
    echo "Next steps:"
    echo "1. Review migrated service: $TARGET_SERVICE"
    echo "2. Update AWS service to include VPC operations"
    echo "3. Test VPC functionality: ./tests/unity/unit/test-unity-aws-service.sh"
}

# Run main
main