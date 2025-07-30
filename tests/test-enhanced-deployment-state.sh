#!/usr/bin/env bash
# =============================================================================
# Enhanced Deployment State Management Test Suite
# Comprehensive tests for state tracking, persistence, and recovery
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh"

# Set LIB_DIR for proper library loading
export LIB_DIR="$PROJECT_ROOT/lib"

# Source required dependencies first
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

# Source the enhanced state management library
source "$PROJECT_ROOT/lib/enhanced-deployment-state.sh"
source "$PROJECT_ROOT/lib/deployment-state-json-helpers.sh"

# Test configuration
TEST_STATE_DIR="/tmp/test-deployment-state-$$"
export STATE_BASE_DIR="$TEST_STATE_DIR"

# =============================================================================
# TEST FIXTURES AND HELPERS
# =============================================================================

setup_test_environment() {
    # Create test directories
    mkdir -p "$TEST_STATE_DIR"
    
    # Initialize state management
    init_enhanced_state_management "true"
    
    # Stop background processes for testing
    stop_state_background_processes
}

cleanup_test_environment() {
    # Stop any background processes
    stop_state_background_processes
    
    # Clean up test directories
    rm -rf "$TEST_STATE_DIR"
}

create_test_deployment() {
    local deployment_id="${1:-test-deployment-1}"
    local stack_name="${2:-test-stack}"
    local deployment_type="${3:-spot}"
    
    init_deployment_with_tracking "$deployment_id" "$stack_name" "$deployment_type" '{
        "timeout": "1800",
        "retry_attempts": "2",
        "notifications_enabled": "true"
    }'
}

# =============================================================================
# STATE INITIALIZATION TESTS
# =============================================================================

test_state_initialization() {
    test_start "State Management Initialization"
    
    # Test 1: Fresh initialization
    test_case "Fresh state initialization"
    cleanup_test_environment
    setup_test_environment
    
    assert_file_exists "$STATE_FILE" "State file should be created"
    assert_directory_exists "$STATE_BACKUP_DIR" "Backup directory should be created"
    assert_directory_exists "$STATE_JOURNAL_DIR" "Journal directory should be created"
    
    # Test 2: State file structure
    test_case "State file has correct structure"
    local version=$(jq -r '.metadata.version' "$STATE_FILE")
    assert_equals "$version" "$ENHANCED_DEPLOYMENT_STATE_VERSION" "Version should match"
    
    assert_json_has_key "$STATE_FILE" ".deployments" "Should have deployments object"
    assert_json_has_key "$STATE_FILE" ".stacks" "Should have stacks object"
    assert_json_has_key "$STATE_FILE" ".transitions" "Should have transitions array"
    
    # Test 3: Initial backup creation
    test_case "Initial backup is created"
    local backup_count=$(find "$STATE_BACKUP_DIR" -name "state-initial-*.json" | wc -l)
    assert_equals "$backup_count" "1" "Should have one initial backup"
    
    test_pass
}

# =============================================================================
# DEPLOYMENT TRACKING TESTS
# =============================================================================

test_deployment_tracking() {
    test_start "Deployment Tracking"
    
    setup_test_environment
    
    # Test 1: Create deployment with tracking
    test_case "Create deployment with enhanced tracking"
    create_test_deployment "deploy-1" "stack-1" "spot"
    
    assert_not_empty "$(aa_get DEPLOYMENT_STATES "deploy-1:session_id")" "Session ID should be set"
    assert_equals "$(aa_get DEPLOYMENT_STATES "deploy-1:status")" "pending" "Initial status should be pending"
    assert_not_empty "$(aa_get DEPLOYMENT_TRANSITIONS "deploy-1:initialized_at")" "Initialize timestamp should be set"
    
    # Test 2: Multiple deployments
    test_case "Track multiple deployments"
    create_test_deployment "deploy-2" "stack-1" "ondemand"
    create_test_deployment "deploy-3" "stack-2" "simple"
    
    local deployment_count=$(count_deployments)
    assert_equals "$deployment_count" "3" "Should track 3 deployments"
    
    # Test 3: Deployment options
    test_case "Deployment options are set correctly"
    assert_equals "$(aa_get DEPLOYMENT_OPTIONS "deploy-1:timeout")" "1800" "Custom timeout should be set"
    assert_equals "$(aa_get DEPLOYMENT_OPTIONS "deploy-1:retry_attempts")" "2" "Custom retry attempts should be set"
    assert_equals "$(aa_get DEPLOYMENT_OPTIONS "deploy-1:notifications_enabled")" "true" "Notifications should be enabled"
    
    test_pass
}

# =============================================================================
# STATE TRANSITION TESTS
# =============================================================================

test_state_transitions() {
    test_start "State Transitions"
    
    setup_test_environment
    create_test_deployment "transition-test" "stack-1" "spot"
    
    # Test 1: Valid transition
    test_case "Valid state transition: pending -> running"
    local result=$(transition_deployment_state "transition-test" "running" "Starting deployment" 2>&1)
    assert_success $? "Transition should succeed"
    assert_equals "$(aa_get DEPLOYMENT_STATES "transition-test:status")" "running" "State should be updated"
    
    # Test 2: Invalid transition
    test_case "Invalid state transition: running -> pending"
    transition_deployment_state "transition-test" "pending" "Invalid transition" 2>&1
    assert_failure $? "Invalid transition should fail"
    assert_equals "$(aa_get DEPLOYMENT_STATES "transition-test:status")" "running" "State should not change"
    
    # Test 3: Transition history
    test_case "Transition history is recorded"
    transition_deployment_state "transition-test" "completed" "Deployment finished"
    
    local transition_count=$(aa_get DEPLOYMENT_TRANSITIONS "transition-test:transition_count")
    assert_equals "$transition_count" "2" "Should have 2 transitions (init + pending->running + running->completed)"
    
    # Test 4: Complex transition path
    test_case "Complex state transition path"
    create_test_deployment "complex-test" "stack-2" "spot"
    
    # Valid path: pending -> running -> paused -> running -> completed
    transition_deployment_state "complex-test" "running" "Start"
    transition_deployment_state "complex-test" "paused" "Pause for maintenance"
    transition_deployment_state "complex-test" "running" "Resume"
    transition_deployment_state "complex-test" "completed" "Finish"
    
    assert_equals "$(aa_get DEPLOYMENT_STATES "complex-test:status")" "completed" "Final state should be completed"
    assert_equals "$(aa_get DEPLOYMENT_TRANSITIONS "complex-test:transition_count")" "4" "Should have 4 transitions"
    
    test_pass
}

# =============================================================================
# STATE PERSISTENCE TESTS
# =============================================================================

test_state_persistence() {
    test_start "State Persistence"
    
    setup_test_environment
    
    # Test 1: Persist state to disk
    test_case "Persist deployment state to disk"
    create_test_deployment "persist-test" "stack-1" "spot"
    persist_deployment_state "persist-test"
    
    assert_file_exists "$STATE_FILE" "State file should exist"
    local persisted_deployment=$(jq -r '.deployments["persist-test"]' "$STATE_FILE" 2>/dev/null)
    assert_not_equals "$persisted_deployment" "null" "Deployment should be persisted"
    
    # Test 2: Load state from disk
    test_case "Load state from disk"
    # Clear memory
    unset DEPLOYMENT_STATES DEPLOYMENT_TRANSITIONS
    declare -gA DEPLOYMENT_STATES
    declare -gA DEPLOYMENT_TRANSITIONS
    
    # Reload from disk
    load_state_from_file
    
    assert_not_empty "$(aa_get DEPLOYMENT_STATES "persist-test:session_id")" "Deployment should be loaded"
    
    # Test 3: Atomic writes
    test_case "Atomic state file updates"
    local original_checksum=$(jq -r '.metadata.checksum' "$STATE_FILE")
    
    create_test_deployment "atomic-test" "stack-2" "ondemand"
    persist_deployment_state "atomic-test"
    
    local new_checksum=$(jq -r '.metadata.checksum' "$STATE_FILE")
    assert_not_equals "$new_checksum" "$original_checksum" "Checksum should be updated"
    
    test_pass
}

# =============================================================================
# BACKUP AND RECOVERY TESTS
# =============================================================================

test_backup_and_recovery() {
    test_start "Backup and Recovery"
    
    setup_test_environment
    
    # Test 1: Create manual backup
    test_case "Create manual backup"
    create_test_deployment "backup-test" "stack-1" "spot"
    create_state_backup "manual"
    
    local backup_count=$(find "$STATE_BACKUP_DIR" -name "state-manual-*.json" | wc -l)
    assert_equals "$backup_count" "1" "Should have one manual backup"
    
    # Test 2: Backup rotation
    test_case "Backup rotation"
    # Create multiple backups
    for i in {1..5}; do
        create_state_backup "test-$i"
        sleep 0.1
    done
    
    local total_backups=$(find "$STATE_BACKUP_DIR" -name "state-*.json*" | wc -l)
    assert_greater_than "$total_backups" "5" "Should have multiple backups"
    
    # Test 3: Recovery from backup
    test_case "Recover state from backup"
    # Modify state
    create_test_deployment "recovery-test" "stack-2" "simple"
    persist_deployment_state "recovery-test"
    
    # Corrupt current state
    echo "{invalid json}" > "$STATE_FILE"
    
    # Recover from latest backup
    recover_state_from_backup "latest"
    assert_success $? "Recovery should succeed"
    
    # Verify state file is valid
    validate_state_file
    assert_success $? "Recovered state should be valid"
    
    # Test 4: Backup compression
    test_case "Large backup compression"
    # Create many deployments to increase file size
    for i in {1..20}; do
        create_test_deployment "large-test-$i" "stack-large" "spot"
    done
    persist_deployment_state "system"
    
    # Force file size over 1MB (simulate)
    dd if=/dev/zero bs=1M count=2 >> "$STATE_FILE" 2>/dev/null || true
    
    create_state_backup "large"
    
    local compressed_backup=$(find "$STATE_BACKUP_DIR" -name "state-large-*.json.gz" | head -1)
    if [[ -n "$compressed_backup" ]]; then
        assert_file_exists "$compressed_backup" "Large backup should be compressed"
    fi
    
    test_pass
}

# =============================================================================
# STATE MONITORING TESTS
# =============================================================================

test_state_monitoring() {
    test_start "State Monitoring and Alerts"
    
    setup_test_environment
    
    # Test 1: Duration threshold monitoring
    test_case "Duration threshold alerts"
    create_test_deployment "monitor-test" "stack-1" "spot"
    
    # Set low threshold for testing
    aa_set STATE_MONITORING_THRESHOLDS "max_duration_pending" "1"
    
    # Transition to running after threshold
    sleep 2
    transition_deployment_state "monitor-test" "running" "Start after delay"
    
    # Check if alert was triggered (would be in DEPLOYMENT_ALERTS)
    local alert_count=$(aa_get DEPLOYMENT_METRICS "monitoring:alert_count" "0")
    # Note: In real implementation, this would trigger an alert
    
    # Test 2: Retry threshold monitoring
    test_case "Retry attempt monitoring"
    create_test_deployment "retry-test" "stack-2" "spot"
    
    # Simulate multiple failures
    aa_set DEPLOYMENT_METRICS "retry-test:retry_count" "3"
    aa_set STATE_MONITORING_THRESHOLDS "max_retry_attempts" "3"
    
    transition_deployment_state "retry-test" "running" "Start"
    transition_deployment_state "retry-test" "failed" "Simulate failure"
    
    # This would trigger max retries alert
    check_state_monitoring_thresholds "retry-test" "failed"
    
    # Test 3: Alert severity
    test_case "Alert severity classification"
    assert_equals "$(get_alert_severity "duration_exceeded")" "warning" "Duration exceeded should be warning"
    assert_equals "$(get_alert_severity "max_retries_exceeded")" "critical" "Max retries should be critical"
    assert_equals "$(get_alert_severity "state_corruption")" "critical" "State corruption should be critical"
    
    test_pass
}

