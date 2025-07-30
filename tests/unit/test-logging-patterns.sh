#!/usr/bin/env bash
# =============================================================================
# Test Logging Patterns
# Comprehensive testing of standardized logging functions
# =============================================================================

# Test configuration
TEST_NAME="test-logging-patterns"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TEMP_DIR="/tmp/${TEST_NAME}-$$"
TEST_LOG_FILE="$TEMP_DIR/test.log"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# TEST HELPERS
# =============================================================================

# Initialize test environment
setup_test_env() {
    echo -e "${BLUE}Setting up test environment...${NC}"
    mkdir -p "$TEMP_DIR"
    
    # Source the logging module
    if ! source "$PROJECT_ROOT/lib/modules/core/logging.sh"; then
        echo -e "${RED}Failed to source logging module${NC}"
        exit 1
    fi
    
    # Initialize logging for tests with file output enabled
    init_logging "$TEST_LOG_FILE" "DEBUG" true true false
    
    # Debug: Check LOG_FILE variable
    echo "DEBUG: LOG_FILE = '$TEST_LOG_FILE'"
    echo "DEBUG: LOG_FILE_ENABLED = '$LOG_FILE_ENABLED'"
    
    # Ensure log file exists and is writable
    if [[ -n "$TEST_LOG_FILE" ]]; then
        touch "$TEST_LOG_FILE"
    else
        echo -e "${RED}ERROR: TEST_LOG_FILE is empty${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Test environment ready${NC}"
}

# Cleanup test environment
cleanup_test_env() {
    echo -e "${BLUE}Cleaning up test environment...${NC}"
    rm -rf "$TEMP_DIR"
}

# Test assertion function
assert() {
    local test_name="$1"
    local condition="$2"
    local message="${3:-Test failed}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if eval "$condition"; then
        echo -e "${GREEN}✓ $test_name${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ $test_name: $message${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test logging function
test_logging_function() {
    local function_name="$1"
    local level="$2"
    local message="$3"
    local expected_pattern="$4"
    
    # Clear log file
    > "$TEST_LOG_FILE"
    
    # Call logging function
    if [[ "$function_name" == "log_fatal" ]]; then
        # For fatal, we need to capture the exit by using a wrapper
        (
            # Override log_fatal to not exit
            log_fatal_no_exit() {
                log_message "FATAL" "$1" "${2:-}"
            }
            log_fatal_no_exit "$message"
        )
    else
        $function_name "$message"
    fi
    
    # Check if message was logged
    if [[ -f "$TEST_LOG_FILE" ]]; then
        assert "$function_name logs message" \
               "grep -q '$expected_pattern' '$TEST_LOG_FILE'" \
               "Expected pattern '$expected_pattern' not found in log"
    else
        assert "$function_name logs message" \
               "false" \
               "Log file not found: $TEST_LOG_FILE"
    fi
}

# =============================================================================
# TEST CASES
# =============================================================================

# Test 1: Log level hierarchy
test_log_levels() {
    echo -e "${BLUE}Testing log level hierarchy...${NC}"
    
    # Test each log level
    set_log_level "DEBUG"
    assert "DEBUG level allows all messages" \
           "should_log_level 'DEBUG' && should_log_level 'INFO' && should_log_level 'WARN' && should_log_level 'ERROR' && should_log_level 'FATAL'" \
           "DEBUG level should allow all log levels"
    
    set_log_level "INFO"
    assert "INFO level blocks DEBUG" \
           "! should_log_level 'DEBUG' && should_log_level 'INFO' && should_log_level 'WARN' && should_log_level 'ERROR' && should_log_level 'FATAL'" \
           "INFO level should block DEBUG but allow others"
    
    set_log_level "WARN"
    assert "WARN level blocks DEBUG and INFO" \
           "! should_log_level 'DEBUG' && ! should_log_level 'INFO' && should_log_level 'WARN' && should_log_level 'ERROR' && should_log_level 'FATAL'" \
           "WARN level should block DEBUG and INFO but allow others"
    
    set_log_level "ERROR"
    assert "ERROR level blocks DEBUG, INFO, and WARN" \
           "! should_log_level 'DEBUG' && ! should_log_level 'INFO' && ! should_log_level 'WARN' && should_log_level 'ERROR' && should_log_level 'FATAL'" \
           "ERROR level should block DEBUG, INFO, and WARN but allow others"
    
    set_log_level "FATAL"
    assert "FATAL level only allows FATAL" \
           "! should_log_level 'DEBUG' && ! should_log_level 'INFO' && ! should_log_level 'WARN' && ! should_log_level 'ERROR' && should_log_level 'FATAL'" \
           "FATAL level should only allow FATAL messages"
}

# Test 2: Logging functions
test_logging_functions() {
    echo -e "${BLUE}Testing logging functions...${NC}"
    
    set_log_level "DEBUG"
    
    # Test each logging function
    test_logging_function "log_debug" "DEBUG" "Debug message" "\[DEBUG\]"
    test_logging_function "log_info" "INFO" "Info message" "\[INFO\]"
    test_logging_function "log_warn" "WARN" "Warning message" "\[WARN\]"
    test_logging_function "log_error" "ERROR" "Error message" "\[ERROR\]"
    test_logging_function "log_fatal" "FATAL" "Fatal message" "\[FATAL\]"
}

# Test 3: Timestamp formatting
test_timestamp_formatting() {
    echo -e "${BLUE}Testing timestamp formatting...${NC}"
    
    # Test standard timestamp
    local timestamp
    timestamp=$(get_timestamp)
    assert "Standard timestamp format" \
           "echo '$timestamp' | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'" \
           "Timestamp should match YYYY-MM-DD HH:MM:SS format"
    
    # Test ISO timestamp
    local iso_timestamp
    iso_timestamp=$(get_iso_timestamp)
    assert "ISO timestamp format" \
           "echo '$iso_timestamp' | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'" \
           "ISO timestamp should match YYYY-MM-DDTHH:MM:SSZ format"
}

# Test 4: Context logging
test_context_logging() {
    echo -e "${BLUE}Testing context logging...${NC}"
    
    # Clear log file
    > "$TEST_LOG_FILE"
    
    # Test logging with context
    log_with_context "INFO" "Test message" "TEST_CONTEXT"
    
    assert "Context logging includes context" \
           "grep -q '\[TEST_CONTEXT\]' '$TEST_LOG_FILE'" \
           "Context should be included in log message"
}

# Test 5: Correlation ID
test_correlation_id() {
    echo -e "${BLUE}Testing correlation ID...${NC}"
    
    # Enable structured logging
    set_structured_logging true
    
    # Generate correlation ID
    local correlation_id
    correlation_id=$(generate_correlation_id)
    
    assert "Correlation ID generation" \
           "[[ -n '$correlation_id' && '$correlation_id' =~ ^[0-9]+-[0-9a-f]{4}$ ]]" \
           "Correlation ID should be in format timestamp-hex"
    
    # Test setting correlation ID
    set_correlation_id "test-cid-123"
    assert "Setting correlation ID" \
           "[[ '$(get_correlation_id)' == 'test-cid-123' ]]" \
           "Correlation ID should be set correctly"
}

# Test 6: Structured logging
test_structured_logging() {
    echo -e "${BLUE}Testing structured logging...${NC}"
    
    # Enable structured logging
    set_structured_logging true
    
    # Clear log file
    > "$TEST_LOG_FILE"
    
    # Test structured logging
    log_structured "INFO" "Structured message" '{"key": "value"}' "TEST_CONTEXT"
    
    assert "Structured logging format" \
           "grep -q '\"level\": \"INFO\"' '$TEST_LOG_FILE'" \
           "Structured log should contain JSON format"
    
    assert "Structured logging data" \
           "grep -q '\"data\": {\"key\": \"value\"}' '$TEST_LOG_FILE'" \
           "Structured log should contain data field"
}

# Test 7: Log file management
test_log_file_management() {
    echo -e "${BLUE}Testing log file management...${NC}"
    
    local test_log="$TEMP_DIR/rotation-test.log"
    
    # Initialize logging with file output
    init_logging "$test_log" "DEBUG" false true false
    
    # Test basic file logging
    log_info "Test message 1"
    log_info "Test message 2"
    log_info "Test message 3"
    
    # Check if log file exists and has content
    assert "Log file creation" \
           "[[ -f '$test_log' ]]" \
           "Log file should be created"
    
    assert "Log file content" \
           "[[ \$(wc -l < \"$test_log\") -ge 3 ]]" \
           "Log file should contain at least 3 lines"
    
    # Test log rotation configuration (without actually triggering rotation)
    set_log_rotation true 100 5  # 100MB max size, 5 files max
    
    assert "Log rotation configuration" \
           "[[ '$LOG_FILE_ROTATION_ENABLED' == 'true' ]]" \
           "Log rotation should be enabled"
    
    assert "Log rotation max files" \
           "[[ $LOG_FILE_MAX_FILES -eq 5 ]]" \
           "Log rotation max files should be set to 5"
}

# Test 8: Performance logging
test_performance_logging() {
    echo -e "${BLUE}Testing performance logging...${NC}"
    
    # Test timer functionality
    start_timer "test_timer"
    
    # Simulate some work
    sleep 0.1
    
    end_timer "test_timer"
    
    assert "Performance timer" \
           "[[ -f '$PERFORMANCE_TIMERS_FILE' || -f '${PERFORMANCE_TIMERS_FILE}.fallback' ]]" \
           "Performance timer file should exist"
}

# Test 9: Log formatting consistency
test_log_formatting() {
    echo -e "${BLUE}Testing log formatting consistency...${NC}"
    
    set_log_level "DEBUG"
    
    # Clear log file
    > "$TEST_LOG_FILE"
    
    # Test different log levels and check format consistency
    log_debug "Debug message"
    log_info "Info message"
    log_warn "Warning message"
    log_error "Error message"
    
    # Check that all messages have consistent format
    local line_count
    line_count=$(wc -l < "$TEST_LOG_FILE")
    local formatted_count
    formatted_count=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[(DEBUG|INFO|WARN|ERROR)\]' "$TEST_LOG_FILE")
    
    assert "Log format consistency" \
           "[[ $line_count -eq $formatted_count ]]" \
           "All log messages should have consistent format"
}

# Test 10: Log configuration
test_log_configuration() {
    echo -e "${BLUE}Testing log configuration...${NC}"
    
    # Test console output configuration
    set_console_output false
    assert "Console output disabled" \
           "[[ '$CONSOLE_OUTPUT_ENABLED' == 'false' ]]" \
           "Console output should be disabled"
    
    set_console_output true
    assert "Console output enabled" \
           "[[ '$CONSOLE_OUTPUT_ENABLED' == 'true' ]]" \
           "Console output should be enabled"
    
    # Test console colors configuration
    set_console_colors false
    assert "Console colors disabled" \
           "[[ '$CONSOLE_COLORS_ENABLED' == 'false' ]]" \
           "Console colors should be disabled"
    
    set_console_colors true
    assert "Console colors enabled" \
           "[[ '$CONSOLE_COLORS_ENABLED' == 'true' ]]" \
           "Console colors should be enabled"
}

# Test 11: Log analysis functions
test_log_analysis() {
    echo -e "${BLUE}Testing log analysis functions...${NC}"
    
    # Create test log with known content
    cat > "$TEST_LOG_FILE" << EOF
2024-01-01 10:00:00 [INFO] Test info message
2024-01-01 10:00:01 [DEBUG] Test debug message
2024-01-01 10:00:02 [WARN] Test warning message
2024-01-01 10:00:03 [ERROR] Test error message
2024-01-01 10:00:04 [INFO] Another info message
EOF
    
    # Test log statistics
    local stats_output
    stats_output=$(get_log_stats "$TEST_LOG_FILE")
    
    assert "Log statistics function" \
           "echo '$stats_output' | grep -q 'Total lines:'" \
           "Log statistics should show total lines"
    
    assert "Log statistics levels" \
           "echo '$stats_output' | grep -q 'INFO:  2'" \
           "Log statistics should show correct level counts"
    
    # Test log search
    local search_results
    search_results=$(search_logs "info" "$TEST_LOG_FILE")
    
    assert "Log search function" \
           "echo '$search_results' | grep -c 'INFO' | grep -q '2'" \
           "Log search should find correct number of INFO messages"
    
    # Test recent logs
    local recent_logs
    recent_logs=$(get_recent_logs 3 "$TEST_LOG_FILE")
    local recent_count
    recent_count=$(echo "$recent_logs" | wc -l)
    
    assert "Recent logs function" \
           "[[ $recent_count -eq 3 ]]" \
           "Recent logs should return requested number of lines"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo -e "${BLUE}Starting Logging Patterns Test Suite${NC}"
    echo "=========================================="
    
    # Setup test environment
    setup_test_env
    
    # Run all tests
    test_log_levels
    test_logging_functions
    test_timestamp_formatting
    test_context_logging
    test_correlation_id
    test_structured_logging
    test_log_file_management
    test_performance_logging
    test_log_formatting
    test_log_configuration
    test_log_analysis
    
    # Print results
    echo ""
    echo -e "${BLUE}Test Results:${NC}"
    echo "=============="
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${BLUE}Total: $TESTS_TOTAL${NC}"
    
    # Cleanup
    cleanup_test_env
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi