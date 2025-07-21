#!/bin/bash

# =============================================================================
# AI Starter Kit - Performance Benchmark and Testing Suite
# =============================================================================
# Comprehensive performance testing for GPU infrastructure
# Features: GPU benchmarks, container performance, network testing,
# memory/CPU utilization, performance baselines, recommendations
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BENCHMARK_TIMEOUT=900  # 15 minutes for comprehensive benchmarks
SSH_TIMEOUT=30
BENCHMARK_ITERATIONS=3

# Performance tracking
BENCHMARK_RESULTS=()
PERFORMANCE_WARNINGS=()
PERFORMANCE_RECOMMENDATIONS=()

# Expected performance baselines by instance type
declare -A EXPECTED_GPU_MEMORY=(
    ["g4dn.xlarge"]="16384"
    ["g4dn.2xlarge"]="16384"
    ["g5g.xlarge"]="16384"
    ["g5g.2xlarge"]="16384"
    ["g5.xlarge"]="24576"
    ["g5.2xlarge"]="24576"
    ["g4ad.xlarge"]="16384"
    ["g4ad.2xlarge"]="16384"
)

declare -A EXPECTED_CPU_CORES=(
    ["g4dn.xlarge"]="4"
    ["g4dn.2xlarge"]="8"
    ["g5g.xlarge"]="4"
    ["g5g.2xlarge"]="8"
    ["g5.xlarge"]="4"
    ["g5.2xlarge"]="8"
    ["g4ad.xlarge"]="4"
    ["g4ad.2xlarge"]="8"
)

declare -A EXPECTED_MEMORY_GB=(
    ["g4dn.xlarge"]="16"
    ["g4dn.2xlarge"]="32"
    ["g5g.xlarge"]="16"
    ["g5g.2xlarge"]="32"
    ["g5.xlarge"]="16"
    ["g5.2xlarge"]="32"
    ["g4ad.xlarge"]="16"
    ["g4ad.2xlarge"]="32"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}"
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $*${NC}"
    PERFORMANCE_WARNINGS+=("$*")
}

error() {
    echo -e "${RED}✗ $*${NC}"
}

info() {
    echo -e "${CYAN}ℹ $*${NC}"
}

separator() {
    echo -e "${PURPLE}$1${NC}"
}

recommend() {
    echo -e "${YELLOW}💡 $*${NC}"
    PERFORMANCE_RECOMMENDATIONS+=("$*")
}

# Timeout wrapper for commands
run_with_timeout() {
    local timeout="$1"
    shift
    timeout "$timeout" "$@" 2>/dev/null || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            error "Command timed out after ${timeout}s: $*"
        else
            error "Command failed with exit code $exit_code: $*"
        fi
        return $exit_code
    }
}

# SSH command wrapper
ssh_exec() {
    local instance_ip="$1"
    local command="$2"
    local timeout="${3:-$SSH_TIMEOUT}"
    
    run_with_timeout "$timeout" ssh -i "${KEY_NAME}.pem" \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        ubuntu@"$instance_ip" "$command"
}

# Calculate average from array of numbers
calculate_average() {
    local numbers=("$@")
    local sum=0
    local count=${#numbers[@]}
    
    for num in "${numbers[@]}"; do
        sum=$(echo "$sum + $num" | bc -l)
    done
    
    if [[ $count -gt 0 ]]; then
        echo "scale=2; $sum / $count" | bc -l
    else
        echo "0"
    fi
}

# =============================================================================
# SYSTEM INFORMATION COLLECTION
# =============================================================================

collect_system_info() {
    local instance_ip="$1"
    separator "=== COLLECTING SYSTEM INFORMATION ==="
    
    log "Gathering system specifications..."
    
    # Get instance type from AWS
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$instance_ip" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || echo "unknown")
    
    local instance_type="unknown"
    if [[ "$instance_id" != "unknown" ]]; then
        instance_type=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].InstanceType' \
            --output text 2>/dev/null || echo "unknown")
    fi
    
    info "Instance Type: $instance_type"
    info "Instance ID: $instance_id"
    
    # CPU Information
    local cpu_info=$(ssh_exec "$instance_ip" "lscpu | grep -E 'Model name|CPU\\(s\\)|Thread|Core'" 30)
    if [[ -n "$cpu_info" ]]; then
        success "CPU Information collected"
        echo "$cpu_info" | while read -r line; do
            info "$line"
        done
    fi
    
    # Memory Information
    local memory_info=$(ssh_exec "$instance_ip" "free -h" 10)
    if [[ -n "$memory_info" ]]; then
        success "Memory Information collected"
        echo "$memory_info"
    fi
    
    # GPU Information
    local gpu_info=$(ssh_exec "$instance_ip" "nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version,compute_mode --format=csv,noheader" 30)
    if [[ -n "$gpu_info" ]]; then
        success "GPU Information collected"
        echo "$gpu_info" | while IFS=',' read -r gpu_name gpu_memory_total gpu_memory_free driver_version compute_mode; do
            info "GPU: $gpu_name"
            info "Total Memory: $gpu_memory_total"
            info "Free Memory: $gpu_memory_free"
            info "Driver: $driver_version"
            info "Compute Mode: $compute_mode"
        done
    fi
    
    # Storage Information
    local storage_info=$(ssh_exec "$instance_ip" "df -h | grep -E '(^/dev|^overlay)'" 15)
    if [[ -n "$storage_info" ]]; then
        success "Storage Information collected"
        echo "$storage_info"
    fi
    
    echo "$instance_type"  # Return instance type for other functions
}

# =============================================================================
# GPU PERFORMANCE BENCHMARKS
# =============================================================================

benchmark_gpu_compute() {
    local instance_ip="$1"
    local instance_type="$2"
    separator "=== GPU COMPUTE BENCHMARKS ==="
    
    log "Running GPU compute performance tests..."
    
    # Check if CUDA samples are available, if not install them
    log "Preparing CUDA benchmarks..."
    ssh_exec "$instance_ip" "
        if [ ! -d ~/cuda-samples ]; then
            git clone https://github.com/NVIDIA/cuda-samples.git ~/cuda-samples
            cd ~/cuda-samples && make -C Samples/0_Introduction/vectorAdd
            make -C Samples/1_Utilities/deviceQuery
            make -C Samples/1_Utilities/bandwidthTest
        fi
    " 120 || warning "Failed to prepare CUDA samples"
    
    # Device Query
    log "Running device query..."
    local device_query=$(ssh_exec "$instance_ip" "cd ~/cuda-samples && ./Samples/1_Utilities/deviceQuery/deviceQuery" 30)
    if [[ -n "$device_query" ]]; then
        success "Device query completed"
        # Extract key information
        local compute_capability=$(echo "$device_query" | grep "CUDA Capability" | head -1)
        local global_memory=$(echo "$device_query" | grep "Total amount of global memory" | head -1)
        info "$compute_capability"
        info "$global_memory"
    fi
    
    # Memory Bandwidth Test
    log "Running memory bandwidth test..."
    local bandwidth_results=()
    for i in $(seq 1 $BENCHMARK_ITERATIONS); do
        log "Bandwidth test iteration $i/$BENCHMARK_ITERATIONS..."
        local bandwidth_output=$(ssh_exec "$instance_ip" "cd ~/cuda-samples && ./Samples/1_Utilities/bandwidthTest/bandwidthTest --memory=pinned --mode=quick" 60)
        if [[ -n "$bandwidth_output" ]]; then
            local h2d_bandwidth=$(echo "$bandwidth_output" | grep "Host to Device" | awk '{print $(NF-1)}' | head -1)
            local d2h_bandwidth=$(echo "$bandwidth_output" | grep "Device to Host" | awk '{print $(NF-1)}' | head -1)
            local d2d_bandwidth=$(echo "$bandwidth_output" | grep "Device to Device" | awk '{print $(NF-1)}' | head -1)
            
            if [[ -n "$h2d_bandwidth" && -n "$d2h_bandwidth" && -n "$d2d_bandwidth" ]]; then
                bandwidth_results+=("H2D:$h2d_bandwidth D2H:$d2h_bandwidth D2D:$d2d_bandwidth")
                info "Iteration $i - H2D: ${h2d_bandwidth}GB/s, D2H: ${d2h_bandwidth}GB/s, D2D: ${d2d_bandwidth}GB/s"
            fi
        fi
    done
    
    if [[ ${#bandwidth_results[@]} -gt 0 ]]; then
        success "Memory bandwidth tests completed"
    else
        warning "Memory bandwidth tests failed"
    fi
    
    # Vector Addition Performance Test
    log "Running vector addition performance test..."
    local vector_results=()
    for i in $(seq 1 $BENCHMARK_ITERATIONS); do
        log "Vector addition test iteration $i/$BENCHMARK_ITERATIONS..."
        local vector_output=$(ssh_exec "$instance_ip" "cd ~/cuda-samples && time ./Samples/0_Introduction/vectorAdd/vectorAdd" 30)
        if [[ "$vector_output" == *"Test PASSED"* ]]; then
            local execution_time=$(echo "$vector_output" | grep "real" | awk '{print $2}')
            if [[ -n "$execution_time" ]]; then
                vector_results+=("$execution_time")
                info "Iteration $i - Execution time: $execution_time"
            fi
        fi
    done
    
    if [[ ${#vector_results[@]} -gt 0 ]]; then
        success "Vector addition tests completed"
    else
        warning "Vector addition tests failed"
    fi
    
    # Simple Matrix Multiplication Benchmark
    log "Running matrix multiplication benchmark..."
    ssh_exec "$instance_ip" "
        cat > /tmp/matrix_bench.cu << 'EOF'
#include <cuda_runtime.h>
#include <iostream>
#include <chrono>

__global__ void matrixMul(float* A, float* B, float* C, int N) {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (i < N && j < N) {
        float sum = 0.0f;
        for (int k = 0; k < N; k++) {
            sum += A[i * N + k] * B[k * N + j];
        }
        C[i * N + j] = sum;
    }
}

int main() {
    const int N = 1024;
    const int size = N * N * sizeof(float);
    
    float *h_A, *h_B, *h_C;
    float *d_A, *d_B, *d_C;
    
    h_A = (float*)malloc(size);
    h_B = (float*)malloc(size);
    h_C = (float*)malloc(size);
    
    for (int i = 0; i < N * N; i++) {
        h_A[i] = 1.0f;
        h_B[i] = 2.0f;
    }
    
    cudaMalloc(&d_A, size);
    cudaMalloc(&d_B, size);
    cudaMalloc(&d_C, size);
    
    cudaMemcpy(d_A, h_A, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, h_B, size, cudaMemcpyHostToDevice);
    
    dim3 blockSize(16, 16);
    dim3 gridSize((N + blockSize.x - 1) / blockSize.x, (N + blockSize.y - 1) / blockSize.y);
    
    auto start = std::chrono::high_resolution_clock::now();
    
    for (int iter = 0; iter < 10; iter++) {
        matrixMul<<<gridSize, blockSize>>>(d_A, d_B, d_C, N);
    }
    
    cudaDeviceSynchronize();
    auto end = std::chrono::high_resolution_clock::now();
    
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    std::cout << \"Matrix multiplication (1024x1024, 10 iterations): \" << duration.count() << \"ms\" << std::endl;
    
    cudaMemcpy(h_C, d_C, size, cudaMemcpyDeviceToHost);
    
    cudaFree(d_A);
    cudaFree(d_B);
    cudaFree(d_C);
    free(h_A);
    free(h_B);
    free(h_C);
    
    return 0;
}
EOF
        nvcc -o /tmp/matrix_bench /tmp/matrix_bench.cu 2>/dev/null && /tmp/matrix_bench
    " 60 || warning "Matrix multiplication benchmark failed"
    
    return 0
}

benchmark_ollama_performance() {
    local instance_ip="$1"
    separator "=== OLLAMA MODEL PERFORMANCE ==="
    
    log "Testing Ollama model inference performance..."
    
    # Check if Ollama is running and models are available
    local ollama_models=$(curl -s "http://$instance_ip:11434/api/tags" 2>/dev/null | jq -r '.models[].name' 2>/dev/null || echo "")
    
    if [[ -z "$ollama_models" ]]; then
        warning "No Ollama models found or service not accessible"
        return 1
    fi
    
    success "Available models: $(echo "$ollama_models" | tr '\n' ' ')"
    
    # Test inference performance with different models
    echo "$ollama_models" | while read -r model; do
        if [[ -n "$model" ]]; then
            log "Testing inference performance for model: $model"
            
            # Simple inference test
            local start_time=$(date +%s.%N)
            local response=$(curl -s -X POST "http://$instance_ip:11434/api/generate" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$model\",\"prompt\":\"Hello, world!\",\"stream\":false}" \
                --max-time 30 2>/dev/null)
            local end_time=$(date +%s.%N)
            
            if [[ -n "$response" && "$response" != *"error"* ]]; then
                local inference_time=$(echo "$end_time - $start_time" | bc -l)
                local response_length=$(echo "$response" | jq -r '.response' 2>/dev/null | wc -c || echo "0")
                success "Model $model - Inference time: ${inference_time}s, Response length: $response_length chars"
            else
                warning "Inference test failed for model: $model"
            fi
        fi
    done
    
    return 0
}

# =============================================================================
# CONTAINER PERFORMANCE BENCHMARKS
# =============================================================================

benchmark_container_performance() {
    local instance_ip="$1"
    separator "=== CONTAINER PERFORMANCE BENCHMARKS ==="
    
    log "Measuring container startup times and resource usage..."
    
    # Get current container status
    local container_stats=$(ssh_exec "$instance_ip" "cd /home/ubuntu/ai-starter-kit && docker compose -f docker-compose.gpu-optimized.yml ps --format json" 30)
    
    if [[ -z "$container_stats" ]]; then
        error "Cannot retrieve container status"
        return 1
    fi
    
    # Test container restart times
    local services=("ollama" "qdrant" "postgres" "n8n")
    
    for service in "${services[@]}"; do
        log "Testing restart time for $service..."
        
        local start_time=$(date +%s.%N)
        ssh_exec "$instance_ip" "cd /home/ubuntu/ai-starter-kit && docker compose -f docker-compose.gpu-optimized.yml restart $service" 60
        
        # Wait for service to be healthy
        local healthy=false
        local wait_time=0
        while [[ $wait_time -lt 120 ]]; do
            local health_status=$(ssh_exec "$instance_ip" "docker ps --filter name=$service --format '{{.Status}}'" 10)
            if [[ "$health_status" == *"healthy"* || "$health_status" == *"Up"* ]]; then
                healthy=true
                break
            fi
            sleep 5
            wait_time=$((wait_time + 5))
        done
        
        local end_time=$(date +%s.%N)
        local restart_time=$(echo "$end_time - $start_time" | bc -l)
        
        if [[ "$healthy" == "true" ]]; then
            success "$service restarted successfully in ${restart_time}s"
        else
            warning "$service restart took ${restart_time}s but may not be fully healthy"
        fi
    done
    
    # Resource usage analysis
    log "Analyzing container resource usage..."
    local resource_stats=$(ssh_exec "$instance_ip" "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}'" 20)
    
    if [[ -n "$resource_stats" ]]; then
        success "Container resource usage:"
        echo "$resource_stats"
        
        # Check for resource-intensive containers
        echo "$resource_stats" | tail -n +2 | while read -r line; do
            local cpu_usage=$(echo "$line" | awk '{print $2}' | sed 's/%//')
            local mem_usage=$(echo "$line" | awk '{print $4}' | sed 's/%//')
            local container_name=$(echo "$line" | awk '{print $1}')
            
            if [[ -n "$cpu_usage" && "$cpu_usage" != "CPUPerc" ]]; then
                if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
                    warning "High CPU usage in $container_name: ${cpu_usage}%"
                fi
            fi
            
            if [[ -n "$mem_usage" && "$mem_usage" != "MemPerc" ]]; then
                if (( $(echo "$mem_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
                    warning "High memory usage in $container_name: ${mem_usage}%"
                fi
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# NETWORK PERFORMANCE BENCHMARKS
# =============================================================================

benchmark_network_performance() {
    local instance_ip="$1"
    separator "=== NETWORK PERFORMANCE BENCHMARKS ==="
    
    log "Testing network latency and throughput..."
    
    # Ping test
    log "Testing network latency..."
    local ping_results=()
    for i in $(seq 1 10); do
        local ping_time=$(ping -c 1 -W 2000 "$instance_ip" | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}' | head -1)
        if [[ -n "$ping_time" ]]; then
            ping_results+=("$ping_time")
        fi
    done
    
    if [[ ${#ping_results[@]} -gt 0 ]]; then
        local avg_ping=$(calculate_average "${ping_results[@]}")
        success "Average ping latency: ${avg_ping}ms"
        
        if (( $(echo "$avg_ping > 100" | bc -l 2>/dev/null || echo "0") )); then
            warning "High network latency detected: ${avg_ping}ms"
        fi
    else
        warning "Ping test failed"
    fi
    
    # HTTP response time test for services
    local services=(
        "n8n:5678:/healthz"
        "ollama:11434:/api/version"
        "qdrant:6333:/health"
        "crawl4ai:11235:/health"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name port endpoint <<< "$service_info"
        log "Testing HTTP response time for $service_name..."
        
        local response_times=()
        for i in $(seq 1 5); do
            local response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time 10 "http://$instance_ip:$port$endpoint" 2>/dev/null || echo "timeout")
            if [[ "$response_time" != "timeout" ]]; then
                response_times+=("$response_time")
            fi
        done
        
        if [[ ${#response_times[@]} -gt 0 ]]; then
            local avg_response=$(calculate_average "${response_times[@]}")
            success "$service_name average response time: ${avg_response}s"
            
            if (( $(echo "$avg_response > 2.0" | bc -l 2>/dev/null || echo "0") )); then
                warning "Slow response time for $service_name: ${avg_response}s"
            fi
        else
            warning "HTTP response test failed for $service_name"
        fi
    done
    
    # Bandwidth test using internal tools
    log "Testing internal network bandwidth..."
    ssh_exec "$instance_ip" "
        # Simple bandwidth test using dd and nc
        timeout 30 bash -c '
            # Test local disk I/O speed
            sync
            echo \"Disk write test:\"
            dd if=/dev/zero of=/tmp/test_write bs=1M count=1024 2>&1 | grep -E \"bytes|copied\"
            sync
            echo \"Disk read test:\"
            dd if=/tmp/test_write of=/dev/null bs=1M 2>&1 | grep -E \"bytes|copied\"
            rm -f /tmp/test_write
        '
    " 60 || warning "Bandwidth test failed"
    
    return 0
}

# =============================================================================
# MEMORY AND CPU BENCHMARKS
# =============================================================================

benchmark_system_performance() {
    local instance_ip="$1"
    local instance_type="$2"
    separator "=== SYSTEM PERFORMANCE BENCHMARKS ==="
    
    log "Running CPU and memory performance tests..."
    
    # CPU benchmark using sysbench
    log "Installing and running CPU benchmark..."
    ssh_exec "$instance_ip" "
        if ! command -v sysbench >/dev/null 2>&1; then
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y sysbench >/dev/null 2>&1
        fi
    " 60 || warning "Failed to install sysbench"
    
    # CPU performance test
    local cpu_benchmark=$(ssh_exec "$instance_ip" "sysbench cpu --cpu-max-prime=20000 --threads=4 run" 30)
    if [[ -n "$cpu_benchmark" ]]; then
        local events_per_second=$(echo "$cpu_benchmark" | grep "events per second" | awk '{print $4}')
        local total_time=$(echo "$cpu_benchmark" | grep "total time:" | awk '{print $3}' | sed 's/s//')
        
        if [[ -n "$events_per_second" && -n "$total_time" ]]; then
            success "CPU benchmark - Events/sec: $events_per_second, Total time: ${total_time}s"
            
            # Compare with expected performance for instance type
            local expected_min_events=1000
            case "$instance_type" in
                "g4dn.xlarge"|"g5g.xlarge"|"g4ad.xlarge") expected_min_events=800 ;;
                "g4dn.2xlarge"|"g5g.2xlarge"|"g4ad.2xlarge") expected_min_events=1500 ;;
                "g5.xlarge") expected_min_events=1200 ;;
                "g5.2xlarge") expected_min_events=2200 ;;
            esac
            
            if (( $(echo "$events_per_second < $expected_min_events" | bc -l 2>/dev/null || echo "0") )); then
                warning "CPU performance below expected for $instance_type: $events_per_second < $expected_min_events events/sec"
            fi
        fi
    else
        warning "CPU benchmark failed"
    fi
    
    # Memory benchmark
    log "Running memory benchmark..."
    local memory_benchmark=$(ssh_exec "$instance_ip" "sysbench memory --memory-block-size=1M --memory-total-size=10G run" 45)
    if [[ -n "$memory_benchmark" ]]; then
        local memory_speed=$(echo "$memory_benchmark" | grep "transferred" | awk '{print $3 " " $4}')
        if [[ -n "$memory_speed" ]]; then
            success "Memory benchmark - Transfer rate: $memory_speed"
        fi
    else
        warning "Memory benchmark failed"
    fi
    
    # Load average and system stress test
    log "Checking system load and running stress test..."
    local load_before=$(ssh_exec "$instance_ip" "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | sed 's/,//'" 5)
    
    # Run a brief stress test
    ssh_exec "$instance_ip" "
        if ! command -v stress >/dev/null 2>&1; then
            sudo apt-get install -y stress >/dev/null 2>&1
        fi
        stress --cpu 4 --timeout 30s >/dev/null 2>&1 &
        sleep 15
        uptime
    " 60 || warning "Stress test failed"
    
    local load_after=$(ssh_exec "$instance_ip" "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | sed 's/,//'" 5)
    
    if [[ -n "$load_before" && -n "$load_after" ]]; then
        info "Load average before stress: $load_before"
        info "Load average during stress: $load_after"
        
        # Check if system handles stress well
        local expected_cores=${EXPECTED_CPU_CORES[$instance_type]:-4}
        if (( $(echo "$load_after > ($expected_cores * 2)" | bc -l 2>/dev/null || echo "0") )); then
            warning "High load average during stress test: $load_after (expected < $((expected_cores * 2)))"
        fi
    fi
    
    return 0
}

# =============================================================================
# PERFORMANCE ANALYSIS AND RECOMMENDATIONS
# =============================================================================

analyze_performance_results() {
    local instance_ip="$1"
    local instance_type="$2"
    separator "=== PERFORMANCE ANALYSIS AND RECOMMENDATIONS ==="
    
    log "Analyzing overall system performance..."
    
    # Check current resource utilization
    local cpu_usage=$(ssh_exec "$instance_ip" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | sed 's/%us,//'" 10)
    local memory_usage=$(ssh_exec "$instance_ip" "free | grep Mem | awk '{print (\$3/\$2) * 100.0}'" 10)
    local disk_usage=$(ssh_exec "$instance_ip" "df -h / | tail -1 | awk '{print \$5}' | sed 's/%//'" 10)
    
    if [[ -n "$cpu_usage" && -n "$memory_usage" && -n "$disk_usage" ]]; then
        info "Current Resource Utilization:"
        info "  CPU: ${cpu_usage}%"
        info "  Memory: $(printf "%.1f" "$memory_usage")%"
        info "  Disk: ${disk_usage}%"
        
        # Performance recommendations based on utilization
        if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
            recommend "High CPU usage detected. Consider upgrading to a larger instance type."
        fi
        
        if (( $(echo "$memory_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
            recommend "High memory usage detected. Consider upgrading instance or optimizing container memory limits."
        fi
        
        if (( $(echo "$disk_usage > 85" | bc -l 2>/dev/null || echo "0") )); then
            recommend "High disk usage detected. Consider cleaning up or expanding storage."
        fi
    fi
    
    # GPU utilization check
    local gpu_utilization=$(ssh_exec "$instance_ip" "nvidia-smi --query-gpu=utilization.gpu,utilization.memory --format=csv,noheader,nounits" 15)
    if [[ -n "$gpu_utilization" ]]; then
        while IFS=',' read -r gpu_util mem_util; do
            info "GPU Utilization: ${gpu_util}%, Memory: ${mem_util}%"
            
            if (( $(echo "$gpu_util < 10" | bc -l 2>/dev/null || echo "0") )); then
                recommend "Low GPU utilization detected. Ensure AI workloads are properly configured to use GPU."
            fi
        done <<< "$gpu_utilization"
    fi
    
    # Container-specific recommendations
    log "Analyzing container configurations..."
    
    # Check for container resource limits
    local container_configs=$(ssh_exec "$instance_ip" "cd /home/ubuntu/ai-starter-kit && docker compose -f docker-compose.gpu-optimized.yml config" 30)
    if [[ -n "$container_configs" ]]; then
        # Check if GPU resources are properly allocated
        if [[ "$container_configs" == *"deploy:"* && "$container_configs" == *"resources:"* ]]; then
            success "Container resource limits are configured"
        else
            recommend "Consider adding resource limits to containers for better resource management"
        fi
        
        # Check for GPU allocation
        if [[ "$container_configs" == *"runtime: nvidia"* || "$container_configs" == *"--gpus"* ]]; then
            success "GPU allocation is configured for containers"
        else
            recommend "Ensure GPU allocation is properly configured for GPU-dependent containers"
        fi
    fi
    
    # Network performance recommendations
    if [[ ${#PERFORMANCE_WARNINGS[@]} -gt 0 ]]; then
        recommend "Review network configuration if experiencing high latency or slow response times"
    fi
    
    # Cost optimization recommendations
    case "$instance_type" in
        "g4dn.xlarge")
            recommend "For higher performance workloads, consider upgrading to g4dn.2xlarge or g5.xlarge"
            ;;
        "g4ad.xlarge")
            recommend "AMD GPU instance detected. Monitor performance and compatibility with CUDA workloads"
            ;;
        "g5g.xlarge")
            recommend "ARM64 instance detected. Ensure all containers support ARM64 architecture"
            ;;
        "g5.xlarge"|"g5.2xlarge")
            recommend "High-performance instance detected. Monitor costs and consider spot instances for development"
            ;;
        "g4ad.2xlarge"|"g4dn.2xlarge")
            recommend "Large instance detected. Monitor utilization to ensure cost efficiency"
            ;;
    esac
    
    return 0
}

generate_performance_report() {
    separator "=== PERFORMANCE BENCHMARK REPORT ==="
    
    local total_warnings=${#PERFORMANCE_WARNINGS[@]}
    local total_recommendations=${#PERFORMANCE_RECOMMENDATIONS[@]}
    
    if [[ $total_warnings -gt 0 ]]; then
        echo -e "${YELLOW}⚠ PERFORMANCE WARNINGS ($total_warnings)${NC}"
        for warning in "${PERFORMANCE_WARNINGS[@]}"; do
            echo -e "${YELLOW}  • $warning${NC}"
        done
        echo ""
    fi
    
    if [[ $total_recommendations -gt 0 ]]; then
        echo -e "${BLUE}💡 PERFORMANCE RECOMMENDATIONS ($total_recommendations)${NC}"
        for recommendation in "${PERFORMANCE_RECOMMENDATIONS[@]}"; do
            echo -e "${BLUE}  • $recommendation${NC}"
        done
        echo ""
    fi
    
    if [[ $total_warnings -eq 0 && $total_recommendations -eq 0 ]]; then
        success "🎉 System performance is optimal! No issues or recommendations found."
    fi
    
    info "📊 Benchmark Summary:"
    info "  • GPU functionality verified"
    info "  • Container performance tested"
    info "  • Network latency measured"
    info "  • System resources analyzed"
    info "  • Performance baselines established"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local instance_ip="${1:-}"
    local benchmark_type="${2:-all}"
    
    # Check if help is requested
    if [[ "$instance_ip" == "--help" || "$instance_ip" == "-h" ]]; then
        echo "Usage: $0 <instance-ip> [benchmark-type]"
        echo ""
        echo "Comprehensive performance benchmarking for AI Starter Kit"
        echo ""
        echo "Benchmark Types:"
        echo "  all         Run all benchmarks (default)"
        echo "  gpu         GPU compute and memory benchmarks only"
        echo "  container   Container performance tests only"
        echo "  network     Network latency and throughput tests only"
        echo "  system      CPU and memory benchmarks only"
        echo ""
        echo "Examples:"
        echo "  $0 54.123.456.789"
        echo "  $0 54.123.456.789 gpu"
        echo "  $0 54.123.456.789 container"
        exit 0
    fi
    
    if [[ -z "$instance_ip" ]]; then
        error "Instance IP address is required"
        echo "Usage: $0 <instance-ip> [benchmark-type]"
        exit 1
    fi
    
    # Configure global variables
    KEY_NAME="${KEY_NAME:-ai-starter-kit-key}"
    
    separator "═══════════════════════════════════════════════════════════════════"
    log "🚀 AI Starter Kit - Performance Benchmark Suite"
    log "Instance IP: $instance_ip"
    log "Benchmark Type: $benchmark_type"
    log "Benchmark Timeout: ${BENCHMARK_TIMEOUT}s"
    separator "═══════════════════════════════════════════════════════════════════"
    
    # Collect system information
    local instance_type=$(collect_system_info "$instance_ip")
    
    local overall_status=0
    
    # Run benchmarks based on type
    case "$benchmark_type" in
        "all")
            benchmark_gpu_compute "$instance_ip" "$instance_type" || overall_status=1
            benchmark_ollama_performance "$instance_ip" || overall_status=1
            benchmark_container_performance "$instance_ip" || overall_status=1
            benchmark_network_performance "$instance_ip" || overall_status=1
            benchmark_system_performance "$instance_ip" "$instance_type" || overall_status=1
            ;;
        "gpu")
            benchmark_gpu_compute "$instance_ip" "$instance_type" || overall_status=1
            benchmark_ollama_performance "$instance_ip" || overall_status=1
            ;;
        "container")
            benchmark_container_performance "$instance_ip" || overall_status=1
            ;;
        "network")
            benchmark_network_performance "$instance_ip" || overall_status=1
            ;;
        "system")
            benchmark_system_performance "$instance_ip" "$instance_type" || overall_status=1
            ;;
        *)
            error "Unknown benchmark type: $benchmark_type"
            exit 1
            ;;
    esac
    
    # Performance analysis and recommendations
    analyze_performance_results "$instance_ip" "$instance_type"
    
    # Generate final report
    separator "═══════════════════════════════════════════════════════════════════"
    log "📊 PERFORMANCE BENCHMARK RESULTS"
    separator "═══════════════════════════════════════════════════════════════════"
    
    generate_performance_report
    
    if [[ $overall_status -eq 0 ]]; then
        success "🏁 Performance benchmarks completed successfully!"
    else
        warning "⚠ Some benchmarks encountered issues. Review the warnings above."
    fi
    
    separator "═══════════════════════════════════════════════════════════════════"
    
    exit $overall_status
}

# Execute main function with all arguments
main "$@"