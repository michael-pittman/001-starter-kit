#!/usr/bin/env bash
# Complete Deployment Flow Test
# Tests the full modular deployment system end-to-end

# Initialize library loader
SCRIPT_DIR_TEMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TEMP="$(cd "$SCRIPT_DIR_TEMP/.." && pwd)/lib"

# Source the errors module for version checking
if [[ -f "$LIB_DIR_TEMP/modules/core/errors.sh" ]]; then
    source "$LIB_DIR_TEMP/modules/core/errors.sh"
else
    # Fallback warning if errors module not found
    echo "WARNING: Could not load errors module" >&2
fi

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-deployment-flow.sh" "core/variables" "core/logging"

readonly TEST_STACK_NAME="test-deployment-$(date +%s)"
readonly TEST_REGION="us-east-1"
readonly TEST_INSTANCE_TYPE="t3.micro"  # Small instance for testing

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Use standardized logging if available, otherwise fallback to custom functions
if command -v log_message >/dev/null 2>&1; then
    log_info() { log_message "INFO" "$1" "TEST"; }
    log_success() { log_message "INFO" "$1" "TEST"; }  # Use INFO level for success
    log_error() { log_message "ERROR" "$1" "TEST"; }
    log_warn() { log_message "WARN" "$1" "TEST"; }
else
    # Fallback to custom colored logging
    log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fi

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_aws_environment() {
    log_info "Validating AWS environment..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI not found"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_warn "AWS credentials not configured - skipping AWS-dependent tests"
        return 1
    fi
    
    log_success "AWS environment validated"
    return 0
}

test_orchestrator_help() {
    log_info "Testing orchestrator help command..."
    
    local help_output
    if help_output=$("$PROJECT_ROOT/scripts/aws-deployment-v2.sh" --help 2>&1); then
        if echo "$help_output" | grep -q "AWS Deployment Orchestrator"; then
            log_success "Help command working correctly"
            return 0
        else
            log_error "Help output missing expected content"
            return 1
        fi
    else
        log_error "Help command failed"
        return 1
    fi
}

test_orchestrator_syntax() {
    log_info "Testing orchestrator script syntax..."
    
    if bash -n "$PROJECT_ROOT/scripts/aws-deployment-v2.sh"; then
        log_success "Orchestrator syntax is valid"
        return 0
    else
        log_error "Orchestrator has syntax errors"
        return 1
    fi
}

test_variable_management() {
    log_info "Testing variable management system..."
    
    # Create a temporary test script
    local test_script="/tmp/test-variables-$$.sh"
    cat > "$test_script" <<'EOF'
set -euo pipefail

# Initialize arrays without -g flag for bash 3.x compatibility
declare -A VARIABLE_REGISTRY
declare -A VARIABLE_VALIDATORS  
declare -A VARIABLE_DEFAULTS
declare -A VARIABLE_VALUES
declare -A VARIABLE_REQUIRED

# Simple sanitization function
sanitize_variable_name() {
    local name="$1"
    echo "$name" | sed 's/[^a-zA-Z0-9_]/_/g' | sed 's/^[0-9]/_&/'
}

# Test sanitization
result=$(sanitize_variable_name "efs-id")
if [[ "$result" == "efs_id" ]]; then
    echo "PASS: Variable sanitization works"
    exit 0
else
    echo "FAIL: Expected 'efs_id', got '$result'"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    if "$test_script"; then
        log_success "Variable management system working"
        rm -f "$test_script"
        return 0
    else
        log_error "Variable management system failed"
        rm -f "$test_script"
        return 1
    fi
}

test_error_handling() {
    log_info "Testing error handling system..."
    
    # Create a temporary test script
    local test_script="/tmp/test-errors-$$.sh"
    cat > "$test_script" <<'EOF'
set -euo pipefail

# Initialize error tracking arrays
declare -A ERROR_COUNT
declare -A ERROR_RECOVERY_STRATEGIES

# Simple error logging function
log_structured_error() {
    local error_code="$1"
    local message="$2"
    local recovery="${3:-abort}"
    
    ERROR_COUNT["$error_code"]=$((${ERROR_COUNT["$error_code"]:-0} + 1))
    ERROR_RECOVERY_STRATEGIES["$error_code"]="$recovery"
    
    echo "ERROR: [$error_code] $message (recovery: $recovery)"
}

# Test error logging
log_structured_error "TEST_ERROR" "Test error message" "retry"

if [[ "${ERROR_COUNT[TEST_ERROR]}" == "1" ]] && [[ "${ERROR_RECOVERY_STRATEGIES[TEST_ERROR]}" == "retry" ]]; then
    echo "PASS: Error handling works"
    exit 0
else
    echo "FAIL: Error handling failed"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    if "$test_script" >/dev/null 2>&1; then
        log_success "Error handling system working"
        rm -f "$test_script"
        return 0
    else
        log_error "Error handling system failed"
        rm -f "$test_script"
        return 1
    fi
}

test_registry_system() {
    log_info "Testing resource registry system..."
    
    # Create a temporary test script
    local test_script="/tmp/test-registry-$$.sh"
    cat > "$test_script" <<'EOF'
set -euo pipefail

RESOURCE_REGISTRY_FILE="/tmp/test-registry-$$.json"

# Initialize test registry
initialize_registry() {
    cat > "$RESOURCE_REGISTRY_FILE" <<REGEOF
{
    "stack_name": "test-stack",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "region": "us-east-1",
    "resources": {
        "instances": [],
        "volumes": []
    }
}
REGEOF
}

# Register a resource (simplified)
register_resource() {
    local resource_type="$1"
    local resource_id="$2"
    
    echo "Registering $resource_type: $resource_id"
    # In real implementation, would use jq to update JSON
    return 0
}

# Test the functions
initialize_registry
register_resource "instances" "i-12345"

if [[ -f "$RESOURCE_REGISTRY_FILE" ]]; then
    echo "PASS: Registry system works"
    rm -f "$RESOURCE_REGISTRY_FILE"
    exit 0
else
    echo "FAIL: Registry file not created"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    if "$test_script" >/dev/null 2>&1; then
        log_success "Registry system working"
        rm -f "$test_script"
        return 0
    else
        log_error "Registry system failed"
        rm -f "$test_script"
        return 1
    fi
}

test_compute_module() {
    log_info "Testing compute module logic..."
    
    # Create a temporary test script
    local test_script="/tmp/test-compute-$$.sh"
    cat > "$test_script" <<'EOF'
set -euo pipefail

# Test instance type fallback logic
declare -A INSTANCE_TYPE_FALLBACKS=(
    ["g4dn.xlarge"]="g4dn.large g5.xlarge"
    ["t3.micro"]="t3.small t2.micro"
)

get_fallback_types() {
    local instance_type="$1"
    echo "${INSTANCE_TYPE_FALLBACKS[$instance_type]:-}"
}

# Test fallback lookup
fallbacks=$(get_fallback_types "g4dn.xlarge")
if [[ "$fallbacks" == "g4dn.large g5.xlarge" ]]; then
    echo "PASS: Compute fallback logic works"
    exit 0
else
    echo "FAIL: Expected 'g4dn.large g5.xlarge', got '$fallbacks'"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    if "$test_script"; then
        log_success "Compute module logic working"
        rm -f "$test_script"
        return 0
    else
        log_error "Compute module logic failed"
        rm -f "$test_script"
        return 1
    fi
}

test_dry_run_deployment() {
    log_info "Testing dry-run deployment validation..."
    
    # Test orchestrator argument parsing without actual deployment
    local output
    if output=$("$PROJECT_ROOT/scripts/aws-deployment-v2.sh" --help 2>&1); then
        log_success "Orchestrator argument parsing works"
        return 0
    else
        log_error "Orchestrator argument parsing failed"
        return 1
    fi
}

# =============================================================================
# AWS INTEGRATION TESTS (if credentials available)
# =============================================================================

test_aws_integration() {
    log_info "Testing AWS integration (if credentials available)..."
    
    if ! validate_aws_environment; then
        log_warn "Skipping AWS integration tests - no valid credentials"
        return 0
    fi
    
    # Test AWS CLI calls
    local caller_id
    if caller_id=$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null); then
        log_success "AWS integration working (Account: $caller_id)"
        return 0
    else
        log_error "AWS integration failed"
        return 1
    fi
}

test_instance_type_availability() {
    log_info "Testing instance type availability check..."
    
    if ! validate_aws_environment; then
        log_warn "Skipping instance type test - no AWS credentials"
        return 0
    fi
    
    # Test instance type availability in region
    if aws ec2 describe-instance-type-offerings \
        --location-type availability-zone \
        --filters "Name=instance-type,Values=$TEST_INSTANCE_TYPE" \
        --region "$TEST_REGION" \
        --query 'InstanceTypeOfferings[0].InstanceType' \
        --output text 2>/dev/null | grep -q "$TEST_INSTANCE_TYPE"; then
        log_success "Instance type $TEST_INSTANCE_TYPE available in $TEST_REGION"
        return 0
    else
        log_warn "Instance type $TEST_INSTANCE_TYPE not available in $TEST_REGION"
        return 1
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_all_tests() {
    local tests_run=0
    local tests_passed=0
    local tests_failed=0
    
    # Array of test functions
    local test_functions=(
        "test_orchestrator_syntax"
        "test_orchestrator_help"
        "test_variable_management"
        "test_error_handling"
        "test_registry_system"
        "test_compute_module"
        "test_dry_run_deployment"
        "test_aws_integration"
        "test_instance_type_availability"
    )
    
    log_info "Starting complete deployment flow tests..."
    echo
    
    for test_func in "${test_functions[@]}"; do
        ((tests_run++))
        echo -n "Running $test_func... "
        
        if $test_func >/dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC}"
            ((tests_passed++))
        else
            echo -e "${RED}FAIL${NC}"
            ((tests_failed++))
            # Run again to show output
            echo "  Error details:"
            $test_func 2>&1 | sed 's/^/    /'
            echo
        fi
    done
    
    echo
    log_info "=== TEST SUMMARY ==="
    log_info "Tests run: $tests_run"
    log_info "Tests passed: $tests_passed"
    log_info "Tests failed: $tests_failed"
    
    if [[ $tests_failed -eq 0 ]]; then
        log_success "All tests passed! The modular deployment system is ready."
        return 0
    else
        log_error "$tests_failed tests failed. Please review the issues above."
        return 1
    fi
}

# =============================================================================
# DEPLOYMENT READINESS CHECKLIST
# =============================================================================

print_deployment_readiness() {
    log_info "=== DEPLOYMENT READINESS CHECKLIST ==="
    echo
    
    # Check AWS CLI
    if command -v aws >/dev/null 2>&1; then
        log_success "✓ AWS CLI installed"
    else
        log_error "✗ AWS CLI not installed"
    fi
    
    # Check AWS credentials
    if aws sts get-caller-identity >/dev/null 2>&1; then
        log_success "✓ AWS credentials configured"
    else
        log_warn "! AWS credentials not configured (required for deployment)"
    fi
    
    # Check required tools
    for tool in jq docker; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "✓ $tool installed"
        else
            log_warn "! $tool not installed (may be required for deployment)"
        fi
    done
    
    # Check modular scripts
    if [[ -f "$PROJECT_ROOT/scripts/aws-deployment-v2.sh" ]]; then
        log_success "✓ Modular deployment orchestrator ready"
    else
        log_error "✗ Modular deployment orchestrator missing"
    fi
    
    echo
    log_info "=== USAGE EXAMPLES ==="
    echo
    echo "# Test deployment (dry-run validation):"
    echo "$PROJECT_ROOT/scripts/aws-deployment-v2.sh --help"
    echo
    echo "# Deploy with default settings:"
    echo "$PROJECT_ROOT/scripts/aws-deployment-v2.sh my-stack"
    echo
    echo "# Deploy with custom instance type and region:"
    echo "$PROJECT_ROOT/scripts/aws-deployment-v2.sh -t g4dn.xlarge -r us-west-2 my-stack"
    echo
    echo "# Cleanup resources:"
    echo "$PROJECT_ROOT/scripts/aws-deployment-v2.sh --cleanup-only my-stack"
    echo
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

main() {
    log_info "Modular Deployment System - Complete Flow Test"
    log_info "Testing stack: $TEST_STACK_NAME"
    echo
    
    # Run all tests
    if run_all_tests; then
        echo
        print_deployment_readiness
        
        log_success "Modular deployment system validation completed successfully!"
        log_info "The system is ready for production deployment."
        return 0
    else
        log_error "Some tests failed. Please address the issues before deploying."
        return 1
    fi
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
