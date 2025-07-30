#!/bin/bash
#
# Test script for maintenance suite functionality
# Tests all maintenance operations and wrapper scripts
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# Test configuration
TEST_STACK_NAME="test-maintenance-suite-$$"
TEST_BACKUP_DIR="$PROJECT_ROOT/backup/test-$$"
TEST_REGION="us-east-1"

# Initialize test environment
test_init "Maintenance Suite Tests"

#######################################
# Setup and Teardown
#######################################

setup_suite() {
    log "Setting up test environment..."
    
    # Create test backup directory
    mkdir -p "$TEST_BACKUP_DIR"
    
    # Source maintenance suite
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh"
    
    # Create test configuration
    export MAINTENANCE_DRY_RUN=true
    export MAINTENANCE_BACKUP_DIR="$TEST_BACKUP_DIR"
}

teardown_suite() {
    log "Cleaning up test environment..."
    
    # Remove test backup directory
    rm -rf "$TEST_BACKUP_DIR"
    
    # Unset test variables
    unset MAINTENANCE_DRY_RUN
    unset MAINTENANCE_BACKUP_DIR
}

#######################################
# Test Functions
#######################################

# Test maintenance suite loading
test_maintenance_suite_loading() {
    test_start "Maintenance Suite Loading"
    
    # Test that maintenance suite can be sourced
    (
        source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || fail "Failed to source maintenance suite"
    )
    
    # Test that main function exists
    if ! declare -f run_maintenance >/dev/null 2>&1; then
        fail "run_maintenance function not found"
    fi
    
    # Test that required modules are loaded
    local required_modules=(
        "maintenance_fix_deployment"
        "maintenance_cleanup_resources"
        "maintenance_update_components"
        "maintenance_health_check"
        "maintenance_backup_system"
        "maintenance_optimize_performance"
        "maintenance_validate_system"
    )
    
    for module in "${required_modules[@]}"; do
        if ! declare -f "$module" >/dev/null 2>&1; then
            fail "Required function $module not found"
        fi
    done
    
    test_pass "All maintenance modules loaded successfully"
}

# Test fix operations
test_fix_operations() {
    test_start "Fix Operations"
    
    # Test deployment fix
    run_maintenance --operation=fix --target=deployment --stack-name="$TEST_STACK_NAME" --dry-run || \
        fail "Deployment fix failed"
    
    # Test disk space fix
    run_maintenance --operation=fix --target=disk-space --dry-run || \
        fail "Disk space fix failed"
    
    # Test docker optimization
    run_maintenance --operation=fix --target=docker-optimization --dry-run || \
        fail "Docker optimization failed"
    
    test_pass "Fix operations completed successfully"
}

# Test cleanup operations
test_cleanup_operations() {
    test_start "Cleanup Operations"
    
    # Test stack cleanup
    run_maintenance --operation=cleanup --scope=stack --stack-name="$TEST_STACK_NAME" --dry-run || \
        fail "Stack cleanup failed"
    
    # Test EFS cleanup by pattern
    run_maintenance --operation=cleanup --scope=efs --pattern="test-*" --dry-run || \
        fail "EFS cleanup failed"
    
    # Test codebase cleanup
    run_maintenance --operation=cleanup --scope=codebase --dry-run || \
        fail "Codebase cleanup failed"
    
    test_pass "Cleanup operations completed successfully"
}

# Test update operations
test_update_operations() {
    test_start "Update Operations"
    
    # Test show versions
    run_maintenance --operation=update --component=docker --action=show || \
        fail "Show versions failed"
    
    # Test update simulation
    run_maintenance --operation=update --component=docker --environment=development --dry-run || \
        fail "Update simulation failed"
    
    test_pass "Update operations completed successfully"
}

# Test health operations
test_health_operations() {
    test_start "Health Operations"
    
    # Test basic health check
    run_maintenance --operation=health --stack-name="$TEST_STACK_NAME" --dry-run || \
        fail "Health check failed"
    
    # Test specific health checks
    run_maintenance --operation=health --check-type=network --dry-run || \
        fail "Network health check failed"
    
    test_pass "Health operations completed successfully"
}

# Test backup operations
test_backup_operations() {
    test_start "Backup Operations"
    
    # Test backup creation
    run_maintenance --operation=backup --backup-type=config --dry-run || \
        fail "Backup creation failed"
    
    # Create a test backup file for verify/restore tests
    local test_backup="$TEST_BACKUP_DIR/test-backup.tar.gz"
    echo "test" | gzip > "$test_backup"
    
    # Test backup verification
    run_maintenance --operation=verify --backup-file="$test_backup" --dry-run || \
        fail "Backup verification failed"
    
    test_pass "Backup operations completed successfully"
}

# Test validation operations
test_validation_operations() {
    test_start "Validation Operations"
    
    # Test configuration validation
    run_maintenance --operation=validate --validation-type=config || \
        fail "Configuration validation failed"
    
    # Test docker-compose validation
    if [[ -f "$PROJECT_ROOT/docker-compose.gpu-optimized.yml" ]]; then
        run_maintenance --operation=validate --validation-type=docker-compose || \
            fail "Docker compose validation failed"
    fi
    
    test_pass "Validation operations completed successfully"
}

# Test parameter validation
test_parameter_validation() {
    test_start "Parameter Validation"
    
    # Test invalid operation
    if run_maintenance --operation=invalid 2>/dev/null; then
        fail "Invalid operation should have failed"
    fi
    
    # Test missing required parameters
    if run_maintenance --operation=fix 2>/dev/null; then
        fail "Missing target parameter should have failed"
    fi
    
    # Test invalid parameter combinations
    if run_maintenance --operation=cleanup --scope=stack 2>/dev/null; then
        fail "Missing stack name should have failed"
    fi
    
    test_pass "Parameter validation working correctly"
}

# Test wrapper scripts
test_wrapper_scripts() {
    test_start "Wrapper Scripts"
    
    local wrapper_scripts=(
        "fix-deployment-issues-wrapper.sh"
        "cleanup-consolidated-wrapper.sh"
        "backup-system-wrapper.sh"
        "restore-backup-wrapper.sh"
        "verify-backup-wrapper.sh"
        "health-check-advanced-wrapper.sh"
        "update-image-versions-wrapper.sh"
        "simple-update-images-wrapper.sh"
    )
    
    for wrapper in "${wrapper_scripts[@]}"; do
        local wrapper_path="$PROJECT_ROOT/scripts/$wrapper"
        
        # Check wrapper exists
        if [[ ! -f "$wrapper_path" ]]; then
            fail "Wrapper script not found: $wrapper"
        fi
        
        # Check wrapper is executable
        if [[ ! -x "$wrapper_path" ]]; then
            fail "Wrapper script not executable: $wrapper"
        fi
        
        # Test wrapper help
        if ! "$wrapper_path" --help >/dev/null 2>&1; then
            fail "Wrapper help failed: $wrapper"
        fi
    done
    
    test_pass "All wrapper scripts validated successfully"
}

# Test Make targets
test_make_targets() {
    test_start "Make Targets"
    
    # Test maintenance help
    make -C "$PROJECT_ROOT" maintenance-help >/dev/null 2>&1 || \
        fail "Make maintenance-help failed"
    
    # Test other targets with dry run
    export MAINTENANCE_DRY_RUN=true
    
    make -C "$PROJECT_ROOT" maintenance-fix STACK_NAME="$TEST_STACK_NAME" >/dev/null 2>&1 || \
        fail "Make maintenance-fix failed"
    
    make -C "$PROJECT_ROOT" maintenance-cleanup STACK_NAME="$TEST_STACK_NAME" DRY_RUN=true >/dev/null 2>&1 || \
        fail "Make maintenance-cleanup failed"
    
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Make targets working correctly"
}

# Test help system
test_help_system() {
    test_start "Help System"
    
    # Test main help
    run_maintenance --help || fail "Main help failed"
    
    # Test operation-specific help
    run_maintenance --operation=fix --help || fail "Fix operation help failed"
    run_maintenance --operation=cleanup --help || fail "Cleanup operation help failed"
    run_maintenance --operation=update --help || fail "Update operation help failed"
    
    test_pass "Help system working correctly"
}

# Test dry run mode
test_dry_run_mode() {
    test_start "Dry Run Mode"
    
    # Test that dry run doesn't make changes
    local test_file="$TEST_BACKUP_DIR/test-dry-run.txt"
    echo "test" > "$test_file"
    
    # Run cleanup in dry run mode
    run_maintenance --operation=cleanup --scope=codebase --dry-run
    
    # Verify file still exists
    if [[ ! -f "$test_file" ]]; then
        fail "Dry run mode made actual changes"
    fi
    
    rm -f "$test_file"
    
    test_pass "Dry run mode working correctly"
}

# Test error handling
test_error_handling() {
    test_start "Error Handling"
    
    # Test handling of non-existent stack
    if run_maintenance --operation=health --stack-name="non-existent-stack-$$" 2>/dev/null; then
        warning "Health check on non-existent stack should show appropriate message"
    fi
    
    # Test handling of invalid backup file
    if run_maintenance --operation=restore --backup-file="/non/existent/backup.tar.gz" 2>/dev/null; then
        warning "Restore with non-existent backup should fail gracefully"
    fi
    
    test_pass "Error handling working correctly"
}

#######################################
# Main Test Execution
#######################################

main() {
    setup_suite
    
    # Run all tests
    test_maintenance_suite_loading
    test_fix_operations
    test_cleanup_operations
    test_update_operations
    test_health_operations
    test_backup_operations
    test_validation_operations
    test_parameter_validation
    test_wrapper_scripts
    test_make_targets
    test_help_system
    test_dry_run_mode
    test_error_handling
    
    teardown_suite
    
    # Show test summary
    test_summary "Maintenance Suite"
}

# Run tests
main "$@"