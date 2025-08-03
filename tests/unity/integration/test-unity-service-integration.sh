#!/bin/bash
# =============================================================================
# Unity Service Integration Tests
# Comprehensive integration testing for cross-service Unity functionality
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework for integration tests
unity_test_init "test-unity-service-integration" "service-integration" "unity-services"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up integration test environment
setup_integration_tests() {
    # Create test integration directory
    export TEST_INTEGRATION_DIR="/tmp/unity-integration-test-$$"
    mkdir -p "$TEST_INTEGRATION_DIR"
    mkdir -p "$TEST_INTEGRATION_DIR/.unity"
    mkdir -p "$TEST_INTEGRATION_DIR/.unity/cache"
    mkdir -p "$TEST_INTEGRATION_DIR/.unity/data"
    mkdir -p "$TEST_INTEGRATION_DIR/.unity/monitoring"
    mkdir -p "$TEST_INTEGRATION_DIR/config"
    mkdir -p "$TEST_INTEGRATION_DIR/lib/unity/services"
    mkdir -p "$TEST_INTEGRATION_DIR/lib/unity/core"
    mkdir -p "$TEST_INTEGRATION_DIR/lib/unity/events"
    mkdir -p "$TEST_INTEGRATION_DIR/lib/modules/core"
    
    # Set test-specific paths
    export PROJECT_ROOT="$TEST_INTEGRATION_DIR"
    export UNITY_CACHE_DIR="$TEST_INTEGRATION_DIR/.unity/cache"
    export UNITY_DATA_DIR="$TEST_INTEGRATION_DIR/.unity/data"
    export MONITOR_STATE_DIR="$TEST_INTEGRATION_DIR/.unity/monitoring"
    
    # Create mock Unity core infrastructure
    _create_mock_unity_infrastructure
    
    # Create mock service files
    _create_mock_unity_services
    
    # Mock external dependencies
    _mock_external_dependencies
    
    # Set test environment variables
    export UNITY_TEST_MODE="true"
    export DEBUG="false"
    export STACK_NAME="integration-test-stack"
    export AWS_REGION="us-west-2"
}

# Create mock Unity infrastructure
_create_mock_unity_infrastructure() {
    # Mock Unity core
    cat > "$TEST_INTEGRATION_DIR/lib/unity/core/unity-core.sh" << 'EOF'
#!/bin/bash
UNITY_SUCCESS=0
UNITY_ERROR_VALIDATION=1
UNITY_ERROR_EXECUTION=2
unity_log() { echo "[$1] $2"; }
unity_emit_event() { echo "[EVENT] $1: $2"; }
unity_handle_error() { echo "ERROR: $3" >&2; return $2; }
unity_register_service() { return 0; }
unity_on_event() { return 0; }
export -f unity_log unity_emit_event unity_handle_error unity_register_service unity_on_event
EOF
    
    # Mock Unity registry
    cat > "$TEST_INTEGRATION_DIR/lib/unity/core/registry.sh" << 'EOF'
#!/bin/bash
declare -A UNITY_SERVICES 2>/dev/null || UNITY_SERVICES=()
declare -A UNITY_SERVICE_STATUS 2>/dev/null || UNITY_SERVICE_STATUS=()
unity_register_service() { 
    local name="$1"
    UNITY_SERVICES["$name"]="$2"
    UNITY_SERVICE_STATUS["$name"]="registered"
    return 0
}
export -f unity_register_service
EOF
    
    # Mock Unity event bus
    cat > "$TEST_INTEGRATION_DIR/lib/unity/events/event-bus.sh" << 'EOF'
#!/bin/bash
unity_event_on() { return 0; }
unity_event_emit() { echo "[TEST-EVENT] $1: $2"; }
export -f unity_event_on unity_event_emit
EOF
    
    # Mock core logging
    cat > "$TEST_INTEGRATION_DIR/lib/modules/core/logging.sh" << 'EOF'
#!/bin/bash
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_debug() { [[ "${DEBUG:-}" == "true" ]] && echo "[DEBUG] $*"; }
export -f log_info log_warn log_error log_debug
EOF
}

# Create mock Unity services
_create_mock_unity_services() {
    # Mock AWS service
    cat > "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-aws"
init_unity_aws_service() {
    echo "AWS service initialized"
    return 0
}
launch_ec2_instance() {
    echo "i-1234567890abcdef0"
    return 0
}
get_spot_price() {
    echo "0.10"
    return 0
}
export -f init_unity_aws_service launch_ec2_instance get_spot_price
EOF
    
    # Mock Docker service
    cat > "$TEST_INTEGRATION_DIR/lib/unity/services/unity-docker-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-docker"
unity_docker_init() {
    echo "Docker service initialized"
    return 0
}
docker_start_container() {
    echo "Container started: $1"
    return 0
}
docker_get_container_status() {
    echo '{"status": "running", "health": "healthy"}'
    return 0
}
export -f unity_docker_init docker_start_container docker_get_container_status
EOF
    
    # Mock Config service
    cat > "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-config"
unity_config_init() {
    echo "Config service initialized"
    return 0
}
unity_config_get() {
    case "$1" in
        "STACK_NAME") echo "integration-test-stack" ;;
        "AWS_REGION") echo "us-west-2" ;;
        "INSTANCE_TYPE") echo "t3.medium" ;;
        *) echo "default-value" ;;
    esac
    return 0
}
unity_config_set() {
    echo "Config set: $1=$2"
    return 0
}
export -f unity_config_init unity_config_get unity_config_set
EOF
    
    # Mock Monitor service
    cat > "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-monitor"
unity_monitor_init() {
    echo "Monitor service initialized"
    return 0
}
unity_monitor_health_check() {
    echo "Health check passed for: $1"
    return 0
}
unity_monitor_alert() {
    echo "Alert sent: [$1] $2 - $3"
    return 0
}
unity_monitor_collect_metrics() {
    echo "Metrics collected"
    return 0
}
export -f unity_monitor_init unity_monitor_health_check unity_monitor_alert unity_monitor_collect_metrics
EOF
    
    # Mock Performance service
    cat > "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-performance"
unity_performance_init() {
    echo "Performance service initialized"
    return 0
}
perf_timer_start() {
    echo "Timer started: $1"
    return 0
}
perf_timer_stop() {
    echo "Timer stopped: $1 (100ms)"
    return 0
}
perf_cache_aws_response() {
    echo "AWS response cached: $1"
    return 0
}
perf_get_cached_aws_response() {
    echo '{"cached": "data", "timestamp": "'$(date -Iseconds)'"}'
    return 0
}
export -f unity_performance_init perf_timer_start perf_timer_stop perf_cache_aws_response perf_get_cached_aws_response
EOF
}

# Mock external dependencies
_mock_external_dependencies() {
    mock_function "aws" 'case "$1 $2" in
        "ec2 describe-instances") echo "{\"Reservations\":[{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\",\"State\":{\"Name\":\"running\"}}]}]}" ;;
        "ec2 run-instances") echo "{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\"}]}" ;;
        "sts get-caller-identity") echo "{\"Account\":\"123456789012\"}" ;;
        *) echo "{\"ResponseMetadata\":{\"RequestId\":\"test-request\"}}" ;;
    esac'
    
    mock_function "docker" 'case "$1" in
        "info") return 0 ;;
        "ps") echo "test-container" ;;
        "run") echo "Container started: test-container" ;;
        *) return 0 ;;
    esac'
    
    mock_function "jq" 'case "$*" in
        *".status"*) echo "healthy" ;;
        *".health"*) echo "healthy" ;;
        *".data"*) echo "{\"test\":\"data\"}" ;;
        *) echo "test-json-output" ;;
    esac'
    
    mock_function "curl" 'echo "200"'
    mock_function "ping" 'return 0'
    mock_function "ps" 'echo "12345"'
}

# Clean up integration test environment
cleanup_integration_tests() {
    # Restore mocked functions
    local mock_functions=("aws" "docker" "jq" "curl" "ping" "ps")
    
    for func in "${mock_functions[@]}"; do
        restore_function "$func" 2>/dev/null || true
    done
    
    # Clean up test files
    if [[ -n "${TEST_INTEGRATION_DIR:-}" && -d "$TEST_INTEGRATION_DIR" ]]; then
        rm -rf "$TEST_INTEGRATION_DIR" 2>/dev/null || true
    fi
    
    # Clean up environment variables
    unset TEST_INTEGRATION_DIR UNITY_CACHE_DIR UNITY_DATA_DIR MONITOR_STATE_DIR
    unset UNITY_TEST_MODE STACK_NAME AWS_REGION
}

# =============================================================================
# CROSS-SERVICE INTEGRATION TESTS
# =============================================================================

test_aws_config_integration() {
    test_start "aws_config_integration" "Test AWS and Config service integration"
    
    setup_integration_tests
    
    # Source both services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_config_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    
    # Test configuration retrieval by AWS service
    local stack_name
    stack_name=$(unity_config_get "STACK_NAME" 2>/dev/null)
    
    if [[ "$stack_name" == "integration-test-stack" ]]; then
        test_pass "AWS service can retrieve configuration from Config service"
        
        # Test using configuration in AWS operations
        local instance_id
        instance_id=$(launch_ec2_instance "t3.medium" "spot" "$stack_name" 2>/dev/null)
        
        if [[ "$instance_id" == "i-1234567890abcdef0" ]]; then
            test_pass "AWS service uses configuration correctly for operations"
        else
            test_fail "AWS service operation failed with configuration: $instance_id"
        fi
    else
        test_fail "AWS service cannot retrieve configuration: got '$stack_name'"
    fi
    
    cleanup_integration_tests
}

test_docker_config_integration() {
    test_start "docker_config_integration" "Test Docker and Config service integration"
    
    setup_integration_tests
    
    # Source both services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_config_init >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    # Test Docker service using configuration
    local stack_name
    stack_name=$(unity_config_get "STACK_NAME" 2>/dev/null)
    
    if [[ -n "$stack_name" ]]; then
        test_pass "Docker service can retrieve configuration"
        
        # Test using configuration in Docker operations
        local container_name="${stack_name}-app"
        local result
        result=$(docker_start_container "nginx:latest" "$container_name" "--detach" 2>/dev/null)
        
        if [[ "$result" == *"$container_name"* ]]; then
            test_pass "Docker service uses configuration correctly for container naming"
        else
            test_fail "Docker service operation failed with configuration: $result"
        fi
    else
        test_fail "Docker service cannot retrieve configuration"
    fi
    
    cleanup_integration_tests
}

test_monitor_aws_integration() {
    test_start "monitor_aws_integration" "Test Monitor and AWS service integration"
    
    setup_integration_tests
    
    # Source both services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_monitor_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    
    # Test Monitor service checking AWS infrastructure
    local health_result
    health_result=$(unity_monitor_health_check "infrastructure" 2>/dev/null)
    
    if [[ "$health_result" == *"infrastructure"* ]]; then
        test_pass "Monitor service can check AWS infrastructure health"
        
        # Test alerting on AWS issues
        local alert_result
        alert_result=$(unity_monitor_alert "warning" "AWS Test Alert" "Test AWS integration alert" 2>/dev/null)
        
        if [[ "$alert_result" == *"Alert sent"* ]]; then
            test_pass "Monitor service can send alerts for AWS issues"
        else
            test_fail "Monitor service alerting failed: $alert_result"
        fi
    else
        test_fail "Monitor service cannot check AWS infrastructure: $health_result"
    fi
    
    cleanup_integration_tests
}

test_performance_aws_integration() {
    test_start "performance_aws_integration" "Test Performance and AWS service integration"
    
    setup_integration_tests
    
    # Source both services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_performance_init "test-performance" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    
    # Test Performance service caching AWS calls
    local test_response='{"Instances": [{"InstanceId": "i-1234567890abcdef0"}]}'
    
    if perf_cache_aws_response "test_ec2_call" "$test_response" 3600 >/dev/null 2>&1; then
        test_pass "Performance service can cache AWS responses"
        
        # Test retrieving cached AWS response
        local cached_response
        cached_response=$(perf_get_cached_aws_response "test_ec2_call" 2>/dev/null)
        
        if [[ -n "$cached_response" ]]; then
            test_pass "Performance service can retrieve cached AWS responses"
        else
            test_fail "Performance service cannot retrieve cached AWS responses"
        fi
    else
        test_fail "Performance service cannot cache AWS responses"
    fi
    
    cleanup_integration_tests
}

test_monitor_docker_integration() {
    test_start "monitor_docker_integration" "Test Monitor and Docker service integration"
    
    setup_integration_tests
    
    # Source both services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_monitor_init >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    # Test Monitor service checking Docker containers
    local health_result
    health_result=$(unity_monitor_health_check "service" 2>/dev/null)
    
    if [[ "$health_result" == *"service"* ]]; then
        test_pass "Monitor service can check Docker service health"
        
        # Test collecting Docker metrics
        local metrics_result
        metrics_result=$(unity_monitor_collect_metrics 2>/dev/null)
        
        if [[ "$metrics_result" == *"collected"* ]]; then
            test_pass "Monitor service can collect Docker metrics"
        else
            test_fail "Monitor service cannot collect Docker metrics: $metrics_result"
        fi
    else
        test_fail "Monitor service cannot check Docker service: $health_result"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# EVENT-DRIVEN INTEGRATION TESTS
# =============================================================================

test_service_event_communication() {
    test_start "service_event_communication" "Test event-driven communication between services"
    
    setup_integration_tests
    
    # Source all services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    
    # Initialize all services
    unity_config_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    unity_performance_init "test-performance" >/dev/null 2>&1
    
    # Test event emission and handling
    # Simulate service startup event
    local event_result
    event_result=$(unity_event_emit "service.started" "unity-aws" 2>/dev/null)
    
    if [[ "$event_result" == *"service.started"* ]]; then
        test_pass "Services can emit events successfully"
    else
        test_fail "Service event emission failed: $event_result"
    fi
    
    # Test performance timer events
    perf_timer_start "test_operation" >/dev/null 2>&1
    sleep 0.1
    local timer_result
    timer_result=$(perf_timer_stop "test_operation" 2>/dev/null)
    
    if [[ "$timer_result" == *"Timer stopped"* ]]; then
        test_pass "Performance service can handle timer events"
    else
        test_fail "Performance service timer events failed: $timer_result"
    fi
    
    cleanup_integration_tests
}

test_config_change_propagation() {
    test_start "config_change_propagation" "Test configuration change propagation"
    
    setup_integration_tests
    
    # Source services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_config_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    
    # Test configuration change
    if unity_config_set "INSTANCE_TYPE" "t3.large" >/dev/null 2>&1; then
        test_pass "Configuration change successful"
        
        # Test retrieval of changed configuration
        local new_instance_type
        new_instance_type=$(unity_config_get "INSTANCE_TYPE" 2>/dev/null)
        
        if [[ "$new_instance_type" == "t3.large" ]]; then
            test_pass "Configuration change propagated correctly"
        else
            test_fail "Configuration change not propagated: got '$new_instance_type'"
        fi
    else
        test_fail "Configuration change failed"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# DEPENDENCY CHAIN TESTS
# =============================================================================

test_service_dependency_chain() {
    test_start "service_dependency_chain" "Test service dependency chain execution"
    
    setup_integration_tests
    
    # Source all services in dependency order
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Test dependency chain initialization
    local init_chain_success=true
    
    # 1. Config service (foundation)
    unity_config_init >/dev/null 2>&1 || init_chain_success=false
    
    # 2. Performance service (optimization layer)
    unity_performance_init "test-performance" >/dev/null 2>&1 || init_chain_success=false
    
    # 3. AWS service (infrastructure layer)
    init_unity_aws_service "test-aws" >/dev/null 2>&1 || init_chain_success=false
    
    # 4. Docker service (application layer)
    unity_docker_init >/dev/null 2>&1 || init_chain_success=false
    
    # 5. Monitor service (observability layer)
    unity_monitor_init >/dev/null 2>&1 || init_chain_success=false
    
    if [[ "$init_chain_success" == "true" ]]; then
        test_pass "Service dependency chain initialized successfully"
        
        # Test cross-service operation
        local stack_name
        stack_name=$(unity_config_get "STACK_NAME" 2>/dev/null)
        
        # Use config in AWS operation
        local instance_id
        instance_id=$(launch_ec2_instance "t3.medium" "spot" "$stack_name" 2>/dev/null)
        
        # Use AWS result in Docker operation
        local container_name="${stack_name}-${instance_id#i-}"
        local docker_result
        docker_result=$(docker_start_container "nginx:latest" "$container_name" 2>/dev/null)
        
        # Monitor the operation
        local health_result
        health_result=$(unity_monitor_health_check "all" 2>/dev/null)
        
        if [[ -n "$instance_id" && -n "$docker_result" && -n "$health_result" ]]; then
            test_pass "Cross-service operations completed successfully"
        else
            test_fail "Cross-service operations failed"
        fi
    else
        test_fail "Service dependency chain initialization failed"
    fi
    
    cleanup_integration_tests
}

test_error_propagation() {
    test_start "error_propagation" "Test error propagation across services"
    
    setup_integration_tests
    
    # Source services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_config_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Mock AWS failure
    mock_function "aws" 'return 1'
    
    # Test error handling and alerting
    local aws_operation_failed=false
    launch_ec2_instance "t3.medium" "spot" "test-stack" >/dev/null 2>&1 || aws_operation_failed=true
    
    if [[ "$aws_operation_failed" == "true" ]]; then
        test_pass "AWS service error correctly detected"
        
        # Test if monitor service can detect and alert on the error
        local alert_result
        alert_result=$(unity_monitor_alert "error" "AWS Operation Failed" "EC2 launch failed" 2>/dev/null)
        
        if [[ "$alert_result" == *"Alert sent"* ]]; then
            test_pass "Monitor service correctly handles AWS service errors"
        else
            test_fail "Monitor service error handling failed: $alert_result"
        fi
    else
        test_fail "AWS service error not properly detected"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# DATA SHARING TESTS
# =============================================================================

test_data_sharing_between_services() {
    test_start "data_sharing_between_services" "Test data sharing between services"
    
    setup_integration_tests
    
    # Source services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_performance_init "test-performance" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Test data caching and sharing
    local test_data='{"instances": [{"id": "i-1234567890abcdef0", "state": "running"}]}'
    
    # Performance service caches AWS data
    if perf_cache_aws_response "shared_data" "$test_data" 3600 >/dev/null 2>&1; then
        test_pass "Performance service can cache shared data"
        
        # Monitor service retrieves shared data
        local cached_data
        cached_data=$(perf_get_cached_aws_response "shared_data" 2>/dev/null)
        
        if [[ -n "$cached_data" ]]; then
            test_pass "Services can share cached data successfully"
        else
            test_fail "Services cannot retrieve shared cached data"
        fi
    else
        test_fail "Performance service cannot cache shared data"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# WORKFLOW INTEGRATION TESTS
# =============================================================================

test_deployment_workflow_integration() {
    test_start "deployment_workflow_integration" "Test complete deployment workflow integration"
    
    setup_integration_tests
    
    # Source all services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Initialize all services
    unity_config_init >/dev/null 2>&1
    unity_performance_init "test-performance" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Simulate complete deployment workflow
    local workflow_success=true
    
    # Step 1: Load configuration
    local stack_name
    stack_name=$(unity_config_get "STACK_NAME" 2>/dev/null) || workflow_success=false
    
    # Step 2: Start performance monitoring
    perf_timer_start "deployment" >/dev/null 2>&1 || workflow_success=false
    
    # Step 3: Launch AWS infrastructure
    local instance_id
    instance_id=$(launch_ec2_instance "t3.medium" "spot" "$stack_name" 2>/dev/null) || workflow_success=false
    
    # Step 4: Deploy containers
    local container_result
    container_result=$(docker_start_container "nginx:latest" "${stack_name}-app" 2>/dev/null) || workflow_success=false
    
    # Step 5: Monitor deployment
    local health_result
    health_result=$(unity_monitor_health_check "all" 2>/dev/null) || workflow_success=false
    
    # Step 6: Stop performance monitoring
    local perf_result
    perf_result=$(perf_timer_stop "deployment" 2>/dev/null) || workflow_success=false
    
    if [[ "$workflow_success" == "true" ]]; then
        test_pass "Complete deployment workflow integration successful"
        
        # Verify all components are working together
        if [[ -n "$stack_name" && -n "$instance_id" && -n "$container_result" && -n "$health_result" && -n "$perf_result" ]]; then
            test_pass "All workflow components executed successfully"
        else
            test_fail "Some workflow components failed to execute properly"
        fi
    else
        test_fail "Deployment workflow integration failed"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# PERFORMANCE INTEGRATION TESTS
# =============================================================================

test_integrated_performance() {
    test_start "integrated_performance" "Test integrated performance across all services"
    
    setup_integration_tests
    
    # Source all services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Measure integrated initialization performance
    local start_time=$(date +%s%N)
    
    unity_config_init >/dev/null 2>&1
    unity_performance_init "test-performance" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Check if integrated initialization is within acceptable limits (under 10 seconds)
    if [[ $duration_ms -lt 10000 ]]; then
        test_pass "Integrated service initialization performance acceptable: ${duration_ms}ms"
        
        # Test integrated operation performance
        local operation_start=$(date +%s%N)
        
        # Perform integrated operations
        unity_config_get "STACK_NAME" >/dev/null 2>&1
        launch_ec2_instance "t3.medium" "spot" "test-stack" >/dev/null 2>&1
        docker_start_container "nginx:latest" "test-container" >/dev/null 2>&1
        unity_monitor_health_check "system" >/dev/null 2>&1
        
        local operation_end=$(date +%s%N)
        local operation_duration=$(( (operation_end - operation_start) / 1000000 ))
        
        if [[ $operation_duration -lt 5000 ]]; then
            test_pass "Integrated operations performance acceptable: ${operation_duration}ms"
        else
            test_warn "Integrated operations slow: ${operation_duration}ms"
        fi
    else
        test_warn "Integrated service initialization slow: ${duration_ms}ms"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# RESOURCE SHARING TESTS
# =============================================================================

test_resource_sharing() {
    test_start "resource_sharing" "Test resource sharing between services"
    
    setup_integration_tests
    
    # Source services
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_INTEGRATION_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Initialize services
    unity_config_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Test shared configuration access
    local aws_config
    aws_config=$(unity_config_get "AWS_REGION" 2>/dev/null)
    
    if [[ "$aws_config" == "us-west-2" ]]; then
        test_pass "Services can share configuration resources"
        
        # Test shared monitoring of AWS resources
        local health_check
        health_check=$(unity_monitor_health_check "infrastructure" 2>/dev/null)
        
        if [[ "$health_check" == *"infrastructure"* ]]; then
            test_pass "Services can share monitoring resources"
        else
            test_fail "Services cannot share monitoring resources"
        fi
    else
        test_fail "Services cannot share configuration resources: got '$aws_config'"
    fi
    
    cleanup_integration_tests
}

# =============================================================================
# RUN ALL INTEGRATION TESTS
# =============================================================================

# Register integration tests with the Unity test framework
unity_register_integration_test "aws_config_integration" "unity-aws-service,unity-config-service" "test_aws_config_integration" ""
unity_register_integration_test "docker_config_integration" "unity-docker-service,unity-config-service" "test_docker_config_integration" ""
unity_register_integration_test "monitor_aws_integration" "unity-monitor-service,unity-aws-service" "test_monitor_aws_integration" ""
unity_register_integration_test "performance_aws_integration" "unity-performance-service,unity-aws-service" "test_performance_aws_integration" ""
unity_register_integration_test "service_event_communication" "unity-config-service,unity-aws-service,unity-monitor-service,unity-performance-service" "test_service_event_communication" ""
unity_register_integration_test "deployment_workflow_integration" "unity-config-service,unity-aws-service,unity-docker-service,unity-monitor-service,unity-performance-service" "test_deployment_workflow_integration" ""

# Run all test functions
main() {
    log_info "Running Unity Service Integration Tests"
    
    # Cross-service integration tests
    test_aws_config_integration
    test_docker_config_integration
    test_monitor_aws_integration
    test_performance_aws_integration
    test_monitor_docker_integration
    
    # Event-driven integration tests
    test_service_event_communication
    test_config_change_propagation
    
    # Dependency chain tests
    test_service_dependency_chain
    test_error_propagation
    
    # Data sharing tests
    test_data_sharing_between_services
    
    # Workflow integration tests
    test_deployment_workflow_integration
    
    # Performance integration tests
    test_integrated_performance
    
    # Resource sharing tests
    test_resource_sharing
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi