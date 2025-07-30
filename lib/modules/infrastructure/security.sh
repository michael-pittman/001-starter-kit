#!/usr/bin/env bash
# =============================================================================
# Security Infrastructure Module
# Manages security groups, IAM roles, and key pairs
# =============================================================================

# Prevent multiple sourcing
[ -n "${_SECURITY_SH_LOADED:-}" ] && return 0
declare -gr _SECURITY_SH_LOADED=1

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies using dependency groups
source "${SCRIPT_DIR}/../core/dependency-groups.sh"
load_dependency_group "INFRASTRUCTURE" "$SCRIPT_DIR/.."

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
    
    # Validate required parameters
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "VPC ID is required for security group creation"
    fi
    
    # Validate VPC ID format (should be vpc-xxxxxxxx)
    if ! [[ "$vpc_id" =~ ^vpc-[a-f0-9]+$ ]]; then
        echo "ERROR: Invalid VPC ID format: '$vpc_id'" >&2
        echo "VPC ID should match pattern: vpc-xxxxxxxx" >&2
        throw_error $ERROR_INVALID_ARGUMENT "Invalid VPC ID format"
    fi
    
    if [ -z "$stack_name" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "Stack name is required for security group creation"
    fi
    
    echo "Creating security group for stack: $stack_name" >&2
    
    # Check if security group already exists
    local existing_sg
    existing_sg=$(get_security_group_by_stack "$stack_name" "$vpc_id") || true
    
    if [ -n "$existing_sg" ] && [ "$existing_sg" != "None" ] && [ "$existing_sg" != "null" ]; then
        echo "Security group already exists: $existing_sg" >&2
        echo "$existing_sg"
        return 0
    fi
    
    # Create security group
    local sg_id
    # Generate tags separately to ensure clean JSON
    local tags_json
    tags_json=$(generate_tags "$stack_name")
    local tag_spec
    tag_spec=$(tags_to_tag_spec "$tags_json" "security-group")
    
    sg_id=$(aws ec2 create-security-group \
        --group-name "${stack_name}-sg" \
        --description "$description" \
        --vpc-id "$vpc_id" \
        --tag-specifications "$tag_spec" \
        --query 'GroupId' \
        --output text) || {
        local exit_code=$?
        echo "Failed to create security group for stack: $stack_name" >&2
        echo "VPC ID: $vpc_id" >&2
        echo "Tag spec: $tag_spec" >&2
        throw_error $ERROR_AWS_API_ERROR "Failed to create security group (exit code: $exit_code)"
    }
    
    # Configure standard rules
    configure_security_group_rules "$sg_id" "$stack_name"
    
    # Register security group
    register_resource "security_groups" "$sg_id" "{\"vpc\": \"$vpc_id\"}"
    
    echo "$sg_id"
}

# =============================================================================
# SERVICE-SPECIFIC SECURITY GROUPS
# =============================================================================

# Create application load balancer security group
create_alb_security_group() {
    local vpc_id="$1"
    local stack_name="${2:-$STACK_NAME}"
    
    with_error_context "create_alb_security_group" \
        _create_alb_security_group_impl "$vpc_id" "$stack_name"
}

_create_alb_security_group_impl() {
    local vpc_id="$1"
    local stack_name="$2"
    
    # Validate required parameters
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "VPC ID is required for ALB security group creation"
    fi
    
    # Validate VPC ID format (should be vpc-xxxxxxxx)
    if ! [[ "$vpc_id" =~ ^vpc-[a-f0-9]+$ ]]; then
        echo "ERROR: Invalid VPC ID format: '$vpc_id'" >&2
        echo "VPC ID should match pattern: vpc-xxxxxxxx" >&2
        throw_error $ERROR_INVALID_ARGUMENT "Invalid VPC ID format"
    fi
    
    echo "Creating ALB security group" >&2
    
    # Check if ALB security group already exists
    local existing_sg
    existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${stack_name}-alb-sg" \
                  "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || true)
    
    if [ -n "$existing_sg" ] && [ "$existing_sg" != "None" ] && [ "$existing_sg" != "null" ]; then
        echo "ALB security group already exists: $existing_sg" >&2
        echo "$existing_sg"
        return 0
    fi
    
    # Create ALB security group
    local sg_id
    # Generate tags separately to ensure clean JSON
    local tags_json
    tags_json=$(generate_tags "$stack_name" '{"Purpose": "ALB"}')
    local tag_spec
    tag_spec=$(tags_to_tag_spec "$tags_json" "security-group")
    
    sg_id=$(aws ec2 create-security-group \
        --group-name "${stack_name}-alb-sg" \
        --description "Load balancer security group for $stack_name" \
        --vpc-id "$vpc_id" \
        --tag-specifications "$tag_spec" \
        --query 'GroupId' \
        --output text) || {
        local exit_code=$?
        echo "Failed to create ALB security group for stack: $stack_name" >&2
        echo "VPC ID: $vpc_id" >&2
        echo "Tag spec: $tag_spec" >&2
        throw_error $ERROR_AWS_API_ERROR "Failed to create ALB security group (exit code: $exit_code)"
    }
    
    # Configure ALB rules
    configure_alb_security_group_rules "$sg_id"
    
    # Register security group
    register_resource "security_groups" "$sg_id" "{\"vpc\": \"$vpc_id\", \"purpose\": \"alb\"}"
    
    echo "$sg_id"
}

# Create EFS security group
create_efs_security_group() {
    local vpc_id="$1"
    local ec2_sg_id="$2"
    local stack_name="${3:-$STACK_NAME}"
    
    with_error_context "create_efs_security_group" \
        _create_efs_security_group_impl "$vpc_id" "$ec2_sg_id" "$stack_name"
}

_create_efs_security_group_impl() {
    local vpc_id="$1"
    local ec2_sg_id="$2"
    local stack_name="$3"
    
    # Validate required parameters
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "VPC ID is required for EFS security group creation"
    fi
    
    # Validate VPC ID format (should be vpc-xxxxxxxx)
    if ! [[ "$vpc_id" =~ ^vpc-[a-f0-9]+$ ]]; then
        echo "ERROR: Invalid VPC ID format: '$vpc_id'" >&2
        echo "VPC ID should match pattern: vpc-xxxxxxxx" >&2
        throw_error $ERROR_INVALID_ARGUMENT "Invalid VPC ID format"
    fi
    
    if [ -z "$ec2_sg_id" ] || [ "$ec2_sg_id" = "None" ] || [ "$ec2_sg_id" = "null" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "EC2 security group ID is required for EFS security group creation"
    fi
    
    echo "Creating EFS security group" >&2
    
    # Check if EFS security group already exists
    local existing_sg
    existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${stack_name}-efs-sg" \
                  "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || true)
    
    if [ -n "$existing_sg" ] && [ "$existing_sg" != "None" ] && [ "$existing_sg" != "null" ]; then
        echo "EFS security group already exists: $existing_sg" >&2
        echo "$existing_sg"
        return 0
    fi
    
    # Create EFS security group
    local sg_id
    # Generate tags separately to ensure clean JSON
    local tags_json
    tags_json=$(generate_tags "$stack_name" '{"Purpose": "EFS"}')
    local tag_spec
    tag_spec=$(tags_to_tag_spec "$tags_json" "security-group")
    
    sg_id=$(aws ec2 create-security-group \
        --group-name "${stack_name}-efs-sg" \
        --description "EFS security group for $stack_name" \
        --vpc-id "$vpc_id" \
        --tag-specifications "$tag_spec" \
        --query 'GroupId' \
        --output text) || {
        local exit_code=$?
        echo "Failed to create EFS security group for stack: $stack_name" >&2
        echo "VPC ID: $vpc_id" >&2  
        echo "Tag spec: $tag_spec" >&2
        throw_error $ERROR_AWS_API_ERROR "Failed to create EFS security group (exit code: $exit_code)"
    }
    
    # Configure EFS rules - allow NFS from EC2 security group
    add_security_group_rule_from_sg "$sg_id" "tcp" 2049 2049 "$ec2_sg_id" "NFS from EC2 instances"
    
    # Register security group
    register_resource "security_groups" "$sg_id" "{\"vpc\": \"$vpc_id\", \"purpose\": \"efs\"}"
    
    echo "$sg_id"
}

# =============================================================================
# SECURITY GROUP RULE CONFIGURATION
# =============================================================================

# Configure security group rules with least privilege approach
configure_security_group_rules() {
    local sg_id="$1"
    local stack_name="$2"
    local allowed_cidrs="${3:-0.0.0.0/0}"  # Can be overridden for security
    
    echo "Configuring security group rules with least privilege" >&2
    
    # SSH access (consider restricting to specific IPs in production)
    add_security_group_rule "$sg_id" "tcp" 22 22 "$allowed_cidrs" "SSH access"
    
    # Application ports with descriptions
    add_security_group_rule "$sg_id" "tcp" 5678 5678 "$allowed_cidrs" "n8n Workflow UI"
    add_security_group_rule "$sg_id" "tcp" 6333 6333 "$allowed_cidrs" "Qdrant Vector Database API"
    add_security_group_rule "$sg_id" "tcp" 11434 11434 "$allowed_cidrs" "Ollama LLM API"
    add_security_group_rule "$sg_id" "tcp" 11235 11235 "$allowed_cidrs" "Crawl4AI Web Scraping API"
    
    # Database ports (should be restricted to internal traffic only)
    add_security_group_rule "$sg_id" "tcp" 5432 5432 "10.0.0.0/8" "PostgreSQL Database (internal)"
    
    # Health check and monitoring
    add_security_group_rule "$sg_id" "tcp" 8080 8080 "$allowed_cidrs" "Health check endpoint"
    add_security_group_rule "$sg_id" "tcp" 9090 9090 "10.0.0.0/8" "Prometheus metrics (internal)"
    
    # HTTPS/TLS ports for secure communication
    add_security_group_rule "$sg_id" "tcp" 443 443 "$allowed_cidrs" "HTTPS"
    add_security_group_rule "$sg_id" "tcp" 80 80 "$allowed_cidrs" "HTTP (redirect to HTTPS)"
    
    # Configure outbound rules (restrictive)
    configure_outbound_rules "$sg_id"
}

# Configure ALB-specific security group rules
configure_alb_security_group_rules() {
    local sg_id="$1"
    
    echo "Configuring ALB security group rules" >&2
    
    # HTTP and HTTPS from anywhere
    add_security_group_rule "$sg_id" "tcp" 80 80 "0.0.0.0/0" "HTTP from internet"
    add_security_group_rule "$sg_id" "tcp" 443 443 "0.0.0.0/0" "HTTPS from internet"
    
    # Health check port
    add_security_group_rule "$sg_id" "tcp" 8080 8080 "10.0.0.0/8" "Health check to targets"
}

# Configure restrictive outbound rules
configure_outbound_rules() {
    local sg_id="$1"
    
    echo "Configuring restrictive outbound rules" >&2
    
    # Remove default allow-all egress rule
    aws ec2 revoke-security-group-egress \
        --group-id "$sg_id" \
        --protocol all \
        --cidr "0.0.0.0/0" 2>/dev/null || true
    
    # Allow specific outbound traffic
    # HTTPS for package downloads and API calls
    add_outbound_rule "$sg_id" "tcp" 443 443 "0.0.0.0/0" "HTTPS outbound"
    
    # HTTP for package downloads
    add_outbound_rule "$sg_id" "tcp" 80 80 "0.0.0.0/0" "HTTP outbound"
    
    # DNS
    add_outbound_rule "$sg_id" "udp" 53 53 "0.0.0.0/0" "DNS queries"
    add_outbound_rule "$sg_id" "tcp" 53 53 "0.0.0.0/0" "DNS TCP queries"
    
    # NTP for time synchronization
    add_outbound_rule "$sg_id" "udp" 123 123 "0.0.0.0/0" "NTP"
    
    # SMTP for notifications (if needed)
    add_outbound_rule "$sg_id" "tcp" 587 587 "0.0.0.0/0" "SMTP TLS"
    add_outbound_rule "$sg_id" "tcp" 25 25 "0.0.0.0/0" "SMTP"
    
    # Internal VPC communication
    add_outbound_rule "$sg_id" "all" 0 65535 "10.0.0.0/8" "Internal VPC traffic"
}

# Add security group rule (ingress)
add_security_group_rule() {
    local sg_id="$1"
    local protocol="$2"
    local from_port="$3"
    local to_port="$4"
    local cidr="$5"
    local description="$6"
    
    # Handle protocol-specific port formats
    local port_param
    if [ "$protocol" = "all" ] || [ "$protocol" = "-1" ]; then
        port_param=""
    elif [ "$from_port" = "$to_port" ]; then
        port_param="--port $from_port"
    else
        port_param="--port $from_port-$to_port"
    fi
    
    # Execute the command with proper error handling
    local cmd="aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol $protocol $port_param --cidr $cidr"
    if [ -n "$description" ]; then
        cmd="$cmd --group-rule-description '$description'"
    fi
    
    eval "$cmd" 2>/dev/null || {
        echo "Ingress rule may already exist for $protocol:$from_port-$to_port" >&2
    }
}

# Add security group rule from another security group
add_security_group_rule_from_sg() {
    local sg_id="$1"
    local protocol="$2"
    local from_port="$3"
    local to_port="$4"
    local source_sg_id="$5"
    local description="$6"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$from_port-$to_port" \
        --source-group "$source_sg_id" \
        --group-rule-description "$description" 2>/dev/null || {
        echo "Rule may already exist for SG $source_sg_id to port $from_port-$to_port" >&2
    }
}

# Add outbound security group rule (egress)
add_outbound_rule() {
    local sg_id="$1"
    local protocol="$2"
    local from_port="$3"
    local to_port="$4"
    local cidr="$5"
    local description="$6"
    
    # Handle protocol-specific port formats
    local port_param
    if [ "$protocol" = "all" ] || [ "$protocol" = "-1" ]; then
        port_param=""
    elif [ "$from_port" = "$to_port" ]; then
        port_param="--port $from_port"
    else
        port_param="--port $from_port-$to_port"
    fi
    
    # Execute the command with proper error handling
    local cmd="aws ec2 authorize-security-group-egress --group-id $sg_id --protocol $protocol $port_param --cidr $cidr"
    if [ -n "$description" ]; then
        cmd="$cmd --group-rule-description '$description'"
    fi
    
    eval "$cmd" 2>/dev/null || {
        echo "Egress rule may already exist for $protocol:$from_port-$to_port" >&2
    }
}

# Get security group by stack
get_security_group_by_stack() {
    local stack_name="$1"
    local vpc_id="${2:-}"
    local sg_id
    
    local filters="Name=tag:Stack,Values=$stack_name"
    [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ] && filters="$filters Name=vpc-id,Values=$vpc_id"
    
    sg_id=$(aws ec2 describe-security-groups \
        --filters $filters \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || true)
    
    # Return empty if no security group found or if result is "None"
    if [ -z "$sg_id" ] || [ "$sg_id" = "None" ] || [ "$sg_id" = "null" ]; then
        return 0
    fi
    
    echo "$sg_id"
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
    # Generate tags separately to ensure clean JSON
    local tags_json
    tags_json=$(generate_tags "${STACK_NAME:-default}")
    local tag_spec
    tag_spec=$(tags_to_tag_spec "$tags_json" "key-pair")
    
    aws ec2 create-key-pair \
        --key-name "$key_name" \
        --tag-specifications "$tag_spec" \
        --query 'KeyMaterial' \
        --output text > "$key_file" || {
        throw_error $ERROR_AWS_API_ERROR "Failed to create key pair"
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
        throw_error $ERROR_AWS_API_ERROR "Failed to import key pair"
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
        --tags $(tags_to_iam_format "$(generate_tags "$stack_name")") || {
        throw_error $ERROR_AWS_API_ERROR "Failed to create IAM role"
    }
    
    # Attach policies
    attach_iam_policies "$role_name"
    
    # Create instance profile
    create_instance_profile "$role_name"
    
    # Register role
    register_resource "iam_roles" "$role_name"
    
    echo "$role_name"
}

# Attach required policies with enhanced permissions
attach_iam_policies() {
    local role_name="$1"
    
    echo "Attaching IAM policies" >&2
    
    # Attach AWS managed policies
    local policies=(
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        "arn:aws:iam::aws:policy/AmazonEFSClientWrite"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" || {
            echo "Policy may already be attached: $policy" >&2
        }
    done
    
    # Create and attach custom policies
    create_parameter_store_policy "$role_name"
    create_cloudwatch_policy "$role_name"
    create_efs_policy "$role_name"
    create_ec2_metadata_policy "$role_name"
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
                "ssm:GetParametersByPath",
                "ssm:PutParameter",
                "ssm:DeleteParameter"
            ],
            "Resource": [
                "arn:aws:ssm:*:*:parameter/aibuildkit/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:Encrypt",
                "kms:GenerateDataKey"
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
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create CloudWatch policy
create_cloudwatch_policy() {
    local role_name="$1"
    local policy_name="${role_name}-cloudwatch"
    
    local policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create EFS policy
create_efs_policy() {
    local role_name="$1"
    local policy_name="${role_name}-efs"
    
    local policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite",
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create EC2 metadata policy
create_ec2_metadata_policy() {
    local role_name="$1"
    local policy_name="${role_name}-ec2-metadata"
    
    local policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:DescribeImages",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Helper function to create and attach policy
create_and_attach_policy() {
    local role_name="$1"
    local policy_name="$2"
    local policy_document="$3"
    
    # Create policy
    aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "$policy_document" \
        --tags $(tags_to_iam_format "$(generate_tags "${STACK_NAME:-default}")") 2>/dev/null || {
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
        
        echo "Attached policy: $policy_name" >&2
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
# SECURITY GROUP MANAGEMENT UTILITIES
# =============================================================================

# Create comprehensive security group setup
create_comprehensive_security_groups() {
    local vpc_id="$1"
    local stack_name="${2:-$STACK_NAME}"
    local allowed_cidrs="${3:-0.0.0.0/0}"
    
    echo "Creating comprehensive security group setup" >&2
    
    # Create main application security group
    local app_sg_id
    app_sg_id=$(create_security_group "$vpc_id" "$stack_name" "Main application security group for $stack_name") || return 1
    
    # Configure with least privilege rules
    configure_security_group_rules "$app_sg_id" "$stack_name" "$allowed_cidrs"
    
    # Create ALB security group if ALB is needed
    local alb_sg_id
    alb_sg_id=$(create_alb_security_group "$vpc_id" "$stack_name") || return 1
    
    # Create EFS security group
    local efs_sg_id
    efs_sg_id=$(create_efs_security_group "$vpc_id" "$app_sg_id" "$stack_name") || return 1
    
    # Return security group information
    cat <<EOF
{
    "application_sg_id": "$app_sg_id",
    "alb_sg_id": "$alb_sg_id",
    "efs_sg_id": "$efs_sg_id"
}
EOF
}

# Get security groups by purpose
get_security_groups_by_purpose() {
    local stack_name="$1"
    local purpose="${2:-application}"  # application, alb, efs
    
    aws ec2 describe-security-groups \
        --filters "Name=tag:Stack,Values=$stack_name" \
                  "Name=tag:Purpose,Values=$purpose" \
        --query 'SecurityGroups[*].{Id:GroupId,Name:GroupName}' \
        --output json
}

# =============================================================================
# LEGACY COMPATIBILITY FUNCTIONS (MIGRATED FROM MONOLITH)
# =============================================================================

# Create standard security group (legacy compatibility function)
create_standard_security_group() {
    local stack_name="$1"
    local vpc_id="$2"
    local additional_ports=("${@:3}")
    
    if [ -z "$stack_name" ] || [ -z "$vpc_id" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "create_standard_security_group requires stack_name and vpc_id parameters"
    fi

    local sg_name="${stack_name}-sg"
    echo "Creating/checking security group: $sg_name" >&2

    # Check if security group exists
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "${AWS_REGION:-us-east-1}" 2>/dev/null)

    if [ "$sg_id" = "None" ] || [ -z "$sg_id" ]; then
        echo "Creating new security group..." >&2
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group for $stack_name GeuseMaker" \
            --vpc-id "$vpc_id" \
            --query 'GroupId' \
            --output text \
            --region "${AWS_REGION:-us-east-1}") || {
            throw_error $ERROR_AWS_API_ERROR "Failed to create security group: $sg_name"
        }
        
        # Standard ports for GeuseMaker
        local standard_ports=(22 5678 11434 11235 6333)
        
        # Combine standard and additional ports
        local all_ports=("${standard_ports[@]}" "${additional_ports[@]}")
        
        # Add ingress rules
        for port in "${all_ports[@]}"; do
            aws ec2 authorize-security-group-ingress \
                --group-id "$sg_id" \
                --protocol tcp \
                --port "$port" \
                --cidr 0.0.0.0/0 \
                --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1 || {
                echo "Rule may already exist for port $port" >&2
            }
        done
        
        echo "Security group created: $sg_name ($sg_id)" >&2
    else
        echo "Security group $sg_name already exists: $sg_id" >&2
    fi

    # Register the resource
    register_resource "security_groups" "$sg_id" "{\"vpc\": \"$vpc_id\", \"name\": \"$sg_name\"}"
    
    echo "$sg_id"
    return 0
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup all security groups for a stack
cleanup_security_groups_comprehensive() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up security groups for: $stack_name" >&2
    
    # Get all security groups for this stack
    local sg_ids
    sg_ids=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --query 'SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")
    
    # Delete security groups (may need multiple attempts due to dependencies)
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ] && [ -n "$sg_ids" ]; do
        echo "Security group cleanup attempt $attempt of $max_attempts" >&2
        
        local remaining_sgs=""
        for sg_id in $sg_ids; do
            if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
                if aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null; then
                    echo "Deleted security group: $sg_id" >&2
                else
                    remaining_sgs="$remaining_sgs $sg_id"
                fi
            fi
        done
        
        sg_ids="$remaining_sgs"
        if [ -z "$sg_ids" ]; then
            break
        fi
        
        # Wait before next attempt
        sleep $((attempt * 2))
        attempt=$((attempt + 1))
    done
    
    if [ -n "$sg_ids" ]; then
        echo "WARNING: Some security groups could not be deleted: $sg_ids" >&2
    fi
}

# Cleanup security resources
cleanup_security_resources() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up security resources for: $stack_name" >&2
    
    # Clean up security groups
    cleanup_security_groups_comprehensive "$stack_name"
    
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

# Cleanup IAM role comprehensive
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
    
    # Detach managed policies
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[*].PolicyArn' \
        --output text 2>/dev/null || echo "")
    
    for policy in $attached_policies; do
        if [ -n "$policy" ] && [ "$policy" != "None" ]; then
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" || true
            echo "Detached policy: $policy" >&2
        fi
    done
    
    # Delete inline policies
    local inline_policies
    inline_policies=$(aws iam list-role-policies \
        --role-name "$role_name" \
        --query 'PolicyNames' \
        --output text 2>/dev/null || echo "")
    
    for policy_name in $inline_policies; do
        if [ -n "$policy_name" ] && [ "$policy_name" != "None" ]; then
            aws iam delete-role-policy \
                --role-name "$role_name" \
                --policy-name "$policy_name" || true
            echo "Deleted inline policy: $policy_name" >&2
        fi
    done
    
    # Delete custom policies created for this role
    local custom_policy_name="${role_name}-parameter-store"
    local policy_arn
    policy_arn=$(aws iam list-policies \
        --query "Policies[?PolicyName=='$custom_policy_name'].Arn | [0]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
        aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
        echo "Deleted custom policy: $policy_arn" >&2
    fi
    
    # Delete role
    aws iam delete-role --role-name "$role_name" || true
    echo "Deleted IAM role: $role_name" >&2
}