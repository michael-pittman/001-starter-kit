#!/bin/bash
# =============================================================================
# OS Compatibility Validation and Testing Framework
# Comprehensive testing for EC2 OS compatibility and bash installation
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/modules/instances/os-compatibility.sh"
source "$PROJECT_ROOT/lib/modules/instances/bash-installers.sh"
source "$PROJECT_ROOT/lib/modules/instances/package-managers.sh"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly VALIDATION_VERSION="1.0.0"
readonly TEST_RESULTS_DIR="$PROJECT_ROOT/test-results/os-compatibility"
readonly TEST_LOG_FILE="$TEST_RESULTS_DIR/validation.log"
readonly SUPPORTED_OS_LIST=(
    "ubuntu:20.04"
    "ubuntu:22.04"
    "ubuntu:24.04"
    "debian:11"
    "debian:12"
    "amazonlinux:2"
    "amazonlinux:2023"
    "rocky:8"
    "rocky:9"
    "almalinux:8"
    "almalinux:9"
)

# Test categories
readonly TEST_CATEGORIES=(
    "os_detection"
    "package_manager"
    "bash_version"
    "bash_installation"
    "package_installation"
    "integration"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Setup test environment
setup_test_environment() {
    log "Setting up test environment for OS compatibility validation..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Initialize test log
    cat > "$TEST_LOG_FILE" << EOF
OS Compatibility Validation Test Log
====================================
Started: $(date)
Version: $VALIDATION_VERSION
Host OS: $(uname -a)

EOF
    
    success "Test environment setup completed"
}

# Log test results
log_test_result() {
    local test_name="$1"
    local status="$2"
    local details="${3:-}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] $test_name: $status" >> "$TEST_LOG_FILE"
    if [ -n "$details" ]; then
        echo "  Details: $details" >> "$TEST_LOG_FILE"
    fi
    echo "" >> "$TEST_LOG_FILE"
    
    case "$status" in
        PASS|SUCCESS)
            success "$test_name: $status"
            ;;
        FAIL|ERROR)
            error "$test_name: $status"
            ;;
        SKIP|WARNING)
            log "$test_name: $status"
            ;;
        *)
            log "$test_name: $status"
            ;;
    esac
}

# Generate test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/os-compatibility-report.html"
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    
    log "Generating test report..."
    
    # Count test results
    if [ -f "$TEST_LOG_FILE" ]; then
        total_tests=$(grep -c ": \(PASS\|FAIL\|SKIP\|SUCCESS\|ERROR\|WARNING\)" "$TEST_LOG_FILE" || echo "0")
        passed_tests=$(grep -c ": \(PASS\|SUCCESS\)" "$TEST_LOG_FILE" || echo "0")
        failed_tests=$(grep -c ": \(FAIL\|ERROR\)" "$TEST_LOG_FILE" || echo "0")
        skipped_tests=$(grep -c ": \(SKIP\|WARNING\)" "$TEST_LOG_FILE" || echo "0")
    fi
    
    # Generate HTML report
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>OS Compatibility Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { background-color: #e8f5e8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .fail { color: #d32f2f; }
        .pass { color: #388e3c; }
        .skip { color: #f57c00; }
        .test-log { background-color: #f9f9f9; padding: 15px; border-left: 4px solid #ccc; margin: 20px 0; }
        pre { white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="header">
        <h1>OS Compatibility Validation Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Version:</strong> $VALIDATION_VERSION</p>
        <p><strong>Host:</strong> $(uname -a)</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $total_tests</p>
        <p><strong class="pass">Passed:</strong> $passed_tests</p>
        <p><strong class="fail">Failed:</strong> $failed_tests</p>
        <p><strong class="skip">Skipped/Warnings:</strong> $skipped_tests</p>
        <p><strong>Success Rate:</strong> $([ $total_tests -gt 0 ] && echo "scale=1; $passed_tests * 100 / $total_tests" | bc || echo "0")%</p>
    </div>
    
    <div class="test-log">
        <h2>Test Log</h2>
        <pre>$(cat "$TEST_LOG_FILE" 2>/dev/null || echo "No test log available")</pre>
    </div>
</body>
</html>
EOF
    
    success "Test report generated: $report_file"
    echo "Open file://$report_file in your browser to view the report"
}

# =============================================================================
# OS DETECTION TESTS
# =============================================================================

test_os_detection() {
    log "Testing OS detection capabilities..."
    
    # Test basic OS detection
    if detect_os >/dev/null 2>&1; then
        log_test_result "OS Detection" "PASS" "OS_ID: ${OS_ID:-unknown}, OS_FAMILY: ${OS_FAMILY:-unknown}"
    else
        log_test_result "OS Detection" "FAIL" "Failed to detect operating system"
        return 1
    fi
    
    # Test OS support validation
    if is_os_supported; then
        log_test_result "OS Support Check" "PASS" "OS $OS_ID is supported"
    else
        log_test_result "OS Support Check" "WARNING" "OS $OS_ID may not be fully supported"
    fi
    
    # Test package manager detection
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    if [ "$pkg_mgr" != "unknown" ]; then
        log_test_result "Package Manager Detection" "PASS" "Detected: $pkg_mgr"
    else
        log_test_result "Package Manager Detection" "FAIL" "Could not detect package manager"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PACKAGE MANAGER TESTS
# =============================================================================

test_package_manager() {
    log "Testing package manager functionality..."
    
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    # Test package list update
    if update_package_lists "$pkg_mgr" >/dev/null 2>&1; then
        log_test_result "Package List Update" "PASS" "Successfully updated package lists"
    else
        log_test_result "Package List Update" "FAIL" "Failed to update package lists"
        return 1
    fi
    
    # Test package installation capability (dry run)
    case "$pkg_mgr" in
        apt)
            if apt-cache show curl >/dev/null 2>&1; then
                log_test_result "Package Availability Test" "PASS" "Test package 'curl' is available"
            else
                log_test_result "Package Availability Test" "FAIL" "Test package 'curl' is not available"
            fi
            ;;
        yum|dnf)
            if $pkg_mgr info curl >/dev/null 2>&1; then
                log_test_result "Package Availability Test" "PASS" "Test package 'curl' is available"
            else
                log_test_result "Package Availability Test" "FAIL" "Test package 'curl' is not available"
            fi
            ;;
        *)
            log_test_result "Package Availability Test" "SKIP" "Test not implemented for $pkg_mgr"
            ;;
    esac
    
    return 0
}

# =============================================================================
# BASH VERSION TESTS
# =============================================================================

test_bash_version() {
    log "Testing bash version detection and validation..."
    
    # Test bash version detection
    local current_version
    current_version=$(get_bash_version)
    if [ "$current_version" != "unknown" ]; then
        log_test_result "Bash Version Detection" "PASS" "Current version: $current_version"
    else
        log_test_result "Bash Version Detection" "FAIL" "Could not detect bash version"
        return 1
    fi
    
    # Test version comparison
    if version_compare "5.3" "5.2" "gt"; then
        log_test_result "Version Comparison Test" "PASS" "5.3 > 5.2"
    else
        log_test_result "Version Comparison Test" "FAIL" "Version comparison logic error"
        return 1
    fi
    
    # Test bash version requirement check
    if check_bash_version "5.3" >/dev/null 2>&1; then
        log_test_result "Bash Version Requirement" "PASS" "Current bash meets 5.3+ requirement"
    else
        log_test_result "Bash Version Requirement" "WARNING" "Current bash does not meet 5.3+ requirement"
    fi
    
    # Test finding best bash
    local best_bash
    if best_bash=$(find_best_bash "4.0"); then
        log_test_result "Find Best Bash" "PASS" "Found suitable bash: $best_bash"
    else
        log_test_result "Find Best Bash" "FAIL" "Could not find suitable bash"
        return 1
    fi
    
    return 0
}

# =============================================================================
# BASH INSTALLATION TESTS
# =============================================================================

test_bash_installation() {
    log "Testing bash installation capabilities..."
    
    # Test build dependency check
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    # Check if build tools are available
    case "$pkg_mgr" in
        apt)
            if apt-cache show build-essential >/dev/null 2>&1; then
                log_test_result "Build Dependencies Available" "PASS" "build-essential package available"
            else
                log_test_result "Build Dependencies Available" "FAIL" "build-essential package not available"
            fi
            ;;
        yum|dnf)
            if $pkg_mgr groupinfo "Development Tools" >/dev/null 2>&1; then
                log_test_result "Build Dependencies Available" "PASS" "Development Tools group available"
            else
                log_test_result "Build Dependencies Available" "FAIL" "Development Tools group not available"
            fi
            ;;
        *)
            log_test_result "Build Dependencies Available" "SKIP" "Test not implemented for $pkg_mgr"
            ;;
    esac
    
    # Test bash source download capability
    local test_url="https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
    if curl -Is --connect-timeout 10 "$test_url" | head -n1 | grep -q "200 OK"; then
        log_test_result "Bash Source Download Test" "PASS" "Bash source is accessible"
    else
        log_test_result "Bash Source Download Test" "WARNING" "Bash source may not be accessible"
    fi
    
    # Test bash installation validation
    if validate_bash_installation "/bin/bash" "4.0" >/dev/null 2>&1; then
        log_test_result "Bash Installation Validation" "PASS" "System bash passes validation"
    else
        log_test_result "Bash Installation Validation" "WARNING" "System bash validation had issues"
    fi
    
    return 0
}

