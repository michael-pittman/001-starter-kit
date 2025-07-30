#!/usr/bin/env bash
#
# Test script for network connectivity validation
# BACKWARD COMPATIBILITY WRAPPER - Delegates to validation-suite.sh
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if new validation suite exists
VALIDATION_SUITE="$PROJECT_ROOT/lib/modules/validation/validation-suite.sh"

if [[ -f "$VALIDATION_SUITE" ]]; then
    # Use new validation suite for network tests
    echo "Note: Using new consolidated validation suite for network tests" >&2
    
    echo "========================================"
    echo "Network Connectivity Validation Test"
    echo "========================================"
    echo ""
    
    # Test 1: Production mode (default)
    echo "Test 1: Production mode (default)"
    echo "================================="
    unset ENVIRONMENT
    unset DEPLOYMENT_MODE
    unset DEVELOPMENT_MODE
    unset SKIP_NETWORK_CHECK
    "$VALIDATION_SUITE" --type network
    echo ""
    
    # Test 2: Development mode via ENVIRONMENT
    echo "Test 2: Development mode (ENVIRONMENT=development)"
    echo "=================================================="
    export ENVIRONMENT="development"
    "$VALIDATION_SUITE" --type network
    unset ENVIRONMENT
    echo ""
    
    # Test 3: Skip network check flag
    echo "Test 3: Skip network check (SKIP_NETWORK_CHECK=true)"
    echo "====================================================="
    export SKIP_NETWORK_CHECK="true"
    "$VALIDATION_SUITE" --type network
    unset SKIP_NETWORK_CHECK
    echo ""
    
    echo "========================================"
    echo "Network validation tests completed!"
    echo "========================================"
    exit 0
fi

# Fallback to original implementation
echo "Warning: Validation suite not found, using legacy implementation" >&2

# Source the library loader
if [[ -f "$PROJECT_ROOT/lib/utils/library-loader.sh" ]]; then
    source "$PROJECT_ROOT/lib/utils/library-loader.sh"
else
    echo "ERROR: Cannot find lib-loader.sh in $PROJECT_ROOT/lib/" >&2
    exit 1
fi

# Enable error handling
set -euo pipefail

# Load required libraries
declare -a REQUIRED_LIBS=(
    "deployment-validation.sh"
)

if ! load_libraries "${REQUIRED_LIBS[@]}"; then
    echo "ERROR: Failed to load required libraries" >&2
    exit 1
fi

echo "========================================"
echo "Network Connectivity Validation Test"
echo "========================================"
echo ""

# Test 1: Production mode (default)
echo "Test 1: Production mode (default)"
echo "================================="
unset ENVIRONMENT
unset DEPLOYMENT_MODE
unset DEVELOPMENT_MODE
unset SKIP_NETWORK_CHECK
check_network_connectivity
echo ""

# Test 2: Development mode via ENVIRONMENT
echo "Test 2: Development mode (ENVIRONMENT=development)"
echo "=================================================="
export ENVIRONMENT="development"
unset DEPLOYMENT_MODE
unset DEVELOPMENT_MODE
unset SKIP_NETWORK_CHECK
check_network_connectivity
unset ENVIRONMENT
echo ""

# Test 3: Development mode via DEPLOYMENT_MODE
echo "Test 3: Development mode (DEPLOYMENT_MODE=development)"
echo "======================================================"
unset ENVIRONMENT
export DEPLOYMENT_MODE="development"
unset DEVELOPMENT_MODE
unset SKIP_NETWORK_CHECK
check_network_connectivity
unset DEPLOYMENT_MODE
echo ""

# Test 4: Skip network check flag
echo "Test 4: Skip network check (SKIP_NETWORK_CHECK=true)"
echo "====================================================="
unset ENVIRONMENT
unset DEPLOYMENT_MODE
unset DEVELOPMENT_MODE
export SKIP_NETWORK_CHECK="true"
check_network_connectivity
unset SKIP_NETWORK_CHECK
echo ""

# Test 5: Full validation in development mode
echo "Test 5: Full validation in development mode"
echo "==========================================="
export ENVIRONMENT="development"
validate_deployment_prerequisites "test-stack" "us-east-1"
unset ENVIRONMENT
echo ""

echo "========================================"
echo "Network validation tests completed!"
echo "========================================"