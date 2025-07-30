#!/usr/bin/env bash
# =============================================================================
# Performance Optimization Test Script
# Demonstrates performance improvements in AWS operations
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/modules/core/logging.sh"
source "$LIB_DIR/modules/performance/aws-api-cache.sh"
source "$LIB_DIR/modules/performance/parallel-executor.sh"
source "$LIB_DIR/modules/performance/performance-monitor.sh"
source "$LIB_DIR/modules/compute/spot-optimizer.sh"

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

# Test parameters
INSTANCE_TYPES=(g4dn.xlarge g4dn.2xlarge g5.xlarge g5.2xlarge)
TEST_REGIONS=(us-east-1 us-west-2 eu-west-1)
MAX_SPOT_PRICE="0.50"

# =============================================================================
# PERFORMANCE COMPARISON TESTS
# =============================================================================

test_serial_vs_parallel() {
    header "Testing Serial vs Parallel Execution"
    
    # Test 1: Serial spot price lookup
    echo "1. Serial Execution (Traditional):"
    perf_timer_start "serial_spot_lookup"
    
    for region in "${TEST_REGIONS[@]}"; do
        for instance_type in "${INSTANCE_TYPES[@]}"; do
            aws ec2 describe-spot-price-history \
                --instance-types "$instance_type" \
                --product-descriptions "Linux/UNIX" \
                --max-items 1 \
                --region "$region" \
                --query 'SpotPriceHistory[0].SpotPrice' \
                --output text >/dev/null 2>&1 || true
        done
    done
    
    perf_timer_stop "serial_spot_lookup"
    local serial_time=$(perf_timer_get "serial_spot_lookup" "s")
    echo "Serial execution time: ${serial_time}s"
    echo ""
    
    # Test 2: Parallel spot price lookup
    echo "2. Parallel Execution (Optimized):"
    perf_timer_start "parallel_spot_lookup"
    
    for instance_type in "${INSTANCE_TYPES[@]}"; do
        parallel_get_spot_prices "$instance_type" "${TEST_REGIONS[@]}" >/dev/null
    done
    
    perf_timer_stop "parallel_spot_lookup"
    local parallel_time=$(perf_timer_get "parallel_spot_lookup" "s")
    echo "Parallel execution time: ${parallel_time}s"
    
    # Calculate improvement
    if [[ $serial_time -gt 0 ]]; then
        local improvement=$(echo "scale=1; (($serial_time - $parallel_time) / $serial_time) * 100" | bc -l)
        success "Performance improvement: ${improvement}%"
    fi
}

test_caching_performance() {
    header "Testing Caching Performance"
    
    # Clear cache first
    clear_cache
    
    # Test 1: First run (cache miss)
    echo "1. First Run (Cache Miss):"
    perf_timer_start "cache_miss_test"
    
    for instance_type in "${INSTANCE_TYPES[@]}"; do
        get_spot_prices_cached "$instance_type" "us-east-1" >/dev/null
    done
    
    perf_timer_stop "cache_miss_test"
    local miss_time=$(perf_timer_get "cache_miss_test" "ms")
    echo "Cache miss time: ${miss_time}ms"
    echo ""
    
    # Test 2: Second run (cache hit)
    echo "2. Second Run (Cache Hit):"
    perf_timer_start "cache_hit_test"
    
    for instance_type in "${INSTANCE_TYPES[@]}"; do
        get_spot_prices_cached "$instance_type" "us-east-1" >/dev/null
    done
    
    perf_timer_stop "cache_hit_test"
    local hit_time=$(perf_timer_get "cache_hit_test" "ms")
    echo "Cache hit time: ${hit_time}ms"
    
    # Calculate improvement
    if [[ $miss_time -gt 0 ]]; then
        local cache_improvement=$(echo "scale=1; (($miss_time - $hit_time) / $miss_time) * 100" | bc -l)
        success "Cache performance improvement: ${cache_improvement}%"
    fi
    
    # Show cache stats
    echo ""
    get_cache_stats
}

test_batch_operations() {
    header "Testing Batch Operations"
    
    # Test 1: Individual operations
    echo "1. Individual Operations:"
    perf_timer_start "individual_ops"
    
    for instance_type in "${INSTANCE_TYPES[@]}"; do
        aws ec2 describe-instance-types \
            --instance-types "$instance_type" \
            --region "us-east-1" \
            --query 'InstanceTypes[0].InstanceType' \
            --output text >/dev/null 2>&1 || true
    done
    
    perf_timer_stop "individual_ops"
    local individual_time=$(perf_timer_get "individual_ops" "ms")
    echo "Individual operations time: ${individual_time}ms"
    echo ""
    
    # Test 2: Batch operation
    echo "2. Batch Operation:"
    perf_timer_start "batch_ops"
    
    get_instance_types_cached "${INSTANCE_TYPES[@]}" >/dev/null
    
    perf_timer_stop "batch_ops"
    local batch_time=$(perf_timer_get "batch_ops" "ms")
    echo "Batch operation time: ${batch_time}ms"
    
    # Calculate improvement
    if [[ $individual_time -gt 0 ]]; then
        local batch_improvement=$(echo "scale=1; (($individual_time - $batch_time) / $individual_time) * 100" | bc -l)
        success "Batch operation improvement: ${batch_improvement}%"
    fi
}

test_optimized_spot_selection() {
    header "Testing Optimized Spot Selection"
    
    # Test traditional approach
    echo "1. Traditional Spot Selection:"
    perf_timer_start "traditional_selection"
    
    # Simulate traditional sequential checking
    local best_price=""
    local best_instance=""
    
    for instance_type in "${INSTANCE_TYPES[@]}"; do
        local price=$(aws ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "us-east-1" \
            --query 'SpotPriceHistory[0].SpotPrice' \
            --output text 2>/dev/null || echo "999")
        
        if [[ -z "$best_price" ]] || (( $(echo "$price < $best_price" | bc -l 2>/dev/null || echo 0) )); then
            best_price="$price"
            best_instance="$instance_type"
        fi
    done
    
    perf_timer_stop "traditional_selection"
    local traditional_time=$(perf_timer_get "traditional_selection" "s")
    echo "Traditional selection time: ${traditional_time}s"
    echo "Best instance: $best_instance at \$$best_price/hour"
    echo ""
    
    # Test optimized approach
    echo "2. Optimized Spot Selection:"
    perf_timer_start "optimized_selection"
    
    local optimal_config=$(select_optimal_spot_config "$MAX_SPOT_PRICE" "$(IFS=,; echo "${INSTANCE_TYPES[*]}")")
    
    perf_timer_stop "optimized_selection"
    local optimized_time=$(perf_timer_get "optimized_selection" "s")
    echo "Optimized selection time: ${optimized_time}s"
    
    # Calculate improvement
    if [[ $traditional_time -gt 0 ]]; then
        local selection_improvement=$(echo "scale=1; (($traditional_time - $optimized_time) / $traditional_time) * 100" | bc -l)
        success "Selection performance improvement: ${selection_improvement}%"
    fi
}

test_capacity_checking() {
    header "Testing Capacity Checking Performance"
    
    echo "Checking spot capacity across AZs..."
    perf_timer_start "capacity_check"
    
    check_spot_capacity_parallel "us-east-1" "${INSTANCE_TYPES[@]}"
    
    perf_timer_stop "capacity_check"
    local capacity_time=$(perf_timer_get "capacity_check" "s")
    echo ""
    echo "Capacity check completed in: ${capacity_time}s"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    banner "AWS Performance Optimization Test Suite"
    
    # Initialize performance systems
    init_spot_optimizer
    
    # Run tests
    test_serial_vs_parallel
    echo ""
    
    test_caching_performance
    echo ""
    
    test_batch_operations
    echo ""
    
    test_optimized_spot_selection
    echo ""
    
    test_capacity_checking
    echo ""
    
    # Generate final report
    header "Performance Optimization Summary"
    generate_spot_optimization_report
    
    # Cleanup
    parallel_clear
    
    success "Performance optimization tests completed!"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi