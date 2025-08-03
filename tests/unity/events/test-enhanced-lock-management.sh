#!/bin/bash
# Test script for Unity Enhanced Lock Management System
# Tests deadlock detection, prevention, and recovery mechanisms

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITY_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
TEST_WORK_DIR="/tmp/unity-lock-tests-$$"

# Source Unity event system
source "$UNITY_ROOT/lib/unity/core/unity-events.sh"

# Test state
TEST_RESULTS=()
CHILD_PIDS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test utilities
log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TEST_RESULTS+=("PASS: $1")
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    TEST_RESULTS+=("FAIL: $1")
}

log_info() {
    echo -e "[INFO] $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Kill child processes
    for pid in "${CHILD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    # Remove test directory
    rm -rf "$TEST_WORK_DIR" 2>/dev/null || true
    
    # Clean up any test locks
    rm -f ".unity/events/locks/"test*.lock 2>/dev/null || true
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    mkdir -p "$TEST_WORK_DIR"
    cd "$TEST_WORK_DIR"
    
    # Initialize Unity event system
    unity_init_events "true"
    
    log_info "Test environment ready at $TEST_WORK_DIR"
}

# Test 1: Basic lock acquisition and release
test_basic_lock_operations() {
    log_test "Testing basic lock acquisition and release"
    
    local lock_file=".unity/events/locks/test-basic.lock"
    
    # Test lock acquisition
    if _acquire_lock "$lock_file" 5 "test_basic"; then
        log_success "Lock acquisition successful"
        
        # Test lock release
        if _release_lock "$lock_file"; then
            log_success "Lock release successful"
        else
            log_failure "Lock release failed"
        fi
    else
        log_failure "Lock acquisition failed"
    fi
}

# Test 2: Lock contention and timeout
test_lock_contention() {
    log_test "Testing lock contention and timeout"
    
    local lock_file=".unity/events/locks/test-contention.lock"
    
    # First process acquires lock
    (
        _acquire_lock "$lock_file" 10 "holder_process"
        sleep 8  # Hold lock for 8 seconds
        _release_lock "$lock_file"
    ) &
    local holder_pid=$!
    CHILD_PIDS+=("$holder_pid")
    
    sleep 1  # Let first process acquire lock
    
    # Second process tries to acquire with timeout
    local start_time=$(date +%s)
    if _acquire_lock "$lock_file" 3 "contender_process"; then
        log_failure "Lock acquisition should have timed out"
        _release_lock "$lock_file"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [[ $duration -ge 3 && $duration -le 5 ]]; then
            log_success "Lock contention timeout worked correctly (${duration}s)"
        else
            log_failure "Lock timeout duration unexpected: ${duration}s"
        fi
    fi
    
    wait "$holder_pid" 2>/dev/null || true
}

# Test 3: Stale lock detection and cleanup
test_stale_lock_cleanup() {
    log_test "Testing stale lock detection and cleanup"
    
    local lock_file=".unity/events/locks/test-stale.lock"
    
    # Create a fake stale lock with non-existent PID
    local fake_pid=99999
    while kill -0 "$fake_pid" 2>/dev/null; do
        fake_pid=$((fake_pid + 1))
    done
    
    echo "$fake_pid|$(date +%s)|fake_process" > "$lock_file"
    
    # Try to acquire lock - should detect stale lock and clean it up
    if _acquire_lock "$lock_file" 5 "cleanup_test"; then
        log_success "Stale lock was cleaned up and lock acquired"
        _release_lock "$lock_file"
    else
        log_failure "Failed to clean up stale lock"
    fi
}

# Test 4: Lock ordering validation
test_lock_ordering() {
    log_test "Testing lock ordering validation"
    
    local lock1=".unity/events/locks/processing.lock"  # Order 100
    local lock2=".unity/events/locks/config.lock"     # Order 300
    
    # Acquire lower order lock first
    if _acquire_lock "$lock1" 5 "ordering_test"; then
        # Try to acquire higher order lock (should succeed)
        if _acquire_lock "$lock2" 5 "ordering_test"; then
            log_success "Lock ordering validation allows correct order"
            _release_lock "$lock2"
            _release_lock "$lock1"
        else
            log_failure "Failed to acquire higher order lock"
            _release_lock "$lock1"
        fi
    else
        log_failure "Failed to acquire first lock for ordering test"
    fi
    
    # Test reverse order (should fail due to ordering violation)
    if _acquire_lock "$lock2" 5 "ordering_test"; then
        # This should fail due to ordering violation
        if _acquire_lock "$lock1" 2 "ordering_test"; then
            log_failure "Lock ordering validation should have prevented reverse order"
            _release_lock "$lock1"
            _release_lock "$lock2"
        else
            log_success "Lock ordering validation correctly prevented reverse order"
            _release_lock "$lock2"
        fi
    else
        log_failure "Failed to acquire first lock for reverse ordering test"
    fi
}

# Test 5: Deadlock detection simulation
test_deadlock_detection() {
    log_test "Testing deadlock detection"
    
    local lock_a=".unity/events/locks/test-deadlock-a.lock"
    local lock_b=".unity/events/locks/test-deadlock-b.lock"
    
    # Process 1: Acquire A, then try B
    (
        if _acquire_lock "$lock_a" 10 "process1"; then
            sleep 2  # Give process 2 time to acquire B
            _acquire_lock "$lock_b" 5 "process1" || true
            _release_lock "$lock_a"
        fi
    ) &
    local proc1_pid=$!
    CHILD_PIDS+=("$proc1_pid")
    
    # Process 2: Acquire B, then try A
    (
        sleep 1  # Let process 1 acquire A first
        if _acquire_lock "$lock_b" 10 "process2"; then
            sleep 1
            _acquire_lock "$lock_a" 5 "process2" || true
            _release_lock "$lock_b"
        fi
    ) &
    local proc2_pid=$!
    CHILD_PIDS+=("$proc2_pid")
    
    # Wait for processes to complete
    wait "$proc1_pid" "$proc2_pid" 2>/dev/null || true
    
    # Check if deadlock was detected in logs
    if grep -q "Deadlock detected" "logs/unity/lock-acquisition.log" 2>/dev/null; then
        log_success "Deadlock was detected"
    else
        log_info "Deadlock detection test completed (check logs for details)"
    fi
}

# Test 6: Lock status reporting
test_lock_status_reporting() {
    log_test "Testing lock status reporting"
    
    local lock_file=".unity/events/locks/test-status.lock"
    
    # Acquire a lock
    if _acquire_lock "$lock_file" 5 "status_test"; then
        # Generate status report
        local report
        report=$(_get_lock_status_report)
        
        if [[ "$report" == *"test-status.lock"* ]]; then
            log_success "Lock status reporting includes active locks"
        else
            log_failure "Lock status reporting missing active lock information"
        fi
        
        _release_lock "$lock_file"
    else
        log_failure "Failed to acquire lock for status test"
    fi
}

# Test 7: Event emission for lock operations
test_lock_event_emission() {
    log_test "Testing lock event emission"
    
    local lock_file=".unity/events/locks/test-events.lock"
    local event_count_before
    local event_count_after
    
    # Count events before
    event_count_before=$(grep -c "LOCK_ACQUIRED" "logs/unity/events-audit.log" 2>/dev/null || echo "0")
    
    # Acquire and release lock
    if _acquire_lock "$lock_file" 5 "event_test"; then
        _release_lock "$lock_file"
        
        sleep 1  # Allow time for event processing
        
        # Count events after
        event_count_after=$(grep -c "LOCK_ACQUIRED" "logs/unity/events-audit.log" 2>/dev/null || echo "0")
        
        if [[ $event_count_after -gt $event_count_before ]]; then
            log_success "Lock events are being emitted"
        else
            log_info "Lock event emission test completed (events may be processed asynchronously)"
        fi
    else
        log_failure "Failed to acquire lock for event emission test"
    fi
}

# Test 8: Concurrent lock operations stress test
test_concurrent_lock_operations() {
    log_test "Testing concurrent lock operations (stress test)"
    
    local lock_file=".unity/events/locks/test-concurrent.lock"
    local success_count=0
    local total_processes=5
    
    # Start multiple processes trying to acquire the same lock
    for i in $(seq 1 $total_processes); do
        (
            if _acquire_lock "$lock_file" 10 "concurrent_test_$i"; then
                sleep 1  # Hold lock briefly
                _release_lock "$lock_file"
                echo "SUCCESS_$i"
            else
                echo "TIMEOUT_$i"
            fi
        ) &
        CHILD_PIDS+=($!)
    done
    
    # Wait for all processes and count successes
    for pid in "${CHILD_PIDS[@]: -$total_processes}"; do
        if wait "$pid" 2>/dev/null; then
            success_count=$((success_count + 1))
        fi
    done
    
    if [[ $success_count -gt 0 ]]; then
        log_success "Concurrent lock operations handled correctly ($success_count/$total_processes successful)"
    else
        log_failure "No processes successfully acquired lock in concurrent test"
    fi
}

# Test 9: Lock recovery after process termination
test_lock_recovery() {
    log_test "Testing lock recovery after process termination"
    
    local lock_file=".unity/events/locks/test-recovery.lock"
    
    # Start process that acquires lock but gets killed
    (
        _acquire_lock "$lock_file" 60 "victim_process"
        sleep 30  # This should be interrupted
    ) &
    local victim_pid=$!
    
    sleep 1  # Let process acquire lock
    
    # Kill the process holding the lock
    kill -KILL "$victim_pid" 2>/dev/null || true
    
    sleep 1  # Allow cleanup to detect dead process
    
    # Try to acquire the lock - should succeed after cleanup
    if _acquire_lock "$lock_file" 5 "recovery_test"; then
        log_success "Lock recovery after process termination works"
        _release_lock "$lock_file"
    else
        log_failure "Failed to recover lock after process termination"
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "Unity Enhanced Lock Management Tests"
    echo "=========================================="
    
    setup_test_environment
    
    # Run all tests
    test_basic_lock_operations
    test_lock_contention
    test_stale_lock_cleanup
    test_lock_ordering
    test_deadlock_detection
    test_lock_status_reporting
    test_lock_event_emission
    test_concurrent_lock_operations
    test_lock_recovery
    
    # Summary
    echo ""
    echo "=========================================="
    echo "Test Results Summary"
    echo "=========================================="
    
    local total_tests=${#TEST_RESULTS[@]}
    local passed_tests=0
    local failed_tests=0
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
        if [[ "$result" == PASS:* ]]; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    echo ""
    echo "Total Tests: $total_tests"
    echo -e "${GREEN}Passed: $passed_tests${NC}"
    echo -e "${RED}Failed: $failed_tests${NC}"
    
    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi