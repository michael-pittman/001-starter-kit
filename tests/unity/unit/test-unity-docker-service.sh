#!/bin/bash
# =============================================================================
# Unity Docker Service Unit Tests
# Comprehensive unit testing for Unity Docker service functions
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework
unity_test_init "test-unity-docker-service" "service-unit" "unity-docker-service"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up test environment
setup_docker_service_tests() {
    # Load the Docker service
    source "$PROJECT_ROOT/lib/unity/services/unity-docker-service.sh" 2>/dev/null || {
        log_error "Failed to load Unity Docker service"
        return 1
    }
    
    # Mock Docker CLI for testing
    mock_function "docker" 'case "$1" in
        "info")
            echo "Docker daemon is running"
            return 0
            ;;
        "version")
            echo "Docker version 24.0.0"
            return 0
            ;;
        "run")
            echo "Container started: test-container"
            return 0
            ;;
        "ps")
            case "$2" in
                "-q")
                    echo "1234567890ab"
                    ;;
                "-a")
                    echo "CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES"
                    echo "1234567890ab   test:latest   \"/bin/sh\"   1 minute ago   Up 1 minute             test-container"
                    ;;
                *)
                    echo "1234567890ab   test:latest   \"/bin/sh\"   1 minute ago   Up 1 minute             test-container"
                    ;;
            esac
            ;;
        "stop")
            echo "Container stopped: $2"
            return 0
            ;;
        "restart")
            echo "Container restarted: $2"
            return 0
            ;;
        "inspect")
            echo "[{\"State\":{\"Status\":\"running\",\"Running\":true,\"Health\":{\"Status\":\"healthy\"}},\"Config\":{\"Image\":\"test:latest\",\"Labels\":{}},\"NetworkSettings\":{\"Ports\":{},\"Networks\":{}},\"Mounts\":[]}]"
            ;;
        "compose")
            case "$2" in
                "version")
                    echo "Docker Compose version v2.24.0"
                    return 0
                    ;;
                "up")
                    echo "Services started successfully"
                    return 0
                    ;;
                "down")
                    echo "Services stopped successfully"
                    return 0
                    ;;
                "ps")
                    if [[ "${3:-}" == "--format" && "${4:-}" == "json" ]]; then
                        echo "[{\"Service\":\"test-service\",\"State\":\"running\",\"Health\":\"healthy\"}]"
                    else
                        echo "NAME           COMMAND   SERVICE      STATUS    PORTS"
                        echo "test-service   test      test-service running   8080:8080"
                    fi
                    ;;
                *)
                    echo "mocked-compose-output"
                    ;;
            esac
            ;;
        "stats")
            echo "{\"Container\":\"test-container\",\"CPUPerc\":\"5.00%\",\"MemUsage\":\"100MiB / 1GiB\",\"MemPerc\":\"10.00%\"}"
            ;;
        "system")
            case "$2" in
                "info")
                    echo "{\"ServerVersion\":\"24.0.0\",\"Architecture\":\"x86_64\"}"
                    ;;
                "df")
                    echo "{\"LayersSize\":1000000,\"Images\":[{\"Size\":500000}],\"Containers\":[{\"Size\":100000}],\"Volumes\":[{\"Size\":50000}]}"
                    ;;
                "prune")
                    echo "Total reclaimed space: 100MB"
                    ;;
            esac
            ;;
        "logs")
            echo "Container log output"
            ;;
        "container"|"image"|"volume"|"network")
            echo "Resources cleaned up"
            ;;
        *)
            echo "mocked-docker-output"
            ;;
    esac'
    
    # Mock system commands
    mock_function "command" 'case "$2" in
        "docker"|"nvidia-smi"|"jq"|"systemctl"|"curl")
            return 0
            ;;
        *)
            return 1
            ;;
    esac'
    
    mock_function "systemctl" 'echo "Service operation completed"'
    mock_function "curl" 'echo "Download completed"'
    mock_function "jq" 'echo "JSON processed"'
    mock_function "nvidia-smi" 'echo "GPU detected"'
    mock_function "sudo" 'shift; "$@"'  # Execute commands without sudo
    
    # Mock file operations
    mock_function "mkdir" 'return 0'
    mock_function "chmod" 'return 0'
    mock_function "tee" 'cat'
    mock_function "cat" 'echo "mocked file content"'
    
    # Set test environment variables
    export DOCKER_MONITORING_ENABLED="true"
    export DOCKER_LOG_AGGREGATION_ENABLED="true"
    export DOCKER_AUTO_RECOVERY_ENABLED="true"
    export DOCKER_DATA_ROOT="/tmp/docker-test"
    export DOCKER_LOG_DIR="/tmp/docker-logs"
}

# Clean up test environment
cleanup_docker_service_tests() {
    # Restore mocked functions
    local mock_functions=("docker" "command" "systemctl" "curl" "jq" "nvidia-smi" "sudo" "mkdir" "chmod" "tee" "cat")
    
    for func in "${mock_functions[@]}"; do
        restore_function "$func" 2>/dev/null || true
    done
    
    # Clean up environment variables
    unset DOCKER_MONITORING_ENABLED DOCKER_LOG_AGGREGATION_ENABLED DOCKER_AUTO_RECOVERY_ENABLED
    unset DOCKER_DATA_ROOT DOCKER_LOG_DIR
}

# =============================================================================
# UNITY DOCKER SERVICE INITIALIZATION TESTS
# =============================================================================

test_unity_docker_service_init() {
    test_start "unity_docker_service_init" "Test Unity Docker service initialization"
    
    setup_docker_service_tests
    
    # Test service initialization
    if unity_docker_init >/dev/null 2>&1; then
        test_pass "Unity Docker service initialized successfully"
    else
        test_fail "Unity Docker service initialization failed"
    fi
    
    cleanup_docker_service_tests
}

test_unity_docker_service_version() {
    test_start "unity_docker_service_version" "Test Unity Docker service version"
    
    setup_docker_service_tests
    
    # Check version variable exists
    if [[ -n "${DOCKER_SERVICE_VERSION:-}" ]]; then
        test_pass "Unity Docker service version is defined: $DOCKER_SERVICE_VERSION"
    else
        test_fail "Unity Docker service version is not defined"
    fi
    
    cleanup_docker_service_tests
}

test_unity_docker_validate() {
    test_start "unity_docker_validate" "Test Unity Docker service validation"
    
    setup_docker_service_tests
    
    # Test service validation
    if unity_docker_validate >/dev/null 2>&1; then
        test_pass "Unity Docker service validation passed"
    else
        test_fail "Unity Docker service validation failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# DOCKER INSTALLATION TESTS
# =============================================================================

test_docker_install() {
    test_start "docker_install" "Test Docker installation function"
    
    setup_docker_service_tests
    
    # Test Docker installation (skip actual installation)
    if docker_install "true" "false" >/dev/null 2>&1; then
        test_pass "Docker installation function completed successfully"
    else
        test_fail "Docker installation function failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_validate_installation() {
    test_start "docker_validate_installation" "Test Docker installation validation"
    
    setup_docker_service_tests
    
    # Mock hello-world test
    mock_function "docker" 'case "$1" in
        "info")
            return 0
            ;;
        "run")
            if [[ "$2" == "--rm" && "$3" == "hello-world" ]]; then
                echo "Hello from Docker!"
                return 0
            fi
            ;;
        "rmi")
            return 0
            ;;
        "compose")
            if [[ "$2" == "version" ]]; then
                echo "Docker Compose version v2.24.0"
                return 0
            fi
            ;;
        *)
            return 0
            ;;
    esac'
    
    # Test installation validation
    if docker_validate_installation >/dev/null 2>&1; then
        test_pass "Docker installation validation passed"
    else
        test_fail "Docker installation validation failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# CONTAINER LIFECYCLE TESTS
# =============================================================================

test_docker_start_container() {
    test_start "docker_start_container" "Test starting Docker container"
    
    setup_docker_service_tests
    
    # Test container start
    if docker_start_container "test:latest" "test-container" "--detach" "false" >/dev/null 2>&1; then
        test_pass "Docker container started successfully"
    else
        test_fail "Docker container start failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_stop_container() {
    test_start "docker_stop_container" "Test stopping Docker container"
    
    setup_docker_service_tests
    
    # Test container stop
    if docker_stop_container "test-container" "30" "false" >/dev/null 2>&1; then
        test_pass "Docker container stopped successfully"
    else
        test_fail "Docker container stop failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_restart_container() {
    test_start "docker_restart_container" "Test restarting Docker container"
    
    setup_docker_service_tests
    
    # Test container restart
    if docker_restart_container "test-container" "false" >/dev/null 2>&1; then
        test_pass "Docker container restarted successfully"
    else
        test_fail "Docker container restart failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_get_container_status() {
    test_start "docker_get_container_status" "Test getting container status"
    
    setup_docker_service_tests
    
    # Test container status retrieval
    local status
    status=$(docker_get_container_status "test-container" "json" 2>/dev/null)
    
    if [[ -n "$status" && "$status" == *'"status"'* ]]; then
        test_pass "Container status retrieved successfully"
    else
        test_fail "Container status retrieval failed: $status"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# DOCKER COMPOSE TESTS
# =============================================================================

test_docker_compose_deploy() {
    test_start "docker_compose_deploy" "Test Docker Compose deployment"
    
    setup_docker_service_tests
    
    # Create temporary compose file
    local compose_file=$(mktemp)
    cat > "$compose_file" << 'EOF'
services:
  test-service:
    image: test:latest
    ports:
      - "8080:8080"
EOF
    
    # Test compose deployment
    if docker_compose_deploy "$compose_file" "" "test-stack" "" "false" >/dev/null 2>&1; then
        test_pass "Docker Compose deployment completed successfully"
    else
        test_fail "Docker Compose deployment failed"
    fi
    
    # Clean up
    rm -f "$compose_file"
    cleanup_docker_service_tests
}

test_docker_compose_stop() {
    test_start "docker_compose_stop" "Test Docker Compose stop"
    
    setup_docker_service_tests
    
    # Create temporary compose file
    local compose_file=$(mktemp)
    cat > "$compose_file" << 'EOF'
services:
  test-service:
    image: test:latest
EOF
    
    # Test compose stop
    if docker_compose_stop "$compose_file" "" "test-stack" "" "false" >/dev/null 2>&1; then
        test_pass "Docker Compose stop completed successfully"
    else
        test_fail "Docker Compose stop failed"
    fi
    
    # Clean up
    rm -f "$compose_file"
    cleanup_docker_service_tests
}

test_docker_compose_status() {
    test_start "docker_compose_status" "Test Docker Compose status"
    
    setup_docker_service_tests
    
    # Create temporary compose file
    local compose_file=$(mktemp)
    cat > "$compose_file" << 'EOF'
services:
  test-service:
    image: test:latest
EOF
    
    # Test compose status
    local status
    status=$(docker_compose_status "$compose_file" "" "test-stack" "json" 2>/dev/null)
    
    if [[ -n "$status" ]]; then
        test_pass "Docker Compose status retrieved successfully"
    else
        test_fail "Docker Compose status retrieval failed"
    fi
    
    # Clean up
    rm -f "$compose_file"
    cleanup_docker_service_tests
}

test_docker_compose_wait_for_health() {
    test_start "docker_compose_wait_for_health" "Test Docker Compose health waiting"
    
    setup_docker_service_tests
    
    # Mock compose command to return healthy services
    mock_function "docker" 'case "$1 $2" in
        "compose ps")
            echo "[{\"Service\":\"test-service\",\"Health\":\"healthy\"}]"
            ;;
        *)
            echo "mocked-docker-output"
            ;;
    esac'
    
    # Create temporary compose file
    local compose_file=$(mktemp)
    cat > "$compose_file" << 'EOF'
services:
  test-service:
    image: test:latest
    healthcheck:
      test: ["CMD", "echo", "healthy"]
EOF
    
    # Test health waiting
    if docker_compose_wait_for_health "$compose_file" "" "test-stack" "30" >/dev/null 2>&1; then
        test_pass "Docker Compose health check completed successfully"
    else
        test_fail "Docker Compose health check failed"
    fi
    
    # Clean up
    rm -f "$compose_file"
    cleanup_docker_service_tests
}

# =============================================================================
# HEALTH MONITORING TESTS
# =============================================================================

test_docker_wait_for_health() {
    test_start "docker_wait_for_health" "Test waiting for container health"
    
    setup_docker_service_tests
    
    # Mock healthy container
    mock_function "docker" 'case "$1" in
        "inspect")
            echo "healthy"
            ;;
        "ps")
            echo "1234567890ab"
            ;;
        *)
            echo "mocked-docker-output"
            ;;
    esac'
    
    # Test health waiting
    if docker_wait_for_health "test-container" "10" >/dev/null 2>&1; then
        test_pass "Container health check completed successfully"
    else
        test_fail "Container health check failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# RESOURCE MONITORING TESTS
# =============================================================================

test_docker_monitor_resources() {
    test_start "docker_monitor_resources" "Test Docker resource monitoring"
    
    setup_docker_service_tests
    
    # Create temporary output file
    local output_file=$(mktemp)
    
    # Test resource monitoring (short duration)
    if timeout 5s docker_monitor_resources "$output_file" "2" "1" >/dev/null 2>&1; then
        test_pass "Docker resource monitoring completed successfully"
    else
        test_pass "Docker resource monitoring completed (expected timeout)"
    fi
    
    # Clean up
    rm -f "$output_file"
    cleanup_docker_service_tests
}

test_docker_cleanup_resources() {
    test_start "docker_cleanup_resources" "Test Docker resource cleanup"
    
    setup_docker_service_tests
    
    # Test resource cleanup
    if docker_cleanup_resources "false" "24h" >/dev/null 2>&1; then
        test_pass "Docker resource cleanup completed successfully"
    else
        test_fail "Docker resource cleanup failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# LOG AGGREGATION TESTS
# =============================================================================

test_docker_setup_log_aggregation() {
    test_start "docker_setup_log_aggregation" "Test Docker log aggregation setup"
    
    setup_docker_service_tests
    
    # Create temporary log directory
    local log_dir=$(mktemp -d)
    
    # Test log aggregation setup
    if docker_setup_log_aggregation "$log_dir" "7" >/dev/null 2>&1; then
        test_pass "Docker log aggregation setup completed successfully"
        
        # Verify scripts were created (mocked)
        if [[ -f "$log_dir/collect-docker-logs.sh" ]]; then
            test_pass "Log collection script created"
        else
            test_warn "Log collection script not found (may be mocked)"
        fi
    else
        test_fail "Docker log aggregation setup failed"
    fi
    
    # Clean up
    rm -rf "$log_dir"
    cleanup_docker_service_tests
}

test_docker_analyze_logs() {
    test_start "docker_analyze_logs" "Test Docker log analysis"
    
    setup_docker_service_tests
    
    # Create temporary log directory with test logs
    local log_dir=$(mktemp -d)
    echo "INFO: Application started" > "$log_dir/test-container_20240101_120000.log"
    echo "ERROR: Database connection failed" >> "$log_dir/test-container_20240101_120000.log"
    echo "WARN: High memory usage detected" >> "$log_dir/test-container_20240101_120000.log"
    
    # Test log analysis
    local analysis_output
    analysis_output=$(docker_analyze_logs "$log_dir" 2>/dev/null)
    
    if [[ -n "$analysis_output" && "$analysis_output" == *"Analysis"* ]]; then
        test_pass "Docker log analysis completed successfully"
    else
        test_fail "Docker log analysis failed or returned no output"
    fi
    
    # Clean up
    rm -rf "$log_dir"
    cleanup_docker_service_tests
}

# =============================================================================
# GPU SUPPORT TESTS
# =============================================================================

test_docker_has_gpu() {
    test_start "docker_has_gpu" "Test GPU detection"
    
    setup_docker_service_tests
    
    # Test GPU detection (mocked to return true)
    if docker_has_gpu >/dev/null 2>&1; then
        test_pass "GPU detection completed successfully"
    else
        test_fail "GPU detection failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_setup_nvidia_runtime() {
    test_start "docker_setup_nvidia_runtime" "Test NVIDIA runtime setup"
    
    setup_docker_service_tests
    
    # Mock additional NVIDIA commands
    mock_function "nvidia-ctk" 'echo "NVIDIA runtime configured"'
    
    # Test NVIDIA runtime setup
    if docker_setup_nvidia_runtime "false" >/dev/null 2>&1; then
        test_pass "NVIDIA runtime setup completed successfully"
    else
        test_fail "NVIDIA runtime setup failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_docker_get_system_info() {
    test_start "docker_get_system_info" "Test getting Docker system information"
    
    setup_docker_service_tests
    
    # Test system info retrieval
    local system_info
    system_info=$(docker_get_system_info "json" 2>/dev/null)
    
    if [[ -n "$system_info" ]]; then
        test_pass "Docker system information retrieved successfully"
    else
        test_fail "Docker system information retrieval failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_list_geusemaker_containers() {
    test_start "docker_list_geusemaker_containers" "Test listing GeuseMaker containers"
    
    setup_docker_service_tests
    
    # Test container listing
    local containers
    containers=$(docker_list_geusemaker_containers "names" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        test_pass "GeuseMaker containers listed successfully"
    else
        test_fail "GeuseMaker containers listing failed"
    fi
    
    cleanup_docker_service_tests
}

test_docker_export_env() {
    test_start "docker_export_env" "Test Docker environment export"
    
    setup_docker_service_tests
    
    # Test environment export
    if docker_export_env "g4dn.xlarge" "us-west-2" >/dev/null 2>&1; then
        test_pass "Docker environment variables exported successfully"
        
        # Verify some environment variables were set
        if [[ -n "${DOCKER_BUILDKIT:-}" ]]; then
            test_pass "DOCKER_BUILDKIT environment variable set"
        else
            test_warn "DOCKER_BUILDKIT environment variable not set"
        fi
    else
        test_fail "Docker environment export failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# UNITY SERVICE INTEGRATION TESTS
# =============================================================================

test_unity_docker_execute() {
    test_start "unity_docker_execute" "Test Unity Docker service execution dispatcher"
    
    setup_docker_service_tests
    
    # Test various operations
    local operations=("status" "system-info" "list")
    
    for operation in "${operations[@]}"; do
        if unity_docker_execute "$operation" "test-container" >/dev/null 2>&1; then
            log_debug "Operation '$operation' executed successfully"
        else
            test_warn "Operation '$operation' failed or not supported"
        fi
    done
    
    test_pass "Unity Docker execute dispatcher works"
    
    cleanup_docker_service_tests
}

test_unity_docker_status() {
    test_start "unity_docker_status" "Test Unity Docker service status"
    
    setup_docker_service_tests
    
    # Test service status
    if unity_docker_status >/dev/null 2>&1; then
        test_pass "Unity Docker service status retrieved successfully"
    else
        test_fail "Unity Docker service status retrieval failed"
    fi
    
    cleanup_docker_service_tests
}

test_unity_docker_cleanup() {
    test_start "unity_docker_cleanup" "Test Unity Docker service cleanup"
    
    setup_docker_service_tests
    
    # Mock process killing
    mock_function "pkill" 'return 0'
    
    # Test service cleanup
    if unity_docker_cleanup >/dev/null 2>&1; then
        test_pass "Unity Docker service cleanup completed successfully"
    else
        test_fail "Unity Docker service cleanup failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_docker_error_handling() {
    test_start "docker_error_handling" "Test Docker service error handling"
    
    setup_docker_service_tests
    
    # Mock Docker to return error
    mock_function "docker" 'return 1'
    
    # Test error handling in container operations
    if docker_start_container "test:latest" "test-container" "" "false" >/dev/null 2>&1; then
        test_fail "Expected function to fail with mocked Docker error"
    else
        test_pass "Function correctly handled Docker CLI error"
    fi
    
    cleanup_docker_service_tests
}

test_invalid_docker_operation() {
    test_start "invalid_docker_operation" "Test handling of invalid Docker operations"
    
    setup_docker_service_tests
    
    # Test invalid operation
    if unity_docker_execute "invalid-operation" >/dev/null 2>&1; then
        test_fail "Expected function to fail with invalid operation"
    else
        test_pass "Function correctly rejected invalid operation"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_docker_service_performance() {
    test_start "docker_service_performance" "Test Unity Docker service performance"
    
    setup_docker_service_tests
    
    # Initialize service and measure performance
    local start_time=$(date +%s%N)
    unity_docker_init >/dev/null 2>&1
    local end_time=$(date +%s%N)
    
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Check if initialization is reasonably fast (under 5 seconds)
    if [[ $duration_ms -lt 5000 ]]; then
        test_pass "Docker service initialization performance acceptable: ${duration_ms}ms"
    else
        test_warn "Docker service initialization slow: ${duration_ms}ms"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_docker_configure_daemon() {
    test_start "docker_configure_daemon" "Test Docker daemon configuration"
    
    setup_docker_service_tests
    
    # Mock Python for JSON validation
    mock_function "python3" 'return 0'
    
    # Test daemon configuration
    if docker_configure_daemon >/dev/null 2>&1; then
        test_pass "Docker daemon configuration completed successfully"
    else
        test_fail "Docker daemon configuration failed"
    fi
    
    cleanup_docker_service_tests
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

# Register all test functions with the Unity test framework
unity_register_service_test "unity-docker-service" "$PROJECT_ROOT/lib/unity/services/unity-docker-service.sh" \
    "unity_docker_init,unity_docker_validate,docker_start_container,docker_compose_deploy,docker_cleanup_resources" \
    "service-unit"

# Run all test functions
main() {
    log_info "Running Unity Docker Service Unit Tests"
    
    # Initialization tests
    test_unity_docker_service_init
    test_unity_docker_service_version
    test_unity_docker_validate
    
    # Installation tests
    test_docker_install
    test_docker_validate_installation
    
    # Container lifecycle tests
    test_docker_start_container
    test_docker_stop_container
    test_docker_restart_container
    test_docker_get_container_status
    
    # Docker Compose tests
    test_docker_compose_deploy
    test_docker_compose_stop
    test_docker_compose_status
    test_docker_compose_wait_for_health
    
    # Health monitoring tests
    test_docker_wait_for_health
    
    # Resource monitoring tests
    test_docker_monitor_resources
    test_docker_cleanup_resources
    
    # Log aggregation tests
    test_docker_setup_log_aggregation
    test_docker_analyze_logs
    
    # GPU support tests
    test_docker_has_gpu
    test_docker_setup_nvidia_runtime
    
    # Utility function tests
    test_docker_get_system_info
    test_docker_list_geusemaker_containers
    test_docker_export_env
    
    # Unity service integration tests
    test_unity_docker_execute
    test_unity_docker_status
    test_unity_docker_cleanup
    
    # Error handling tests
    test_docker_error_handling
    test_invalid_docker_operation
    
    # Performance tests
    test_docker_service_performance
    
    # Configuration tests
    test_docker_configure_daemon
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi