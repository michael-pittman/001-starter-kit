#!/bin/bash

# Minimal Unity Integration Test
# Tests critical fixes without sourcing Unity modules

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test configuration
TEST_NAME="Unity Minimal Test"
TEST_LOG_DIR="/tmp/unity-test-$$"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test tracking
test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

# Create test environment
mkdir -p "$TEST_LOG_DIR"

echo "================================================"
echo "$TEST_NAME"
echo "================================================"
echo "Project Root: $PROJECT_ROOT"
echo "Test Log Dir: $TEST_LOG_DIR"
echo "Bash Version: ${BASH_VERSION}"
echo "================================================"

# Test 1: Unity Files Exist
echo -e "\n${YELLOW}Test 1: Unity Files Exist${NC}"

files=(
    "lib/unity/core/unity-core.sh"
    "lib/unity/core/unity-events.sh"
    "lib/unity/core/registry.sh"
    "lib/unity/services/aws.sh"
    "lib/unity/services/monitor.sh"
    "lib/unity/events/event-bus.sh"
    "config/unity.yml"
)

for file in "${files[@]}"; do
    if [[ -f "$PROJECT_ROOT/$file" ]]; then
        test_pass "File $file exists"
    else
        test_fail "File $file missing"
    fi
done

# Test 2: Unity Functions Defined
echo -e "\n${YELLOW}Test 2: Unity Functions Defined${NC}"

# Check if functions are defined in files
functions=(
    "unity_init:lib/unity/core/unity-core.sh"
    "unity_emit_event:lib/unity/core/unity-events.sh"
    "unity_on_event:lib/unity/core/unity-events.sh"
    "unity_register_service:lib/unity/core/unity-core.sh"
    "unity_discover_service:lib/unity/core/unity-core.sh"
)

for func_file in "${functions[@]}"; do
    IFS=: read -r func file <<< "$func_file"
    if grep -q "^${func}()" "$PROJECT_ROOT/$file" 2>/dev/null; then
        test_pass "Function $func defined in $file"
    else
        test_fail "Function $func not found in $file"
    fi
done

# Test 3: Log Directory Permissions
echo -e "\n${YELLOW}Test 3: Log Directory Permissions${NC}"

if [[ -w "$TEST_LOG_DIR" ]]; then
    test_pass "Log directory writable"
    
    # Test file creation
    if touch "$TEST_LOG_DIR/test-$$" 2>/dev/null; then
        test_pass "Can create files in log directory"
        rm -f "$TEST_LOG_DIR/test-$$"
    else
        test_fail "Cannot create files in log directory"
    fi
else
    test_fail "Log directory not writable"
fi

# Test 4: Unity Config Readable
echo -e "\n${YELLOW}Test 4: Unity Configuration${NC}"

config_file="$PROJECT_ROOT/config/unity.yml"
if [[ -f "$config_file" ]]; then
    test_pass "Unity config exists"
    
    # Check if it's valid YAML (basic check)
    if grep -q "^unity:" "$config_file" 2>/dev/null; then
        test_pass "Unity config has unity section"
    else
        test_fail "Unity config missing unity section"
    fi
else
    test_fail "Unity config missing"
fi

# Test 5: Service Files Structure
echo -e "\n${YELLOW}Test 5: Service Files Structure${NC}"

services=(
    "aws"
    "monitor"
    "config"
    "docker"
)

for service in "${services[@]}"; do
    service_file="$PROJECT_ROOT/lib/unity/services/${service}.sh"
    if [[ -f "$service_file" ]]; then
        # Check for required functions
        if grep -q "init_${service}_service" "$service_file" 2>/dev/null; then
            test_pass "Service $service has init function"
        else
            test_fail "Service $service missing init function"
        fi
    else
        test_fail "Service $service file missing"
    fi
done

# Test 6: Event Bus Structure
echo -e "\n${YELLOW}Test 6: Event Bus Structure${NC}"

event_file="$PROJECT_ROOT/lib/unity/events/event-bus.sh"
if [[ -f "$event_file" ]]; then
    test_pass "Event bus file exists"
    
    # Check for event handling functions
    if grep -q "emit_event\|handle_event" "$event_file" 2>/dev/null; then
        test_pass "Event bus has event functions"
    else
        test_fail "Event bus missing event functions"
    fi
else
    test_fail "Event bus file missing"
fi

# Test 7: Unity CLI
echo -e "\n${YELLOW}Test 7: Unity CLI${NC}"

cli_file="$PROJECT_ROOT/scripts/unity-cli.sh"
if [[ -f "$cli_file" ]]; then
    test_pass "Unity CLI exists"
    
    if [[ -x "$cli_file" ]]; then
        test_pass "Unity CLI is executable"
    else
        test_fail "Unity CLI not executable"
    fi
else
    test_fail "Unity CLI missing"
fi

# Cleanup
rm -rf "$TEST_LOG_DIR"

# Summary
echo -e "\n================================================"
echo "Test Summary:"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"

total=$((PASSED + FAILED))
if [[ $total -gt 0 ]]; then
    pass_rate=$(( (PASSED * 100) / total ))
    echo "  Pass Rate: ${pass_rate}%"
fi
echo "================================================"

# Exit status
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi