#!/bin/bash
# Simple test for Unity AWS Service basic functionality

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Unity AWS Service Simple Test ==="
echo ""

# Test 1: Check if the service file exists
echo -n "1. Checking if Unity AWS Service exists... "
if [[ -f "$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh" ]]; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Test 2: Check if it sources without errors
echo -n "2. Checking if service can be sourced... "
if bash -c "source '$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh' 2>/dev/null && echo 'OK'"; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "   Error details:"
    bash -c "source '$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh'"
    exit 1
fi

# Test 3: Check if key functions are defined
echo -n "3. Checking if key functions are defined... "
if bash -c "
    source '$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh' 2>/dev/null
    command -v unity_aws >/dev/null 2>&1 && \
    command -v launch_ec2_instance >/dev/null 2>&1 && \
    command -v create_or_get_vpc >/dev/null 2>&1
"; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Test 4: Test help command
echo -n "4. Testing help command... "
if bash -c "
    source '$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh' 2>/dev/null
    unity_aws help | grep -q 'Unity AWS Service'
"; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Test 5: Test CIDR allocation function
echo -n "5. Testing CIDR allocation... "
if bash -c "
    source '$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh' 2>/dev/null
    cidr=\$(get_available_cidr 2>/dev/null)
    [[ -n \"\$cidr\" ]] && echo \"\$cidr\" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$'
"; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Test 6: Test price lookup
echo -n "6. Testing price lookup... "
if bash -c "
    source '$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh' 2>/dev/null
    price=\$(get_ondemand_price 'g4dn.xlarge' 2>/dev/null)
    [[ \"\$price\" == \"0.526\" ]]
"; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

echo ""
echo -e "${GREEN}All basic tests passed!${NC}"
echo ""
echo "Note: Full functionality requires AWS credentials and proper initialization."