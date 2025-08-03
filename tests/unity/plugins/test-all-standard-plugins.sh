#!/bin/bash
# =============================================================================
# Test Suite: All Standard Plugins
# Master test runner for all Unity standard plugins
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Test configuration
TEST_SUITE_NAME="Unity Standard Plugins Test Suite"
TEST_OUTPUT_DIR="$PROJECT_ROOT/test-reports/unity/plugins"
mkdir -p "$TEST_OUTPUT_DIR"

# Standard plugins to test
STANDARD_PLUGINS=(
    "spot-optimizer"
    "cost-analyzer"
    "security-validator"
    "performance-tuner"
)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}=========================================="
    echo -e "$1"
    echo -e "==========================================${NC}"
}

# Test execution function
run_plugin_test() {
    local plugin_name="$1"
    local test_script="$SCRIPT_DIR/test-${plugin_name}.sh"
    
    log_info "Running test suite for $plugin_name plugin..."
    
    if [[ ! -f "$test_script" ]]; then
        log_error "Test script not found: $test_script"
        return 1
    fi
    
    if [[ ! -x "$test_script" ]]; then
        chmod +x "$test_script"
    fi
    
    # Run the test script
    local start_time=$(date +%s)
    
    if bash "$test_script"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "$plugin_name plugin tests passed (${duration}s)"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "$plugin_name plugin tests failed (${duration}s)"
        return 1
    fi
}

# Plugin existence check
check_plugin_exists() {
    local plugin_name="$1"
    local plugin_file="$PROJECT_ROOT/lib/unity/plugins/standard-plugins/${plugin_name}.sh"
    
    if [[ ! -f "$plugin_file" ]]; then
        log_error "Plugin file not found: $plugin_file"
        return 1
    fi
    
    if [[ ! -x "$plugin_file" ]]; then
        log_warning "Plugin file is not executable: $plugin_file"
        chmod +x "$plugin_file"
    fi
    
    return 0
}

# Generate comprehensive test report
generate_comprehensive_report() {
    local total_tests="$1"
    local passed_tests="$2"
    local failed_tests="$3"
    local total_time="$4"
    local plugin_results="$5"
    
    local report_file="$TEST_OUTPUT_DIR/standard-plugins-comprehensive-report.json"
    
    cat > "$report_file" <<EOF
{
    "test_suite": "$TEST_SUITE_NAME",
    "timestamp": $(date +%s),
    "execution_time": $total_time,
    "summary": {
        "total_plugins": ${#STANDARD_PLUGINS[@]},
        "plugins_passed": $passed_tests,
        "plugins_failed": $failed_tests,
        "success_rate": $(echo "scale=2; $passed_tests * 100 / ${#STANDARD_PLUGINS[@]}" | bc 2>/dev/null || echo "0")
    },
    "plugin_results": $plugin_results,
    "environment": {
        "bash_version": "$BASH_VERSION",
        "test_environment": "automated",
        "project_root": "$PROJECT_ROOT"
    }
}
EOF
    
    log_info "Comprehensive test report generated: $report_file"
}

# Generate HTML test report
generate_html_report() {
    local total_tests="$1"
    local passed_tests="$2"
    local failed_tests="$3"
    local total_time="$4"
    
    local html_report="$TEST_OUTPUT_DIR/standard-plugins-test-report.html"
    
    cat > "$html_report" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Unity Standard Plugins Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; padding: 15px; background-color: #e8f4f8; border-radius: 5px; }
        .plugin-result { margin: 10px 0; padding: 10px; border-radius: 5px; }
        .passed { background-color: #d4edda; border-left: 5px solid #28a745; }
        .failed { background-color: #f8d7da; border-left: 5px solid #dc3545; }
        .stats { display: flex; justify-content: space-around; margin: 20px 0; }
        .stat-box { text-align: center; padding: 15px; background-color: #f8f9fa; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Unity Standard Plugins Test Report</h1>
        <p>Generated on $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <div class="stats">
            <div class="stat-box">
                <h3>${#STANDARD_PLUGINS[@]}</h3>
                <p>Total Plugins</p>
            </div>
            <div class="stat-box">
                <h3>$passed_tests</h3>
                <p>Passed</p>
            </div>
            <div class="stat-box">
                <h3>$failed_tests</h3>
                <p>Failed</p>
            </div>
            <div class="stat-box">
                <h3>${total_time}s</h3>
                <p>Execution Time</p>
            </div>
        </div>
    </div>
    
    <div class="plugin-results">
        <h2>Plugin Test Results</h2>
EOF
    
    # Add plugin results to HTML
    for plugin in "${STANDARD_PLUGINS[@]}"; do
        local result_file="$TEST_OUTPUT_DIR/${plugin}-test-results.json"
        if [[ -f "$result_file" ]]; then
            local plugin_passed
            plugin_passed=$(jq -r '.tests_failed' "$result_file" 2>/dev/null || echo "1")
            if [[ "$plugin_passed" == "0" ]]; then
                cat >> "$html_report" <<EOF
        <div class="plugin-result passed">
            <h3>✅ $plugin Plugin</h3>
            <p>All tests passed successfully</p>
        </div>
EOF
            else
                cat >> "$html_report" <<EOF
        <div class="plugin-result failed">
            <h3>❌ $plugin Plugin</h3>
            <p>Some tests failed - see detailed report</p>
        </div>
EOF
            fi
        else
            cat >> "$html_report" <<EOF
        <div class="plugin-result failed">
            <h3>❌ $plugin Plugin</h3>
            <p>Test results not available</p>
        </div>
EOF
        fi
    done
    
    cat >> "$html_report" <<EOF
    </div>
</body>
</html>
EOF
    
    log_info "HTML test report generated: $html_report"
}

# Cleanup function
cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Clean up any temporary files
    rm -rf "/tmp/test_unity_plugins_"* 2>/dev/null || true
    rm -f "/tmp/aws" "/tmp/free" "/tmp/df" "/tmp/top" "/tmp/ps" "/tmp/uptime" 2>/dev/null || true
    
    # Clean up plugin state directories
    for plugin in "${STANDARD_PLUGINS[@]}"; do
        rm -rf ".unity/plugins/${plugin}" 2>/dev/null || true
    done
    
    log_info "Test environment cleaned up"
}

# Pre-test validation
validate_test_environment() {
    log_info "Validating test environment..."
    
    # Check if standard plugins directory exists
    local plugins_dir="$PROJECT_ROOT/lib/unity/plugins/standard-plugins"
    if [[ ! -d "$plugins_dir" ]]; then
        log_error "Standard plugins directory not found: $plugins_dir"
        return 1
    fi
    
    # Check if each plugin exists
    local missing_plugins=()
    for plugin in "${STANDARD_PLUGINS[@]}"; do
        if ! check_plugin_exists "$plugin"; then
            missing_plugins+=("$plugin")
        fi
    done
    
    if [[ ${#missing_plugins[@]} -gt 0 ]]; then
        log_error "Missing plugins: ${missing_plugins[*]}"
        return 1
    fi
    
    # Check for required commands
    local required_commands=("jq" "bc" "date")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_warning "Optional command not found: $cmd (some features may be limited)"
        fi
    done
    
    log_success "Test environment validation completed"
    return 0
}

# Main test execution function
main() {
    local start_time=$(date +%s)
    
    log_header "$TEST_SUITE_NAME"
    log_info "Starting comprehensive test suite for Unity standard plugins"
    
    # Validate test environment
    if ! validate_test_environment; then
        log_error "Test environment validation failed"
        exit 1
    fi
    
    # Initialize test results
    local passed_plugins=0
    local failed_plugins=0
    local plugin_results="["
    local first_result=true
    
    # Cleanup before starting tests
    cleanup_test_environment
    
    # Run tests for each standard plugin
    for plugin in "${STANDARD_PLUGINS[@]}"; do
        log_header "Testing $plugin Plugin"
        
        local plugin_start_time=$(date +%s)
        
        if run_plugin_test "$plugin"; then
            ((passed_plugins++))
            local plugin_status="passed"
        else
            ((failed_plugins++))
            local plugin_status="failed"
        fi
        
        local plugin_end_time=$(date +%s)
        local plugin_duration=$((plugin_end_time - plugin_start_time))
        
        # Add to plugin results JSON
        if [[ "$first_result" != "true" ]]; then
            plugin_results="$plugin_results,"
        fi
        first_result=false
        
        plugin_results="$plugin_results{\"plugin\":\"$plugin\",\"status\":\"$plugin_status\",\"duration\":$plugin_duration}"
        
        log_info "$plugin plugin test completed in ${plugin_duration}s"
    done
    
    plugin_results="$plugin_results]"
    
    # Calculate final results
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local total_plugins=${#STANDARD_PLUGINS[@]}
    local success_rate=0
    
    if [[ $total_plugins -gt 0 ]]; then
        success_rate=$(echo "scale=2; $passed_plugins * 100 / $total_plugins" | bc 2>/dev/null || echo "0")
    fi
    
    # Display final results
    log_header "Test Results Summary"
    echo ""
    echo "📊 Test Execution Summary:"
    echo "   Total Plugins Tested: $total_plugins"
    echo "   Plugins Passed: $passed_plugins"
    echo "   Plugins Failed: $failed_plugins"
    echo "   Success Rate: ${success_rate}%"
    echo "   Total Execution Time: ${total_time}s"
    echo ""
    
    # Display individual plugin results
    echo "🔍 Individual Plugin Results:"
    for plugin in "${STANDARD_PLUGINS[@]}"; do
        local result_file="$TEST_OUTPUT_DIR/${plugin}-test-results.json"
        if [[ -f "$result_file" ]]; then
            local plugin_failed
            plugin_failed=$(jq -r '.tests_failed' "$result_file" 2>/dev/null || echo "1")
            if [[ "$plugin_failed" == "0" ]]; then
                echo "   ✅ $plugin: All tests passed"
            else
                local plugin_total
                plugin_total=$(jq -r '.total_tests' "$result_file" 2>/dev/null || echo "unknown")
                local plugin_passed
                plugin_passed=$(jq -r '.tests_passed' "$result_file" 2>/dev/null || echo "unknown")
                echo "   ❌ $plugin: $plugin_failed tests failed ($plugin_passed/$plugin_total passed)"
            fi
        else
            echo "   ❓ $plugin: Test results not available"
        fi
    done
    echo ""
    
    # Generate reports
    log_info "Generating test reports..."
    generate_comprehensive_report "$total_plugins" "$passed_plugins" "$failed_plugins" "$total_time" "$plugin_results"
    generate_html_report "$total_plugins" "$passed_plugins" "$failed_plugins" "$total_time"
    
    # Cleanup after tests
    cleanup_test_environment
    
    # Final status
    if [[ $failed_plugins -eq 0 ]]; then
        log_success "🎉 All standard plugin tests passed successfully!"
        echo ""
        echo "📁 Test reports available at:"
        echo "   JSON: $TEST_OUTPUT_DIR/standard-plugins-comprehensive-report.json"
        echo "   HTML: $TEST_OUTPUT_DIR/standard-plugins-test-report.html"
        echo ""
        return 0
    else
        log_error "❌ $failed_plugins plugin test(s) failed"
        echo ""
        echo "📁 Test reports available at:"
        echo "   JSON: $TEST_OUTPUT_DIR/standard-plugins-comprehensive-report.json"
        echo "   HTML: $TEST_OUTPUT_DIR/standard-plugins-test-report.html"
        echo ""
        return 1
    fi
}

# Script options handling
case "${1:-run}" in
    "help"|"-h"|"--help")
        echo "Unity Standard Plugins Test Suite"
        echo ""
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  run (default)  - Run all standard plugin tests"
        echo "  validate       - Validate test environment only"
        echo "  cleanup        - Cleanup test environment"
        echo "  list           - List standard plugins"
        echo "  help           - Show this help message"
        echo ""
        echo "Standard Plugins:"
        for plugin in "${STANDARD_PLUGINS[@]}"; do
            echo "  - $plugin"
        done
        echo ""
        ;;
    "validate")
        log_header "Test Environment Validation"
        if validate_test_environment; then
            log_success "Test environment is ready"
            exit 0
        else
            log_error "Test environment validation failed"
            exit 1
        fi
        ;;
    "cleanup")
        log_header "Test Environment Cleanup"
        cleanup_test_environment
        log_success "Test environment cleaned up"
        ;;
    "list")
        echo "Unity Standard Plugins:"
        for plugin in "${STANDARD_PLUGINS[@]}"; do
            local plugin_file="$PROJECT_ROOT/lib/unity/plugins/standard-plugins/${plugin}.sh"
            if [[ -f "$plugin_file" ]]; then
                echo "  ✅ $plugin"
            else
                echo "  ❌ $plugin (missing)"
            fi
        done
        ;;
    "run"|*)
        main "$@"
        ;;
esac