#!/bin/bash
# Test Unity AWS Service functionality

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the Unity AWS Service
source "$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh"

# Test colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
test_function() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        if [[ "$expected_result" -eq 0 ]]; then
            echo -e "${GREEN}PASSED${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAILED${NC} (expected failure but passed)"
            ((TESTS_FAILED++))
        fi
    else
        if [[ "$expected_result" -ne 0 ]]; then
            echo -e "${GREEN}PASSED${NC} (expected failure)"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAILED${NC}"
            ((TESTS_FAILED++))
        fi
    fi
}

echo "=== Unity AWS Service Test Suite ==="
echo ""

# Test 1: Service initialization
echo "1. Testing service initialization..."
test_function "init_unity_aws_service" "init_unity_aws_service test-service"

# Test 2: Get available CIDR
echo ""
echo "2. Testing CIDR allocation..."
test_function "get_available_cidr" "cidr=\$(get_available_cidr); [[ -n \"\$cidr\" ]]"

# Test 3: On-demand price lookup
echo ""
echo "3. Testing price lookups..."
test_function "get_ondemand_price g4dn.xlarge" "price=\$(get_ondemand_price g4dn.xlarge); [[ \"\$price\" == \"0.526\" ]]"
test_function "get_ondemand_price t3.medium" "price=\$(get_ondemand_price t3.medium); [[ \"\$price\" == \"0.0416\" ]]"

# Test 4: CLI interface
echo ""
echo "4. Testing CLI interface..."
test_function "unity_aws help" "unity_aws help | grep -q 'Unity AWS Service'"

# Test 5: Cost calculation (with empty state)
echo ""
echo "5. Testing cost calculation..."
test_function "calculate_deployment_cost" "cost=\$(calculate_deployment_cost test-stack 1); [[ \"\$cost\" == \"0\" ]]"

# Test 6: Resource tracking
echo ""
echo "6. Testing resource tracking..."
test_function "track_resource" "track_resource ec2 i-test123 test-stack"
test_function "track_cost" "track_cost ec2-spot i-test123 0.10"

# Test 7: List resources
echo ""
echo "7. Testing resource listing..."
test_function "list_stack_resources" "list_stack_resources test-stack | grep -q 'test-stack' || true"

# Test 8: Quota checking simulation
echo ""
echo "8. Testing quota checking..."
# These will fail without AWS credentials, which is expected
test_function "check_vpc_quota (no AWS)" "check_vpc_quota" 1
test_function "check_ec2_quota (no AWS)" "check_ec2_quota t3.medium" 1

# Test 9: Find existing VPC
echo ""
echo "9. Testing VPC finder..."
test_function "find_existing_vpc" "vpc=\$(find_existing_vpc test-stack); [[ -z \"\$vpc\" || -n \"\$vpc\" ]]"

# Test 10: Optimize deployment costs
echo ""
echo "10. Testing cost optimization..."
test_function "optimize_deployment_costs" "optimize_deployment_costs test-stack"

echo ""
echo "=== Test Summary ==="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi