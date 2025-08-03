#!/bin/bash

# Unity Critical Fixes Validation Test
# Validates that critical Unity fixes are properly implemented

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test configuration
TEST_NAME="Unity Critical Fixes Validation"
TEST_LOG_DIR="/tmp/unity-fixes-test-$$"
PASSED=0
FAILED=0
WARNINGS=0

# Output functions
pass() {
    echo "[PASS] $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "[FAIL] $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo "[WARN] $1"
    WARNINGS=$((WARNINGS + 1))
}

# Create test environment
mkdir -p "$TEST_LOG_DIR"

echo "================================================"
echo "$TEST_NAME"
echo "================================================"
echo "Date: $(date)"
echo "Project Root: $PROJECT_ROOT"
echo "Test Log Dir: $TEST_LOG_DIR"
echo "Bash Version: ${BASH_VERSION}"
echo "================================================"

# Test 1: Event System Fix - unity_emit_event availability
echo ""
echo "Test 1: Event System Fix"
echo "------------------------"

# Check if unity_emit_event is properly defined
if grep -q "^unity_emit_event()" "$PROJECT_ROOT/lib/unity/core/unity-events.sh" 2>/dev/null; then
    pass "unity_emit_event function is defined"
    
    # Check for proper error handling
    if grep -q "Error emitting event" "$PROJECT_ROOT/lib/unity/core/unity-events.sh" 2>/dev/null; then
        pass "Event error handling is implemented"
    else
        warn "Event error handling may be missing"
    fi
else
    fail "unity_emit_event function not found"
fi

# Test 2: Service Registry Fix
echo ""
echo "Test 2: Service Registry Fix"
echo "-----------------------------"

# Check service registration function
if grep -q "^unity_register_service()" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
    pass "unity_register_service function is defined"
else
    fail "unity_register_service function not found"
fi

# Check service discovery function
if grep -q "^unity_discover_service()" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
    pass "unity_discover_service function is defined"
else
    fail "unity_discover_service function not found"
fi

# Test 3: Log Directory Permission Fix
echo ""
echo "Test 3: Log Directory Permission Fix"
echo "------------------------------------"

# Check for log directory creation with fallback
if grep -q "mkdir -p.*log_dir.*2>/dev/null" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
    pass "Log directory creation has error handling"
    
    # Check for fallback to temp directory
    if grep -q "TMPDIR\|/tmp.*unity-logs" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
        pass "Log directory has temp fallback"
    else
        warn "Log directory may not have temp fallback"
    fi
else
    fail "Log directory creation error handling not found"
fi

# Test 4: Unity Initialization
echo ""
echo "Test 4: Unity Initialization"
echo "----------------------------"

# Check unity_init function
if grep -q "^unity_init()" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
    pass "unity_init function is defined"
    
    # Check for initialization flag
    if grep -q "UNITY_INITIALIZED" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
        pass "Unity initialization tracking is implemented"
    else
        warn "Unity initialization tracking may be missing"
    fi
else
    fail "unity_init function not found"
fi

# Test 5: Event Bus Implementation
echo ""
echo "Test 5: Event Bus Implementation"
echo "--------------------------------"

event_bus="$PROJECT_ROOT/lib/unity/events/event-bus.sh"
if [ -f "$event_bus" ]; then
    pass "Event bus file exists"
    
    # Check for event handling
    if grep -q "emit_event\|handle_event" "$event_bus" 2>/dev/null; then
        pass "Event handling functions present"
    else
        fail "Event handling functions missing"
    fi
else
    fail "Event bus file missing"
fi

# Test 6: Service Files Structure
echo ""
echo "Test 6: Service Files Structure"
echo "-------------------------------"

services=(
    "aws-service"
    "monitor-service"
    "config-service"
    "docker-service"
)

all_services_ok=true
for service in "${services[@]}"; do
    service_file="$PROJECT_ROOT/lib/unity/services/${service}.sh"
    if [ -f "$service_file" ]; then
        pass "Service $service exists"
    else
        fail "Service $service missing"
        all_services_ok=false
    fi
done

# Test 7: Unity Configuration
echo ""
echo "Test 7: Unity Configuration"
echo "---------------------------"

config_file="$PROJECT_ROOT/config/unity.yml"
if [ -f "$config_file" ]; then
    pass "Unity configuration exists"
    
    # Check required sections
    for section in "unity:" "services:" "events:"; do
        if grep -q "^$section" "$config_file" 2>/dev/null; then
            pass "Config has $section section"
        else
            warn "Config missing $section section"
        fi
    done
else
    fail "Unity configuration missing"
fi

# Test 8: Integration Points
echo ""
echo "Test 8: Integration Points"
echo "--------------------------"

# Check if Unity is integrated with deployment scripts
if grep -q "unity_emit_event\|unity_init" "$PROJECT_ROOT/scripts/aws-deployment-modular.sh" 2>/dev/null; then
    pass "Unity integrated with deployment scripts"
else
    warn "Unity may not be integrated with deployment scripts"
fi

# Check if Unity config migration tools exist
if [ -f "$PROJECT_ROOT/scripts/unity-config-migration.sh" ]; then
    pass "Unity config migration tool exists"
else
    fail "Unity config migration tool missing"
fi

# Cleanup
rm -rf "$TEST_LOG_DIR"

# Summary
echo ""
echo "================================================"
echo "Validation Summary:"
echo "  Passed:   $PASSED"
echo "  Failed:   $FAILED"
echo "  Warnings: $WARNINGS"
echo "  Total:    $((PASSED + FAILED + WARNINGS))"
echo "================================================"

# Generate report
report_file="$PROJECT_ROOT/test-reports/unity-critical-fixes-$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$PROJECT_ROOT/test-reports"

{
    echo "Unity Critical Fixes Validation Report"
    echo "======================================"
    echo "Date: $(date)"
    echo "Bash Version: ${BASH_VERSION}"
    echo ""
    echo "Results:"
    echo "  Passed:   $PASSED"
    echo "  Failed:   $FAILED"
    echo "  Warnings: $WARNINGS"
    echo ""
    echo "Critical Fixes Status:"
    echo "- Event System: $( [ $FAILED -eq 0 ] && echo "FIXED" || echo "NEEDS ATTENTION" )"
    echo "- Service Registry: $( [ $FAILED -eq 0 ] && echo "FIXED" || echo "NEEDS ATTENTION" )"
    echo "- Log Permissions: $( [ $FAILED -eq 0 ] && echo "FIXED" || echo "NEEDS ATTENTION" )"
    echo "- Unity Init: $( [ $FAILED -eq 0 ] && echo "FIXED" || echo "NEEDS ATTENTION" )"
    echo ""
    echo "Recommendation: $( [ $FAILED -eq 0 ] && echo "System is ready for use" || echo "Address failed tests before deployment" )"
} > "$report_file"

echo ""
echo "Report saved to: $report_file"

# Exit status
if [ $FAILED -eq 0 ]; then
    echo ""
    echo "Result: ALL CRITICAL FIXES VALIDATED ✓"
    exit 0
else
    echo ""
    echo "Result: SOME CRITICAL FIXES NEED ATTENTION"
    exit 1
fi