#!/bin/bash
# Performance benchmarking framework for consolidated test suites
# Measures execution time improvements between original and consolidated scripts

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
BENCHMARK_DIR="$PROJECT_ROOT/benchmark-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="$BENCHMARK_DIR/benchmark_results_$TIMESTAMP.txt"
SUMMARY_FILE="$BENCHMARK_DIR/benchmark_summary_$TIMESTAMP.md"

# Create benchmark results directory
mkdir -p "$BENCHMARK_DIR"

# Load required libraries
source "$LIB_DIR/associative-arrays.sh"
source "$LIB_DIR/error-handling.sh"

# Benchmark configuration
declare -A BENCHMARK_RUNS=(
    ["iterations"]=5
    ["warmup"]=1
)

# Test suites to benchmark
declare -A TEST_SUITES=(
    ["validation"]="test-suite-integration.sh"
    ["validation_simple"]="test-suite-integration-simple.sh"
    ["deployment"]="test-deployment-comprehensive.sh"
    ["deployment_flow"]="test-deployment-flow.sh"
    ["modular"]="test-modular-v2.sh"
    ["modular_system"]="test-modular-system.sh"
    ["infrastructure"]="test-infrastructure-modules.sh"
    ["error_handling"]="test-enhanced-error-handling.sh"
    ["performance_load"]="test-performance-load-testing.sh"
)

