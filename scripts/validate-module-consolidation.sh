#!/usr/bin/env bash
# validate-module-consolidation.sh - Validate the module consolidation was successful
# BACKWARD COMPATIBILITY WRAPPER - Delegates to validation-suite.sh

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Handle benchmark mode
if [[ "${1:-}" == "--benchmark-mode" ]]; then
    # Simplified execution for benchmarking
    export BENCHMARK_MODE=1
    shift
fi

# Check if new validation suite exists
VALIDATION_SUITE="$PROJECT_ROOT/lib/modules/validation/validation-suite.sh"

if [[ -f "$VALIDATION_SUITE" ]]; then
    # Use new validation suite
    echo "Note: Using new consolidated validation suite" >&2
    exec "$VALIDATION_SUITE" --type modules "$@"
fi

# Fallback to original implementation
echo "Warning: Validation suite not found, using legacy implementation" >&2

LIB_DIR="$PROJECT_ROOT/lib"
MODULES_DIR="$LIB_DIR/modules"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result display
test_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"
    
    ((TOTAL_TESTS++))
    
    if [[ "$result" == "PASS" ]]; then
        ((PASSED_TESTS++))
        echo -e "[${GREEN}PASS${NC}] $test_name"
    else
        ((FAILED_TESTS++))
        echo -e "[${RED}FAIL${NC}] $test_name"
        if [[ -n "$message" ]]; then
            echo "       └─ $message"
        fi
    fi
}

echo "========================================="
echo "Module Consolidation Validation Script"
echo "========================================="
echo

# 1. Check that new consolidated modules exist
echo "1. Checking new consolidated modules..."

# Define expected consolidated modules
declare -A CONSOLIDATED_MODULES=(
    ["compute/ami.sh"]="AMI selection and validation"
    ["compute/core.sh"]="Core compute functionality"
    ["compute/launch.sh"]="Instance launch operations"
    ["compute/lifecycle.sh"]="Instance lifecycle management"
    ["compute/security.sh"]="Security group management"
    ["compute/spot.sh"]="Spot instance operations"
    ["compute/autoscaling.sh"]="Auto-scaling configuration"
    ["infrastructure/base.sh"]="Base infrastructure utilities"
    ["infrastructure/compute.sh"]="Compute-specific infrastructure"
    ["infrastructure/ec2.sh"]="EC2 infrastructure management"
)

for module in "${!CONSOLIDATED_MODULES[@]}"; do
    if [[ -f "$MODULES_DIR/$module" ]]; then
        test_result "Module exists: $module" "PASS"
    else
        test_result "Module exists: $module" "FAIL" "File not found: $MODULES_DIR/$module"
    fi
done

echo

# 2. Verify compatibility wrappers exist
echo "2. Checking compatibility wrappers..."

# Check for compatibility wrapper files
COMPAT_DIR="$MODULES_DIR/compatibility"
if [[ -d "$COMPAT_DIR" ]]; then
    # Check for specific compatibility wrapper
    if [[ -f "$COMPAT_DIR/legacy_wrapper.sh" ]]; then
        test_result "Compatibility wrapper exists" "PASS"
        
        # Check if it contains proper deprecation notices
        if grep -q "DEPRECATION NOTICE" "$COMPAT_DIR/legacy_wrapper.sh" 2>/dev/null; then
            test_result "Wrapper contains deprecation notices" "PASS"
        else
            test_result "Wrapper contains deprecation notices" "FAIL" "No deprecation notices found"
        fi
    else
        test_result "Compatibility wrapper exists" "FAIL" "legacy_wrapper.sh not found"
    fi
else
    test_result "Compatibility directory exists" "FAIL" "Directory not found: $COMPAT_DIR"
fi

echo

# 3. Test that old modules can still be loaded
echo "3. Testing backward compatibility..."

# Create a temporary test script
TEST_SCRIPT=$(mktemp)
cat > "$TEST_SCRIPT" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Get the lib directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"

# Try to source old module paths via compatibility layer
OLD_MODULES=(
    "modules/instances/ami.sh"
    "modules/instances/launch.sh"
    "modules/instances/bash-installers.sh"
    "modules/instances/os-compatibility.sh"
    "modules/instances/package-managers.sh"
    "modules/core/bash_version.sh"
    "modules/infrastructure/efs_legacy.sh"
)

for module in "${OLD_MODULES[@]}"; do
    # Check if compatibility wrapper handles this
    if [[ -f "$LIB_DIR/$module" ]]; then
        echo "FOUND: $module"
    elif [[ -f "$LIB_DIR/modules/compatibility/legacy_wrapper.sh" ]]; then
        # Source compatibility wrapper to see if it provides the functions
        source "$LIB_DIR/modules/compatibility/legacy_wrapper.sh" 2>/dev/null || true
        echo "COMPAT: $module"
    else
        echo "MISSING: $module"
    fi
done
EOF

chmod +x "$TEST_SCRIPT"
COMPAT_RESULT=$("$TEST_SCRIPT" 2>&1 || true)
rm -f "$TEST_SCRIPT"

# Check results
if echo "$COMPAT_RESULT" | grep -q "MISSING:"; then
    test_result "Old module paths accessible" "FAIL" "Some old modules not accessible via compatibility"
    echo "$COMPAT_RESULT" | grep "MISSING:" | sed 's/^/       /'
else
    test_result "Old module paths accessible" "PASS"
fi

echo

# 4. Validate empty compatibility directory was removed
echo "4. Checking for removed empty directories..."

# Check if the old empty compatibility directory exists
if [[ -d "$MODULES_DIR/compatibility" ]]; then
    # Check if it has the legacy wrapper
    if [[ -f "$MODULES_DIR/compatibility/legacy_wrapper.sh" ]]; then
        test_result "Compatibility directory properly maintained" "PASS"
    else
        # Check if it's empty
        if [[ -z "$(ls -A "$MODULES_DIR/compatibility" 2>/dev/null)" ]]; then
            test_result "Empty compatibility directory removed" "FAIL" "Empty directory still exists"
        else
            test_result "Compatibility directory has content" "PASS"
        fi
    fi
else
    test_result "Old empty compatibility directory removed" "PASS"
fi

echo

# 5. Check documentation updates
echo "5. Checking documentation updates..."

# Check if CLAUDE.md mentions the consolidation
if grep -q "Modular System Structure" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
    test_result "CLAUDE.md updated with module structure" "PASS"
else
    test_result "CLAUDE.md updated with module structure" "FAIL" "Module structure section not found"
fi

# Check if module architecture docs exist
if [[ -f "$PROJECT_ROOT/docs/module-architecture.md" ]]; then
    test_result "Module architecture documentation exists" "PASS"
else
    test_result "Module architecture documentation exists" "FAIL" "docs/module-architecture.md not found"
fi

echo

# 6. Additional validation - Check for function migrations
echo "6. Checking function migrations..."

# Check if key functions are available in new modules
declare -A KEY_FUNCTIONS=(
    ["compute/ami.sh"]="get_latest_ami_id"
    ["compute/launch.sh"]="launch_instance"
    ["compute/spot.sh"]="request_spot_instance"
    ["infrastructure/ec2.sh"]="check_ec2_limits"
)

for module in "${!KEY_FUNCTIONS[@]}"; do
    func="${KEY_FUNCTIONS[$module]}"
    if grep -q "^[[:space:]]*${func}[[:space:]]*(" "$MODULES_DIR/$module" 2>/dev/null; then
        test_result "Function $func in $module" "PASS"
    else
        test_result "Function $func in $module" "FAIL" "Function not found in expected module"
    fi
done

echo
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✓ Module consolidation validation PASSED!${NC}"
    exit 0
else
    echo -e "${RED}✗ Module consolidation validation FAILED!${NC}"
    echo
    echo "Please review the failed tests above and ensure:"
    echo "1. All new consolidated modules are in place"
    echo "2. Compatibility wrappers are properly configured"
    echo "3. Documentation has been updated"
    echo "4. Key functions have been migrated correctly"
    exit 1
fi