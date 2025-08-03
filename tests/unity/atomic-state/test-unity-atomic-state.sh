#!/bin/bash
# Unity Atomic State Management Tests
# Comprehensive test suite for atomic writes, recovery, and failure scenarios

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load test framework
source "$PROJECT_ROOT/tests/lib/test-framework.sh"
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
source "$PROJECT_ROOT/lib/unity/core/unity-atomic-state.sh"

# Test configuration
TEST_SUITE_NAME="Unity Atomic State Management"
TEST_STATE_DIR=".unity-test/atomic-state-test"
TEST_BACKUP_DIR=".unity-test/atomic-state-test/backups"
TEST_LOCK_DIR=".unity-test/atomic-state-test/locks"
TEST_TEMP_DIR=".unity-test/atomic-state-test/temp"

# Override atomic state directories for testing
export UNITY_ATOMIC_STATE_DIR="$TEST_STATE_DIR"
export UNITY_ATOMIC_BACKUP_DIR="$TEST_BACKUP_DIR"
export UNITY_ATOMIC_LOCK_DIR="$TEST_LOCK_DIR"
export UNITY_ATOMIC_TEMP_DIR="$TEST_TEMP_DIR"
export UNITY_ATOMIC_MAX_BACKUP_COUNT=5
export UNITY_ATOMIC_LOCK_TIMEOUT=10

#############################################
# Test Setup and Teardown
#############################################

setup_atomic_tests() {
    unity_log "INFO" "Setting up atomic state tests..."
    
    # Clean up any existing test state
    rm -rf ".unity-test" 2>/dev/null || true
    
    # Initialize Unity core for testing
    unity_init >/dev/null 2>&1 || true
    
    # Initialize atomic state system
    init_unity_atomic_state
    
    unity_log "DEBUG" "Atomic state test setup completed"
}

teardown_atomic_tests() {
    unity_log "INFO" "Cleaning up atomic state tests..."
    
    # Clean up test directories
    rm -rf ".unity-test" 2>/dev/null || true
    
    unity_log "DEBUG" "Atomic state test cleanup completed"
}

#############################################
# Basic Atomic Write Tests
#############################################

test_atomic_write_basic() {
    test_start "Basic atomic write functionality"
    
    local test_file="$TEST_STATE_DIR/test-basic.json"
    local test_content='{"test": "basic", "value": 123, "timestamp": '$(date +%s)'}'
    
    # Test basic atomic write
    if unity_atomic_write "$test_file" "$test_content" "json" "false"; then
        test_assert_file_exists "$test_file"
        
        # Verify content
        local read_content
        read_content="$(unity_atomic_read "$test_file" "true")"
        test_assert_equals "$test_content" "$read_content" "Content verification"
        
        # Verify checksum file exists
        test_assert_file_exists "${test_file}.checksum"
        
        test_pass
    else
        test_fail "Atomic write failed"
    fi
}

test_atomic_write_json_validation() {
    test_start "JSON validation during atomic write"
    
    local test_file="$TEST_STATE_DIR/test-validation.json"
    local valid_json='{"valid": true, "data": [1, 2, 3]}'
    local invalid_json='{"invalid": true, "unclosed": [1, 2, 3'
    
    # Test valid JSON
    if unity_atomic_write "$test_file" "$valid_json" "json" "false"; then
        test_assert_file_exists "$test_file"
    else
        test_fail "Valid JSON write failed"
        return
    fi
    
    # Test invalid JSON (should fail)
    if unity_atomic_write "$test_file" "$invalid_json" "json" "false"; then
        test_fail "Invalid JSON was accepted"
    else
        # File should still contain valid content
        local read_content
        read_content="$(unity_atomic_read "$test_file" "true")"
        test_assert_equals "$valid_json" "$read_content" "Original content preserved"
        test_pass
    fi
}

