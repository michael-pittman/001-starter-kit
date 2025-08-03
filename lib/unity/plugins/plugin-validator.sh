#!/bin/bash
# =============================================================================
# Unity Plugin Validator
# Plugin validation, security checking, and compliance verification
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load required libraries
if [[ -f "$PROJECT_ROOT/lib/associative-arrays.sh" ]]; then
    source "$PROJECT_ROOT/lib/associative-arrays.sh"
fi

if [[ -f "$SCRIPT_DIR/plugin-interface.sh" ]]; then
    source "$SCRIPT_DIR/plugin-interface.sh"
fi

# =============================================================================
# PLUGIN VALIDATOR CONSTANTS
# =============================================================================

readonly UNITY_PLUGIN_VALIDATOR_VERSION="1.0.0"
readonly PLUGIN_VALIDATION_TIMEOUT=30
readonly PLUGIN_SECURITY_SCAN_TIMEOUT=60

# Validation levels
readonly VALIDATION_LEVEL_BASIC="basic"
readonly VALIDATION_LEVEL_STANDARD="standard"
readonly VALIDATION_LEVEL_STRICT="strict"
readonly VALIDATION_LEVEL_PARANOID="paranoid"

# Security risk levels
readonly SECURITY_RISK_LOW="low"
readonly SECURITY_RISK_MEDIUM="medium"
readonly SECURITY_RISK_HIGH="high"
readonly SECURITY_RISK_CRITICAL="critical"

# Validation categories
readonly VALIDATION_CATEGORY_SYNTAX="syntax"
readonly VALIDATION_CATEGORY_INTERFACE="interface"
readonly VALIDATION_CATEGORY_METADATA="metadata"
readonly VALIDATION_CATEGORY_DEPENDENCIES="dependencies"
readonly VALIDATION_CATEGORY_SECURITY="security"
readonly VALIDATION_CATEGORY_PERFORMANCE="performance"
readonly VALIDATION_CATEGORY_COMPLIANCE="compliance"

# Security check patterns
SECURITY_DANGEROUS_COMMANDS=(
    "rm -rf /"
    "dd if="
    "mkfs"
    "fdisk"
    "parted"
    "format"
    "shutdown"
    "reboot"
    "halt"
    "init 0"
    "init 6"
    "kill -9"
    "killall"
    "pkill.*-9"
    ":(){ :|:& };:"
    "curl.*|.*sh"
    "wget.*|.*sh"
    "eval.*\\$"
    "exec.*\\$"
    "system("
    "passthru("
    "shell_exec("
)

SECURITY_SUSPICIOUS_PATTERNS=(
    "/etc/passwd"
    "/etc/shadow"
    "/root/"
    "~/.ssh/"
    "id_rsa"
    "id_dsa"
    "authorized_keys"
    "/dev/[rs]d[a-z]"
    "/proc/version"
    "/proc/cpuinfo"
    "base64.*-d"
    "openssl.*dec"
    "gpg.*--decrypt"
    "\\$\\(.*\\)"
    "`.*`"
    "nc -l"
    "netcat -l"
    "socat"
    "python.*-c"
    "perl.*-e"
    "ruby.*-e"
    "php.*-r"
)

SECURITY_NETWORK_PATTERNS=(
    "curl.*--data"
    "wget.*--post"
    "nc.*[0-9]\\+\\.[0-9]"
    "telnet"
    "ssh.*@"
    "scp.*@"
    "rsync.*@"
    "ftp.*@"
    "sftp.*@"
)

# Validation directories and files
readonly PLUGIN_VALIDATION_DIR=".unity/validation"
readonly PLUGIN_VALIDATION_LOG=".unity/logs/plugin-validator.log"
readonly PLUGIN_QUARANTINE_DIR=".unity/quarantine"

# =============================================================================
# PLUGIN VALIDATOR INITIALIZATION
# =============================================================================

# Initialize plugin validator
init_plugin_validator() {
    local verbose="${1:-false}"
    
    # Create required directories
    mkdir -p "$PLUGIN_VALIDATION_DIR" "$PLUGIN_QUARANTINE_DIR" "$(dirname "$PLUGIN_VALIDATION_LOG")"
    
    # Initialize validation state tracking
    if [[ "$USE_COMPAT_MODE" == "true" ]]; then
        kv_clear "plugin_validation_results"
        kv_clear "plugin_security_scores"
        kv_clear "plugin_compliance_status"
    else
        declare -gA plugin_validation_results=()
        declare -gA plugin_security_scores=()
        declare -gA plugin_compliance_status=()
    fi
    
    # Create validation config
    _create_validation_config
    
    if [[ "$verbose" == "true" ]]; then
        _validator_log "SUCCESS" "Plugin validator initialized"
    fi
    
    return 0
}

# Create validation configuration
_create_validation_config() {
    local config_file="$PLUGIN_VALIDATION_DIR/validator.conf"
    
    cat > "$config_file" <<'VALIDATOR_CONFIG'
# Unity Plugin Validator Configuration

# Validation settings
VALIDATION_LEVEL=standard
VALIDATION_TIMEOUT=30
SECURITY_SCAN_ENABLED=true
PERFORMANCE_CHECK_ENABLED=true
COMPLIANCE_CHECK_ENABLED=true

# Security settings
QUARANTINE_SUSPICIOUS_PLUGINS=true
ALLOW_NETWORK_ACCESS=false
ALLOW_FILE_SYSTEM_ACCESS=limited
BLOCK_DANGEROUS_COMMANDS=true
SCAN_FOR_MALWARE_PATTERNS=true

# Performance limits
MAX_MEMORY_MB=100
MAX_CPU_PERCENT=20
MAX_DISK_MB=50
MAX_EXECUTION_TIME=30

# Compliance requirements
REQUIRE_METADATA=true
REQUIRE_DOCUMENTATION=false
REQUIRE_TESTS=false
REQUIRE_LICENSE=false
CHECK_CODE_QUALITY=true

# Reporting
GENERATE_DETAILED_REPORTS=true
LOG_ALL_VALIDATIONS=true
NOTIFY_ON_FAILURES=true
VALIDATOR_CONFIG
}

# =============================================================================
# PLUGIN VALIDATION ENGINE
# =============================================================================

# Validate plugin comprehensively
# Usage: validate_plugin plugin_name plugin_path [validation_level]
validate_plugin() {
    local plugin_name="$1"
    local plugin_path="$2"
    local validation_level="${3:-$VALIDATION_LEVEL_STANDARD}"
    
    _validator_log "INFO" "Starting comprehensive validation for plugin: $plugin_name"
    
    # Initialize validation result
    local validation_result
    validation_result=$(cat <<EOF
{
  "plugin_name": "$plugin_name",
  "plugin_path": "$plugin_path",
  "validation_level": "$validation_level",
  "timestamp": $(date '+%s'),
  "overall_status": "pending",
  "categories": {},
  "security_score": 0,
  "risk_level": "unknown",
  "issues": [],
  "recommendations": []
}
EOF
)
    
    local overall_status="passed"
    local total_issues=0
    local critical_issues=0
    
    # Run validation categories
    local categories=("$VALIDATION_CATEGORY_SYNTAX" "$VALIDATION_CATEGORY_INTERFACE" "$VALIDATION_CATEGORY_METADATA")
    
    # Add additional categories based on validation level
    case "$validation_level" in
        "$VALIDATION_LEVEL_STANDARD"|"$VALIDATION_LEVEL_STRICT"|"$VALIDATION_LEVEL_PARANOID")
            categories+=("$VALIDATION_CATEGORY_DEPENDENCIES" "$VALIDATION_CATEGORY_SECURITY")
            ;;
    esac
    
    case "$validation_level" in
        "$VALIDATION_LEVEL_STRICT"|"$VALIDATION_LEVEL_PARANOID")
            categories+=("$VALIDATION_CATEGORY_PERFORMANCE" "$VALIDATION_CATEGORY_COMPLIANCE")
            ;;
    esac
    
    # Run each validation category
    for category in "${categories[@]}"; do
        local category_result
        category_result=$(_validate_category "$plugin_name" "$plugin_path" "$category" "$validation_level")
        local category_status=$?
        
        # Parse category result
        local category_issues
        category_issues=$(echo "$category_result" | grep -o '"issue_count": [0-9]*' | cut -d':' -f2 | tr -d ' ' || echo "0")
        local category_critical
        category_critical=$(echo "$category_result" | grep -o '"critical_issues": [0-9]*' | cut -d':' -f2 | tr -d ' ' || echo "0")
        
        total_issues=$((total_issues + category_issues))
        critical_issues=$((critical_issues + category_critical))
        
        if [[ $category_status -ne 0 ]]; then
            overall_status="failed"
        fi
        
        _validator_log "DEBUG" "Category $category validation completed: $category_issues issues ($category_critical critical)"
    done
    
    # Calculate security score
    local security_score
    security_score=$(_calculate_security_score "$plugin_path" "$total_issues" "$critical_issues")
    
    # Determine risk level
    local risk_level
    risk_level=$(_determine_risk_level "$security_score" "$critical_issues")
    
    # Update validation result
    validation_result=$(echo "$validation_result" | sed -e "s/\"overall_status\": \"pending\"/\"overall_status\": \"$overall_status\"/" \
                                                         -e "s/\"security_score\": 0/\"security_score\": $security_score/" \
                                                         -e "s/\"risk_level\": \"unknown\"/\"risk_level\": \"$risk_level\"/")
    
    # Store validation result
    aa_set "plugin_validation_results" "$plugin_name" "$validation_result"
    aa_set "plugin_security_scores" "$plugin_name" "$security_score"
    
    # Generate validation report
    _generate_validation_report "$plugin_name" "$validation_result"
    
    # Take action based on risk level
    _handle_validation_result "$plugin_name" "$plugin_path" "$overall_status" "$risk_level"
    
    _validator_log "SUCCESS" "Plugin validation completed: $plugin_name (status: $overall_status, risk: $risk_level, score: $security_score)"
    
    # Return appropriate exit code
    case "$overall_status" in
        "passed") return 0 ;;
        "failed") return 1 ;;
        *) return 2 ;;
    esac
}

# Validate specific category
# Usage: _validate_category plugin_name plugin_path category validation_level
_validate_category() {
    local plugin_name="$1"
    local plugin_path="$2"
    local category="$3"
    local validation_level="$4"
    
    local category_result
    local category_status=0
    
    case "$category" in
        "$VALIDATION_CATEGORY_SYNTAX")
            category_result=$(_validate_syntax "$plugin_path")
            category_status=$?
            ;;
        "$VALIDATION_CATEGORY_INTERFACE")
            category_result=$(_validate_interface "$plugin_path")
            category_status=$?
            ;;
        "$VALIDATION_CATEGORY_METADATA")
            category_result=$(_validate_metadata "$plugin_path")
            category_status=$?
            ;;
        "$VALIDATION_CATEGORY_DEPENDENCIES")
            category_result=$(_validate_dependencies "$plugin_path")
            category_status=$?
            ;;
        "$VALIDATION_CATEGORY_SECURITY")
            category_result=$(_validate_security "$plugin_path" "$validation_level")
            category_status=$?
            ;;
        "$VALIDATION_CATEGORY_PERFORMANCE")
            category_result=$(_validate_performance "$plugin_path")
            category_status=$?
            ;;
        "$VALIDATION_CATEGORY_COMPLIANCE")
            category_result=$(_validate_compliance "$plugin_path")
            category_status=$?
            ;;
        *)
            category_result='{"category": "unknown", "status": "skipped", "issue_count": 0, "critical_issues": 0}'
            ;;
    esac
    
    echo "$category_result"
    return $category_status
}

# =============================================================================
# VALIDATION CATEGORY IMPLEMENTATIONS
# =============================================================================

