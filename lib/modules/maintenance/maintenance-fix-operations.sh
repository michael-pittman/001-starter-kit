#!/bin/bash
#
# Maintenance Fix Operations Module
# Contains all fix operations extracted from maintenance scripts
#

# =============================================================================
# DEPLOYMENT FIX OPERATIONS
# =============================================================================

# Fix deployment issues (main function)
fix_deployment_issues() {
    log_maintenance "INFO" "Fixing deployment issues..."
    increment_counter "processed"
    
    local issues_fixed=0
    
    # Fix disk space issues
    if fix_disk_issues; then
        ((issues_fixed++))
    fi
    
    # Fix EFS issues
    if fix_efs_issues; then
        ((issues_fixed++))
    fi
    
    # Fix parameter store integration
    if fix_parameter_store_issues; then
        ((issues_fixed++))
    fi
    
    # Fix Docker issues
    if fix_docker_issues; then
        ((issues_fixed++))
    fi
    
    if [[ $issues_fixed -gt 0 ]]; then
        log_maintenance "SUCCESS" "Fixed $issues_fixed deployment issues"
        increment_counter "fixed"
        return 0
    else
        log_maintenance "WARNING" "No deployment issues fixed"
        increment_counter "skipped"
        return 1
    fi
}

# =============================================================================
# DISK SPACE FIX OPERATIONS
# =============================================================================

# Fix disk space issues
fix_disk_issues() {
    log_maintenance "INFO" "Checking and fixing disk space issues..."
    increment_counter "processed"
    
    local disk_usage=$(get_system_resources "disk")
    local disk_available=$(get_system_resources "disk_available")
    
    log_maintenance "INFO" "Current disk usage: ${disk_usage}%, Available: ${disk_available}GB"
    
    if [[ $disk_usage -lt 80 ]]; then
        log_maintenance "INFO" "Disk usage is acceptable"
        increment_counter "skipped"
        return 0
    fi
    
    # Clean up Docker resources
    cleanup_docker_space
    
    # Expand root volume if needed
    if [[ $disk_usage -gt 90 ]]; then
        expand_root_volume
    fi
    
    # Re-check disk usage
    local new_disk_usage=$(get_system_resources "disk")
    if [[ $new_disk_usage -lt $disk_usage ]]; then
        log_maintenance "SUCCESS" "Disk usage reduced from ${disk_usage}% to ${new_disk_usage}%"
        increment_counter "fixed"
        return 0
    else
        log_maintenance "WARNING" "Unable to reduce disk usage significantly"
        increment_counter "failed"
        return 1
    fi
}

# Cleanup Docker space
cleanup_docker_space() {
    log_maintenance "INFO" "Cleaning up Docker to free disk space..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would clean Docker resources"
        return 0
    fi
    
    # Stop all containers safely
    local running_containers=$(docker ps -q 2>/dev/null)
    if [[ -n "$running_containers" ]]; then
        log_maintenance "INFO" "Stopping running containers..."
        for container in $running_containers; do
            docker stop "$container" 2>/dev/null || true
        done
    fi
    
    # Calculate space before cleanup
    local before_size=$(calculate_docker_usage | grep -oE '[0-9]+' | awk '{sum+=$1} END {print sum}')
    
    # Remove unused containers, networks, images, and build cache
    docker system prune -af --volumes 2>/dev/null || true
    
    # Remove unused images more aggressively
    docker image prune -af 2>/dev/null || true
    
    # Clean up Docker overlay2 directory if needed
    if [[ -d /var/lib/docker/overlay2 ]]; then
        local overlay_usage=$(get_directory_size "/var/lib/docker/overlay2" true)
        log_maintenance "INFO" "Docker overlay2 usage after cleanup: $overlay_usage"
    fi
    
    # Calculate space after cleanup
    local after_size=$(calculate_docker_usage | grep -oE '[0-9]+' | awk '{sum+=$1} END {print sum}')
    local saved_space=$((before_size - after_size))
    
    log_maintenance "SUCCESS" "Docker cleanup completed, freed approximately ${saved_space} bytes"
}

# Expand root volume
expand_root_volume() {
    log_maintenance "INFO" "Attempting to expand root volume..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would attempt volume expansion"
        return 0
    fi
    
    # Get the root device safely
    local root_device root_kname
    root_kname=$(lsblk -no KNAME / 2>/dev/null) || {
        log_maintenance "ERROR" "Failed to identify root device"
        return 1
    }
    
    if [[ -n "$root_kname" ]] && [[ -b "/dev/$root_kname" ]]; then
        root_device=$(lsblk -no PKNAME "/dev/$root_kname" 2>/dev/null)
        if [[ -n "$root_device" ]] && [[ -b "/dev/$root_device" ]]; then
            # Resize the partition and filesystem
            if sudo growpart "/dev/$root_device" 1 2>/dev/null; then
                log_maintenance "SUCCESS" "Partition expanded"
                
                if sudo resize2fs "/dev/${root_device}1" 2>/dev/null; then
                    log_maintenance "SUCCESS" "Filesystem expanded"
                    return 0
                else
                    log_maintenance "WARNING" "Failed to expand filesystem"
                fi
            else
                log_maintenance "INFO" "No expansion needed or not possible"
            fi
        fi
    fi
    
    return 1
}

# =============================================================================
# EFS FIX OPERATIONS
# =============================================================================

# Fix EFS issues
fix_efs_issues() {
    local stack_name="${MAINTENANCE_STACK_NAME:-}"
    local aws_region="${MAINTENANCE_AWS_REGION:-us-east-1}"
    
    if [[ -z "$stack_name" ]]; then
        log_maintenance "WARNING" "Stack name required for EFS fixes"
        increment_counter "skipped"
        return 1
    fi
    
    log_maintenance "INFO" "Setting up EFS mounting for stack: $stack_name"
    increment_counter "processed"
    
    # Check if EFS exists for this stack
    local efs_id
    efs_id=$(safe_aws_command \
        "aws efs describe-file-systems --query \"FileSystems[?Tags[?Key=='Name' && Value=='${stack_name}-efs']].FileSystemId\" --output text --region $aws_region" \
        "Check EFS existence")
    
    if [[ -z "$efs_id" ]] || [[ "$efs_id" == "None" ]]; then
        log_maintenance "WARNING" "No EFS found for stack $stack_name. Creating one..."
        if create_efs_for_stack "$stack_name" "$aws_region"; then
            efs_id=$(safe_aws_command \
                "aws efs describe-file-systems --query \"FileSystems[?Tags[?Key=='Name' && Value=='${stack_name}-efs']].FileSystemId\" --output text --region $aws_region" \
                "Get new EFS ID")
        else
            increment_counter "failed"
            return 1
        fi
    fi
    
    # Get EFS DNS name
    local efs_dns="${efs_id}.efs.${aws_region}.amazonaws.com"
    
    # Install EFS utils if not present
    if ! command -v mount.efs &> /dev/null; then
        log_maintenance "INFO" "Installing EFS utilities..."
        if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            sudo apt-get update -qq
            sudo apt-get install -y amazon-efs-utils nfs-common
        fi
    fi
    
    # Create mount points
    if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
        sudo mkdir -p /mnt/efs/{data,models,logs,config}
    fi
    
    # Mount EFS
    log_maintenance "INFO" "Mounting EFS: $efs_dns"
    if ! mountpoint -q /mnt/efs; then
        if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            sudo mount -t efs -o tls "$efs_id":/ /mnt/efs || {
                log_maintenance "ERROR" "Failed to mount EFS"
                increment_counter "failed"
                return 1
            }
            
            # Add to fstab for persistence
            if ! grep -q "$efs_id" /etc/fstab; then
                echo "$efs_dns:/ /mnt/efs efs tls,_netdev 0 0" | sudo tee -a /etc/fstab
            fi
            
            # Set proper permissions
            sudo chown -R ubuntu:ubuntu /mnt/efs
            sudo chmod 755 /mnt/efs
        fi
        
        log_maintenance "SUCCESS" "EFS mounted successfully"
    else
        log_maintenance "INFO" "EFS already mounted"
    fi
    
    # Update environment file with EFS DNS
    if [[ -f /home/ubuntu/GeuseMaker/.env ]]; then
        if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            if grep -q "EFS_DNS=" /home/ubuntu/GeuseMaker/.env; then
                sed -i "s/EFS_DNS=.*/EFS_DNS=$efs_dns/" /home/ubuntu/GeuseMaker/.env
            else
                echo "EFS_DNS=$efs_dns" >> /home/ubuntu/GeuseMaker/.env
            fi
        fi
    fi
    
    log_maintenance "INFO" "EFS DNS: $efs_dns"
    increment_counter "fixed"
    return 0
}

# Create EFS for stack
create_efs_for_stack() {
    local stack_name="$1"
    local aws_region="$2"
    
    log_maintenance "INFO" "Creating EFS for stack: $stack_name"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create EFS"
        return 0
    fi
    
    # Create EFS
    local efs_id
    efs_id=$(safe_aws_command \
        "aws efs create-file-system --performance-mode generalPurpose --throughput-mode provisioned --provisioned-throughput-in-mibps 100 --tags Key=Name,Value=${stack_name}-efs Key=Stack,Value=$stack_name --query 'FileSystemId' --output text --region $aws_region" \
        "Create EFS")
    
    if [[ -z "$efs_id" ]]; then
        log_maintenance "ERROR" "Failed to create EFS"
        return 1
    fi
    
    # Wait for EFS to be available
    log_maintenance "INFO" "Waiting for EFS to be available..."
    aws efs wait file-system-available --file-system-id "$efs_id" --region "$aws_region"
    
    # Get VPC and subnet info
    local vpc_id
    vpc_id=$(safe_aws_command \
        "aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text --region $aws_region" \
        "Get default VPC")
    
    # Get subnets
    local subnet_ids
    subnet_ids=$(safe_aws_command \
        "aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpc_id Name=state,Values=available --query 'Subnets[].SubnetId' --output text --region $aws_region" \
        "Get subnets")
    
    # Create security group for EFS
    local efs_sg_id
    efs_sg_id=$(safe_aws_command \
        "aws ec2 create-security-group --group-name ${stack_name}-efs-sg --description \"EFS security group for $stack_name\" --vpc-id $vpc_id --query 'GroupId' --output text --region $aws_region" \
        "Create EFS security group")
    
    # Add NFS rule to security group
    safe_aws_command \
        "aws ec2 authorize-security-group-ingress --group-id $efs_sg_id --protocol tcp --port 2049 --cidr 10.0.0.0/8 --region $aws_region" \
        "Add NFS rule to security group"
    
    # Create mount targets
    for subnet_id in $subnet_ids; do
        safe_aws_command \
            "aws efs create-mount-target --file-system-id $efs_id --subnet-id $subnet_id --security-groups $efs_sg_id --region $aws_region" \
            "Create mount target in subnet $subnet_id" || true
    done
    
    log_maintenance "SUCCESS" "EFS created: $efs_id"
    echo "$efs_id"
}

# =============================================================================
# PARAMETER STORE FIX OPERATIONS
# =============================================================================

# Fix Parameter Store integration
fix_parameter_store_issues() {
    local stack_name="${MAINTENANCE_STACK_NAME:-GeuseMaker}"
    local aws_region="${MAINTENANCE_AWS_REGION:-us-east-1}"
    
    log_maintenance "INFO" "Setting up Parameter Store integration for stack: $stack_name"
    increment_counter "processed"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would setup Parameter Store integration"
        increment_counter "skipped"
        return 0
    fi
    
    # Create parameter store retrieval script
    local script_path="/home/ubuntu/GeuseMaker/scripts/get-parameters.sh"
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << 'EOF'
#!/usr/bin/env bash

# Parameter Store Integration Script
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-GeuseMaker}"

get_parameter() {
    local param_name="$1"
    local default_value="${2:-}"
    
    # Try to get parameter from AWS Systems Manager
    local value
    value=$(aws ssm get-parameter \
        --name "/aibuildkit/$param_name" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "$default_value")
    
    if [ "$value" = "None" ] || [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Get all parameters and create environment file
{
    echo "# Auto-generated environment file from Parameter Store"
    echo "# Generated on: $(date)"
    echo ""
    
    # PostgreSQL Configuration
    echo "POSTGRES_DB=n8n"
    echo "POSTGRES_USER=n8n"
    echo "POSTGRES_PASSWORD=$(get_parameter 'POSTGRES_PASSWORD' "$(openssl rand -hex 32)")"
    echo ""
    
    # n8n Configuration
    echo "N8N_ENCRYPTION_KEY=$(get_parameter 'n8n/ENCRYPTION_KEY' "$(openssl rand -hex 32)")"
    echo "N8N_USER_MANAGEMENT_JWT_SECRET=$(get_parameter 'n8n/USER_MANAGEMENT_JWT_SECRET' "$(openssl rand -hex 32)")"
    echo "N8N_HOST=0.0.0.0"
    echo "N8N_PORT=5678"
    echo "N8N_PROTOCOL=http"
    echo ""
    
    # API Keys
    echo "OPENAI_API_KEY=$(get_parameter 'OPENAI_API_KEY')"
    echo "ANTHROPIC_API_KEY=$(get_parameter 'ANTHROPIC_API_KEY')"
    echo "DEEPSEEK_API_KEY=$(get_parameter 'DEEPSEEK_API_KEY')"
    echo "GROQ_API_KEY=$(get_parameter 'GROQ_API_KEY')"
    echo "TOGETHER_API_KEY=$(get_parameter 'TOGETHER_API_KEY')"
    echo "MISTRAL_API_KEY=$(get_parameter 'MISTRAL_API_KEY')"
    echo "GEMINI_API_TOKEN=$(get_parameter 'GEMINI_API_TOKEN')"
    echo ""
    
    # n8n Security Settings
    echo "N8N_CORS_ENABLE=$(get_parameter 'n8n/CORS_ENABLE' 'true')"
    echo "N8N_CORS_ALLOWED_ORIGINS=$(get_parameter 'n8n/CORS_ALLOWED_ORIGINS' '*')"
    echo "N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=$(get_parameter 'n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE' 'true')"
    echo ""
    
    # AWS Configuration
    echo "INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo '')"
    echo "INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo '')"
    echo "AWS_DEFAULT_REGION=$AWS_REGION"
    echo ""
    
    # Webhook URL
    local public_ip
    public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'localhost')
    echo "WEBHOOK_URL=$(get_parameter 'WEBHOOK_URL' "http://$public_ip:5678")"
    echo ""
    
    # EFS Configuration
    echo "EFS_DNS=${EFS_DNS:-}"
    
} > /home/ubuntu/GeuseMaker/.env

chmod 600 /home/ubuntu/GeuseMaker/.env
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/.env

echo "Environment file updated from Parameter Store"
EOF
    
    chmod +x "$script_path"
    
    # Run the parameter retrieval
    cd /home/ubuntu/GeuseMaker
    STACK_NAME="$stack_name" AWS_REGION="$aws_region" ./scripts/get-parameters.sh
    
    log_maintenance "SUCCESS" "Parameter Store integration completed"
    increment_counter "fixed"
    return 0
}

# =============================================================================
# DOCKER FIX OPERATIONS
# =============================================================================

# Fix Docker issues
fix_docker_issues() {
    log_maintenance "INFO" "Fixing Docker configuration issues..."
    increment_counter "processed"
    
    # Optimize Docker for limited space
    optimize_docker_for_limited_space
    
    # Fix Docker permissions
    fix_docker_permissions
    
    # Ensure Docker service is running properly
    if ! systemctl is-active --quiet docker; then
        log_maintenance "WARNING" "Docker service not running, attempting to start..."
        if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            sudo systemctl start docker || {
                log_maintenance "ERROR" "Failed to start Docker service"
                increment_counter "failed"
                return 1
            }
        fi
    fi
    
    log_maintenance "SUCCESS" "Docker issues fixed"
    increment_counter "fixed"
    return 0
}

# Optimize Docker for limited space
optimize_docker_for_limited_space() {
    log_maintenance "INFO" "Optimizing Docker configuration for limited disk space..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would optimize Docker configuration"
        return 0
    fi
    
    # Create Docker daemon configuration for space optimization
    sudo mkdir -p /etc/docker
    
    # Backup existing configuration
    if [[ -f /etc/docker/daemon.json ]]; then
        create_timestamped_backup "/etc/docker/daemon.json" "docker-config"
    fi
    
    cat << 'EOF' | sudo tee /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.size=20G"
    ],
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 3,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    }
}
EOF
    
    # Restart Docker to apply configuration
    sudo systemctl restart docker
    
    # Wait for Docker to be ready
    wait_for_service "Docker" 2375 30
    
    log_maintenance "SUCCESS" "Docker optimization completed"
}

# Fix Docker permissions
fix_docker_permissions() {
    log_maintenance "INFO" "Fixing Docker permissions..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would fix Docker permissions"
        return 0
    fi
    
    # Ensure current user is in docker group
    local current_user="${USER:-ubuntu}"
    if ! groups "$current_user" | grep -q docker; then
        sudo usermod -aG docker "$current_user"
        log_maintenance "INFO" "Added $current_user to docker group"
    fi
    
    # Fix socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        sudo chmod 666 /var/run/docker.sock
    fi
    
    log_maintenance "SUCCESS" "Docker permissions fixed"
}

# =============================================================================
# PERMISSIONS FIX OPERATIONS
# =============================================================================

# Fix file permissions
fix_permissions_issues() {
    log_maintenance "INFO" "Fixing file and directory permissions..."
    increment_counter "processed"
    
    local project_root="${MAINTENANCE_PROJECT_ROOT:-/home/ubuntu/GeuseMaker}"
    local user="${USER:-ubuntu}"
    
    if [[ ! -d "$project_root" ]]; then
        log_maintenance "WARNING" "Project root not found: $project_root"
        increment_counter "skipped"
        return 1
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would fix permissions in $project_root"
        increment_counter "skipped"
        return 0
    fi
    
    # Fix ownership
    sudo chown -R "$user:$user" "$project_root"
    
    # Fix directory permissions
    find "$project_root" -type d -exec chmod 755 {} \;
    
    # Fix file permissions
    find "$project_root" -type f -exec chmod 644 {} \;
    
    # Fix script permissions
    find "$project_root" -name "*.sh" -exec chmod 755 {} \;
    
    # Fix .env file permissions
    if [[ -f "$project_root/.env" ]]; then
        chmod 600 "$project_root/.env"
    fi
    
    log_maintenance "SUCCESS" "Permissions fixed for $project_root"
    increment_counter "fixed"
    return 0
}

# =============================================================================
# NETWORK FIX OPERATIONS
# =============================================================================

# Fix network issues
fix_network_issues() {
    log_maintenance "INFO" "Fixing network configuration issues..."
    increment_counter "processed"
    
    # Check and fix DNS resolution
    if ! fix_dns_resolution; then
        increment_counter "failed"
        return 1
    fi
    
    # Check and fix firewall rules
    if ! fix_firewall_rules; then
        increment_counter "failed"
        return 1
    fi
    
    log_maintenance "SUCCESS" "Network issues fixed"
    increment_counter "fixed"
    return 0
}

# Fix DNS resolution
fix_dns_resolution() {
    log_maintenance "INFO" "Checking DNS resolution..."
    
    # Test DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        log_maintenance "WARNING" "DNS resolution issues detected"
        
        if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            # Add Google DNS as fallback
            echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
            echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
        fi
        
        # Re-test
        if nslookup google.com >/dev/null 2>&1; then
            log_maintenance "SUCCESS" "DNS resolution fixed"
            return 0
        else
            log_maintenance "ERROR" "Failed to fix DNS resolution"
            return 1
        fi
    fi
    
    log_maintenance "INFO" "DNS resolution working correctly"
    return 0
}

# Fix firewall rules
fix_firewall_rules() {
    log_maintenance "INFO" "Checking firewall rules..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would check and fix firewall rules"
        return 0
    fi
    
    # Check if ufw is installed and active
    if command -v ufw >/dev/null 2>&1; then
        if sudo ufw status | grep -q "Status: active"; then
            # Ensure required ports are open
            local required_ports=(22 80 443 5678 11434 6333 11235)
            
            for port in "${required_ports[@]}"; do
                sudo ufw allow "$port/tcp" >/dev/null 2>&1 || true
            done
            
            log_maintenance "SUCCESS" "Firewall rules updated"
        fi
    fi
    
    return 0
}

# =============================================================================
# SERVICES FIX OPERATIONS
# =============================================================================

# Fix service issues
fix_services_issues() {
    log_maintenance "INFO" "Fixing service startup and configuration issues..."
    increment_counter "processed"
    
    local services_fixed=0
    
    # Check Docker Compose services
    if [[ -f /home/ubuntu/GeuseMaker/docker-compose.gpu-optimized.yml ]]; then
        cd /home/ubuntu/GeuseMaker
        
        # Get list of services
        local services=$(docker-compose ps --services 2>/dev/null)
        
        for service in $services; do
            local health=$(get_container_health "$service")
            
            if [[ "$health" != "healthy" ]] && [[ "$health" != "running" ]]; then
                log_maintenance "WARNING" "Service $service is $health, attempting to fix..."
                
                if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                    # Restart the service
                    docker-compose restart "$service" >/dev/null 2>&1 || {
                        # If restart fails, try recreating
                        docker-compose up -d --force-recreate "$service" >/dev/null 2>&1 || true
                    }
                    
                    # Wait for service to be ready
                    sleep 10
                    
                    # Re-check health
                    local new_health=$(get_container_health "$service")
                    if [[ "$new_health" == "healthy" ]] || [[ "$new_health" == "running" ]]; then
                        log_maintenance "SUCCESS" "Service $service fixed"
                        ((services_fixed++))
                    else
                        log_maintenance "ERROR" "Failed to fix service $service"
                    fi
                fi
            fi
        done
    fi
    
    if [[ $services_fixed -gt 0 ]]; then
        log_maintenance "SUCCESS" "Fixed $services_fixed services"
        increment_counter "fixed"
        return 0
    else
        log_maintenance "INFO" "No service issues found"
        increment_counter "skipped"
        return 0
    fi
}

# Export all fix functions
export -f fix_deployment_issues
export -f fix_disk_issues
export -f cleanup_docker_space
export -f expand_root_volume
export -f fix_efs_issues
export -f create_efs_for_stack
export -f fix_parameter_store_issues
export -f fix_docker_issues
export -f optimize_docker_for_limited_space
export -f fix_docker_permissions
export -f fix_permissions_issues
export -f fix_network_issues
export -f fix_dns_resolution
export -f fix_firewall_rules
export -f fix_services_issues