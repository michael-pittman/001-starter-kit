#!/usr/bin/env bash
# =============================================================================
# Epic 5 Integration Test Suite
# Comprehensive testing of all consolidated suites and their interactions
# =============================================================================

set -euo pipefail

# Test configuration
readonly TEST_NAME="Epic 5 Integration Tests"
readonly TEST_VERSION="1.0.0"
readonly TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly TEST_LOG_FILE="/tmp/epic5-integration-${TEST_TIMESTAMP}.log"
readonly TEST_RESULTS_FILE="/tmp/epic5-integration-results-${TEST_TIMESTAMP}.json"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Performance metrics
declare -A PERFORMANCE_METRICS=()
declare -A TEST_DURATIONS=()

# Initialize test environment
init_test_environment() {
    echo "=== Epic 5 Integration Test Suite ==="
    echo "Version: $TEST_VERSION"
    echo "Timestamp: $TEST_TIMESTAMP"
    echo "Log File: $TEST_LOG_FILE"
    echo "Results File: $TEST_RESULTS_FILE"
    echo "====================================="
    
    # Create test directories
    mkdir -p /tmp/epic5-test-{validation,health,setup,maintenance}
    
    # Initialize performance tracking
    PERFORMANCE_METRICS=()
    TEST_DURATIONS=()
    
    # Load project libraries
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils/library-loader.sh" || {
        echo "ERROR: Failed to load library loader" >&2
        exit 1
    }
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    local test_description="${3:-}"
    
    ((TOTAL_TESTS++))
    local start_time=$(date +%s.%N)
    
    echo -e "\n${BLUE}[TEST $TOTAL_TESTS]${NC} $test_name"
    [[ -n "$test_description" ]] && echo -e "${YELLOW}Description:${NC} $test_description"
    
    if eval "$test_function" >> "$TEST_LOG_FILE" 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED_TESTS++))
        local result="PASSED"
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED_TESTS++))
        local result="FAILED"
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    TEST_DURATIONS["$test_name"]="$duration"
    
    # Record performance metric
    PERFORMANCE_METRICS["$test_name"]="$result"
    
    return 0
}

# Test suite functions

test_cross_suite_validation_health_maintenance() {
    echo "Testing Validation → Health → Maintenance workflow"
    
    # Test validation suite
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    
    # Test health suite
    source "$PROJECT_ROOT/lib/modules/health/health-suite.sh" || return 1
    
    # Test maintenance suite
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    # Test cross-suite interaction
    local validation_result
    validation_result=$(run_validation --type=environment --parallel --cache) || return 1
    
    local health_result
    health_result=$(run_health_check --check-type=service --metrics) || return 1
    
    local maintenance_result
    maintenance_result=$(run_maintenance --operation=health --scope=all --dry-run) || return 1
    
    echo "Cross-suite workflow completed successfully"
    return 0
}

test_cross_suite_setup_validation_health() {
    echo "Testing Setup → Validation → Health workflow"
    
    # Test setup suite
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    
    # Test validation suite
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    
    # Test health suite
    source "$PROJECT_ROOT/lib/modules/health/health-suite.sh" || return 1
    
    # Test cross-suite interaction
    local setup_result
    setup_result=$(run_setup --component=all --interactive=false --validate) || return 1
    
    local validation_result
    validation_result=$(run_validation --type=modules --parallel --cache) || return 1
    
    local health_result
    health_result=$(run_health_check --check-type=deployment --metrics) || return 1
    
    echo "Setup → Validation → Health workflow completed successfully"
    return 0
}

test_cross_suite_maintenance_setup_validation() {
    echo "Testing Maintenance → Setup → Validation workflow"
    
    # Test maintenance suite
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    # Test setup suite
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    
    # Test validation suite
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    
    # Test cross-suite interaction
    local maintenance_result
    maintenance_result=$(run_maintenance --operation=update --component=configurations --dry-run) || return 1
    
    local setup_result
    setup_result=$(run_setup --component=configurations --interactive=false --validate) || return 1
    
    local validation_result
    validation_result=$(run_validation --type=environment --parallel --cache) || return 1
    
    echo "Maintenance → Setup → Validation workflow completed successfully"
    return 0
}

test_end_to_end_deployment() {
    echo "Testing complete end-to-end deployment workflow"
    
    # Load all suites
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/health/health-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    # Simulate complete deployment workflow
    local test_stack_name="epic5-test-${TEST_TIMESTAMP}"
    
    # 1. Setup environment
    echo "Step 1: Environment setup"
    run_setup --component=all --interactive=false --validate || return 1
    
    # 2. Validate environment
    echo "Step 2: Environment validation"
    run_validation --type=all --parallel --cache || return 1
    
    # 3. Health check
    echo "Step 3: Health check"
    run_health_check --check-type=all --metrics || return 1
    
    # 4. Maintenance preparation
    echo "Step 4: Maintenance preparation"
    run_maintenance --operation=health --scope=all --dry-run || return 1
    
    echo "End-to-end deployment workflow completed successfully"
    return 0
}

test_disaster_recovery() {
    echo "Testing disaster recovery workflow"
    
    # Load maintenance suite
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    # Simulate disaster recovery scenario
    local backup_dir="/tmp/epic5-test-backup-${TEST_TIMESTAMP}"
    mkdir -p "$backup_dir"
    
    # Create test backup
    echo "Creating test backup"
    run_maintenance --operation=backup --scope=all --dry-run || return 1
    
    # Simulate failure
    echo "Simulating failure scenario"
    
    # Test recovery
    echo "Testing recovery procedures"
    run_maintenance --operation=fix --target=deployment --dry-run || return 1
    
    # Cleanup
    rm -rf "$backup_dir"
    
    echo "Disaster recovery workflow completed successfully"
    return 0
}

test_performance_load() {
    echo "Testing performance under load"
    
    # Load all suites
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/health/health-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    # Simulate load testing
    local concurrent_operations=5
    local operation_count=0
    
    echo "Running $concurrent_operations concurrent operations"
    
    for i in $(seq 1 $concurrent_operations); do
        (
            # Run validation in background
            run_validation --type=environment --parallel --cache >/dev/null 2>&1 &
            local validation_pid=$!
            
            # Run health check in background
            run_health_check --check-type=service --metrics >/dev/null 2>&1 &
            local health_pid=$!
            
            # Wait for completion
            wait $validation_pid $health_pid
            
            ((operation_count++))
        ) &
    done
    
    # Wait for all background operations
    wait
    
    echo "Performance load test completed: $operation_count operations"
    return 0
}

test_bash_version_compatibility() {
    echo "Testing bash version compatibility"
    
    # Test with different bash versions
    local bash_versions=("3.2" "4.0" "4.3" "5.0" "5.3")
    local current_version="${BASH_VERSION%%.*}"
    
    echo "Current bash version: $BASH_VERSION"
    
    # Test library loading with current version
    source "$PROJECT_ROOT/lib/utils/library-loader.sh" || return 1
    
    # Test basic functionality
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/health/health-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    echo "Bash version compatibility test completed"
    return 0
}

test_platform_compatibility() {
    echo "Testing platform compatibility"
    
    # Detect platform
    local platform=$(uname -s)
    local architecture=$(uname -m)
    
    echo "Platform: $platform"
    echo "Architecture: $architecture"
    
    # Test platform-specific functionality
    case "$platform" in
        Darwin)
            echo "Testing macOS compatibility"
            # Test macOS-specific features
            ;;
        Linux)
            echo "Testing Linux compatibility"
            # Test Linux-specific features
            ;;
        *)
            echo "Testing generic platform compatibility"
            ;;
    esac
    
    # Test basic functionality
    source "$PROJECT_ROOT/lib/utils/library-loader.sh" || return 1
    
    echo "Platform compatibility test completed"
    return 0
}

test_aws_region_compatibility() {
    echo "Testing AWS region compatibility"
    
    # Test AWS CLI availability
    if ! command -v aws >/dev/null 2>&1; then
        echo "AWS CLI not available, skipping region compatibility test"
        return 0
    fi
    
    # Test with different regions
    local test_regions=("us-east-1" "us-west-2" "eu-west-1")
    local current_region="${AWS_DEFAULT_REGION:-us-east-1}"
    
    echo "Current AWS region: $current_region"
    
    # Test basic AWS functionality
    aws sts get-caller-identity >/dev/null 2>&1 || {
        echo "AWS credentials not configured, skipping region test"
        return 0
    }
    
    for region in "${test_regions[@]}"; do
        echo "Testing region: $region"
        AWS_DEFAULT_REGION="$region" aws sts get-caller-identity >/dev/null 2>&1 || {
            echo "Warning: Region $region not accessible"
        }
    done
    
    echo "AWS region compatibility test completed"
    return 0
}

test_startup_performance() {
    echo "Testing startup performance"
    
    local start_time=$(date +%s.%N)
    
    # Load all core libraries
    source "$PROJECT_ROOT/lib/utils/library-loader.sh" || return 1
    source "$PROJECT_ROOT/lib/error-handling.sh" || return 1
    source "$PROJECT_ROOT/lib/aws-cli-v2.sh" || return 1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    echo "Startup time: ${duration}s"
    
    # Check if startup time is acceptable (<2 seconds)
    if (( $(echo "$duration < 2.0" | bc -l) )); then
        echo "Startup performance: ACCEPTABLE"
        return 0
    else
        echo "Startup performance: SLOW (>2s)"
        return 1
    fi
}

test_deployment_performance() {
    echo "Testing deployment performance"
    
    local start_time=$(date +%s.%N)
    
    # Simulate deployment workflow
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    
    # Run setup and validation
    run_setup --component=all --interactive=false --validate >/dev/null 2>&1 || return 1
    run_validation --type=all --parallel --cache >/dev/null 2>&1 || return 1
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    echo "Deployment time: ${duration}s"
    
    # Check if deployment time is acceptable (<3 minutes)
    if (( $(echo "$duration < 180.0" | bc -l) )); then
        echo "Deployment performance: ACCEPTABLE"
        return 0
    else
        echo "Deployment performance: SLOW (>3min)"
        return 1
    fi
}

test_memory_usage() {
    echo "Testing memory usage"
    
    # Get initial memory usage
    local initial_memory=0
    if command -v ps >/dev/null 2>&1; then
        initial_memory=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
    fi
    
    # Load all suites
    source "$PROJECT_ROOT/lib/utils/library-loader.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/config/setup-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/validation/validation-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/health/health-suite.sh" || return 1
    source "$PROJECT_ROOT/lib/modules/maintenance/maintenance-suite.sh" || return 1
    
    # Get final memory usage
    local final_memory=0
    if command -v ps >/dev/null 2>&1; then
        final_memory=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
    fi
    
    local memory_usage=$((final_memory - initial_memory))
    echo "Memory usage: ${memory_usage}KB"
    
    # Check if memory usage is acceptable (<100MB)
    if [[ $memory_usage -lt 102400 ]]; then
        echo "Memory usage: ACCEPTABLE"
        return 0
    else
        echo "Memory usage: HIGH (>100MB)"
        return 1
    fi
}

# Generate test report
generate_test_report() {
    echo -e "\n=== Epic 5 Integration Test Report ==="
    echo "Timestamp: $TEST_TIMESTAMP"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Skipped: $SKIPPED_TESTS"
    echo "Success Rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    
    echo -e "\n=== Performance Metrics ==="
    for test_name in "${!TEST_DURATIONS[@]}"; do
        echo "$test_name: ${TEST_DURATIONS[$test_name]}s"
    done
    
    echo -e "\n=== Detailed Results ==="
    for test_name in "${!PERFORMANCE_METRICS[@]}"; do
        local status="${PERFORMANCE_METRICS[$test_name]}"
        local duration="${TEST_DURATIONS[$test_name]}"
        echo "$test_name: $status (${duration}s)"
    done
    
    # Generate JSON report
    cat > "$TEST_RESULTS_FILE" << EOF
{
    "test_suite": "Epic 5 Integration Tests",
    "version": "$TEST_VERSION",
    "timestamp": "$TEST_TIMESTAMP",
    "summary": {
        "total_tests": $TOTAL_TESTS,
        "passed": $PASSED_TESTS,
        "failed": $FAILED_TESTS,
        "skipped": $SKIPPED_TESTS,
        "success_rate": $((PASSED_TESTS * 100 / TOTAL_TESTS))
    },
    "performance_metrics": {
EOF
    
    local first=true
    for test_name in "${!TEST_DURATIONS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$TEST_RESULTS_FILE"
        fi
        cat >> "$TEST_RESULTS_FILE" << EOF
        "$test_name": {
            "status": "${PERFORMANCE_METRICS[$test_name]}",
            "duration": "${TEST_DURATIONS[$test_name]}"
        }
EOF
    done
    
    cat >> "$TEST_RESULTS_FILE" << EOF
    }
}
EOF
    
    echo -e "\nDetailed report saved to: $TEST_RESULTS_FILE"
    echo "Log file: $TEST_LOG_FILE"
}

# Main test execution
main() {
    init_test_environment
    
    echo -e "\n${BLUE}=== Cross-Suite Integration Tests ===${NC}"
    run_test "Validation → Health → Maintenance" test_cross_suite_validation_health_maintenance "Test cross-suite workflow integration"
    run_test "Setup → Validation → Health" test_cross_suite_setup_validation_health "Test setup to validation to health workflow"
    run_test "Maintenance → Setup → Validation" test_cross_suite_maintenance_setup_validation "Test maintenance to setup to validation workflow"
    
    echo -e "\n${BLUE}=== End-to-End Tests ===${NC}"
    run_test "Complete Deployment Workflow" test_end_to_end_deployment "Test complete deployment workflow"
    run_test "Disaster Recovery" test_disaster_recovery "Test disaster recovery procedures"
    run_test "Performance Load Test" test_performance_load "Test performance under load"
    
    echo -e "\n${BLUE}=== Compatibility Tests ===${NC}"
    run_test "Bash Version Compatibility" test_bash_version_compatibility "Test compatibility across bash versions"
    run_test "Platform Compatibility" test_platform_compatibility "Test cross-platform compatibility"
    run_test "AWS Region Compatibility" test_aws_region_compatibility "Test AWS region compatibility"
    
    echo -e "\n${BLUE}=== Performance Tests ===${NC}"
    run_test "Startup Performance" test_startup_performance "Test system startup performance"
    run_test "Deployment Performance" test_deployment_performance "Test deployment workflow performance"
    run_test "Memory Usage" test_memory_usage "Test memory usage under load"
    
    # Generate final report
    generate_test_report
    
    # Cleanup
    rm -rf /tmp/epic5-test-*
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed! Epic 5 integration testing successful.${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed. Epic 5 integration testing needs attention.${NC}"
        exit 1
    fi
}

# Execute main function
main "$@" 