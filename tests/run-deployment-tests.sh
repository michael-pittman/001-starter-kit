#!/bin/bash
# run-deployment-tests.sh - Simple runner for deployment tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Deployment Test Suite Runner${NC}"
echo -e "${BLUE}================================${NC}"
echo

# Check if we should run in live mode
if [[ "${1:-}" == "--live" ]]; then
    echo -e "${RED}WARNING: Live mode will create actual AWS resources!${NC}"
    echo "This may incur AWS charges."
    read -p "Are you absolutely sure? Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
    echo
fi

# Run the comprehensive test suite
echo -e "${YELLOW}Running comprehensive deployment tests...${NC}"
"$SCRIPT_DIR/test-deployment-comprehensive.sh" "$@"

# Check exit code
if [[ $? -eq 0 ]]; then
    echo -e "\n${GREEN}✓ All tests passed!${NC}"
else
    echo -e "\n${RED}✗ Some tests failed. Check the report for details.${NC}"
    exit 1
fi