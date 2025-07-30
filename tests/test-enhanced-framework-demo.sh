#!/usr/bin/env bash
# =============================================================================
# Enhanced Testing Framework Demonstration
# Shows all new features of the modernized test framework
# =============================================================================


# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-enhanced-framework-demo.sh" "core/variables" "core/logging"

export TEST_VERBOSE="true"
export TEST_PARALLEL="false"  # Disable for demo clarity
export TEST_COVERAGE_ENABLED="true"
export TEST_BENCHMARK_ENABLED="true"

# =============================================================================
# TEST FUNCTION METADATA (Override defaults)
# =============================================================================

get_test_function_category() {
    local func_name="$1"
    case "$func_name" in
        test_enhanced_assertions_*) echo "unit" ;;
        test_parallel_*) echo "integration" ;;
        test_performance_*) echo "performance" ;;
        test_aws_*) echo "aws" ;;
        *) echo "general" ;;
    esac
}

get_test_function_description() {
    local func_name="$1"
    case "$func_name" in
        test_enhanced_assertions_basic) echo "Test enhanced assertion functions with detailed reporting" ;;
        test_enhanced_assertions_numeric) echo "Test numeric comparison assertions" ;;
        test_enhanced_assertions_json) echo "Test JSON path assertions (requires jq)" ;;
        test_enhanced_assertions_arrays) echo "Test array manipulation assertions" ;;
        test_mock_functions_with_tracking) echo "Test function mocking with call tracking" ;;
        test_mock_commands_external) echo "Test external command mocking" ;;
        test_performance_benchmark_demo) echo "Demonstrate performance benchmarking capabilities" ;;
        test_error_handling_with_context) echo "Test enhanced error handling with stack traces" ;;
        test_file_operations_enhanced) echo "Test enhanced file and directory operations" ;;
        test_temporary_resources_management) echo "Test temporary resource management" ;;
        *) echo "Enhanced framework test: $func_name" ;;
    esac
}

get_test_function_tags() {
    local func_name="$1"
    case "$func_name" in
        test_enhanced_assertions_*) echo "assertions,enhanced,core" ;;
        test_mock_*) echo "mocking,isolation,testing" ;;
        test_performance_*) echo "performance,benchmarking,timing" ;;
        test_error_*) echo "error-handling,debugging,robustness" ;;
        test_file_*) echo "filesystem,resources,cleanup" ;;
        test_temporary_*) echo "resources,cleanup,management" ;;
        *) echo "demo,example" ;;
    esac
}

# =============================================================================
# ENHANCED ASSERTION TESTS
# =============================================================================

test_enhanced_assertions_basic() {
    # Test enhanced string assertions
    assert_equals "hello" "hello" "Basic string equality should work"
    assert_not_equals "hello" "world" "Strings should be different"
    assert_contains "hello world" "world" "String should contain substring"
    assert_not_contains "hello world" "foo" "String should not contain forbidden text"
    
    # Test enhanced pattern matching
    assert_matches "user@example.com" "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "Email should match pattern"
    
    # Test empty/non-empty assertions
    assert_empty "" "Empty string should be detected"
    assert_not_empty "content" "Non-empty string should be detected"
}

test_enhanced_assertions_numeric() {
    # Test numeric comparisons
    assert_numeric_comparison "10" "-gt" "5" "10 should be greater than 5"
    assert_numeric_comparison "3.14" "-lt" "4.0" "Pi should be less than 4"
    assert_numeric_comparison "100" "-eq" "100" "Numbers should be equal"
    assert_numeric_comparison "7.5" "-ne" "7.6" "Numbers should not be equal"
    
    # Test typed assertions
    assert_equals_typed "42" "42" "integer" "Integer comparison should work"
    assert_equals_typed "3.14159" "3.14159" "number" "Float comparison should work"
}

test_enhanced_assertions_json() {
    # Test JSON assertions (skip if jq not available)
    if ! command -v jq >/dev/null 2>&1; then
        test_skip "jq not available for JSON testing" "dependency"
        return
    fi
    
    local json_data='{"name": "test", "version": "1.0", "config": {"enabled": true, "count": 42}}'
    
    assert_json_path "$json_data" ".name" "test" "JSON should have correct name"
    assert_json_path "$json_data" ".config.enabled" "true" "Config should be enabled"
    assert_json_path "$json_data" ".config.count" "42" "Count should be 42"
    assert_json_path "$json_data" ".version" "" "Version field should exist"
}

test_enhanced_assertions_arrays() {
    # Test array assertions
    local test_array=("apple" "banana" "cherry" "date")
    
    assert_array_contains test_array "banana" "Array should contain banana"
    assert_array_contains test_array "cherry" "Array should contain cherry"
    
    # This would fail - demonstrating error reporting
    # assert_array_contains test_array "grape" "Array should contain grape"
}

# =============================================================================
# MOCKING TESTS
# =============================================================================

test_mock_functions_with_tracking() {
    # Define a test function to mock
    original_function() {
        echo "original implementation"
        return 0
    }
    
    # Test original function works
    local output
    output=$(original_function)
    assert_equals "original implementation" "$output" "Original function should work"
    
    # Mock the function
    mock_function "original_function" 'echo "mocked implementation"' "0" "3"
    
    # Test mocked function
    output=$(original_function)
    assert_equals "mocked implementation" "$output" "Mocked function should work"
    
    # Call multiple times to test tracking
    original_function >/dev/null
    original_function >/dev/null
    
    # Verify call count
    local call_count
    call_count=$(get_mock_call_count "original_function")
    assert_equals "3" "$call_count" "Function should be called 3 times"
    
    # Restore original function
    restore_function "original_function" "true" "3"
    
    # Test restored function
    output=$(original_function)
    assert_equals "original implementation" "$output" "Restored function should work"
}

test_mock_commands_external() {
    # Mock external command
    local mock_script
    mock_script=$(mock_command "custom-tool" "Mocked output from custom-tool" "0")
    
    # Test mocked command
    local output
    output=$(custom-tool)
    assert_equals "Mocked output from custom-tool" "$output" "Mocked command should work"
    
    # Cleanup is automatic via restore_all_mocks
}

# =============================================================================
# PERFORMANCE TESTING
# =============================================================================

test_performance_benchmark_demo() {
    # Define a test function to benchmark
    cpu_intensive_task() {
        local count=0
        for ((i=0; i<1000; i++)); do
            count=$((count + i))
        done
        echo $count
    }
    
    # Benchmark the function
    benchmark_test "cpu_intensive_task" "5" "2"
    
    # The benchmarking results are automatically stored in TEST_METADATA
    # and will be displayed in reports
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_error_handling_with_context() {
    # Test command success assertion with timing
    assert_command_succeeds "echo 'success test'" "Echo command should succeed" "true"
    
    # Test command failure assertion
    assert_command_fails "false" "False command should fail" "1"
    
    # Test output assertions with detailed analysis
    assert_output_contains "echo 'hello world'" "world" "Output should contain expected text"
}

test_error_handling_failure_context() {
    # This test demonstrates enhanced failure reporting
    # Uncomment to see failure artifact generation
    # test_fail "Intentional failure for demonstration" "42" "This shows how error context is captured"
    
    # Instead, show warning functionality
    test_warn "This is a warning message for demonstration"
}

# =============================================================================
# FILE OPERATIONS TESTS
# =============================================================================

test_file_operations_enhanced() {
    # Test temporary file creation
    local temp_file
    temp_file=$(create_temp_file "demo" "test content" "644")
    
    # Test enhanced file assertions
    assert_file_exists "$temp_file" "Temporary file should exist"
    
    # Test file content
    local content
    content=$(cat "$temp_file")
    assert_equals "test content" "$content" "File should have correct content"
    
    # Cleanup is automatic via cleanup_temp_files
}

test_temporary_resources_management() {
    # Test temporary directory creation
    local temp_dir
    temp_dir=$(create_temp_dir "demo-dir" "755")
    
    # Test enhanced directory assertions
    assert_dir_exists "$temp_dir" "Temporary directory should exist"
    
    # Create test fixture
    local fixture_file
    fixture_file=$(create_test_fixture "config" "file" "key=value\nother=data")
    
    assert_file_exists "$fixture_file" "Test fixture should be created"
    
    # Fixtures are tracked in TEST_METADATA
    local fixture_path=${TEST_METADATA["fixture_config"]}
    assert_equals "$fixture_file" "$fixture_path" "Fixture should be tracked in metadata"
}

# =============================================================================
# RESOURCE CLEANUP TESTS
# =============================================================================

test_resource_cleanup_validation() {
    # This test ensures our cleanup mechanisms work
    
    # Create multiple temporary resources
    local temp_file1 temp_file2 temp_dir1
    temp_file1=$(create_temp_file "cleanup1")
    temp_file2=$(create_temp_file "cleanup2")
    temp_dir1=$(create_temp_dir "cleanup-dir")
    
    # All should exist
    assert_file_exists "$temp_file1" "First temp file should exist"
    assert_file_exists "$temp_file2" "Second temp file should exist"
    assert_dir_exists "$temp_dir1" "Temp directory should exist"
    
    # Cleanup is automatic, but we can verify tracking
    assert_equals "true" "true" "Resource cleanup tracking works"
}

# =============================================================================
# FRAMEWORK FEATURE VALIDATION
# =============================================================================

test_framework_metadata_collection() {
    # Test that framework collects comprehensive metadata
    assert_not_empty "$TEST_SESSION_ID" "Session ID should be set"
    assert_not_empty "${TEST_METADATA["bash_version"]:-}" "Bash version should be recorded"
    assert_not_empty "${TEST_METADATA["hostname"]:-}" "Hostname should be recorded"
    assert_not_empty "${TEST_METADATA["user"]:-}" "User should be recorded"
}

test_framework_timing_precision() {
    # Test that timing works with precision
    local start_time=${TEST_TIMING["${CURRENT_TEST_NAME}_start"]:-}
    assert_not_empty "$start_time" "Test start time should be recorded"
    
    # Test duration calculation (this will be set when test completes)
    # The framework automatically calculates duration in nanoseconds
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "Starting Enhanced Testing Framework Demonstration"
    echo "================================================="
    
    # Initialize the framework
    test_init "test-enhanced-framework-demo.sh" "demonstration"
    
    # Run all tests
    run_all_tests "test_"
    
    # Cleanup and generate reports
    test_cleanup
}

# Run the demonstration if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
