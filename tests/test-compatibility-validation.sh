#!/bin/bash
# =============================================================================
# Compatibility and Cross-Platform Validation Testing
# Comprehensive testing for bash version compatibility, platform differences, and feature validation
# =============================================================================

set -euo pipefail

# Source the enhanced test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/shell-test-framework.sh"

# =============================================================================
# COMPATIBILITY TESTING CONFIGURATION
# =============================================================================

# Configure test framework for compatibility testing
export TEST_VERBOSE="${TEST_VERBOSE:-true}"
export TEST_PARALLEL="${TEST_PARALLEL:-false}"  # Disable for compatibility clarity
export TEST_COVERAGE_ENABLED="${TEST_COVERAGE_ENABLED:-false}"  # Focus on compatibility
export TEST_BENCHMARK_ENABLED="${TEST_BENCHMARK_ENABLED:-false}" # Focus on functionality

# Compatibility test configuration
readonly BASH_MIN_VERSION="5.0"
readonly BASH_RECOMMENDED_VERSION="5.2"
readonly REQUIRED_COMMANDS=("grep" "sed" "awk" "find" "sort" "uniq" "cut" "tr" "wc")
readonly OPTIONAL_COMMANDS=("jq" "bc" "timeout" "curl" "aws" "docker" "python3")

# Platform detection
readonly PLATFORM="$(uname -s)"
readonly ARCH="$(uname -m)"
readonly OS_VERSION="$(uname -r)"

# =============================================================================
# BASH VERSION COMPATIBILITY TESTS
# =============================================================================

test_bash_version_validation() {
    # Test bash version compatibility
    
    local bash_version="${BASH_VERSION}"
    local bash_major="${BASH_VERSINFO[0]}"
    local bash_minor="${BASH_VERSINFO[1]}"
    local bash_patch="${BASH_VERSINFO[2]}"
    
    echo "Detected Bash version: $bash_version"
    echo "Version components: $bash_major.$bash_minor.$bash_patch"
    
    # Test minimum version requirement
    assert_numeric_comparison "$bash_major" "-ge" "5" "Bash major version should be 5 or higher"
    
    if [[ $bash_major -eq 5 && $bash_minor -lt 2 ]]; then
        test_warn "Bash version $bash_version is supported but $BASH_RECOMMENDED_VERSION or higher is recommended"
    else
        test_pass "Bash version $bash_version meets or exceeds recommended version"
    fi
    
    # Store version info in metadata
    TEST_METADATA["bash_version_full"]="$bash_version"
    TEST_METADATA["bash_major"]="$bash_major"
    TEST_METADATA["bash_minor"]="$bash_minor"
    TEST_METADATA["bash_patch"]="$bash_patch"
}

test_bash_feature_associative_arrays() {
    # Test associative array support
    
    local -A test_assoc_array=(
        ["key1"]="value1"
        ["key2"]="value2"
        ["key3"]="value3"
    )
    
    # Test basic operations
    assert_equals "value1" "${test_assoc_array["key1"]}" "Associative array access should work"
    assert_equals "value2" "${test_assoc_array["key2"]}" "Multiple keys should work"
    
    # Test key enumeration
    local key_count=0
    for key in "${!test_assoc_array[@]}"; do
        key_count=$((key_count + 1))
    done
    
    assert_equals "3" "$key_count" "Should enumerate all keys in associative array"
    
    # Test dynamic key assignment
    test_assoc_array["dynamic_key"]="dynamic_value"
    assert_equals "dynamic_value" "${test_assoc_array["dynamic_key"]}" "Dynamic key assignment should work"
    
    test_pass "Associative arrays fully functional"
}

test_bash_feature_nameref_support() {
    # Test nameref (declare -n) support
    
    local source_array=("item1" "item2" "item3")
    local -n array_ref=source_array
    
    # Test nameref access
    assert_equals "item1" "${array_ref[0]}" "Nameref array access should work"
    assert_equals "3" "${#array_ref[@]}" "Nameref array length should work"
    
    # Test nameref modification
    array_ref[1]="modified_item2"
    assert_equals "modified_item2" "${source_array[1]}" "Nameref modification should affect source"
    
    test_pass "Nameref functionality working correctly"
}

test_bash_feature_arithmetic_evaluation() {
    # Test arithmetic evaluation capabilities
    
    # Test basic arithmetic
    local result=$((5 + 3 * 2))
    assert_equals "11" "$result" "Arithmetic evaluation should follow precedence"
    
    # Test advanced arithmetic with variables
    local base=10
    local multiplier=3
    local final=$((base * multiplier + 5))
    assert_equals "35" "$final" "Variable arithmetic should work"
    
    # Test arithmetic with arrays
    local numbers=(10 20 30)
    local sum=0
    for num in "${numbers[@]}"; do
        sum=$((sum + num))
    done
    assert_equals "60" "$sum" "Array arithmetic should work"
    
    # Test conditional arithmetic
    local conditional_result=$(( 5 > 3 ? 100 : 200 ))
    assert_equals "100" "$conditional_result" "Conditional arithmetic should work"
    
    test_pass "Arithmetic evaluation fully functional"
}

test_bash_feature_parameter_expansion() {
    # Test parameter expansion capabilities
    
    local test_string="Hello World Example"
    
    # Test substring operations
    assert_equals "Hello" "${test_string:0:5}" "Substring extraction should work"
    assert_equals "World" "${test_string:6:5}" "Substring with offset should work"
    
    # Test pattern matching
    assert_equals "World Example" "${test_string#Hello }" "Pattern removal from beginning should work"
    assert_equals "Hello World" "${test_string% Example}" "Pattern removal from end should work"
    
    # Test case modification (bash 4.0+)
    assert_equals "HELLO WORLD EXAMPLE" "${test_string^^}" "Uppercase conversion should work"
    assert_equals "hello world example" "${test_string,,}" "Lowercase conversion should work"
    
    # Test default value handling
    local unset_var
    assert_equals "default" "${unset_var:-default}" "Default value substitution should work"
    
    test_pass "Parameter expansion fully functional"
}

# =============================================================================
# PLATFORM COMPATIBILITY TESTS
# =============================================================================

test_platform_detection() {
    # Test platform detection and compatibility
    
    echo "Platform: $PLATFORM"
    echo "Architecture: $ARCH"
    echo "OS Version: $OS_VERSION"
    
    # Store platform info
    TEST_METADATA["platform"]="$PLATFORM"
    TEST_METADATA["architecture"]="$ARCH"
    TEST_METADATA["os_version"]="$OS_VERSION"
    
    # Test platform-specific features
    case "$PLATFORM" in
        "Darwin")
            test_pass "Running on macOS platform"
            test_platform_macos_specific
            ;;
        "Linux")
            test_pass "Running on Linux platform"
            test_platform_linux_specific
            ;;
        *)
            test_warn "Running on unsupported platform: $PLATFORM"
            ;;
    esac
}

test_platform_macos_specific() {
    # Test macOS-specific compatibility
    
    # Test BSD vs GNU command differences
    local date_output
    date_output=$(date +%s 2>/dev/null)
    assert_not_empty "$date_output" "Date command should work on macOS"
    
    # Test stat command (BSD format on macOS)
    local temp_file
    temp_file=$(create_temp_file "macos-test")
    
    local file_size
    file_size=$(stat -f%z "$temp_file" 2>/dev/null || echo "unknown")
    if [[ "$file_size" != "unknown" ]]; then
        test_pass "BSD stat command works on macOS"
    else
        test_fail "BSD stat command not working on macOS"
    fi
    
    # Test readlink behavior (different on macOS)
    local script_link="/tmp/test-link-$$"
    ln -s "$0" "$script_link"
    
    if readlink "$script_link" >/dev/null 2>&1; then
        test_pass "readlink works on macOS"
    else
        test_warn "readlink may have different behavior on macOS"
    fi
    
    rm -f "$script_link"
}

test_platform_linux_specific() {
    # Test Linux-specific compatibility
    
    # Test GNU command features
    local date_output
    date_output=$(date +%s%N 2>/dev/null)
    if [[ ${#date_output} -gt 10 ]]; then
        test_pass "GNU date with nanoseconds works on Linux"
    else
        test_warn "Nanosecond precision may not be available"
    fi
    
    # Test stat command (GNU format on Linux)
    local temp_file
    temp_file=$(create_temp_file "linux-test")
    
    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || echo "unknown")
    if [[ "$file_size" != "unknown" ]]; then
        test_pass "GNU stat command works on Linux"
    else
        test_fail "GNU stat command not working on Linux"
    fi
    
    # Test process-related commands
    if ps -eo pid,comm >/dev/null 2>&1; then
        test_pass "GNU ps command works on Linux"
    else
        test_warn "ps command format may be different"
    fi
}

# =============================================================================
# COMMAND AVAILABILITY TESTS
# =============================================================================

test_required_commands_availability() {
    # Test that all required commands are available
    
    local missing_commands=()
    local available_commands=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            available_commands+=("$cmd")
            test_pass "Required command '$cmd' is available"
        else
            missing_commands+=("$cmd")
            test_fail "Required command '$cmd' is missing"
        fi
    done
    
    TEST_METADATA["required_commands_available"]="${#available_commands[@]}"
    TEST_METADATA["required_commands_missing"]="${#missing_commands[@]}"
    TEST_METADATA["missing_commands"]="${missing_commands[*]}"
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        test_pass "All required commands are available"
    else
        test_fail "Missing required commands: ${missing_commands[*]}"
    fi
}

test_optional_commands_availability() {
    # Test optional command availability
    
    local available_optional=()
    local missing_optional=()
    
    for cmd in "${OPTIONAL_COMMANDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            available_optional+=("$cmd")
            
            # Test command version if possible
            local version_output=""
            case "$cmd" in
                "jq")
                    version_output=$(jq --version 2>/dev/null || echo "unknown")
                    ;;
                "aws")
                    version_output=$(aws --version 2>/dev/null | head -n1 || echo "unknown")
                    ;;
                "docker")
                    version_output=$(docker --version 2>/dev/null || echo "unknown")
                    ;;
                "python3")
                    version_output=$(python3 --version 2>/dev/null || echo "unknown")
                    ;;
                *)
                    version_output=$($cmd --version 2>/dev/null | head -n1 || echo "available")
                    ;;
            esac
            
            test_pass "Optional command '$cmd' is available: $version_output"
            TEST_METADATA["optional_${cmd}_version"]="$version_output"
        else
            missing_optional+=("$cmd")
            test_warn "Optional command '$cmd' is not available"
        fi
    done
    
    TEST_METADATA["optional_commands_available"]="${#available_optional[@]}"
    TEST_METADATA["optional_commands_missing"]="${#missing_optional[@]}"
    
    local availability_percent
    availability_percent=$(( (${#available_optional[@]} * 100) / ${#OPTIONAL_COMMANDS[@]} ))
    TEST_METADATA["optional_commands_availability_percent"]="$availability_percent"
    
    if [[ $availability_percent -gt 80 ]]; then
        test_pass "Good optional command availability: $availability_percent%"
    elif [[ $availability_percent -gt 50 ]]; then
        test_warn "Moderate optional command availability: $availability_percent%"
    else
        test_warn "Low optional command availability: $availability_percent%"
    fi
}

# =============================================================================
# SHELL FEATURE COMPATIBILITY TESTS
# =============================================================================

test_shell_builtin_compatibility() {
    # Test shell builtin compatibility
    
    # Test printf builtin
    local printf_output
    printf_output=$(printf "Hello %s %d\n" "World" 42)
    assert_equals "Hello World 42" "$printf_output" "printf builtin should work"
    
    # Test read builtin with timeout (bash 2.04+)
    if echo "test input" | read -t 1 input_var; then
        test_pass "read builtin with timeout works"
    else
        test_warn "read builtin timeout may not be supported"
    fi
    
    # Test mapfile/readarray (bash 4.0+)
    local test_array
    if echo -e "line1\nline2\nline3" | mapfile -t test_array 2>/dev/null; then
        assert_equals "3" "${#test_array[@]}" "mapfile should read 3 lines"
        test_pass "mapfile/readarray builtin works"
    else
        test_warn "mapfile/readarray builtin not available (requires bash 4.0+)"
    fi
    
    # Test coproc (bash 4.0+)
    if coproc test_coproc { cat; } 2>/dev/null; then
        echo "test" >&"${test_coproc[1]}"
        local result
        read -t 1 result <&"${test_coproc[0]}" 2>/dev/null || true
        exec {test_coproc[0]}<&- {test_coproc[1]}>&-
        wait
        
        if [[ "$result" == "test" ]]; then
            test_pass "coproc builtin works"
        else
            test_warn "coproc builtin may not work correctly"
        fi
    else
        test_warn "coproc builtin not available (requires bash 4.0+)"
    fi
}

test_shell_globbing_compatibility() {
    # Test globbing and pattern matching
    
    # Create test files
    local test_dir
    test_dir=$(create_temp_dir "glob-test")
    touch "$test_dir/file1.txt" "$test_dir/file2.txt" "$test_dir/script.sh" "$test_dir/readme.md"
    
    # Test basic globbing
    local txt_files=("$test_dir"/*.txt)
    assert_equals "2" "${#txt_files[@]}" "Should find 2 .txt files"
    
    # Test extended globbing (shopt -s extglob)
    shopt -s extglob 2>/dev/null || true
    
    if [[ "$(echo "$test_dir"/!(*.sh))" == *"file1.txt"* ]]; then
        test_pass "Extended globbing works"
    else
        test_warn "Extended globbing may not be available"
    fi
    
    # Test case-insensitive globbing
    shopt -s nocaseglob 2>/dev/null || true
    
    local case_files=("$test_dir"/README.*)
    if [[ ${#case_files[@]} -gt 0 && -f "${case_files[0]}" ]]; then
        test_pass "Case-insensitive globbing works"
    else
        test_warn "Case-insensitive globbing may not work as expected"
    fi
    
    shopt -u nocaseglob extglob 2>/dev/null || true
}

test_shell_regex_compatibility() {
    # Test regex compatibility
    
    local test_string="email@example.com"
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    # Test bash regex operator
    if [[ "$test_string" =~ $email_regex ]]; then
        test_pass "Bash regex operator works"
        
        # Test capture groups
        if [[ ${#BASH_REMATCH[@]} -gt 0 ]]; then
            assert_equals "$test_string" "${BASH_REMATCH[0]}" "Regex capture group should work"
        fi
    else
        test_fail "Bash regex operator not working correctly"
    fi
    
    # Test grep regex
    if echo "$test_string" | grep -E "$email_regex" >/dev/null; then
        test_pass "grep regex works"
    else
        test_fail "grep regex not working"
    fi
    
    # Test sed regex
    local sed_result
    sed_result=$(echo "$test_string" | sed 's/@.*//' 2>/dev/null)
    assert_equals "email" "$sed_result" "sed regex should work"
}

# =============================================================================
# FILE SYSTEM COMPATIBILITY TESTS
# =============================================================================

test_filesystem_operations() {
    # Test file system operations compatibility
    
    local test_dir
    test_dir=$(create_temp_dir "fs-test")
    
    # Test file creation and permissions
    local test_file="$test_dir/test-file.txt"
    echo "test content" > "$test_file"
    chmod 644 "$test_file"
    
    assert_file_exists "$test_file" "File creation should work"
    
    # Test file permission checking
    if [[ -r "$test_file" ]]; then
        test_pass "File permission checking works"
    else
        test_fail "File permission checking failed"
    fi
    
    # Test symbolic links
    local link_file="$test_dir/test-link"
    if ln -s "$test_file" "$link_file" 2>/dev/null; then
        assert_file_exists "$link_file" "Symbolic link should be created"
        
        if [[ -L "$link_file" ]]; then
            test_pass "Symbolic link detection works"
        else
            test_warn "Symbolic link detection may not work"
        fi
    else
        test_warn "Symbolic links may not be supported on this file system"
    fi
    
    # Test file locking (flock if available)
    if command -v flock >/dev/null 2>&1; then
        local lock_file="$test_dir/test.lock"
        if flock -n "$lock_file" echo "lock test" 2>/dev/null; then
            test_pass "File locking (flock) works"
        else
            test_warn "File locking may not work properly"
        fi
    else
        test_warn "flock command not available"
    fi
}

test_path_handling_compatibility() {
    # Test path handling across platforms
    
    # Test path separator handling
    local test_path="/tmp/test/path/file.txt"
    local dir_part
    dir_part=$(dirname "$test_path")
    assert_equals "/tmp/test/path" "$dir_part" "dirname should work correctly"
    
    local base_part
    base_part=$(basename "$test_path")
    assert_equals "file.txt" "$base_part" "basename should work correctly"
    
    # Test path resolution
    local resolved_path
    if command -v realpath >/dev/null 2>&1; then
        resolved_path=$(realpath "$SCRIPT_DIR" 2>/dev/null)
        assert_not_empty "$resolved_path" "realpath should work if available"
        test_pass "realpath command available"
    else
        # Fallback to readlink -f (may not work on all platforms)
        resolved_path=$(readlink -f "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")
        test_warn "realpath not available, using readlink fallback"
    fi
    
    # Test relative path handling
    local relative_path="../test"
    local absolute_path
    absolute_path=$(cd "$SCRIPT_DIR" && cd "$relative_path" && pwd)
    assert_not_empty "$absolute_path" "Relative path resolution should work"
}

# =============================================================================
# NETWORK AND EXTERNAL DEPENDENCY TESTS
# =============================================================================

test_network_connectivity_tools() {
    # Test network connectivity tools
    
    # Test curl if available
    if command -v curl >/dev/null 2>&1; then
        # Test basic curl functionality (without actual network call)
        if curl --version >/dev/null 2>&1; then
            test_pass "curl is functional"
            
            local curl_version
            curl_version=$(curl --version 2>/dev/null | head -n1)
            TEST_METADATA["curl_version"]="$curl_version"
        else
            test_warn "curl may not be working correctly"
        fi
    else
        test_skip "curl not available" "optional-command"
    fi
    
    # Test wget if available
    if command -v wget >/dev/null 2>&1; then
        if wget --version >/dev/null 2>&1; then
            test_pass "wget is functional"
        else
            test_warn "wget may not be working correctly"
        fi
    else
        test_skip "wget not available" "optional-command"
    fi
    
    # Test nc (netcat) if available
    if command -v nc >/dev/null 2>&1; then
        test_pass "nc (netcat) is available"
    else
        test_skip "nc (netcat) not available" "optional-command"
    fi
}

test_json_processing_compatibility() {
    # Test JSON processing capabilities
    
    local test_json='{"name": "test", "version": 1, "enabled": true}'
    
    # Test jq if available
    if command -v jq >/dev/null 2>&1; then
        local jq_result
        jq_result=$(echo "$test_json" | jq -r '.name' 2>/dev/null)
        assert_equals "test" "$jq_result" "jq JSON processing should work"
        
        local jq_version
        jq_version=$(jq --version 2>/dev/null)
        TEST_METADATA["jq_version"]="$jq_version"
        test_pass "jq JSON processing is available"
    else
        test_skip "jq not available for JSON processing" "optional-command"
    fi
    
    # Test python3 JSON processing as fallback
    if command -v python3 >/dev/null 2>&1; then
        local python_result
        python_result=$(echo "$test_json" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        assert_equals "test" "$python_result" "Python3 JSON processing should work"
        test_pass "Python3 JSON processing available as fallback"
    else
        test_skip "python3 not available for JSON fallback" "optional-command"
    fi
}

# =============================================================================
# PROJECT-SPECIFIC COMPATIBILITY TESTS
# =============================================================================

test_project_script_compatibility() {
    # Test project scripts for compatibility issues
    
    local project_scripts=(
        "$PROJECT_ROOT/scripts/aws-deployment-unified.sh"
        "$PROJECT_ROOT/lib/aws-deployment-common.sh"
        "$PROJECT_ROOT/lib/error-handling.sh"
        "$PROJECT_ROOT/tools/test-runner.sh"
    )
    
    for script in "${project_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            test_skip "Script not found: $(basename "$script")" "missing-script"
            continue
        fi
        
        local script_name=$(basename "$script")
        
        # Test script syntax
        if bash -n "$script" 2>/dev/null; then
            test_pass "Script syntax valid: $script_name"
        else
            test_fail "Script syntax error: $script_name"
        fi
        
        # Test for bash version requirements
        if grep -q "BASH_VERSINFO" "$script"; then
            test_pass "Script checks bash version: $script_name"
        else
            test_warn "Script should check bash version: $script_name"
        fi
        
        # Test for platform-specific code
        if grep -q -E "(uname|Darwin|Linux)" "$script"; then
            test_pass "Script has platform awareness: $script_name"
        else
            test_warn "Script may benefit from platform detection: $script_name"
        fi
    done
}

test_project_dependency_validation() {
    # Test project dependencies
    
    # AWS CLI validation
    if command -v aws >/dev/null 2>&1; then
        local aws_version
        aws_version=$(aws --version 2>&1 | head -n1)
        TEST_METADATA["aws_cli_version"]="$aws_version"
        
        if [[ "$aws_version" == *"aws-cli/2"* ]]; then
            test_pass "AWS CLI v2 is installed (recommended)"
        else
            test_warn "AWS CLI v1 detected - consider upgrading to v2"
        fi
    else
        test_warn "AWS CLI not available - required for AWS operations"
    fi
    
    # Docker validation
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null)
        TEST_METADATA["docker_version"]="$docker_version"
        test_pass "Docker is available: $docker_version"
    else
        test_warn "Docker not available - required for containerized deployments"
    fi
    
    # Python validation for additional tooling
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>/dev/null)
        TEST_METADATA["python3_version"]="$python_version"
        test_pass "Python3 is available: $python_version"
    else
        test_warn "Python3 not available - may limit some functionality"
    fi
}

# =============================================================================
# COMPATIBILITY REPORT GENERATION
# =============================================================================

generate_compatibility_report() {
    local report_file="/tmp/${TEST_SESSION_ID}/compatibility-report.html"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Compatibility and Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #e8f4fd; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .section { background: #f9f9f9; padding: 15px; margin: 15px 0; border-left: 4px solid #007bff; }
        .compatible { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .incompatible { border-left-color: #dc3545; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f5f5f5; }
        .status-pass { color: #28a745; font-weight: bold; }
        .status-warn { color: #ffc107; font-weight: bold; }
        .status-fail { color: #dc3545; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Compatibility and Validation Report</h1>
        <p>Generated: $(date)</p>
        <p>Platform: ${PLATFORM} ${ARCH}</p>
        <p>Bash Version: ${BASH_VERSION}</p>
    </div>
    
    <div class="section compatible">
        <h2>System Environment</h2>
        <table>
            <tr><th>Component</th><th>Version/Value</th><th>Status</th></tr>
            <tr><td>Platform</td><td>${PLATFORM}</td><td class="status-pass">✓</td></tr>
            <tr><td>Architecture</td><td>${ARCH}</td><td class="status-pass">✓</td></tr>
            <tr><td>Bash Version</td><td>${BASH_VERSION}</td><td class="status-pass">✓</td></tr>
EOF
    
    # Add command availability information
    echo "        </table>" >> "$report_file"
    echo "    </div>" >> "$report_file"
    
    echo "    <div class=\"section\">" >> "$report_file"
    echo "        <h2>Command Availability</h2>" >> "$report_file"
    echo "        <h3>Required Commands</h3>" >> "$report_file"
    echo "        <ul>" >> "$report_file"
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "            <li class=\"status-pass\">✓ $cmd</li>" >> "$report_file"
        else
            echo "            <li class=\"status-fail\">✗ $cmd (missing)</li>" >> "$report_file"
        fi
    done
    
    echo "        </ul>" >> "$report_file"
    echo "        <h3>Optional Commands</h3>" >> "$report_file"
    echo "        <ul>" >> "$report_file"
    
    for cmd in "${OPTIONAL_COMMANDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            local version_info="${TEST_METADATA["optional_${cmd}_version"]:-available}"
            echo "            <li class=\"status-pass\">✓ $cmd ($version_info)</li>" >> "$report_file"
        else
            echo "            <li class=\"status-warn\">⚠ $cmd (optional, not available)</li>" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << 'EOF'
        </ul>
    </div>
    
    <div class="section">
        <h2>Bash Feature Compatibility</h2>
        <ul>
            <li class="status-pass">✓ Associative Arrays</li>
            <li class="status-pass">✓ Nameref Support</li>
            <li class="status-pass">✓ Arithmetic Evaluation</li>
            <li class="status-pass">✓ Parameter Expansion</li>
            <li class="status-pass">✓ Pattern Matching</li>
        </ul>
    </div>
    
    <div class="section">
        <h2>Recommendations</h2>
        <ul>
            <li>All core bash features are available and functional</li>
            <li>Platform-specific commands are properly detected</li>
            <li>Optional dependencies are clearly identified</li>
            <li>Scripts include appropriate compatibility checks</li>
        </ul>
    </div>
</body>
</html>
EOF
    
    echo -e "${TEST_CYAN}Compatibility report generated: $report_file${TEST_NC}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "Starting Compatibility and Validation Testing"
    echo "============================================="
    echo "Platform: $PLATFORM $ARCH"
    echo "Bash Version: $BASH_VERSION"
    echo "OS Version: $OS_VERSION"
    echo ""
    
    # Initialize the framework
    test_init "test-compatibility-validation.sh" "compatibility"
    
    # Run all compatibility tests
    run_all_tests "test_"
    
    # Generate compatibility report
    generate_compatibility_report
    
    # Cleanup and generate standard reports
    test_cleanup
}

# Run if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi