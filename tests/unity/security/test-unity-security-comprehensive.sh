#!/bin/bash
# =============================================================================
# Unity Comprehensive Security Compliance Test Suite
# Security validation, vulnerability scanning, and compliance testing for Unity services
# =============================================================================

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source the Unity test framework
source "$PROJECT_ROOT/lib/unity/testing/unity-test-framework.sh"

# =============================================================================
# TEST SUITE INITIALIZATION
# =============================================================================

# Initialize Unity test framework with security focus
unity_test_init "unity-security-comprehensive" "security" "unity-system"

# Security test configuration
declare -A SECURITY_STANDARDS=(
    ["min_security_score"]=80
    ["max_vulnerabilities"]=0
    ["critical_vulnerabilities"]=0
    ["password_complexity"]=12
    ["encryption_required"]=true
    ["audit_logging"]=true
)

declare -A SECURITY_RESULTS=()
declare -A VULNERABILITY_SCAN_RESULTS=()
declare -A COMPLIANCE_RESULTS=()

# =============================================================================
# SECURITY TESTING UTILITIES
# =============================================================================

# Calculate security score based on checks
calculate_security_score() {
    local checks_passed="$1"
    local total_checks="$2"
    local security_score=0
    
    if [[ $total_checks -gt 0 ]]; then
        security_score=$(( (checks_passed * 100) / total_checks ))
    fi
    
    echo "$security_score"
}

# Check for sensitive data exposure
check_sensitive_data_exposure() {
    local file_path="$1"
    local sensitive_patterns=("password" "secret" "token" "api.*key" "private.*key" "credential")
    local exposure_count=0
    
    if [[ -f "$file_path" ]]; then
        for pattern in "${sensitive_patterns[@]}"; do
            if grep -qi "$pattern" "$file_path" 2>/dev/null; then
                ((exposure_count++))
            fi
        done
    fi
    
    echo "$exposure_count"
}

# Validate file permissions
validate_file_permissions() {
    local file_path="$1"
    local max_permissions="$2"  # e.g., 644, 600
    
    if [[ -f "$file_path" ]]; then
        local current_permissions=$(stat -c "%a" "$file_path" 2>/dev/null || stat -f "%Lp" "$file_path" 2>/dev/null || echo "644")
        
        # Convert to numeric for comparison
        if [[ $current_permissions -le $max_permissions ]]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# =============================================================================
# UNITY SERVICE SECURITY TESTS
# =============================================================================

test_unity_aws_service_security() {
    test_start "unity_aws_service_security" "Security validation for Unity AWS service"
    
    local service_file="$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh"
    local security_score=0
    local total_checks=0
    local security_issues=()
    
    # Test 1: Check for AWS credential handling
    ((total_checks++))
    if [[ -f "$service_file" ]]; then
        if grep -q "AWS_SECRET_ACCESS_KEY\|AWS_ACCESS_KEY_ID" "$service_file"; then
            if grep -q "unset\|>/dev/null\|Parameter Store" "$service_file"; then
                ((security_score++))
            else
                security_issues+=("Potential AWS credential exposure")
            fi
        else
            ((security_score++))  # No hardcoded credentials found
        fi
    fi
    
    # Test 2: Check for input validation
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q -E "(validate_|check_|sanitize_)" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("Missing input validation functions")
    fi
    
    # Test 3: Check for error information disclosure
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "2>&1.*log\|>/dev/null 2>&1" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("Potential error information disclosure")
    fi
    
    # Test 4: Check for command injection protection
    ((total_checks++))
    if [[ -f "$service_file" ]]; then
        if ! grep -q -E '\$\([^)]*\$[^)]*\)|\`[^`]*\$[^`]*\`' "$service_file"; then
            ((security_score++))
        else
            security_issues+=("Potential command injection vulnerability")
        fi
    fi
    
    # Test 5: Check for secure temporary file handling
    ((total_checks++))
    if [[ -f "$service_file" ]]; then
        if grep -q "mktemp"; then
            if grep -q "rm.*temp\|cleanup"; then
                ((security_score++))
            else
                security_issues+=("Temporary files may not be cleaned up securely")
            fi
        else
            ((security_score++))  # No temp files used
        fi
    fi
    
    local final_security_score=$(calculate_security_score "$security_score" "$total_checks")
    SECURITY_RESULTS["aws_service_score"]="$final_security_score"
    SECURITY_RESULTS["aws_service_issues"]="${#security_issues[@]}"
    
    # Evaluate security test results
    if [[ $final_security_score -ge ${SECURITY_STANDARDS["min_security_score"]} ]]; then
        test_pass "AWS service security validation passed: ${final_security_score}% (${security_score}/${total_checks} checks)"
    else
        local issues_text=""
        if [[ ${#security_issues[@]} -gt 0 ]]; then
            issues_text=" Issues: $(IFS=', '; echo "${security_issues[*]}")"
        fi
        test_fail "AWS service security validation failed: ${final_security_score}% (${security_score}/${total_checks} checks)$issues_text"
    fi
}

test_unity_docker_service_security() {
    test_start "unity_docker_service_security" "Security validation for Unity Docker service"
    
    local service_file="$PROJECT_ROOT/lib/unity/services/unity-docker-service.sh"
    local security_score=0
    local total_checks=0
    local security_issues=()
    
    # Test 1: Check for privileged container usage
    ((total_checks++))
    if [[ -f "$service_file" ]]; then
        if ! grep -q "privileged.*true\|--privileged" "$service_file"; then
            ((security_score++))
        else
            security_issues+=("Privileged container usage detected")
        fi
    fi
    
    # Test 2: Check for Docker socket mounting
    ((total_checks++))
    if [[ -f "$service_file" ]]; then
        if ! grep -q "/var/run/docker.sock" "$service_file"; then
            ((security_score++))
        else
            security_issues+=("Docker socket mounting detected")
        fi
    fi
    
    # Test 3: Check for network security
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "network.*none\|--net.*none\|network_mode.*none" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No network isolation configuration found")
    fi
    
    # Test 4: Check for user namespace configuration
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "user.*[0-9]\|--user" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No non-root user configuration found")
    fi
    
    # Test 5: Check for resource limits
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "memory.*limit\|cpu.*limit\|--memory\|--cpus" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No resource limits configuration found")
    fi
    
    # Test 6: Check for image verification
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "docker.*trust\|image.*verify\|signature" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No image verification found")
    fi
    
    local final_security_score=$(calculate_security_score "$security_score" "$total_checks")
    SECURITY_RESULTS["docker_service_score"]="$final_security_score"
    SECURITY_RESULTS["docker_service_issues"]="${#security_issues[@]}"
    
    # Evaluate security test results
    if [[ $final_security_score -ge ${SECURITY_STANDARDS["min_security_score"]} ]]; then
        test_pass "Docker service security validation passed: ${final_security_score}% (${security_score}/${total_checks} checks)"
    else
        local issues_text=""
        if [[ ${#security_issues[@]} -gt 0 ]]; then
            issues_text=" Issues: $(IFS=', '; echo "${security_issues[*]}")"
        fi
        test_fail "Docker service security validation failed: ${final_security_score}% (${security_score}/${total_checks} checks)$issues_text"
    fi
}

test_unity_config_service_security() {
    test_start "unity_config_service_security" "Security validation for Unity Config service"
    
    local service_file="$PROJECT_ROOT/lib/unity/services/unity-config-service.sh"
    local security_score=0
    local total_checks=0
    local security_issues=()
    
    # Test 1: Check for configuration encryption
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "encrypt\|cipher\|gpg" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No configuration encryption found")
    fi
    
    # Test 2: Check for sensitive data handling
    ((total_checks++))
    local sensitive_exposure=$(check_sensitive_data_exposure "$service_file")
    if [[ $sensitive_exposure -eq 0 ]]; then
        ((security_score++))
    else
        security_issues+=("$sensitive_exposure potential sensitive data exposures")
    fi
    
    # Test 3: Check for file permission validation
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "chmod\|permission\|stat.*mode" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No file permission validation found")
    fi
    
    # Test 4: Check for backup security
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "backup.*encrypt\|secure.*backup" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No secure backup configuration found")
    fi
    
    # Test 5: Check for audit logging
    ((total_checks++))
    if [[ -f "$service_file" ]] && grep -q "audit.*log\|config.*change.*log" "$service_file"; then
        ((security_score++))
    else
        security_issues+=("No audit logging found")
    fi
    
    local final_security_score=$(calculate_security_score "$security_score" "$total_checks")
    SECURITY_RESULTS["config_service_score"]="$final_security_score"
    SECURITY_RESULTS["config_service_issues"]="${#security_issues[@]}"
    
    # Evaluate security test results
    if [[ $final_security_score -ge ${SECURITY_STANDARDS["min_security_score"]} ]]; then
        test_pass "Config service security validation passed: ${final_security_score}% (${security_score}/${total_checks} checks)"
    else
        local issues_text=""
        if [[ ${#security_issues[@]} -gt 0 ]]; then
            issues_text=" Issues: $(IFS=', '; echo "${security_issues[*]}")"
        fi
        test_fail "Config service security validation failed: ${final_security_score}% (${security_score}/${total_checks} checks)$issues_text"
    fi
}

# =============================================================================
# VULNERABILITY SCANNING TESTS
# =============================================================================

test_shell_script_vulnerability_scan() {
    test_start "shell_script_vulnerability_scan" "Scan Unity shell scripts for vulnerabilities"
    
    local scan_results=()
    local critical_vulns=0
    local high_vulns=0
    local medium_vulns=0
    local low_vulns=0
    
    # Find all Unity shell scripts
    local unity_scripts=()
    if [[ -d "$PROJECT_ROOT/lib/unity" ]]; then
        while IFS= read -r -d '' script; do
            unity_scripts+=("$script")
        done < <(find "$PROJECT_ROOT/lib/unity" -name "*.sh" -type f -print0 2>/dev/null)
    fi
    
    log_info "Scanning ${#unity_scripts[@]} Unity shell scripts for vulnerabilities"
    
    for script in "${unity_scripts[@]}"; do
        local script_name=$(basename "$script")
        local script_vulns=0
        
        # Check for common shell vulnerabilities
        
        # 1. Unquoted variables that could lead to word splitting
        if grep -q '\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]' "$script" 2>/dev/null; then
            ((script_vulns++))
            ((medium_vulns++))
            scan_results+=("$script_name: Potential word splitting vulnerability (unquoted variables)")
        fi
        
        # 2. Use of eval with user input
        if grep -q 'eval.*\$' "$script" 2>/dev/null; then
            ((script_vulns++))
            ((high_vulns++))
            scan_results+=("$script_name: Dangerous use of eval with variables")
        fi
        
        # 3. Temporary file race conditions
        if grep -q '/tmp/[^$]' "$script" 2>/dev/null; then
            if ! grep -q 'mktemp' "$script" 2>/dev/null; then
                ((script_vulns++))
                ((medium_vulns++))
                scan_results+=("$script_name: Potential race condition with temporary files")
            fi
        fi
        
        # 4. Command injection via backticks or $()
        if grep -q '\`.*\$.*\`\|\$([^)]*\$[^)]*)' "$script" 2>/dev/null; then
            ((script_vulns++))
            ((high_vulns++))
            scan_results+=("$script_name: Potential command injection vulnerability")
        fi
        
        # 5. Inadequate error handling
        if ! grep -q 'set -e\|set -euo pipefail' "$script" 2>/dev/null; then
            ((script_vulns++))
            ((low_vulns++))
            scan_results+=("$script_name: Missing strict error handling")
        fi
        
        # 6. Hardcoded credentials or secrets
        local secret_patterns=("password=" "secret=" "token=" "key=" "credential=")
        for pattern in "${secret_patterns[@]}"; do
            if grep -qi "$pattern" "$script" 2>/dev/null; then
                if ! grep -qi "parameter.*store\|vault\|encrypted" "$script" 2>/dev/null; then
                    ((script_vulns++))
                    ((critical_vulns++))
                    scan_results+=("$script_name: Potential hardcoded credential: $pattern")
                fi
            fi
        done
        
        # 7. Insecure file permissions
        if grep -q 'chmod.*777\|chmod.*666' "$script" 2>/dev/null; then
            ((script_vulns++))
            ((medium_vulns++))
            scan_results+=("$script_name: Insecure file permissions (777/666)")
        fi
    done
    
    local total_vulns=$((critical_vulns + high_vulns + medium_vulns + low_vulns))
    
    # Store vulnerability scan results
    VULNERABILITY_SCAN_RESULTS["total_vulnerabilities"]="$total_vulns"
    VULNERABILITY_SCAN_RESULTS["critical_vulnerabilities"]="$critical_vulns"
    VULNERABILITY_SCAN_RESULTS["high_vulnerabilities"]="$high_vulns"
    VULNERABILITY_SCAN_RESULTS["medium_vulnerabilities"]="$medium_vulns"
    VULNERABILITY_SCAN_RESULTS["low_vulnerabilities"]="$low_vulns"
    VULNERABILITY_SCAN_RESULTS["scripts_scanned"]="${#unity_scripts[@]}"
    
    # Evaluate vulnerability scan results
    if [[ $critical_vulns -eq 0 && $high_vulns -eq 0 && $medium_vulns -le 2 ]]; then
        test_pass "Vulnerability scan excellent: $total_vulns total vulnerabilities (Critical: $critical_vulns, High: $high_vulns, Medium: $medium_vulns, Low: $low_vulns)"
    elif [[ $critical_vulns -eq 0 && $high_vulns -le 1 ]]; then
        test_pass "Vulnerability scan good: $total_vulns total vulnerabilities (Critical: $critical_vulns, High: $high_vulns, Medium: $medium_vulns, Low: $low_vulns)"
    elif [[ $critical_vulns -eq 0 ]]; then
        test_warn "Vulnerability scan acceptable: $total_vulns total vulnerabilities (Critical: $critical_vulns, High: $high_vulns, Medium: $medium_vulns, Low: $low_vulns)"
    else
        test_fail "Vulnerability scan failed: $total_vulns total vulnerabilities (Critical: $critical_vulns, High: $high_vulns, Medium: $medium_vulns, Low: $low_vulns)"
    fi
    
    # Log detailed scan results if there are issues
    if [[ ${#scan_results[@]} -gt 0 && $total_vulns -gt 0 ]]; then
        log_info "Detailed vulnerability findings:"
        for result in "${scan_results[@]}"; do
            log_info "  - $result"
        done
    fi
}

test_configuration_security_scan() {
    test_start "configuration_security_scan" "Scan Unity configuration files for security issues"
    
    local config_files=()
    local config_issues=()
    local security_score=0
    local total_checks=0
    
    # Find Unity configuration files
    if [[ -d "$PROJECT_ROOT/config" ]]; then
        while IFS= read -r -d '' config_file; do
            config_files+=("$config_file")
        done < <(find "$PROJECT_ROOT/config" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) -print0 2>/dev/null)
    fi
    
    log_info "Scanning ${#config_files[@]} configuration files for security issues"
    
    for config_file in "${config_files[@]}"; do
        local file_name=$(basename "$config_file")
        
        # Check file permissions
        ((total_checks++))
        if validate_file_permissions "$config_file" 644; then
            ((security_score++))
        else
            config_issues+=("$file_name: Insecure file permissions")
        fi
        
        # Check for sensitive data exposure
        ((total_checks++))
        local sensitive_count=$(check_sensitive_data_exposure "$config_file")
        if [[ $sensitive_count -eq 0 ]]; then
            ((security_score++))
        else
            config_issues+=("$file_name: $sensitive_count potential sensitive data exposures")
        fi
        
        # Check for default/weak passwords
        ((total_checks++))
        if grep -qi "password.*admin\|password.*123\|password.*password" "$config_file" 2>/dev/null; then
            config_issues+=("$file_name: Default or weak password detected")
        else
            ((security_score++))
        fi
        
        # Check for debug/development settings in production configs
        ((total_checks++))
        if echo "$file_name" | grep -q "prod\|production"; then
            if grep -qi "debug.*true\|development.*true" "$config_file" 2>/dev/null; then
                config_issues+=("$file_name: Debug settings enabled in production config")
            else
                ((security_score++))
            fi
        else
            ((security_score++))  # Not a production config
        fi
    done
    
    local config_security_score=$(calculate_security_score "$security_score" "$total_checks")
    SECURITY_RESULTS["config_security_score"]="$config_security_score"
    SECURITY_RESULTS["config_issues"]="${#config_issues[@]}"
    
    # Evaluate configuration security
    if [[ $config_security_score -ge ${SECURITY_STANDARDS["min_security_score"]} ]]; then
        test_pass "Configuration security scan passed: ${config_security_score}% (${security_score}/${total_checks} checks)"
    else
        local issues_text=""
        if [[ ${#config_issues[@]} -gt 0 ]]; then
            issues_text=" Issues: $(IFS=', '; echo "${config_issues[*]}")"
        fi
        test_fail "Configuration security scan failed: ${config_security_score}% (${security_score}/${total_checks} checks)$issues_text"
    fi
}

# =============================================================================
# COMPLIANCE TESTING
# =============================================================================

test_security_compliance_standards() {
    test_start "security_compliance_standards" "Test compliance with security standards"
    
    local compliance_score=0
    local total_standards=0
    local compliance_issues=()
    
    # CIS (Center for Internet Security) Controls compliance
    
    # 1. Inventory and Control of Hardware Assets
    ((total_standards++))
    if [[ -f "$PROJECT_ROOT/config/inventory.yml" ]] || command -v unity_inventory_scan >/dev/null 2>&1; then
        ((compliance_score++))
    else
        compliance_issues+=("Missing hardware asset inventory")
    fi
    
    # 2. Inventory and Control of Software Assets
    ((total_standards++))
    if command -v get_docker_images >/dev/null 2>&1 || command -v unity_software_inventory >/dev/null 2>&1; then
        ((compliance_score++))
    else
        compliance_issues+=("Missing software asset inventory")
    fi
    
    # 3. Continuous Vulnerability Management
    ((total_standards++))
    if [[ ${VULNERABILITY_SCAN_RESULTS["critical_vulnerabilities"]} -eq 0 ]]; then
        ((compliance_score++))
    else
        compliance_issues+=("Critical vulnerabilities found")
    fi
    
    # 4. Controlled Use of Administrative Privileges
    ((total_standards++))
    if grep -q "sudo\|root" "$PROJECT_ROOT/lib/unity/services/"*.sh 2>/dev/null; then
        if grep -q "check.*sudo\|validate.*root" "$PROJECT_ROOT/lib/unity/services/"*.sh 2>/dev/null; then
            ((compliance_score++))
        else
            compliance_issues+=("Administrative privileges not properly controlled")
        fi
    else
        ((compliance_score++))  # No admin privileges used
    fi
    
    # 5. Secure Configuration for Hardware and Software
    ((total_standards++))
    if [[ ${SECURITY_RESULTS["config_security_score"]} -ge 80 ]]; then
        ((compliance_score++))
    else
        compliance_issues+=("Insecure configuration detected")
    fi
    
    # 6. Maintenance, Monitoring, and Analysis of Audit Logs
    ((total_standards++))
    if grep -q "log.*audit\|audit.*log" "$PROJECT_ROOT/lib/unity/services/"*.sh 2>/dev/null; then
        ((compliance_score++))
    else
        compliance_issues+=("Missing audit logging implementation")
    fi
    
    # 7. Email and Web Browser Protections (N/A for this system)
    
    # 8. Malware Defenses
    ((total_standards++))
    if command -v docker >/dev/null 2>&1; then
        if grep -q "image.*scan\|security.*scan" "$PROJECT_ROOT/lib/unity/services/"*.sh 2>/dev/null; then
            ((compliance_score++))
        else
            compliance_issues+=("No malware/vulnerability scanning for container images")
        fi
    else
        ((compliance_score++))  # No containers used
    fi
    
    # 9. Limitation and Control of Network Ports, Protocols, and Services
    ((total_standards++))
    if grep -q "port.*restrict\|firewall\|network.*security" "$PROJECT_ROOT/lib/unity/services/"*.sh 2>/dev/null; then
        ((compliance_score++))
    else
        compliance_issues+=("No network port restrictions found")
    fi
    
    # 10. Data Recovery Capabilities
    ((total_standards++))
    if command -v backup_config >/dev/null 2>&1 || grep -q "backup\|restore" "$PROJECT_ROOT/lib/unity/services/"*.sh 2>/dev/null; then
        ((compliance_score++))
    else
        compliance_issues+=("No data recovery capabilities found")
    fi
    
    local final_compliance_score=$(calculate_security_score "$compliance_score" "$total_standards")
    COMPLIANCE_RESULTS["cis_compliance_score"]="$final_compliance_score"
    COMPLIANCE_RESULTS["cis_compliance_issues"]="${#compliance_issues[@]}"
    
    # Evaluate compliance
    if [[ $final_compliance_score -ge 90 ]]; then
        test_pass "Security compliance excellent: ${final_compliance_score}% CIS Controls compliance (${compliance_score}/${total_standards})"
    elif [[ $final_compliance_score -ge 80 ]]; then
        test_pass "Security compliance good: ${final_compliance_score}% CIS Controls compliance (${compliance_score}/${total_standards})"
    elif [[ $final_compliance_score -ge 70 ]]; then
        test_warn "Security compliance acceptable: ${final_compliance_score}% CIS Controls compliance (${compliance_score}/${total_standards})"
    else
        local issues_text=""
        if [[ ${#compliance_issues[@]} -gt 0 ]]; then
            issues_text=" Issues: $(IFS=', '; echo "${compliance_issues[*]}")"
        fi
        test_fail "Security compliance failed: ${final_compliance_score}% CIS Controls compliance (${compliance_score}/${total_standards})$issues_text"
    fi
}

test_aws_security_compliance() {
    test_start "aws_security_compliance" "Test AWS security best practices compliance"
    
    local aws_compliance_score=0
    local total_aws_checks=0
    local aws_compliance_issues=()
    
    local aws_service_file="$PROJECT_ROOT/lib/unity/services/unity-aws-service.sh"
    
    # AWS Security Best Practices
    
    # 1. Use IAM roles instead of access keys
    ((total_aws_checks++))
    if [[ -f "$aws_service_file" ]]; then
        if grep -q "AssumeRole\|IAM.*role" "$aws_service_file" || ! grep -q "AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY" "$aws_service_file"; then
            ((aws_compliance_score++))
        else
            aws_compliance_issues+=("AWS access keys usage detected - prefer IAM roles")
        fi
    fi
    
    # 2. Use least privilege principle
    ((total_aws_checks++))
    if [[ -f "$aws_service_file" ]] && grep -q "policy.*minimum\|least.*privilege\|minimal.*permissions" "$aws_service_file"; then
        ((aws_compliance_score++))
    else
        aws_compliance_issues+=("No least privilege validation found")
    fi
    
    # 3. Enable AWS CloudTrail
    ((total_aws_checks++))
    if [[ -f "$aws_service_file" ]] && grep -q "cloudtrail\|audit.*trail" "$aws_service_file"; then
        ((aws_compliance_score++))
    else
        aws_compliance_issues+=("No CloudTrail integration found")
    fi
    
    # 4. Use encryption in transit and at rest
    ((total_aws_checks++))
    if [[ -f "$aws_service_file" ]] && grep -q "encrypt\|ssl\|tls" "$aws_service_file"; then
        ((aws_compliance_score++))
    else
        aws_compliance_issues+=("No encryption configuration found")
    fi
    
    # 5. Secure S3 bucket configurations (if used)
    ((total_aws_checks++))
    if [[ -f "$aws_service_file" ]]; then
        if grep -q "s3" "$aws_service_file"; then
            if grep -q "public.*read.*false\|block.*public\|bucket.*encrypt" "$aws_service_file"; then
                ((aws_compliance_score++))
            else
                aws_compliance_issues+=("S3 security configurations not found")
            fi
        else
            ((aws_compliance_score++))  # S3 not used
        fi
    fi
    
    # 6. VPC security groups configuration
    ((total_aws_checks++))
    if [[ -f "$aws_service_file" ]] && grep -q "security.*group\|sg-" "$aws_service_file"; then
        if grep -q "restrict\|specific.*port\|minimal.*access" "$aws_service_file"; then
            ((aws_compliance_score++))
        else
            aws_compliance_issues+=("Security group restrictions not configured")
        fi
    else
        aws_compliance_issues+=("No security group configuration found")
    fi
    
    local aws_final_score=$(calculate_security_score "$aws_compliance_score" "$total_aws_checks")
    COMPLIANCE_RESULTS["aws_compliance_score"]="$aws_final_score"
    COMPLIANCE_RESULTS["aws_compliance_issues"]="${#aws_compliance_issues[@]}"
    
    # Evaluate AWS compliance
    if [[ $aws_final_score -ge ${SECURITY_STANDARDS["min_security_score"]} ]]; then
        test_pass "AWS security compliance passed: ${aws_final_score}% (${aws_compliance_score}/${total_aws_checks} checks)"
    else
        local issues_text=""
        if [[ ${#aws_compliance_issues[@]} -gt 0 ]]; then
            issues_text=" Issues: $(IFS=', '; echo "${aws_compliance_issues[*]}")"
        fi
        test_fail "AWS security compliance failed: ${aws_final_score}% (${aws_compliance_score}/${total_aws_checks} checks)$issues_text"
    fi
}

# =============================================================================
# SECURITY REPORTING
# =============================================================================

generate_security_report() {
    test_start "security_report_generation" "Generate comprehensive security report"
    
    local report_file="$UNITY_TEST_DIR/reports/unity-security-detailed-report.html"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Unity Security Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #dc3545 0%, #6610f2 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
        .section { margin: 30px 0; }
        .section h2 { color: #333; border-bottom: 2px solid #dc3545; padding-bottom: 10px; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0; }
        .metric-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #dc3545; }
        .metric-value { font-size: 2em; font-weight: bold; color: #dc3545; }
        .metric-label { color: #666; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; }
        .excellent { color: #28a745; font-weight: bold; }
        .good { color: #20c997; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .critical { color: #dc3545; font-weight: bold; }
        .vulnerability-high { background: #ffe6e6; border-left: 4px solid #dc3545; }
        .vulnerability-medium { background: #fff3cd; border-left: 4px solid #ffc107; }
        .vulnerability-low { background: #d1ecf1; border-left: 4px solid #17a2b8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 Unity Security Compliance Report</h1>
            <p><strong>Generated:</strong> $(date)</p>
            <p><strong>Security Standards:</strong> CIS Controls, AWS Security Best Practices</p>
        </div>
        
        <div class="section">
            <h2>🛡️ Security Score Overview</h2>
            <div class="metric-grid">
EOF
    
    # Add security scores
    for key in "${!SECURITY_RESULTS[@]}"; do
        local value="${SECURITY_RESULTS[$key]}"
        if [[ "$key" == *"_score" ]]; then
            cat >> "$report_file" << EOF
                <div class="metric-card">
                    <div class="metric-value">$value%</div>
                    <div class="metric-label">${key//_/ }</div>
                </div>
EOF
        fi
    done
    
    cat >> "$report_file" << 'EOF'
            </div>
        </div>
        
        <div class="section">
            <h2>🔍 Vulnerability Scan Results</h2>
            <table>
                <tr><th>Severity</th><th>Count</th><th>Description</th><th>Risk Level</th></tr>
EOF
    
    # Add vulnerability scan results
    if [[ -n "${VULNERABILITY_SCAN_RESULTS["critical_vulnerabilities"]:-}" ]]; then
        local critical="${VULNERABILITY_SCAN_RESULTS["critical_vulnerabilities"]}"
        local high="${VULNERABILITY_SCAN_RESULTS["high_vulnerabilities"]}"
        local medium="${VULNERABILITY_SCAN_RESULTS["medium_vulnerabilities"]}"
        local low="${VULNERABILITY_SCAN_RESULTS["low_vulnerabilities"]}"
        
        cat >> "$report_file" << EOF
                <tr class="vulnerability-high">
                    <td>Critical</td>
                    <td>$critical</td>
                    <td>Immediate security threats requiring urgent attention</td>
                    <td><span class="critical">Critical</span></td>
                </tr>
                <tr class="vulnerability-high">
                    <td>High</td>
                    <td>$high</td>
                    <td>Serious security issues that should be addressed quickly</td>
                    <td><span class="critical">High</span></td>
                </tr>
                <tr class="vulnerability-medium">
                    <td>Medium</td>
                    <td>$medium</td>
                    <td>Moderate security issues for planned remediation</td>
                    <td><span class="warning">Medium</span></td>
                </tr>
                <tr class="vulnerability-low">
                    <td>Low</td>
                    <td>$low</td>
                    <td>Minor security improvements</td>
                    <td><span class="good">Low</span></td>
                </tr>
EOF
    fi
    
    cat >> "$report_file" << 'EOF'
            </table>
        </div>
        
        <div class="section">
            <h2>📋 Compliance Assessment</h2>
            <table>
                <tr><th>Compliance Framework</th><th>Score</th><th>Status</th><th>Issues</th></tr>
EOF
    
    # Add compliance results
    if [[ -n "${COMPLIANCE_RESULTS["cis_compliance_score"]:-}" ]]; then
        local cis_score="${COMPLIANCE_RESULTS["cis_compliance_score"]}"
        local cis_issues="${COMPLIANCE_RESULTS["cis_compliance_issues"]}"
        
        local cis_status_class="excellent"
        local cis_status_text="Excellent"
        if [[ $cis_score -lt 90 ]]; then
            cis_status_class="good"
            cis_status_text="Good"
        fi
        if [[ $cis_score -lt 80 ]]; then
            cis_status_class="warning"
            cis_status_text="Needs Improvement"
        fi
        if [[ $cis_score -lt 70 ]]; then
            cis_status_class="critical"
            cis_status_text="Critical"
        fi
        
        cat >> "$report_file" << EOF
                <tr>
                    <td>CIS Controls</td>
                    <td>${cis_score}%</td>
                    <td><span class="$cis_status_class">$cis_status_text</span></td>
                    <td>$cis_issues</td>
                </tr>
EOF
    fi
    
    if [[ -n "${COMPLIANCE_RESULTS["aws_compliance_score"]:-}" ]]; then
        local aws_score="${COMPLIANCE_RESULTS["aws_compliance_score"]}"
        local aws_issues="${COMPLIANCE_RESULTS["aws_compliance_issues"]}"
        
        local aws_status_class="excellent"
        local aws_status_text="Excellent"
        if [[ $aws_score -lt 90 ]]; then
            aws_status_class="good"
            aws_status_text="Good"
        fi
        if [[ $aws_score -lt 80 ]]; then
            aws_status_class="warning"
            aws_status_text="Needs Improvement"
        fi
        if [[ $aws_score -lt 70 ]]; then
            aws_status_class="critical"
            aws_status_text="Critical"
        fi
        
        cat >> "$report_file" << EOF
                <tr>
                    <td>AWS Security Best Practices</td>
                    <td>${aws_score}%</td>
                    <td><span class="$aws_status_class">$aws_status_text</span></td>
                    <td>$aws_issues</td>
                </tr>
EOF
    fi
    
    cat >> "$report_file" << 'EOF'
            </table>
        </div>
        
        <div class="section">
            <h2>🔧 Security Recommendations</h2>
            <div class="metric-card">
                <h3>Immediate Actions Required</h3>
                <ul>
                    <li>Address all critical and high severity vulnerabilities</li>
                    <li>Implement missing audit logging mechanisms</li>
                    <li>Review and strengthen IAM permission boundaries</li>
                    <li>Enable encryption for all data in transit and at rest</li>
                    <li>Implement automated security scanning in CI/CD pipeline</li>
                </ul>
            </div>
            
            <div class="metric-card">
                <h3>Security Improvements</h3>
                <ul>
                    <li>Implement container image vulnerability scanning</li>
                    <li>Add network segmentation and firewall rules</li>
                    <li>Enhance backup and disaster recovery procedures</li>
                    <li>Implement security monitoring and alerting</li>
                    <li>Regular security awareness training for team members</li>
                </ul>
            </div>
            
            <div class="metric-card">
                <h3>Compliance Enhancements</h3>
                <ul>
                    <li>Implement comprehensive asset inventory management</li>
                    <li>Establish security baseline configurations</li>
                    <li>Deploy automated compliance monitoring</li>
                    <li>Regular penetration testing and security assessments</li>
                    <li>Incident response plan development and testing</li>
                </ul>
            </div>
        </div>
    </div>
</body>
</html>
EOF
    
    test_pass "Security report generated successfully: $report_file"
}

# =============================================================================
# RUN ALL SECURITY TESTS
# =============================================================================

# Unity service security tests
test_unity_aws_service_security
test_unity_docker_service_security
test_unity_config_service_security

# Vulnerability scanning tests
test_shell_script_vulnerability_scan
test_configuration_security_scan

# Compliance testing
test_security_compliance_standards
test_aws_security_compliance

# Generate comprehensive security report
generate_security_report

# Clean up Unity test framework
unity_test_cleanup

echo ""
echo "Unity Comprehensive Security Compliance Tests Completed"
echo "Security validation, vulnerability scanning, and compliance testing completed"
echo "Test Report: $UNITY_TEST_DIR/reports/"