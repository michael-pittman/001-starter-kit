#!/usr/bin/env bash
# =============================================================================
# Compute Security Module
# Security group management for compute resources
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_SECURITY_SH_LOADED:-}" ] && return 0
_COMPUTE_SECURITY_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# SECURITY GROUP DEFAULTS
# =============================================================================

# Common ports
readonly PORT_SSH=22
readonly PORT_HTTP=80
readonly PORT_HTTPS=443
readonly PORT_RDP=3389

# Application ports
readonly PORT_N8N=5678
readonly PORT_OLLAMA=11434
readonly PORT_QDRANT=6333
readonly PORT_CRAWL4AI=11235
readonly PORT_POSTGRES=5432

# Protocol types
readonly PROTOCOL_TCP="tcp"
readonly PROTOCOL_UDP="udp"
readonly PROTOCOL_ICMP="icmp"
readonly PROTOCOL_ALL="-1"

# =============================================================================
# SECURITY GROUP CREATION
# =============================================================================

# Create security group
create_security_group() {
    local stack_name="$1"
    local vpc_id="$2"
    local sg_type="${3:-compute}"  # compute, alb, database, etc.
    local description="${4:-Security group for $sg_type resources}"
    
    log_info "Creating security group for $sg_type" "SECURITY"
    
    # Generate security group name
    local sg_name=$(generate_compute_resource_name "sg-$sg_type" "$stack_name")
    
    # Create security group
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$description" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text 2>&1) || {
        
        log_error "Failed to create security group: $sg_id" "SECURITY"
        return 1
    }
    
    log_info "Security group created: $sg_id" "SECURITY"
    
    # Tag security group
    local tags=$(generate_compute_tags "$stack_name" "security-group")
    aws ec2 create-tags \
        --resources "$sg_id" \
        --tags "Key=Name,Value=$sg_name" \
               "Key=Type,Value=$sg_type" \
        --tags $(echo "$tags" | jq -r '.[] | "Key=\(.Key),Value=\(.Value)"' | tr '\n' ' ') 2>/dev/null
    
    # Register security group
    register_resource "security_groups" "$sg_id" \
        "{\"name\": \"$sg_name\", \"type\": \"$sg_type\", \"vpc\": \"$vpc_id\", \"stack\": \"$stack_name\"}"
    
    # Configure rules based on type
    case "$sg_type" in
        compute)
            configure_compute_sg_rules "$sg_id" "$vpc_id"
            ;;
        alb)
            configure_alb_sg_rules "$sg_id"
            ;;
        database)
            configure_database_sg_rules "$sg_id" "$vpc_id"
            ;;
        *)
            log_info "No default rules for type: $sg_type" "SECURITY"
            ;;
    esac
    
    echo "$sg_id"
}

# =============================================================================
# SECURITY GROUP RULE CONFIGURATIONS
# =============================================================================

# Configure compute security group rules
configure_compute_sg_rules() {
    local sg_id="$1"
    local vpc_id="$2"
    
    log_info "Configuring compute security group rules" "SECURITY"
    
    # SSH access (restricted to VPC by default)
    add_ingress_rule "$sg_id" "$PORT_SSH" "$PROTOCOL_TCP" "10.0.0.0/8" "SSH access" || true
    
    # HTTP/HTTPS from ALB or anywhere
    local alb_sg_id=$(get_variable "ALB_SECURITY_GROUP_ID" || echo "")
    if [ -n "$alb_sg_id" ]; then
        # From ALB only
        add_ingress_rule_from_sg "$sg_id" "$PORT_HTTP" "$PROTOCOL_TCP" "$alb_sg_id" "HTTP from ALB"
        add_ingress_rule_from_sg "$sg_id" "$PORT_HTTPS" "$PROTOCOL_TCP" "$alb_sg_id" "HTTPS from ALB"
    else
        # From anywhere (development)
        add_ingress_rule "$sg_id" "$PORT_HTTP" "$PROTOCOL_TCP" "0.0.0.0/0" "HTTP access"
        add_ingress_rule "$sg_id" "$PORT_HTTPS" "$PROTOCOL_TCP" "0.0.0.0/0" "HTTPS access"
    fi
    
    # Application ports (from VPC)
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs \
        --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].CidrBlock' \
        --output text 2>/dev/null || echo "10.0.0.0/16")
    
    add_ingress_rule "$sg_id" "$PORT_N8N" "$PROTOCOL_TCP" "$vpc_cidr" "n8n access"
    add_ingress_rule "$sg_id" "$PORT_OLLAMA" "$PROTOCOL_TCP" "$vpc_cidr" "Ollama access"
    add_ingress_rule "$sg_id" "$PORT_QDRANT" "$PROTOCOL_TCP" "$vpc_cidr" "Qdrant access"
    add_ingress_rule "$sg_id" "$PORT_CRAWL4AI" "$PROTOCOL_TCP" "$vpc_cidr" "Crawl4AI access"
    
    # All outbound traffic
    add_egress_rule "$sg_id" "$PROTOCOL_ALL" "$PROTOCOL_ALL" "0.0.0.0/0" "All outbound traffic"
}

# Configure ALB security group rules
configure_alb_sg_rules() {
    local sg_id="$1"
    
    log_info "Configuring ALB security group rules" "SECURITY"
    
    # HTTP/HTTPS from anywhere
    add_ingress_rule "$sg_id" "$PORT_HTTP" "$PROTOCOL_TCP" "0.0.0.0/0" "HTTP access"
    add_ingress_rule "$sg_id" "$PORT_HTTPS" "$PROTOCOL_TCP" "0.0.0.0/0" "HTTPS access"
    
    # All outbound traffic
    add_egress_rule "$sg_id" "$PROTOCOL_ALL" "$PROTOCOL_ALL" "0.0.0.0/0" "All outbound traffic"
}

# Configure database security group rules
configure_database_sg_rules() {
    local sg_id="$1"
    local vpc_id="$2"
    
    log_info "Configuring database security group rules" "SECURITY"
    
    # PostgreSQL from compute instances
    local compute_sg_id=$(get_variable "COMPUTE_SECURITY_GROUP_ID" || echo "")
    if [ -n "$compute_sg_id" ]; then
        add_ingress_rule_from_sg "$sg_id" "$PORT_POSTGRES" "$PROTOCOL_TCP" "$compute_sg_id" "PostgreSQL from compute"
    else
        # From VPC
        local vpc_cidr
        vpc_cidr=$(aws ec2 describe-vpcs \
            --vpc-ids "$vpc_id" \
            --query 'Vpcs[0].CidrBlock' \
            --output text 2>/dev/null || echo "10.0.0.0/16")
        
        add_ingress_rule "$sg_id" "$PORT_POSTGRES" "$PROTOCOL_TCP" "$vpc_cidr" "PostgreSQL from VPC"
    fi
    
    # No outbound rules needed for RDS
}

# =============================================================================
# SECURITY GROUP RULE MANAGEMENT
# =============================================================================

# Add ingress rule
add_ingress_rule() {
    local sg_id="$1"
    local port="$2"
    local protocol="$3"
    local cidr="$4"
    local description="${5:-}"
    
    log_info "Adding ingress rule: $protocol/$port from $cidr" "SECURITY"
    
    local cmd="aws ec2 authorize-security-group-ingress"
    cmd="$cmd --group-id $sg_id"
    cmd="$cmd --protocol $protocol"
    
    # Handle port specification
    if [ "$port" != "$PROTOCOL_ALL" ]; then
        cmd="$cmd --port $port"
    fi
    
    cmd="$cmd --cidr $cidr"
    
    # Add description if provided
    if [ -n "$description" ]; then
        # Create rule specification with description
        local rule_spec=$(cat <<EOF
{
    "IpProtocol": "$protocol",
    "FromPort": $port,
    "ToPort": $port,
    "IpRanges": [{
        "CidrIp": "$cidr",
        "Description": "$description"
    }]
}
EOF
)
        
        # For 'all' protocol, adjust the spec
        if [ "$protocol" = "$PROTOCOL_ALL" ]; then
            rule_spec=$(cat <<EOF
{
    "IpProtocol": "-1",
    "IpRanges": [{
        "CidrIp": "$cidr",
        "Description": "$description"
    }]
}
EOF
)
        fi
        
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --ip-permissions "$rule_spec" 2>&1 || {
            
            # Check if rule already exists
            if [[ $? -eq 255 ]] || [[ "$rule_spec" =~ "already exists" ]]; then
                log_warn "Ingress rule already exists" "SECURITY"
                return 0
            else
                log_error "Failed to add ingress rule" "SECURITY"
                return 1
            fi
        }
    else
        eval "$cmd" 2>&1 || {
            log_warn "Ingress rule may already exist" "SECURITY"
            return 0
        }
    fi
    
    log_info "Ingress rule added successfully" "SECURITY"
}

# Add ingress rule from security group
add_ingress_rule_from_sg() {
    local sg_id="$1"
    local port="$2"
    local protocol="$3"
    local source_sg_id="$4"
    local description="${5:-}"
    
    log_info "Adding ingress rule: $protocol/$port from SG $source_sg_id" "SECURITY"
    
    # Create rule specification
    local rule_spec
    if [ "$port" = "$PROTOCOL_ALL" ]; then
        rule_spec=$(cat <<EOF
{
    "IpProtocol": "-1",
    "UserIdGroupPairs": [{
        "GroupId": "$source_sg_id",
        "Description": "$description"
    }]
}
EOF
)
    else
        rule_spec=$(cat <<EOF
{
    "IpProtocol": "$protocol",
    "FromPort": $port,
    "ToPort": $port,
    "UserIdGroupPairs": [{
        "GroupId": "$source_sg_id",
        "Description": "$description"
    }]
}
EOF
)
    fi
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --ip-permissions "$rule_spec" 2>&1 || {
        
        if [[ $? -eq 255 ]]; then
            log_warn "Ingress rule already exists" "SECURITY"
            return 0
        else
            log_error "Failed to add ingress rule from SG" "SECURITY"
            return 1
        fi
    }
    
    log_info "Ingress rule from SG added successfully" "SECURITY"
}

# Add egress rule
add_egress_rule() {
    local sg_id="$1"
    local port="$2"
    local protocol="$3"
    local cidr="$4"
    local description="${5:-}"
    
    log_info "Adding egress rule: $protocol/$port to $cidr" "SECURITY"
    
    # Note: Default security groups already allow all outbound traffic
    # This function is for custom egress rules
    
    local rule_spec
    if [ "$port" = "$PROTOCOL_ALL" ]; then
        rule_spec=$(cat <<EOF
{
    "IpProtocol": "-1",
    "IpRanges": [{
        "CidrIp": "$cidr",
        "Description": "$description"
    }]
}
EOF
)
    else
        rule_spec=$(cat <<EOF
{
    "IpProtocol": "$protocol",
    "FromPort": $port,
    "ToPort": $port,
    "IpRanges": [{
        "CidrIp": "$cidr",
        "Description": "$description"
    }]
}
EOF
)
    fi
    
    aws ec2 authorize-security-group-egress \
        --group-id "$sg_id" \
        --ip-permissions "$rule_spec" 2>&1 || {
        
        if [[ $? -eq 255 ]]; then
            log_warn "Egress rule already exists" "SECURITY"
            return 0
        else
            log_error "Failed to add egress rule" "SECURITY"
            return 1
        fi
    }
    
    log_info "Egress rule added successfully" "SECURITY"
}

# Remove ingress rule
remove_ingress_rule() {
    local sg_id="$1"
    local port="$2"
    local protocol="$3"
    local cidr="$4"
    
    log_info "Removing ingress rule: $protocol/$port from $cidr" "SECURITY"
    
    local cmd="aws ec2 revoke-security-group-ingress"
    cmd="$cmd --group-id $sg_id"
    cmd="$cmd --protocol $protocol"
    
    if [ "$port" != "$PROTOCOL_ALL" ]; then
        cmd="$cmd --port $port"
    fi
    
    cmd="$cmd --cidr $cidr"
    
    eval "$cmd" 2>&1 || {
        log_error "Failed to remove ingress rule" "SECURITY"
        return 1
    }
    
    log_info "Ingress rule removed successfully" "SECURITY"
}

# =============================================================================
# SECURITY GROUP QUERIES
# =============================================================================

# Get security group details
get_security_group_details() {
    local sg_id="$1"
    
    aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query 'SecurityGroups[0]' \
        --output json 2>/dev/null || echo "{}"
}

# Get security group rules
get_security_group_rules() {
    local sg_id="$1"
    local rule_type="${2:-all}"  # all, ingress, egress
    
    local query="SecurityGroups[0]"
    
    case "$rule_type" in
        ingress)
            query="$query.IpPermissions"
            ;;
        egress)
            query="$query.IpPermissionsEgress"
            ;;
        all)
            query="$query.{Ingress: IpPermissions, Egress: IpPermissionsEgress}"
            ;;
    esac
    
    aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query "$query" \
        --output json 2>/dev/null || echo "{}"
}

