#!/usr/bin/env bash
# =============================================================================
# Validation test for deployment type selection (Story 3.3)
# =============================================================================

set -euo pipefail

echo "=========================================="
echo "Deployment Type Selection Validation"
echo "=========================================="
echo ""

# Test 1: Help output contains deployment types
echo "Test 1: Checking help output..."
if ./deploy.sh --help | grep -q "DEPLOYMENT TYPES:"; then
    echo "✓ Help contains DEPLOYMENT TYPES section"
else
    echo "✗ Help missing DEPLOYMENT TYPES section"
    exit 1
fi

if ./deploy.sh --help | grep -q "70% cost savings"; then
    echo "✓ Help contains spot savings information"
else
    echo "✗ Help missing spot savings information"
    exit 1
fi

# Test 2: Check all deployment types are documented
echo ""
echo "Test 2: Checking deployment type documentation..."
for type in spot alb cdn full; do
    if ./deploy.sh --help | grep -q -- "--type $type"; then
        echo "✓ Help documents --type $type"
    else
        echo "✗ Help missing --type $type"
        exit 1
    fi
done

# Test 3: Version output works
echo ""
echo "Test 3: Checking version output..."
version_output=$(./deploy.sh --version 2>&1)
if echo "$version_output" | grep -q "GeuseMaker Deployment Orchestrator"; then
    echo "✓ Version output works correctly"
else
    echo "✗ Version output failed"
    echo "Output was: $version_output"
    exit 1
fi

# Test 4: Check deployment type details section
echo ""
echo "Test 4: Checking deployment type details..."
if ./deploy.sh --help | grep -q "DEPLOYMENT TYPE DETAILS:"; then
    echo "✓ Help contains deployment type details section"
else
    echo "✗ Help missing deployment type details section"
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "✓ All deployment type validation tests passed!"
echo "=========================================="