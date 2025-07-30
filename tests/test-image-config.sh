#!/usr/bin/env bash
# Test image configuration management

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "test-image-config.sh" "core/variables" "core/logging"

log "Testing image configuration management..."

# Test image versions configuration
if [[ -f "$PROJECT_ROOT/config/image-versions.yml" ]]; then
    success "✓ Image versions configuration found"
else
    error "✗ Image versions configuration missing"
    exit 1
fi

# Test that the update script works
if [[ -f "$PROJECT_ROOT/scripts/update-image-versions.sh" ]]; then
    success "✓ Image update script found"
    
    # Test script syntax
    if bash -n "$PROJECT_ROOT/scripts/update-image-versions.sh"; then
        success "✓ Image update script syntax is valid"
    else
        error "✗ Image update script has syntax errors"
        exit 1
    fi
else
    error "✗ Image update script missing"
    exit 1
fi

success "Image configuration tests completed"