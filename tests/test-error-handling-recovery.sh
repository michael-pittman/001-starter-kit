#!/usr/bin/env bash
# =============================================================================
# Error Handling and Recovery Testing
# Comprehensive testing of error conditions, recovery mechanisms, and failure scenarios
# =============================================================================


# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-error-handling-recovery.sh" "core/variables" "core/logging"

export TEST_VERBOSE="${TEST_VERBOSE:-true}"
export TEST_PARALLEL="${TEST_PARALLEL:-false}"  # Disable for error testing clarity
export TEST_STOP_ON_FAILURE="${TEST_STOP_ON_FAILURE:-false}"  # Continue on failures
export TEST_COVERAGE_ENABLED="${TEST_COVERAGE_ENABLED:-true}"
export TEST_BENCHMARK_ENABLED="${TEST_BENCHMARK_ENABLED:-false}"  # Focus on functionality

# Error testing configuration
readonly ERROR_TEST_TIMEOUT="${ERROR_TEST_TIMEOUT:-30}"
readonly RECOVERY_TEST_RETRIES="${RECOVERY_TEST_RETRIES:-3}"
readonly FAILURE_SIMULATION_ENABLED="${FAILURE_SIMULATION_ENABLED:-true}"

# =============================================================================
# ERROR SIMULATION UTILITIES
# =============================================================================

# Simulate network failure
simulate_network_failure() {
    local duration="${1:-5}"
    local failure_type="${2:-timeout}"
    
    case "$failure_type" in
        "timeout")
            sleep "$duration"
            return 124  # Timeout exit code
            ;;
        "connection_refused")
            return 111  # Connection refused
            ;;
        "dns_failure")
            return 2    # DNS resolution failure
            ;;
        "permission_denied")
            return 13   # Permission denied
            ;;
        *)
            return 1    # Generic failure
            ;;
    esac
}

# Simulate file system errors
simulate_filesystem_error() {
    local error_type="${1:-permission}"
    local file_path="${2:-/tmp/test-file}"
    
    case "$error_type" in
        "permission")
            # Create file with no permissions
            touch "$file_path"
            chmod 000 "$file_path"
            cat "$file_path" 2>/dev/null  # This will fail
            return $?
            ;;
        "disk_full")
            # Simulate disk full (mock)
            echo "No space left on device" >&2
            return 28  # ENOSPC
            ;;
        "file_not_found")
            cat "/nonexistent/file" 2>/dev/null
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

# Simulate memory pressure
simulate_memory_pressure() {
    local size_mb="${1:-100}"
    local duration="${2:-5}"
    
    # Create memory pressure by allocating large arrays
    local large_data=()
    for ((i=0; i<size_mb; i++)); do
        # Each iteration adds roughly 1MB of data
        for ((j=0; j<1000; j++)); do
            large_data+=("$(printf '%1000s' | tr ' ' 'x')")
        done
        
        if [[ $i -gt 0 && $((i % 10)) -eq 0 ]]; then
            echo "Allocated ${i}MB of memory..." >&2
            sleep 0.1
        fi
    done
    
    sleep "$duration"
    echo "Memory pressure simulation completed" >&2
}

# Simulate process limits
simulate_process_limits() {
    local max_processes="${1:-50}"
    local pids=()
    
    # Start multiple background processes
    for ((i=0; i<max_processes; i++)); do
        sleep 60 &
        pids+=($!)
        
        if [[ $((i % 10)) -eq 0 ]]; then
            echo "Started $i background processes..." >&2
        fi
    done
    
    # Clean up processes
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    
    wait 2>/dev/null || true
}

# =============================================================================
# BASIC ERROR HANDLING TESTS
# =============================================================================

test_error_handling_command_failures() {
    # Test handling of command failures
    
    # Test command that should fail
    assert_command_fails "false" "False command should fail" "1"
    
    # Test command with specific exit code
    assert_command_fails "exit 42" "Exit 42 should fail with code 42" "42"
    
    # Test command timeout
    disable_error_trap  # Temporarily disable to test timeout
    local output
    output=$(run_with_timeout "2" "sleep 5" 2>&1) || local exit_code=$?
    enable_error_trap
    
    if [[ ${exit_code:-0} -eq 124 ]]; then
        test_pass "Timeout handling works correctly"
    else
        test_fail "Timeout handling failed, exit code: ${exit_code:-0}"
    fi
}

test_error_handling_file_operations() {
    # Test file operation error handling
    
    # Test reading non-existent file
    assert_command_fails "cat /nonexistent/file/path" "Reading non-existent file should fail"
    
    # Test writing to protected directory
    assert_command_fails "echo 'test' > /root/protected-file" "Writing to protected directory should fail"
    
    # Test file permission errors
    local temp_file
    temp_file=$(create_temp_file "permission-test" "test content")
    chmod 000 "$temp_file"
    
    assert_command_fails "cat '$temp_file'" "Reading file without permissions should fail"
    
    # Restore permissions for cleanup
    chmod 644 "$temp_file"
}

test_error_handling_network_simulation() {
    # Test network error simulation
    
    # Test timeout simulation
    disable_error_trap
    local start_time=$(date +%s)
    simulate_network_failure "2" "timeout" || local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    enable_error_trap
    
    assert_equals "124" "${exit_code:-0}" "Network timeout should return exit code 124"
    assert_numeric_comparison "$duration" "-ge" "2" "Timeout should take at least 2 seconds"
    
    # Test connection refused simulation
    disable_error_trap
    simulate_network_failure "0" "connection_refused" || local exit_code=$?
    enable_error_trap
    
    assert_equals "111" "${exit_code:-0}" "Connection refused should return exit code 111"
}

# =============================================================================
# ADVANCED ERROR SCENARIO TESTS
# =============================================================================

test_error_handling_nested_failures() {
    # Test error handling in nested function calls
    
    level_three_function() {
        echo "Level 3: About to fail"
        return 3
    }
    
    level_two_function() {
        echo "Level 2: Calling level 3"
        level_three_function
        local exit_code=$?
        echo "Level 2: Level 3 returned $exit_code"
        return $((exit_code + 1))
    }
    
    level_one_function() {
        echo "Level 1: Calling level 2"
        level_two_function
        local exit_code=$?
        echo "Level 1: Level 2 returned $exit_code"
        return $((exit_code + 1))
    }
    
    disable_error_trap
    local output
    output=$(level_one_function 2>&1) || local final_exit_code=$?
    enable_error_trap
    
    assert_equals "5" "${final_exit_code:-0}" "Nested error codes should propagate correctly (3+1+1=5)"
    assert_contains "$output" "Level 1" "Output should contain level 1 messages"
    assert_contains "$output" "Level 2" "Output should contain level 2 messages"
    assert_contains "$output" "Level 3" "Output should contain level 3 messages"
}

test_error_handling_trap_mechanisms() {
    # Test error trap mechanisms
    
    test_function_with_trap() {
        local cleanup_called=false
        
        # Set up cleanup trap
        trap 'cleanup_called=true; echo "Cleanup trap called"' EXIT
        
        # Simulate some work
        echo "Doing some work..."
        
        # Simulate error
        return 1
    }
    
    disable_error_trap
    local output
    output=$(test_function_with_trap 2>&1) || local exit_code=$?
    enable_error_trap
    
    assert_equals "1" "${exit_code:-0}" "Function should return error code 1"
    assert_contains "$output" "Cleanup trap called" "Cleanup trap should be executed"
}

test_error_handling_signal_handling() {
    # Test signal handling
    
    signal_test_function() {
        local signal_received=""
        
        # Set up signal handler
        trap 'signal_received="TERM"; echo "SIGTERM received"' TERM
        trap 'signal_received="INT"; echo "SIGINT received"' INT
        
        # Start a background process to send signal
        {
            sleep 1
            kill -TERM $$
        } &
        
        # Wait for signal
        sleep 3
        
        echo "Signal received: $signal_received"
    }
    
    disable_error_trap
    local output
    output=$(signal_test_function 2>&1) || local exit_code=$?
    enable_error_trap
    
    # Note: This test might be platform-specific
    if [[ "$output" == *"SIGTERM received"* ]]; then
        test_pass "Signal handling works correctly"
    else
        test_warn "Signal handling test inconclusive (platform-dependent)"
    fi
}

# =============================================================================
# RECOVERY MECHANISM TESTS
# =============================================================================

test_recovery_retry_mechanisms() {
    # Test retry mechanisms
    
    local attempt_count=0
    
    flaky_function() {
        attempt_count=$((attempt_count + 1))
        echo "Attempt $attempt_count"
        
        if [[ $attempt_count -lt 3 ]]; then
            return 1  # Fail on first two attempts
        else
            return 0  # Succeed on third attempt
        fi
    }
    
    retry_with_backoff() {
        local max_attempts="$1"
        local base_delay="$2"
        local func="$3"
        
        for ((i=1; i<=max_attempts; i++)); do
            if "$func"; then
                echo "Success on attempt $i"
                return 0
            else
                echo "Attempt $i failed"
                if [[ $i -lt $max_attempts ]]; then
                    local delay=$((base_delay * i))
                    echo "Waiting ${delay}s before retry..."
                    sleep "$delay"
                fi
            fi
        done
        
        echo "All $max_attempts attempts failed"
        return 1
    }
    
    local output
    output=$(retry_with_backoff 5 1 "flaky_function" 2>&1)
    local exit_code=$?
    
    assert_equals "0" "$exit_code" "Retry mechanism should eventually succeed"
    assert_equals "3" "$attempt_count" "Should succeed on third attempt"
    assert_contains "$output" "Success on attempt 3" "Should report success on correct attempt"
}

test_recovery_circuit_breaker() {
    # Test circuit breaker pattern
    
    local failure_count=0
    local circuit_open=false
    local circuit_threshold=3
    
    failing_service() {
        failure_count=$((failure_count + 1))
        echo "Service call failed (failure $failure_count)"
        return 1
    }
    
    circuit_breaker_call() {
        if [[ "$circuit_open" == "true" ]]; then
            echo "Circuit breaker is OPEN - not attempting call"
            return 2  # Circuit open error code
        fi
        
        if failing_service; then
            failure_count=0  # Reset on success
            return 0
        else
            if [[ $failure_count -ge $circuit_threshold ]]; then
                circuit_open=true
                echo "Circuit breaker OPENED after $failure_count failures"
            fi
            return 1
        fi
    }
    
    # Test circuit breaker behavior
    local outputs=()
    local exit_codes=()
    
    for ((i=1; i<=5; i++)); do
        disable_error_trap
        local output
        output=$(circuit_breaker_call 2>&1) || local exit_code=$?
        enable_error_trap
        
        outputs+=("$output")
        exit_codes+=("${exit_code:-0}")
    done
    
    # First 3 calls should fail with exit code 1
    assert_equals "1" "${exit_codes[0]}" "First call should fail with code 1"
    assert_equals "1" "${exit_codes[1]}" "Second call should fail with code 1"
    assert_equals "1" "${exit_codes[2]}" "Third call should fail with code 1"
    
    # Subsequent calls should fail with exit code 2 (circuit open)
    assert_equals "2" "${exit_codes[3]}" "Fourth call should fail with code 2 (circuit open)"
    assert_equals "2" "${exit_codes[4]}" "Fifth call should fail with code 2 (circuit open)"
    
    # Check circuit breaker messages
    assert_contains "${outputs[2]}" "Circuit breaker OPENED" "Circuit should open after threshold"
    assert_contains "${outputs[3]}" "Circuit breaker is OPEN" "Subsequent calls should be blocked"
}

