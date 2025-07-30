#!/bin/bash
#
# Maintenance Backup Operations Module
# Contains all backup and restore operations
#

# Backup configuration
declare -r BACKUP_VERSION="1.0.0"
declare -r BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
declare -r BACKUP_ROOT="${MAINTENANCE_BACKUP_DIR:-${MAINTENANCE_PROJECT_ROOT}/backup}"
declare -r BACKUP_CURRENT="${BACKUP_ROOT}/${BACKUP_TIMESTAMP}"
declare -r BACKUP_METADATA="${BACKUP_CURRENT}/backup-metadata.json"
declare -r BACKUP_CHECKSUM="${BACKUP_CURRENT}/backup-checksum.sha256"
declare -r BACKUP_MANIFEST="${BACKUP_CURRENT}/backup-manifest.txt"

# Default backup scope
declare -a BACKUP_SCOPE=(
    "scripts/"
    "lib/"
    "config/"
    "docs/"
    "tests/"
    "Makefile"
    "README.md"
    "CLAUDE.md"
    "deploy.sh"
    "docker-compose*.yml"
    ".env.template"
)

# =============================================================================
# BACKUP CREATION OPERATIONS
# =============================================================================

# Create backup (main operation)
backup_create() {
    log_maintenance "INFO" "Creating backup..."
    increment_counter "processed"
    
    # Initialize backup directory
    if ! init_backup_directory; then
        increment_counter "failed"
        return 1
    fi
    
    # Create backup metadata
    if ! create_backup_metadata; then
        increment_counter "failed"
        return 1
    fi
    
    # Perform backup based on type
    local backup_type="${BACKUP_TYPE:-full}"
    local backup_result=0
    
    case "$backup_type" in
        full)
            create_full_backup || backup_result=$?
            ;;
        incremental)
            create_incremental_backup || backup_result=$?
            ;;
        selective)
            create_selective_backup || backup_result=$?
            ;;
        *)
            log_maintenance "ERROR" "Unknown backup type: $backup_type"
            backup_result=1
            ;;
    esac
    
    if [[ $backup_result -eq 0 ]]; then
        # Verify backup
        if verify_backup_integrity; then
            log_maintenance "SUCCESS" "Backup created and verified: ${BACKUP_CURRENT}"
            increment_counter "fixed"
            
            # Create latest symlink
            ln -sfn "${BACKUP_CURRENT}" "${BACKUP_ROOT}/latest"
            
            # Show backup summary
            show_backup_summary
            
            return 0
        else
            log_maintenance "ERROR" "Backup verification failed"
            increment_counter "failed"
            return 1
        fi
    else
        log_maintenance "ERROR" "Backup creation failed"
        increment_counter "failed"
        return 1
    fi
}

# Initialize backup directory
init_backup_directory() {
    log_maintenance "INFO" "Initializing backup directory: ${BACKUP_CURRENT}"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create backup directory"
        return 0
    fi
    
    # Create backup directory structure
    mkdir -p "${BACKUP_CURRENT}"/{files,database,configs,state} || {
        log_maintenance "ERROR" "Failed to create backup directory"
        return 1
    }
    
    return 0
}

# Create backup metadata
create_backup_metadata() {
    log_maintenance "INFO" "Creating backup metadata..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create backup metadata"
        return 0
    fi
    
    # Gather system information
    local hostname=$(hostname)
    local username=$(whoami)
    local os_info=$(uname -s)
    local os_version=$(uname -r)
    
    # Create metadata JSON
    cat > "${BACKUP_METADATA}" << EOF
{
    "backup_info": {
        "version": "${BACKUP_VERSION}",
        "timestamp": "${BACKUP_TIMESTAMP}",
        "type": "${BACKUP_TYPE:-full}",
        "compression": ${MAINTENANCE_COMPRESS},
        "project_root": "${MAINTENANCE_PROJECT_ROOT}"
    },
    "system_info": {
        "hostname": "${hostname}",
        "user": "${username}",
        "bash_version": "${BASH_VERSION}",
        "os": "${os_info}",
        "os_version": "${os_version}"
    },
    "stack_info": {
        "stack_name": "${MAINTENANCE_STACK_NAME:-}",
        "aws_region": "${MAINTENANCE_AWS_REGION:-}"
    },
    "backup_scope": $(printf '%s\n' "${BACKUP_SCOPE[@]}" | jq -R . | jq -s .),
    "backup_size": null,
    "backup_checksum": null,
    "file_count": null,
    "compression_ratio": null
}
EOF
    
    return 0
}

