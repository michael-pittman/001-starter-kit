#!/bin/bash
#
# Maintenance Cleanup Operations Module
# Contains all cleanup operations extracted from maintenance scripts
#

# =============================================================================
# LOG CLEANUP OPERATIONS
# =============================================================================

# Cleanup log files
cleanup_logs() {
    log_maintenance "INFO" "Cleaning up log files..."
    increment_counter "processed"
    
    local cleaned_count=0
    local saved_space=0
    
    # Define log locations
    local log_locations=(
        "/var/log/GeuseMaker*.log"
        "/var/log/docker/*.log"
        "/home/ubuntu/GeuseMaker/logs/*.log"
        "${MAINTENANCE_PROJECT_ROOT}/logs/*.log"
    )
    
    for location in "${log_locations[@]}"; do
        # Find log files older than 7 days
        local old_logs=$(find_old_files "$(dirname "$location")" 7 "$(basename "$location")")
        
        for log_file in $old_logs; do
            if [[ -f "$log_file" ]]; then
                local file_size=$(get_directory_size "$log_file")
                
                if safe_delete_file "$log_file" "old log file"; then
                    ((cleaned_count++))
                    ((saved_space += file_size))
                fi
            fi
        done
        
        # Truncate large active log files
        for log_file in $location; do
            if [[ -f "$log_file" ]]; then
                local size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)
                if [[ $size_mb -gt 100 ]]; then
                    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                        log_maintenance "INFO" "[DRY RUN] Would truncate large log: $log_file (${size_mb}MB)"
                    else
                        # Keep last 1000 lines
                        tail -n 1000 "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"
                        log_maintenance "SUCCESS" "Truncated large log: $log_file"
                        ((cleaned_count++))
                    fi
                fi
            fi
        done
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Cleaned $cleaned_count log files, freed $(numfmt --to=iec $saved_space 2>/dev/null || echo "${saved_space} bytes")"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "No log files needed cleaning"
        increment_counter "skipped"
    fi
}

# =============================================================================
# DOCKER CLEANUP OPERATIONS
# =============================================================================

# Cleanup Docker resources
cleanup_docker() {
    log_maintenance "INFO" "Cleaning up Docker resources..."
    increment_counter "processed"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_maintenance "WARNING" "Docker not installed, skipping"
        increment_counter "skipped"
        return 0
    fi
    
    # Check if it's safe to clean Docker
    if ! is_operation_safe "cleanup_docker"; then
        log_maintenance "WARNING" "Critical services running, skipping aggressive cleanup"
        # Do only safe cleanup
        cleanup_docker_safe
        return 0
    fi
    
    # Get space before cleanup
    local before_space=$(calculate_docker_usage | grep -oE '[0-9]+' | awk '{sum+=$1} END {print sum}')
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would clean Docker resources"
        show_docker_cleanup_preview
        return 0
    fi
    
    # Stop all containers
    local containers=$(docker ps -aq)
    if [[ -n "$containers" ]]; then
        log_maintenance "INFO" "Stopping all containers..."
        docker stop $containers >/dev/null 2>&1 || true
    fi
    
    # Remove stopped containers
    local stopped=$(docker ps -aq -f status=exited)
    if [[ -n "$stopped" ]]; then
        docker rm $stopped >/dev/null 2>&1 || true
        log_maintenance "SUCCESS" "Removed stopped containers"
    fi
    
    # Remove unused images
    docker image prune -af >/dev/null 2>&1 || true
    
    # Remove unused volumes
    docker volume prune -f >/dev/null 2>&1 || true
    
    # Remove unused networks
    docker network prune -f >/dev/null 2>&1 || true
    
    # System prune for everything else
    docker system prune -af --volumes >/dev/null 2>&1 || true
    
    # Get space after cleanup
    local after_space=$(calculate_docker_usage | grep -oE '[0-9]+' | awk '{sum+=$1} END {print sum}')
    local freed_space=$((before_space - after_space))
    
    log_maintenance "SUCCESS" "Docker cleanup completed, freed $(numfmt --to=iec $freed_space 2>/dev/null || echo "${freed_space} bytes")"
    increment_counter "fixed"
}

# Safe Docker cleanup (preserves running containers)
cleanup_docker_safe() {
    log_maintenance "INFO" "Performing safe Docker cleanup..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would perform safe Docker cleanup"
        return 0
    fi
    
    # Remove only stopped containers
    docker container prune -f >/dev/null 2>&1 || true
    
    # Remove dangling images only
    docker image prune -f >/dev/null 2>&1 || true
    
    # Remove unused networks (safe)
    docker network prune -f >/dev/null 2>&1 || true
    
    log_maintenance "SUCCESS" "Safe Docker cleanup completed"
}

# Show Docker cleanup preview
show_docker_cleanup_preview() {
    echo "Docker resources that would be cleaned:"
    
    # Stopped containers
    local stopped_count=$(docker ps -aq -f status=exited | wc -l)
    echo "  - Stopped containers: $stopped_count"
    
    # Dangling images
    local dangling_count=$(docker images -f "dangling=true" -q | wc -l)
    echo "  - Dangling images: $dangling_count"
    
    # All images
    local total_images=$(docker images -q | wc -l)
    echo "  - Total images: $total_images"
    
    # Volumes
    local volume_count=$(docker volume ls -q | wc -l)
    echo "  - Volumes: $volume_count"
    
    # Networks
    local network_count=$(docker network ls --format "{{.Name}}" | grep -v -E '^(bridge|host|none)$' | wc -l)
    echo "  - Custom networks: $network_count"
}

# =============================================================================
# TEMPORARY FILES CLEANUP
# =============================================================================

# Cleanup temporary files
cleanup_temp() {
    log_maintenance "INFO" "Cleaning up temporary files..."
    increment_counter "processed"
    
    local cleaned_count=0
    local saved_space=0
    
    # Define temporary file locations
    local temp_locations=(
        "/tmp/*"
        "/var/tmp/*"
        "${MAINTENANCE_PROJECT_ROOT}/tmp/*"
        "${MAINTENANCE_PROJECT_ROOT}/.tmp/*"
        "${HOME}/.cache/*"
    )
    
    # Define patterns to clean
    local temp_patterns=(
        "*.tmp"
        "*.temp"
        "*.swp"
        "*.swo"
        "*~"
        "core.*"
        "*.pid"
        "*.lock"
    )
    
    for location in "${temp_locations[@]}"; do
        local base_dir=$(dirname "$location")
        if [[ -d "$base_dir" ]]; then
            # Clean files older than 1 day
            local old_files=$(find_old_files "$base_dir" 1 "*")
            
            for file in $old_files; do
                # Skip if it's a system file
                if [[ "$file" == "/tmp/"* ]] && [[ "$file" == *"systemd"* ]]; then
                    continue
                fi
                
                local file_size=$(get_directory_size "$file")
                
                if safe_delete_file "$file" "old temporary file"; then
                    ((cleaned_count++))
                    ((saved_space += file_size))
                fi
            done
        fi
    done
    
    # Clean specific patterns
    for pattern in "${temp_patterns[@]}"; do
        while IFS= read -r file; do
            local file_size=$(get_directory_size "$file")
            
            if safe_delete_file "$file" "temporary file ($pattern)"; then
                ((cleaned_count++))
                ((saved_space += file_size))
            fi
        done < <(find "${MAINTENANCE_PROJECT_ROOT}" -name "$pattern" -type f 2>/dev/null || true)
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Cleaned $cleaned_count temporary files, freed $(numfmt --to=iec $saved_space 2>/dev/null || echo "${saved_space} bytes")"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "No temporary files needed cleaning"
        increment_counter "skipped"
    fi
}

# =============================================================================
# AWS CLEANUP OPERATIONS
# =============================================================================

# Cleanup AWS resources
cleanup_aws() {
    log_maintenance "INFO" "Cleaning up AWS resources..."
    increment_counter "processed"
    
    if [[ -z "$MAINTENANCE_STACK_NAME" ]]; then
        log_maintenance "WARNING" "Stack name required for AWS cleanup"
        increment_counter "skipped"
        return 1
    fi
    
    local resources_cleaned=0
    
    # Cleanup EC2 instances
    if cleanup_ec2_instances; then
        ((resources_cleaned++))
    fi
    
    # Cleanup EFS resources
    if cleanup_efs_resources; then
        ((resources_cleaned++))
    fi
    
    # Cleanup network resources
    if cleanup_network_resources; then
        ((resources_cleaned++))
    fi
    
    # Cleanup IAM resources
    if cleanup_iam_resources; then
        ((resources_cleaned++))
    fi
    
    # Cleanup monitoring resources
    if cleanup_monitoring_resources; then
        ((resources_cleaned++))
    fi
    
    # Cleanup storage resources
    if cleanup_storage_resources; then
        ((resources_cleaned++))
    fi
    
    if [[ $resources_cleaned -gt 0 ]]; then
        log_maintenance "SUCCESS" "Cleaned $resources_cleaned AWS resource types"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "No AWS resources needed cleaning"
        increment_counter "skipped"
    fi
}

# Cleanup EC2 instances
cleanup_ec2_instances() {
    log_maintenance "INFO" "Cleaning up EC2 instances for stack: $MAINTENANCE_STACK_NAME"
    
    # Find instances by stack name
    local instance_ids
    instance_ids=$(safe_aws_command \
        "aws ec2 describe-instances --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME Name=instance-state-name,Values=running,stopped,stopping --query 'Reservations[].Instances[].InstanceId' --output text" \
        "Find instances")
    
    if [[ -n "$instance_ids" ]] && [[ "$instance_ids" != "None" ]]; then
        log_maintenance "INFO" "Found instances to cleanup: $instance_ids"
        
        for instance_id in $instance_ids; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would terminate instance: $instance_id"
            else
                if safe_aws_command \
                    "aws ec2 terminate-instances --region $MAINTENANCE_AWS_REGION --instance-ids $instance_id" \
                    "Terminate instance $instance_id"; then
                    log_maintenance "SUCCESS" "Terminated instance: $instance_id"
                else
                    log_maintenance "ERROR" "Failed to terminate instance: $instance_id"
                fi
            fi
        done
        
        # Cleanup spot instance requests
        cleanup_spot_requests
        
        return 0
    else
        log_maintenance "INFO" "No instances found for cleanup"
        return 1
    fi
}

# Cleanup spot instance requests
cleanup_spot_requests() {
    local spot_request_ids
    spot_request_ids=$(safe_aws_command \
        "aws ec2 describe-spot-instance-requests --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME Name=state,Values=open,active --query 'SpotInstanceRequests[].SpotInstanceRequestId' --output text" \
        "Find spot requests")
    
    if [[ -n "$spot_request_ids" ]] && [[ "$spot_request_ids" != "None" ]]; then
        for request_id in $spot_request_ids; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would cancel spot request: $request_id"
            else
                if safe_aws_command \
                    "aws ec2 cancel-spot-instance-requests --region $MAINTENANCE_AWS_REGION --spot-instance-request-ids $request_id" \
                    "Cancel spot request $request_id"; then
                    log_maintenance "SUCCESS" "Cancelled spot request: $request_id"
                fi
            fi
        done
    fi
}

# Cleanup EFS resources
cleanup_efs_resources() {
    log_maintenance "INFO" "Cleaning up EFS resources..."
    
    # Find EFS file systems by stack name
    local efs_ids
    efs_ids=$(safe_aws_command \
        "aws efs describe-file-systems --region $MAINTENANCE_AWS_REGION --query \"FileSystems[?Tags[?Key=='StackName' && Value=='$MAINTENANCE_STACK_NAME']].FileSystemId\" --output text" \
        "Find EFS file systems")
    
    if [[ -n "$efs_ids" ]] && [[ "$efs_ids" != "None" ]]; then
        for efs_id in $efs_ids; do
            cleanup_single_efs "$efs_id"
        done
        return 0
    else
        log_maintenance "INFO" "No EFS file systems found for cleanup"
        return 1
    fi
}

# Cleanup single EFS file system
cleanup_single_efs() {
    local efs_id="$1"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would cleanup EFS file system: $efs_id"
        return 0
    fi
    
    # Get mount targets
    local mount_target_ids
    mount_target_ids=$(safe_aws_command \
        "aws efs describe-mount-targets --region $MAINTENANCE_AWS_REGION --file-system-id $efs_id --query 'MountTargets[].MountTargetId' --output text" \
        "Get mount targets")
    
    # Delete mount targets first
    if [[ -n "$mount_target_ids" ]] && [[ "$mount_target_ids" != "None" ]]; then
        for mount_target_id in $mount_target_ids; do
            if safe_aws_command \
                "aws efs delete-mount-target --region $MAINTENANCE_AWS_REGION --mount-target-id $mount_target_id" \
                "Delete mount target $mount_target_id"; then
                log_maintenance "SUCCESS" "Deleted mount target: $mount_target_id"
            fi
        done
        
        # Wait a bit for mount targets to be deleted
        sleep 10
    fi
    
    # Delete the file system
    if safe_aws_command \
        "aws efs delete-file-system --region $MAINTENANCE_AWS_REGION --file-system-id $efs_id" \
        "Delete EFS $efs_id"; then
        log_maintenance "SUCCESS" "Deleted EFS file system: $efs_id"
    fi
}

# Cleanup network resources
cleanup_network_resources() {
    log_maintenance "INFO" "Cleaning up network resources..."
    
    local cleaned=false
    
    # Cleanup security groups
    if cleanup_security_groups; then
        cleaned=true
    fi
    
    # Cleanup load balancers
    if cleanup_load_balancers; then
        cleaned=true
    fi
    
    # Cleanup CloudFront distributions
    if cleanup_cloudfront_distributions; then
        cleaned=true
    fi
    
    [[ "$cleaned" == true ]]
}

# Cleanup security groups
cleanup_security_groups() {
    local security_group_ids
    security_group_ids=$(safe_aws_command \
        "aws ec2 describe-security-groups --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME --query 'SecurityGroups[].GroupId' --output text" \
        "Find security groups")
    
    if [[ -n "$security_group_ids" ]] && [[ "$security_group_ids" != "None" ]]; then
        for sg_id in $security_group_ids; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete security group: $sg_id"
            else
                if safe_aws_command \
                    "aws ec2 delete-security-group --region $MAINTENANCE_AWS_REGION --group-id $sg_id" \
                    "Delete security group $sg_id"; then
                    log_maintenance "SUCCESS" "Deleted security group: $sg_id"
                fi
            fi
        done
        return 0
    fi
    return 1
}

# Cleanup load balancers
cleanup_load_balancers() {
    local load_balancer_arns
    load_balancer_arns=$(safe_aws_command \
        "aws elbv2 describe-load-balancers --region $MAINTENANCE_AWS_REGION --query \"LoadBalancers[?contains(LoadBalancerName, '$MAINTENANCE_STACK_NAME')].LoadBalancerArn\" --output text" \
        "Find load balancers")
    
    if [[ -n "$load_balancer_arns" ]] && [[ "$load_balancer_arns" != "None" ]]; then
        for lb_arn in $load_balancer_arns; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete load balancer: $lb_arn"
            else
                if safe_aws_command \
                    "aws elbv2 delete-load-balancer --region $MAINTENANCE_AWS_REGION --load-balancer-arn $lb_arn" \
                    "Delete load balancer"; then
                    log_maintenance "SUCCESS" "Deleted load balancer: $lb_arn"
                fi
            fi
        done
        return 0
    fi
    return 1
}

# Cleanup CloudFront distributions
cleanup_cloudfront_distributions() {
    local distribution_ids
    distribution_ids=$(safe_aws_command \
        "aws cloudfront list-distributions --query \"DistributionList.Items[?Comment=='$MAINTENANCE_STACK_NAME'].Id\" --output text" \
        "Find CloudFront distributions")
    
    if [[ -n "$distribution_ids" ]] && [[ "$distribution_ids" != "None" ]]; then
        for dist_id in $distribution_ids; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete CloudFront distribution: $dist_id"
            else
                # Note: CloudFront deletion requires disabling first
                log_maintenance "WARNING" "CloudFront distribution $dist_id needs manual deletion"
            fi
        done
        return 0
    fi
    return 1
}

# Cleanup IAM resources
cleanup_iam_resources() {
    log_maintenance "INFO" "Cleaning up IAM resources..."
    
    local role_name="${MAINTENANCE_STACK_NAME}-role"
    local profile_name="${MAINTENANCE_STACK_NAME}-instance-profile"
    
    # Clean alternative naming patterns
    if [[ "${MAINTENANCE_STACK_NAME}" =~ ^[0-9] ]]; then
        local clean_name=$(echo "${MAINTENANCE_STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    fi
    
    # Cleanup instance profile
    if safe_aws_command \
        "aws iam get-instance-profile --instance-profile-name $profile_name" \
        "Check instance profile" >/dev/null; then
        
        if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
            log_maintenance "INFO" "[DRY RUN] Would delete instance profile: $profile_name"
        else
            # Remove role from instance profile
            safe_aws_command \
                "aws iam remove-role-from-instance-profile --instance-profile-name $profile_name --role-name $role_name" \
                "Remove role from instance profile" || true
            
            # Delete instance profile
            if safe_aws_command \
                "aws iam delete-instance-profile --instance-profile-name $profile_name" \
                "Delete instance profile"; then
                log_maintenance "SUCCESS" "Deleted instance profile: $profile_name"
            fi
        fi
    fi
    
    # Cleanup IAM role
    if safe_aws_command \
        "aws iam get-role --role-name $role_name" \
        "Check IAM role" >/dev/null; then
        
        if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
            log_maintenance "INFO" "[DRY RUN] Would delete IAM role: $role_name"
        else
            # Delete inline policies
            local inline_policies
            inline_policies=$(safe_aws_command \
                "aws iam list-role-policies --role-name $role_name --query 'PolicyNames[]' --output text" \
                "List inline policies")
            
            for policy_name in $inline_policies; do
                if [[ -n "$policy_name" ]] && [[ "$policy_name" != "None" ]]; then
                    safe_aws_command \
                        "aws iam delete-role-policy --role-name $role_name --policy-name $policy_name" \
                        "Delete inline policy $policy_name" || true
                fi
            done
            
            # Detach managed policies
            local managed_policies
            managed_policies=$(safe_aws_command \
                "aws iam list-attached-role-policies --role-name $role_name --query 'AttachedPolicies[].PolicyArn' --output text" \
                "List attached policies")
            
            for policy_arn in $managed_policies; do
                if [[ -n "$policy_arn" ]] && [[ "$policy_arn" != "None" ]]; then
                    safe_aws_command \
                        "aws iam detach-role-policy --role-name $role_name --policy-arn $policy_arn" \
                        "Detach policy" || true
                fi
            done
            
            # Delete the role
            if safe_aws_command \
                "aws iam delete-role --role-name $role_name" \
                "Delete IAM role"; then
                log_maintenance "SUCCESS" "Deleted IAM role: $role_name"
            fi
        fi
        
        return 0
    fi
    
    return 1
}

# Cleanup monitoring resources
cleanup_monitoring_resources() {
    log_maintenance "INFO" "Cleaning up monitoring resources..."
    
    local cleaned=false
    
    # Cleanup CloudWatch alarms
    local alarm_names
    alarm_names=$(safe_aws_command \
        "aws cloudwatch describe-alarms --region $MAINTENANCE_AWS_REGION --query \"MetricAlarms[?contains(AlarmName, '$MAINTENANCE_STACK_NAME')].AlarmName\" --output text" \
        "Find CloudWatch alarms")
    
    if [[ -n "$alarm_names" ]] && [[ "$alarm_names" != "None" ]]; then
        for alarm_name in $alarm_names; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete alarm: $alarm_name"
            else
                if safe_aws_command \
                    "aws cloudwatch delete-alarms --region $MAINTENANCE_AWS_REGION --alarm-names $alarm_name" \
                    "Delete alarm $alarm_name"; then
                    log_maintenance "SUCCESS" "Deleted CloudWatch alarm: $alarm_name"
                    cleaned=true
                fi
            fi
        done
    fi
    
    # Cleanup CloudWatch log groups
    local log_group_names
    log_group_names=$(safe_aws_command \
        "aws logs describe-log-groups --region $MAINTENANCE_AWS_REGION --query \"logGroups[?contains(logGroupName, '$MAINTENANCE_STACK_NAME')].logGroupName\" --output text" \
        "Find log groups")
    
    if [[ -n "$log_group_names" ]] && [[ "$log_group_names" != "None" ]]; then
        for log_group_name in $log_group_names; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete log group: $log_group_name"
            else
                if safe_aws_command \
                    "aws logs delete-log-group --region $MAINTENANCE_AWS_REGION --log-group-name $log_group_name" \
                    "Delete log group"; then
                    log_maintenance "SUCCESS" "Deleted log group: $log_group_name"
                    cleaned=true
                fi
            fi
        done
    fi
    
    [[ "$cleaned" == true ]]
}

# Cleanup storage resources
cleanup_storage_resources() {
    log_maintenance "INFO" "Cleaning up storage resources..."
    
    local cleaned=false
    
    # Cleanup EBS volumes
    local volume_ids
    volume_ids=$(safe_aws_command \
        "aws ec2 describe-volumes --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME Name=status,Values=available --query 'Volumes[].VolumeId' --output text" \
        "Find EBS volumes")
    
    if [[ -n "$volume_ids" ]] && [[ "$volume_ids" != "None" ]]; then
        for volume_id in $volume_ids; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete volume: $volume_id"
            else
                if safe_aws_command \
                    "aws ec2 delete-volume --region $MAINTENANCE_AWS_REGION --volume-id $volume_id" \
                    "Delete volume $volume_id"; then
                    log_maintenance "SUCCESS" "Deleted EBS volume: $volume_id"
                    cleaned=true
                fi
            fi
        done
    fi
    
    # Cleanup snapshots
    local snapshot_ids
    snapshot_ids=$(safe_aws_command \
        "aws ec2 describe-snapshots --region $MAINTENANCE_AWS_REGION --owner-ids self --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME --query 'Snapshots[].SnapshotId' --output text" \
        "Find snapshots")
    
    if [[ -n "$snapshot_ids" ]] && [[ "$snapshot_ids" != "None" ]]; then
        for snapshot_id in $snapshot_ids; do
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would delete snapshot: $snapshot_id"
            else
                if safe_aws_command \
                    "aws ec2 delete-snapshot --region $MAINTENANCE_AWS_REGION --snapshot-id $snapshot_id" \
                    "Delete snapshot $snapshot_id"; then
                    log_maintenance "SUCCESS" "Deleted snapshot: $snapshot_id"
                    cleaned=true
                fi
            fi
        done
    fi
    
    [[ "$cleaned" == true ]]
}

# =============================================================================
# BACKUP CLEANUP OPERATIONS
# =============================================================================

# Cleanup old backups
cleanup_backups() {
    log_maintenance "INFO" "Cleaning up old backup files..."
    increment_counter "processed"
    
    local days_to_keep="${MAINTENANCE_BACKUP_RETENTION_DAYS:-7}"
    local backup_dir="${MAINTENANCE_BACKUP_DIR}"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_maintenance "INFO" "No backup directory found"
        increment_counter "skipped"
        return 0
    fi
    
    # Find old backup directories
    local old_backups=$(find_old_files "$backup_dir" "$days_to_keep" "*")
    local cleaned_count=0
    local saved_space=0
    
    for backup in $old_backups; do
        if [[ -d "$backup" ]] || [[ -f "$backup" ]]; then
            local backup_size=$(get_directory_size "$backup")
            
            if safe_delete_file "$backup" "old backup (>$days_to_keep days)"; then
                ((cleaned_count++))
                ((saved_space += backup_size))
            fi
        fi
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Cleaned $cleaned_count old backups, freed $(numfmt --to=iec $saved_space 2>/dev/null || echo "${saved_space} bytes")"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "No old backups found"
        increment_counter "skipped"
    fi
}

# =============================================================================
# CODEBASE CLEANUP OPERATIONS
# =============================================================================

# Cleanup codebase files
cleanup_codebase() {
    log_maintenance "INFO" "Cleaning up codebase files..."
    increment_counter "processed"
    
    local removed_count=0
    
    # Cleanup backup files
    log_maintenance "INFO" "Cleaning up backup files..."
    while IFS= read -r file; do
        if safe_delete_file "$file" "backup file"; then
            ((removed_count++))
        fi
    done < <(find "$MAINTENANCE_PROJECT_ROOT" \
        -name "*.backup" -o \
        -name "*.backup-*" -o \
        -name "*.bak" -o \
        -name "*~" \
        -type f 2>/dev/null || true)
    
    # Cleanup system files
    log_maintenance "INFO" "Cleaning up system files..."
    while IFS= read -r file; do
        if safe_delete_file "$file" "system file"; then
            ((removed_count++))
        fi
    done < <(find "$MAINTENANCE_PROJECT_ROOT" \
        -name ".DS_Store" -o \
        -name "Thumbs.db" -o \
        -name "*.swp" -o \
        -name "*.swo" \
        -type f 2>/dev/null || true)
    
    # Cleanup redundant scripts
    cleanup_redundant_scripts
    
    if [[ $removed_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Codebase cleanup completed. Removed $removed_count files."
        increment_counter "fixed"
    else
        log_maintenance "INFO" "No codebase files needed cleaning"
        increment_counter "skipped"
    fi
}

# Cleanup redundant scripts
cleanup_redundant_scripts() {
    log_maintenance "INFO" "Cleaning up redundant scripts..."
    
    # List of redundant scripts to remove
    local redundant_scripts=(
        "cleanup-unified.sh"
        "cleanup-comparison.sh"
        "cleanup-codebase.sh"
        "quick-cleanup-test.sh"
        "test-cleanup-integration.sh"
        "test-cleanup-unified.sh"
        "test-cleanup-017.sh"
        "test-cleanup-iam.sh"
        "test-full-iam-cleanup.sh"
        "test-inline-policy-cleanup.sh"
        "aws-deployment-v2-simple.sh"
        "simple-demo.sh"
        "test-intelligent-selection.sh"
        "test-os-compatibility.sh"
        "validate-os-compatibility.sh"
    )
    
    for script in "${redundant_scripts[@]}"; do
        # Check in multiple locations
        for dir in "scripts" "tests" "archive/legacy"; do
            local file_path="${MAINTENANCE_PROJECT_ROOT}/${dir}/${script}"
            if [[ -f "$file_path" ]]; then
                safe_delete_file "$file_path" "redundant script"
            fi
        done
    done
}

# Export all cleanup functions
export -f cleanup_logs
export -f cleanup_docker
export -f cleanup_docker_safe
export -f show_docker_cleanup_preview
export -f cleanup_temp
export -f cleanup_aws
export -f cleanup_ec2_instances
export -f cleanup_spot_requests
export -f cleanup_efs_resources
export -f cleanup_single_efs
export -f cleanup_network_resources
export -f cleanup_security_groups
export -f cleanup_load_balancers
export -f cleanup_cloudfront_distributions
export -f cleanup_iam_resources
export -f cleanup_monitoring_resources
export -f cleanup_storage_resources
export -f cleanup_backups
export -f cleanup_codebase
export -f cleanup_redundant_scripts