# Original vs consolidated script mappings
declare -A SCRIPT_MAPPINGS=(
    ["original_validation"]="validate-environment.sh"
    ["consolidated_validation"]="scripts/validate-module-consolidation.sh"
    ["original_deployment"]="aws-deployment-modular.sh"
    ["consolidated_deployment"]="scripts/aws-deployment-modular.sh"
    ["original_cleanup"]="cleanup-consolidated.sh"
    ["consolidated_cleanup"]="scripts/cleanup-consolidated-wrapper.sh"
    ["original_health"]="health-check-advanced.sh"
    ["consolidated_health"]="scripts/health-check-advanced-wrapper.sh"
)

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Benchmark timing function
benchmark_script() {
    local script_name="$1"
    local script_path="$2"
    local iterations="${3:-5}"
    local warmup="${4:-1}"
    
    echo "Benchmarking: $script_name" | tee -a "$RESULTS_FILE"
    echo "Script: $script_path" | tee -a "$RESULTS_FILE"
    echo "Iterations: $iterations (Warmup: $warmup)" | tee -a "$RESULTS_FILE"
    
    local times=()
    local total_time=0
    
    # Warmup runs
    for i in $(seq 1 "$warmup"); do
        echo -n "  Warmup $i/$warmup... "
        if [[ -f "$script_path" ]]; then
            local start=$(date +%s.%N)
            timeout 300 bash "$script_path" --benchmark-mode >/dev/null 2>&1 || true
            local end=$(date +%s.%N)
            local duration=$(echo "$end - $start" | bc)
            echo "done (${duration}s)"
        else
            echo "SKIP (file not found)"
        fi
    done
    
    # Actual benchmark runs
    for i in $(seq 1 "$iterations"); do
        echo -n "  Run $i/$iterations... "
        if [[ -f "$script_path" ]]; then
            local start=$(date +%s.%N)
            timeout 300 bash "$script_path" --benchmark-mode >/dev/null 2>&1 || true
            local end=$(date +%s.%N)
            local duration=$(echo "$end - $start" | bc)
            times+=("$duration")
            total_time=$(echo "$total_time + $duration" | bc)
            echo "done (${duration}s)"
        else
            echo "SKIP (file not found)"
            return 1
        fi
    done
    
    # Calculate statistics
    if [[ ${#times[@]} -gt 0 ]]; then
        local avg_time=$(echo "scale=3; $total_time / $iterations" | bc)
        local min_time=$(printf '%s\n' "${times[@]}" | sort -n | head -1)
        local max_time=$(printf '%s\n' "${times[@]}" | sort -n | tail -1)
        
        echo "  Average: ${avg_time}s" | tee -a "$RESULTS_FILE"
        echo "  Min: ${min_time}s" | tee -a "$RESULTS_FILE"
        echo "  Max: ${max_time}s" | tee -a "$RESULTS_FILE"
        echo "" | tee -a "$RESULTS_FILE"
        
        echo "$avg_time"
    else
        echo "0"
    fi
}

# Compare performance between two scripts
compare_performance() {
    local name="$1"
    local original_script="$2"
    local consolidated_script="$3"
    
    print_header "Comparing: $name"
    
    echo "## $name Comparison" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Benchmark original
    echo "### Original Script" >> "$SUMMARY_FILE"
    local original_time=$(benchmark_script "Original $name" "$original_script" "${BENCHMARK_RUNS[iterations]}" "${BENCHMARK_RUNS[warmup]}")
    echo "Average time: ${original_time}s" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Benchmark consolidated
    echo "### Consolidated Script" >> "$SUMMARY_FILE"
    local consolidated_time=$(benchmark_script "Consolidated $name" "$consolidated_script" "${BENCHMARK_RUNS[iterations]}" "${BENCHMARK_RUNS[warmup]}")
    echo "Average time: ${consolidated_time}s" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Calculate improvement
    if [[ "$original_time" != "0" && "$consolidated_time" != "0" ]]; then
        local improvement=$(echo "scale=2; (($original_time - $consolidated_time) / $original_time) * 100" | bc)
        local speedup=$(echo "scale=2; $original_time / $consolidated_time" | bc)
        
        echo "### Performance Improvement" >> "$SUMMARY_FILE"
        echo "- Improvement: ${improvement}%" >> "$SUMMARY_FILE"
        echo "- Speedup: ${speedup}x" >> "$SUMMARY_FILE"
        echo "- Time saved: $(echo "$original_time - $consolidated_time" | bc)s" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        
        if (( $(echo "$improvement >= 20" | bc -l) )); then
            print_success "Achieved ${improvement}% improvement (target: 20%)"
        else
            print_warning "Only ${improvement}% improvement (target: 20%)"
        fi
    else
        print_error "Could not calculate improvement (missing scripts)"
        echo "### Performance Improvement" >> "$SUMMARY_FILE"
        echo "Could not calculate - one or both scripts missing" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    fi
}

# Benchmark test suites
benchmark_test_suites() {
    print_header "Benchmarking Test Suites"
    
    echo "# Test Suite Benchmarks" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    for suite_name in "${!TEST_SUITES[@]}"; do
        local suite_script="${TEST_SUITES[$suite_name]}"
        local suite_path="$PROJECT_ROOT/tests/$suite_script"
        
        if [[ -f "$suite_path" ]]; then
            echo "## $suite_name Suite" >> "$SUMMARY_FILE"
            benchmark_script "$suite_name" "$suite_path" 3 1
            echo "" >> "$SUMMARY_FILE"
        fi
    done
}

# Memory usage profiling
profile_memory_usage() {
    local script_name="$1"
    local script_path="$2"
    
    if command -v /usr/bin/time >/dev/null 2>&1; then
        echo "Memory profiling: $script_name"
        /usr/bin/time -l bash "$script_path" --benchmark-mode >/dev/null 2>&1 2>&1 | grep -E "maximum resident set size|page reclaims" || true
    fi
}

# Main benchmark execution
main() {
    print_header "Performance Benchmark Suite"
    echo "Results will be saved to: $BENCHMARK_DIR"
    
    # Initialize summary file
    echo "# Performance Benchmark Report" > "$SUMMARY_FILE"
    echo "Date: $(date)" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # System information
    echo "## System Information" >> "$SUMMARY_FILE"
    echo "- OS: $(uname -s) $(uname -r)" >> "$SUMMARY_FILE"
    echo "- CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2)" >> "$SUMMARY_FILE"
    echo "- Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024 " GB"}' || free -h | grep Mem | awk '{print $2}')" >> "$SUMMARY_FILE"
    echo "- Bash: $(bash --version | head -1)" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Run comparisons
    echo "# Script Comparisons" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Validation scripts
    compare_performance "Validation" \
        "$PROJECT_ROOT/scripts/validate-environment.sh" \
        "$PROJECT_ROOT/scripts/validate-module-consolidation.sh"
    
    # Cleanup scripts
    compare_performance "Cleanup" \
        "$PROJECT_ROOT/scripts/cleanup-consolidated.sh" \
        "$PROJECT_ROOT/scripts/cleanup-consolidated-wrapper.sh"
    
    # Health check scripts
    compare_performance "Health Check" \
        "$PROJECT_ROOT/scripts/health-check-advanced.sh" \
        "$PROJECT_ROOT/scripts/health-check-advanced-wrapper.sh"
    
    # Benchmark test suites
    benchmark_test_suites
    
    # Generate final summary
    print_header "Benchmark Summary"
    
    echo "## Overall Results" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Calculate overall improvement
    local total_improvements=$(grep -E "Improvement: [0-9\.\-]+" "$SUMMARY_FILE" | grep -o "[0-9\.\-]*" | paste -sd+ - | bc)
    local improvement_count=$(grep -c "Improvement:" "$SUMMARY_FILE" || echo 0)
    
    if [[ $improvement_count -gt 0 ]]; then
        local avg_improvement=$(echo "scale=2; $total_improvements / $improvement_count" | bc)
        echo "### Average Improvement: ${avg_improvement}%" >> "$SUMMARY_FILE"
        
        if (( $(echo "$avg_improvement >= 20" | bc -l) )); then
            print_success "Target achieved! Average improvement: ${avg_improvement}%"
        else
            print_warning "Target not met. Average improvement: ${avg_improvement}% (target: 20%)"
        fi
    fi
    
    echo "" >> "$SUMMARY_FILE"
    echo "Full results saved to:" | tee -a "$SUMMARY_FILE"
    echo "- Detailed: $RESULTS_FILE" | tee -a "$SUMMARY_FILE"
    echo "- Summary: $SUMMARY_FILE" | tee -a "$SUMMARY_FILE"
}

# Execute benchmark
main "$@"