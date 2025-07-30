#!/usr/bin/env bash
# =============================================================================
# Enhanced Test Framework Library
# Modern test framework using associative arrays
# Compatible with bash 3.x+
# =============================================================================


# Load associative array utilities
source "${LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}/associative-arrays.sh"

# Prevent multiple sourcing
if [[ "${ENHANCED_TEST_FRAMEWORK_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly ENHANCED_TEST_FRAMEWORK_LIB_LOADED=true

# =============================================================================
# LIBRARY METADATA
# =============================================================================

readonly ENHANCED_TEST_FRAMEWORK_VERSION="1.0.0"

# =============================================================================
# GLOBAL ASSOCIATIVE ARRAYS FOR TEST MANAGEMENT
# =============================================================================

# Test results and metrics
declare -A TEST_RESULTS            # Test execution results
declare -A TEST_METRICS            # Performance and timing metrics
declare -A TEST_CATEGORIES         # Test category definitions and metadata
declare -A TEST_DEPENDENCIES       # Test dependency mapping
declare -A TEST_CONFIGURATION      # Test framework configuration
declare -A TEST_FIXTURES           # Shared test fixtures and setup data
declare -A TEST_ASSERTIONS         # Custom assertion results
declare -A TEST_COVERAGE           # Code coverage tracking

# Test execution state
declare -A TEST_EXECUTION_STATE
declare -A TEST_SUITE_METADATA

# =============================================================================
# TEST FRAMEWORK INITIALIZATION
# =============================================================================

# Initialize test framework
init_test_framework() {
    local framework_config="${1:-{}}"  # JSON configuration
    
    log "Initializing Enhanced Test Framework (v${ENHANCED_TEST_FRAMEWORK_VERSION})"
    
    # Initialize test categories with associative arrays
    aa_set TEST_CATEGORIES "unit:description" "Unit tests for individual functions"
    aa_set TEST_CATEGORIES "unit:timeout" "30"
    aa_set TEST_CATEGORIES "unit:parallel" "true"
    aa_set TEST_CATEGORIES "unit:dependencies" ""
    
    aa_set TEST_CATEGORIES "integration:description" "Integration tests for component interaction"
    aa_set TEST_CATEGORIES "integration:timeout" "120"
    aa_set TEST_CATEGORIES "integration:parallel" "false"
    aa_set TEST_CATEGORIES "integration:dependencies" "unit"
    
    aa_set TEST_CATEGORIES "security:description" "Security vulnerability scans and validation"
    aa_set TEST_CATEGORIES "security:timeout" "300"
    aa_set TEST_CATEGORIES "security:parallel" "true"
    aa_set TEST_CATEGORIES "security:dependencies" ""
    
    aa_set TEST_CATEGORIES "performance:description" "Performance and load tests"
    aa_set TEST_CATEGORIES "performance:timeout" "600"
    aa_set TEST_CATEGORIES "performance:parallel" "false"
    aa_set TEST_CATEGORIES "performance:dependencies" "unit,integration"
    
    aa_set TEST_CATEGORIES "deployment:description" "Deployment validation tests"
    aa_set TEST_CATEGORIES "deployment:timeout" "300"
    aa_set TEST_CATEGORIES "deployment:parallel" "false"
    aa_set TEST_CATEGORIES "deployment:dependencies" "unit,security"
    
    aa_set TEST_CATEGORIES "smoke:description" "Basic smoke tests for quick validation"
    aa_set TEST_CATEGORIES "smoke:timeout" "60"
    aa_set TEST_CATEGORIES "smoke:parallel" "true"
    aa_set TEST_CATEGORIES "smoke:dependencies" ""
    
    aa_set TEST_CATEGORIES "config:description" "Configuration management tests"
    aa_set TEST_CATEGORIES "config:timeout" "60"
    aa_set TEST_CATEGORIES "config:parallel" "true"
    aa_set TEST_CATEGORIES "config:dependencies" ""
    
    # Initialize framework configuration
    aa_set TEST_CONFIGURATION "reports_dir" "${TEST_REPORTS_DIR:-./test-reports}"
    aa_set TEST_CONFIGURATION "parallel_jobs" "${PARALLEL_JOBS:-4}"
    aa_set TEST_CONFIGURATION "default_timeout" "60"
    aa_set TEST_CONFIGURATION "coverage_enabled" "${TEST_COVERAGE:-false}"
    aa_set TEST_CONFIGURATION "verbose_mode" "${TEST_VERBOSE:-false}"
    aa_set TEST_CONFIGURATION "fail_fast" "${TEST_FAIL_FAST:-false}"
    
    # Initialize execution state
    aa_set TEST_EXECUTION_STATE "session_id" "$(date +%s)-$$"
    aa_set TEST_EXECUTION_STATE "start_time" "$(date +%s)"
    aa_set TEST_EXECUTION_STATE "total_tests" "0"
    aa_set TEST_EXECUTION_STATE "passed_tests" "0"
    aa_set TEST_EXECUTION_STATE "failed_tests" "0"
    aa_set TEST_EXECUTION_STATE "skipped_tests" "0"
    aa_set TEST_EXECUTION_STATE "current_category" ""
    aa_set TEST_EXECUTION_STATE "current_test" ""
    
    # Parse custom configuration if provided
    if [[ "$framework_config" != "{}" ]] && command -v jq >/dev/null 2>&1; then
        local config_keys
        config_keys=$(echo "$framework_config" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        for key in $config_keys; do
            local value
            value=$(echo "$framework_config" | jq -r ".$key" 2>/dev/null || echo "")
            if [[ -n "$value" && "$value" != "null" ]]; then
                aa_set TEST_CONFIGURATION "$key" "$value"
            fi
        done
    fi
    
    # Create reports directory
    local reports_dir=$(aa_get TEST_CONFIGURATION "reports_dir")
    mkdir -p "$reports_dir"
    
    success "Test framework initialized"
}

# =============================================================================
# TEST REGISTRATION AND DISCOVERY
# =============================================================================

# Register a test function
# Usage: register_test category test_name test_function [metadata_json]
register_test() {
    local category="$1"
    local test_name="$2" 
    local test_function="$3"
    local metadata_json="${4:-{}}"
    
    if [[ -z "$category" ]] || [[ -z "$test_name" ]] || [[ -z "$test_function" ]]; then
        error "register_test requires category, test_name, and test_function"
        return 1
    fi
    
    # Validate category exists
    if ! aa_has_key TEST_CATEGORIES "${category}:description"; then
        error "Unknown test category: $category"
        return 1
    fi
    
    # Validate function exists
    if ! declare -f "$test_function" >/dev/null 2>&1; then
        error "Test function not found: $test_function"
        return 1
    fi
    
    local test_key="${category}:${test_name}"
    local timestamp=$(date +%s)
    
    # Register test metadata
    aa_set TEST_RESULTS "${test_key}:function" "$test_function"
    aa_set TEST_RESULTS "${test_key}:category" "$category"
    aa_set TEST_RESULTS "${test_key}:status" "registered"
    aa_set TEST_RESULTS "${test_key}:registered_at" "$timestamp"
    
    # Parse and store custom metadata
    if [[ "$metadata_json" != "{}" ]] && command -v jq >/dev/null 2>&1; then
        local metadata_keys
        metadata_keys=$(echo "$metadata_json" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        for key in $metadata_keys; do
            local value
            value=$(echo "$metadata_json" | jq -r ".$key" 2>/dev/null || echo "")
            if [[ -n "$value" && "$value" != "null" ]]; then
                aa_set TEST_RESULTS "${test_key}:meta:${key}" "$value"
            fi
        done
    fi
    
    # Update test counter
    local total_tests=$(aa_get TEST_EXECUTION_STATE "total_tests")
    aa_set TEST_EXECUTION_STATE "total_tests" "$((total_tests + 1))"
    
    if declare -f log >/dev/null 2>&1; then
        log "Registered test: $category/$test_name -> $test_function"
    fi
}

# Auto-discover tests in a directory
discover_tests() {
    local test_dir="$1"
    local pattern="${2:-test_*.sh}"
    
    if [[ ! -d "$test_dir" ]]; then
        error "Test directory not found: $test_dir"
        return 1
    fi
    
    log "Discovering tests in: $test_dir (pattern: $pattern)"
    
    local discovered_count=0
    
    # Find test files matching pattern
    while IFS= read -r -d '' test_file; do
        if [[ -f "$test_file" && -r "$test_file" ]]; then
            local test_name
            test_name=$(basename "$test_file" .sh)
            
            # Determine category from file name or directory structure
            local category="unit"  # default
            if [[ "$test_name" =~ integration ]]; then
                category="integration"
            elif [[ "$test_name" =~ security ]]; then
                category="security"
            elif [[ "$test_name" =~ performance ]]; then
                category="performance"
            elif [[ "$test_name" =~ deployment ]]; then
                category="deployment"
            elif [[ "$test_name" =~ smoke ]]; then
                category="smoke"
            elif [[ "$test_name" =~ config ]]; then
                category="config"
            fi
            
            # Register the test file as executable test
            register_test "$category" "$test_name" "$test_file" "{\"discovered\":true,\"file\":\"$test_file\"}"
            discovered_count=$((discovered_count + 1))
        fi
    done < <(find "$test_dir" -name "$pattern" -type f -print0)
    
    success "Discovered $discovered_count tests in $test_dir"
}

# =============================================================================
# TEST EXECUTION ENGINE
# =============================================================================

# Execute a single test with comprehensive tracking
execute_test() {
    local test_key="$1"
    local verbose="${2:-false}"
    
    if ! aa_has_key TEST_RESULTS "${test_key}:function"; then
        error "Test not found: $test_key"
        return 1
    fi
    
    local test_function=$(aa_get TEST_RESULTS "${test_key}:function")
    local category=$(aa_get TEST_RESULTS "${test_key}:category")
    local test_name="${test_key#*:}"
    
    # Update execution state
    aa_set TEST_EXECUTION_STATE "current_category" "$category"
    aa_set TEST_EXECUTION_STATE "current_test" "$test_name"
    
    local start_time=$(date +%s.%N 2>/dev/null || date +%s)
    local timeout_duration=$(aa_get TEST_CATEGORIES "${category}:timeout" "60")
    
    aa_set TEST_RESULTS "${test_key}:status" "running"
    aa_set TEST_RESULTS "${test_key}:start_time" "$start_time"
    
    if [[ "$verbose" == "true" ]]; then
        info "Executing test: $category/$test_name"
    fi
    
    # Create test execution environment
    declare -A test_context
    aa_set test_context "test_key" "$test_key"
    aa_set test_context "test_name" "$test_name"
    aa_set test_context "category" "$category"
    aa_set test_context "start_time" "$start_time"
    
    # Execute test with timeout and capture output
    local test_output=""
    local test_exit_code=0
    local execution_time=0
    
    # Create temporary files for output capture
    local stdout_file="/tmp/test_stdout_$$_$(date +%s)"
    local stderr_file="/tmp/test_stderr_$$_$(date +%s)"
    
    # Execute test function
    if [[ -f "$test_function" ]]; then
        # Test function is a script file
        if timeout "${timeout_duration}s" bash "$test_function" >"$stdout_file" 2>"$stderr_file"; then
            test_exit_code=0
        else
            test_exit_code=$?
        fi
    else
        # Test function is a bash function
        if timeout "${timeout_duration}s" "$test_function" >"$stdout_file" 2>"$stderr_file"; then
            test_exit_code=0
        else
            test_exit_code=$?
        fi
    fi
    
    local end_time=$(date +%s.%N 2>/dev/null || date +%s)
    execution_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Capture output
    test_output=$(cat "$stdout_file" "$stderr_file" 2>/dev/null | head -100)
    
    # Clean up temporary files
    rm -f "$stdout_file" "$stderr_file"
    
    # Store test results
    aa_set TEST_RESULTS "${test_key}:end_time" "$end_time"
    aa_set TEST_RESULTS "${test_key}:execution_time" "$execution_time"
    aa_set TEST_RESULTS "${test_key}:exit_code" "$test_exit_code"
    aa_set TEST_RESULTS "${test_key}:output" "$test_output"
    
    # Update metrics
    aa_set TEST_METRICS "${test_key}:execution_time" "$execution_time"
    aa_set TEST_METRICS "${test_key}:memory_usage" "0"  # Placeholder for future enhancement
    aa_set TEST_METRICS "${test_key}:cpu_usage" "0"    # Placeholder for future enhancement
    
    # Determine test status
    local test_status
    case $test_exit_code in
        0)
            test_status="passed"
            local passed_count=$(aa_get TEST_EXECUTION_STATE "passed_tests")
            aa_set TEST_EXECUTION_STATE "passed_tests" "$((passed_count + 1))"
            if [[ "$verbose" == "true" ]]; then
                success "Test passed: $test_name (${execution_time}s)"
            fi
            ;;
        124)
            test_status="timeout"
            local failed_count=$(aa_get TEST_EXECUTION_STATE "failed_tests")
            aa_set TEST_EXECUTION_STATE "failed_tests" "$((failed_count + 1))"
            if [[ "$verbose" == "true" ]]; then
                error "Test timed out: $test_name (>${timeout_duration}s)"
            fi
            ;;
        *)
            test_status="failed"
            local failed_count=$(aa_get TEST_EXECUTION_STATE "failed_tests")
            aa_set TEST_EXECUTION_STATE "failed_tests" "$((failed_count + 1))"
            if [[ "$verbose" == "true" ]]; then
                error "Test failed: $test_name (exit code: $test_exit_code)"
            fi
            ;;
    esac
    
    aa_set TEST_RESULTS "${test_key}:status" "$test_status"
    
    # Check fail fast mode
    local fail_fast=$(aa_get TEST_CONFIGURATION "fail_fast")
    if [[ "$fail_fast" == "true" && "$test_status" != "passed" ]]; then
        error "Fail fast mode enabled - stopping execution due to test failure"
        return $test_exit_code
    fi
    
    return $test_exit_code
}

# Execute tests by category with dependency resolution
execute_test_category() {
    local category="$1"
    local parallel="${2:-auto}"
    local verbose="${3:-false}"
    
    if ! aa_has_key TEST_CATEGORIES "${category}:description"; then
        error "Unknown test category: $category"
        return 1
    fi
    
    log "Executing test category: $category"
    
    # Check and resolve dependencies
    local dependencies=$(aa_get TEST_CATEGORIES "${category}:dependencies" "")
    if [[ -n "$dependencies" ]]; then
        log "Resolving dependencies for $category: $dependencies"
        
        IFS=',' read -ra dep_array <<< "$dependencies"
        for dep in "${dep_array[@]}"; do
            dep=$(echo "$dep" | xargs)  # trim whitespace
            if [[ -n "$dep" ]]; then
                # Check if dependency has been executed successfully
                local dep_passed=true
                for test_key in $(aa_keys TEST_RESULTS); do
                    if [[ "$test_key" =~ ^${dep}: ]] && [[ "$test_key" =~ :status$ ]]; then
                        local base_key="${test_key%:status}"
                        local status=$(aa_get TEST_RESULTS "$test_key")
                        if [[ "$status" != "passed" ]]; then
                            dep_passed=false
                            break
                        fi
                    fi
                done
                
                if [[ "$dep_passed" != "true" ]]; then
                    warning "Dependency $dep has not passed - executing $category anyway"
                fi
            fi
        done
    fi
    
    # Collect tests for this category
    declare -A category_tests
    for test_key in $(aa_keys TEST_RESULTS); do
        if [[ "$test_key" =~ ^${category}: ]] && [[ "$test_key" =~ :function$ ]]; then
            local base_key="${test_key%:function}"
            local status=$(aa_get TEST_RESULTS "${base_key}:status" "registered")
            if [[ "$status" == "registered" ]]; then
                aa_set category_tests "$base_key" "pending"
            fi
        fi
    done
    
    if aa_is_empty category_tests; then
        warning "No tests found for category: $category"
        return 0
    fi
    
    local test_count=$(aa_size category_tests)
    log "Found $test_count tests in category: $category"
    
    # Determine if we should run in parallel
    local run_parallel=false
    if [[ "$parallel" == "auto" ]]; then
        local category_parallel=$(aa_get TEST_CATEGORIES "${category}:parallel" "false")
        run_parallel="$category_parallel"
    else
        run_parallel="$parallel"
    fi
    
    local category_exit_code=0
    
    if [[ "$run_parallel" == "true" ]]; then
        log "Running tests in parallel for category: $category"
        
        # Run tests in parallel using background processes
        declare -A test_pids
        local max_jobs=$(aa_get TEST_CONFIGURATION "parallel_jobs" "4")
        local running_jobs=0
        
        for test_key in $(aa_keys category_tests); do
            # Wait if we have too many running jobs
            while [[ $running_jobs -ge $max_jobs ]]; do
                for pid_test_key in $(aa_keys test_pids); do
                    local pid=$(aa_get test_pids "$pid_test_key")
                    if ! kill -0 "$pid" 2>/dev/null; then
                        # Process finished
                        wait "$pid"
                        local test_result=$?
                        if [[ $test_result -ne 0 ]]; then
                            category_exit_code=1
                        fi
                        aa_delete test_pids "$pid_test_key"
                        running_jobs=$((running_jobs - 1))
                    fi
                done
                sleep 0.1
            done
            
            # Start test in background
            execute_test "$test_key" "$verbose" &
            local test_pid=$!
            aa_set test_pids "$test_key" "$test_pid"
            running_jobs=$((running_jobs + 1))
        done
        
        # Wait for all remaining tests to complete
        for pid_test_key in $(aa_keys test_pids); do
            local pid=$(aa_get test_pids "$pid_test_key")
            wait "$pid"
            local test_result=$?
            if [[ $test_result -ne 0 ]]; then
                category_exit_code=1
            fi
        done
        
    else
        log "Running tests sequentially for category: $category"
        
        # Run tests sequentially
        for test_key in $(aa_keys category_tests); do
            execute_test "$test_key" "$verbose"
            local test_result=$?
            if [[ $test_result -ne 0 ]]; then
                category_exit_code=1
                
                # Check fail fast mode
                local fail_fast=$(aa_get TEST_CONFIGURATION "fail_fast")
                if [[ "$fail_fast" == "true" ]]; then
                    error "Fail fast mode - stopping category execution"
                    break
                fi
            fi
        done
    fi
    
    # Report category results
    local passed_in_category=0
    local failed_in_category=0
    local total_time=0
    
    for test_key in $(aa_keys category_tests); do
        local status=$(aa_get TEST_RESULTS "${test_key}:status" "unknown")
        local exec_time=$(aa_get TEST_RESULTS "${test_key}:execution_time" "0")
        
        case "$status" in
            "passed") passed_in_category=$((passed_in_category + 1)) ;;
            "failed"|"timeout") failed_in_category=$((failed_in_category + 1)) ;;
        esac
        
        total_time=$(echo "$total_time + $exec_time" | bc -l 2>/dev/null || echo "$total_time")
    done
    
    info "Category $category completed: $passed_in_category passed, $failed_in_category failed (${total_time}s)"
    
    return $category_exit_code
}

# =============================================================================
# TEST REPORTING AND ANALYTICS
# =============================================================================

# Generate comprehensive test report
generate_enhanced_test_report() {
    local format="${1:-html}"  # html, json, yaml, markdown
    local include_details="${2:-true}"
    
    local reports_dir=$(aa_get TEST_CONFIGURATION "reports_dir")
    local session_id=$(aa_get TEST_EXECUTION_STATE "session_id")
    local start_time=$(aa_get TEST_EXECUTION_STATE "start_time")
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    declare -A report_summary
    aa_set report_summary "session_id" "$session_id"
    aa_set report_summary "start_time" "$start_time"
    aa_set report_summary "end_time" "$end_time"
    aa_set report_summary "duration_seconds" "$total_duration"
    aa_set report_summary "total_tests" "$(aa_get TEST_EXECUTION_STATE "total_tests")"
    aa_set report_summary "passed_tests" "$(aa_get TEST_EXECUTION_STATE "passed_tests")"
    aa_set report_summary "failed_tests" "$(aa_get TEST_EXECUTION_STATE "failed_tests")"
    aa_set report_summary "skipped_tests" "$(aa_get TEST_EXECUTION_STATE "skipped_tests")"
    
    case "$format" in
        "html")
            generate_html_report report_summary "$include_details"
            ;;
        "json")
            generate_json_report report_summary "$include_details"
            ;;
        "yaml")
            generate_yaml_report report_summary "$include_details"
            ;;
        "markdown")
            generate_markdown_report report_summary "$include_details"
            ;;
        *)
            error "Unsupported report format: $format"
            return 1
            ;;
    esac
}

