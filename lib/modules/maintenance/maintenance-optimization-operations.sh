#!/bin/bash
#
# Maintenance Optimization Operations Module
# Contains all system and resource optimization operations
#

# =============================================================================
# DOCKER OPTIMIZATION OPERATIONS
# =============================================================================

# Optimize Docker resources
optimize_docker() {
    log_maintenance "INFO" "Optimizing Docker resources..."
    increment_counter "processed"
    
    local optimizations_made=0
    
    # Optimize Docker daemon configuration
    if optimize_docker_daemon; then
        ((optimizations_made++))
    fi
    
    # Optimize Docker images
    if optimize_docker_images; then
        ((optimizations_made++))
    fi
    
    # Optimize Docker containers
    if optimize_docker_containers; then
        ((optimizations_made++))
    fi
    
    # Optimize Docker networks
    if optimize_docker_networks; then
        ((optimizations_made++))
    fi
    
    # Optimize Docker volumes
    if optimize_docker_volumes; then
        ((optimizations_made++))
    fi
    
    if [[ $optimizations_made -gt 0 ]]; then
        log_maintenance "SUCCESS" "Completed $optimizations_made Docker optimizations"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "Docker already optimized"
        increment_counter "skipped"
    fi
    
    return 0
}

# Optimize Docker daemon configuration
optimize_docker_daemon() {
    log_maintenance "INFO" "Optimizing Docker daemon configuration..."
    
    local daemon_config="/etc/docker/daemon.json"
    local optimized=false
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize Docker daemon configuration"
        return 0
    fi
    
    # Backup existing configuration
    if [[ -f "$daemon_config" ]]; then
        create_timestamped_backup "$daemon_config" "docker-daemon"
    fi
    
    # Create optimized configuration
    local temp_config=$(mktemp)
    cat > "$temp_config" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 3,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    },
    "live-restore": true,
    "userland-proxy": false,
    "ip-forward": true,
    "iptables": true,
    "ip-masq": true,
    "bridge": "docker0",
    "registry-mirrors": [],
    "insecure-registries": [],
    "metrics-addr": "0.0.0.0:9323",
    "experimental": true
}
EOF
    
    # Merge with existing configuration if present
    if [[ -f "$daemon_config" ]]; then
        # Simple merge (would need jq for proper JSON merge)
        if command -v jq >/dev/null 2>&1; then
            jq -s '.[0] * .[1]' "$daemon_config" "$temp_config" > "${temp_config}.merged"
            mv "${temp_config}.merged" "$temp_config"
        fi
    fi
    
    # Apply configuration
    if sudo mv "$temp_config" "$daemon_config"; then
        log_maintenance "SUCCESS" "Updated Docker daemon configuration"
        
        # Restart Docker to apply changes
        if sudo systemctl restart docker; then
            log_maintenance "SUCCESS" "Docker daemon restarted with optimized configuration"
            optimized=true
        else
            log_maintenance "WARNING" "Failed to restart Docker daemon"
        fi
    else
        log_maintenance "ERROR" "Failed to update Docker daemon configuration"
        rm -f "$temp_config"
    fi
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize Docker images
optimize_docker_images() {
    log_maintenance "INFO" "Optimizing Docker images..."
    
    local before_size=$(docker system df --format "table {{.Size}}" | grep "Images" | awk '{print $3}')
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize Docker images"
        show_docker_optimization_preview
        return 0
    fi
    
    # Remove dangling images
    docker image prune -f >/dev/null 2>&1
    
    # Find and remove duplicate image layers
    remove_duplicate_layers
    
    # Optimize image sizes by rebuilding with multi-stage builds
    optimize_image_builds
    
    local after_size=$(docker system df --format "table {{.Size}}" | grep "Images" | awk '{print $3}')
    
    if [[ "$before_size" != "$after_size" ]]; then
        log_maintenance "SUCCESS" "Optimized Docker images: $before_size -> $after_size"
        return 0
    fi
    
    return 1
}

# Remove duplicate Docker layers
remove_duplicate_layers() {
    log_maintenance "INFO" "Removing duplicate image layers..."
    
    # Get all image IDs and their sizes
    docker images --format "table {{.ID}}\t{{.Size}}" | tail -n +2 | sort -k2 -hr | \
    while read -r image_id size; do
        # Check if image is used by any container
        if ! docker ps -a --format "{{.Image}}" | grep -q "$image_id"; then
            # Check if image has duplicates
            local digest=$(docker inspect "$image_id" --format='{{.RepoDigests}}' 2>/dev/null || echo "")
            if [[ -n "$digest" ]] && [[ "$digest" != "[]" ]]; then
                # Keep only the latest version
                docker rmi "$image_id" >/dev/null 2>&1 || true
            fi
        fi
    done
}

# Optimize image builds
optimize_image_builds() {
    log_maintenance "INFO" "Checking for image optimization opportunities..."
    
    # Check if any Dockerfiles exist in the project
    local dockerfiles=$(find "${MAINTENANCE_PROJECT_ROOT}" -name "Dockerfile*" -type f 2>/dev/null)
    
    for dockerfile in $dockerfiles; do
        if [[ -f "$dockerfile" ]]; then
            # Analyze Dockerfile for optimization opportunities
            analyze_dockerfile "$dockerfile"
        fi
    done
}

# Analyze Dockerfile for optimizations
analyze_dockerfile() {
    local dockerfile="$1"
    
    log_maintenance "INFO" "Analyzing Dockerfile: $dockerfile"
    
    # Check for optimization opportunities
    local suggestions=()
    
    # Check for multiple RUN commands that could be combined
    local run_count=$(grep -c "^RUN" "$dockerfile" || echo 0)
    if [[ $run_count -gt 3 ]]; then
        suggestions+=("Consider combining multiple RUN commands to reduce layers")
    fi
    
    # Check for missing .dockerignore
    local dockerignore="${dockerfile%/*}/.dockerignore"
    if [[ ! -f "$dockerignore" ]]; then
        suggestions+=("Add .dockerignore file to exclude unnecessary files")
    fi
    
    # Check for apt-get without cleanup
    if grep -q "apt-get install" "$dockerfile" && ! grep -q "rm -rf /var/lib/apt/lists" "$dockerfile"; then
        suggestions+=("Clean apt cache after installation: rm -rf /var/lib/apt/lists/*")
    fi
    
    # Check for missing multi-stage builds
    if ! grep -q "^FROM.*AS" "$dockerfile"; then
        suggestions+=("Consider using multi-stage builds to reduce final image size")
    fi
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        log_maintenance "INFO" "Optimization suggestions for $dockerfile:"
        for suggestion in "${suggestions[@]}"; do
            echo "  - $suggestion"
        done
    fi
}

# Optimize Docker containers
optimize_docker_containers() {
    log_maintenance "INFO" "Optimizing Docker containers..."
    
    local optimized=false
    
    # Set resource limits on containers without them
    docker ps --format "{{.Names}}" | while read -r container; do
        local has_limits=$(docker inspect "$container" --format='{{.HostConfig.Memory}}' 2>/dev/null)
        
        if [[ "$has_limits" == "0" ]]; then
            log_maintenance "INFO" "Container $container has no memory limit"
            
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                # Set reasonable default limits based on container type
                case "$container" in
                    postgres)
                        docker update --memory="2g" --memory-swap="2g" "$container" >/dev/null 2>&1 || true
                        ;;
                    n8n)
                        docker update --memory="1g" --memory-swap="1g" "$container" >/dev/null 2>&1 || true
                        ;;
                    ollama)
                        # Ollama needs more memory for models
                        docker update --memory="8g" --memory-swap="8g" "$container" >/dev/null 2>&1 || true
                        ;;
                    *)
                        docker update --memory="512m" --memory-swap="512m" "$container" >/dev/null 2>&1 || true
                        ;;
                esac
                
                log_maintenance "SUCCESS" "Set memory limits for container: $container"
                optimized=true
            fi
        fi
    done
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize Docker networks
optimize_docker_networks() {
    log_maintenance "INFO" "Optimizing Docker networks..."
    
    # Remove unused networks
    local unused_networks=$(docker network ls --filter "dangling=true" -q)
    
    if [[ -n "$unused_networks" ]]; then
        if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
            log_maintenance "INFO" "[DRY RUN] Would remove unused networks"
        else
            docker network prune -f >/dev/null 2>&1
            log_maintenance "SUCCESS" "Removed unused Docker networks"
        fi
        return 0
    fi
    
    return 1
}

# Optimize Docker volumes
optimize_docker_volumes() {
    log_maintenance "INFO" "Optimizing Docker volumes..."
    
    # Find and remove orphaned volumes
    local orphaned_volumes=$(docker volume ls -qf dangling=true)
    
    if [[ -n "$orphaned_volumes" ]]; then
        if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
            log_maintenance "INFO" "[DRY RUN] Would remove orphaned volumes"
        else
            docker volume rm $orphaned_volumes >/dev/null 2>&1 || true
            log_maintenance "SUCCESS" "Removed orphaned Docker volumes"
        fi
        return 0
    fi
    
    return 1
}

# Show Docker optimization preview
show_docker_optimization_preview() {
    echo "Docker optimization preview:"
    
    # Images
    local dangling_images=$(docker images -f "dangling=true" -q | wc -l)
    echo "  - Dangling images to remove: $dangling_images"
    
    # Containers without limits
    local containers_no_limits=0
    docker ps --format "{{.Names}}" | while read -r container; do
        local has_limits=$(docker inspect "$container" --format='{{.HostConfig.Memory}}' 2>/dev/null)
        [[ "$has_limits" == "0" ]] && ((containers_no_limits++))
    done
    echo "  - Containers without resource limits: $containers_no_limits"
    
    # Networks
    local unused_networks=$(docker network ls --filter "dangling=true" -q | wc -l)
    echo "  - Unused networks: $unused_networks"
    
    # Volumes
    local orphaned_volumes=$(docker volume ls -qf dangling=true | wc -l)
    echo "  - Orphaned volumes: $orphaned_volumes"
}

# =============================================================================
# SYSTEM RESOURCE OPTIMIZATION
# =============================================================================

# Optimize system resources
optimize_system_resources() {
    log_maintenance "INFO" "Optimizing system resources..."
    increment_counter "processed"
    
    local optimizations_made=0
    
    # Optimize system memory
    if optimize_system_memory; then
        ((optimizations_made++))
    fi
    
    # Optimize disk I/O
    if optimize_disk_io; then
        ((optimizations_made++))
    fi
    
    # Optimize network settings
    if optimize_network_settings; then
        ((optimizations_made++))
    fi
    
    # Optimize system services
    if optimize_system_services; then
        ((optimizations_made++))
    fi
    
    if [[ $optimizations_made -gt 0 ]]; then
        log_maintenance "SUCCESS" "Completed $optimizations_made system optimizations"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "System already optimized"
        increment_counter "skipped"
    fi
    
    return 0
}

# Optimize system memory
optimize_system_memory() {
    log_maintenance "INFO" "Optimizing system memory..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize system memory"
        return 0
    fi
    
    local optimized=false
    
    # Clear page cache
    local mem_before=$(free -m | awk 'NR==2{print $4}')
    sync && echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1
    local mem_after=$(free -m | awk 'NR==2{print $4}')
    
    local mem_freed=$((mem_after - mem_before))
    if [[ $mem_freed -gt 100 ]]; then
        log_maintenance "SUCCESS" "Freed ${mem_freed}MB of memory"
        optimized=true
    fi
    
    # Optimize swappiness for server workload
    local current_swappiness=$(cat /proc/sys/vm/swappiness)
    if [[ $current_swappiness -gt 10 ]]; then
        echo 10 | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1
        log_maintenance "SUCCESS" "Adjusted swappiness: $current_swappiness -> 10"
        optimized=true
    fi
    
    # Set up hugepages if not configured
    local hugepages=$(grep -E "^HugePages_Total:" /proc/meminfo | awk '{print $2}')
    if [[ $hugepages -eq 0 ]]; then
        # Calculate hugepages (use 25% of total memory)
        local total_mem=$(free -m | awk 'NR==2{print $2}')
        local hugepages_count=$((total_mem / 8))  # 2MB pages, use 25% of memory
        
        echo $hugepages_count | sudo tee /proc/sys/vm/nr_hugepages >/dev/null 2>&1
        log_maintenance "INFO" "Configured $hugepages_count hugepages"
        optimized=true
    fi
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize disk I/O
optimize_disk_io() {
    log_maintenance "INFO" "Optimizing disk I/O..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize disk I/O"
        return 0
    fi
    
    local optimized=false
    
    # Get root device
    local root_device=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
    
    if [[ -b "$root_device" ]]; then
        # Set optimal I/O scheduler
        local current_scheduler=$(cat /sys/block/$(basename $root_device)/queue/scheduler | grep -o '\[[^]]*\]' | tr -d '[]')
        
        # For SSDs, use noop or deadline
        if [[ -f /sys/block/$(basename $root_device)/queue/rotational ]]; then
            local is_ssd=$(cat /sys/block/$(basename $root_device)/queue/rotational)
            
            if [[ $is_ssd -eq 0 ]]; then
                # SSD detected
                if [[ "$current_scheduler" != "noop" ]] && [[ "$current_scheduler" != "deadline" ]]; then
                    echo noop | sudo tee /sys/block/$(basename $root_device)/queue/scheduler >/dev/null 2>&1 || \
                    echo deadline | sudo tee /sys/block/$(basename $root_device)/queue/scheduler >/dev/null 2>&1
                    
                    log_maintenance "SUCCESS" "Set I/O scheduler for SSD: $current_scheduler -> noop/deadline"
                    optimized=true
                fi
            fi
        fi
        
        # Optimize read-ahead
        local current_readahead=$(blockdev --getra $root_device 2>/dev/null || echo 256)
        if [[ $current_readahead -lt 256 ]]; then
            sudo blockdev --setra 256 $root_device 2>/dev/null || true
            log_maintenance "SUCCESS" "Increased read-ahead buffer: $current_readahead -> 256"
            optimized=true
        fi
    fi
    
    # Enable filesystem optimizations
    if mount | grep -q "ext4.*commit="; then
        # Already optimized
        :
    else
        # Remount with optimizations (commit=60 for less frequent writes)
        local root_mount=$(mount | grep " / " | head -1)
        if echo "$root_mount" | grep -q "ext4"; then
            sudo mount -o remount,commit=60 / 2>/dev/null || true
            log_maintenance "INFO" "Optimized ext4 commit interval"
            optimized=true
        fi
    fi
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize network settings
optimize_network_settings() {
    log_maintenance "INFO" "Optimizing network settings..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize network settings"
        return 0
    fi
    
    local optimized=false
    
    # Optimize TCP settings for better performance
    declare -A tcp_settings=(
        ["net.core.rmem_max"]="134217728"
        ["net.core.wmem_max"]="134217728"
        ["net.ipv4.tcp_rmem"]="4096 87380 134217728"
        ["net.ipv4.tcp_wmem"]="4096 65536 134217728"
        ["net.ipv4.tcp_congestion_control"]="bbr"
        ["net.core.default_qdisc"]="fq"
        ["net.ipv4.tcp_fastopen"]="3"
        ["net.core.somaxconn"]="1024"
        ["net.ipv4.tcp_max_syn_backlog"]="2048"
    )
    
    for setting in "${!tcp_settings[@]}"; do
        local current_value=$(sysctl -n "$setting" 2>/dev/null || echo "")
        local new_value="${tcp_settings[$setting]}"
        
        if [[ "$current_value" != "$new_value" ]]; then
            echo "$setting = $new_value" | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1
            sudo sysctl -w "$setting=$new_value" >/dev/null 2>&1 || true
            
            log_maintenance "SUCCESS" "Optimized $setting"
            optimized=true
        fi
    done
    
    # Enable BBR congestion control if available
    if modinfo tcp_bbr >/dev/null 2>&1; then
        if ! lsmod | grep -q tcp_bbr; then
            sudo modprobe tcp_bbr 2>/dev/null || true
            log_maintenance "INFO" "Enabled BBR congestion control"
            optimized=true
        fi
    fi
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize system services
optimize_system_services() {
    log_maintenance "INFO" "Optimizing system services..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize system services"
        return 0
    fi
    
    local optimized=false
    
    # Disable unnecessary services
    local unnecessary_services=(
        "bluetooth.service"
        "cups.service"
        "avahi-daemon.service"
        "ModemManager.service"
    )
    
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            sudo systemctl disable "$service" >/dev/null 2>&1 || true
            sudo systemctl stop "$service" >/dev/null 2>&1 || true
            log_maintenance "SUCCESS" "Disabled unnecessary service: $service"
            optimized=true
        fi
    done
    
    # Optimize systemd settings
    local systemd_conf="/etc/systemd/system.conf"
    if [[ -f "$systemd_conf" ]]; then
        # Increase default limits
        if ! grep -q "^DefaultLimitNOFILE=" "$systemd_conf"; then
            echo "DefaultLimitNOFILE=65535" | sudo tee -a "$systemd_conf" >/dev/null 2>&1
            log_maintenance "SUCCESS" "Increased systemd file limit"
            optimized=true
        fi
        
        if ! grep -q "^DefaultLimitMEMLOCK=" "$systemd_conf"; then
            echo "DefaultLimitMEMLOCK=infinity" | sudo tee -a "$systemd_conf" >/dev/null 2>&1
            log_maintenance "SUCCESS" "Set systemd memory lock to infinity"
            optimized=true
        fi
    fi
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# =============================================================================
# AWS RESOURCE OPTIMIZATION
# =============================================================================

# Optimize AWS resources
optimize_aws_resources() {
    log_maintenance "INFO" "Optimizing AWS resources..."
    increment_counter "processed"
    
    if [[ -z "$MAINTENANCE_STACK_NAME" ]]; then
        log_maintenance "WARNING" "Stack name required for AWS optimization"
        increment_counter "skipped"
        return 1
    fi
    
    local optimizations_made=0
    
    # Optimize EC2 instances
    if optimize_ec2_instances; then
        ((optimizations_made++))
    fi
    
    # Optimize EBS volumes
    if optimize_ebs_volumes; then
        ((optimizations_made++))
    fi
    
    # Optimize security groups
    if optimize_security_groups; then
        ((optimizations_made++))
    fi
    
    # Optimize CloudWatch logs
    if optimize_cloudwatch_logs; then
        ((optimizations_made++))
    fi
    
    if [[ $optimizations_made -gt 0 ]]; then
        log_maintenance "SUCCESS" "Completed $optimizations_made AWS optimizations"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "AWS resources already optimized"
        increment_counter "skipped"
    fi
    
    return 0
}

# Optimize EC2 instances
optimize_ec2_instances() {
    log_maintenance "INFO" "Optimizing EC2 instances..."
    
    # Get instances for stack
    local instance_ids
    instance_ids=$(safe_aws_command \
        "aws ec2 describe-instances --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text" \
        "Get instances")
    
    if [[ -z "$instance_ids" ]] || [[ "$instance_ids" == "None" ]]; then
        return 1
    fi
    
    local optimized=false
    
    for instance_id in $instance_ids; do
        # Check if instance has optimal settings
        local instance_info=$(safe_aws_command \
            "aws ec2 describe-instances --instance-ids $instance_id --region $MAINTENANCE_AWS_REGION --query 'Reservations[0].Instances[0]'" \
            "Get instance info")
        
        # Check EBS optimization
        local ebs_optimized=$(echo "$instance_info" | jq -r '.EbsOptimized')
        if [[ "$ebs_optimized" == "false" ]]; then
            local instance_type=$(echo "$instance_info" | jq -r '.InstanceType')
            
            # Check if instance type supports EBS optimization
            if [[ "$instance_type" =~ ^(m5|c5|r5|g4dn|g5) ]]; then
                log_maintenance "INFO" "Instance $instance_id could benefit from EBS optimization"
                
                if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                    # Note: Requires instance stop/start
                    log_maintenance "WARNING" "EBS optimization requires instance restart"
                fi
            fi
        fi
        
        # Check monitoring
        local monitoring=$(echo "$instance_info" | jq -r '.Monitoring.State')
        if [[ "$monitoring" == "disabled" ]]; then
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                if safe_aws_command \
                    "aws ec2 monitor-instances --instance-ids $instance_id --region $MAINTENANCE_AWS_REGION" \
                    "Enable detailed monitoring"; then
                    log_maintenance "SUCCESS" "Enabled detailed monitoring for $instance_id"
                    optimized=true
                fi
            fi
        fi
    done
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize EBS volumes
optimize_ebs_volumes() {
    log_maintenance "INFO" "Optimizing EBS volumes..."
    
    # Get volumes for instances
    local volume_ids
    volume_ids=$(safe_aws_command \
        "aws ec2 describe-volumes --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME --query 'Volumes[].VolumeId' --output text" \
        "Get volumes")
    
    if [[ -z "$volume_ids" ]] || [[ "$volume_ids" == "None" ]]; then
        return 1
    fi
    
    local optimized=false
    
    for volume_id in $volume_ids; do
        local volume_info=$(safe_aws_command \
            "aws ec2 describe-volumes --volume-ids $volume_id --region $MAINTENANCE_AWS_REGION --query 'Volumes[0]'" \
            "Get volume info")
        
        # Check if volume type can be upgraded
        local volume_type=$(echo "$volume_info" | jq -r '.VolumeType')
        local volume_size=$(echo "$volume_info" | jq -r '.Size')
        
        if [[ "$volume_type" == "gp2" ]] && [[ $volume_size -lt 170 ]]; then
            # gp3 is more cost-effective for smaller volumes
            log_maintenance "INFO" "Volume $volume_id could be upgraded from gp2 to gp3"
            
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                if safe_aws_command \
                    "aws ec2 modify-volume --volume-id $volume_id --volume-type gp3 --region $MAINTENANCE_AWS_REGION" \
                    "Upgrade volume to gp3"; then
                    log_maintenance "SUCCESS" "Upgraded volume $volume_id to gp3"
                    optimized=true
                fi
            fi
        fi
    done
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize security groups
optimize_security_groups() {
    log_maintenance "INFO" "Optimizing security groups..."
    
    # Get security groups
    local sg_ids
    sg_ids=$(safe_aws_command \
        "aws ec2 describe-security-groups --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME --query 'SecurityGroups[].GroupId' --output text" \
        "Get security groups")
    
    if [[ -z "$sg_ids" ]] || [[ "$sg_ids" == "None" ]]; then
        return 1
    fi
    
    local optimized=false
    
    for sg_id in $sg_ids; do
        # Check for overly permissive rules
        local rules=$(safe_aws_command \
            "aws ec2 describe-security-groups --group-ids $sg_id --region $MAINTENANCE_AWS_REGION --query 'SecurityGroups[0].IpPermissions'" \
            "Get security group rules")
        
        # Check for 0.0.0.0/0 rules on non-standard ports
        if echo "$rules" | jq -r '.[] | select(.IpRanges[]?.CidrIp == "0.0.0.0/0")' | grep -v -E '"(80|443|22)"'; then
            log_maintenance "WARNING" "Security group $sg_id has overly permissive rules"
            # Don't auto-fix security rules
        fi
    done
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# Optimize CloudWatch logs
optimize_cloudwatch_logs() {
    log_maintenance "INFO" "Optimizing CloudWatch logs..."
    
    # Get log groups
    local log_groups
    log_groups=$(safe_aws_command \
        "aws logs describe-log-groups --region $MAINTENANCE_AWS_REGION --query 'logGroups[?contains(logGroupName, `'$MAINTENANCE_STACK_NAME'`)].logGroupName' --output text" \
        "Get log groups")
    
    if [[ -z "$log_groups" ]] || [[ "$log_groups" == "None" ]]; then
        return 1
    fi
    
    local optimized=false
    
    for log_group in $log_groups; do
        # Check retention policy
        local retention=$(safe_aws_command \
            "aws logs describe-log-groups --log-group-name-prefix $log_group --region $MAINTENANCE_AWS_REGION --query 'logGroups[0].retentionInDays' --output text" \
            "Get retention policy")
        
        if [[ "$retention" == "None" ]] || [[ "$retention" == "null" ]]; then
            # Set 30-day retention
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                if safe_aws_command \
                    "aws logs put-retention-policy --log-group-name $log_group --retention-in-days 30 --region $MAINTENANCE_AWS_REGION" \
                    "Set retention policy"; then
                    log_maintenance "SUCCESS" "Set 30-day retention for $log_group"
                    optimized=true
                fi
            fi
        fi
    done
    
    return $([[ "$optimized" == true ]] && echo 0 || echo 1)
}

# =============================================================================
# VALIDATION OPERATIONS
# =============================================================================

# Validate scripts
validate_scripts() {
    log_maintenance "INFO" "Validating scripts..."
    increment_counter "processed"
    
    local scripts_dir="${MAINTENANCE_PROJECT_ROOT}/scripts"
    local validation_failed=false
    local validated_count=0
    
    # Find all shell scripts
    find "$scripts_dir" -name "*.sh" -type f | while read -r script; do
        if validate_shell_script "$script"; then
            ((validated_count++))
        else
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == true ]]; then
        log_maintenance "ERROR" "Some scripts failed validation"
        increment_counter "failed"
        return 1
    else
        log_maintenance "SUCCESS" "All $validated_count scripts passed validation"
        increment_counter "fixed"
        return 0
    fi
}

# Validate configurations
validate_configurations() {
    log_maintenance "INFO" "Validating configurations..."
    increment_counter "processed"
    
    local config_dir="${MAINTENANCE_PROJECT_ROOT}/config"
    local validation_failed=false
    
    # Validate YAML files
    find "$config_dir" -name "*.yml" -o -name "*.yaml" 2>/dev/null | while read -r yaml_file; do
        if ! validate_yaml "$yaml_file"; then
            validation_failed=true
        fi
    done
    
    # Validate JSON files
    find "$config_dir" -name "*.json" 2>/dev/null | while read -r json_file; do
        if ! validate_json "$json_file"; then
            validation_failed=true
        fi
    done
    
    # Validate Docker Compose files
    find "${MAINTENANCE_PROJECT_ROOT}" -name "docker-compose*.yml" 2>/dev/null | while read -r compose_file; do
        if ! validate_yaml "$compose_file"; then
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == true ]]; then
        log_maintenance "ERROR" "Some configurations failed validation"
        increment_counter "failed"
        return 1
    else
        log_maintenance "SUCCESS" "All configurations passed validation"
        increment_counter "fixed"
        return 0
    fi
}

# Validate AWS resources
validate_aws_resources() {
    log_maintenance "INFO" "Validating AWS resources..."
    increment_counter "processed"
    
    if [[ -z "$MAINTENANCE_STACK_NAME" ]]; then
        log_maintenance "WARNING" "Stack name required for AWS validation"
        increment_counter "skipped"
        return 1
    fi
    
    local validation_passed=true
    
    # Validate instances are running
    local instance_ids
    instance_ids=$(safe_aws_command \
        "aws ec2 describe-instances --region $MAINTENANCE_AWS_REGION --filters Name=tag:StackName,Values=$MAINTENANCE_STACK_NAME Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text" \
        "Check running instances")
    
    if [[ -z "$instance_ids" ]] || [[ "$instance_ids" == "None" ]]; then
        log_maintenance "WARNING" "No running instances found for stack"
        validation_passed=false
    fi
    
    # Validate EFS is mounted
    if [[ -n "$instance_ids" ]]; then
        # Check if EFS exists
        local efs_id
        efs_id=$(safe_aws_command \
            "aws efs describe-file-systems --region $MAINTENANCE_AWS_REGION --query \"FileSystems[?Tags[?Key=='StackName' && Value=='$MAINTENANCE_STACK_NAME']].FileSystemId\" --output text" \
            "Check EFS")
        
        if [[ -z "$efs_id" ]] || [[ "$efs_id" == "None" ]]; then
            log_maintenance "WARNING" "No EFS found for stack"
            validation_passed=false
        fi
    fi
    
    if [[ "$validation_passed" == true ]]; then
        log_maintenance "SUCCESS" "AWS resources validation passed"
        increment_counter "fixed"
        return 0
    else
        log_maintenance "ERROR" "AWS resources validation failed"
        increment_counter "failed"
        return 1
    fi
}

# Export optimization functions
export -f optimize_docker
export -f optimize_docker_daemon
export -f optimize_docker_images
export -f remove_duplicate_layers
export -f optimize_image_builds
export -f analyze_dockerfile
export -f optimize_docker_containers
export -f optimize_docker_networks
export -f optimize_docker_volumes
export -f show_docker_optimization_preview
export -f optimize_system_resources
export -f optimize_system_memory
export -f optimize_disk_io
export -f optimize_network_settings
export -f optimize_system_services
export -f optimize_aws_resources
export -f optimize_ec2_instances
export -f optimize_ebs_volumes
export -f optimize_security_groups
export -f optimize_cloudwatch_logs
export -f validate_scripts
export -f validate_configurations
export -f validate_aws_resources