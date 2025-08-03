#!/bin/bash
# Unity Complete System Integration Test
# Tests all 7 phases of Unity implementation

set -euo pipefail

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/lib/utils/test-utils.sh" || exit 1

# Test configuration
TEST_STACK="unity-integration-test-$(date +%s)"
TEST_RESULTS_DIR="$PROJECT_ROOT/test-reports/unity-integration"
PHASE_RESULTS=()
TOTAL_PHASES=7
PASSED_PHASES=0

# Initialize test environment
setup_test() {
    echo "=== Setting up Unity Integration Test ==="
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Create test configuration
    cat > "$TEST_RESULTS_DIR/test-config.yml" << EOF
stack_name: $TEST_STACK
region: us-east-1
environment: test
unity_enabled: true
performance_mode: optimized
EOF
    
    # Initialize Unity system
    export UNITY_CONFIG="$TEST_RESULTS_DIR/test-config.yml"
    export UNITY_TEST_MODE="true"
    
    echo "✓ Test environment configured"
}

# Phase 1: Core Services Validation
test_phase1_core_services() {
    local phase_name="Phase 1: Core Services"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=4
    
    # Test AWS Service
    echo "Testing AWS Service..."
    if "$PROJECT_ROOT/lib/unity/services/aws-service.sh" test; then
        ((tests_passed++))
        echo "✓ AWS Service operational"
    else
        echo "✗ AWS Service failed"
    fi
    
    # Test Docker Service
    echo "Testing Docker Service..."
    if "$PROJECT_ROOT/lib/unity/services/docker-service.sh" test; then
        ((tests_passed++))
        echo "✓ Docker Service operational"
    else
        echo "✗ Docker Service failed"
    fi
    
    # Test Config Service
    echo "Testing Config Service..."
    if "$PROJECT_ROOT/lib/unity/services/config-service.sh" test; then
        ((tests_passed++))
        echo "✓ Config Service operational"
    else
        echo "✗ Config Service failed"
    fi
    
    # Test Monitor Service
    echo "Testing Monitor Service..."
    if "$PROJECT_ROOT/lib/unity/services/monitor-service.sh" test; then
        ((tests_passed++))
        echo "✓ Monitor Service operational"
    else
        echo "✗ Monitor Service failed"
    fi
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# Phase 2: Event-Driven Orchestration
test_phase2_event_orchestration() {
    local phase_name="Phase 2: Event-Driven Orchestration"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=5
    
    # Test Event Bus
    echo "Testing Event Bus..."
    if "$PROJECT_ROOT/lib/unity/events/event-bus.sh" test; then
        ((tests_passed++))
        echo "✓ Event Bus operational"
    else
        echo "✗ Event Bus failed"
    fi
    
    # Test Event Handlers
    echo "Testing Event Handlers..."
    if "$PROJECT_ROOT/lib/unity/events/handlers/test-all-handlers.sh"; then
        ((tests_passed++))
        echo "✓ Event Handlers operational"
    else
        echo "✗ Event Handlers failed"
    fi
    
    # Test Deployment Orchestration
    echo "Testing Deployment Orchestration..."
    if "$PROJECT_ROOT/tests/test-unity-deployment-orchestration.sh" --quick; then
        ((tests_passed++))
        echo "✓ Deployment Orchestration operational"
    else
        echo "✗ Deployment Orchestration failed"
    fi
    
    # Test Reactive Patterns
    echo "Testing Reactive Patterns..."
    if "$PROJECT_ROOT/tests/test-reactive-patterns.sh"; then
        ((tests_passed++))
        echo "✓ Reactive Patterns operational"
    else
        echo "✗ Reactive Patterns failed"
    fi
    
    # Test Rollback Mechanisms
    echo "Testing Rollback Mechanisms..."
    if "$PROJECT_ROOT/tests/test-rollback-mechanisms.sh"; then
        ((tests_passed++))
        echo "✓ Rollback Mechanisms operational"
    else
        echo "✗ Rollback Mechanisms failed"
    fi
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# Phase 3: Plugin Framework
test_phase3_plugin_framework() {
    local phase_name="Phase 3: Plugin Framework"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=6
    
    # Test Plugin Loader
    echo "Testing Plugin Loader..."
    if "$PROJECT_ROOT/lib/unity/plugins/plugin-loader.sh" test; then
        ((tests_passed++))
        echo "✓ Plugin Loader operational"
    else
        echo "✗ Plugin Loader failed"
    fi
    
    # Test Plugin Manager
    echo "Testing Plugin Manager..."
    if "$PROJECT_ROOT/lib/unity/plugins/plugin-manager.sh" test; then
        ((tests_passed++))
        echo "✓ Plugin Manager operational"
    else
        echo "✗ Plugin Manager failed"
    fi
    
    # Test Standard Plugins
    local plugins=("spot-optimizer" "cost-analyzer" "security-validator" "performance-tuner")
    for plugin in "${plugins[@]}"; do
        echo "Testing $plugin plugin..."
        if "$PROJECT_ROOT/lib/unity/plugins/standard/$plugin.sh" test 2>/dev/null; then
            ((tests_passed++))
            echo "✓ $plugin plugin operational"
        else
            echo "✗ $plugin plugin failed"
        fi
    done
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# Phase 4: Configuration Migration
test_phase4_config_migration() {
    local phase_name="Phase 4: Configuration Migration"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=4
    
    # Test Config Migration Script
    echo "Testing Config Migration..."
    if "$PROJECT_ROOT/scripts/unity-config-migration.sh" --test; then
        ((tests_passed++))
        echo "✓ Config Migration operational"
    else
        echo "✗ Config Migration failed"
    fi
    
    # Test Config Validation
    echo "Testing Config Validation..."
    if "$PROJECT_ROOT/lib/unity/services/config-service.sh" validate; then
        ((tests_passed++))
        echo "✓ Config Validation operational"
    else
        echo "✗ Config Validation failed"
    fi
    
    # Test Environment Override
    echo "Testing Environment Override..."
    if ENVIRONMENT=test "$PROJECT_ROOT/lib/unity/services/config-service.sh" test-override; then
        ((tests_passed++))
        echo "✓ Environment Override operational"
    else
        echo "✗ Environment Override failed"
    fi
    
    # Test Dynamic Reloading
    echo "Testing Dynamic Reloading..."
    if "$PROJECT_ROOT/lib/unity/services/config-service.sh" test-reload; then
        ((tests_passed++))
        echo "✓ Dynamic Reloading operational"
    else
        echo "✗ Dynamic Reloading failed"
    fi
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# Phase 5: Performance Optimization
test_phase5_performance() {
    local phase_name="Phase 5: Performance Optimization"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=5
    
    # Test Performance Benchmarks
    echo "Testing Performance Benchmarks..."
    if "$PROJECT_ROOT/tests/test-unity-performance.sh" --quick; then
        ((tests_passed++))
        echo "✓ Performance Benchmarks passed"
    else
        echo "✗ Performance Benchmarks failed"
    fi
    
    # Test Lazy Loading
    echo "Testing Lazy Loading..."
    local start_time=$(date +%s%N)
    "$PROJECT_ROOT/scripts/unity-cli.sh" version >/dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $duration -lt 2000 ]]; then
        ((tests_passed++))
        echo "✓ Lazy Loading operational (${duration}ms)"
    else
        echo "✗ Lazy Loading failed (${duration}ms > 2000ms)"
    fi
    
    # Test Caching System
    echo "Testing Caching System..."
    if "$PROJECT_ROOT/lib/unity/performance/cache-manager.sh" test 2>/dev/null; then
        ((tests_passed++))
        echo "✓ Caching System operational"
    else
        echo "✗ Caching System failed"
    fi
    
    # Test Memory Usage
    echo "Testing Memory Usage..."
    local mem_usage=$(ps aux | grep unity | awk '{sum+=$6} END {print sum/1024}' | cut -d. -f1)
    if [[ ${mem_usage:-0} -lt 100 ]]; then
        ((tests_passed++))
        echo "✓ Memory Usage optimal (${mem_usage:-0}MB < 100MB)"
    else
        echo "✗ Memory Usage excessive (${mem_usage:-0}MB > 100MB)"
    fi
    
    # Test API Call Reduction
    echo "Testing API Call Reduction..."
    if "$PROJECT_ROOT/tests/benchmark-enhancements.sh" --api-calls-only 2>/dev/null; then
        ((tests_passed++))
        echo "✓ API Call Reduction achieved"
    else
        echo "✗ API Call Reduction failed"
    fi
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# Phase 6: Testing Framework
test_phase6_testing_framework() {
    local phase_name="Phase 6: Testing Framework"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=4
    
    # Test Unit Tests
    echo "Testing Unit Test Suite..."
    if "$PROJECT_ROOT/tools/test-runner.sh" unit --quick; then
        ((tests_passed++))
        echo "✓ Unit Tests passed"
    else
        echo "✗ Unit Tests failed"
    fi
    
    # Test Integration Tests
    echo "Testing Integration Test Suite..."
    if "$PROJECT_ROOT/tools/test-runner.sh" integration --quick; then
        ((tests_passed++))
        echo "✓ Integration Tests passed"
    else
        echo "✗ Integration Tests failed"
    fi
    
    # Test Performance Tests
    echo "Testing Performance Test Suite..."
    if "$PROJECT_ROOT/tools/test-runner.sh" performance --quick; then
        ((tests_passed++))
        echo "✓ Performance Tests passed"
    else
        echo "✗ Performance Tests failed"
    fi
    
    # Test Coverage Report
    echo "Testing Coverage Report Generation..."
    if "$PROJECT_ROOT/tools/test-runner.sh" --coverage --quick 2>/dev/null; then
        ((tests_passed++))
        echo "✓ Coverage Report generated"
    else
        echo "✗ Coverage Report failed"
    fi
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# Phase 7: Documentation Consolidation
test_phase7_documentation() {
    local phase_name="Phase 7: Documentation Consolidation"
    echo -e "\n=== Testing $phase_name ==="
    
    local tests_passed=0
    local tests_total=4
    
    # Test Architecture Documentation
    echo "Testing Architecture Documentation..."
    if [[ -f "$PROJECT_ROOT/docs/unity/architecture.md" ]]; then
        ((tests_passed++))
        echo "✓ Architecture Documentation exists"
    else
        echo "✗ Architecture Documentation missing"
    fi
    
    # Test API Documentation
    echo "Testing API Documentation..."
    if [[ -f "$PROJECT_ROOT/docs/unity/api-reference.md" ]]; then
        ((tests_passed++))
        echo "✓ API Documentation exists"
    else
        echo "✗ API Documentation missing"
    fi
    
    # Test Migration Guide
    echo "Testing Migration Guide..."
    if [[ -f "$PROJECT_ROOT/docs/unity/migration-guide.md" ]]; then
        ((tests_passed++))
        echo "✓ Migration Guide exists"
    else
        echo "✗ Migration Guide missing"
    fi
    
    # Test Plugin Development Guide
    echo "Testing Plugin Development Guide..."
    if [[ -f "$PROJECT_ROOT/docs/unity/plugin-development.md" ]]; then
        ((tests_passed++))
        echo "✓ Plugin Development Guide exists"
    else
        echo "✗ Plugin Development Guide missing"
    fi
    
    local result="$phase_name: $tests_passed/$tests_total tests passed"
    PHASE_RESULTS+=("$result")
    
    if [[ $tests_passed -eq $tests_total ]]; then
        ((PASSED_PHASES++))
        echo -e "\n✓ $phase_name PASSED"
        return 0
    else
        echo -e "\n✗ $phase_name FAILED"
        return 1
    fi
}

# End-to-End Integration Test
test_end_to_end_integration() {
    echo -e "\n=== Testing End-to-End Integration ==="
    
    local test_success=true
    
    # 1. Initialize Unity System
    echo "1. Initializing Unity System..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" init --test-mode; then
        echo "✓ Unity System initialized"
    else
        echo "✗ Unity System initialization failed"
        test_success=false
    fi
    
    # 2. Load Configuration
    echo "2. Loading Unity Configuration..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" config load "$UNITY_CONFIG"; then
        echo "✓ Configuration loaded"
    else
        echo "✗ Configuration loading failed"
        test_success=false
    fi
    
    # 3. Start Services
    echo "3. Starting Unity Services..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" services start all; then
        echo "✓ Services started"
    else
        echo "✗ Services startup failed"
        test_success=false
    fi
    
    # 4. Load Plugins
    echo "4. Loading Unity Plugins..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" plugins load all; then
        echo "✓ Plugins loaded"
    else
        echo "✗ Plugin loading failed"
        test_success=false
    fi
    
    # 5. Test Deployment Workflow
    echo "5. Testing Deployment Workflow..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" deploy --dry-run "$TEST_STACK"; then
        echo "✓ Deployment workflow successful"
    else
        echo "✗ Deployment workflow failed"
        test_success=false
    fi
    
    # 6. Test Monitoring
    echo "6. Testing Monitoring Integration..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" monitor status; then
        echo "✓ Monitoring operational"
    else
        echo "✗ Monitoring failed"
        test_success=false
    fi
    
    # 7. Generate Reports
    echo "7. Generating Integration Report..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" report generate integration; then
        echo "✓ Report generated"
    else
        echo "✗ Report generation failed"
        test_success=false
    fi
    
    # 8. Cleanup
    echo "8. Cleaning up Unity System..."
    if "$PROJECT_ROOT/scripts/unity-cli.sh" cleanup --test-mode; then
        echo "✓ Cleanup successful"
    else
        echo "✗ Cleanup failed"
        test_success=false
    fi
    
    if [[ "$test_success" == "true" ]]; then
        echo -e "\n✓ End-to-End Integration PASSED"
        return 0
    else
        echo -e "\n✗ End-to-End Integration FAILED"
        return 1
    fi
}

# Generate Final Report
generate_final_report() {
    local report_file="$TEST_RESULTS_DIR/integration-report.txt"
    
    echo "=== Unity System Integration Test Report ===" > "$report_file"
    echo "Test Date: $(date)" >> "$report_file"
    echo "Test Stack: $TEST_STACK" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "Phase Results:" >> "$report_file"
    echo "-------------" >> "$report_file"
    for result in "${PHASE_RESULTS[@]}"; do
        echo "$result" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    echo "Overall Result: $PASSED_PHASES/$TOTAL_PHASES phases passed" >> "$report_file"
    
    if [[ $PASSED_PHASES -eq $TOTAL_PHASES ]]; then
        echo "Status: SUCCESS" >> "$report_file"
    else
        echo "Status: FAILURE" >> "$report_file"
    fi
    
    # Generate HTML report
    cat > "$TEST_RESULTS_DIR/integration-report.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Unity Integration Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .success { color: green; }
        .failure { color: red; }
        .phase { margin: 10px 0; padding: 10px; border: 1px solid #ddd; }
        .summary { background: #f0f0f0; padding: 15px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Unity System Integration Test Report</h1>
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Date: $(date)</p>
        <p>Stack: $TEST_STACK</p>
        <p>Result: <span class="$([ $PASSED_PHASES -eq $TOTAL_PHASES ] && echo 'success' || echo 'failure')">
            $PASSED_PHASES/$TOTAL_PHASES phases passed
        </span></p>
    </div>
    <h2>Phase Results</h2>
EOF
    
    for result in "${PHASE_RESULTS[@]}"; do
        if [[ "$result" == *"PASSED"* ]]; then
            echo "    <div class='phase success'>$result</div>" >> "$TEST_RESULTS_DIR/integration-report.html"
        else
            echo "    <div class='phase failure'>$result</div>" >> "$TEST_RESULTS_DIR/integration-report.html"
        fi
    done
    
    echo "</body></html>" >> "$TEST_RESULTS_DIR/integration-report.html"
    
    echo -e "\n=== Test Reports Generated ==="
    echo "Text Report: $report_file"
    echo "HTML Report: $TEST_RESULTS_DIR/integration-report.html"
}

# Main test execution
main() {
    echo "=== Unity Complete System Integration Test ==="
    echo "Testing all 7 phases of Unity implementation"
    echo "============================================="
    
    # Setup
    setup_test
    
    # Run all phase tests
    test_phase1_core_services || true
    test_phase2_event_orchestration || true
    test_phase3_plugin_framework || true
    test_phase4_config_migration || true
    test_phase5_performance || true
    test_phase6_testing_framework || true
    test_phase7_documentation || true
    
    # Run end-to-end integration test
    test_end_to_end_integration || true
    
    # Generate final report
    generate_final_report
    
    # Final summary
    echo -e "\n=== Integration Test Complete ==="
    echo "Total Phases: $TOTAL_PHASES"
    echo "Passed Phases: $PASSED_PHASES"
    
    if [[ $PASSED_PHASES -eq $TOTAL_PHASES ]]; then
        echo -e "\n✓ ALL PHASES PASSED - Unity System is fully operational!"
        return 0
    else
        echo -e "\n✗ Some phases failed - Review the report for details"
        return 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi