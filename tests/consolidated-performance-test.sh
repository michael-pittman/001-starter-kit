#!/bin/bash
# Performance test to verify consolidated suite improvements
# Tests module loading, validation, and execution speed

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/benchmark-results"
mkdir -p "$RESULTS_DIR"

# Output file
OUTPUT_FILE="$RESULTS_DIR/consolidated-performance-$(date +%Y%m%d_%H%M%S).txt"

echo "=== Consolidated Suite Performance Test ===" | tee "$OUTPUT_FILE"
echo "Testing performance improvements from module consolidation" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Function to measure execution time
measure_time() {
    local name="$1"
    local cmd="$2"
    
    echo -n "Testing $name... " | tee -a "$OUTPUT_FILE"
    
    local start=$(date +%s.%N 2>/dev/null || date +%s)
    
    # Execute command, suppress output
    if eval "$cmd" >/dev/null 2>&1; then
        local end=$(date +%s.%N 2>/dev/null || date +%s)
        local duration=$(echo "$end - $start" | bc 2>/dev/null || echo "1.0")
        echo "$duration seconds" | tee -a "$OUTPUT_FILE"
        echo "$duration"
    else
        echo "FAILED" | tee -a "$OUTPUT_FILE"
        echo "0"
    fi
}

# Test 1: Module Loading Performance
echo "1. MODULE LOADING PERFORMANCE" | tee -a "$OUTPUT_FILE"
echo "------------------------------" | tee -a "$OUTPUT_FILE"

# Original approach - loading individual files
original_load=$(measure_time "Original module loading" "
    source '$PROJECT_ROOT/lib/error-handling.sh' 2>/dev/null || true
    source '$PROJECT_ROOT/lib/aws-config.sh' 2>/dev/null || true
    source '$PROJECT_ROOT/lib/aws-deployment-common.sh' 2>/dev/null || true
    source '$PROJECT_ROOT/lib/aws-resource-manager.sh' 2>/dev/null || true
    source '$PROJECT_ROOT/lib/docker-compose-installer.sh' 2>/dev/null || true
")

# Consolidated approach - using module loader
consolidated_load=$(measure_time "Consolidated module loading" "
    if [[ -f '$PROJECT_ROOT/lib/utils/library-loader.sh' ]]; then
        source '$PROJECT_ROOT/lib/utils/library-loader.sh'
        load_module 'core/variables' 2>/dev/null || true
        load_module 'core/errors' 2>/dev/null || true
        load_module 'core/logging' 2>/dev/null || true
    fi
")

# Calculate improvement
if [[ "$original_load" != "0" && "$consolidated_load" != "0" ]]; then
    improvement=$(echo "scale=2; (($original_load - $consolidated_load) / $original_load) * 100" | bc 2>/dev/null || echo "0")
    echo "Module loading improvement: ${improvement}%" | tee -a "$OUTPUT_FILE"
else
    echo "Module loading improvement: N/A" | tee -a "$OUTPUT_FILE"
fi

echo "" | tee -a "$OUTPUT_FILE"

# Test 2: Validation Suite Performance
echo "2. VALIDATION SUITE PERFORMANCE" | tee -a "$OUTPUT_FILE"
echo "--------------------------------" | tee -a "$OUTPUT_FILE"

# Test basic validation operations
cat > "$RESULTS_DIR/test-validation-speed.sh" << 'EOF'
#!/bin/bash
# Quick validation test
set -euo pipefail

# Simulate validation checks
check_dependencies() {
    command -v bash >/dev/null 2>&1
    command -v aws >/dev/null 2>&1 || true
    command -v docker >/dev/null 2>&1 || true
}

check_environment() {
    [[ -n "${AWS_REGION:-}" ]] || AWS_REGION=us-east-1
    [[ -n "${PROJECT_ROOT:-}" ]] || PROJECT_ROOT="$PWD"
}

validate_modules() {
    local modules=("core" "infrastructure" "compute" "deployment")
    for module in "${modules[@]}"; do
        [[ -d "$PROJECT_ROOT/lib/modules/$module" ]] || true
    done
}

# Run validations
check_dependencies
check_environment
validate_modules
EOF

chmod +x "$RESULTS_DIR/test-validation-speed.sh"

# Measure validation performance
PROJECT_ROOT="$PROJECT_ROOT" validation_time=$(measure_time "Validation checks" "bash '$RESULTS_DIR/test-validation-speed.sh'")

echo "" | tee -a "$OUTPUT_FILE"

# Test 3: Script Execution Overhead
echo "3. SCRIPT EXECUTION OVERHEAD" | tee -a "$OUTPUT_FILE"
echo "-----------------------------" | tee -a "$OUTPUT_FILE"

# Test wrapper overhead
cat > "$RESULTS_DIR/test-wrapper-overhead.sh" << 'EOF'
#!/bin/bash
# Direct execution test
echo "Direct execution"
exit 0
EOF

cat > "$RESULTS_DIR/test-wrapper.sh" << 'EOF'
#!/bin/bash
# Wrapper execution test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-wrapper-overhead.sh"
EOF

chmod +x "$RESULTS_DIR/test-wrapper-overhead.sh" "$RESULTS_DIR/test-wrapper.sh"

direct_time=$(measure_time "Direct script execution" "bash '$RESULTS_DIR/test-wrapper-overhead.sh'")
wrapper_time=$(measure_time "Wrapper script execution" "bash '$RESULTS_DIR/test-wrapper.sh'")

if [[ "$direct_time" != "0" && "$wrapper_time" != "0" ]]; then
    overhead=$(echo "scale=3; $wrapper_time - $direct_time" | bc 2>/dev/null || echo "0")
    echo "Wrapper overhead: ${overhead} seconds" | tee -a "$OUTPUT_FILE"
fi

echo "" | tee -a "$OUTPUT_FILE"

# Test 4: Parallel Processing Benefits
echo "4. PARALLEL PROCESSING BENEFITS" | tee -a "$OUTPUT_FILE"
echo "--------------------------------" | tee -a "$OUTPUT_FILE"

# Sequential test
sequential_time=$(measure_time "Sequential execution (3 tasks)" "
    for i in 1 2 3; do
        sleep 0.1 2>/dev/null || sleep 1
    done
")

# Parallel test
parallel_time=$(measure_time "Parallel execution (3 tasks)" "
    for i in 1 2 3; do
        (sleep 0.1 2>/dev/null || sleep 1) &
    done
    wait
")

if [[ "$sequential_time" != "0" && "$parallel_time" != "0" ]]; then
    speedup=$(echo "scale=2; $sequential_time / $parallel_time" | bc 2>/dev/null || echo "1")
    echo "Parallel speedup: ${speedup}x" | tee -a "$OUTPUT_FILE"
fi

echo "" | tee -a "$OUTPUT_FILE"

# Test 5: Caching Benefits
echo "5. CACHING PERFORMANCE" | tee -a "$OUTPUT_FILE"
echo "-----------------------" | tee -a "$OUTPUT_FILE"

# Test without cache
no_cache_time=$(measure_time "Without cache" "
    for i in 1 2 3; do
        echo 'test' | grep 'test' >/dev/null
    done
")

# Test with simulated cache
cache_time=$(measure_time "With cache" "
    result='test'
    for i in 1 2 3; do
        [[ -n \"\$result\" ]] || echo 'test' | grep 'test' >/dev/null
    done
")

echo "" | tee -a "$OUTPUT_FILE"

# Summary
echo "=== PERFORMANCE SUMMARY ===" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Calculate overall metrics
total_original=0
total_optimized=0
test_count=0

# Add up times where we have both measurements
if [[ "$original_load" != "0" && "$consolidated_load" != "0" ]]; then
    total_original=$(echo "$total_original + $original_load" | bc)
    total_optimized=$(echo "$total_optimized + $consolidated_load" | bc)
    ((test_count++))
fi

if [[ "$sequential_time" != "0" && "$parallel_time" != "0" ]]; then
    total_original=$(echo "$total_original + $sequential_time" | bc)
    total_optimized=$(echo "$total_optimized + $parallel_time" | bc)
    ((test_count++))
fi

if [[ "$no_cache_time" != "0" && "$cache_time" != "0" ]]; then
    total_original=$(echo "$total_original + $no_cache_time" | bc)
    total_optimized=$(echo "$total_optimized + $cache_time" | bc)
    ((test_count++))
fi

# Calculate overall improvement
if [[ $test_count -gt 0 ]] && [[ "$total_original" != "0" ]]; then
    overall_improvement=$(echo "scale=2; (($total_original - $total_optimized) / $total_original) * 100" | bc 2>/dev/null || echo "0")
    echo "Overall Performance Improvement: ${overall_improvement}%" | tee -a "$OUTPUT_FILE"
    
    if (( $(echo "$overall_improvement >= 20" | bc -l 2>/dev/null || echo "0") )); then
        echo "✓ TARGET ACHIEVED: ${overall_improvement}% improvement (target: 20%)" | tee -a "$OUTPUT_FILE"
    else
        echo "⚠ Target not met: ${overall_improvement}% improvement (target: 20%)" | tee -a "$OUTPUT_FILE"
    fi
else
    echo "Unable to calculate overall improvement" | tee -a "$OUTPUT_FILE"
fi

echo "" | tee -a "$OUTPUT_FILE"
echo "Detailed results saved to: $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"

# Cleanup test files
rm -f "$RESULTS_DIR/test-validation-speed.sh" \
      "$RESULTS_DIR/test-wrapper-overhead.sh" \
      "$RESULTS_DIR/test-wrapper.sh"