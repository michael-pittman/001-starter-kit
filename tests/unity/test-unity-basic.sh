#!/bin/bash

# Basic Unity Test - Compatible with bash 3.2+
# Tests critical Unity components

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test results
PASSED=0
FAILED=0

# Simple output functions
pass() {
    echo "[PASS] $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "[FAIL] $1"
    FAILED=$((FAILED + 1))
}

echo "================================================"
echo "Unity Basic Test"
echo "================================================"
echo "Project Root: $PROJECT_ROOT"
echo "Bash Version: ${BASH_VERSION}"
echo "================================================"

# Test 1: Unity Core Files
echo ""
echo "Test 1: Unity Core Files"
echo "------------------------"

if [ -f "$PROJECT_ROOT/lib/unity/core/unity-core.sh" ]; then
    pass "unity-core.sh exists"
else
    fail "unity-core.sh missing"
fi

if [ -f "$PROJECT_ROOT/lib/unity/core/unity-events.sh" ]; then
    pass "unity-events.sh exists"
else
    fail "unity-events.sh missing"
fi

if [ -f "$PROJECT_ROOT/lib/unity/core/registry.sh" ]; then
    pass "registry.sh exists"
else
    fail "registry.sh missing"
fi

# Test 2: Unity Service Files
echo ""
echo "Test 2: Unity Service Files"
echo "---------------------------"

for service in aws-service monitor-service config-service docker-service; do
    if [ -f "$PROJECT_ROOT/lib/unity/services/${service}.sh" ]; then
        pass "Service $service exists"
    else
        fail "Service $service missing"
    fi
done

# Test 3: Unity Configuration
echo ""
echo "Test 3: Unity Configuration"
echo "---------------------------"

if [ -f "$PROJECT_ROOT/config/unity.yml" ]; then
    pass "unity.yml exists"
    
    # Check basic structure
    if grep -q "^unity:" "$PROJECT_ROOT/config/unity.yml" 2>/dev/null; then
        pass "unity.yml has unity section"
    else
        fail "unity.yml missing unity section"
    fi
else
    fail "unity.yml missing"
fi

# Test 4: Unity Scripts
echo ""
echo "Test 4: Unity Scripts"
echo "---------------------"

if [ -f "$PROJECT_ROOT/scripts/unity-config-migration.sh" ]; then
    pass "unity-config-migration.sh exists"
else
    fail "unity-config-migration.sh missing"
fi

if [ -f "$PROJECT_ROOT/scripts/unity-config-migration-cli.sh" ]; then
    pass "unity-config-migration-cli.sh exists"
else
    fail "unity-config-migration-cli.sh missing"
fi

# Test 5: Event Bus
echo ""
echo "Test 5: Event Bus"
echo "-----------------"

if [ -f "$PROJECT_ROOT/lib/unity/events/event-bus.sh" ]; then
    pass "event-bus.sh exists"
else
    fail "event-bus.sh missing"
fi

# Test 6: Function Definitions
echo ""
echo "Test 6: Function Definitions"
echo "----------------------------"

# Check for key functions in files
if grep -q "^unity_init()" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
    pass "unity_init defined"
else
    fail "unity_init not found"
fi

if grep -q "^unity_emit_event()" "$PROJECT_ROOT/lib/unity/core/unity-events.sh" 2>/dev/null; then
    pass "unity_emit_event defined"
else
    fail "unity_emit_event not found"
fi

if grep -q "^unity_register_service()" "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null; then
    pass "unity_register_service defined"
else
    fail "unity_register_service not found"
fi

# Summary
echo ""
echo "================================================"
echo "Test Summary:"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "  Total:  $((PASSED + FAILED))"
echo "================================================"

if [ $FAILED -eq 0 ]; then
    echo "Result: ALL TESTS PASSED"
    exit 0
else
    echo "Result: SOME TESTS FAILED"
    exit 1
fi