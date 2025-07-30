#!/bin/bash
#
# Maintenance Safety Operations Module
# Comprehensive safety checks, warnings, and rollback mechanisms
#

# =============================================================================
# SAFETY CONFIGURATION
# =============================================================================

# Destructive operations that require confirmation
declare -a DESTRUCTIVE_OPERATIONS=(
    "cleanup:aws"
    "cleanup:all"
    "fix:deployment"
    "update:dependencies"
    "update:scripts"
    "rollback:*"
    "restore:*"
)

# Critical files that require extra protection
declare -a CRITICAL_FILES=(
    ".env"
    "docker-compose.yml"
    "docker-compose.gpu-optimized.yml"
    "config/production.yml"
    "scripts/aws-deployment-modular.sh"
    "lib/modules/core/variables.sh"
)

# Safety thresholds
declare -r MAX_CLEANUP_SIZE_GB=10
declare -r MAX_FILES_TO_DELETE=1000
declare -r MIN_FREE_SPACE_GB=5
declare -r BACKUP_RETENTION_DAYS=30

# =============================================================================
# PRE-OPERATION SAFETY CHECKS
# =============================================================================

# Perform comprehensive safety checks before operation
perform_safety_checks() {
    local operation="$1"
    local target="$2"
    
    log_maintenance "INFO" "Performing safety checks for: $operation on $target"
    
    # Check if operation is destructive
    if is_destructive_operation "$operation" "$target"; then
        if ! handle_destructive_operation "$operation" "$target"; then
            return 1
        fi
    fi
    
    # Check system state
    if ! check_system_safety; then
        return 1
    fi
    
    # Check for running services
    if ! check_running_services "$operation"; then
        return 1
    fi
    
    # Check available disk space
    if ! check_disk_space; then
        return 1
    fi
    
    # Verify backups are available
    if [[ "$MAINTENANCE_ROLLBACK" == true ]] && ! verify_backup_availability; then
        return 1
    fi
    
    log_maintenance "SUCCESS" "All safety checks passed"
    return 0
}

# Check if operation is destructive
is_destructive_operation() {
    local operation="$1"
    local target="$2"
    local check="${operation}:${target}"
    
    for destructive in "${DESTRUCTIVE_OPERATIONS[@]}"; do
        if [[ "$check" == $destructive ]] || [[ "$destructive" == *":*" && "$operation" == "${destructive%:*}" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Handle destructive operation with warnings
handle_destructive_operation() {
    local operation="$1"
    local target="$2"
    
    # Display prominent warning
    show_destructive_warning "$operation" "$target"
    
    # Estimate impact
    local impact=$(estimate_operation_impact "$operation" "$target")
    if [[ -n "$impact" ]]; then
        echo ""
        echo "Estimated Impact:"
        echo "$impact"
    fi
    
    # Force backup for destructive operations
    if [[ "$MAINTENANCE_BACKUP" != true ]] && [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
        log_maintenance "WARNING" "Backup is required for destructive operations"
        echo ""
        read -p "Enable automatic backup? (yes/no): " enable_backup
        if [[ "$enable_backup" == "yes" ]]; then
            MAINTENANCE_BACKUP=true
            log_maintenance "INFO" "Automatic backup enabled"
        else
            log_maintenance "ERROR" "Cannot proceed without backup for destructive operation"
            return 1
        fi
    fi
    
    # Get explicit confirmation
    if ! confirm_destructive_operation "$operation" "$target"; then
        log_maintenance "INFO" "Operation cancelled by user"
        return 1
    fi
    
    return 0
}

# Show destructive operation warning
show_destructive_warning() {
    local operation="$1"
    local target="$2"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    ⚠️  DESTRUCTIVE OPERATION ⚠️                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Operation: $operation"
    echo "Target: $target"
    echo ""
    
    case "$operation" in
        cleanup)
            echo "This operation will permanently delete resources."
            echo "Deleted data cannot be recovered without a backup."
            ;;
        fix)
            echo "This operation will modify system configuration."
            echo "Services may be restarted or reconfigured."
            ;;
        update)
            echo "This operation will update system components."
            echo "Compatibility issues may occur."
            ;;
        rollback|restore)
            echo "This operation will restore previous system state."
            echo "Current configuration will be overwritten."
            ;;
    esac
}

# Confirm destructive operation with multiple checks
confirm_destructive_operation() {
    local operation="$1"
    local target="$2"
    
    if [[ "$MAINTENANCE_FORCE" == true ]]; then
        log_maintenance "WARNING" "Force flag set, skipping confirmation"
        return 0
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "DRY RUN mode - no actual changes will be made"
        return 0
    fi
    
    echo ""
    echo "To proceed, you must:"
    echo "1. Type the operation name: $operation"
    echo "2. Type the target name: $target"
    echo "3. Type 'CONFIRM' to proceed"
    echo ""
    
    read -p "Enter operation name: " confirm_op
    if [[ "$confirm_op" != "$operation" ]]; then
        log_maintenance "ERROR" "Operation name mismatch"
        return 1
    fi
    
    read -p "Enter target name: " confirm_target
    if [[ "$confirm_target" != "$target" ]]; then
        log_maintenance "ERROR" "Target name mismatch"
        return 1
    fi
    
    read -p "Type CONFIRM to proceed: " final_confirm
    if [[ "$final_confirm" != "CONFIRM" ]]; then
        log_maintenance "ERROR" "Final confirmation not received"
        return 1
    fi
    
    return 0
}

# =============================================================================
# SYSTEM SAFETY CHECKS
# =============================================================================

# Check overall system safety
check_system_safety() {
    log_maintenance "DEBUG" "Checking system safety..."
    
    # Check if maintenance is already running
    if is_maintenance_running; then
        log_maintenance "ERROR" "Another maintenance operation is already running"
        return 1
    fi
    
    # Check system load
    if ! check_system_load; then
        log_maintenance "WARNING" "System load is high"
        if ! confirm_operation "Proceed with high system load?" "This may impact performance"; then
            return 1
        fi
    fi
    
    # Check critical files integrity
    if ! check_critical_files; then
        log_maintenance "ERROR" "Critical files check failed"
        return 1
    fi
    
    return 0
}

# Check if maintenance is already running
is_maintenance_running() {
    local lockfile="${MAINTENANCE_STATE_FILE}.lock"
    
    if [[ -f "$lockfile" ]]; then
        local pid=$(cat "$lockfile" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Stale lock file
            rm -f "$lockfile"
        fi
    fi
    
    # Create lock file
    echo $$ > "$lockfile"
    return 1
}

# Check system load
check_system_load() {
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "1")
    
    # Check if load is reasonable (less than 2x CPU count)
    local max_load=$((cpu_count * 2))
    if (( $(echo "$load_avg > $max_load" | bc -l 2>/dev/null || echo 0) )); then
        return 1
    fi
    
    return 0
}

# Check critical files
check_critical_files() {
    local all_good=true
    
    for file in "${CRITICAL_FILES[@]}"; do
        local full_path="${MAINTENANCE_PROJECT_ROOT}/${file}"
        if [[ -f "$full_path" ]]; then
            # Check if file is readable and writable
            if [[ ! -r "$full_path" ]] || [[ ! -w "$full_path" ]]; then
                log_maintenance "ERROR" "Critical file not accessible: $file"
                all_good=false
            fi
            
            # Check if file has recent backup
            if [[ "$MAINTENANCE_BACKUP" == true ]]; then
                if ! has_recent_backup "$full_path"; then
                    log_maintenance "WARNING" "No recent backup for critical file: $file"
                fi
            fi
        fi
    done
    
    [[ "$all_good" == true ]]
}

# Check for running services
check_running_services() {
    local operation="$1"
    
    # Skip check for read-only operations
    case "$operation" in
        list|verify|check)
            return 0
            ;;
    esac
    
    log_maintenance "DEBUG" "Checking for running services..."
    
    # Check Docker containers
    local running_containers=$(docker ps -q 2>/dev/null | wc -l)
    if [[ $running_containers -gt 0 ]]; then
        log_maintenance "WARNING" "Found $running_containers running Docker containers"
        
        if [[ "$operation" == "update" ]] || [[ "$operation" == "fix" ]]; then
            echo ""
            echo "Running containers:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
            echo ""
            
            if ! confirm_operation "Proceed with running containers?" "Services may be interrupted"; then
                return 1
            fi
        fi
    fi
    
    return 0
}

# Check disk space
check_disk_space() {
    local available_space_gb=$(df -BG "${MAINTENANCE_PROJECT_ROOT}" | awk 'NR==2 {print $4}' | tr -d 'G')
    
    if [[ $available_space_gb -lt $MIN_FREE_SPACE_GB ]]; then
        log_maintenance "ERROR" "Insufficient disk space: ${available_space_gb}GB available, need at least ${MIN_FREE_SPACE_GB}GB"
        
        # Suggest cleanup if low on space
        echo ""
        echo "Consider running: $0 --operation=cleanup --target=all"
        return 1
    fi
    
    return 0
}

# =============================================================================
# BACKUP SAFETY OPERATIONS
# =============================================================================

# Create safety backup before operation
create_safety_backup() {
    local operation="$1"
    local target="$2"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create safety backup"
        return 0
    fi
    
    if [[ "$MAINTENANCE_BACKUP" != true ]]; then
        return 0
    fi
    
    log_maintenance "INFO" "Creating safety backup before $operation..."
    
    local backup_tag="safety-${operation}-${target}-$(date +%Y%m%d_%H%M%S)"
    local backup_manifest="${MAINTENANCE_BACKUP_DIR}/${backup_tag}/manifest.json"
    
    mkdir -p "${MAINTENANCE_BACKUP_DIR}/${backup_tag}"
    
    # Create backup manifest
    cat > "$backup_manifest" << EOF
{
    "backup_tag": "${backup_tag}",
    "operation": "${operation}",
    "target": "${target}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "backed_up_items": []
}
EOF
    
    # Backup based on operation type
    case "$operation" in
        cleanup)
            backup_before_cleanup "$target" "$backup_tag"
            ;;
        fix)
            backup_before_fix "$target" "$backup_tag"
            ;;
        update)
            backup_before_update "$target" "$backup_tag"
            ;;
    esac
    
    log_maintenance "SUCCESS" "Safety backup created: $backup_tag"
    echo "$backup_tag"
}

# Backup before cleanup operation
backup_before_cleanup() {
    local target="$1"
    local backup_tag="$2"
    
    case "$target" in
        logs)
            # Backup recent logs
            backup_directory "${MAINTENANCE_PROJECT_ROOT}/logs" "$backup_tag" "*.log"
            ;;
        docker)
            # Backup Docker configurations
            backup_docker_state "$backup_tag"
            ;;
        aws)
            # Backup AWS resource list
            backup_aws_resources "$backup_tag"
            ;;
    esac
}

# Backup before fix operation
backup_before_fix() {
    local target="$1"
    local backup_tag="$2"
    
    case "$target" in
        deployment)
            # Backup deployment configurations
            backup_files "$backup_tag" \
                "scripts/aws-deployment-modular.sh" \
                "lib/modules/deployment/*.sh"
            ;;
        docker)
            # Backup Docker files
            backup_files "$backup_tag" \
                "docker-compose*.yml" \
                ".env" \
                "scripts/setup-docker.sh"
            ;;
        permissions)
            # Backup current permissions
            backup_permissions "$backup_tag"
            ;;
    esac
}

# Backup before update operation
backup_before_update() {
    local component="$1"
    local backup_tag="$2"
    
    case "$component" in
        docker)
            # Backup Docker images list
            docker images --format "json" > "${MAINTENANCE_BACKUP_DIR}/${backup_tag}/docker-images.json" 2>/dev/null || true
            ;;
        scripts)
            # Backup all scripts
            backup_directory "${MAINTENANCE_PROJECT_ROOT}/scripts" "$backup_tag" "*.sh"
            backup_directory "${MAINTENANCE_PROJECT_ROOT}/lib" "$backup_tag" "*.sh"
            ;;
    esac
}

# =============================================================================
# ROLLBACK OPERATIONS
# =============================================================================

# Perform rollback from safety backup
perform_safety_rollback() {
    local backup_tag="$1"
    
    if [[ -z "$backup_tag" ]]; then
        # Find most recent safety backup
        backup_tag=$(find "${MAINTENANCE_BACKUP_DIR}" -maxdepth 1 -name "safety-*" -type d | sort -r | head -1 | xargs basename)
    fi
    
    if [[ -z "$backup_tag" ]] || [[ ! -d "${MAINTENANCE_BACKUP_DIR}/${backup_tag}" ]]; then
        log_maintenance "ERROR" "No safety backup found: $backup_tag"
        return 1
    fi
    
    log_maintenance "INFO" "Performing rollback from: $backup_tag"
    
    # Verify backup integrity
    if ! verify_backup_integrity "${MAINTENANCE_BACKUP_DIR}/${backup_tag}"; then
        log_maintenance "ERROR" "Backup integrity check failed"
        return 1
    fi
    
    # Get rollback confirmation
    if ! confirm_operation "Rollback from backup?" "This will restore system to state: $backup_tag"; then
        return 1
    fi
    
    # Perform rollback based on manifest
    local manifest="${MAINTENANCE_BACKUP_DIR}/${backup_tag}/manifest.json"
    if [[ -f "$manifest" ]]; then
        local operation=$(jq -r '.operation' "$manifest")
        local target=$(jq -r '.target' "$manifest")
        
        case "$operation" in
            cleanup)
                rollback_cleanup "$target" "$backup_tag"
                ;;
            fix)
                rollback_fix "$target" "$backup_tag"
                ;;
            update)
                rollback_update "$target" "$backup_tag"
                ;;
        esac
    fi
    
    log_maintenance "SUCCESS" "Rollback completed successfully"
    return 0
}

# =============================================================================
# VALIDATION OPERATIONS
# =============================================================================

# Verify backup availability
verify_backup_availability() {
    local backup_count=$(find "${MAINTENANCE_BACKUP_DIR}" -maxdepth 1 -name "safety-*" -type d 2>/dev/null | wc -l)
    
    if [[ $backup_count -eq 0 ]]; then
        log_maintenance "WARNING" "No safety backups available for rollback"
        
        if [[ "$MAINTENANCE_ROLLBACK" == true ]]; then
            log_maintenance "ERROR" "Rollback requested but no backups available"
            return 1
        fi
    fi
    
    return 0
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_dir="$1"
    
    if [[ ! -f "${backup_dir}/manifest.json" ]]; then
        log_maintenance "ERROR" "Backup manifest not found"
        return 1
    fi
    
    # Verify manifest is valid JSON
    if ! jq empty "${backup_dir}/manifest.json" 2>/dev/null; then
        log_maintenance "ERROR" "Invalid backup manifest"
        return 1
    fi
    
    # Verify backed up files exist
    local backed_up_items=$(jq -r '.backed_up_items[]' "${backup_dir}/manifest.json" 2>/dev/null)
    for item in $backed_up_items; do
        if [[ ! -e "${backup_dir}/${item}" ]]; then
            log_maintenance "ERROR" "Missing backup item: $item"
            return 1
        fi
    done
    
    return 0
}

# Check if file has recent backup
has_recent_backup() {
    local file="$1"
    local max_age_hours="${2:-24}"
    
    local filename=$(basename "$file")
    local recent_backup=$(find "${MAINTENANCE_BACKUP_DIR}" -name "$filename" -type f -mmin -$((max_age_hours * 60)) 2>/dev/null | head -1)
    
    [[ -n "$recent_backup" ]]
}

# =============================================================================
# IMPACT ESTIMATION
# =============================================================================

# Estimate operation impact
estimate_operation_impact() {
    local operation="$1"
    local target="$2"
    
    case "$operation" in
        cleanup)
            estimate_cleanup_impact "$target"
            ;;
        fix)
            estimate_fix_impact "$target"
            ;;
        update)
            estimate_update_impact "$target"
            ;;
    esac
}

# Estimate cleanup impact
estimate_cleanup_impact() {
    local target="$1"
    local impact=""
    
    case "$target" in
        logs)
            local log_size=$(du -sh "${MAINTENANCE_PROJECT_ROOT}/logs" 2>/dev/null | cut -f1)
            impact="- Estimated space to be freed: ${log_size:-unknown}"
            ;;
        docker)
            local image_count=$(docker images -q 2>/dev/null | wc -l)
            local container_count=$(docker ps -aq 2>/dev/null | wc -l)
            local volume_count=$(docker volume ls -q 2>/dev/null | wc -l)
            impact="- Docker images: $image_count\n- Containers: $container_count\n- Volumes: $volume_count"
            ;;
        aws)
            impact="- Will scan for orphaned AWS resources\n- May affect running services"
            ;;
        all)
            impact="- Will clean ALL maintenance targets\n- Comprehensive system cleanup"
            ;;
    esac
    
    echo -e "$impact"
}

# Estimate fix impact
estimate_fix_impact() {
    local target="$1"
    local impact=""
    
    case "$target" in
        deployment)
            impact="- Services may be restarted\n- Configuration will be validated\n- Downtime possible: 1-5 minutes"
            ;;
        docker)
            impact="- Docker daemon may be restarted\n- Running containers may be affected"
            ;;
        permissions)
            impact="- File permissions will be reset\n- May affect service access"
            ;;
    esac
    
    echo -e "$impact"
}

# Estimate update impact
estimate_update_impact() {
    local component="$1"
    local impact=""
    
    case "$component" in
        docker)
            local current_images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | wc -l)
            impact="- Current images: $current_images\n- All images will be updated\n- Download size varies"
            ;;
        dependencies)
            impact="- System packages will be updated\n- Reboot may be required"
            ;;
        scripts)
            impact="- Deployment scripts will be updated\n- Compatibility verification required"
            ;;
    esac
    
    echo -e "$impact"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Backup files with manifest update
