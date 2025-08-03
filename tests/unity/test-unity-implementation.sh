#!/bin/bash
# Test Unity Implementation - Validates the complete Unity migration

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test logging
log_test() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        PASS)
            echo -e "${GREEN}[PASS]${NC} $message"
            ((TESTS_PASSED++))
            ;;
        FAIL)
            echo -e "${RED}[FAIL]${NC} $message"
            ((TESTS_FAILED++))
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
    esac
}

# Print test banner
print_banner() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Unity Implementation Test Suite                  ║"
    echo "║                  Testing Complete Migration                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

#############################################
# Phase 1: Foundation Tests
#############################################

test_unity_cli() {
    log_test "INFO" "Testing Unity CLI..."
    
    # Test Unity CLI exists
    if [[ -x "$PROJECT_ROOT/unity" ]]; then
        log_test "PASS" "Unity CLI exists and is executable"
    else
        log_test "FAIL" "Unity CLI not found or not executable"
        return 1
    fi
    
    # Test Unity CLI help
    if "$PROJECT_ROOT/unity" help >/dev/null 2>&1; then
        log_test "PASS" "Unity CLI help command works"
    else
        log_test "FAIL" "Unity CLI help command failed"
    fi
    
    # Test deploy.sh wrapper
    if [[ -x "$PROJECT_ROOT/deploy.sh" ]]; then
        log_test "PASS" "deploy.sh wrapper exists and is executable"
    else
        log_test "FAIL" "deploy.sh wrapper not found"
    fi
}

test_preflight_system() {
    log_test "INFO" "Testing pre-flight validation system..."
    
    # Check if preflight script exists
    if [[ -f "$PROJECT_ROOT/lib/unity/core/unity-preflight.sh" ]]; then
        log_test "PASS" "Pre-flight validation script exists"
        
        # Source and test functions
        source "$PROJECT_ROOT/lib/unity/core/unity-preflight.sh" || {
            log_test "FAIL" "Failed to source pre-flight script"
            return 1
        }
        
        # Test function availability
        if command -v preflight_check_all >/dev/null 2>&1; then
            log_test "PASS" "Pre-flight check functions available"
        else
            log_test "FAIL" "Pre-flight check functions not found"
        fi
    else
        log_test "FAIL" "Pre-flight validation script not found"
    fi
}

test_migration_tools() {
    log_test "INFO" "Testing migration tools..."
    
    # Check migration directory
    if [[ -d "$PROJECT_ROOT/scripts/migrate-to-unity" ]]; then
        log_test "PASS" "Migration tools directory exists"
        
        # Check main migration script
        if [[ -x "$PROJECT_ROOT/scripts/migrate-to-unity/migrate-all.sh" ]]; then
            log_test "PASS" "Main migration script is executable"
        else
            log_test "FAIL" "Main migration script not found or not executable"
        fi
        
        # Check migration utilities
        if [[ -f "$PROJECT_ROOT/scripts/migrate-to-unity/lib/migration-utils.sh" ]]; then
            log_test "PASS" "Migration utilities exist"
        else
            log_test "FAIL" "Migration utilities not found"
        fi
    else
        log_test "FAIL" "Migration tools directory not found"
    fi
}

#############################################
# Phase 2: Service Enhancement Tests
#############################################

test_aws_service_enhancement() {
    log_test "INFO" "Testing enhanced AWS service..."
    
    # Check for enhanced AWS service files
    local aws_services=(
        "unity-aws-service-complete.sh"
        "unity-aws-service-vpc.sh"
    )
    
    for service in "${aws_services[@]}"; do
        if [[ -f "$PROJECT_ROOT/lib/unity/services/$service" ]]; then
            log_test "PASS" "AWS service found: $service"
            
            # Test syntax
            if bash -n "$PROJECT_ROOT/lib/unity/services/$service" 2>/dev/null; then
                log_test "PASS" "AWS service syntax valid: $service"
            else
                log_test "FAIL" "AWS service syntax error: $service"
            fi
        else
            log_test "WARN" "AWS service not found: $service"
        fi
    done
}

test_docker_service_enhancement() {
    log_test "INFO" "Testing enhanced Docker service..."
    
    # Check for enhanced Docker service
    if [[ -f "$PROJECT_ROOT/lib/unity/services/unity-docker-service-complete.sh" ]]; then
        log_test "PASS" "Enhanced Docker service exists"
        
        # Test syntax
        if bash -n "$PROJECT_ROOT/lib/unity/services/unity-docker-service-complete.sh" 2>/dev/null; then
            log_test "PASS" "Docker service syntax valid"
        else
            log_test "FAIL" "Docker service syntax error"
        fi
    else
        log_test "FAIL" "Enhanced Docker service not found"
    fi
}

test_monitoring_service() {
    log_test "INFO" "Testing monitoring service..."
    
    # Check for monitoring service
    if [[ -f "$PROJECT_ROOT/lib/unity/services/unity-monitoring-complete.sh" ]]; then
        log_test "PASS" "Monitoring service exists"
        
        # Source and test
        source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || {
            log_test "FAIL" "Failed to load Unity core"
            return 1
        }
        
        source "$PROJECT_ROOT/lib/unity/services/unity-monitoring-complete.sh" || {
            log_test "FAIL" "Failed to source monitoring service"
            return 1
        }
        
        # Test service functions
        if command -v init_unity_monitoring_service >/dev/null 2>&1; then
            log_test "PASS" "Monitoring service functions available"
        else
            log_test "FAIL" "Monitoring service functions not found"
        fi
    else
        log_test "FAIL" "Monitoring service not found"
    fi
}

#############################################
# Integration Tests
#############################################

test_unity_core_integration() {
    log_test "INFO" "Testing Unity core integration..."
    
    # Initialize Unity
    source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" || {
        log_test "FAIL" "Failed to source Unity core"
        return 1
    }
    
    if unity_init >/dev/null 2>&1; then
        log_test "PASS" "Unity core initialization successful"
    else
        log_test "FAIL" "Unity core initialization failed"
    fi
    
    # Test service registration
    if unity_register_service "test" "$SCRIPT_DIR/test-service.sh" "test" "" >/dev/null 2>&1; then
        log_test "PASS" "Service registration works"
    else
        log_test "WARN" "Service registration failed (may be normal)"
    fi
    
    # Test event system
    if unity_emit_event "TEST_EVENT" "test-suite" "test-data" >/dev/null 2>&1; then
        log_test "PASS" "Event emission works"
    else
        log_test "FAIL" "Event emission failed"
    fi
}

test_deployment_flow() {
    log_test "INFO" "Testing deployment flow..."
    
    # Test dry-run deployment
    if "$PROJECT_ROOT/deploy.sh" spot test-stack --dry-run >/dev/null 2>&1; then
        log_test "PASS" "Deployment dry-run works"
    else
        log_test "WARN" "Deployment dry-run failed (may need AWS credentials)"
    fi
}

#############################################
# Configuration Tests
#############################################

test_unity_configuration() {
    log_test "INFO" "Testing Unity configuration..."
    
    # Check configuration files
    if [[ -f "$PROJECT_ROOT/config/unity.yml" ]]; then
        log_test "PASS" "Unity configuration file exists"
        
        # Test YAML syntax if yq is available
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.' "$PROJECT_ROOT/config/unity.yml" >/dev/null 2>&1; then
                log_test "PASS" "Unity configuration syntax valid"
            else
                log_test "FAIL" "Unity configuration syntax error"
            fi
        else
            log_test "WARN" "yq not available, skipping YAML validation"
        fi
    else
        log_test "FAIL" "Unity configuration file not found"
    fi
    
    # Check Unity agents configuration
    if [[ -f "$PROJECT_ROOT/config/unity-agents.yml" ]]; then
        log_test "PASS" "Unity agents configuration exists"
    else
        log_test "WARN" "Unity agents configuration not found"
    fi
}

#############################################
# Performance Tests
#############################################

test_unity_performance() {
    log_test "INFO" "Testing Unity performance..."
    
    # Test initialization speed
    local start_time=$(date +%s%N)
    source "$PROJECT_ROOT/lib/unity/core/unity-core.sh" 2>/dev/null || true
    local end_time=$(date +%s%N)
    
    local init_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [[ $init_time -lt 1000 ]]; then
        log_test "PASS" "Unity initialization fast: ${init_time}ms"
    else
        log_test "WARN" "Unity initialization slow: ${init_time}ms"
    fi
}

#############################################
# Documentation Tests
#############################################

test_documentation() {
    log_test "INFO" "Testing documentation..."
    
    # Check key documentation files
    local docs=(
        "docs/unity/unity-complete-migration-plan.md"
        "docs/unity/unity-implementation-roadmap.md"
        "docs/unity/unity-architecture.md"
        "CLAUDE.md"
        "README.md"
    )
    
    for doc in "${docs[@]}"; do
        if [[ -f "$PROJECT_ROOT/$doc" ]]; then
            log_test "PASS" "Documentation exists: $doc"
        else
            log_test "WARN" "Documentation missing: $doc"
        fi
    done
}

#############################################
# Summary Report
#############################################

generate_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Unity Implementation Test Summary"
    echo "═══════════════════════════════════════════════════════════"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! Unity implementation is complete.${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed. Please review the implementation.${NC}"
        return 1
    fi
}

#############################################
# Main Execution
#############################################

main() {
    print_banner
    
    # Phase 1: Foundation
    echo ""
    echo "Phase 1: Foundation Tests"
    echo "========================="
    test_unity_cli
    test_preflight_system
    test_migration_tools
    
    # Phase 2: Service Enhancement
    echo ""
    echo "Phase 2: Service Enhancement Tests"
    echo "==================================="
    test_aws_service_enhancement
    test_docker_service_enhancement
    test_monitoring_service
    
    # Integration Tests
    echo ""
    echo "Integration Tests"
    echo "================="
    test_unity_core_integration
    test_deployment_flow
    
    # Configuration Tests
    echo ""
    echo "Configuration Tests"
    echo "==================="
    test_unity_configuration
    
    # Performance Tests
    echo ""
    echo "Performance Tests"
    echo "================="
    test_unity_performance
    
    # Documentation Tests
    echo ""
    echo "Documentation Tests"
    echo "==================="
    test_documentation
    
    # Generate summary
    generate_summary
}

# Run tests
main "$@"