test_atomic_write_with_backup() {
    test_start "Atomic write with backup creation"
    
    local test_file="$TEST_STATE_DIR/test-backup.json"
    local original_content='{"version": 1, "data": "original"}'
    local updated_content='{"version": 2, "data": "updated"}'
    
    # Create initial file
    unity_atomic_write "$test_file" "$original_content" "json" "false"
    test_assert_file_exists "$test_file"
    
    # Update with backup
    if unity_atomic_write "$test_file" "$updated_content" "json" "true"; then
        # Verify updated content
        local read_content
        read_content="$(unity_atomic_read "$test_file" "true")"
        test_assert_equals "$updated_content" "$read_content" "Updated content verification"
        
        # Verify backup was created
        local backup_count
        backup_count="$(find "$TEST_BACKUP_DIR" -name "test-backup.json.*.bak" | wc -l)"
        test_assert_greater_than 0 "$backup_count" "Backup file created"
        
        test_pass
    else
        test_fail "Atomic write with backup failed"
    fi
}

#############################################
# Concurrency and Locking Tests
#############################################

test_file_locking_mechanism() {
    test_start "File locking prevents concurrent writes"
    
    local test_file="$TEST_STATE_DIR/test-locking.json"
    local lock_file="$TEST_LOCK_DIR/test-locking.json.lock"
    
    # Create a lock file manually
    echo "manual_test:$$:$(date +%s)" > "$lock_file"
    
    # Try to write while locked (should fail quickly)
    local start_time=$(date +%s)
    if unity_atomic_write "$test_file" '{"locked": true}' "json" "false"; then
        test_fail "Write succeeded despite lock"
        return
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should have failed within timeout period
    test_assert_less_than_or_equal "$duration" "$((UNITY_ATOMIC_LOCK_TIMEOUT + 2))" "Lock timeout respected"
    
    # Remove lock and try again
    rm -f "$lock_file"
    if unity_atomic_write "$test_file" '{"unlocked": true}' "json" "false"; then
        test_pass
    else
        test_fail "Write failed after lock removal"
    fi
}

test_concurrent_writes() {
    test_start "Concurrent write protection"
    
    local test_file="$TEST_STATE_DIR/test-concurrent.json"
    local results_file="$TEST_TEMP_DIR/concurrent-results.txt"
    
    # Clear results
    echo "" > "$results_file"
    
    # Start multiple writes in background
    for i in {1..5}; do
        (
            sleep 0.$i  # Stagger start times slightly
            if unity_atomic_write "$test_file" "{\"writer\": $i, \"timestamp\": $(date +%s%N)}" "json" "true"; then
                echo "success:$i" >> "$results_file"
            else
                echo "failed:$i" >> "$results_file"
            fi
        ) &
    done
    
    # Wait for all background processes
    wait
    
    # Analyze results
    local success_count failed_count
    success_count="$(grep -c "^success:" "$results_file" || echo "0")"
    failed_count="$(grep -c "^failed:" "$results_file" || echo "0")"
    
    # At least one should succeed, others may fail due to locking
    test_assert_greater_than 0 "$success_count" "At least one write succeeded"
    
    # Final file should exist and be valid
    test_assert_file_exists "$test_file"
    
    local final_content
    final_content="$(unity_atomic_read "$test_file" "true")"
    test_assert_not_empty "$final_content" "Final content exists"
    
    test_pass
}

#############################################
# Recovery and Corruption Tests
#############################################

test_corruption_detection() {
    test_start "Corruption detection via checksum"
    
    local test_file="$TEST_STATE_DIR/test-corruption.json"
    local test_content='{"integrity": "test", "data": [1, 2, 3, 4, 5]}'
    
    # Create file with atomic write
    unity_atomic_write "$test_file" "$test_content" "json" "true"
    test_assert_file_exists "$test_file"
    test_assert_file_exists "${test_file}.checksum"
    
    # Corrupt the file
    echo "CORRUPTED DATA" > "$test_file"
    
    # Check if corruption is detected
    if unity_atomic_needs_recovery "$test_file"; then
        test_pass
    else
        test_fail "Corruption not detected"
    fi
}

