#!/usr/bin/env bash
# =============================================================================
# Comprehensive Test Runner
# Runs all types of tests for the GeuseMaker
# =============================================================================

set -euo pipefail

# Initialize library loader
SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

# Source the errors module
if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
    source "$LIB_DIR_TEMP/modules/core/errors.sh"
else
    # Fallback warning if errors module not found
    echo "WARNING: Could not load errors module" >&2
fi

# Standard library loader
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Load required libraries with error handling
load_library() {
    local library="$1"
    local library_path="${LIB_DIR}/${library}"
    
    if [ ! -f "$library_path" ]; then
        echo "ERROR: Required library not found: $library_path" >&2
        exit 1
    fi
    
    # shellcheck source=/dev/null
    source "$library_path" || {
        echo "ERROR: Failed to source library: $library_path" >&2
        exit 1
    }
}

# Load common libraries
load_library "aws-deployment-common.sh"
load_library "error-handling.sh"

# Initialize error handling
init_error_handling "resilient"

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

readonly TEST_REPORTS_DIR="$PROJECT_ROOT/test-reports"
readonly COVERAGE_DIR="$TEST_REPORTS_DIR/coverage"
readonly RESULTS_FILE="$TEST_REPORTS_DIR/test-results.json"

# Test categories - using arrays that work with bash 3.x and 4.x
readonly TEST_CATEGORIES_UNIT="Unit tests for individual functions"
readonly TEST_CATEGORIES_INTEGRATION="Integration tests for component interaction"
readonly TEST_CATEGORIES_SECURITY="Security vulnerability scans"
readonly TEST_CATEGORIES_PERFORMANCE="Performance and load tests"
readonly TEST_CATEGORIES_DEPLOYMENT="Deployment validation tests"
readonly TEST_CATEGORIES_SMOKE="Basic smoke tests for quick validation"

# Helper function to get test category description
get_test_category_description() {
    local category="$1"
    case "$category" in
        "unit") echo "$TEST_CATEGORIES_UNIT" ;;
        "integration") echo "$TEST_CATEGORIES_INTEGRATION" ;;
        "security") echo "$TEST_CATEGORIES_SECURITY" ;;
        "performance") echo "$TEST_CATEGORIES_PERFORMANCE" ;;
        "deployment") echo "$TEST_CATEGORIES_DEPLOYMENT" ;;
        "smoke") echo "$TEST_CATEGORIES_SMOKE" ;;
        "config") echo "Configuration management tests" ;;
        "maintenance") echo "Maintenance suite functionality tests" ;;
        *) echo "Unknown test category" ;;
    esac
}

# Array of available test categories
readonly AVAILABLE_TEST_CATEGORIES=("unit" "integration" "security" "performance" "deployment" "smoke" "config" "maintenance")

# =============================================================================
# SETUP AND CLEANUP
# =============================================================================

setup_test_environment() {
    log "Setting up test environment..."
    
    # Create test reports directory
    mkdir -p "$TEST_REPORTS_DIR" "$COVERAGE_DIR"
    
    # Initialize results file
    cat > "$RESULTS_FILE" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project": "GeuseMaker",
    "environment": "${TEST_ENVIRONMENT:-development}",
    "results": {}
}
EOF
    
    # Shell-based testing - no Python virtual environment needed
    log "Using shell-based testing framework..."
    
    # Check for required shell tools
    local required_tools=("bash" "grep" "find")
    local optional_tools=("bandit" "safety" "trivy")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_warning "Optional security tool not available: $tool"
        fi
    done
    
    success "Test environment setup complete"
}

cleanup_test_environment() {
    log "Cleaning up test environment..."
    
    # Clean up temporary files
    find "$PROJECT_ROOT" -name "*.tmp" -delete 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.temp" -delete 2>/dev/null || true
    
    success "Test environment cleanup complete"
}

# =============================================================================
# UNIT TESTS
# =============================================================================

run_unit_tests() {
    log "Running unit tests..."
    
    local exit_code=0
    
    # Run security validation tests
    local security_test="$PROJECT_ROOT/tests/test-security-validation.sh"
    if [ -f "$security_test" ]; then
        info "Running security validation unit tests..."
        
        if "$security_test"; then
            success "Security validation tests passed"
        else
            log_error "Security validation tests failed"
            exit_code=1
        fi
    else
        log_warning "Security validation test not found: $security_test"
    fi
    
    # Run configuration management tests
    local config_test="$PROJECT_ROOT/tests/test-config-management.sh"
    if [ -f "$config_test" ]; then
        info "Running configuration management unit tests..."
        
        if "$config_test"; then
            success "Configuration management tests passed"
        else
            log_error "Configuration management tests failed"
            exit_code=1
        fi
    else
        log_warning "Configuration management test not found: $config_test"
    fi
    
    # Run library unit tests (new shell-based framework)
    info "Running library unit tests..."
    local lib_test_dir="$PROJECT_ROOT/tests/lib"
    if [ -d "$lib_test_dir" ]; then
        local lib_unit_tests=(
            "$lib_test_dir/test-aws-deployment-common.sh"
            "$lib_test_dir/test-error-handling.sh"
            "$lib_test_dir/test-aws-config.sh"
            "$lib_test_dir/test-spot-instance.sh"
            "$lib_test_dir/test-docker-compose-installer.sh"
            "$lib_test_dir/test-instance-libraries.sh"
        )
        
        for test_script in "${lib_unit_tests[@]}"; do
            if [ -f "$test_script" ]; then
                local test_name=$(basename "$test_script" .sh)
                info "Running library unit test: $test_name"
                
                if "$test_script"; then
                    success "Library unit test passed: $test_name"
                else
                    log_error "Library unit test failed: $test_name"
                    exit_code=1
                fi
            else
                log_warning "Library unit test not found: $test_script"
            fi
        done
    else
        log_warning "Library unit test directory not found: $lib_test_dir"
    fi
    
    # Run other unit test scripts
    for test_script in "$PROJECT_ROOT/tests"/test-*.sh; do
        [ -f "$test_script" ] || continue
        [ "$test_script" == "$security_test" ] && continue
        
        local test_name=$(basename "$test_script" .sh)
        if [[ "$test_name" == *"unit"* ]] || [[ "$test_name" == *"security"* ]]; then
            info "Running unit test: $test_name"
            
            if "$test_script"; then
                success "Unit test passed: $test_name"
            else
                log_error "Unit test failed: $test_name"
                exit_code=1
            fi
        fi
    done
    
    # Update results
    update_test_results "unit" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

run_integration_tests() {
    log "Running integration tests..."
    
    local exit_code=0
    
    # Check if Docker is available for integration tests
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker not available - some integration tests may be skipped"
    fi
    
    # Run deployment workflow integration tests
    local deployment_test="$PROJECT_ROOT/tests/test-deployment-workflow.sh"
    if [ -f "$deployment_test" ]; then
        info "Running deployment workflow integration tests..."
        
        if "$deployment_test"; then
            success "Deployment workflow tests passed"
        else
            log_error "Deployment workflow tests failed"
            exit_code=1
        fi
    else
        log_warning "Deployment workflow test not found: $deployment_test"
    fi
    
    # Run other existing integration test scripts
    local integration_scripts=(
        "$PROJECT_ROOT/tests/test-alb-cloudfront.sh"
        "$PROJECT_ROOT/tests/test-compose-validation.sh"
        "$PROJECT_ROOT/tests/test-docker-config.sh"
        "$PROJECT_ROOT/tests/test-image-config.sh"
    )
    
    for test_script in "${integration_scripts[@]}"; do
        if [ -f "$test_script" ]; then
            local test_name=$(basename "$test_script" .sh)
            info "Running integration test: $test_name"
            
            if "$test_script"; then
                success "Integration test passed: $test_name"
            else
                log_error "Integration test failed: $test_name"
                exit_code=1
            fi
        fi
    done
    
    # Update results
    update_test_results "integration" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# SECURITY TESTS
# =============================================================================

run_security_tests() {
    log "Running security tests..."
    
    local exit_code=0
    
    # Python security scan with bandit
    if command -v bandit >/dev/null 2>&1; then
        info "Running Python security scan with bandit..."
        
        if bandit -r "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/lib" \
            -f json -o "$TEST_REPORTS_DIR/security-python.json" \
            -f txt -o "$TEST_REPORTS_DIR/security-python.txt"; then
            success "Python security scan passed"
        else
            log_warning "Python security issues found (check reports)"
        fi
    fi
    
    # Dependency vulnerability scan with safety
    if command -v safety >/dev/null 2>&1; then
        info "Running dependency vulnerability scan..."
        
        if safety check --json --output "$TEST_REPORTS_DIR/security-deps.json"; then
            success "Dependency security scan passed"
        else
            log_warning "Dependency vulnerabilities found"
        fi
    fi
    
    # Docker image security scan with trivy
    if command -v trivy >/dev/null 2>&1; then
        info "Running Docker image security scan..."
        
        # Scan common base images used in docker-compose
        local images=("postgres:16.1-alpine3.19" "n8nio/n8n:1.19.4" "qdrant/qdrant:v1.7.3")
        
        for image in "${images[@]}"; do
            if trivy image "$image" \
                --format json \
                --output "$TEST_REPORTS_DIR/security-${image//[:\/]/-}.json" \
                --severity HIGH,CRITICAL; then
                success "Security scan passed for $image"
            else
                log_warning "Security issues found in $image"
            fi
        done
    fi
    
    # File permission and sensitive data checks
    info "Running file security checks..."
    
    # Check for files with overly permissive permissions
    find "$PROJECT_ROOT" -type f -perm /o+w 2>/dev/null | while read -r file; do
        log_warning "World-writable file found: $file"
    done
    
    # Check for potential secrets in files
    if command -v grep >/dev/null 2>&1; then
        local secret_patterns=("password" "secret" "token" "api.*key" "private.*key")
        
        for pattern in "${secret_patterns[@]}"; do
            if grep -r -i "$pattern" "$PROJECT_ROOT" \
                --exclude-dir=".git" \
                --exclude-dir="test-reports" \
                --exclude-dir=".test-venv" \
                --exclude="*.md" 2>/dev/null | head -10; then
                log_warning "Potential secrets found matching pattern: $pattern"
            fi
        done
    fi
    
    # Update results
    update_test_results "security" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

run_performance_tests() {
    log "Running performance tests..."
    
    local test_dir="$PROJECT_ROOT/tests/performance"
    local exit_code=0
    
    if [ ! -d "$test_dir" ]; then
        log_warning "Performance test directory not found: $test_dir"
        return 0
    fi
    
    # Run performance tests if they exist
    if command -v pytest >/dev/null 2>&1; then
        info "Running performance tests with pytest..."
        
        if pytest "$test_dir" \
            --verbose \
            --benchmark-only \
            --benchmark-json="$TEST_REPORTS_DIR/performance-results.json" \
            --junitxml="$TEST_REPORTS_DIR/performance-tests.xml"; then
            success "Performance tests passed"
        else
            log_error "Performance tests failed"
            exit_code=1
        fi
    fi
    
    # Basic script performance tests
    info "Running script performance analysis..."
    
    local scripts=("$PROJECT_ROOT/scripts/aws-deployment-v2-simple.sh" "$PROJECT_ROOT/scripts/aws-deployment-modular.sh")
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            info "Analyzing script: $(basename "$script")"
            
            # Time the script's help function
            local help_time
            help_time=$(timeout 30s time "$script" --help 2>&1 | grep real || echo "timeout")
            
            info "Help execution time: $help_time"
        fi
    done
    
    # Update results
    update_test_results "performance" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# DEPLOYMENT TESTS
# =============================================================================

run_deployment_tests() {
    log "Running deployment validation tests..."
    
    local exit_code=0
    
    # Test deployment script syntax and validation
    info "Testing deployment script validation..."
    
    local deployment_script="$PROJECT_ROOT/scripts/aws-deployment-v2-simple.sh"
    
    if [ -f "$deployment_script" ]; then
        # Test script syntax
        if bash -n "$deployment_script"; then
            success "Deployment script syntax is valid"
        else
            log_error "Deployment script has syntax errors"
            exit_code=1
        fi
        
        # Test validation mode
        if "$deployment_script" --validate-only test-stack 2>/dev/null; then
            success "Deployment validation mode works"
        else
            log_warning "Deployment validation mode failed (may need AWS credentials)"
        fi
    fi
    
    # Test Terraform configuration
    if [ -d "$PROJECT_ROOT/terraform" ]; then
        info "Testing Terraform configuration..."
        
        cd "$PROJECT_ROOT/terraform"
        
        if command -v terraform >/dev/null 2>&1; then
            # Initialize and validate
            if terraform init >/dev/null 2>&1 && terraform validate; then
                success "Terraform configuration is valid"
            else
                log_error "Terraform configuration validation failed"
                exit_code=1
            fi
            
            # Test plan generation
            if terraform plan -var="stack_name=test-stack" >/dev/null 2>&1; then
                success "Terraform plan generation works"
            else
                log_warning "Terraform plan failed (may need AWS credentials)"
            fi
        fi
        
        cd "$PROJECT_ROOT"
    fi
    
    # Test Docker Compose configurations
    info "Testing Docker Compose configurations..."
    
    local compose_files=(
        "$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
        "$PROJECT_ROOT/docker-compose.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        if [ -f "$compose_file" ] && command -v docker-compose >/dev/null 2>&1; then
            if docker-compose -f "$compose_file" config >/dev/null 2>&1; then
                success "$(basename "$compose_file") configuration is valid"
            else
                log_error "$(basename "$compose_file") configuration is invalid"
                exit_code=1
            fi
        fi
    done
    
    # Update results
    update_test_results "deployment" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# CONFIGURATION MANAGEMENT TESTS
# =============================================================================

run_config_tests() {
    log "Running configuration management tests..."
    
    local exit_code=0
    
    # Test configuration management system
    info "Testing centralized configuration management..."
    
    if [ -f "$PROJECT_ROOT/tests/test-config-management.sh" ]; then
        info "Running configuration management test suite..."
        
        if timeout 60s bash "$PROJECT_ROOT/tests/test-config-management.sh"; then
            success "Configuration management tests passed"
        else
            error "Configuration management tests failed"
            exit_code=1
        fi
    else
        log_warning "Configuration management test suite not found"
    fi
    
    # Test configuration validation
    info "Testing configuration validation..."
    
    if [ -f "$PROJECT_ROOT/tools/validate-config.sh" ]; then
        if timeout 30s "$PROJECT_ROOT/tools/validate-config.sh" >/dev/null 2>&1; then
            success "Configuration validation works"
        else
            error "Configuration validation failed"
            exit_code=1
        fi
    else
        log_warning "Configuration validation script not found"
    fi
    
    # Test environment file generation
    info "Testing environment file generation..."
    
    if [ -f "$PROJECT_ROOT/lib/config-management.sh" ]; then
        # Source the config management library
        source "$PROJECT_ROOT/lib/config-management.sh"
        
        # Test environment file generation
        local test_env_file="/tmp/test-env-$$"
        if generate_environment_file "development" "$test_env_file" >/dev/null 2>&1; then
            if [ -f "$test_env_file" ]; then
                success "Environment file generation works"
                rm -f "$test_env_file"
            else
                error "Environment file generation failed"
                exit_code=1
            fi
        else
            error "Environment file generation failed"
            exit_code=1
        fi
    else
        log_warning "Configuration management library not found"
    fi
    
    return $exit_code
}

# =============================================================================
# MAINTENANCE TESTS
# =============================================================================

run_maintenance_tests() {
    log "Running maintenance suite tests..."
    
    local exit_code=0
    
    # Run maintenance suite unit tests
    local maintenance_test="$PROJECT_ROOT/tests/test-maintenance-suite.sh"
    if [ -f "$maintenance_test" ]; then
        info "Running maintenance suite functionality tests..."
        
        if "$maintenance_test"; then
            success "Maintenance suite tests passed"
        else
            log_error "Maintenance suite tests failed"
            exit_code=1
        fi
    else
        log_warning "Maintenance suite test not found: $maintenance_test"
    fi
    
    # Run maintenance integration tests
    local maintenance_integration="$PROJECT_ROOT/tests/test-maintenance-integration.sh"
    if [ -f "$maintenance_integration" ]; then
        info "Running maintenance integration tests..."
        
        if "$maintenance_integration"; then
            success "Maintenance integration tests passed"
        else
            log_error "Maintenance integration tests failed"
            exit_code=1
        fi
    else
        log_warning "Maintenance integration test not found: $maintenance_integration"
    fi
    
    # Test wrapper scripts
    info "Testing maintenance wrapper scripts..."
    local wrapper_dir="$PROJECT_ROOT/scripts"
    local wrapper_count=0
    
    for wrapper in "$wrapper_dir"/*-wrapper.sh; do
        if [ -f "$wrapper" ]; then
            ((wrapper_count++))
            local wrapper_name=$(basename "$wrapper")
            
            # Test wrapper syntax
            if bash -n "$wrapper"; then
                success "Wrapper syntax valid: $wrapper_name"
            else
                log_error "Wrapper syntax error: $wrapper_name"
                exit_code=1
            fi
            
            # Test wrapper help
            if timeout 10s "$wrapper" --help >/dev/null 2>&1; then
                success "Wrapper help works: $wrapper_name"
            else
                log_warning "Wrapper help timeout: $wrapper_name"
            fi
        fi
    done
    
    info "Tested $wrapper_count wrapper scripts"
    
    # Update results
    update_test_results "maintenance" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# SMOKE TESTS
# =============================================================================

run_smoke_tests() {
    log "Running smoke tests..."
    
    local exit_code=0
    
    # Test basic script functionality
    info "Testing basic script functionality..."
    
    local scripts=(
        "$PROJECT_ROOT/tools/validate-config.sh"
        "$PROJECT_ROOT/scripts/config-manager.sh"
        "$PROJECT_ROOT/scripts/security-validation.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            info "Testing $(basename "$script")..."
            
            # Test help function
            if timeout 10s "$script" --help >/dev/null 2>&1; then
                success "$(basename "$script") help function works"
            else
                log_warning "$(basename "$script") help function failed"
            fi
            
            # Test syntax
            if bash -n "$script"; then
                success "$(basename "$script") syntax is valid"
            else
                log_error "$(basename "$script") has syntax errors"
                exit_code=1
            fi
        fi
    done
    
    # Test configuration files
    info "Testing configuration accessibility..."
    
    local config_files=(
        "$PROJECT_ROOT/.gitignore"
        "$PROJECT_ROOT/.editorconfig"
        "$PROJECT_ROOT/Makefile"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            success "$(basename "$config_file") exists and is readable"
        else
            log_error "$(basename "$config_file") is missing"
            exit_code=1
        fi
    done
    
    # Update results
    update_test_results "smoke" "$exit_code"
    
    return $exit_code
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

update_test_results() {
    local category="$1"
    local exit_code="$2"
    local status="passed"
    
    if [ "$exit_code" -ne 0 ]; then
        status="failed"
    fi
    
    # Update results JSON
    if command -v jq >/dev/null 2>&1; then
        local temp_file
        temp_file=$(mktemp)
        
        jq --arg category "$category" \
           --arg status "$status" \
           --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.results[$category] = {
               "status": $status,
               "timestamp": $timestamp,
               "exit_code": "'$exit_code'"
           }' "$RESULTS_FILE" > "$temp_file"
        
        mv "$temp_file" "$RESULTS_FILE"
    fi
}

generate_test_report() {
    log "Generating test report..."
    
    local report_file="$TEST_REPORTS_DIR/test-summary.html"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>GeuseMaker Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .category { margin: 20px 0; padding: 15px; border-left: 4px solid #ccc; }
        .passed { border-left-color: #4CAF50; background: #f1f8e9; }
        .failed { border-left-color: #f44336; background: #ffebee; }
        .warning { border-left-color: #ff9800; background: #fff3e0; }
        .results { margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f5f5f5; }
    </style>
</head>
<body>
    <div class="header">
        <h1>GeuseMaker Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Environment: ${TEST_ENVIRONMENT:-development}</p>
    </div>
    
    <div class="results">
        <h2>Test Results Summary</h2>
        <table>
            <tr><th>Category</th><th>Status</th><th>Description</th></tr>
EOF
    
    # Add test results to HTML
    for category in "${AVAILABLE_TEST_CATEGORIES[@]}"; do
        local description=$(get_test_category_description "$category")
        local status="Not Run"
        local css_class="warning"
        
        # Try to get status from results file
        if [ -f "$RESULTS_FILE" ] && command -v jq >/dev/null 2>&1; then
            local result_status
            result_status=$(jq -r --arg cat "$category" '.results[$cat].status // "not_run"' "$RESULTS_FILE")
            
            case "$result_status" in
                "passed") status="✅ Passed"; css_class="passed" ;;
                "failed") status="❌ Failed"; css_class="failed" ;;
                *) status="⚠️ Not Run"; css_class="warning" ;;
            esac
        fi
        
        cat >> "$report_file" << EOF
            <tr class="$css_class">
                <td>$category</td>
                <td>$status</td>
                <td>$description</td>
            </tr>
EOF
    done
    
    cat >> "$report_file" << 'EOF'
        </table>
    </div>
    
    <div class="category">
        <h3>Report Files</h3>
        <ul>
            <li><a href="test-results.json">Test Results (JSON)</a></li>
            <li><a href="coverage/">Coverage Reports</a></li>
            <li><a href="unit-tests.xml">Unit Test Results (XML)</a></li>
            <li><a href="integration-tests.xml">Integration Test Results (XML)</a></li>
        </ul>
    </div>
</body>
</html>
EOF
    
    success "Test report generated: $report_file"
    info "Open in browser: file://$report_file"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_help() {
    cat << EOF
Comprehensive Test Runner for GeuseMaker

Usage: $0 [options] [test-categories...]

Test Categories:
EOF
    
    for category in "${AVAILABLE_TEST_CATEGORIES[@]}"; do
        printf "  %-12s %s\n" "$category" "$(get_test_category_description "$category")"
    done
    
    cat << EOF

Options:
    --help, -h          Show this help message
    --setup-only        Only set up test environment
    --no-cleanup        Don't clean up after tests
    --parallel          Run tests in parallel where possible
    --report            Generate HTML report after tests
    --coverage          Generate coverage reports
    --environment ENV   Set test environment (default: development)

Examples:
    $0                          Run all test categories
    $0 unit integration         Run only unit and integration tests
    $0 --report smoke           Run smoke tests and generate report
    $0 --coverage unit          Run unit tests with coverage

Environment Variables:
    TEST_ENVIRONMENT    Test environment name (development, staging, production)
    USE_VENV           Use Python virtual environment (default: true)
    PARALLEL_JOBS      Number of parallel jobs (default: auto)

EOF
}

main() {
    local test_categories=()
    local setup_only=false
    local no_cleanup=false
    local generate_report=false
    local run_coverage=false
    local parallel_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --setup-only)
                setup_only=true
                shift
                ;;
            --no-cleanup)
                no_cleanup=true
                shift
                ;;
            --report)
                generate_report=true
                shift
                ;;
            --coverage)
                run_coverage=true
                shift
                ;;
            --parallel)
                parallel_mode=true
                shift
                ;;
            --environment)
                export TEST_ENVIRONMENT="$2"
                shift 2
                ;;
            --*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                # Check if category is valid
                local category_valid=false
                for valid_category in "${AVAILABLE_TEST_CATEGORIES[@]}"; do
                    if [[ "$1" == "$valid_category" ]]; then
                        category_valid=true
                        break
                    fi
                done
                
                if [[ "$category_valid" == "true" ]]; then
                    test_categories+=("$1")
                else
                    log_error "Unknown test category: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Use all categories if none specified
    if [ ${#test_categories[@]} -eq 0 ]; then
        test_categories=("${AVAILABLE_TEST_CATEGORIES[@]}")
    fi
    
    # Setup test environment
    setup_test_environment
    
    if [ "$setup_only" = "true" ]; then
        success "Test environment setup complete"
        exit 0
    fi
    
    # Run tests
    local overall_exit_code=0
    
    log "Running test categories: ${test_categories[*]}"
    
    for category in "${test_categories[@]}"; do
        echo
        log "=== Running $category tests ==="
        
        case "$category" in
            "unit")
                if ! run_unit_tests; then
                    overall_exit_code=1
                fi
                ;;
            "integration")
                if ! run_integration_tests; then
                    overall_exit_code=1
                fi
                ;;
            "security")
                if ! run_security_tests; then
                    overall_exit_code=1
                fi
                ;;
            "performance")
                if ! run_performance_tests; then
                    overall_exit_code=1
                fi
                ;;
            "deployment")
                if ! run_deployment_tests; then
                    overall_exit_code=1
                fi
                ;;
            "smoke")
                if ! run_smoke_tests; then
                    overall_exit_code=1
                fi
                ;;
            "config")
                if ! run_config_tests; then
                    overall_exit_code=1
                fi
                ;;
            "maintenance")
                if ! run_maintenance_tests; then
                    overall_exit_code=1
                fi
                ;;
        esac
    done
    
    # Generate report if requested
    if [ "$generate_report" = "true" ]; then
        generate_test_report
    fi
    
    # Cleanup
    if [ "$no_cleanup" != "true" ]; then
        cleanup_test_environment
    fi
    
    # Final summary
    echo
    if [ $overall_exit_code -eq 0 ]; then
        success "🎉 All tests completed successfully!"
    else
        warning "⚠️  Some tests failed. Check the output above for details."
    fi
    
    info "Test reports available in: $TEST_REPORTS_DIR"
    
    exit $overall_exit_code
}

# Run main function with all arguments
main "$@"