#!/usr/bin/env bash
# =============================================================================
# Parameter Store Setup Compatibility Wrapper
# Redirects to setup-suite.sh for parameter store setup functionality
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

echo "INFO: Redirecting to setup suite for parameter store setup..." >&2
"$SETUP_SUITE" --component parameter-store "$@" 