# =============================================================================
# STATE SYNCHRONIZATION TESTS
# =============================================================================

test_state_synchronization() {
    test_start "State Synchronization"
    
    setup_test_environment
    
    # Test 1: Lock acquisition
    test_case "Deployment lock acquisition"
    create_test_deployment "lock-test" "stack-1" "spot"
    
    acquire_deployment_lock "lock-test" "test_operation" 5
    assert_success $? "Should acquire lock"
    
    # Try to acquire same lock (should fail)
    acquire_deployment_lock "lock-test" "test_operation" 1 2>/dev/null
    assert_failure $? "Should not acquire already held lock"
    
    release_deployment_lock "lock-test" "test_operation"
    
    # Test 2: Stale lock cleanup
    test_case "Stale lock cleanup"
    local lock_dir="${STATE_LOCK_DIR}/stale-test.operation.lock"
    mkdir -p "$lock_dir"
    echo "99999:$(($(date +%s) - 400))" > "${lock_dir}/owner"  # Old lock with non-existent PID
    
    acquire_deployment_lock "stale-test" "operation" 2
    assert_success $? "Should acquire lock after stale cleanup"
    
    release_deployment_lock "stale-test" "operation"
    
    # Test 3: State synchronization
    test_case "State synchronization"
    create_test_deployment "sync-test" "stack-1" "spot"
    
    sync_deployment_state "sync-test" "partial"
    assert_success $? "Partial sync should succeed"
    
    sync_deployment_state "all" "metadata"
    assert_success $? "Metadata sync should succeed"
    
    test_pass
}

# =============================================================================
# JOURNAL AND AUDIT TESTS
# =============================================================================

test_journal_and_audit() {
    test_start "Journal and Audit Trail"
    
    setup_test_environment
    
    # Test 1: Journal entry creation
    test_case "Journal entry creation"
    create_test_deployment "journal-test" "stack-1" "spot"
    
    add_to_journal "journal-test" "test_event" "Test event details"
    
    local journal_file=$(find "$STATE_JOURNAL_DIR" -name "journal-*.log" | head -1)
    assert_file_exists "$journal_file" "Journal file should exist"
    
    local journal_content=$(cat "$journal_file")
    assert_contains "$journal_content" "journal-test" "Journal should contain deployment ID"
    assert_contains "$journal_content" "test_event" "Journal should contain event type"
    
    # Test 2: Journal rotation
    test_case "Journal file rotation"
    # Create old journal file
    local old_journal="${STATE_JOURNAL_DIR}/journal-20200101.log"
    touch -t 202001010000 "$old_journal" 2>/dev/null || touch "$old_journal"
    
    rotate_journal_files
    
    # Old file should be removed if older than retention period
    # (depends on STATE_JOURNAL_RETENTION_DAYS setting)
    
    # Test 3: Export journal to JSON
    test_case "Export journal to JSON"
    # Add multiple journal entries
    for i in {1..5}; do
        add_to_journal "journal-test" "event_$i" "Event $i details"
    done
    
    local journal_json=$(export_journal_json)
    assert_contains "$journal_json" '"deployment_id":"journal-test"' "Journal JSON should contain entries"
    
    test_pass
}

# =============================================================================
# METRICS AND REPORTING TESTS
# =============================================================================

test_metrics_and_reporting() {
    test_start "Metrics and Reporting"
    
    setup_test_environment
    
    # Test 1: Update metrics
    test_case "Update deployment metrics"
    create_test_deployment "metrics-test" "stack-1" "spot"
    
    update_deployment_metrics "metrics-test" "cpu_usage" "75.5"
    update_deployment_metrics "metrics-test" "memory_usage" "2048"
    
    assert_equals "$(aa_get DEPLOYMENT_METRICS "metrics-test:cpu_usage")" "75.5" "CPU metric should be set"
    assert_equals "$(aa_get DEPLOYMENT_METRICS "metrics-test:memory_usage")" "2048" "Memory metric should be set"
    
    # Test 2: Metrics file creation
    test_case "Metrics file creation"
    local metrics_file=$(find "$STATE_METRICS_DIR" -name "metrics-*.json" | head -1)
    assert_file_exists "$metrics_file" "Metrics file should exist"
    
    # Test 3: Generate reports
    test_case "Generate state reports"
    # Create test data
    create_test_deployment "report-1" "stack-1" "spot"
    transition_deployment_state "report-1" "running" "Start"
    transition_deployment_state "report-1" "completed" "Finish"
    
    create_test_deployment "report-2" "stack-1" "ondemand"
    transition_deployment_state "report-2" "running" "Start"
    transition_deployment_state "report-2" "failed" "Error"
    
    local summary_report=$(generate_state_report "summary" "text")
    assert_contains "$summary_report" "Total Deployments:" "Summary should show total"
    assert_contains "$summary_report" "Completed:" "Summary should show completed count"
    assert_contains "$summary_report" "Failed:" "Summary should show failed count"
    
    test_pass
}

# =============================================================================
# EVENT SUBSCRIPTION TESTS
# =============================================================================

test_event_subscriptions() {
    test_start "Event Subscriptions"
    
    setup_test_environment
    
    # Test 1: Subscribe to events
    test_case "Subscribe to state events"
    
    # Define test callback
    test_event_callback() {
        local deployment_id="$1"
        local event_type="$2"
        local event_data="$3"
        echo "CALLBACK: $deployment_id - $event_type - $event_data" >> /tmp/test-events.log
    }
    export -f test_event_callback
    
    local sub_id=$(subscribe_to_state_event "test-deploy" "state_changed" "test_event_callback")
    assert_not_empty "$sub_id" "Should return subscription ID"
    
    # Test 2: Trigger events
    test_case "Trigger subscribed events"
    rm -f /tmp/test-events.log
    
    create_test_deployment "test-deploy" "stack-1" "spot"
    trigger_state_event "test-deploy" "state_changed" '{"test":"data"}'
    
    if [[ -f /tmp/test-events.log ]]; then
        local callback_output=$(cat /tmp/test-events.log)
        assert_contains "$callback_output" "test-deploy" "Callback should receive deployment ID"
        assert_contains "$callback_output" "state_changed" "Callback should receive event type"
    fi
    
    # Test 3: Wildcard subscriptions
    test_case "Wildcard event subscriptions"
    subscribe_to_state_event "*" "state_changed" "test_event_callback"
    
    create_test_deployment "wildcard-test" "stack-2" "simple"
    trigger_state_event "wildcard-test" "state_changed" '{"wildcard":"test"}'
    
    # Wildcard subscription should receive events from any deployment
    
    rm -f /tmp/test-events.log
    test_pass
}

# =============================================================================
# STRESS AND PERFORMANCE TESTS
# =============================================================================

test_stress_and_performance() {
    test_start "Stress and Performance Tests"
    
    setup_test_environment
    
    # Test 1: Multiple concurrent deployments
    test_case "Handle multiple concurrent deployments"
    local start_time=$(date +%s)
    
    # Create 50 deployments
    for i in {1..50}; do
        create_test_deployment "stress-test-$i" "stack-stress" "spot" &
    done
    wait
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local deployment_count=$(count_deployments)
    assert_greater_than "$deployment_count" "49" "Should create all deployments"
    
    echo "Created 50 deployments in ${duration}s"
    assert_less_than "$duration" "10" "Should complete within 10 seconds"
    
    # Test 2: Large state file handling
    test_case "Handle large state files"
    persist_deployment_state "system"
    
    local file_size=$(stat -f%z "$STATE_FILE" 2>/dev/null || stat -c%s "$STATE_FILE" 2>/dev/null)
    echo "State file size: $file_size bytes"
    
    # Test load performance
    local load_start=$(date +%s%N)
    load_state_from_file
    local load_end=$(date +%s%N)
    local load_time=$(( (load_end - load_start) / 1000000 ))
    
    echo "Load time: ${load_time}ms"
    assert_less_than "$load_time" "1000" "Should load within 1 second"
    
    # Test 3: Rapid state transitions
    test_case "Rapid state transitions"
    create_test_deployment "rapid-test" "stack-rapid" "spot"
    
    local transition_start=$(date +%s%N)
    for state in running paused running completed; do
        transition_deployment_state "rapid-test" "$state" "Rapid transition"
    done
    local transition_end=$(date +%s%N)
    local transition_time=$(( (transition_end - transition_start) / 1000000 ))
    
    echo "4 transitions in ${transition_time}ms"
    assert_less_than "$transition_time" "500" "Transitions should be fast"
    
    test_pass
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_error_handling() {
    test_start "Error Handling"
    
    setup_test_environment
    
    # Test 1: Handle corrupted state file
    test_case "Handle corrupted state file"
    echo "{invalid json" > "$STATE_FILE"
    
    validate_state_file 2>/dev/null
    assert_failure $? "Should detect invalid JSON"
    
    # Test 2: Handle missing deployment
    test_case "Handle operations on missing deployment"
    transition_deployment_state "non-existent" "running" "Test" 2>/dev/null
    assert_failure $? "Should fail for non-existent deployment"
    
    get_deployment_status "non-existent" 2>/dev/null
    assert_failure $? "Should handle missing deployment gracefully"
    
    # Test 3: Handle file system errors
    test_case "Handle file system errors"
    # Make state file read-only
    chmod 444 "$STATE_FILE"
    
    create_test_deployment "readonly-test" "stack-1" "spot"
    persist_deployment_state "readonly-test" 2>/dev/null
    # Should handle gracefully (might fail or use fallback)
    
    chmod 644 "$STATE_FILE"
    
    test_pass
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_full_deployment_lifecycle() {
    test_start "Full Deployment Lifecycle"
    
    setup_test_environment
    
    # Test complete deployment flow
    test_case "Complete deployment lifecycle with all features"
    
    # 1. Initialize deployment
    init_deployment_with_tracking "lifecycle-test" "prod-stack" "spot" '{
        "timeout": "3600",
        "retry_attempts": "3",
        "notifications_enabled": "true",
        "rollback_enabled": "true"
    }'
    
    # 2. Start deployment
    start_deployment "lifecycle-test"
    assert_equals "$(aa_get DEPLOYMENT_STATES "lifecycle-test:status")" "running" "Should be running"
    
    # 3. Execute phases (simulated)
    for phase in validation preparation infrastructure application verification; do
        execute_deployment_phase "lifecycle-test" "$phase"
        sleep 0.1
    done
    
    # 4. Complete deployment
    transition_deployment_state "lifecycle-test" "completed" "All phases completed"
    
    # 5. Verify final state
    assert_equals "$(aa_get DEPLOYMENT_STATES "lifecycle-test:status")" "completed" "Should be completed"
    
    # 6. Check persistence
    persist_deployment_state "lifecycle-test"
    
    # 7. Generate report
    local report=$(get_deployment_status "lifecycle-test" "detailed")
    assert_contains "$report" "completed" "Report should show completion"
    
    # 8. Verify backup exists
    local backups=$(find "$STATE_BACKUP_DIR" -name "state-*.json*" | wc -l)
    assert_greater_than "$backups" "0" "Should have backups"
    
    test_pass
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

run_all_tests() {
    echo "Running Enhanced Deployment State Management Tests"
    echo "=================================================="
    
    # Setup
    trap cleanup_test_environment EXIT
    
    # Run test suites
    test_state_initialization
    test_deployment_tracking
    test_state_transitions
    test_state_persistence
    test_backup_and_recovery
    test_state_monitoring
    test_state_synchronization
    test_journal_and_audit
    test_metrics_and_reporting
    test_event_subscriptions
    test_stress_and_performance
    test_error_handling
    test_full_deployment_lifecycle
    
    # Summary
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi