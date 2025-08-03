#!/bin/bash
#
# Unity System Critical Fixes Test
# Focuses on testing the most critical issues that need to be fixed
#

set -euo pipefail

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test configuration
export UNITY_LOG_DIR="$PROJECT_ROOT/test-reports/unity-critical-$(date +%s)"
export DEBUG=true
export LOG_LEVEL=DEBUG

# Create test directories
mkdir -p "$UNITY_LOG_DIR"

echo "Unity Critical Fixes Test"
echo "========================"
echo "Testing critical Unity system fixes..."
echo ""

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

#############################################
# Test 1: Unity Core Can Load
#############################################

echo "Test 1: Unity Core Loading"
echo "--------------------------"

if [[ -f "$PROJECT_ROOT/lib/unity/core/init.sh" ]]; then
    if source "$PROJECT_ROOT/lib/unity/core/init.sh" 2>/dev/null; then
        echo "✅ Unity core loads successfully"
        ((TESTS_PASSED++))
    else
        echo "❌ Unity core failed to load"
        echo "   Error: Check syntax and dependencies in lib/unity/core/init.sh"
        ((TESTS_FAILED++))
    fi
else
    echo "❌ Unity core init.sh not found"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 2: Event System Function Availability
#############################################

echo "Test 2: Event System Functions"
echo "------------------------------"

# Check if critical event functions exist
if type -t unity_emit_event >/dev/null 2>&1; then
    echo "✅ unity_emit_event function available"
    ((TESTS_PASSED++))
else
    echo "❌ unity_emit_event function NOT available"
    echo "   This is a critical function that must be defined"
    ((TESTS_FAILED++))
fi

if type -t unity_register_handler >/dev/null 2>&1; then
    echo "✅ unity_register_handler function available"
    ((TESTS_PASSED++))
else
    echo "❌ unity_register_handler function NOT available"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 3: Log Directory Permissions
#############################################

echo "Test 3: Log Directory Permissions"
echo "---------------------------------"

if [[ -d "$UNITY_LOG_DIR" ]]; then
    if [[ -w "$UNITY_LOG_DIR" ]]; then
        # Try to create a test file
        if touch "$UNITY_LOG_DIR/test-write.tmp" 2>/dev/null; then
            rm -f "$UNITY_LOG_DIR/test-write.tmp"
            echo "✅ Log directory is writable"
            ((TESTS_PASSED++))
        else
            echo "❌ Cannot write to log directory"
            ((TESTS_FAILED++))
        fi
    else
        echo "❌ Log directory exists but is not writable"
        ((TESTS_FAILED++))
    fi
else
    echo "❌ Log directory was not created"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 4: Service Registry Basic Functions
#############################################

echo "Test 4: Service Registry Functions"
echo "----------------------------------"

if [[ -f "$PROJECT_ROOT/lib/unity/services/registry.sh" ]]; then
    if source "$PROJECT_ROOT/lib/unity/services/registry.sh" 2>/dev/null; then
        echo "✅ Service registry loads successfully"
        
        # Check for critical functions
        if type -t unity_register_service >/dev/null 2>&1; then
            echo "✅ unity_register_service function available"
            ((TESTS_PASSED++))
        else
            echo "❌ unity_register_service function NOT available"
            ((TESTS_FAILED++))
        fi
    else
        echo "❌ Service registry failed to load"
        ((TESTS_FAILED++))
    fi
else
    echo "❌ Service registry not found"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 5: AWS Service Loading
#############################################

echo "Test 5: AWS Service Loading"
echo "---------------------------"

if [[ -f "$PROJECT_ROOT/lib/unity/services/aws/aws-service.sh" ]]; then
    # Test in isolation to catch loading errors
    (
        source "$PROJECT_ROOT/lib/unity/services/aws/aws-service.sh" 2>&1
    ) > "$UNITY_LOG_DIR/aws-load-test.log" 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo "✅ AWS service loads without errors"
        ((TESTS_PASSED++))
    else
        echo "❌ AWS service has loading errors"
        echo "   Check: $UNITY_LOG_DIR/aws-load-test.log"
        cat "$UNITY_LOG_DIR/aws-load-test.log" | head -10
        ((TESTS_FAILED++))
    fi
else
    echo "⚠️  AWS service not found (may not be implemented yet)"
fi

echo ""

#############################################
# Test 6: Bash Version Compatibility
#############################################

echo "Test 6: Bash Version Compatibility"
echo "----------------------------------"

echo "Current Bash version: $BASH_VERSION"

# Test basic bash compatibility features
if [[ "${BASH_VERSION%%.*}" -ge 3 ]]; then
    echo "✅ Bash version is 3.x or higher"
    ((TESTS_PASSED++))
else
    echo "❌ Bash version too old"
    ((TESTS_FAILED++))
fi

# Test string manipulation (works in bash 3+)
test_string="hello:world"
if [[ "${test_string%%:*}" == "hello" ]]; then
    echo "✅ String manipulation works"
    ((TESTS_PASSED++))
else
    echo "❌ String manipulation failed"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 7: Event Bus Loading
#############################################

echo "Test 7: Event Bus Loading"
echo "-------------------------"

if [[ -f "$PROJECT_ROOT/lib/unity/events/event-bus.sh" ]]; then
    # Load in subshell to test for errors
    if (source "$PROJECT_ROOT/lib/unity/events/event-bus.sh") 2>"$UNITY_LOG_DIR/event-bus-errors.log"; then
        echo "✅ Event bus loads successfully"
        ((TESTS_PASSED++))
    else
        echo "❌ Event bus failed to load"
        echo "   Errors:"
        cat "$UNITY_LOG_DIR/event-bus-errors.log"
        ((TESTS_FAILED++))
    fi
else
    echo "❌ Event bus not found at lib/unity/events/event-bus.sh"
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Test 8: Critical Function Integration
#############################################

echo "Test 8: Critical Function Integration"
echo "------------------------------------"

# Try to use the Unity system as it would be used
test_integration() {
    # Load Unity
    source "$PROJECT_ROOT/lib/unity/core/init.sh" 2>/dev/null || return 1
    
    # Try to emit an event
    if type -t unity_emit_event >/dev/null 2>&1; then
        unity_emit_event "test.integration" "test-source" "test-data" 2>/dev/null || return 1
        return 0
    else
        return 1
    fi
}

if test_integration 2>"$UNITY_LOG_DIR/integration-errors.log"; then
    echo "✅ Basic Unity integration works"
    ((TESTS_PASSED++))
else
    echo "❌ Unity integration failed"
    echo "   Check: $UNITY_LOG_DIR/integration-errors.log"
    if [[ -s "$UNITY_LOG_DIR/integration-errors.log" ]]; then
        echo "   First few errors:"
        head -5 "$UNITY_LOG_DIR/integration-errors.log"
    fi
    ((TESTS_FAILED++))
fi

echo ""

#############################################
# Summary
#############################################

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo "=================================="
echo "TEST SUMMARY"
echo "=================================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

# Generate report
REPORT_FILE="$PROJECT_ROOT/test-reports/unity-critical-fixes-$(date +%Y%m%d_%H%M%S).txt"
{
    echo "Unity Critical Fixes Test Report"
    echo "================================"
    echo "Date: $(date)"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""
    echo "Critical Issues Found:"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "1. Check lib/unity/core/init.sh for loading errors"
        echo "2. Ensure unity_emit_event is properly defined"
        echo "3. Check log directory creation and permissions"
        echo "4. Verify service registry functions"
        echo "5. Review event bus implementation"
    else
        echo "None - all critical tests passed!"
    fi
    
    echo ""
    echo "Log Directory: $UNITY_LOG_DIR"
} > "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All critical tests passed!"
    exit 0
else
    echo "❌ Critical issues found - please fix before proceeding"
    echo ""
    echo "Most common fixes needed:"
    echo "1. Ensure unity_emit_event is defined in event-bus.sh"
    echo "2. Check that Unity core init.sh sources all required files"
    echo "3. Verify log directory is created with proper permissions"
    echo "4. Make sure service registry defines all required functions"
    exit 1
fi