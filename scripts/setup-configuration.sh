#!/usr/bin/env bash
# =============================================================================
# Configuration Setup Script
# Helps users set up their environment configuration properly
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# =============================================================================
# SETUP FUNCTIONS
# =============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws-cli")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    # Optional but recommended
    if ! command -v yq >/dev/null 2>&1; then
        print_warning "yq not found - YAML parsing will use fallback methods"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install missing tools before continuing."
        return 1
    fi
    
    print_success "All required tools are installed"
    return 0
}

setup_environment_file() {
    local environment="${1:-local}"
    local template_file=""
    local target_file=""
    
    print_header "Setting up $environment environment"
    
    # Determine files
    case "$environment" in
        local)
            template_file=".env.local.template"
            target_file=".env.local"
            ;;
        development)
            template_file=".env.development.template"
            target_file=".env.development"
            ;;
        staging)
            template_file=".env.staging.template"
            target_file=".env.staging"
            ;;
        production)
            template_file=".env.production.template"
            target_file=".env.production"
            ;;
        *)
            print_error "Unknown environment: $environment"
            return 1
            ;;
    esac
    
    # Check if template exists
    if [[ ! -f "$PROJECT_ROOT/$template_file" ]]; then
        print_error "Template file not found: $template_file"
        return 1
    fi
    
    # Check if target already exists
    if [[ -f "$PROJECT_ROOT/$target_file" ]]; then
        print_warning "$target_file already exists"
        read -p "Do you want to overwrite it? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping $target_file"
            return 0
        fi
    fi
    
    # Copy template
    cp "$PROJECT_ROOT/$template_file" "$PROJECT_ROOT/$target_file"
    print_success "Created $target_file from template"
    
    # Prompt for required values
    print_info "Please update the following required values in $target_file:"
    echo "  - STACK_NAME: Your unique stack identifier"
    echo "  - KEY_NAME: Your AWS SSH key pair name"
    
    # Offer to edit
    if command -v "${EDITOR:-nano}" >/dev/null 2>&1; then
        read -p "Would you like to edit $target_file now? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            "${EDITOR:-nano}" "$PROJECT_ROOT/$target_file"
        fi
    fi
    
    return 0
}

validate_configuration() {
    local env_file="${1:-.env.local}"
    
    print_header "Validating Configuration"
    
    if [[ ! -f "$PROJECT_ROOT/$env_file" ]]; then
        print_error "Configuration file not found: $env_file"
        return 1
    fi
    
    # Source the file
    set -a
    source "$PROJECT_ROOT/$env_file"
    set +a
    
    local errors=0
    
    # Check required variables
    if [[ -z "${STACK_NAME:-}" ]]; then
        print_error "STACK_NAME is not set"
        ((errors++))
    else
        print_success "STACK_NAME is set: $STACK_NAME"
    fi
    
    if [[ -z "${KEY_NAME:-}" ]]; then
        print_error "KEY_NAME is not set"
        ((errors++))
    else
        print_success "KEY_NAME is set: $KEY_NAME"
    fi
    
    # Check AWS configuration
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        if aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            print_success "AWS profile is valid: $AWS_PROFILE"
        else
            print_error "AWS profile is invalid or not configured: $AWS_PROFILE"
            ((errors++))
        fi
    fi
    
    # Check deployment type
    if [[ -n "${DEPLOYMENT_TYPE:-}" ]]; then
        case "$DEPLOYMENT_TYPE" in
            spot|ondemand|simple|enterprise|alb|cdn|full)
                print_success "Deployment type is valid: $DEPLOYMENT_TYPE"
                ;;
            *)
                print_error "Invalid deployment type: $DEPLOYMENT_TYPE"
                ((errors++))
                ;;
        esac
    fi
    
    if [[ $errors -gt 0 ]]; then
        print_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
    
    print_success "Configuration validation passed"
    return 0
}

show_configuration() {
    local env_file="${1:-.env.local}"
    
    print_header "Current Configuration"
    
    if [[ -f "$PROJECT_ROOT/$env_file" ]]; then
        # Source the file
        set -a
        source "$PROJECT_ROOT/$env_file"
        set +a
        
        echo "Environment: ${ENVIRONMENT:-not set}"
        echo "Stack Name: ${STACK_NAME:-not set}"
        echo "AWS Region: ${AWS_REGION:-not set}"
        echo "Deployment Type: ${DEPLOYMENT_TYPE:-not set}"
        echo "Instance Type: ${INSTANCE_TYPE:-not set}"
        echo "Key Name: ${KEY_NAME:-not set}"
        echo
        echo "Features:"
        echo "  Multi-AZ: ${ENABLE_MULTI_AZ:-false}"
        echo "  ALB: ${ENABLE_ALB:-false}"
        echo "  CloudFront: ${ENABLE_CLOUDFRONT:-false}"
        echo "  EFS: ${ENABLE_EFS:-true}"
        echo "  Backup: ${ENABLE_BACKUP:-false}"
    else
        print_error "Configuration file not found: $env_file"
        return 1
    fi
}

setup_parameter_store() {
    print_header "Setting up AWS Parameter Store"
    
    local prefix="${PARAM_STORE_PREFIX:-/aibuildkit}"
    local environment="${ENVIRONMENT:-development}"
    
    print_info "This will help you set up secure parameters in AWS Parameter Store"
    print_info "Prefix: $prefix/$environment"
    
    # Required parameters
    local -a required_params=(
        "POSTGRES_PASSWORD"
        "n8n/ENCRYPTION_KEY"
        "n8n/USER_MANAGEMENT_JWT_SECRET"
    )
    
    # Optional parameters
    local -a optional_params=(
        "OPENAI_API_KEY"
        "WEBHOOK_URL"
    )
    
    echo -e "\nRequired parameters:"
    for param in "${required_params[@]}"; do
        local full_path="$prefix/$environment/$param"
        if aws ssm get-parameter --name "$full_path" >/dev/null 2>&1; then
            print_success "$param already exists"
        else
            print_warning "$param needs to be created"
            read -p "Enter value for $param (or press Enter to skip): " -s param_value
            echo
            if [[ -n "$param_value" ]]; then
                aws ssm put-parameter \
                    --name "$full_path" \
                    --value "$param_value" \
                    --type "SecureString" \
                    --overwrite || print_error "Failed to create $param"
                print_success "Created $param"
            fi
        fi
    done
}

# =============================================================================
# MAIN MENU
# =============================================================================

show_menu() {
    echo -e "\n${BLUE}GeuseMaker Configuration Setup${NC}"
    echo "================================"
    echo "1. Setup local development configuration"
    echo "2. Setup development environment"
    echo "3. Setup staging environment"
    echo "4. Setup production environment"
    echo "5. Validate current configuration"
    echo "6. Show current configuration"
    echo "7. Setup AWS Parameter Store"
    echo "8. Run all setup steps"
    echo "9. Exit"
    echo
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_header "GeuseMaker Configuration Setup"
    
    # Check prerequisites first
    check_prerequisites || exit 1
    
    while true; do
        show_menu
        read -p "Select an option (1-9): " choice
        
        case $choice in
            1)
                setup_environment_file "local"
                ;;
            2)
                setup_environment_file "development"
                ;;
            3)
                setup_environment_file "staging"
                ;;
            4)
                setup_environment_file "production"
                ;;
            5)
                read -p "Enter configuration file to validate [.env.local]: " env_file
                validate_configuration "${env_file:-.env.local}"
                ;;
            6)
                read -p "Enter configuration file to show [.env.local]: " env_file
                show_configuration "${env_file:-.env.local}"
                ;;
            7)
                setup_parameter_store
                ;;
            8)
                setup_environment_file "local"
                validate_configuration ".env.local"
                show_configuration ".env.local"
                ;;
            9)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi