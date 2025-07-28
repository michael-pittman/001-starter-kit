#!/bin/bash
# =============================================================================
# Modern Shell Unit Testing Framework
# Enhanced testing framework leveraging bash 5.3+ features
# Features: associative arrays, parallel execution, advanced error handling
# =============================================================================

set -euo pipefail

# Ensure bash 5.0+ for modern features
if (( BASH_VERSINFO[0] < 5 )); then
    echo "Error: This framework requires bash 5.0 or later. Current: ${BASH_VERSION}" >&2
    exit 1
fi

# =============================================================================
# FRAMEWORK GLOBALS AND CONFIGURATION
# =============================================================================

# Color codes for output
declare -r TEST_RED='\033[0;31m'
declare -r TEST_GREEN='\033[0;32m'
declare -r TEST_YELLOW='\033[0;33m'
declare -r TEST_BLUE='\033[0;34m'
declare -r TEST_CYAN='\033[0;36m'
declare -r TEST_BOLD='\033[1m'
declare -r TEST_NC='\033[0m'
declare -r TEST_DIM='\033[2m'
declare -r TEST_MAGENTA='\033[0;35m'

# Test state using associative arrays (bash 5.3+ feature)
declare -A TEST_RESULTS=()
declare -A TEST_METADATA=()
declare -A TEST_TIMING=()
declare -A TEST_COVERAGE=()
declare -A TEST_CATEGORIES=()

# Test counters using associative arrays for better organization
declare -A TEST_COUNTERS=(
    [total]=0
    [passed]=0
    [failed]=0
    [skipped]=0
    [warnings]=0
)

# Backward compatibility variables
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# Test state
declare CURRENT_TEST_NAME=""
declare CURRENT_TEST_FILE=""
declare CURRENT_TEST_CATEGORY=""
declare TEST_OUTPUT_FILE=""
declare TEST_START_TIME=""
declare TEST_SESSION_ID=""

# Framework configuration with enhanced defaults
declare TEST_VERBOSE="${TEST_VERBOSE:-false}"
declare TEST_STOP_ON_FAILURE="${TEST_STOP_ON_FAILURE:-false}"
declare TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
declare TEST_PARALLEL="${TEST_PARALLEL:-false}"
declare TEST_MAX_PARALLEL="${TEST_MAX_PARALLEL:-4}"
declare TEST_REPORT_FORMAT="${TEST_REPORT_FORMAT:-html}"
declare TEST_COVERAGE_ENABLED="${TEST_COVERAGE_ENABLED:-false}"
declare TEST_BENCHMARK_ENABLED="${TEST_BENCHMARK_ENABLED:-false}"

# Parallel execution control
declare -A PARALLEL_PIDS=()
declare -A PARALLEL_RESULTS=()
declare PARALLEL_JOB_COUNT=0

# =============================================================================
# CORE TESTING FUNCTIONS
# =============================================================================

# Initialize test framework
test_init() {
    local test_file="${1:-unknown}"
    CURRENT_TEST_FILE="$test_file"
    TEST_OUTPUT_FILE="/tmp/shell-test-$$-$(date +%s).log"
    TEST_START_TIME=$(date +%s)
    
    # Create test output directory
    mkdir -p "$(dirname "$TEST_OUTPUT_FILE")"
    
    echo -e "${TEST_BLUE}${TEST_BOLD}=== Shell Unit Test Framework ===${TEST_NC}"
    echo -e "${TEST_CYAN}Test file: $test_file${TEST_NC}"
    echo -e "${TEST_CYAN}Started at: $(date)${TEST_NC}"
    echo ""
}

# Clean up test framework
test_cleanup() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    
    echo ""
    echo -e "${TEST_BLUE}${TEST_BOLD}=== Test Results Summary ===${TEST_NC}"
    echo -e "${TEST_CYAN}Test file: $CURRENT_TEST_FILE${TEST_NC}"
    echo -e "${TEST_CYAN}Duration: ${duration}s${TEST_NC}"
    echo -e "${TEST_GREEN}Passed: $TEST_PASSED${TEST_NC}"
    echo -e "${TEST_RED}Failed: $TEST_FAILED${TEST_NC}"
    echo -e "${TEST_YELLOW}Skipped: $TEST_SKIPPED${TEST_NC}"
    echo -e "${TEST_CYAN}Total: $TEST_TOTAL${TEST_NC}"
    
    # Clean up temporary files
    if [[ -f "$TEST_OUTPUT_FILE" ]]; then
        rm -f "$TEST_OUTPUT_FILE"
    fi
    
    # Exit with error code if any tests failed
    if [[ $TEST_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# Start a test case
test_start() {
    local test_name="$1"
    local test_description="${2:-No description provided}"
    local test_tags="${3:-}"
    
    CURRENT_TEST_NAME="$test_name"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_COUNTERS[total]=$((TEST_COUNTERS[total] + 1))
    
    # Record test start time with nanosecond precision
    TEST_TIMING["${test_name}_start"]=$(date +%s%N)
    
    # Store test metadata
    TEST_METADATA["${test_name}_description"]="$test_description"
    TEST_METADATA["${test_name}_tags"]="$test_tags"
    TEST_METADATA["${test_name}_category"]="$CURRENT_TEST_CATEGORY"
    
    if [[ "$TEST_VERBOSE" == "true" ]]; then
        echo -e "${TEST_CYAN}${TEST_BOLD}▶${TEST_NC} ${TEST_CYAN}Running: $test_name${TEST_NC}"
        if [[ -n "$test_description" && "$test_description" != "No description provided" ]]; then
            echo -e "${TEST_DIM}  Description: $test_description${TEST_NC}"
        fi
        if [[ -n "$test_tags" ]]; then
            echo -e "${TEST_DIM}  Tags: $test_tags${TEST_NC}"
        fi
    fi
}

# Mark test as passed
test_pass() {
    local message="${1:-Test passed}"
    
    TEST_PASSED=$((TEST_PASSED + 1))
    TEST_COUNTERS[passed]=$((TEST_COUNTERS[passed] + 1))
    
    # Record test end time and calculate duration
    local end_time=$(date +%s%N)
    local start_time=${TEST_TIMING["${CURRENT_TEST_NAME}_start"]:-$end_time}
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    TEST_TIMING["${CURRENT_TEST_NAME}_duration"]=$duration_ms
    TEST_RESULTS["$CURRENT_TEST_NAME"]="PASS"
    TEST_METADATA["${CURRENT_TEST_NAME}_message"]="$message"
    
    if [[ "$TEST_BENCHMARK_ENABLED" == "true" ]]; then
        echo -e "${TEST_GREEN}✓${TEST_NC} $CURRENT_TEST_NAME ${TEST_DIM}(${duration_ms}ms)${TEST_NC}"
    else
        echo -e "${TEST_GREEN}✓${TEST_NC} $CURRENT_TEST_NAME"
    fi
    
    if [[ "$TEST_VERBOSE" == "true" && "$message" != "Test passed" ]]; then
        echo -e "${TEST_DIM}  → $message${TEST_NC}"
    fi
}

# Mark test as failed
test_fail() {
    local message="${1:-No message provided}"
    local error_code="${2:-1}"
    local context="${3:-}"
    
    TEST_FAILED=$((TEST_FAILED + 1))
    TEST_COUNTERS[failed]=$((TEST_COUNTERS[failed] + 1))
    
    # Record test end time and calculate duration
    local end_time=$(date +%s%N)
    local start_time=${TEST_TIMING["${CURRENT_TEST_NAME}_start"]:-$end_time}
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    TEST_TIMING["${CURRENT_TEST_NAME}_duration"]=$duration_ms
    TEST_RESULTS["$CURRENT_TEST_NAME"]="FAIL"
    TEST_METADATA["${CURRENT_TEST_NAME}_error"]="$message"
    TEST_METADATA["${CURRENT_TEST_NAME}_error_code"]="$error_code"
    
    if [[ -n "$context" ]]; then
        TEST_METADATA["${CURRENT_TEST_NAME}_context"]="$context"
    fi
    
    echo -e "${TEST_RED}✗${TEST_NC} $CURRENT_TEST_NAME ${TEST_DIM}(${duration_ms}ms)${TEST_NC}"
    echo -e "${TEST_RED}  ✗ Error: $message${TEST_NC}"
    
    if [[ -n "$context" ]]; then
        echo -e "${TEST_DIM}  Context: $context${TEST_NC}"
    fi
    
    if [[ "$TEST_STOP_ON_FAILURE" == "true" ]]; then
        echo -e "${TEST_RED}${TEST_BOLD}Stopping on failure as requested${TEST_NC}"
        test_cleanup
        exit 1
    fi
}

# Skip a test
test_skip() {
    local reason="${1:-No reason provided}"
    local skip_category="${2:-general}"
    
    TEST_SKIPPED=$((TEST_SKIPPED + 1))
    TEST_COUNTERS[skipped]=$((TEST_COUNTERS[skipped] + 1))
    
    # Record skip metadata
    TEST_RESULTS["$CURRENT_TEST_NAME"]="SKIP"
    TEST_METADATA["${CURRENT_TEST_NAME}_skip_reason"]="$reason"
    TEST_METADATA["${CURRENT_TEST_NAME}_skip_category"]="$skip_category"
    
    echo -e "${TEST_YELLOW}○${TEST_NC} $CURRENT_TEST_NAME ${TEST_YELLOW}(skipped: $reason)${TEST_NC}"
    
    if [[ "$TEST_VERBOSE" == "true" ]]; then
        echo -e "${TEST_DIM}  Category: $skip_category${TEST_NC}"
    fi
}

# Add test warning (new feature)
test_warn() {
    local message="${1:-Warning message}"
    local warning_code="${2:-0}"
    
    TEST_COUNTERS[warnings]=$((TEST_COUNTERS[warnings] + 1))
    
    TEST_METADATA["${CURRENT_TEST_NAME}_warning"]="$message"
    TEST_METADATA["${CURRENT_TEST_NAME}_warning_code"]="$warning_code"
    
    echo -e "${TEST_YELLOW}⚠${TEST_NC} $CURRENT_TEST_NAME ${TEST_YELLOW}(warning: $message)${TEST_NC}"
}

# =============================================================================
# ASSERTION FUNCTIONS
# =============================================================================

# Assert that two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [[ "$expected" == "$actual" ]]; then
        test_pass
    else
        test_fail "$message. Expected: '$expected', Actual: '$actual'"
    fi
}

# Assert that two values are not equal
assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        test_pass
    else
        test_fail "$message. Both values are: '$expected'"
    fi
}

# Assert that a string contains a substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        test_pass
    else
        test_fail "$message. '$haystack' does not contain '$needle'"
    fi
}

# Assert that a string does not contain a substring
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        test_pass
    else
        test_fail "$message. '$haystack' contains '$needle'"
    fi
}

# Assert that a string matches a pattern
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern}"
    
    if [[ "$string" =~ $pattern ]]; then
        test_pass
    else
        test_fail "$message. '$string' does not match pattern '$pattern'"
    fi
}

# Assert that a value is empty
assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"
    
    if [[ -z "$value" ]]; then
        test_pass
    else
        test_fail "$message. Value is: '$value'"
    fi
}

# Assert that a value is not empty
assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"
    
    if [[ -n "$value" ]]; then
        test_pass
    else
        test_fail "$message. Value is empty"
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file_path" ]]; then
        test_pass
    else
        test_fail "$message. File does not exist: '$file_path'"
    fi
}

# Assert that a directory exists
assert_dir_exists() {
    local dir_path="$1"
    local message="${2:-Directory should exist}"
    
    if [[ -d "$dir_path" ]]; then
        test_pass
    else
        test_fail "$message. Directory does not exist: '$dir_path'"
    fi
}

# Assert that a command succeeds (exit code 0)
assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command should succeed}"
    
    if eval "$command" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "$message. Command failed: '$command'"
    fi
}

