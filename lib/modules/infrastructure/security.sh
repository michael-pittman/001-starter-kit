#!/bin/bash
# =============================================================================
# Security Infrastructure Module
# Manages security groups, IAM roles, and key pairs
# =============================================================================

# Prevent multiple sourcing
[ -n "${_SECURITY_SH_LOADED:-}" ] && return 0
_SECURITY_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# SECURITY GROUP MANAGEMENT
# =============================================================================

# Create security group with standard rules
create_security_group() {
    local vpc_id="$1"
    local stack_name="${2:-$STACK_NAME}"
    local description="${3:-Security group for $stack_name}"
    
    with_error_context "create_security_group" \
        _create_security_group_impl "$vpc_id" "$stack_name" "$description"
}

_create_security_group_impl() {
    local vpc_id="$1"
    local stack_name="$2"
    local description="$3"
    
    echo "Creating security group for stack: $stack_name" >&2
    
    # Check if security group already exists
    local existing_sg
    existing_sg=$(get_security_group_by_stack "$stack_name" "$vpc_id") || true
    
    if [ -n "$existing_sg" ]; then
        echo "Security group already exists: $existing_sg" >&2
        echo "$existing_sg"
        return 0
    fi
    
    # Create security group
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "${stack_name}-sg" \
        --description "$description" \
        --vpc-id "$vpc_id" \
        --tag-specifications "$(tags_to_tag_spec "$(generate_tags "$stack_name")" "security-group")" \
        --query 'GroupId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create security group"
    }
    
    # Configure standard rules
    configure_security_group_rules "$sg_id" "$stack_name"
    
    # Register security group
    register_resource "security_groups" "$sg_id" "{\"vpc\": \"$vpc_id\"}"
    
    echo "$sg_id"
}

# Configure security group rules
configure_security_group_rules() {
    local sg_id="$1"
    local stack_name="$2"
    
    echo "Configuring security group rules" >&2
    
    # SSH access
    add_security_group_rule "$sg_id" "tcp" 22 22 "0.0.0.0/0" "SSH access"
    
    # Application ports
    add_security_group_rule "$sg_id" "tcp" 5678 5678 "0.0.0.0/0" "n8n UI"
    add_security_group_rule "$sg_id" "tcp" 6333 6333 "0.0.0.0/0" "Qdrant API"
    add_security_group_rule "$sg_id" "tcp" 11434 11434 "0.0.0.0/0" "Ollama API"
    add_security_group_rule "$sg_id" "tcp" 11235 11235 "0.0.0.0/0" "Crawl4AI API"
    
    # Health check port
    add_security_group_rule "$sg_id" "tcp" 8080 8080 "0.0.0.0/0" "Health check"
    
    # Allow all outbound
    aws ec2 authorize-security-group-egress \
        --group-id "$sg_id" \
        --protocol all \
        --cidr "0.0.0.0/0" 2>/dev/null || true
}

# Add security group rule
add_security_group_rule() {
    local sg_id="$1"
    local protocol="$2"
    local from_port="$3"
    local to_port="$4"
    local cidr="$5"
    local description="$6"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$from_port-$to_port" \
        --cidr "$cidr" \
        --group-rule-description "$description" 2>/dev/null || {
        echo "Rule may already exist for port $from_port-$to_port" >&2
    }
}

# Get security group by stack
get_security_group_by_stack() {
    local stack_name="$1"
    local vpc_id="${2:-}"
    
    local filters="Name=tag:Stack,Values=$stack_name"
    [ -n "$vpc_id" ] && filters="$filters Name=vpc-id,Values=$vpc_id"
    
    aws ec2 describe-security-groups \
        --filters $filters \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -v "None" || true
}

# =============================================================================
# KEY PAIR MANAGEMENT
# =============================================================================

# Create or get key pair
ensure_key_pair() {
    local key_name="${1:-${KEY_NAME:-${STACK_NAME}-key}}"
    local key_dir="${2:-$HOME/.ssh}"
    
    with_error_context "ensure_key_pair" \
        _ensure_key_pair_impl "$key_name" "$key_dir"
}

_ensure_key_pair_impl() {
    local key_name="$1"
    local key_dir="$2"
    local key_file="${key_dir}/${key_name}.pem"
    
    # Check if key already exists locally
    if [ -f "$key_file" ]; then
        echo "Key pair already exists locally: $key_file" >&2
        
        # Verify it exists in AWS
        if aws ec2 describe-key-pairs --key-names "$key_name" >/dev/null 2>&1; then
            echo "$key_name"
            return 0
        else
            echo "Key exists locally but not in AWS, importing..." >&2
            import_key_pair "$key_name" "$key_file"
            echo "$key_name"
            return 0
        fi
    fi
    
    # Check if key exists in AWS
    if aws ec2 describe-key-pairs --key-names "$key_name" >/dev/null 2>&1; then
        echo "WARNING: Key pair exists in AWS but not locally: $key_name" >&2
        echo "You'll need the private key file to connect to instances" >&2
        echo "$key_name"
        return 0
    fi
    
    # Create new key pair
    create_key_pair "$key_name" "$key_dir"
    echo "$key_name"
}

# Create new key pair
create_key_pair() {
    local key_name="$1"
    local key_dir="$2"
    local key_file="${key_dir}/${key_name}.pem"
    
    echo "Creating new key pair: $key_name" >&2
    
    # Ensure directory exists
    mkdir -p "$key_dir"
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "$key_name" \
        --tag-specifications "$(tags_to_tag_spec "$(generate_tags "${STACK_NAME:-default}")" "key-pair")" \
        --query 'KeyMaterial' \
        --output text > "$key_file" || {
        throw_error $ERROR_AWS_API "Failed to create key pair"
    }
    
    # Set permissions
    chmod 600 "$key_file"
    
    # Register key pair
    register_resource "key_pairs" "$key_name" "{\"file\": \"$key_file\"}"
    
    echo "Key pair created: $key_file" >&2
}

# Import existing key pair
import_key_pair() {
    local key_name="$1"
    local key_file="$2"
    
    echo "Importing key pair: $key_name" >&2
    
    # Generate public key from private key
    local public_key
    public_key=$(ssh-keygen -y -f "$key_file") || {
        throw_error $ERROR_INVALID_ARGUMENT "Failed to extract public key from $key_file"
    }
    
    # Import to AWS
    aws ec2 import-key-pair \
        --key-name "$key_name" \
        --public-key-material "$public_key" || {
        throw_error $ERROR_AWS_API "Failed to import key pair"
    }
    
    # Register key pair
    register_resource "key_pairs" "$key_name" "{\"file\": \"$key_file\"}"
}

# =============================================================================
# IAM ROLE MANAGEMENT
# =============================================================================

# Create IAM role for EC2
create_iam_role() {
    local stack_name="${1:-$STACK_NAME}"
    local role_name="${2:-${stack_name}-role}"
    
    with_error_context "create_iam_role" \
        _create_iam_role_impl "$stack_name" "$role_name"
}

_create_iam_role_impl() {
    local stack_name="$1"
    local role_name="$2"
    
    echo "Creating IAM role: $role_name" >&2
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        echo "IAM role already exists: $role_name" >&2
        echo "$role_name"
        return 0
    fi
    
    # Create trust policy
    local trust_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    # Create role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" \
        --tags "$(tags_to_cli_format "$(generate_tags "$stack_name")")" || {
        throw_error $ERROR_AWS_API "Failed to create IAM role"
    }
    
    # Attach policies
    attach_iam_policies "$role_name"
    
    # Create instance profile
    create_instance_profile "$role_name"
    
    # Register role
    register_resource "iam_roles" "$role_name"
    
    echo "$role_name"
}

# Attach required policies
attach_iam_policies() {
    local role_name="$1"
    
    echo "Attaching IAM policies" >&2
    
    # Attach managed policies
    local policies=(
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" || {
            echo "Policy may already be attached: $policy" >&2
        }
    done
    
    # Create and attach custom policy for Parameter Store
    create_parameter_store_policy "$role_name"
}

# Create Parameter Store policy
create_parameter_store_policy() {
    local role_name="$1"
    local policy_name="${role_name}-parameter-store"
    
    local policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Resource": [
                "arn:aws:ssm:*:*:parameter/aibuildkit/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": "ssm.\${AWS::Region}.amazonaws.com"
                }
            }
        }
    ]
}
EOF
)
    
    # Create policy
    aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "$policy_document" \
        --tags "$(tags_to_cli_format "$(generate_tags "${STACK_NAME:-default}")")" 2>/dev/null || {
        echo "Policy may already exist: $policy_name" >&2
    }
    
    # Get policy ARN
    local policy_arn
    policy_arn=$(aws iam list-policies \
        --query "Policies[?PolicyName=='$policy_name'].Arn | [0]" \
        --output text)
    
    # Attach policy
    if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn" || true
            
        # Register policy
        register_resource "iam_policies" "$policy_name" "{\"arn\": \"$policy_arn\"}"
    fi
}

# Create instance profile
create_instance_profile() {
    local role_name="$1"
    local profile_name="${role_name}-profile"
    
    echo "Creating instance profile: $profile_name" >&2
    
    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name "$profile_name" 2>/dev/null || {
        echo "Instance profile may already exist" >&2
    }
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" 2>/dev/null || {
        echo "Role may already be added to profile" >&2
    }
    
    # Wait for profile to be ready
    sleep 5
    
    echo "$profile_name"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup security resources
cleanup_security_resources() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up security resources for: $stack_name" >&2
    
    # Clean up IAM resources
    local role_name="${stack_name}-role"
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        cleanup_iam_role "$role_name"
    fi
    
    # Clean up key pairs
    local key_name="${stack_name}-key"
    if aws ec2 describe-key-pairs --key-names "$key_name" >/dev/null 2>&1; then
        echo "Deleting key pair: $key_name" >&2
        aws ec2 delete-key-pair --key-name "$key_name" || true
    fi
}

# Cleanup IAM role
cleanup_iam_role() {
    local role_name="$1"
    local profile_name="${role_name}-profile"
    
    echo "Cleaning up IAM role: $role_name" >&2
    
    # Remove role from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" 2>/dev/null || true
    
    # Delete instance profile
    aws iam delete-instance-profile \
        --instance-profile-name "$profile_name" 2>/dev/null || true
    
    # Detach policies
    local policies
    policies=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[*].PolicyArn' \
        --output text 2>/dev/null)
    
    for policy in $policies; do
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" || true
    done
    
    # Delete role
    aws iam delete-role --role-name "$role_name" || true
}