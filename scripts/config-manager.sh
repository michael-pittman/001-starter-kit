#!/usr/bin/env bash
# =============================================================================
# Config Manager Compatibility Wrapper
# Redirects to setup-suite.sh for config management functionality
# This script is maintained for backward compatibility
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the setup suite
SETUP_SUITE="$PROJECT_ROOT/lib/modules/config/setup-suite.sh"

if [[ ! -f "$SETUP_SUITE" ]]; then
    echo "ERROR: Setup suite not found at $SETUP_SUITE" >&2
    echo "Please ensure the setup suite is properly installed" >&2
    exit 1
fi

# Parse command line arguments
COMMAND="${1:-}"
ENVIRONMENT="${2:-}"

case "$COMMAND" in
    "generate")
        if [[ -z "$ENVIRONMENT" ]]; then
            echo "ERROR: Environment required for generate command" >&2
            echo "Usage: $0 generate <environment>" >&2
            exit 1
        fi
        echo "INFO: Redirecting to setup suite for config generation..." >&2
        "$SETUP_SUITE" --component config --environment "$ENVIRONMENT"
        ;;
    "env")
        if [[ -z "$ENVIRONMENT" ]]; then
            echo "ERROR: Environment required for env command" >&2
            echo "Usage: $0 env <environment>" >&2
            exit 1
        fi
        echo "INFO: Redirecting to setup suite for environment setup..." >&2
        "$SETUP_SUITE" --component config --environment "$ENVIRONMENT"
        ;;
    "validate")
        echo "INFO: Redirecting to setup suite for validation..." >&2
        "$SETUP_SUITE" --component config --validate-only
        ;;
    "help"|"--help"|"-h")
        echo "Config Manager Compatibility Wrapper" >&2
        echo "" >&2
        echo "This script redirects to the setup suite for config management." >&2
        echo "" >&2
        echo "Usage:" >&2
        echo "  $0 generate <environment>  - Generate configuration for environment" >&2
        echo "  $0 env <environment>       - Setup environment configuration" >&2
        echo "  $0 validate               - Validate configuration" >&2
        echo "  $0 help                   - Show this help" >&2
        echo "" >&2
        echo "Note: This is a compatibility wrapper. Consider using setup-suite.sh directly." >&2
        ;;
    *)
        echo "ERROR: Unknown command: $COMMAND" >&2
        echo "Usage: $0 {generate|env|validate|help} [environment]" >&2
        exit 1
        ;;
esac 