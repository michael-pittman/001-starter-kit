#!/usr/bin/env bash
# Simple test to validate library system usage on a subset of scripts
# Exit codes:
# 0 - All scripts use libraries correctly
# 1 - Scripts found bypassing library system

# Compatible with bash 3.x+

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Load required modules through the library system
load_module "core/errors"
load_module "core/logging"
safe_source "aws-deployment-common.sh" true "AWS deployment common"

# Test specific scripts
declare -a TEST_SCRIPTS=(
    "$PROJECT_ROOT/scripts/aws-deployment-v2-simple.sh"
    "$PROJECT_ROOT/scripts/aws-deployment-modular.sh"
    "$PROJECT_ROOT/lib/deployment-health.sh"
    "$PROJECT_ROOT/lib/deployment-validation.sh"
    "$PROJECT_ROOT/lib/modules/compute/provisioner.sh"
)

# Patterns that indicate direct module sourcing (violations)
declare -a VIOLATION_PATTERNS=(
    'source.*modules/core/'
    'source.*modules/infrastructure/'
    'source.*modules/compute/'
    'source.*modules/application/'
    'source.*modules/cleanup/'
    'source.*modules/errors/'
    'source.*modules/deployment/'
    'source.*modules/monitoring/'
)

echo -e "${BLUE}Library System Usage Quick Test${NC}"
echo -e "${BLUE}===============================${NC}"
echo ""

TOTAL_VIOLATIONS=0

for script in "${TEST_SCRIPTS[@]}"; do
    if [[ ! -f "$script" ]]; then
        echo -e "${YELLOW}Skipping (not found): $script${NC}"
        continue
    fi
    
    echo -e "${BLUE}Checking: ${script#$PROJECT_ROOT/}${NC}"
    
    violations=0
    while IFS= read -r line; do
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        for pattern in "${VIOLATION_PATTERNS[@]}"; do
            if [[ "$line" =~ $pattern ]]; then
                echo -e "${RED}  ✗ Found direct module source: $line${NC}"
                ((violations++))
            fi
        done
    done < "$script"
    
    if [[ $violations -eq 0 ]]; then
        echo -e "${GREEN}  ✓ OK - No direct module sourcing${NC}"
    else
        echo -e "${RED}  ✗ FAIL - Found $violations violations${NC}"
        ((TOTAL_VIOLATIONS++))
    fi
    echo ""
done

echo -e "${BLUE}Summary:${NC}"
if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checked scripts follow library conventions!${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $TOTAL_VIOLATIONS scripts with violations${NC}"
    exit 1
fi