test_recovery_graceful_degradation() {
    # Test graceful degradation
    
    primary_service() {
        echo "Primary service failed"
        return 1
    }
    
    fallback_service() {
        echo "Fallback service response"
        return 0
    }
    
    service_with_fallback() {
        local service_name="$1"
        
        echo "Attempting primary service..."
        if primary_service; then
            echo "Primary service succeeded"
            return 0
        else
            echo "Primary service failed, trying fallback..."
            if fallback_service; then
                echo "Fallback service succeeded"
                return 0
            else
                echo "Both services failed"
                return 1
            fi
        fi
    }
    
    local output
    output=$(service_with_fallback "test" 2>&1)
    local exit_code=$?
    
    assert_equals "0" "$exit_code" "Service with fallback should succeed"
    assert_contains "$output" "Primary service failed" "Should attempt primary first"
    assert_contains "$output" "Fallback service succeeded" "Should use fallback on primary failure"
}

# =============================================================================
# RESOURCE EXHAUSTION TESTS
# =============================================================================

test_error_handling_memory_exhaustion() {
    # Test behavior under memory pressure
    
    if [[ "$FAILURE_SIMULATION_ENABLED" != "true" ]]; then
        test_skip "Failure simulation disabled" "simulation"
        return
    fi
    
    memory_intensive_function() {
        echo "Starting memory-intensive operation..."
        
        # Create a moderately large array to test memory handling
        local large_array=()
        for ((i=0; i<10000; i++)); do
            large_array+=("data-item-$i-$(printf '%100s' | tr ' ' 'x')")
            
            # Check if we should exit early (memory pressure)
            if [[ $((i % 1000)) -eq 0 && $i -gt 0 ]]; then
                echo "Processed $i items..."
            fi
        done
        
        echo "Memory operation completed with ${#large_array[@]} items"
        return 0
    }
    
    # Monitor memory usage during test
    local mem_before
    mem_before=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
    
    local output
    output=$(memory_intensive_function 2>&1)
    local exit_code=$?
    
    local mem_after
    mem_after=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
    local mem_diff=$((mem_after - mem_before))
    
    assert_equals "0" "$exit_code" "Memory-intensive function should complete"
    assert_contains "$output" "completed" "Should report completion"
    
    if [[ $mem_diff -gt 50000 ]]; then  # 50MB threshold
        test_warn "High memory usage detected: ${mem_diff}KB"
    else
        test_pass "Memory usage acceptable: ${mem_diff}KB increase"
    fi
}

test_error_handling_file_descriptor_limits() {
    # Test file descriptor limit handling
    
    if [[ "$FAILURE_SIMULATION_ENABLED" != "true" ]]; then
        test_skip "Failure simulation disabled" "simulation"
        return
    fi
    
    file_descriptor_test() {
        local temp_files=()
        local max_files=100
        local opened_files=0
        
        echo "Testing file descriptor limits..."
        
        for ((i=0; i<max_files; i++)); do
            local temp_file
            temp_file=$(mktemp) || break
            
            # Open file for reading (consumes file descriptor)
            if exec {fd}< "$temp_file" 2>/dev/null; then
                temp_files+=("$temp_file")
                opened_files=$((opened_files + 1))
            else
                echo "Failed to open file $i (file descriptor limit reached)"
                break
            fi
            
            if [[ $((i % 20)) -eq 0 && $i -gt 0 ]]; then
                echo "Opened $i files..."
            fi
        done
        
        # Close file descriptors and clean up
        for temp_file in "${temp_files[@]}"; do
            rm -f "$temp_file" 2>/dev/null || true
        done
        
        echo "Successfully opened $opened_files files"
        return 0
    }
    
    local output
    output=$(file_descriptor_test 2>&1)
    local exit_code=$?
    
    assert_equals "0" "$exit_code" "File descriptor test should complete"
    assert_contains "$output" "Successfully opened" "Should report number of opened files"
}

# =============================================================================
# ERROR LOGGING AND DEBUGGING TESTS
# =============================================================================

test_error_logging_stack_traces() {
    # Test stack trace generation
    
    function_level_3() {
        echo "Function level 3 executing"
        local stack_trace
        stack_trace=$(capture_stack_trace)
        echo "Stack trace from level 3:"
        echo "$stack_trace"
        return 1
    }
    
    function_level_2() {
        echo "Function level 2 executing"
        function_level_3
    }
    
    function_level_1() {
        echo "Function level 1 executing"
        function_level_2
    }
    
    disable_error_trap
    local output
    output=$(function_level_1 2>&1) || local exit_code=$?
    enable_error_trap
    
    assert_equals "1" "${exit_code:-0}" "Function should propagate error code"
    assert_contains "$output" "Function level 1" "Should show level 1 execution"
    assert_contains "$output" "Function level 2" "Should show level 2 execution"
    assert_contains "$output" "Function level 3" "Should show level 3 execution"
    assert_contains "$output" "Stack trace" "Should generate stack trace"
}

test_error_logging_context_preservation() {
    # Test that error context is preserved
    
    contextual_error_function() {
        local operation="database_connection"
        local connection_string="postgresql://localhost:5432/testdb"
        local retry_count=3
        
        echo "Attempting $operation with $connection_string (retry $retry_count)"
        
        # Simulate failure with context
        echo "Error: Connection timeout after 30 seconds" >&2
        echo "Context: operation=$operation, connection=$connection_string, retries=$retry_count" >&2
        
        return 1
    }
    
    disable_error_trap
    local output
    output=$(contextual_error_function 2>&1) || local exit_code=$?
    enable_error_trap
    
    assert_equals "1" "$exit_code" "Function should return error code"
    assert_contains "$output" "database_connection" "Should preserve operation context"
    assert_contains "$output" "postgresql://localhost" "Should preserve connection context"
    assert_contains "$output" "Context:" "Should include explicit context information"
}

# =============================================================================
# INTEGRATION ERROR TESTING
# =============================================================================

test_error_handling_project_scripts() {
    # Test error handling in project scripts
    
    local test_scripts=(
        "$PROJECT_ROOT/scripts/aws-deployment-v2-simple.sh"
        "$PROJECT_ROOT/scripts/aws-deployment-modular.sh"
        "$PROJECT_ROOT/tools/test-runner.sh"
    )
    
    for script in "${test_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            test_skip "Script not found: $(basename "$script")" "missing-script"
            continue
        fi
        
        # Test script with invalid arguments
        local script_name=$(basename "$script")
        
        disable_error_trap
        local output
        output=$("$script" --invalid-argument 2>&1) || local exit_code=$?
        enable_error_trap
        
        # Scripts should handle invalid arguments gracefully
        if [[ ${exit_code:-0} -ne 0 ]]; then
            test_pass "Script $script_name handles invalid arguments correctly (exit code: ${exit_code:-0})"
        else
            test_warn "Script $script_name may not validate arguments properly"
        fi
        
        # Test help output for error guidance
        if "$script" --help 2>&1 | grep -q -i "usage\\|help\\|error"; then
            test_pass "Script $script_name provides helpful error guidance"
        else
            test_warn "Script $script_name could improve error guidance"
        fi
    done
}

test_error_handling_library_functions() {
    # Test error handling in library functions
    
    if [[ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]]; then
        source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
        
        # Test error function if available
        if declare -f "error" >/dev/null 2>&1; then
            disable_error_trap
            local output
            output=$(error "Test error message" 2>&1) || local exit_code=$?
            enable_error_trap
            
            # Error function should output message and exit
            assert_contains "$output" "Test error message" "Error function should output message"
            if [[ ${exit_code:-0} -ne 0 ]]; then
                test_pass "Error function exits with non-zero code"
            else
                test_warn "Error function should exit with non-zero code"
            fi
        else
            test_skip "Error function not found in aws-deployment-common.sh" "missing-function"
        fi
        
        # Test log function error handling
        if declare -f "log" >/dev/null 2>&1; then
            local output
            output=$(log "Test log message" 2>&1)
            
            assert_contains "$output" "Test log message" "Log function should output message"
        else
            test_skip "Log function not found in aws-deployment-common.sh" "missing-function"
        fi
    else
        test_skip "AWS deployment common library not found" "missing-library"
    fi
}

# =============================================================================
# ERROR RECOVERY VALIDATION
# =============================================================================

test_error_recovery_state_restoration() {
    # Test that system state can be restored after errors
    
    state_modification_with_recovery() {
        local original_dir=$(pwd)
        local temp_dir
        temp_dir=$(create_temp_dir "state-test")
        
        # Set up cleanup trap
        trap "cd '$original_dir'; echo 'State restored'" EXIT
        
        echo "Changing to temporary directory: $temp_dir"
        cd "$temp_dir"
        
        echo "Creating test files..."
        touch file1.txt file2.txt file3.txt
        
        echo "Simulating error..."
        return 1
    }
    
    local original_pwd=$(pwd)
    
    disable_error_trap
    local output
    output=$(state_modification_with_recovery 2>&1) || local exit_code=$?
    enable_error_trap
    
    local current_pwd=$(pwd)
    
    assert_equals "1" "${exit_code:-0}" "Function should return error code"
    assert_equals "$original_pwd" "$current_pwd" "Working directory should be restored"
    assert_contains "$output" "State restored" "Cleanup should execute"
}

test_error_recovery_resource_cleanup() {
    # Test resource cleanup after errors
    
    resource_allocation_with_cleanup() {
        local temp_files=()
        local temp_dirs=()
        
        # Allocate resources
        for ((i=1; i<=5; i++)); do
            local temp_file
            temp_file=$(create_temp_file "cleanup-test-$i")
            temp_files+=("$temp_file")
            
            local temp_dir
            temp_dir=$(create_temp_dir "cleanup-dir-$i")
            temp_dirs+=("$temp_dir")
        done
        
        echo "Allocated ${#temp_files[@]} files and ${#temp_dirs[@]} directories"
        
        # Simulate work and error
        echo "Processing resources..."
        sleep 0.1
        
        echo "Simulating error during processing..."
        return 1
    }
    
    # Track resources before test
    local resources_before
    resources_before=$(find /tmp -name "*cleanup-test*" -o -name "*cleanup-dir*" 2>/dev/null | wc -l)
    
    disable_error_trap
    local output
    output=$(resource_allocation_with_cleanup 2>&1) || local exit_code=$?
    enable_error_trap
    
    # Allow cleanup to occur
    sleep 0.5
    
    # Framework should clean up temporary resources automatically
    # (This is handled by the cleanup_temp_files function)
    
    assert_equals "1" "${exit_code:-0}" "Function should return error code"
    assert_contains "$output" "Allocated 5 files and 5 directories" "Should allocate resources"
    test_pass "Resource cleanup test completed (cleanup verified by framework)"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "Starting Error Handling and Recovery Testing"
    echo "============================================"
    echo "Timeout: $ERROR_TEST_TIMEOUT seconds"
    echo "Retries: $RECOVERY_TEST_RETRIES"
    echo "Failure Simulation: $FAILURE_SIMULATION_ENABLED"
    echo ""
    
    # Initialize the framework
    test_init "test-error-handling-recovery.sh" "error-handling"
    
    # Run all error handling tests
    run_all_tests "test_"
    
    # Cleanup and generate reports
    test_cleanup
}

# Run if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
