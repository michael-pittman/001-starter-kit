#!/bin/bash
# =============================================================================
# Resource Cleanup Module
# Handles cleanup of all AWS resources
# =============================================================================

# Prevent multiple sourcing
[ -n "${_RESOURCES_CLEANUP_SH_LOADED:-}" ] && return 0
_RESOURCES_CLEANUP_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# CLEANUP ORCHESTRATION
# =============================================================================

# Main cleanup function
cleanup_all_resources() {
    local stack_name="${1:-$STACK_NAME}"
    local force="${2:-false}"
    
    echo "=== Starting Resource Cleanup for Stack: $stack_name ==="
    
    # Load registry if exists
    if [ ! -f "$RESOURCE_REGISTRY_FILE" ]; then
        echo "No resource registry found, attempting tag-based cleanup..." >&2
        cleanup_by_tags "$stack_name"
        return
    fi
    
    # Get cleanup order
    local cleanup_order=($(get_cleanup_order))
    
    # Cleanup each resource type
    for resource_type in "${cleanup_order[@]}"; do
        cleanup_resource_type "$resource_type" "$force"
    done
    
    echo "=== Cleanup Complete ==="
}

# Cleanup specific resource type
cleanup_resource_type() {
    local resource_type="$1"
    local force="$2"
    
    # Get resources of this type
    local resources=($(get_resources "$resource_type"))
    
    if [ ${#resources[@]} -eq 0 ]; then
        return 0
    fi
    
    echo "Cleaning up $resource_type (${#resources[@]} resources)..."
    
    case "$resource_type" in
        spot_requests)
            cleanup_spot_requests "${resources[@]}"
            ;;
        instances)
            cleanup_instances "${resources[@]}"
            ;;
        elastic_ips)
            cleanup_elastic_ips "${resources[@]}"
            ;;
        efs_mount_targets)
            cleanup_efs_mount_targets "${resources[@]}"
            ;;
        efs_filesystems)
            cleanup_efs_filesystems "${resources[@]}"
            ;;
        target_groups)
            cleanup_target_groups "${resources[@]}"
            ;;
        load_balancers)
            cleanup_load_balancers "${resources[@]}"
            ;;
        network_interfaces)
            cleanup_network_interfaces "${resources[@]}"
            ;;
        security_groups)
            cleanup_security_groups "${resources[@]}"
            ;;
        subnets)
            cleanup_subnets "${resources[@]}"
            ;;
        internet_gateways)
            cleanup_internet_gateways "${resources[@]}"
            ;;
        route_tables)
            cleanup_route_tables "${resources[@]}"
            ;;
        vpc)
            cleanup_vpcs "${resources[@]}"
            ;;
        iam_policies)
            cleanup_iam_policies "${resources[@]}"
            ;;
        iam_roles)
            cleanup_iam_roles "${resources[@]}"
            ;;
        key_pairs)
            cleanup_key_pairs "${resources[@]}"
            ;;
        volumes)
            cleanup_volumes "${resources[@]}"
            ;;
        *)
            echo "Unknown resource type: $resource_type" >&2
            ;;
    esac
}

# =============================================================================
# INSTANCE CLEANUP
# =============================================================================

cleanup_instances() {
    local instances=("$@")
    
    for instance_id in "${instances[@]}"; do
        echo "Terminating instance: $instance_id"
        
        aws ec2 terminate-instances \
            --instance-ids "$instance_id" 2>/dev/null || {
            echo "Failed to terminate instance: $instance_id" >&2
        }
        
        unregister_resource "instances" "$instance_id"
    done
    
    # Wait for termination
    if [ ${#instances[@]} -gt 0 ]; then
        echo "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated \
            --instance-ids "${instances[@]}" 2>/dev/null || true
    fi
}

cleanup_spot_requests() {
    local requests=("$@")
    
    for request_id in "${requests[@]}"; do
        echo "Cancelling spot request: $request_id"
        
        aws ec2 cancel-spot-instance-requests \
            --spot-instance-request-ids "$request_id" 2>/dev/null || {
            echo "Failed to cancel spot request: $request_id" >&2
        }
        
        unregister_resource "spot_requests" "$request_id"
    done
}

# =============================================================================
# NETWORK CLEANUP
# =============================================================================

cleanup_security_groups() {
    local groups=("$@")
    
    for group_id in "${groups[@]}"; do
        echo "Deleting security group: $group_id"
        
        # Remove all rules first
        echo "Removing security group rules..."
        aws ec2 revoke-security-group-ingress \
            --group-id "$group_id" \
            --ip-permissions "$(aws ec2 describe-security-groups \
                --group-ids "$group_id" \
                --query 'SecurityGroups[0].IpPermissions' 2>/dev/null)" \
            2>/dev/null || true
        
        # Delete security group
        aws ec2 delete-security-group \
            --group-id "$group_id" 2>/dev/null || {
            echo "Failed to delete security group: $group_id" >&2
        }
        
        unregister_resource "security_groups" "$group_id"
    done
}

cleanup_subnets() {
    local subnets=("$@")
    
    for subnet_id in "${subnets[@]}"; do
        echo "Deleting subnet: $subnet_id"
        
        aws ec2 delete-subnet \
            --subnet-id "$subnet_id" 2>/dev/null || {
            echo "Failed to delete subnet: $subnet_id" >&2
        }
        
        unregister_resource "subnets" "$subnet_id"
    done
}

cleanup_internet_gateways() {
    local igws=("$@")
    
    for igw_id in "${igws[@]}"; do
        echo "Deleting internet gateway: $igw_id"
        
        # Get attached VPCs
        local vpcs
        vpcs=$(aws ec2 describe-internet-gateways \
            --internet-gateway-ids "$igw_id" \
            --query 'InternetGateways[0].Attachments[*].VpcId' \
            --output text 2>/dev/null)
        
        # Detach from VPCs
        for vpc_id in $vpcs; do
            echo "Detaching IGW from VPC: $vpc_id"
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$igw_id" \
                --vpc-id "$vpc_id" 2>/dev/null || true
        done
        
        # Delete IGW
        aws ec2 delete-internet-gateway \
            --internet-gateway-id "$igw_id" 2>/dev/null || {
            echo "Failed to delete internet gateway: $igw_id" >&2
        }
        
        unregister_resource "internet_gateways" "$igw_id"
    done
}

cleanup_vpcs() {
    local vpcs=("$@")
    
    for vpc_id in "${vpcs[@]}"; do
        echo "Deleting VPC: $vpc_id"
        
        aws ec2 delete-vpc \
            --vpc-id "$vpc_id" 2>/dev/null || {
            echo "Failed to delete VPC: $vpc_id" >&2
        }
        
        unregister_resource "vpc" "$vpc_id"
    done
}

# =============================================================================
# IAM CLEANUP
# =============================================================================

cleanup_iam_roles() {
    local roles=("$@")
    
    for role_name in "${roles[@]}"; do
        echo "Deleting IAM role: $role_name"
        
        # Remove from instance profiles
        local profile_name="${role_name}-profile"
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$profile_name" \
            --role-name "$role_name" 2>/dev/null || true
        
        aws iam delete-instance-profile \
            --instance-profile-name "$profile_name" 2>/dev/null || true
        
        # Detach policies
        local policies
        policies=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null)
        
        for policy_arn in $policies; do
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role \
            --role-name "$role_name" 2>/dev/null || {
            echo "Failed to delete IAM role: $role_name" >&2
        }
        
        unregister_resource "iam_roles" "$role_name"
    done
}

cleanup_iam_policies() {
    local policies=("$@")
    
    for policy_name in "${policies[@]}"; do
        echo "Deleting IAM policy: $policy_name"
        
        # Get policy ARN
        local policy_arn
        policy_arn=$(aws iam list-policies \
            --query "Policies[?PolicyName=='$policy_name'].Arn | [0]" \
            --output text 2>/dev/null)
        
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            aws iam delete-policy \
                --policy-arn "$policy_arn" 2>/dev/null || {
                echo "Failed to delete IAM policy: $policy_name" >&2
            }
        fi
        
        unregister_resource "iam_policies" "$policy_name"
    done
}

# =============================================================================
# STORAGE CLEANUP
# =============================================================================

cleanup_efs_filesystems() {
    local filesystems=("$@")
    
    for fs_id in "${filesystems[@]}"; do
        echo "Deleting EFS filesystem: $fs_id"
        
        # Delete mount targets first
        local mount_targets
        mount_targets=$(aws efs describe-mount-targets \
            --file-system-id "$fs_id" \
            --query 'MountTargets[*].MountTargetId' \
            --output text 2>/dev/null)
        
        for mt_id in $mount_targets; do
            echo "Deleting mount target: $mt_id"
            aws efs delete-mount-target \
                --mount-target-id "$mt_id" 2>/dev/null || true
        done
        
        # Wait for mount targets to be deleted
        if [ -n "$mount_targets" ]; then
            echo "Waiting for mount targets to be deleted..."
            sleep 30
        fi
        
        # Delete filesystem
        aws efs delete-file-system \
            --file-system-id "$fs_id" 2>/dev/null || {
            echo "Failed to delete EFS filesystem: $fs_id" >&2
        }
        
        unregister_resource "efs_filesystems" "$fs_id"
    done
}

cleanup_volumes() {
    local volumes=("$@")
    
    for volume_id in "${volumes[@]}"; do
        echo "Deleting volume: $volume_id"
        
        aws ec2 delete-volume \
            --volume-id "$volume_id" 2>/dev/null || {
            echo "Failed to delete volume: $volume_id" >&2
        }
        
        unregister_resource "volumes" "$volume_id"
    done
}

# =============================================================================
# KEY PAIR CLEANUP
# =============================================================================

cleanup_key_pairs() {
    local key_pairs=("$@")
    
    for key_name in "${key_pairs[@]}"; do
        echo "Deleting key pair: $key_name"
        
        aws ec2 delete-key-pair \
            --key-name "$key_name" 2>/dev/null || {
            echo "Failed to delete key pair: $key_name" >&2
        }
        
        unregister_resource "key_pairs" "$key_name"
    done
}

# =============================================================================
# TAG-BASED CLEANUP
# =============================================================================

cleanup_by_tags() {
    local stack_name="$1"
    
    echo "Performing tag-based cleanup for stack: $stack_name"
    
    # Find and terminate instances
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Stack,Values=$stack_name" \
                  "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    if [ -n "$instances" ]; then
        cleanup_instances $instances
    fi
    
    # Find and delete security groups
    local security_groups
    security_groups=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Stack,Values=$stack_name" \
        --query 'SecurityGroups[*].GroupId' \
        --output text)
    
    if [ -n "$security_groups" ]; then
        cleanup_security_groups $security_groups
    fi
    
    # Continue with other resources...
    echo "Tag-based cleanup complete"
}