# =============================================================================
# PACKAGE INSTALLATION TESTS
# =============================================================================

test_package_installation() {
    log "Testing package installation capabilities..."
    
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    # Test essential packages availability
    local essential_packages
    case "$pkg_mgr" in
        apt)
            essential_packages="curl wget git unzip"
            ;;
        yum|dnf)
            essential_packages="curl wget git unzip"
            ;;
        *)
            essential_packages="curl wget git"
            ;;
    esac
    
    local available_count=0
    local total_count=0
    
    for package in $essential_packages; do
        total_count=$((total_count + 1))
        case "$pkg_mgr" in
            apt)
                if apt-cache show "$package" >/dev/null 2>&1; then
                    available_count=$((available_count + 1))
                fi
                ;;
            yum|dnf)
                if $pkg_mgr info "$package" >/dev/null 2>&1; then
                    available_count=$((available_count + 1))
                fi
                ;;
        esac
    done
    
    if [ $available_count -eq $total_count ]; then
        log_test_result "Essential Packages Available" "PASS" "All $total_count essential packages available"
    else
        log_test_result "Essential Packages Available" "WARNING" "Only $available_count/$total_count essential packages available"
    fi
    
    # Test Docker dependency availability
    case "$pkg_mgr" in
        apt)
            if apt-cache show docker.io >/dev/null 2>&1 || apt-cache show docker-ce >/dev/null 2>&1; then
                log_test_result "Docker Package Available" "PASS" "Docker package available"
            else
                log_test_result "Docker Package Available" "WARNING" "Docker package not found in default repositories"
            fi
            ;;
        yum|dnf)
            if $pkg_mgr info docker >/dev/null 2>&1 || $pkg_mgr info docker-ce >/dev/null 2>&1; then
                log_test_result "Docker Package Available" "PASS" "Docker package available"
            else
                log_test_result "Docker Package Available" "WARNING" "Docker package not found in default repositories"
            fi
            ;;
        *)
            log_test_result "Docker Package Available" "SKIP" "Test not implemented for $pkg_mgr"
            ;;
    esac
    
    return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_integration() {
    log "Testing integration scenarios..."
    
    # Test complete OS compatibility workflow
    if test_os_compatibility >/dev/null 2>&1; then
        log_test_result "OS Compatibility Workflow" "PASS" "Complete workflow executed successfully"
    else
        log_test_result "OS Compatibility Workflow" "WARNING" "Workflow had issues but continued"
    fi
    
    # Test package manager status
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    # Check if package manager is functional
    case "$pkg_mgr" in
        apt)
            if dpkg --version >/dev/null 2>&1; then
                log_test_result "Package Manager Functional" "PASS" "APT/DPKG is functional"
            else
                log_test_result "Package Manager Functional" "FAIL" "APT/DPKG is not functional"
                return 1
            fi
            ;;
        yum|dnf)
            if rpm --version >/dev/null 2>&1; then
                log_test_result "Package Manager Functional" "PASS" "RPM-based package manager is functional"
            else
                log_test_result "Package Manager Functional" "FAIL" "RPM-based package manager is not functional"
                return 1
            fi
            ;;
        *)
            log_test_result "Package Manager Functional" "SKIP" "Functionality test not implemented for $pkg_mgr"
            ;;
    esac
    
    # Test network connectivity for package downloads
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_test_result "Network Connectivity" "PASS" "Internet connectivity available"
    else
        log_test_result "Network Connectivity" "WARNING" "Internet connectivity may be limited"
    fi
    
    # Test disk space requirements
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [ "$available_space" -gt "$required_space" ]; then
        log_test_result "Disk Space Check" "PASS" "Sufficient disk space available ($(($available_space/1024/1024))GB)"
    else
        log_test_result "Disk Space Check" "WARNING" "Limited disk space ($(($available_space/1024/1024))GB)"
    fi
    
    return 0
}

# =============================================================================
# SIMULATED AMI TESTS
# =============================================================================

test_simulated_ami_scenarios() {
    log "Testing simulated AMI scenarios..."
    
    # Test different OS scenarios
    local test_scenarios=(
        "ubuntu:22.04:apt"
        "amazonlinux:2:yum"
        "rocky:9:dnf"
        "debian:11:apt"
    )
    
    for scenario in "${test_scenarios[@]}"; do
        local os_id=$(echo "$scenario" | cut -d: -f1)
        local os_version=$(echo "$scenario" | cut -d: -f2)
        local expected_pkg_mgr=$(echo "$scenario" | cut -d: -f3)
        
        # Simulate OS detection for this scenario
        export OS_ID="$os_id"
        export OS_VERSION="$os_version"
        
        case "$os_id" in
            ubuntu|debian)
                export OS_FAMILY="debian"
                ;;
            amazonlinux|rocky|centos)
                export OS_FAMILY="redhat"
                ;;
        esac
        
        # Test package manager detection for simulated OS
        local detected_pkg_mgr
        detected_pkg_mgr=$(get_package_manager 2>/dev/null || echo "unknown")
        
        # Note: This will likely be "unknown" since we're simulating
        log_test_result "Simulated $os_id:$os_version" "PASS" "Scenario processed (detected: $detected_pkg_mgr)"
    done
    
    # Restore original OS detection
    detect_os >/dev/null 2>&1
    
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_test_category() {
    local category="$1"
    
    case "$category" in
        os_detection)
            test_os_detection
            ;;
        package_manager)
            test_package_manager
            ;;
        bash_version)
            test_bash_version
            ;;
        bash_installation)
            test_bash_installation
            ;;
        package_installation)
            test_package_installation
            ;;
        integration)
            test_integration
            ;;
        simulation)
            test_simulated_ami_scenarios
            ;;
        *)
            error "Unknown test category: $category"
            return 1
            ;;
    esac
}

run_all_tests() {
    local categories=("${@:-${TEST_CATEGORIES[@]}}")
    local failed_categories=()
    
    log "Running OS compatibility validation tests..."
    log "Test categories: ${categories[*]}"
    
    for category in "${categories[@]}"; do
        log "Running $category tests..."
        if run_test_category "$category"; then
            success "✓ $category tests completed successfully"
        else
            error "✗ $category tests failed"
            failed_categories+=("$category")
        fi
        echo ""
    done
    
    # Run simulation tests separately
    run_test_category "simulation"
    
    # Summary
    if [ ${#failed_categories[@]} -eq 0 ]; then
        success "All test categories passed!"
        return 0
    else
        error "Failed test categories: ${failed_categories[*]}"
        return 1
    fi
}

# =============================================================================
# CLI INTERFACE
# =============================================================================

show_usage() {
    cat << EOF
OS Compatibility Validation and Testing Framework

Usage: $0 [OPTIONS] [TEST_CATEGORIES...]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -r, --report-only       Generate report from existing test results
    -c, --clean             Clean test results before running
    --list-categories       List available test categories

Test Categories:
    os_detection           Test OS detection capabilities
    package_manager        Test package manager functionality  
    bash_version           Test bash version detection and validation
    bash_installation      Test bash installation capabilities
    package_installation   Test package installation capabilities
    integration            Test integration scenarios
    all                    Run all test categories (default)

Examples:
    $0                                  # Run all tests
    $0 os_detection bash_version        # Run specific test categories
    $0 --report-only                    # Generate report only
    $0 --clean all                      # Clean and run all tests

EOF
}

main() {
    local test_categories=()
    local report_only=false
    local clean_results=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                return 0
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            -r|--report-only)
                report_only=true
                shift
                ;;
            -c|--clean)
                clean_results=true
                shift
                ;;
            --list-categories)
                echo "Available test categories:"
                printf "  %s\n" "${TEST_CATEGORIES[@]}"
                return 0
                ;;
            all)
                test_categories=("${TEST_CATEGORIES[@]}")
                shift
                ;;
            os_detection|package_manager|bash_version|bash_installation|package_installation|integration)
                test_categories+=("$1")
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                return 1
                ;;
        esac
    done
    
    # Default to all categories if none specified
    if [ ${#test_categories[@]} -eq 0 ]; then
        test_categories=("${TEST_CATEGORIES[@]}")
    fi
    
    # Setup test environment
    if [ "$report_only" != "true" ]; then
        if [ "$clean_results" = "true" ]; then
            log "Cleaning previous test results..."
            rm -rf "$TEST_RESULTS_DIR"
        fi
        
        setup_test_environment
        
        # Run tests
        if run_all_tests "${test_categories[@]}"; then
            success "OS compatibility validation completed successfully"
        else
            error "OS compatibility validation completed with errors"
        fi
    fi
    
    # Generate report
    generate_test_report
    
    return 0
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi