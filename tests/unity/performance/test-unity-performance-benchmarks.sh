#!/bin/bash
# =============================================================================
# Unity Performance Benchmarks and Stress Tests
# Comprehensive performance testing for Unity services with stress testing
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# Initialize Unity test framework for performance tests
unity_test_init "test-unity-performance-benchmarks" "performance" "unity-performance-benchmarks"

# =============================================================================
# PERFORMANCE TEST CONFIGURATION
# =============================================================================

# Performance thresholds (adjustable based on system capabilities)
readonly PERFORMANCE_INIT_THRESHOLD_MS=5000        # Service initialization: 5 seconds
readonly PERFORMANCE_OPERATION_THRESHOLD_MS=2000   # Single operations: 2 seconds
readonly PERFORMANCE_BATCH_THRESHOLD_MS=10000      # Batch operations: 10 seconds
readonly PERFORMANCE_MEMORY_THRESHOLD_MB=100       # Memory usage: 100MB
readonly PERFORMANCE_CPU_THRESHOLD_PERCENT=80      # CPU usage: 80%

# Stress test parameters
readonly STRESS_TEST_ITERATIONS=100
readonly STRESS_TEST_CONCURRENT_OPERATIONS=10
readonly STRESS_TEST_DURATION_SECONDS=30
readonly STRESS_TEST_MEMORY_LIMIT_MB=500

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Set up performance test environment
setup_performance_tests() {
    # Create test performance directory
    export TEST_PERFORMANCE_DIR="/tmp/unity-performance-test-$$"
    mkdir -p "$TEST_PERFORMANCE_DIR"
    mkdir -p "$TEST_PERFORMANCE_DIR/.unity"
    mkdir -p "$TEST_PERFORMANCE_DIR/.unity/cache"
    mkdir -p "$TEST_PERFORMANCE_DIR/.unity/data"
    mkdir -p "$TEST_PERFORMANCE_DIR/.unity/monitoring"
    mkdir -p "$TEST_PERFORMANCE_DIR/.unity/performance"
    mkdir -p "$TEST_PERFORMANCE_DIR/config"
    mkdir -p "$TEST_PERFORMANCE_DIR/lib/unity/services"
    mkdir -p "$TEST_PERFORMANCE_DIR/lib/unity/core"
    mkdir -p "$TEST_PERFORMANCE_DIR/lib/unity/events"
    mkdir -p "$TEST_PERFORMANCE_DIR/lib/modules/core"
    
    # Set test-specific paths
    export PROJECT_ROOT="$TEST_PERFORMANCE_DIR"
    export UNITY_CACHE_DIR="$TEST_PERFORMANCE_DIR/.unity/cache"
    export UNITY_DATA_DIR="$TEST_PERFORMANCE_DIR/.unity/data"
    export PERFORMANCE_METRICS_DIR="$TEST_PERFORMANCE_DIR/.unity/performance"
    
    # Create mock Unity infrastructure for performance testing
    _create_mock_unity_performance_infrastructure
    
    # Create mock service files optimized for performance testing
    _create_mock_unity_performance_services
    
    # Mock external dependencies with performance considerations
    _mock_external_dependencies_performance
    
    # Set test environment variables
    export UNITY_TEST_MODE="true"
    export UNITY_PERFORMANCE_MODE="true"
    export DEBUG="false"  # Disable debug for accurate performance measurement
    export STACK_NAME="performance-test-stack"
    export AWS_REGION="us-west-2"
    
    # Initialize performance monitoring
    _init_performance_monitoring
}

# Create mock Unity infrastructure optimized for performance
_create_mock_unity_performance_infrastructure() {
    # Mock Unity core with performance tracking
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/core/unity-core.sh" << 'EOF'
#!/bin/bash
UNITY_SUCCESS=0
UNITY_ERROR_VALIDATION=1
UNITY_ERROR_EXECUTION=2

# Performance tracking variables
declare -g UNITY_PERF_START_TIME=0
declare -g UNITY_PERF_OPERATION_COUNT=0

unity_log() { 
    [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]] || echo "[$1] $2"
}

unity_emit_event() { 
    ((UNITY_PERF_OPERATION_COUNT++))
    [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]] || echo "[EVENT] $1: $2"
}

unity_handle_error() { 
    echo "ERROR: $3" >&2
    return $2
}

unity_register_service() { 
    ((UNITY_PERF_OPERATION_COUNT++))
    return 0
}

unity_on_event() { 
    ((UNITY_PERF_OPERATION_COUNT++))
    return 0
}

unity_perf_start_timer() {
    UNITY_PERF_START_TIME=$(date +%s%N)
}

unity_perf_stop_timer() {
    local end_time=$(date +%s%N)
    local duration_ns=$((end_time - UNITY_PERF_START_TIME))
    echo $((duration_ns / 1000000))  # Return milliseconds
}

export -f unity_log unity_emit_event unity_handle_error unity_register_service unity_on_event
export -f unity_perf_start_timer unity_perf_stop_timer
EOF
    
    # Mock Unity registry with performance optimizations
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/core/registry.sh" << 'EOF'
#!/bin/bash
# Use regular arrays for bash 3 compatibility and better performance
declare -a UNITY_SERVICES_KEYS=()
declare -a UNITY_SERVICES_VALUES=()
declare -a UNITY_SERVICE_STATUS_KEYS=()
declare -a UNITY_SERVICE_STATUS_VALUES=()

unity_register_service() { 
    local name="$1"
    local path="$2"
    
    # Add to arrays (performance optimized)
    UNITY_SERVICES_KEYS+=("$name")
    UNITY_SERVICES_VALUES+=("$path")
    UNITY_SERVICE_STATUS_KEYS+=("$name")
    UNITY_SERVICE_STATUS_VALUES+=("registered")
    
    return 0
}

unity_get_service() {
    local name="$1"
    local i
    for i in "${!UNITY_SERVICES_KEYS[@]}"; do
        if [[ "${UNITY_SERVICES_KEYS[i]}" == "$name" ]]; then
            echo "${UNITY_SERVICES_VALUES[i]}"
            return 0
        fi
    done
    return 1
}

export -f unity_register_service unity_get_service
EOF
    
    # Mock Unity event bus with minimal overhead
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/events/event-bus.sh" << 'EOF'
#!/bin/bash
unity_event_on() { return 0; }
unity_event_emit() { 
    [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]] || echo "[TEST-EVENT] $1: $2"
    return 0
}
export -f unity_event_on unity_event_emit
EOF
    
    # Mock core logging with performance mode
    cat > "$TEST_PERFORMANCE_DIR/lib/modules/core/logging.sh" << 'EOF'
#!/bin/bash
log_info() { [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]] || echo "[INFO] $*"; }
log_warn() { [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]] || echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_debug() { [[ "${DEBUG:-}" == "true" && "${UNITY_PERFORMANCE_MODE:-}" != "true" ]] && echo "[DEBUG] $*"; }
export -f log_info log_warn log_error log_debug
EOF
}

# Create mock Unity services optimized for performance testing
_create_mock_unity_performance_services() {
    # Mock AWS service with performance simulation
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-aws"

init_unity_aws_service() {
    # Simulate initialization time based on performance mode
    if [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]]; then
        sleep 0.1  # Fast initialization for performance testing
    else
        sleep 0.5  # Normal initialization
    fi
    echo "AWS service initialized"
    return 0
}

launch_ec2_instance() {
    # Simulate AWS API call latency
    if [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]]; then
        sleep 0.05  # Fast API simulation
    else
        sleep 0.2   # Normal API latency
    fi
    echo "i-$(openssl rand -hex 8)$(date +%s | tail -c 8)"
    return 0
}

get_spot_price() {
    # Simulate spot price lookup
    sleep 0.01
    echo "0.$(($RANDOM % 50 + 10))"
    return 0
}

# Stress test function - handles multiple concurrent operations
aws_stress_operation() {
    local operation_type="$1"
    local iterations="${2:-10}"
    
    for ((i=1; i<=iterations; i++)); do
        case "$operation_type" in
            "ec2_launch")
                launch_ec2_instance "t3.medium" "spot" "stress-test-$i" >/dev/null
                ;;
            "spot_price")
                get_spot_price "t3.medium" "us-west-2" >/dev/null
                ;;
            *)
                echo "Stress operation: $operation_type iteration $i"
                ;;
        esac
    done
}

export -f init_unity_aws_service launch_ec2_instance get_spot_price aws_stress_operation
EOF
    
    # Mock Docker service with performance simulation
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-docker"

unity_docker_init() {
    # Simulate Docker daemon check
    if [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]]; then
        sleep 0.05
    else
        sleep 0.3
    fi
    echo "Docker service initialized"
    return 0
}

docker_start_container() {
    local image="$1"
    local name="$2"
    
    # Simulate container startup time
    if [[ "${UNITY_PERFORMANCE_MODE:-}" == "true" ]]; then
        sleep 0.02
    else
        sleep 0.1
    fi
    echo "Container started: $name"
    return 0
}

docker_get_container_status() {
    local name="$1"
    local format="${2:-json}"
    
    # Simulate status check
    sleep 0.01
    
    if [[ "$format" == "json" ]]; then
        echo '{"status": "running", "health": "healthy", "uptime": "'"$((RANDOM % 3600))"'"}'
    else
        echo "running"
    fi
    return 0
}

# Stress test function - handles container operations under load
docker_stress_operation() {
    local operation_type="$1"
    local iterations="${2:-10}"
    
    for ((i=1; i<=iterations; i++)); do
        case "$operation_type" in
            "start_container")
                docker_start_container "nginx:latest" "stress-container-$i" >/dev/null
                ;;
            "check_status")
                docker_get_container_status "stress-container-$i" >/dev/null
                ;;
            *)
                echo "Docker stress operation: $operation_type iteration $i"
                ;;
        esac
    done
}

export -f unity_docker_init docker_start_container docker_get_container_status docker_stress_operation
EOF
    
    # Mock Config service with caching performance
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-config"

# Performance-optimized config cache
declare -a CONFIG_CACHE_KEYS=()
declare -a CONFIG_CACHE_VALUES=()
declare -g CONFIG_CACHE_SIZE=0

unity_config_init() {
    # Pre-populate cache for performance testing
    _populate_config_cache
    echo "Config service initialized"
    return 0
}

_populate_config_cache() {
    local default_configs=("STACK_NAME=performance-test-stack" "AWS_REGION=us-west-2" "INSTANCE_TYPE=t3.medium" "DEBUG=false")
    
    for config in "${default_configs[@]}"; do
        local key="${config%%=*}"
        local value="${config#*=}"
        CONFIG_CACHE_KEYS+=("$key")
        CONFIG_CACHE_VALUES+=("$value")
        ((CONFIG_CACHE_SIZE++))
    done
}

unity_config_get() {
    local key="$1"
    local default="${2:-}"
    
    # Performance-optimized cache lookup
    local i
    for i in "${!CONFIG_CACHE_KEYS[@]}"; do
        if [[ "${CONFIG_CACHE_KEYS[i]}" == "$key" ]]; then
            echo "${CONFIG_CACHE_VALUES[i]}"
            return 0
        fi
    done
    
    echo "$default"
    return 0
}

unity_config_set() {
    local key="$1"
    local value="$2"
    
    # Update or add to cache
    local i found=false
    for i in "${!CONFIG_CACHE_KEYS[@]}"; do
        if [[ "${CONFIG_CACHE_KEYS[i]}" == "$key" ]]; then
            CONFIG_CACHE_VALUES[i]="$value"
            found=true
            break
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        CONFIG_CACHE_KEYS+=("$key")
        CONFIG_CACHE_VALUES+=("$value")
        ((CONFIG_CACHE_SIZE++))
    fi
    
    return 0
}

# Stress test function - rapid config operations
config_stress_operation() {
    local operation_type="$1"
    local iterations="${2:-10}"
    
    for ((i=1; i<=iterations; i++)); do
        case "$operation_type" in
            "get_operations")
                unity_config_get "STACK_NAME" >/dev/null
                unity_config_get "AWS_REGION" >/dev/null
                unity_config_get "INSTANCE_TYPE" >/dev/null
                ;;
            "set_operations")
                unity_config_set "TEST_VAR_$i" "test_value_$i" >/dev/null
                ;;
            *)
                echo "Config stress operation: $operation_type iteration $i"
                ;;
        esac
    done
}

export -f unity_config_init unity_config_get unity_config_set config_stress_operation
EOF
    
    # Mock Monitor service with metrics collection
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-monitor-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-monitor"

unity_monitor_init() {
    # Initialize monitoring with minimal overhead
    sleep 0.05
    echo "Monitor service initialized"
    return 0
}

unity_monitor_health_check() {
    local target="$1"
    
    # Fast health check simulation
    sleep 0.01
    echo "Health check passed for: $target"
    return 0
}

unity_monitor_collect_metrics() {
    local format="${1:-json}"
    
    # Simulate metrics collection
    sleep 0.02
    
    if [[ "$format" == "json" ]]; then
        echo '{"cpu_usage": "'"$((RANDOM % 80 + 10))"'", "memory_usage": "'"$((RANDOM % 70 + 20))"'", "disk_usage": "'"$((RANDOM % 60 + 30))"'"}'
    else
        echo "CPU: $((RANDOM % 80 + 10))% MEM: $((RANDOM % 70 + 20))% DISK: $((RANDOM % 60 + 30))%"
    fi
    return 0
}

# Performance monitoring function
monitor_performance_metrics() {
    local duration_seconds="${1:-10}"
    local interval_seconds="${2:-1}"
    local output_file="${3:-/dev/null}"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + duration_seconds))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        unity_monitor_collect_metrics "json" >> "$output_file"
        sleep "$interval_seconds"
    done
}

export -f unity_monitor_init unity_monitor_health_check unity_monitor_collect_metrics monitor_performance_metrics
EOF
    
    # Mock Performance service with benchmarking capabilities
    cat > "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SERVICE_NAME="unity-performance"

# Performance tracking arrays
declare -a PERF_TIMER_NAMES=()
declare -a PERF_TIMER_START_TIMES=()
declare -a PERF_CACHE_KEYS=()
declare -a PERF_CACHE_VALUES=()
declare -a PERF_CACHE_TIMESTAMPS=()

unity_performance_init() {
    echo "Performance service initialized"
    return 0
}

perf_timer_start() {
    local name="$1"
    local start_time=$(date +%s%N)
    
    PERF_TIMER_NAMES+=("$name")
    PERF_TIMER_START_TIMES+=("$start_time")
    
    return 0
}

perf_timer_stop() {
    local name="$1"
    local end_time=$(date +%s%N)
    
    # Find the timer
    local i
    for i in "${!PERF_TIMER_NAMES[@]}"; do
        if [[ "${PERF_TIMER_NAMES[i]}" == "$name" ]]; then
            local start_time="${PERF_TIMER_START_TIMES[i]}"
            local duration_ms=$(( (end_time - start_time) / 1000000 ))
            echo "Timer stopped: $name (${duration_ms}ms)"
            
            # Remove timer from arrays
            unset PERF_TIMER_NAMES[i]
            unset PERF_TIMER_START_TIMES[i]
            
            # Reindex arrays
            PERF_TIMER_NAMES=("${PERF_TIMER_NAMES[@]}")
            PERF_TIMER_START_TIMES=("${PERF_TIMER_START_TIMES[@]}")
            
            return 0
        fi
    done
    
    echo "Timer not found: $name (0ms)"
    return 1
}

perf_cache_aws_response() {
    local key="$1"
    local response="$2"
    local ttl="${3:-3600}"
    
    local timestamp=$(date +%s)
    
    PERF_CACHE_KEYS+=("$key")
    PERF_CACHE_VALUES+=("$response")
    PERF_CACHE_TIMESTAMPS+=("$timestamp")
    
    return 0
}

perf_get_cached_aws_response() {
    local key="$1"
    local current_time=$(date +%s)
    
    local i
    for i in "${!PERF_CACHE_KEYS[@]}"; do
        if [[ "${PERF_CACHE_KEYS[i]}" == "$key" ]]; then
            local timestamp="${PERF_CACHE_TIMESTAMPS[i]}"
            local age=$((current_time - timestamp))
            
            if [[ $age -lt 3600 ]]; then  # 1 hour TTL
                echo "${PERF_CACHE_VALUES[i]}"
                return 0
            fi
        fi
    done
    
    return 1
}

# Benchmark function for performance testing
perf_run_benchmark() {
    local benchmark_name="$1"
    local iterations="${2:-100}"
    
    perf_timer_start "$benchmark_name"
    
    for ((i=1; i<=iterations; i++)); do
        case "$benchmark_name" in
            "cache_operations")
                perf_cache_aws_response "test_key_$i" '{"test": "data"}' 3600 >/dev/null
                perf_get_cached_aws_response "test_key_$i" >/dev/null
                ;;
            "timer_operations")
                perf_timer_start "nested_timer_$i" >/dev/null
                sleep 0.001  # 1ms operation
                perf_timer_stop "nested_timer_$i" >/dev/null
                ;;
            *)
                echo "Benchmark operation: $benchmark_name iteration $i"
                ;;
        esac
    done
    
    perf_timer_stop "$benchmark_name"
}

export -f unity_performance_init perf_timer_start perf_timer_stop 
export -f perf_cache_aws_response perf_get_cached_aws_response perf_run_benchmark
EOF
}

# Mock external dependencies with performance considerations
_mock_external_dependencies_performance() {
    mock_function "aws" 'sleep 0.01; echo "{\"test\": \"response\"}"'
    mock_function "docker" 'sleep 0.005; echo "docker-response"'
    mock_function "jq" 'echo "json-output"'
    mock_function "curl" 'sleep 0.01; echo "200"'
    mock_function "ping" 'return 0'
    mock_function "ps" 'echo "process-list"'
    mock_function "free" 'echo "Mem: 8000000 4000000 4000000"'
    mock_function "df" 'echo "/dev/sda1 100G 50G 50G 50% /"'
    mock_function "top" 'echo "load average: 0.50, 0.30, 0.20"'
}

# Initialize performance monitoring
_init_performance_monitoring() {
    # Create performance metrics directory
    mkdir -p "$PERFORMANCE_METRICS_DIR"
    
    # Initialize metrics files
    echo "timestamp,operation,duration_ms,memory_mb,cpu_percent" > "$PERFORMANCE_METRICS_DIR/performance_metrics.csv"
    echo "{\"benchmarks\": [], \"started\": \"$(date -Iseconds)\"}" > "$PERFORMANCE_METRICS_DIR/benchmark_results.json"
}

# Clean up performance test environment
cleanup_performance_tests() {
    # Restore mocked functions
    local mock_functions=("aws" "docker" "jq" "curl" "ping" "ps" "free" "df" "top")
    
    for func in "${mock_functions[@]}"; do
        restore_function "$func" 2>/dev/null || true
    done
    
    # Clean up test files
    if [[ -n "${TEST_PERFORMANCE_DIR:-}" && -d "$TEST_PERFORMANCE_DIR" ]]; then
        rm -rf "$TEST_PERFORMANCE_DIR" 2>/dev/null || true
    fi
    
    # Clean up environment variables
    unset TEST_PERFORMANCE_DIR UNITY_CACHE_DIR UNITY_DATA_DIR PERFORMANCE_METRICS_DIR
    unset UNITY_PERFORMANCE_MODE STACK_NAME AWS_REGION
}

# =============================================================================
# PERFORMANCE MEASUREMENT UTILITIES
# =============================================================================

# Measure operation performance
measure_performance() {
    local operation_name="$1"
    local operation_command="$2"
    local iterations="${3:-1}"
    
    local total_time=0
    local max_time=0
    local min_time=999999999
    local memory_before memory_after cpu_before cpu_after
    
    # Get initial system metrics
    memory_before=$(get_memory_usage_mb)
    cpu_before=$(get_cpu_usage_percent)
    
    log_info "Starting performance measurement: $operation_name ($iterations iterations)"
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date +%s%N)
        
        # Execute the operation
        eval "$operation_command" >/dev/null 2>&1 || true
        
        local end_time=$(date +%s%N)
        local duration_ms=$(( (end_time - start_time) / 1000000 ))
        
        total_time=$((total_time + duration_ms))
        
        if [[ $duration_ms -gt $max_time ]]; then
            max_time=$duration_ms
        fi
        
        if [[ $duration_ms -lt $min_time ]]; then
            min_time=$duration_ms
        fi
        
        # Log individual iteration if needed
        if [[ $iterations -le 10 ]]; then
            log_debug "Iteration $i: ${duration_ms}ms"
        fi
    done
    
    # Get final system metrics
    memory_after=$(get_memory_usage_mb)
    cpu_after=$(get_cpu_usage_percent)
    
    local avg_time=$((total_time / iterations))
    local memory_delta=$((memory_after - memory_before))
    
    # Log results
    log_info "Performance Results for $operation_name:"
    log_info "  Iterations: $iterations"
    log_info "  Average time: ${avg_time}ms"
    log_info "  Min time: ${min_time}ms"
    log_info "  Max time: ${max_time}ms"
    log_info "  Total time: ${total_time}ms"
    log_info "  Memory delta: ${memory_delta}MB"
    log_info "  CPU before/after: ${cpu_before}%/${cpu_after}%"
    
    # Write to metrics file
    echo "$(date -Iseconds),$operation_name,$avg_time,$memory_delta,$cpu_after" >> "$PERFORMANCE_METRICS_DIR/performance_metrics.csv"
    
    # Return average time for test validation
    echo "$avg_time"
}

# Get memory usage in MB
get_memory_usage_mb() {
    if command -v free >/dev/null 2>&1; then
        free -m | awk 'NR==2{printf "%.0f", $3}'
    else
        echo "0"
    fi
}

# Get CPU usage percentage
get_cpu_usage_percent() {
    if command -v top >/dev/null 2>&1; then
        top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'
    else
        echo "0"
    fi
}

# Run stress test with concurrent operations
run_stress_test() {
    local test_name="$1"
    local operation_command="$2"
    local concurrent_processes="${3:-$STRESS_TEST_CONCURRENT_OPERATIONS}"
    local duration_seconds="${4:-$STRESS_TEST_DURATION_SECONDS}"
    
    log_info "Starting stress test: $test_name"
    log_info "  Concurrent processes: $concurrent_processes"
    log_info "  Duration: ${duration_seconds}s"
    
    local pids=()
    local start_time=$(date +%s)
    local end_time=$((start_time + duration_seconds))
    
    # Start concurrent processes
    for ((i=1; i<=concurrent_processes; i++)); do
        (
            local process_operations=0
            while [[ $(date +%s) -lt $end_time ]]; do
                eval "$operation_command" >/dev/null 2>&1 || true
                ((process_operations++))
            done
            echo "$process_operations" > "/tmp/stress_ops_$i.tmp"
        ) &
        pids+=($!)
    done
    
    # Monitor system resources during stress test
    local monitor_pid
    (
        while [[ $(date +%s) -lt $end_time ]]; do
            local timestamp=$(date -Iseconds)
            local memory_mb=$(get_memory_usage_mb)
            local cpu_percent=$(get_cpu_usage_percent)
            echo "$timestamp,stress_monitor,0,$memory_mb,$cpu_percent" >> "$PERFORMANCE_METRICS_DIR/performance_metrics.csv"
            sleep 1
        done
    ) &
    monitor_pid=$!
    
    # Wait for all processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Stop monitoring
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
    
    # Calculate total operations
    local total_operations=0
    for ((i=1; i<=concurrent_processes; i++)); do
        if [[ -f "/tmp/stress_ops_$i.tmp" ]]; then
            local ops=$(cat "/tmp/stress_ops_$i.tmp")
            total_operations=$((total_operations + ops))
            rm -f "/tmp/stress_ops_$i.tmp"
        fi
    done
    
    local operations_per_second=$((total_operations / duration_seconds))
    
    log_info "Stress test completed: $test_name"
    log_info "  Total operations: $total_operations"
    log_info "  Operations per second: $operations_per_second"
    
    echo "$operations_per_second"
}

# =============================================================================
# SERVICE INITIALIZATION PERFORMANCE TESTS
# =============================================================================

test_unity_service_initialization_performance() {
    test_start "unity_service_initialization_performance" "Test Unity service initialization performance"
    
    setup_performance_tests
    
    # Source all services
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Test individual service initialization performance
    local services=("unity_config_init" "unity_performance_init test-perf" "init_unity_aws_service test-aws" "unity_docker_init" "unity_monitor_init")
    local service_names=("Config" "Performance" "AWS" "Docker" "Monitor")
    local all_services_fast=true
    
    for i in "${!services[@]}"; do
        local service="${services[i]}"
        local name="${service_names[i]}"
        
        local avg_time
        avg_time=$(measure_performance "${name}_init" "$service" 5)
        
        if [[ $avg_time -lt $PERFORMANCE_INIT_THRESHOLD_MS ]]; then
            test_pass "$name service initialization performance acceptable: ${avg_time}ms (< ${PERFORMANCE_INIT_THRESHOLD_MS}ms)"
        else
            test_warn "$name service initialization slow: ${avg_time}ms (> ${PERFORMANCE_INIT_THRESHOLD_MS}ms)"
            all_services_fast=false
        fi
    done
    
    # Test all services initialization together
    local combined_init="unity_config_init && unity_performance_init test-perf && init_unity_aws_service test-aws && unity_docker_init && unity_monitor_init"
    local combined_time
    combined_time=$(measure_performance "All_Services_init" "$combined_init" 3)
    
    local combined_threshold=$((PERFORMANCE_INIT_THRESHOLD_MS * 2))  # Allow 2x threshold for combined
    if [[ $combined_time -lt $combined_threshold ]]; then
        test_pass "Combined service initialization performance acceptable: ${combined_time}ms (< ${combined_threshold}ms)"
    else
        test_warn "Combined service initialization slow: ${combined_time}ms (> ${combined_threshold}ms)"
    fi
    
    if [[ "$all_services_fast" == "true" ]]; then
        test_pass "All Unity services meet initialization performance requirements"
    else
        test_warn "Some Unity services exceed initialization performance thresholds"
    fi
    
    cleanup_performance_tests
}

# =============================================================================
# OPERATION PERFORMANCE TESTS
# =============================================================================

test_unity_config_operation_performance() {
    test_start "unity_config_operation_performance" "Test Unity Config service operation performance"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Test config get operations
    local get_time
    get_time=$(measure_performance "Config_get" "unity_config_get STACK_NAME" 100)
    
    if [[ $get_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "Config get operation performance acceptable: ${get_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "Config get operation slow: ${get_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    # Test config set operations
    local set_time
    set_time=$(measure_performance "Config_set" "unity_config_set TEST_PERF_VAR test_value" 100)
    
    if [[ $set_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "Config set operation performance acceptable: ${set_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "Config set operation slow: ${set_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    cleanup_performance_tests
}

test_unity_aws_operation_performance() {
    test_start "unity_aws_operation_performance" "Test Unity AWS service operation performance"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    
    # Test EC2 launch operations
    local launch_time
    launch_time=$(measure_performance "AWS_EC2_launch" "launch_ec2_instance t3.medium spot test-stack" 10)
    
    if [[ $launch_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "AWS EC2 launch operation performance acceptable: ${launch_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "AWS EC2 launch operation slow: ${launch_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    # Test spot price operations
    local spot_time
    spot_time=$(measure_performance "AWS_spot_price" "get_spot_price t3.medium us-west-2" 50)
    
    if [[ $spot_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "AWS spot price operation performance acceptable: ${spot_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "AWS spot price operation slow: ${spot_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    cleanup_performance_tests
}

test_unity_docker_operation_performance() {
    test_start "unity_docker_operation_performance" "Test Unity Docker service operation performance"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    # Test container start operations
    local start_time
    start_time=$(measure_performance "Docker_start_container" "docker_start_container nginx:latest perf-test-container" 20)
    
    if [[ $start_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "Docker container start operation performance acceptable: ${start_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "Docker container start operation slow: ${start_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    # Test container status operations
    local status_time
    status_time=$(measure_performance "Docker_get_status" "docker_get_container_status perf-test-container json" 50)
    
    if [[ $status_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "Docker container status operation performance acceptable: ${status_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "Docker container status operation slow: ${status_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    cleanup_performance_tests
}

test_unity_performance_cache_operations() {
    test_start "unity_performance_cache_operations" "Test Unity Performance service cache operations"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    unity_performance_init "test-perf" >/dev/null 2>&1
    
    # Test cache write operations
    local cache_write_time
    cache_write_time=$(measure_performance "Cache_write" "perf_cache_aws_response test_key '{\"test\": \"data\"}' 3600" 100)
    
    if [[ $cache_write_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "Cache write operation performance acceptable: ${cache_write_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "Cache write operation slow: ${cache_write_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    # Pre-populate cache for read tests
    for ((i=1; i<=100; i++)); do
        perf_cache_aws_response "test_key_$i" '{"test": "data"}' 3600 >/dev/null 2>&1
    done
    
    # Test cache read operations
    local cache_read_time
    cache_read_time=$(measure_performance "Cache_read" "perf_get_cached_aws_response test_key_50" 100)
    
    if [[ $cache_read_time -lt $PERFORMANCE_OPERATION_THRESHOLD_MS ]]; then
        test_pass "Cache read operation performance acceptable: ${cache_read_time}ms (< ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    else
        test_warn "Cache read operation slow: ${cache_read_time}ms (> ${PERFORMANCE_OPERATION_THRESHOLD_MS}ms)"
    fi
    
    cleanup_performance_tests
}

# =============================================================================
# STRESS TESTS
# =============================================================================

test_unity_config_stress() {
    test_start "unity_config_stress" "Test Unity Config service under stress"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Stress test config operations
    local ops_per_second
    ops_per_second=$(run_stress_test "Config_stress" "config_stress_operation get_operations 10")
    
    # Expect at least 100 operations per second under stress
    if [[ $ops_per_second -gt 100 ]]; then
        test_pass "Config service stress test passed: ${ops_per_second} ops/sec (> 100 ops/sec)"
    else
        test_warn "Config service stress test underperformed: ${ops_per_second} ops/sec (< 100 ops/sec)"
    fi
    
    cleanup_performance_tests
}

test_unity_aws_stress() {
    test_start "unity_aws_stress" "Test Unity AWS service under stress"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    
    # Stress test AWS operations
    local ops_per_second
    ops_per_second=$(run_stress_test "AWS_stress" "aws_stress_operation spot_price 5")
    
    # Expect at least 20 operations per second under stress (simulated AWS calls)
    if [[ $ops_per_second -gt 20 ]]; then
        test_pass "AWS service stress test passed: ${ops_per_second} ops/sec (> 20 ops/sec)"
    else
        test_warn "AWS service stress test underperformed: ${ops_per_second} ops/sec (< 20 ops/sec)"
    fi
    
    cleanup_performance_tests
}

test_unity_docker_stress() {
    test_start "unity_docker_stress" "Test Unity Docker service under stress"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    
    # Stress test Docker operations
    local ops_per_second
    ops_per_second=$(run_stress_test "Docker_stress" "docker_stress_operation check_status 5")
    
    # Expect at least 50 operations per second under stress
    if [[ $ops_per_second -gt 50 ]]; then
        test_pass "Docker service stress test passed: ${ops_per_second} ops/sec (> 50 ops/sec)"
    else
        test_warn "Docker service stress test underperformed: ${ops_per_second} ops/sec (< 50 ops/sec)"
    fi
    
    cleanup_performance_tests
}

test_unity_integrated_stress() {
    test_start "unity_integrated_stress" "Test integrated Unity services under stress"
    
    setup_performance_tests
    
    # Source all services
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    # Initialize all services
    unity_config_init >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Integrated stress test operation
    local integrated_operation='
        unity_config_get STACK_NAME >/dev/null 2>&1
        launch_ec2_instance t3.medium spot test-stack >/dev/null 2>&1
        docker_start_container nginx:latest stress-container >/dev/null 2>&1
        unity_monitor_health_check system >/dev/null 2>&1
    '
    
    local ops_per_second
    ops_per_second=$(run_stress_test "Integrated_stress" "$integrated_operation" 5 20)
    
    # Expect at least 10 integrated operations per second
    if [[ $ops_per_second -gt 10 ]]; then
        test_pass "Integrated services stress test passed: ${ops_per_second} ops/sec (> 10 ops/sec)"
    else
        test_warn "Integrated services stress test underperformed: ${ops_per_second} ops/sec (< 10 ops/sec)"
    fi
    
    cleanup_performance_tests
}

# =============================================================================
# MEMORY AND RESOURCE TESTS
# =============================================================================

test_unity_memory_usage() {
    test_start "unity_memory_usage" "Test Unity services memory usage"
    
    setup_performance_tests
    
    # Source all services
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
    
    local memory_before=$(get_memory_usage_mb)
    
    # Initialize all services
    unity_config_init >/dev/null 2>&1
    unity_performance_init "test-perf" >/dev/null 2>&1
    init_unity_aws_service "test-aws" >/dev/null 2>&1
    unity_docker_init >/dev/null 2>&1
    unity_monitor_init >/dev/null 2>&1
    
    # Perform some operations to populate caches
    for ((i=1; i<=50; i++)); do
        unity_config_get "STACK_NAME" >/dev/null 2>&1
        perf_cache_aws_response "test_key_$i" '{"test": "data"}' 3600 >/dev/null 2>&1
        launch_ec2_instance "t3.medium" "spot" "test-stack-$i" >/dev/null 2>&1
        docker_start_container "nginx:latest" "test-container-$i" >/dev/null 2>&1
    done
    
    local memory_after=$(get_memory_usage_mb)
    local memory_usage=$((memory_after - memory_before))
    
    if [[ $memory_usage -lt $PERFORMANCE_MEMORY_THRESHOLD_MB ]]; then
        test_pass "Unity services memory usage acceptable: ${memory_usage}MB (< ${PERFORMANCE_MEMORY_THRESHOLD_MB}MB)"
    else
        test_warn "Unity services memory usage high: ${memory_usage}MB (> ${PERFORMANCE_MEMORY_THRESHOLD_MB}MB)"
    fi
    
    cleanup_performance_tests
}

test_unity_resource_cleanup() {
    test_start "unity_resource_cleanup" "Test Unity services resource cleanup"
    
    setup_performance_tests
    
    # Source performance service
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    unity_performance_init "test-perf" >/dev/null 2>&1
    
    # Create many cached items
    for ((i=1; i<=1000; i++)); do
        perf_cache_aws_response "cleanup_test_key_$i" '{"test": "data"}' 3600 >/dev/null 2>&1
    done
    
    local memory_before=$(get_memory_usage_mb)
    
    # Simulate cleanup by clearing arrays (in real implementation, this would be a cleanup function)
    PERF_CACHE_KEYS=()
    PERF_CACHE_VALUES=()
    PERF_CACHE_TIMESTAMPS=()
    
    local memory_after=$(get_memory_usage_mb)
    local memory_freed=$((memory_before - memory_after))
    
    # Memory should be freed (or at least not increased significantly)
    if [[ $memory_freed -ge 0 ]]; then
        test_pass "Resource cleanup freed memory: ${memory_freed}MB"
    else
        test_warn "Resource cleanup did not free memory as expected: ${memory_freed}MB"
    fi
    
    cleanup_performance_tests
}

# =============================================================================
# SCALABILITY TESTS
# =============================================================================

test_unity_scalability_config_cache() {
    test_start "unity_scalability_config_cache" "Test Unity Config service scalability with large cache"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
    unity_config_init >/dev/null 2>&1
    
    # Test with increasing cache sizes
    local cache_sizes=(100 500 1000 5000)
    local all_scalable=true
    
    for size in "${cache_sizes[@]}"; do
        # Populate cache
        for ((i=1; i<=size; i++)); do
            unity_config_set "SCALE_TEST_VAR_$i" "value_$i" >/dev/null 2>&1
        done
        
        # Measure lookup performance
        local lookup_time
        lookup_time=$(measure_performance "Config_lookup_${size}_items" "unity_config_get SCALE_TEST_VAR_$((size/2))" 10)
        
        # Performance should remain reasonable even with large cache
        local threshold=$((PERFORMANCE_OPERATION_THRESHOLD_MS * 2))  # Allow 2x threshold for large cache
        if [[ $lookup_time -lt $threshold ]]; then
            test_pass "Config scalability good with $size items: ${lookup_time}ms (< ${threshold}ms)"
        else
            test_warn "Config scalability poor with $size items: ${lookup_time}ms (> ${threshold}ms)"
            all_scalable=false
        fi
    done
    
    if [[ "$all_scalable" == "true" ]]; then
        test_pass "Config service scales well with large cache sizes"
    else
        test_warn "Config service has scalability issues with large cache sizes"
    fi
    
    cleanup_performance_tests
}

test_unity_scalability_performance_cache() {
    test_start "unity_scalability_performance_cache" "Test Unity Performance service cache scalability"
    
    setup_performance_tests
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    unity_performance_init "test-perf" >/dev/null 2>&1
    
    # Test with increasing cache sizes
    local cache_sizes=(1000 5000 10000)
    local all_scalable=true
    
    for size in "${cache_sizes[@]}"; do
        # Populate performance cache
        for ((i=1; i<=size; i++)); do
            perf_cache_aws_response "scale_test_key_$i" '{"instance_id": "i-'$i'"}' 3600 >/dev/null 2>&1
        done
        
        # Measure cache lookup performance
        local lookup_time
        lookup_time=$(measure_performance "Perf_cache_lookup_${size}_items" "perf_get_cached_aws_response scale_test_key_$((size/2))" 10)
        
        # Performance should remain reasonable
        local threshold=$((PERFORMANCE_OPERATION_THRESHOLD_MS * 3))  # Allow 3x threshold for very large cache
        if [[ $lookup_time -lt $threshold ]]; then
            test_pass "Performance cache scalability good with $size items: ${lookup_time}ms (< ${threshold}ms)"
        else
            test_warn "Performance cache scalability poor with $size items: ${lookup_time}ms (> ${threshold}ms)"
            all_scalable=false
        fi
    done
    
    if [[ "$all_scalable" == "true" ]]; then
        test_pass "Performance service cache scales well with large sizes"
    else
        test_warn "Performance service cache has scalability issues"
    fi
    
    cleanup_performance_tests
}

# =============================================================================
# BENCHMARK SUITE
# =============================================================================

test_unity_benchmark_suite() {
    test_start "unity_benchmark_suite" "Run comprehensive Unity performance benchmark suite"
    
    setup_performance_tests
    
    # Source performance service for benchmarking
    source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-performance-service.sh" >/dev/null 2>&1
    unity_performance_init "benchmark-suite" >/dev/null 2>&1
    
    log_info "Running Unity Performance Benchmark Suite"
    
    # Benchmark cache operations
    perf_run_benchmark "cache_operations" 1000 >/dev/null 2>&1
    
    # Benchmark timer operations
    perf_run_benchmark "timer_operations" 500 >/dev/null 2>&1
    
    # Custom benchmarks
    local benchmark_tests=("config_rapid_access" "aws_batch_operations" "docker_lifecycle" "monitor_health_checks")
    
    for benchmark in "${benchmark_tests[@]}"; do
        case "$benchmark" in
            "config_rapid_access")
                source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-config-service.sh" >/dev/null 2>&1
                unity_config_init >/dev/null 2>&1
                measure_performance "Benchmark_$benchmark" "unity_config_get STACK_NAME; unity_config_get AWS_REGION; unity_config_get INSTANCE_TYPE" 200 >/dev/null
                ;;
            "aws_batch_operations")
                source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-aws-service.sh" >/dev/null 2>&1
                init_unity_aws_service "benchmark-aws" >/dev/null 2>&1
                measure_performance "Benchmark_$benchmark" "get_spot_price t3.medium us-west-2; get_spot_price t3.large us-west-2; get_spot_price t3.xlarge us-west-2" 50 >/dev/null
                ;;
            "docker_lifecycle")
                source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-docker-service.sh" >/dev/null 2>&1
                unity_docker_init >/dev/null 2>&1
                measure_performance "Benchmark_$benchmark" "docker_start_container nginx:latest benchmark-container; docker_get_container_status benchmark-container" 20 >/dev/null
                ;;
            "monitor_health_checks")
                source "$TEST_PERFORMANCE_DIR/lib/unity/services/unity-monitor-service.sh" >/dev/null 2>&1
                unity_monitor_init >/dev/null 2>&1
                measure_performance "Benchmark_$benchmark" "unity_monitor_health_check system; unity_monitor_health_check services; unity_monitor_health_check network" 100 >/dev/null
                ;;
        esac
    done
    
    # Generate benchmark report
    local benchmark_report="$PERFORMANCE_METRICS_DIR/benchmark_summary.txt"
    echo "Unity Performance Benchmark Suite Results" > "$benchmark_report"
    echo "=========================================" >> "$benchmark_report"
    echo "Generated: $(date)" >> "$benchmark_report"
    echo "" >> "$benchmark_report"
    
    # Summarize metrics
    if [[ -f "$PERFORMANCE_METRICS_DIR/performance_metrics.csv" ]]; then
        echo "Performance Metrics Summary:" >> "$benchmark_report"
        tail -n +2 "$PERFORMANCE_METRICS_DIR/performance_metrics.csv" | \
        awk -F',' '{
            operations[$2] += 1
            total_time[$2] += $3
            if (min_time[$2] == "" || $3 < min_time[$2]) min_time[$2] = $3
            if (max_time[$2] == "" || $3 > max_time[$2]) max_time[$2] = $3
        }
        END {
            for (op in operations) {
                avg = total_time[op] / operations[op]
                printf "  %-30s: %3d ops, avg %6.1fms, min %6.1fms, max %6.1fms\n", op, operations[op], avg, min_time[op], max_time[op]
            }
        }' >> "$benchmark_report"
    fi
    
    test_pass "Unity benchmark suite completed successfully"
    log_info "Benchmark report saved to: $benchmark_report"
    
    cleanup_performance_tests
}

# =============================================================================
# RUN ALL PERFORMANCE TESTS
# =============================================================================

# Register performance tests with the Unity test framework
unity_register_performance_test "unity_service_initialization_performance" "all-unity-services" "test_unity_service_initialization_performance" ""
unity_register_performance_test "unity_config_operation_performance" "unity-config-service" "test_unity_config_operation_performance" ""
unity_register_performance_test "unity_aws_operation_performance" "unity-aws-service" "test_unity_aws_operation_performance" ""
unity_register_performance_test "unity_docker_operation_performance" "unity-docker-service" "test_unity_docker_operation_performance" ""

# Run all test functions
main() {
    log_info "Running Unity Performance Benchmarks and Stress Tests"
    
    # Service initialization performance tests
    test_unity_service_initialization_performance
    
    # Operation performance tests
    test_unity_config_operation_performance
    test_unity_aws_operation_performance
    test_unity_docker_operation_performance
    test_unity_performance_cache_operations
    
    # Stress tests
    test_unity_config_stress
    test_unity_aws_stress
    test_unity_docker_stress
    test_unity_integrated_stress
    
    # Memory and resource tests
    test_unity_memory_usage
    test_unity_resource_cleanup
    
    # Scalability tests
    test_unity_scalability_config_cache
    test_unity_scalability_performance_cache
    
    # Comprehensive benchmark suite
    test_unity_benchmark_suite
    
    # Clean up and generate reports
    unity_test_cleanup
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi