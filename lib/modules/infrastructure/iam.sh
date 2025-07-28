#!/bin/bash
# =============================================================================
# IAM Infrastructure Module
# Comprehensive IAM roles, policies, and permissions management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_IAM_SH_LOADED:-}" ] && return 0
_IAM_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# IAM ROLE MANAGEMENT
# =============================================================================

# Create comprehensive IAM role for EC2 instances
create_ec2_iam_role() {
    local stack_name="${1:-$STACK_NAME}"
    local role_name="${2:-${stack_name}-ec2-role}"
    local enable_efs="${3:-true}"
    local enable_secrets="${4:-true}"
    
    with_error_context "create_ec2_iam_role" \
        _create_ec2_iam_role_impl "$stack_name" "$role_name" "$enable_efs" "$enable_secrets"
}

_create_ec2_iam_role_impl() {
    local stack_name="$1"
    local role_name="$2"
    local enable_efs="$3"
    local enable_secrets="$4"
    
    echo "Creating comprehensive EC2 IAM role: $role_name" >&2
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        echo "IAM role already exists: $role_name" >&2
        
        # Ensure instance profile exists
        create_instance_profile "$role_name"
        echo "$role_name"
        return 0
    fi
    
    # Create trust policy for EC2
    local trust_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "ec2.amazonaws.com",
                    "ssm.amazonaws.com"
                ]
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
        --description "Comprehensive IAM role for EC2 instances in $stack_name" \
        --tags $(tags_to_iam_format "$(generate_tags "$stack_name")") || {
        throw_error $ERROR_AWS_API "Failed to create IAM role"
    }
    
    # Attach AWS managed policies
    attach_aws_managed_policies "$role_name"
    
    # Create and attach custom policies
    create_parameter_store_policy "$role_name" "$enable_secrets"
    create_cloudwatch_comprehensive_policy "$role_name"
    create_ec2_management_policy "$role_name"
    
    if [ "$enable_efs" = "true" ]; then
        create_efs_comprehensive_policy "$role_name"
    fi
    
    # Create instance profile
    create_instance_profile "$role_name"
    
    # Register role
    register_resource "iam_roles" "$role_name" "{\"stack\": \"$stack_name\"}"
    
    echo "$role_name"
}

# Create service-linked role
create_service_linked_role() {
    local service_name="$1"  # e.g., "elasticfilesystem", "elasticloadbalancing"
    
    with_error_context "create_service_linked_role" \
        _create_service_linked_role_impl "$service_name"
}

_create_service_linked_role_impl() {
    local service_name="$1"
    
    echo "Creating service-linked role for: $service_name" >&2
    
    # Check if service-linked role already exists
    local existing_role
    existing_role=$(aws iam get-role \
        --role-name "AWSServiceRoleFor${service_name}" \
        --query 'Role.RoleName' \
        --output text 2>/dev/null || true)
    
    if [ -n "$existing_role" ] && [ "$existing_role" != "None" ] && [ "$existing_role" != "null" ]; then
        echo "Service-linked role already exists: $existing_role" >&2
        echo "$existing_role"
        return 0
    fi
    
    # Create service-linked role
    local role_arn
    role_arn=$(aws iam create-service-linked-role \
        --aws-service-name "${service_name}.amazonaws.com" \
        --query 'Role.Arn' \
        --output text) || {
        echo "Failed to create service-linked role for $service_name" >&2
        return 1
    }
    
    local role_name
    role_name=$(echo "$role_arn" | cut -d'/' -f2)
    
    echo "Created service-linked role: $role_name" >&2
    echo "$role_name"
}

# =============================================================================
# INSTANCE PROFILE MANAGEMENT
# =============================================================================

# Create and configure instance profile
create_instance_profile() {
    local role_name="$1"
    local profile_name="${role_name}-profile"
    
    echo "Creating instance profile: $profile_name" >&2
    
    # Check if instance profile already exists
    if aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        echo "Instance profile already exists: $profile_name" >&2
        echo "$profile_name"
        return 0
    fi
    
    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name "$profile_name" \
        --tags $(tags_to_iam_format "$(generate_tags "${STACK_NAME:-default}")") || {
        throw_error $ERROR_AWS_API "Failed to create instance profile"
    }
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" || {
        throw_error $ERROR_AWS_API "Failed to add role to instance profile"
    }
    
    # Wait for instance profile to propagate
    echo "Waiting for instance profile to propagate..." >&2
    sleep 10
    
    # Register instance profile
    register_resource "instance_profiles" "$profile_name" "{\"role\": \"$role_name\"}"
    
    echo "$profile_name"
}

# =============================================================================
# AWS MANAGED POLICIES
# =============================================================================

# Attach AWS managed policies
attach_aws_managed_policies() {
    local role_name="$1"
    
    echo "Attaching AWS managed policies" >&2
    
    # Core AWS managed policies for EC2 instances
    local managed_policies=(
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        "arn:aws:iam::aws:policy/AmazonEFSClientWrite"
        "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
    )
    
    for policy_arn in "${managed_policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn" || {
            echo "Policy may already be attached: $policy_arn" >&2
        }
        echo "Attached managed policy: $(echo "$policy_arn" | cut -d'/' -f2)" >&2
    done
}

# =============================================================================
# CUSTOM POLICY CREATION
# =============================================================================

# Create comprehensive Parameter Store policy
create_parameter_store_policy() {
    local role_name="$1"
    local enable_secrets="${2:-true}"
    local policy_name="${role_name}-parameter-store"
    
    local policy_document
    if [ "$enable_secrets" = "true" ]; then
        policy_document=$(cat <<EOF
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
                "ssm:DeleteParameter",
                "ssm:DescribeParameters"
            ],
            "Resource": [
                "arn:aws:ssm:*:*:parameter/aibuildkit/*",
                "arn:aws:ssm:*:*:parameter/${STACK_NAME:-default}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": [
                "arn:aws:secretsmanager:*:*:secret:aibuildkit/*",
                "arn:aws:secretsmanager:*:*:secret:${STACK_NAME:-default}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:Encrypt",
                "kms:GenerateDataKey",
                "kms:DescribeKey"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": [
                        "ssm.\${AWS::Region}.amazonaws.com",
                        "secretsmanager.\${AWS::Region}.amazonaws.com"
                    ]
                }
            }
        }
    ]
}
EOF
)
    else
        policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath",
                "ssm:DescribeParameters"
            ],
            "Resource": [
                "arn:aws:ssm:*:*:parameter/aibuildkit/*",
                "arn:aws:ssm:*:*:parameter/${STACK_NAME:-default}/*"
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
    fi
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create comprehensive CloudWatch policy
create_cloudwatch_comprehensive_policy() {
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
                "cloudwatch:GetMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams",
                "logs:DescribeLogGroups",
                "logs:PutRetentionPolicy"
            ],
            "Resource": [
                "arn:aws:logs:*:*:log-group:/aws/ec2/*",
                "arn:aws:logs:*:*:log-group:/aibuildkit/*",
                "arn:aws:logs:*:*:log-group:/${STACK_NAME:-default}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeInstances",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create EC2 management policy
create_ec2_management_policy() {
    local role_name="$1"
    local policy_name="${role_name}-ec2-management"
    
    local policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:DescribeImages",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeRegions",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:ModifyInstanceAttribute"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "ec2:ResourceTag/Stack": "${STACK_NAME:-default}"
                }
            }
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create comprehensive EFS policy
create_efs_comprehensive_policy() {
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
                "elasticfilesystem:ClientRootAccess",
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets",
                "elasticfilesystem:DescribeAccessPoints"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:CreateAccessPoint",
                "elasticfilesystem:DeleteAccessPoint",
                "elasticfilesystem:TagResource"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "elasticfilesystem:ResourceTag/Stack": "${STACK_NAME:-default}"
                }
            }
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# Create policy for application-specific permissions
create_application_policy() {
    local role_name="$1"
    local policy_name="${role_name}-application"
    
    local policy_document=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::aibuildkit-*/*",
                "arn:aws:s3:::${STACK_NAME:-default}-*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::aibuildkit-*",
                "arn:aws:s3:::${STACK_NAME:-default}-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": [
                "arn:aws:sns:*:*:aibuildkit-*",
                "arn:aws:sns:*:*:${STACK_NAME:-default}-*"
            ]
        }
    ]
}
EOF
)
    
    create_and_attach_policy "$role_name" "$policy_name" "$policy_document"
}

# =============================================================================
# POLICY MANAGEMENT UTILITIES
# =============================================================================

# Helper function to create and attach custom policy
create_and_attach_policy() {
    local role_name="$1"
    local policy_name="$2"
    local policy_document="$3"
    
    echo "Creating custom policy: $policy_name" >&2
    
    # Create policy
    local policy_arn
    policy_arn=$(aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "$policy_document" \
        --description "Custom policy for $role_name" \
        --tags $(tags_to_iam_format "$(generate_tags "${STACK_NAME:-default}")") \
        --query 'Policy.Arn' \
        --output text 2>/dev/null) || {
        
        # Policy might already exist, try to get ARN
        policy_arn=$(aws iam list-policies \
            --query "Policies[?PolicyName=='$policy_name'].Arn | [0]" \
            --output text 2>/dev/null)
        
        if [ -z "$policy_arn" ] || [ "$policy_arn" = "None" ]; then
            echo "Failed to create or find policy: $policy_name" >&2
            return 1
        fi
        
        echo "Policy already exists: $policy_name" >&2
    }
    
    # Attach policy to role
    if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn" || {
            echo "Failed to attach policy $policy_name to role $role_name" >&2
            return 1
        }
        
        # Register policy
        register_resource "iam_policies" "$policy_name" "{\"arn\": \"$policy_arn\", \"role\": \"$role_name\"}"
        
        echo "Successfully attached policy: $policy_name" >&2
    fi
    
    return 0
}

# List policies attached to role
list_role_policies() {
    local role_name="$1"
    
    echo "=== Attached Managed Policies ===" >&2
    aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[*].{PolicyName:PolicyName,PolicyArn:PolicyArn}' \
        --output table
    
    echo "=== Inline Policies ===" >&2
    aws iam list-role-policies \
        --role-name "$role_name" \
        --query 'PolicyNames' \
        --output table
}

# =============================================================================
# ROLE MANAGEMENT UTILITIES
# =============================================================================

# Validate role permissions
validate_role_permissions() {
    local role_name="$1"
    local instance_id="${2:-}"
    
    echo "Validating role permissions for: $role_name" >&2
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        echo "ERROR: Role does not exist: $role_name" >&2
        return 1
    fi
    
    # Check instance profile
    local profile_name="${role_name}-profile"
    if ! aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        echo "ERROR: Instance profile does not exist: $profile_name" >&2
        return 1
    fi
    
    # If instance ID provided, check if role is attached
    if [ -n "$instance_id" ]; then
        local attached_profile
        attached_profile=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
            --output text 2>/dev/null || echo "")
        
        # Handle None/null values
        if [ "$attached_profile" = "None" ] || [ "$attached_profile" = "null" ]; then
            attached_profile=""
        fi
        
        if [ -z "$attached_profile" ]; then
            echo "WARNING: No IAM instance profile attached to instance: $instance_id" >&2
        else
            echo "Instance profile attached: $(echo "$attached_profile" | cut -d'/' -f2)" >&2
        fi
    fi
    
    echo "Role validation completed" >&2
    return 0
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Comprehensive IAM cleanup
cleanup_iam_resources_comprehensive() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Starting comprehensive IAM cleanup for stack: $stack_name" >&2
    
    # Get all roles for this stack
    local role_names
    role_names=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '$stack_name')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    for role_name in $role_names; do
        if [ -n "$role_name" ] && [ "$role_name" != "None" ]; then
            cleanup_iam_role_comprehensive "$role_name"
        fi
    done
    
    echo "IAM cleanup completed" >&2
}

# Cleanup individual IAM role with all dependencies
cleanup_iam_role_comprehensive() {
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
    
    for policy_arn in $attached_policies; do
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" || true
            echo "Detached policy: $policy_arn" >&2
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
    local custom_policies=(
        "${role_name}-parameter-store"
        "${role_name}-cloudwatch"
        "${role_name}-ec2-management"
        "${role_name}-efs"
        "${role_name}-application"
    )
    
    for policy_name in "${custom_policies[@]}"; do
        local policy_arn
        policy_arn=$(aws iam list-policies \
            --query "Policies[?PolicyName=='$policy_name'].Arn | [0]" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
            echo "Deleted custom policy: $policy_name" >&2
        fi
    done
    
    # Delete role
    aws iam delete-role --role-name "$role_name" || true
    echo "Deleted IAM role: $role_name" >&2
}

# =============================================================================
# LEGACY COMPATIBILITY FUNCTIONS (MIGRATED FROM MONOLITH)
# =============================================================================

# Create standard IAM role (legacy compatibility function)
create_standard_iam_role() {
    local stack_name="$1"
    local additional_policies=("${@:2}")
    
    if [ -z "$stack_name" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "create_standard_iam_role requires stack_name parameter"
    fi

    local role_name="${stack_name}-role"
    # Ensure profile name starts with letter for AWS IAM compliance
    local profile_name
    if [[ "${stack_name}" =~ ^[0-9] ]]; then
        # Use simple prefix for numeric stacks to avoid AWS restrictions
        local clean_name
        clean_name=$(echo "${stack_name}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${stack_name}-instance-profile"
    fi
    
    echo "Creating/checking IAM role: $role_name" >&2

    # Check if role exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        echo "IAM role $role_name already exists." >&2
    else
        # Create trust policy
        local trust_policy='{
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
        }'

        # Create role
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$trust_policy" \
            --region "${AWS_REGION:-us-east-1}" >/dev/null || {
            throw_error $ERROR_AWS_API "Failed to create IAM role: $role_name"
        }

        # Standard policies for GeuseMaker
        local standard_policies=(
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
            "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        )
        
        # Attach standard policies
        for policy in "${standard_policies[@]}"; do
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" \
                --region "${AWS_REGION:-us-east-1}" || {
                echo "Failed to attach policy: $policy" >&2
            }
        done
        
        # Attach additional policies
        for policy in "${additional_policies[@]+"${additional_policies[@]}"}"; do
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" \
                --region "${AWS_REGION:-us-east-1}" || {
                echo "Failed to attach additional policy: $policy" >&2
            }
        done

        echo "IAM role created: $role_name" >&2
    fi

    # Create instance profile
    if aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        echo "Instance profile $profile_name already exists." >&2
        
        # Check if role is associated with the instance profile
        local associated_roles
        associated_roles=$(aws iam get-instance-profile \
            --instance-profile-name "$profile_name" \
            --query 'InstanceProfile.Roles[].RoleName' \
            --output text \
            --region "${AWS_REGION:-us-east-1}" 2>/dev/null || echo "")
        
        if [[ ! "$associated_roles" =~ "$role_name" ]]; then
            echo "Associating role $role_name with instance profile $profile_name" >&2
            aws iam add-role-to-instance-profile \
                --instance-profile-name "$profile_name" \
                --role-name "$role_name" \
                --region "${AWS_REGION:-us-east-1}" || {
                echo "Failed to associate role with instance profile" >&2
            }
            echo "Role associated with existing instance profile" >&2
        else
            echo "Role already associated with instance profile" >&2
        fi
    else
        aws iam create-instance-profile \
            --instance-profile-name "$profile_name" \
            --region "${AWS_REGION:-us-east-1}" >/dev/null || {
            throw_error $ERROR_AWS_API "Failed to create instance profile: $profile_name"
        }
        
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$profile_name" \
            --role-name "$role_name" \
            --region "${AWS_REGION:-us-east-1}" || {
            throw_error $ERROR_AWS_API "Failed to add role to instance profile"
        }
        
        echo "Instance profile created: $profile_name" >&2
    fi

    # Wait for IAM propagation
    sleep 10
    
    # Register the resources
    register_resource "iam_roles" "$role_name" "{\"profile\": \"$profile_name\"}"
    register_resource "iam_instance_profiles" "$profile_name" "{\"role\": \"$role_name\"}"
    
    echo "$profile_name"
    return 0
}

# Create standard key pair (legacy compatibility function)
create_standard_key_pair() {
    local stack_name="$1"
    local key_file="$2"
    
    if [ -z "$stack_name" ] || [ -z "$key_file" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "create_standard_key_pair requires stack_name and key_file parameters"
    fi

    echo "Creating/checking key pair: ${stack_name}-key" >&2

    # Check if key pair already exists
    if aws ec2 describe-key-pairs --key-names "${stack_name}-key" --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1; then
        echo "Key pair ${stack_name}-key already exists. Skipping creation." >&2
        
        # Check if local key file exists
        if [ ! -f "$key_file" ]; then
            throw_error $ERROR_RESOURCE_NOT_FOUND "Key pair exists in AWS but local key file $key_file is missing. Please either delete the AWS key pair or provide the private key file."
        fi
    else
        echo "Creating new key pair..." >&2
        aws ec2 create-key-pair \
            --key-name "${stack_name}-key" \
            --query 'KeyMaterial' \
            --output text \
            --region "${AWS_REGION:-us-east-1}" > "$key_file" || {
            throw_error $ERROR_AWS_API "Failed to create key pair: ${stack_name}-key"
        }
        
        chmod 600 "$key_file"
        echo "Key pair created: ${stack_name}-key" >&2
    fi

    # Register the resource
    register_resource "key_pairs" "${stack_name}-key" "{\"file\": \"$key_file\"}"
    
    return 0
}

# =============================================================================
# INITIALIZATION AND SETUP
# =============================================================================

# Setup comprehensive IAM for deployment
setup_comprehensive_iam() {
    local stack_name="${1:-$STACK_NAME}"
    local enable_efs="${2:-true}"
    local enable_secrets="${3:-true}"
    local enable_application="${4:-false}"
    
    echo "Setting up comprehensive IAM for: $stack_name" >&2
    
    # Create main EC2 role
    local role_name
    role_name=$(create_ec2_iam_role "$stack_name" "${stack_name}-role" "$enable_efs" "$enable_secrets") || return 1
    
    # Add application-specific permissions if requested
    if [ "$enable_application" = "true" ]; then
        create_application_policy "$role_name"
    fi
    
    # Create service-linked roles if they don't exist
    create_service_linked_role "elasticfilesystem" || true
    create_service_linked_role "elasticloadbalancing" || true
    
    # Validate setup
    validate_role_permissions "$role_name"
    
    # Return role information
    cat <<EOF
{
    "role_name": "$role_name",
    "instance_profile": "${role_name}-profile"
}
EOF
}