# Create full backup
create_full_backup() {
    log_maintenance "INFO" "Creating full backup..."
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create full backup"
        show_backup_preview
        return 0
    fi
    
    local backup_archive="${BACKUP_CURRENT}/backup-${BACKUP_TIMESTAMP}.tar"
    local temp_dir="${BACKUP_CURRENT}/temp"
    local file_count=0
    
    # Create temporary directory for backup
    mkdir -p "${temp_dir}"
    
    # Create manifest file
    echo "Backup Manifest - ${BACKUP_TIMESTAMP}" > "${BACKUP_MANIFEST}"
    echo "Type: Full Backup" >> "${BACKUP_MANIFEST}"
    echo "Created: $(date)" >> "${BACKUP_MANIFEST}"
    echo "" >> "${BACKUP_MANIFEST}"
    echo "Files included:" >> "${BACKUP_MANIFEST}"
    
    # Copy files to backup
    for item in "${BACKUP_SCOPE[@]}"; do
        local source="${MAINTENANCE_PROJECT_ROOT}/${item}"
        
        if [[ -e "$source" ]]; then
            log_maintenance "INFO" "Backing up: ${item}"
            
            # Copy preserving structure
            if [[ -d "$source" ]]; then
                mkdir -p "${temp_dir}/$(dirname "$item")"
                cp -r "$source" "${temp_dir}/$(dirname "$item")/"
                
                # Add to manifest
                find "$source" -type f | while read -r file; do
                    echo "${file#$MAINTENANCE_PROJECT_ROOT/}" >> "${BACKUP_MANIFEST}"
                    ((file_count++))
                done
            else
                mkdir -p "${temp_dir}/$(dirname "$item")"
                cp "$source" "${temp_dir}/${item}"
                echo "$item" >> "${BACKUP_MANIFEST}"
                ((file_count++))
            fi
        else
            log_maintenance "WARNING" "Item not found: ${item}"
        fi
    done
    
    # Backup environment file if exists (without sensitive data)
    if [[ -f "${MAINTENANCE_PROJECT_ROOT}/.env" ]]; then
        log_maintenance "INFO" "Backing up environment file (sanitized)..."
        sanitize_env_file "${MAINTENANCE_PROJECT_ROOT}/.env" "${temp_dir}/.env.sanitized"
        echo ".env.sanitized" >> "${BACKUP_MANIFEST}"
    fi
    
    # Backup Docker volumes if requested
    if [[ "${BACKUP_DOCKER_VOLUMES:-false}" == true ]]; then
        backup_docker_volumes "${BACKUP_CURRENT}/docker-volumes"
    fi
    
    # Create archive
    log_maintenance "INFO" "Creating archive..."
    tar -cf "${backup_archive}" -C "${temp_dir}" . || {
        log_maintenance "ERROR" "Failed to create backup archive"
        rm -rf "${temp_dir}"
        return 1
    }
    
    # Compress if requested
    if [[ "$MAINTENANCE_COMPRESS" == true ]]; then
        log_maintenance "INFO" "Compressing backup..."
        gzip "${backup_archive}"
        backup_archive="${backup_archive}.gz"
    fi
    
    # Calculate checksum
    log_maintenance "INFO" "Calculating checksum..."
    sha256sum "${backup_archive}" > "${BACKUP_CHECKSUM}"
    
    # Update metadata
    local backup_size=$(stat -f%z "${backup_archive}" 2>/dev/null || stat -c%s "${backup_archive}" 2>/dev/null || echo "0")
    local checksum=$(cat "${BACKUP_CHECKSUM}" | cut -d' ' -f1)
    
    # Calculate compression ratio if compressed
    local compression_ratio="1.0"
    if [[ "$MAINTENANCE_COMPRESS" == true ]]; then
        local uncompressed_size=$(gzip -l "${backup_archive}" | tail -1 | awk '{print $2}')
        if [[ $uncompressed_size -gt 0 ]]; then
            compression_ratio=$(awk "BEGIN {printf \"%.2f\", $backup_size / $uncompressed_size}")
        fi
    fi
    
    # Update metadata with final information
    jq --arg size "${backup_size}" \
       --arg checksum "${checksum}" \
       --arg count "${file_count}" \
       --arg ratio "${compression_ratio}" \
       '.backup_size = $size | 
        .backup_checksum = $checksum | 
        .file_count = $count | 
        .compression_ratio = $ratio' \
       "${BACKUP_METADATA}" > "${BACKUP_METADATA}.tmp" && \
    mv "${BACKUP_METADATA}.tmp" "${BACKUP_METADATA}"
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    log_maintenance "SUCCESS" "Full backup created: ${backup_archive}"
    return 0
}

# Create incremental backup
create_incremental_backup() {
    log_maintenance "INFO" "Creating incremental backup..."
    
    # Find the latest full backup
    local latest_full=$(find "${BACKUP_ROOT}" -name "backup-*.tar*" -type f | \
                        xargs ls -t 2>/dev/null | \
                        head -1)
    
    if [[ -z "$latest_full" ]]; then
        log_maintenance "WARNING" "No previous backup found, creating full backup instead"
        BACKUP_TYPE="full"
        create_full_backup
        return $?
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create incremental backup based on: $latest_full"
        return 0
    fi
    
    # TODO: Implement incremental backup logic
    log_maintenance "WARNING" "Incremental backup not fully implemented, creating full backup"
    BACKUP_TYPE="full"
    create_full_backup
}

# Create selective backup
create_selective_backup() {
    log_maintenance "INFO" "Creating selective backup..."
    
    # Use custom backup scope if provided
    if [[ -n "${SELECTIVE_BACKUP_ITEMS:-}" ]]; then
        BACKUP_SCOPE=($SELECTIVE_BACKUP_ITEMS)
    fi
    
    create_full_backup
}

# Sanitize environment file
sanitize_env_file() {
    local source="$1"
    local dest="$2"
    
    # Copy file but redact sensitive values
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" ]] || [[ "$key" =~ ^[[:space:]]*# ]] && echo "$key" && continue
        
        # Redact sensitive values
        case "$key" in
            *PASSWORD*|*SECRET*|*KEY*|*TOKEN*)
                echo "${key}=<REDACTED>"
                ;;
            *)
                echo "${key}=${value}"
                ;;
        esac
    done < "$source" > "$dest"
}

# Backup Docker volumes
backup_docker_volumes() {
    local volume_backup_dir="$1"
    
    log_maintenance "INFO" "Backing up Docker volumes..."
    
    mkdir -p "$volume_backup_dir"
    
    # Get list of volumes
    local volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(postgres|n8n|qdrant)" || true)
    
    for volume in $volumes; do
        log_maintenance "INFO" "Backing up volume: $volume"
        
        # Create volume backup using temporary container
        docker run --rm \
            -v "$volume:/source:ro" \
            -v "$volume_backup_dir:/backup" \
            alpine tar -czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null || {
            log_maintenance "WARNING" "Failed to backup volume: $volume"
        }
    done
}

# Show backup preview
show_backup_preview() {
    echo "Backup preview:"
    echo "  Type: ${BACKUP_TYPE:-full}"
    echo "  Destination: ${BACKUP_CURRENT}"
    echo "  Compression: ${MAINTENANCE_COMPRESS}"
    echo ""
    echo "Items to backup:"
    
    local total_size=0
    for item in "${BACKUP_SCOPE[@]}"; do
        local source="${MAINTENANCE_PROJECT_ROOT}/${item}"
        if [[ -e "$source" ]]; then
            local size=$(get_directory_size "$source" true)
            echo "  - $item ($size)"
            
            # Add to total
            local size_bytes=$(get_directory_size "$source")
            ((total_size += size_bytes))
        else
            echo "  - $item (not found)"
        fi
    done
    
    echo ""
    echo "Estimated backup size: $(numfmt --to=iec $total_size 2>/dev/null || echo "${total_size} bytes")"
}

# Show backup summary
show_backup_summary() {
    if [[ -f "${BACKUP_METADATA}" ]]; then
        echo ""
        echo "Backup Summary:"
        echo "==============="
        
        local backup_size=$(jq -r '.backup_size' "${BACKUP_METADATA}")
        local file_count=$(jq -r '.file_count' "${BACKUP_METADATA}")
        local compression_ratio=$(jq -r '.compression_ratio' "${BACKUP_METADATA}")
        
        echo "Location: ${BACKUP_CURRENT}"
        echo "Files backed up: ${file_count}"
        echo "Backup size: $(numfmt --to=iec ${backup_size} 2>/dev/null || echo "${backup_size} bytes")"
        
        if [[ "$MAINTENANCE_COMPRESS" == true ]]; then
            echo "Compression ratio: ${compression_ratio}"
        fi
        
        echo ""
    fi
}

# =============================================================================
# BACKUP RESTORE OPERATIONS
# =============================================================================

# Restore backup (main operation)
backup_restore() {
    local backup_timestamp="${1:-latest}"
    
    log_maintenance "INFO" "Restoring backup..."
    increment_counter "processed"
    
    # Find backup to restore
    local restore_dir
    if [[ "$backup_timestamp" == "latest" ]]; then
        restore_dir="${BACKUP_ROOT}/latest"
        if [[ ! -L "$restore_dir" ]]; then
            # Find most recent backup
            restore_dir=$(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -1)
        fi
    else
        restore_dir="${BACKUP_ROOT}/${backup_timestamp}"
    fi
    
    if [[ ! -d "$restore_dir" ]]; then
        log_maintenance "ERROR" "Backup not found: $backup_timestamp"
        increment_counter "failed"
        return 1
    fi
    
    # Find backup archive
    local backup_archive=$(find "$restore_dir" -name "backup-*.tar*" -type f | head -1)
    
    if [[ ! -f "$backup_archive" ]]; then
        log_maintenance "ERROR" "Backup archive not found in: $restore_dir"
        increment_counter "failed"
        return 1
    fi
    
    log_maintenance "INFO" "Found backup: $backup_archive"
    
    # Verify backup before restore
    local checksum_file="${restore_dir}/backup-checksum.sha256"
    if [[ -f "$checksum_file" ]]; then
        log_maintenance "INFO" "Verifying backup integrity..."
        
        if ! (cd "$restore_dir" && sha256sum -c "$checksum_file" >/dev/null 2>&1); then
            log_maintenance "ERROR" "Backup integrity check failed"
            increment_counter "failed"
            return 1
        fi
        
        log_maintenance "SUCCESS" "Backup integrity verified"
    else
        log_maintenance "WARNING" "No checksum file found, skipping integrity check"
    fi
    
    # Confirm restore
    if ! confirm_operation "Restore from backup?" "This will overwrite current files with backup from $backup_timestamp"; then
        log_maintenance "INFO" "Restore cancelled"
        increment_counter "skipped"
        return 0
    fi
    
    # Create pre-restore backup
    log_maintenance "INFO" "Creating backup of current state before restore..."
    local pre_restore_backup="${BACKUP_ROOT}/pre-restore-${BACKUP_TIMESTAMP}"
    mkdir -p "$pre_restore_backup"
    
    # Quick backup of current state
    for item in "${BACKUP_SCOPE[@]}"; do
        local source="${MAINTENANCE_PROJECT_ROOT}/${item}"
        if [[ -e "$source" ]]; then
            cp -r "$source" "$pre_restore_backup/" 2>/dev/null || true
        fi
    done
    
    # Perform restore
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would restore from: $backup_archive"
        show_restore_preview "$restore_dir"
        return 0
    fi
    
    log_maintenance "INFO" "Extracting backup..."
    
    # Extract based on compression
    if [[ "$backup_archive" == *.gz ]]; then
        tar -xzf "$backup_archive" -C "${MAINTENANCE_PROJECT_ROOT}" || {
            log_maintenance "ERROR" "Failed to extract backup"
            increment_counter "failed"
            return 1
        }
    else
        tar -xf "$backup_archive" -C "${MAINTENANCE_PROJECT_ROOT}" || {
            log_maintenance "ERROR" "Failed to extract backup"
            increment_counter "failed"
            return 1
        }
    fi
    
    # Restore Docker volumes if present
    local volume_backup_dir="${restore_dir}/docker-volumes"
    if [[ -d "$volume_backup_dir" ]]; then
        restore_docker_volumes "$volume_backup_dir"
    fi
    
    # Fix permissions
    fix_restored_permissions
    
    log_maintenance "SUCCESS" "Restore completed successfully from backup: $backup_timestamp"
    log_maintenance "INFO" "Pre-restore backup saved at: $pre_restore_backup"
    
    increment_counter "fixed"
    return 0
}

# Show restore preview
show_restore_preview() {
    local restore_dir="$1"
    local metadata_file="${restore_dir}/backup-metadata.json"
    
    echo "Restore preview:"
    
    if [[ -f "$metadata_file" ]]; then
        local backup_type=$(jq -r '.backup_info.type' "$metadata_file")
        local backup_time=$(jq -r '.backup_info.timestamp' "$metadata_file")
        local file_count=$(jq -r '.file_count' "$metadata_file")
        local backup_size=$(jq -r '.backup_size' "$metadata_file")
        
        echo "  Backup type: $backup_type"
        echo "  Backup time: $backup_time"
        echo "  Files to restore: $file_count"
        echo "  Backup size: $(numfmt --to=iec ${backup_size} 2>/dev/null || echo "${backup_size} bytes")"
    fi
    
    if [[ -f "${restore_dir}/backup-manifest.txt" ]]; then
        echo ""
        echo "Files that will be restored:"
        head -20 "${restore_dir}/backup-manifest.txt" | sed 's/^/  - /'
        
        local total_files=$(wc -l < "${restore_dir}/backup-manifest.txt")
        if [[ $total_files -gt 20 ]]; then
            echo "  ... and $((total_files - 20)) more files"
        fi
    fi
}

# Restore Docker volumes
restore_docker_volumes() {
    local volume_backup_dir="$1"
    
    log_maintenance "INFO" "Restoring Docker volumes..."
    
    for volume_backup in "$volume_backup_dir"/*.tar.gz; do
        if [[ -f "$volume_backup" ]]; then
            local volume_name=$(basename "$volume_backup" .tar.gz)
            
            log_maintenance "INFO" "Restoring volume: $volume_name"
            
            # Stop containers using the volume
            local containers=$(docker ps -q --filter "volume=$volume_name" 2>/dev/null)
            if [[ -n "$containers" ]]; then
                docker stop $containers >/dev/null 2>&1 || true
            fi
            
            # Restore volume
            docker run --rm \
                -v "$volume_name:/target" \
                -v "$volume_backup_dir:/backup:ro" \
                alpine sh -c "rm -rf /target/* && tar -xzf /backup/${volume_name}.tar.gz -C /target" || {
                log_maintenance "WARNING" "Failed to restore volume: $volume_name"
            }
        fi
    done
}

# Fix permissions after restore
fix_restored_permissions() {
    log_maintenance "INFO" "Fixing restored file permissions..."
    
    # Fix script permissions
    find "${MAINTENANCE_PROJECT_ROOT}" -name "*.sh" -type f -exec chmod +x {} \;
    
    # Fix directory permissions
    find "${MAINTENANCE_PROJECT_ROOT}" -type d -exec chmod 755 {} \;
    
    # Fix .env file permissions if exists
    if [[ -f "${MAINTENANCE_PROJECT_ROOT}/.env" ]]; then
        chmod 600 "${MAINTENANCE_PROJECT_ROOT}/.env"
    fi
}

# =============================================================================
# BACKUP LIST OPERATIONS
# =============================================================================

# List backups
backup_list() {
    log_maintenance "INFO" "Available backups:"
    increment_counter "processed"
    
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_maintenance "WARNING" "No backup directory found"
        increment_counter "skipped"
        return 0
    fi
    
    echo ""
    echo "Timestamp            Type      Size         Files   Compressed"
    echo "-------------------- --------- ------------ ------- ----------"
    
    # List backups sorted by date
    for backup_dir in $(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name "[0-9]*" | sort -r); do
        local timestamp=$(basename "${backup_dir}")
        local metadata_file="${backup_dir}/backup-metadata.json"
        
        if [[ -f "${metadata_file}" ]]; then
            local backup_type=$(jq -r '.backup_info.type // "unknown"' "${metadata_file}")
            local backup_size=$(jq -r '.backup_size // "0"' "${metadata_file}")
            local file_count=$(jq -r '.file_count // "0"' "${metadata_file}")
            local compressed=$(jq -r '.backup_info.compression // false' "${metadata_file}")
            
            # Format size
            local size_human=$(numfmt --to=iec ${backup_size} 2>/dev/null || echo "${backup_size}")
            
            # Check if this is the latest
            local latest_marker=""
            if [[ -L "${BACKUP_ROOT}/latest" ]] && [[ "$(readlink "${BACKUP_ROOT}/latest")" == "$backup_dir" ]]; then
                latest_marker=" *"
            fi
            
            printf "%-20s %-9s %-12s %-7s %-10s%s\n" \
                "$timestamp" \
                "$backup_type" \
                "$size_human" \
                "$file_count" \
                "$compressed" \
                "$latest_marker"
        else
            printf "%-20s %-9s %-12s %-7s %-10s\n" \
                "$timestamp" \
                "unknown" \
                "-" \
                "-" \
                "-"
        fi
    done
    
    echo ""
    echo "* = latest backup"
    
    # Show total backup size
    local total_size=$(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)
    echo ""
    echo "Total backup storage used: $total_size"
    
    increment_counter "fixed"
    return 0
}

# =============================================================================
# BACKUP VERIFY OPERATIONS
# =============================================================================

# Verify backup
backup_verify() {
    local backup_timestamp="${1:-latest}"
    
    log_maintenance "INFO" "Verifying backup..."
    increment_counter "processed"
    
    # Find backup to verify
    local verify_dir
    if [[ "$backup_timestamp" == "latest" ]]; then
        verify_dir="${BACKUP_ROOT}/latest"
        if [[ ! -L "$verify_dir" ]]; then
            verify_dir=$(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -1)
        fi
    else
        verify_dir="${BACKUP_ROOT}/${backup_timestamp}"
    fi
    
    if [[ ! -d "$verify_dir" ]]; then
        log_maintenance "ERROR" "Backup not found: $backup_timestamp"
        increment_counter "failed"
        return 1
    fi
    
    # Verify backup components
    local verification_passed=true
    
    # Check metadata
    if [[ -f "${verify_dir}/backup-metadata.json" ]]; then
        if validate_json "${verify_dir}/backup-metadata.json"; then
            log_maintenance "SUCCESS" "Metadata file is valid"
        else
            log_maintenance "ERROR" "Metadata file is corrupted"
            verification_passed=false
        fi
    else
        log_maintenance "ERROR" "Metadata file missing"
        verification_passed=false
    fi
    
    # Check archive
    local backup_archive=$(find "$verify_dir" -name "backup-*.tar*" -type f | head -1)
    if [[ -f "$backup_archive" ]]; then
        # Verify checksum
        if [[ -f "${verify_dir}/backup-checksum.sha256" ]]; then
            if (cd "$verify_dir" && sha256sum -c "backup-checksum.sha256" >/dev/null 2>&1); then
                log_maintenance "SUCCESS" "Archive checksum verified"
            else
                log_maintenance "ERROR" "Archive checksum mismatch"
                verification_passed=false
            fi
        else
            log_maintenance "WARNING" "No checksum file found"
        fi
        
        # Test archive integrity
        if [[ "$backup_archive" == *.gz ]]; then
            if gzip -t "$backup_archive" 2>/dev/null; then
                log_maintenance "SUCCESS" "Archive compression is valid"
            else
                log_maintenance "ERROR" "Archive compression is corrupted"
                verification_passed=false
            fi
        fi
        
        # Test extraction
        if tar -tf "$backup_archive" >/dev/null 2>&1; then
            log_maintenance "SUCCESS" "Archive can be extracted"
        else
            log_maintenance "ERROR" "Archive extraction test failed"
            verification_passed=false
        fi
    else
        log_maintenance "ERROR" "Backup archive not found"
        verification_passed=false
    fi
    
    # Check manifest
    if [[ -f "${verify_dir}/backup-manifest.txt" ]]; then
        local manifest_files=$(wc -l < "${verify_dir}/backup-manifest.txt")
        log_maintenance "INFO" "Manifest contains $manifest_files files"
    else
        log_maintenance "WARNING" "Manifest file missing"
    fi
    
    if [[ "$verification_passed" == true ]]; then
        log_maintenance "SUCCESS" "Backup verification passed"
        increment_counter "fixed"
        return 0
    else
        log_maintenance "ERROR" "Backup verification failed"
        increment_counter "failed"
        return 1
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    # This is called during backup creation
    backup_verify "${BACKUP_TIMESTAMP}"
}

# =============================================================================
# BACKUP CLEANUP OPERATIONS
# =============================================================================

# Cleanup old backups
backup_cleanup() {
    local days_to_keep="${1:-7}"
    
    log_maintenance "INFO" "Cleaning up backups older than ${days_to_keep} days..."
    increment_counter "processed"
    
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_maintenance "INFO" "No backup directory found"
        increment_counter "skipped"
        return 0
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would clean up old backups"
        show_cleanup_preview "$days_to_keep"
        return 0
    fi
    
    local cutoff_timestamp=$(date -d "${days_to_keep} days ago" +%Y%m%d 2>/dev/null || \
                             date -v -${days_to_keep}d +%Y%m%d 2>/dev/null)
    local removed_count=0
    local freed_space=0
    
    for backup_dir in "${BACKUP_ROOT}"/[0-9]*; do
        if [[ -d "$backup_dir" ]]; then
            local dir_timestamp=$(basename "$backup_dir" | cut -d'_' -f1)
            
            # Compare timestamps
            if [[ "$dir_timestamp" < "$cutoff_timestamp" ]]; then
                # Don't remove if it's the only backup
                local backup_count=$(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name "[0-9]*" | wc -l)
                if [[ $backup_count -le 1 ]]; then
                    log_maintenance "WARNING" "Keeping $backup_dir as it's the only backup"
                    continue
                fi
                
                local backup_size=$(get_directory_size "$backup_dir")
                
                if rm -rf "$backup_dir"; then
                    log_maintenance "SUCCESS" "Removed old backup: $(basename "$backup_dir")"
                    ((removed_count++))
                    ((freed_space += backup_size))
                else
                    log_maintenance "ERROR" "Failed to remove: $backup_dir"
                fi
            fi
        fi
    done
    
    # Update latest symlink if needed
    if [[ -L "${BACKUP_ROOT}/latest" ]]; then
        local latest_target=$(readlink "${BACKUP_ROOT}/latest")
        if [[ ! -d "$latest_target" ]]; then
            # Find new latest
            local new_latest=$(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -1)
            if [[ -n "$new_latest" ]]; then
                ln -sfn "$new_latest" "${BACKUP_ROOT}/latest"
                log_maintenance "INFO" "Updated latest symlink to: $(basename "$new_latest")"
            fi
        fi
    fi
    
    if [[ $removed_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Removed $removed_count old backups, freed $(numfmt --to=iec $freed_space 2>/dev/null || echo "${freed_space} bytes")"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "No old backups to remove"
        increment_counter "skipped"
    fi
    
    return 0
}

# Show cleanup preview
show_cleanup_preview() {
    local days_to_keep="$1"
    local cutoff_timestamp=$(date -d "${days_to_keep} days ago" +%Y%m%d 2>/dev/null || \
                             date -v -${days_to_keep}d +%Y%m%d 2>/dev/null)
    
    echo "Backups that would be removed (older than $days_to_keep days):"
    
    local found=false
    for backup_dir in "${BACKUP_ROOT}"/[0-9]*; do
        if [[ -d "$backup_dir" ]]; then
            local dir_timestamp=$(basename "$backup_dir" | cut -d'_' -f1)
            
            if [[ "$dir_timestamp" < "$cutoff_timestamp" ]]; then
                local size=$(get_directory_size "$backup_dir" true)
                echo "  - $(basename "$backup_dir") ($size)"
                found=true
            fi
        fi
    done
    
    if [[ "$found" == false ]]; then
        echo "  (none)"
    fi
}

# Export backup functions
export -f backup_create
export -f backup_restore
export -f backup_list
export -f backup_verify
export -f backup_cleanup
export -f init_backup_directory
export -f create_backup_metadata
export -f create_full_backup
export -f create_incremental_backup
export -f create_selective_backup
export -f sanitize_env_file
export -f backup_docker_volumes
export -f show_backup_preview
export -f show_backup_summary
export -f show_restore_preview
export -f restore_docker_volumes
export -f fix_restored_permissions
export -f verify_backup_integrity
export -f show_cleanup_preview