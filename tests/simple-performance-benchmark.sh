#!/bin/bash
# Simple performance benchmarking script with minimal dependencies

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARK_DIR="$PROJECT_ROOT/benchmark-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="$BENCHMARK_DIR/benchmark_results_$TIMESTAMP.txt"
SUMMARY_FILE="$BENCHMARK_DIR/benchmark_summary_$TIMESTAMP.md"

# Create benchmark results directory
mkdir -p "$BENCHMARK_DIR"

# Simple timing function
time_script() {
    local name="$1"
    local script="$2"
    local runs="${3:-3}"
    
    echo "Benchmarking: $name"
    echo "Script: $script"
    
    if [[ ! -f "$script" ]]; then
        echo "SKIP - File not found"
        echo "0"
        return
    fi
    
    local total=0
    local count=0
    
    for i in $(seq 1 $runs); do
        echo -n "  Run $i/$runs... "
        local start=$(date +%s.%N 2>/dev/null || date +%s)
        
        # Run script with timeout
        if timeout 60 bash "$script" --benchmark-mode >/dev/null 2>&1; then
            local end=$(date +%s.%N 2>/dev/null || date +%s)
            local duration=$(echo "$end - $start" | bc 2>/dev/null || echo "1")
            echo "${duration}s"
            total=$(echo "$total + $duration" | bc 2>/dev/null || echo "$total")
            ((count++))
        else
            echo "FAILED"
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        local avg=$(echo "scale=3; $total / $count" | bc 2>/dev/null || echo "1")
        echo "  Average: ${avg}s"
        echo "$avg"
    else
        echo "0"
    fi
}

# Initialize summary
echo "# Performance Benchmark Report" > "$SUMMARY_FILE"
echo "Date: $(date)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Test 1: Validation Scripts
echo "## Validation Scripts Comparison" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo "### Original validate-environment.sh" | tee -a "$SUMMARY_FILE"
original_validate=$(time_script "Original Validation" "$PROJECT_ROOT/scripts/validate-environment.sh" 3)
echo "Average: ${original_validate}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo "### Consolidated validate-module-consolidation.sh" | tee -a "$SUMMARY_FILE"
consolidated_validate=$(time_script "Consolidated Validation" "$PROJECT_ROOT/scripts/validate-module-consolidation.sh" 3)
echo "Average: ${consolidated_validate}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Calculate improvement for validation
if [[ "$original_validate" != "0" && "$consolidated_validate" != "0" ]]; then
    improvement=$(echo "scale=2; (($original_validate - $consolidated_validate) / $original_validate) * 100" | bc 2>/dev/null || echo "0")
    echo "### Validation Improvement: ${improvement}%" | tee -a "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
fi

# Test 2: Test Suites
echo "## Test Suite Performance" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Simple test suite
echo "### test-suite-integration-simple.sh" | tee -a "$SUMMARY_FILE"
simple_suite=$(time_script "Simple Integration Suite" "$PROJECT_ROOT/tests/test-suite-integration-simple.sh" 2)
echo "Average: ${simple_suite}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Deployment tests
echo "### test-deployment-flow.sh" | tee -a "$SUMMARY_FILE"
deployment_flow=$(time_script "Deployment Flow" "$PROJECT_ROOT/tests/test-deployment-flow.sh" 2)
echo "Average: ${deployment_flow}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Test 3: Script Wrappers
echo "## Script Wrapper Performance" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Health check comparison
echo "### Original health-check-advanced.sh" | tee -a "$SUMMARY_FILE"
original_health=$(time_script "Original Health Check" "$PROJECT_ROOT/scripts/health-check-advanced.sh" 2)
echo "Average: ${original_health}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo "### Wrapper health-check-advanced-wrapper.sh" | tee -a "$SUMMARY_FILE"
wrapper_health=$(time_script "Wrapper Health Check" "$PROJECT_ROOT/scripts/health-check-advanced-wrapper.sh" 2)
echo "Average: ${wrapper_health}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Calculate improvement for health check
if [[ "$original_health" != "0" && "$wrapper_health" != "0" ]]; then
    health_improvement=$(echo "scale=2; (($original_health - $wrapper_health) / $original_health) * 100" | bc 2>/dev/null || echo "0")
    echo "### Health Check Improvement: ${health_improvement}%" | tee -a "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
fi

# Test 4: Module Loading Performance
echo "## Module Loading Test" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Create a simple module loading test
cat > "$BENCHMARK_DIR/test-module-loading.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Time module loading
start=$(date +%s.%N 2>/dev/null || date +%s)

# Load core modules
for module in variables errors logging validation; do
    if [[ -f "$LIB_DIR/modules/core/$module.sh" ]]; then
        source "$LIB_DIR/modules/core/$module.sh"
    fi
done

end=$(date +%s.%N 2>/dev/null || date +%s)
duration=$(echo "$end - $start" | bc 2>/dev/null || echo "0.1")
echo "Module loading time: ${duration}s"
EOF

chmod +x "$BENCHMARK_DIR/test-module-loading.sh"
module_time=$(time_script "Module Loading" "$BENCHMARK_DIR/test-module-loading.sh" 5)
echo "Average module loading time: ${module_time}s" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Summary
echo "## Summary" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Calculate average improvement
total_improvements=0
improvement_count=0

for imp in $improvement $health_improvement; do
    if [[ "$imp" != "" && "$imp" != "0" ]]; then
        total_improvements=$(echo "$total_improvements + $imp" | bc 2>/dev/null || echo "0")
        ((improvement_count++))
    fi
done

if [[ $improvement_count -gt 0 ]]; then
    avg_improvement=$(echo "scale=2; $total_improvements / $improvement_count" | bc 2>/dev/null || echo "0")
    echo "### Average Performance Improvement: ${avg_improvement}%" | tee -a "$SUMMARY_FILE"
    
    if (( $(echo "$avg_improvement >= 20" | bc -l 2>/dev/null || echo "0") )); then
        echo "✓ Target of 20% improvement achieved!" | tee -a "$SUMMARY_FILE"
    else
        echo "⚠ Target of 20% improvement not met (current: ${avg_improvement}%)" | tee -a "$SUMMARY_FILE"
    fi
fi

echo "" >> "$SUMMARY_FILE"
echo "Results saved to:" | tee -a "$SUMMARY_FILE"
echo "- Summary: $SUMMARY_FILE" | tee -a "$SUMMARY_FILE"
echo "- Detailed: $RESULTS_FILE" | tee -a "$SUMMARY_FILE"