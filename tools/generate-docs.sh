#!/usr/bin/env bash
# Generate documentation

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "generate-docs.sh" "core/variables" "core/logging"

log "Generating project documentation..."

# Create docs directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/docs"

# Generate README if it doesn't exist
if [[ ! -f "$PROJECT_ROOT/README.md" ]]; then
    log "Creating README.md..."
    cat > "$PROJECT_ROOT/README.md" << 'EOF'
# AI Starter Kit

A comprehensive AWS deployment toolkit for AI applications.

## Quick Start

```bash
./deploy.sh
```

## Documentation

See the `docs/` directory for detailed documentation.
EOF
fi

success "Documentation generation complete"