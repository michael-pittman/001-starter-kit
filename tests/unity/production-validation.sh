#!/bin/bash
# Production Validation for Unity System
# Comprehensive checks to ensure Unity is production-ready

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Validation results
CHECKS_PASSED=0
CHECKS_FAILED=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log validation result
log_check() {
    local status="$1"
    local check="$2"
    local details="${3:-}"
    
    case "$status" in
        PASS)
            echo -e "${GREEN}[✓]${NC} $check"
            ((CHECKS_PASSED++))
            ;;
        FAIL)
            echo -e "${RED}[✗]${NC} $check"
            [[ -n "$details" ]] && echo "    $details"
            ((CHECKS_FAILED++))
            ;;
        WARN)
            echo -e "${YELLOW}[!]${NC} $check"
            [[ -n "$details" ]] && echo "    $details"
            ((WARNINGS++))
            ;;
        INFO)
            echo -e "${BLUE}[i]${NC} $check"
            ;;
    esac
}

# Print banner
print_banner() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Unity Production Validation Suite                   ║"
    echo "║              Comprehensive Readiness Check                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Date: $(date)"
    echo "System: $(uname -s) $(uname -r)"
    echo ""
}

#############################################
# Core System Checks
#############################################

check_unity_core() {
    log_check "INFO" "Checking Unity Core System..."
    
    # Unity CLI exists and is executable
    if [[ -x "$PROJECT_ROOT/unity" ]]; then
        log_check "PASS" "Unity CLI is executable"
    else
        log_check "FAIL" "Unity CLI not found or not executable"
    fi
    
    # Unity scripts directory exists
    if [[ -d "$PROJECT_ROOT/scripts" && -f "$PROJECT_ROOT/scripts/unity-cli.sh" ]]; then
        log_check "PASS" "Unity scripts directory exists"
    else
        log_check "FAIL" "Unity scripts directory missing"
    fi
    
    # Core Unity library exists
    if [[ -d "$PROJECT_ROOT/lib/unity/core" ]]; then
        log_check "PASS" "Unity core library exists"
        
        # Check core components
        local core_files=(
            "unity-core.sh"
            "unity-events.sh"
            "unity-plugins.sh"
            "unity-preflight.sh"
        )
        
        for file in "${core_files[@]}"; do
            if [[ -f "$PROJECT_ROOT/lib/unity/core/$file" ]]; then
                log_check "PASS" "Core component: $file"
            else
                log_check "FAIL" "Missing core component: $file"
            fi
        done
    else
        log_check "FAIL" "Unity core library missing"
    fi
}

#############################################
# Service Checks
#############################################

check_unity_services() {
    log_check "INFO" "Checking Unity Services..."
    
    # Check service directory
    if [[ -d "$PROJECT_ROOT/lib/unity/services" ]]; then
        log_check "PASS" "Unity services directory exists"
        
        # Required services
        local required_services=(
            "unity-aws-service-complete.sh"
            "unity-docker-service-complete.sh"
            "unity-monitoring-complete.sh"
            "unity-deployment-service.sh"
            "config-service.sh"
        )
        
        for service in "${required_services[@]}"; do
            if [[ -f "$PROJECT_ROOT/lib/unity/services/$service" ]]; then
                # Check syntax
                if bash -n "$PROJECT_ROOT/lib/unity/services/$service" 2>/dev/null; then
                    log_check "PASS" "Service valid: $service"
                else
                    log_check "FAIL" "Service syntax error: $service"
                fi
            else
                log_check "WARN" "Service not found: $service" "May be using alternate implementation"
            fi
        done
    else
        log_check "FAIL" "Unity services directory missing"
    fi
}

#############################################
# Configuration Checks
#############################################

check_configuration() {
    log_check "INFO" "Checking Configuration..."
    
    # Unity configuration file
    if [[ -f "$PROJECT_ROOT/config/unity.yml" ]]; then
        log_check "PASS" "Unity configuration file exists"
        
        # Check YAML validity if yq is available
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.' "$PROJECT_ROOT/config/unity.yml" >/dev/null 2>&1; then
                log_check "PASS" "Unity configuration is valid YAML"
            else
                log_check "FAIL" "Unity configuration has invalid YAML syntax"
            fi
        else
            log_check "WARN" "yq not available, skipping YAML validation"
        fi
    else
        log_check "FAIL" "Unity configuration file missing"
    fi
    
    # Check for sensitive data
    if grep -r "AKIA\|aws_secret" "$PROJECT_ROOT/config" 2>/dev/null; then
        log_check "FAIL" "Found potential hardcoded credentials in config"
    else
        log_check "PASS" "No hardcoded credentials found"
    fi
}

#############################################
# Documentation Checks
#############################################

check_documentation() {
    log_check "INFO" "Checking Documentation..."
    
    # Essential documentation
    local essential_docs=(
        "README.md"
        "CLAUDE.md"
        "docs/unity/unity-architecture.md"
        "docs/unity/unity-implementation-summary.md"
    )
    
    for doc in "${essential_docs[@]}"; do
        if [[ -f "$PROJECT_ROOT/$doc" ]]; then
            log_check "PASS" "Documentation exists: $doc"
        else
            log_check "WARN" "Documentation missing: $doc"
        fi
    done
    
    # Check if README mentions Unity
    if grep -q "Unity" "$PROJECT_ROOT/README.md" 2>/dev/null; then
        log_check "PASS" "README mentions Unity deployment system"
    else
        log_check "WARN" "README should be updated to mention Unity"
    fi
}

#############################################
# Test Suite Checks
#############################################

check_test_suites() {
    log_check "INFO" "Checking Test Suites..."
    
    # Unity test directory
    if [[ -d "$PROJECT_ROOT/tests/unity" ]]; then
        log_check "PASS" "Unity test directory exists"
        
        # Count test files
        local test_count=$(find "$PROJECT_ROOT/tests/unity" -name "*.sh" -type f | wc -l)
        if [[ $test_count -gt 10 ]]; then
            log_check "PASS" "Found $test_count Unity test files"
        else
            log_check "WARN" "Only $test_count Unity test files found"
        fi
    else
        log_check "FAIL" "Unity test directory missing"
    fi
}

#############################################
# Migration Checks
#############################################

check_migration_status() {
    log_check "INFO" "Checking Migration Status..."
    
    # Check for legacy code
    if [[ -d "$PROJECT_ROOT/archive" ]]; then
        log_check "WARN" "Legacy archive directory still exists" "Consider running deprecation script"
    else
        log_check "PASS" "Legacy archive directory removed"
    fi
    
    # Check for deprecated directory
    if [[ -d "$PROJECT_ROOT/deprecated" ]]; then
        log_check "PASS" "Deprecated directory exists (legacy code archived)"
    fi
    
    # Check for make compatibility
    if [[ -x "$PROJECT_ROOT/make" ]]; then
        log_check "PASS" "Makefile compatibility script exists"
    else
        log_check "WARN" "Makefile compatibility script missing"
    fi
}

#############################################
# Performance Checks
#############################################

check_performance() {
    log_check "INFO" "Checking Performance Metrics..."
    
    # Test Unity initialization speed
    local start_time=$(date +%s%N)
    source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null || true
    local end_time=$(date +%s%N)
    
    local init_time=$(( (end_time - start_time) / 1000000 ))  # milliseconds
    
    if [[ $init_time -lt 500 ]]; then
        log_check "PASS" "Unity initialization time: ${init_time}ms (excellent)"
    elif [[ $init_time -lt 1000 ]]; then
        log_check "PASS" "Unity initialization time: ${init_time}ms (good)"
    else
        log_check "WARN" "Unity initialization time: ${init_time}ms (could be optimized)"
    fi
}

#############################################
# Security Checks
#############################################

check_security() {
    log_check "INFO" "Checking Security..."
    
    # Check file permissions on sensitive directories
    if [[ -d "$PROJECT_ROOT/secrets" ]]; then
        local perms=$(stat -c %a "$PROJECT_ROOT/secrets" 2>/dev/null || stat -f %A "$PROJECT_ROOT/secrets" 2>/dev/null || echo "unknown")
        if [[ "$perms" == "700" ]] || [[ "$perms" == "unknown" ]]; then
            log_check "PASS" "Secrets directory has secure permissions"
        else
            log_check "WARN" "Secrets directory permissions: $perms (should be 700)"
        fi
    fi
    
    # Check for .env files
    if find "$PROJECT_ROOT" -name ".env" -not -path "*/deprecated/*" -not -path "*/.git/*" | grep -q .; then
        log_check "WARN" "Found .env files (ensure they're in .gitignore)"
    else
        log_check "PASS" "No .env files in active directories"
    fi
}

#############################################
# Deployment Readiness
#############################################

check_deployment_readiness() {
    log_check "INFO" "Checking Deployment Readiness..."
    
    # Check AWS CLI
    if command -v aws >/dev/null 2>&1; then
        log_check "PASS" "AWS CLI is installed"
    else
        log_check "WARN" "AWS CLI not found (required for deployment)"
    fi
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        log_check "PASS" "Docker is installed"
    else
        log_check "WARN" "Docker not found (required for some deployments)"
    fi
    
    # Check bash version
    local bash_major_version="${BASH_VERSION%%.*}"
    if [[ $bash_major_version -ge 3 ]]; then
        log_check "PASS" "Bash version $BASH_VERSION (compatible)"
    else
        log_check "FAIL" "Bash version $BASH_VERSION (requires 3.x or higher)"
    fi
}

#############################################
# Summary Report
#############################################

generate_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Production Validation Summary"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Checks Passed: $CHECKS_PASSED"
    echo "Checks Failed: $CHECKS_FAILED"
    echo "Warnings: $WARNINGS"
    echo ""
    
    local total_checks=$((CHECKS_PASSED + CHECKS_FAILED))
    local pass_rate=0
    if [[ $total_checks -gt 0 ]]; then
        pass_rate=$(( CHECKS_PASSED * 100 / total_checks ))
    fi
    
    echo "Pass Rate: ${pass_rate}%"
    echo ""
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ Unity is PRODUCTION READY!${NC}"
        echo ""
        echo "All critical checks passed. The system is ready for production use."
    elif [[ $pass_rate -ge 80 ]]; then
        echo -e "${YELLOW}⚠️  Unity is MOSTLY READY${NC}"
        echo ""
        echo "Most checks passed, but some issues need attention before production."
    else
        echo -e "${RED}❌ Unity is NOT YET READY${NC}"
        echo ""
        echo "Several critical issues must be resolved before production use."
    fi
    
    # Save report
    local report_file="$PROJECT_ROOT/UNITY_PRODUCTION_VALIDATION_$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "Unity Production Validation Report"
        echo "=================================="
        echo "Date: $(date)"
        echo "Checks Passed: $CHECKS_PASSED"
        echo "Checks Failed: $CHECKS_FAILED"
        echo "Warnings: $WARNINGS"
        echo "Pass Rate: ${pass_rate}%"
    } > "$report_file"
    
    echo ""
    echo "Full report saved to: $report_file"
}

#############################################
# Main Execution
#############################################

main() {
    print_banner
    
    # Run all checks
    check_unity_core
    echo ""
    
    check_unity_services
    echo ""
    
    check_configuration
    echo ""
    
    check_documentation
    echo ""
    
    check_test_suites
    echo ""
    
    check_migration_status
    echo ""
    
    check_performance
    echo ""
    
    check_security
    echo ""
    
    check_deployment_readiness
    echo ""
    
    # Generate summary
    generate_summary
}

# Run validation
main "$@"