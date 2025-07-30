#!/usr/bin/env bash
# Test Docker configuration management

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-docker-config.sh" "core/variables" "core/logging"

log "Testing Docker configuration management..."

# Test configuration file exists
if [[ -f "$PROJECT_ROOT/config/docker-compose-template.yml" ]]; then
    success "✓ Docker compose template found"
else
    error "✗ Docker compose template missing"
    exit 1
fi

# Test environment configurations
for env in development staging production; do
    if [[ -f "$PROJECT_ROOT/config/environments/$env.yml" ]]; then
        success "✓ Environment config for $env found"
    else
        warn "⚠ Environment config for $env missing"
    fi
done

success "Docker configuration tests completed"