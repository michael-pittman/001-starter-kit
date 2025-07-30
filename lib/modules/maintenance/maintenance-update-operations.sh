#!/bin/bash
#
# Maintenance Update Operations Module
# Contains all update operations extracted from maintenance scripts
#

# =============================================================================
# DOCKER UPDATE OPERATIONS
# =============================================================================

# Update Docker images
update_docker() {
    log_maintenance "INFO" "Updating Docker images..."
    increment_counter "processed"
    
    local compose_file="${MAINTENANCE_PROJECT_ROOT}/docker-compose.gpu-optimized.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_maintenance "ERROR" "Docker Compose file not found: $compose_file"
        increment_counter "failed"
        return 1
    fi
    
    # Detect Docker Compose command
    local docker_compose_cmd
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker_compose_cmd="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker_compose_cmd="docker-compose"
    else
        log_maintenance "ERROR" "Neither 'docker compose' nor 'docker-compose' command found"
        increment_counter "failed"
        return 1
    fi
    
    # Create backup
    if [[ "$MAINTENANCE_BACKUP" == true ]]; then
        local backup_path=$(create_timestamped_backup "$compose_file" "docker-compose")
        log_maintenance "INFO" "Created backup: $backup_path"
    fi
    
    # Show current versions
    show_docker_image_versions "before"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would update Docker images to latest versions"
        show_docker_update_preview
        return 0
    fi
    
    # Update images based on configuration
    if [[ -f "${MAINTENANCE_PROJECT_ROOT}/config/image-versions.yml" ]]; then
        # Use configured versions
        update_docker_with_config
    else
        # Update to latest
        update_docker_to_latest
    fi
    
    # Validate configuration
    if ! validate_docker_compose "$compose_file" "$docker_compose_cmd"; then
        log_maintenance "ERROR" "Docker Compose validation failed"
        
        # Rollback if enabled
        if [[ "$MAINTENANCE_ROLLBACK" == true ]] && [[ -n "$backup_path" ]]; then
            log_maintenance "WARNING" "Rolling back Docker Compose file..."
            rollback_from_backup "$backup_path" "$compose_file"
        fi
        
        increment_counter "failed"
        return 1
    fi
    
    # Show updated versions
    show_docker_image_versions "after"
    
    # Pull updated images if requested
    if confirm_operation "Pull updated Docker images?" "This will download all updated images"; then
        pull_docker_images "$compose_file" "$docker_compose_cmd"
    fi
    
    log_maintenance "SUCCESS" "Docker images updated"
    increment_counter "fixed"
    return 0
}

# Update Docker images to latest
update_docker_to_latest() {
    local compose_file="${MAINTENANCE_PROJECT_ROOT}/docker-compose.gpu-optimized.yml"
    
    log_maintenance "INFO" "Updating Docker images to latest versions..."
    
    # Update specific images to latest
    sed -i.tmp 's|image: postgres:.*|image: postgres:latest|g' "$compose_file"
    sed -i.tmp 's|image: n8nio/n8n:.*|image: n8nio/n8n:latest|g' "$compose_file"
    sed -i.tmp 's|image: qdrant/qdrant:.*|image: qdrant/qdrant:latest|g' "$compose_file"
    sed -i.tmp 's|image: ollama/ollama:.*|image: ollama/ollama:latest|g' "$compose_file"
    sed -i.tmp 's|image: curlimages/curl:.*|image: curlimages/curl:latest|g' "$compose_file"
    sed -i.tmp 's|image: unclecode/crawl4ai:.*|image: unclecode/crawl4ai:latest|g' "$compose_file"
    
    # Clean up temp files
    rm -f "${compose_file}.tmp"
}

# Update Docker with configuration
update_docker_with_config() {
    local compose_file="${MAINTENANCE_PROJECT_ROOT}/docker-compose.gpu-optimized.yml"
    local config_file="${MAINTENANCE_PROJECT_ROOT}/config/image-versions.yml"
    
    log_maintenance "INFO" "Updating Docker images based on configuration..."
    
    # Parse configuration and update each service
    local services=("postgres" "n8n" "qdrant" "ollama" "curl" "crawl4ai")
    
    for service in "${services[@]}"; do
        local version=$(get_configured_version "$service" "$config_file")
        if [[ -n "$version" ]]; then
            update_service_image "$service" "$version" "$compose_file"
        fi
    done
}

# Get configured version for service
get_configured_version() {
    local service="$1"
    local config_file="$2"
    local environment="${MAINTENANCE_ENVIRONMENT:-development}"
    
    # Simple YAML parsing
    local version=""
    
    # First check environment-specific version
    version=$(grep -A 10 "^environments:" "$config_file" 2>/dev/null | \
              grep -A 5 "^  $environment:" | \
              grep -A 3 "^    $service:" | \
              grep "^      image:" | \
              sed 's/.*image: *//' | \
              tr -d '"')
    
    # If not found, check default version
    if [[ -z "$version" ]]; then
        version=$(grep -A 10 "^services:" "$config_file" 2>/dev/null | \
                  grep -A 3 "^  $service:" | \
                  grep "^    default:" | \
                  sed 's/.*default: *//' | \
                  tr -d '"')
    fi
    
    echo "$version"
}

# Update individual service image
update_service_image() {
    local service="$1"
    local version="$2"
    local compose_file="$3"
    
    case "$service" in
        postgres)
            sed -i.tmp "s|image: postgres:.*|image: postgres:$version|g" "$compose_file"
            ;;
        n8n)
            sed -i.tmp "s|image: n8nio/n8n:.*|image: n8nio/n8n:$version|g" "$compose_file"
            ;;
        qdrant)
            sed -i.tmp "s|image: qdrant/qdrant:.*|image: qdrant/qdrant:$version|g" "$compose_file"
            ;;
        ollama)
            sed -i.tmp "s|image: ollama/ollama:.*|image: ollama/ollama:$version|g" "$compose_file"
            ;;
        curl)
            sed -i.tmp "s|image: curlimages/curl:.*|image: curlimages/curl:$version|g" "$compose_file"
            ;;
        crawl4ai)
            sed -i.tmp "s|image: unclecode/crawl4ai:.*|image: unclecode/crawl4ai:$version|g" "$compose_file"
            ;;
    esac
    
    rm -f "${compose_file}.tmp"
}

# Show Docker image versions
show_docker_image_versions() {
    local stage="$1"
    local compose_file="${MAINTENANCE_PROJECT_ROOT}/docker-compose.gpu-optimized.yml"
    
    log_maintenance "INFO" "Docker image versions ($stage update):"
    echo ""
    
    grep -n "image:" "$compose_file" | while IFS=: read -r line_num line_content; do
        local service=$(sed -n "$((line_num-1))p" "$compose_file" | grep -o '^  [a-zA-Z-]*' | sed 's/^  //' || echo "unknown")
        local image=$(echo "$line_content" | sed 's/.*image: *//')
        printf "  %-20s %s\n" "$service:" "$image"
    done
    echo ""
}

# Show Docker update preview
show_docker_update_preview() {
    echo "Docker images that would be updated:"
    echo "  - postgres -> postgres:latest"
    echo "  - n8n -> n8nio/n8n:latest"
    echo "  - qdrant -> qdrant/qdrant:latest"
    echo "  - ollama -> ollama/ollama:latest"
    echo "  - curl -> curlimages/curl:latest"
    echo "  - crawl4ai -> unclecode/crawl4ai:latest"
}

# Validate Docker Compose configuration
validate_docker_compose() {
    local compose_file="$1"
    local docker_compose_cmd="$2"
    
    log_maintenance "INFO" "Validating Docker Compose configuration..."
    
    # Create temporary environment file for validation
    local temp_env_file=$(mktemp)
    cat > "$temp_env_file" << 'EOF'
# Minimal environment for Docker Compose validation
EFS_DNS=placeholder.efs.region.amazonaws.com
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=placeholder
N8N_HOST=0.0.0.0
WEBHOOK_URL=http://localhost:5678
N8N_CORS_ALLOWED_ORIGINS=http://localhost:5678
OLLAMA_ORIGINS=http://localhost:*
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=i-placeholder
OPENAI_API_KEY=placeholder
ANTHROPIC_API_KEY=placeholder
DEEPSEEK_API_KEY=placeholder
GROQ_API_KEY=placeholder
TOGETHER_API_KEY=placeholder
MISTRAL_API_KEY=placeholder
GEMINI_API_TOKEN=placeholder
EOF
    
    # Attempt validation
    if $docker_compose_cmd -f "$compose_file" --env-file "$temp_env_file" config >/dev/null 2>&1; then
        log_maintenance "SUCCESS" "Docker Compose configuration is valid"
        rm -f "$temp_env_file"
        return 0
    else
        log_maintenance "ERROR" "Docker Compose configuration validation failed"
        if [[ "$MAINTENANCE_VERBOSE" == true ]]; then
            log_maintenance "DEBUG" "Validation errors:"
            $docker_compose_cmd -f "$compose_file" --env-file "$temp_env_file" config 2>&1 | head -20
        fi
        rm -f "$temp_env_file"
        return 1
    fi
}

# Pull Docker images
pull_docker_images() {
    local compose_file="$1"
    local docker_compose_cmd="$2"
    
    log_maintenance "INFO" "Pulling Docker images..."
    
    cd "$(dirname "$compose_file")"
    
    if $docker_compose_cmd -f "$compose_file" pull; then
        log_maintenance "SUCCESS" "Docker images pulled successfully"
    else
        log_maintenance "WARNING" "Some images failed to pull"
    fi
}

# =============================================================================
# DEPENDENCIES UPDATE OPERATIONS
# =============================================================================

# Update system dependencies
update_dependencies() {
    log_maintenance "INFO" "Updating system dependencies..."
    increment_counter "processed"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would update system dependencies"
        show_dependencies_update_preview
        return 0
    fi
    
    # Update package lists
    log_maintenance "INFO" "Updating package lists..."
    sudo apt-get update -qq || {
        log_maintenance "ERROR" "Failed to update package lists"
        increment_counter "failed"
        return 1
    }
    
    # Update critical packages
    local critical_packages=(
        "docker-ce"
        "docker-compose"
        "aws-cli"
        "amazon-efs-utils"
        "nfs-common"
        "jq"
        "curl"
        "git"
        "python3"
        "python3-pip"
    )
    
    local updated_count=0
    for package in "${critical_packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package"; then
            log_maintenance "INFO" "Checking updates for $package..."
            
            if apt-get -s upgrade "$package" 2>/dev/null | grep -q "^Inst $package"; then
                if sudo apt-get install -y --only-upgrade "$package"; then
                    log_maintenance "SUCCESS" "Updated $package"
                    ((updated_count++))
                else
                    log_maintenance "WARNING" "Failed to update $package"
                fi
            fi
        fi
    done
    
    # Update Python packages
    if command -v pip3 >/dev/null 2>&1; then
        log_maintenance "INFO" "Updating Python packages..."
        
        # Update critical Python packages
        local python_packages=(
            "awscli"
            "docker-compose"
            "pyyaml"
            "requests"
        )
        
        for package in "${python_packages[@]}"; do
            if pip3 show "$package" >/dev/null 2>&1; then
                if pip3 install --upgrade "$package" >/dev/null 2>&1; then
                    log_maintenance "SUCCESS" "Updated Python package: $package"
                    ((updated_count++))
                fi
            fi
        done
    fi
    
    if [[ $updated_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Updated $updated_count dependencies"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "All dependencies are up to date"
        increment_counter "skipped"
    fi
    
    return 0
}

# Show dependencies update preview
show_dependencies_update_preview() {
    echo "Dependencies that would be updated:"
    echo "  System packages:"
    echo "    - docker-ce"
    echo "    - docker-compose"
    echo "    - aws-cli"
    echo "    - amazon-efs-utils"
    echo "    - jq, curl, git"
    echo "  Python packages:"
    echo "    - awscli"
    echo "    - docker-compose"
    echo "    - pyyaml"
    echo "    - requests"
}

# =============================================================================
# SCRIPTS UPDATE OPERATIONS
# =============================================================================

# Update deployment scripts
update_scripts() {
    log_maintenance "INFO" "Updating deployment scripts..."
    increment_counter "processed"
    
    local scripts_dir="${MAINTENANCE_PROJECT_ROOT}/scripts"
    local updated_count=0
    
    if [[ ! -d "$scripts_dir" ]]; then
        log_maintenance "ERROR" "Scripts directory not found: $scripts_dir"
        increment_counter "failed"
        return 1
    fi
    
    # Update script permissions
    log_maintenance "INFO" "Updating script permissions..."
    find "$scripts_dir" -name "*.sh" -type f | while read -r script; do
        if [[ ! -x "$script" ]]; then
            if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
                log_maintenance "INFO" "[DRY RUN] Would make executable: $script"
            else
                chmod +x "$script"
                log_maintenance "SUCCESS" "Made executable: $script"
                ((updated_count++))
            fi
        fi
    done
    
    # Update shebang lines
    log_maintenance "INFO" "Checking shebang lines..."
    find "$scripts_dir" -name "*.sh" -type f | while read -r script; do
        local first_line=$(head -n1 "$script")
        
        if [[ ! "$first_line" =~ ^#!/ ]]; then
            log_maintenance "WARNING" "Missing shebang in: $script"
            
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                # Add shebang
                local temp_file=$(mktemp)
                echo "#!/usr/bin/env bash" > "$temp_file"
                cat "$script" >> "$temp_file"
                mv "$temp_file" "$script"
                log_maintenance "SUCCESS" "Added shebang to: $script"
                ((updated_count++))
            fi
        elif [[ "$first_line" == "#!/bin/sh" ]]; then
            # Update to bash for consistency
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                sed -i '1s|#!/bin/sh|#!/usr/bin/env bash|' "$script"
                log_maintenance "SUCCESS" "Updated shebang in: $script"
                ((updated_count++))
            fi
        fi
    done
    
    # Validate scripts
    log_maintenance "INFO" "Validating scripts..."
    local validation_failed=false
    
    find "$scripts_dir" -name "*.sh" -type f | while read -r script; do
        if ! validate_shell_script "$script"; then
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == true ]]; then
        log_maintenance "WARNING" "Some scripts have validation issues"
    fi
    
    if [[ $updated_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Updated $updated_count scripts"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "All scripts are up to date"
        increment_counter "skipped"
    fi
    
    return 0
}

# =============================================================================
# CONFIGURATION UPDATE OPERATIONS
# =============================================================================

# Update configurations
update_configurations() {
    log_maintenance "INFO" "Updating configurations..."
    increment_counter "processed"
    
    local config_dir="${MAINTENANCE_PROJECT_ROOT}/config"
    local configs_updated=0
    
    # Create config directory if missing
    if [[ ! -d "$config_dir" ]]; then
        if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            mkdir -p "$config_dir"
            log_maintenance "INFO" "Created config directory"
        fi
    fi
    
    # Update image versions configuration
    if update_image_versions_config; then
        ((configs_updated++))
    fi
    
    # Update environment configuration
    if update_environment_config; then
        ((configs_updated++))
    fi
    
    # Update AWS configuration
    if update_aws_config; then
        ((configs_updated++))
    fi
    
    if [[ $configs_updated -gt 0 ]]; then
        log_maintenance "SUCCESS" "Updated $configs_updated configurations"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "All configurations are up to date"
        increment_counter "skipped"
    fi
    
    return 0
}

# Update image versions configuration
update_image_versions_config() {
    local config_file="${MAINTENANCE_PROJECT_ROOT}/config/image-versions.yml"
    
    if [[ -f "$config_file" ]]; then
        # Validate existing configuration
        if validate_yaml "$config_file"; then
            log_maintenance "INFO" "Image versions configuration is valid"
            return 1
        fi
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create/update image versions configuration"
        return 0
    fi
    
    # Create default configuration
    cat > "$config_file" << 'EOF'
# Docker Image Versions Configuration
# Used by update-image-versions.sh

services:
  postgres:
    image: postgres
    default: latest
    fallback: "15"
    
  n8n:
    image: n8nio/n8n
    default: latest
    fallback: "1.0.0"
    
  qdrant:
    image: qdrant/qdrant
    default: latest
    fallback: "v1.7.0"
    
  ollama:
    image: ollama/ollama
    default: latest
    fallback: "0.1.0"
    
  curl:
    image: curlimages/curl
    default: latest
    fallback: "8.5.0"
    
  crawl4ai:
    image: unclecode/crawl4ai
    default: latest
    fallback: "0.2.0"
    
  cuda:
    image: nvidia/cuda
    default: "12.2.0-base-ubuntu22.04"
    fallback: "11.8.0-base-ubuntu22.04"

environments:
  development:
    # Use latest versions in development
    
  production:
    # Pin specific versions for production
    postgres:
      image: postgres:15
    n8n:
      image: n8nio/n8n:1.0.0
    qdrant:
      image: qdrant/qdrant:v1.7.0
    
  testing:
    # Use known-good versions for testing
    postgres:
      image: postgres:15
    n8n:
      image: n8nio/n8n:0.236.0
EOF
    
    log_maintenance "SUCCESS" "Created image versions configuration"
    return 0
}

# Update environment configuration
update_environment_config() {
    local env_template="${MAINTENANCE_PROJECT_ROOT}/.env.template"
    
    if [[ -f "$env_template" ]]; then
        # Check if template is up to date
        if grep -q "EFS_DNS" "$env_template"; then
            return 1
        fi
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would create/update environment template"
        return 0
    fi
    
    # Create environment template
    cat > "$env_template" << 'EOF'
# GeuseMaker Environment Configuration Template
# Copy this file to .env and update with your values

# PostgreSQL Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=your_secure_password_here

# n8n Configuration
N8N_ENCRYPTION_KEY=your_encryption_key_here
N8N_USER_MANAGEMENT_JWT_SECRET=your_jwt_secret_here
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http

# API Keys (Optional)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=

# n8n Security Settings
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=*
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# AWS Configuration
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=
INSTANCE_TYPE=

# EFS Configuration
EFS_DNS=

# Webhook Configuration
WEBHOOK_URL=

# Monitoring
ENABLE_MONITORING=true
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
EOF
    
    log_maintenance "SUCCESS" "Created environment template"
    return 0
}

# Update AWS configuration
update_aws_config() {
    local aws_config="${HOME}/.aws/config"
    
    if [[ ! -f "$aws_config" ]]; then
        return 1
    fi
    
    # Check if default region is set
    if grep -q "region = ${MAINTENANCE_AWS_REGION}" "$aws_config"; then
        return 1
    fi
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_maintenance "INFO" "[DRY RUN] Would update AWS default region to $MAINTENANCE_AWS_REGION"
        return 0
    fi
    
    # Update default region
    if grep -q "\[default\]" "$aws_config"; then
        # Update existing default section
        sed -i "/\[default\]/,/\[/{s/region = .*/region = $MAINTENANCE_AWS_REGION/}" "$aws_config"
    else
        # Add default section
        echo -e "\n[default]\nregion = $MAINTENANCE_AWS_REGION" >> "$aws_config"
    fi
    
    log_maintenance "SUCCESS" "Updated AWS default region to $MAINTENANCE_AWS_REGION"
    return 0
}

# =============================================================================
# PARAMETER STORE UPDATE OPERATIONS
# =============================================================================

# Update AWS Parameter Store values
update_parameters() {
    log_maintenance "INFO" "Updating AWS Parameter Store values..."
    increment_counter "processed"
    
    if ! command -v aws >/dev/null 2>&1; then
        log_maintenance "ERROR" "AWS CLI not installed"
        increment_counter "failed"
        return 1
    fi
    
    # Parameters to check and update
    local parameters=(
        "/aibuildkit/POSTGRES_PASSWORD"
        "/aibuildkit/n8n/ENCRYPTION_KEY"
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET"
        "/aibuildkit/WEBHOOK_URL"
    )
    
    local updated_count=0
    
    for param in "${parameters[@]}"; do
        # Check if parameter exists
        if safe_aws_command \
            "aws ssm get-parameter --name $param --region $MAINTENANCE_AWS_REGION" \
            "Check parameter $param" >/dev/null; then
            
            log_maintenance "INFO" "Parameter exists: $param"
        else
            log_maintenance "WARNING" "Parameter missing: $param"
            
            if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                # Create parameter with default value
                local default_value=""
                
                case "$param" in
                    *PASSWORD*|*KEY*|*SECRET*)
                        default_value=$(openssl rand -hex 32)
                        ;;
                    *WEBHOOK_URL*)
                        default_value="http://localhost:5678"
                        ;;
                esac
                
                if safe_aws_command \
                    "aws ssm put-parameter --name $param --value '$default_value' --type SecureString --region $MAINTENANCE_AWS_REGION" \
                    "Create parameter $param"; then
                    
                    log_maintenance "SUCCESS" "Created parameter: $param"
                    ((updated_count++))
                fi
            fi
        fi
    done
    
    if [[ $updated_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Updated $updated_count parameters"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "All parameters exist"
        increment_counter "skipped"
    fi
    
    return 0
}

# =============================================================================
# CERTIFICATE UPDATE OPERATIONS
# =============================================================================

# Update SSL certificates
update_certificates() {
    log_maintenance "INFO" "Checking SSL certificates..."
    increment_counter "processed"
    
    local certs_dir="${MAINTENANCE_PROJECT_ROOT}/certs"
    local updated_count=0
    
    if [[ ! -d "$certs_dir" ]]; then
        log_maintenance "INFO" "No certificates directory found"
        increment_counter "skipped"
        return 0
    fi
    
    # Check certificate expiration
    find "$certs_dir" -name "*.crt" -o -name "*.pem" | while read -r cert; do
        if [[ -f "$cert" ]]; then
            local expiry_date=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
            
            if [[ -n "$expiry_date" ]]; then
                local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
                local current_epoch=$(date +%s)
                local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
                
                if [[ $days_until_expiry -lt 30 ]]; then
                    log_maintenance "WARNING" "Certificate expiring in $days_until_expiry days: $cert"
                    
                    if [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
                        # TODO: Implement certificate renewal logic
                        log_maintenance "INFO" "Certificate renewal not yet implemented"
                    fi
                else
                    log_maintenance "INFO" "Certificate valid for $days_until_expiry days: $cert"
                fi
            fi
        fi
    done
    
    if [[ $updated_count -gt 0 ]]; then
        log_maintenance "SUCCESS" "Updated $updated_count certificates"
        increment_counter "fixed"
    else
        log_maintenance "INFO" "All certificates are valid"
        increment_counter "skipped"
    fi
    
    return 0
}

# Export all update functions
export -f update_docker
export -f update_docker_to_latest
export -f update_docker_with_config
export -f get_configured_version
export -f update_service_image
export -f show_docker_image_versions
export -f show_docker_update_preview
export -f validate_docker_compose
export -f pull_docker_images
export -f update_dependencies
export -f show_dependencies_update_preview
export -f update_scripts
export -f update_configurations
export -f update_image_versions_config
export -f update_environment_config
export -f update_aws_config
export -f update_parameters
export -f update_certificates