backup_files() {
    local backup_tag="$1"
    shift
    local files=("$@")
    
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/${backup_tag}"
    local manifest="${backup_dir}/manifest.json"
    
    for file in "${files[@]}"; do
        if [[ -f "${MAINTENANCE_PROJECT_ROOT}/${file}" ]]; then
            local dir=$(dirname "$file")
            mkdir -p "${backup_dir}/${dir}"
            cp "${MAINTENANCE_PROJECT_ROOT}/${file}" "${backup_dir}/${file}"
            
            # Update manifest
            jq --arg file "$file" '.backed_up_items += [$file]' "$manifest" > "${manifest}.tmp" && mv "${manifest}.tmp" "$manifest"
        fi
    done
}

# Backup directory
backup_directory() {
    local source_dir="$1"
    local backup_tag="$2"
    local pattern="${3:-*}"
    
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/${backup_tag}"
    local relative_path="${source_dir#$MAINTENANCE_PROJECT_ROOT/}"
    
    mkdir -p "${backup_dir}/${relative_path}"
    find "$source_dir" -name "$pattern" -type f -exec cp {} "${backup_dir}/${relative_path}/" \; 2>/dev/null || true
}

# Backup Docker state
backup_docker_state() {
    local backup_tag="$1"
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/${backup_tag}"
    
    mkdir -p "${backup_dir}/docker-state"
    
    # Save Docker state
    docker ps -a --format "json" > "${backup_dir}/docker-state/containers.json" 2>/dev/null || true
    docker images --format "json" > "${backup_dir}/docker-state/images.json" 2>/dev/null || true
    docker volume ls --format "json" > "${backup_dir}/docker-state/volumes.json" 2>/dev/null || true
    docker network ls --format "json" > "${backup_dir}/docker-state/networks.json" 2>/dev/null || true
}

# Backup AWS resources
backup_aws_resources() {
    local backup_tag="$1"
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/${backup_tag}"
    
    mkdir -p "${backup_dir}/aws-resources"
    
    # Save AWS resource lists
    aws ec2 describe-instances --output json > "${backup_dir}/aws-resources/ec2-instances.json" 2>/dev/null || true
    aws ec2 describe-security-groups --output json > "${backup_dir}/aws-resources/security-groups.json" 2>/dev/null || true
    aws efs describe-file-systems --output json > "${backup_dir}/aws-resources/efs-filesystems.json" 2>/dev/null || true
}

# Backup file permissions
backup_permissions() {
    local backup_tag="$1"
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/${backup_tag}"
    
    # Save current permissions
    find "${MAINTENANCE_PROJECT_ROOT}" -type f -exec stat -c "%n %a %U %G" {} \; > "${backup_dir}/permissions.txt" 2>/dev/null || \
    find "${MAINTENANCE_PROJECT_ROOT}" -type f -exec stat -f "%N %Mp%Lp %Su %Sg" {} \; > "${backup_dir}/permissions.txt" 2>/dev/null || true
}

# =============================================================================
# CLEANUP OPERATIONS
# =============================================================================

# Cleanup old safety backups
cleanup_old_safety_backups() {
    log_maintenance "INFO" "Cleaning up old safety backups..."
    
    local cutoff_date=$(date -d "${BACKUP_RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || \
                        date -v -${BACKUP_RETENTION_DAYS}d +%Y%m%d 2>/dev/null)
    
    local removed_count=0
    for backup_dir in "${MAINTENANCE_BACKUP_DIR}"/safety-*; do
        if [[ -d "$backup_dir" ]]; then
            local backup_date=$(basename "$backup_dir" | grep -oE '[0-9]{8}' | head -1)
            
            if [[ "$backup_date" < "$cutoff_date" ]]; then
                if rm -rf "$backup_dir"; then
                    ((removed_count++))
                fi
            fi
        fi
    done
    
    log_maintenance "INFO" "Removed $removed_count old safety backups"
}

# Remove maintenance lock
cleanup_maintenance_lock() {
    local lockfile="${MAINTENANCE_STATE_FILE}.lock"
    
    if [[ -f "$lockfile" ]]; then
        local pid=$(cat "$lockfile" 2>/dev/null)
        if [[ "$pid" == "$$" ]]; then
            rm -f "$lockfile"
        fi
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f perform_safety_checks
export -f is_destructive_operation
export -f handle_destructive_operation
export -f show_destructive_warning
export -f confirm_destructive_operation
export -f check_system_safety
export -f is_maintenance_running
export -f check_system_load
export -f check_critical_files
export -f check_running_services
export -f check_disk_space
export -f create_safety_backup
export -f perform_safety_rollback
export -f verify_backup_availability
export -f verify_backup_integrity
export -f has_recent_backup
export -f estimate_operation_impact
export -f cleanup_old_safety_backups
export -f cleanup_maintenance_lock