#!/bin/bash
# Unity Deployment Service Atomic State Integration Tests
# Tests the integration of atomic state management with deployment orchestration

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load test framework and Unity components
source "$PROJECT_ROOT/tests/lib/test-framework.sh"
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
source "$PROJECT_ROOT/lib/unity/core/unity-events.sh"
source "$PROJECT_ROOT/lib/unity/core/unity-atomic-state.sh"
source "$PROJECT_ROOT/lib/unity/services/unity-deployment-service.sh"

# Test configuration
TEST_SUITE_NAME="Unity Deployment Atomic State Integration"
TEST_DEPLOYMENT_STATE_DIR=".unity-test/deployment/state"
TEST_ATOMIC_STATE_DIR=".unity-test/atomic-state"

# Override directories for testing
export UNITY_DEPLOYMENT_STATE_DIR="$TEST_DEPLOYMENT_STATE_DIR"
export UNITY_ATOMIC_STATE_DIR="$TEST_ATOMIC_STATE_DIR"
export UNITY_ATOMIC_BACKUP_DIR="$TEST_ATOMIC_STATE_DIR/backups"
export UNITY_ATOMIC_LOCK_DIR="$TEST_ATOMIC_STATE_DIR/locks"
export UNITY_ATOMIC_TEMP_DIR="$TEST_ATOMIC_STATE_DIR/temp"

#############################################
# Test Setup and Teardown
#############################################

setup_deployment_atomic_tests() {
    unity_log "INFO" "Setting up deployment atomic state integration tests..."
    
    # Clean up any existing test state
    rm -rf ".unity-test" 2>/dev/null || true
    
    # Initialize Unity core
    unity_init >/dev/null 2>&1 || true
    
    # Initialize deployment service (which should initialize atomic state)
    unity_deployment_init "false" >/dev/null 2>&1 || true
    
    unity_log "DEBUG" "Deployment atomic state test setup completed"
}

teardown_deployment_atomic_tests() {
    unity_log "INFO" "Cleaning up deployment atomic state integration tests..."
    
    # Clean up deployment service
    unity_deployment_cleanup >/dev/null 2>&1 || true
    
    # Clean up test directories
    rm -rf ".unity-test" 2>/dev/null || true
    
    unity_log "DEBUG" "Deployment atomic state test cleanup completed"
}

#############################################
# Deployment State Integrity Tests
#############################################

test_deployment_state_creation() {
    test_start "Deployment state creation with atomic writes"
    
    local stack_name="test-stack-atomic"
    local deployment_type="spot"
    local strategy="rolling"
    
    # Execute deployment creation
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "$deployment_type" "$strategy" 2>/dev/null || echo "")"
    
    test_assert_not_empty "$deployment_id" "Deployment ID generated"
    
    # Verify state file was created atomically
    local state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    test_assert_file_exists "$state_file" "Deployment state file created"
    test_assert_file_exists "${state_file}.checksum" "Deployment state checksum created"
    
    # Verify state content integrity
    local state_content
    state_content="$(unity_atomic_read "$state_file" "true")"
    test_assert_not_empty "$state_content" "State content readable"
    
    # Verify required fields
    if echo "$state_content" | grep -q "\"deployment_id\":" &&
       echo "$state_content" | grep -q "\"stack_name\":" &&
       echo "$state_content" | grep -q "\"deployment_type\":" &&
       echo "$state_content" | grep -q "\"status\":"; then
        test_pass
    else
        test_fail "Required state fields missing"
    fi
}

test_deployment_state_updates() {
    test_start "Deployment state updates with atomic operations"
    
    local stack_name="test-stack-updates"
    local deployment_type="alb"
    
    # Create deployment
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "$deployment_type" 2>/dev/null || echo "")"
    test_assert_not_empty "$deployment_id" "Deployment created"
    
    # Test state updates
    if _update_deployment_state "$deployment_id" "configuring" '{"step": "vpc_creation"}'; then
        local state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
        local state_content
        state_content="$(unity_atomic_read "$state_file" "true")"
        
        # Verify status was updated
        if echo "$state_content" | grep -q "\"status\":[[:space:]]*\"configuring\""; then
            test_pass
        else
            test_fail "State status not updated correctly"
        fi
    else
        test_fail "State update failed"
    fi
}

test_deployment_transaction_logging() {
    test_start "Deployment transaction logging"
    
    local stack_name="test-stack-transactions"
    local deployment_type="cdn"
    
    # Create deployment
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "$deployment_type" 2>/dev/null || echo "")"
    test_assert_not_empty "$deployment_id" "Deployment created"
    
    # Add transaction log entries
    _add_deployment_transaction_log "$deployment_id" "vpc_created" "VPC infrastructure created" "success"
    _add_deployment_transaction_log "$deployment_id" "alb_configured" "Application Load Balancer configured" "success"
    _add_deployment_transaction_log "$deployment_id" "cdn_setup" "CloudFront distribution created" "success"
    
    # Verify transaction log in state
    local state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    local state_content
    state_content="$(unity_atomic_read "$state_file" "true")"
    
    if echo "$state_content" | grep -q "transaction_log" &&
       echo "$state_content" | grep -q "vpc_created" &&
       echo "$state_content" | grep -q "alb_configured" &&
       echo "$state_content" | grep -q "cdn_setup"; then
        test_pass
    else
        test_fail "Transaction log entries not found in state"
    fi
}

#############################################
# Deployment State Recovery Tests
#############################################

test_deployment_state_corruption_recovery() {
    test_start "Deployment state corruption and recovery"
    
    local stack_name="test-stack-recovery"
    local deployment_type="full"
    
    # Create deployment
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "$deployment_type" 2>/dev/null || echo "")"
    test_assert_not_empty "$deployment_id" "Deployment created"
    
    local state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    
    # Make some updates to create backups
    _update_deployment_state "$deployment_id" "provisioning" '{"progress": 25}'
    _update_deployment_state "$deployment_id" "configuring" '{"progress": 50}'
    
    # Corrupt the state file
    echo "CORRUPTED DEPLOYMENT STATE" > "$state_file"
    
    # Verify corruption detection
    if unity_atomic_needs_recovery "$state_file"; then
        # Attempt recovery
        if unity_atomic_force_recovery "$state_file"; then
            # Verify recovery worked
            local recovered_content
            recovered_content="$(unity_atomic_read "$state_file" "true")"
            
            if echo "$recovered_content" | grep -q "\"deployment_id\":" &&
               echo "$recovered_content" | grep -q "\"stack_name\":"; then
                test_pass
            else
                test_fail "Recovery did not restore valid deployment state"
            fi
        else
            test_fail "Recovery attempt failed"
        fi
    else
        test_fail "Corruption not detected"
    fi
}

test_deployment_state_validation_on_startup() {
    test_start "Deployment state validation during service initialization"
    
    # Create a deployment with valid state
    local stack_name="test-stack-validation"
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "spot" 2>/dev/null || echo "")"
    test_assert_not_empty "$deployment_id" "Deployment created"
    
    # Create a corrupted state file
    local corrupted_deployment_id="corrupted_$(date +%s%N)"
    local corrupted_state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${corrupted_deployment_id}.state"
    echo "INVALID JSON CONTENT" > "$corrupted_state_file"
    
    # Create a missing fields state file
    local incomplete_deployment_id="incomplete_$(date +%s%N)"
    local incomplete_state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${incomplete_deployment_id}.state"
    echo '{"deployment_id": "'$incomplete_deployment_id'"}' > "$incomplete_state_file"
    
    # Run validation
    if _validate_existing_deployment_states; then
        test_fail "Validation should have detected errors"
    else
        # Validation should have failed due to corrupted/incomplete states
        # Check if the valid deployment is still accessible
        local valid_state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
        if [[ -f "$valid_state_file" ]]; then
            local state_content
            state_content="$(unity_atomic_read "$valid_state_file" "true" 2>/dev/null || echo "")"
            if [[ -n "$state_content" ]]; then
                test_pass
            else
                test_fail "Valid deployment state became unreadable"
            fi
        else
            test_fail "Valid deployment state file missing"
        fi
    fi
}

#############################################
# Deployment State Movement Tests
#############################################

test_deployment_state_movement() {
    test_start "Atomic deployment state movement between directories"
    
    local stack_name="test-stack-movement"
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "spot" 2>/dev/null || echo "")"
    test_assert_not_empty "$deployment_id" "Deployment created"
    
    # Verify initial state in active directory
    local active_state_file="$TEST_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state"
    test_assert_file_exists "$active_state_file" "Active state file exists"
    
    # Move to completed
    if _move_deployment_state "$deployment_id" "active" "completed" "completed"; then
        local completed_state_file="$TEST_DEPLOYMENT_STATE_DIR/completed/${deployment_id}.state"
        
        test_assert_file_exists "$completed_state_file" "Completed state file exists"
        test_assert_file_not_exists "$active_state_file" "Active state file removed"
        
        # Verify checksum file was also moved
        if [[ -f "${completed_state_file}.checksum" ]]; then
            test_pass
        else
            test_fail "Checksum file not moved with state file"
        fi
    else
        test_fail "State movement failed"
    fi
}

test_deployment_status_with_atomic_reads() {
    test_start "Deployment status retrieval with atomic reads"
    
    # Create multiple deployments in different states
    local deployments=()
    
    # Active deployment
    local active_id
    active_id="$(unity_deployment_execute "deploy" "active-stack" "spot" 2>/dev/null || echo "")"
    deployments+=("$active_id")
    
    # Completed deployment
    local completed_id
    completed_id="$(unity_deployment_execute "deploy" "completed-stack" "alb" 2>/dev/null || echo "")"
    _move_deployment_state "$completed_id" "active" "completed" "completed"
    deployments+=("$completed_id")
    
    # Failed deployment
    local failed_id
    failed_id="$(unity_deployment_execute "deploy" "failed-stack" "cdn" 2>/dev/null || echo "")"
    _move_deployment_state "$failed_id" "active" "failed" "failed"
    deployments+=("$failed_id")
    
    # Test status retrieval for all deployments
    local status_output
    status_output="$(unity_deployment_execute "status" 2>/dev/null || echo "")"
    
    test_assert_not_empty "$status_output" "Status output generated"
    
    # Verify each deployment appears in status
    local all_found=true
    for deployment_id in "${deployments[@]}"; do
        if [[ -n "$deployment_id" ]] && ! echo "$status_output" | grep -q "$deployment_id"; then
            all_found=false
            break
        fi
    done
    
    if [[ "$all_found" == "true" ]]; then
        test_pass
    else
        test_fail "Not all deployments found in status output"
    fi
}

#############################################
# Concurrent Deployment Tests
#############################################

test_concurrent_deployment_state_integrity() {
    test_start "Concurrent deployment state integrity"
    
    local results_file="$TEST_ATOMIC_STATE_DIR/concurrent-deployment-results.txt"
    echo "" > "$results_file"
    
    # Start multiple deployments concurrently
    for i in {1..3}; do
        (
            local stack_name="concurrent-stack-$i"
            local deployment_id
            deployment_id="$(unity_deployment_execute "deploy" "$stack_name" "spot" "" 2>/dev/null || echo "")"
            
            if [[ -n "$deployment_id" ]]; then
                # Make several state updates
                _update_deployment_state "$deployment_id" "provisioning" "{\"step\": \"vpc_creation\", \"progress\": 20}"
                _update_deployment_state "$deployment_id" "configuring" "{\"step\": \"instance_launch\", \"progress\": 60}"
                _update_deployment_state "$deployment_id" "finalizing" "{\"step\": \"health_checks\", \"progress\": 90}"
                
                echo "success:$i:$deployment_id" >> "$results_file"
            else
                echo "failed:$i" >> "$results_file"
            fi
        ) &
    done
    
    # Wait for all background processes
    wait
    
    # Analyze results
    local success_count
    success_count="$(grep -c "^success:" "$results_file" || echo "0")"
    
    test_assert_greater_than 0 "$success_count" "At least one concurrent deployment succeeded"
    
    # Verify all successful deployments have valid states
    local valid_states=true
    while IFS=':' read -r status seq deployment_id; do
        if [[ "$status" == "success" && -n "$deployment_id" ]]; then
            if ! _validate_deployment_state "$deployment_id"; then
                valid_states=false
                break
            fi
        fi
    done < "$results_file"
    
    if [[ "$valid_states" == "true" ]]; then
        test_pass
    else
        test_fail "Concurrent deployments resulted in invalid states"
    fi
}

#############################################
# Performance and Scale Tests
#############################################

test_deployment_state_performance() {
    test_start "Deployment state operation performance"
    
    local iterations=50
    local start_time end_time duration
    
    # Create a deployment for testing
    local deployment_id
    deployment_id="$(unity_deployment_execute "deploy" "performance-test" "spot" 2>/dev/null || echo "")"
    test_assert_not_empty "$deployment_id" "Test deployment created"
    
    # Time state update operations
    start_time=$(date +%s%N)
    
    for i in $(seq 1 $iterations); do
        _update_deployment_state "$deployment_id" "processing" "{\"iteration\": $i, \"timestamp\": $(date +%s)}" >/dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    local avg_time=$((duration / iterations))
    
    unity_log "INFO" "Performance: $iterations state updates in ${duration}ms (avg: ${avg_time}ms per update)"
    
    # Performance threshold (should be reasonable even with atomic operations)
    test_assert_less_than "$avg_time" 200 "Average state update time under 200ms"
    
    test_pass
}

#############################################
# Main Test Execution
#############################################

run_all_deployment_atomic_tests() {
    test_suite_start "$TEST_SUITE_NAME"
    
    # Setup
    setup_deployment_atomic_tests
    
    # State integrity tests
    test_deployment_state_creation
    test_deployment_state_updates
    test_deployment_transaction_logging
    
    # Recovery tests
    test_deployment_state_corruption_recovery
    test_deployment_state_validation_on_startup
    
    # State movement tests  
    test_deployment_state_movement
    test_deployment_status_with_atomic_reads
    
    # Concurrency tests
    test_concurrent_deployment_state_integrity
    
    # Performance tests
    test_deployment_state_performance
    
    # Cleanup
    teardown_deployment_atomic_tests
    
    test_suite_end
}

# Execute tests if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_deployment_atomic_tests
fi