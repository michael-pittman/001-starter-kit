#!/bin/bash
#
# Maintenance Utilities Module
# Shared utility functions for all maintenance operations
#

# =============================================================================
# LOGGING AND OUTPUT UTILITIES
# =============================================================================

# Enhanced logging with file output
log_maintenance() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file if available
    if [[ -n "${MAINTENANCE_LOG_FILE:-}" ]] && [[ -w "$(dirname "${MAINTENANCE_LOG_FILE}")" ]]; then
        echo "[$timestamp] [$level] $message" >> "$MAINTENANCE_LOG_FILE"
    fi
    
    # Log to console with colors
    case "$level" in
        "INFO")
            log_info "$message"
            ;;
        "SUCCESS")
            log_success "$message"
            ;;
        "WARNING")
            log_warning "$message"
            ;;
        "ERROR")
            log_error "$message"
            ;;
        "DEBUG")
            [[ "$MAINTENANCE_VERBOSE" == true ]] && log_debug "$message"
            ;;
    esac
}

# Health check result formatter
check_result() {
    local service="$1"
    local status="$2"
    local details="$3"
    
    if [[ "$status" == "healthy" ]]; then
        log_success "✅ $service: HEALTHY - $details"
        echo "✅ $service: HEALTHY - $details" >> "${HEALTH_REPORT:-/dev/null}"
    else
        log_error "❌ $service: UNHEALTHY - $details"
        echo "❌ $service: UNHEALTHY - $details" >> "${HEALTH_REPORT:-/dev/null}"
        OVERALL_HEALTH=false
    fi
}

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local task="$3"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))
    
    printf "\r[%${filled}s%${empty}s] %d%% - %s" | tr ' ' '=' | tr ' ' '-'
    printf " %d%% - %s" "$percentage" "$task"
    
    [[ $current -eq $total ]] && echo ""
}

# =============================================================================
# BACKUP AND ROLLBACK UTILITIES
# =============================================================================

# Create timestamped backup
create_timestamped_backup() {
    local source="$1"
    local backup_type="${2:-file}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${MAINTENANCE_BACKUP_DIR}/${backup_type}/${timestamp}"
    
    mkdir -p "$backup_path"
    
    if [[ -e "$source" ]]; then
        log_maintenance "INFO" "Creating backup of $source"
        
        if [[ "$MAINTENANCE_COMPRESS" == true ]]; then
            tar -czf "${backup_path}/backup.tar.gz" -C "$(dirname "$source")" "$(basename "$source")"
            echo "${backup_path}/backup.tar.gz"
        else
            cp -r "$source" "${backup_path}/"
            echo "${backup_path}/$(basename "$source")"
        fi
    else
        log_maintenance "WARNING" "Source not found for backup: $source"
        return 1
    fi
}

# Rollback from backup
rollback_from_backup() {
    local backup_path="$1"
    local target="$2"
    
    if [[ ! -e "$backup_path" ]]; then
        log_maintenance "ERROR" "Backup not found: $backup_path"
        return 1
    fi
    
    log_maintenance "INFO" "Rolling back from: $backup_path"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        tar -xzf "$backup_path" -C "$(dirname "$target")"
    else
        cp -r "$backup_path" "$target"
    fi
    
    log_maintenance "SUCCESS" "Rollback completed"
}

# =============================================================================
# SAFETY CHECK UTILITIES
# =============================================================================

# Confirm destructive operation
confirm_operation() {
    local operation="$1"
    local details="$2"
    
    if [[ "$MAINTENANCE_FORCE" == true ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: $operation"
    echo "Details: $details"
    echo ""
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        echo "This is a DRY RUN - no changes will be made."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    [[ "$confirm" == "yes" ]]
}

# Check if operation is safe
is_operation_safe() {
    local operation="$1"
    
    # Check if critical services are running
    local critical_services=("postgres" "n8n")
    
    for service in "${critical_services[@]}"; do
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${service}$"; then
            if [[ "$operation" == "cleanup_docker" ]] || [[ "$operation" == "fix_docker" ]]; then
                log_maintenance "WARNING" "Critical service $service is running"
                return 1
            fi
        fi
    done
    
    return 0
}

# =============================================================================
# AWS UTILITIES
# =============================================================================

# Safe AWS command execution
safe_aws_command() {
    local command="$1"
    local description="$2"
    local retries="${3:-3}"
    
    local attempt=1
    local output
    local exit_code
    
    while [[ $attempt -le $retries ]]; do
        if [[ "$MAINTENANCE_VERBOSE" == true ]]; then
            log_maintenance "DEBUG" "Executing AWS command (attempt $attempt): $command"
        fi
        
        output=$(eval "$command" 2>&1) && exit_code=0 || exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo "$output"
            return 0
        else
            log_maintenance "WARNING" "$description failed (attempt $attempt): $output"
            ((attempt++))
            [[ $attempt -le $retries ]] && sleep 2
        fi
    done
    
    log_maintenance "ERROR" "$description failed after $retries attempts"
    return 1
}

# Get AWS resource tags
get_resource_tags() {
    local resource_type="$1"
    local resource_id="$2"
    local tag_key="$3"
    
    case "$resource_type" in
        "instance")
            safe_aws_command "aws ec2 describe-tags --filters Name=resource-id,Values=$resource_id Name=key,Values=$tag_key --query 'Tags[0].Value' --output text --region $MAINTENANCE_AWS_REGION" \
                "Get $tag_key tag for instance $resource_id"
            ;;
        "efs")
            safe_aws_command "aws efs describe-file-systems --file-system-id $resource_id --query 'FileSystems[0].Tags[?Key==\`$tag_key\`].Value' --output text --region $MAINTENANCE_AWS_REGION" \
                "Get $tag_key tag for EFS $resource_id"
            ;;
        *)
            log_maintenance "ERROR" "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# =============================================================================
# DOCKER UTILITIES
# =============================================================================

# Get Docker container health
get_container_health() {
    local container="$1"
    
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        echo "not_running"
        return 1
    fi
    
    local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    
    case "$health" in
        "healthy")
            echo "healthy"
            return 0
            ;;
        "unhealthy")
            echo "unhealthy"
            return 1
            ;;
        "starting")
            echo "starting"
            return 2
            ;;
        *)
            # No health check defined
            if docker exec "$container" echo "alive" >/dev/null 2>&1; then
                echo "running"
                return 0
            else
                echo "error"
                return 1
            fi
            ;;
    esac
}

# Calculate Docker space usage
calculate_docker_usage() {
    local usage_info=""
    
    # Images
    local images_size=$(docker images --format "table {{.Size}}" | tail -n +2 | awk '{sum+=$1} END {print sum}' 2>/dev/null || echo "0")
    usage_info+="Images: $(numfmt --to=iec $images_size 2>/dev/null || echo "${images_size} bytes")\n"
    
    # Containers
    local containers_size=$(docker ps -as --format "table {{.Size}}" | tail -n +2 | awk '{sum+=$1} END {print sum}' 2>/dev/null || echo "0")
    usage_info+="Containers: $(numfmt --to=iec $containers_size 2>/dev/null || echo "${containers_size} bytes")\n"
    
    # Volumes
    local volumes_size=$(docker system df --format "table {{.Size}}" | grep "Local Volumes" | awk '{print $3}' 2>/dev/null || echo "0")
    usage_info+="Volumes: $volumes_size\n"
    
    echo -e "$usage_info"
}

# =============================================================================
# SYSTEM UTILITIES
# =============================================================================

# Get system resource usage
get_system_resources() {
    local resource="$1"
    
    case "$resource" in
        "cpu")
            # Get CPU usage percentage
            top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
            ;;
        "memory")
            # Get memory usage percentage
            free -m | awk 'NR==2{printf "%.1f", $3*100/$2}'
            ;;
        "disk")
            # Get disk usage for root
            df -h / | awk 'NR==2{print $5}' | sed 's/%//'
            ;;
        "disk_available")
            # Get available disk space in GB
            df -BG / | awk 'NR==2{print $4}' | sed 's/G//'
            ;;
        "load")
            # Get system load average
            uptime | awk -F'load average:' '{print $2}'
            ;;
    esac
}

# Check if sufficient resources available
check_resource_availability() {
    local min_disk_gb="${1:-5}"
    local min_memory_percent="${2:-20}"
    
    local disk_available=$(get_system_resources "disk_available")
    local memory_usage=$(get_system_resources "memory")
    local memory_available=$((100 - ${memory_usage%.*}))
    
    if [[ $disk_available -lt $min_disk_gb ]]; then
        log_maintenance "WARNING" "Low disk space: ${disk_available}GB available (minimum: ${min_disk_gb}GB)"
        return 1
    fi
    
    if [[ $memory_available -lt $min_memory_percent ]]; then
        log_maintenance "WARNING" "Low memory: ${memory_available}% available (minimum: ${min_memory_percent}%)"
        return 1
    fi
    
    return 0
}

# =============================================================================
# FILE SYSTEM UTILITIES
# =============================================================================

# Find old files
find_old_files() {
    local directory="$1"
    local days="$2"
    local pattern="${3:-*}"
    
    find "$directory" -name "$pattern" -type f -mtime +"$days" 2>/dev/null
}

# Calculate directory size
get_directory_size() {
    local directory="$1"
    local human_readable="${2:-false}"
    
    if [[ ! -d "$directory" ]]; then
        echo "0"
        return
    fi
    
    if [[ "$human_readable" == true ]]; then
        du -sh "$directory" 2>/dev/null | cut -f1
    else
        du -sb "$directory" 2>/dev/null | cut -f1
    fi
}

# Safe file deletion with backup
safe_delete_file() {
    local file="$1"
    local reason="${2:-maintenance}"
    
    if [[ ! -e "$file" ]]; then
        return 0
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would delete: $file ($reason)"
        return 0
    fi
    
    # Create backup if requested
    if [[ "$MAINTENANCE_BACKUP" == true ]]; then
        local backup_path=$(create_timestamped_backup "$file" "deleted-files")
        log_maintenance "INFO" "Backed up to: $backup_path"
    fi
    
    # Delete the file
    if rm -rf "$file"; then
        log_maintenance "SUCCESS" "Deleted: $file ($reason)"
        increment_counter "fixed"
    else
        log_maintenance "ERROR" "Failed to delete: $file"
        increment_counter "failed"
        return 1
    fi
}

# =============================================================================
# VALIDATION UTILITIES
# =============================================================================

# Validate JSON file
validate_json() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_maintenance "ERROR" "JSON file not found: $file"
        return 1
    fi
    
    if jq empty "$file" 2>/dev/null; then
        log_maintenance "SUCCESS" "Valid JSON: $file"
        return 0
    else
        log_maintenance "ERROR" "Invalid JSON: $file"
        return 1
    fi
}

# Validate YAML file
validate_yaml() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_maintenance "ERROR" "YAML file not found: $file"
        return 1
    fi
    
    # Simple YAML validation using Python if available
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log_maintenance "SUCCESS" "Valid YAML: $file"
            return 0
        else
            log_maintenance "ERROR" "Invalid YAML: $file"
            return 1
        fi
    else
        # Basic syntax check
        if grep -E '^\s*-\s+\w+:|^\s*\w+:\s*' "$file" >/dev/null; then
            log_maintenance "SUCCESS" "Basic YAML syntax OK: $file"
            return 0
        else
            log_maintenance "ERROR" "Invalid YAML syntax: $file"
            return 1
        fi
    fi
}

# Validate shell script
validate_shell_script() {
    local script="$1"
    
    if [[ ! -f "$script" ]]; then
        log_maintenance "ERROR" "Script not found: $script"
        return 1
    fi
    
    # Check bash syntax
    if bash -n "$script" 2>/dev/null; then
        log_maintenance "SUCCESS" "Valid bash syntax: $script"
        
        # Run shellcheck if available
        if command -v shellcheck >/dev/null 2>&1; then
            if shellcheck "$script" 2>/dev/null; then
                log_maintenance "SUCCESS" "ShellCheck passed: $script"
            else
                log_maintenance "WARNING" "ShellCheck warnings: $script"
            fi
        fi
        
        return 0
    else
        log_maintenance "ERROR" "Invalid bash syntax: $script"
        return 1
    fi
}

# =============================================================================
# NETWORK UTILITIES
# =============================================================================

# Check port availability
check_port() {
    local port="$1"
    local host="${2:-localhost}"
    
    if nc -z "$host" "$port" 2>/dev/null; then
        echo "open"
        return 0
    else
        echo "closed"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service="$1"
    local port="$2"
    local timeout="${3:-60}"
    local host="${4:-localhost}"
    
    local elapsed=0
    
    log_maintenance "INFO" "Waiting for $service on $host:$port..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if check_port "$port" "$host" >/dev/null; then
            log_maintenance "SUCCESS" "$service is ready"
            return 0
        fi
        
        sleep 2
        ((elapsed += 2))
        show_progress "$elapsed" "$timeout" "Waiting for $service"
    done
    
    log_maintenance "ERROR" "$service failed to start within ${timeout}s"
    return 1
}

# =============================================================================
# EXPORT UTILITIES
# =============================================================================

# Export all utility functions
export -f log_maintenance
export -f check_result
export -f show_progress
export -f create_timestamped_backup
export -f rollback_from_backup
export -f confirm_operation
export -f is_operation_safe
export -f safe_aws_command
export -f get_resource_tags
export -f get_container_health
export -f calculate_docker_usage
export -f get_system_resources
export -f check_resource_availability
export -f find_old_files
export -f get_directory_size
export -f safe_delete_file
export -f validate_json
export -f validate_yaml
export -f validate_shell_script
export -f check_port
export -f wait_for_service