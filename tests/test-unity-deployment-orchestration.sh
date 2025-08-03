#!/bin/bash
# Unity Deployment Orchestration Service Integration Tests
# Tests event-driven deployment workflows, self-healing, scaling, and cost optimization

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test configuration
TEST_STACK_NAME="unity-test-stack-$(date +%s)"
TEST_DEPLOYMENT_ID=""
TEST_LOG_FILE="$PROJECT_ROOT/logs/test-deployment-orchestration.log"
TEST_PASSED=0
TEST_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source Unity components
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
source "$PROJECT_ROOT/lib/unity/core/unity-events.sh"
source "$PROJECT_ROOT/lib/unity/events/reactive-patterns.sh"
source "$PROJECT_ROOT/lib/unity/events/rollback-manager.sh"
source "$PROJECT_ROOT/lib/unity/services/unity-deployment-service.sh"

# Test utilities
log_test() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [TEST:$level] $message" | tee -a "$TEST_LOG_FILE"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ $test_name${NC}"
        ((TEST_PASSED++))
    else
        echo -e "${RED}✗ $test_name${NC}"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        ((TEST_FAILED++))
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓ $test_name${NC}"
        ((TEST_PASSED++))
    else
        echo -e "${RED}✗ $test_name${NC}"
        echo "  File not found: $file"
        ((TEST_FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓ $test_name${NC}"
        ((TEST_PASSED++))
    else
        echo -e "${RED}✗ $test_name${NC}"
        echo "  String not found: $needle"
        echo "  In: $haystack"
        ((TEST_FAILED++))
    fi
}

#############################################
# Test Setup and Teardown
#############################################

setup_test_environment() {
    log_test "INFO" "Setting up test environment..."
    
    # Create test directories
    mkdir -p "$PROJECT_ROOT/logs"
    mkdir -p "$PROJECT_ROOT/.unity/test"
    
    # Initialize Unity core
    unity_init >/dev/null 2>&1
    
    # Initialize event system
    unity_init_events >/dev/null 2>&1
    
    # Initialize reactive patterns
    init_reactive_patterns >/dev/null 2>&1
    
    # Initialize rollback manager
    init_rollback_manager >/dev/null 2>&1
    
    # Initialize deployment service
    unity_deployment_init >/dev/null 2>&1
    
    log_test "INFO" "Test environment setup complete"
}

teardown_test_environment() {
    log_test "INFO" "Cleaning up test environment..."
    
    # Clean up deployment service
    unity_deployment_cleanup >/dev/null 2>&1
    
    # Remove test files
    rm -rf "$PROJECT_ROOT/.unity/test"
    
    log_test "INFO" "Test environment cleanup complete"
}

#############################################
# Service Initialization Tests
#############################################

test_service_initialization() {
    echo -e "\n${YELLOW}Testing Service Initialization...${NC}"
    
    # Test service is initialized
    assert_equals "true" "$UNITY_DEPLOYMENT_SERVICE_INITIALIZED" "Deployment service initialized"
    
    # Test required directories exist
    assert_file_exists "$UNITY_DEPLOYMENT_STATE_DIR" "Deployment state directory exists"
    assert_file_exists "$UNITY_DEPLOYMENT_WORKFLOWS_DIR" "Deployment workflows directory exists"
    assert_file_exists "$UNITY_DEPLOYMENT_METRICS_DIR" "Deployment metrics directory exists"
    
    # Test service validation
    local validation_result
    validation_result=$(unity_deployment_validate 2>&1 && echo "SUCCESS" || echo "FAILED")
    assert_equals "SUCCESS" "$validation_result" "Service validation passes"
}

#############################################
# Deployment Workflow Tests
#############################################

test_deployment_workflows() {
    echo -e "\n${YELLOW}Testing Deployment Workflows...${NC}"
    
    # Test rolling deployment
    log_test "INFO" "Testing rolling deployment workflow..."
    local deployment_id
    deployment_id=$(unity_deployment_execute "deploy" "$TEST_STACK_NAME" "spot" "rolling" 2>/dev/null)
    assert_contains "$deployment_id" "deploy_" "Rolling deployment ID generated"
    TEST_DEPLOYMENT_ID="$deployment_id"
    
    # Test deployment state file created
    assert_file_exists "$UNITY_DEPLOYMENT_STATE_DIR/active/${deployment_id}.state" "Deployment state file created"
    
    # Test blue-green deployment
    log_test "INFO" "Testing blue-green deployment workflow..."
    local bg_deployment_id
    bg_deployment_id=$(unity_deployment_execute "deploy" "${TEST_STACK_NAME}-bg" "spot" "blue-green" 2>/dev/null)
    assert_contains "$bg_deployment_id" "deploy_" "Blue-green deployment ID generated"
    
    # Test canary deployment
    log_test "INFO" "Testing canary deployment workflow..."
    local canary_deployment_id
    canary_deployment_id=$(unity_deployment_execute "deploy" "${TEST_STACK_NAME}-canary" "spot" "canary" 2>/dev/null)
    assert_contains "$canary_deployment_id" "deploy_" "Canary deployment ID generated"
    
    # Test deployment status
    local status_output
    status_output=$(unity_deployment_execute "status" "all" 2>/dev/null)
    assert_contains "$status_output" "Active Deployments:" "Status command shows active deployments"
}

#############################################
# Event-Driven Orchestration Tests
#############################################

test_event_driven_orchestration() {
    echo -e "\n${YELLOW}Testing Event-Driven Orchestration...${NC}"
    
    # Create test event handler to capture events
    local events_captured=0
    capture_deployment_events() {
        local event_type="$1"
        ((events_captured++))
        echo "$event_type" >> "$PROJECT_ROOT/.unity/test/captured_events.log"
    }
    
    # Register event handler
    unity_on_event "deployment\..*" "capture_deployment_events"
    
    # Emit deployment event
    unity_emit_event "deployment.started" "test" "{\"deployment_id\":\"test-123\"}"
    
    # Process events
    unity_process_events 1 >/dev/null 2>&1
    
    # Check events were captured
    sleep 1
    assert_file_exists "$PROJECT_ROOT/.unity/test/captured_events.log" "Events captured to log"
}

#############################################
# Self-Healing Mechanism Tests
#############################################

test_self_healing_mechanisms() {
    echo -e "\n${YELLOW}Testing Self-Healing Mechanisms...${NC}"
    
    # Test health check failure handling
    log_test "INFO" "Testing health check failure handling..."
    unity_emit_event "monitor.service.unhealthy" "test" "{\"service\":\"test-service\",\"status\":\"unhealthy\"}"
    
    # Process events to trigger self-healing
    unity_process_events 1 >/dev/null 2>&1
    
    # Check if self-healing was triggered
    local audit_log="$PROJECT_ROOT/logs/unity/events-audit.log"
    if [[ -f "$audit_log" ]]; then
        local healing_triggered
        healing_triggered=$(grep -c "deployment.self_healing" "$audit_log" 2>/dev/null || echo "0")
        if [[ $healing_triggered -gt 0 ]]; then
            echo -e "${GREEN}✓ Self-healing triggered on service failure${NC}"
            ((TEST_PASSED++))
        else
            echo -e "${RED}✗ Self-healing not triggered on service failure${NC}"
            ((TEST_FAILED++))
        fi
    fi
    
    # Test container failure handling
    log_test "INFO" "Testing container failure handling..."
    unity_emit_event "docker.container.failed" "test" "{\"container_name\":\"test-container\",\"exit_code\":1}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Test spot instance termination handling
    log_test "INFO" "Testing spot instance termination handling..."
    unity_emit_event "aws.ec2.terminated" "test" "{\"instance_id\":\"i-1234567890\",\"reason\":\"spot_interruption\"}"
    unity_process_events 1 >/dev/null 2>&1
}

#############################################
# Dynamic Scaling Tests
#############################################

test_dynamic_scaling() {
    echo -e "\n${YELLOW}Testing Dynamic Scaling...${NC}"
    
    # Test CPU threshold scaling
    log_test "INFO" "Testing CPU-based scaling..."
    unity_emit_event "monitor.metric.collected" "test" "{\"metric\":\"cpu_utilization\",\"value\":85,\"resource_id\":\"test-resource\"}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Check if threshold event was emitted
    unity_emit_event "monitor.threshold.exceeded" "test" "{\"threshold_type\":\"cpu_high\",\"value\":85,\"resource_id\":\"test-resource\"}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Test memory threshold scaling
    log_test "INFO" "Testing memory-based scaling..."
    unity_emit_event "monitor.metric.collected" "test" "{\"metric\":\"memory_utilization\",\"value\":90,\"resource_id\":\"test-resource\"}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Verify scaling policies exist
    assert_file_exists "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/templates/scaling_policies.json" "Scaling policies configured"
}

#############################################
# Cost Optimization Tests
#############################################

test_cost_optimization() {
    echo -e "\n${YELLOW}Testing Cost Optimization...${NC}"
    
    # Test cost threshold handling
    log_test "INFO" "Testing cost threshold exceeded..."
    unity_emit_event "aws.cost.threshold_exceeded" "test" "{\"amount\":1500,\"category\":\"ec2\",\"threshold\":1000}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Test cost analysis completion
    log_test "INFO" "Testing cost analysis recommendations..."
    unity_emit_event "deployment.cost_analysis.completed" "test" "{\"recommendations\":[{\"action\":\"convert_to_spot\",\"savings\":\"70%\"}]}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Verify cost optimization strategies exist
    assert_file_exists "$UNITY_DEPLOYMENT_WORKFLOWS_DIR/templates/cost_optimization.json" "Cost optimization strategies configured"
}

#############################################
# Deployment Strategy Tests
#############################################

test_deployment_strategies() {
    echo -e "\n${YELLOW}Testing Deployment Strategies...${NC}"
    
    # Test blue-green workflow creation
    local bg_workflow_file="$UNITY_DEPLOYMENT_WORKFLOWS_DIR/instances/${TEST_DEPLOYMENT_ID}_blue_green.workflow"
    if [[ -f "$bg_workflow_file" ]]; then
        local bg_content
        bg_content=$(cat "$bg_workflow_file")
        assert_contains "$bg_content" "blue-green" "Blue-green workflow contains strategy"
        assert_contains "$bg_content" "switch_load_balancer_targets" "Blue-green workflow has LB switch step"
    fi
    
    # Test canary workflow creation
    local canary_workflow_file="$UNITY_DEPLOYMENT_WORKFLOWS_DIR/instances/${TEST_DEPLOYMENT_ID}_canary.workflow"
    if [[ -f "$canary_workflow_file" ]]; then
        local canary_content
        canary_content=$(cat "$canary_workflow_file")
        assert_contains "$canary_content" "canary" "Canary workflow contains strategy"
        assert_contains "$canary_content" "canary_config" "Canary workflow has canary configuration"
    fi
}

#############################################
# Rollback Tests
#############################################

test_rollback_mechanisms() {
    echo -e "\n${YELLOW}Testing Rollback Mechanisms...${NC}"
    
    # Test manual rollback
    log_test "INFO" "Testing manual rollback..."
    local rollback_result
    rollback_result=$(unity_deployment_execute "rollback" "$TEST_DEPLOYMENT_ID" "manual" 2>&1 && echo "SUCCESS" || echo "FAILED")
    assert_equals "SUCCESS" "$rollback_result" "Manual rollback initiated"
    
    # Test automatic rollback on failure
    log_test "INFO" "Testing automatic rollback on failure..."
    unity_emit_event "deployment.failed" "test" "{\"deployment_id\":\"test-auto-rollback\",\"rollback_enabled\":true}"
    unity_process_events 1 >/dev/null 2>&1
}

#############################################
# Monitoring and Alerting Tests
#############################################

test_monitoring_alerting() {
    echo -e "\n${YELLOW}Testing Monitoring and Alerting...${NC}"
    
    # Test metric collection
    log_test "INFO" "Testing metric collection..."
    local metrics_dir="$UNITY_DEPLOYMENT_METRICS_DIR"
    assert_file_exists "$metrics_dir" "Metrics directory exists"
    
    # Test health check events
    unity_emit_event "deployment.health_check.started" "test" "{\"deployment_id\":\"$TEST_DEPLOYMENT_ID\"}"
    unity_process_events 1 >/dev/null 2>&1
    
    # Test monitoring configuration
    assert_file_exists "$UNITY_DEPLOYMENT_METRICS_DIR/collection.config" "Metric collection configured"
}

#############################################
# Service Status Tests
#############################################

test_service_status() {
    echo -e "\n${YELLOW}Testing Service Status...${NC}"
    
    # Test deployment service status
    local status_output
    status_output=$(unity_deployment_status 2>/dev/null)
    assert_contains "$status_output" "Unity Deployment Service Status:" "Status command returns service info"
    assert_contains "$status_output" "Initialized: true" "Service shows as initialized"
    assert_contains "$status_output" "Active Deployments:" "Status shows deployment counts"
}

#############################################
# Run All Tests
#############################################

run_all_tests() {
    echo -e "${YELLOW}=== Unity Deployment Orchestration Service Tests ===${NC}"
    echo "Starting tests at $(date)"
    echo ""
    
    # Setup
    setup_test_environment
    
    # Run test suites
    test_service_initialization
    test_deployment_workflows
    test_event_driven_orchestration
    test_self_healing_mechanisms
    test_dynamic_scaling
    test_cost_optimization
    test_deployment_strategies
    test_rollback_mechanisms
    test_monitoring_alerting
    test_service_status
    
    # Teardown
    teardown_test_environment
    
    # Summary
    echo -e "\n${YELLOW}=== Test Summary ===${NC}"
    echo -e "Tests passed: ${GREEN}$TEST_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TEST_FAILED${NC}"
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi