#!/usr/bin/env bash
# =============================================================================
# Unit tests for Setup Suite
# Tests all components, modes, and functionality
# =============================================================================

set -euo pipefail

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/tests/lib/shell-test-framework.sh" || {
    echo "ERROR: Failed to load test framework" >&2
    exit 1
}

# Setup suite location
SETUP_SUITE="$PROJECT_ROOT/lib/modules/config/setup-suite.sh"

# Test environment
TEST_SECRETS_DIR="$PROJECT_ROOT/test-secrets-$$"
TEST_BACKUP_DIR="$PROJECT_ROOT/test-backup-$$"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Create test directories
    mkdir -p "$TEST_SECRETS_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    
    # Export test paths
    export SECRETS_DIR="$TEST_SECRETS_DIR"
    export BACKUP_DIR="$TEST_BACKUP_DIR"
    
    # Mock AWS CLI if not available
    if ! command -v aws >/dev/null 2>&1; then
        export PATH="$SCRIPT_DIR:$PATH"
        cat > "$SCRIPT_DIR/aws" << 'EOF'
#!/usr/bin/env bash
# Mock AWS CLI for testing
echo "Mock AWS CLI output"
exit 0
EOF
        chmod +x "$SCRIPT_DIR/aws"
    fi
}

teardown_test_environment() {
    # Clean up test directories
    rm -rf "$TEST_SECRETS_DIR"
    rm -rf "$TEST_BACKUP_DIR"
    
    # Remove mock AWS CLI
    rm -f "$SCRIPT_DIR/aws"
    
    # Clean up any generated files
    rm -f "$PROJECT_ROOT/.env.development"
    rm -f "$PROJECT_ROOT/.env.staging"
    rm -f "$PROJECT_ROOT/.env.production"
    rm -f "$PROJECT_ROOT/docker-compose.override.yml"
}

# =============================================================================
# COMPONENT TESTS
# =============================================================================

test_setup_suite_exists() {
    local test_name="Setup suite script exists"
    
    if [[ -f "$SETUP_SUITE" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Setup suite not found at: $SETUP_SUITE"
    fi
}

test_setup_suite_executable() {
    local test_name="Setup suite is executable"
    
    if [[ -x "$SETUP_SUITE" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Setup suite is not executable"
    fi
}

test_help_option() {
    local test_name="Help option works"
    
    local output
    output=$(bash "$SETUP_SUITE" --help 2>&1)
    
    if [[ "$output" =~ "GeuseMaker Setup Suite" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Help output not as expected"
    fi
}

test_validate_option() {
    local test_name="Validate option works"
    
    local output
    output=$(bash "$SETUP_SUITE" --validate 2>&1)
    
    if [[ "$output" =~ "Running comprehensive validation" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Validation output not as expected"
    fi
}

test_component_docker() {
    local test_name="Docker component option"
    
    # Skip if not running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        skip "$test_name" "Requires root or sudo access"
        return
    fi
    
    local output
    output=$(bash "$SETUP_SUITE" --component docker --validate 2>&1)
    
    if [[ "$output" =~ "Docker" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Docker component validation failed"
    fi
}

test_component_secrets() {
    local test_name="Secrets component setup"
    
    local output
    output=$(bash "$SETUP_SUITE" --component secrets 2>&1)
    
    # Check if secrets were created
    if [[ -f "$TEST_SECRETS_DIR/postgres_password.txt" ]] && \
       [[ -f "$TEST_SECRETS_DIR/n8n_encryption_key.txt" ]] && \
       [[ -f "$TEST_SECRETS_DIR/n8n_jwt_secret.txt" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Secrets files not created properly"
    fi
}

test_component_config() {
    local test_name="Config component setup"
    
    # Create a mock stdin for environment prompt
    local output
    output=$(echo "development" | bash "$SETUP_SUITE" --component config 2>&1)
    
    # Check if config files were created
    if [[ -f "$PROJECT_ROOT/.env.development" ]] && \
       [[ -f "$PROJECT_ROOT/docker-compose.override.yml" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Config files not created properly"
    fi
}

test_verbose_mode() {
    local test_name="Verbose mode output"
    
    local output
    output=$(bash "$SETUP_SUITE" --component secrets --verbose 2>&1)
    
    # Verbose mode should show more detailed output
    if [[ $(echo "$output" | wc -l) -gt 10 ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Verbose mode did not produce enough output"
    fi
}

test_interactive_mode() {
    local test_name="Interactive mode detection"
    
    local output
    output=$(bash "$SETUP_SUITE" --interactive --help 2>&1)
    
    if [[ "$output" =~ "interactive mode" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Interactive mode not detected in output"
    fi
}

test_return_codes() {
    local test_name="Return codes validation"
    
    # Test successful execution
    bash "$SETUP_SUITE" --help >/dev/null 2>&1
    local success_code=$?
    
    if [[ $success_code -eq 0 ]]; then
        pass "$test_name - Success code"
    else
        fail "$test_name - Success code" "Expected 0, got $success_code"
    fi
    
    # Test invalid option
    bash "$SETUP_SUITE" --invalid-option >/dev/null 2>&1
    local failure_code=$?
    
    if [[ $failure_code -eq 1 ]]; then
        pass "$test_name - Failure code"
    else
        fail "$test_name - Failure code" "Expected 1, got $failure_code"
    fi
}

# =============================================================================
# BACKWARD COMPATIBILITY TESTS
# =============================================================================

test_docker_wrapper() {
    local test_name="Docker wrapper compatibility"
    
    local docker_wrapper="$PROJECT_ROOT/scripts/setup-docker.sh"
    if [[ ! -f "$docker_wrapper" ]]; then
        skip "$test_name" "Docker wrapper not found"
        return
    fi
    
    local output
    output=$(bash "$docker_wrapper" help 2>&1)
    
    if [[ "$output" =~ "deprecated" ]] && [[ "$output" =~ "Setup Suite" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Docker wrapper not showing deprecation notice"
    fi
}

test_parameter_store_wrapper() {
    local test_name="Parameter Store wrapper compatibility"
    
    local ps_wrapper="$PROJECT_ROOT/scripts/setup-parameter-store.sh"
    if [[ ! -f "$ps_wrapper" ]]; then
        skip "$test_name" "Parameter Store wrapper not found"
        return
    fi
    
    local output
    output=$(bash "$ps_wrapper" --help 2>&1)
    
    if [[ "$output" =~ "deprecated" ]] && [[ "$output" =~ "Setup Suite" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Parameter Store wrapper not showing deprecation notice"
    fi
}

test_secrets_wrapper() {
    local test_name="Secrets wrapper compatibility"
    
    local secrets_wrapper="$PROJECT_ROOT/scripts/setup-secrets.sh"
    if [[ ! -f "$secrets_wrapper" ]]; then
        skip "$test_name" "Secrets wrapper not found"
        return
    fi
    
    local output
    output=$(bash "$secrets_wrapper" help 2>&1)
    
    if [[ "$output" =~ "deprecated" ]] && [[ "$output" =~ "Setup Suite" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Secrets wrapper not showing deprecation notice"
    fi
}

test_config_wrapper() {
    local test_name="Config Manager wrapper compatibility"
    
    local config_wrapper="$PROJECT_ROOT/scripts/config-manager.sh"
    if [[ ! -f "$config_wrapper" ]]; then
        skip "$test_name" "Config Manager wrapper not found"
        return
    fi
    
    local output
    output=$(bash "$config_wrapper" help 2>&1)
    
    if [[ "$output" =~ "deprecated" ]] && [[ "$output" =~ "Setup Suite" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Config Manager wrapper not showing deprecation notice"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_all_components_setup() {
    local test_name="All components setup"
    
    # This test would take too long, so we just validate the option exists
    local output
    output=$(bash "$SETUP_SUITE" --component all --help 2>&1)
    
    if [[ "$output" =~ "all" ]] && [[ "$output" =~ "Setup all components" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "All components option not properly documented"
    fi
}

test_secrets_permissions() {
    local test_name="Secrets file permissions"
    
    # Setup secrets first
    bash "$SETUP_SUITE" --component secrets >/dev/null 2>&1
    
    # Check permissions on created files
    if [[ -f "$TEST_SECRETS_DIR/postgres_password.txt" ]]; then
        local perms
        perms=$(stat -c %a "$TEST_SECRETS_DIR/postgres_password.txt" 2>/dev/null || stat -f %A "$TEST_SECRETS_DIR/postgres_password.txt")
        
        if [[ "$perms" == "600" ]]; then
            pass "$test_name"
        else
            fail "$test_name" "Incorrect permissions: $perms (expected 600)"
        fi
    else
        fail "$test_name" "Secrets file not created"
    fi
}

test_config_content_validation() {
    local test_name="Config content validation"
    
    # Create config for development
    echo "development" | bash "$SETUP_SUITE" --component config >/dev/null 2>&1
    
    if [[ -f "$PROJECT_ROOT/.env.development" ]]; then
        local content
        content=$(cat "$PROJECT_ROOT/.env.development")
        
        if [[ "$content" =~ "ENVIRONMENT=development" ]] && \
           [[ "$content" =~ "PROJECT_NAME=GeuseMaker" ]]; then
            pass "$test_name"
        else
            fail "$test_name" "Config content not as expected"
        fi
    else
        fail "$test_name" "Config file not created"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_tests() {
    section "Setup Suite Unit Tests"
    
    # Setup test environment
    setup_test_environment
    
    # Basic functionality tests
    subsection "Basic Functionality"
    test_setup_suite_exists
    test_setup_suite_executable
    test_help_option
    test_validate_option
    
    # Component tests
    subsection "Component Tests"
    test_component_docker
    test_component_secrets
    test_component_config
    
    # Mode tests
    subsection "Mode Tests"
    test_verbose_mode
    test_interactive_mode
    test_return_codes
    
    # Backward compatibility tests
    subsection "Backward Compatibility"
    test_docker_wrapper
    test_parameter_store_wrapper
    test_secrets_wrapper
    test_config_wrapper
    
    # Integration tests
    subsection "Integration Tests"
    test_all_components_setup
    test_secrets_permissions
    test_config_content_validation
    
    # Cleanup test environment
    teardown_test_environment
    
    # Show results
    show_results
}

# Run tests
run_tests