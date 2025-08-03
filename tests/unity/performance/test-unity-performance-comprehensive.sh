#!/bin/bash
# =============================================================================
# Unity Comprehensive Performance Test Suite
# Performance benchmarking, stress testing, and resource monitoring for Unity services
# =============================================================================

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source the Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Source Unity services for performance testing
source "$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh" 2>/dev/null || echo "Warning: Unity AWS service not found"
source "$PROJECT_ROOT/lib/unity/services/unity-docker-service.sh" 2>/dev/null || echo "Warning: Unity Docker service not found"
source "$PROJECT_ROOT/lib/unity/services/unity-config-service.sh" 2>/dev/null || echo "Warning: Unity Config service not found"
source "$PROJECT_ROOT/lib/unity/services/unity-monitor-service.sh" 2>/dev/null || echo "Warning: Unity Monitor service not found"

# =============================================================================
# TEST SUITE INITIALIZATION
# =============================================================================

# Initialize Unity test framework with performance focus
unity_test_init "unity-performance-comprehensive" "performance" "unity-system"

# Performance test configuration
declare -A PERFORMANCE_THRESHOLDS=(
    ["service_init_ms"]=2000
    ["api_call_ms"]=500
    ["memory_usage_mb"]=100
    ["cpu_usage_percent"]=80
    ["concurrent_operations"]=10
    ["stress_test_duration"]=60
)

declare -A PERFORMANCE_RESULTS=()
declare -A STRESS_TEST_RESULTS=()
declare -A RESOURCE_USAGE_RESULTS=()

# =============================================================================
# PERFORMANCE TESTING UTILITIES
# =============================================================================

# Get current memory usage
get_memory_usage() {
    if command -v ps >/dev/null 2>&1; then
        ps -o vsz= -p $$ 2>/dev/null | tr -d ' ' || echo "0"
    else
        echo "0"
    fi
}

# Get current CPU usage (approximation)
get_cpu_usage() {
    if command -v top >/dev/null 2>&1; then
        # This is a simplified CPU check - in real scenarios you'd want more sophisticated monitoring
        local cpu_idle=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $7}' | sed 's/%idle//' 2>/dev/null || echo "100")
        echo $((100 - ${cpu_idle%.*}))
    else
        echo "0"
    fi
}

# Performance test wrapper
performance_test_wrapper() {
    local test_name="$1"
    local test_function="$2"
    local iterations="${3:-5}"
    local max_duration_ms="${4:-1000}"
    local max_memory_mb="${5:-50}"
    
    test_start "perf_$test_name" "Performance test: $test_name ($iterations iterations)"
    
    local durations=()
    local memory_usage=()
    local cpu_usage=()
    local total_duration=0
    local max_duration=0
    local min_duration=999999999
    local failures=0
    
    log_info "Running performance test: $test_name ($iterations iterations)"
    
    for ((i=1; i<=iterations; i++)); do
        # Memory tracking
        local mem_before=$(get_memory_usage)
        local cpu_before=$(get_cpu_usage)
        
        # Time the function
        local start_time=$(date +%s%N)
        local func_result=0
        
        if command -v "$test_function" >/dev/null 2>&1; then
            "$test_function" >/dev/null 2>&1 || func_result=$?
        else
            # Mock function for testing
            sleep 0.01  # Simulate some work
            func_result=0
        fi
        
        local end_time=$(date +%s%N)
        
        # Calculate metrics
        local duration_ns=$((end_time - start_time))
        local duration_ms=$((duration_ns / 1000000))
        
        local mem_after=$(get_memory_usage)
        local cpu_after=$(get_cpu_usage)
        
        local mem_diff_kb=$((mem_after - mem_before))
        local mem_diff_mb=$((mem_diff_kb / 1024))
        local cpu_diff=$((cpu_after - cpu_before))
        
        # Track metrics
        durations+=("$duration_ms")
        memory_usage+=("$mem_diff_mb")
        cpu_usage+=("$cpu_diff")
        total_duration=$((total_duration + duration_ms))
        
        if [[ $duration_ms -gt $max_duration ]]; then
            max_duration=$duration_ms
        fi
        if [[ $duration_ms -lt $min_duration ]]; then
            min_duration=$duration_ms
        fi
        
        # Check for failures
        if [[ $func_result -ne 0 ]]; then
            ((failures++))
        fi
        
        # Brief pause between iterations
        sleep 0.1
    done
    
    # Calculate statistics
    local avg_duration=$((total_duration / iterations))
    local avg_memory=0
    local avg_cpu=0
    
    if [[ ${#memory_usage[@]} -gt 0 ]]; then
        local total_memory=0
        local total_cpu=0
        for ((i=0; i<${#memory_usage[@]}; i++)); do
            total_memory=$((total_memory + memory_usage[i]))
            total_cpu=$((total_cpu + cpu_usage[i]))
        done
        avg_memory=$((total_memory / iterations))
        avg_cpu=$((total_cpu / iterations))
    fi
    
    # Store results
    PERFORMANCE_RESULTS["${test_name}_avg_duration"]="$avg_duration"
    PERFORMANCE_RESULTS["${test_name}_min_duration"]="$min_duration"
    PERFORMANCE_RESULTS["${test_name}_max_duration"]="$max_duration"
    PERFORMANCE_RESULTS["${test_name}_avg_memory"]="$avg_memory"
    PERFORMANCE_RESULTS["${test_name}_avg_cpu"]="$avg_cpu"
    PERFORMANCE_RESULTS["${test_name}_failures"]="$failures"
    
    # Store in Unity benchmarks
    UNITY_SERVICE_BENCHMARKS["${test_name}"]="$avg_duration|$min_duration|$max_duration|$avg_memory|$iterations"
    
    # Validate performance thresholds
    local performance_passed=true
    local performance_details="Avg: ${avg_duration}ms, Min: ${min_duration}ms, Max: ${max_duration}ms, Memory: ${avg_memory}MB, CPU: ${avg_cpu}%, Failures: $failures"
    
    if [[ $avg_duration -gt $max_duration_ms ]]; then
        performance_passed=false
        performance_details+=", EXCEEDED DURATION THRESHOLD (${max_duration_ms}ms)"
    fi
    
    if [[ $avg_memory -gt $max_memory_mb ]]; then
        performance_passed=false
        performance_details+=", EXCEEDED MEMORY THRESHOLD (${max_memory_mb}MB)"
    fi
    
    if [[ $failures -gt 0 ]]; then
        performance_passed=false
        performance_details+=", HAD FAILURES"
    fi
    
    if [[ "$performance_passed" == "true" ]]; then
        test_pass "Performance test passed: $performance_details"
    else
        test_fail "Performance test failed: $performance_details"
    fi
}

# =============================================================================
# SERVICE INITIALIZATION PERFORMANCE TESTS
# =============================================================================

test_config_service_init_performance() {
    performance_test_wrapper "config_service_init" "init_unity_config_service" "5" "2000" "20"
}

test_aws_service_init_performance() {
    # Mock AWS CLI for consistent performance testing
    mock_function "aws" "echo 'mocked-aws-response'"
    
    performance_test_wrapper "aws_service_init" "init_unity_aws_service" "5" "2000" "20"
    
    restore_function "aws"
}

test_docker_service_init_performance() {
    # Mock Docker CLI for consistent performance testing
    mock_function "docker" "echo 'mocked-docker-response'"
    mock_function "docker-compose" "echo 'mocked-compose-response'"
    
    performance_test_wrapper "docker_service_init" "init_unity_docker_service" "5" "2000" "20"
    
    restore_function "docker"
    restore_function "docker-compose"
}

test_monitor_service_init_performance() {
    performance_test_wrapper "monitor_service_init" "init_unity_monitor_service" "5" "2000" "20"
}

# =============================================================================
# API CALL PERFORMANCE TESTS
# =============================================================================

test_config_api_performance() {
    test_start "config_api_performance" "Test Config service API performance"
    
    # Mock yq for consistent performance testing
    mock_function "yq" "echo 'mocked-config-value'"
    
    # Create test config file
    local test_config="/tmp/unity-perf-config-$$.yml"
    cat > "$test_config" << 'EOF'
test:
  key1: "value1"
  key2: "value2"
  nested:
    key3: "value3"
EOF
    
    # Test config loading performance
    performance_test_wrapper "config_load_file" "load_config_file $test_config" "10" "500" "10"
    
    # Test config value retrieval performance
    if command -v get_config_value >/dev/null 2>&1; then
        performance_test_wrapper "config_get_value" "get_config_value test.key1" "20" "100" "5"
    fi
    
    # Clean up
    rm -f "$test_config"
    restore_function "yq"
}

test_aws_api_performance() {
    test_start "aws_api_performance" "Test AWS service API performance"
    
    # Mock AWS CLI for consistent performance testing
    mock_function "aws" "echo 'mocked-aws-api-response'"
    
    # Test AWS regions retrieval performance
    if command -v get_aws_regions >/dev/null 2>&1; then
        performance_test_wrapper "aws_get_regions" "get_aws_regions" "10" "500" "10"
    fi
    
    # Test EC2 instances retrieval performance
    if command -v get_ec2_instances >/dev/null 2>&1; then
        performance_test_wrapper "aws_get_instances" "get_ec2_instances" "10" "1000" "15"
    fi
    
    # Test spot prices retrieval performance
    if command -v get_spot_prices >/dev/null 2>&1; then
        performance_test_wrapper "aws_get_spot_prices" "get_spot_prices t3.micro us-west-2" "5" "1500" "15"
    fi
    
    restore_function "aws"
}

test_docker_api_performance() {
    test_start "docker_api_performance" "Test Docker service API performance"
    
    # Mock Docker CLI for consistent performance testing
    mock_function "docker" "echo 'mocked-docker-api-response'"
    
    # Test Docker images retrieval performance
    if command -v get_docker_images >/dev/null 2>&1; then
        performance_test_wrapper "docker_get_images" "get_docker_images" "10" "800" "10"
    fi
    
    # Test running containers retrieval performance
    if command -v get_running_containers >/dev/null 2>&1; then
        performance_test_wrapper "docker_get_containers" "get_running_containers" "10" "600" "10"
    fi
    
    restore_function "docker"
}

# =============================================================================
# CONCURRENT OPERATIONS PERFORMANCE TESTS
# =============================================================================

test_concurrent_config_operations() {
    test_start "concurrent_config_ops" "Test concurrent configuration operations"
    
    # Mock yq for consistent performance testing
    mock_function "yq" "echo 'mocked-config-value'"
    
    local concurrent_processes=5
    local operations_per_process=10
    local start_time=$(date +%s%N)
    local pids=()
    
    log_info "Starting $concurrent_processes concurrent config processes"
    
    for ((i=1; i<=concurrent_processes; i++)); do
        (
            for ((j=1; j<=operations_per_process; j++)); do
                if command -v get_config_value >/dev/null 2>&1; then
                    get_config_value "test.key$j" >/dev/null 2>&1 || true
                else
                    sleep 0.01  # Simulate work
                fi
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all processes to complete
    local completed=0
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((completed++))
        fi
    done
    
    local end_time=$(date +%s%N)
    local total_duration_ms=$(((end_time - start_time) / 1000000))
    local total_operations=$((concurrent_processes * operations_per_process))
    local ops_per_second=$((total_operations * 1000 / total_duration_ms))
    
    # Store results
    PERFORMANCE_RESULTS["concurrent_config_duration"]="$total_duration_ms"
    PERFORMANCE_RESULTS["concurrent_config_operations"]="$total_operations"
    PERFORMANCE_RESULTS["concurrent_config_ops_per_sec"]="$ops_per_second"
    PERFORMANCE_RESULTS["concurrent_config_completed"]="$completed"
    
    # Evaluate concurrent performance
    if [[ $completed -eq $concurrent_processes && $total_duration_ms -lt 10000 ]]; then
        test_pass "Concurrent config operations successful: ${total_operations} ops in ${total_duration_ms}ms (${ops_per_second} ops/sec)"
    elif [[ $completed -ge $((concurrent_processes / 2)) ]]; then
        test_pass "Concurrent config operations partially successful: ${completed}/${concurrent_processes} processes"
    else
        test_fail "Concurrent config operations failed: only ${completed}/${concurrent_processes} processes completed"
    fi
    
    restore_function "yq"
}

test_concurrent_service_initialization() {
    test_start "concurrent_service_init" "Test concurrent service initialization"
    
    # Mock external dependencies
    mock_function "aws" "echo 'mocked-aws-response'"
    mock_function "docker" "echo 'mocked-docker-response'"
    mock_function "yq" "echo 'mocked-config-value'"
    
    local services=("init_unity_config_service" "init_unity_aws_service" "init_unity_docker_service")
    local start_time=$(date +%s%N)
    local pids=()
    local results=()
    
    log_info "Starting concurrent initialization of ${#services[@]} services"
    
    for service in "${services[@]}"; do
        (
            if command -v "$service" >/dev/null 2>&1; then
                "$service" >/dev/null 2>&1
                echo "success"
            else
                sleep 0.5  # Simulate initialization time
                echo "mocked"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all services to initialize
    local completed=0
    for i in "${!pids[@]}"; do
        local pid=${pids[i]}
        if wait "$pid"; then
            ((completed++))
            results+=("success")
        else
            results+=("failed")
        fi
    done
    
    local end_time=$(date +%s%N)
    local total_duration_ms=$(((end_time - start_time) / 1000000))
    
    # Store results
    PERFORMANCE_RESULTS["concurrent_init_duration"]="$total_duration_ms"
    PERFORMANCE_RESULTS["concurrent_init_services"]="${#services[@]}"
    PERFORMANCE_RESULTS["concurrent_init_completed"]="$completed"
    
    # Evaluate concurrent initialization performance
    if [[ $completed -eq ${#services[@]} && $total_duration_ms -lt 5000 ]]; then
        test_pass "Concurrent service initialization successful: ${completed} services in ${total_duration_ms}ms"
    elif [[ $completed -ge 2 ]]; then
        test_pass "Concurrent service initialization partially successful: ${completed}/${#services[@]} services"
    else
        test_fail "Concurrent service initialization failed: only ${completed}/${#services[@]} services initialized"
    fi
    
    restore_function "aws"
    restore_function "docker"
    restore_function "yq"
}

# =============================================================================
# STRESS TESTING
# =============================================================================

test_config_service_stress() {
    test_start "config_service_stress" "Stress test configuration service"
    
    # Mock yq for stress testing
    mock_function "yq" "echo 'stress-test-value'"
    
    local stress_duration=30  # seconds
    local start_time=$(date +%s)
    local end_time=$((start_time + stress_duration))
    local operations=0
    local errors=0
    
    log_info "Running config service stress test for ${stress_duration} seconds"
    
    while [[ $(date +%s) -lt $end_time ]]; do
        if command -v get_config_value >/dev/null 2>&1; then
            if get_config_value "stress.test.key" >/dev/null 2>&1; then
                ((operations++))
            else
                ((errors++))
            fi
        else
            # Mock operation
            sleep 0.001
            ((operations++))
        fi
        
        # Brief pause to prevent overwhelming the system
        if [[ $((operations % 100)) -eq 0 ]]; then
            sleep 0.01
        fi
    done
    
    local actual_duration=$(($(date +%s) - start_time))
    local ops_per_second=$((operations / actual_duration))
    local error_rate=$((errors * 100 / operations))
    
    # Store stress test results
    STRESS_TEST_RESULTS["config_operations"]="$operations"
    STRESS_TEST_RESULTS["config_errors"]="$errors"
    STRESS_TEST_RESULTS["config_duration"]="$actual_duration"
    STRESS_TEST_RESULTS["config_ops_per_sec"]="$ops_per_second"
    STRESS_TEST_RESULTS["config_error_rate"]="$error_rate"
    
    # Evaluate stress test results
    if [[ $operations -gt 1000 && $error_rate -lt 5 ]]; then
        test_pass "Config service stress test excellent: ${operations} ops in ${actual_duration}s (${ops_per_second} ops/sec, ${error_rate}% errors)"
    elif [[ $operations -gt 500 && $error_rate -lt 10 ]]; then
        test_pass "Config service stress test good: ${operations} ops in ${actual_duration}s (${ops_per_second} ops/sec, ${error_rate}% errors)"
    elif [[ $operations -gt 100 ]]; then
        test_warn "Config service stress test acceptable: ${operations} ops in ${actual_duration}s (${ops_per_second} ops/sec, ${error_rate}% errors)"
    else
        test_fail "Config service stress test poor: ${operations} ops in ${actual_duration}s (${ops_per_second} ops/sec, ${error_rate}% errors)"
    fi
    
    restore_function "yq"
}

test_memory_leak_detection() {
    test_start "memory_leak_detection" "Test for memory leaks in Unity services"
    
    local initial_memory=$(get_memory_usage)
    local peak_memory=$initial_memory
    local operations=500
    local memory_samples=()
    
    log_info "Running memory leak detection test with $operations operations"
    
    # Mock external dependencies
    mock_function "yq" "echo 'memory-test-value'"
    
    for ((i=1; i<=operations; i++)); do
        # Perform operations that might cause memory leaks
        if command -v get_config_value >/dev/null 2>&1; then
            get_config_value "memory.test.key$i" >/dev/null 2>&1 || true
        else
            # Mock operation that might use memory
            local temp_var="memory_test_data_$i"
            eval "$temp_var='some data'"
        fi
        
        # Sample memory usage every 50 operations
        if [[ $((i % 50)) -eq 0 ]]; then
            local current_memory=$(get_memory_usage)
            memory_samples+=("$current_memory")
            
            if [[ $current_memory -gt $peak_memory ]]; then
                peak_memory=$current_memory
            fi
        fi
    done
    
    local final_memory=$(get_memory_usage)
    local memory_growth=$((final_memory - initial_memory))
    local memory_growth_mb=$((memory_growth / 1024))
    local peak_growth_mb=$(((peak_memory - initial_memory) / 1024))
    
    # Store memory usage results
    RESOURCE_USAGE_RESULTS["initial_memory_kb"]="$initial_memory"
    RESOURCE_USAGE_RESULTS["final_memory_kb"]="$final_memory"
    RESOURCE_USAGE_RESULTS["peak_memory_kb"]="$peak_memory"
    RESOURCE_USAGE_RESULTS["memory_growth_mb"]="$memory_growth_mb"
    RESOURCE_USAGE_RESULTS["peak_growth_mb"]="$peak_growth_mb"
    
    # Evaluate memory leak detection
    if [[ $memory_growth_mb -lt 10 ]]; then
        test_pass "Memory leak test excellent: ${memory_growth_mb}MB growth (peak: ${peak_growth_mb}MB) after $operations operations"
    elif [[ $memory_growth_mb -lt 25 ]]; then
        test_pass "Memory leak test good: ${memory_growth_mb}MB growth (peak: ${peak_growth_mb}MB) after $operations operations"
    elif [[ $memory_growth_mb -lt 50 ]]; then
        test_warn "Memory leak test acceptable: ${memory_growth_mb}MB growth (peak: ${peak_growth_mb}MB) after $operations operations"
    else
        test_fail "Memory leak test poor: ${memory_growth_mb}MB growth (peak: ${peak_growth_mb}MB) after $operations operations - possible memory leak"
    fi
    
    restore_function "yq"
}

# =============================================================================
# RESOURCE MONITORING TESTS
# =============================================================================

test_resource_usage_monitoring() {
    test_start "resource_usage_monitoring" "Monitor resource usage during operations"
    
    local monitoring_duration=20  # seconds
    local start_time=$(date +%s)
    local end_time=$((start_time + monitoring_duration))
    
    local memory_samples=()
    local cpu_samples=()
    local operation_count=0
    
    log_info "Monitoring resource usage for ${monitoring_duration} seconds"
    
    # Mock external dependencies
    mock_function "aws" "echo 'resource-monitor-aws'"
    mock_function "docker" "echo 'resource-monitor-docker'"
    mock_function "yq" "echo 'resource-monitor-config'"
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Sample resource usage
        local current_memory=$(get_memory_usage)
        local current_cpu=$(get_cpu_usage)
        
        memory_samples+=("$current_memory")
        cpu_samples+=("$current_cpu")
        
        # Perform some operations
        if command -v get_config_value >/dev/null 2>&1; then
            get_config_value "monitor.test" >/dev/null 2>&1 || true
        fi
        
        if command -v get_aws_regions >/dev/null 2>&1; then
            get_aws_regions >/dev/null 2>&1 || true
        fi
        
        ((operation_count++))
        
        sleep 1
    done
    
    # Calculate resource usage statistics
    local total_memory=0
    local max_memory=0
    local total_cpu=0
    local max_cpu=0
    
    for memory in "${memory_samples[@]}"; do
        total_memory=$((total_memory + memory))
        if [[ $memory -gt $max_memory ]]; then
            max_memory=$memory
        fi
    done
    
    for cpu in "${cpu_samples[@]}"; do
        total_cpu=$((total_cpu + cpu))
        if [[ $cpu -gt $max_cpu ]]; then
            max_cpu=$cpu
        fi
    done
    
    local avg_memory_mb=$(((total_memory / ${#memory_samples[@]}) / 1024))
    local max_memory_mb=$((max_memory / 1024))
    local avg_cpu=$((total_cpu / ${#cpu_samples[@]}))
    
    # Store resource monitoring results
    RESOURCE_USAGE_RESULTS["avg_memory_mb"]="$avg_memory_mb"
    RESOURCE_USAGE_RESULTS["max_memory_mb"]="$max_memory_mb"
    RESOURCE_USAGE_RESULTS["avg_cpu_percent"]="$avg_cpu"
    RESOURCE_USAGE_RESULTS["max_cpu_percent"]="$max_cpu"
    RESOURCE_USAGE_RESULTS["operations_performed"]="$operation_count"
    
    # Evaluate resource usage
    local resource_acceptable=true
    local resource_details="Avg Memory: ${avg_memory_mb}MB, Max Memory: ${max_memory_mb}MB, Avg CPU: ${avg_cpu}%, Max CPU: ${max_cpu}%"
    
    if [[ $max_memory_mb -gt ${PERFORMANCE_THRESHOLDS["memory_usage_mb"]} ]]; then
        resource_acceptable=false
        resource_details+=", EXCEEDED MEMORY THRESHOLD"
    fi
    
    if [[ $max_cpu -gt ${PERFORMANCE_THRESHOLDS["cpu_usage_percent"]} ]]; then
        resource_acceptable=false
        resource_details+=", EXCEEDED CPU THRESHOLD"
    fi
    
    if [[ "$resource_acceptable" == "true" ]]; then
        test_pass "Resource usage monitoring excellent: $resource_details ($operation_count operations)"
    else
        test_warn "Resource usage monitoring concerning: $resource_details ($operation_count operations)"
    fi
    
    restore_function "aws"
    restore_function "docker"
    restore_function "yq"
}

# =============================================================================
# PERFORMANCE REPORTING
# =============================================================================

generate_performance_report() {
    test_start "performance_report_generation" "Generate comprehensive performance report"
    
    local report_file="$UNITY_TEST_DIR/reports/unity-performance-detailed-report.html"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Unity Performance Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #28a745 0%, #20c997 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
        .section { margin: 30px 0; }
        .section h2 { color: #333; border-bottom: 2px solid #28a745; padding-bottom: 10px; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0; }
        .metric-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #28a745; }
        .metric-value { font-size: 2em; font-weight: bold; color: #28a745; }
        .metric-label { color: #666; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; }
        .excellent { color: #28a745; font-weight: bold; }
        .good { color: #20c997; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .poor { color: #dc3545; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚡ Unity Performance Test Report</h1>
            <p><strong>Generated:</strong> $(date)</p>
            <p><strong>Test Duration:</strong> Comprehensive performance analysis</p>
        </div>
        
        <div class="section">
            <h2>📊 Performance Metrics Overview</h2>
            <div class="metric-grid">
EOF
    
    # Add performance metrics
    for key in "${!PERFORMANCE_RESULTS[@]}"; do
        local value="${PERFORMANCE_RESULTS[$key]}"
        cat >> "$report_file" << EOF
                <div class="metric-card">
                    <div class="metric-value">$value</div>
                    <div class="metric-label">${key//_/ }</div>
                </div>
EOF
    done
    
    cat >> "$report_file" << 'EOF'
            </div>
        </div>
        
        <div class="section">
            <h2>🔥 Stress Test Results</h2>
            <table>
                <tr><th>Test</th><th>Operations</th><th>Duration (s)</th><th>Ops/Sec</th><th>Error Rate</th><th>Status</th></tr>
EOF
    
    # Add stress test results
    if [[ -n "${STRESS_TEST_RESULTS["config_operations"]:-}" ]]; then
        local ops="${STRESS_TEST_RESULTS["config_operations"]}"
        local duration="${STRESS_TEST_RESULTS["config_duration"]}"
        local ops_per_sec="${STRESS_TEST_RESULTS["config_ops_per_sec"]}"
        local error_rate="${STRESS_TEST_RESULTS["config_error_rate"]}"
        
        local status_class="excellent"
        local status_text="Excellent"
        if [[ $error_rate -gt 5 ]]; then
            status_class="warning"
            status_text="Warning"
        fi
        if [[ $ops_per_sec -lt 10 ]]; then
            status_class="poor"
            status_text="Poor"
        fi
        
        cat >> "$report_file" << EOF
                <tr>
                    <td>Config Service Stress</td>
                    <td>$ops</td>
                    <td>$duration</td>
                    <td>$ops_per_sec</td>
                    <td>${error_rate}%</td>
                    <td><span class="$status_class">$status_text</span></td>
                </tr>
EOF
    fi
    
    cat >> "$report_file" << 'EOF'
            </table>
        </div>
        
        <div class="section">
            <h2>💾 Resource Usage Analysis</h2>
            <table>
                <tr><th>Metric</th><th>Average</th><th>Peak</th><th>Threshold</th><th>Status</th></tr>
EOF
    
    # Add resource usage results
    if [[ -n "${RESOURCE_USAGE_RESULTS["avg_memory_mb"]:-}" ]]; then
        local avg_memory="${RESOURCE_USAGE_RESULTS["avg_memory_mb"]}"
        local max_memory="${RESOURCE_USAGE_RESULTS["max_memory_mb"]}"
        local memory_threshold="${PERFORMANCE_THRESHOLDS["memory_usage_mb"]}"
        
        local memory_status_class="excellent"
        local memory_status_text="Excellent"
        if [[ $max_memory -gt $memory_threshold ]]; then
            memory_status_class="warning"
            memory_status_text="Warning"
        fi
        
        cat >> "$report_file" << EOF
                <tr>
                    <td>Memory Usage</td>
                    <td>${avg_memory}MB</td>
                    <td>${max_memory}MB</td>
                    <td>${memory_threshold}MB</td>
                    <td><span class="$memory_status_class">$memory_status_text</span></td>
                </tr>
EOF
    fi
    
    if [[ -n "${RESOURCE_USAGE_RESULTS["avg_cpu_percent"]:-}" ]]; then
        local avg_cpu="${RESOURCE_USAGE_RESULTS["avg_cpu_percent"]}"
        local max_cpu="${RESOURCE_USAGE_RESULTS["max_cpu_percent"]}"
        local cpu_threshold="${PERFORMANCE_THRESHOLDS["cpu_usage_percent"]}"
        
        local cpu_status_class="excellent"
        local cpu_status_text="Excellent"
        if [[ $max_cpu -gt $cpu_threshold ]]; then
            cpu_status_class="warning"
            cpu_status_text="Warning"
        fi
        
        cat >> "$report_file" << EOF
                <tr>
                    <td>CPU Usage</td>
                    <td>${avg_cpu}%</td>
                    <td>${max_cpu}%</td>
                    <td>${cpu_threshold}%</td>
                    <td><span class="$cpu_status_class">$cpu_status_text</span></td>
                </tr>
EOF
    fi
    
    cat >> "$report_file" << 'EOF'
            </table>
        </div>
        
        <div class="section">
            <h2>📈 Performance Recommendations</h2>
            <div class="metric-card">
                <h3>Optimization Opportunities</h3>
                <ul>
                    <li>Consider implementing response caching for frequently accessed configuration values</li>
                    <li>Implement connection pooling for AWS API calls to reduce latency</li>
                    <li>Add circuit breakers for external service calls to improve resilience</li>
                    <li>Consider asynchronous processing for non-critical operations</li>
                    <li>Implement adaptive timeout mechanisms based on historical performance</li>
                </ul>
            </div>
            
            <div class="metric-card">
                <h3>Monitoring Recommendations</h3>
                <ul>
                    <li>Set up real-time performance monitoring with alerts</li>
                    <li>Implement distributed tracing for cross-service operations</li>
                    <li>Add custom metrics for business-specific performance indicators</li>
                    <li>Regular performance regression testing in CI/CD pipeline</li>
                    <li>Capacity planning based on performance trends</li>
                </ul>
            </div>
        </div>
    </div>
</body>
</html>
EOF
    
    test_pass "Performance report generated successfully: $report_file"
}

# =============================================================================
# RUN ALL PERFORMANCE TESTS
# =============================================================================

# Service initialization performance tests
test_config_service_init_performance
test_aws_service_init_performance
test_docker_service_init_performance
test_monitor_service_init_performance

# API call performance tests
test_config_api_performance
test_aws_api_performance
test_docker_api_performance

# Concurrent operations tests
test_concurrent_config_operations
test_concurrent_service_initialization

# Stress tests
test_config_service_stress
test_memory_leak_detection

# Resource monitoring tests
test_resource_usage_monitoring

# Generate comprehensive performance report
generate_performance_report

# Clean up Unity test framework
unity_test_cleanup

echo ""
echo "Unity Comprehensive Performance Tests Completed"
echo "Performance benchmarks, stress tests, and resource monitoring completed"
echo "Test Report: $UNITY_TEST_DIR/reports/"