# Generate HTML test report
generate_html_report() {
    local -n summary_ref="$1"
    local include_details="$2"
    
    local reports_dir=$(aa_get TEST_CONFIGURATION "reports_dir")
    local report_file="$reports_dir/enhanced-test-report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Enhanced Test Report - GeuseMaker</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; background: #f5f6fa; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
        .metric-value { font-size: 2em; font-weight: bold; margin-bottom: 5px; }
        .metric-label { color: #666; font-size: 0.9em; }
        .passed { color: #27ae60; }
        .failed { color: #e74c3c; }
        .skipped { color: #f39c12; }
        .category-section { background: white; margin-bottom: 20px; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .category-header { background: #34495e; color: white; padding: 15px; }
        .test-list { padding: 0; }
        .test-item { padding: 15px; border-bottom: 1px solid #ecf0f1; display: flex; justify-content: space-between; align-items: center; }
        .test-item:last-child { border-bottom: none; }
        .test-status { padding: 5px 10px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
        .status-passed { background: #d5f4e6; color: #27ae60; }
        .status-failed { background: #fadbd8; color: #e74c3c; }
        .status-timeout { background: #fdeaa7; color: #f39c12; }
        .execution-time { color: #7f8c8d; font-size: 0.9em; }
        .details { margin-top: 10px; padding: 10px; background: #f8f9fa; border-radius: 4px; font-family: monospace; font-size: 0.8em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Enhanced Test Report</h1>
            <p>Generated: $(date)</p>
            <p>Session ID: $(aa_get summary_ref "session_id")</p>
            <p>Duration: $(aa_get summary_ref "duration_seconds") seconds</p>
        </div>
        
        <div class="summary">
            <div class="metric-card">
                <div class="metric-value">$(aa_get summary_ref "total_tests")</div>
                <div class="metric-label">Total Tests</div>
            </div>
            <div class="metric-card">
                <div class="metric-value passed">$(aa_get summary_ref "passed_tests")</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value failed">$(aa_get summary_ref "failed_tests")</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value skipped">$(aa_get summary_ref "skipped_tests")</div>
                <div class="metric-label">Skipped</div>
            </div>
        </div>
EOF

    # Add category sections if details are requested
    if [[ "$include_details" == "true" ]]; then
        # Group tests by category
        declare -A category_tests
        for test_key in $(aa_keys TEST_RESULTS); do
            if [[ "$test_key" =~ :category$ ]]; then
                local base_key="${test_key%:category}"
                local category=$(aa_get TEST_RESULTS "$test_key")
                local existing_tests=$(aa_get category_tests "$category" "")
                if [[ -n "$existing_tests" ]]; then
                    aa_set category_tests "$category" "${existing_tests},${base_key}"
                else
                    aa_set category_tests "$category" "$base_key"
                fi
            fi
        done
        
        # Generate category sections
        for category in $(aa_keys category_tests); do
            local category_description=$(aa_get TEST_CATEGORIES "${category}:description" "No description")
            
            cat >> "$report_file" << EOF
        <div class="category-section">
            <div class="category-header">
                <h3>$category Tests</h3>
                <p>$category_description</p>
            </div>
            <div class="test-list">
EOF
            
            local test_list=$(aa_get category_tests "$category")
            IFS=',' read -ra tests <<< "$test_list"
            
            for test_key in "${tests[@]}"; do
                local test_name="${test_key#*:}"
                local status=$(aa_get TEST_RESULTS "${test_key}:status" "unknown")
                local exec_time=$(aa_get TEST_RESULTS "${test_key}:execution_time" "0")
                local output=$(aa_get TEST_RESULTS "${test_key}:output" "")
                
                local status_class="status-$status"
                local status_display="$status"
                case "$status" in
                    "passed") status_display="✅ Passed" ;;
                    "failed") status_display="❌ Failed" ;;
                    "timeout") status_display="⏱️ Timeout" ;;
                esac
                
                cat >> "$report_file" << EOF
                <div class="test-item">
                    <div>
                        <strong>$test_name</strong>
                        <div class="execution-time">Execution time: ${exec_time}s</div>
EOF
                
                if [[ -n "$output" && "$status" != "passed" ]]; then
                    cat >> "$report_file" << EOF
                        <div class="details">$output</div>
EOF
                fi
                
                cat >> "$report_file" << EOF
                    </div>
                    <div class="test-status $status_class">$status_display</div>
                </div>
EOF
            done
            
            cat >> "$report_file" << EOF
            </div>
        </div>
EOF
        done
    fi
    
    cat >> "$report_file" << EOF
    </div>
</body>
</html>
EOF
    
    success "HTML test report generated: $report_file"
}

# Generate JSON test report
generate_json_report() {
    local -n summary_ref="$1"
    local include_details="$2"
    
    local reports_dir=$(aa_get TEST_CONFIGURATION "reports_dir")
    local report_file="$reports_dir/enhanced-test-results.json"
    
    # Start building JSON report
    local json_report="{"
    json_report+='"summary":{'
    json_report+='"session_id":"'$(aa_get summary_ref "session_id")'",'
    json_report+='"start_time":'$(aa_get summary_ref "start_time")','
    json_report+='"end_time":'$(aa_get summary_ref "end_time")','
    json_report+='"duration_seconds":'$(aa_get summary_ref "duration_seconds")','
    json_report+='"total_tests":'$(aa_get summary_ref "total_tests")','
    json_report+='"passed_tests":'$(aa_get summary_ref "passed_tests")','
    json_report+='"failed_tests":'$(aa_get summary_ref "failed_tests")','
    json_report+='"skipped_tests":'$(aa_get summary_ref "skipped_tests")
    json_report+='},'
    
    if [[ "$include_details" == "true" ]]; then
        json_report+='"test_results":['
        
        local first_test=true
        for test_key in $(aa_keys TEST_RESULTS); do
            if [[ "$test_key" =~ :function$ ]]; then
                local base_key="${test_key%:function}"
                
                if [[ "$first_test" != "true" ]]; then
                    json_report+=","
                else
                    first_test=false
                fi
                
                local test_name="${base_key#*:}"
                local category=$(aa_get TEST_RESULTS "${base_key}:category" "unknown")
                local status=$(aa_get TEST_RESULTS "${base_key}:status" "unknown")
                local exec_time=$(aa_get TEST_RESULTS "${base_key}:execution_time" "0")
                local exit_code=$(aa_get TEST_RESULTS "${base_key}:exit_code" "0")
                
                json_report+='{'
                json_report+='"test_name":"'$test_name'",'
                json_report+='"category":"'$category'",'
                json_report+='"status":"'$status'",'
                json_report+='"execution_time":'$exec_time','
                json_report+='"exit_code":'$exit_code
                json_report+='}'
            fi
        done
        
        json_report+=']'
    fi
    
    json_report+='}'
    
    echo "$json_report" | jq . > "$report_file" 2>/dev/null || echo "$json_report" > "$report_file"
    
    success "JSON test report generated: $report_file"
}

# =============================================================================
# CUSTOM ASSERTIONS
# =============================================================================

# Custom assertion framework
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "Expected: $expected"
        echo "Actual: $actual"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" != "$actual" ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "Expected not: $expected"
        echo "Actual: $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" =~ $needle ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "String '$haystack' does not contain '$needle'"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-File does not exist}"
    
    if [[ -f "$file_path" ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "File not found: $file_path"
        return 1
    fi
}

assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command failed}"
    
    if eval "$command" >/dev/null 2>&1; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "Command failed: $command"
        return 1
    fi
}

# =============================================================================
# LIBRARY EXPORTS
# =============================================================================

# Export all functions
export -f init_test_framework register_test discover_tests
export -f execute_test execute_test_category
export -f generate_enhanced_test_report generate_html_report generate_json_report
export -f assert_equals assert_not_equals assert_contains assert_file_exists assert_command_succeeds

# Log successful loading
if declare -f log >/dev/null 2>&1; then
    log "Enhanced Test Framework library loaded (v${ENHANCED_TEST_FRAMEWORK_VERSION})"
fi