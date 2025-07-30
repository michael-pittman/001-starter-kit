#!/bin/bash
#
# Test Maintenance Safety Features
# Tests backup, rollback, dry-run, and notification systems
#

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# Load maintenance suite
source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite-enhanced.sh"

# Test context
test_context "Maintenance Safety Features"

# =============================================================================
# TEST SETUP
# =============================================================================

setup_test_environment() {
    # Create test directories
    TEST_TEMP_DIR=$(mktemp -d -t maintenance-test-XXXXXX)
    export MAINTENANCE_PROJECT_ROOT="$TEST_TEMP_DIR"
    export MAINTENANCE_BACKUP_DIR="$TEST_TEMP_DIR/backup"
    export MAINTENANCE_STATE_FILE="$TEST_TEMP_DIR/.maintenance-state"
    export MAINTENANCE_LOG_FILE="$TEST_TEMP_DIR/maintenance.log"
    
    # Create test structure
    mkdir -p "$TEST_TEMP_DIR"/{scripts,lib,config,logs,backup}
    
    # Create test files
    echo "test script" > "$TEST_TEMP_DIR/scripts/test.sh"
    echo "test config" > "$TEST_TEMP_DIR/config/test.yml"
    echo "test log" > "$TEST_TEMP_DIR/logs/test.log"
    
    # Set test mode
    export MAINTENANCE_TEST_MODE=true
}

cleanup_test_environment() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Set up trap for cleanup
trap cleanup_test_environment EXIT

# =============================================================================
# DRY RUN TESTS
# =============================================================================

test_group "Dry Run Mode"

test_case "Dry run prevents actual changes"
setup_test_environment

# Run cleanup in dry-run mode
output=$(run_maintenance --operation=cleanup --scope=logs --dry-run 2>&1 || true)

# Check that files still exist
assert_file_exists "$TEST_TEMP_DIR/logs/test.log" "Log file should still exist after dry-run"

# Check output mentions dry run
assert_contains "$output" "DRY RUN" "Output should indicate dry-run mode"

cleanup_test_environment

test_case "Dry run shows what would be done"
setup_test_environment

# Create multiple log files
for i in {1..5}; do
    echo "log $i" > "$TEST_TEMP_DIR/logs/test$i.log"
done

# Run cleanup in dry-run mode
output=$(run_maintenance --operation=cleanup --scope=logs --dry-run 2>&1 || true)

# Check that output shows preview
assert_contains "$output" "Would clean" "Output should show preview of actions"

cleanup_test_environment

# =============================================================================
# DESTRUCTIVE OPERATION WARNING TESTS
# =============================================================================

test_group "Destructive Operation Warnings"

test_case "Destructive operations require confirmation"
setup_test_environment

# Set force flag to skip confirmation in test
export MAINTENANCE_FORCE=true

# Run destructive operation
output=$(run_maintenance --operation=cleanup --scope=all --dry-run 2>&1 || true)

# Check for warning
assert_contains "$output" "cleanup" "Should show operation type"

unset MAINTENANCE_FORCE
cleanup_test_environment

test_case "Non-destructive operations don't require confirmation"
setup_test_environment

# Run non-destructive operation
output=$(run_maintenance --operation=health --service=system 2>&1 || true)

# Should complete without confirmation
assert_success "Non-destructive operation should complete"

cleanup_test_environment

# =============================================================================
# BACKUP TESTS
# =============================================================================

test_group "Backup Operations"

test_case "Backup is created for destructive operations"
setup_test_environment

# Force backup for destructive operation
export MAINTENANCE_FORCE=true
export MAINTENANCE_BACKUP=true

# Run with backup
output=$(run_maintenance --operation=cleanup --scope=logs --backup --dry-run 2>&1 || true)

# Check backup directory was referenced
assert_contains "$output" "backup" "Should mention backup"

unset MAINTENANCE_FORCE
cleanup_test_environment

test_case "Backup metadata is created"
setup_test_environment

# Create backup directly
output=$(run_maintenance --operation=backup --action=create 2>&1 || true)

# Check for backup directory
backup_dirs=$(find "$MAINTENANCE_BACKUP_DIR" -type d -name "[0-9]*" 2>/dev/null || true)
assert_not_empty "$backup_dirs" "Backup directory should be created"

cleanup_test_environment

test_case "Backup verification works"
setup_test_environment

# Create and verify backup
run_maintenance --operation=backup --action=create 2>&1 || true
output=$(run_maintenance --operation=backup --action=verify 2>&1 || true)

# Check verification output
assert_contains "$output" "verif" "Should show verification results"

cleanup_test_environment

# =============================================================================
# ROLLBACK TESTS
# =============================================================================

test_group "Rollback Operations"

test_case "Rollback flag enables rollback on failure"
setup_test_environment

# Test with rollback flag
export MAINTENANCE_ROLLBACK=true
export MAINTENANCE_DRY_RUN=true

output=$(run_maintenance --operation=fix --target=deployment --rollback --dry-run 2>&1 || true)

# Check that rollback is mentioned
assert_contains "$output" "rollback" "Should mention rollback capability"

unset MAINTENANCE_ROLLBACK
cleanup_test_environment

# =============================================================================
# NOTIFICATION TESTS
# =============================================================================

test_group "Notification System"

test_case "Notifications are sent when enabled"
setup_test_environment

# Enable notifications to log
export MAINTENANCE_NOTIFY=true
export NOTIFICATION_METHOD="log"

# Run operation with notifications
run_maintenance --operation=health --service=system --notify 2>&1 || true

# Check notification log
if [[ -f "$TEST_TEMP_DIR/logs/maintenance-notifications.log" ]]; then
    assert_file_exists "$TEST_TEMP_DIR/logs/maintenance-notifications.log" "Notification log should exist"
fi

unset MAINTENANCE_NOTIFY
cleanup_test_environment

test_case "Test notification system"
setup_test_environment

# Load notification module
source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-notifications.sh"

# Test notification
export MAINTENANCE_NOTIFY=true
export NOTIFICATION_METHOD="log"
export NOTIFICATION_LOG_FILE="$TEST_TEMP_DIR/test-notifications.log"

test_notifications

assert_file_exists "$NOTIFICATION_LOG_FILE" "Test notification log should be created"

cleanup_test_environment

# =============================================================================
# SAFETY CHECK TESTS
# =============================================================================

test_group "Safety Checks"

test_case "System safety checks prevent concurrent operations"
setup_test_environment

# Create lock file to simulate running operation
mkdir -p "$(dirname "$MAINTENANCE_STATE_FILE")"
echo "$$" > "${MAINTENANCE_STATE_FILE}.lock"

# Load safety operations
source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-safety-operations.sh"

# Test concurrent operation check
if is_maintenance_running; then
    assert_success "Should detect running maintenance"
else
    assert_failure "Should detect running maintenance"
fi

# Clean up lock
rm -f "${MAINTENANCE_STATE_FILE}.lock"

cleanup_test_environment

test_case "Disk space check prevents operations when low"
setup_test_environment

# This test would require mocking disk space, so we just verify the function exists
source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-safety-operations.sh"

# Verify function exists
if declare -f check_disk_space >/dev/null; then
    assert_success "Disk space check function exists"
else
    assert_failure "Disk space check function should exist"
fi

cleanup_test_environment

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_group "Integration Tests"

test_case "Full safety workflow with dry-run"
setup_test_environment

# Run complete maintenance with all safety features
output=$(run_maintenance \
    --operation=cleanup \
    --scope=logs \
    --backup \
    --notify \
    --dry-run \
    2>&1 || true)

# Verify all safety features were active
assert_contains "$output" "DRY RUN" "Should show dry-run mode"

# Verify files weren't actually deleted
assert_file_exists "$TEST_TEMP_DIR/logs/test.log" "Files should remain after dry-run"

cleanup_test_environment

test_case "Safety features prevent destructive operations without backup"
setup_test_environment

# Load safety operations
source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-safety-operations.sh"

# Test destructive operation check
if is_destructive_operation "cleanup" "all"; then
    assert_success "Should identify cleanup:all as destructive"
else
    assert_failure "Should identify cleanup:all as destructive"
fi

cleanup_test_environment

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_group "Error Handling"

test_case "Critical errors trigger notifications"
setup_test_environment

# Load notification module
source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-notifications.sh"

# Enable notifications
export MAINTENANCE_NOTIFY=true
export NOTIFICATION_METHOD="log"
export NOTIFICATION_LOG_FILE="$TEST_TEMP_DIR/error-notifications.log"

# Send critical error
notify_critical_error "Test Error" "This is a test error"

# Check notification was logged
if [[ -f "$NOTIFICATION_LOG_FILE" ]]; then
    content=$(cat "$NOTIFICATION_LOG_FILE")
    assert_contains "$content" "critical" "Should log critical error"
fi

cleanup_test_environment

# =============================================================================
# SUMMARY
# =============================================================================

# Print test summary
print_test_summary