test_automatic_recovery() {
    test_start "Automatic recovery from backup"
    
    local test_file="$TEST_STATE_DIR/test-recovery.json"
    local original_content='{"recovery": "test", "version": 1}'
    local updated_content='{"recovery": "test", "version": 2}'
    
    # Create original file
    unity_atomic_write "$test_file" "$original_content" "json" "true"
    
    # Update file (creates backup)
    unity_atomic_write "$test_file" "$updated_content" "json" "true"
    
    # Corrupt the current file
    echo "CORRUPTED" > "$test_file"
    
    # Force recovery
    if unity_atomic_force_recovery "$test_file"; then
        local recovered_content
        recovered_content="$(unity_atomic_read "$test_file" "true")"
        
        # Should have recovered the latest valid version
        test_assert_equals "$updated_content" "$recovered_content" "Recovery restored correct content"
        test_pass
    else
        test_fail "Recovery failed"
    fi
}

test_backup_rotation() {
    test_start "Backup file rotation"
    
    local test_file="$TEST_STATE_DIR/test-rotation.json"
    
    # Create multiple versions to trigger rotation
    for i in {1..8}; do
        local content='{"version": '$i', "data": "backup rotation test"}'
        unity_atomic_write "$test_file" "$content" "json" "true"
        sleep 1  # Ensure different timestamps
    done
    
    # Count backup files
    local backup_count
    backup_count="$(find "$TEST_BACKUP_DIR" -name "test-rotation.json.*.bak" | wc -l)"
    
    # Should not exceed max backup count
    test_assert_less_than_or_equal "$backup_count" "$UNITY_ATOMIC_MAX_BACKUP_COUNT" "Backup rotation working"
    
    test_pass
}

#############################################
# Batch Operations Tests
#############################################

test_batch_atomic_writes() {
    test_start "Batch atomic write operations"
    
    local files=(
        "$TEST_STATE_DIR/batch1.json:{\"file\": 1, \"batch\": true}"
        "$TEST_STATE_DIR/batch2.json:{\"file\": 2, \"batch\": true}"
        "$TEST_STATE_DIR/batch3.json:{\"file\": 3, \"batch\": true}"
    )
    
    # Perform batch write
    if unity_atomic_write_batch files "json" "false"; then
        # Verify all files were created
        for file_spec in "${files[@]}"; do
            local file_path="${file_spec%%:*}"
            local expected_content="${file_spec#*:}"
            
            test_assert_file_exists "$file_path"
            
            local actual_content
            actual_content="$(unity_atomic_read "$file_path" "true")"
            test_assert_equals "$expected_content" "$actual_content" "Batch file content: $(basename "$file_path")"
        done
        
        test_pass
    else
        test_fail "Batch atomic write failed"
    fi
}

test_batch_write_failure_rollback() {
    test_start "Batch write failure rollback"
    
    # Create some existing files first
    unity_atomic_write "$TEST_STATE_DIR/existing1.json" '{"exists": true}' "json" "true"
    unity_atomic_write "$TEST_STATE_DIR/existing2.json" '{"exists": true}' "json" "true"
    
    local files=(
        "$TEST_STATE_DIR/existing1.json:{\"updated\": 1}"
        "$TEST_STATE_DIR/existing2.json:{\"updated\": 2}"
        "$TEST_STATE_DIR/new_file.json:{\"invalid json"  # This will cause validation failure
    )
    
    # Batch write should fail due to invalid JSON
    if unity_atomic_write_batch files "json" "true"; then
        test_fail "Batch write should have failed due to invalid JSON"
        return
    fi
    
    # Verify original files were not modified (rollback occurred)
    local content1 content2
    content1="$(unity_atomic_read "$TEST_STATE_DIR/existing1.json" "true")"
    content2="$(unity_atomic_read "$TEST_STATE_DIR/existing2.json" "true")"
    
    test_assert_equals '{"exists": true}' "$content1" "First file rollback"
    test_assert_equals '{"exists": true}' "$content2" "Second file rollback"
    
    # New file should not exist
    test_assert_file_not_exists "$TEST_STATE_DIR/new_file.json"
    
    test_pass
}

#############################################
# Performance and Stress Tests
#############################################

test_atomic_write_performance() {
    test_start "Atomic write performance benchmark"
    
    local test_file="$TEST_STATE_DIR/performance-test.json"
    local iterations=100
    local start_time end_time duration
    
    start_time=$(date +%s%N)
    
    for i in $(seq 1 $iterations); do
        local content='{"iteration": '$i', "timestamp": '$(date +%s)', "data": "performance test"}'
        unity_atomic_write "$test_file" "$content" "json" "true" >/dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    local avg_time=$((duration / iterations))
    
    unity_log "INFO" "Performance: $iterations writes in ${duration}ms (avg: ${avg_time}ms per write)"
    
    # Performance threshold (should be reasonable)
    test_assert_less_than "$avg_time" 100 "Average write time under 100ms"
    
    test_pass
}

test_large_file_atomic_write() {
    test_start "Large file atomic write"
    
    local test_file="$TEST_STATE_DIR/large-file.json"
    
    # Generate large JSON content (approximately 1MB)
    local large_content='{"large_file": true, "data": "'
    for i in {1..10000}; do
        large_content+="This is line $i with some substantial content to make the file large. "
    done
    large_content+='"}'
    
    if unity_atomic_write "$test_file" "$large_content" "json" "true"; then
        test_assert_file_exists "$test_file"
        
        local read_content
        read_content="$(unity_atomic_read "$test_file" "true")"
        test_assert_equals "$large_content" "$read_content" "Large file content integrity"
        
        test_pass
    else
        test_fail "Large file atomic write failed"
    fi
}

#############################################
# Integration Tests
#############################################

test_transaction_logging() {
    test_start "Transaction logging functionality"
    
    local test_file="$TEST_STATE_DIR/transaction-test.json"
    local content='{"transaction": "test"}'
    
    # Perform several operations
    unity_atomic_write "$test_file" "$content" "json" "true"
    unity_atomic_write "$test_file" '{"transaction": "updated"}' "json" "true"
    unity_atomic_write "$test_file" '{"transaction": "final"}' "json" "true"
    
    # Check transaction history
    local history
    history="$(unity_atomic_get_transaction_history "$test_file" 5)"
    
    test_assert_not_empty "$history" "Transaction history exists"
    
    # Should contain STARTED and COMPLETED entries
    if echo "$history" | grep -q "STARTED" && echo "$history" | grep -q "COMPLETED"; then
        test_pass
    else
        test_fail "Transaction history incomplete"
    fi
}

test_atomic_state_system_status() {
    test_start "Atomic state system status reporting"
    
    # Create some test files to populate the system
    unity_atomic_write "$TEST_STATE_DIR/status-test1.json" '{"test": 1}' "json" "true"
    unity_atomic_write "$TEST_STATE_DIR/status-test2.json" '{"test": 2}' "json" "true"
    
    # Get status output
    local status_output
    status_output="$(unity_atomic_status)"
    
    test_assert_not_empty "$status_output" "Status output generated"
    
    # Check for key status information
    if echo "$status_output" | grep -q "Unity Atomic State Management Status" &&
       echo "$status_output" | grep -q "State Directory" &&
       echo "$status_output" | grep -q "Backup Directory"; then
        test_pass
    else
        test_fail "Status output incomplete"
    fi
}

#############################################
# Main Test Execution
#############################################

run_all_atomic_tests() {
    test_suite_start "$TEST_SUITE_NAME"
    
    # Setup
    setup_atomic_tests
    
    # Basic functionality tests
    test_atomic_write_basic
    test_atomic_write_json_validation
    test_atomic_write_with_backup
    
    # Concurrency tests
    test_file_locking_mechanism
    test_concurrent_writes
    
    # Recovery tests
    test_corruption_detection
    test_automatic_recovery
    test_backup_rotation
    
    # Batch operations
    test_batch_atomic_writes
    test_batch_write_failure_rollback
    
    # Performance tests
    test_atomic_write_performance
    test_large_file_atomic_write
    
    # Integration tests
    test_transaction_logging
    test_atomic_state_system_status
    
    # Cleanup
    teardown_atomic_tests
    
    test_suite_end
}

# Execute tests if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_atomic_tests
fi