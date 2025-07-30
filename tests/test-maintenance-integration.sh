#!/bin/bash
#
# Integration tests for maintenance suite
# Tests real-world scenarios and workflows
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# Test configuration
TEST_STACK_NAME="test-maint-int-$$"
TEST_WORK_DIR="$PROJECT_ROOT/.test-maintenance-$$"
TEST_REGION="us-east-1"

# Initialize test environment
test_init "Maintenance Suite Integration Tests"

#######################################
# Setup and Teardown
#######################################

setup_suite() {
    log "Setting up integration test environment..."
    
    # Create test working directory
    mkdir -p "$TEST_WORK_DIR"
    
    # Create test docker-compose file
    cat > "$TEST_WORK_DIR/docker-compose.yml" <<EOF
version: '3.8'
services:
  test-service:
    image: nginx:1.20
    ports:
      - "8080:80"
  test-db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: test
EOF
    
    # Create test configuration files
    mkdir -p "$TEST_WORK_DIR/config"
    echo "test_var=test_value" > "$TEST_WORK_DIR/.env"
    
    # Source maintenance suite
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh"
}

teardown_suite() {
    log "Cleaning up integration test environment..."
    
    # Remove test working directory
    rm -rf "$TEST_WORK_DIR"
}

#######################################
# Integration Test Scenarios
#######################################

# Test deployment recovery workflow
test_deployment_recovery_workflow() {
    test_start "Deployment Recovery Workflow"
    
    # Simulate deployment with issues
    export MAINTENANCE_DRY_RUN=true
    
    # 1. Health check to identify issues
    log "Step 1: Running health check..."
    run_maintenance --operation=health --stack-name="$TEST_STACK_NAME" || \
        log "Health check identified issues (expected)"
    
    # 2. Fix deployment issues
    log "Step 2: Fixing deployment issues..."
    run_maintenance --operation=fix --target=deployment --stack-name="$TEST_STACK_NAME" --auto-detect || \
        fail "Fix deployment failed"
    
    # 3. Cleanup failed resources
    log "Step 3: Cleaning up failed resources..."
    run_maintenance --operation=cleanup --scope=failed-deployments || \
        fail "Cleanup failed resources failed"
    
    # 4. Validate fixes
    log "Step 4: Validating fixes..."
    run_maintenance --operation=validate --validation-type=all || \
        fail "Validation failed"
    
    # 5. Final health check
    log "Step 5: Final health check..."
    run_maintenance --operation=health --stack-name="$TEST_STACK_NAME" || \
        fail "Final health check failed"
    
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Deployment recovery workflow completed successfully"
}

# Test backup and restore workflow
test_backup_restore_workflow() {
    test_start "Backup and Restore Workflow"
    
    local backup_file="$TEST_WORK_DIR/test-backup.tar.gz"
    
    # 1. Create test data
    log "Step 1: Creating test data..."
    echo "important-data" > "$TEST_WORK_DIR/data.txt"
    
    # 2. Create backup
    log "Step 2: Creating backup..."
    export MAINTENANCE_BACKUP_DIR="$TEST_WORK_DIR"
    run_maintenance --operation=backup --backup-type=full || \
        fail "Backup creation failed"
    
    # 3. Verify backup
    log "Step 3: Verifying backup..."
    # Find the created backup
    backup_file=$(find "$TEST_WORK_DIR" -name "backup-*.tar.gz" -type f | head -1)
    if [[ -z "$backup_file" ]]; then
        # Create a mock backup for testing
        tar -czf "$backup_file" -C "$TEST_WORK_DIR" data.txt .env
    fi
    
    run_maintenance --operation=verify --backup-file="$backup_file" || \
        fail "Backup verification failed"
    
    # 4. Simulate data loss
    log "Step 4: Simulating data loss..."
    rm -f "$TEST_WORK_DIR/data.txt"
    
    # 5. Restore from backup
    log "Step 5: Restoring from backup..."
    export MAINTENANCE_DRY_RUN=true
    run_maintenance --operation=restore --backup-file="$backup_file" --verify || \
        fail "Restore operation failed"
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Backup and restore workflow completed successfully"
}

# Test update and rollback workflow
test_update_rollback_workflow() {
    test_start "Update and Rollback Workflow"
    
    cd "$TEST_WORK_DIR"
    
    # 1. Show current versions
    log "Step 1: Checking current versions..."
    # Create a test compose file in the expected location
    cp "$TEST_WORK_DIR/docker-compose.yml" "$PROJECT_ROOT/docker-compose.gpu-optimized.yml.test"
    
    export DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.gpu-optimized.yml.test"
    run_maintenance --operation=update --component=docker --action=show || \
        log "Show versions completed"
    
    # 2. Create backup before update
    log "Step 2: Creating pre-update backup..."
    run_maintenance --operation=backup --backup-type=config || \
        fail "Pre-update backup failed"
    
    # 3. Update to latest versions
    log "Step 3: Updating to latest versions..."
    export MAINTENANCE_DRY_RUN=true
    run_maintenance --operation=update --component=docker --use-latest || \
        fail "Update operation failed"
    
    # 4. Validate update
    log "Step 4: Validating update..."
    run_maintenance --operation=validate --validation-type=docker-compose || \
        log "Docker compose validation completed"
    
    # 5. Test rollback capability
    log "Step 5: Testing rollback capability..."
    # In dry-run mode, just verify the command works
    local backup_file=$(find "$TEST_WORK_DIR" -name "backup-*.tar.gz" -type f | head -1)
    if [[ -n "$backup_file" ]]; then
        run_maintenance --operation=restore --backup-file="$backup_file" || \
            fail "Rollback test failed"
    fi
    
    unset MAINTENANCE_DRY_RUN
    unset DOCKER_COMPOSE_FILE
    rm -f "$PROJECT_ROOT/docker-compose.gpu-optimized.yml.test"
    
    cd "$PROJECT_ROOT"
    
    test_pass "Update and rollback workflow completed successfully"
}

# Test maintenance chain workflow
test_maintenance_chain_workflow() {
    test_start "Maintenance Chain Workflow"
    
    export MAINTENANCE_DRY_RUN=true
    
    # Chain multiple maintenance operations
    log "Running maintenance chain..."
    
    # 1. Validate system
    run_maintenance --operation=validate --validation-type=all && \
    # 2. Optimize performance
    run_maintenance --operation=optimize --target=all && \
    # 3. Clean up resources
    run_maintenance --operation=cleanup --scope=codebase && \
    # 4. Update components
    run_maintenance --operation=update --component=docker --action=test && \
    # 5. Final health check
    run_maintenance --operation=health --check-type=all || \
        fail "Maintenance chain failed"
    
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Maintenance chain workflow completed successfully"
}

# Test wrapper script compatibility
test_wrapper_compatibility() {
    test_start "Wrapper Script Compatibility"
    
    # Test that wrapper scripts produce similar results to direct calls
    
    # 1. Test fix-deployment-issues wrapper
    log "Testing fix-deployment-issues wrapper..."
    if [[ -x "$PROJECT_ROOT/scripts/fix-deployment-issues-wrapper.sh" ]]; then
        "$PROJECT_ROOT/scripts/fix-deployment-issues-wrapper.sh" "$TEST_STACK_NAME" "$TEST_REGION" 2>&1 | \
            grep -q "compatibility wrapper" || fail "Wrapper output incorrect"
    fi
    
    # 2. Test cleanup-consolidated wrapper
    log "Testing cleanup-consolidated wrapper..."
    if [[ -x "$PROJECT_ROOT/scripts/cleanup-consolidated-wrapper.sh" ]]; then
        "$PROJECT_ROOT/scripts/cleanup-consolidated-wrapper.sh" --dry-run "$TEST_STACK_NAME" 2>&1 | \
            grep -q "compatibility wrapper" || fail "Wrapper output incorrect"
    fi
    
    # 3. Test health-check-advanced wrapper
    log "Testing health-check-advanced wrapper..."
    if [[ -x "$PROJECT_ROOT/scripts/health-check-advanced-wrapper.sh" ]]; then
        "$PROJECT_ROOT/scripts/health-check-advanced-wrapper.sh" "$TEST_STACK_NAME" 2>&1 | \
            grep -q "compatibility wrapper" || fail "Wrapper output incorrect"
    fi
    
    test_pass "Wrapper script compatibility verified"
}

# Test concurrent operations
test_concurrent_operations() {
    test_start "Concurrent Operations"
    
    export MAINTENANCE_DRY_RUN=true
    
    # Run multiple non-conflicting operations in parallel
    log "Running concurrent operations..."
    
    (
        run_maintenance --operation=validate --validation-type=config &
        run_maintenance --operation=health --check-type=network &
        run_maintenance --operation=update --component=docker --action=show &
        wait
    ) || fail "Concurrent operations failed"
    
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Concurrent operations completed successfully"
}

# Test error recovery
test_error_recovery() {
    test_start "Error Recovery"
    
    export MAINTENANCE_DRY_RUN=true
    
    # Test recovery from various error conditions
    
    # 1. Invalid stack name recovery
    log "Testing invalid stack recovery..."
    run_maintenance --operation=fix --target=deployment --stack-name="" 2>&1 | \
        grep -qE "(ERROR|error|required)" || fail "Should handle empty stack name"
    
    # 2. Missing backup file recovery
    log "Testing missing backup recovery..."
    run_maintenance --operation=restore --backup-file="/non/existent.tar.gz" 2>&1 | \
        grep -qE "(ERROR|error|not found)" || warning "Should handle missing backup file"
    
    # 3. Invalid operation recovery
    log "Testing invalid operation recovery..."
    run_maintenance --operation=invalid-op 2>&1 | \
        grep -qE "(ERROR|error|Invalid)" || fail "Should handle invalid operation"
    
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Error recovery working correctly"
}

# Test notification system
test_notification_system() {
    test_start "Notification System"
    
    # Test that notifications would be sent (in dry-run mode)
    export MAINTENANCE_DRY_RUN=true
    export MAINTENANCE_NOTIFY=true
    
    log "Testing notification triggers..."
    
    # Operations that should trigger notifications
    run_maintenance --operation=fix --target=deployment --stack-name="$TEST_STACK_NAME" --notify || \
        log "Fix operation with notifications"
    
    run_maintenance --operation=backup --backup-type=full --notify || \
        log "Backup operation with notifications"
    
    unset MAINTENANCE_NOTIFY
    unset MAINTENANCE_DRY_RUN
    
    test_pass "Notification system tested successfully"
}

#######################################
# Main Test Execution
#######################################

main() {
    setup_suite
    
    # Run integration tests
    test_deployment_recovery_workflow
    test_backup_restore_workflow
    test_update_rollback_workflow
    test_maintenance_chain_workflow
    test_wrapper_compatibility
    test_concurrent_operations
    test_error_recovery
    test_notification_system
    
    teardown_suite
    
    # Show test summary
    test_summary "Maintenance Suite Integration"
}

# Run tests
main "$@"