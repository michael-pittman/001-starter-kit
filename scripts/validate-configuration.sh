#!/usr/bin/env bash
# =============================================================================
# Configuration Validation Script
# Validates configuration consistency across all sources
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Load required libraries
safe_source "config-defaults-loader.sh" false "Config defaults loader"
safe_source "deployment-variable-management.sh" false "Deployment variable management"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    ((VALIDATION_ERRORS++))
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}" >&2
    ((VALIDATION_WARNINGS++))
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if defaults.yml exists and is valid
validate_defaults_file() {
    echo -e "\n${BLUE}=== Validating defaults.yml ===${NC}\n"
    
    local defaults_file="$PROJECT_ROOT/config/defaults.yml"
    
    if [[ ! -f "$defaults_file" ]]; then
        log_error "defaults.yml not found at $defaults_file"
        return 1
    fi
    
    log_success "defaults.yml exists"
    
    # Check YAML syntax if yq is available
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' "$defaults_file" >/dev/null 2>&1; then
            log_success "defaults.yml has valid YAML syntax"
        else
            log_error "defaults.yml has invalid YAML syntax"
            return 1
        fi
        
        # Check required sections
        local required_sections=("global" "deployment_variables" "infrastructure")
        for section in "${required_sections[@]}"; do
            if yq eval ".$section" "$defaults_file" | grep -q null; then
                log_error "Required section '$section' missing in defaults.yml"
            else
                log_success "Section '$section' exists in defaults.yml"
            fi
        done
    else
        log_warning "yq not installed, skipping YAML syntax validation"
    fi
    
    return 0
}

# Validate consistency between different configuration sources
validate_consistency() {
    echo -e "\n${BLUE}=== Validating Configuration Consistency ===${NC}\n"
    
    # Load defaults from YAML
    if declare -f load_defaults_from_yaml >/dev/null 2>&1; then
        load_defaults_from_yaml || {
            log_warning "Failed to load defaults from YAML"
        }
    fi
    
    # Compare key variables across sources
    local vars_to_check=(
        "AWS_REGION:us-east-1"
        "INSTANCE_TYPE:g4dn.xlarge"
        "VOLUME_SIZE:30"
        "DEPLOYMENT_TYPE:spot"
        "ENVIRONMENT:development"
    )
    
    for var_spec in "${vars_to_check[@]}"; do
        IFS=':' read -r var_name expected_default <<< "$var_spec"
        
        # Get value from environment
        local env_value="${!var_name:-}"
        
        # Get value from defaults.yml (if loaded)
        local yaml_value="${!var_name:-$expected_default}"
        
        if [[ -n "$env_value" ]]; then
            log_info "$var_name: $env_value (from environment)"
        else
            log_info "$var_name: $yaml_value (from defaults)"
        fi
    done
}

# Validate variable registration consistency
validate_variable_registration() {
    echo -e "\n${BLUE}=== Validating Variable Registration ===${NC}\n"
    
    # Check if variables module is loaded
    if ! declare -f register_variable >/dev/null 2>&1; then
        log_warning "Variable registration system not loaded"
        return 0
    fi
    
    # Check critical variables are registered
    local critical_vars=("STACK_NAME" "AWS_REGION" "DEPLOYMENT_TYPE" "INSTANCE_TYPE")
    
    for var in "${critical_vars[@]}"; do
        if is_variable_registered "$var" 2>/dev/null; then
            log_success "$var is registered"
        else
            log_error "$var is not registered"
        fi
    done
}

# Validate environment files
validate_environment_files() {
    echo -e "\n${BLUE}=== Validating Environment Files ===${NC}\n"
    
    local env_files=(
        ".env"
        ".env.local"
        ".env.development"
        ".env.staging"
        ".env.production"
    )
    
    for env_file in "${env_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$env_file" ]]; then
            log_info "Found $env_file"
            
            # Check for required variables
            if grep -q "STACK_NAME=" "$PROJECT_ROOT/$env_file"; then
                local stack_value=$(grep "STACK_NAME=" "$PROJECT_ROOT/$env_file" | cut -d= -f2)
                if [[ -n "$stack_value" ]]; then
                    log_success "  STACK_NAME is set in $env_file"
                else
                    log_warning "  STACK_NAME is empty in $env_file"
                fi
            else
                log_warning "  STACK_NAME not found in $env_file"
            fi
        fi
    done
}

# Validate deployment type configurations
validate_deployment_types() {
    echo -e "\n${BLUE}=== Validating Deployment Types ===${NC}\n"
    
    local deployment_types_file="$PROJECT_ROOT/config/deployment-types.yml"
    
    if [[ ! -f "$deployment_types_file" ]]; then
        log_warning "deployment-types.yml not found"
        return 0
    fi
    
    if command -v yq >/dev/null 2>&1; then
        local types=(spot ondemand simple enterprise alb cdn full)
        for type in "${types[@]}"; do
            if yq eval ".$type" "$deployment_types_file" | grep -q null; then
                log_warning "Deployment type '$type' not defined in deployment-types.yml"
            else
                log_success "Deployment type '$type' is defined"
            fi
        done
    fi
}

# Check for conflicting configurations
check_conflicts() {
    echo -e "\n${BLUE}=== Checking for Configuration Conflicts ===${NC}\n"
    
    # Check if both .env and .env.local exist
    if [[ -f "$PROJECT_ROOT/.env" ]] && [[ -f "$PROJECT_ROOT/.env.local" ]]; then
        log_warning "Both .env and .env.local exist - .env.local will take precedence"
    fi
    
    # Check for hardcoded values that differ from defaults
    local vars_module="$PROJECT_ROOT/lib/modules/config/variables.sh"
    if [[ -f "$vars_module" ]]; then
        # Check VOLUME_SIZE inconsistency
        if grep -q 'VOLUME_SIZE.*"100"' "$vars_module"; then
            log_warning "VOLUME_SIZE default is 100 in variables.sh but 30 in defaults.yml"
        fi
        
        # Check ENVIRONMENT inconsistency
        if grep -q 'ENVIRONMENT.*"production"' "$vars_module"; then
            log_warning "ENVIRONMENT default is 'production' in variables.sh but 'development' in defaults.yml"
        fi
    fi
}

# Generate configuration report
generate_report() {
    echo -e "\n${BLUE}=== Configuration Validation Report ===${NC}\n"
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log_success "No errors found"
    else
        log_error "Found $VALIDATION_ERRORS error(s)"
    fi
    
    if [[ $VALIDATION_WARNINGS -eq 0 ]]; then
        log_success "No warnings found"
    else
        log_warning "Found $VALIDATION_WARNINGS warning(s)"
    fi
    
    # Recommendations
    if [[ $VALIDATION_ERRORS -gt 0 ]] || [[ $VALIDATION_WARNINGS -gt 0 ]]; then
        echo -e "\n${BLUE}Recommendations:${NC}"
        echo "1. Run ./scripts/setup-configuration.sh to set up proper configuration"
        echo "2. Ensure defaults.yml is the single source of truth for defaults"
        echo "3. Use environment-specific .env files for overrides"
        echo "4. Keep hardcoded defaults consistent with defaults.yml"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo -e "${BLUE}GeuseMaker Configuration Validation${NC}"
    echo "===================================="
    
    # Run all validations
    validate_defaults_file
    validate_consistency
    validate_variable_registration
    validate_environment_files
    validate_deployment_types
    check_conflicts
    
    # Generate report
    generate_report
    
    # Exit with error if validation failed
    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        exit 1
    fi
    
    exit 0
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi