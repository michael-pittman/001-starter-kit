#!/usr/bin/env bash
# =============================================================================
# Test Bash Version Validation Module
# Tests the bash version checking functionality across different scenarios
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

test_count=0
pass_count=0

# Test tracking functions
start_test() {
    ((test_count++))
    echo -e "${BLUE}[TEST $test_count] $1${NC}"
}

pass_test() {
    ((pass_count++))
    echo -e "${GREEN}  ✓ PASS${NC}"
}

fail_test() {
    echo -e "${RED}  ✗ FAIL: $1${NC}"
}

# Source the bash version module
source "$PROJECT_ROOT/lib/modules/core/bash_version.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_version_parsing() {
    start_test "Version component parsing"
    
    # Test current bash version parsing
    local components
    components=$(get_bash_version_components)
    
    if [[ $? -eq 0 ]] && [[ -n "$components" ]]; then
        pass_test
        echo "    Current bash components: $components"
    else
        fail_test "Failed to parse bash version components"
    fi
}

test_version_comparison() {
    start_test "Version comparison logic"
    
    if check_bash_version; then
        pass_test
        echo "    Current bash version meets minimum requirements"
    else
        fail_test "Current bash version fails minimum requirement check"
        echo "    Current: $(get_current_bash_version)"
        echo "    Required: $BASH_MIN_VERSION_STRING+"
    fi
}

test_platform_detection() {
    start_test "Platform detection"
    
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos|ubuntu|debian|amzn|amazonlinux|linux|unknown)
            pass_test
            echo "    Detected platform: $platform"
            ;;
        *)
            fail_test "Invalid platform detected: $platform"
            ;;
    esac
}

test_convenience_functions() {
    start_test "Convenience functions"
    
    # Test bash_533_available
    if bash_533_available; then
        pass_test
        echo "    bash_533_available() correctly returns true"
    else
        fail_test "bash_533_available() returns false when it should be true"
    fi
    
    # Test get_current_bash_version
    local version
    version=$(get_current_bash_version)
    if [[ -n "$version" ]] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        pass_test
        echo "    get_current_bash_version() returns: $version"
    else
        fail_test "get_current_bash_version() returned invalid format: $version"
    fi
}

test_upgrade_instructions() {
    start_test "Upgrade instructions generation"
    
    local instructions
    instructions=$(get_bash_upgrade_instructions)
    
    if [[ -n "$instructions" ]] && [[ ${#instructions} -gt 100 ]]; then
        pass_test
        echo "    Generated upgrade instructions (${#instructions} chars)"
    else
        fail_test "Failed to generate proper upgrade instructions"
    fi
}

test_ec2_install_script() {
    start_test "EC2 install script generation"
    
    local script
    script=$(get_ec2_bash_install_script)
    
    if [[ -n "$script" ]] && [[ "$script" == *"install_modern_bash"* ]]; then
        pass_test
        echo "    Generated EC2 install script"
    else
        fail_test "Failed to generate EC2 install script"
    fi
}

test_error_messaging() {
    start_test "Error message generation (non-exiting test)"
    
    # Create a temporary test script to avoid exiting this test
    local temp_script="/tmp/bash_version_test_$$"
    cat > "$temp_script" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Mock an old bash version by temporarily changing BASH_VERSION
BASH_VERSION="3.2.57(1)-release"
export BASH_VERSION

source "$PROJECT_ROOT/lib/modules/core/bash_version.sh"
validate_bash_version_with_message "test-script" false 2>&1
EOF
    
    chmod +x "$temp_script"
    local output
    output=$("$temp_script" 2>&1)
    rm -f "$temp_script"
    
    if [[ "$output" == *"ERROR: Bash version requirement not met"* ]] && [[ "$output" == *"Required version: bash 5.3.3"* ]]; then
        pass_test
        echo "    Error message generated correctly"
    else
        fail_test "Error message not generated properly"
        echo "    Output: $output"
    fi
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo -e "${YELLOW}Testing Bash Version Validation Module${NC}"
echo "========================================"

test_version_parsing
test_version_comparison
test_platform_detection
test_convenience_functions
test_upgrade_instructions
test_ec2_install_script
test_error_messaging

# =============================================================================
# SUMMARY
# =============================================================================

echo
echo "========================================"
if [[ $pass_count -eq $test_count ]]; then
    echo -e "${GREEN}ALL TESTS PASSED: $pass_count/$test_count${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED: $pass_count/$test_count passed${NC}"
    exit 1
fi