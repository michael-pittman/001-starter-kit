#!/usr/bin/env bash

# Test User Feedback Module
# Tests for enhanced user feedback functionality

set -euo pipefail

# Test configuration
TEST_NAME="User Feedback Tests"
TEST_VERSION="1.0"
TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test colors
TEST_COLOR_GREEN='\033[0;32m'
TEST_COLOR_RED='\033[0;31m'
TEST_COLOR_YELLOW='\033[1;33m'
TEST_COLOR_BLUE='\033[0;34m'
TEST_COLOR_RESET='\033[0m'

# Test functions
test_start() {
    local test_name="$1"
    printf "%s[TEST]%s %s\n" "$TEST_COLOR_BLUE" "$TEST_COLOR_RESET" "$test_name"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

test_pass() {
    local test_name="$1"
    printf "  %s✓ PASS%s: %s\n" "$TEST_COLOR_GREEN" "$TEST_COLOR_RESET" "$test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local test_name="$1"
    local message="$2"
    printf "  %s✗ FAIL%s: %s - %s\n" "$TEST_COLOR_RED" "$TEST_COLOR_RESET" "$test_name" "$message"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_summary() {
    printf "\n%s=== Test Summary ===%s\n" "$TEST_COLOR_BLUE" "$TEST_COLOR_RESET"
    printf "Total Tests: %d\n" "$TESTS_TOTAL"
    printf "%sPassed: %d%s\n" "$TEST_COLOR_GREEN" "$TESTS_PASSED" "$TEST_COLOR_RESET"
    printf "%sFailed: %d%s\n" "$TEST_COLOR_RED" "$TESTS_FAILED" "$TEST_COLOR_RESET"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        printf "%sAll tests passed!%s\n" "$TEST_COLOR_GREEN" "$TEST_COLOR_RESET"
        return 0
    else
        printf "%sSome tests failed.%s\n" "$TEST_COLOR_RED" "$TEST_COLOR_RESET"
        return 1
    fi
}

# Load test dependencies
load_test_dependencies() {
    # Source the CLI utilities module
    if [[ -f "lib/utils/cli.sh" ]]; then
        source "lib/utils/cli.sh"
    else
        echo "Error: CLI utilities module not found"
        exit 1
    fi
    
    # Mock logging functions if not available
    if [[ -z "${LIB_LOGGING_LOADED:-}" ]]; then
        log_info() { :; }
        log_error() { :; }
        log_warn() { :; }
        export -f log_info log_error log_warn
        export LIB_LOGGING_LOADED=true
    fi
}

# Test helper functions
capture_output() {
    local command="$1"
    local output
    output=$(eval "$command" 2>&1)
    echo "$output"
}

test_color_support() {
    test_start "Color Support Detection"
    
    # Test terminal detection
    cli_detect_terminal
    
    # Verify color support detection works
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" || "$CLI_TERMINAL_SUPPORTS_COLOR" == "false" ]]; then
        test_pass "Color support detection"
    else
        test_fail "Color support detection" "Invalid color support value"
    fi
    
    # Test terminal dimensions
    if [[ "$CLI_TERMINAL_WIDTH" -gt 0 && "$CLI_TERMINAL_HEIGHT" -gt 0 ]]; then
        test_pass "Terminal dimensions detection"
    else
        test_fail "Terminal dimensions detection" "Invalid terminal dimensions"
    fi
}

test_success_indicators() {
    test_start "Success Indicators"
    
    # Test success message
    local output
    output=$(capture_output 'cli_success "Operation completed successfully"')
    
    if [[ "$output" == *"Success"* ]]; then
        test_pass "Success message display"
    else
        test_fail "Success message display" "Success message not found in output"
    fi
    
    if [[ "$output" == *"✓"* ]]; then
        test_pass "Success icon display"
    else
        test_fail "Success icon display" "Success icon not found in output"
    fi
    
    # Test success message with details
    output=$(capture_output 'cli_success "Database backup completed" "2.5GB"')
    
    if [[ "$output" == *"2.5GB"* ]]; then
        test_pass "Success message with details"
    else
        test_fail "Success message with details" "Details not found in output"
    fi
}

test_failure_indicators() {
    test_start "Failure Indicators"
    
    # Test failure message
    local output
    output=$(capture_output 'cli_failure "Operation failed"')
    
    if [[ "$output" == *"Error"* ]]; then
        test_pass "Failure message display"
    else
        test_fail "Failure message display" "Error message not found in output"
    fi
    
    if [[ "$output" == *"✗"* ]]; then
        test_pass "Failure icon display"
    else
        test_fail "Failure icon display" "Failure icon not found in output"
    fi
    
    # Test failure message with recovery
    output=$(capture_output 'cli_failure "Connection failed" "NETWORK_ERROR" "Check your internet connection"')
    
    if [[ "$output" == *"Recovery"* ]]; then
        test_pass "Failure message with recovery"
    else
        test_fail "Failure message with recovery" "Recovery message not found in output"
    fi
}

test_warning_indicators() {
    test_start "Warning Indicators"
    
    # Test warning message
    local output
    output=$(capture_output 'cli_warning "Resource usage is high"')
    
    if [[ "$output" == *"Warning"* ]]; then
        test_pass "Warning message display"
    else
        test_fail "Warning message display" "Warning message not found in output"
    fi
    
    if [[ "$output" == *"⚠"* ]]; then
        test_pass "Warning icon display"
    else
        test_fail "Warning icon display" "Warning icon not found in output"
    fi
}

test_info_indicators() {
    test_start "Info Indicators"
    
    # Test info message
    local output
    output=$(capture_output 'cli_info "Processing configuration"')
    
    if [[ "$output" == *"Info"* ]]; then
        test_pass "Info message display"
    else
        test_fail "Info message display" "Info message not found in output"
    fi
    
    if [[ "$output" == *"ℹ"* ]]; then
        test_pass "Info icon display"
    else
        test_fail "Info icon display" "Info icon not found in output"
    fi
}

test_status_updates() {
    test_start "Status Updates"
    
    # Test step status
    local output
    output=$(capture_output 'cli_step "1" "5" "Initializing deployment" "running"')
    
    if [[ "$output" == *"[1/5]"* ]]; then
        test_pass "Step numbering"
    else
        test_fail "Step numbering" "Step number not found in output"
    fi
    
    if [[ "$output" == *"running"* ]]; then
        test_pass "Step status display"
    else
        test_fail "Step status display" "Step status not found in output"
    fi
    
    # Test operation status
    output=$(capture_output 'cli_status "Database Backup" "completed"')
    
    if [[ "$output" == *"Database Backup"* ]]; then
        test_pass "Operation name display"
    else
        test_fail "Operation name display" "Operation name not found in output"
    fi
    
    if [[ "$output" == *"✓"* ]]; then
        test_pass "Operation success indicator"
    else
        test_fail "Operation success indicator" "Success indicator not found in output"
    fi
}

test_headers_and_formatting() {
    test_start "Headers and Formatting"
    
    # Test header
    local output
    output=$(capture_output 'cli_header "Deployment Process" "Starting infrastructure deployment"')
    
    if [[ "$output" == *"Deployment Process"* ]]; then
        test_pass "Header title display"
    else
        test_fail "Header title display" "Header title not found in output"
    fi
    
    if [[ "$output" == *"Starting infrastructure deployment"* ]]; then
        test_pass "Header subtitle display"
    else
        test_fail "Header subtitle display" "Header subtitle not found in output"
    fi
    
    # Test subheader
    output=$(capture_output 'cli_subheader "Configuration Validation"')
    
    if [[ "$output" == *"Configuration Validation"* ]]; then
        test_pass "Subheader display"
    else
        test_fail "Subheader display" "Subheader not found in output"
    fi
    
    # Test separator
    output=$(capture_output 'cli_separator')
    
    if [[ "$output" == *"-"* ]]; then
        test_pass "Separator display"
    else
        test_fail "Separator display" "Separator not found in output"
    fi
}

test_user_friendly_messages() {
    test_start "User-Friendly Messages"
    
    # Test operation message
    local output
    output=$(capture_output 'cli_operation "VPC Creation" "Creating virtual private cloud" "starting"')
    
    if [[ "$output" == *"VPC Creation"* ]]; then
        test_pass "Operation name display"
    else
        test_fail "Operation name display" "Operation name not found in output"
    fi
    
    if [[ "$output" == *"starting"* ]]; then
        test_pass "Operation status display"
    else
        test_fail "Operation status display" "Operation status not found in output"
    fi
    
    # Test tip message
    output=$(capture_output 'cli_tip "Use --dry-run to preview changes"')
    
    if [[ "$output" == *"Tip"* ]]; then
        test_pass "Tip message display"
    else
        test_fail "Tip message display" "Tip message not found in output"
    fi
    
    # Test note message
    output=$(capture_output 'cli_note "This operation may take several minutes"')
    
    if [[ "$output" == *"Note"* ]]; then
        test_pass "Note message display"
    else
        test_fail "Note message display" "Note message not found in output"
    fi
}

test_error_message_helpers() {
    test_start "Error Message Helpers"
    
    # Test error with recovery
    local output
    output=$(capture_output 'cli_error_with_recovery "AWS credentials not found" "CREDENTIALS_ERROR" "1. Run aws configure\n2. Check environment variables" "Contact your administrator if issues persist"')
    
    if [[ "$output" == *"Error"* ]]; then
        test_pass "Error message display"
    else
        test_fail "Error message display" "Error message not found in output"
    fi
    
    if [[ "$output" == *"Recovery Steps"* ]]; then
        test_pass "Recovery steps display"
    else
        test_fail "Recovery steps display" "Recovery steps not found in output"
    fi
    
    # Test common error patterns
    output=$(capture_output 'cli_common_error "aws_credentials"')
    
    if [[ "$output" == *"AWS credentials not found"* ]]; then
        test_pass "Common AWS credentials error"
    else
        test_fail "Common AWS credentials error" "AWS credentials error message not found"
    fi
    
    output=$(capture_output 'cli_common_error "network_timeout"')
    
    if [[ "$output" == *"Network operation timed out"* ]]; then
        test_pass "Common network timeout error"
    else
        test_fail "Common network timeout error" "Network timeout error message not found"
    fi
}

test_prompt_and_interaction() {
    test_start "Prompt and Interaction"
    
    # Test prompt
    local output
    output=$(capture_output 'cli_prompt "Enter deployment region" "us-east-1" "y/n"')
    
    if [[ "$output" == *"Enter deployment region"* ]]; then
        test_pass "Prompt question display"
    else
        test_fail "Prompt question display" "Prompt question not found in output"
    fi
    
    if [[ "$output" == *"us-east-1"* ]]; then
        test_pass "Prompt default value display"
    else
        test_fail "Prompt default value display" "Prompt default value not found in output"
    fi
    
    # Test confirmation prompt
    output=$(capture_output 'cli_confirm "Continue with deployment?" "y"')
    
    if [[ "$output" == *"Continue with deployment?"* ]]; then
        test_pass "Confirmation prompt display"
    else
        test_fail "Confirmation prompt display" "Confirmation prompt not found in output"
    fi
    
    if [[ "$output" == *"Y/n"* ]]; then
        test_pass "Confirmation options display"
    else
        test_fail "Confirmation options display" "Confirmation options not found in output"
    fi
}

test_progress_and_loading() {
    test_start "Progress and Loading"
    
    # Test progress bar
    local output
    output=$(capture_output 'cli_progress "5" "10" "Processing files"')
    
    if [[ "$output" == *"50%"* ]]; then
        test_pass "Progress percentage calculation"
    else
        test_fail "Progress percentage calculation" "Progress percentage not found in output"
    fi
    
    if [[ "$output" == *"Processing files"* ]]; then
        test_pass "Progress description display"
    else
        test_fail "Progress description display" "Progress description not found in output"
    fi
}

test_consistent_formatting() {
    test_start "Consistent Formatting"
    
    # Test that all messages follow consistent format
    local success_output
    local failure_output
    local warning_output
    local info_output
    
    success_output=$(capture_output 'cli_success "Test message"')
    failure_output=$(capture_output 'cli_failure "Test message"')
    warning_output=$(capture_output 'cli_warning "Test message"')
    info_output=$(capture_output 'cli_info "Test message"')
    
    # Check that all messages contain the message text
    if [[ "$success_output" == *"Test message"* && "$failure_output" == *"Test message"* && "$warning_output" == *"Test message"* && "$info_output" == *"Test message"* ]]; then
        test_pass "Message content consistency"
    else
        test_fail "Message content consistency" "Message content not consistent across types"
    fi
    
    # Check that all messages have appropriate icons
    if [[ "$success_output" == *"✓"* && "$failure_output" == *"✗"* && "$warning_output" == *"⚠"* && "$info_output" == *"ℹ"* ]]; then
        test_pass "Icon consistency"
    else
        test_fail "Icon consistency" "Icons not consistent across message types"
    fi
}

test_user_friendly_language() {
    test_start "User-Friendly Language"
    
    # Test that error messages are helpful
    local output
    output=$(capture_output 'cli_common_error "permission_denied"')
    
    if [[ "$output" == *"Check if you have the required permissions"* ]]; then
        test_pass "Helpful error message content"
    else
        test_fail "Helpful error message content" "Helpful error message not found"
    fi
    
    # Test that recovery steps are actionable
    if [[ "$output" == *"Contact your system administrator"* ]]; then
        test_pass "Actionable recovery steps"
    else
        test_fail "Actionable recovery steps" "Actionable recovery steps not found"
    fi
}

test_edge_cases() {
    test_start "Edge Cases and Error Handling"
    
    # Test rapid message updates
    local output
    for i in {1..10}; do
        output=$(capture_output "cli_success 'Rapid update $i'")
        if [[ "$output" == *"Success"* ]]; then
            test_pass "Rapid message update $i"
        else
            test_fail "Rapid message update $i" "Message not displayed correctly"
        fi
    done
    
    # Test invalid progress parameters
    output=$(capture_output 'cli_progress "invalid" "10" "Test"')
    if [[ "$output" == *"Error: Invalid progress parameters"* ]]; then
        test_pass "Invalid progress parameter handling"
    else
        test_fail "Invalid progress parameter handling" "Should handle invalid parameters"
    fi
    
    # Test division by zero in progress
    output=$(capture_output 'cli_progress "5" "0" "Test"')
    if [[ "$output" == *"Error: Total cannot be zero"* ]]; then
        test_pass "Division by zero handling"
    else
        test_fail "Division by zero handling" "Should handle division by zero"
    fi
    
    # Test out of range progress values
    output=$(capture_output 'cli_progress "15" "10" "Test"')
    if [[ "$output" == *"Error: Current value (15) must be between 0 and 10"* ]]; then
        test_pass "Out of range progress handling"
    else
        test_fail "Out of range progress handling" "Should handle out of range values"
    fi
}

test_terminal_compatibility() {
    test_start "Terminal Compatibility Edge Cases"
    
    # Test with different terminal types
    local original_term="$TERM"
    
    # Test xterm-256color
    export TERM="xterm-256color"
    cli_detect_terminal
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        test_pass "xterm-256color color support"
    else
        test_fail "xterm-256color color support" "Should support color"
    fi
    
    # Test dumb terminal
    export TERM="dumb"
    cli_detect_terminal
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "false" ]]; then
        test_pass "dumb terminal fallback"
    else
        test_fail "dumb terminal fallback" "Should not support color"
    fi
    
    # Test unknown terminal
    export TERM="unknown-terminal"
    cli_detect_terminal
    if [[ "$CLI_TERMINAL_WIDTH" -gt 0 && "$CLI_TERMINAL_HEIGHT" -gt 0 ]]; then
        test_pass "Unknown terminal dimension fallback"
    else
        test_fail "Unknown terminal dimension fallback" "Should have fallback dimensions"
    fi
    
    # Restore original terminal
    export TERM="$original_term"
    cli_detect_terminal
}

# Main test execution
main() {
    printf "%s=== %s ===%s\n" "$TEST_COLOR_BLUE" "$TEST_NAME" "$TEST_COLOR_RESET"
    printf "Version: %s\n" "$TEST_VERSION"
    printf "Timestamp: %s\n\n" "$TEST_TIMESTAMP"
    
    # Load dependencies
    load_test_dependencies
    
    # Run all tests
    test_color_support
    test_success_indicators
    test_failure_indicators
    test_warning_indicators
    test_info_indicators
    test_status_updates
    test_headers_and_formatting
    test_user_friendly_messages
    test_error_message_helpers
    test_prompt_and_interaction
    test_progress_and_loading
    test_consistent_formatting
    test_user_friendly_language
    test_edge_cases
    test_terminal_compatibility
    
    # Show test summary
    test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi