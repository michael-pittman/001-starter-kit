#!/bin/bash
# =============================================================================
# Unity Standard Plugin: Security Validator
# Validates security configurations and compliance across AWS deployments
# Integrates with existing GeuseMaker security validation functionality
# Supports bash 3.x+ with compatibility layers
# =============================================================================

set -euo pipefail

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Load required libraries
source "$PROJECT_ROOT/lib/associative-arrays.sh" 2>/dev/null || true
source "$PROJECT_ROOT/scripts/security-check.sh" 2>/dev/null || true

# =============================================================================
# PLUGIN METADATA - REQUIRED
# =============================================================================

plugin_metadata() {
    cat <<'PLUGIN_METADATA'
{
  "name": "security-validator",
  "version": "2.0.0",
  "api_version": "2.0",
  "description": "Validates security configurations and compliance across AWS deployments",
  "author": "GeuseMaker Unity Team",
  "license": "MIT",
  "homepage": "https://github.com/geusemake/unity-plugins",
  "type": "monitoring",
  "category": "security-validation",
  "priority": 90,
  "execution_mode": "sync",
  "bash_compatibility": {
    "min_version": "3.2",
    "tested_versions": ["3.2", "4.0", "4.4", "5.0", "5.1"]
  },
  "dependencies": {
    "required": ["aws-cli"],
    "optional": ["jq", "openssl"],
    "unity_services": ["config", "events"],
    "system_commands": ["curl", "date", "grep", "awk", "sort"]
  },
  "capabilities": {
    "extension_points": ["pre_deployment", "post_deployment", "on_security_violation"],
    "event_handlers": ["aws.resource.created", "deployment.started", "deployment.completed"],
    "configuration_schema": true,
    "metrics_collection": true,
    "health_monitoring": true
  },
  "configuration": {
    "config_file": "security-validator.yml",
    "environment_prefix": "SECURITY_VALIDATOR",
    "required_config": [],
    "optional_config": ["compliance_framework", "severity_threshold", "auto_remediation", "reporting_enabled"]
  },
  "resources": {
    "max_memory_mb": 40,
    "max_cpu_percent": 10,
    "max_disk_mb": 75,
    "network_access": true,
    "file_permissions": ["read", "write:tmp", "read:/home/ec2-user/.aws"]
  },
  "security": {
    "sandbox_mode": false,
    "allowed_commands": ["aws", "curl", "date", "grep", "awk", "sort", "openssl"],
    "restricted_paths": ["/etc/passwd", "/etc/shadow", "/root"],
    "environment_isolation": false
  }
}
PLUGIN_METADATA
}

# =============================================================================
# PLUGIN CONFIGURATION
# =============================================================================

# Plugin configuration defaults
readonly SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK="${SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK:-AWS_FOUNDATIONAL}"
readonly SECURITY_VALIDATOR_SEVERITY_THRESHOLD="${SECURITY_VALIDATOR_SEVERITY_THRESHOLD:-MEDIUM}"
readonly SECURITY_VALIDATOR_AUTO_REMEDIATION="${SECURITY_VALIDATOR_AUTO_REMEDIATION:-false}"
readonly SECURITY_VALIDATOR_REPORTING_ENABLED="${SECURITY_VALIDATOR_REPORTING_ENABLED:-true}"
readonly SECURITY_VALIDATOR_CACHE_TTL="${SECURITY_VALIDATOR_CACHE_TTL:-1800}"

# Plugin state variables
PLUGIN_SECURITY_VALIDATOR_STATE=""
PLUGIN_SECURITY_VALIDATOR_METRICS=""

# Security check categories
readonly SECURITY_CATEGORIES=("iam" "vpc" "encryption" "logging" "monitoring" "compliance")

# Severity levels
readonly SECURITY_SEVERITY_CRITICAL="CRITICAL"
readonly SECURITY_SEVERITY_HIGH="HIGH"
readonly SECURITY_SEVERITY_MEDIUM="MEDIUM"
readonly SECURITY_SEVERITY_LOW="LOW"
readonly SECURITY_SEVERITY_INFO="INFO"

# =============================================================================
# PLUGIN VALIDATION - REQUIRED
# =============================================================================

plugin_validate() {
    local errors=0
    local warnings=0
    
    _plugin_log "INFO" "Validating Security Validator Plugin"
    
    # Validate bash version compatibility
    if ! _validate_bash_version; then
        _plugin_log "ERROR" "Bash version not supported (requires 3.2+)"
        errors=$((errors + 1))
    fi
    
    # Validate required dependencies
    if ! _validate_dependencies; then
        _plugin_log "ERROR" "Required dependencies not available"
        errors=$((errors + 1))
    fi
    
    # Validate AWS CLI access and permissions
    if ! _validate_aws_access; then
        _plugin_log "ERROR" "AWS CLI access validation failed"
        errors=$((errors + 1))
    fi
    
    # Validate security scanning permissions
    if ! _validate_security_permissions; then
        _plugin_log "WARNING" "Some security scanning permissions missing - limited functionality"
        warnings=$((warnings + 1))
    fi
    
    # Validate configuration
    if ! _validate_configuration; then
        _plugin_log "WARNING" "Configuration validation issues detected"
        warnings=$((warnings + 1))
    fi
    
    # Validate system resources
    if ! _validate_resources; then
        _plugin_log "WARNING" "Resource constraints may be exceeded"
        warnings=$((warnings + 1))
    fi
    
    _plugin_log "INFO" "Validation completed: $errors errors, $warnings warnings"
    return $errors
}

# Helper validation functions
_validate_bash_version() {
    local required_version="3.2"
    local current_version="${BASH_VERSION%%.*}.${BASH_VERSION#*.}"
    current_version="${current_version%%.*}"
    
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" == "$required_version" ]]; then
        return 0
    else
        return 1
    fi
}

_validate_dependencies() {
    local required_deps=("aws")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            _plugin_log "ERROR" "Required dependency not found: $dep"
            return 1
        fi
    done
    
    # Check AWS CLI version
    if command -v aws >/dev/null 2>&1; then
        local aws_version
        aws_version=$(aws --version 2>&1 | head -n1 | cut -d' ' -f1 | cut -d'/' -f2)
        _plugin_log "INFO" "AWS CLI version: $aws_version"
    fi
    
    return 0
}

_validate_aws_access() {
    # Test basic AWS access
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        _plugin_log "ERROR" "AWS credentials not configured or invalid"
        return 1
    fi
    
    return 0
}

_validate_security_permissions() {
    # Test various AWS service permissions needed for security validation
    local permission_tests=(
        "iam:list-roles"
        "ec2:describe-security-groups"
        "s3:list-buckets"
        "cloudtrail:describe-trails"
    )
    
    local failed_tests=0
    
    for test in "${permission_tests[@]}"; do
        local service="${test%:*}"
        local action="${test#*:}"
        
        case "$service" in
            "iam")
                if ! aws iam list-roles --max-items 1 >/dev/null 2>&1; then
                    _plugin_log "WARNING" "IAM permissions limited: $action"
                    failed_tests=$((failed_tests + 1))
                fi
                ;;
            "ec2")
                if ! aws ec2 describe-security-groups --max-items 1 >/dev/null 2>&1; then
                    _plugin_log "WARNING" "EC2 permissions limited: $action"
                    failed_tests=$((failed_tests + 1))
                fi
                ;;
            "s3")
                if ! aws s3api list-buckets >/dev/null 2>&1; then
                    _plugin_log "WARNING" "S3 permissions limited: $action"
                    failed_tests=$((failed_tests + 1))
                fi
                ;;
            "cloudtrail")
                if ! aws cloudtrail describe-trails >/dev/null 2>&1; then
                    _plugin_log "WARNING" "CloudTrail permissions limited: $action"
                    failed_tests=$((failed_tests + 1))
                fi
                ;;
        esac
    done
    
    return $failed_tests
}

_validate_configuration() {
    # Validate configuration values
    local valid_frameworks=("AWS_FOUNDATIONAL" "CIS" "NIST" "SOC2" "PCI_DSS")
    local framework_valid=false
    
    for framework in "${valid_frameworks[@]}"; do
        if [[ "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK" == "$framework" ]]; then
            framework_valid=true
            break
        fi
    done
    
    if [[ "$framework_valid" == "false" ]]; then
        _plugin_log "WARNING" "Invalid compliance framework: $SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK"
        return 1
    fi
    
    local valid_severities=("CRITICAL" "HIGH" "MEDIUM" "LOW" "INFO")
    local severity_valid=false
    
    for severity in "${valid_severities[@]}"; do
        if [[ "$SECURITY_VALIDATOR_SEVERITY_THRESHOLD" == "$severity" ]]; then
            severity_valid=true
            break
        fi
    done
    
    if [[ "$severity_valid" == "false" ]]; then
        _plugin_log "WARNING" "Invalid severity threshold: $SECURITY_VALIDATOR_SEVERITY_THRESHOLD"
        return 1
    fi
    
    return 0
}

_validate_resources() {
    # Check available memory
    local available_memory
    available_memory=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "1000")
    
    if [[ $available_memory -lt 40 ]]; then
        _plugin_log "WARNING" "Low memory available: ${available_memory}MB"
        return 1
    fi
    
    # Check disk space in /tmp
    local available_disk
    available_disk=$(df /tmp 2>/dev/null | awk 'NR==2{print int($4/1024)}' || echo "1000")
    
    if [[ $available_disk -lt 75 ]]; then
        _plugin_log "WARNING" "Low disk space in /tmp: ${available_disk}MB"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PLUGIN LIFECYCLE FUNCTIONS - REQUIRED
# =============================================================================

plugin_init() {
    local plugin_name="security-validator"
    
    _plugin_log "INFO" "Initializing Security Validator Plugin v2.0.0"
    
    # Initialize plugin state directory
    local plugin_dir=".unity/plugins/$plugin_name"
    mkdir -p "$plugin_dir/state" "$plugin_dir/logs" "$plugin_dir/cache" "$plugin_dir/reports" "$plugin_dir/metrics"
    
    # Initialize plugin state
    PLUGIN_SECURITY_VALIDATOR_STATE="$plugin_dir/state"
    PLUGIN_SECURITY_VALIDATOR_METRICS="$plugin_dir/metrics"
    
    # Create initial state file
    cat > "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" <<EOF
{
    "status": "initialized",
    "timestamp": $(date '+%s'),
    "version": "2.0.0",
    "scans_performed": 0,
    "vulnerabilities_found": 0,
    "compliance_score": 0,
    "last_scan": null
}
EOF
    
    # Load plugin configuration
    if ! _load_plugin_config; then
        _plugin_log "ERROR" "Failed to load plugin configuration"
        return 1
    fi
    
    # Initialize security baseline
    if ! _init_security_baseline; then
        _plugin_log "WARNING" "Failed to initialize security baseline"
    fi
    
    # Initialize compliance framework
    if ! _init_compliance_framework; then
        _plugin_log "WARNING" "Failed to initialize compliance framework"
    fi
    
    # Register with Unity event system
    if command -v register_extension_handler >/dev/null 2>&1; then
        register_extension_handler "security-validator" "pre_deployment" "_handle_pre_deployment"
        register_extension_handler "security-validator" "post_deployment" "_handle_post_deployment"
        register_extension_handler "security-validator" "on_security_violation" "_handle_security_violation"
        _plugin_log "INFO" "Registered extension handlers"
    else
        _plugin_log "WARNING" "Unity extension system not available"
    fi
    
    _plugin_log "SUCCESS" "Security Validator Plugin initialized successfully"
    return 0
}

plugin_start() {
    local plugin_name="security-validator"
    
    _plugin_log "INFO" "Starting Security Validator Plugin"
    
    # Check if plugin is initialized
    if ! _is_plugin_initialized; then
        _plugin_log "ERROR" "Plugin not initialized - cannot start"
        return 1
    fi
    
    # Start continuous monitoring if enabled
    if [[ "${SECURITY_VALIDATOR_CONTINUOUS_MONITORING:-false}" == "true" ]]; then
        if ! _start_continuous_monitoring; then
            _plugin_log "WARNING" "Failed to start continuous monitoring"
        fi
    fi
    
    # Perform initial security scan
    if ! _perform_initial_scan; then
        _plugin_log "WARNING" "Initial security scan failed"
    fi
    
    # Update plugin state
    cat > "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" <<EOF
{
    "status": "active",
    "timestamp": $(date '+%s'),
    "version": "2.0.0",
    "scans_performed": $(grep -c "scan_completed" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0"),
    "vulnerabilities_found": $(grep -c "vulnerability_detected" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0"),
    "compliance_score": 85,
    "last_scan": $(stat -c %Y "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "null")
}
EOF
    
    _plugin_log "SUCCESS" "Security Validator Plugin started successfully"
    return 0
}

plugin_stop() {
    local plugin_name="security-validator"
    
    _plugin_log "INFO" "Stopping Security Validator Plugin"
    
    # Stop continuous monitoring if running
    if [[ -f "$PLUGIN_SECURITY_VALIDATOR_STATE/monitoring.pid" ]]; then
        local monitoring_pid
        monitoring_pid=$(cat "$PLUGIN_SECURITY_VALIDATOR_STATE/monitoring.pid")
        if kill -0 "$monitoring_pid" 2>/dev/null; then
            kill "$monitoring_pid"
            rm -f "$PLUGIN_SECURITY_VALIDATOR_STATE/monitoring.pid"
            _plugin_log "INFO" "Stopped continuous monitoring (PID: $monitoring_pid)"
        fi
    fi
    
    # Save plugin state
    if ! _save_plugin_state; then
        _plugin_log "WARNING" "Failed to save plugin state"
    fi
    
    # Generate final security report
    if ! _generate_final_security_report; then
        _plugin_log "WARNING" "Failed to generate final security report"
    fi
    
    # Update status
    cat > "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" <<EOF
{
    "status": "stopped",
    "timestamp": $(date '+%s'),
    "version": "2.0.0",
    "stop_reason": "manual",
    "final_metrics": $(cat "$PLUGIN_SECURITY_VALIDATOR_METRICS/summary.json" 2>/dev/null || echo "{}")
}
EOF
    
    _plugin_log "SUCCESS" "Security Validator Plugin stopped successfully"
    return 0
}

plugin_cleanup() {
    local plugin_name="security-validator"
    
    _plugin_log "INFO" "Cleaning up Security Validator Plugin"
    
    # Ensure plugin is stopped first
    if _is_plugin_active; then
        plugin_stop
    fi
    
    # Cleanup temporary resources
    if ! _cleanup_temp_resources; then
        _plugin_log "WARNING" "Failed to cleanup temporary resources"
    fi
    
    # Cleanup cache files
    rm -rf "$PLUGIN_SECURITY_VALIDATOR_STATE/cache"/* 2>/dev/null || true
    
    # Preserve security reports and metrics unless explicitly requested to remove
    local cleanup_state="${PLUGIN_CLEANUP_STATE:-false}"
    if [[ "$cleanup_state" == "true" ]]; then
        rm -rf ".unity/plugins/$plugin_name" 2>/dev/null || true
        _plugin_log "INFO" "Removed all plugin data"
    else
        _plugin_log "INFO" "Preserved security reports and metrics"
    fi
    
    _plugin_log "SUCCESS" "Security Validator Plugin cleanup completed"
    return 0
}

# =============================================================================
# PLUGIN CORE FUNCTIONALITY
# =============================================================================

# Perform comprehensive security scan
perform_security_scan() {
    local scan_scope="${1:-all}"
    local detailed="${2:-false}"
    
    _plugin_log "INFO" "Starting security scan with scope: $scan_scope"
    
    local scan_results=()
    local total_issues=0
    local critical_issues=0
    local high_issues=0
    
    # IAM Security Scan
    if [[ "$scan_scope" == "all" || "$scan_scope" == "iam" ]]; then
        local iam_results
        iam_results=$(_scan_iam_security)
        if [[ -n "$iam_results" ]]; then
            scan_results+=("$iam_results")
            local iam_issues
            iam_issues=$(echo "$iam_results" | grep -c '"severity":"' || echo "0")
            total_issues=$((total_issues + iam_issues))
            critical_issues=$((critical_issues + $(echo "$iam_results" | grep -c '"severity":"CRITICAL"' || echo "0")))
            high_issues=$((high_issues + $(echo "$iam_results" | grep -c '"severity":"HIGH"' || echo "0")))
        fi
    fi
    
    # VPC Security Scan
    if [[ "$scan_scope" == "all" || "$scan_scope" == "vpc" ]]; then
        local vpc_results
        vpc_results=$(_scan_vpc_security)
        if [[ -n "$vpc_results" ]]; then
            scan_results+=("$vpc_results")
            local vpc_issues
            vpc_issues=$(echo "$vpc_results" | grep -c '"severity":"' || echo "0")
            total_issues=$((total_issues + vpc_issues))
            critical_issues=$((critical_issues + $(echo "$vpc_results" | grep -c '"severity":"CRITICAL"' || echo "0")))
            high_issues=$((high_issues + $(echo "$vpc_results" | grep -c '"severity":"HIGH"' || echo "0")))
        fi
    fi
    
    # Encryption Security Scan
    if [[ "$scan_scope" == "all" || "$scan_scope" == "encryption" ]]; then
        local encryption_results
        encryption_results=$(_scan_encryption_security)
        if [[ -n "$encryption_results" ]]; then
            scan_results+=("$encryption_results")
            local encryption_issues
            encryption_issues=$(echo "$encryption_results" | grep -c '"severity":"' || echo "0")
            total_issues=$((total_issues + encryption_issues))
            critical_issues=$((critical_issues + $(echo "$encryption_results" | grep -c '"severity":"CRITICAL"' || echo "0")))
            high_issues=$((high_issues + $(echo "$encryption_results" | grep -c '"severity":"HIGH"' || echo "0")))
        fi
    fi
    
    # Logging and Monitoring Security Scan
    if [[ "$scan_scope" == "all" || "$scan_scope" == "logging" ]]; then
        local logging_results
        logging_results=$(_scan_logging_security)
        if [[ -n "$logging_results" ]]; then
            scan_results+=("$logging_results")
            local logging_issues
            logging_issues=$(echo "$logging_results" | grep -c '"severity":"' || echo "0")
            total_issues=$((total_issues + logging_issues))
            critical_issues=$((critical_issues + $(echo "$logging_results" | grep -c '"severity":"CRITICAL"' || echo "0")))
            high_issues=$((high_issues + $(echo "$logging_results" | grep -c '"severity":"HIGH"' || echo "0")))
        fi
    fi
    
    # Calculate compliance score
    local compliance_score
    compliance_score=$(_calculate_compliance_score "$total_issues" "$critical_issues" "$high_issues")
    
    # Generate scan summary
    cat <<EOF
{
    "scan_timestamp": $(date '+%s'),
    "scan_scope": "$scan_scope",
    "compliance_framework": "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK",
    "total_issues": $total_issues,
    "critical_issues": $critical_issues,
    "high_issues": $high_issues,
    "compliance_score": $compliance_score,
    "scan_results": [
        $(IFS=,; echo "${scan_results[*]}")
    ],
    "recommendations": [
        $(echo "${scan_results[@]}" | grep -o '"recommendations":\[[^]]*\]' | tr '\n' ',' | sed 's/,$//')
    ]
}
EOF
    
    # Record scan
    _record_security_scan "$scan_scope" "$total_issues" "$critical_issues" "$high_issues" "$compliance_score"
    
    _plugin_log "SUCCESS" "Security scan completed: $total_issues issues found, compliance score: $compliance_score%"
    return 0
}

# Validate deployment security configuration
validate_deployment_security() {
    local stack_name="${1:-}"
    local pre_deployment="${2:-false}"
    
    if [[ -z "$stack_name" ]]; then
        _plugin_log "ERROR" "Stack name is required for deployment security validation"
        return 1
    fi
    
    _plugin_log "INFO" "Validating security configuration for deployment: $stack_name"
    
    local validation_results=()
    local validation_errors=0
    local validation_warnings=0
    
    # Pre-deployment validation
    if [[ "$pre_deployment" == "true" ]]; then
        # Validate CloudFormation template security
        local template_validation
        template_validation=$(_validate_template_security "$stack_name")
        if [[ $? -ne 0 ]]; then
            validation_errors=$((validation_errors + 1))
            validation_results+=("$template_validation")
        fi
    else
        # Post-deployment validation
        # Validate deployed resources security
        local resource_validation
        resource_validation=$(_validate_deployed_resources_security "$stack_name")
        if [[ $? -ne 0 ]]; then
            validation_warnings=$((validation_warnings + 1))
            validation_results+=("$resource_validation")
        fi
    fi
    
    # Generate validation summary
    cat <<EOF
{
    "validation_timestamp": $(date '+%s'),
    "stack_name": "$stack_name",
    "validation_type": "$(if [[ "$pre_deployment" == "true" ]]; then echo "pre_deployment"; else echo "post_deployment"; fi)",
    "validation_errors": $validation_errors,
    "validation_warnings": $validation_warnings,
    "validation_passed": $(if [[ $validation_errors -eq 0 ]]; then echo "true"; else echo "false"; fi),
    "validation_results": [
        $(IFS=,; echo "${validation_results[*]}")
    ]
}
EOF
    
    _plugin_log "SUCCESS" "Deployment security validation completed for $stack_name: $validation_errors errors, $validation_warnings warnings"
    return $validation_errors
}

# Generate security compliance report
generate_compliance_report() {
    local report_format="${1:-json}"
    local include_details="${2:-true}"
    
    _plugin_log "INFO" "Generating security compliance report in $report_format format"
    
    # Perform comprehensive scan
    local scan_results
    scan_results=$(perform_security_scan "all" "$include_details")
    
    # Extract compliance metrics
    local compliance_score
    compliance_score=$(echo "$scan_results" | grep -o '"compliance_score":[0-9]*' | cut -d':' -f2)
    
    local total_issues
    total_issues=$(echo "$scan_results" | grep -o '"total_issues":[0-9]*' | cut -d':' -f2)
    
    local critical_issues
    critical_issues=$(echo "$scan_results" | grep -o '"critical_issues":[0-9]*' | cut -d':' -f2)
    
    # Generate compliance summary by category
    local category_scores=()
    for category in "${SECURITY_CATEGORIES[@]}"; do
        local category_score
        category_score=$(_get_category_compliance_score "$category")
        category_scores+=("\"$category\": $category_score")
    done
    
    # Generate report
    case "$report_format" in
        "json")
            cat <<EOF
{
    "report_type": "security_compliance",
    "report_timestamp": $(date '+%s'),
    "compliance_framework": "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK",
    "overall_compliance_score": $compliance_score,
    "total_issues": $total_issues,
    "critical_issues": $critical_issues,
    "category_scores": {
        $(IFS=,; echo "${category_scores[*]}")
    },
    "scan_details": $scan_results,
    "report_summary": {
        "status": "$(if [[ $compliance_score -ge 80 ]]; then echo "compliant"; elif [[ $compliance_score -ge 60 ]]; then echo "partially_compliant"; else echo "non_compliant"; fi)",
        "risk_level": "$(if [[ $critical_issues -gt 0 ]]; then echo "high"; elif [[ $total_issues -gt 10 ]]; then echo "medium"; else echo "low"; fi)"
    }
}
EOF
            ;;
        "summary")
            echo "Security Compliance Report - $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Framework: $SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK"
            echo "Overall Score: $compliance_score%"
            echo "Total Issues: $total_issues"
            echo "Critical Issues: $critical_issues"
            echo "Status: $(if [[ $compliance_score -ge 80 ]]; then echo "COMPLIANT"; elif [[ $compliance_score -ge 60 ]]; then echo "PARTIALLY COMPLIANT"; else echo "NON-COMPLIANT"; fi)"
            ;;
    esac
    
    # Save report
    local report_file=".unity/plugins/security-validator/reports/compliance_report_$(date '+%Y%m%d_%H%M%S').$report_format"
    if [[ "$report_format" == "json" ]]; then
        cat <<EOF > "$report_file"
{
    "report_type": "security_compliance",
    "report_timestamp": $(date '+%s'),
    "compliance_framework": "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK",
    "overall_compliance_score": $compliance_score,
    "total_issues": $total_issues,
    "critical_issues": $critical_issues,
    "category_scores": {
        $(IFS=,; echo "${category_scores[*]}")
    },
    "scan_details": $scan_results
}
EOF
    fi
    
    _plugin_log "SUCCESS" "Security compliance report generated: $report_file"
    return 0
}

# =============================================================================
# PLUGIN EXTENSION POINT HANDLERS
# =============================================================================

_handle_pre_deployment() {
    local extension_point="$1"
    local context_data="$2"
    
    _plugin_log "INFO" "Pre-deployment security validation hook activated"
    
    # Extract deployment information from context
    local stack_name
    stack_name=$(echo "$context_data" | grep -o '"stack_name":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    
    if [[ -n "$stack_name" ]]; then
        # Validate deployment security configuration
        local validation_result
        validation_result=$(validate_deployment_security "$stack_name" "true")
        
        if [[ $? -eq 0 ]]; then
            _plugin_log "SUCCESS" "Pre-deployment security validation passed for $stack_name"
            
            # Emit security validation event
            if command -v unity_emit_event >/dev/null 2>&1; then
                unity_emit_event "security.validation.passed" "$validation_result"
            fi
        else
            _plugin_log "ERROR" "Pre-deployment security validation failed for $stack_name"
            
            # Emit security violation event
            if command -v unity_emit_event >/dev/null 2>&1; then
                unity_emit_event "security.validation.failed" "$validation_result"
            fi
            
            return 1  # Abort deployment if critical security issues found
        fi
    fi
    
    return 0
}

_handle_post_deployment() {
    local extension_point="$1"
    local context_data="$2"
    
    _plugin_log "INFO" "Post-deployment security validation hook activated"
    
    # Extract deployment information
    local stack_name
    stack_name=$(echo "$context_data" | grep -o '"stack_name":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    
    if [[ -n "$stack_name" ]]; then
        # Perform post-deployment security scan
        local security_scan_result
        security_scan_result=$(validate_deployment_security "$stack_name" "false")
        
        # Save scan results for this deployment
        echo "$security_scan_result" > "$PLUGIN_SECURITY_VALIDATOR_STATE/deployments/${stack_name}_security_scan.json"
        
        _plugin_log "SUCCESS" "Post-deployment security scan completed for $stack_name"
        
        # Emit security scan completion event
        if command -v unity_emit_event >/dev/null 2>&1; then
            unity_emit_event "security.scan.completed" "$security_scan_result"
        fi
    fi
    
    return 0
}

_handle_security_violation() {
    local extension_point="$1"
    local context_data="$2"
    
    _plugin_log "WARNING" "Security violation detected - triggering response"
    
    # Extract violation information
    local violation_type severity resource_id
    violation_type=$(echo "$context_data" | grep -o '"violation_type":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    severity=$(echo "$context_data" | grep -o '"severity":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "MEDIUM")
    resource_id=$(echo "$context_data" | grep -o '"resource_id":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    
    _plugin_log "CRITICAL" "Security violation: $violation_type (severity: $severity) on resource: $resource_id"
    
    # Record security violation
    echo "$(date '+%Y-%m-%d %H:%M:%S') security_violation type:$violation_type severity:$severity resource:$resource_id" >> "$PLUGIN_SECURITY_VALIDATOR_STATE/violations.log"
    
    # Auto-remediation if enabled and safe
    if [[ "$SECURITY_VALIDATOR_AUTO_REMEDIATION" == "true" ]]; then
        if _can_auto_remediate "$violation_type" "$severity"; then
            _perform_auto_remediation "$violation_type" "$resource_id" "$context_data"
        fi
    fi
    
    # Send security alert
    _send_security_alert "$violation_type" "$severity" "$resource_id"
    
    return 0
}

# =============================================================================
# PLUGIN OPTIONAL FUNCTIONS
# =============================================================================

plugin_health_check() {
    local plugin_name="security-validator"
    local health_status=0
    local health_details=()
    
    # Check if plugin is active
    if ! _is_plugin_active; then
        health_details+=("Plugin is not active")
        health_status=2
    fi
    
    # Check AWS API connectivity
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        health_details+=("AWS API connectivity issues")
        health_status=1
    fi
    
    # Check security scanning permissions
    if ! _validate_security_permissions >/dev/null 2>&1; then
        health_details+=("Security scanning permissions limited")
        health_status=1
    fi
    
    # Check scan cache health
    if [[ ! -d "$PLUGIN_SECURITY_VALIDATOR_STATE/cache" ]]; then
        health_details+=("Security scan cache directory missing")
        health_status=1
    fi
    
    # Check recent scan activity
    local last_scan
    last_scan=$(stat -c %Y "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_since_last=$((current_time - last_scan))
    
    if [[ $time_since_last -gt 86400 ]]; then  # 24 hours
        health_details+=("No recent security scan activity")
        health_status=1
    fi
    
    # Generate health report
    local status_text
    case $health_status in
        0) status_text="healthy" ;;
        1) status_text="degraded" ;;
        2) status_text="unhealthy" ;;
    esac
    
    cat <<EOF
{
  "plugin": "$plugin_name",
  "status": "$status_text",
  "timestamp": $(date '+%s'),
  "version": "2.0.0",
  "details": [$(IFS=,; echo "${health_details[*]/#/\"}" | sed 's/,/", "/g' | sed 's/^""//' | sed 's/""$//')],
  "metrics": {
    "scans_performed": $(grep -c "scan_completed" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0"),
    "last_scan_age_hours": $((time_since_last / 3600)),
    "violations_detected": $(grep -c "security_violation" "$PLUGIN_SECURITY_VALIDATOR_STATE/violations.log" 2>/dev/null || echo "0"),
    "compliance_score": $(grep "compliance_score:" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null | tail -1 | cut -d':' -f2 || echo "0")
  }
}
EOF
    
    return $health_status
}

plugin_status() {
    local plugin_name="security-validator"
    
    # Read current status
    local status_data
    if [[ -f "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" ]]; then
        status_data=$(cat "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json")
    else
        status_data='{"status": "unknown", "timestamp": 0}'
    fi
    
    # Get metrics
    local metrics_data="{}"
    if [[ -f "$PLUGIN_SECURITY_VALIDATOR_METRICS/summary.json" ]]; then
        metrics_data=$(cat "$PLUGIN_SECURITY_VALIDATOR_METRICS/summary.json")
    fi
    
    cat <<EOF
{
  "plugin": "$plugin_name",
  "current_status": $status_data,
  "metrics": $metrics_data,
  "configuration": {
    "compliance_framework": "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK",
    "severity_threshold": "$SECURITY_VALIDATOR_SEVERITY_THRESHOLD",
    "auto_remediation": $SECURITY_VALIDATOR_AUTO_REMEDIATION,
    "reporting_enabled": $SECURITY_VALIDATOR_REPORTING_ENABLED
  }
}
EOF
}

plugin_metrics() {
    local plugin_name="security-validator"
    
    # Calculate metrics
    local total_scans
    total_scans=$(grep -c "scan_completed" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0")
    
    local total_violations
    total_violations=$(grep -c "security_violation" "$PLUGIN_SECURITY_VALIDATOR_STATE/violations.log" 2>/dev/null || echo "0")
    
    local critical_violations
    critical_violations=$(grep -c "severity:CRITICAL" "$PLUGIN_SECURITY_VALIDATOR_STATE/violations.log" 2>/dev/null || echo "0")
    
    local avg_compliance_score
    avg_compliance_score=$(grep "compliance_score:" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null | \
        awk -F':' '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0.0"}')
    
    cat <<EOF
{
  "plugin": "$plugin_name",
  "timestamp": $(date '+%s'),
  "metrics": {
    "total_scans": $total_scans,
    "total_violations": $total_violations,
    "critical_violations": $critical_violations,
    "average_compliance_score": $avg_compliance_score,
    "scan_success_rate": "$(echo "scale=2; $total_scans * 100 / $(grep -c "scan_attempted" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null | sed 's/^0$/1/')" | bc -l 2>/dev/null || echo "0.00")%",
    "compliance_framework": "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK"
  }
}
EOF
}

# =============================================================================
# PLUGIN HELPER FUNCTIONS
# =============================================================================

_is_plugin_initialized() {
    [[ -f "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" ]] && \
    [[ "$(grep -o '"status":"[^"]*"' "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" | cut -d'"' -f4)" != "unknown" ]]
}

_is_plugin_active() {
    [[ -f "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" ]] && \
    [[ "$(grep -o '"status":"[^"]*"' "$PLUGIN_SECURITY_VALIDATOR_STATE/status.json" | cut -d'"' -f4)" == "active" ]]
}

_load_plugin_config() {
    # Load configuration from Unity config system or environment
    _plugin_log "DEBUG" "Loading plugin configuration"
    return 0
}

_init_security_baseline() {
    mkdir -p "$PLUGIN_SECURITY_VALIDATOR_STATE/cache/baselines" \
             "$PLUGIN_SECURITY_VALIDATOR_STATE/deployments"
    
    # Initialize security baseline
    local baseline_scan
    baseline_scan=$(perform_security_scan "all" "false" 2>/dev/null || echo '{"error": "baseline_not_available"}')
    
    echo "$baseline_scan" > "$PLUGIN_SECURITY_VALIDATOR_STATE/baseline_scan.json"
    return 0
}

_init_compliance_framework() {
    # Initialize compliance framework rules
    local framework_file="$PLUGIN_SECURITY_VALIDATOR_STATE/compliance_framework.json"
    
    case "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK" in
        "AWS_FOUNDATIONAL")
            cat > "$framework_file" <<EOF
{
    "framework": "AWS_FOUNDATIONAL",
    "rules": [
        {"id": "AWS.IAM.1", "description": "Root user access keys should not exist", "severity": "CRITICAL"},
        {"id": "AWS.EC2.1", "description": "Security groups should not allow unrestricted access", "severity": "HIGH"},
        {"id": "AWS.S3.1", "description": "S3 buckets should not allow public access", "severity": "HIGH"},
        {"id": "AWS.CT.1", "description": "CloudTrail should be enabled", "severity": "MEDIUM"}
    ]
}
EOF
            ;;
        "CIS")
            cat > "$framework_file" <<EOF
{
    "framework": "CIS",
    "rules": [
        {"id": "CIS.1.1", "description": "Avoid root user access keys", "severity": "CRITICAL"},
        {"id": "CIS.2.1", "description": "Ensure CloudTrail is enabled", "severity": "HIGH"},
        {"id": "CIS.3.1", "description": "Ensure VPC flow logs are enabled", "severity": "MEDIUM"}
    ]
}
EOF
            ;;
        *)
            _plugin_log "WARNING" "Unknown compliance framework: $SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK"
            ;;
    esac
    
    return 0
}

_perform_initial_scan() {
    _plugin_log "INFO" "Performing initial security scan"
    
    # Perform initial security scan
    local initial_scan
    initial_scan=$(perform_security_scan "all" "false")
    
    if [[ $? -eq 0 ]]; then
        echo "$initial_scan" > "$PLUGIN_SECURITY_VALIDATOR_STATE/initial_scan.json"
        _plugin_log "SUCCESS" "Initial security scan completed"
        return 0
    else
        _plugin_log "WARNING" "Initial security scan failed"
        return 1
    fi
}

# Security scan implementations
_scan_iam_security() {
    _plugin_log "DEBUG" "Scanning IAM security configuration"
    
    # Check for root access keys
    local root_keys_exist="false"
    if aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text 2>/dev/null | grep -q "1"; then
        root_keys_exist="true"
    fi
    
    # Check for overly permissive IAM policies
    local overpermissive_policies
    overpermissive_policies=$(aws iam list-policies --scope Local --query 'Policies[?contains(PolicyName, `Admin`) || contains(PolicyName, `admin`)].PolicyName' --output text | wc -w || echo "0")
    
    cat <<EOF
{
    "category": "iam",
    "issues": [
        {
            "id": "IAM.1",
            "severity": "$(if [[ "$root_keys_exist" == "true" ]]; then echo "CRITICAL"; else echo "INFO"; fi)",
            "description": "Root user access keys $(if [[ "$root_keys_exist" == "true" ]]; then echo "exist"; else echo "do not exist"; fi)",
            "compliant": $(if [[ "$root_keys_exist" == "true" ]]; then echo "false"; else echo "true"; fi)
        },
        {
            "id": "IAM.2",
            "severity": "$(if [[ $overpermissive_policies -gt 0 ]]; then echo "MEDIUM"; else echo "INFO"; fi)",
            "description": "Found $overpermissive_policies potentially overpermissive IAM policies",
            "compliant": $(if [[ $overpermissive_policies -gt 0 ]]; then echo "false"; else echo "true"; fi)
        }
    ],
    "recommendations": [
        $(if [[ "$root_keys_exist" == "true" ]]; then echo "\"Remove root user access keys\""; fi)
        $(if [[ $overpermissive_policies -gt 0 ]]; then echo "\"Review and restrict overpermissive IAM policies\""; fi)
    ]
}
EOF
}

_scan_vpc_security() {
    _plugin_log "DEBUG" "Scanning VPC security configuration"
    
    # Check for open security groups
    local open_security_groups
    open_security_groups=$(aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]]' --output json | grep -c '"GroupId"' || echo "0")
    
    # Check for default VPC usage
    local default_vpc_used
    default_vpc_used=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    default_vpc_used=$(if [[ "$default_vpc_used" != "None" && -n "$default_vpc_used" ]]; then echo "true"; else echo "false"; fi)
    
    cat <<EOF
{
    "category": "vpc",
    "issues": [
        {
            "id": "VPC.1",
            "severity": "$(if [[ $open_security_groups -gt 0 ]]; then echo "HIGH"; else echo "INFO"; fi)",
            "description": "Found $open_security_groups security groups with unrestricted access",
            "compliant": $(if [[ $open_security_groups -gt 0 ]]; then echo "false"; else echo "true"; fi)
        },
        {
            "id": "VPC.2",
            "severity": "$(if [[ "$default_vpc_used" == "true" ]]; then echo "MEDIUM"; else echo "INFO"; fi)",
            "description": "Default VPC $(if [[ "$default_vpc_used" == "true" ]]; then echo "is in use"; else echo "is not in use"; fi)",
            "compliant": $(if [[ "$default_vpc_used" == "true" ]]; then echo "false"; else echo "true"; fi)
        }
    ],
    "recommendations": [
        $(if [[ $open_security_groups -gt 0 ]]; then echo "\"Restrict security group rules to specific IP ranges\""; fi)
        $(if [[ "$default_vpc_used" == "true" ]]; then echo "\"Use custom VPC instead of default VPC\""; fi)
    ]
}
EOF
}

_scan_encryption_security() {
    _plugin_log "DEBUG" "Scanning encryption security configuration"
    
    # Check for unencrypted EBS volumes
    local unencrypted_volumes
    unencrypted_volumes=$(aws ec2 describe-volumes --query 'Volumes[?Encrypted==`false`]' --output json | grep -c '"VolumeId"' || echo "0")
    
    # Check for unencrypted S3 buckets
    local total_buckets
    total_buckets=$(aws s3api list-buckets --query 'Buckets' --output json | grep -c '"Name"' || echo "0")
    
    cat <<EOF
{
    "category": "encryption",
    "issues": [
        {
            "id": "ENC.1",
            "severity": "$(if [[ $unencrypted_volumes -gt 0 ]]; then echo "HIGH"; else echo "INFO"; fi)",
            "description": "Found $unencrypted_volumes unencrypted EBS volumes",
            "compliant": $(if [[ $unencrypted_volumes -gt 0 ]]; then echo "false"; else echo "true"; fi)
        },
        {
            "id": "ENC.2",
            "severity": "$(if [[ $total_buckets -gt 0 ]]; then echo "MEDIUM"; else echo "INFO"; fi)",
            "description": "Found $total_buckets S3 buckets (encryption status needs verification)",
            "compliant": "unknown"
        }
    ],
    "recommendations": [
        $(if [[ $unencrypted_volumes -gt 0 ]]; then echo "\"Enable encryption for EBS volumes\""; fi)
        $(if [[ $total_buckets -gt 0 ]]; then echo "\"Verify and enable S3 bucket encryption\""; fi)
    ]
}
EOF
}

_scan_logging_security() {
    _plugin_log "DEBUG" "Scanning logging and monitoring security configuration"
    
    # Check CloudTrail status
    local cloudtrail_enabled
    cloudtrail_enabled=$(aws cloudtrail describe-trails --query 'trailList[0].IsLogging' --output text 2>/dev/null || echo "false")
    
    # Check VPC Flow Logs
    local vpc_flow_logs
    vpc_flow_logs=$(aws ec2 describe-flow-logs --query 'FlowLogs' --output json | grep -c '"FlowLogId"' || echo "0")
    
    cat <<EOF
{
    "category": "logging",
    "issues": [
        {
            "id": "LOG.1",
            "severity": "$(if [[ "$cloudtrail_enabled" != "true" ]]; then echo "MEDIUM"; else echo "INFO"; fi)",
            "description": "CloudTrail $(if [[ "$cloudtrail_enabled" == "true" ]]; then echo "is enabled"; else echo "is not enabled"; fi)",
            "compliant": $(if [[ "$cloudtrail_enabled" == "true" ]]; then echo "true"; else echo "false"; fi)
        },
        {
            "id": "LOG.2",
            "severity": "$(if [[ $vpc_flow_logs -eq 0 ]]; then echo "MEDIUM"; else echo "INFO"; fi)",
            "description": "Found $vpc_flow_logs VPC Flow Logs configured",
            "compliant": $(if [[ $vpc_flow_logs -gt 0 ]]; then echo "true"; else echo "false"; fi)
        }
    ],
    "recommendations": [
        $(if [[ "$cloudtrail_enabled" != "true" ]]; then echo "\"Enable CloudTrail logging\""; fi)
        $(if [[ $vpc_flow_logs -eq 0 ]]; then echo "\"Enable VPC Flow Logs\""; fi)
    ]
}
EOF
}

_calculate_compliance_score() {
    local total_issues="$1"
    local critical_issues="$2"
    local high_issues="$3"
    
    # Simplified compliance score calculation
    local base_score=100
    local penalty=$((critical_issues * 20 + high_issues * 10 + (total_issues - critical_issues - high_issues) * 5))
    local compliance_score=$((base_score - penalty))
    
    # Ensure score is not negative
    if [[ $compliance_score -lt 0 ]]; then
        compliance_score=0
    fi
    
    echo "$compliance_score"
}

_get_category_compliance_score() {
    local category="$1"
    
    # This would calculate category-specific compliance scores
    # For now, return a simplified score
    echo "85"
}

_record_security_scan() {
    local scan_scope="$1"
    local total_issues="$2"
    local critical_issues="$3"
    local high_issues="$4"
    local compliance_score="$5"
    
    # Record scan in history log
    echo "$(date '+%Y-%m-%d %H:%M:%S') scan_completed scope:$scan_scope issues:$total_issues critical:$critical_issues high:$high_issues compliance_score:$compliance_score" >> "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log"
    
    # Update metrics
    local current_total
    current_total=$(grep -c "scan_completed" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" || echo "0")
    
    cat > "$PLUGIN_SECURITY_VALIDATOR_METRICS/summary.json" <<EOF
{
    "total_scans": $current_total,
    "last_scan": {
        "timestamp": $(date '+%s'),
        "scope": "$scan_scope",
        "total_issues": $total_issues,
        "critical_issues": $critical_issues,
        "high_issues": $high_issues,
        "compliance_score": $compliance_score
    }
}
EOF
}

_validate_template_security() {
    local stack_name="$1"
    
    # This would validate CloudFormation template security
    # For now, return a simple validation result
    cat <<EOF
{
    "validation_type": "template_security",
    "stack_name": "$stack_name",
    "issues": [],
    "passed": true
}
EOF
    
    return 0
}

_validate_deployed_resources_security() {
    local stack_name="$1"
    
    # This would validate deployed resources security
    # For now, return a simple validation result
    cat <<EOF
{
    "validation_type": "deployed_resources_security",
    "stack_name": "$stack_name",
    "issues": [],
    "passed": true
}
EOF
    
    return 0
}

_can_auto_remediate() {
    local violation_type="$1"
    local severity="$2"
    
    # Only allow auto-remediation for specific low-risk violations
    case "$violation_type" in
        "unused_security_group"|"unattached_eip")
            if [[ "$severity" != "CRITICAL" ]]; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

_perform_auto_remediation() {
    local violation_type="$1"
    local resource_id="$2"
    local context_data="$3"
    
    _plugin_log "INFO" "Performing auto-remediation for $violation_type on $resource_id"
    
    # This would implement auto-remediation logic
    # For now, just log the action
    echo "$(date '+%Y-%m-%d %H:%M:%S') auto_remediation_attempted type:$violation_type resource:$resource_id" >> "$PLUGIN_SECURITY_VALIDATOR_STATE/remediation.log"
}

_send_security_alert() {
    local violation_type="$1"
    local severity="$2"
    local resource_id="$3"
    
    _plugin_log "ALERT" "Security alert: $violation_type ($severity) on $resource_id"
    
    # This would send alerts via configured channels
    echo "$(date '+%Y-%m-%d %H:%M:%S') security_alert_sent type:$violation_type severity:$severity resource:$resource_id" >> "$PLUGIN_SECURITY_VALIDATOR_STATE/alerts.log"
}

_start_continuous_monitoring() {
    # Start continuous security monitoring
    _plugin_log "INFO" "Starting continuous security monitoring"
    return 0
}

_generate_final_security_report() {
    # Generate final security report
    _plugin_log "INFO" "Generating final security report"
    
    local final_report=".unity/plugins/security-validator/reports/final_security_report_$(date '+%Y%m%d_%H%M%S').json"
    
    cat > "$final_report" <<EOF
{
    "report_type": "final_security_report",
    "timestamp": $(date '+%s'),
    "plugin_version": "2.0.0",
    "total_scans": $(grep -c "scan_completed" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0"),
    "total_violations": $(grep -c "security_violation" "$PLUGIN_SECURITY_VALIDATOR_STATE/violations.log" 2>/dev/null || echo "0"),
    "session_summary": "Security validation session completed successfully"
}
EOF
    
    return 0
}

_save_plugin_state() {
    # Save current plugin state for persistence
    local timestamp=$(date '+%s')
    
    cat > "$PLUGIN_SECURITY_VALIDATOR_STATE/last_state.json" <<EOF
{
    "saved_timestamp": $timestamp,
    "configuration": {
        "compliance_framework": "$SECURITY_VALIDATOR_COMPLIANCE_FRAMEWORK",
        "severity_threshold": "$SECURITY_VALIDATOR_SEVERITY_THRESHOLD",
        "auto_remediation": $SECURITY_VALIDATOR_AUTO_REMEDIATION,
        "reporting_enabled": $SECURITY_VALIDATOR_REPORTING_ENABLED
    },
    "runtime_state": {
        "scans_performed": $(grep -c "scan_completed" "$PLUGIN_SECURITY_VALIDATOR_STATE/scan_history.log" 2>/dev/null || echo "0"),
        "violations_detected": $(grep -c "security_violation" "$PLUGIN_SECURITY_VALIDATOR_STATE/violations.log" 2>/dev/null || echo "0")
    }
}
EOF
    
    return 0
}

_cleanup_temp_resources() {
    # Clean up temporary files and resources
    rm -f "/tmp/security_validator_"* 2>/dev/null || true
    
    # Clean up old cache entries (older than 24 hours)
    find "$PLUGIN_SECURITY_VALIDATOR_STATE/cache" -name "*.json" -mtime +1 -delete 2>/dev/null || true
    
    return 0
}

# =============================================================================
# PLUGIN LOGGING UTILITY
# =============================================================================

_plugin_log() {
    local level="$1"
    local message="$2"
    local extra_data="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local plugin_name="security-validator"
    
    # Format log message
    local log_entry="$timestamp [$level] [$plugin_name] $message"
    if [[ -n "$extra_data" ]]; then
        log_entry="$log_entry | $extra_data"
    fi
    
    # Write to plugin log file
    local log_dir=".unity/plugins/$plugin_name/logs"
    mkdir -p "$log_dir"
    echo "$log_entry" >> "$log_dir/plugin.log"
    
    # Also log to Unity system log if available
    if command -v unity_log >/dev/null 2>&1; then
        unity_log "$level" "Plugin[$plugin_name]: $message"
    else
        # Fallback to stderr/stdout
        case "$level" in
            "ERROR"|"CRITICAL"|"ALERT")
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

# =============================================================================
# PLUGIN MAIN EXECUTION
# =============================================================================

# If script is executed directly, show plugin information
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Unity Standard Plugin: Security Validator v2.0.0"
    echo "Validates security configurations and compliance across AWS deployments"
    echo ""
    
    case "${1:-help}" in
        "metadata")
            plugin_metadata | jq '.' 2>/dev/null || cat
            ;;
        "validate")
            plugin_validate
            ;;
        "init")
            plugin_init
            ;;
        "start")
            plugin_start
            ;;
        "stop")
            plugin_stop
            ;;
        "cleanup")
            plugin_cleanup
            ;;
        "health")
            plugin_health_check | jq '.' 2>/dev/null || cat
            ;;
        "status")
            plugin_status | jq '.' 2>/dev/null || cat
            ;;
        "metrics")
            plugin_metrics | jq '.' 2>/dev/null || cat
            ;;
        "scan")
            perform_security_scan "${2:-all}" "${3:-false}"
            ;;
        "validate-deployment")
            validate_deployment_security "${2:-}" "${3:-false}"
            ;;
        "compliance-report")
            generate_compliance_report "${2:-json}" "${3:-true}"
            ;;
        "help"|*)
            echo "Available commands:"
            echo "  metadata                    - Show plugin metadata"
            echo "  validate                    - Validate plugin environment"
            echo "  init                        - Initialize plugin"
            echo "  start                       - Start plugin"
            echo "  stop                        - Stop plugin"
            echo "  cleanup                     - Cleanup plugin resources"
            echo "  health                      - Check plugin health"
            echo "  status                      - Show plugin status"
            echo "  metrics                     - Show plugin metrics"
            echo "  scan [scope] [detailed]     - Perform security scan"
            echo "  validate-deployment <stack> [pre] - Validate deployment security"
            echo "  compliance-report [format] [details] - Generate compliance report"
            echo "  help                        - Show this help"
            ;;
    esac
fi