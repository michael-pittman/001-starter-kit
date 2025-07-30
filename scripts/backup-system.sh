#!/usr/bin/env bash
# Backup System for AWS Deployment System
# Provides comprehensive backup and restoration capabilities

set -euo pipefail

# Simple backup system without external dependencies

# Configuration
BACKUP_ROOT="${PROJECT_ROOT:-$(pwd)}/backup"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_TIMESTAMP}"
BACKUP_METADATA="${BACKUP_DIR}/backup-metadata.json"
BACKUP_CHECKSUM="${BACKUP_DIR}/backup-checksum.sha256"

# Backup scope
BACKUP_SCOPE=(
    "scripts/"
    "lib/"
    "config/"
    "docs/"
    "tests/"
    "Makefile"
    "README.md"
    "deploy.sh"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Initialize backup system
init_backup() {
    log_info "Initializing backup system..."
    
    # Create backup directory structure
    mkdir -p "${BACKUP_DIR}"
    
    # Create backup metadata
    cat > "${BACKUP_METADATA}" << EOF
{
    "backup_timestamp": "${BACKUP_TIMESTAMP}",
    "backup_version": "1.0",
    "project_root": "${PROJECT_ROOT:-$(pwd)}",
    "backup_scope": $(printf '%s\n' "${BACKUP_SCOPE[@]}" | jq -R . | jq -s .),
    "system_info": {
        "hostname": "$(hostname)",
        "user": "$(whoami)",
        "bash_version": "${BASH_VERSION}",
        "os": "$(uname -s)",
        "os_version": "$(uname -r)"
    },
    "backup_checksum": null,
    "backup_size": null,
    "compression_ratio": null
}
EOF
    
    log_success "Backup system initialized at ${BACKUP_DIR}"
}

# Create backup
create_backup() {
    log_info "Creating backup..."
    
    local backup_archive="${BACKUP_DIR}/backup-${BACKUP_TIMESTAMP}.tar.gz"
    local temp_dir="${BACKUP_DIR}/temp"
    
    # Create temporary directory for backup
    mkdir -p "${temp_dir}"
    
    # Copy files to backup
    for item in "${BACKUP_SCOPE[@]}"; do
        if [[ -e "${PROJECT_ROOT:-$(pwd)}/${item}" ]]; then
            log_info "Backing up: ${item}"
            cp -r "${PROJECT_ROOT:-$(pwd)}/${item}" "${temp_dir}/"
        else
            log_warning "Item not found: ${item}"
        fi
    done
    
    # Create compressed archive
    log_info "Creating compressed archive..."
    tar -czf "${backup_archive}" -C "${temp_dir}" .
    
    # Calculate checksum
    log_info "Calculating checksum..."
    sha256sum "${backup_archive}" > "${BACKUP_CHECKSUM}"
    
    # Update metadata
    local backup_size=$(stat -f%z "${backup_archive}" 2>/dev/null || stat -c%s "${backup_archive}" 2>/dev/null || echo "0")
    local checksum=$(cat "${BACKUP_CHECKSUM}" | cut -d' ' -f1)
    
    jq --arg size "${backup_size}" \
       --arg checksum "${checksum}" \
       '.backup_size = $size | .backup_checksum = $checksum' \
       "${BACKUP_METADATA}" > "${BACKUP_METADATA}.tmp" && \
    mv "${BACKUP_METADATA}.tmp" "${BACKUP_METADATA}"
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    log_success "Backup created: ${backup_archive}"
    log_info "Backup size: ${backup_size} bytes"
    log_info "Checksum: ${checksum}"
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."
    
    local backup_archive="${BACKUP_DIR}/backup-${BACKUP_TIMESTAMP}.tar.gz"
    
    if [[ ! -f "${backup_archive}" ]]; then
        log_error "Backup archive not found: ${backup_archive}"
        return 1
    fi
    
    if [[ ! -f "${BACKUP_CHECKSUM}" ]]; then
        log_error "Backup checksum file not found: ${BACKUP_CHECKSUM}"
        return 1
    fi
    
    # Verify checksum
    if cd "${BACKUP_DIR}" && sha256sum -c "${BACKUP_CHECKSUM}"; then
        log_success "Backup integrity verified"
    else
        log_error "Backup integrity check failed"
        return 1
    fi
    
    # Test archive extraction
    log_info "Testing archive extraction..."
    local test_dir="${BACKUP_DIR}/test-extract"
    mkdir -p "${test_dir}"
    
    if tar -tzf "${backup_archive}" >/dev/null 2>&1; then
        log_success "Archive extraction test passed"
        rm -rf "${test_dir}"
    else
        log_error "Archive extraction test failed"
        rm -rf "${test_dir}"
        return 1
    fi
}

# List available backups
list_backups() {
    log_info "Available backups:"
    
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_warning "No backup directory found"
        return 0
    fi
    
    for backup_dir in "${BACKUP_ROOT}"/*/; do
        if [[ -d "${backup_dir}" ]]; then
            local timestamp=$(basename "${backup_dir}")
            local metadata_file="${backup_dir}/backup-metadata.json"
            
            if [[ -f "${metadata_file}" ]]; then
                local size=$(jq -r '.backup_size // "unknown"' "${metadata_file}")
                echo "  ${timestamp} (${size} bytes)"
            else
                echo "  ${timestamp} (no metadata)"
            fi
        fi
    done
}

# Restore from backup
restore_backup() {
    local backup_timestamp="$1"
    local restore_dir="${BACKUP_ROOT}/${backup_timestamp}"
    local backup_archive="${restore_dir}/backup-${backup_timestamp}.tar.gz"
    
    if [[ ! -d "${restore_dir}" ]]; then
        log_error "Backup not found: ${backup_timestamp}"
        return 1
    fi
    
    if [[ ! -f "${backup_archive}" ]]; then
        log_error "Backup archive not found: ${backup_archive}"
        return 1
    fi
    
    log_warning "This will restore the system to the state at ${backup_timestamp}"
    log_warning "Current files will be overwritten!"
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Restore cancelled"
        return 0
    fi
    
    # Verify backup integrity before restore
    if ! verify_backup; then
        log_error "Backup integrity check failed, aborting restore"
        return 1
    fi
    
    # Create restore backup
    log_info "Creating backup of current state before restore..."
    create_backup
    
    # Extract backup
    log_info "Restoring from backup..."
    tar -xzf "${backup_archive}" -C "${PROJECT_ROOT:-$(pwd)}"
    
    log_success "Restore completed successfully"
}

# Clean up old backups
cleanup_backups() {
    local days_to_keep="${1:-7}"
    log_info "Cleaning up backups older than ${days_to_keep} days..."
    
    local cutoff_date=$(date -d "${days_to_keep} days ago" +%Y%m%d)
    local removed_count=0
    
    for backup_dir in "${BACKUP_ROOT}"/*/; do
        if [[ -d "${backup_dir}" ]]; then
            local timestamp=$(basename "${backup_dir}")
            local backup_date=$(echo "${timestamp}" | cut -d'_' -f1)
            
            if [[ "${backup_date}" < "${cutoff_date}" ]]; then
                log_info "Removing old backup: ${timestamp}"
                rm -rf "${backup_dir}"
                ((removed_count++))
            fi
        fi
    done
    
    log_success "Removed ${removed_count} old backups"
}

# Main function
main() {
    local action="${1:-create}"
    
    case "${action}" in
        "create")
            init_backup
            create_backup
            verify_backup
            ;;
        "verify")
            verify_backup
            ;;
        "list")
            list_backups
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                log_error "Backup timestamp required for restore"
                echo "Usage: $0 restore <backup_timestamp>"
                exit 1
            fi
            restore_backup "$2"
            ;;
        "cleanup")
            cleanup_backups "${2:-7}"
            ;;
        "help"|"-h"|"--help")
            echo "Backup System Usage:"
            echo "  $0 create     - Create a new backup"
            echo "  $0 verify     - Verify backup integrity"
            echo "  $0 list       - List available backups"
            echo "  $0 restore <timestamp> - Restore from backup"
            echo "  $0 cleanup [days] - Clean up old backups (default: 7 days)"
            echo "  $0 help       - Show this help"
            ;;
        *)
            log_error "Unknown action: ${action}"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 