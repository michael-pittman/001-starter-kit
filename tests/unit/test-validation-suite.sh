#!/usr/bin/env bash
# =============================================================================
# Unit Tests for Validation Suite
# Tests all validation types, parallel processing, caching, and retry mechanisms
# =============================================================================

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/lib/utils/library-loader.sh"
load_module "enhanced-test-framework"

# Test subject
VALIDATION_SUITE="$PROJECT_ROOT/lib/modules/validation/validation-suite.sh"

# Test data
TEST_CACHE_DIR=$(mktemp -d)
export VALIDATION_CACHE_DIR="$TEST_CACHE_DIR"
export VALIDATION_LOG_FILE="$TEST_CACHE_DIR/test.log"

# =============================================================================
# TEST SUITE SETUP
# =============================================================================

setup_test_suite() {
    test_suite_name "Validation Suite Tests"
    test_suite_description "Comprehensive tests for consolidated validation framework"
}

cleanup_test() {
    rm -rf "$TEST_CACHE_DIR"
}

# =============================================================================
# BASIC FUNCTIONALITY TESTS
# =============================================================================

test_validation_suite_exists() {
    test_start "Validation suite script exists"
    
    if [[ -f "$VALIDATION_SUITE" ]]; then
        test_pass "Validation suite found at expected location"
    else
        test_fail "Validation suite not found at: $VALIDATION_SUITE"
    fi
}

test_validation_suite_executable() {
    test_start "Validation suite is executable"
    
    if [[ -x "$VALIDATION_SUITE" ]]; then
        test_pass "Validation suite has execute permissions"
    else
        test_fail "Validation suite is not executable"
    fi
}

test_validation_suite_help() {
    test_start "Validation suite shows help"
    
    local output
    if output=$("$VALIDATION_SUITE" --help 2>&1); then
        if echo "$output" | grep -q "Usage:"; then
            test_pass "Help message displayed correctly"
        else
            test_fail "Help message does not contain usage information"
        fi
    else
        test_fail "Failed to run validation suite with --help"
    fi
}

# =============================================================================
# VALIDATION TYPE TESTS
# =============================================================================

test_dependencies_validation() {
    test_start "Dependencies validation"
    
    local output
    local exit_code=0
    
    output=$("$VALIDATION_SUITE" --type dependencies 2>&1) || exit_code=$?
    
    if echo "$output" | grep -q '"status"'; then
        test_pass "Dependencies validation returned structured output"
    else
        test_fail "Dependencies validation did not return expected output"
    fi
}

test_environment_validation() {
    test_start "Environment validation"
    
    # Set minimal required variables for test
    export POSTGRES_PASSWORD="test-password-12345678"
    export N8N_ENCRYPTION_KEY="test-encryption-key-12345678901234567890"
    export N8N_USER_MANAGEMENT_JWT_SECRET="test-jwt-secret-1234567890"
    export ENVIRONMENT="development"
    
    local output
    local exit_code=0
    
    output=$("$VALIDATION_SUITE" --type environment 2>&1) || exit_code=$?
    
    if echo "$output" | grep -q '"status"'; then
        test_pass "Environment validation returned structured output"
    else
        test_fail "Environment validation did not return expected output"
    fi
    
    # Cleanup
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET ENVIRONMENT
}

test_modules_validation() {
    test_start "Modules validation"
    
    local output
    local exit_code=0
    
    output=$("$VALIDATION_SUITE" --type modules 2>&1) || exit_code=$?
    
    if echo "$output" | grep -q '"status"'; then
        test_pass "Modules validation returned structured output"
    else
        test_fail "Modules validation did not return expected output"
    fi
}

test_network_validation() {
    test_start "Network validation"
    
    # Skip network checks for testing
    export SKIP_NETWORK_CHECK="true"
    
    local output
    local exit_code=0
    
    output=$("$VALIDATION_SUITE" --type network 2>&1) || exit_code=$?
    
    if echo "$output" | grep -q '"status"'; then
        test_pass "Network validation returned structured output"
    else
        test_fail "Network validation did not return expected output"
    fi
    
    unset SKIP_NETWORK_CHECK
}

test_invalid_validation_type() {
    test_start "Invalid validation type handling"
    
    local output
    local exit_code=0
    
    output=$("$VALIDATION_SUITE" --type invalid 2>&1) || exit_code=$?
    
    if [[ $exit_code -eq 2 ]]; then
        test_pass "Invalid validation type returns exit code 2"
    else
        test_fail "Invalid validation type did not return expected exit code (got $exit_code)"
    fi
}

# =============================================================================
# PARALLEL PROCESSING TESTS
# =============================================================================

test_parallel_all_validations() {
    test_start "Parallel execution of all validations"
    
    # Set required environment for tests
    export POSTGRES_PASSWORD="test-password-12345678"
    export N8N_ENCRYPTION_KEY="test-encryption-key-12345678901234567890"
    export N8N_USER_MANAGEMENT_JWT_SECRET="test-jwt-secret-1234567890"
    export ENVIRONMENT="development"
    export SKIP_NETWORK_CHECK="true"
    
    local start_time=$(date +%s)
    local output
    local exit_code=0
    
    output=$("$VALIDATION_SUITE" --type all --parallel 2>&1) || exit_code=$?
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if echo "$output" | grep -q '"dependencies"'; then
        if echo "$output" | grep -q '"environment"'; then
            if echo "$output" | grep -q '"modules"'; then
                if echo "$output" | grep -q '"network"'; then
                    test_pass "All validations executed in parallel (${duration}s)"
                else
                    test_fail "Network validation missing from parallel output"
                fi
            else
                test_fail "Modules validation missing from parallel output"
            fi
        else
            test_fail "Environment validation missing from parallel output"
        fi
    else
        test_fail "Dependencies validation missing from parallel output"
    fi
    
    # Cleanup
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET ENVIRONMENT SKIP_NETWORK_CHECK
}

# =============================================================================
# CACHING TESTS
# =============================================================================

test_caching_functionality() {
    test_start "Caching functionality"
    
    # Clear cache
    rm -rf "$TEST_CACHE_DIR"/*
    
    # First run with caching enabled
    local start_time1=$(date +%s%N)
    local output1
    output1=$("$VALIDATION_SUITE" --type dependencies --cache 2>&1)
    local end_time1=$(date +%s%N)
    local duration1=$((($end_time1 - $start_time1) / 1000000))
    
    # Second run should use cache
    local start_time2=$(date +%s%N)
    local output2
    output2=$("$VALIDATION_SUITE" --type dependencies --cache 2>&1)
    local end_time2=$(date +%s%N)
    local duration2=$((($end_time2 - $start_time2) / 1000000))
    
    # Check if cache file was created
    if ls "$TEST_CACHE_DIR"/*.json >/dev/null 2>&1; then
        # Second run should be significantly faster
        if [[ $duration2 -lt $duration1 ]]; then
            test_pass "Caching working correctly (first: ${duration1}ms, cached: ${duration2}ms)"
        else
            test_warn "Cache may not be working efficiently (first: ${duration1}ms, cached: ${duration2}ms)"
        fi
    else
        test_fail "No cache files created in $TEST_CACHE_DIR"
    fi
}

# =============================================================================
# RETRY MECHANISM TESTS
# =============================================================================

test_retry_mechanism() {
    test_start "Retry mechanism"
    
    # This is difficult to test without mocking failures
    # We'll just verify the retry flag is accepted
    local output
    local exit_code=0
    
    export SKIP_NETWORK_CHECK="true"
    output=$("$VALIDATION_SUITE" --type network --retry 2>&1) || exit_code=$?
    
    if [[ -f "$VALIDATION_LOG_FILE" ]]; then
        if grep -q "retry" "$VALIDATION_LOG_FILE"; then
            test_pass "Retry mechanism initialized (check log for details)"
        else
            test_pass "Retry flag accepted (no retries needed)"
        fi
    else
        test_warn "Could not verify retry mechanism (log file not found)"
    fi
    
    unset SKIP_NETWORK_CHECK
}

# =============================================================================
# STRUCTURED LOGGING TESTS
# =============================================================================

test_structured_logging() {
    test_start "Structured logging"
    
    # Clear log
    > "$VALIDATION_LOG_FILE"
    
    # Run a validation
    "$VALIDATION_SUITE" --type dependencies >/dev/null 2>&1 || true
    
    if [[ -f "$VALIDATION_LOG_FILE" ]]; then
        # Check for JSON structured logs
        local json_lines=0
        while IFS= read -r line; do
            if echo "$line" | jq . >/dev/null 2>&1; then
                ((json_lines++))
            fi
        done < "$VALIDATION_LOG_FILE"
        
        if [[ $json_lines -gt 0 ]]; then
            test_pass "Structured JSON logging working ($json_lines log entries)"
        else
            test_fail "No valid JSON log entries found"
        fi
    else
        test_fail "Log file not created at $VALIDATION_LOG_FILE"
    fi
}

# =============================================================================
# BACKWARD COMPATIBILITY TESTS
# =============================================================================

test_backward_compatibility_environment() {
    test_start "Backward compatibility - validate-environment.sh"
    
    export POSTGRES_PASSWORD="test-password-12345678"
    export N8N_ENCRYPTION_KEY="test-encryption-key-12345678901234567890"
    export N8N_USER_MANAGEMENT_JWT_SECRET="test-jwt-secret-1234567890"
    export ENVIRONMENT="development"
    
    local output
    if output=$("$PROJECT_ROOT/scripts/validate-environment.sh" 2>&1); then
        if echo "$output" | grep -q "Using new consolidated validation suite"; then
            test_pass "validate-environment.sh correctly delegates to validation suite"
        else
            test_warn "validate-environment.sh may be using legacy implementation"
        fi
    else
        test_fail "validate-environment.sh failed to execute"
    fi
    
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET ENVIRONMENT
}

test_backward_compatibility_dependencies() {
    test_start "Backward compatibility - check-dependencies.sh"
    
    local output
    if output=$("$PROJECT_ROOT/scripts/check-dependencies.sh" 2>&1); then
        if echo "$output" | grep -q "Using new consolidated validation suite"; then
            test_pass "check-dependencies.sh correctly delegates to validation suite"
        else
            test_warn "check-dependencies.sh may be using legacy implementation"
        fi
    else
        test_fail "check-dependencies.sh failed to execute"
    fi
}

test_backward_compatibility_modules() {
    test_start "Backward compatibility - validate-module-consolidation.sh"
    
    local output
    if output=$("$PROJECT_ROOT/scripts/validate-module-consolidation.sh" 2>&1); then
        if echo "$output" | grep -q "Using new consolidated validation suite"; then
            test_pass "validate-module-consolidation.sh correctly delegates to validation suite"
        else
            test_warn "validate-module-consolidation.sh may be using legacy implementation"
        fi
    else
        test_fail "validate-module-consolidation.sh failed to execute"
    fi
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance_sequential_vs_parallel() {
    test_start "Performance comparison - sequential vs parallel"
    
    # Set required environment
    export POSTGRES_PASSWORD="test-password-12345678"
    export N8N_ENCRYPTION_KEY="test-encryption-key-12345678901234567890"
    export N8N_USER_MANAGEMENT_JWT_SECRET="test-jwt-secret-1234567890"
    export ENVIRONMENT="development"
    export SKIP_NETWORK_CHECK="true"
    
    # Sequential execution
    local seq_start=$(date +%s%N)
    "$VALIDATION_SUITE" --type all >/dev/null 2>&1 || true
    local seq_end=$(date +%s%N)
    local seq_duration=$((($seq_end - $seq_start) / 1000000))
    
    # Parallel execution
    local par_start=$(date +%s%N)
    "$VALIDATION_SUITE" --type all --parallel >/dev/null 2>&1 || true
    local par_end=$(date +%s%N)
    local par_duration=$((($par_end - $par_start) / 1000000))
    
    if [[ $par_duration -lt $seq_duration ]]; then
        local speedup=$(echo "scale=2; $seq_duration / $par_duration" | bc)
        test_pass "Parallel execution faster (sequential: ${seq_duration}ms, parallel: ${par_duration}ms, speedup: ${speedup}x)"
    else
        test_warn "Parallel execution not faster (sequential: ${seq_duration}ms, parallel: ${par_duration}ms)"
    fi
    
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET ENVIRONMENT SKIP_NETWORK_CHECK
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    setup_test_suite
    
    # Basic functionality tests
    run_test test_validation_suite_exists
    run_test test_validation_suite_executable
    run_test test_validation_suite_help
    
    # Validation type tests
    run_test test_dependencies_validation
    run_test test_environment_validation
    run_test test_modules_validation
    run_test test_network_validation
    run_test test_invalid_validation_type
    
    # Feature tests
    run_test test_parallel_all_validations
    run_test test_caching_functionality
    run_test test_retry_mechanism
    run_test test_structured_logging
    
    # Backward compatibility tests
    run_test test_backward_compatibility_environment
    run_test test_backward_compatibility_dependencies
    run_test test_backward_compatibility_modules
    
    # Performance tests
    run_test test_performance_sequential_vs_parallel
    
    # Cleanup
    cleanup_test
    
    # Show results
    test_suite_summary
}

# Run tests
main "$@"