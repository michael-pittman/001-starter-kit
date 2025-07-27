#!/bin/bash
# =============================================================================
# EFS Infrastructure Module
# Manages EFS file systems, mount targets, and access points
# =============================================================================

# Prevent multiple sourcing
[ -n "${_EFS_SH_LOADED:-}" ] && return 0
_EFS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# EFS FILE SYSTEM MANAGEMENT
# =============================================================================

# Create EFS file system with comprehensive configuration
create_efs_file_system() {
    local stack_name="${1:-$STACK_NAME}"
    local performance_mode="${2:-generalPurpose}"  # generalPurpose or maxIO
    local encryption_enabled="${3:-true}"
    local backup_enabled="${4:-true}"
    
    with_error_context "create_efs_file_system" \
        _create_efs_file_system_impl "$stack_name" "$performance_mode" "$encryption_enabled" "$backup_enabled"
}

_create_efs_file_system_impl() {
    local stack_name="$1"
    local performance_mode="$2"
    local encryption_enabled="$3"
    local backup_enabled="$4"
    
    echo "Creating EFS file system for stack: $stack_name" >&2
    
    # Check if EFS already exists for this stack
    local existing_efs
    existing_efs=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Stack' && Value=='$stack_name']].FileSystemId | [0]" \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [ -n "$existing_efs" ]; then
        echo "EFS file system already exists: $existing_efs" >&2
        echo "$existing_efs"
        return 0
    fi
    
    # Build creation parameters
    local creation_params="--performance-mode $performance_mode"
    
    if [ "$encryption_enabled" = "true" ]; then
        creation_params="$creation_params --encrypted"
    fi
    
    # Add lifecycle policy for cost optimization
    local lifecycle_policy='[{
        "TransitionToIA": "AFTER_30_DAYS",
        "TransitionToPrimaryStorageClass": "AFTER_1_ACCESS"
    }]'
    
    creation_params="$creation_params --lifecycle-policy '$lifecycle_policy'"
    
    # Create EFS file system
    local efs_id
    efs_id=$(eval "aws efs create-file-system \
        $creation_params \
        --tags $(tags_to_cli_format "$(generate_tags "$stack_name" '{"Service": "EFS"}')") \
        --query 'FileSystemId' \
        --output text") || {
        throw_error $ERROR_AWS_API "Failed to create EFS file system"
    }
    
    echo "EFS file system created: $efs_id" >&2
    
    # Wait for file system to be available
    echo "Waiting for EFS file system to be available..." >&2
    aws efs wait file-system-available --file-system-id "$efs_id" || {
        throw_error $ERROR_TIMEOUT "EFS file system did not become available"
    }
    
    # Enable backup if requested
    if [ "$backup_enabled" = "true" ]; then
        enable_efs_backup "$efs_id"
    fi
    
    # Register EFS file system
    register_resource "efs_filesystems" "$efs_id" \
        "{\"stack\": \"$stack_name\", \"performance_mode\": \"$performance_mode\", \"encrypted\": $encryption_enabled}"
    
    echo "$efs_id"
}

# Enable EFS backup policy
enable_efs_backup() {
    local efs_id="$1"
    
    echo "Enabling backup for EFS: $efs_id" >&2
    
    aws efs put-backup-policy \
        --file-system-id "$efs_id" \
        --backup-policy Status=ENABLED || {
        echo "WARNING: Failed to enable backup for EFS $efs_id" >&2
    }
}

# =============================================================================
# MOUNT TARGET MANAGEMENT
# =============================================================================

# Create mount targets across multiple subnets
create_efs_mount_targets() {
    local efs_id="$1"
    local subnets_json="$2"  # JSON array of subnet objects
    local security_group_id="$3"
    
    with_error_context "create_efs_mount_targets" \
        _create_efs_mount_targets_impl "$efs_id" "$subnets_json" "$security_group_id"
}

_create_efs_mount_targets_impl() {
    local efs_id="$1"
    local subnets_json="$2"
    local security_group_id="$3"
    
    echo "Creating EFS mount targets for: $efs_id" >&2
    
    # Check if mount targets already exist
    local existing_targets
    existing_targets=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query 'MountTargets[*].MountTargetId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_targets" ] && [ "$existing_targets" != "None" ]; then
        echo "Mount targets already exist for EFS: $efs_id" >&2
        echo "$existing_targets" | tr '\t' '\n' | head -1
        return 0
    fi
    
    # Create mount targets for each subnet
    local mount_target_ids=()\n    echo "$subnets_json" | jq -c '.[]' | while read -r subnet_obj; do\n        local subnet_id\n        subnet_id=$(echo "$subnet_obj" | jq -r '.id')\n        local az\n        az=$(echo "$subnet_obj" | jq -r '.az')\n        \n        echo "Creating mount target in subnet: $subnet_id ($az)" >&2\n        \n        local mount_target_id\n        mount_target_id=$(aws efs create-mount-target \\\n            --file-system-id "$efs_id" \\\n            --subnet-id "$subnet_id" \\\n            --security-groups "$security_group_id" \\\n            --query 'MountTargetId' \\\n            --output text) || {\n            echo "WARNING: Failed to create mount target in $subnet_id" >&2\n            continue\n        }\n        \n        # Register mount target\n        register_resource "efs_mount_targets" "$mount_target_id" \\\n            "{\"efs_id\": \"$efs_id\", \"subnet_id\": \"$subnet_id\", \"az\": \"$az\"}"\n        \n        mount_target_ids+=("$mount_target_id")\n        echo "Created mount target: $mount_target_id in $az" >&2\n    done\n    \n    # Wait for mount targets to be available\n    echo "Waiting for mount targets to be available..." >&2\n    for mount_target_id in "${mount_target_ids[@]}"; do\n        aws efs wait mount-target-available --mount-target-id "$mount_target_id" || {\n            echo "WARNING: Mount target $mount_target_id did not become available" >&2\n        }\n    done\n    \n    # Return first mount target ID\n    echo "${mount_target_ids[0]:-}"\n}

# Create mount target in specific subnet
create_efs_mount_target() {
    local efs_id="$1"
    local subnet_id="$2"
    local security_group_id="$3"
    
    echo "Creating EFS mount target: $efs_id in $subnet_id" >&2
    
    # Check if mount target already exists in this subnet
    local existing_target
    existing_target=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query "MountTargets[?SubnetId=='$subnet_id'].MountTargetId | [0]" \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [ -n "$existing_target" ]; then
        echo "Mount target already exists in subnet: $existing_target" >&2
        echo "$existing_target"
        return 0
    fi
    
    # Create mount target
    local mount_target_id
    mount_target_id=$(aws efs create-mount-target \
        --file-system-id "$efs_id" \
        --subnet-id "$subnet_id" \
        --security-groups "$security_group_id" \
        --query 'MountTargetId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create mount target"
    }
    
    # Wait for mount target to be available
    echo "Waiting for mount target to be available..." >&2
    aws efs wait mount-target-available --mount-target-id "$mount_target_id" || {
        throw_error $ERROR_TIMEOUT "Mount target did not become available"
    }
    
    # Register mount target
    register_resource "efs_mount_targets" "$mount_target_id" \
        "{\"efs_id\": \"$efs_id\", \"subnet_id\": \"$subnet_id\"}"
    
    echo "$mount_target_id"
}

# =============================================================================
# ACCESS POINT MANAGEMENT
# =============================================================================

# Create EFS access point for specific application
create_efs_access_point() {
    local efs_id="$1"
    local path="${2:-/}"
    local uid="${3:-1000}"
    local gid="${4:-1000}"
    local permissions="${5:-755}"
    local stack_name="${6:-$STACK_NAME}"
    
    with_error_context "create_efs_access_point" \
        _create_efs_access_point_impl "$efs_id" "$path" "$uid" "$gid" "$permissions" "$stack_name"
}

_create_efs_access_point_impl() {
    local efs_id="$1"
    local path="$2"
    local uid="$3"
    local gid="$4"
    local permissions="$5"
    local stack_name="$6"
    
    echo "Creating EFS access point: $path for $efs_id" >&2
    
    # Check if access point already exists
    local existing_ap
    existing_ap=$(aws efs describe-access-points \
        --file-system-id "$efs_id" \
        --query "AccessPoints[?RootDirectory.Path=='$path'].AccessPointId | [0]" \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [ -n "$existing_ap" ]; then
        echo "Access point already exists: $existing_ap" >&2
        echo "$existing_ap"
        return 0
    fi
    
    # Create access point configuration
    local access_point_config=$(cat <<EOF
{
    "Path": "$path",
    "CreationInfo": {
        "OwnerUid": $uid,
        "OwnerGid": $gid,
        "Permissions": "$permissions"
    }
}
EOF
)
    
    local posix_user_config=$(cat <<EOF
{
    "Uid": $uid,
    "Gid": $gid
}
EOF
)
    
    # Create access point
    local access_point_id
    access_point_id=$(aws efs create-access-point \
        --file-system-id "$efs_id" \
        --root-directory "$access_point_config" \
        --posix-user "$posix_user_config" \
        --tags "$(tags_to_cli_format "$(generate_tags "$stack_name" "{\"Path\": \"$path\"}")")" \
        --query 'AccessPointId' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create access point"
    }
    
    # Wait for access point to be available
    echo "Waiting for access point to be available..." >&2
    aws efs wait access-point-available --access-point-id "$access_point_id" || {
        throw_error $ERROR_TIMEOUT "Access point did not become available"
    }
    
    # Register access point
    register_resource "efs_access_points" "$access_point_id" \
        "{\"efs_id\": \"$efs_id\", \"path\": \"$path\", \"uid\": $uid, \"gid\": $gid}"
    
    echo "$access_point_id"
}

# =============================================================================
# EFS ORCHESTRATION
# =============================================================================

# Setup complete EFS infrastructure
setup_efs_infrastructure() {
    local stack_name="${1:-$STACK_NAME}"
    local subnets_json="$2"  # JSON array of subnet objects
    local security_group_id="$3"
    local performance_mode="${4:-generalPurpose}"
    local create_access_points="${5:-true}"
    
    echo "Setting up EFS infrastructure for: $stack_name" >&2
    
    # Create EFS file system
    local efs_id
    efs_id=$(create_efs_file_system "$stack_name" "$performance_mode" "true" "true") || return 1
    echo "EFS file system ready: $efs_id" >&2
    
    # Create mount targets
    local mount_target_id
    mount_target_id=$(create_efs_mount_targets "$efs_id" "$subnets_json" "$security_group_id") || return 1
    echo "Mount targets created" >&2
    
    # Create access points for different applications
    local access_points="[]"
    if [ "$create_access_points" = "true" ]; then
        echo "Creating application access points..." >&2
        
        # Create access points for different services
        local n8n_ap
        n8n_ap=$(create_efs_access_point "$efs_id" "/n8n" "1000" "1000" "755" "$stack_name") || true
        
        local ollama_ap
        ollama_ap=$(create_efs_access_point "$efs_id" "/ollama" "1000" "1000" "755" "$stack_name") || true
        
        local qdrant_ap
        qdrant_ap=$(create_efs_access_point "$efs_id" "/qdrant" "1000" "1000" "755" "$stack_name") || true
        
        local shared_ap
        shared_ap=$(create_efs_access_point "$efs_id" "/shared" "1000" "1000" "755" "$stack_name") || true
        
        # Build access points JSON
        access_points=$(cat <<EOF
[
    {"service": "n8n", "access_point_id": "$n8n_ap", "path": "/n8n"},
    {"service": "ollama", "access_point_id": "$ollama_ap", "path": "/ollama"},
    {"service": "qdrant", "access_point_id": "$qdrant_ap", "path": "/qdrant"},
    {"service": "shared", "access_point_id": "$shared_ap", "path": "/shared"}
]
EOF
)
    fi
    
    # Get EFS DNS name
    local efs_dns
    efs_dns=$(get_efs_dns_name "$efs_id")
    
    # Return EFS information
    cat <<EOF
{
    "efs_id": "$efs_id",
    "efs_dns": "$efs_dns",
    "mount_target_id": "$mount_target_id",
    "access_points": $access_points
}
EOF
}

# =============================================================================
# EFS UTILITIES
# =============================================================================

# Get EFS DNS name
get_efs_dns_name() {
    local efs_id="$1"
    local region="${AWS_REGION:-us-east-1}"
    
    echo "${efs_id}.efs.${region}.amazonaws.com"
}

# Get EFS file system info
get_efs_info() {
    local efs_id="$1"
    
    aws efs describe-file-systems \
        --file-system-id "$efs_id" \
        --query 'FileSystems[0]' \
        --output json
}

# Get mount targets for EFS
get_efs_mount_targets() {
    local efs_id="$1"
    
    aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query 'MountTargets[*].{Id:MountTargetId,SubnetId:SubnetId,State:LifeCycleState}' \
        --output json
}

# Generate mount commands for different systems
generate_mount_commands() {
    local efs_id="$1"
    local mount_point="${2:-/mnt/efs}"
    local region="${AWS_REGION:-us-east-1}"
    local efs_dns
    efs_dns=$(get_efs_dns_name "$efs_id")
    
    cat <<EOF
# EFS Mount Commands for $efs_id

## Traditional NFS Mount
sudo mkdir -p $mount_point
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 $efs_dns:/ $mount_point

## EFS Utils Mount (recommended)
sudo mkdir -p $mount_point
sudo mount -t efs $efs_id $mount_point

## Docker Volume Mount
docker run -v $mount_point:/data your-container

## Docker Compose (add to volumes section)
volumes:
  efs_volume:
    driver: local
    driver_opts:
      type: nfs4
      o: addr=$efs_dns,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2
      device: :/

## Systemd Auto-mount (/etc/fstab)
$efs_dns:/ $mount_point efs defaults,_netdev 0 0

EOF
}

# =============================================================================
# PERFORMANCE AND MONITORING
# =============================================================================

# Setup EFS performance monitoring
setup_efs_monitoring() {
    local efs_id="$1"
    local stack_name="${2:-$STACK_NAME}"
    
    echo "Setting up EFS monitoring for: $efs_id" >&2
    
    # Create CloudWatch dashboard
    create_efs_dashboard "$efs_id" "$stack_name"
    
    # Create CloudWatch alarms
    create_efs_alarms "$efs_id" "$stack_name"
}

# Create EFS CloudWatch dashboard
create_efs_dashboard() {
    local efs_id="$1"
    local stack_name="$2"
    local dashboard_name="${stack_name}-efs-dashboard"
    
    local dashboard_body=$(cat <<EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EFS", "TotalIOBytes", "FileSystemId", "$efs_id"],
                    [".", "DataReadIOBytes", ".", "."],
                    [".", "DataWriteIOBytes", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION:-us-east-1}",
                "title": "EFS IO Bytes"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EFS", "TotalIOTime", "FileSystemId", "$efs_id"],
                    [".", "DataReadIOTime", ".", "."],
                    [".", "DataWriteIOTime", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION:-us-east-1}",
                "title": "EFS IO Time"
            }
        }
    ]
}
EOF
)
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body "$dashboard_body" || {
        echo "WARNING: Failed to create EFS dashboard" >&2
    }
}

# Create EFS CloudWatch alarms
create_efs_alarms() {
    local efs_id="$1"
    local stack_name="$2"
    
    # High IO alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-efs-high-io" \
        --alarm-description "EFS high IO detected" \
        --metric-name TotalIOBytes \
        --namespace AWS/EFS \
        --statistic Sum \
        --period 300 \
        --threshold 1000000000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FileSystemId,Value="$efs_id" || true
}

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

# Comprehensive EFS cleanup
cleanup_efs_comprehensive() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Starting comprehensive EFS cleanup for: $stack_name" >&2
    
    # Get all EFS file systems for this stack
    local efs_ids
    efs_ids=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Stack' && Value=='$stack_name']].FileSystemId" \
        --output text 2>/dev/null || echo "")
    
    for efs_id in $efs_ids; do
        if [ -n "$efs_id" ] && [ "$efs_id" != "None" ]; then
            cleanup_efs_file_system "$efs_id"
        fi
    done
    
    echo "EFS cleanup completed" >&2
}

# Cleanup individual EFS file system
cleanup_efs_file_system() {
    local efs_id="$1"
    
    echo "Cleaning up EFS file system: $efs_id" >&2
    
    # Delete access points
    echo "Deleting access points..." >&2
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
    
    # Delete mount targets
    echo "Deleting mount targets..." >&2
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
    
    # Delete file system
    echo "Deleting EFS file system: $efs_id" >&2
    aws efs delete-file-system --file-system-id "$efs_id" || true
    
    echo "EFS file system deletion initiated: $efs_id" >&2
}