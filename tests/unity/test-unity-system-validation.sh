#!/bin/bash
#
# Unity System Validation Test
# Tests the actual Unity implementation as it exists
#

set -euo pipefail

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test configuration
export UNITY_LOG_DIR="$PROJECT_ROOT/test-reports/unity-validation-$(date +%s)"
export DEBUG=true
export LOG_LEVEL=DEBUG

# Create test directories
mkdir -p "$UNITY_LOG_DIR"

echo "Unity System Validation Test"
echo "============================"
echo "Testing actual Unity implementation..."
echo ""

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

#############################################
# Test 1: Unity Core Components
#############################################

echo "Test 1: Unity Core Components"
echo "-----------------------------"

# Check for core Unity files
core_files=(
    "lib/unity/core/unity-core.sh"
    "lib/unity/core/unity-events.sh"
    "lib/unity/core/unity-plugins.sh"
    "lib/unity/core/registry.sh"
    "lib/unity/events/event-bus.sh"
)

for file in "${core_files[@]}"; do
    if [[ -f "$PROJECT_ROOT/$file" ]]; then
        echo "✅ Found: $file"
        ((TESTS_PASSED++))
    else
        echo "❌ Missing: $file"
        ((TESTS_FAILED++))
    fi
done

echo ""

#############################################
# Test 2: Load Unity Core
#############################################

echo "Test 2: Load Unity Core"
echo "-----------------------"

# Try to load the main Unity core file
if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-core.sh" ]]; then
    if source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>"$UNITY_LOG_DIR/core-load-errors.log"; then
        echo "✅ Unity core loaded successfully"
        ((TESTS_PASSED++))
    else
        echo "❌ Unity core failed to load"
        echo "   Errors:"
        cat "$UNITY_LOG_DIR/core-load-errors.log" | head -10
        ((TESTS_FAILED++))
    fi
else
    echo "❌ Unity core file not found"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 3: Event System Functions
#############################################

echo "Test 3: Event System Functions"
echo "------------------------------"

# Load event bus
if [[ -f "$PROJECT_ROOT/lib/unity/events/event-bus.sh" ]]; then
    if source "$PROJECT_ROOT/lib/unity/events/event-bus.sh" 2>"$UNITY_LOG_DIR/event-load-errors.log"; then
        echo "✅ Event bus loaded"
        
        # Check for critical functions
        for func in unity_emit_event unity_register_handler unity_event_init; do
            if type -t "$func" >/dev/null 2>&1; then
                echo "✅ Function available: $func"
                ((TESTS_PASSED++))
            else
                echo "❌ Function missing: $func"
                ((TESTS_FAILED++))
            fi
        done
    else
        echo "❌ Event bus failed to load"
        cat "$UNITY_LOG_DIR/event-load-errors.log" | head -5
        ((TESTS_FAILED++))
    fi
fi

echo ""

#############################################
# Test 4: Service Loading
#############################################

echo "Test 4: Service Loading"
echo "-----------------------"

services=(
    "aws-service.sh"
    "docker-service.sh"
    "config-service.sh"
    "monitor-service.sh"
)

for service in "${services[@]}"; do
    service_path="$PROJECT_ROOT/lib/unity/services/$service"
    if [[ -f "$service_path" ]]; then
        echo "Found: $service"
        
        # Try to load in isolation
        if (source "$service_path") 2>"$UNITY_LOG_DIR/${service%.sh}-errors.log"; then
            echo "✅ $service loads cleanly"
            ((TESTS_PASSED++))
        else
            echo "⚠️  $service has loading issues"
            ((WARNINGS++))
        fi
    else
        echo "⚠️  Service not found: $service"
        ((WARNINGS++))
    fi
done

echo ""

#############################################
# Test 5: Plugin System
#############################################

echo "Test 5: Plugin System"
echo "---------------------"

if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-plugins.sh" ]]; then
    if source "$PROJECT_ROOT/lib/unity/core/unity-plugins.sh" 2>"$UNITY_LOG_DIR/plugin-errors.log"; then
        echo "✅ Plugin system loaded"
        ((TESTS_PASSED++))
        
        # Check for plugin functions
        if type -t unity_load_plugin >/dev/null 2>&1; then
            echo "✅ unity_load_plugin function available"
            ((TESTS_PASSED++))
        else
            echo "❌ unity_load_plugin function missing"
            ((TESTS_FAILED++))
        fi
    else
        echo "❌ Plugin system failed to load"
        ((TESTS_FAILED++))
    fi
fi

echo ""

#############################################
# Test 6: Integration Test
#############################################

echo "Test 6: Basic Integration"
echo "-------------------------"

# Create a simple integration test
integration_test() {
    # Load core components
    source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || return 1
    source "$PROJECT_ROOT/lib/unity/events/event-bus.sh" || return 1
    
    # Initialize event system
    unity_event_init || return 1
    
    # Try to emit an event
    unity_emit_event "test.validation" "integration-test" "test-data" || return 1
    
    return 0
}

if integration_test 2>"$UNITY_LOG_DIR/integration-test.log"; then
    echo "✅ Basic integration successful"
    ((TESTS_PASSED++))
else
    echo "❌ Integration test failed"
    echo "   Check: $UNITY_LOG_DIR/integration-test.log"
    if [[ -s "$UNITY_LOG_DIR/integration-test.log" ]]; then
        tail -10 "$UNITY_LOG_DIR/integration-test.log"
    fi
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 7: Configuration Files
#############################################

echo "Test 7: Configuration Files"
echo "---------------------------"

config_files=(
    "config/unity.yml"
    "config/unity-agents.yml"
)

for config in "${config_files[@]}"; do
    if [[ -f "$PROJECT_ROOT/$config" ]]; then
        echo "✅ Found: $config"
        ((TESTS_PASSED++))
        
        # Validate YAML syntax
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.' "$PROJECT_ROOT/$config" >/dev/null 2>&1; then
                echo "   ✓ Valid YAML syntax"
            else
                echo "   ✗ Invalid YAML syntax"
                ((TESTS_FAILED++))
            fi
        fi
    else
        echo "⚠️  Missing: $config"
        ((WARNINGS++))
    fi
done

echo ""

#############################################
# Summary
#############################################

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo "=================================="
echo "VALIDATION SUMMARY"
echo "=================================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "Warnings: $WARNINGS"
echo ""

# Generate detailed report
REPORT_FILE="$PROJECT_ROOT/test-reports/unity-validation-$(date +%Y%m%d_%H%M%S).txt"
{
    echo "Unity System Validation Report"
    echo "=============================="
    echo "Date: $(date)"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Warnings: $WARNINGS"
    echo ""
    
    if [[ $TESTS_FAILED -gt 0 ]] || [[ $WARNINGS -gt 0 ]]; then
        echo "Issues Found:"
        echo "-------------"
        
        if [[ $TESTS_FAILED -gt 0 ]]; then
            echo "Critical Issues:"
            echo "- Some Unity core components failed to load"
            echo "- Check error logs in: $UNITY_LOG_DIR"
        fi
        
        if [[ $WARNINGS -gt 0 ]]; then
            echo ""
            echo "Warnings:"
            echo "- Some optional components not found or have issues"
            echo "- This may be expected if Unity is still being implemented"
        fi
    else
        echo "All tests passed successfully!"
    fi
    
    echo ""
    echo "Log Directory: $UNITY_LOG_DIR"
    echo ""
    echo "Error Logs:"
    ls -la "$UNITY_LOG_DIR"/*.log 2>/dev/null || echo "No error logs found"
} > "$REPORT_FILE"

echo "Detailed report saved to: $REPORT_FILE"
echo ""

# Provide actionable feedback
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "❌ Critical issues found. Recommended actions:"
    echo "   1. Check error logs in $UNITY_LOG_DIR"
    echo "   2. Ensure all Unity core files exist and have proper syntax"
    echo "   3. Verify function definitions in event-bus.sh"
    echo "   4. Run: shellcheck lib/unity/**/*.sh"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo "⚠️  Some warnings found, but core system appears functional"
    exit 0
else
    echo "✅ Unity system validation successful!"
    exit 0
fi