#!/usr/bin/env bash
#
# Compatibility wrapper for error_types.sh
# This file is DEPRECATED and will be removed in a future version.
# Please use lib/modules/core/errors.sh instead.
#

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Show deprecation warning
echo "WARNING: lib/modules/errors/error_types.sh is deprecated." >&2
echo "         Please update your scripts to use lib/modules/core/errors.sh instead." >&2
echo "         Called from: ${BASH_SOURCE[1]:-unknown}" >&2

# Source the new module
source "${MODULE_ROOT}/core/errors.sh"