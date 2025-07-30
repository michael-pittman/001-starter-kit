#!/usr/bin/env bash
# Backup Verification Script
# Standalone script for verifying backup integrity

set -euo pipefail

# Configuration
BACKUP_ROOT="${PROJECT_ROOT:-$(pwd)}/backup"
VERIFICATION_LOG="/tmp/backup-verification.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${VERIFICATION_LOG}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${VERIFICATION_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${VERIFICATION_LOG}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${VERIFICATION_LOG}"
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_timestamp="$1"
    local backup_dir="${BACKUP_ROOT}/${backup_timestamp}"
    local backup_archive="${backup_dir}/backup-${backup_timestamp}.tar.gz"
    local backup_checksum="${backup_dir}/backup-checksum.sha256"
    local backup_metadata="${backup_dir}/backup-metadata.json"
    
    log_info "Verifying backup: ${backup_timestamp}"
    
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
    
    # Verify metadata
    log_info "Verifying metadata..."
    if jq empty "${backup_metadata}" 2>/dev/null; then
        log_success "Metadata JSON validation passed"
    else
        log_error "Metadata JSON validation failed"
        return 1
    fi
    
    # Check backup size
    local expected_size=$(jq -r '.backup_size // "unknown"' "${backup_metadata}")
    local actual_size=$(stat -c%s "${backup_archive}")
    
    if [[ "${expected_size}" != "unknown" && "${expected_size}" == "${actual_size}" ]]; then
        log_success "Backup size verification passed"
    else
        log_warning "Backup size mismatch: expected ${expected_size}, actual ${actual_size}"
    fi
    
    log_success "Backup verification completed successfully"
    return 0
}

# Verify all backups
verify_all_backups() {
    log_info "Verifying all available backups..."
    
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_warning "No backup directory found"
        return 0
    fi
    
    local total_backups=0
    local successful_verifications=0
    local failed_verifications=0
    
    for backup_dir in "${BACKUP_ROOT}"/*/; do
        if [[ -d "${backup_dir}" ]]; then
            local timestamp=$(basename "${backup_dir}")
            ((total_backups++))
            
            if verify_backup_integrity "${timestamp}"; then
                ((successful_verifications++))
            else
                ((failed_verifications++))
            fi
            
            echo "" # Add spacing between backups
        fi
    done
    
    log_info "Verification Summary:"
    log_info "  Total backups: ${total_backups}"
    log_info "  Successful: ${successful_verifications}"
    log_info "  Failed: ${failed_verifications}"
    
    if [[ ${failed_verifications} -gt 0 ]]; then
        log_error "Some backups failed verification"
        return 1
    else
        log_success "All backups verified successfully"
        return 0
    fi
}

# Main function
main() {
    # Clear verification log
    > "${VERIFICATION_LOG}"
    
    log_info "Starting backup verification process..."
    log_info "Verification log: ${VERIFICATION_LOG}"
    
    if [[ -n "${1:-}" ]]; then
        # Verify specific backup
        verify_backup_integrity "$1"
    else
        # Verify all backups
        verify_all_backups
    fi
    
    log_info "Verification process completed"
    log_info "Full log available at: ${VERIFICATION_LOG}"
}

# Run main function with all arguments
main "$@" 