# Assert that a command fails (exit code != 0)
assert_command_fails() {
    local command="$1"
    local message="${2:-Command should fail}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "$message. Command succeeded: '$command'"
    fi
}

# Assert that command output contains expected text
assert_output_contains() {
    local command="$1"
    local expected="$2"
    local message="${3:-Command output should contain expected text}"
    
    local output
    output=$(eval "$command" 2>&1)
    
    if [[ "$output" == *"$expected"* ]]; then
        test_pass
    else
        test_fail "$message. Output: '$output', Expected to contain: '$expected'"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Capture command output (both stdout and stderr)
capture_output() {
    local command="$1"
    eval "$command" 2>&1
}

# Run command with timeout
run_with_timeout() {
    local timeout="$1"
    local command="$2"
    
    # Use timeout command if available, otherwise basic timeout
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" bash -c "$command"
    else
        # Fallback for systems without timeout command
        eval "$command"
    fi
}

# Create temporary test file
create_temp_file() {
    local prefix="${1:-test}"
    mktemp "/tmp/${prefix}-XXXXXX"
}

# Create temporary test directory
create_temp_dir() {
    local prefix="${1:-test}"
    mktemp -d "/tmp/${prefix}-XXXXXX"
}

# =============================================================================
# MOCK FUNCTIONS
# =============================================================================

# Simple function override mechanism for mocking
mock_function() {
    local original_function="$1"
    local mock_implementation="$2"
    
    # Create backup of original function
    if declare -f "$original_function" >/dev/null 2>&1; then
        # Use a simpler backup method
        declare -f "$original_function" > /tmp/${original_function}_backup.sh
        sed -i.bak "1s/.*/${original_function}_original()/" /tmp/${original_function}_backup.sh
        source /tmp/${original_function}_backup.sh
        rm -f /tmp/${original_function}_backup.sh /tmp/${original_function}_backup.sh.bak
    fi
    
    # Replace with mock using temporary file for complex implementations
    local temp_mock=$(mktemp)
    echo "$original_function() {" > "$temp_mock"
    echo "$mock_implementation" >> "$temp_mock"
    echo "}" >> "$temp_mock"
    
    source "$temp_mock"
    rm -f "$temp_mock"
}

# Restore mocked function
restore_function() {
    local function_name="$1"
    
    if declare -f "${function_name}_original" >/dev/null 2>&1; then
        # Unset the mock
        unset -f "$function_name"
        
        # Restore using temporary file
        local temp_restore=$(mktemp)
        declare -f "${function_name}_original" | sed "s/${function_name}_original/${function_name}/" > "$temp_restore"
        source "$temp_restore"
        rm -f "$temp_restore"
        
        # Clean up the backup
        unset -f "${function_name}_original"
    fi
}

# =============================================================================
# TEST DISCOVERY AND EXECUTION
# =============================================================================

# Run all test functions in current script
run_all_tests() {
    local test_functions
    test_functions=$(declare -F | grep '^declare -f test_' | awk '{print $3}' | grep -v '^test_init$' | grep -v '^test_cleanup$' | grep -v '^test_start$' | grep -v '^test_pass$' | grep -v '^test_fail$' | grep -v '^test_skip$')
    
    for test_func in $test_functions; do
        test_start "$test_func"
        if declare -f "$test_func" >/dev/null 2>&1; then
            if ! "$test_func"; then
                test_fail "Test function threw an error"
            fi
        else
            test_fail "Test function not found: $test_func"
        fi
    done
}

# Run tests from external test file
run_test_file() {
    local test_file="$1"
    
    if [[ ! -f "$test_file" ]]; then
        echo -e "${TEST_RED}Error: Test file not found: $test_file${TEST_NC}"
        return 1
    fi
    
    # Source the test file and run tests
    source "$test_file"
    run_all_tests
}

# =============================================================================
# COVERAGE AND PERFORMANCE TRACKING
# =============================================================================

# Initialize coverage tracking
init_coverage_tracking() {
    if [[ -z "${TEST_COVERED_FUNCTIONS:-}" ]]; then
        declare -gA TEST_COVERED_FUNCTIONS=()
        declare -gA TEST_FUNCTION_CALL_COUNTS=()
    fi
}

# Start coverage tracking for a test
start_test_coverage() {
    local test_name="$1"
    
    if [[ "$TEST_COVERAGE_ENABLED" != "true" ]]; then
        return
    fi
    
    # Enable function tracing
    set -T
    trap 'track_function_call "${FUNCNAME[0]}"' DEBUG
}

# End coverage tracking for a test
end_test_coverage() {
    local test_name="$1"
    
    if [[ "$TEST_COVERAGE_ENABLED" != "true" ]]; then
        return
    fi
    
    # Disable function tracing
    trap - DEBUG
    set +T
}

# Track function calls for coverage
track_function_call() {
    local function_name="$1"
    
    # Skip framework functions
    if [[ "$function_name" == test_* || "$function_name" == assert_* || "$function_name" == mock_* ]]; then
        return
    fi
    
    TEST_COVERED_FUNCTIONS["$function_name"]=1
    TEST_FUNCTION_CALL_COUNTS["$function_name"]=$((${TEST_FUNCTION_CALL_COUNTS["$function_name"]:-0} + 1))
}

# Generate coverage report
generate_coverage_report() {
    if [[ "$TEST_COVERAGE_ENABLED" != "true" ]]; then
        return
    fi
    
    local coverage_file="/tmp/${TEST_SESSION_ID}/coverage/coverage-report.html"
    
    cat > "$coverage_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Test Coverage Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .function { padding: 10px; margin: 5px 0; border-left: 4px solid #ccc; }
        .covered { border-left-color: #4CAF50; background: #f1f8e9; }
        .uncovered { border-left-color: #f44336; background: #ffebee; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f5f5f5; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Function Coverage Report</h1>
        <p>Session: ${TEST_SESSION_ID}</p>
        <p>Generated: $(date)</p>
    </div>
    
    <h2>Covered Functions</h2>
    <table>
        <tr><th>Function</th><th>Call Count</th></tr>
EOF
    
    for func in "${!TEST_COVERED_FUNCTIONS[@]}"; do
        local call_count=${TEST_FUNCTION_CALL_COUNTS["$func"]:-0}
        echo "        <tr><td>$func</td><td>$call_count</td></tr>" >> "$coverage_file"
    done
    
    cat >> "$coverage_file" << 'EOF'
    </table>
</body>
</html>
EOF
    
    echo -e "${TEST_CYAN}Coverage report generated: $coverage_file${TEST_NC}"
}

# =============================================================================
# PERFORMANCE AND BENCHMARKING
# =============================================================================

# Performance benchmark wrapper
benchmark_test() {
    local test_function="$1"
    local iterations="${2:-1}"
    local warmup_iterations="${3:-0}"
    
    if [[ "$TEST_BENCHMARK_ENABLED" != "true" ]]; then
        "$test_function"
        return
    fi
    
    local total_time=0
    local min_time=9999999999
    local max_time=0
    
    # Warmup runs
    for ((i=0; i<warmup_iterations; i++)); do
        "$test_function" >/dev/null 2>&1
    done
    
    # Benchmark runs
    for ((i=0; i<iterations; i++)); do
        local start_time=$(date +%s%N)
        "$test_function"
        local end_time=$(date +%s%N)
        local duration=$((end_time - start_time))
        
        total_time=$((total_time + duration))
        
        if [[ $duration -lt $min_time ]]; then
            min_time=$duration
        fi
        if [[ $duration -gt $max_time ]]; then
            max_time=$duration
        fi
    done
    
    local avg_time=$((total_time / iterations))
    local avg_ms=$((avg_time / 1000000))
    local min_ms=$((min_time / 1000000))
    local max_ms=$((max_time / 1000000))
    
    TEST_METADATA["${test_function}_benchmark_avg"]="$avg_ms"
    TEST_METADATA["${test_function}_benchmark_min"]="$min_ms"
    TEST_METADATA["${test_function}_benchmark_max"]="$max_ms"
    TEST_METADATA["${test_function}_benchmark_iterations"]="$iterations"
    
    echo -e "${TEST_MAGENTA}Benchmark: $test_function - Avg: ${avg_ms}ms, Min: ${min_ms}ms, Max: ${max_ms}ms (${iterations} runs)${TEST_NC}"
}

# Display performance statistics
display_performance_stats() {
    echo -e "${TEST_BLUE}${TEST_BOLD}=== Performance Statistics ===${TEST_NC}"
    
    local total_benchmark_time=0
    local benchmark_count=0
    
    for key in "${!TEST_METADATA[@]}"; do
        if [[ "$key" == *"_benchmark_avg" ]]; then
            local test_name=${key%_benchmark_avg}
            local avg_time=${TEST_METADATA["$key"]}
            local min_time=${TEST_METADATA["${test_name}_benchmark_min"]:-0}
            local max_time=${TEST_METADATA["${test_name}_benchmark_max"]:-0}
            local iterations=${TEST_METADATA["${test_name}_benchmark_iterations"]:-1}
            
            echo -e "${TEST_CYAN}$test_name: ${avg_time}ms avg (${min_time}-${max_time}ms, ${iterations} runs)${TEST_NC}"
            
            total_benchmark_time=$((total_benchmark_time + avg_time))
            benchmark_count=$((benchmark_count + 1))
        fi
    done
    
    if [[ $benchmark_count -gt 0 ]]; then
        local avg_benchmark_time=$((total_benchmark_time / benchmark_count))
        echo -e "${TEST_BLUE}Overall average: ${avg_benchmark_time}ms across $benchmark_count tests${TEST_NC}"
    fi
}

# =============================================================================
# ENHANCED REPORTING
# =============================================================================

# Generate comprehensive test report
generate_enhanced_report() {
    local duration_s="$1"
    local duration_ms="$2"
    
    local report_file="/tmp/${TEST_SESSION_ID}/test-report.html"
    local success_rate=0
    
    if [[ ${TEST_COUNTERS[total]} -gt 0 ]]; then
        success_rate=$(( (TEST_COUNTERS[passed] * 100) / TEST_COUNTERS[total] ))
    fi
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Enhanced Test Report - ${TEST_METADATA["test_file"]:-Unknown}</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background: #f8f9fa; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; border-left: 4px solid #007bff; }
        .test-result { margin: 15px 0; padding: 15px; border-radius: 8px; border-left: 4px solid #ccc; }
        .pass { border-left-color: #28a745; background: #d4edda; }
        .fail { border-left-color: #dc3545; background: #f8d7da; }
        .skip { border-left-color: #ffc107; background: #fff3cd; }
        .warn { border-left-color: #fd7e14; background: #ffeaa7; }
        .metadata { background: #e9ecef; padding: 15px; border-radius: 8px; margin-top: 20px; }
        .timing { font-size: 0.9em; color: #6c757d; }
        .error-details { background: #ffe6e6; padding: 10px; border-radius: 5px; margin-top: 10px; font-family: monospace; font-size: 0.9em; }
        .success-rate { font-size: 2em; font-weight: bold; color: #28a745; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #dee2e6; }
        th { background: #f8f9fa; font-weight: 600; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Enhanced Test Report</h1>
            <p><strong>Session:</strong> ${TEST_METADATA["session_id"]:-N/A}</p>
            <p><strong>Test File:</strong> ${TEST_METADATA["test_file"]:-N/A}</p>
            <p><strong>Category:</strong> ${TEST_METADATA["category"]:-N/A}</p>
            <p><strong>Started:</strong> ${TEST_METADATA["start_time"]:-N/A}</p>
            <p><strong>Duration:</strong> ${duration_s}.$(printf "%03d" $((duration_ms % 1000)))s</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="success-rate">${TEST_COUNTERS[passed]}/${TEST_COUNTERS[total]}</div>
                <div>Tests Passed (${success_rate}%)</div>
            </div>
            <div class="stat-card">
                <div style="font-size: 2em; font-weight: bold; color: #dc3545;">${TEST_COUNTERS[failed]}</div>
                <div>Failed</div>
            </div>
            <div class="stat-card">
                <div style="font-size: 2em; font-weight: bold; color: #ffc107;">${TEST_COUNTERS[skipped]}</div>
                <div>Skipped</div>
            </div>
            <div class="stat-card">
                <div style="font-size: 2em; font-weight: bold; color: #fd7e14;">${TEST_COUNTERS[warnings]}</div>
                <div>Warnings</div>
            </div>
        </div>
        
        <h2>Test Results</h2>
EOF
    
    # Add individual test results
    for test_name in "${!TEST_RESULTS[@]}"; do
        local result=${TEST_RESULTS["$test_name"]}
        local duration=${TEST_TIMING["${test_name}_duration"]:-0}
        local message=${TEST_METADATA["${test_name}_message"]:-}
        local error=${TEST_METADATA["${test_name}_error"]:-}
        local css_class=""
        local status_icon=""
        
        case "$result" in
            "PASS") css_class="pass"; status_icon="✓" ;;
            "FAIL") css_class="fail"; status_icon="✗" ;;
            "SKIP") css_class="skip"; status_icon="○" ;;
            *) css_class="warn"; status_icon="⚠" ;;
        esac
        
        cat >> "$report_file" << EOF
        <div class="test-result $css_class">
            <h3>$status_icon $test_name</h3>
            <div class="timing">Duration: ${duration}ms</div>
EOF
        
        if [[ -n "$message" ]]; then
            echo "            <p>$message</p>" >> "$report_file"
        fi
        
        if [[ -n "$error" ]]; then
            echo "            <div class=\"error-details\">Error: $error</div>" >> "$report_file"
        fi
        
        echo "        </div>" >> "$report_file"
    done
    
    # Add metadata section
    cat >> "$report_file" << EOF
        
        <div class="metadata">
            <h3>Test Environment</h3>
            <p><strong>Bash Version:</strong> ${TEST_METADATA["bash_version"]:-N/A}</p>
            <p><strong>Hostname:</strong> ${TEST_METADATA["hostname"]:-N/A}</p>
            <p><strong>User:</strong> ${TEST_METADATA["user"]:-N/A}</p>
            <p><strong>Working Directory:</strong> ${TEST_METADATA["pwd"]:-N/A}</p>
            <p><strong>Parallel Execution:</strong> $TEST_PARALLEL</p>
            <p><strong>Coverage Enabled:</strong> $TEST_COVERAGE_ENABLED</p>
            <p><strong>Benchmarking Enabled:</strong> $TEST_BENCHMARK_ENABLED</p>
        </div>
    </div>
</body>
</html>
EOF
    
    echo -e "${TEST_CYAN}Enhanced report generated: $report_file${TEST_NC}"
}

# Save failure artifact for debugging
save_failure_artifact() {
    local test_name="$1"
    local error_message="$2"
    local context="$3"
    local stack_trace="$4"
    
    local artifact_file="/tmp/${TEST_SESSION_ID}/artifacts/failure-${test_name}.txt"
    
    cat > "$artifact_file" << EOF
Test Failure Artifact
=====================
Test Name: $test_name
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
Error: $error_message
Context: $context

Stack Trace:
$stack_trace

Environment:
Bash Version: $BASH_VERSION
PWD: $(pwd)
User: $(whoami)
Hostname: $(hostname)

Test Session: ${TEST_SESSION_ID}
EOF
}

# Capture stack trace for debugging
capture_stack_trace() {
    local stack=""
    local frame=0
    
    while [[ ${BASH_LINENO[$frame]} ]]; do
        local line=${BASH_LINENO[$frame]}
        local func=${FUNCNAME[$((frame + 1))]}
        local file=${BASH_SOURCE[$((frame + 1))]}
        
        if [[ "$func" != "capture_stack_trace" && "$func" != "test_fail" ]]; then
            stack+="  at $func ($file:$line)\\n"
        fi
        
        frame=$((frame + 1))
    done
    
    echo -e "$stack"
}

# Cleanup temporary files while preserving reports
cleanup_temp_files() {
    # Clean up temporary test files
    if [[ -n "${TEST_TEMP_FILES:-}" ]]; then
        for file in "${TEST_TEMP_FILES[@]}"; do
            rm -f "$file" 2>/dev/null || true
        done
    fi
    
    # Clean up temporary directories (except reports)
    if [[ -n "${TEST_TEMP_DIRS:-}" ]]; then
        for dir in "${TEST_TEMP_DIRS[@]}"; do
            if [[ "$dir" != *"${TEST_SESSION_ID}"* ]]; then
                rm -rf "$dir" 2>/dev/null || true
            fi
        done
    fi
    
    # Clean up mock scripts
    restore_all_mocks
}

# =============================================================================
# ENHANCED TRAP HANDLERS
# =============================================================================

# Enhanced error trap handler
error_trap_handler() {
    local exit_code=$?
    local line_number=${BASH_LINENO[0]}
    local command="${BASH_COMMAND}"
    
    if [[ $exit_code -ne 0 && -n "$CURRENT_TEST_NAME" ]]; then
        local error_context="Line $line_number: $command"
        test_fail "Unexpected error in test execution" "$exit_code" "$error_context"
    fi
}

# Enhanced exit trap handler
exit_trap_handler() {
    # Ensure cleanup runs even on unexpected exit
    test_cleanup 2>/dev/null || true
}

# Disable error trap temporarily
disable_error_trap() {
    trap - ERR
}

# Re-enable error trap
enable_error_trap() {
    trap 'error_trap_handler' ERR
}

# =============================================================================
# FRAMEWORK INITIALIZATION
# =============================================================================

# Auto-initialize framework when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Framework is being sourced, initialize silently
    if [[ -z "${TEST_SESSION_ID:-}" ]]; then
        TEST_SESSION_ID="framework-$$-$(date +%s)"
        
        # Create session directory
        mkdir -p "/tmp/${TEST_SESSION_ID}/coverage"
        mkdir -p "/tmp/${TEST_SESSION_ID}/artifacts"
        
        # Initialize tracking arrays if not already done
        if [[ -z "${TEST_RESULTS:-}" ]]; then
            declare -gA TEST_RESULTS=()
            declare -gA TEST_METADATA=()
            declare -gA TEST_TIMING=()
            declare -gA TEST_COVERAGE=()
            declare -gA TEST_CATEGORIES=()
        fi
        
        # Initialize tracking variables
        if [[ -z "${TEST_TEMP_FILES:-}" ]]; then
            declare -g TEST_TEMP_FILES=()
            declare -g TEST_TEMP_DIRS=()
            declare -g TEST_MOCK_SCRIPTS=()
        fi
    fi
    
    # Set up enhanced traps
    trap 'error_trap_handler' ERR
    trap 'exit_trap_handler' EXIT
else
    # Framework is being executed directly - show help
    echo "Modern Shell Testing Framework v2.0"
    echo "====================================="
    echo "This framework provides enhanced testing capabilities for bash 5.3+"
    echo ""
    echo "Features:"
    echo "  • Associative arrays for comprehensive test tracking"
    echo "  • Parallel test execution with job control"
    echo "  • Enhanced mocking with call tracking"
    echo "  • Coverage tracking and reporting"
    echo "  • Performance benchmarking"
    echo "  • Detailed HTML reports with metadata"
    echo "  • Advanced assertion functions"
    echo "  • Error handling with stack traces"
    echo ""
    echo "Usage: source this file in your test scripts"
    echo "Example:"
    echo "  source /path/to/shell-test-framework.sh"
    echo "  test_init \"my-test.sh\" \"unit\""
    echo "  # Your tests here"
    echo "  test_cleanup"
fi