#!/bin/bash
# =============================================================================
# EFS Legacy Compatibility Functions
# Extracted legacy functions from the monolithic deployment scripts
# =============================================================================

# Prevent multiple sourcing
[ -n "${_EFS_LEGACY_SH_LOADED:-}" ] && return 0
_EFS_LEGACY_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# LEGACY COMPATIBILITY FUNCTIONS (MIGRATED FROM MONOLITH)
# =============================================================================

# Create shared EFS (legacy compatibility function)
create_shared_efs() {
    local stack_name="$1"
    local performance_mode="${2:-generalPurpose}"
    
    if [ -z "$stack_name" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "create_shared_efs requires stack_name parameter"
    fi

    echo "Creating/checking EFS: ${stack_name}-efs" >&2

    # Check if EFS exists
    local efs_id
    efs_id=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='${stack_name}-efs']].FileSystemId" \
        --output text \
        --region "${AWS_REGION:-us-east-1}" 2>/dev/null)

    if [ -z "$efs_id" ] || [ "$efs_id" = "None" ]; then
        echo "Creating new EFS..." >&2
        efs_id=$(aws efs create-file-system \
            --performance-mode "$performance_mode" \
            --throughput-mode provisioned \
            --provisioned-throughput-in-mibps 100 \
            --tags Key=Name,Value="${stack_name}-efs" Key=Stack,Value="$stack_name" \
            --query 'FileSystemId' \
            --output text \
            --region "${AWS_REGION:-us-east-1}") || {
            throw_error $ERROR_AWS_API "Failed to create EFS file system"
        }
        
        echo "EFS created: ${stack_name}-efs ($efs_id)" >&2
    else
        echo "EFS ${stack_name}-efs already exists: $efs_id" >&2
    fi

    # Register the resource
    register_resource "efs_file_systems" "$efs_id" "{\"name\": \"${stack_name}-efs\", \"stack\": \"$stack_name\"}"
    
    echo "$efs_id"
    return 0
}

# Create EFS mount target for availability zone (legacy compatibility function)
create_efs_mount_target_for_az() {
    local efs_id="$1"
    local subnet_id="$2"
    local security_group_id="$3"
    
    if [ -z "$efs_id" ] || [ -z "$subnet_id" ] || [ -z "$security_group_id" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "create_efs_mount_target_for_az requires efs_id, subnet_id, and security_group_id parameters"
    fi

    echo "Creating EFS mount target for subnet: $subnet_id" >&2

    # Check if mount target exists
    local mount_target_id
    mount_target_id=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query "MountTargets[?SubnetId=='$subnet_id'].MountTargetId" \
        --output text \
        --region "${AWS_REGION:-us-east-1}" 2>/dev/null)

    if [ -z "$mount_target_id" ] || [ "$mount_target_id" = "None" ]; then
        mount_target_id=$(aws efs create-mount-target \
            --file-system-id "$efs_id" \
            --subnet-id "$subnet_id" \
            --security-groups "$security_group_id" \
            --region "${AWS_REGION:-us-east-1}" \
            --query 'MountTargetId' \
            --output text 2>/dev/null) || {
            throw_error $ERROR_AWS_API "Failed to create EFS mount target"
        }
        
        echo "EFS mount target created for subnet: $subnet_id" >&2
    else
        echo "EFS mount target already exists for subnet: $subnet_id" >&2
    fi

    # Register the resource
    register_resource "efs_mount_targets" "$mount_target_id" "{\"efs_id\": \"$efs_id\", \"subnet_id\": \"$subnet_id\"}"
    
    return 0
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup EFS resources for a stack
cleanup_efs_resources() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up EFS resources for: $stack_name" >&2
    
    # Get EFS file systems for this stack
    local efs_ids
    efs_ids=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Stack' && Value=='$stack_name']].FileSystemId" \
        --output text 2>/dev/null || echo "")
    
    for efs_id in $efs_ids; do
        if [ -n "$efs_id" ] && [ "$efs_id" != "None" ]; then
            cleanup_efs_file_system "$efs_id"
        fi
    done
}

# Cleanup individual EFS file system
cleanup_efs_file_system() {
    local efs_id="$1"
    
    echo "Cleaning up EFS file system: $efs_id" >&2
    
    # Delete mount targets first
    local mount_targets
    mount_targets=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query 'MountTargets[*].MountTargetId' \
        --output text 2>/dev/null || echo "")
    
    for mt_id in $mount_targets; do
        if [ -n "$mt_id" ] && [ "$mt_id" != "None" ]; then
            aws efs delete-mount-target --mount-target-id "$mt_id" || true
            echo "Deleted mount target: $mt_id" >&2
        fi
    done
    
    # Wait for mount targets to be deleted
    if [ -n "$mount_targets" ] && [ "$mount_targets" != "None" ]; then
        echo "Waiting for mount targets to be deleted..." >&2
        sleep 30
    fi
    
    # Delete access points
    local access_points
    access_points=$(aws efs describe-access-points \
        --file-system-id "$efs_id" \
        --query 'AccessPoints[*].AccessPointId' \
        --output text 2>/dev/null || echo "")
    
    for ap_id in $access_points; do
        if [ -n "$ap_id" ] && [ "$ap_id" != "None" ]; then
            aws efs delete-access-point --access-point-id "$ap_id" || true
            echo "Deleted access point: $ap_id" >&2
        fi
    done
    
    # Delete file system
    aws efs delete-file-system --file-system-id "$efs_id" || true
    echo "Deleted EFS file system: $efs_id" >&2
}