# Validate plugin syntax
# Usage: _validate_syntax plugin_path
_validate_syntax() {
    local plugin_path="$1"
    local issues=()
    local critical_issues=0
    
    # Check if file exists and is readable
    if [[ ! -r "$plugin_path" ]]; then
        issues+=("File not readable: $plugin_path")
        critical_issues=$((critical_issues + 1))
    fi
    
    # Check bash syntax
    if ! bash -n "$plugin_path" 2>/dev/null; then
        issues+=("Bash syntax errors detected")
        critical_issues=$((critical_issues + 1))
    fi
    
    # Check shebang
    local first_line
    first_line=$(head -n1 "$plugin_path" 2>/dev/null || echo "")
    if [[ ! "$first_line" =~ ^#!/.*/bash ]]; then
        issues+=("Missing or invalid bash shebang")
    fi
    
    # Check for set -euo pipefail
    if ! grep -q "set -euo pipefail" "$plugin_path"; then
        issues+=("Missing 'set -euo pipefail' for error handling")
    fi
    
    # Check for proper function declarations
    local function_count
    function_count=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*(" "$plugin_path" 2>/dev/null || echo "0")
    if [[ $function_count -eq 0 ]]; then
        issues+=("No functions detected in plugin")
    fi
    
    _generate_category_result "$VALIDATION_CATEGORY_SYNTAX" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    if [[ $critical_issues -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Validate plugin interface
# Usage: _validate_interface plugin_path
_validate_interface() {
    local plugin_path="$1"
    local issues=()
    local critical_issues=0
    
    # Source the plugin to check functions
    if ! source "$plugin_path" 2>/dev/null; then
        issues+=("Failed to source plugin file")
        critical_issues=$((critical_issues + 1))
        _generate_category_result "$VALIDATION_CATEGORY_INTERFACE" "failed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 1
    fi
    
    # Check required functions
    for func in "${UNITY_PLUGIN_REQUIRED_FUNCTIONS[@]}"; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            issues+=("Required function missing: $func")
            critical_issues=$((critical_issues + 1))
        fi
    done
    
    # Test plugin_metadata function
    if declare -f plugin_metadata >/dev/null 2>&1; then
        local metadata
        if ! metadata=$(plugin_metadata 2>/dev/null); then
            issues+=("plugin_metadata function failed to execute")
            critical_issues=$((critical_issues + 1))
        else
            # Basic JSON validation
            if [[ ! "$metadata" =~ ^\{.*\}$ ]]; then
                issues+=("plugin_metadata must return valid JSON")
                critical_issues=$((critical_issues + 1))
            fi
        fi
    fi
    
    # Test plugin_validate function
    if declare -f plugin_validate >/dev/null 2>&1; then
        if ! plugin_validate >/dev/null 2>&1; then
            issues+=("plugin_validate function failed")
        fi
    fi
    
    _generate_category_result "$VALIDATION_CATEGORY_INTERFACE" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    if [[ $critical_issues -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Validate plugin metadata
# Usage: _validate_metadata plugin_path
_validate_metadata() {
    local plugin_path="$1"
    local issues=()
    local critical_issues=0
    
    # Source plugin and get metadata
    if ! source "$plugin_path" 2>/dev/null; then
        issues+=("Cannot source plugin to extract metadata")
        critical_issues=$((critical_issues + 1))
        _generate_category_result "$VALIDATION_CATEGORY_METADATA" "failed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 1
    fi
    
    if ! declare -f plugin_metadata >/dev/null 2>&1; then
        issues+=("plugin_metadata function not found")
        critical_issues=$((critical_issues + 1))
        _generate_category_result "$VALIDATION_CATEGORY_METADATA" "failed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 1
    fi
    
    local metadata
    if ! metadata=$(plugin_metadata 2>/dev/null); then
        issues+=("Failed to extract plugin metadata")
        critical_issues=$((critical_issues + 1))
        _generate_category_result "$VALIDATION_CATEGORY_METADATA" "failed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 1
    fi
    
    # Check required metadata fields
    local required_fields=("name" "version" "api_version" "description" "type")
    for field in "${required_fields[@]}"; do
        if [[ ! "$metadata" =~ \"$field\": ]]; then
            issues+=("Required metadata field missing: $field")
            critical_issues=$((critical_issues + 1))
        fi
    done
    
    # Validate API version
    local api_version
    api_version=$(echo "$metadata" | grep -o '"api_version": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    if [[ -n "$api_version" ]]; then
        if ! is_plugin_api_version_supported "$api_version"; then
            issues+=("Unsupported API version: $api_version")
            critical_issues=$((critical_issues + 1))
        fi
    fi
    
    # Validate plugin type
    local plugin_type
    plugin_type=$(echo "$metadata" | grep -o '"type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    local valid_types=("$PLUGIN_TYPE_CORE" "$PLUGIN_TYPE_INFRASTRUCTURE" "$PLUGIN_TYPE_DEPLOYMENT" "$PLUGIN_TYPE_MONITORING" "$PLUGIN_TYPE_OPTIMIZATION" "$PLUGIN_TYPE_INTEGRATION" "$PLUGIN_TYPE_EXTENSION")
    local type_valid=false
    for valid_type in "${valid_types[@]}"; do
        if [[ "$plugin_type" == "$valid_type" ]]; then
            type_valid=true
            break
        fi
    done
    if [[ "$type_valid" == "false" ]]; then
        issues+=("Invalid plugin type: $plugin_type")
    fi
    
    # Check version format (semantic versioning)
    local version
    version=$(echo "$metadata" | grep -o '"version": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    if [[ -n "$version" ]]; then
        if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][^"]*)?$ ]]; then
            issues+=("Invalid version format (not semantic versioning): $version")
        fi
    fi
    
    _generate_category_result "$VALIDATION_CATEGORY_METADATA" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    if [[ $critical_issues -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Validate plugin dependencies
# Usage: _validate_dependencies plugin_path
_validate_dependencies() {
    local plugin_path="$1"
    local issues=()
    local critical_issues=0
    
    # Source plugin and get metadata
    if ! source "$plugin_path" 2>/dev/null; then
        issues+=("Cannot source plugin to check dependencies")
        critical_issues=$((critical_issues + 1))
        _generate_category_result "$VALIDATION_CATEGORY_DEPENDENCIES" "failed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 1
    fi
    
    local metadata
    if ! metadata=$(plugin_metadata 2>/dev/null); then
        issues+=("Cannot extract metadata to check dependencies")
        _generate_category_result "$VALIDATION_CATEGORY_DEPENDENCIES" "skipped" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 0
    fi
    
    # Extract dependencies (simplified - would use proper JSON parser)
    local required_deps
    required_deps=$(echo "$metadata" | grep -o '"required": \[[^]]*\]' | sed 's/"required": \[\([^]]*\)\]/\1/' | tr -d '"' | tr ',' ' ' 2>/dev/null || echo "")
    
    # Check required dependencies
    for dep in $required_deps; do
        if [[ -n "$dep" ]]; then
            if ! command -v "$dep" >/dev/null 2>&1; then
                issues+=("Required dependency not available: $dep")
                critical_issues=$((critical_issues + 1))
            fi
        fi
    done
    
    # Check system commands
    local system_commands
    system_commands=$(echo "$metadata" | grep -o '"system_commands": \[[^]]*\]' | sed 's/"system_commands": \[\([^]]*\)\]/\1/' | tr -d '"' | tr ',' ' ' 2>/dev/null || echo "")
    
    for cmd in $system_commands; do
        if [[ -n "$cmd" ]]; then
            if ! command -v "$cmd" >/dev/null 2>&1; then
                issues+=("Required system command not available: $cmd")
            fi
        fi
    done
    
    # Check Unity service dependencies
    local unity_services
    unity_services=$(echo "$metadata" | grep -o '"unity_services": \[[^]]*\]' | sed 's/"unity_services": \[\([^]]*\)\]/\1/' | tr -d '"' | tr ',' ' ' 2>/dev/null || echo "")
    
    for service in $unity_services; do
        if [[ -n "$service" ]]; then
            # Would check if Unity service is available
            _validator_log "DEBUG" "Unity service dependency: $service"
        fi
    done
    
    _generate_category_result "$VALIDATION_CATEGORY_DEPENDENCIES" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    if [[ $critical_issues -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Validate plugin security
# Usage: _validate_security plugin_path validation_level
_validate_security() {
    local plugin_path="$1"
    local validation_level="$2"
    local issues=()
    local critical_issues=0
    
    _validator_log "INFO" "Running security validation on: $plugin_path"
    
    # Read plugin content for analysis
    local plugin_content
    plugin_content=$(cat "$plugin_path" 2>/dev/null || echo "")
    
    if [[ -z "$plugin_content" ]]; then
        issues+=("Cannot read plugin file for security analysis")
        critical_issues=$((critical_issues + 1))
        _generate_category_result "$VALIDATION_CATEGORY_SECURITY" "failed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
        return 1
    fi
    
    # Check for dangerous commands
    for dangerous_cmd in "${SECURITY_DANGEROUS_COMMANDS[@]}"; do
        if grep -q "$dangerous_cmd" "$plugin_path" 2>/dev/null; then
            issues+=("Dangerous command detected: $dangerous_cmd")
            critical_issues=$((critical_issues + 1))
        fi
    done
    
    # Check for suspicious patterns
    for suspicious_pattern in "${SECURITY_SUSPICIOUS_PATTERNS[@]}"; do
        if grep -q "$suspicious_pattern" "$plugin_path" 2>/dev/null; then
            issues+=("Suspicious pattern detected: $suspicious_pattern")
            case "$validation_level" in
                "$VALIDATION_LEVEL_STRICT"|"$VALIDATION_LEVEL_PARANOID")
                    critical_issues=$((critical_issues + 1))
                    ;;
            esac
        fi
    done
    
    # Check for network access patterns
    for network_pattern in "${SECURITY_NETWORK_PATTERNS[@]}"; do
        if grep -q "$network_pattern" "$plugin_path" 2>/dev/null; then
            issues+=("Network access pattern detected: $network_pattern")
            case "$validation_level" in
                "$VALIDATION_LEVEL_PARANOID")
                    critical_issues=$((critical_issues + 1))
                    ;;
            esac
        fi
    done
    
    # Check file permissions and paths
    if grep -q "/etc/\|/root/\|/boot/\|/sys/\|/proc/" "$plugin_path" 2>/dev/null; then
        issues+=("Access to sensitive system paths detected")
        case "$validation_level" in
            "$VALIDATION_LEVEL_STRICT"|"$VALIDATION_LEVEL_PARANOID")
                critical_issues=$((critical_issues + 1))
                ;;
        esac
    fi
    
    # Check for eval/exec usage
    if grep -q "eval\|exec" "$plugin_path" 2>/dev/null; then
        issues+=("Dynamic code execution (eval/exec) detected")
        case "$validation_level" in
            "$VALIDATION_LEVEL_STRICT"|"$VALIDATION_LEVEL_PARANOID")
                critical_issues=$((critical_issues + 1))
                ;;
        esac
    fi
    
    # Check for base64 decode patterns (potential obfuscation)
    if grep -q "base64.*-d\|openssl.*dec" "$plugin_path" 2>/dev/null; then
        issues+=("Potential code obfuscation detected")
        case "$validation_level" in
            "$VALIDATION_LEVEL_PARANOID")
                critical_issues=$((critical_issues + 1))
                ;;
        esac
    fi
    
    # Check for external downloads
    if grep -q "curl\|wget\|fetch" "$plugin_path" 2>/dev/null; then
        issues+=("External download capability detected")
        case "$validation_level" in
            "$VALIDATION_LEVEL_PARANOID")
                critical_issues=$((critical_issues + 1))
                ;;
        esac
    fi
    
    _generate_category_result "$VALIDATION_CATEGORY_SECURITY" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    if [[ $critical_issues -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Validate plugin performance characteristics
# Usage: _validate_performance plugin_path
_validate_performance() {
    local plugin_path="$1"
    local issues=()
    local critical_issues=0
    
    # Check file size
    local file_size
    file_size=$(stat -f%z "$plugin_path" 2>/dev/null || stat -c%s "$plugin_path" 2>/dev/null || echo "0")
    local max_size=$((1024 * 1024))  # 1MB
    
    if [[ $file_size -gt $max_size ]]; then
        issues+=("Plugin file too large: ${file_size} bytes (max: ${max_size})")
    fi
    
    # Check complexity (number of functions, lines of code)
    local line_count
    line_count=$(wc -l < "$plugin_path" 2>/dev/null || echo "0")
    local max_lines=1000
    
    if [[ $line_count -gt $max_lines ]]; then
        issues+=("Plugin too complex: $line_count lines (max: $max_lines)")
    fi
    
    # Check for potential performance issues
    if grep -q "while true\|for.*in.*\*\|find.*-exec\|grep.*-r" "$plugin_path" 2>/dev/null; then
        issues+=("Potential performance issues detected")
    fi
    
    # Check for memory-intensive operations
    if grep -q "sort.*-k\|awk.*'[^']*'.*[^']*'\|sed.*'[^']*'.*[^']*'" "$plugin_path" 2>/dev/null; then
        issues+=("Memory-intensive operations detected")
    fi
    
    _generate_category_result "$VALIDATION_CATEGORY_PERFORMANCE" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    return 0
}

# Validate plugin compliance
# Usage: _validate_compliance plugin_path
_validate_compliance() {
    local plugin_path="$1"
    local issues=()
    local critical_issues=0
    
    # Check for documentation
    local plugin_dir
    plugin_dir=$(dirname "$plugin_path")
    
    if [[ ! -f "$plugin_dir/README.md" ]] && [[ ! -f "$plugin_dir/README.txt" ]]; then
        issues+=("Plugin documentation (README) not found")
    fi
    
    # Check for license information
    if ! grep -q -i "license\|copyright\|mit\|apache\|gpl" "$plugin_path" 2>/dev/null; then
        if [[ ! -f "$plugin_dir/LICENSE" ]]; then
            issues+=("License information not found")
        fi
    fi
    
    # Check for proper header comments
    local header_lines
    header_lines=$(head -n 10 "$plugin_path" | grep -c "^#" 2>/dev/null || echo "0")
    
    if [[ $header_lines -lt 3 ]]; then
        issues+=("Insufficient header documentation")
    fi
    
    # Check for function documentation
    local total_functions
    total_functions=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*(" "$plugin_path" 2>/dev/null || echo "0")
    local documented_functions
    documented_functions=$(grep -B1 "^[a-zA-Z_][a-zA-Z0-9_]*(" "$plugin_path" | grep -c "^#" 2>/dev/null || echo "0")
    
    if [[ $total_functions -gt 0 ]] && [[ $documented_functions -lt $((total_functions / 2)) ]]; then
        issues+=("Insufficient function documentation")
    fi
    
    _generate_category_result "$VALIDATION_CATEGORY_COMPLIANCE" "passed" "${#issues[@]}" "$critical_issues" "${issues[@]}"
    
    return 0
}

# =============================================================================
# SECURITY SCORING AND RISK ASSESSMENT
# =============================================================================

# Calculate security score
# Usage: _calculate_security_score plugin_path total_issues critical_issues
_calculate_security_score() {
    local plugin_path="$1"
    local total_issues="$2"
    local critical_issues="$3"
    
    local base_score=100
    local score=$((base_score - (total_issues * 5) - (critical_issues * 20)))
    
    # Ensure score is not negative
    if [[ $score -lt 0 ]]; then
        score=0
    fi
    
    echo "$score"
}

# Determine risk level based on score and critical issues
# Usage: _determine_risk_level security_score critical_issues
_determine_risk_level() {
    local security_score="$1"
    local critical_issues="$2"
    
    if [[ $critical_issues -gt 5 ]] || [[ $security_score -lt 20 ]]; then
        echo "$SECURITY_RISK_CRITICAL"
    elif [[ $critical_issues -gt 2 ]] || [[ $security_score -lt 50 ]]; then
        echo "$SECURITY_RISK_HIGH"
    elif [[ $critical_issues -gt 0 ]] || [[ $security_score -lt 70 ]]; then
        echo "$SECURITY_RISK_MEDIUM"
    else
        echo "$SECURITY_RISK_LOW"
    fi
}

# =============================================================================
# VALIDATION RESULT HANDLING
# =============================================================================

# Handle validation result based on risk level
# Usage: _handle_validation_result plugin_name plugin_path status risk_level
_handle_validation_result() {
    local plugin_name="$1"
    local plugin_path="$2"
    local status="$3"
    local risk_level="$4"
    
    case "$risk_level" in
        "$SECURITY_RISK_CRITICAL"|"$SECURITY_RISK_HIGH")
            _quarantine_plugin "$plugin_name" "$plugin_path" "$risk_level"
            ;;
        "$SECURITY_RISK_MEDIUM")
            _validator_log "WARNING" "Medium risk plugin requires manual review: $plugin_name"
            ;;
        "$SECURITY_RISK_LOW")
            _validator_log "INFO" "Low risk plugin approved: $plugin_name"
            ;;
    esac
}

# Quarantine suspicious plugin
# Usage: _quarantine_plugin plugin_name plugin_path risk_level
_quarantine_plugin() {
    local plugin_name="$1"
    local plugin_path="$2"
    local risk_level="$3"
    
    _validator_log "WARNING" "Quarantining plugin due to $risk_level risk: $plugin_name"
    
    # Create quarantine directory for plugin
    local quarantine_dir="$PLUGIN_QUARANTINE_DIR/$plugin_name"
    mkdir -p "$quarantine_dir"
    
    # Copy plugin to quarantine
    cp "$plugin_path" "$quarantine_dir/"
    
    # Create quarantine info file
    cat > "$quarantine_dir/quarantine.info" <<EOF
{
  "plugin_name": "$plugin_name",
  "original_path": "$plugin_path",
  "quarantine_timestamp": $(date '+%s'),
  "risk_level": "$risk_level",
  "reason": "Security validation failed",
  "action_required": "manual_review"
}
EOF
    
    # Mark plugin as quarantined
    aa_set "plugin_compliance_status" "$plugin_name" "quarantined"
    
    _validator_log "WARNING" "Plugin quarantined: $plugin_name -> $quarantine_dir"
}

# =============================================================================
# VALIDATION REPORTING
# =============================================================================

# Generate category result
# Usage: _generate_category_result category status issue_count critical_issues issues...
_generate_category_result() {
    local category="$1"
    local status="$2"
    local issue_count="$3"
    local critical_issues="$4"
    shift 4
    local issues=("$@")
    
    # Build issues array for JSON
    local issues_json="[]"
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json="["
        local first=true
        for issue in "${issues[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                issues_json="$issues_json,"
            fi
            issues_json="$issues_json\"$issue\""
        done
        issues_json="$issues_json]"
    fi
    
    cat <<EOF
{
  "category": "$category",
  "status": "$status",
  "issue_count": $issue_count,
  "critical_issues": $critical_issues,
  "issues": $issues_json
}
EOF
}

# Generate validation report
# Usage: _generate_validation_report plugin_name validation_result
_generate_validation_report() {
    local plugin_name="$1"
    local validation_result="$2"
    
    local report_file="$PLUGIN_VALIDATION_DIR/${plugin_name}_validation_report.json"
    
    echo "$validation_result" > "$report_file"
    
    _validator_log "INFO" "Validation report generated: $report_file"
}

# =============================================================================
# BATCH VALIDATION
# =============================================================================

# Validate all plugins in registry
# Usage: validate_all_plugins [validation_level]
validate_all_plugins() {
    local validation_level="${1:-$VALIDATION_LEVEL_STANDARD}"
    local validated_count=0
    local passed_count=0
    local failed_count=0
    
    _validator_log "INFO" "Starting batch validation with level: $validation_level"
    
    while IFS= read -r plugin_name; do
        if [[ -n "$plugin_name" ]]; then
            local plugin_path
            plugin_path=$(aa_get "plugin_registry" "$plugin_name")
            
            if [[ -n "$plugin_path" ]] && [[ -f "$plugin_path" ]]; then
                validated_count=$((validated_count + 1))
                
                if validate_plugin "$plugin_name" "$plugin_path" "$validation_level"; then
                    passed_count=$((passed_count + 1))
                else
                    failed_count=$((failed_count + 1))
                fi
            fi
        fi
    done < <(aa_keys "plugin_registry")
    
    _validator_log "INFO" "Batch validation completed: $validated_count total, $passed_count passed, $failed_count failed"
    
    return $failed_count
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Validator logging
# Usage: _validator_log level message [extra_data]
_validator_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format log message
    local log_entry="$timestamp [$level] [PluginValidator] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to validator log
    echo "$log_entry" >> "$PLUGIN_VALIDATION_LOG"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "PluginValidator: $message"
    else
        # Fallback to stderr/stdout
        case "$level" in
            "ERROR"|"CRITICAL")
                echo "$log_entry" >&2
                ;;
            "SUCCESS")
                echo "$log_entry"
                ;;
            "INFO"|"WARNING"|"DEBUG")
                if [[ "${UNITY_PLUGIN_VERBOSE:-false}" == "true" ]]; then
                    echo "$log_entry"
                fi
                ;;
        esac
    fi
}

# Get validation status for plugin
# Usage: get_plugin_validation_status plugin_name
get_plugin_validation_status() {
    local plugin_name="$1"
    
    if aa_has_key "plugin_validation_results" "$plugin_name"; then
        aa_get "plugin_validation_results" "$plugin_name"
    else
        echo '{"status": "not_validated", "message": "Plugin not yet validated"}'
        return 1
    fi
}

# Get validator status summary
get_plugin_validator_status() {
    local total_validated
    total_validated=$(aa_size "plugin_validation_results")
    
    local high_risk_count=0
    local quarantined_count=0
    
    if [[ $total_validated -gt 0 ]]; then
        while IFS= read -r plugin_name; do
            if [[ -n "$plugin_name" ]]; then
                local result
                result=$(aa_get "plugin_validation_results" "$plugin_name")
                local risk_level
                risk_level=$(echo "$result" | grep -o '"risk_level": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
                
                case "$risk_level" in
                    "$SECURITY_RISK_HIGH"|"$SECURITY_RISK_CRITICAL")
                        high_risk_count=$((high_risk_count + 1))
                        ;;
                esac
                
                local compliance_status
                compliance_status=$(aa_get "plugin_compliance_status" "$plugin_name" "unknown")
                if [[ "$compliance_status" == "quarantined" ]]; then
                    quarantined_count=$((quarantined_count + 1))
                fi
            fi
        done < <(aa_keys "plugin_validation_results")
    fi
    
    cat <<EOF
{
  "validator_version": "$UNITY_PLUGIN_VALIDATOR_VERSION",
  "total_validated": $total_validated,
  "high_risk_plugins": $high_risk_count,
  "quarantined_plugins": $quarantined_count,
  "validation_dir": "$PLUGIN_VALIDATION_DIR",
  "quarantine_dir": "$PLUGIN_QUARANTINE_DIR",
  "log_file": "$PLUGIN_VALIDATION_LOG"
}
EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all validator functions
export -f init_plugin_validator
export -f validate_plugin
export -f validate_all_plugins
export -f get_plugin_validation_status
export -f get_plugin_validator_status

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize validator when sourced
if [[ -z "${UNITY_PLUGIN_VALIDATOR_INITIALIZED:-}" ]]; then
    init_plugin_validator
    export UNITY_PLUGIN_VALIDATOR_INITIALIZED=true
fi

# If sourced directly, show validator information
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Plugin Validator v$UNITY_PLUGIN_VALIDATOR_VERSION"
    echo "Validation levels: basic, standard, strict, paranoid"
    echo "Security patterns: ${#SECURITY_DANGEROUS_COMMANDS[@]} dangerous commands, ${#SECURITY_SUSPICIOUS_PATTERNS[@]} suspicious patterns"
    echo ""
    echo "Use validate_plugin <name> <path> [level] to validate a plugin"
    echo "Use validate_all_plugins [level] to validate all registered plugins"
fi