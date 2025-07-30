#!/usr/bin/env bash

# Test Interactive CLI Features
# Tests the comprehensive interactive CLI system including help, discovery, validation, and prompts

set -euo pipefail

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

# Test configuration
TEST_NAME="Interactive CLI Features"
TEST_VERSION="1.0"
TEST_DESCRIPTION="Comprehensive testing of interactive CLI features"

# Test results tracking
TEST_RESULTS=()
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# Test data
TEST_CONFIG_FILE=""
TEST_TEMP_DIR=""

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Load test framework
if [[ -f "tests/lib/shell-test-framework.sh" ]]; then
    source "tests/lib/shell-test-framework.sh"
else
    # Fallback test utilities
    test_pass() {
        echo "✅ PASS: $1"
        TEST_PASSED=$((TEST_PASSED + 1))
        TEST_RESULTS+=("PASS: $1")
    }
    
    test_fail() {
        echo "❌ FAIL: $1"
        TEST_FAILED=$((TEST_FAILED + 1))
        TEST_RESULTS+=("FAIL: $1")
    }
    
    test_skip() {
        echo "⏭️  SKIP: $1"
        TEST_SKIPPED=$((TEST_SKIPPED + 1))
        TEST_RESULTS+=("SKIP: $1")
    }
    
    test_assert() {
        if [[ $1 -eq 0 ]]; then
            test_pass "$2"
        else
            test_fail "$2"
        fi
    }
    
    test_assert_contains() {
        if echo "$1" | grep -q "$2"; then
            test_pass "$3"
        else
            test_fail "$3 (expected: '$2', got: '$1')"
        fi
    }
fi

# Load CLI module
if [[ -f "lib/utils/cli.sh" ]]; then
    source "lib/utils/cli.sh"
else
    echo "❌ CLI module not found: lib/utils/cli.sh"
    exit 1
fi

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    echo "🔧 Setting up test environment..."
    
    # Create temporary directory
    TEST_TEMP_DIR=$(mktemp -d)
    TEST_CONFIG_FILE="$TEST_TEMP_DIR/test-config.yml"
    
    # Create test configuration file
    cat > "$TEST_CONFIG_FILE" << 'EOF'
# Test configuration file
environment: test
version: 1.0.0
settings:
  debug: true
  verbose: false
  timeout: 30
EOF
    
    # Register test commands
    cli_register_command "test-help" "Test help command" "test-help [section]" "Testing"
    cli_register_command "test-discover" "Test command discovery" "test-discover <query>" "Testing"
    cli_register_command "test-validate" "Test configuration validation" "test-validate <file>" "Testing"
    cli_register_command "test-confirm" "Test confirmation prompts" "test-confirm <operation>" "Testing"
    cli_register_command "deploy" "Deploy application" "deploy --environment <env>" "Deployment"
    cli_register_command "config" "Manage configuration" "config --validate" "Configuration"
    cli_register_command "status" "Show status" "status --verbose" "Monitoring"
    
    echo "✅ Test environment setup complete"
}

cleanup_test_environment() {
    echo "🧹 Cleaning up test environment..."
    
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    
    echo "✅ Test environment cleanup complete"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

test_help_system_registration() {
    echo "🧪 Testing help system registration..."
    
    # Test command registration
    local output
    output=$(cli_register_command "test-cmd" "Test command" "test-cmd --option" "TestSection" 2>&1)
    test_assert $? "Command registration should succeed"
    
    # Verify command was registered
    if [[ -n "${CLI_COMMANDS[test-cmd]:-}" ]]; then
        test_pass "Command should be registered in CLI_COMMANDS"
    else
        test_fail "Command should be registered in CLI_COMMANDS"
    fi
    
    # Verify section was created
    if [[ -n "${CLI_HELP_SECTIONS[TestSection]:-}" ]]; then
        test_pass "Section should be created in CLI_HELP_SECTIONS"
    else
        test_fail "Section should be created in CLI_HELP_SECTIONS"
    fi
}

test_help_menu_structure() {
    echo "🧪 Testing help menu structure..."
    
    # Test help menu output (non-interactive)
    local output
    output=$(cli_help_menu 2>&1 || true)
    
    # Check for expected elements
    test_assert_contains "$output" "Interactive CLI Help System" "Help menu should display title"
    test_assert_contains "$output" "Available Sections" "Help menu should show sections"
    test_assert_contains "$output" "Testing" "Help menu should include Testing section"
    test_assert_contains "$output" "Deployment" "Help menu should include Deployment section"
}

test_help_section_display() {
    echo "🧪 Testing help section display..."
    
    # Test section display
    local output
    output=$(cli_help_section "Testing" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Help: Testing" "Section help should display section name"
    test_assert_contains "$output" "test-help" "Section should show registered commands"
    test_assert_contains "$output" "Test help command" "Section should show command descriptions"
}

test_help_command_display() {
    echo "🧪 Testing help command display..."
    
    # Test command help display
    local output
    output=$(cli_help_command "test-help" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Command Help: test-help" "Command help should display command name"
    test_assert_contains "$output" "Test help command" "Command help should show description"
    test_assert_contains "$output" "test-help [section]" "Command help should show usage example"
}

test_help_command_not_found() {
    echo "🧪 Testing help command not found..."
    
    # Test command not found
    local output
    output=$(cli_help_command "nonexistent-command" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Command not found" "Should show command not found message"
    test_assert_contains "$output" "Did you mean" "Should suggest similar commands"
}

# =============================================================================
# COMMAND DISCOVERY TESTS
# =============================================================================

test_command_discovery_exact_match() {
    echo "🧪 Testing command discovery with exact match..."
    
    # Test exact match
    local output
    output=$(cli_discover_commands "test-help" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Command Discovery Results: test-help" "Should show discovery results"
    test_assert_contains "$output" "test-help" "Should find exact match"
    test_assert_contains "$output" "score: 100" "Exact match should have highest score"
}

test_command_discovery_partial_match() {
    echo "🧪 Testing command discovery with partial match..."
    
    # Test partial match
    local output
    output=$(cli_discover_commands "test" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Command Discovery Results: test" "Should show discovery results"
    test_assert_contains "$output" "test-help" "Should find partial matches"
    test_assert_contains "$output" "test-discover" "Should find partial matches"
}

test_command_discovery_no_results() {
    echo "🧪 Testing command discovery with no results..."
    
    # Test no results
    local output
    output=$(cli_discover_commands "xyz123" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "No commands found matching" "Should show no results message"
}

test_autocomplete_suggestions() {
    echo "🧪 Testing autocomplete suggestions..."
    
    # Test autocomplete
    local output
    output=$(cli_autocomplete "test" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Suggestions for 'test':" "Should show suggestions header"
    test_assert_contains "$output" "test-help" "Should suggest matching commands"
    test_assert_contains "$output" "test-discover" "Should suggest matching commands"
}

# =============================================================================
# INTERACTIVE VALIDATION TESTS
# =============================================================================

test_config_validation_valid_file() {
    echo "🧪 Testing configuration validation with valid file..."
    
    # Test valid configuration
    local output
    output=$(cli_validate_config_interactive "$TEST_CONFIG_FILE" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Interactive Configuration Validation" "Should show validation header"
    test_assert_contains "$output" "Configuration validation passed" "Should pass validation"
}

test_config_validation_invalid_file() {
    echo "🧪 Testing configuration validation with invalid file..."
    
    # Create invalid YAML file
    local invalid_file="$TEST_TEMP_DIR/invalid.yml"
    echo "invalid: yaml: [content" > "$invalid_file"
    
    # Test invalid configuration
    local output
    output=$(cli_validate_config_interactive "$invalid_file" 2>&1 || true)
    
    # Check for expected elements
    test_assert_contains "$output" "Interactive Configuration Validation" "Should show validation header"
    test_assert_contains "$output" "Validation Errors" "Should show validation errors"
}

test_config_validation_nonexistent_file() {
    echo "🧪 Testing configuration validation with nonexistent file..."
    
    # Test nonexistent file
    local output
    output=$(cli_validate_config_interactive "/nonexistent/file.yml" 2>&1 || true)
    
    # Check for expected elements
    test_assert_contains "$output" "Configuration file not found" "Should show file not found error"
}

# =============================================================================
# CONFIRMATION PROMPTS TESTS
# =============================================================================

test_confirmation_prompt_timeout() {
    echo "🧪 Testing confirmation prompt with timeout..."
    
    # Test timeout confirmation (non-interactive)
    local output
    output=$(timeout 1s bash -c 'source lib/utils/cli.sh; cli_confirm_timeout "Test question" 1 "n"' 2>&1 || true)
    
    # Check for expected elements
    test_assert_contains "$output" "Test question" "Should show the question"
    test_assert_contains "$output" "timeout: 1s" "Should show timeout information"
}

test_destructive_confirmation_structure() {
    echo "🧪 Testing destructive confirmation structure..."
    
    # Test destructive confirmation (non-interactive)
    local output
    output=$(echo "cancel" | cli_confirm_destructive "delete" "test-resource" "test details" 2>&1 || true)
    
    # Check for expected elements
    test_assert_contains "$output" "DESTRUCTIVE OPERATION DETECTED" "Should show destructive warning"
    test_assert_contains "$output" "Operation: delete" "Should show operation details"
    test_assert_contains "$output" "Resource: test-resource" "Should show resource details"
    test_assert_contains "$output" "This operation cannot be undone" "Should show warning"
}

# =============================================================================
# CONTEXT-SENSITIVE HELP TESTS
# =============================================================================

test_context_help_deployment() {
    echo "🧪 Testing context help for deployment..."
    
    # Test deployment context help
    local output
    output=$(cli_context_help "deployment" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Deployment Context Help" "Should show deployment context"
    test_assert_contains "$output" "Continue deployment" "Should show deployment options"
    test_assert_contains "$output" "Rollback deployment" "Should show rollback option"
}

test_context_help_configuration() {
    echo "🧪 Testing context help for configuration..."
    
    # Test configuration context help
    local output
    output=$(cli_context_help "configuration" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Configuration Context Help" "Should show configuration context"
    test_assert_contains "$output" "Validate configuration" "Should show validation option"
    test_assert_contains "$output" "Edit configuration" "Should show edit option"
}

test_context_help_error() {
    echo "🧪 Testing context help for error recovery..."
    
    # Test error context help
    local output
    output=$(cli_context_help "error" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Error Recovery Help" "Should show error context"
    test_assert_contains "$output" "Retry operation" "Should show retry option"
    test_assert_contains "$output" "Check logs" "Should show logs option"
}

# =============================================================================
# SMART SUGGESTIONS TESTS
# =============================================================================

test_smart_suggestions_help() {
    echo "🧪 Testing smart suggestions for help..."
    
    # Test help suggestions
    local output
    output=$(cli_smart_suggestions "help" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Suggestions:" "Should show suggestions"
    test_assert_contains "$output" "help menu" "Should suggest help menu"
    test_assert_contains "$output" "help commands" "Should suggest help commands"
}

test_smart_suggestions_deploy() {
    echo "🧪 Testing smart suggestions for deploy..."
    
    # Test deploy suggestions
    local output
    output=$(cli_smart_suggestions "deploy" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Suggestions:" "Should show suggestions"
    test_assert_contains "$output" "deploy start" "Should suggest deploy start"
    test_assert_contains "$output" "deploy status" "Should suggest deploy status"
}

test_smart_suggestions_context() {
    echo "🧪 Testing smart suggestions with context..."
    
    # Test context-specific suggestions
    local output
    output=$(cli_smart_suggestions "status" "deployment" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Suggestions:" "Should show suggestions"
    test_assert_contains "$output" "rollback" "Should suggest rollback in deployment context"
    test_assert_contains "$output" "cancel" "Should suggest cancel in deployment context"
}

# =============================================================================
# COMMAND SYNTAX TESTS
# =============================================================================

test_command_syntax_display() {
    echo "🧪 Testing command syntax display..."
    
    # Test syntax display
    local output
    output=$(cli_show_syntax "test-help" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Command Syntax: test-help" "Should show command syntax"
    test_assert_contains "$output" "Usage:" "Should show usage section"
    test_assert_contains "$output" "test-help" "Should show command name"
    test_assert_contains "$output" "test-help [section]" "Should show usage example"
}

test_command_syntax_not_found() {
    echo "🧪 Testing command syntax for non-existent command..."
    
    # Test non-existent command
    local output
    output=$(cli_show_syntax "nonexistent" 2>&1 || true)
    
    # Check for expected elements
    test_assert_contains "$output" "Command not found" "Should show command not found message"
}

test_command_options_display() {
    echo "🧪 Testing command options display..."
    
    # Test options display
    local output
    output=$(cli_show_command_options "deploy" 2>&1)
    
    # Check for expected elements
    test_assert_contains "$output" "Options:" "Should show options section"
    test_assert_contains "$output" "--environment" "Should show environment option"
    test_assert_contains "$output" "--dry-run" "Should show dry-run option"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_integration_help_flow() {
    echo "🧪 Testing integrated help flow..."
    
    # Test complete help flow
    local output
    output=$(cli_help_menu 2>&1 || true)
    
    # Verify help system is functional
    test_assert_contains "$output" "Interactive CLI Help System" "Help system should be functional"
    test_assert_contains "$output" "Available Sections" "Should show available sections"
}

test_integration_command_discovery_flow() {
    echo "🧪 Testing integrated command discovery flow..."
    
    # Test complete discovery flow
    local output
    output=$(cli_discover_commands "test" 2>&1)
    
    # Verify discovery system is functional
    test_assert_contains "$output" "Command Discovery Results: test" "Discovery should be functional"
    test_assert_contains "$output" "test-help" "Should discover registered commands"
}

test_integration_validation_flow() {
    echo "🧪 Testing integrated validation flow..."
    
    # Test complete validation flow
    local output
    output=$(cli_validate_config_interactive "$TEST_CONFIG_FILE" 2>&1)
    
    # Verify validation system is functional
    test_assert_contains "$output" "Interactive Configuration Validation" "Validation should be functional"
    test_assert_contains "$output" "Configuration validation passed" "Should validate correctly"
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance_help_menu() {
    echo "🧪 Testing help menu performance..."
    
    # Test help menu performance
    local start_time
    start_time=$(date +%s.%N)
    
    cli_help_menu >/dev/null 2>&1 || true
    
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Should complete within reasonable time (5 seconds)
    if (( $(echo "$duration < 5" | bc -l 2>/dev/null || echo 1) )); then
        test_pass "Help menu should complete within 5 seconds (took ${duration}s)"
    else
        test_fail "Help menu should complete within 5 seconds (took ${duration}s)"
    fi
}

test_performance_command_discovery() {
    echo "🧪 Testing command discovery performance..."
    
    # Test discovery performance
    local start_time
    start_time=$(date +%s.%N)
    
    cli_discover_commands "test" >/dev/null 2>&1
    
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Should complete within reasonable time (2 seconds)
    if (( $(echo "$duration < 2" | bc -l 2>/dev/null || echo 1) )); then
        test_pass "Command discovery should complete within 2 seconds (took ${duration}s)"
    else
        test_fail "Command discovery should complete within 2 seconds (took ${duration}s)"
    fi
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_error_handling_invalid_input() {
    echo "🧪 Testing error handling for invalid input..."
    
    # Test invalid input handling
    local output
    output=$(cli_discover_commands "" 2>&1 || true)
    
    # Check for expected error handling
    test_assert_contains "$output" "No search query provided" "Should handle empty input"
}

test_error_handling_missing_files() {
    echo "🧪 Testing error handling for missing files..."
    
    # Test missing file handling
    local output
    output=$(cli_validate_config_interactive "/nonexistent/file.yml" 2>&1 || true)
    
    # Check for expected error handling
    test_assert_contains "$output" "Configuration file not found" "Should handle missing files"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_all_tests() {
    echo "🚀 Starting $TEST_NAME tests..."
    echo "Version: $TEST_VERSION"
    echo "Description: $TEST_DESCRIPTION"
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Help System Tests
    echo "📋 Running Help System Tests..."
    test_help_system_registration
    test_help_menu_structure
    test_help_section_display
    test_help_command_display
    test_help_command_not_found
    
    # Command Discovery Tests
    echo "🔍 Running Command Discovery Tests..."
    test_command_discovery_exact_match
    test_command_discovery_partial_match
    test_command_discovery_no_results
    test_autocomplete_suggestions
    
    # Interactive Validation Tests
    echo "✅ Running Interactive Validation Tests..."
    test_config_validation_valid_file
    test_config_validation_invalid_file
    test_config_validation_nonexistent_file
    
    # Confirmation Prompts Tests
    echo "⚠️  Running Confirmation Prompts Tests..."
    test_confirmation_prompt_timeout
    test_destructive_confirmation_structure
    
    # Context-Sensitive Help Tests
    echo "🎯 Running Context-Sensitive Help Tests..."
    test_context_help_deployment
    test_context_help_configuration
    test_context_help_error
    
    # Smart Suggestions Tests
    echo "💡 Running Smart Suggestions Tests..."
    test_smart_suggestions_help
    test_smart_suggestions_deploy
    test_smart_suggestions_context
    
    # Command Syntax Tests
    echo "📝 Running Command Syntax Tests..."
    test_command_syntax_display
    test_command_syntax_not_found
    test_command_options_display
    
    # Integration Tests
    echo "🔗 Running Integration Tests..."
    test_integration_help_flow
    test_integration_command_discovery_flow
    test_integration_validation_flow
    
    # Performance Tests
    echo "⚡ Running Performance Tests..."
    test_performance_help_menu
    test_performance_command_discovery
    
    # Error Handling Tests
    echo "🚨 Running Error Handling Tests..."
    test_error_handling_invalid_input
    test_error_handling_missing_files
    
    # Cleanup
    cleanup_test_environment
    
    # Test summary
    echo ""
    echo "📊 Test Summary:"
    echo "  Passed: $TEST_PASSED"
    echo "  Failed: $TEST_FAILED"
    echo "  Skipped: $TEST_SKIPPED"
    echo "  Total: $((TEST_PASSED + TEST_FAILED + TEST_SKIPPED))"
    
    # Detailed results
    echo ""
    echo "📋 Detailed Results:"
    for result in "${TEST_RESULTS[@]}"; do
        echo "  $result"
    done
    
    # Exit with appropriate code
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo ""
        echo "✅ All tests passed!"
        exit 0
    else
        echo ""
        echo "❌ Some tests failed!"
        exit 1
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if running as main script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi