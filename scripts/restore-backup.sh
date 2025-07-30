#!/usr/bin/env bash
# Backup Restoration Script
# Standalone script for restoring from backups

set -euo pipefail

# Configuration
BACKUP_ROOT="${PROJECT_ROOT:-$(pwd)}/backup"
RESTORE_LOG="/tmp/backup-restore.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${RESTORE_LOG}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${RESTORE_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${RESTORE_LOG}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${RESTORE_LOG}"
}

# Verify backup before restoration
verify_backup_for_restore() {
    local backup_timestamp="$1"
    local backup_dir="${BACKUP_ROOT}/${backup_timestamp}"
    local backup_archive="${backup_dir}/backup-${backup_timestamp}.tar.gz"
    local backup_checksum="${backup_dir}/backup-checksum.sha256"
    local backup_metadata="${backup_dir}/backup-metadata.json"
    
    log_info "Verifying backup before restoration: ${backup_timestamp}"
    
    # Check if backup directory exists
    if [[ ! -d "${backup_dir}" ]]; then
        log_error "Backup directory not found: ${backup_dir}"
        return 1
    fi
    
    # Check if backup archive exists
    if [[ ! -f "${backup_archive}" ]]; then
        log_error "Backup archive not found: ${backup_archive}"
        return 1
    fi
    
    # Check if checksum file exists
    if [[ ! -f "${backup_checksum}" ]]; then
        log_error "Backup checksum file not found: ${backup_checksum}"
        return 1
    fi
    
    # Check if metadata file exists
    if [[ ! -f "${backup_metadata}" ]]; then
        log_error "Backup metadata file not found: ${backup_metadata}"
        return 1
    fi
    
    # Verify checksum
    log_info "Verifying checksum..."
    if cd "${backup_dir}" && sha256sum -c "${backup_checksum}"; then
        log_success "Checksum verification passed"
    else
        log_error "Checksum verification failed"
        return 1
    fi
    
    # Test archive extraction
    log_info "Testing archive extraction..."
    local test_dir="${backup_dir}/test-extract-$$"
    mkdir -p "${test_dir}"
    
    if tar -tzf "${backup_archive}" >/dev/null 2>&1; then
        log_success "Archive extraction test passed"
        rm -rf "${test_dir}"
    else
        log_error "Archive extraction test failed"
        rm -rf "${test_dir}"
        return 1
    fi
    
    log_success "Backup verification completed successfully"
    return 0
}

# Create pre-restore backup
create_pre_restore_backup() {
    log_info "Creating backup of current state before restoration..."
    
    local pre_restore_timestamp=$(date +%Y%m%d_%H%M%S)
    local pre_restore_dir="${BACKUP_ROOT}/pre-restore-${pre_restore_timestamp}"
    
    mkdir -p "${pre_restore_dir}"
    
    # Create backup of current state
    tar -czf "${pre_restore_dir}/pre-restore-${pre_restore_timestamp}.tar.gz" \
        --exclude="${BACKUP_ROOT}" \
        --exclude="*.log" \
        --exclude="*.tmp" \
        .
    
    # Create checksum
    cd "${pre_restore_dir}"
    sha256sum "pre-restore-${pre_restore_timestamp}.tar.gz" > "pre-restore-checksum.sha256"
    
    # Create metadata
    cat > "pre-restore-metadata.json" << EOF
{
    "backup_timestamp": "${pre_restore_timestamp}",
    "backup_type": "pre-restore",
    "restore_from": "${1}",
    "project_root": "${PROJECT_ROOT:-$(pwd)}",
    "system_info": {
        "hostname": "$(hostname)",
        "user": "$(whoami)",
        "bash_version": "${BASH_VERSION}",
        "os": "$(uname -s)",
        "os_version": "$(uname -r)"
    }
}
EOF
    
    log_success "Pre-restore backup created: ${pre_restore_dir}"
    echo "${pre_restore_dir}"
}

# Restore from backup
restore_from_backup() {
    local backup_timestamp="$1"
    local backup_dir="${BACKUP_ROOT}/${backup_timestamp}"
    local backup_archive="${backup_dir}/backup-${backup_timestamp}.tar.gz"
    local backup_metadata="${backup_dir}/backup-metadata.json"
    
    log_info "Restoring from backup: ${backup_timestamp}"
    
    # Verify backup before restoration
    if ! verify_backup_for_restore "${backup_timestamp}"; then
        log_error "Backup verification failed, aborting restoration"
        return 1
    fi
    
    # Create pre-restore backup
    local pre_restore_dir=$(create_pre_restore_backup "${backup_timestamp}")
    
    # Show backup information
    log_info "Backup information:"
    if [[ -f "${backup_metadata}" ]]; then
        local backup_date=$(jq -r '.backup_timestamp' "${backup_metadata}")
        local system_info=$(jq -r '.system_info.hostname' "${backup_metadata}")
        log_info "  Backup date: ${backup_date}"
        log_info "  System: ${system_info}"
    fi
    
    # Confirm restoration
    log_warning "This will restore the system to the state at ${backup_timestamp}"
    log_warning "Current files will be overwritten!"
    log_warning "A backup of the current state has been created at: ${pre_restore_dir}"
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Restoration cancelled"
        return 0
    fi
    
    # Perform restoration
    log_info "Starting restoration process..."
    
    # Extract backup
    log_info "Extracting backup archive..."
    if tar -xzf "${backup_archive}" -C "${PROJECT_ROOT:-$(pwd)}"; then
        log_success "Backup extraction completed"
    else
        log_error "Backup extraction failed"
        return 1
    fi
    
    # Verify restoration
    log_info "Verifying restoration..."
    
    # Check if key files were restored
    local key_files=("scripts/" "lib/" "config/" "docs/" "README.md")
    local missing_files=()
    
    for file in "${key_files[@]}"; do
        if [[ ! -e "${PROJECT_ROOT:-$(pwd)}/${file}" ]]; then
            missing_files+=("${file}")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_warning "Some files may not have been restored:"
        for file in "${missing_files[@]}"; do
            log_warning "  - ${file}"
        done
    else
        log_success "All key files restored successfully"
    fi
    
    log_success "Restoration completed successfully"
    log_info "Pre-restore backup available at: ${pre_restore_dir}"
    
    return 0
}

# List available backups
list_available_backups() {
    log_info "Available backups for restoration:"
    
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_warning "No backup directory found"
        return 0
    fi
    
    local backup_count=0
    
    for backup_dir in "${BACKUP_ROOT}"/*/; do
        if [[ -d "${backup_dir}" ]]; then
            local timestamp=$(basename "${backup_dir}")
            local metadata_file="${backup_dir}/backup-metadata.json"
            
            if [[ -f "${metadata_file}" ]]; then
                local size=$(jq -r '.backup_size // "unknown"' "${metadata_file}")
                local size_formatted=$(numfmt --to=iec "${size}" 2>/dev/null || echo "unknown")
                local system_info=$(jq -r '.system_info.hostname // "unknown"' "${metadata_file}")
                echo "  ${timestamp} (${size_formatted}) - ${system_info}"
            else
                echo "  ${timestamp} (no metadata)"
            fi
            
            ((backup_count++))
        fi
    done
    
    if [[ ${backup_count} -eq 0 ]]; then
        log_warning "No backups found"
    else
        log_info "Total backups available: ${backup_count}"
    fi
}

# Main function
main() {
    # Clear restore log
    > "${RESTORE_LOG}"
    
    log_info "Starting backup restoration process..."
    log_info "Restoration log: ${RESTORE_LOG}"
    
    case "${1:-}" in
        "list"|"ls")
            list_available_backups
            ;;
        "restore"|"")
            if [[ -z "${2:-}" ]]; then
                log_error "Backup timestamp required for restoration"
                echo "Usage: $0 restore <backup_timestamp>"
                echo "Usage: $0 list"
                exit 1
            fi
            restore_from_backup "$2"
            ;;
        "help"|"-h"|"--help")
            echo "Backup Restoration Usage:"
            echo "  $0 list                    - List available backups"
            echo "  $0 restore <timestamp>     - Restore from backup"
            echo "  $0 help                    - Show this help"
            ;;
        *)
            log_error "Unknown action: ${1}"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
    
    log_info "Restoration process completed"
    log_info "Full log available at: ${RESTORE_LOG}"
}

# Run main function with all arguments
main "$@" 