# Find security groups by tag
find_security_groups_by_tag() {
    local tag_key="$1"
    local tag_value="$2"
    
    aws ec2 describe-security-groups \
        --filters "Name=tag:$tag_key,Values=$tag_value" \
        --query 'SecurityGroups[].{
            GroupId: GroupId,
            GroupName: GroupName,
            VpcId: VpcId,
            Tags: Tags
        }' \
        --output json 2>/dev/null || echo "[]"
}

# Check if port is open
is_port_open() {
    local sg_id="$1"
    local port="$2"
    local protocol="${3:-tcp}"
    local direction="${4:-ingress}"
    
    local rules=$(get_security_group_rules "$sg_id" "$direction")
    
    # Check if port is in any rule
    echo "$rules" | jq -e --arg port "$port" --arg proto "$protocol" '
        .[] | select(
            .IpProtocol == $proto and
            ((.FromPort <= ($port | tonumber)) and (.ToPort >= ($port | tonumber)))
        )' >/dev/null 2>&1
}

# =============================================================================
# SECURITY GROUP VALIDATION
# =============================================================================

# Validate security group configuration
validate_security_group() {
    local sg_id="$1"
    local expected_type="${2:-compute}"
    
    log_info "Validating security group: $sg_id" "SECURITY"
    
    local sg_details=$(get_security_group_details "$sg_id")
    
    if [ -z "$sg_details" ] || [ "$sg_details" = "{}" ]; then
        log_error "Security group not found: $sg_id" "SECURITY"
        return 1
    fi
    
    # Check basic properties
    local vpc_id=$(echo "$sg_details" | jq -r '.VpcId')
    local sg_name=$(echo "$sg_details" | jq -r '.GroupName')
    
    log_info "Security group: $sg_name in VPC: $vpc_id" "SECURITY"
    
    # Validate rules based on type
    case "$expected_type" in
        compute)
            # Check SSH access
            if ! is_port_open "$sg_id" "$PORT_SSH" "$PROTOCOL_TCP" "ingress"; then
                log_warn "SSH port not open in compute security group" "SECURITY"
            fi
            
            # Check HTTP/HTTPS
            if ! is_port_open "$sg_id" "$PORT_HTTP" "$PROTOCOL_TCP" "ingress"; then
                log_warn "HTTP port not open in compute security group" "SECURITY"
            fi
            ;;
        alb)
            # Check HTTP/HTTPS from anywhere
            if ! is_port_open "$sg_id" "$PORT_HTTP" "$PROTOCOL_TCP" "ingress"; then
                log_error "HTTP port not open in ALB security group" "SECURITY"
                return 1
            fi
            
            if ! is_port_open "$sg_id" "$PORT_HTTPS" "$PROTOCOL_TCP" "ingress"; then
                log_error "HTTPS port not open in ALB security group" "SECURITY"
                return 1
            fi
            ;;
    esac
    
    log_info "Security group validation passed" "SECURITY"
    return 0
}

# Audit security group rules
audit_security_group() {
    local sg_id="$1"
    
    log_info "Auditing security group: $sg_id" "SECURITY"
    
    local rules=$(get_security_group_rules "$sg_id" "all")
    local warnings=0
    
    # Check for overly permissive rules
    echo "$rules" | jq -r '.Ingress[]' | jq -c '.' | while read -r rule; do
        local protocol=$(echo "$rule" | jq -r '.IpProtocol')
        local ranges=$(echo "$rule" | jq -r '.IpRanges[].CidrIp')
        
        for cidr in $ranges; do
            if [ "$cidr" = "0.0.0.0/0" ]; then
                local from_port=$(echo "$rule" | jq -r '.FromPort // "all"')
                local to_port=$(echo "$rule" | jq -r '.ToPort // "all"')
                
                # Check for sensitive ports open to world
                case "$from_port" in
                    22|3389|5432|3306|6379|27017)
                        log_warn "SECURITY RISK: Port $from_port open to 0.0.0.0/0" "SECURITY"
                        ((warnings++))
                        ;;
                    *)
                        if [ "$protocol" = "-1" ]; then
                            log_warn "SECURITY RISK: All ports open to 0.0.0.0/0" "SECURITY"
                            ((warnings++))
                        fi
                        ;;
                esac
            fi
        done
    done
    
    if [ $warnings -eq 0 ]; then
        log_info "Security audit passed - no major risks found" "SECURITY"
        return 0
    else
        log_warn "Security audit found $warnings warnings" "SECURITY"
        return 1
    fi
}

# =============================================================================
# SECURITY GROUP UPDATES
# =============================================================================

# Update security group description
update_security_group_description() {
    local sg_id="$1"
    local new_description="$2"
    
    log_info "Updating security group description" "SECURITY"
    
    # Note: AWS doesn't support updating SG description directly
    # This is a placeholder for documentation
    log_warn "Security group descriptions cannot be updated after creation" "SECURITY"
    
    # Update tags instead
    aws ec2 create-tags \
        --resources "$sg_id" \
        --tags "Key=Description,Value=$new_description" 2>/dev/null
}

# Copy security group rules
copy_security_group_rules() {
    local source_sg_id="$1"
    local target_sg_id="$2"
    
    log_info "Copying rules from $source_sg_id to $target_sg_id" "SECURITY"
    
    # Get source rules
    local source_rules=$(get_security_group_rules "$source_sg_id" "ingress")
    
    # Apply each rule to target
    echo "$source_rules" | jq -c '.[]' | while read -r rule; do
        local protocol=$(echo "$rule" | jq -r '.IpProtocol')
        local from_port=$(echo "$rule" | jq -r '.FromPort // empty')
        local to_port=$(echo "$rule" | jq -r '.ToPort // empty')
        
        # Handle CIDR rules
        echo "$rule" | jq -c '.IpRanges[]' 2>/dev/null | while read -r range; do
            local cidr=$(echo "$range" | jq -r '.CidrIp')
            local desc=$(echo "$range" | jq -r '.Description // "Copied rule"')
            
            if [ -n "$from_port" ] && [ "$from_port" != "null" ]; then
                add_ingress_rule "$target_sg_id" "$from_port" "$protocol" "$cidr" "$desc"
            else
                add_ingress_rule "$target_sg_id" "$PROTOCOL_ALL" "$protocol" "$cidr" "$desc"
            fi
        done
        
        # Handle SG rules
        echo "$rule" | jq -c '.UserIdGroupPairs[]' 2>/dev/null | while read -r sg_ref; do
            local ref_sg_id=$(echo "$sg_ref" | jq -r '.GroupId')
            local desc=$(echo "$sg_ref" | jq -r '.Description // "Copied SG rule"')
            
            if [ -n "$from_port" ] && [ "$from_port" != "null" ]; then
                add_ingress_rule_from_sg "$target_sg_id" "$from_port" "$protocol" "$ref_sg_id" "$desc"
            else
                add_ingress_rule_from_sg "$target_sg_id" "$PROTOCOL_ALL" "$protocol" "$ref_sg_id" "$desc"
            fi
        done
    done
    
    log_info "Security group rules copied successfully" "SECURITY"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Delete security group
delete_security_group() {
    local sg_id="$1"
    local force="${2:-false}"
    
    log_info "Deleting security group: $sg_id" "SECURITY"
    
    # Check if SG is in use
    if [ "$force" != "true" ]; then
        local instances
        instances=$(aws ec2 describe-instances \
            --filters "Name=instance.group-id,Values=$sg_id" \
                     "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text 2>/dev/null)
        
        if [ -n "$instances" ] && [ "$instances" != "None" ]; then
            log_error "Security group is in use by instances: $instances" "SECURITY"
            return 1
        fi
    fi
    
    # Delete security group
    aws ec2 delete-security-group \
        --group-id "$sg_id" 2>&1 || {
        
        log_error "Failed to delete security group" "SECURITY"
        return 1
    }
    
    # Unregister security group
    unregister_resource "security_groups" "$sg_id"
    
    log_info "Security group deleted successfully" "SECURITY"
}

# Delete all security groups for stack
delete_stack_security_groups() {
    local stack_name="$1"
    
    log_info "Deleting all security groups for stack: $stack_name" "SECURITY"
    
    # Find security groups with stack tag
    local sgs=$(find_security_groups_by_tag "Stack" "$stack_name")
    
    if [ "$sgs" = "[]" ]; then
        log_info "No security groups found for stack" "SECURITY"
        return 0
    fi
    
    # Delete each security group
    echo "$sgs" | jq -r '.[].GroupId' | while read -r sg_id; do
        delete_security_group "$sg_id" true || {
            log_error "Failed to delete security group: $sg_id" "SECURITY"
        }
    done
    
    log_info "Stack security groups deleted" "SECURITY"
}