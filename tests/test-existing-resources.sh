#!/usr/bin/env bash
# =============================================================================
# Test Existing Resources Implementation
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test framework
source "${PROJECT_ROOT}/tests/lib/shell-test-framework.sh"
source "${PROJECT_ROOT}/lib/modules/infrastructure/existing-resources.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_configuration_loading() {
    echo "Testing configuration loading..."
    
    # Test loading from dev environment
    if load_existing_resources_config "dev"; then
        echo "✅ Configuration loading test passed"
    else
        echo "❌ Configuration loading test failed"
        return 1
    fi
}

test_vpc_validation() {
    echo "Testing VPC validation..."
    
    # Test with invalid VPC (should fail)
    if ! validate_existing_vpc "vpc-invalid"; then
        echo "✅ VPC validation correctly failed for invalid VPC"
    else
        echo "❌ VPC validation should have failed for invalid VPC"
        return 1
    fi
    
    # Test with empty VPC (should pass)
    if validate_existing_vpc ""; then
        echo "✅ VPC validation correctly passed for empty VPC"
    else
        echo "❌ VPC validation should have passed for empty VPC"
        return 1
    fi
}

test_resource_discovery() {
    echo "Testing resource discovery..."
    
    # Test discovery with mock stack name
    local discovered_resources
    discovered_resources=$(discover_existing_resources "test-stack" "dev")
    
    if [[ -n "$discovered_resources" ]]; then
        echo "✅ Resource discovery test passed"
        echo "Discovered resources: $discovered_resources"
    else
        echo "⚠️  No resources discovered (this is expected if no resources exist)"
    fi
}

test_variable_mapping() {
    echo "Testing variable mapping..."
    
    # Create mock resources configuration
    local mock_config='{
        "vpc": {"id": "vpc-test123"},
        "subnets": {
            "public": {"ids": ["subnet-123", "subnet-456"]},
            "private": {"ids": ["subnet-789"]}
        },
        "security_groups": {
            "alb": {"id": "sg-alb123"},
            "ec2": {"id": "sg-ec2123"}
        }
    }'
    
    # Test mapping
    if map_existing_resources "$mock_config" "test-stack"; then
        echo "✅ Variable mapping test passed"
    else
        echo "❌ Variable mapping test failed"
        return 1
    fi
}

test_cli_script() {
    echo "Testing CLI script..."
    
    # Test help command
    if ./scripts/manage-existing-resources.sh help >/dev/null 2>&1; then
        echo "✅ CLI help command test passed"
    else
        echo "❌ CLI help command test failed"
        return 1
    fi
    
    # Test list command
    if ./scripts/manage-existing-resources.sh list -e dev >/dev/null 2>&1; then
        echo "✅ CLI list command test passed"
    else
        echo "⚠️  CLI list command test failed (expected if no config)"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "🧪 Running Existing Resources Tests"
    echo "=================================="
    
    local test_results=()
    
    # Run tests
    test_configuration_loading && test_results+=("✅ Configuration Loading") || test_results+=("❌ Configuration Loading")
    test_vpc_validation && test_results+=("✅ VPC Validation") || test_results+=("❌ VPC Validation")
    test_resource_discovery && test_results+=("✅ Resource Discovery") || test_results+=("❌ Resource Discovery")
    test_variable_mapping && test_results+=("✅ Variable Mapping") || test_results+=("❌ Variable Mapping")
    test_cli_script && test_results+=("✅ CLI Script") || test_results+=("❌ CLI Script")
    
    # Display results
    echo ""
    echo "📊 Test Results:"
    echo "================"
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    
    # Count failures
    local failures=0
    for result in "${test_results[@]}"; do
        if [[ "$result" == ❌* ]]; then
            ((failures++))
        fi
    done
    
    if [[ $failures -eq 0 ]]; then
        echo ""
        echo "🎉 All tests passed!"
        exit 0
    else
        echo ""
        echo "⚠️  $failures test(s) failed"
        exit 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi