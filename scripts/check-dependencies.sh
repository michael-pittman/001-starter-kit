#!/usr/bin/env bash
#
# Simple wrapper script for dependency checking
# Used by Makefile to check dependencies
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the deployment validation library
source "$PROJECT_ROOT/lib/deployment-validation.sh"

# Run dependency check
check_dependencies

# If successful, also run bash version check
if [[ $? -eq 0 ]]; then
    check_bash_version_enhanced
fi