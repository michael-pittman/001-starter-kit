#!/usr/bin/env bash
# =============================================================================
# Consolidated Setup Suite for GeuseMaker
# Combines docker, parameter-store, secrets, and config management setup
# Supports interactive, automated, and component-specific execution
# Compatible with bash 3.x+
# =============================================================================

set -euo pipefail

# Script initialization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Load library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh" || {
    echo "ERROR: Failed to load library loader" >&2
    exit 1
}

# Initialize script with required modules
initialize_script "setup-suite.sh" "core/variables" "core/logging" "core/validation"

# Load additional libraries
safe_source "aws-cli-v2.sh" true "AWS CLI v2 enhancements"
safe_source "config-management.sh" true "Configuration management"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Setup modes
INTERACTIVE_MODE=false
VERBOSE_MODE=false
VALIDATE_ONLY=false
COMPONENT=""
ALL_COMPONENTS="docker parameter-store secrets config"

# Configuration paths
SECRETS_DIR="${SECRETS_DIR:-$PROJECT_ROOT/secrets}"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/.secrets-backup}"
CONFIG_DIR="${CONFIG_DIR:-$PROJECT_ROOT/config}"

# Docker configuration
readonly DOCKER_VERSION_MIN="20.10.0"
readonly DOCKER_COMPOSE_VERSION_MIN="2.0.0"
readonly DOCKER_DAEMON_TIMEOUT=180

# Security configuration
readonly KEY_LENGTH=64  # 64 hex chars = 256 bits

# Return codes
readonly SUCCESS=0
readonly SETUP_FAILED=1
readonly VALIDATION_FAILED=2

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Enhanced logging for verbose mode
verbose_log() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log "$@"
    fi
}

# Interactive prompt
prompt_user() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        if [[ -n "$default" ]]; then
            read -p "$prompt [$default]: " response
            echo "${response:-$default}"
        else
            read -p "$prompt: " response
            echo "$response"
        fi
    else
        echo "$default"
    fi
}

# Yes/No prompt
confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        local response
        read -p "$prompt (y/N): " -n 1 -r response
        echo
        [[ "$response" =~ ^[Yy]$ ]]
    else
        [[ "$default" == "y" ]]
    fi
}

# Progress indicator
show_progress() {
    local step="$1"
    local total="$2"
    local description="$3"
    
    local percentage=$((step * 100 / total))
    echo -e "\n${BLUE}[${percentage}%]${NC} ${description}"
}

# =============================================================================
# DOCKER SETUP FUNCTIONS (from setup-docker.sh)
# =============================================================================

# Check if Docker daemon is responding
docker_daemon_responding() {
    docker info >/dev/null 2>&1
}

# Get Docker version
get_docker_version() {
    docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown"
}

# Validate Docker installation
validate_docker_installation() {
    verbose_log "Validating Docker installation..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed"
        return $VALIDATION_FAILED
    fi
    
    # Check Docker version
    local docker_version
    docker_version=$(get_docker_version)
    if [[ "$docker_version" == "unknown" ]]; then
        warning "Cannot determine Docker version"
    else
        verbose_log "Docker version: $docker_version"
    fi
    
    # Check Docker Compose
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
        verbose_log "Docker Compose version: $compose_version"
    elif docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        verbose_log "Docker Compose plugin version: $compose_version"
    else
        warning "Docker Compose not available"
    fi
    
    return $SUCCESS
}

# Setup Docker component
setup_docker_component() {
    show_progress 1 4 "Setting up Docker..."
    
    # Create Docker daemon configuration
    verbose_log "Creating Docker daemon configuration..."
    
    # Ensure Docker config directory exists
    sudo mkdir -p /etc/docker
    
    # Create daemon configuration
    local config_file="/etc/docker/daemon.json"
    local temp_config="/tmp/docker-daemon-config.json"
    
    cat > "$temp_config" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "data-root": "/var/lib/docker",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "default-runtime": "runc",
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 5,
    "default-shm-size": "64M"
}
EOF
    
    # Move configuration to final location
    sudo mv "$temp_config" "$config_file"
    sudo chmod 644 "$config_file"
    
    show_progress 2 4 "Starting Docker daemon..."
    
    # Start Docker service
    if ! systemctl is-active --quiet docker; then
        sudo systemctl start docker || {
            error "Failed to start Docker daemon"
            return $SETUP_FAILED
        }
    fi
    
    # Enable Docker to start on boot
    sudo systemctl enable docker || warning "Failed to enable Docker service on boot"
    
    show_progress 3 4 "Waiting for Docker daemon..."
    
    # Wait for Docker daemon
    local wait_time=0
    while [[ $wait_time -lt $DOCKER_DAEMON_TIMEOUT ]]; do
        if docker_daemon_responding; then
            verbose_log "Docker daemon is responding"
            break
        fi
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    if [[ $wait_time -ge $DOCKER_DAEMON_TIMEOUT ]]; then
        error "Docker daemon did not become ready within ${DOCKER_DAEMON_TIMEOUT}s"
        return $SETUP_FAILED
    fi
    
    show_progress 4 4 "Setting up Docker permissions..."
    
    # Add ubuntu user to docker group
    if id ubuntu >/dev/null 2>&1; then
        if ! groups ubuntu | grep -q docker; then
            sudo usermod -aG docker ubuntu
            verbose_log "Added ubuntu user to docker group"
        fi
    fi
    
    success "Docker setup completed"
    return $SUCCESS
}

# =============================================================================
# PARAMETER STORE SETUP FUNCTIONS (from setup-parameter-store.sh)
# =============================================================================

# Create parameter in Parameter Store
create_parameter() {
    local name="$1"
    local value="$2"
    local type="${3:-String}"
    local description="$4"
    local aws_region="${5:-us-east-1}"
    
    # Check if parameter already exists
    if aws_cli_with_retry ssm get-parameter --name "$name" --region "$aws_region" &>/dev/null; then
        verbose_log "Parameter $name already exists"
        return $SUCCESS
    fi
    
    # Create parameter
    aws_cli_with_retry ssm put-parameter \
        --name "$name" \
        --value "$value" \
        --type "$type" \
        --description "$description" \
        --region "$aws_region" \
        --overwrite > /dev/null
    
    verbose_log "Created parameter: $name"
    return $SUCCESS
}

# Setup Parameter Store component
setup_parameter_store_component() {
    local aws_region
    aws_region=$(prompt_user "AWS Region" "us-east-1")
    
    show_progress 1 4 "Checking AWS permissions..."
    
    # Check AWS CLI and permissions
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI not available"
        return $SETUP_FAILED
    fi
    
    if ! aws_cli_with_retry ssm describe-parameters --region "$aws_region" --max-items 1 &>/dev/null; then
        error "Missing SSM permissions or invalid AWS credentials"
        return $SETUP_FAILED
    fi
    
    show_progress 2 4 "Creating database parameters..."
    
    # PostgreSQL password
    create_parameter \
        "/aibuildkit/POSTGRES_PASSWORD" \
        "$(openssl rand -hex 32)" \
        "SecureString" \
        "PostgreSQL database password for GeuseMaker" \
        "$aws_region"
    
    show_progress 3 4 "Creating n8n parameters..."
    
    # n8n encryption key
    create_parameter \
        "/aibuildkit/n8n/ENCRYPTION_KEY" \
        "$(openssl rand -hex 32)" \
        "SecureString" \
        "n8n encryption key for data protection" \
        "$aws_region"
    
    # n8n JWT secret
    create_parameter \
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET" \
        "$(openssl rand -hex 32)" \
        "SecureString" \
        "n8n JWT secret for user management" \
        "$aws_region"
    
    # n8n CORS settings
    create_parameter \
        "/aibuildkit/n8n/CORS_ENABLE" \
        "true" \
        "String" \
        "Enable CORS for n8n" \
        "$aws_region"
    
    create_parameter \
        "/aibuildkit/n8n/CORS_ALLOWED_ORIGINS" \
        "*" \
        "String" \
        "Allowed CORS origins for n8n" \
        "$aws_region"
    
    show_progress 4 4 "Creating API key placeholders..."
    
    # API key placeholders
    local api_keys=(
        "OPENAI_API_KEY:OpenAI API key for LLM services"
        "ANTHROPIC_API_KEY:Anthropic Claude API key"
        "DEEPSEEK_API_KEY:DeepSeek API key for local models"
        "GROQ_API_KEY:Groq API key for fast inference"
    )
    
    for key_info in "${api_keys[@]}"; do
        local key_name="${key_info%:*}"
        local description="${key_info#*:}"
        
        create_parameter \
            "/aibuildkit/$key_name" \
            "" \
            "SecureString" \
            "$description (placeholder - add your actual key)" \
            "$aws_region"
    done
    
    # Webhook URL
    create_parameter \
        "/aibuildkit/WEBHOOK_URL" \
        "http://localhost:5678" \
        "String" \
        "Base webhook URL for n8n" \
        "$aws_region"
    
    success "Parameter Store setup completed"
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo
        warning "Next steps:"
        echo "Update API keys with your actual values:"
        for key_info in "${api_keys[@]}"; do
            local key_name="${key_info%:*}"
            echo "  aws ssm put-parameter --name '/aibuildkit/$key_name' --value 'YOUR_KEY' --type SecureString --overwrite --region $aws_region"
        done
    fi
    
    return $SUCCESS
}

# Validate Parameter Store setup
validate_parameter_store() {
    local aws_region="${1:-us-east-1}"
    
    verbose_log "Validating Parameter Store setup..."
    
    local required_params=(
        "/aibuildkit/POSTGRES_PASSWORD"
        "/aibuildkit/n8n/ENCRYPTION_KEY"
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET"
        "/aibuildkit/WEBHOOK_URL"
    )
    
    local missing_params=()
    
    for param in "${required_params[@]}"; do
        if ! aws_cli_with_retry ssm get-parameter --name "$param" --region "$aws_region" &>/dev/null; then
            missing_params+=("$param")
        fi
    done
    
    if [[ ${#missing_params[@]} -eq 0 ]]; then
        success "All required parameters are present"
        return $SUCCESS
    else
        error "Missing required parameters:"
        for param in "${missing_params[@]}"; do
            echo "  - $param"
        done
        return $VALIDATION_FAILED
    fi
}

# =============================================================================
# SECRETS SETUP FUNCTIONS (from setup-secrets.sh)
# =============================================================================

# Generate secure key
generate_secure_key() {
    local length="${1:-$KEY_LENGTH}"
    openssl rand -hex "$((length/2))"
}

# Generate secure password
generate_secure_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Setup secrets component
setup_secrets_component() {
    show_progress 1 3 "Creating secrets directory structure..."
    
    # Create directories
    mkdir -p "$SECRETS_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Set restrictive permissions
    chmod 700 "$SECRETS_DIR"
    chmod 700 "$BACKUP_DIR"
    
    # Create .gitignore
    cat > "$SECRETS_DIR/.gitignore" << 'EOF'
# Ignore all files in this directory
*
# Except this file
!.gitignore
!README.md
EOF
    
    # Create README
    cat > "$SECRETS_DIR/README.md" << 'EOF'
# Secrets Directory

This directory contains sensitive credentials for GeuseMaker.

**IMPORTANT**: Never commit these files to version control!

## Files

- `postgres_password.txt` - PostgreSQL database password
- `n8n_encryption_key.txt` - n8n data encryption key
- `n8n_jwt_secret.txt` - n8n JWT signing secret
- `admin_password.txt` - Admin user password
- `api_keys.env` - External API keys (optional)

## Security

- All files should have 600 permissions
- Backup these files securely
- Rotate secrets regularly
- Use AWS Secrets Manager in production
EOF
    
    show_progress 2 3 "Generating secure secrets..."
    
    local regenerate=false
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        if [[ -f "$SECRETS_DIR/postgres_password.txt" ]]; then
            regenerate=$(confirm_action "Secrets already exist. Regenerate?" "n")
        fi
    fi
    
    # PostgreSQL password
    if [[ ! -f "$SECRETS_DIR/postgres_password.txt" ]] || [[ "$regenerate" == "true" ]]; then
        generate_secure_password 32 > "$SECRETS_DIR/postgres_password.txt"
        chmod 600 "$SECRETS_DIR/postgres_password.txt"
        verbose_log "Generated PostgreSQL password"
    fi
    
    # n8n encryption key
    if [[ ! -f "$SECRETS_DIR/n8n_encryption_key.txt" ]] || [[ "$regenerate" == "true" ]]; then
        generate_secure_key 64 > "$SECRETS_DIR/n8n_encryption_key.txt"
        chmod 600 "$SECRETS_DIR/n8n_encryption_key.txt"
        verbose_log "Generated n8n encryption key"
    fi
    
    # n8n JWT secret
    if [[ ! -f "$SECRETS_DIR/n8n_jwt_secret.txt" ]] || [[ "$regenerate" == "true" ]]; then
        generate_secure_key 64 > "$SECRETS_DIR/n8n_jwt_secret.txt"
        chmod 600 "$SECRETS_DIR/n8n_jwt_secret.txt"
        verbose_log "Generated n8n JWT secret"
    fi
    
    # Admin password
    if [[ ! -f "$SECRETS_DIR/admin_password.txt" ]] || [[ "$regenerate" == "true" ]]; then
        generate_secure_password 24 > "$SECRETS_DIR/admin_password.txt"
        chmod 600 "$SECRETS_DIR/admin_password.txt"
        verbose_log "Generated admin password"
    fi
    
    # API keys template
    if [[ ! -f "$SECRETS_DIR/api_keys.env" ]]; then
        cat > "$SECRETS_DIR/api_keys.env" << 'EOF'
# External API Keys (Optional)
# Add your API keys here

# OpenAI
OPENAI_API_KEY=

# Anthropic Claude
ANTHROPIC_API_KEY=

# Other services
DEEPSEEK_API_KEY=
GROQ_API_KEY=
MISTRAL_API_KEY=
EOF
        chmod 600 "$SECRETS_DIR/api_keys.env"
        verbose_log "Created API keys template"
    fi
    
    show_progress 3 3 "Validating secrets..."
    
    # Validate secrets
    local errors=0
    local required_files=(
        "postgres_password.txt"
        "n8n_encryption_key.txt"
        "n8n_jwt_secret.txt"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$SECRETS_DIR/$file" ]]; then
            error "Missing required secret: $file"
            ((errors++))
        elif [[ ! -s "$SECRETS_DIR/$file" ]]; then
            error "Secret file is empty: $file"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        success "Secrets setup completed"
        return $SUCCESS
    else
        error "Secrets validation failed with $errors errors"
        return $SETUP_FAILED
    fi
}

# =============================================================================
# CONFIG SETUP FUNCTIONS (from config-manager.sh)
# =============================================================================

# Setup config component
setup_config_component() {
    local environment
    environment=$(prompt_user "Environment (development/staging/production)" "development")
    
    show_progress 1 3 "Validating environment..."
    
    # Validate environment
    local valid_environments=("development" "staging" "production")
    local valid=false
    for env in "${valid_environments[@]}"; do
        if [[ "$environment" == "$env" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        error "Invalid environment: $environment"
        return $SETUP_FAILED
    fi
    
    show_progress 2 3 "Generating configuration files..."
    
    # Generate environment file
    local env_file="$PROJECT_ROOT/.env.${environment}"
    cat > "$env_file" << EOF
# Generated Environment Configuration
# Environment: $environment
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Global Configuration
ENVIRONMENT=$environment
AWS_REGION=us-east-1
STACK_NAME=GeuseMaker-$environment
PROJECT_NAME=GeuseMaker

# Infrastructure Configuration
VPC_CIDR=10.0.0.0/16
EFS_PERFORMANCE_MODE=generalPurpose

# Security Configuration
CONTAINER_SECURITY_ENABLED=false
NETWORK_SECURITY_STRICT=false

# Monitoring Configuration
MONITORING_ENABLED=true
LOG_LEVEL=debug

# Application placeholders
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET}
OPENAI_API_KEY=\${OPENAI_API_KEY}
EOF
    
    chmod 644 "$env_file"
    verbose_log "Generated environment file: $env_file"
    
    # Generate Docker Compose override
    local override_file="$PROJECT_ROOT/docker-compose.override.yml"
    cat > "$override_file" << EOF
# Generated Docker Compose Override
# Environment: $environment
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

version: '3.8'

services:
  postgres:
    environment:
      - POSTGRES_DB=\${POSTGRES_DB:-n8n}
      - POSTGRES_USER=\${POSTGRES_USER:-n8n}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}

  n8n:
    environment:
      - N8N_HOST=\${N8N_HOST:-0.0.0.0}
      - N8N_PORT=5678
      - WEBHOOK_URL=\${WEBHOOK_URL:-http://localhost:5678}
      - N8N_CORS_ENABLE=\${N8N_CORS_ENABLE:-true}
      - N8N_CORS_ALLOWED_ORIGINS=\${N8N_CORS_ALLOWED_ORIGINS:-*}

  ollama:
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=\${OLLAMA_ORIGINS:-http://localhost:*}

  qdrant:
    environment:
      - QDRANT__SERVICE__HTTP_PORT=6333
      - QDRANT__SERVICE__GRPC_PORT=6334
EOF
    
    chmod 644 "$override_file"
    verbose_log "Generated Docker Compose override: $override_file"
    
    show_progress 3 3 "Validating configuration..."
    
    # Basic validation
    if [[ -f "$env_file" ]] && [[ -f "$override_file" ]]; then
        success "Configuration setup completed"
        return $SUCCESS
    else
        error "Configuration file generation failed"
        return $SETUP_FAILED
    fi
}

# =============================================================================
# COMPREHENSIVE VALIDATION
# =============================================================================

# Validate all components
validate_all_components() {
    log "Running comprehensive validation..."
    
    local validation_errors=0
    
    # Docker validation
    if command -v docker >/dev/null 2>&1; then
        if validate_docker_installation; then
            success "✓ Docker validation passed"
        else
            error "✗ Docker validation failed"
            ((validation_errors++))
        fi
    else
        warning "⚠ Docker not installed"
    fi
    
    # Parameter Store validation
    if command -v aws >/dev/null 2>&1; then
        local aws_region="${AWS_REGION:-us-east-1}"
        if validate_parameter_store "$aws_region"; then
            success "✓ Parameter Store validation passed"
        else
            error "✗ Parameter Store validation failed"
            ((validation_errors++))
        fi
    else
        warning "⚠ AWS CLI not available"
    fi
    
    # Secrets validation
    if [[ -d "$SECRETS_DIR" ]]; then
        local required_secrets=(
            "postgres_password.txt"
            "n8n_encryption_key.txt"
            "n8n_jwt_secret.txt"
        )
        local missing=0
        for file in "${required_secrets[@]}"; do
            if [[ ! -f "$SECRETS_DIR/$file" ]] || [[ ! -s "$SECRETS_DIR/$file" ]]; then
                ((missing++))
            fi
        done
        if [[ $missing -eq 0 ]]; then
            success "✓ Secrets validation passed"
        else
            error "✗ Secrets validation failed ($missing files missing)"
            ((validation_errors++))
        fi
    else
        warning "⚠ Secrets directory not found"
    fi
    
    # Configuration validation
    local env_files=0
    for env in development staging production; do
        if [[ -f "$PROJECT_ROOT/.env.$env" ]]; then
            ((env_files++))
        fi
    done
    if [[ $env_files -gt 0 ]]; then
        success "✓ Configuration files found ($env_files environments)"
    else
        warning "⚠ No configuration files generated yet"
    fi
    
    # Summary
    echo
    if [[ $validation_errors -eq 0 ]]; then
        success "All validations passed!"
        return $SUCCESS
    else
        error "Validation failed with $validation_errors errors"
        return $VALIDATION_FAILED
    fi
}

# =============================================================================
# MAIN SETUP FUNCTIONS
# =============================================================================

# Setup specific component
setup_component() {
    local component="$1"
    
    case "$component" in
        "docker")
            setup_docker_component
            ;;
        "parameter-store")
            setup_parameter_store_component
            ;;
        "secrets")
            setup_secrets_component
            ;;
        "config")
            setup_config_component
            ;;
        "all")
            setup_all_components
            ;;
        *)
            error "Unknown component: $component"
            return $SETUP_FAILED
            ;;
    esac
}

# Setup all components
setup_all_components() {
    log "Setting up all components..."
    
    local total_steps=4
    local current_step=0
    local failed_components=()
    
    # Docker setup
    ((current_step++))
    show_progress $current_step $total_steps "Docker setup"
    if ! setup_docker_component; then
        failed_components+=("docker")
        warning "Docker setup failed, continuing..."
    fi
    
    # Parameter Store setup
    ((current_step++))
    show_progress $current_step $total_steps "Parameter Store setup"
    if ! setup_parameter_store_component; then
        failed_components+=("parameter-store")
        warning "Parameter Store setup failed, continuing..."
    fi
    
    # Secrets setup
    ((current_step++))
    show_progress $current_step $total_steps "Secrets setup"
    if ! setup_secrets_component; then
        failed_components+=("secrets")
        warning "Secrets setup failed, continuing..."
    fi
    
    # Config setup
    ((current_step++))
    show_progress $current_step $total_steps "Configuration setup"
    if ! setup_config_component; then
        failed_components+=("config")
        warning "Configuration setup failed, continuing..."
    fi
    
    # Summary
    echo
    if [[ ${#failed_components[@]} -eq 0 ]]; then
        success "All components setup completed successfully!"
        return $SUCCESS
    else
        error "Setup completed with failures in: ${failed_components[*]}"
        return $SETUP_FAILED
    fi
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
GeuseMaker Setup Suite

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --component COMPONENT    Setup specific component (docker|secrets|parameter-store|config|all)
    --interactive           Enable interactive mode with prompts
    --verbose              Enable verbose output
    --validate             Run validation only
    --help                 Show this help message

COMPONENTS:
    docker          Docker daemon configuration and setup
    parameter-store AWS Systems Manager Parameter Store setup
    secrets         Local secrets generation
    config          Configuration file generation
    all             Setup all components (default)

EXAMPLES:
    # Interactive setup of all components
    $0 --interactive

    # Setup only Docker with verbose output
    $0 --component docker --verbose

    # Validate existing setup
    $0 --validate

    # Non-interactive setup of Parameter Store
    $0 --component parameter-store

RETURN CODES:
    0 - Success
    1 - Setup failed
    2 - Validation failed

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --component)
                COMPONENT="$2"
                shift 2
                ;;
            --interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            --validate)
                VALIDATE_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit $SUCCESS
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit $SETUP_FAILED
                ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Set default component if not specified
    if [[ -z "$COMPONENT" ]] && [[ "$VALIDATE_ONLY" != "true" ]]; then
        COMPONENT="all"
    fi
    
    # Header
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                GeuseMaker Setup Suite"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        log "Running in interactive mode"
    fi
    
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log "Verbose mode enabled"
    fi
    
    # Run validation or setup
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        validate_all_components
    else
        setup_component "$COMPONENT"
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi